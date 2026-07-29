# R2 — The single-threaded WebAssembly performance envelope

**Date:** 2026-07-27 · **Target:** Godot 4.7, Web export, `thread_support=false`, WebGL2 / `gl_compatibility`, GitHub Pages
**Scope:** audio voice budget, physics cost of mutual `CharacterBody3D` collision, ragdoll, download payload.

Evidence tiers used throughout: **T1** official docs / engine source · **T2** maintainer statements or confirmed issues · **T3** reputable secondary or well-maintained reference implementation · **T4** community anecdote.
"Corrob." = number of *independent* sources supporting the claim.

---

## Bottom line

1. **The audio brief is asking the wrong question.** On web, Godot does not mix `AudioStreamPlayer3D` voices at all — the platform default is `Playback Type: Sample`, which hands each voice to the browser's Web Audio graph. There is no software mixer to overflow, so "how many voices before dropout" is not the ceiling. The ceiling is Web Audio node count and, specifically, **one `AudioWorkletNode` per live voice that `postMessage`s the main thread every 128-sample render quantum (~344 msg/s/voice at 44.1 kHz)**. 24 groaning zombies = ~8,300 cross-thread messages per second landing on the same single thread that runs your game and renderer. That, not mixing, is what will cost you.

2. **`AudioEffectReverb`, Doppler, `Area3D` reverb-bus override, and the distance low-pass filter do not work on the shipping build — at all.** Not "slow": absent. Official 4.7 docs state it for reverb and Doppler; the engine's own `library_godot_audio.js` contains zero `ConvolverNode`, `BiquadFilterNode`, `PannerNode` or `DelayNode` — only gains and channel splitters. Budgeting 2–3 reverb buses is budgeting for something that will silently no-op. Switching to `Stream` playback to get them back reintroduces the frame-rate-coupled audio garbling that Sample mode was created to fix.

3. **The project is almost certainly running GodotPhysics3D, not Jolt — and nobody chose that.** `project.godot` has no `physics/3d/physics_engine` key; in the 4.7 source only `godot_physics_3d` calls `set_default_server`, Jolt never does. Jolt *is* compiled into the web template (its `config.py` allows every platform). This is a one-line project setting, and it is the single highest-leverage change before adding 24 mutually-colliding capsules — the headline evidence is ~10–40 vs ~800 `CharacterBody3D` instances. But there is real counter-evidence that per-call `move_and_slide` can be *slower* under Jolt, so **measure both, do not assume.**

4. **The payload is already over budget and content is not the reason.** Measured live against `https://fahim-mygithub.github.io/kriegsnacht/`: GitHub Pages serves `index.wasm` gzipped at **10,246,865 bytes**, total first load **≈10.58 MB**. Brotli (which would give 6.90 MB) is **not** served by GitHub Pages even when requested. Meanwhile the `.pck` is 261 KB gzipped and *all audio is synthesised at runtime, costing zero bytes*. The engine binary is 97.5% of the download. Adding content is nearly free; shrinking the engine is the only lever that matters.

5. **`PhysicalBone3D` ragdolls are not a real option here** and the trade is already decided by the art pipeline: there are no rigged meshes in the project. An animated death sprite clip is the correct call; a single-capsule "fake ragdoll" is the correct *upgrade* if one is wanted later.

6. **Set `max_distance` on every `AudioStreamPlayer3D` you add.** It defaults to `0.0` = never culled, and the class docs say explicitly it "can be used to prevent the `AudioStreamPlayer3D` from requiring audio mixing when the listener is far away, which saves CPU resources." This is free and the gap analysis's VS-2 plan (distance-cull at 20 m) should be implemented through this property rather than in GDScript.

---

## Findings

### A. Audio

#### A1 — Web export defaults to `Sample` playback; effects, reverb, Doppler and procedural generation are unsupported under it
**Tier 1 · Corrob. 4 (official docs ×2, official engine blog, engine source)**

- `https://docs.godotengine.org/en/latest/tutorials/export/exporting_for_web.html` (4.7 docs) — Audio playback section: *"AudioEffects are not supported. Reverberation and doppler effects are not supported. Procedural audio generation is not supported."*
- `https://docs.godotengine.org/en/latest/tutorials/audio/audio_streams.html` (4.7 docs) — on reverb buses and on the Doppler effect, each: *"This feature is not supported on the web platform if the AudioStreamPlayer's playback mode is set to **Sample**, which is the default."* Both *"will only work if the playback mode is set to **Stream**, at the cost of increased latency if threads are not enabled."*
- `https://godotengine.org/article/progress-report-web-export-in-4-3/` — origin and rationale; feature marked experimental in 4.3.
- Corroborating bug reports: `https://github.com/godotengine/godot/issues/95991` and `https://github.com/godotengine/godot/issues/100102` (both closed/archived as known-behaviour, 4.3-stable and 4.4.dev6).

**Direct answers to the brief:**
- *"What do 2–3 concurrent `AudioEffectReverb` buses cost?"* → Nothing, because they do not run. On desktop/editor they will, so the shipped build and your dev build will sound different.
- *"Is `Area3D` bus override honoured under that driver?"* → **No.** `AudioStreamPlayer3D.area_mask` is documented (T1, `doc/classes/AudioStreamPlayer3D.xml`) as *"Determines which Area3D layers affect the sound for reverb and audio bus effects"* — precisely the reverb-bus feature the web docs exclude.

