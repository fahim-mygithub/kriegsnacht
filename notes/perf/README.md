# Measurements

Raw probe output lives beside this file as `<mode>-<timestamp>.json`, written by
`tools/perf_collector.py`. `scripts/perf_probe.gd` produces it; it ships in no
build (`tools/build.ps1 -Perf` registers it as an autoload for the duration of
one export and takes it out again, and `tools/perf_native.ps1` does the same for
the duration of one native run). Capture modes also write PNGs, to
`notes/perf/shots/`.

Every budget in `notes/research/SYNTHESIS.md` §2 was an estimate. This file
records which of them are now measured, and — more importantly — which are not.

---

## How to read anything below

**Three buckets, and confusing them is the failure mode this file exists to
prevent.** A measurement taken in the wrong one still produces a number, and the
number still looks like an answer.

| Bucket | What it can answer | What it cannot |
|---|---|---|
| **Headless native** (`--headless`) | CPU work: the physics server, integer sweeps, anything the probe times itself | Anything about a frame. `draw_calls` is 0, `video_mem` is 0, and the frame time is pinned near **6.9 ms** by Godot's low-processor sleep regardless of load |
| **Windowed native** | *Structural* facts about `gl_compatibility`: does the draw count jump when a second light casts, does that shader build at all, which sign is upright, does per-instance colour reach the fragment | Milliseconds you can hold a budget against. This is a desktop GL driver on this machine's GPU, not WebGL2 on a stranger's laptop |
| **Exported web build, focused tab** | Everything, and it is the only bucket that is authoritative for a budget | Nothing — but it needs a human at a visible, focused tab |

**A background tab reports *nothing*, not *slow*.** Chrome suspends
`requestAnimationFrame` in a hidden tab, so an automated run produces a
`started` event and then no stages at all. The numbers are absent, not
pessimistic. Every web row below has to be taken by a person with the tab in
front of them.

**A windowed native run is vsynced unless something turns vsync off.** It pins
every frame at 16.67 ms, which is the same shape of lie as the headless 6.9 ms
and much harder to spot because it looks like a plausible frame time. The probe
disables vsync and uncaps `Engine.max_fps` in `begin()`. If a native row comes
back at exactly 16.67 ms, that code did not run.

**On a `flow` row or a capture row, ignore the frame-time columns.** The 200-solve
batch and the viewport readback both block for tens of milliseconds, and that
stall lands in the next frame's delta. Those rows are read from their own
`flow_*` / `vm_*` / `mm_*` / `sc_*` / `bb_*` fields. On a `warm` row the opposite
holds: the spike *is* the measurement.

**Every row carries its own configuration** in the `env` block: renderer,
driver, display server, physics server class, render scale, MSAA, shadow atlas
size, whether the torch casts, whether SSAO and the LUT are on, whether the
warm-up pass was disabled, whether the render-scale governor was frozen, and the
camera FOV. A row without its configuration is not a measurement — this project
has committed a wrong-labelled table twice.

**The render-scale governor is frozen for the duration of a probe run, and
`render_scale` is stamped on every row as well as in `env`.** `quality_governor`
demotes after one 1.4 s window under 38 fps and promotes after three over 58, and
a ladder takes minutes — so left running it can render stage 1 at scale 1.0 and
stage 4 at 0.75 and report one number for both. `perf_probe.begin()` takes the
governor out of the frame loop (`set_process(false)`, exactly what
`quality_governor._ready()` already does for `--shot` and `--verify`) and records
`env.governor_frozen`. **If `governor_frozen` is false, or if the per-row
`render_scale` column is not constant down a ladder, the rows are not comparable
to each other.**

---

## Milestone 2 triage — where each of the twelve can actually be answered

| # | Bucket | Apparatus | Status |
|---|---|---|---|
| **M-WARM** | web (native = floor only) | `-Mode warm`, A/B pair | apparatus built, **not run** |
| **M-SHADOW** | windowed native for structure, web for budget | `-Mode shadow` | apparatus built, **not run** |
| **M-SHADOW2** | windowed native | `-Mode shadow`, last row | apparatus built, **not run** |
| **M-SSAO** | web for budget, native for structure | `-Mode ssao` + `--no-post-fx` A/B | apparatus built, **not run** |
| **M-VMFOV** | windowed native **and** web — both required | `-Mode vmfov`, PNG + centroid readback | **ANSWERED natively**, web still open |
| **M-VMCLIP** | neither — it is a `verify.gd` assertion | `verify.gd` `_viewmodel()` | **ANSWERED** — 0.2319 m against `Player.RADIUS` 0.24 |
| **M-BILLBOARD** | windowed native | `-Mode billboard` | apparatus built, **not run** |
| **M-SHADOWCAST** | windowed native | `-Mode shadowcast`, two-frame diff | apparatus built, **not run** |
| **M-MMCOLOR** | native provisional, web authoritative | `-Mode mmcolor`, A/B strips | apparatus built, **not run** |
| **M-PARTICLES** | web for the ceiling, native for the shape | `-Mode particles` — **GPU path only** | apparatus built, **not run**; the CPU-vs-GPU half has none |
| **M-FLOW** | headless native, **and** the same mode on web | `-Mode flow` | **ANSWERED natively**, web still open |
| **M-SEP** | headless native | `-Mode sep` | **ANSWERED** |

Three of these are worth reading twice.

**M-FLOW is genuinely answerable headlessly, and it is also genuinely answerable
on the web with the same code** — `?mode=flow`, same mode, same probe. There is
no frame in it, so the headless number is real work rather than a sleep target.
Run both and record the ratio; nothing else in this project has a measured
native-to-wasm ratio for anything.

*Corrected while reviewing this file:* an earlier draft claimed the sweep is
"integer arithmetic over a `PackedInt32Array` with no allocation", which would
have made the native number nearly a translation of the web one. It is not.
`FlowField.solve()` writes its distances into a `PackedInt32Array` but drives the
wavefront off `var q: Array[int] = [start]` and grows it with `append()`, up to
one entry per open tile — so each solve is a heap allocation and a GDScript
`Array` reallocation as well as integer work, and single-threaded wasm is under
no obligation to keep the same ratio on either. **The native number is a lower
bound. The web number is the answer.**

