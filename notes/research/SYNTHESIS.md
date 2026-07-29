# SYNTHESIS — what to build, in what order, and what is now ruled out

**Date:** 2026-07-27
**Inputs:** R1-R7 (platform/domain research), M1-M3 (mechanic research), `ancestor-diff.md`, `2026-07-27-gap-analysis.md`.
**Audience:** the developer about to start Milestone 1. This document supersedes the research briefs as the working artefact; they remain the evidence base.

**How to read this.** Section 1 lists what the research *changed*. Section 2 is the number table every later decision cites. Section 3 is free progress. Section 4 is one recommendation per mechanic. Section 5 is what we still do not know. Section 6 is the plan.

Where two briefs disagree, this document picks one and says why. Where the honest answer is "measure it", it says that instead of inventing a preference.

---

## 1. Decisions now forced by evidence

### 1.1 Forward+-only techniques that must be abandoned

The shipped build is `gl_compatibility` on WebGL2 and **cannot be anything else** — `main/main.cpp` declares `rendering/renderer/rendering_method.web` as a single-value enum containing only `gl_compatibility` (R1, Tier 1). Every ❌ below is unconditional. The editor currently runs Forward+, so **the editor is lying to you**; every visual decision must be validated in an exported web build.

**Delete these from the backlog outright:**

| Technique | Where it was proposed | Why it is dead |
|---|---|---|
| `Decal` nodes | T3.9, T2.10, M3 | All GLES3 decal API functions are empty stubs in 4.7. PR #118070 is open, milestone **4.8**. |
| `FogVolume` / volumetric fog | T1.10 "dust motes and light shafts" | ❌ in Compatibility. Depth+height fog is the entire atmosphere budget. |
| SSR, SSIL, SDFGI, `VoxelGI` | scattered raw findings | ❌ |
| `CompositorEffect` | implied by "post-process pass" phrasing | Forward+/Mobile only |
| Depth-of-field blur, sub-surface scattering | raw findings | ❌ |
| FXAA / SMAA / TAA / FSR2 | T0.7 step 3 | ❌. **MSAA 3D is the only AA available** (SSAA via render-scale >1 also works but is expensive). |
| Debanding | — | ❌, and the colour buffer is RGBA8 LDR, so gradients and fog *will* band. |
| Light projector textures (spotlight cookies) | T1.10 | ❌ |
| PCSS soft shadows | — | ❌ — shadows are hard-edged PCF. For this genre that is a feature. |
| Particle **trails** | T3.9 "ribbon tracers" | Explicit `WARN_PRINT_ONCE_ED`, no effect |
| Particle **sub-emitters** | — | same |
| **`GPUParticles3D.emit_particle()`** | any "spawn a burst at this exact point" design | same — **this is the one that changes FX architecture**. See §4.3. |
| Vector-field particle attractors, SDF particle colliders | — | same |
| Shader baker, pipeline precompilation, ubershaders, the "hidden node" prewarm trick | any "precompile shaders" plan | Docs state verbatim that the page "only applies to Forward+ and Mobile, not Compatibility" and "the shader baker is not supported on the web platform". |
| Compute shaders / any `RenderingDevice` code path | — | ❌ |
| `Environment.glow_levels/1..7` and `glow_blend_mode` | any glow-tuning task | Never read by the Compatibility path. `post.glsl` hard-codes screen blend. Tuning these sliders does nothing on web. |
| SSAO `half_size`, `blur_passes`, `fadeout_*`, `adaptive_target` | R1's own first-draft measurement plan | Silently discarded by `environment_set_ssao_quality`. Only `ssao_intensity` (×2.0) and `ssao_radius` (×0.5) are live. |
| `INSTANCE_CUSTOM` on a plain `MeshInstance3D` | per-zombie shader variation | Hardcoded `vec4(0.0)` outside `USE_INSTANCING`. Only MultiMesh/particles get it. |
| `set_instance_shader_parameter()` on the web build | R5 tier 3 in R6 | godot#112674 open: instances past ~20 render **black** on web export, budget is global across materials, invisible nodes still count. Four independent confirmations. Use `SpriteBase3D.modulate` instead. |
| `no_depth_test = true` for the viewmodel | **T2.2, explicitly** | R1 F10: `depth_test_disabled` *forces the surface into the transparent queue*, which runs after the entire opaque queue, so it draws unconditionally over every alpha-scissor billboard and every wall. Correct only for things that should always be visible — which is not what T2.2 meant. |
| SubViewport + `CLEAR_MODE_NEVER` splat-accumulation buffer | R1's own first-draft top recommendation | godot#86940, filed by a Godot org **member** with an MRP: `CLEAR_MODE_NEVER` does not render in Compatibility. Open since Jan 2024. Downgraded to a one-hour spike, not a plan. |
| SubViewport viewmodel camera | M1 F2 (four repos do it) | Rejected on **cost**, not support: a second full-screen colour+depth target, clear and composite blit, plus a second shader compile of every viewmodel material on the main thread. See §4.1. |
| `AudioEffectReverb`, `AudioEffectHardLimiter`, `AudioEffectCompressor`, sidechaining, `Area3D` bus override, Doppler | **T2.1 in full, T1.9's muffle, T3.8 in full** | See §1.2. This is the largest single deletion. |
| `AudioStreamSynchronized` layered stems | **T1.6's ambience design** | godot#109494 open: garbled audio on no-threads web builds, reproduced on exactly this configuration with an MRP. |
| `PhysicalBone3D` ragdolls | T2.6 death variants, T4.3 | No rigged meshes exist and none can be cheaply produced. 24 ragdolls ≈ 200-260 constrained bodies on one wasm thread. Ruled out upstream of performance. |
| Migrating to `NavigationRegion3D` + `NavigationAgent3D` | R5's own framing question | `use_async_iterations` is compiled to `false` without `THREADS_ENABLED`; `WorkerThreadPool` runs every task inline. Door purchases become synchronous main-thread navmesh rebuilds; unreachable targets (which this game creates *by design*) are the documented catastrophic case. |
| `LightmapGI` | M3 F4 | Rendering works; baking needs RenderingDevice, and the level is built at runtime with `gi_mode = GI_MODE_DISABLED`. Converting to a baked `.tscn` abandons runtime generation. |
| Fresnel / rim-light overlay shaders | generic "rim light the zombies" advice | Geometrically meaningless on a billboard: `NORMAL` is constant across the quad, so fresnel produces a flat tint, not a rim. Use an alpha-edge outline in the sprite shader instead. |
| Raising `max_lights_per_object` above 8 | T0.7-adjacent | Costs shader compile time you cannot cache on web. Split the geometry instead. |
| `antzGames/Godot-Compatibility-Decal-Node` | M2 F21, M3 | **No licence stated in its README.** Disqualified for a project deployed publicly under the author's own name until that is resolved. |
| `QbieShay/DecalCo` | surfaced in search | Godot **3.2+**. Rejected under version discipline. Recorded so nobody loses a day to it. |

**Newly *available*, and previously assumed dead:**

- **SSAO is supported** in Compatibility since 4.6 (GH-109447, in the 4.6 beta 1 release notes). Every pre-2026 source saying otherwise is 4.5-or-earlier. It is *S4AO*, fused into the existing post/tonemap fullscreen triangle — marginal cost is extra depth taps, no extra render target, no extra pass. **Cheaper than Forward+ SSAO.**
- **`Environment.adjustment_*` (BCS) and colour-correction LUTs (3D or 1D) are fully supported.** `USE_BCS`, `USE_COLOR_CORRECTION`, `USE_1D_LUT` in `post.glsl`. For a project with no art team, **a hand-authored LUT is the highest visual-return-per-hour tool available** — it restyles the whole game from one small image, costs one texture fetch in a pass that already runs, and needs no shader authoring. This was absent from the backlog entirely; add it.
- **`GPUParticles3D` genuinely works** — full transform-feedback implementation, not a CPU fallback. The widely-repeated "Compatibility silently falls back to CPU particles" claim is **false**. Only the depth *sort* is CPU-side.
- **`SCREEN_TEXTURE` / `DEPTH_TEXTURE` work in spatial shaders** — one backbuffer blit before the transparent pass, no mipmaps, and using them drags the material into the transparent queue.
- **Occlusion culling builds for `wasm32`** and is present in stock web templates — but it parallelises through `WorkerThreadPool`, so on a single-threaded build it all runs inline on your one thread. Not obviously a win; room-graph visibility from `MapData` is strictly better information at a fraction of the cost.
- **Glow is supported** (the 2022 tracker entry saying otherwise is four years stale), with a fixed 4-level chain and screen blend.

**One rule that follows from all of the above:** *the post-processing configuration is a build-time decision, not a runtime one.* Every toggle of glow, SSAO, adjustments or the LUT is a fresh `glLinkProgram` of the post shader, mid-frame, with no cache. Pick one combination (`USE_GLOW | USE_BCS | USE_SSAO_MED | USE_COLOR_CORRECTION`) and never change it at runtime. The T0.7/A10 quality selector must therefore operate on **`scaling_3d_scale`, not on effect toggles.**

### 1.2 The audio plan is wrong at its foundation

This is the single largest reversal in the research, and it invalidates a whole backlog tier.

On web with `thread_support=false`, Godot 4.3+ plays audio as **samples**, not streams — each voice is handed to the browser's Web Audio graph. There is no software mixer in wasm. Consequences, all Tier 1 (official 4.7 docs plus `platform/web/js/libs/library_godot_audio.js` read directly, corroborated by R2 and R3 independently):

| Feature | Status on the shipped build |
|---|---|
| `AudioEffect*` of any kind (reverb, limiter, compressor, filter, delay) | **Does not run.** "AudioEffects are not supported." The engine's own JS library contains zero `ConvolverNode`, `BiquadFilterNode`, `PannerNode` or `DelayNode` — only gains and channel splitter/mergers. |
| Reverb buses, `Area3D.audio_bus_override` | Dead |
| Doppler | Dead |
| `attenuation_filter_cutoff_hz` / `attenuation_filter_db` (the "distant sounds are muffled" cue) | **Absent.** Inferred from source absence — no maintainer statement, no issue. Verify by ear (M3-audio). |
| Distance attenuation, stereo panning, `max_distance` culling | **Work.** Computed in wasm on the game frame and pushed to 6 `GainNode`s. Near-zero cost. |
| `AudioStreamWAV`, `AudioStreamOggVorbis`, `AudioStreamMP3` as samples | All `can_be_sampled() == true`. The restriction is *static vs streaming*, not *WAV vs compressed*. |
| `AudioStreamPolyphonic`, `AudioStreamRandomizer` | Work |
| Bus **volume** grouping (for volume sliders) | Works |
| `AudioStreamSynchronized` | godot#109494 — garbled on this exact configuration |

**Therefore:**
- **T2.1's `default_bus_layout.tres` with `AudioEffectHardLimiter` on Master and sidechained `AudioEffectCompressor` is deleted.** Buses survive only as volume groups for the settings menu.
- **T3.8 (reverb, occlusion, per-room acoustics) is deleted in full.** It was a Tier 3 L-effort item resting entirely on features that do not execute.
- **T1.9's global low-pass muffle on down is deleted.** The ancestor's `setMuffled()` is the most memorable audio moment in a Zombies death and it cannot be reproduced with a bus effect. **Replacement:** bake a darker, low-passed variant of the handful of sounds that matter and crossfade to them on down. This is entirely in keeping with the project's procedural-audio approach and costs zero bytes.
- **T1.6's layered `AudioStreamSynchronized` ambience is deleted.** Replacement: pre-mixed stem sets per tension tier (rounds 1-5 / 6-15 / 16+), or independent players started in the same frame accepting mild drift.
- **The worst failure mode here is that all of these work in the editor and vanish in the browser.** Do not build against the editor's audio.

**The real audio ceiling is not mixing, it is main-thread message pressure.** Every live voice constructs one `AudioWorkletNode` whose `process()` posts a position message every 128-sample render quantum — **~344 messages/second per voice at 44.1 kHz**, landing on the same single thread that runs `_process`, `_physics_process` and the WebGL2 renderer. 24 groaning zombies = ~8,300 msg/s. The gap analysis's VS-2 "voice-capped at ~10" is, by luck, in the right neighbourhood. Design against **12-16 concurrent 3D voices** and set `max_distance` on every one (it defaults to `0.0` = never culled, and the class docs name it as the documented CPU lever).

Two overflow behaviours, inconsistent, both Tier 1: `AudioStreamPlaybackPolyphonic.play_stream()` returns `INVALID_ID` and **drops silently**; `AudioStreamPlayer3D.max_polyphony` (default **1**) **steals the oldest**. For a horde, oldest-wins is what you want. If you use `AudioStreamPolyphonic`, check the return value.

### 1.3 Canon numbers that contradict the current code — and one that contradicts the gap analysis

R4 read Treyarch's shipped GSC directly (Plutonium t4/t5/t6 mirrors, adversarially re-verified by a second pass against the same repos and against this project's source). These are Tier 1 game-source numbers, not wiki claims.