#### A2 — Per-voice cost under Sample: ~10 Web Audio nodes plus one AudioWorklet posting ~344 messages/second to the main thread
**Tier 1 · Corrob. 1 (engine source, read directly) — the most important finding in this document**

Source: `platform/web/js/libs/library_godot_audio.js` and `platform/web/js/libs/audio.position.worklet.js` at `godotengine/godot@master`. (Confirmed to match this project's shipped build: local `docs/index.audio.position.worklet.js` is 2,973 bytes, byte-identical in size to master's `audio.position.worklet.js`.)

Every `SampleNode` (= one playing voice) constructs:

| Node | Count | Purpose |
|---|---|---|
| `AudioBufferSourceNode` | 1 | the sample |
| `AudioWorkletNode` (`godot-position-reporting-processor`) | 1 | playback position reporting |
| `ChannelSplitterNode(6)` | 1 (per bus routed to) | `SampleNodeBus` |
| `GainNode` | 6 (per bus) | the 6-channel volume matrix |
| `ChannelMergerNode(6)` | 1 (per bus) | `SampleNodeBus` |

The position worklet's `process()` runs unconditionally every render quantum and posts on every call:

```js
this.position += input[0].length;
this.port.postMessage({ type: 'position', data: this.position });
```

A render quantum is 128 frames (T1, W3C Web Audio API 1.1 / `https://www.w3.org/TR/webaudio-1.1/`). At 44.1 kHz that is **344.5 messages per second per live voice**; at 48 kHz, **375**. These land on the main thread — the same thread running your `_process`, `_physics_process` and the WebGL2 renderer, with no other thread to absorb them.

Mitigating detail (also T1 source): the worklet nodes are **pooled** (`GodotAudio.audioPositionWorkletNodes.pop()`), so repeated gunshots do not thrash allocation. The message rate, however, scales with *concurrent live* voices, not with allocations.

**This is the number to design against.** A 12-voice cap costs ~4,100 msg/s. A 24-voice cap costs ~8,300 msg/s. The gap analysis's VS-2 plan ("voice-capped at ~10") is, by luck, in the right neighbourhood.

#### A3 — The per-voice attenuation cost in wasm is near-zero, but the attenuation low-pass filter silently does not exist on web
**Tier 1 for the mechanism · Tier 1-by-absence for the filter · Corrob. 1**

Under Sample, Godot computes a `MAX_VOLUME_CHANNELS: 8` volume array in wasm on the idle/physics frame and pushes it to the 6 `GainNode`s via `SampleNodeBus.setVolume()`. There is no per-audio-frame DSP in WebAssembly. So distance attenuation and panning cost roughly a `Vector3` distance and a small matrix per voice per *game* frame — negligible.

However: `AudioStreamPlayer3D.attenuation_filter_cutoff_hz` (default `5000.0`) and `attenuation_filter_db` (default `-24.0`) describe a low-pass filter applied to distant sounds. `library_godot_audio.js` contains **no** `BiquadFilterNode` and no filter of any kind (grep for `biquad|lowpass|filter` returns only `Array.prototype.filter` calls). The complete set of Web Audio constructors used is: `createGain` ×9, `createScriptProcessor` ×2 (legacy Stream fallback), `createBufferSource` ×2, `createBuffer` ×2, `createMediaStreamSource`, `createChannelSplitter`, `createChannelMerger`.

**Inference, flagged as such:** the "distant sounds get muffled" cue is absent on the shipping build. This is not stated in the docs and I found no issue tracking it. It follows directly from the source but has not been confirmed by a maintainer, and it should be verified by ear before being treated as fact.

#### A4 — `Stream` playback is the only route to effects, and it is the bug Sample mode was created to fix
**Tier 2 · Corrob. 3**

`https://github.com/godotengine/godot/issues/87329` — "Cracking audio with Godot 4 no-threads Web builds", confirmed, assigned to adamscott, fixed for 4.3 via PR #91382. Root cause per the 4.3 engine blog: *"Audio rendering is tied with the frame rate. And if it drops, there's not enough audio frames to fill out the buffer, hence the glitches."* Under `thread_support=false`, opting back into `Stream` globally reinstates exactly this coupling. The 4.7 docs' own guidance: *"Changing this setting is not recommended, unless you have an explicit reason to."*

A per-node escape hatch exists (`AudioStreamPlayer3D.playback_type`, marked **experimental** in 4.7) — a single music/ambience `Stream` player is defensible; 24 zombie voices are not.

#### A5 — Two different, inconsistent overflow behaviours
**Tier 1 · Corrob. 2 (both from `doc/classes/*.xml` at master)**

- `AudioStreamPlaybackPolyphonic.play_stream()` → *"This function returns `INVALID_ID` if the amount of streams currently playing equals `AudioStreamPolyphonic.polyphony`."* `INVALID_ID = -1`. **Silent drop, no error, no warning.** If you do not check the return value you will never learn a sound was skipped.
- `AudioStreamPlayer3D.max_polyphony` (**default `1`**) → *"Playing additional sounds after this value is reached will cut off the oldest sounds."* **Voice stealing, not dropping.**