**M-VMCLIP has no apparatus and will not get a fake one.** SYNTHESIS §5 asks for
a unit test that every viewmodel mesh corner is within 0.22 m of the camera
origin. There is no viewmodel mesh in this checkout — it is being built in
another package — and `scripts/dev/verify.gd` is not this package's file. The
assertion is specified below, in words precise enough to implement, and that is
all this package can honestly deliver for it.

**M-PARTICLES answers half its SYNTHESIS row.** The emitter ceiling is measured;
the `CPUParticles3D` vs `GPUParticles3D` comparison the row also asks for is not,
and no mode pretends to. Building it would mean rebuilding the blood effect on
`CPUParticles3D` for the benchmark, and a version built for the benchmark is not
the version that ships — which is precisely why this mode clones the shipped
emitter instead of authoring one. The reasoning and the trigger for revisiting it
are in the M-PARTICLES section.

---

## Corrections to SYNTHESIS §5, found while building the apparatus

Four of the twelve rows describe a codebase that has since changed, or state
something the renderer research contradicts. Following them literally would have
produced measurements of the wrong thing.

**1. M-SHADOW's "draw calls should be flat across all four" is wrong at the
off→on step.** `R1-renderer-constraints.md` F6 quotes `_fill_render_list`
directly: a light *with* a shadow is pushed to `inst->light_passes`, and only a
light *without* one goes in the base pass. So every shadow-casting light adds
one full additive re-draw of every instance it touches, plus the shadow map
render itself. Draw calls should be flat **across the three enabled
resolutions** — 512/1024/2048 change the map size, not the number of draws — and
should **rise** from off to on. If they do not rise, the torch is not actually
casting or nothing is inside its cone, and the ladder is measuring nothing.
Note also that the shipped build already sets `_torch.shadow_enabled = true` in
`Player._ready()`, so the "off" row is the counterfactual and the "on" rows are
the status quo.

**2. M-SEP's decision rule has already been acted on.** It reads: *"If p90 >
~0.4 (×2.4 ≈ 1.0, equal to the unit flow vector), §4.5 item 3 is mandatory."*
Item 3 — the clamp — is in: `Zombie.SEPARATION_LIMIT` is `0.6` and
`Zombie._separation()` ends `return push.limit_length(SEPARATION_LIMIT)`. So
`_separation()` can no longer exceed 0.6 by construction, and logging its length
would measure the clamp rather than the pressure on it. The probe therefore
records **both**: the raw pre-clamp sum (recomputed from `zombie.gd`'s own
constants) and the fraction of samples where the clamp actually bound. The
question has changed from *"is the clamp mandatory"* to *"is the clamp
load-bearing, and is 0.6 the right number"* — which is a better question and the
same apparatus answers it.

**3. M-VMFOV's "editor (Forward+ **and** Compatibility)" is no longer possible
without editing a committed setting.** `project.godot:145-147` pins
`renderer/rendering_method` to `gl_compatibility` on every platform, which was
the M1.0 gate item. The Forward+ half of that comparison is gone unless someone
temporarily unpins it. That is a fair trade — the whole point of pinning was to
stop authoring against a renderer that never ships — but the row's procedure
should not be read as still available.

**4. M-SSAO's "toggle `ssao_enabled` with a debug key" would measure the wrong
thing and is also against §1.1.** Every combination of glow / BCS / SSAO /
colour-correction is a separate specialisation of `post.glsl`, and WebGL2 has no
program-binary API, so a runtime toggle is a full-screen GLSL compile on the
main thread mid-frame. `quality_governor.heavy_post()` answers it once before
the first frame for exactly that reason. The probe's `ssao` ladder does toggle,
but only across a full settle so the recompile lands outside the window — and
the *shipping* A/B already exists as `--no-post-fx` natively / `?post=off` on
web, which is a build-time decision and therefore the honest one.

---

## The twelve, in detail

Each section is: what the question is, the exact command, and what to look for.
Nothing below has been run — the numbers are the next person's job.

### M-WARM — does the shader warm-up pass actually remove the first-draw hitches?

```
pwsh tools/perf_native.ps1 -Mode warm      # floor only; see the caveat
```
```
pwsh tools/build.ps1 -Perf
python tools/perf_collector.py build/perf
#   http://127.0.0.1:8970/index.html?mode=warm            (warm-up ON)
#   http://127.0.0.1:8970/index.html?mode=warm&warm=off   (warm-up OFF)
```

Seven stages, one first-draw event each, fired at the top of a 1 s window so the
spike cannot land in the settle and be thrown away: `baseline`, `shot`, `flesh`,
`caster`, `death`, `wall`, `metal`. The two wall stages come last because they
teleport the player to stand in front of a wall of the right texture — a burst
fired at a wall across the map is occluded, and a fragment that never rasterises
compiles no fragment stage, so the measurement would report "already warm" for a
shader that had never been drawn.

**Read `worst_ms`, never `mean_ms`.** This is a stutter measurement; averaging is
the thing that hides it.

**The measurement is the difference between the two passes.** With the warm-up
on, no stage's `worst_ms` should exceed ~30 ms. The `warm=off` pass skips *both*
`warm.warm(...)` and `fx.warm()`, so every stage is a candidate to spike, not
only the two things `shader_warmup.gd` structurally cannot reach (the particle
*process* shaders and the MultiMesh *instanced* draw variant). How much each one
spikes is the value of the warm-up pass stated as a number, per material family.

**One trigger SYNTHESIS names is missing, and cannot exist.** The row asks for
"first shadowed light" in isolation. `Player._ready()` sets
`_torch.shadow_enabled = true` before the first frame, so the shadowed-light
specialisations of every world material are compiled during load whatever the
warm-up pass does; there is no later moment at which a light first casts. The
`caster` stage is the nearest thing — the first time a *sprite* enters the cone —
and it is labelled as that rather than as the row's wording.