| Quantity | Port today | Canon (WaW/BO1) | Action |
|---|---|---|---|
| Zombie melee damage | 34 | **60** | Change |
| Player base HP | 100 | 100 | Correct |
| Juggernog HP | **250** | **160** (upgraded: 190) | Change |
| Hits to down, unperked / with Jug | 3 / 8 | **2 / 3** | Falls out of the above |
| Per-attacker damage cooldown | one **global** 0.35 s | per-attacker `ignore_enemy_timer = 0.4` | Change — without it a pile of six deletes a full-health player in one frame |
| Zombie speed | continuous `minf(1.05 + r*0.155, 3.45)`, saturates round 16 | **three discrete classes rolled per spawn** | Change (§4.5) |
| Zombie HP curve | 150, +100 to r9, then ×1.1, uncapped | identical | **No action.** |
| Zombie HP **cap** | none | **none exists** | **No action.** |
| Power-up trigger | kill counter (first at 6, then 16-29) | lifetime **points earned**: first at 2,000, then `+2000×1.14ⁿ`, never reset; **plus** a flat 3% per death | Change the trigger only |
| Per-round drop cap | 4 | 4 | **Already correct** |
| Headshot | flat ×1.5 damage | **no damage multiplier anywhere in the zombie scripts**; +50 points | Move the multiplier per-weapon; keep the +50 |
| Insta-Kill points | full payout incl. headshot bonus | BO1: **flat 50** | Change |
| Dog rounds | fixed cadence | first `randi_range(5,7)`, then `+randi_range(4,5)` | Change |
| Dog-round Max Ammo | none | **guaranteed** on the last dog, with `drop_count` reset to 0 first so the per-round cap cannot swallow it | Add |
| Perk cap | none | **4** | Add as a constant |
| Quick Revive (solo) | 1500, power-gated, no revive | **500**, live from round 1 without power, 1 life per purchase, machine leaves after 3 | Change |
| PaP wall-buy ammo | derived | flat **4500** | Add |

**Three corrections to the gap analysis itself, all from R4's verification pass:**

1. **T0.1's proposed fix is wrong.** It says: *"Set `melee_damage = 50.0` so the canon 2-hits-to-down / 5-with-Juggernog counts hold against `BASE_HP 100` / `JUG_HP 250`."* Both halves are wrong. Canon is 60 damage against 100/**160**, giving 2 and **3**. The community's "250 HP / 5 hits" figure is **BO3 with *upgraded* Juggernog** (100 + 150 = 250, ⌈250/60⌉ = 5) — an era conflation with an exact source. If you want the 5-hit feel, change *Juggernog* and label it a deliberate BO3-flavoured deviation; do not change the melee damage, because 60-vs-100 is what makes the unperked player feel correct.
2. **T0.1's "cap `zombie_hp` at 1,000,000 as canon does" attacks something that does not exist.** There is no health cap in any title. The port's curve is already canon. The only "cap" in the series is BO2's int32 overflow clamp at round 163, which Godot's 64-bit ints spare you from inheriting. **No action.**
3. **"Hounds are too slow" is false and acting on it would do real damage.** `zombie.gd` gives hounds `base_speed * 1.55`, so the real ceiling is `3.45 × 1.55 × 1.14 ≈ 6.10 m/s` against a 4.88 m/s player sprint — hounds already outrun the player. The unlosable-game diagnosis applies to **standard zombies only**. Do not scale hounds. Also: the port already has ±14% per-spawn speed variance; what it lacks is the *discrete three-class structure* and the round-driven shift in the class mixture.

**Still unsourced:** WaW's zombie melee damage (WaW never sets `meleeDamage` in script). Use BO1's 60, which is sourced end-to-end, and label the port **BO1-era**.

### 1.4 Live platform defects

**(a) The pause key cannot work, and half of it is provable from spec.** WHATWG HTML's *activation triggering input event* definition explicitly excludes `Esc`; `requestPointerLock()` requires transient activation (MDN, Tier 1). Therefore `hud.gd:188-194`'s "Esc to resume → `Player.set_capture(true)`" **can never re-capture the mouse, in any browser, ever.** The overlay copy at `hud.gd:262` instructs the player to do the one thing that provably cannot work. Compounding (probable, not spec-guaranteed): the first Escape while locked is swallowed by the user agent, so pausing takes two presses. Godot's own docs add that capture must originate inside a live input event — `hud.gd` polls `Input.is_action_just_pressed` inside `_process`, which is the documented prohibited pattern.