So "how does polyphonic behave on overflow" has different answers depending on which API you reach for. For a zombie horde, oldest-wins stealing is the behaviour you want; silent-drop is the behaviour you get from `AudioStreamPolyphonic`.

#### A6 — `max_distance` defaults to no culling, and is the documented CPU lever
**Tier 1 · Corrob. 2**

`doc/classes/AudioStreamPlayer3D.xml`: `max_distance` default `0.0`, *"Only has an effect if set to a value greater than `0.0` … This can be used to prevent the AudioStreamPlayer3D from requiring audio mixing when the listener is far away, which saves CPU resources."* Corroborated by the open behaviour report `https://github.com/godotengine/godot/issues/96670` ("AudioStreamPlayer3D doesn't stop processing when out of range").

Also T1: *"Hiding an AudioStreamPlayer3D node does not disable its audio output."* Do not rely on `visible = false` for culling.

#### A7 — Web-Sample-specific bugs to be aware of
**Tier 2 · Corrob. 3**

| Issue | Status | Relevance |
|---|---|---|
| `https://github.com/godotengine/godot/issues/93904` — `finished()` never emits under single-threaded web Sample playback | **Closed**, fixed by PR #94044, shipped 4.3 | Was a player-pool killer. Confirm it stays fixed; a pool that recycles on `finished` is the standard pattern. |
| `https://github.com/godotengine/godot/issues/94724` — `AudioStreamPlaybackPolyphonic.stop_stream()` does not stop audio in HTML export (Sample) | Reported against 4.3 beta3, Chrome/Edge/Android | **Unverified for 4.7.** If you build a polyphonic-based voice manager, test `stop_stream` on the web build specifically. |
| Sample-mode looping misbehaviour (multiple itch.io devlog reports) | T4 | Ambient/music loops may need `Stream` mode. |

#### A8 — This project's audio costs zero download bytes and is Sample-compatible
**Tier 1 · Corrob. 2 (engine source + local code)**

`scripts/autoload/sfx.gd` synthesises every sound at startup into `AudioStreamWAV` (16-bit, 22,050 Hz, mono) via GDScript per-sample loops. `AudioStreamWAV::can_be_sampled()` returns `true` (T1, `scene/resources/audio/audio_stream_wav.h`), so these work under Sample playback with no change.

Correcting a common misreading of the 4.3 blog's "static audio only": **`AudioStreamOggVorbis` and `AudioStreamMP3` also return `can_be_sampled() == true`** (T1, `modules/vorbis/audio_stream_ogg_vorbis.h`, `modules/mp3/audio_stream_mp3.h`). Ogg files are usable as samples. The restriction is *static vs. streaming/procedural*, not *WAV vs. compressed*.

The cost that *does* exist is boot time: each `_bake()` runs a GDScript loop at `dur × 22050` iterations. This is measurable, currently small, and grows linearly with the sound count.

---

### B. Physics

#### B1 — Jolt is compiled into the web export template
**Tier 1 · Corrob. 1 (engine source), 2 with the 4.4 merge announcement**

`modules/jolt_physics/config.py` at master, in full:

```python
def can_build(env, platform):
    return not env["disable_physics_3d"]

def configure(env):
    pass
```

No platform exclusion. Jolt has been an in-tree **engine module** (not a GDExtension) since 4.4, so it is in the stock web template. This resolves the confusion in older material: the *godot-jolt GDExtension* never shipped a web binary (`https://github.com/godot-jolt/godot-jolt/issues/477`), which is irrelevant now — and would be doubly irrelevant here, since this export has `variant/extensions_support=false`.

#### B2 — This project is running GodotPhysics3D by default, unintentionally
**Tier 1 · Corrob. 2 (engine source + local `project.godot`) — highest-value actionable finding in the physics section**

- `project.godot` contains **no** `[physics]` section and no `physics/3d/physics_engine` key.
- `servers/physics_3d/physics_server_3d_manager.cpp` (T1): `initialize_server()` calls `new_server(GLOBAL_GET("physics/3d/physics_engine"))`; when that fails it falls back to `new_default_server()`, i.e. whichever module registered itself with the highest priority.
- `modules/godot_physics_3d/register_types.cpp` (T1) calls `set_default_server("GodotPhysics3D")` **unconditionally**.
- `modules/jolt_physics/register_types.cpp` (T1) calls `register_server("Jolt Physics", …)` and **never** calls `set_default_server`.

Therefore the runtime fallback in 4.7 is GodotPhysics3D. The 4.6 release note (`https://godotengine.org/releases/4.6/`) — *"make Jolt the default physics engine for all new 3D projects … Existing projects aren't affected"* — is implemented somewhere in the project-creation path, not in the runtime default, and this project's `project.godot` predates or bypasses it.

**Verification is one line** (see §Measurement M0). Do not act on this without running it.

#### B3 — Mutually-colliding `CharacterBody3D` is GodotPhysics3D's documented weak spot
**Tier 2 · Corrob. 2**

`https://github.com/godotengine/godot/issues/78761` (closed/archived) reports instance counts before noticeable degradation:

