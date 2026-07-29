# R7 — Assets, Audio and Licensing for a Solo Fan Project

**Research theme 7.** Where art and audio come from, and what the licence texts actually say.
Date: 2026-07-27. Target: Godot **4.7** (`config/features=PackedStringArray("4.7", "Forward Plus")`),
single-threaded HTML5/WebGL2 on GitHub Pages.

> **Not legal advice.** Part (c) reports what licence texts, statutes and published practice
> say, and where practice is settled versus genuinely uncertain. Where the honest answer is
> "consult a lawyer or avoid the risk", it says so. The risk-avoiding option is free here and
> is led with.

---

## Bottom line

1. **The asset generator is not lost — it is in the repo.** `kriegsnacht.html` lines 374–1450
   contain the complete Canvas2D art pipeline (`makeCanvas`, `bake`, `outlineSprite`,
   `makeZombieSet`, `makeCrawlerSet`, `makeHoundSet`, `makeViewmodel`, `makeChalk`,
   `makePerkMachine`, `makeBox`, `makeGenerator`, `makePowerup`, `makePaP`). Its **only** DOM
   dependency is `document.createElement('canvas')`. **I extracted it and ran it under Node 22
   with `@napi-rs/canvas` in this session** — it regenerated `zombie0_walk.png` at the correct
   288×64 in **244 ms end-to-end**, with a mean per-pixel delta of **2.7/255** and only
   **18 of 18 432 pixels (0.098 %)** differing by more than 32 in any channel. Build
   `tools/gen/` as a Node script, not a Godot `@tool` script and not a headless-browser capture.
2. **8-direction atlases, crawl cycles and gib chunks are additions to that generator, not new
   art.** `zombieBody(g, p, o)` is already parameterised (`swing`, `bob`, `reach`, `lean`,
   `tornArm`, `ribs`); the crawler set already exists in all three palettes; `makeChalk` already
   draws wall-buy plaques and `makeViewmodel` already draws a first-person weapon. Adding a
   `yaw` parameter to `zombieBody` and looping 8 yaws × 6 frames is a day of work, and Godot
   4.7 can bake a 384×512, 64-frame atlas headlessly in **169 ms** (measured, below) if you
   ever want it engine-side instead.
3. **You do not need Mixamo, and you should not use it.** Quaternius ships an
   **Animated Zombie Pack** — rigged, animated, 2 models, **CC0** — plus a **Universal Animation
   Library 2** with zombie locomotion, also CC0. Mixamo's own FAQ describes the service as a
   *"limited duration technology preview"*, forbids distributing *"the raw character and
   animation files"*, and a Godot web export is a plain `.pck` served over HTTP that
   `gdsdecomp` reconstructs back into the original import formats. CC0 removes that whole
   question for free.
4. **Keep synthesising the audio; sampled weapons are not the bottleneck you think, but they
   are not the win either.** Measured with ffmpeg 8.0.1: 12 weapons × 3 layers × 3 variants
   ≈ **572 KB at q0/22.05 kHz mono** or **840 KB at q4/32 kHz mono** — i.e. a rounding error
   against a Godot web payload. The real costs are (a) Godot 4.7 docs explicitly say Ogg Vorbis
   *"require significantly more processing power to play back"* and recommend **MP3 over Ogg for
   web**, and (b) 108 files of per-file Freesound licence bookkeeping. The current parametric
   synth gives infinite variants at zero bytes and zero attribution. **Hybrid:** keep the synth
   as the base layer, add ≤6 CC0 samples only for what synthesis does badly (a real tail, a
   bolt/mech transient).
5. **The repo has no LICENSE, which means all rights reserved.** GitHub's ToS grants viewers
   only *"view and fork"* — nothing else. Ship a REUSE-3.3-shaped `LICENSES/` + `REUSE.toml` +
   `NOTICE`, MIT for code, CC0 or CC BY 4.0 for your own procedural art, and build the in-game
   credits screen from `Engine.get_copyright_info()` — **verified in 4.7: it returns 102
   third-party component entries and `get_license_info()` returns 19 licences**, which you are
   otherwise hand-maintaining wrong.
6. **Rename the trademarks now, while it is a 40-line diff.** Real firearm *names* are the
   lowest-risk item on the list (settled industry practice since 2013, and Activision won
   *AM General* on exactly this ground). The perk **jingles** are the highest-risk item and the
   one where "I re-synthesised it myself" does **not** help: a jingle is a copyrighted
   *musical composition*, and 17 U.S.C. § 101 defines "phonorecords" to exclude *"sounds
   accompanying a motion picture or other audiovisual work"* — so the § 115 compulsory
   mechanical licence, the thing that makes cover songs legal, **does not reach a video game
   at all**. There is no compulsory path. Write original jingles.

---

## Findings

### Part (a) — the asset pipeline

#### A1. The generator source is already committed. `kriegsnacht.html` is the tool.
**Tier 1 (repo source, read directly).** `C:\Users\fahim\Desktop\Pojects\Cod Zombies Rouglike\kriegsnacht.html`, 139 769 bytes.

| Concern | Lines | Note |
|---|---|---|
| Seeded PRNG (`_seed`, `srnd`, `sr`) | 374–392 | deterministic; regeneration is reproducible |
| `makeCanvas` / `bake` / `grain` / `splotch` | 564–597 | `bake(w,h,fn)` returns `{w,h,data:Uint32Array}` |
| Wall/floor textures (`T`, `tex`) | 599–838 | 64×64, no DOM deps |
| `ZPAL` (3 zombie palettes), `zombieBody` | 844–950 | fully parameterised body draw |
| `outlineSprite` — the 1 px dark rim | 955–972 | thresholds `alpha > 18` and neighbour `alpha > 80`, stamps `rgba(6,6,5,205)` |
| `makeZombieSet` / `makeCrawlerSet` / `makeHoundSet` | 973–1130 | walk 6 / attack 2 / death 4 |
| `makeViewmodel(key, tint)` | 1210 | **a viewmodel generator already exists** |
| `makeChalk(key, label, cost)` | 1244–1262 | 52×40 wall-buy plaque, `drawParts(GUNART[key], …)` |
| `makePerkMachine` / `makeBox` / `makeGenerator` / `makePowerup` / `makePaP` | 1271–2011 | |