**This one measurement needs a change outside the probe.** `main.gd` builds the
warm-up pass unconditionally, so there is nothing to turn off. The A/B needs a
`--no-warmup` / `?warm=off` check around `warm.warm(...)` and `fx.warm()`,
mirroring `quality_governor`'s existing `--no-post-fx` / `?post=off`. Until that
lands, **both passes of `-Mode warm` are the same run** — the probe records the
flag in `env.warmup_disabled`, so a JSON with `warmup_disabled: true` and no
change in `worst_ms` means the wiring is missing, not that the warm-up pass does
nothing. `perf_native.ps1` greps `main.gd` for `_warmup_disabled` before running
this mode and prints a `!!` block if it is absent, so the inert case announces
itself rather than being inferred from two identical tables afterwards.

**Caveat that makes the native run a floor rather than an answer.** Godot
compiles `_load_from_cache`/`_save_to_cache` out under `#ifdef WEB_ENABLED`, so
desktop keeps a shader cache and a second native run starts warm. The harness
deletes `user://shader_cache` before each `warm` pass; the graphics driver's own
program cache is not ours to clear. Only the browser is genuinely cold every
time, which is the entire reason the warm-up pass exists.

### M-SHADOW — what does the torch shadow cost?

```
pwsh tools/perf_native.ps1 -Mode shadow
#   web: http://127.0.0.1:8970/index.html?mode=shadow
```

Five rows at 24 zombies: torch shadow off, then on at atlas 512 / 1024 / 2048,
then 2048 with one room omni also casting (that last row is M-SHADOW2). The
atlas is set through `Viewport.positional_shadow_atlas_size`, which is a runtime
property — the project setting of the same name is only read at startup.

Look at `draw_calls` and `objects` first and frame time second. Per correction 1
above: **flat across 512/1024/2048, higher than the off row.**

**Decision rule (SYNTHESIS §5, unchanged):** take the largest resolution within
1.0 ms of shadows-off at 24 zombies. If even 512 costs more than 1.5 ms, the
flashlight shadow is not affordable and the fallback is `world_builder`'s
per-vertex AO bake alone. Take that 1.0 ms from the **web** run.

### M-SHADOW2 — does a second shadowed light really double geometry cost?

The last row of `-Mode shadow`. One `OmniLight3D` (`lighting._lamps[0]`) gets
`shadow_enabled = true` on top of the torch. An omni in CubeMap mode is six
shadow renders to a spot's one, and Dual Paraboloid `ERR_FAIL`s outright, so one
omni is already the expensive case.

Read `draw_calls`, `objects` and `primitives` together, and frame rate last. The
probe records all three because **which of them an additive pass increments is
not something this project has verified.** SYNTHESIS §5 says watch
`RENDER_TOTAL_PRIMITIVES_IN_FRAME`; R1 F6's `_fill_render_list` quote predicts a
whole extra *draw* of every instance the second light touches. Those are
consistent if the counters are incremented per pass and inconsistent if they are
incremented per instance, and nobody here has read that part of the GLES3
renderer. So:

- All three rise on the omni row → the one-shadowed-light rule is confirmed on
  this hardware and can stop being thought about.
- `draw_calls` rises and the other two do not → the counters are per instance,
  not per pass. Read the ladder off `draw_calls` and say so in the result.
- Nothing rises → the omni is not actually casting, or nothing it reaches is in
  frame. Check `env.shadow_atlas` and look at a `--shot` before concluding
  anything about cost.

### M-SSAO — what do SSAO and the colour LUT cost, separately?

```
pwsh tools/perf_native.ps1 -Mode ssao
#   web: http://127.0.0.1:8970/index.html?mode=ssao
```

Four rows at 24 zombies: neither, SSAO only, LUT only, both. Splitting them
matters because `quality_governor.heavy_post()` gates them together, so a single
combined number cannot say which half to drop if the budget is missed.

Read `process_ms` and `median_ms`. Budget: ≤2 ms for the pair.

**Check `env.lut_enabled` before believing the LUT half.** `lighting.gd` only
assigns `adjustment_color_correction` when `quality_governor.heavy_post()` says
yes, so a session that inherited a demotion — or any run with `--no-post-fx` —
has no LUT to toggle, the "lut" rows are byte-for-byte the "plain" rows, and a
flat pair reads as "the LUT is free" rather than "the LUT was never on". The
probe posts a `warn` event when it finds nothing to put back; `perf_native.ps1`
prints warn lines with `!!`, so it will be on screen.

**Do not sweep `half_size`, `blur_passes`, `fadeout_*` or `adaptive_target`.**
They are silently discarded by `environment_set_ssao_quality` in Compatibility
(R1 F3a); sweeping them measures a flat line and invites the wrong conclusion.
Only `ssao_intensity` (×2.0) and `ssao_radius` (×0.5) are live, and neither
changes the cost.

**The visual half needs no new code.** SSAO is applied as `color.rgb *=
s4ao(UV)` on the fully composited, post-glow image, so it darkens emissives, the
muzzle flash and the bloom itself. The before/after frames R1 asks for are:

```
"$env:USERPROFILE\Godot\Godot_v4.7-stable_win64_console.exe" --path . --shot shots/post_on.png 0
"$env:USERPROFILE\Godot\Godot_v4.7-stable_win64_console.exe" --path . --shot shots/post_off.png 0 --no-post-fx
```

Compare a lamp fixture, the Pack-a-Punch glow and a zombie's eyes across the
pair. If AO is eating the emissives, lower `ssao_intensity` rather than
disabling it.

### M-VMFOV — does the vertex-only `PROJECTION_MATRIX` override behave, and what is the `[1][1]` sign?

```
pwsh tools/perf_native.ps1 -Mode vmfov
#   web, one sign per URL so a person can hold each on screen:
#   http://127.0.0.1:8970/index.html?mode=vmfov&sign=0
#   http://127.0.0.1:8970/index.html?mode=vmfov&sign=1
#   http://127.0.0.1:8970/index.html?mode=vmfov&sign=-1
```

