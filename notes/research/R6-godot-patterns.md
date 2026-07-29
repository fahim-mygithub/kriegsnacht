# R6 — Godot 4.7 architecture patterns where the first choice is expensive to undo

Research date: 2026-07-27 · Target: Godot **4.7**, `gl_compatibility` (WebGL2), single-threaded web export.

Evidence tiers: **T1** official docs / engine source · **T2** maintainer statement or engine issue tracker · **T3** reputable secondary or well-maintained reference implementation · **T4** community anecdote.

> **Version-discipline note.** During retrieval, godotengine/godot PR #52151 surfaced as the top hit for the billboard question. Its shader code uses `INV_CAMERA_MATRIX`, `CAMERA_MATRIX` and `WORLD_MATRIX` — **Godot 3.x spatial builtins**. It was rejected and replaced with current `master` source (`MODEL_MATRIX` / `VIEW_MATRIX` / `MAIN_CAM_INV_VIEW_MATRIX`). Every finding below was re-checked against 4.x-era material. Where only 4.2–4.5 evidence exists for a 4.7 target, it is flagged inline.

---

## Bottom line

1. **`SpriteBase3D` billboard modes destroy the model's rotation entirely** — the generated shader overwrites `MODELVIEW_MATRIX` with a camera-derived basis plus `MODEL_MATRIX[3]` (translation only). A local Z rotation is not merely ignored, it is *unrepresentable*. The "tilt the sprite to clamber through a window" trick **cannot work** with `StandardMaterial3D`. It becomes a ~6-line `ShaderMaterial` that rebuilds the same basis and post-multiplies a roll — cheap, and entities do **not** need to become meshes. (T1, engine source)
2. **Do not use per-instance shader uniforms for per-zombie state on this project.** They only arrived in the Compatibility renderer in **4.4** (PR #96819), and they are **broken on web export** past roughly 20 instances — surplus instances render black. Issue #112674 is **open**, with four independent confirmations across Chrome/Firefox, Linux/macOS/Android. Use `SpriteBase3D.modulate` (free, per-node, shared material, routed through vertex `COLOR`) plus a per-entity `material.duplicate()` for anything modulate can't carry. (T2 bug, T1 docs)
3. **`AudioStreamSynchronized` is the wrong bet for layered music/ambience here.** Issue #109494 — *"Garbled audio with AudioStreamSynchronized on no-threads web builds"* — is **open**, reproduced on exactly this configuration (`gl_compatibility`, web, `thread_support=false`), with an MRP showing `AudioStreamMP3` fine and `AudioStreamSynchronized` garbled. Per-stream volume *is* runtime-settable by API, but sample-lock under the web driver is the failing part. (T2)
4. **The recoil fix is a dedicated pivot node, not smarter maths.** Keep one authoritative `_look_pitch` written only by mouse motion onto `Head`, and put recoil on a separate `RecoilPivot` between `Head` and `Camera3D`. Transform composition then adds them for free and neither can clobber the other. `player.gd:95` and `player.gd:197` currently both write `_cam.rotation.x` — that is the whole bug.
5. **The viewmodel rule is one line: never let script and `AnimationPlayer` write the same node.** Procedural sway/bob/ADS go on a parent `Node3D`; keyed clips drive a child. Reach for `AnimationNodeAdd2` only if you need to blend two *authored* clips additively — it does not solve code-vs-animation contention, and additive blending in 4.3+ requires `deterministic = true` or weights get normalised and additive stops behaving. (T1)
6. **Pool decal quads and CPU particle emitters; do not pool `AudioStreamPlayer` nodes** — `AudioStreamPolyphonic` is the engine's built-in voice pool (`polyphony`, default 32; `play_stream()` returns an int ID, `INVALID_ID = -1` when full). Hitscan weapons need no bullet pool at all. (T1)

---

## Findings

### F1 — Billboard modes overwrite the full basis (T1, corroboration ×3)

Current engine source generates, for `BILLBOARD_FIXED_Y`:

```glsl
MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
        vec4(normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz)), 0.0),
        vec4(0.0, 1.0, 0.0, 0.0),
        vec4(normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
        MODEL_MATRIX[3]);
```

Only column 3 (translation) survives from the model. `FLAG_BILLBOARD_KEEP_SCALE` post-multiplies a **diagonal** matrix of `length(MODEL_MATRIX[n].xyz)` — scale magnitudes only, still no rotation.

- `scene/resources/material.cpp`, `_update_shader()` — https://github.com/godotengine/godot/blob/master/scene/resources/material.cpp (T1)
- Long-standing feature request confirming rotation is ignored by design: https://github.com/godotengine/godot/issues/18296 (T2)
- Proposal discussion "Allow Rotation of Billboard Sprite3Ds": https://github.com/godotengine/godot-proposals/discussions/5821 (T2)

**Caveat:** verified against `master` (commit ref `1597016`), not the exact `4.7-stable` tag. The 4.7 `BaseMaterial3D` class reference describes the same behaviour, so drift is unlikely but unproven.

### F2 — Per-instance shader uniforms: supported on Compatibility, broken on web (T2, corroboration ×4)

- Feature landed for Compatibility in **4.4**: PR "Implement instance uniforms in Compatibility renderer" https://github.com/godotengine/godot/pull/96819 (T2). Engine source confirms `gl_compatibility` handles `SCOPE_INSTANCE` in `drivers/gles3/storage/material_storage.cpp` (T1).
- **Open bug, web export specifically:** https://github.com/godotengine/godot/issues/112674 (T2). Reported on 4.5.1; instances beyond ~20 render black. Confirmations from `mrwolfyer`, `BunkWire2X8`, `prvak` and `Minyatan`; last activity 2026-03-21. `prvak` adds two nasty details: **the limit is global across unrelated materials**, and **invisible nodes still count toward it**.
- Docs: 16 instance uniforms per shader, indices 0–15, no textures or arrays — https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html (T1, 4.7)

The "~20" figure is the reporter's estimate (T4); the *existence* of the defect is T2.

**`INSTANCE_CUSTOM` is not an escape hatch.** In `drivers/gles3/shaders/scene.glsl` it is populated only inside `#ifdef USE_INSTANCING`; the `#else` branch is `vec4 instance_custom = vec4(0.0);` (T1). It carries data only for `MultiMeshInstance3D`, not for ordinary `Sprite3D`/`MeshInstance3D` nodes.

### F3 — `SpriteBase3D.modulate` is the free per-instance channel (T1)

`modulate` is *"A color value used to multiply the texture's colors"*, per-node, **not** requiring a separate material — but with a custom material it needs `vertex_color_use_as_albedo` (BaseMaterial3D) or an explicit `ALBEDO *= COLOR.rgb;` in shader code. https://docs.godotengine.org/en/stable/classes/class_spritebase3d.html (T1, 4.7). Each `Sprite3D` generates its own mesh, so `modulate` rides vertex colour and costs nothing.

### F4 — `AudioStreamSynchronized` (T1 API, T2 defect)

API (4.7 docs, https://docs.godotengine.org/en/stable/classes/class_audiostreamsynchronized.html): `set_sync_stream_volume(stream_index, volume_db)` / `get_sync_stream_volume`, `stream_count`, `MAX_STREAMS = 32`. *"The streams begin at exactly the same time when play is pressed, and will end when the last of them ends."* The docs state **no** restriction requiring playback restart, so runtime volume change is intended to work — but the docs also make **no explicit runtime-mutation guarantee**, so this is inference, not a quoted promise.

Defect: https://github.com/godotengine/godot/issues/109494 (T2) — open, labels `bug`, `platform:web`, `needs testing`, `topic:audio`. Tested `4.3.stable`, `4.4.1.stable`, `4.5.beta5`. Follow-up to #87329; PR #91382 fixed most `AudioStream` resources but not this one. MRP: https://github.com/elliotfontaine/godot-web-audio-garble

### F5 — `AudioStreamPolyphonic` is the engine-provided audio pool (T1)

https://docs.godotengine.org/en/stable/classes/class_audiostreamplaybackpolyphonic.html (T1, 4.7):

```
int  play_stream(stream, from_offset=0, volume_db=0, pitch_scale=1.0, playback_type=0, bus=&"Master")
void stop_stream(stream: int)
void set_stream_volume(stream: int, volume_db: float)
void set_stream_pitch_scale(stream: int, pitch_scale: float)
bool is_stream_playing(stream: int) const
```

*"An AudioStream that lets the user play custom streams at any time from code, simultaneously using a single player."* `polyphony` default 32. `play_stream()` returns a unique int ID; `INVALID_ID = -1` *"is returned if the polyphony limit is reached."* That return value is your back-pressure signal — check it.

### F6 — Additive animation blending (T1)

- `AnimationNodeAdd2`: *"Blends two animations additively based on the amount value."* Ports `in` and `add`. Amount > 1.0 amplifies the `add` input; amount < 0.0 inverts it. https://docs.godotengine.org/en/stable/classes/class_animationnodeadd2.html (T1, 4.7)
- The 4.0→4.3 migration article is the load-bearing one: *"In additive blending, cases where the total weight of blending is `total_weight < 1` or `total_weight > 1` the value must be interpolated from the default value."* And critically: *"If the `Deterministic` option is disabled, the total weight of blending will be normalized, so additive blending will not work as expected."* https://godotengine.org/article/migrating-animations-from-godot-4-0-to-4-3/ (T1)
- `AnimationMixer.deterministic`: *"the blending uses the deterministic algorithm. The total weight is not normalized and the result is accumulated with an initial value (`0` or a `"RESET"` animation if present)."* https://docs.godotengine.org/en/stable/classes/class_animationmixer.html (T1, 4.7)

**Take-away:** additive blending in 4.x is for combining *authored* clips and needs `deterministic = true` plus a `RESET` animation to behave. It is not the mechanism for merging per-frame procedural code with clips.

### F7 — State machine playback API (T1)

https://docs.godotengine.org/en/stable/classes/class_animationnodestatemachineplayback.html (T1, 4.7):
- `travel(to_node, reset_on_teleport=true)` — *"Transitions from the current state to another one, following the shortest path... If the path does not connect from the current state, the animation will play after the state teleports."*
- `next()` — *"If there is a next path by travel or auto advance, immediately transitions from the current state to the next state."*
- `get_current_play_position()`, `get_current_length()`, `get_travel_path()`.

Transition config (https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html, T1, 4.7): three switch modes *"Immediate, Sync, At End"*; advance mode *"If `Disabled`, the transition will not be used. If `Enabled`, the transition will only be used during `travel()`. If `Auto`, the transition will be used if the advance condition and expression are true."*

### F8 — Camera controller convention (T3)

The widely-cited Godot 4 reference implementation splits yaw and pitch onto **separate nodes** (`CharacterBody3D` → `Head` → `CameraContainer` → `Camera3D`) *"to prevent gimbal lock by isolating yaw and pitch axes"*, applies rotation to nodes rather than accumulating in script vars, calls `orthonormalize()` after each rotation because *"the node's transforms must not deteriorate over time"*, and clamps pitch on `head.rotation.x`. https://yosoyfreeman.github.io/article/godot/tutorial/achieving-better-mouse-input-in-godot-4-the-perfect-camera-controller/ (T3)

This corroborates the *node-splitting* principle but does **not** itself address recoil. The recoil-pivot extension below is my synthesis, not a quoted source.

---

## Recommendations for this project

### R1 — The rig (do this before anything else; it is the expensive-to-undo one)

```
Player (CharacterBody3D)          ← yaw:   rotate_y() from mouse X
└─ Head (Node3D)                  ← pitch: _look_pitch, mouse Y ONLY
   └─ RecoilPivot (Node3D)        ← recoil accumulator, script ONLY
      └─ Camera3D
         └─ ViewmodelRoot (Node3D)  ← sway + bob + ADS lerp, script ONLY
            └─ WeaponMesh (Node3D)  ← AnimationPlayer keys THIS node ONLY
               └─ MuzzlePoint (Marker3D)
```

**Invariant: exactly one writer per node.** Godot composes parent/child transforms multiplicatively every frame, so "additive" comes for free and no blending machinery is required. You need `AnimationTree` only when you must cross-fade two authored clips; for a viewmodel, `AnimationPlayer` on `WeaponMesh` is enough and avoids `AnimationTree`'s extra setup on a renderer where you want fewer moving parts.

This also sidesteps a question the docs never answer (see gaps): whether `AnimationMixer` re-writes keyed properties every frame over script writes. With one writer per node, it cannot matter.

### R2 — Recoil accumulator

Replace the two conflicting writes in `player.gd`. Note the framerate-independent decay — mandatory on web, where `delta` is genuinely erratic.

```gdscript
@onready var _head: Node3D = $Head
@onready var _recoil_pivot: Node3D = $Head/RecoilPivot

var _look_pitch := 0.0        # authoritative; ONLY mouse motion writes this
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0

const RECOIL_RECOVER := 8.0   # higher = snappier return

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * MOUSE_SENS)
        _look_pitch = clampf(_look_pitch - event.relative.y * MOUSE_SENS,
                             -PITCH_LIMIT, PITCH_LIMIT)
        _head.rotation.x = _look_pitch        # recomputed, never accumulated

func _process(delta: float) -> void:
    var k := 1.0 - exp(-RECOIL_RECOVER * delta)   # framerate-independent
    _recoil_pitch = lerpf(_recoil_pitch, 0.0, k)
    _recoil_yaw   = lerpf(_recoil_yaw,   0.0, k)
    _recoil_pivot.rotation.x = _recoil_pitch
    _recoil_pivot.rotation.y = _recoil_yaw

func _apply_recoil(kick: float) -> void:        # called from _shoot()
    _recoil_pitch += kick * 0.0035
    _recoil_yaw   += randf_range(-1.0, 1.0) * kick * 0.0012
```

Mouse look and recoil now live on different nodes and simply cannot overwrite each other. If you want CoD-style *permanent* climb (where the player must pull down), bleed a fraction of the decayed recoil into `_look_pitch` instead of returning all of it to zero.

Both a script-side authoritative pitch **and** a dedicated pivot are used here — the pivot is what makes it robust, the authoritative `_look_pitch` is what makes clamping correct.

### R3 — Shotgun reload: `AnimationPlayer` + `animation_finished`, not `seek()`

Recommended because it needs no unverified engine feature, keeps cancel logic in testable GDScript, and adds no `AnimationTree`.

```gdscript
enum Reload { NONE, START, SHELL, FINISH }
var _reload := Reload.NONE
var _cancel_requested := false

func begin_reload() -> void:
    if _reload != Reload.NONE or shells_in_tube >= tube_capacity: return
    _reload = Reload.START
    _anim.play("reload_start")

func _on_animation_finished(name: StringName) -> void:
    match _reload:
        Reload.START, Reload.SHELL:
            shells_in_tube = mini(shells_in_tube + (1 if name == &"reload_shell" else 0),
                                  tube_capacity)
            # cancel is evaluated ONLY at a shell boundary -> never a partial shell
            if _cancel_requested or shells_in_tube >= tube_capacity:
                _reload = Reload.FINISH
                _anim.play("reload_finish")     # the pump
            else:
                _reload = Reload.SHELL
                _anim.play("reload_shell")
        Reload.FINISH:
            _reload = Reload.NONE
            _cancel_requested = false

func try_fire() -> void:
    if _reload != Reload.NONE:
        _cancel_requested = true    # fire is queued, not dropped
        return
    _fire_now()
```

The key design point — and the thing that makes shotgun reloads feel right in shipped games — is that **cancel is latched, then honoured at the next shell boundary**, so you always get the pump animation and never interrupt mid-shell.

If you later do move to `AnimationTree`: a `reload_shell` state with a transition **to itself**, switch mode `At End`, advance mode `Auto`, advance expression `shells_needed > 0` is the shape you want. I could not verify that `AnimationNodeStateMachine` permits self-transitions in 4.7 (see gaps) — which is precisely why the `AnimationPlayer` version is the recommendation.

### R4 — Audio

- **Layered adaptive music/ambience: do not use `AudioStreamSynchronized` on the web build.** Ship pre-mixed stem sets, or run independent `AudioStreamPlayer`s started in the same frame and accept mild drift. Re-test #109494 on 4.7 before committing either way (procedure below).
- **All one-shot SFX (gunshots, hits, footsteps, zombie vocals): one `AudioStreamPlayer` with an `AudioStreamPolyphonic`**, not a node pool. Check `play_stream() != -1` and treat `-1` as "drop this sound", which is the correct behaviour for a horde game anyway.
- Positional audio still needs `AudioStreamPlayer3D` per source — `AudioStreamPolyphonic` is one emitter position. Pool a small fixed ring of 3D players (8–16) and steal the oldest/quietest.

### R5 — Per-zombie visual state

Priority order, given F2:

1. **`modulate`** — free, per-node, shared material. Covers damage tint, burning glow ramp, palette variation. This alone probably covers the whole requirement.
2. **`material.duplicate()` per zombie** if you need a scalar the shader must branch on. At ~24 zombies that is 24 materials — the batching loss is irrelevant, and alpha-blended billboards batch poorly regardless.
3. **`set_instance_shader_parameter()`** — avoid until #112674 is confirmed fixed on 4.7 web.

### R6 — Billboard tilt shader (unblocks the vault/clamber trick)

Rebuild the `FIXED_Y` basis, then post-multiply a roll about local Z:

```glsl
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, specular_disabled;

uniform sampler2D tex : source_color, filter_nearest;
uniform float tilt = 0.0;   // radians — per-material (see R5, NOT an instance uniform)

void vertex() {
    vec3 up    = vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(up, MAIN_CAM_INV_VIEW_MATRIX[2].xyz));
    vec3 fwd   = normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, up));
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(up, 0.0),
                                          vec4(fwd, 0.0), MODEL_MATRIX[3]);
    float c = cos(tilt), s = sin(tilt);
    MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(   // roll in the screen plane
        vec4( c,   s,   0.0, 0.0),
        vec4(-s,   c,   0.0, 0.0),
        vec4( 0.0, 0.0, 1.0, 0.0),
        vec4( 0.0, 0.0, 0.0, 1.0));
}

void fragment() {
    vec4 t = texture(tex, UV);
    ALBEDO = t.rgb * COLOR.rgb;   // <- keeps SpriteBase3D.modulate working
    ALPHA  = t.a * COLOR.a;
}
```

Entities stay 2D sprites. **Verify `MAIN_CAM_INV_VIEW_MATRIX` compiles under `gl_compatibility`** — if not, substitute `INV_VIEW_MATRIX` (it differs only during shadow passes, which this project does not have).

### R7 — Pooling, given no threads

- **Bullets:** the project is hitscan. No pool needed. Do not build one.
- **Decals:** `Decal` nodes are Forward+/Mobile only, so bullet holes must be quad `MeshInstance3D`s — pool a fixed ring (e.g. 64) and recycle oldest-first.
- **Particles:** `CPUParticles3D` only on Compatibility. Pre-instantiate N emitters, park with `emitting = false` + `visible = false`, wake with `restart()`.
- **Audio:** see R4 — `AudioStreamPolyphonic`, not a node pool.
- **Convention:** preallocate in `_ready()`, keep a free-list `Array[int]`, never `queue_free()` a pooled object, park with `set_process(false)` / `set_physics_process(false)` / `visible = false`, and reparent nothing at runtime.
- **Single-threaded web specific:** shader compilation happens on the main thread mid-gameplay. Pool objects must be **rendered at least once during the loading screen** (one frame, tiny, off-screen or behind the fade) so their shader variants compile before the first round, not on the first zombie hit.

---

## Coverage gaps

1. **`AudioStreamSynchronized` on 4.6/4.7 — unverified.** Issue #109494's tested-versions list stops at `4.5.beta5` and it carries a `needs testing` label. The project is on 4.7. Treat as broken; confirm by measurement.
2. **Instance-uniform web bug on 4.6/4.7 — unverified.** #112674 was reported on 4.5.1 with confirmations through 2026-03. No fix PR was located. The exact instance count that triggers it is unknown; "~20" is the reporter's guess (T4), and `prvak`'s claim that the budget is global across materials and counts invisible nodes is a single T4 report, uncorroborated.
3. **Does `AnimationMixer` overwrite script-set values on keyed properties each frame?** Neither the `AnimationTree` tutorial nor the `AnimationMixer` class reference states this explicitly. My R1 recommendation is built so the answer never matters, but the claim itself is **inference, not sourced**.
4. **`AnimationNodeStateMachine` self-transitions** — I could not find documentation confirming a state may transition to itself in 4.7. The `AnimationPlayer` recommendation avoids depending on it.
5. **No authoritative "standard viewmodel rig" exists.** The node-composition pattern in R1 is convention synthesised from transform semantics (T1) plus the camera-controller split (T3), not a documented Godot pattern. Treat as a defensible default, not received wisdom.
6. **Gweebo's FPS Template (Godot 4.3)** advertises exactly the procedural recoil/sway/bob/tilt stack in question, but is distributed on itch.io and was not retrieved or inspected. It is the single most likely source of a concrete counter-example to R1/R2 and is worth 20 minutes.
7. **Verified against `master`, not the `4.7-stable` tag** — applies to F1, F2's source-level claims, and the `scene.glsl` `INSTANCE_CUSTOM` finding.
8. **`ResourceLoader.load_threaded_request()` behaviour with `thread_support=false`** was not researched. Assume it degrades to a blocking load; confirm before relying on it for streaming.

---

## What must be measured rather than researched

### M1 — Instance-uniform ceiling on the actual web build
Decides whether R5 tier 3 is ever available.
1. Scene with one `ShaderMaterial` declaring `instance uniform vec4 tint : source_color;`.
2. Spawn N `MeshInstance3D`s sharing it, each `set_instance_shader_parameter("tint", <distinct colour>)`, N ∈ {8, 16, 24, 32, 64}.
3. Export with the project's real preset (`thread_support=false`) and open on GitHub Pages, not `localhost` — Chrome and Firefox both.
4. Record the largest N at which **all** instances show their colour. Repeat with half the meshes `visible = false` to test `prvak`'s global-budget claim.
Pass condition: correct colours at N ≥ 32 with invisible nodes present.

### M2 — `AudioStreamSynchronized` on 4.7 web
Run the MRP from https://github.com/elliotfontaine/godot-web-audio-garble under 4.7 with `thread_support=false`, exported to Pages. Listen to demo 3. If clean, re-test with 3–4 stems at the project's real mix rate. Also confirm `set_sync_stream_volume()` mid-playback neither restarts nor desyncs, by ramping one stem 0 → -40 dB over 10 s and checking for a re-attack.

### M3 — Concurrent voice ceiling
`AudioStreamPolyphonic.polyphony` defaults to 32, but the web driver's real limit is unpublished. Fire one-shots at increasing rate; log the first frame where `play_stream()` returns `-1`, and separately listen for crackle — the audible limit will likely be lower than the API limit. Use the existing `scripts/perf_probe.gd`.

### M4 — Billboard shader compiles and performs under `gl_compatibility`
Confirm `MAIN_CAM_INV_VIEW_MATRIX` resolves; then compare frame time with 24 tilt-shader sprites vs 24 `StandardMaterial3D` sprites. **Switch the editor to the Compatibility renderer first** — otherwise you are validating against Forward+, which is not what ships.