The only DOM call in the whole block is `document.createElement('canvas')` at line 565.
Everything else is standard Canvas2D: `fillRect`, `beginPath/ellipse/fill`, `save/restore`,
`translate/rotate`, `globalAlpha`, `getImageData/putImageData`, `imageSmoothingEnabled`,
and — in `makeChalk` only — `font` + `fillText`.

`scripts/world/sprite_lib.gd` independently corroborates the provenance in its own docstring:
*"Those PNGs were generated by replaying the browser build's own canvas drawing code."*
**Corroboration: 2 independent (the HTML source; the GDScript that consumes its output).**

#### A2. Node + `@napi-rs/canvas` reproduces the art to 99.9 %. Executed, not researched.
**Tier 1 (executed this session).**

Method: concatenated `kriegsnacht.html` lines 374–392 and 564–1007 into a CommonJS file,
prefixed with

```js
const { createCanvas } = require('@napi-rs/canvas');
const document = { createElement: () => createCanvas(1, 1) };
```

then called `makeZombieSet(ZPAL[0])` and blitted the six walk frames into a 288×64 strip.

Result:

```
frames 6  size 288x64                 wall clock 0.244 s (incl. node startup)
regen 288x64   committed 288x64
pixels 18432  differing 3860 (20.94%)  maxChannelDelta 255  meanDeltaOnDiff 2.7
delta histogram (bucket=32): {0: 3842, 1: 8, 6: 6, 7: 4}
```

Read that carefully: 3 842 of the 3 860 differing pixels differ by **≤ 31**, and the mean
delta across all differing pixels is **2.7 / 255**. Exactly **18 pixels** in the whole strip
differ by more than 32 — these are `outlineSprite` rim pixels flipping on or off because an
antialiased edge landed at alpha 79 vs 81 either side of its `> 80` neighbour threshold.

Control: I re-ran including the full texture-generation block (lines 599–838) so the global
`_seed` advanced exactly as it does in the browser. **The diff was byte-for-byte identical**,
which falsifies the "RNG state divergence" hypothesis and pins the residual on rasteriser
antialiasing (Skia standalone vs Skia-inside-Blink), not on determinism. `zombieBody` does not
consume `sr()`.

`node_modules` for this is 37 MB and installs in under a minute with no native toolchain
(`@napi-rs/canvas` ships prebuilt binaries and uses Skia — the same engine as Chrome).
**Corroboration: 1 (direct execution) + 1 secondary on library choice.**
Secondary: <https://www.pkgpulse.com/guides/node-canvas-vs-napi-rs-canvas-vs-skia-canvas-server-2026> (Tier 3).

#### A3. Godot `@tool` / headless is viable but is the wrong tool for *this* job.
**Tier 1 (executed this session, Godot v4.7.stable.official.5b4e0cb0f).**

I generated a full 8-direction × 8-frame, 48×64-cell atlas (384×512) headlessly including a
naive per-pixel `get_pixel`/`set_pixel` rim pass:

```
save_png err=0 OK=0
atlas=(384, 512) frames=64
gen_ms=169.42  save_ms=5.077
```

API confirmed against the 4.7 class reference
(<https://docs.godotengine.org/en/stable/classes/class_image.html>, Tier 1):
`Image.create_empty(w, h, use_mipmaps, format)` — **`Image.create()` is deprecated in favour of
`create_empty()`** — plus `fill`, `fill_rect`, `set_pixel`, `blit_rect`, `blend_rect`,
`save_png`, `save_png_to_buffer`, `resize`, `convert`.

Two gotchas I hit and you will too:
- GDScript 2.0 rejects `var nx := x + dx` when `dx` comes from an untyped `Array` literal
  (`Cannot infer the type of "nx" variable`). Use `range(-1, 2)` or annotate `var nx: int`.
- Godot's `Image` has no path API, no ellipse, no font rendering, and no `globalAlpha`. The
  ancestor art leans on all four. Reimplementing `zombieBody` — which is dozens of rotated,
  alpha-blended ellipse strokes — against `Image` primitives would be a rewrite from scratch,
  not a port. That is why A2 wins.

Where a Godot `@tool`/`EditorScript` *is* correct: post-processing that must live inside the
engine's own import graph — packing existing strips into atlases, generating `SpriteFrames`
resources, or building `AtlasTexture` regions. Not for drawing.

#### A4. Headless-browser capture is the only byte-identical option, and it is not worth it.
**Tier 3, plus reasoning from A2.** A Playwright/Puppeteer capture runs the code in Blink,
which is the exact rasteriser the committed PNGs came from, so it is byte-identical by
construction. It costs a ~150 MB browser download, an async harness, and a much slower loop.
Given A2's measured 0.098 % visibly-different pixels on pixel art with a hard-thresholded rim,
this is not a good trade — **unless** you want to preserve the existing 17 committed strips
byte-for-byte while adding new ones. See "What must be measured".

#### A5. The one place Node will genuinely diverge: `makeChalk` uses fonts.
**Tier 1 (repo source, line 1253–1261).**

```js
g.font='6px ui-monospace, monospace';
g.fillText(label.toUpperCase(), W/2, H-14);
g.fillStyle='#E0A62B';
g.font='bold 10px ui-monospace, monospace';
```

`ui-monospace` is a CSS system-font keyword. It will not resolve in Node, and it resolves to a
*different* face on Windows vs macOS vs a CI runner. The chalk plaques are the only sprites in
the pipeline with text. **Fix at the source**: register an explicit bitmap or OFL-licensed
monospace face in the generator (`@napi-rs/canvas` supports `GlobalFonts.registerFromPath`), or
replace `fillText` with a hand-rolled 5×7 pixel font baked into `tools/gen/`. The latter is
more in keeping with the art style, is deterministic across machines, and removes a font
licence from the NOTICE file.

#### A6. Effort ranking for the four requested deliverables
All four are additions to `tools/gen/`, in ascending order of work:

| Deliverable | Approach | Effort |
|---|---|---|
| Chalk wall-buy plaques | `makeChalk` already exists; swap `ui-monospace` per A5, loop over the wall-buy table | XS |
| Crawl cycle | `makeCrawlerSet` already exists and already ships in 3 palettes (`assets/sprites/crawler{0,1,2}_{walk,death}.png`) | none — already done |
| 8-direction atlas | add a `yaw` parameter to `zombieBody`'s `o` object; mirror 3 of the 8 yaws to halve the drawing work; emit one 8×N grid per palette per animation | S–M |
| Gib chunks | new `makeGib(p, kind)` reusing `ZPAL[p]` colours, `splotch()` for the flesh blob and `outlineSprite()` for the rim; 6–8 chunk types × 4 tumble frames | S |

---

### Part (b) — sourcing, if generation fails

#### B1. Quaternius is the answer for a rigged low-poly zombie. CC0, no attribution, ships today.
**Tier 1 (vendor pages).**
- <https://quaternius.com/packs/animatedzombie.html> — **Animated Zombie Pack**: licence stated
  as **CC0**; 2 models, rigged and animated, atlas-textured, **FBX / OBJ / Blend**. Free tier
  downloads immediately with no membership.
- <https://quaternius.itch.io/universal-animation-library> — **Universal Animation Library**,
  licence stated verbatim as *"Creative Commons Zero v1.0 Universal … Free to use in personal,
  educational and commercial projects."* 120+ animations (45 in the free standard tier), FBX +
  GLB + .blend, universal humanoid rig, *"compatible with other common rigs (Mixamo for
  example)"*. Its **sequel (Universal Animation Library 2) is the one carrying zombie
  locomotion** — the original does not.