**Both runs are required.** The community shaders disagree about the sign and
every one of them was written against Forward+; the Compatibility backend
renders to an OpenGL framebuffer with the opposite texture-space Y convention,
and whether it needs the same sign is not documented anywhere. Native tells you
what desktop GL does with the GLSL; only the exported build tells you what
WebGL2 does.

**The test mesh.** Four unshaded boxes at 0.15 m in front of the lens, sharing
one `Shader`, deliberately neither mirror-symmetric nor vertically symmetric:

| Marker | Where | What it answers |
|---|---|---|
| grey body | off-centre, 0.10 m deep, centred at 0.15 m | shape and scale, for the human |
| **red** | 0.042 m **right** of green, 0.034 m **below** it | mirrored? upside-down? |
| **green** | above the body | (the other half of the same pair) |
| **blue** | 0.08 m from the lens, on the body's **screen centre** | were the depth terms left alone? |

`y_sign = 0` leaves `PROJECTION_MATRIX` untouched. That is the reference frame,
through the same mesh and the same material, and it is what makes "mirrored" and
"upside-down" answerable rather than a matter of opinion.

**The blue marker's placement is not the obvious one, and the obvious one does
not work.** It is 0.08 m from the lens — in front of the body's front face at
0.10 m — but its x and y are the body's *scaled by 0.08/0.15*, because the
perspective divide is by z. A marker carrying the body's own offsets unchanged
projects 1.9× further from the optical axis and clears the body almost entirely,
leaving a fifteen-pixel sliver of overlap that proves nothing. Scaled, it lands
on the body's centre, and since both scale by the same factor when the override
is applied, the occlusion holds at every `y_sign`. That is what makes "blue
stopped covering the body" a statement about the depth terms — the one thing this
shader deliberately does not touch.

**What the probe reports, per row.** `rg_dx` and `rg_dy` (red minus green, in
pixels), `right_dx` and `top_dy` (red's and green's offsets from screen centre,
`top_dy` positive *downward* because image rows grow downward), `span_px`
(red-to-green distance), `blue_visible`, and the three marker pixel counts. Plus
a PNG per row in `notes/perf/shots/`.

**How to read it against the reference row (`y_sign 0`):**

- **`rg_dx` flips sign → mirrored. `rg_dy` flips sign → upside-down.** These are
  the two that decide it, and they are marker-to-marker rather than
  marker-to-screen-centre, so nothing that merely shifts the rig can move them.
  Upright and unmirrored, both are positive.
- `right_dx` and `top_dy` say where the rig *is*, which is what you compare the
  PNG against. Do **not** read the verdict off them: green's centre sits about a
  dozen pixels off the optical axis, so a translation can swamp its sign where it
  cannot touch `rg_dy`.
- `span_px` ÷ reference `span_px` should be `tan(74/2)/tan(55/2) = 1.448`
  (`expected_span_ratio` is computed from the live camera FOV, so it stays right
  if the FOV moves). Materially off → the override is scaling wrongly, not
  merely flipping.
- `red_px` or `green_px` = 0 → **the rig is not being drawn at all**, which is
  the third of the three outcomes and the one a sign flip cannot rescue.
- `blue_visible` false, or the blue marker stops covering the body's middle in
  the PNG → the override touched more than `[0][0]` and `[1][1]`.

**Decision rule (SYNTHESIS §4.1/§5).** Correct → ship the shader. Fixed by a
sign flip → ship it with the `uniform float y_sign` the viewmodel package is
already building behind. Wrong in any other way → drop the shader and tune mesh
scale at the native FOV of 74.

### M-VMCLIP — does the geometric no-clip guarantee hold?

**No apparatus, deliberately.** There is no viewmodel mesh in this checkout and
`scripts/dev/verify.gd` is not this package's file. What is needed is one
assertion and one manual pass:

*The assertion.* Build every weapon's viewmodel mesh, take the mesh AABB in
viewmodel-root local space, and assert that the distance from the camera origin
to the **furthest corner** of that AABB is `< 0.22`. The number is not arbitrary:
`Player.RADIUS` is `0.24`, so world geometry can never come
within 0.24 m of the camera origin, and 0.22 leaves 2 cm of margin. Assert per
weapon, and name the weapon in the failure detail — the whole value of this test
is that adding a long-barrelled gun (RPK, China Lake) fails loudly at build time
instead of clipping through a doorframe in front of a player.

*The manual pass.* Walk into every wall type, every door frame and every window
board at every look angle. **Interior convex corners are the adversarial case**,
because a capsule lets the camera get closer to a corner than to a flat wall.

### M-BILLBOARD — does `MAIN_CAM_INV_VIEW_MATRIX` compile here, and what does a custom billboard shader cost?

```
pwsh tools/perf_native.ps1 -Mode billboard
```

Three rows, 24 sprites each, identical texture, identical size, identical
positions — only the material path differs: `Sprite3D` with `BILLBOARD_FIXED_Y`
(the control), then the ~6-line tilt shader with `INV_VIEW_MATRIX`, then the same
shader with `MAIN_CAM_INV_VIEW_MATRIX`. The two shader rows are one `Shader`
resource each, so a cost row is not secretly 24 compiles of identical source.

**The compile half.** `bb_lit_px` counts bright pixels in the frame. A shader
that fails to build draws nothing, so: the two tilt rows must agree with each
other and both must be in the neighbourhood of the control. `0` on the
`MAIN_CAM` row means it did not build. The harness also greps stderr for
`shader` / `Compilation`, because a GLSL build failure under `gl_compatibility`
prints and then draws nothing — it does not throw and it does not set an exit
code.

**Why this now decides a switch rather than a ship.** `zombie.gd`'s rim shader
already took the conservative branch: it uses `INV_VIEW_MATRIX` and says so at
the header comment on `Zombie.RIM_CODE`, precisely because this measurement did
not exist. The two differ only during shadow and reflection passes, which an
additively-blended surface enters neither. So a pass here is permission to use
the built-in that Godot's own generated billboard code uses; a failure confirms
the existing choice was right and closes the question.