| Configuration | Instances |
|---|---|
| Godot 4.0.3 / 4.1, GodotPhysics3D | **10–40** |
| Godot 3.5.2, Bullet | 250–300 |
| Godot 4.0.3 + Godot Jolt | **~800** |

The reporter isolated the cause: *"disabling collision mask bits eliminated the performance problem"* — i.e. it is the mutual-collision case specifically, which is exactly what the plan introduces. Corroborated by `https://github.com/godotengine/godot/issues/93184` (performance tanks past ~50 characters, most of the cost in `move_and_slide`/`move_and_collide`).

**Caveats, stated plainly:** no frame times, no hardware, no viewport size, and this is 4.0/4.1-era GodotPhysics3D — three minor releases before 4.7. Treat "10–40" as an order of magnitude, not a number. Note that 24 zombies sits uncomfortably inside that band.

#### B4 — Counter-evidence: Jolt's `move_and_slide` has been *slower* per call than GodotPhysics
**Tier 2 · Corrob. 1 — this is why B3 must not be read as "just switch to Jolt"**

`https://github.com/godot-jolt/godot-jolt/issues/626`:

| Backend | `move_and_slide` |
|---|---|
| Godot Physics | 4.74 ms |
| Godot Jolt 0.6.0 | 3.41 ms |
| Godot Jolt 0.7.0 | 5.70 ms |
| Godot Jolt 0.8.0 | 6.11 ms |