- Also present on quaternius.com: *Zombie Apocalypse Kit*, *Animated Men/Women Pack*,
  *Ultimate Modular Men/Women Pack*, *Ultimate Animated Character Pack*.

**Godot-side caveat (Tier 1):** the zombie pack ships FBX/OBJ/Blend, **not glTF**. Per
<https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html>
(4.7): glTF 2.0 is the recommended format; *"any FBX file added to a Godot project in Godot 4.3
or later will use the ufbx import method"* (so no FBX2glTF binary needed); `.blend` import
*"requires Blender installed"* and is unavailable on the web editor. Practical path: open the
`.blend` in Blender once, export `.glb`, commit the `.glb`. **Corroboration: 2** (vendor page +
Godot docs; plus Tier-3 aggregator confirming Quaternius/Kenney/KayKit as the CC0 rigged-character cluster:
<https://app.cinevva.com/guides/game-assets-guide>).

#### B2. Kenney is CC0 but is a weaker fit for rigged humanoids.
**Tier 1.** <https://kenney.nl/support> — *"all game assets on the asset pages are public domain
licensed (CC0)"*, *"Attribution is not required, but if you choose to give credit you can do so
by mentioning 'Kenney'"*, with the one restriction that the **Kenney logo** is not covered.
Kenney's 3D catalogue is strongest on props/kits; the rigged-humanoid gap is exactly what
Quaternius fills.

#### B3. Mixamo — the correction. This is the widely-misunderstood one.
**Tier 1/2 (Adobe's own FAQ text, via the Adobe community mirror), corroborated Tier 3.**

What is true:
- Royalty-free, commercial and non-commercial, **no attribution required**:
  *"you're certainly welcome to, but are not required to give credit to Adobe, Mixamo, or Fuse
  in any way."*
- Use inside a game as NPCs/avatars is squarely permitted.

What people get wrong, and it matters here:
- Adobe's own wording is *"Mixamo online animation services are **currently in a limited
  duration technology preview**, and during that preview they are available for free, with no
  licensing or royalty fees."* That is a **time-limited grant by its own terms**, not a
  perpetual public-domain dedication. A CC0 asset can never be withdrawn; a technology-preview
  grant explicitly contemplates ending.
- The restriction is *"The only thing you can't do is distribute the raw character and animation
  files"*, and it explicitly names *"Packages for 3D stock or asset store websites where
  character or animation raw files will be sold or distributed."*
- **The project-specific problem:** a Godot HTML5 build on GitHub Pages is a `.pck` served
  as a static file at a guessable URL. `gdsdecomp` (GDRETools) performs *"full project
  recovery … converts all imported resources back to their original import formats"* —
  <https://github.com/GDRETools/gdsdecomp> (Tier 1, tool README). So a Mixamo FBX shipped in
  this build is, in practice, a downloadable raw Mixamo FBX. Whether that crosses Adobe's line
  is a judgement call I am not qualified to make, and I found **no** enforcement action either
  way. It does not matter, because Quaternius CC0 costs nothing and has no such question.
- **Service health, 2026 (Tier 3, single source, treat as directional):** Mixamo is up and free
  as of July 2026 but *"unmaintained"*, with authenticated features (upload, download,
  auto-rigger) *"intermittently broken since June 16, 2025 because of a backend authentication
  failure"*. Fuse was discontinued in 2020. Source:
  <https://app.cinevva.com/guides/free-character-animations-rigging>. **Corroboration: 1.** I could
  not independently confirm the outage claim — flagged as a gap.

**Verdict: do not build a dependency on Mixamo. Use Quaternius CC0.**

#### B4. Gib/limb sprite strips — nothing off-the-shelf will match your palette. Generate them.
**Tier 1.** The best CC0 candidate is *Gore Blood Gibs Meat Chunks* by Reactorcore,
<https://opengameart.org/content/gore-blood-gibs-meat-chunks> — licence line confirmed as
**CC0**; contains red pixel spray, meat chunks/bones/organs, animated blood splashes, glow
splash/mist; 75.7 KB zip.

But the established style is three specific palettes (`ZPAL[0..2]`: skin `#8A9478`, dark
`#5B6650`, cloth `#3D4238`, wound `#5E1114`, …) plus a `rgba(6,6,5,205)` 1 px rim stamped by a
specific alpha-threshold algorithm. **No third-party pack will carry that rim or those hues**,
and recolouring someone else's gibs to match is more work than `makeGib()` per A6. Use
Reactorcore's pack, if at all, only as the *blood splash* layer where palette matching is loose.

#### B5. Sonniss GDC bundles — terms are excellent and unusually clear.
**Tier 1.** <https://sonniss.com/gdc-bundle-license/>:
- *"Licensee may use and modify the licensed sound effects for personal and commercial projects
  **without attribution**."*
- *"Licensee may use the licensed sound effects on an unlimited number of projects for the
  entirety of their life time."*
- *"Licensee may not modify any of the sound effects with intent to claim authorship."*
- *"Licensee may not sell any of the sound effects as they come"* — i.e. the raw-redistribution
  restriction only; shipping them inside a game is fine.
- **AI/ML clause:** *"Licensee is expressly prohibited from using any sound effects … for the
  purpose of training artificial intelligence technologies"* without written permission.

Free/non-commercial games are covered. Bundles are at <https://gdc.sonniss.com/>.
**Corroboration: 2** (licence page + search-surfaced summaries).

**Caveat for this project (my inference, not a source claim):** the same `.pck` extractability
in B3 applies, and "may not sell the sound effects as they come" is about selling, not about
extractability — so Sonniss is materially safer than Mixamo on this axis. It is also several GB
per bundle, so you would be hand-picking a handful of files.

#### B6. Freesound — per-file licence variation is the whole story, and it is machine-readable.
**Tier 1.** <https://freesound.org/help/faq/> — four licences appear on uploads:
**CC0**, **CC-BY**, **CC-BY-NC**, and the retired **Sampling+** (behaved like CC-BY-NC and
additionally barred commercial advertising; CC retired it but old uploads still carry it).
Attribution format for CC-BY: sound title, uploader, Freesound URL, licence — and for long
lists you may link to an external attribution page rather than inline every credit.

**This is machine-checkable, so make it a build step.** From the APIv2 docs
(<https://freesound.org/docs/api/resources_apiv2.html>, Tier 1) the sound resource carries a
`license` field described as *"The Creative Commons license under which the sound is available
to you ('Attribution', 'Attribution NonCommercial', 'Creative Commons 0')"*, and `license` is a
filterable search field: `filter=license:"Creative Commons 0"`.

Practical rule: **filter to CC0 only.** It removes the NOTICE burden entirely, removes the
CC-BY-NC ambiguity (this is non-commercial today, but a portfolio piece under your real name
is arguably promotional, and CC-BY-NC's "NonCommercial" boundary is famously unsettled), and
removes the retired-Sampling+ trap.

#### B7. The payload arithmetic — measured, not estimated.
**Tier 1 (executed this session, ffmpeg 8.0.1-full_build).** Mono `libvorbis`, pink noise —
deliberately the *worst case* for Vorbis, so these are upper bounds for real gunshots.

| Layer | Duration | q0 / 22.05 kHz | q2 / 32 kHz | q4 / 32 kHz | q6 / 44.1 kHz |
|---|---|---|---|---|---|
| Transient ("crack") | 0.35 s | 4 955 B | 5 983 B | 6 758 B | 8 574 B |
| Tail / reverb | 1.20 s | 8 511 B | 11 815 B | 13 236 B | 18 745 B |
| Mech/foley (est. 0.2 s) | 0.20 s | ~2 800 B | ~3 400 B | ~3 900 B | ~4 900 B |

12 weapons × 3 variants = **36 sets**, each of 3 layers:

| Quality | Per set | **108 files total** |
|---|---|---|
| q0 / 22.05 kHz | 16.3 KB | **≈ 572 KB** |
| q4 / 32 kHz | 23.9 KB | **≈ 840 KB** |
| q6 / 44.1 kHz | 32.2 KB | **≈ 1.11 MB** |

Add ~30 announcer lines at ~1.5 s: speech compresses far better than noise, realistically
5–7 KB each ⇒ **~180 KB**. **Total sampled-audio payload: 0.75–1.3 MB.**

**Conclusion: payload is not the constraint.** The README records a 47 MB VRAM figure and the
Godot web runtime dominates transfer size regardless. What *is* a constraint:

**Tier 1**, <https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_audio_samples.html>
(page identifies as **Godot 4.7**):
- *"Consider using WAV for short and repetitive sound effects, and Ogg Vorbis for music, speech,
  and long sound effects."*
- WAV is *"lightweight to play back on the CPU (hundreds of simultaneous voices in this format
  are fine)"*.
- Ogg Vorbis requires *"significantly more processing power to play back"*.
- **MP3** *"demands less CPU usage to play back compared to Ogg Vorbis"* and is
  **recommended "for mobile and web projects where CPU resources are limited"**.
- Ogg/MP3 support only a *loop begin* point, not loop end; WAV supports forward, ping-pong and
  backward loops with real loop points.

**This inverts the brief's premise.** "Mono Ogg Vorbis" is the wrong default for a
single-threaded WebAssembly build. For a wave shooter firing 10 rounds/second, short SFX should
be **WAV (with IMA-ADPCM import compression if size matters)** and only the long tails/music
should be compressed — and if compressed, **MP3 beats Ogg on web** per Godot's own docs.

#### B8. Is pure synthesis competitive at this art style? Yes — and it is already winning.
**Tier 1 (repo source).** `scripts/autoload/sfx.gd` (133 lines) bakes every sound at startup
into `AudioStreamWAV` at `RATE = 22050`, mono, `FORMAT_16_BITS`, through a 12-voice pool. The
docstring records the lineage: *"The browser build synthesised every sound through the Web Audio
API from oscillators plus one shared noise buffer — no samples anywhere."* `_gunshot(freq,
thump, body)` is a decaying sine "crack" + a swept low "thump" + exponentially-enveloped noise,
with per-weapon parameters coming straight out of `scripts/data/weapons.gd`.

The honest scorecard:

| | Synthesis (today) | 108 Ogg/WAV samples |
|---|---|---|
| Payload | **0 bytes** | 0.6–1.3 MB |
| Variants | **unbounded** (jitter the seed) | 3, then audibly repeats |
| Attribution/NOTICE burden | **none** | 108 rows, per-file licence audit |
| Startup cost | CPU on the main thread at load — **must be measured**, see below | file decode, also main-thread |
| Realism ceiling | low: no convolution tail, no room, no mechanical detail | high |
| Fit to a Wolf3D-lineage billboard shooter | **excellent — the style is already stylised** | can read as mismatched |

At this art style, synthesis is not a compromise, it is stylistically coherent — the sprites are
48×64 hand-drawn rectangles and ellipses; a photoreal AK-74u sample would be the odd one out.
The two things synthesis genuinely cannot fake are **a convolved room tail** and **mechanical
foley** (bolt, mag, charging handle). Buy exactly those from Sonniss or CC0-filtered Freesound
(≈6 files, ≈60 KB), keep everything else parametric.

#### B9. Announcer TTS — Kokoro-82M is the clean answer; Piper's popular voices are a trap.
**Tier 1 (model cards and dataset licences).**

- **Kokoro-82M** — <https://huggingface.co/hexgrad/Kokoro-82M>. Weights **Apache-2.0**. Model
  card states training on public-domain audio, Apache/MIT-licensed audio, and synthetic audio,
  with named attributions (Koniwa <1 h CC BY 3.0; SIWIS <11 h CC BY 4.0). 82 M parameters,
  54 voices, 24 kHz output, runs offline. Apache-2.0 places no restriction on generated audio.
- **Piper** — the original `rhasspy/piper` (MIT) was archived in October 2025; active
  development is <https://github.com/OHF-Voice/piper1-gpl>, which is **GPL-3.0**. More
  importantly, `docs/VOICES.md` states: *"Piper is intended for personal use and text to speech
  research only"* and *"Some voices may have restrictive licenses, however, so please review
  them carefully!"*
- **The trap, concretely.** The most-used English Piper voice, `en_US-lessac-medium`, is trained
  on the CSTR Blizzard 2013 Lessac corpus. That licence
  (<https://www.cstr.ed.ac.uk/projects/blizzard/2013/lessac_blizzard2013/license.html>, Tier 1)
  restricts use to *"Research Purposes"*, which it defines to **exclude** *"any commercial
  purpose, including the development, marketing, commercialisation, sale or licencing of voice
  synthesis or speech recognition products"*, states the recordings *"are not licenced for
  stand-alone use"*, and forbids letting *"the Materials … be used by any third party"*.
  Shipping audio rendered from that voice in a public game is at best outside what that licence
  contemplates.

**GPL-and-output note.** If you *do* use a GPL-3.0 tool (piper1-gpl, or eSpeak NG) only at
build time to render Ogg files, the GPL governs distribution of the *program*, not of the
program's output — running a GPL tool does not make your audio GPL. That is a well-understood
FSF position, but it is **orthogonal** to the dataset-licence problem above, which is what
actually bites. **Corroboration: this specific point is reasoning from the GPL's own scope, not
a retrieved source — treat as Tier 4 and verify if you rely on it.**

**Does it survive heavy pitch-shift + ring-mod?** This must be measured, not researched — see
the last section for the exact procedure. The prior is favourable: the CoD announcer timbre is
itself a heavily processed voice, and destructive processing (–5 to –8 semitones, ring-mod at
30–80 Hz, bandpass, bitcrush) tends to *erase* the tell-tale TTS artefacts (flat prosody,
over-smooth formant transitions) that make raw TTS sound synthetic. It also erases voice
identity, which is a licensing benefit. But the specific failure mode — TTS phase artefacts
becoming *more* audible under ring modulation — is real and is a 20-minute experiment.

---

### Part (c) — licensing and legal reality

> Again: this reports what the licence texts, statutes and published practice say. It is not
> legal advice. Where I say "uncertain", I mean the sources genuinely disagree or are silent.

#### C1. No LICENSE file = all rights reserved. This is the most concrete problem in the brief.
**Tier 1.** <https://choosealicense.com/no-permission/>: without a licence *"nobody else can
copy, distribute, or modify your work without being at risk of take-downs, shake-downs, or
litigation"*; for a public GitHub repo *"you have accepted the Terms of Service, by which you
allow others to view and fork your repository"* — and the page is explicit that *"[n]either site
terms nor jurisdiction-specific copyright limitations are sufficient for the kinds of
collaboration that people usually seek on a public code host."*

Verified: `ls LICENSE*` in the repo root returns nothing. There is also no `NOTICE`.

#### C2. Real firearm names and shapes — the most settled item, and the lowest risk.
**Tier 1 (court outcome) + Tier 3 (industry practice), corroboration 3.**

- *AM General LLC v. Activision Blizzard*, S.D.N.Y., **decided 1 April 2020**: Activision could
  not be held liable for depicting and naming Humvees in *Call of Duty*. The court applied the
  *Rogers* test and found *"Activision Blizzard's interest in presenting military
  verisimilitude easily met the low bar for artistic relevance"* with insufficient likelihood of
  confusion. <https://www.aipla.org/detail/news/2020/04/08/activision-beats-humvee-trademark-claims-over-call-of-duty>,
  <https://www.finnegan.com/en/insights/blogs/incontestable/in-legal-warfare-over-humvee-trademarks-the-first-amendment-goes-beyond-the-call-of-duty-in-dismissing-am-generals-claims.html>
- **May 2013:** EA publicly announced it would stop entering licensing agreements with gun
  manufacturers while continuing to feature branded firearms, asserting First Amendment
  protection. <https://www.nbcnews.com/tech/tech-news/video-game-maker-drops-gun-makers-not-their-guns-flna1c9840069>,
  <https://techdirt.com/articles/20130507/21473422998/ea-says-its-going-to-keep-using-manufacturers-guns-its-games-its-just-done-asking-permission.shtml>
- *EA v. Textron* (Bell helicopters in *Battlefield 3*) settled confidentially, **dismissed with
  prejudice 20 May 2013** — no adverse ruling. Since 2013, Activision, Take-Two, Bethesda,
  PUBG Corp and Epic have followed EA's non-licensing approach.
  <https://rowan.legal/en/the-use-of-trademarks-in-video-games-in-light-of-current-case-law/>

**The 2023 wrinkle you must not miss.** *Jack Daniel's Properties v. VIP Products*, 599 U.S. ___
(2023) **narrowed** *Rogers*: it does not apply when the defendant uses the mark *"as a
designation of source for the infringer's own goods."* <https://supreme.justia.com/cases/federal/us/599/22-148/>,
<https://www.skadden.com/insights/publications/2023/06/supreme-court-sharply-limits-applicability>.
The decision **left *Rogers* intact for genuinely expressive works**, so an in-game weapon named
"AK-74u" is still on the *Rogers* side of the line. The line it moved is **titles, branding and
marketing** — naming your *game* after someone's mark, or putting their logo on your store page,
is now materially worse off than it was in 2020.

**Practical read:** in-game firearm names and shapes are the *least* of this project's exposure.
Note that "AK-47"/"Kalashnikov" and "Glock" are actively-policed marks whose owners send letters
regardless of the case law, and a solo developer's cost is the letter, not the verdict.

#### C3. Perk jingles — the highest-risk item, and re-synthesis does not save you.
**Tier 1 (statute) + Tier 3 (practitioner sources), corroboration 3.**

Every recorded track carries **two** copyrights: the **musical composition** (melody, harmony,
lyrics, arrangement) and the **sound recording**. Re-synthesising a jingle from scratch creates
a new sound recording and leaves the composition copyright fully infringed. This is the same
reason an unauthorised cover version infringes.
<https://scarincihollenbeck.com/law-firm-insights/sound-recording-and-musical-composition-difference>

The § 115 compulsory mechanical licence — the mechanism that lets anyone record a cover without
asking — **does not reach video games at all.** 17 U.S.C. § 101 (Tier 1,
<https://www.law.cornell.edu/uscode/text/17/101>) defines:

> **"Phonorecords"** are material objects in which sounds, **other than those accompanying a
> motion picture or other audiovisual work**, are fixed by any method now known or later
> developed…

§ 115 licenses the making and distribution of *phonorecords*. Music synchronised to an
audiovisual work is by definition not a phonorecord, so it requires a **synchronisation
licence**, which is **voluntary** — the rights holder can simply refuse, at any price.
Practitioner sources are unanimous that a cover is not fair use and that a mechanical licence is
required even for a re-recording:
<https://attorneyatlawmagazine.com/public-articles/intellectual-property/myth-cover-songs-are-copyright-fair-use>,
<https://ipwatchdog.com/2025/04/07/no-infringement-intended-can-band-cover-famous-song-look-copyright-law-music/>

**Settled.** Do not recreate the Juggernog/Speed Cola/Double Tap/Quick Revive jingles, in any
form, by any method. Write original 8–12 note motifs — you already have the synthesis engine to
play them, and the browser ancestor already had a 12-note `boxOpen` melody of its own
(html:527–534, per the gap analysis) that appears to be original.

#### C4. Trademarked names in fan works — the practical boundary is enforcement, not doctrine.
**Tier 3, corroboration 3.**

- <https://odinlaw.com/blog-fan-games-legal-risks/>: *"Copyright protects the code, characters,
  story, dialogue, art, and music. Trademarks cover names, logos, and symbols…"*;
  *"Any fan project that uses these elements without permission may infringe, **regardless of
  whether it is distributed for free**"*; *"fair use is not permission granted in advance; it is
  a defense raised after infringement is alleged"*; *"fan games often copy characters, settings,
  music, and other substantial parts of the original, [so] fair use arguments are rarely
  successful."* Precedents cited: Pokémon Uranium and AM2R, both DMCA'd by Nintendo. The
  article's practical advice is *"consider rebranding projects as original IP"*, and it is
  notably **silent on disclaimers** — i.e. the README's "not affiliated with Activision"
  paragraph is good manners, not a defence.
- **Activision specifically enforces, and specifically on Zombies content.** In 2023 Activision
  issued DMCA notices against *Call of Duty*-themed Fortnite Creative 2.0 maps — including
  Zombies maps — causing at least one creator to delete their maps and associated posts.
  <https://gamerant.com/fortnite-creative-call-of-duty-maps-dmca-takedown/>,
  <https://wccftech.com/activision-is-reportedly-issuing-dmca-strikes-against-call-of-duty-map-recreations-in-fortnite/>
  Activision has also C&D'd fan clients (SM2, X-Labs, BOIII).

**What is settled:** game *mechanics, rules and systems* are not copyrightable — the HP curve,
the points economy, the round structure, the perk effects and the PaP multipliers are all fine.
The README already says this and is correct.
**What is settled the other way:** *names* — "Juggernog", "Speed Cola", "Double Tap",
"Quick Revive", "Pack-a-Punch", "Mystery Box", the twelve PaP weapon names — are Treyarch marks
and carry real takedown risk on a live public URL under your real name. So do specific *map*
recreations (Kino der Toten geometry) and any announcer line lifted verbatim.
**What is genuinely uncertain:** whether Activision would bother with a solo Godot demake. The
observed pattern is that they act on high-visibility recreations. There is no reliable way to
predict this, and a DMCA on your personal GitHub account carries a strike, not just a takedown.

**The risk-avoiding option is free here.** Renaming four perks, one machine, one box and twelve
guns is a `scripts/data/weapons.gd` + `PERKDEF` diff of well under a hundred lines. Original
names — "Ironhide", "Quickhands", "Twinfire", "Second Wind"; "The Reforge" for Pack-a-Punch —
cost nothing, lose nothing mechanically, and remove the single largest category of exposure in
one commit. **Do it before the audio and art work lands**, because every jingle, announcer line,
chalk plaque and HUD badge you author afterwards bakes the name in deeper.

#### C5. What a correct LICENSE + NOTICE pair looks like here.
**Tier 1 (REUSE spec, Godot API verified by execution).**

The project mixes three provenance classes, and they need three different treatments:

| Class | Examples | Treatment |
|---|---|---|
| Original code | `scripts/`, `tools/gen/` | **MIT** (or Apache-2.0 if you want an express patent grant) |
| Your own procedurally-generated art & audio | `assets/`, everything `tools/gen/` emits, all `sfx.gd` output | **CC0-1.0** or **CC BY 4.0** — you authored the generator, so you hold it |
| Third-party CC assets | any Quaternius/Kenney/Sonniss/Freesound file | keep original licence, record it per-file |

Recommended layout, following the **REUSE Specification 3.3**
(<https://reuse.software/spec-3.3/>, Tier 1):

```
LICENSE                 -> MIT, with a scope note naming which directories it covers
LICENSES/
  MIT.txt
  CC0-1.0.txt
  CC-BY-4.0.txt         (only if you actually ship a CC-BY asset)
REUSE.toml              -> bulk annotations for assets/ and third_party/
NOTICE                  -> human-readable attributions + the trademark disclaimer
THIRD-PARTY.md          -> table: path | source URL | author | SPDX id | date retrieved
```

REUSE rules that matter: *"The `LICENSES/` directory MUST NOT include any other files"*, and
every SPDX identifier used anywhere must have a matching licence file in it. Source files get
a header comment carrying *"one or more Copyright Notices and one or more `SPDX-License-Identifier`
tag-value pairs"*. `REUSE.toml` (which superseded `.reuse/dep5` in spec 3.2) is the right place
to record download URLs for third-party files. `reuse lint` runs in CI in a few seconds and will
tell you the moment an unlicensed file lands.

**Do not hand-write the engine attributions.** Verified by execution in Godot 4.7 this session:

```
license_text_len=1149
first_line=Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
copyright_entries=102        # Engine.get_copyright_info()
license_info_keys=19         # Engine.get_license_info()
sample_components=["Godot Engine", "Bullet Continuous Collision Detection and Physics Library",
                   "Linux AppStream Metadata File", "Godot Engine logo", "Betsy"]
```

Build the in-game credits screen from `Engine.get_copyright_info()` / `get_license_info()` /
`get_license_text()`. It is 102 entries you would otherwise get wrong, and it stays correct
across engine upgrades for free.

**The `NOTICE` file should carry the trademark disclaimer**, moved out of the README where it
currently lives (README lines 126–134), and it should say that the names are being replaced —
or, once C4 is actioned, that the project uses no third-party marks at all, which is a far
stronger position than a disclaimer.

---

## Recommendations for this project

**R1 — Build `tools/gen/` as a Node ESM/CJS project using `@napi-rs/canvas`. (a)**
Extract `kriegsnacht.html` 374–392 + 564–1450 into `tools/gen/lib/` modules preserving order,
add the two-line `document` shim, and add a `render.js` that writes every strip into
`assets/sprites/` and `assets/props/`. Measured: 244 ms, 0.098 % visibly-different pixels, 37 MB
of `node_modules`, no native toolchain. Commit a `tools/gen/README.md` recording the extraction
line ranges so the provenance never gets lost again. Justified against the constraints: no
runtime cost, no shipped dependency, no art budget, and the output is byte-stable across
rebuilds because `_seed` is deterministic.

**R2 — Fix `makeChalk`'s font before generating anything. (a)**
`'6px ui-monospace, monospace'` is machine-dependent. Replace with a hand-rolled 5×7 bitmap font
in `tools/gen/lib/font.js`. This costs an hour, matches the art style better than a system font,
makes CI regeneration reproducible, and removes a font licence from `NOTICE`.

**R3 — Add `yaw` to `zombieBody`, not a skeleton. (a) + gap-analysis T1.0**
The gap analysis already recommends staying on billboards with 8-direction facing and defers to
this report on whether a free rigged source exists. It does (B1, CC0) — but the constraints kill
it anyway: `gl_compatibility` on single-threaded WebGL2 running 24 skinned humanoids, with no
threads for background loading and shader compilation on the main thread mid-gameplay, is a
performance risk that a billboard atlas does not carry. **Confirmed recommendation: 8-direction
billboard atlas, generated by R1.** Revisit rigged meshes only if the T0.7 web perf baseline
shows real headroom.

**R4 — Keep the synthesiser. Buy at most six samples. (b)**
Do not build a 108-file sample library. Keep `sfx.gd` as the base layer; add a small CC0-only
set for a convolution tail and mechanical foley. If you add samples: **WAV for short SFX, MP3
(not Ogg) for anything long**, per Godot 4.7's own web guidance. Budget impact of the full
library would have been 0.6–1.3 MB, which is affordable — the reason not to do it is CPU decode
on a single main thread plus 108 rows of licence bookkeeping, not bytes.

**R5 — Announcer: Kokoro-82M, rendered offline at build time to WAV, then processed. (b)**
Apache-2.0 weights, curated training corpus, no output restriction, 82 M params so it runs on
your machine in seconds. Avoid Piper's `lessac` voices entirely — the Blizzard 2013 corpus is
research-only by its own licence text. Render at build time, commit the processed files, ship
no model. Then measure whether it survives the processing chain (see below).

**R6 — Rename the trademarks in the next commit, before any audio or art work. (c)**
Four perks, Pack-a-Punch, Mystery Box, twelve PaP weapon names. Under 100 lines. This is the
single highest-value legal action available and it is free. Keep the real firearm base names
(AK-74u, MP40, RPK) — those are the settled, low-risk end of the spectrum per C2.

**R7 — Write original perk jingles. (c)** Non-negotiable per C3: there is no compulsory-licence
path for music in an audiovisual work, and re-synthesis reproduces the composition. Use the
existing synth to play 8–12 note original motifs in the same *role* (a rising four-note sting on
purchase) without reproducing the same *melody*.

**R8 — Land the licensing scaffold this week. (c)**
`LICENSE` (MIT, scoped), `LICENSES/`, `REUSE.toml`, `NOTICE`, `THIRD-PARTY.md`, `reuse lint` in
CI, and a credits screen driven by `Engine.get_copyright_info()`. Every asset added before this
lands is an asset whose provenance you will have to reconstruct later — which is exactly the
situation `tools/` is in right now.

---

## Coverage gaps

1. **Mixamo FAQ, primary URL.** `https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html`
   timed out at 60 s. The quoted licence wording in B3 comes from Adobe's own community FAQ
   mirror (`community.adobe.com/t5/mixamo-discussions/...td-p/13234775`), which is Adobe-hosted
   but user-posted. **Verify the "limited duration technology preview" wording against
   helpx.adobe.com before relying on it.** It is the load-bearing sentence in B3.
2. **Mixamo 2026 service health.** Single Tier-3 source (Cinevva) for the June-2025 auth-backend
   outage claim. Not independently corroborated. Directional only.
3. **Universal Animation Library 2 licence.** I confirmed CC0 for UAL 1 and for the Animated
   Zombie Pack directly. UAL 2 — which is the pack that actually carries zombie locomotion — I
   only saw referenced from UAL 1's page. **Check its itch.io licence field before downloading.**
4. **Quaternius Animated Zombie Pack file formats.** The pack page lists FBX/OBJ/Blend. The
   itch.io mirrors of other Quaternius packs also carry GLB. I did not confirm whether a GLB
   exists for this specific pack.
5. **Copyright Office Circular 73.** The PDF fetched but the fetch tool could not extract the
   definitional passages. The § 101 phonorecord definition in C3 is quoted from Cornell LII,
   which is authoritative for statutory text; the § 115-does-not-reach-audiovisual conclusion
   follows from that definition plus § 115's own scope, and is corroborated by practitioner
   sources — but I did not read a Copyright Office statement saying it in those words.
6. **The "GPL output is not GPL" point (B9).** This is reasoning from the GPL's scope, not a
   retrieved FSF FAQ entry. Tier 4. Verify before relying on it — though it is moot if you take
   R5 and use Apache-2.0 Kokoro.
7. **Sonniss bundle contents.** I confirmed the licence terms (Tier 1) but did not enumerate
   what firearm content the 2024–2026 bundles actually contain, or their download sizes.
8. **GitHub ToS section H.** The canonical ToS URL returned 404 (page has moved). The
   "view and fork" characterisation in C1 is quoted from choosealicense.com, which is
   GitHub-operated, but is a paraphrase of the ToS rather than the ToS itself.
9. **Non-US jurisdictions.** Everything in part (c) is US law. *Rogers* and § 115 have no direct
   EU/UK analogue; the EU has no fair use doctrine at all. If you are not in the US, most of C2
   does not transfer.
10. **No lawyer read any of this.** For a project deployed under your real name, C4's
    "rebrand to original IP" advice is the one recommendation that makes the lawyer question
    moot, which is why it is R6.

---

## What must be measured rather than researched

### M1 — Node-vs-Blink rasteriser divergence, if you want the existing 17 strips preserved
**Why:** A2 measured 0.098 % visibly-different pixels on `zombie0_walk.png`. That is one
sprite. Crawlers, hounds, perk machines and the PaP machine use different primitive mixes
(`ellipse` at different radii, `globalAlpha` compositing, `strokeRect`) and may diverge more.

**Procedure:**
1. Extend `tools/gen/render.js` to emit all 17 strips plus the 16 prop PNGs to a scratch dir.
2. Run the diff harness from this session (`@napi-rs/canvas` `loadImage` → `getImageData` →
   per-channel max delta, histogram at bucket 32) against every committed file in
   `assets/sprites/` and `assets/props/`.
3. **Threshold:** accept if for each file, pixels with any-channel delta > 32 are < 0.5 % of the
   image *and* no such pixel forms a contiguous run of ≥ 3 along a silhouette edge (a broken
   rim reads as a visible notch at 48×64).
4. Any file that fails: capture it via Playwright + Chromium instead and commit the capture. Do
   not mix approaches per-file silently — record which files came from which path in
   `tools/gen/README.md`.

### M2 — SFX bake time on the main thread in the *exported web build*
**Why:** `sfx.gd` synthesises every sound at startup, in GDScript, sample by sample, on the only
thread there is. On native this is invisible. On WebAssembly in a browser it is a hard stall
before the first frame, and threads cannot be turned on. **No number for this exists anywhere in
the repo.** This is the single measurement that decides B8 — if the bake costs 2 s of white
screen, the argument for shipping samples strengthens sharply.

**Procedure:**
1. In `Sfx._ready()`, wrap the bake loop: `var t0 := Time.get_ticks_usec()` … `print("sfx_bake_ms=", (Time.get_ticks_usec()-t0)/1000.0)`.
2. Export to web, deploy to the real GitHub Pages URL (not a local server — the CDN and the
   `.pck` transfer are part of the number).
3. Measure on **median hardware**, not the RTX 5090 the README's 6.06 ms figure came from.
   Chrome desktop mid-range, and one mobile Chrome device.
4. Read `sfx_bake_ms` from the browser console. Also capture `performance.now()` from page load
   to first rendered frame.
5. **Decision rule:** < 150 ms → keep pure synthesis, close the question. 150–500 ms → keep
   synthesis but bake lazily on first use per sound, or move the bake behind the existing
   click-to-start gate. > 500 ms → precompute the WAVs at build time with a `--headless` Godot
   script and commit them; you keep zero third-party licences and pay bytes instead of stall.

### M3 — Does TTS survive the announcer processing chain?
**Why:** unfalsifiable by research. The question is whether ring modulation amplifies or masks
TTS artefacts, and that depends on the specific voice and the specific chain.

**Procedure (about 30 minutes):**
1. Render 5 lines through Kokoro-82M at 24 kHz — pick prosodically hard ones:
   `"Round eight"`, `"Pack-a-Punch"` (or its replacement), a long one, a one-syllable one, and
   one with a plosive-heavy start.
2. Also render the same 5 lines through any second engine you have, as a control.
3. Apply the chain in ffmpeg or Audacity, in this order, capturing after each stage:
   `asetrate` pitch-shift −6 semitones → ring-mod against a 45 Hz sine (`amultiply` or an LFO on
   a tremolo at audio rate) → bandpass 300–3400 Hz → light bitcrush → normalise.
4. **Listening test:** can you identify the words at −20 dB relative to the game's gunshot bus,
   with 12 zombies groaning? Intelligibility under mix, not in isolation, is the pass criterion —
   an announcer that is unintelligible during a round is worse than no announcer.
5. **Also check:** the ring-mod sidebands of a 24 kHz source alias badly when resampled to
   22 050 Hz to match `sfx.gd`'s `RATE`. Render at 44.1 kHz, process, then resample last.
6. If it fails: fall back to non-verbal announcer cues (the round-change stinger the ancestor
   already had at html:527–534) plus on-screen text. That is a legitimate design answer and it
   costs zero licences.

### M4 — Actual Ogg/MP3/WAV decode cost with 10 concurrent voices on WebGL2
**Why:** B7's Godot-docs guidance (*"significantly more processing power"*, MP3 preferred on
web) is qualitative. Whether it matters at your voice count is a number.

**Procedure:** extend `scripts/perf_probe.gd` — which already ramps 0/6/12/18/24 zombies and
samples five seconds of frame times — to additionally fire N concurrent one-shots per second in
each of three builds (all-WAV, all-Ogg-q4, all-MP3). Run in the **exported web build**, commit
the CSV. Compare `frame_ms` p99, not mean; audio decode stalls show up in the tail.