**The cost half** gates the vault/clamber tilt: `SpriteBase3D` billboard modes
overwrite `MODELVIEW_MATRIX` with a camera basis plus the model translation, so
a local Z roll is not ignored, it is *unrepresentable*. The tilt rows price the
only thing that can express it.

### M-SHADOWCAST — do alpha-scissor billboards cast shadows?

```
pwsh tools/perf_native.ps1 -Mode shadowcast
```

Two frames that differ in exactly one property: one zombie parked on bare floor
inside the torch cone, camera held still, torch shadow off then on. Every pixel
that got darker between them is something the shadow did. A single frame of a
sprite on a dark floor proves nothing, because a dark patch under a sprite is
also just a dark floor.

The caster is frozen three times over. `set_physics_process(false)` on the Zombie
stops it steering; `stop()` on its `AnimatedSprite3D`, which runs its own clock,
stops the pose cycling under it; and its **world position is decided once and
reused by the second stage** rather than re-derived from the camera, so the two
frames cannot differ by however far the camera drifted between them. Any one of
the three missing turns the diff into a picture of something other than a shadow.

The camera itself is left to settle rather than pinned. With no input,
`Player._update_view()` runs the bob at zero amplitude and the recoil spring at
rest, so the pose is genuinely static by the end of the settle — but that is a
property of the player code rather than something enforced here, and it is the
first thing to check if `sc_bbox` comes back covering half the frame.

Reported: `sc_darker_px`, `sc_darker_frac`, `sc_bbox` (the darkened region) and
`sc_caster_screen` (where the zombie is on screen). If the bbox extends
appreciably below or beside the caster, that is a cast shadow. `sc_darker_px` of
0 means no shadow at all, or the caster is outside the cone — check the PNGs
before concluding the first.

**The two PNGs are the real deliverable.** Material logic says this should work
(`ALPHA_CUT_DISCARD` is the alpha-scissor path, which supports shadow casting),
but the `Sprite3D` shadow issue history is long and every issue found was 3.x or
unresolved. A zombie's shadow thrown across a floor by a flashlight is, per unit
of effort, the single most CoD-Zombies-looking thing available — worth looking
at properly.

### M-MMCOLOR — does `MultiMesh.set_instance_color` reach the fragment?

```
pwsh tools/perf_native.ps1 -Mode mmcolor
#   web (authoritative): http://127.0.0.1:8970/index.html?mode=mmcolor
```

**The A/B, and why it is an A/B.** Two 32-instance strips carrying the same
ramp — hue across, alpha down — over an opaque mid-grey backdrop so the alpha
half blends against a known constant. Strip 0's material sets
`vertex_color_use_as_albedo`; strip 1's is identical and does not. A single
uniform strip could not distinguish *"the per-instance colour never reached the
vertex stream"* from *"the material was not told to read vertex colour"*, and
those have different fixes.

Sampled at each instance's projected centre. Absolute values are **not** compared
against what was written — they have been through FILMIC, glow, SSAO and the LUT
by the time they reach the framebuffer. What is compared is how many *distinct*
5-bit-quantised values came back, which is the part of the question that
survives grading.

| Result | Meaning |
|---|---|
| `mm_distinct_albedo` ≈ 32, `mm_distinct_no_albedo` = 1 | works, and the material flag is the gate. `fx.gd` is correct. |
| `mm_distinct_albedo` = 1 | **fails** — per-instance colour does not reach the fragment |
| anything else | read the PNG |

**Why this matters here specifically.** `fx.gd` has three ring buffers riding on
it — bullet holes, blood pools and tracers all call `set_instance_color` — and it
was written to degrade to a *wrong tint* rather than to *invisible*: the decal
materials leave `albedo_color` at white and put the whole falloff in the
texture's alpha, so a failure paints white splats rather than nothing. Confirmed
by reading `fx._decal_material()`, and it is why this is a measurement rather
than an
emergency. R1 F8 reads the GLES3 shader source and says colour and custom data
*are* in the vertex stream, unpacked as half floats — but that is a source read,
and desktop GL is not ANGLE, so **the web row is the one that decides.**

### M-PARTICLES — how many concurrent emitters fit in the budget?

```
pwsh tools/perf_native.ps1 -Mode particles
#   web (authoritative): http://127.0.0.1:8970/index.html?mode=particles
```

Emitter ladder 0 / 8 / 16 / 24 / 40 / 64, then two extra rows at 24: one with
`draw_order = VIEW_DEPTH`, one with the per-emitter `amount` doubled. The probe
builds its own emitters but clones the *shipped* blood emitter's process
material and draw mesh, so the shader and the particle behaviour are the game's
and only the counts differ — which is the whole point, since `fx.gd` fixes
`amount` deliberately (changing it reallocates the buffer).

**Held at 12 zombies, not 24, and that is a deviation.** SYNTHESIS §5 asks for
"the actual gameplay scene", and what that phrase is protecting against is an
empty-scene number — the real level, the real lighting, the real fill. Twelve is
a genuine round-5 horde. Twenty-four would put the frame near budget before the
first emitter runs, and every particle row would read as a crossing of the
threshold that the zombies had already crossed.

The shipped pools total **14** emitters (6 blood + 8 debris), so the ladder
brackets the status quo on both sides.

**Deliverable:** a hard constant. SYNTHESIS asks for
`MAX_CONCURRENT_PARTICLE_EMITTERS`; no such constant exists yet — the pool sizes
live as `fx.IMPACT_POOL` and `fx.POOL_PER_FAM`. Whatever N the web
run gives, write it down next to those, not in someone's head.

**The `VIEW_DEPTH` row exists to settle godot#107633**, which reports a WebGL
readback stall from the CPU depth sort. It is 4.3/4.4-era, unconfirmed on 4.7,
and contains no frame-time measurement. Reproducing it — or failing to — is
itself a useful result and worth reporting upstream. The rule stays either way,
because sort order is irrelevant for additive FX and costs nothing to avoid.