Maintainer diagnosis: *"Godot Jolt is returning collisions from `body_test_motion` that causes Godot to believe that some of them are not contacting the floor"*, triggering excessive `apply_floor_snap`. Closed **not planned** (ref. PR #860).

Jolt's advantage in B3 is broadphase and solver *scaling*; its per-call `move_and_slide` overhead is a separate axis and has regressed before. At 24 bodies — well inside both engines' comfortable range — the constant factor may dominate the scaling factor. Version caveat: those numbers are godot-jolt 0.6–0.8 (GDExtension), not the in-tree 4.7 module. **This is a measurement, not a lookup.**

#### B5 — There is no published cost for `CharacterBody3D` collision on single-threaded wasm
**Coverage gap — see §Coverage gaps.** Every number above is native desktop. No source found gives a wasm/WebGL2 figure. The general WASM-vs-native literature (`https://www.usenix.org/conference/atc19/presentation/jangda`, T3, 2019 — 45% Firefox / 55% Chrome mean slowdown, peaks 2.08×/2.5×) is old, measured on SPEC CPU rather than game physics, and predates most Wasm SIMD and JIT work. **Do not extrapolate the RTX 5090 native number by a fixed ratio.** That would be inventing a measurement.

#### B6 — Ragdoll: no published cap, and the trade is already settled by the art pipeline
**Tier 1 for the docs · Tier 4 for the practice · Corrob. 2**

`https://docs.godotengine.org/en/latest/tutorials/physics/ragdoll_system.html` (4.7) gives exactly one performance statement: *"For each PhysicalBone3D the engine needs to simulate, there is a performance cost."* No count, no cost model, no cap. The only concrete guidance is structural — remove small and utility bones, prefer partial ragdolls — plus the community practice of calling `physical_bones_stop_simulation()` once a body settles (T4, Godot forum).

A minimal humanoid is realistically 8–11 `PhysicalBone3D`s plus joints. Twenty-four simultaneous ragdolls is 200–260 constrained rigid bodies with joint solving — on a single thread, in wasm, alongside 24 `CharacterBody3D`s and a WebGL2 renderer.

**The decisive constraint is upstream of performance:** this project has *no 3D models of any kind* and no rigged meshes. `PhysicalBone3D` requires a `Skeleton3D`. Building a rigged humanoid, with no art team and no budget, to drive a physics feature with an unknown cost on the shipping target, is the worst trade in this backlog. The gap analysis's own T1.1 recommendation (stay on billboards) already implies this.

**Recommended ordering of the three options:**
1. **Animated death clip** (sprite-frame swap) — zero physics cost, zero new art (the death sprite strips already exist), fits the established style. Ship this.
2. **Single-capsule "fake ragdoll"** — one `RigidBody3D` capsule given the shot's impulse, with the billboard parented to it. ~1 body per corpse, despawned on a timer. A genuine upgrade over (1) for directional death feedback, still trivially cheap, still zero new art. Take this if death feedback tests as insufficient.
3. **`PhysicalBone3D`** — do not.

---

### C. Payload

#### C1 — Measured: the live build is 10.58 MB over the wire, gzip only
**Tier 1 · Corrob. 1 (direct measurement, 2026-07-27) — the only hard number in this document that is about *this* build**

`curl -D -` against `https://fahim-mygithub.github.io/kriegsnacht/` with `Accept-Encoding: gzip, deflate, br, zstd`:

| File | `Content-Length` (on the wire) | `Content-Encoding` | Content-Type |
|---|---|---|---|
| `index.wasm` | **10,246,865** | `gzip` | `application/wasm` |
| `index.pck` | 261,528 | `gzip` | `application/octet-stream` |
| `index.js` | 69,439 | `gzip` | `application/javascript` |
| `index.html` | 2,187 | `gzip` | `text/html` |
| worklets (2 files) | ~4 KB | — | — |
| **Total first load** | **≈10.58 MB** | | |

Local recompression of the same artefacts:

| File | raw | gzip -9 | brotli -q 11 |
|---|---|---|---|
| `index.wasm` | 39,509,339 | 10,082,564 | **6,900,136** |
| `index.pck` | 291,940 | 261,412 | 255,514 |
| `index.js` | 279,815 | 68,399 | 59,857 |

**GitHub Pages does compress `.wasm` and `.pck`** (good — the Godot docs' claim at `https://docs.godotengine.org/en/latest/tutorials/export/exporting_for_web.html` that "GitHub Pages provides automatic gzip compression" is confirmed to extend to `application/wasm`, which was not obvious). **It does not serve Brotli**, even when the client advertises `br`. The 3.35 MB Brotli saving is unreachable without moving hosts.

Corroboration on the Brotli point (T3/T4): `https://github.com/orgs/community/discussions/21655` — GitHub Pages supports on-the-fly gzip only; pre-compressing to `.wasm.br` does not help because the server must advertise `Content-Encoding`, and Pages provides no header control. Cloudflare Pages, GitLab Pages and Vercel all do Brotli.

#### C2 — Acceptable size: the only credible published budget is Poki's, and this build is over it
**Tier 3 · Corrob. 2 (Poki developer docs, plus general web-performance statistics)**

Poki — a platform with real, large-scale abandonment telemetry — publishes: **initial download ≤ 5 MB, total ≤ 8 MB**, with "strongest titles" under 20 MB total, and a stated goal of *"getting players into fun in under 10 seconds"* (`https://developers.poki.com/guide/web-game-engines`, `https://sdk.poki.com/`).

At **10.58 MB with no loading-screen-deferrable split**, this build exceeds both thresholds before a single byte of content is added.

Generic web statistics (T3, e.g. `https://www.hostinger.com/tutorials/website-load-time-statistics`) — 53% mobile abandonment past 3 s, bounce +90% from 1 s → 5 s — are about *pages*, not games. Players expect a game to load; they do not expect a page to. Cite them as directional pressure, not as a game-specific threshold. Real arithmetic is more useful: on a 10 Mbit/s median connection, 10.58 MB is **~8.5 seconds of transfer alone**, before wasm compilation and shader warm-up. On 4G at 5 Mbit/s it is ~17 s.

**Important corollary:** the wasm caches (`Cache-Control: max-age=600` — note: only 10 minutes, so returning players re-validate often). First-load cost dominates.

#### C3 — Content headroom is enormous; engine headroom is nil
**Tier 1 · Corrob. 1 (local measurement)**

`index.wasm` is **97.5%** of the wire payload. All game content — 17 sprite strips, wall/floor textures, props, all scripts — is 292 KB raw / 261 KB gzipped. `assets/` on disk is 664 KB total. Audio is 0 bytes (synthesised at runtime, §A8).

So: **you could 10× the art budget and add ~2.5 MB of Ogg music and still not have moved the needle as much as a 20% engine-size reduction would.** The payload conversation should be about the export template, not about assets.

#### C4 — Engine-size levers, in order of return
**Tier 1 for mechanism · Tier 3/T4 for the magnitudes · Corrob. 3**

Already applied in `export_presets.cfg`: `variant/extensions_support=false`, `variant/thread_support=false`. Both correct.

Remaining, all requiring a **custom export template** built from source:
1. **Module stripping via a build profile / `custom.py`** — the largest lever. Text Server Advanced → Fallback, and disabling unused modules (webrtc, websocket, multiplayer, camera, mobile_vr, csg, gridmap, xr, theora, webp/svg if unused, gltf/fbx importers, and — check this — `godot_physics_3d` once Jolt is chosen, or `jolt_physics` if not). Reported reductions are large but the specific figures I found are T3/T4 and not for a 4.7 web build: `https://amann.dev/blog/2025/godot_web_size/`, `https://popcar.bearblog.dev/how-to-minify-godots-build-size/`.
2. **`optimize=size` SCons flag** and **`wasm-opt`** post-pass (T3, same sources).
3. **The engine's own trajectory**: the 4.3 blog quoted ~40 MB uncompressed / ~5 MB Brotli for the stock template. This project's 4.7 template is 39.5 MB / 6.9 MB Brotli — i.e. it has not shrunk, and if anything the Brotli figure is worse. Do not expect a future release to solve this for you.

**Honest caveat:** I found **no** measured before/after for a Godot 4.7 web build with modules stripped. Every figure is either an older version or a non-web platform. The saving is real but its magnitude for *this* project is unmeasured. See §Measurement M5.

#### C5 — Audio encoding: what to use if pre-baked audio is ever added
**Tier 1 · Corrob. 2 (`doc/classes/AudioStreamWAV.xml`, engine source)**

`AudioStreamWAV` formats: `FORMAT_8_BITS`, `FORMAT_16_BITS` (uncompressed PCM), `FORMAT_IMA_ADPCM`, `FORMAT_QOA` (Quite OK Audio) — the latter two lossy, roughly 4:1. Ogg Vorbis is a separate resource type and, per §A8, is sample-compatible on web.

Practical ordering for this project:
- **Short SFX (< 2 s):** WAV / QOA. Small enough that container overhead dominates; QOA decodes trivially.
- **Music / long ambience:** Ogg Vorbis, and consider giving *that one player* `playback_type = Stream` (accepting its latency) since long loops have known Sample-mode looping bugs (§A7).
- **Sample rate is the cheapest lever.** `sfx.gd` already uses 22,050 Hz. The class docs note lower rates such as 32,000 or 22,050 are usable "with no loss in quality" for lower-pitched sources. Halving the rate halves the bytes and halves the `AudioBuffer` RAM.
- **Mono, always**, for anything played through `AudioStreamPlayer3D` — a stereo source defeats positional panning and doubles the size.

#### C6 — Texture compression on WebGL2
**Tier 1 for the current state · Tier 2/3 for the recommendation · Corrob. 3**

Current state (local, T1): every texture imports with `compress/mode=0` (Lossless) and `metadata={"vram_texture": false}`, `mipmaps/generate=false`. So there is **no VRAM compression in use at all** — textures are stored as PNG in the `.pck` and uploaded uncompressed.

`export_presets.cfg` has `vram_texture_compression/for_desktop=true`, `for_mobile=false`. That flag only takes effect for textures actually imported with VRAM compression, so today it does nothing. Left as-is, if VRAM compression were ever enabled, `for_desktop` alone means S3TC/BPTC — which most mobile WebGL2 contexts do not expose, causing fallback or failure. Enable **both** or use Basis Universal.

For WebGL2 the recommendation ordering is:
1. **Leave the sprites lossless.** They are 64 px alpha-scissor billboards; block compression (DXT/ETC2) produces visible artefacts on hard alpha edges, and 664 KB of textures is not a problem worth solving.
2. **If bulk textures are ever added**, use **Basis Universal** (`Project Settings > Rendering > Textures > VRAM Compression > Basis Universal`), which transcodes at runtime to ETC2 on mobile and S3TC/BPTC on desktop from one asset. Caveat (T2): `https://github.com/godotengine/godot/issues/109337` reports a "null function or function signature mismatch" on HTML5 with Basis Universal in the 4.4.beta1–4.4.1 range. **Unverified for 4.7 — test before committing.**
3. **Do turn on `mipmaps/generate` for the wall/floor textures.** This is an image-quality fix (the gap analysis already flags edge crawl at T0.7) with a ~33% texture-memory cost and negligible download cost, and it is orthogonal to compression.

---

## Recommendations for this project

Ordered by (value × confidence) ÷ effort, and justified against the constraints.

**R1 — Verify and then explicitly set the physics engine. (5 minutes)**
Run M0. If it confirms GodotPhysics3D, add to `project.godot`:
```ini
[physics]
3d/physics_engine="Jolt Physics"
```
…then run M1 under *both* values and keep whichever wins. Explicit is right either way: relying on an unwritten default that the engine's own release notes describe as having changed is how a physics backend silently swaps under you on an editor upgrade. Justification vs. constraints: costs nothing in payload (both modules are already in the stock template), no art, no threads required (`run_on_separate_thread` is compiled out under `THREADS_ENABLED` — both servers hard-code `using_threads = false` when threads are off, T1 source).

**R2 — Design the audio layer for Sample mode from day one; do not plan reverb.**
The gap analysis's VS-1 "add a bus layout" is fine for *volume grouping and mixing control*, which works. But drop any plan for `AudioEffectReverb`, Doppler, or `Area3D` reverb zones on the shipped build — they will work in your editor and vanish in the browser, which is the worst possible failure mode for a solo developer. If a "muffled indoors" cue is wanted, achieve it with **volume and low-passed source material** (bake a darker variant of the sample in `sfx.gd` and cross-fade by zone) rather than with a bus effect. This is entirely in keeping with the project's existing procedural-audio approach and costs zero bytes.

**R3 — Cap concurrent 3D voices at 12–16 and enforce it explicitly.**
Rationale: §A2's ~344 msg/s/voice on the single main thread. Implementation:
- Keep the existing pool pattern in `sfx.gd` but make the pool `AudioStreamPlayer3D`, and *stop* rather than let a voice run out when the pool wraps.
- Set `max_distance` on every 3D player (§A6) — 20 m for groans per the VS-2 plan, tighter for footsteps. This is the documented CPU lever and it removes voices from the Web Audio graph entirely.
- Set `max_polyphony` deliberately (default is `1`); for a shared "zombie vocal" player, oldest-wins stealing is the right behaviour.
- If you use `AudioStreamPolyphonic` instead, **check `play_stream`'s return value against `INVALID_ID`** — it drops silently (§A5).

**R4 — Do not build `PhysicalBone3D` ragdolls. Ship the sprite death clip; keep the single-capsule fake ragdoll as the one upgrade path.**
Justified by the no-art-team constraint before it is justified by performance: `PhysicalBone3D` needs a rigged `Skeleton3D` that does not exist and cannot be cheaply produced. See §B6.

**R5 — Treat the payload as an engine problem, not a content problem.**
Concretely: (a) accept that Brotli is off the table on GitHub Pages unless you move to Cloudflare Pages or GitLab Pages — that single move would take 10.58 MB → ~7.2 MB, a 32% cut for zero code change and it is worth pricing; (b) if you stay, the only real lever is a custom export template with modules stripped (§C4), which is a day of SCons work with an unmeasured payoff — do M5 before committing to it; (c) meanwhile, add art and audio freely, because content is 2.5% of the download.

**R6 — Fix the renderer field in `perf_probe.gd` before trusting another number from it.**
`perf_probe.gd:198` reports `ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")`. That key has no `.web` override in this project, so it will report **`forward_plus` in the web build** while the build actually runs `gl_compatibility`. Replace with `RenderingServer.get_current_rendering_method()` (returns `forward_plus` / `mobile` / `gl_compatibility`, T1) and `RenderingServer.get_current_rendering_driver_name()` (`opengl3`, `opengl3_angle`, …). Otherwise every future benchmark carries a mislabelled renderer.

---

## Coverage gaps

Things I could not verify. None of these are guesses presented as facts above.

1. **No published wasm/WebGL2 physics or audio benchmark for Godot 4.x exists that I could find.** Every physics number in §B is native desktop. Every audio limit in §A2 is derived from reading the source, not from a measurement. This is the single largest gap and it is unfixable by research — see §Measurement.
2. **Where Godot 4.6+ actually makes new projects choose Jolt.** I confirmed the runtime fallback is GodotPhysics3D and that `jolt_physics` never self-registers as default (T1 source, both files read in full). I could **not** locate the code in `editor/` that writes `physics/3d/physics_engine="Jolt Physics"` into a new `project.godot`; GitHub code search over `editor/` returned only translation files and `editor_build_profile.cpp`. It is possible the mechanism lives in a file the search index missed. The practical conclusion (this project has no key → GodotPhysics3D) is unaffected, but M0 exists precisely because I will not assert it without a runtime check.
3. **The magnitude of a custom-template size reduction for a 4.7 web build.** All figures found were for 4.3/4.4 or for desktop binaries (T3/T4).
4. **Whether the attenuation low-pass filter is truly absent on web** (§A3) — a source-absence inference, no maintainer statement, no issue found.
5. **Whether `AudioStreamPlaybackPolyphonic.stop_stream()` still fails on web Sample playback in 4.7** (§A7) — issue #94724 is against 4.3 beta3 and I found no 4.5/4.6/4.7 retest.
6. **Whether Basis Universal's HTML5 crash (#109337) persists in 4.7** — reported 4.4.beta1–4.4.1, not reproducible in 4.4.dev7. Version-uncertain.
7. **Concurrent `AudioWorkletNode` ceilings per browser.** Paul Adenot's `https://padenot.github.io/web-audio-perf/` (T3, Firefox Web Audio implementer — the best available source) gives design principles but explicitly no node-count numbers, no postMessage cost figure, and no worklet-vs-native-node comparison. Nobody publishes this; it varies per browser and per machine.
8. **`AudioEffectReverb` desktop cost** — not researched, because §A1 makes it moot for the shipping target. If a desktop build is ever a goal, this reopens.
9. **Godot 4.7 is unreleased/in-development.** All engine-source citations are from `godotengine/godot@master` (commit `1597016`), which is 4.7-dev, and all docs citations are from `docs.godotengine.org/en/latest`, labelled "4.7 (latest/unstable)". Behaviour may change before 4.7 stable. Where I could only find 4.3/4.4-era evidence (§B3, §B4, §A7, §C4, §C6) I have said so inline.

---

## What must be measured rather than researched

The honest answer to most of this brief is "measure it". `scripts/perf_probe.gd` is a good harness and needs five additions. Everything below runs inside the engine and beacons to `http://127.0.0.1:8970/result`, so it works in the exported web build where JS-side FPS is fiction (as the probe's own header comment correctly notes).

### M0 — Which physics server is actually running (30 seconds, do this first)

Add to `_finish()`'s `env` block:
```gdscript
"physics_engine_setting": ProjectSettings.get_setting("physics/3d/physics_engine", "<unset>"),
"rendering_method": RenderingServer.get_current_rendering_method(),
"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
```
`<unset>` confirms §B2. This also fixes the mislabelled-renderer bug in R6.

### M1 — The physics question: cost of mutual collision, 0→24, both backends

Extend the probe's stage loop with a second axis. Keep `STAGES := [0, 6, 12, 18, 24]` and add:

```gdscript
const COLLISION_MODES := [false, true]   # masks disjoint (today) vs. mutual
const PILE := true                        # herd every zombie at one doorway cell
```

For each `(stage, collision_mode)` pair:
1. Set `zombie.collision_mask = 1` (today) or `1 | 2` (planned), and player `collision_mask = 1` or `1 | 4`.
2. **Force the doorway pile** — this is the load case that matters and the current `_spawn()` scatters zombies randomly, which will *understate* the cost by a wide margin. Pick the narrowest walkable cell in `_main.map`, place the player one cell beyond it, and spawn all N zombies on the far side so the flow field funnels them into it. Measure only after the pile forms (extend `SETTLE` to ~4 s for this mode).
3. Sample the three physics monitors that already exist and are not currently recorded:

```gdscript
const MONITORS := {
    ...
    "phys_active_objects": Performance.PHYSICS_3D_ACTIVE_OBJECTS,
    "phys_collision_pairs": Performance.PHYSICS_3D_COLLISION_PAIRS,   # the key number
    "phys_islands":         Performance.PHYSICS_3D_ISLAND_COUNT,
    "audio_latency_ms":     Performance.AUDIO_OUTPUT_LATENCY,
}
```
`PHYSICS_3D_COLLISION_PAIRS` is the direct read on whether the doorway pile is going quadratic. Plot it against N: if it rises as N² rather than N, the boid separation in `zombie.gd:163-173` and the physics broadphase are fighting each other.

4. **Report the outputs that matter, not just mean FPS.** `p99_ms` and `worst_ms` are already collected — good, keep them front and centre. A doorway pile is a *spike* problem; a mean will hide it.

Run the whole matrix twice: once with `physics/3d/physics_engine` unset (GodotPhysics3D) and once `="Jolt Physics"`. That directly resolves §B3 vs §B4, which no amount of reading will.

**Where to run it:** the exported web build, in a normal (non-automation) browser tab, on the median machine you actually care about — an integrated-GPU laptop, not the 5090. Also run it once natively on the 5090 so you have a native↔wasm ratio *for this workload*, which is the only trustworthy way to get one (§B5).

### M2 — The audio question: voice count vs. frame time

Add an audio axis the probe does not currently have:

```gdscript
const VOICE_STAGES := [0, 4, 8, 12, 16, 24, 32]
```

For each: spawn N `AudioStreamPlayer3D` nodes scattered around the player, each looping a ~2 s synthesised groan from `Sfx`, each with `max_distance = 0.0` (worst case) in one pass and `max_distance = 20.0` in another. Hold the zombie count at 24 so the measurement reflects real conditions. Record `mean_ms`, `p99_ms`, and `Performance.AUDIO_OUTPUT_LATENCY`.

What you are looking for is **not** a clean cliff. Per §A2 the cost is main-thread message pressure, so it will show as a rising `p99_ms` and rising jitter well before anything audibly drops out. Find the N where `p99_ms` starts diverging from `median_ms` and set the voice cap below it.

Also run one pass with `max_distance = 0.0` vs `20.0` at N=24 specifically — that isolates the §A6 saving and tells you whether distance culling is worth the code.

### M3 — Verify the Sample-mode limitations by ear, on the deployed build

Not automatable, but 15 minutes and it closes gaps 4 and 5:
1. Add an `AudioEffectReverb` to a bus, route one sound to it. Editor: reverb. Web build: no reverb → confirms §A1.
2. Set `attenuation_filter_cutoff_hz = 500` on a distant looping source. If it does not audibly muffle on the web build, §A3's inference is confirmed and should be reported upstream.
3. Play a polyphonic stream, call `stop_stream()`. If it keeps playing, #94724 survives into 4.7 — do not build a voice manager on `AudioStreamPolyphonic`.
4. Confirm `finished` fires on an `AudioStreamPlayer3D` in the web build (#93904's fix holding). Your whole pool-recycling strategy depends on it.

### M4 — Boot cost of runtime audio synthesis

`sfx.gd` bakes every sound in `_ready()` with GDScript per-sample loops. Wrap it:
```gdscript
var t0 := Time.get_ticks_usec()
# ... existing bake calls ...
_post({"event": "sfx_bake", "usec": Time.get_ticks_usec() - t0, "sounds": _cache.size()})
```
Run it in the web build. This gives you the marginal cost per new sound, so the audio backlog (VS-1, VS-2, VS-4, the ancestor's ~10 deleted cues) can be costed in milliseconds of added boot time before it is written. Note the probe already captures `boot_to_first_frame_ms` — but it assigns `Time.get_ticks_msec()` at `begin()`, which is a *timestamp*, not a duration. Fix that too while you are in there.

### M5 — Custom export template size delta

Purely a build-system experiment, no probe changes:
1. Build a stock 4.7 web release template from source; record `.wasm` size and `gzip -9` size. Confirm it reproduces the current 39,509,339 / 10,082,564.
2. Build again with a `custom.py` disabling: `text_server_adv` (use fallback), `webrtc`, `websocket`, `camera`, `mobile_vr`, `openxr`, `theora`, `csg`, `gridmap`, `navigation` if unused, plus whichever of `godot_physics_3d` / `jolt_physics` M1 rejects. Add `optimize=size`.
3. Run `wasm-opt -Oz` on the result.
4. Record gzip size at each step, and **verify the game still boots and plays**.

Only commit to this path if step 2 gets the gzipped `.wasm` under ~7 MB. Below that it is a day of work for a marginal gain, and moving to a Brotli-serving host achieves ~7.2 MB for free.

### A note on methodology

Run every measurement three times and report the median of the medians. Single-run browser numbers are dominated by JIT warm-up, shader compilation stalls (unavoidable on the main thread per the project constraints), and whatever else the OS is doing. The existing `SETTLE := 1.5` is probably too short for a web build where shader compilation happens lazily on first draw — raise it to 3–4 s for web runs, or the first stage will absorb every compilation stall and libel itself.