**Fix, and it is not "make Escape work":** invert the trigger. *Losing the pointer lock is the pause event* (correct on every browser and also correct when the player alt-tabs); *resume is a click*, handled in `_unhandled_input` where transient activation is present, with `set_input_as_handled()` so the resume click does not also fire the weapon; rebind primary `pause` to `P` with Escape kept as a secondary; change the copy to **"Click to resume."** `DisplayServerWeb::mouse_get_mode()` queries the browser live in 4.7 (the 4.4-era desync was fixed by PR #102719), so polling `Input.mouse_mode` is a reliable detector. Do **not** pursue `navigator.keyboard.lock()` — four incompatible behaviours across three engines, and the Godot proposal is closed as not-planned.

**(b) `user://` has a real lost-write window, and it is wider than "mid-write tab close".** The engine hooks `FileAccess` close and flags an IndexedDB sync that fires on the *next* `main_loop_iterate()`. So: the write must reach `close()` (a `FileAccess` held in a member variable never syncs); the sync lands one frame later at the earliest, then runs an async IDB transaction with no completion signal; and **a backgrounded tab stops the main loop entirely**, so the classic loss case is *write → switch tab → close tab*. `JavaScriptBridge.force_fs_sync()` does not help — it only sets the same flag. `thread_support` is irrelevant to any of this (contradicting the gap analysis's T2.7 suspicion).

**Fix:** `localStorage` via `JavaScriptBridge.eval()` on web (synchronous by spec, committed before the call returns, ~5 MB quota against a <1 KB profile blob), `user://` on desktop with a mandatory `f.close()`. Do not bother with a `beforeunload` flush — a backgrounded tab cannot run it.

**(c) `perf_probe.gd` mislabels the renderer.** It reports `ProjectSettings.get_setting("rendering/renderer/rendering_method")`, which has no `.web` override in this project, so **it will say `forward_plus` in a build that is actually running `gl_compatibility`.** Every number it has ever produced carries a wrong label. Replace with `RenderingServer.get_current_rendering_method()` and `get_current_rendering_driver_name()`. Also `boot_to_first_frame_ms` assigns `Time.get_ticks_msec()` at `begin()` — that is a timestamp, not a duration.

**(d) The physics backend is GodotPhysics3D, and nobody chose it.** `project.godot` has no `physics/3d/physics_engine` key. In 4.7 source only `godot_physics_3d` calls `set_default_server`; `jolt_physics` registers but never self-defaults. Jolt *is* compiled into the stock web template (`config.py` excludes no platform). The 4.6 release note about Jolt becoming default applies to *new project creation*, not the runtime fallback. **This matters because T0.1 introduces exactly GodotPhysics3D's documented weak spot** — mutually-colliding `CharacterBody3D`, reported to degrade at 10-40 instances vs ~800 under Jolt (4.0/4.1-era, order of magnitude only). But there is real counter-evidence that Jolt's per-call `move_and_slide` has been *slower* (4.74 ms → 6.11 ms across godot-jolt 0.6→0.8). **At 24 bodies the constant factor may dominate the scaling factor. Measure both; do not assume.** Set the key explicitly either way — relying on an unwritten default that the engine's own release notes describe as having changed is how a physics backend silently swaps under you on an editor upgrade.

**(e) The payload is already over budget, and content is not the reason.** Measured live: `index.wasm` is **10,246,865 bytes gzipped**, total first load **≈10.58 MB**. The `.pck` is 261 KB. **The engine binary is 97.5% of the download.** Poki — the only platform publishing real abandonment telemetry — budgets ≤5 MB initial / ≤8 MB total. GitHub Pages does gzip `application/wasm` (good, and not obvious) but **does not serve Brotli** even when requested, so the 6.90 MB Brotli figure is unreachable without moving hosts. `Cache-Control: max-age=600` means returning visitors re-validate after ten minutes.
**Consequence:** *add art and audio freely.* You could 10× the art budget and add 2.5 MB of music without moving the needle as much as a 20% engine reduction would. The payload conversation is about the export template and the host, not about assets.

**(f) `CULL_DISABLED` on every world material.** `world_builder.gd:44` disables backface culling on every wall, floor and ceiling — a self-inflicted ~2× rasterisation cost on all static geometry, taken to avoid debugging winding order. On a fill-rate-bound WebGL2 target this is likely the cheapest frame-time win in the codebase.

**(g) Texture compression is inert but armed.** All 56 PNGs import at `compress/mode=0` with `metadata.vram_texture=false`, so `vram_texture_compression/for_desktop=true` currently selects nothing — **the gap analysis's T0.2(c) describes a bug that does not exist today.** But every sprite carries `detect_3d/compress_to=1`, so the moment the editor's 3D-usage detector fires, it silently reimports as VRAM Compressed and ships desktop-only formats. **Fix: set `detect_3d/compress_to=0`, leave `for_mobile=false`.** Block compression on 64 px nearest-filtered pixel art is worse than useless. (Even if it fired, PR #101178 confirms GLES3 decompresses unsupported formats at runtime — cost is CPU decompress, not black textures.)

**(h) The threads constraint is overstated, and it should be restated honestly.** Godot's PWA export option ships a service worker that rewrites every response with `COEP: require-corp` and `COOP: same-origin`, and the stock HTML template — **already present verbatim in this project's shipped `docs/index.html`, dormant only because PWA is off** — auto-installs it and reloads. This is first-party, documented, in-tree engine machinery. Cost: one extra navigation on first visit, no third-party subresources, a larger template. **This is not a recommendation to flip today.** But "threads cannot be turned on, full stop" is not accurate, and it is being carried into every downstream decision — including an audio plan that cannot work without them. Restate as: *single-threaded by choice, because the threaded build requires a service-worker COOP/COEP shim with a known price.* Then treat "enable threads" as a live, priced option — and note that it is the **only** route back to audio bus effects. Untested on GitHub Pages specifically; see §5.

### 1.5 Architecture decisions now forced

**The map must be split into per-room `MeshInstance3D` nodes.** This is the highest-value structural change in the research.

Correct the premise first, because both R1's first draft and M3 got it wrong: `world_builder.gd::_commit()` builds **one `MeshInstance3D` per texture** (up to 7 wall + 4 floor + 4 ceiling ≈ 15), not one for the whole map — but every one of them spans the full 42×34 grid, so they share an AABB, a map-centre score, and a light list. And the project spawns **exactly 8 `OmniLight3D`s** (one per `MapData.ROOMS` entry), not 10, against a cap of 8. **Nothing is being dropped today.** M3's "you are already over, and which 8 win is view-dependent" is false.

The two real reasons to split, both stronger than the "lighting is arbitrary" claim:

1. **Present-tense fill-rate waste.** Light pairing gates on **AABB intersection first** (`OmniLight3D`/`SpotLight3D` class docs, Tier 1), then scores survivors. A map-spanning instance intersects *every* light in the level, so all 8 omnis are paired to every wall, floor and ceiling instance, and `OMNI_LIGHT_COUNT` is a uniform — **every fragment on the map currently loops over all 8 omnis.** Per-room instances drop most to 1-3.
2. **Zero headroom, with a silent cliff.** Light #9 — a muzzle flash, a Pack-a-Punch glow, a perk machine, a lit generator, a box beam — silently evicts a room lamp. Because the score is computed from the map centre for all 15 instances, the eviction is *identical everywhere and stable*, so you get a room that is dark, in the same way, forever, with **no warning printed**.

Splitting also buys per-room frustum culling, cheap additive shadow passes (F6), and makes room-graph visibility possible. Draw-call arithmetic: 8 rooms × ~3 textures ≈ 24-40 worst case before culling, against `max_renderable_elements = 65536`. **It costs nothing and buys back fragment cost.** Granularity note: the code pairs per *geometry instance*, not per mesh resource (the class docs say "mesh resource" and are wrong) — so two instances sharing one `Mesh` still get independent light lists, which is in your favour.

**One shadow-casting light, and it is the torch.** In Compatibility, all shadowless lights plus the base pass are one draw; **every additional shadow-casting light re-draws every instance it touches, with additive blending** (clayjohn, PR #77496). A `SpotLight3D` needs one shadow render; an `OmniLight3D` in CubeMap mode needs **six**, and Dual Paraboloid `ERR_FAIL`s outright. Shadowed lights also blend in sRGB rather than linear, so they look brighter than an unshadowed light of the same energy — **retune `light_energy` after enabling shadows, do not just flip the flag.**

**Shader warm-up is mandatory and runs on every page load.** There is no shader cache on web: the GLES3 program-binary cache is compiled out under `#ifdef WEB_ENABLED // not supported in webgl`, because WebGL 2.0 exposes no program-binary API. **Every visitor, on every page load, recompiles every shader variant from GLSL source, on the main thread, mid-frame.** The only mitigation is the 1998 one the docs name explicitly: display every material, particle system and lighting configuration in the camera frustum for at least one frame during load. This is a permanent maintenance task, not a one-time fix — it goes in the release checklist, and it is re-run after every new material.

**Keep the flow field.** Do not migrate to navigation. Beyond §1.1's reasons, the BFS gets unreachability for free (`dist == -1`), and this is a genre where the player is routinely behind an unpurchased door — which is navigation's documented 40× framerate cliff.

**Billboards are confirmed; T0.8 is closed and should not be revisited.** The decisive argument is not aesthetic or effort — it is that on web + Compatibility there is no shader precompilation and no thread to compile on, so a 3D zombie's *material variety* converts directly into mid-round frame hitches you cannot engineer away. Add: no decals, open skinned-mesh correctness bugs on exactly this renderer (godot#67522, #94500), 384 rigid bodies for physics hit reactions, and Mixamo as a frozen unmaintained asset source with a redistribution clause that a trivially-extractable `.pck` sits uncomfortably against.

**One writer per node.** `player.gd:95` and `player.gd:197` both write `_cam.rotation.x` — that is the whole recoil bug. The fix is a dedicated `RecoilPivot` between `Head` and `Camera3D`, not smarter maths. Godot composes parent/child transforms multiplicatively every frame, so "additive" is free and no blending machinery is needed. Same rule for the viewmodel: procedural sway/bob/ADS on a parent, `AnimationPlayer` keying a child.

**`SpriteBase3D` billboard modes destroy the model's rotation entirely** — the generated shader overwrites `MODELVIEW_MATRIX` with a camera-derived basis plus `MODEL_MATRIX[3]` (translation only). A local Z rotation is not ignored, it is *unrepresentable*. The "tilt the sprite to clamber through a window" trick **cannot work** with `StandardMaterial3D`; it becomes a ~6-line `ShaderMaterial` rebuilding the same basis and post-multiplying a roll. Entities do not need to become meshes.

**Rename the trademarks and add a LICENSE before any art or audio lands.** The repo has **no LICENSE file**, which means all rights reserved — GitHub's ToS grants viewers only "view and fork". Separately, the perk *jingles* are the highest-risk item and "I re-synthesised it myself" does not help: a jingle is a copyrighted musical *composition*, and 17 U.S.C. § 101 defines "phonorecords" to exclude sounds accompanying an audiovisual work — **so the § 115 compulsory mechanical licence does not reach a video game at all.** There is no compulsory path; sync licences are voluntary. Write original motifs. Real firearm *names* are the lowest-risk item on the list (settled practice since EA's 2013 announcement; Activision won *AM General* in 2020 on exactly this ground) — keep AK-74u, MP40, RPK. Rename four perks, Pack-a-Punch, Mystery Box and the twelve PaP names: under 100 lines, free, and it removes the largest category of exposure in one commit. Activision demonstrably enforces on Zombies-themed fan content (2023 Fortnite Creative DMCAs). **Do it now, because every jingle, announcer line, chalk plaque and HUD badge authored afterwards bakes the name in deeper.**

---

## 2. The constraint envelope

**This is the reference table every later decision cites.** Confidence column: **SOURCED** = Tier 1 engine source, official docs, or shipped game script · **MEASURED** = measured against this build · **ESTIMATE** = a starting budget that must be replaced by a measurement.

### 2.1 Hard caps

| Constraint | Value | Confidence | Source / note |
|---|---|---|---|
| **Concurrent 3D audio voices** | **12-16** | ESTIMATE | Cost is ~344 main-thread `postMessage`/s **per voice** at 44.1 kHz (one `AudioWorkletNode` per live voice, posting every 128-sample quantum). 24 voices ≈ 8,300 msg/s on the thread running the game and renderer. Find the N where p99 diverges from median and set the cap below it (§5, M-AUDIO). |
| `max_distance` on every `AudioStreamPlayer3D` | **mandatory**; 20 m groans, tighter for footsteps | SOURCED | Defaults to `0.0` = never culled. Documented CPU lever. `visible = false` does **not** stop audio. |
| `max_polyphony` | set deliberately (default is **1**) | SOURCED | Oldest-wins stealing is correct for a horde |
| Audio effects / reverb / Doppler / attenuation low-pass | **0 — none execute** | SOURCED | §1.2 |
| Audio sample rate | 22,050 Hz today; do not raise until bake time is measured | SOURCED | Halving rate halves bytes *and* `AudioBuffer` RAM. Docs: 22-32 kHz is fine for lower-pitched sources. |
| Audio format, if samples are ever added | **WAV/QOA for short SFX; MP3 (not Ogg) for anything long** | SOURCED | Godot 4.7 docs: Ogg "requires significantly more processing power"; MP3 "recommended for mobile and web projects where CPU resources are limited". **This inverts the gap analysis's "mono Ogg Vorbis" premise.** |
| **Shadow-casting lights** | **1** (the player torch `SpotLight3D`) | SOURCED | Each extra shadowed light = one full additive re-draw of every instance it touches. Omni CubeMap = 6 shadow renders; Dual Paraboloid `ERR_FAIL`s. |
| Non-shadowed lights **per geometry instance** | **8 omni + 8 spot** (`max_lights_per_object`) | SOURCED | Silent drop via max-heap, **no warning**. Gated on AABB *intersection* first, then `distance / (range × energy)`. Currently 8 omni against a cap of 8 → **zero headroom**. |
| Total positional lights considered per frame | 32 (`max_renderable_lights`, per type) | SOURCED | Comfortable |
| Max renderable elements | 65536 | SOURCED | Not a constraint here |
| Max directional lights | 8 | SOURCED | Project uses none |
| `ReflectionProbe` | 2 per mesh | SOURCED | Unused |
| **Ragdolls (`PhysicalBone3D`)** | **0** | SOURCED | No rigged meshes; ruled out upstream of performance. Upgrade path is a **single-capsule fake ragdoll** (1 `RigidBody3D` per corpse, despawned on a timer), not skeletal. |
| **Concurrent alive zombies** | **24** (`zombie_max_ai`, canon) | SOURCED | 8 on dog rounds (gap analysis T1.1) |
| 24 mutually-colliding `CharacterBody3D` | **unknown** — GodotPhysics3D degrades at 10-40 (4.0/4.1-era, order of magnitude only); Jolt ~800 but with a *worse* per-call `move_and_slide` constant | ESTIMATE | 24 sits uncomfortably inside that band. **Measure both backends** (§5, M-PHYS). |
| **Particles: simulation** | GPU via transform feedback — **works** | SOURCED | Not a CPU fallback |
| Particle `draw_order` | **`INDEX` or `LIFETIME` only. Never `VIEW_DEPTH`.** | SOURCED (rule) / Tier 3 (the stall) | godot#107633 reports a WebGL readback stall, but it is 4.3/4.4-era, unconfirmed on 4.7, contains **no frame-time measurement**, and its reporter is the same person as the DecalCompatibility plugin author cited elsewhere. **The rule holds because sort order is irrelevant for additive FX and costs nothing to avoid — not because a stall is proven.** |
| Emitter pool budget | 8 impact + 4 blood + 1 muzzle `GPUParticles3D` nodes; `amount` 6-10 per burst | ESTIMATE | Each node is its own draw call and process shader. Pool and `restart()`; never instance per hit. |
| `GPUParticles3D.emit_particle()` | **does nothing** | SOURCED | Forces the pooled-emitter-and-reposition architecture |
| **Decal-shaped things** | 2 `MultiMeshInstance3D` ring buffers: bullet holes **48**, blood splats **32**; tracers **8**, casings **16** | ESTIMATE | One draw call each. Offset `+normal * 0.008`, alpha-scissor (keeps them in the opaque queue, self-sorting, no popping), random roll, **guarded `look_at` up-vector** (`Vector3.RIGHT` if `abs(normal.dot(UP)) > 0.99`, else `UP`). |
| MultiMesh per-instance custom data precision | **16-bit half float** | SOURCED | Fine for 0-1 factors; **not** for large integers or precise world coordinates |
| Per-instance shader uniforms on web | **≤ ~20 instances before the surplus renders black** | Tier 2 (open bug, 4 confirmations) | Budget is **global across unrelated materials**; **invisible nodes still count**. Use `modulate` instead. |
| **Payload — today** | **10.58 MB** first load (wasm 10,246,865 B gzip; pck 261,528 B) | MEASURED (2026-07-27) | GitHub Pages gzips `.wasm`; **Brotli is not served** even when advertised |
| **Payload — target** | ≤5 MB initial / ≤8 MB total | SOURCED (Poki) | Currently over both before a byte of content is added |
| Content headroom | effectively unlimited | MEASURED | Engine is **97.5%** of the wire payload; all art+scripts = 261 KB gzipped; audio = 0 bytes |
| Enemy sprite VRAM, 5-column 8-direction atlas | **≈3.8 MB** (2.76 MB zombies + crawler + hound) | Computed | ≈300 KB of PNG. **Memory was never the constraint; authoring is.** |
| Frame budget | **16.6 ms** at 24 zombies with all FX live, on an **integrated-GPU** machine; p99 < 25 ms | ESTIMATE | Cut order if missed: shell casings → tracers → blood decals → shadow resolution → particle `amount` → torch shadows |
| Flow-field solve | accept if **p99 < 2.0 ms**; time-slice or move to 4-pass fast sweeping if > 4 ms | ESTIMATE | 1428 cells; fires only on player tile change (~4/s at sprint) |

### 2.2 Renderer feature matrix (`gl_compatibility` / WebGL2 / Godot 4.7)

| Feature | Status | Note |
|---|---|---|
| `GPUParticles3D` (base) | ✔️ | Transform feedback. Real GPU simulation. |
| Particle trails / sub-emitters / `emit_particle()` / vector attractors / SDF collision | ❌ | Warning printed, no effect. Sphere/box/heightfield attractors and colliders **do** work. |
| `CPUParticles3D` | ✔️ | Simulates in C++ on the main thread + re-uploads a MultiMesh buffer each frame. Use only where you need `emit_particle`-style one-shots or trails. |
| Omni/spot **shadow maps** | ✔️ multi-pass | See the 1-light cap above. Omni **must** use CubeMap mode. |
| **SSAO** | ✔️ **since 4.6** | *S4AO*, fused into the post/tonemap triangle. Only `ssao_intensity` (×2.0) and `ssao_radius` (×0.5) are live. ⚠️ Applied as `color.rgb *= s4ao(UV)` on the **fully composited, post-glow** image — it darkens emissives, muzzle flashes, glow and transparents. Dial glow in first, then SSAO, then re-check your bloom. |
| **Glow / bloom** | ✔️ | Fixed 4-level chain, 8 passes at ≤half res. `glow_levels/*` and `glow_blend_mode` **ignored** (screen blend hard-coded). RGBA8 LDR → keep `glow_hdr_bleed_threshold` near 0.9-1.0 or nothing blooms. |
| **`Environment` adjustments (BCS)** | ✔️ | Already in use |
| **Colour-correction LUT (3D or 1D)** | ✔️ | **The highest visual-return-per-hour tool available to this project.** One texture fetch in a pass that already runs. |
| Depth + height fog | ✔️ | Analytic per-fragment, effectively free. This is the whole atmosphere budget. |
| MSAA **3D** | ✔️ | The only AA. Cost on integrated GPUs at 1080p is untested. |
| MSAA 2D / FXAA / SMAA / TAA / FSR2 / debanding | ❌ | SSAA via render-scale >1 works but is expensive |
| `SCREEN_TEXTURE` / `DEPTH_TEXTURE` in spatial shaders | ✔️ | One backbuffer blit before the transparent pass. **No mipmaps** — `filter_linear_mipmap` gives you level 0. Using it drags the material into the transparent queue and forces a full-screen copy each active frame. |
| Normal/roughness buffer | ❌ | |
| Custom post-processing via fullscreen quad (`CanvasLayer` + `ColorRect`) | ✔️ | The right tool for whole-screen effects |
| `CompositorEffect` | ❌ | |
| `MultiMeshInstance3D`, one draw call, per-instance colour + custom data | ✔️ | `glVertexAttribDivisor` → one `glDrawElementsInstanced` |
| `INSTANCE_CUSTOM` on plain `MeshInstance3D` | ❌ (always zero) | |
| `Decal` | ❌ | 4.8 at the earliest |
| Volumetric fog / `FogVolume` | ❌ | |
| SSR / SSIL / SDFGI / `VoxelGI` | ❌ | |
| `LightmapGI` | ⚠️ renders, but baking needs RenderingDevice | Impractical given runtime map generation |
| DoF / SSS / light projectors / PCSS | ❌ | |
| `OccluderInstance3D` | ✔️ builds for wasm32, but runs **inline on your one thread** | Room-graph visibility from `MapData` is better information at lower cost |
| Colour buffer | **RGBA8, LDR** | No HDR viewport, no HDR output |
| Depth buffer | 24-bit, no reverse-Z precision benefit | Z-fighting risk for offset quads — hence `+normal * 0.008` |
| **Reverse Z** | **active** (`GL_GREATER` in the GLES3 backend) | The widely-copied viewmodel depth shader (`POSITION.z = mix(POSITION.z, 0, 0.999)`) pushes the gun **behind** the world on 4.3+. Avoided entirely by §4.1. |
| Shader cache / program binary | ❌ **none on web** | Full recompile from GLSL on every page load |
| Depth prepass | available | `rendering/driver/depth_prepass/enable` |

### 2.3 Platform (web / GitHub Pages)

| Constraint | Status |
|---|---|
| Renderer | `gl_compatibility`, single-value enum, **not overridable** |
| Threads | Off. Achievable via the PWA COOP/COEP service-worker shim at the cost of one extra first-load navigation and no third-party subresources. **Untested on GitHub Pages specifically.** |
| Audio playback mode | Sample (no effects). `Stream` reintroduces the frame-rate-coupled garbling that Sample mode was created to fix. |
| Persistence | IDBFS/IndexedDB. Requires `FileAccess.close()`; syncs next frame; **a backgrounded tab never syncs**. Fails outright in incognito and third-party-cookie-blocked iframes. Prefer `localStorage` via `JavaScriptBridge`. |
| Pointer lock | Escape can never re-lock. No mobile support at all. `MOUSE_MODE_CONFINED` `ERR_FAIL`s. |
| Compression | gzip only. Brotli requires a different host (Cloudflare/GitLab/Vercel Pages → 10.58 MB becomes ~7.2 MB for zero code change). |
| Cache | `Cache-Control: max-age=600`. PWA service worker fixes this. |
| Loading progress bar | **Works** — the loader seeds totals from export-baked file sizes, not `Content-Length`. The docs' `total == 0` caveat does not bite. |
| Gamepad | Works for Xbox/PS on Chromium; unreliable in general (the Gamepad API withholds vendor ID, so SDL mappings cannot apply). Never put anything essential behind a trigger axis. |
| Mobile | Not a target. The blocker is the 39.5 MB wasm compiled on the main thread on phone silicon plus no pointer lock — **not** texture formats. |
| Background tabs | `_process`/`_physics_process` stop entirely |

---

## 3. Restore before you build

`kriegsnacht.html` sits in the repo root with a working, **play-tested and tuned** implementation of roughly forty things the port deleted. These are transliterations of ten to thirty lines of JavaScript with the constants already dialled in. `ancestor-diff.md` §2 carries the recipe for every one. **Doing these first is free progress and it makes every later feel-tuning task start from a known-good baseline instead of from zero.**

Ranked by value ÷ cost. All are **S** (≤1 day), several are under an hour.

| Rank | Item | Recipe | Why first |
|---|---|---|---|
| 1 | **VS-4 — killing-blow audio order** | Move `Sfx.play("hit"/"headshot")` above the `hp <= 0` early-return at `zombie.gd:203-207` | **One line.** Today the *killing* shot is the only event with no impact sound. |
| 2 | **A1 — wall-face directional shading** | `lit = (lit*186)>>8` on ±Z faces only = **×0.7266**; multiply the vertex-colour `shade` in `_emit_wall_faces`. Composes cleanly with the per-tile jitter the port already has. | Three lines. Under `gl_compatibility` with no shadows this is the cheapest restoration of depth read in the entire project — it is why every corner in the port meets at identical luminance. |
| 3 | **A9 — recoil spring + view bob + shake** | `viewKickV += -viewKick*46*dt - viewKickV*11*dt; viewKick += viewKickV*dt`. Bob phase at 9.4 / 13 / 2.2 rad/s; **X and Y use different functions** (`sin` vs `abs(cos)`) — that is what makes it read as a figure-eight. Shake decays 2.2/s; applied on X as a *camera-plane perturbation*, not a translation, so it reads as roll. | **Fixes a live aim bug**: `player.gd:197` adds `def.kick*0.0035` into `_cam.rotation.x` with nothing to pull it back, so a 100-round RPK mag walks the camera up ~30° permanently. Land it on the new `RecoilPivot` (§1.5). The ancestor's properly-integrated damped oscillator is a **better** feel than the two-lerp model four Godot repos converge on, and it is already tuned. |
| 4 | **A5 — per-zombie attack timer** | `atkT: rnd(0.6)` at spawn; cadence 1.05 s normal / 0.85 s hound / 1.1 s downed | The port's single global 0.35 s cooldown caps the entire horde at one zombie's DPS. This is half of "make the game losable" and it is ~10 lines. Combine with canon's 0.4 s per-attacker ignore timer (§1.3). |
| 5 | **A2 — hitmarker on every damage event** | 26×26 px rotated 45°, four 2×8 bars, `#EDE7D6`, `scale(.55)→1` over 0.22 s ease-out, cleared and reflowed per hit; blood-red `#C4222A` on kill; auto-clear 230 ms | Fires on **non-kill hits too** — that is the whole point. Firing a weapon currently produces zero pixels of change. |
| 6 | **A3 — hit flinch** | `hitT = 0.09`; tint toward `(255,235,220)` at `alpha = min(210, hitT*640)` → starts ~58/255 and falls to zero over 90 ms. Insta-Kill adds a permanent +40 toward `(255,90,70)` on every live zombie — which is how you *see* the power-up is active. | Pure `modulate`, free per-node channel (§1.1) |
| 7 | **A6/A7 — interaction states** | `interactInfo()` returns `{label, cost, ok, none, free, sub, hold}`; unavailable entries are `continue`d **in the scan** (2675-2691), not blanked in the prompt; `deny()` + 260 ms red flash on refusal | A7 fixes a real bug: dead objects currently win nearest-pick and silently eat the F key. |
| 8 | **A11 — zombie idle groans** | `groanT: rnd(6,1)`, re-rolled `rnd(9,3.5)`, culled at 20 m, `pitch = pal/2` so the three palettes are three voices. Saw `58+pitch*36` Hz → ×0.62 over 0.85 s + bandpass `300+pitch*260` Q 2.4. Hound bark: saw 220→110 Hz over 0.16 s + bandpass 900 Q 1.2. | Requires positional audio first. **The primary threat-awareness channel** — and per M2 F24, the *correct* answer to "how do I know something is behind me", which 8-direction sprites do not solve. |
| 9 | **B9 — distance-weighted spawn window** | `wt = (1/(1 + d*0.14)) * rnd(1.6, 0.4)`, best-of over all live windows. `flow.dist[...]` already holds the exact BFS distance. | ~6 lines. The port's uniform pick makes late-round pressure **fall** as you open the map — exactly backwards. |
| 10 | **A8 — downed HUD** | `"YOU ARE DOWN / bleeding out — N"`, camera drops 17% of screen height, speed 1.15 m/s, spread ×1.4 | `downed_changed` is emitted three times and **connected nowhere**. |
| 11 | **A10 — render-quality selector + automatic governor** | `QUAL = [320,480,700]`, 400,000-pixel hard cap, and the governor: `if(frames/fpsT < 38 && quality > 0){ quality--; resize(); }` on a 1.4 s window. Godot: `get_viewport().scaling_3d_scale` at 0.5/0.75/1.0, `SCALING_3D_MODE_BILINEAR`. | Given single-threaded WebGL2 on unknown consumer hardware with no telemetry, **this is the only mechanism in the ancestor that made the build survive a bad machine.** ⚠️ Drive it with `scaling_3d_scale` **only** — never by toggling glow/SSAO/LUT, each of which is an uncached mid-frame shader compile (§1.1). |
| 12 | **A17 — damage wash masked by the inverse vignette** | `k = (dmg*(255-v))>>8` — strongest exactly where the vignette is darkest (the corners), vanishing at the crosshair. `dmgFlash += 120` per hit, capped 255, decaying 260/s. | T1.4 proposes to *design* this. It already has an exact recipe. |
| 13 | **A16 — low-HP pulse** | `opacity = hp/maxHp < 0.34 ? (0.4 + sin(t*7)*0.22) : 0`, `inset 0 0 140px 40px rgba(140,8,10,.8)` | Edge-only ~1.1 Hz pulse |
| 14 | **A13/A14/A15 — HUD readouts** | Points: thousands separator, `scale(1.13)` for 110 ms, red on spend, floating `+N`/`-N` for 700 ms. Ammo: `--` while reloading, `.low` at ≤25%, `.empty` blink `0.55s steps(2)`, `✦` PaP suffix, `[Q]` alt-weapon line. Tally: `min(round,10)` bars, `skewX(-14deg)`, 10th turns sodium past round 10. | Cheap legibility across three separate readouts |
| 15 | **A4 — hold-F barricade rebuild** | 0.34 s/board, +10 points, 6 boards → 2.04 s / 60 points. Tap-F is explicitly excluded for windows — **hold is the only verb.** Windows are the one interactable exempt from the facing test. | `PTS_REBUILD` is declared and referenced nowhere; the `board` sound is baked in `sfx.gd:99` and played by nothing. Restores the round 1-3 economy. |
| 16 | **A12 — round title card** | Numeral at `clamp(72px,14vw,190px)`, per-round subtitle (`'the hounds are loose'` / `'the dead are coming'`), snapped to opacity 1 then faded over 2.1 s ease-out | Fires with the sting and the tension bump |
| 17 | **A19 — spread while moving/downed** | `spread * (moving ? 1.5 : 1) * (downed ? 1.4 : 1)`, `moving = hypot(vx,vy) > 0.6` | Two lines. ⚠️ Fix the distribution at the same time — `player.gd:214-217` applies two independent axis rotations, which is a **square** ~1.41× wider on the diagonals, not a cone. Use `a = randf()*TAU; r = sqrt(randf())*spread_rad`. |
| 18 | **A21 — night-sky ceiling curve** | `skyLUT[i] = min(150, (0.26 + 0.34/(1+d²*0.2))*256)`, +9 blue. Godot: `SHADING_MODE_UNSHADED` on the `night` ceiling material. | The Alley currently reads as an indoor room because the torch lights the sky |
| 19 | **A24 — wall-buy refuses at full reserve** | `{ok:false, none:true}`, `"Olympia — ammo full"` | The port charges you and refills **every** gun (see T1.5) |
| 20 | **A20/A22/A23/A18** | Metal walls +26 lit on power; perk blurbs in the prompt (`PERKDEF.blurb` exists, never read); round ≥14 regular-zombie ×1.06; toast colour classes | Minutes each |

**Do not restore these** — `ancestor-diff.md` §6 flags them as ancestor bugs or dead code, and a faithful transliteration would import them:

- **`G.decals` never existed.** It is declared, cleared, and nothing ever pushes to it. The backlog lists "bullet-hole decal array | 1638 | deleted" as a restoration. **It was never implemented** — bullet holes are new design, not a restoration.
- `G.hitFlash` / `G.hitKill` / `G.killFeedT` — declared, never read or written.
- `reduceMotion` — the `matchMedia` result is captured into a `const` and never used. Only the CSS half works. "Restore the ancestor's reduced-motion handling" means restoring a CSS rule and writing the logic from scratch.
- The nuke dead branch, the `dropTick` reset omission (which the port faithfully inherited), and the Thundergun accuracy double-count that lets end-of-run accuracy exceed 100%.

**And do not regress what the port did better** (§5 of `ancestor-diff.md`): real `intersect_ray` hit registration against real capsules (the ancestor had *no height test at all* — you could kill a crawler while aiming at the ceiling); the world-space headshot height test; correct cumulative-weight box rolling; `move_and_slide` collision; `Input.set_mouse_mode` replacing ~75 lines of capture fallback; and keeping the flow field.

---

## 4. Recommended technical approach, per mechanic

### 4.1 Viewmodel — **geometric no-clip + a vertex-only FOV override, on a procedurally extruded `GUNART` mesh**

**Recommendation.** The player capsule has `RADIUS = 0.24`, so world geometry can never come within 0.24 m of the camera origin. **If the entire viewmodel mesh fits inside a sphere of radius ~0.22 m at the camera, wall clipping is geometrically impossible** — not mitigated, not depth-tricked, impossible. Make that small object read as a full-size gun by writing **only** the two scale terms of the projection matrix in `vertex()`:

```glsl
float onetanfov = 1.0 / tan(0.5 * radians(viewmodel_fov));
PROJECTION_MATRIX[0][0] = onetanfov / (VIEWPORT_SIZE.x / VIEWPORT_SIZE.y);
PROJECTION_MATRIX[1][1] = onetanfov;   // sign UNVERIFIED on gl_compatibility — see §5
```

No `POSITION` write, no `DEPTH` write, depth terms untouched. Zero extra passes, zero extra render targets, zero extra fill, and complete immunity to the reverse-Z breakage that has invalidated every widely-copied viewmodel shader.

Build the mesh by extruding `GUNART` (`kriegsnacht.html:1150`): every entry is `['r', x, y, w, h, colour]` — an axis-aligned rect in a 100×60 space — plus a few circles, one rotated rect and one polygon. Each rect becomes a box; ~72 triangles per weapon; **one ~150-line builder covers all 12 guns plus the knife plus the Pack-a-Punch tint.** The `MUZZLE` table (`:2020`) gives per-weapon muzzle coordinates in the same space, so the `Marker3D` attachment point is free. Use `SurfaceTool` with `vertex_color_use_as_albedo`, exactly as `world_builder.gd` already does — which means the weapon is stylistically identical to the level *by construction*.

**Rejected:**
- **SubViewport + mirrored camera** (four independent repos do it, and it is the standard answer). Rejected on cost: a second colour+depth target, clear and composite blit — all full-screen and unconditional regardless of how few pixels the gun covers — plus a **second shader compile of every viewmodel material on the main thread at whatever moment the player first draws that weapon**, which is precisely the failure mode this platform punishes. Godot allows only one active camera per viewport (`cull_mask` does not help), so this is the only "second camera" option, and it costs too much.
- **The depth-hack clip shader** (`POSITION.z = mix(...)`). The Godot 3.x original and its 4.x syntax-port both push the gun *behind* the world on 4.3+, because reverse Z made 0 the far plane. Only the newest forks fix it. And the fragment-stage variant (`DEPTH = ...`) disables early-Z, which is a real cost on the tile-based/mobile-class GPUs a browser build lands on.
- **`no_depth_test = true` + `render_priority`** (T2.2's stated plan). Forces the surface into the transparent queue, drawing over every billboard and wall unconditionally (§1.1).
- **12 CC0 weapon models.** Kenney's kits are the only stylistically-consistent permissive source and they are **sci-fi blasters**; you need an M1911, an MP40, an M14, an AK-74u, a China Lake. Assembling 12 era-correct weapons at CC0 from mixed authors yields 12 polycounts, texel densities and art styles, and anything photoreal fights the nearest-neighbour billboard aesthetic head-on. This is the *worst* option, not merely weaker.
- **A 2D sprite viewmodel** (what the ancestor did) is a legitimate **fallback** if the FOV override misbehaves, and a 2-hour stopgap to close "no viewmodel at all" immediately. But it caps you permanently: ADS becomes a fake zoom, recoil cannot rotate in depth, and the muzzle flash is a screen-space blob rather than a world-space light.

**Structure:** `Player → Head (pitch, mouse only) → RecoilPivot (script only) → Camera3D → ViewmodelRoot (sway/bob/ADS, script only) → WeaponMesh (AnimationPlayer keys this only) → MuzzlePoint`. **Exactly one writer per node.** Use `move_toward` (not `lerp`) for every return-to-rest, because `lerp` is asymptotic and produces the weapon that never quite re-centres. Split the reciprocating part into its own child so the slide cycles on fire — driven by a plain float, **not a `Tween`**, because 880 RPM would allocate ~15 tweens a second.

**Shotgun reload:** `AnimationPlayer` + `animation_finished`, with cancel **latched and honoured at the next shell boundary** so you always get the pump and never interrupt mid-shell. Not `AnimationTree` — self-transitions in `AnimationNodeStateMachine` could not be confirmed for 4.7, and this needs no unverified engine feature.

### 4.2 Enemy animation and gore — **billboards, 5 drawn columns mirrored to 8, gore via sprite tricks**

**Recommendation.** Stay on billboards (§1.5). For directional facing, use **DOOM's own convention: rotations 2↔8, 3↔7, 4↔6 are horizontal mirrors**, so 8 directions need only **5 unique drawings** — front, front-¾, side, back-¾, back. `AnimatedSprite3D` exposes `flip_h`, so mirroring is free. At 3 palettes × 5 columns × 15 frames of 48×64 that is a single 720×960 texture, ≈2.8 MB VRAM, ≈300 KB of PNG. (An automated summary of the DOOM wiki will tell you 4 unique rotations suffice. It is wrong: rot 1 and rot 5 are self-facing and cannot be mirrored. **1 + 3 + 1 = 5.**)

**The critical framing:** `sprite_lib.gd`'s own docstring records that the PNGs "were generated by replaying the browser build's own canvas drawing code". So the deliverable is **five view-specific draw routines in the generator, not 225 hand-drawn cells.** Memory was never the constraint; authoring is, and the generator collapses it.

**Gore, ranked by value per line:**
1. **Walker→crawler on legs destroyed** — `SpriteLib.frames_for("crawler", pal)`, `pixel_size` 0.62/34, re-seat Y, shrink the capsule, drop the speed, adjust the head threshold. **All three crawler palettes already exist.** ~20 lines, zero new art, and it buys the single most CoD-Zombies beat available.
2. **Hit flash + positional punch** on `modulate` (§3 item 6).
3. **Glowing eyes** — a child `Sprite3D` with `shaded = false`. The eye pixels are already authored (frame 0 carries a symmetric pale-cream pair at (20,14)/(26,14), the two brightest pixels in the sprite); they are dark only because `shaded = true`. For additive specifically, `SpriteBase3D` exposes no blend mode — use a small unshaded `QuadMesh` with `BLEND_MODE_ADD` + `BILLBOARD_ENABLED`.
4. **Limbless sprite variants** as a boolean passed into the generator's draw routine, swapped at runtime with a re-seek so the gait does not pop.
5. **Gib burst** — pooled emitters (§4.3).

**Rejected:**
- **Rigged/skinned meshes** (§1.5). Recorded for a future reader who reconsiders: dismemberment must be a `SkeletonModifier3D` (because `AnimationMixer` runs *before* `Skeleton3D` and will stomp `set_bone_pose_scale` called from `_process`); `set_bone_global_pose_override` is **deprecated in 4.7** so the popular 4.2 tutorial cannot be copied verbatim; ragdoll must be a pool of 2-3 with animated death clips as the default, started after `await get_tree().physics_frame`.
- **Mixamo.** Adobe's own wording is *"currently in a limited duration technology preview"* — a time-limited grant, not a perpetual dedication — and it forbids distributing *"the raw character and animation files"*, which a `.pck` served from a guessable URL and reconstructable by `gdsdecomp` sits uncomfortably against. **Quaternius ships a CC0 Animated Zombie Pack and a CC0 animation library**; CC0 removes the question for free and can never be withdrawn.
- **Third-party gib packs.** The established style is three specific palettes plus a `rgba(6,6,5,205)` 1 px rim stamped by a specific alpha-threshold algorithm. No third-party pack carries that rim or those hues, and recolouring someone else's gibs is more work than a `makeGib()` in the generator.
- **8-direction sprites as a fix for situational awareness.** They answer "which way is that one looking", not "what is behind me". The enemy behind you is not on screen. **Spend that budget on positional audio.** Sell the directional atlas to yourself on *aggro legibility*, which is real but secondary.

**The escape hatch, if richer motion is ever wanted:** rig a CC0 humanoid, batch-render 8 directions × N frames through a Blender directional sprite renderer, quantise to the existing three palettes at 48×64, and stamp the same 1 px rim. You get a full locomotion library **and** the pixel-art identity **and** zero runtime skinning, zero new materials, zero ragdoll physics. This is the third option the gap analysis did not consider and it dominates both named branches.

### 4.3 Combat FX — **pooled `GPUParticles3D` emitters + two MultiMesh ring buffers + zero screen-read shaders**

**Recommendation.**

- **Particles: `GPUParticles3D`, pooled, `draw_order = INDEX`.** The CPU is the scarce resource on a single wasm thread; GPU particles' per-frame CPU cost is ~zero. But because `emit_particle()` does nothing (§1.1), the architecture is forced: **pre-place a fixed pool of emitters (8 impact, 4 blood, 1 muzzle), reposition and `restart()`.** Never instantiate a node per hit — one surveyed reference instantiates a muzzle flash per shot and never frees it, which is a leak at 880 RPM.
- **Bullet holes and blood splats: two `MultiMeshInstance3D` ring buffers** (48 and 32), unshaded, `render_priority = 1`, `cast_shadow = OFF`, `+normal * 0.008`, random roll, **guarded `look_at` up-vector**, alpha-scissor so they stay in the opaque queue and self-sort by depth. One draw call each instead of 80. Move the write cursor; never allocate.
- **Muzzle flash:** one persistent `OmniLight3D` (`omni_range` 1.5-3 m, `shadow_enabled = false`) plus one billboarded quad, both toggled by **one persistent `Timer`** at ~0.05 s. Never `await get_tree().create_timer()` per shot — each call allocates a `SceneTreeTimer` and a coroutine frame. Per-weapon colour and anchor from the ancestor's tables (Ray Gun `160,255,90`, Thundergun `150,235,255`, else `255,214,130`; radius ×2.2 for the Thundergun). **Confirmed safe:** `OMNI_LIGHT_COUNT` is a *uniform*, not a shader define, so toggling a non-shadowed muzzle light cannot trigger a recompile. Keep it shadowless and it stays free. Give it a small range so its AABB touches as few instances as possible — every instance it touches spends one of that instance's 8 slots.
- **Surface lookup: quantise `ray.get_collision_point()` to the tile grid and read `MapData`.** Exact, free, zero per-node storage, and available only because the world is a grid. Fall back to `collider.get_meta("surface_type", &"concrete")` for doors/windows/props, and a type check for flesh.
- **Screen effects: no shaders at all.** Damage-direction chevron = a rotated `TextureRect`. Blood vignette = a `GradientTexture2D` modulate. Downed grayscale = tween `Environment.adjustment_saturation → 0` (already enabled, part of a pass that already runs). Nuke whiteout = a `ColorRect` alpha tween. Hit marker = four ticks. **Every `hint_screen_texture` you avoid is a full-screen back-buffer copy you do not pay for.**
- **Rim lighting on zombies: an alpha-edge outline in the sprite shader**, four neighbour taps on the alpha channel, `EMISSION += rim_color * edge * rim_energy`, with glow on. Fresnel cannot work on a billboard (§1.1). Note the baked rim is **dark**, which reads against a *light* background — correct for a flat-lit raycaster, invisible in a genuinely dark level. The shader route is reversible and needs no re-export.
- **Tracers on ~1 in 4 shots**, MultiMesh, 8 slots, 2-frame life, unshaded emissive. Not `GPUParticles3D` trails (unsupported) and not a moving projectile node for a hitscan weapon.
- **Shell casings last, and physics-free** — ballistic integration in GDScript into a 16-slot MultiMesh, no collision, despawn at 1.2 s. Cut entirely if the budget is tight.

**Rejected:** `Decal` (unsupported); the depth-projected decal shader (correct but overkill for a grid-aligned level, and it `discard`s, defeating early-Z); `CPUParticles3D` as the default (it simulates every particle in C++ on your one thread and re-uploads a MultiMesh buffer each frame — use it only where you need `emit_particle`-style one-shots); the SubViewport splat-accumulation buffer (godot#86940); the third-party decal plugin (no licence).

**Lighting mood, concretely.** The principle is that **contrast comes from what is *unlit*, not from how bright the lights are.** Dropping `ambient_light_energy` from 0.30 to ~0.10 will do more for the mood than any effect in this document and costs nothing. Also drop `fog_density` 0.055 → ~0.030 (fog at 0.055 with low ambient greys out the darks), room-lamp energy 1.5 → 0.8, `spot_angle` 42° → 34°, `adjustment_contrast` 1.08 → 1.20. **Do this before building any effect, because every effect is judged against how dark the scene is.** Then dial glow, *then* SSAO (it multiplies the composited post-glow image and will eat your bloom), then the LUT.

**One free win the gap analysis missed:** `world_builder._quad()` already writes a per-face `shade` into vertex colours with `vertex_color_use_as_albedo`. **That is already a baked lighting channel.** Upgrade it from per-face constant to per-*vertex*: at generation time compute a cheap AO term from neighbouring solid tiles plus a `1/d²` sum from each room lamp. Runtime cost: **zero** — it is already in the vertex stream. Load cost: single-digit milliseconds. This gives the LightmapGI look without the LightmapGI pipeline, and it composes with the one real shadowed torch on top.

### 4.4 Audio — **Sample-mode-native, 12-16 3D voices, zero effects, synthesis retained**

**Recommendation.** Design for Sample playback from day one (§1.2). Concretely:

- `AudioStreamPlayer3D` with **`max_distance` set on every single one** — 20 m for groans, tighter for footsteps. This is the documented CPU lever and it removes voices from the Web Audio graph entirely.
- A **pooled ring of 12-16 3D players**, stealing the oldest. Set `max_polyphony` deliberately.
- **`AudioStreamPolyphonic` on one `AudioStreamPlayer` for non-positional one-shots** — it is the engine's built-in voice pool. Check `play_stream() != INVALID_ID`; it drops silently.
- **`AudioStreamRandomizer`** with N=5 baked variants for repeatable ids, `PLAYBACK_RANDOM_NO_REPEATS`. Today `sfx.gd` uses a fixed seed and caches one buffer per id forever, so the `hit` sound is literally the same 1985 samples every time, every run — and the `pitch` argument on `play()` is never passed by any of the 24 call sites.
- **Buses as volume groups only**, wired to the settings sliders. No effects.
- **Scale gunshot gain by `body`** so the Thundergun (body 2.0) is genuinely louder than the M1911 (0.7). `sfx.gd:131` hard-codes −4.0 dB for everything.
- **Coalesce mass death into one scaled cue.** A Nuke currently fires up to 24 phase-coherent copies of the same 0.42 s buffer in one frame, summing ~21 dB hot instead of reading as a horde.
- **Keep the synthesiser.** It costs **0 bytes**, gives unbounded variants, and carries zero attribution burden. At this art style it is not a compromise — the sprites are 48×64 hand-drawn rectangles and ellipses; a photoreal AK-74u sample would be the odd one out. The two things synthesis genuinely cannot fake are a convolved room tail and mechanical foley (bolt, mag, charging handle). Buy **≤6 CC0 files** for exactly those (≈60 KB) and keep everything else parametric.
- **Announcer, if wanted:** Kokoro-82M (Apache-2.0 weights, curated corpus, no output restriction), rendered offline at build time. **Avoid Piper's popular `lessac` voices entirely** — the CSTR Blizzard 2013 corpus restricts use to "Research Purposes", explicitly excluding commercialisation and standalone use.

**Rejected:** every `AudioEffect`, reverb zones, Doppler, `AudioStreamSynchronized`, `Stream` playback globally (it reinstates the frame-rate-coupled garbling Sample mode was created to fix; a single music player is defensible, 24 zombie voices are not), a 108-file sample library (0.6-1.3 MB is affordable — the reason not to is CPU decode on one thread plus 108 rows of per-file licence bookkeeping), and **raising the sample rate to 44.1 kHz until the bake time is measured** (`sfx.gd` synthesises every sound in a GDScript per-sample loop at startup, on the only thread there is; no number for this exists anywhere).

**Unresolved and load-bearing:** whether the distance low-pass truly does not exist on web is a source-absence inference. Verify by ear before treating it as fact.

### 4.5 Pathfinding — **keep the BFS flow field; harden it; fix the force balance**

**Recommendation.** Keep it and do **not** migrate (§1.1). The published reference architecture — Emerson's *Crowd Pathfinding and Steering Using Flow Field Tiles* (Supreme Commander 2, Game AI Pro ch. 23) — specifies exactly what you already half-have, and names your LOS override and prop-stamping requirement as *features of the design*, not improvisations. Harden it in this order:

1. **`invalidate()`** — one line, called from the door-purchase path. `flow_field.gd:22-27` early-returns on an unchanged player tile and the door path never invalidates, so a player who buys a door and stands still leaves every zombie steering on a graph where that door is still a wall. Correctness precondition for everything below.
2. **Range-gate the LOS override to `dist < 9`** (the ancestor's value). Removes 24 full-length `intersect_ray` calls per tick and stops the whole horde converging on a point in the 16×14 Theatre. Emerson runs LOS as a *near-goal* integration pass, not a global override — its purpose is flow quality around the goal, not long-range steering.
3. **Clamp the separation vector.** **This is the real crowd bug, and it was not in the backlog.** `SEPARATION_FORCE = 2.4` multiplies a per-neighbour push that reaches magnitude 1.0 as separation → 0, summed over *all* neighbours, then added to a **unit-length** flow direction before normalising. With 4+ crowded neighbours the separation term is **5-10× the steering term**, so a dense pack becomes a repulsion gas that can move *away* from the player and into walls. `push = push.limit_length(0.6)` before the multiply, or drop `SEPARATION_FORCE` to ~0.8 and normalise per-neighbour by count.
4. **8-bit cost field + a wall-adjacency blur** (255 = wall, +2..+4 within one tile of a wall). This is the *published* fix for corner bunching, and it is what makes prop stamping meaningful — a crate can be cost 200 rather than 255, so zombies squeeze past but slowly. Switch the sweep from BFS to **4-pass fast sweeping** (Zhao 2005, O(N), no queue, pure `PackedFloat32Array` indexing — 4 sweeps over 1428 cells = 5712 updates, comparable to the current BFS and far cheaper than a GDScript heap).
5. **`stamp(rect, cost) → Stamp` / `unstamp(Stamp)`** with saved originals. This is the T3.4 prop API, and Emerson saves originals precisely so a failing stamp can be rolled back.
6. **Per-agent goal offset + speed jitter** — `target + Vector2.from_angle(randf()*TAU) * randf_range(0, 1.2)`, re-rolled every 3-5 s. **~10 lines, and 80% of the "horde not conga line" feel at 24 agents.**
7. **Direction blending across cell boundaries** — kills the visible snap when a zombie crosses a tile line.

**Local minima are impossible in this field** — a BFS/Dijkstra integration field is a monotone distance function over the connected component, so every non-goal cell has a strictly-smaller neighbour. "Flow fields have local minima" is a confusion imported from *potential-field* methods, which are a different technique.

**Rejected:** `NavigationRegion3D`/`NavigationAgent3D` (§1.1); **congestion maps** (Pentheny's technique is explicitly aimed at "tens or hundreds of thousands of agents", introduces a documented oscillation drawback, and at 24 agents item 6 gets most of the benefit for a tenth of the complexity); **a layered 2.5D flow field** for verticality — the answer there is a **single-layer grid plus an explicit list of vertical link edges** (~30 lines: the BFS neighbour loop gains `+ links[i]`), which covers every WaW-era Zombies staircase because none has a second walkable surface directly above another in plan. Full layered fields (shaped on Recast's `rcHeightfieldLayer`) are 3-5 days plus a debug visualiser you cannot work without, **and no game-side reference write-up exists** — you would be porting a robotics/navmesh-baker data structure into a gameplay pathfinder.

**Build the map validator** (~200 lines, ~1 day, highest value-per-line in R5). Six checks, run at map build in debug for **every door-open state** (4 doors → 16 states, ~0.5 ms each):
- **I1** corridor width: `agents_abreast(W) = floor((W - 0.52)/0.62) + 1` → 1 tile = **guaranteed conga line**, 2 tiles = 3 abreast, 3 tiles = 5. *No tile on any spawn→player route may have width 1.* Every current `DOORS` and `OPENINGS` entry is 2 tiles, so the shipped map passes.
- **I2** portal throughput ≈ `1.1 × W` zombies/s from the pedestrian fundamental diagram → **a 2-tile door passes ~2.2-2.4 zombies/s.** Cap total spawn cadence below the narrowest portal on the aggregate route, or rounds read as empty-then-wall.
- **I3** every purchasable region must contain a biconnected component of ≥36 floor tiles (a trainable loop) and every room ≥2 doorway tiles after prop stamping.
- **I4** dead-end pockets ≤ ~6 tiles.
- **I5** no diagonal-only connections (BFS is 4-connected; a diagonal-only gap is unreachable by the field but visible to the LOS override — agents walk into the corner forever).
- **I6** stamp monotonicity: no previously-reachable tile, window interior, wall-buy, perk or box spot may become unreachable.

---

## 5. Still unknown — must be measured

Consolidated from every brief's coverage gaps. **Nothing below licenses a design decision until it has a number.** The existing `scripts/perf_probe.gd` is the right harness for most of it — extend it rather than building anything new. Run everything in the **exported web build served over HTTP, in a focused browser tab** (the probe's own header correctly notes that automation tabs report `visibilityState=hidden`, which throttles rAF and makes JS-side FPS fiction), on **median hardware — an integrated-GPU laptop, not the RTX 5090** — in both Chrome and Firefox, three times, reporting the median of the medians.

**Tier 1 — blocks Milestone 1.**

| # | Question | Procedure | Decision rule |
|---|---|---|---|
| **M-0** | Which physics server, renderer and driver are actually running? | Add `ProjectSettings.get_setting("physics/3d/physics_engine", "<unset>")`, `RenderingServer.get_current_rendering_method()`, `get_current_rendering_driver_name()` to the probe's env block. **30 seconds.** | `<unset>` confirms GodotPhysics3D. Also fixes the mislabelled-renderer bug. |
| **M-BASE** | Does the current billboard build have any headroom? | Existing 0/6/12/18/24 ladder in the exported web build. Report **p99 and worst**, not mean. Raise `SETTLE` to 3-4 s for web or the first stage absorbs every shader compile and libels itself. | Every budget in §2 is provisional until this exists. Commit the number to the repo. |
| **M-PHYS** | Cost of 24 mutually-colliding `CharacterBody3D`, both backends | Add a `COLLISION_MODES := [false, true]` axis. **Force the doorway pile** — the current `_spawn()` scatters randomly, which will *understate* the cost by a wide margin. Record `PHYSICS_3D_COLLISION_PAIRS` against N: if it rises as N² rather than N, boid separation and the broadphase are fighting. Run the whole matrix under both `physics/3d/physics_engine` values. | Keep whichever wins. This is the one question no amount of reading resolves (§1.4d). |
| **M-AUDIO** | Voice count vs frame time | `VOICE_STAGES := [0,4,8,12,16,24,32]` looping groans, zombie count held at 24. Two passes: `max_distance = 0.0` and `= 20.0`. Record `mean_ms`, `p99_ms`, `AUDIO_OUTPUT_LATENCY`. | **Expect no clean cliff** — the cost is message pressure, so it shows as rising p99 and jitter well before audible dropout. Set the cap below the N where p99 diverges from median. The `max_distance` pass isolates whether distance culling is worth the code. |
| **M-SFXBAKE** | Boot cost of runtime audio synthesis | Wrap `Sfx._ready()`'s bake loop in `Time.get_ticks_usec()`, read from the browser console on the live URL. | **<150 ms** → keep pure synthesis, close the question. **150-500 ms** → bake lazily per sound, or move it behind the click-to-start gate. **>500 ms** → precompute WAVs at build time with a `--headless` script and pay bytes instead of stall. This single number decides the synthesis-vs-samples argument. |
| **M-ESC** | Does the first Escape keydown reach the page while pointer-locked? | Log `InputEventKey` for `KEY_ESCAPE` with `Input.mouse_mode`, on the **live URL**, in Chrome/Firefox/Safari, windowed and fullscreen. | Does **not** change the fix (§1.4a is correct either way) — but it changes whether the claim is "the pause key is dead" or the provable "the pause key is double-press and cannot resume". |
| **M-SAVE** | Does the save survive a hostile close? | (a) write then kill the tab same-frame; (b) write, switch tabs 5 s, close from the tab strip without returning; (c) both in incognito, logging `OS.is_userfs_persistent()`. Three runs each — one pass proves nothing about a race. | (b) predicts `user://` loses the write and `localStorage` keeps it. Confirms §1.4b. |

**Tier 2 — blocks Milestone 2.**

| # | Question | Procedure | Decision rule |
|---|---|---|---|
| **M-SHADOW** | Cost of the torch shadow | Ladder ×4: shadows off; on @512/1024/2048. **Draw calls should be flat across all four** (one shadowed light stays in the base pass). | Take the largest resolution within **1.0 ms** of shadows-off at 24 zombies. If even 512 costs >1.5 ms, the flashlight shadow is not affordable — fall back to the vertex-colour bake alone. If draw calls *jump*, something else picked up a shadow. |
| **M-SHADOW2** | Does a second shadowed light really double geometry cost? | Enable shadows on one room omni as well. Watch `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, not FPS. | If primitives rise sharply, the one-shadowed-light rule is confirmed on your hardware and you can stop thinking about it. |
| **M-WARM** | Does shader warm-up actually work? | This is a **stutter** measurement — averaging hides it. Report `_deltas.max()` and p99. Cold-load with cache disabled, then trigger first shot / first metal hit / first blood / first death / first shadowed light / first particle **in isolation**, with warm-up disabled and enabled. **The measurement is the difference.** | If spikes survive, the SubViewport is not actually drawing them — check `render_target_update_mode`, that the camera is `current`, that the effect is in frustum, and that you waited enough frames. Iterate until no in-game frame exceeds ~30 ms. **Re-run after every new material — permanently.** |
| **M-SSAO** | SSAO cost and visual regression on WebGL2 | Toggle `ssao_enabled` with a debug key, record `TIME_PROCESS` over 10 s at shipping resolution. **Do NOT sweep `half_size`/`blur_passes`/`fadeout_*`** — discarded, you would measure a flat line and draw the wrong conclusion. Also screenshot before/after a muzzle flash, a machine glow, and smoke in front of a corner. | Fixed budget (e.g. ≤2 ms). If AO is visibly eating emissives, lower `ssao_intensity` rather than disabling. |
| **M-VMFOV** | Does the vertex-only `PROJECTION_MATRIX` override behave on `gl_compatibility`, and what is the `[1][1]` sign? | Asymmetric, deliberately non-mirror-symmetric test mesh at ~0.15 m. Editor (Forward+ **and** Compatibility) and an exported web build over HTTP. Record: upside-down? mirrored? correctly scaled? | Correct → ship §4.1. Fixable by a sign flip → ship with a `uniform float y_sign`. Wrong any other way → drop the shader, tune mesh scale at the native FOV of 74. **Every community shader for this was written against Forward+ and they disagree about the sign.** |
| **M-VMCLIP** | Does the geometric no-clip guarantee hold? | Assert as a **unit test** that every mesh corner is within 0.22 m of the camera origin, so adding a long-barrelled weapon (RPK, China Lake) fails loudly. Then walk into every wall type, door frame and window board at every look angle. **Interior corners are the adversarial case** — the capsule lets the camera get closer to a convex corner than to a flat wall. | |
| **M-BILLBOARD** | Does `MAIN_CAM_INV_VIEW_MATRIX` compile under `gl_compatibility`? | Compile the tilt shader (§1.5). If not, substitute `INV_VIEW_MATRIX` (differs only during shadow passes). Then compare frame time, 24 tilt-shader sprites vs 24 `StandardMaterial3D` sprites. **Switch the editor to Compatibility first.** | Gates the vault/clamber trick |
| **M-SHADOWCAST** | Do alpha-scissor billboards actually cast shadows in 4.7 `gl_compatibility`? | Enable the torch shadow, look at a zombie on a floor. | Material logic says yes (`ALPHA_CUT_DISCARD` is the scissor path, which supports shadow casting). **The Sprite3D shadow issue history is long and every issue found is 3.x or unresolved.** A zombie's shadow thrown across a floor by a flashlight is, per unit of effort, the single most CoD-Zombies-looking thing available. **Test, do not assume.** |
| **M-MMCOLOR** | Does `set_instance_color` work on `gl_compatibility`? | 32 instances, distinct alphas, exported web build. | R1's engine-source read says colour and custom data *are* in the vertex stream as half floats, which largely resolves M3's open question — but the material must consume it (`vertex_color_use_as_albedo`). Fallback if it fails: scale the instance transform to zero at end of life. |
| **M-PARTICLES** | `CPUParticles3D` vs `GPUParticles3D` ceiling, and does #107633 reproduce on 4.7? | 12 concurrent bursts of 16, in the **actual gameplay scene** (an empty-scene number is useless). Step `amount` and emitter count until frame time crosses 16.6 ms. Test `GPUParticles3D` at `INDEX` **and** `VIEW_DEPTH`. | Record as a hard constant `MAX_CONCURRENT_PARTICLE_EMITTERS`, not as a habit. **Reproducing — or failing to reproduce — #107633 on 4.7 is itself a useful result and worth reporting upstream.** |
| **M-FLOW** | Flow-field sweep cost in wasm | Worst case: solve from the tile furthest from any wall with all doors open, 200 consecutive solves, min/median/p99, behind `OS.is_debug_build()`. | **p99 < 2.0 ms** accept. **> 4 ms** → time-slice or move to fast sweeping. |
| **M-SEP** | Separation force balance | Log `_separation(here).length()` for 30 s of a round-10 pack. | If p90 > ~0.4 (×2.4 ≈ 1.0, equal to the unit flow vector), §4.5 item 3 is **mandatory**, not optional. Re-measure after clamping and confirm the horde spreads across a 2-tile corridor rather than filing. |

**Tier 3 — blocks Milestone 3/4, or is a standing question.**

| # | Question | Note |
|---|---|---|
| **M-PWA** | Does the PWA COOP/COEP shim actually isolate on **GitHub Pages specifically**? | Docs claim "any website" and the mechanism is sound, but Pages' Fastly layer, `Vary` handling and SW scope under a project subpath (`/kriegsnacht/`) are untested. Check `crossOriginIsolated` and `typeof SharedArrayBuffer` before and after the auto-reload, and that the injected header appears on `index.wasm`. **Also confirm the single-threaded PWA build still boots — a broken SW is worse than no SW.** Gates the entire "threads are a priced option" claim, and with it any return of audio effects. |
| **M-TEMPLATE** | Custom export template size delta | Build stock 4.7 web release from source (confirm it reproduces 39,509,339 / 10,082,564), then again with modules stripped (`text_server_adv` → fallback, webrtc, websocket, camera, mobile_vr, openxr, theora, csg, gridmap, xr, plus whichever physics module M-PHYS rejects) + `optimize=size` + `wasm-opt -Oz`. **No measured before/after for a 4.7 web build exists anywhere.** Commit only if step 2 gets gzipped wasm under ~7 MB — below that it is a day of SCons work for a marginal gain, and moving to a Brotli-serving host achieves ~7.2 MB for free. |
| **M-SUBVIEW** | godot#86940 on 4.7 | One-hour spike **in an exported web build** (editor and export differ per godot#86258): `SubViewport` 256×256, `CLEAR_MODE_NEVER`, `UPDATE_ONCE`, two quads on two frames. Both survive → the splat-texture design is revived. Last tested 4.3.dev1, Jan 2024, unrefuted and unfixed. |
| **M-INSTUNI** | godot#112674 on 4.7 | N ∈ {8,16,24,32,64} instances with a distinct `instance uniform vec4 tint`, on GitHub Pages not localhost, Chrome and Firefox. Repeat with half the meshes `visible = false` to test the global-budget claim. Pass at N ≥ 32 with invisible nodes present. Reported on 4.5.1; no fix PR located. |
| **M-SYNC** | godot#109494 on 4.7 | Run the MRP under 4.7 with `thread_support=false`. Only matters if layered ambience is revisited. |
| **M-AUDIOEAR** | Verify the Sample-mode limitations by ear, on the deployed build | 15 minutes, closes three inferences: add an `AudioEffectReverb` (editor: reverb, web: none); set `attenuation_filter_cutoff_hz = 500` on a distant loop (if it does not audibly muffle, §1.2's inference is confirmed and should be reported upstream); call `stop_stream()` on a polyphonic stream (godot#94724, unverified on 4.7 — if it survives, do not build a voice manager on `AudioStreamPolyphonic`); confirm `finished` fires (your whole pool-recycling strategy depends on it). |
| **M-GEN** | Node-vs-Blink rasteriser divergence across all 17 strips | The generator was **executed this session**: 244 ms end-to-end, mean delta **2.7/255**, only **18 of 18,432 pixels** differ by more than 32 — and those are `outlineSprite` rim pixels flipping either side of an alpha threshold. A control run with the full texture block confirmed the residual is rasteriser antialiasing, **not** RNG divergence. But that is *one* sprite; crawlers, hounds and machines use different primitive mixes. Accept per file if >32-delta pixels are <0.5% **and** no such pixel forms a contiguous run of ≥3 along a silhouette edge (a broken rim reads as a visible notch at 48×64). Failures get a Playwright/Chromium capture instead — and record which file came from which path. |
| **M-TTS** | Does TTS survive the announcer processing chain? | Unfalsifiable by research. Render 5 prosodically-hard lines, apply pitch-shift −6 st → ring-mod ~45 Hz → bandpass 300-3400 → bitcrush → normalise, capturing after each stage. **Pass criterion is intelligibility *under mix*** at −20 dB against gunshots with 12 zombies groaning, not in isolation. Render at 44.1 kHz and resample **last** — ring-mod sidebands alias badly at 22,050. Failure is fine: non-verbal stingers plus on-screen text is a legitimate answer that costs zero licences. |
| **M-DEV** | Real-device WebGL2 spread | Minimum: one desktop discrete GPU, one desktop integrated GPU, one mid-range mobile browser. `get_video_adapter_name()` is already logged, so results self-label. |

**Flagged as genuinely inconclusive — do not paper over these:**

- **Absolute zombie speeds in m/s are unresearchable.** They are root-motion properties of `.xanim` assets, differ per animation *within* a class, and differ per map (Verrückt's "fast zombies" reputation comes from a different animation set, not different logic). **Anyone who quotes a single m/s number for "a zombie" is guessing.** Tune against the *invariant* instead: *a round-10+ sprinter must hold or close distance on a player sprinting in a straight line, and lose distance only on an efficient training loop.* Verify with a repeatable test — spawn one sprinter, sprint straight for 10 s, log the gap. If it grows monotonically, the game is unlosable no matter what the source numbers say.
- **WaW's zombie melee damage is not sourced.** Use BO1's 60 and label the port BO1-era.
- **Per-weapon head damage multipliers** were not retrieved. The "no global 1.5×" conclusion is safe (it rests on the *absence* of hit-location damage scaling in the zombie scripts); the positive per-weapon values are unknown.
- **R4's line numbers and file paths are decorative.** Every value was verified by *file + symbol + exact text*; **not one line citation could be verified**, and the T5 paths are `ZM/Common/maps/…`, not `t5/…`. Verify by symbol, never by line — someone opening `t5/_zombiemode.gsc:244` will find nothing and may wrongly conclude the whole brief is fabricated.
- **No published wasm/WebGL2 benchmark for Godot 4.x physics or audio exists.** Every physics figure is native desktop; every audio limit is derived from reading source. Do not extrapolate native numbers by a fixed ratio — that would be inventing a measurement.
- **No open-source Godot 4 FPS ships combat FX specifically to WebGL2.** The closest reference has `OS.has_feature("web")` branches that *reduce* particle counts and *disable* decals — evidence that someone hit this wall, not a worked solution. **Every WebGL2-specific budget in §2 is synthesis, not anyone's measured result.**
- **No game-industry write-up of a layered flow field exists**, across four distinct search phrasings. The engineering pattern exists (Recast, MLS maps); the game write-up does not.
- **`MSAA 3D` on WebGL2** is documented as supported but has no web-specific confirmation, and its cost on integrated GPUs at 1080p is unknown.
- **`alpha_to_coverage` behaviour on WebGL2** is untested — relevant because it is the cheapest way to soften alpha-scissor billboard edges.
- **`ResourceLoader.load_threaded_request()` with `thread_support=false`** was not researched. Assume it degrades to a blocking load.
- **No lawyer read §1.5's licensing conclusions.** The rebrand recommendation is the one action that makes the lawyer question moot, which is why it is scheduled first.

---

## 6. Revised milestone plan

Four milestones. Milestone 1 is the vertical slice. Effort scale: **S** ≤1 day · **M** 1-3 days · **L** 1-2 weeks.

Two structural changes from the gap analysis's plan. First, a small **gate** precedes the slice — six items, all S, that are either blocking (you cannot author against the wrong renderer, or measure with a probe that mislabels it) or that get strictly more expensive with every commit (the trademark rename, the LICENSE). Second, the slice absorbs the **canon corrections** and the **restore list**, because both make the slice's own tuning honest and both are cheaper than the slice items they support.

---

### Milestone 1 — the vertical slice: **"It responds to me, and it can kill me."**

**Goal:** a stranger opens the page, shoots a zombie and can tell they hit it; hears a groan behind them and turns around; sees eyes in an unlit corner; rebuilds a barricade for points — and by round fifteen, gets caught and dies. None of that is true today.

**M1.0 — Gate (all S, land before anything else).**
- Pin `rendering/renderer/rendering_method = "gl_compatibility"` and **switch the editor to Compatibility while authoring**, so the viewport is the shipping target. Update `config/features`.
- **Split the map into per-room `MeshInstance3D` nodes** (§1.5). Localised to `_build_static()`/`_commit()`; the 8-entry room list already exists.
- Fix `perf_probe.gd`: renderer/driver/physics-engine fields (M-0), and the `boot_to_first_frame_ms` timestamp-vs-duration bug. Then **run M-BASE and M-PHYS and commit the numbers to the repo.** Set `physics/3d/physics_engine` explicitly to whichever wins.
- Restore `CULL_BACK` by fixing quad winding; set `detect_3d/compress_to=0` on all 56 sprite imports; enable MSAA 3D.
- **`ShaderWarmup` scene skeleton** — every material, every particle system, every lighting configuration (shadowed spot, shadowed omni, unshadowed), the real `Environment`, the same MSAA and render scale, one frame each, sequenced across frames behind a progress bar. It grows with every later material; build the frame now.
- **Rename the trademarked names and add `LICENSE` + `LICENSES/` + `REUSE.toml` + `NOTICE` + `THIRD-PARTY.md`.** Under 100 lines of renames. Build the credits screen from `Engine.get_copyright_info()` (verified: 102 entries, 19 licences) rather than hand-maintaining it wrong. Do it now, because every jingle, plaque and badge authored after this bakes the old name in deeper.
- **One-command reproducible build** (`tools/build.sh`). Exporting currently requires hand-mutating `project.godot`; the committed config does not match what ships, and the live public build is already stale. Before 200 changes start landing this must be one command.

**M1.1 — Restore (§3, items 1-20).** The ancestor transliterations, in the ranked order. Most valuable: the wall-face shading multiplier, the recoil spring on its new `RecoilPivot`, the per-zombie attack timer, the hitmarker, the hit flinch, the interaction-state scan fix, the distance-weighted spawn window, the quality governor.

**M1.2 — Canon corrections (§1.3).** Melee 60 / Juggernog 160 / 0.4 s per-attacker ignore timer. Discrete three-class speed rolled per spawn, with R4's per-round mix table as the acceptance test. Points-earned power-up trigger (keep the existing 4/round cap — do not reimplement it). Randomised dog rounds with the guaranteed, cap-bypassing Max Ammo. Perk cap 4. **No health-curve change — it is already correct. No hound speed change — they are already faster than the player.**

**M1.3 — Make it losable.** Zombie↔player collision masks (`zombie.collision_mask = 1|2`, player `1|4`), retaining boid separation as the symmetric-standoff tie-breaker **with the clamp from §4.5 item 3**. Finite sprint (~4 s drain, ~4 s recovery) with a ~0.25 s sprint-out fire gate. `max_alive()` returning 8 on dog rounds.

**M1.4 — Perception (the slice proper).**
- **Positional audio foundation** — `AudioStreamPlayer3D` where it matters, `Sfx.play_at(id, Vector3)`, `max_distance` on every player, a 12-16 voice pool with oldest-wins stealing, buses as volume groups only. **No effects, no reverb** (§1.2).
- **Zombie idle groans** (§3 item 8), pitched per palette, culled at 20 m.
- **Hit confirmation** — blood puff from a pooled `GPUParticles3D` emitter, white `modulate` flash, flinch, HUD hitmarker.
- **Muzzle flash + muzzle light** — one persistent shadowless `OmniLight3D` + one quad, one persistent `Timer`, per-weapon colour (§4.3).
- **Glowing eyes** — unshaded overlay + `env.glow_enabled` at a low threshold.
- **Barricade rebuild** (hold-F, the first half of the interaction refactor).
- **Flow-field hardening items 1-3** (`invalidate()`, LOS range gate, separation clamp) — all one-to-three-line changes that make the horde behave, and item 3 is a real bug.
- **Fix the pause key** (§1.4a) and the save path (§1.4b).

**Done looks like:** M-BASE, M-PHYS, M-AUDIO, M-SFXBAKE, M-ESC and M-SAVE are all recorded in the repo. A cold page load produces no in-game frame over ~30 ms (M-WARM's first pass). A stranger playing to round 15 gets killed. The build deploys with one command and the page carries no third-party trademarks.

**Estimate:** 3-4 weeks. Larger than the gap analysis's 5-8 days, because it now includes the gate, the canon pass and the restores — all of which the slice's own tuning depends on.

---

### Milestone 2 — **"It reads as Call of Duty Zombies."**

**Goal:** a screenshot of this build is recognisable as the genre, and the round 1-5 loop is the barricade rather than a shooting gallery.

**Contents.**
- **The barricade loop in full** (T1.3, the largest item here and worth it): carve exterior pockets excluded from `compute_reach()`; rebuild the window tile as a frame with six separate plank meshes so a stripped barricade is genuinely shoot-through; `State.TEARING_BOARDS` with a per-plank accumulator at `randf_range(0.9, 1.4)` s playing the already-baked, never-played `board` sound positionally; vault on zero boards via a short `Curve3D` tween with the hitbox live; and reduce the free between-round regrowth so rebuilding matters. **A zombie parked at a window is fully shootable and completely harmless — that asymmetry *is* the tempo of rounds 1-5.**
- **The lighting pass, in the mandated order** (§4.3): ambient 0.30 → 0.10, fog 0.055 → 0.030, lamp energy 1.5 → 0.8, torch cone 42° → 34°. Then the power-on event — lamps start at zero, staggered `Tween` chain one room per ~0.15 s in distance-from-generator order with a three-flicker preamble, under the ancestor's `powerOn()` whine. Then glow. **Then** SSAO. **Then** the colour-correction LUT. Enable shadows on the torch `SpotLight3D` **only** and retune its energy downward (sRGB blending brightens it). Upgrade `world_builder`'s per-face vertex shade to per-vertex AO + lamp falloff — a free static bake with zero runtime cost.
- **Viewmodel rig** (§4.1) — after M-VMFOV and M-VMCLIP.
- **Weapon state machine** (T1.2) — land it *before* the viewmodel binds to it. It also fixes the most player-visible bug in the project: `_update_fire` clears `_fire_queued` before the cooldown check, so **roughly 8 of 9 semi-auto M1911 clicks are silently discarded**; plus the banked-click-after-reload bug, the fire-latch-stuck-on-unpause bug, the sub-tick remainder discard that means **no automatic weapon fires at its stated RPM** (and *inverts* the RPK/M16 cadence relationship), and the stowed-gun reload freeze.
- **Combat FX** (§4.3): pooled impact emitters with grid-quantised surface lookup, two MultiMesh ring buffers, tracers, the alpha-edge rim shader on zombies, and the shader-free screen-effect layer (which subsumes T1.4, including the inverted-damage-overlay fix — the defect is channel sharing plus inverted timing, not stickiness).
- **Round ceremony** (T1.6, minus the deleted `AudioStreamSynchronized` design): the four-layer descending stinger (the port's currently sweeps the **wrong direction** — `sweep = 1.6` makes the pitch *rise*), the title card, three pre-mixed ambience tiers selected on round, a 1.2 s beat of silence before the sting, and a distinct hound-round variant.
- **`tools/gen/` as a committed Node + `@napi-rs/canvas` project** — extract `kriegsnacht.html` 374-392 + 564-1450, add the two-line `document` shim, record the extraction line ranges in a README so the provenance is never lost again. **Fix `makeChalk`'s `ui-monospace` font first** (it resolves differently on every machine) with a hand-rolled 5×7 bitmap font. This blocks chalk plaques, the PaP art, the directional atlas and every future sprite.
- **Chalk wall-buy plaques and the Pack-a-Punch machine art** — both are already-authored ancestor drawing code that the original export pass simply never reached. Restoring them is an **export-script task before it is a gameplay task**.

**Done looks like:** M-WARM, M-SHADOW, M-SHADOW2, M-SSAO, M-VMFOV, M-VMCLIP, M-BILLBOARD, M-SHADOWCAST, M-MMCOLOR, M-PARTICLES, M-FLOW and M-SEP are all recorded. The frame budget in §2.1 holds on integrated-GPU hardware with all FX live. Rounds 1-5 play as the barricade loop. A screenshot reads as the genre.

**Estimate:** 5-7 weeks.

---

### Milestone 3 — **"It's a real game you can lose, understand, and come back to."**

**Goal:** everything around the core loop — the shell, the economy, the systems architecture, and the tooling that makes further balance work falsifiable.

**Contents.**
- **`main.gd` split** (T0.4) into `RoundDirector` / `PowerupManager` / `InteractionSystem` / `MysteryBox` / `Atmosphere`, and **switch pause to real `get_tree().paused`** with `PROCESS_MODE_WHEN_PAUSED` on the HUD subtree. The current early-return-per-node pattern already leaks (HUD timers keep decaying while paused) and **will not survive** the tweens, particles and `AnimationPlayer`s Milestone 2 just added.
- **Seeded RNG** (T0.3) — collapse three uncorrelated entropy sources into one authority with named sub-streams, so a cosmetic `randf()` cannot desync the spawn sequence. Split `Game` into run state and profile state.
- **Iteration harness** (T0.5) — debug console (`round N`, `give`, `points`, `perk`, `timescale`, `freecam`, `spawn`, live constant sliders) and a **headless balance sim** emitting CSV. Right now, if someone changes zombie speed, **nothing in this repo can answer whether round 12 got harder or easier.** Add golden-value tests on the canon curves so a refactor cannot break them silently.
- **Economy correctness pass** (T1.5): teddy bear still pays out (a teddy pull is currently *strictly better* than a normal pull); wall-buy ammo refills every gun including a PaP'd Ray Gun; **100% of Thundergun kills score as headshots** (and the knife can never headshot, by construction); Insta-Kill is pure upside; `drop_tick` never resets so drops land earlier the longer a run goes; AoE hits through walls (`_has_los` is the exact helper needed and already exists); the Thundergun cone is a **134.8° wedge**, ~4× the real weapon; the knife cannot reach crawlers or hounds and hits an arbitrary group-order target rather than the nearest.
- **Interaction system** (T1.7) — facing test, occlusion ray, hold accumulator with a radial arc, affordability in the prompt, deregistration of satisfied entries. Verified: the MP40 wall-buy is **buyable through a wall corner**.
- **Downed state and a Quick Revive that revives** (T1.9) — `Player.revive()` is defined and called by nothing. Add the revive countdown, `Game.revives_left`, perk loss on down (the single biggest economic punishment in Zombies, currently absent), the camera drop and capsule shrink, the forced M1911, and connect `downed_changed`. **The global muffle is replaced by baked darker variants** (§1.2).
- **Menus, options, persistence, accessibility, and the loading shell** (T2.7). There are no `Button` nodes anywhere in the project. Build a real `Control` menu with focus neighbours. `Settings` over the §1.4b save path. **The accessibility toggles this plan makes mandatory**: reduce-motion (the plan actively adds shake, bob, cant, flashes and a whiteout with no way to turn any off), captions for audio-only channels (the audio work makes directional threat cues *primary*, which makes the game strictly less playable deaf than it is today), a visual damage-direction indicator, and a colourblind path. **And own the first ninety seconds**: a custom shell (copy `misc/dist/html/full-size.html`, half a day) carrying the wordmark, a real percentage bar (it works — the loader seeds totals from export-baked sizes), the keybind table, the points-economy hint, the fan-project disclaimer, the desktop-only notice, and a **CLICK TO PLAY** button that resolves the AudioContext unlock, the initial pointer-lock activation and the onboarding text in one gesture. Enable the PWA option for caching (it fixes the measured `max-age=600` re-download) and **re-run the pause fix against the PWA build**, because a stale service worker is the classic "my fix didn't deploy" trap.
- **Pack-a-Punch machine and Mystery Box theatre** (T2.8, T2.9) — mirror the existing `_box_state` machine, which is already the right shape. Randomise the starting box spot (`Game.box_spot = 0` is hard-set, so the box is *always* in the Theatre behind the 750 door on a fresh game). Port `boxOpen`/`boxTake`/`teddy` as **original** motifs (§1.5).

**Done looks like:** M-PWA and M-TEMPLATE are answered. A stranger loads the page, understands the controls, plays, loses, sees their stats, changes their sensitivity, closes the tab, comes back, and it remembered. The balance sim can answer "did round 12 get harder".

**Estimate:** 5-6 weeks.

---

### Milestone 4 — **Depth and identity.**

**Goal:** the things that distinguish a competent demake from a game worth a second run.

**Contents.**
- **Projectiles and wonder-weapon identity** (T2.4) — an `Area3D`-based projectile with manual integration and swept raycasts (not `RigidBody3D`). **The travelling `OmniLight3D` is the whole point of the Ray Gun**, because it lights the corridor as it flies. Shared `_explode()` with a **line-of-sight-gated** splash query. Currently the Ray Gun is a 180-damage single-target hitscan — strictly *worse* than the 500-point M14 — and its declared 1150 splash is dead data pointing at a deleted subsystem, invisible in play because nothing errors.
- **8-direction atlas** (§4.2) — five draw routines in the generator, `flip_h` for the rest. Plus the free variety currently unused: every spawn starts on walk frame 0 (a wave marches in genuine lockstep), and `speed_scale` is a one-shot `randf_range` set at `_ready()` rather than tied to velocity, so a *fast* zombie can play a *slower* cycle than a slow one. Reconcile the 0.52 m collider against 1.365 m of drawn billboard — the outer ~40% each side is empty space to `_hitscan`, which reads as broken hit registration.
- **Walker→crawler by leg-shot** (§4.2 item 1) and limbless variants — needs the splash system and the generator.
- **Corpses and death variants** (T2.6) — thread the `cause` enum and killing direction (both already available at the call sites and both currently discarded) into `_die`. Nuke kills staggered by `distance_to(player) * 0.045` so the horde collapses as an outward wave. **Single-capsule fake ragdoll only** (§2.1).
- **ADS** (T2.3) — and fix the square-not-conical spread distribution while there.
- **Interior geometry, props and the map validator** (T3.4 + §4.5) — cost field, blur pass, `stamp`/`unstamp`, and the six invariants run across all 16 door-open states. Give the machines real colliders so they act as training pivots.
- **Traps** (T3.3) and **perk roster expansion** (T3.5) — Stamin-Up only becomes meaningful now that sprint is finite. Fix the HUD refresh bug: `_refresh_perks()` is called from exactly one site, inside `_on_weapon`, so **buying a perk does not update the strip until you next shoot, reload or swap.**
- **Grenades and the Monkey Bomb** (T3.1) — the Monkey Bomb needs no new systems beyond a global `Game.lure_position` that zombies target instead of the player.
- **Payload work** — act on M-TEMPLATE, and price the move to a Brotli-serving host (10.58 MB → ~7.2 MB for zero code change).
- **Seeded run layer** (T4.2, cheap version) — seeded shuffle of wall-buys/perk spots/box spots, randomised door costs, an intermission draft in the existing 6.5 s window. `compute_reach()` already re-derives reachability, so nothing downstream breaks.

**Explicitly deferred past M4:** level verticality (T4.1, XL, invalidates the 2D flow field — and the explicit test for whether you need it is *"does any (x,z) column need two walkable surfaces at different heights?"*; if no, the 30-line link-edge approach suffices and layered fields are waste); skeletal enemies (T4.3, closed); teleporters/buildables/boss rounds (T4.4, map-specific set pieces on an original map with no matching fiction); music and the easter-egg song (T4.5, original compositions only); occlusion culling and LOD (T4.6 — not a gap against the reference, and the current draw budget is nowhere near strained); controller support and aim assist (T4.7 — worth recording that **aim assist contributes more to "CoD gunplay feel" than the recoil curve does**, and that a 27-finding gunplay report never mentioned it; deferred only because the project commits to desktop mouse-and-keyboard).

**Done looks like:** a run is distinguishable from the last one, the wonder weapons are wonder weapons, and the frame budget still holds.

**Estimate:** 6-8 weeks.