**Half of the SYNTHESIS row has no apparatus and is not going to get a fake
one.** §5 asks for "`CPUParticles3D` vs `GPUParticles3D` ceiling"; this mode
measures only the GPU path, because that is what `fx.gd` ships and because the
probe clones the shipped emitter rather than authoring its own — which is the
thing that makes the numbers mean anything. A CPU comparison would need the
whole blood effect rebuilt on `CPUParticles3D`, and a version of it built for a
benchmark would not be the version that ships. R1 R5 already argues the default
(GPU particles cost ~zero main-thread time; `CPUParticles3D` simulates every
particle in C++ on the one thread and re-uploads a MultiMesh every frame), and
R1 F4 gives the only reason to want the CPU path at all — `emit_particle()` does
nothing under `gl_compatibility`, which `fx.gd` already works around with a pool.
**If the GPU ladder crosses budget at a count the game actually reaches, that is
when to build the CPU comparison, and it is a package rather than a mode.**

### M-FLOW — what does one flow-field sweep cost?

```
pwsh tools/perf_native.ps1 -Mode flow
#   web (also a real answer): http://127.0.0.1:8970/index.html?mode=flow
```

Two rows — doors shut, then every door open — each 200 consecutive
`FlowField.solve()` calls timed individually with `Time.get_ticks_usec()`.

**Worst case by construction.** The origin is the open tile furthest from any
wall, found with a multi-source BFS out of every blocked tile at once; that is
the source whose wavefront travels furthest before anything stops it. The row
records `flow_origin` and `flow_reachable_tiles` so the two door states are
visibly different sweeps and not the same one twice.

**Decision rule (SYNTHESIS §5):** `flow_p99_ms < 2.0` accept. `> 4` → time-slice
it, or move from BFS to 4-pass fast sweeping (§4.5 item 4).

This is the one Milestone 2 measurement that is honest headlessly, because there
is no frame in it — and it is also the one whose web version is the same code, so
run both and record the ratio. Nothing else in this project has a measured
native-to-wasm ratio for anything.

**But it is a lower bound, not a translation.** `FlowField.solve()` keeps its
distances in a `PackedInt32Array` and its wavefront in `var q: Array[int]`, grown
with `append()` up to one entry per open tile. That is a heap allocation and a
GDScript `Array` reallocation per solve on top of the integer arithmetic, and
neither is guaranteed to scale the same way under single-threaded wasm. If the
native p99 is comfortably under 2.0 ms that is encouraging and nothing more; the
web row is what the decision rule is stated against.

### M-SEP — is the separation term still overpowering steering?

```
pwsh tools/perf_native.ps1 -Mode sep
```

One 30-second window with 24 round-10 zombies piled into a doorway, sampling
every live zombie's separation vector every frame — about 43,000 samples.

Read correction 2 above first: the clamp is already in, so the raw sum is
recomputed in the probe from `zombie.gd`'s own constants rather than read off
`_separation()`, which returns the post-clamp value.

Reported: `sep_p50`, `sep_p90`, `sep_p99`, `sep_max` (all raw, pre-clamp),
`sep_clamped_frac` (how often the clamp actually bound), and `sep_p90_scaled` —
the p90 multiplied by `SEPARATION_FORCE`, because what matters is its size next
to the **unit-length** flow vector it is added to. `sep_limit_scaled` is the
ceiling the clamp imposes on that, for comparison.

**How to read it.** `sep_p90_scaled` near or above 1.0 means separation is at
least as strong as steering for a tenth of the horde, and the clamp is the only
thing standing between the pack and a repulsion gas. `sep_clamped_frac` near 0
means the clamp never fires and could be removed; near 1 means it fires
constantly and 0.6 is doing all the work, which is worth knowing before anyone
retunes `SEPARATION_FORCE`. Then confirm by eye that the horde spreads across a
2-tile corridor rather than filing down it.

This one is genuinely headless: it is physics and arithmetic, with no frame in
it.

---

## M-PHYS — what 24 mutually-colliding `CharacterBody3D` cost · **ANSWERED**

`pwsh tools/perf_native.ps1 -Mode phys` · headless · 2026-07-27 · Windows 11, RTX 5090

Headless deliberately: the question is about the physics server, so removing the
renderer from the frame makes `physics_ms` the signal instead of a term inside
it. **The frame-time columns in a headless run are meaningless** — Godot's
low-processor sleep pins them near 6.9 ms regardless of load. Only `physics_ms`
and `collision_pairs` carry information here.

`collide` is zombie↔zombie contact: the shipped game runs with it **off**
(`zombie.collision_mask = 1|2`), so the `true` rows price an option, not the
status quo.

| zombies | collide | GodotPhysics3D `physics_ms` | Jolt `physics_ms` | pairs (Godot) |
|--------:|:--------|---------------------------:|------------------:|--------------:|
| 0  | no  | 0.48 | 0.58 | 1 |
| 6  | no  | 0.94 | 0.70 | 8 |
| 12 | no  | 0.98 | 0.74 | 15 |
| 18 | no  | 1.54 | 0.98 | 23 |
| 24 | no  | **2.36** | **1.28** | 32 |
| 0  | yes | 0.26 | 0.30 | 1 |
| 6  | yes | 0.76 | 0.60 | 13 |
| 12 | yes | 1.24 | 0.98 | 30 |
| 18 | yes | 2.34 | 1.22 | 48 |
| 24 | yes | **2.52** | **1.26** | 63 |

**Jolt is about twice as fast at 24 bodies** — 1.26 ms against 2.52 ms with
contact live. `physics/3d/physics_engine` is now `"Jolt Physics"`.

Three findings that change what the research assumed:

1. **Neither backend collapses.** The 4.0/4.1-era reports of GodotPhysics3D
   degrading somewhere between 10 and 40 mutually-colliding `CharacterBody3D`
   do not reproduce in 4.7 at this scale. 2.52 ms is not a cliff.
2. **The counter-evidence did not materialise.** SYNTHESIS §1.4d warned that
   Jolt's per-call `move_and_slide` constant had regressed (4.74 → 6.11 ms
   across godot-jolt 0.6→0.8) and might dominate the scaling factor at only 24
   bodies. It does not — Jolt wins at every stage from 6 up.
3. **Collision pairs grow linearly, not quadratically** — roughly 2.6·N with
   contact on (13/30/48/63 at 6/12/18/24). This was the specific diagnostic
   §5 asked for: had it gone N², boid separation and the broadphase would have
   been fighting each other. They are not.

Consequently **enabling zombie↔zombie contact is now a priced option rather than
an unmeasured risk**: +0.16 ms on GodotPhysics3D, free on Jolt. It has *not*
been enabled — M1.3 specifies `1|2` with boid separation as the standoff
tie-breaker, and that is still what ships. The number simply means the door is
open.

### Two traps, both hit during this run

**`"JoltPhysics3D"` is not a valid engine name and fails silently.** The
setting's own hint string is `DEFAULT,Jolt Physics,GodotPhysics3D,Dummy` — the
Jolt entry has a space. An unrecognised value falls back to GodotPhysics3D
without a warning. The first pass of this matrix asked for `"JoltPhysics3D"`,
got GodotPhysics3D twice, and produced a near-perfect dead heat that read as a
real result. The probe now records
`env.physics_server` — the concrete `PhysicsDirectSpaceState3D` subclass, which
is the only field that distinguishes the backends. **A backend comparison
without it can compare a backend against itself.** The table above is confirmed
`GodotPhysicsDirectSpaceState3D` vs `JoltPhysicsDirectSpaceState3D`.

**Jolt does not report `PHYSICS_3D_COLLISION_PAIRS`** — it is 0 at every stage,
including 24 bodies visibly in contact. That is a monitor gap, not an absence of
contacts. The pair column above is GodotPhysics3D's.

### Still unverified

These are native numbers. The web ratio is unmeasured, and single-threaded wasm
is not obliged to preserve it. Jolt is compiled into the stock web template, so
the switch costs no download size, and it is one line to revert.

---

## M-BASE — frame cost on the actual web target · **NOT ANSWERED**

## M-AUDIO — concurrent 3D voice count vs frame time · **NOT ANSWERED**

Both are web-specific by construction. M-BASE is about WebGL2 fill rate; M-AUDIO
is about `postMessage` pressure on the one thread that also runs the renderer
(~344 messages/s per live voice). Neither is answerable natively, and the
headless frame times above must not be borrowed for them. `tools/perf_native.ps1`
now refuses these two modes outright rather than producing a native number for
them.

The harness is built and works end to end — the probe boots, reads its mode from
the query string, and POSTs to the collector, all confirmed in a real browser.
What blocked it is that **Chrome throttles a background tab to nothing**, so the
run produced a `started` event and then no stages at all. This is the failure
mode `perf_probe.gd`'s own header warns about, and it is why a hidden tab
reports *nothing* rather than reporting *slow* — the numbers are absent, not
pessimistic. Driving it from an automated tab does not work; the tab has to be
genuinely foreground.

To finish these, with the tab visible and focused:

```
pwsh tools/build.ps1 -Perf
python tools/perf_collector.py build/perf
#   http://127.0.0.1:8970/index.html?mode=base
#   http://127.0.0.1:8970/index.html?mode=audio
```

Results land here automatically. What to look for:

- **M-BASE** — report p99 and worst, not mean. `SETTLE` is already 3.5 s on web
  so the first stage does not absorb the whole shader-compile storm and libel
  itself.
- **M-AUDIO** — expect **no clean cliff**. The cost is message pressure, so it
  shows as p99 diverging from median (the `jitter` column) well before anything
  is audible. Set the voice pool below the N where that starts. `Sfx.POOL_3D` is
  currently **14, chosen by estimate, not by measurement.** The two
  `max_distance` passes (0.0 = never culled, which is the Godot default, vs
  20.0) say whether distance culling earns its code.

## M-SFXBAKE · **ANSWERED**

29–35 ms to synthesise the combat set at boot, printed by `--verify`. It is a
per-sample GDScript loop on the only thread there is, which is why it is done up
front rather than lazily — the alternative was baking a weapon's first shot
during a fight.

---

## Running any of it

```
# headless — physics and the two arithmetic sweeps
pwsh tools/perf_native.ps1 -Mode phys
pwsh tools/perf_native.ps1 -Mode flow
pwsh tools/perf_native.ps1 -Mode sep

# windowed — anything that needs a frame to have been drawn.
# A window opens. Leave it alone; do not alt-tab into it.
pwsh tools/perf_native.ps1 -Mode warm         # runs the A/B pair itself
pwsh tools/perf_native.ps1 -Mode shadow
pwsh tools/perf_native.ps1 -Mode ssao
pwsh tools/perf_native.ps1 -Mode particles
pwsh tools/perf_native.ps1 -Mode billboard
pwsh tools/perf_native.ps1 -Mode vmfov        # + PNGs in notes/perf/shots/
pwsh tools/perf_native.ps1 -Mode mmcolor      # + PNGs
pwsh tools/perf_native.ps1 -Mode shadowcast   # + PNGs

# web — the authoritative bucket for every budget, and the only bucket at all
# for M-BASE and M-AUDIO. Tab must be VISIBLE and FOCUSED.
pwsh tools/build.ps1 -Perf
python tools/perf_collector.py build/perf
#   http://127.0.0.1:8970/index.html?mode=<mode>
#   ?mode=warm&warm=off      the M-WARM control
#   ?mode=vmfov&sign=-1      one sign held on screen
#   ?post=off                the shipping SSAO+LUT A/B (quality_governor)
```

The collector prints each stage as it lands and writes the whole run to
`notes/perf/<mode>-<timestamp>.json`. It is optional for a native run — the rows
are on stdout either way — but it is the only way to keep a web run.

Six things the harness does that are easy to undo by accident:

1. **It never passes `--shot`.** `main.gd`'s `--shot` handler quits after 60
   frames and steers the player's yaw itself, while the probe's capture modes
   settle for longer than that and own the camera. Two writers, one node. The
   probe writes its own PNGs through `--perf-shots`.
2. **It restores `project.godot` in a `finally` block, and refuses to start if a
   backup is already there.** The probe is registered as an autoload for the
   duration of a run and taken out again, exactly as `tools/build.ps1` does it.
   A surviving `project.godot.perfbak` means a run was killed before its finally
   block: `project.godot` on disk is the *injected* copy and the backup is the
   only clean one left, so a second run that blindly copied over it would destroy
   the clean copy and then "restore" the injected one. That is how a `PerfProbe=`
   autoload gets committed and every visitor's browser starts opening a localhost
   socket. The script stops and tells you to `Move-Item` the backup back.
3. **It clears `user://shader_cache` before a `warm` run** and says so. Every
   other mode deliberately leaves it alone, because those modes are not asking
   about first-draw cost and a cold cache would just add noise to their settle.
4. **It greps `main.gd` for the M-WARM wiring before running `-Mode warm`** and
   says loudly if it is missing, because without it the two passes are the same
   run and the difference between them is zero by construction.
5. **It says so when a run produced no stage rows, and when a run produced rows
   but no `final` payload.** Both scroll past as "nothing interesting happened"
   otherwise. No rows plus a timeout means a parse error until stderr proves
   otherwise — a parse error in any script reachable from the main scene makes
   Godot hang rather than exit.
6. **The probe freezes `quality_governor`** so the render scale cannot move under
   a ladder, and stamps `render_scale` on every row so that freeze is checkable
   rather than assumed. See the third note under "How to read anything below".

---

# Milestone 2 results

Three of the twelve are answered. The rest have apparatus and no numbers; the
status table above says which is which, and an unrun row is a blank rather than a
guess.

## M-VMFOV — does the vertex-only `PROJECTION_MATRIX` override behave, and what is the `[1][1]` sign? · **ANSWERED (native)**

`pwsh tools/perf_native.ps1 -Mode vmfov` · windowed · 2026-07-29 · RTX 5090

The rig is an asymmetric test object: a red marker to the right of the body, a
green one above it, a blue one nearer the lens. Grading by colour centroid against
the frame centre, in pixels:

| | red vs body | green vs body | body pixels |
|---|---|---|---|
| `sign 0` — reference, matrix untouched | RIGHT | ABOVE | 46,220 |
| `y_sign +1` | RIGHT | **BELOW** | 96,457 |
| `y_sign -1` | RIGHT | ABOVE | 96,454 |

**The override works, and the sign that preserves orientation on
`gl_compatibility` is negative.** Writing `+1/tan(fov/2)` into `[1][1]` — which is
what most of the widely-copied community shaders do — renders vertically flipped
here. R1's warning that "every community shader for this was written against
Forward+ and they disagree about the sign" is confirmed rather than dodged.

The magnification is right too, and it is a genuinely independent check:
`sqrt(96457 / 46220) = 1.4443` in linear terms, against the predicted
`tan(74/2) / tan(55/2) = 1.4476`. Two parts in a thousand.

**What ships does not depend on the answer.** `viewmodel.gd`'s shader *scales* the
existing terms — `PROJECTION_MATRIX[1][1] *= k / abs(PROJECTION_MATRIX[1][1])` —
so it inherits whatever sign, aspect and keep-mode the engine already put there.
That is why the sign question is settled rather than merely measured: a build that
reads the engine's own matrix cannot disagree with it. The measurement now stands
as the evidence for why the shader is written that way.

**Still open on web.** These are native numbers. The Forward+ half of the row's
original procedure is gone by design — `project.godot` pins
`renderer/rendering_method` to `gl_compatibility` on every platform, which was the
M1.0 gate item.

## M-FLOW — what does a flow-field solve cost, and how does it scale? · **ANSWERED (native)**

`pwsh tools/perf_native.ps1 -Mode flow` · headless · 200 solves per stage

| doors | reachable tiles | median | p99 | max |
|---|--:|--:|--:|--:|
| shut | 250 | 0.406 ms | 0.901 ms | 0.941 ms |
| open | 764 | 1.585 ms | 2.223 ms | 2.505 ms |

**It scales with reachable area, very nearly linearly** — 3.06x the tiles for
3.90x the cost. Mildly superlinear, which is what a BFS over a growing frontier
should look like, and nothing like the blow-up that would force the layered field
§4.5 explicitly deferred.

1.6 ms of main thread with the whole map open is real money against the frame
budget, but the field only re-solves when the player changes tile or a door
purchase invalidates it — not every frame. The number to watch is not this one, it
is how often `invalidate()` fires.

**Headless frame times in these rows carry no information** (see M-PHYS above);
`flow_*_ms` is the signal and it is measured directly around the solve.

## M-SEP — does boid separation overwhelm the flow vector? · **ANSWERED**

`pwsh tools/perf_native.ps1 -Mode sep` · headless · 24 zombies piled at one
doorway · 104,376 samples

The probe records the **raw, pre-clamp** sum, because `_separation()` returns the
value *after* `limit_length()` and the question is how far past the limit the raw
sum reaches.

| | p50 | p90 | p99 | max | clamped |
|---|--:|--:|--:|--:|--:|
| raw | 0.238 | 0.508 | 0.858 | 0.867 | — |
| x`SEPARATION_FORCE` 2.4 | 0.57 | 1.22 | 2.06 | 2.08 | 8% of samples |

The flow vector this is added to is unit length, so **at p90 separation is about
1.2x the steering term and at its worst about 2x**. That is a real force and not a
dominant one. §4.5 item 3 feared roughly 10x — six crowded neighbours summing to
~4 before scaling — and the pile does not reach it, because bodies cannot actually
occupy the same square.

**The clamp is doing real work, not sitting idle**: it binds on ~8% of samples in
a genuine doorway pile (0.016 to 0.08 across runs, RNG-dependent). So it is not a
belt-and-braces guard that could be removed — remove it and one sample in twelve
steers on a force twice the size of the one that knows where the player is.
`verify.gd` pins the behaviour as well as the constants.
