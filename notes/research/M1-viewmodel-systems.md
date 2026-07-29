# M1 — First-person weapon viewmodels and weapon animation in Godot 4

Research brief for **Kriegsnacht** (Godot 4.7 → single-threaded WebGL2/`gl_compatibility` on GitHub Pages).
Compiled 2026-07-27. All source code cited was read, not summarised from search snippets.

Evidence tiers: **1** official docs/engine source · **2** maintainer statements/tracked issues ·
**3** reputable secondary or a well-maintained reference implementation · **4** community anecdote.

---

## Bottom line

- **You cannot do the Unity-style "second camera, same viewport, narrow FOV" viewmodel in Godot.**
  The docs are explicit: *"Only one camera can be active per viewport."* (tier 1). The feature request
  to allow otherwise cites FPS viewmodels as its motivating case and is still open (tier 2). Your only
  three options are a SubViewport, a vertex-shader projection override, or making the gun small enough
  that it geometrically cannot clip.
- **The third option is the right one for this project and almost nobody talks about it.** Your player
  capsule has `RADIUS = 0.24` (`scripts/entities/player.gd:22`), so no wall can ever be closer than
  0.24 m to the camera axis. A viewmodel that fits inside a ~0.22 m sphere at the camera **cannot clip
  a wall, ever** — no SubViewport, no depth hack, no extra fill rate. Add a vertex-only
  `PROJECTION_MATRIX` FOV override to make that small object read as a full-size gun. `PROJECTION_MATRIX`
  is `inout` in `vertex()` and is used by the built-in transform when you don't write `POSITION` (tier 1),
  so this costs nothing and touches no depth state.
- **The viewmodel shader everyone copies is Godot 3.x code and its depth line is wrong on 4.3+.** The
  lineage is traceable: the original (`2nafish117`/`Braboware`, Godot 3 — `hint_color`, `NORMALMAP`) uses
  `POSITION.z = mix(POSITION.z, 0, 0.999)`. Godot 4.3 introduced reverse Z, where **0 is the far plane**,
  so that line now pushes the gun *behind* the world. Only the 4.3+ forks fix it
  (`mix(POSITION.z, POSITION.w, 0.9)`). Reverse Z **is** active in the Compatibility/WebGL2 renderer —
  confirmed in engine source, not inferred.
- **Recoil has one canonical implementation and four independent repos wrote it identically:** a
  two-stage lerp — `target → 0` at `return_speed`, then `current → target` at `snappiness`. Split it
  into *view kick* (rotation on a camera-parent node) and *weapon kick* (position on the weapon node,
  ~half magnitude). That split is the whole feel.
- **Buy nothing, model nothing — extrude `GUNART`.** Its parts are axis-aligned rects in a 100×60 space;
  each becomes a box. ~70 triangles per weapon, one ~150-line builder covers all 12 plus the knife plus
  the Pack-a-Punch tint. You already have exactly this pipeline in `scripts/world/world_builder.gd`.
  CC0 model packs are the wrong answer here: Kenney's kits are **sci-fi blasters**, not M1911/MP40/AK-74u.
- **Two things I could not find in any open-source Godot 4 project:** a sprint-out fire gate, and
  tactical-vs-empty reload. Every template surveyed has neither. Design them from the CoD convention;
  there is no reference implementation to crib.

---

## Findings

### F1 — Godot allows exactly one active Camera3D per Viewport

**Tier 1.** <https://docs.godotengine.org/en/stable/classes/class_camera3d.html>
> "Only one camera can be active per viewport."

`cull_mask` selects which `VisualInstance3D.layers` the *active* camera renders; it does not enable a
second simultaneous camera. So "put the gun on layer 2 and give it its own camera" only works if that
camera owns its own viewport.

**Corroboration (tier 2):** godot-proposals#956, *"Support using multiple cameras in a single viewport"* —
still open, and the request text names the exact use case:
> "A primary camera is used to render the world, with player-changeable FOV. A secondary camera is used
> to render viewspace objects, such as gun viewmodels, hands, grenades, etc."

The author's own suggested workaround is `Viewport`/`ViewportTexture`, "less intuitive and potentially
with performance implications."
<https://github.com/godotengine/godot-proposals/issues/956>

**Independent corroboration: 2** (docs + proposal).

---

### F2 — The SubViewport pattern, as actually implemented in the wild

Four separate Godot 4 projects converge on the identical seven-line solution: a `SubViewport` containing
a second `Camera3D` whose `global_transform` is copied from the main camera every frame.

| Repo | File | Tick |
|---|---|---|
| `Jeh3no/Godot-simple-FPS-weapon-system` | `.../Weapons/Scripts/Camera/viewport_camera_script.gd` | `_physics_process` |
| `bukkbeek/GodotFPS-Template` | `common/utils/weapon_sub_viewport.gd` | `_process` |
| `AxelReviron/Godot-FPS-Template` | `entities/player/weapon_camera.gd` | `_process` |
| `matiturock/fps-tutorial` | `Player_Controller/scripts/SubViewportContainer.gd` | signal-driven FOV |

Canonical form (bukkbeek, `weapon_sub_viewport.gd`, complete file):

```gdscript
extends SubViewport

@onready var camera: Camera3D = $Camera3D
@onready var main_camera: Camera3D = %MainCamera

func _process(_delta: float) -> void:
	camera.global_transform = main_camera.global_transform
```

The weapon FOV is then just `camera.fov` on the viewport camera — no shader at all. `AxelReviron`'s
`sub_viewport.gd` additionally sets `size = get_window().size` at `_ready()`, which is a bug on any
resizable window (it never updates on resize).

**Tier 3, independent corroboration: 4.**
- <https://github.com/Jeh3no/Godot-simple-FPS-weapon-system>
- <https://github.com/bukkbeek/GodotFPS-Template>
- <https://github.com/AxelReviron/Godot-FPS-Template>
- <https://github.com/matiturock/fps-tutorial>

**Cost on WebGL2 — the honest position.** A full-window SubViewport is a second colour+depth target and
a second scene pass. The *fragment* cost is bounded by how many pixels the gun covers, but the render
target allocation, clear, and the composite blit are full-screen and unconditional. I found one report
of SubViewport 3D collapsing to **<1 FPS on HTML5 while running fine natively** (Godot 4.3) — but it is
an unresolved forum thread, the setup was *many* SubViewports inside a Control-based 2D game, and no
responder diagnosed it. **Tier 4, confounded, do not treat as a measurement of your case.**
<https://forum.godotengine.org/t/subviewport-rendering-performances-on-web/101434>

---

### F3 — The viewmodel clip shader is Godot 3.x code with a 4.3-breaking depth line

This is the highest-risk item in the brief, because the shader is widely copied and the broken version
still ranks first in search.

**Generation 1 — Godot 3.x** (`2nafish117/godot-viewmodel-render-test`, mirrored by `Braboware/...-annotated`).
Identifiable as 3.x by `hint_color`, `hint_albedo`, `hint_white`, `NORMALMAP`. Its annotated depth line:

```glsl
POSITION.z = mix(POSITION.z, 0, 0.999); // modify z value to draw on top of everything
                                        // effectively smushes everything down on the depth-axis
                                        // 0.001 thick up against the camera
```
<https://github.com/Braboware/godot-viewmodel-render-test-annotated> (branch `master`)

**Generation 2 — Godot 4.x, still wrong for 4.3+** (`matiturock/fps-tutorial`,
`Player_Controller/ViewModelShader/viewmodel.gdshader`). Ported the syntax, kept `mix(POSITION.z, 0, 0.999)`,
and added `PROJECTION_MATRIX[1][1] = -onetanfov;` (negative, for Godot 4's clip-space Y flip).

**Generation 3 — reverse-Z-correct.** majikayogames' gist carries the comment *"Above doesn't work for
Godot 4.3 Z was reversed"* and mixes toward `POSITION.w` (the near plane under reverse Z) instead of 0:

```glsl
POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX.xyz, 1.0);
POSITION.z = mix(POSITION.z, POSITION.w, 0.9);
```
<https://gist.github.com/majikayogames/94ac6c76650a609e4db09febb82ab197> — **tier 3**

A fourth variant writes depth in the fragment stage instead:
`DEPTH = 1.0 - (1.0 - FRAGCOORD.z) * 0.7;`
<https://godotshaders.com/shader/first-person-view-model-shader-updated-for-godot-4-3/> — **tier 3**.
**Avoid this one.** Writing `DEPTH` in `fragment()` disables early-Z rejection, which is a real cost on
tile-based/mobile-class GPUs — exactly the hardware a browser build lands on. A secondary source states
the concern plainly ("avoiding setting DEPTH in the fragment function which is a performance killer",
tier 4), and the Godot docs add the correctness trap (tier 1): *"If DEPTH is written to in any shader
branch, then you are responsible for setting DEPTH for all other branches."*

**Reverse Z applies to your renderer.** The announcement post does not say which renderers are affected
<https://godotengine.org/article/introducing-reverse-z/> (tier 1, but silent on this). Engine source
settles it — the GLES3/Compatibility backend uses a greater-than depth test:

- `drivers/gles3/rasterizer_scene_gles3.cpp` → `scene_state.set_gl_depth_func(GL_GREATER);`
- `drivers/gles3/storage/light_storage.cpp` → `glTexParameteri(..., GL_TEXTURE_COMPARE_FUNC, GL_GREATER);`

**Tier 1** (engine source, `godotengine/godot`). Reverse Z is on in Compatibility. The 4.3+ form of the
shader is the one you would need — *if* you used this technique at all (see R1, where I recommend you don't).

The general guidance from the same announcement (tier 1) is worth heeding:
> "Ultimately, most operations should not be done in clip space as it is a non-linear space… We recommend
> that, if you are doing operations in clip space… you switch to doing those operations in view space instead."

---

### F4 — Recoil: one algorithm, four independent implementations

Every Godot 4 project surveyed that does procedural recoil uses the same two-stage lerp. It is a
discrete approximation of a critically-damped spring and it is the single most portable thing in this document.

```gdscript
func _process(delta: float) -> void:
	target_rotation  = lerp(target_rotation,  Vector3.ZERO,     return_speed * delta)
	current_rotation = lerp(current_rotation, target_rotation,  snappiness   * delta)
	rotation = current_rotation

func add_recoil(kick: Vector3) -> void:
	target_rotation += Vector3(kick.x, randf_range(-kick.y, kick.y), randf_range(-kick.z, kick.z))
```

`target` is the impulse accumulator that bleeds off; `current` chases it. Firing faster than the bleed
rate stacks the kick — which is exactly how a real spray pattern climbs, for free.

| Source | Names used | Notes |
|---|---|---|
| `vi4hu/godot-procedural-recoil` `addons/procedural-recoil/recoil.gd` | `returnSpeed`, `snappiness` | Explicitly a port of a Unity procedural-recoil system; separate `recoil` / `aimRecoil` vectors |
| `Jeh3no/...` `Camera/camera_recoil_holder_script.gd` | `base_rotation_speed`, `target_rotation_speed` | Same math, confusingly named |
| `AxelReviron/...` `objects/weapons/camera_recoil.gd` | `recoil_speed`, `recoil_snap_amount` | Clamps pitch to `MAX_RECOIL_X = 0.5` |
| `AxelReviron/...` `objects/weapons/weapon_recoil.gd` | same | **Position**, not rotation |

**Tier 3, independent corroboration: 4** (3 repos, 4 files).

**View kick vs weapon kick — the distinction the brief asked about.** `AxelReviron` is the only surveyed
project that separates them, and it does so cleanly: two sibling nodes, same math, same `weapon_fired`
signal, different output channel.

```gdscript
# camera_recoil.gd  — VIEW KICK: rotates a camera ancestor. Changes where bullets go.
basis = Quaternion.from_euler(current_rotation)

# weapon_recoil.gd  — WEAPON KICK: translates the weapon node only. Pure cosmetics.
target_position += Vector3(-recoil_amount_x * 0.5,   # gun travels back toward the player
                            recoil_amount_y * 0.5,   # and up
                            0.0)
```

Note the `* 0.5` and the tiny constants (`MAX_RECOIL_X = 0.0015` metres for the weapon vs `0.5` radians
for the view). Both take an `is_aiming()` branch with a separate, smaller ADS recoil vector.

Your ancestor already had the view-kick half, as a scalar spring integrated properly rather than lerped
(`kriegsnacht.html:2960`):

```javascript
P.viewKickV += -P.viewKick*46*dt - P.viewKickV*11*dt;   // stiffness 46, damping 11
P.viewKick  += P.viewKickV*dt;
```

That is a genuine damped harmonic oscillator and it will overshoot and settle, where the two-lerp model
will not. The ancestor's is arguably the better feel and is already tuned — and `_recoil` in
`scripts/entities/player.gd:41` is the vestige of it.

---

### F5 — Sway, bob and tilt: additive procedural offsets on the weapon node

`Jeh3no/...` `Weapons/Scripts/animation_manager_script.gd` is the most complete readable implementation.
Three independent generators, each lerping its own persistent accumulator, summed once per frame:

```gdscript
func weapon_model_positioning(tilt_values, sway_values, bob_values) -> void:
	current_weapon.model.position = current_weapon.resources.pos_val[0] + sway_values[0] + bob_values
	current_weapon.model.rotation = current_weapon.resources.pos_val[1] + sway_values[1] + tilt_values
```

**Sway — driven by mouse delta, not velocity.** Target offset is proportional to clamped `mouse_input`,
lerped in both position and rotation:

```gdscript
sway_pos_target.x =  mouse_input.x * sway_amount_pos
sway_pos_target.y = -mouse_input.y * sway_amount_pos
current_sway_pos_val = lerp(current_sway_pos_val, sway_pos_target, sway_speed_pos * delta)

sway_rot_target.y = -deg_to_rad(mouse_input.x * sway_amount_rot)
sway_rot_target.x =  deg_to_rad(mouse_input.y * sway_amount_rot)
```

The detail worth stealing is the dead-zone return, with a comment that names the exact failure mode:

```gdscript
if mouse_input.length() <= 4.0:
	# "resets the value to exactly 0, prevents the drift caused by the lerp"
	current_sway_pos_val.x = move_toward(current_sway_pos_val.x, 0.0, delta * back_to_origin_pos_speed)
```

`lerp` is asymptotic and never reaches its target; `move_toward` is linear and does. Mixing them —
`lerp` while moving, `move_toward` at rest — is the standard fix for a weapon that never quite re-centres.

**Bob — sinusoid scaled by speed**, with the horizontal axis at half the vertical frequency, which is
what produces the figure-eight rather than a bounce:

```gdscript
bob_pos_target.y = sin(Time.get_ticks_msec() * (bob_freq / 100.0))       * (bob_amount / 100.0) * vel
bob_pos_target.x = sin(Time.get_ticks_msec() * (bob_freq / 100.0) * 0.5) * (bob_amount / 100.0) * vel
```

Driving phase from `Time.get_ticks_msec()` rather than an accumulator is a mild flaw — phase is not
pausable and not resettable on stop. Your ancestor did it correctly with an accumulator whose rate
switches on sprint (`kriegsnacht.html:2952`): `P.bobPhase += dt*(sprinting?13:9.4)`.

**Tilt / lean** is a lerp toward `input.x * tilt_rot_amount` on a configurable axis. Camera-side roll is
the same idea in `camera_script.gd`, with a useful distinction the author documents: forward/back tilt is
a one-shot `Tween` fired on *movement start*, while strafe tilt is a continuous `lerp` — because
"in most first person games, forward and backward tilt is not continuous."

**Per-state bob parameters** — `AxelReviron` drives bob constants from the movement state machine, so
sprint bob differs from walk bob at the call site rather than via a branch inside the bob function:

```gdscript
# sprinting_player_state.gd
WEAPON.sway_weapon(delta, false)
WEAPON.weapon_bob(delta, Constants.WEAPON_SPRINTING_BOB_SPEED,
	Constants.WEAPON_SPRINTING_BOB_H_AMOUNT, Constants.WEAPON_SPRINTING_BOB_V_AMOUNT)
```

**Tier 3, independent corroboration: 3.** One caution: `Jeh3no`'s camera bob accumulates into
`camera.v_offset` with `+=` and then clamps to `[0, cam_max_v_offset]`, which half-rectifies the sine and
lets the camera ride high. Read it, don't copy it.

---

### F6 — ADS: marker-to-marker transform tween plus a separate FOV tween

`bukkbeek/GodotFPS-Template` `common/weapon/weapon.gd` is the cleanest pattern found. Two `Marker3D`
nodes per weapon hold the hip and sighted poses; ADS tweens the arms root between them:

```gdscript
@onready var standard_aim_position: Marker3D = $StandardAimPosition
@onready var focused_aim_position:  Marker3D = $FocusedAimPosition

func _on_aim_mode_changed(aim_mode: bool) -> void:
	if aim_tween: aim_tween.kill()          # kill before retarget, or the tweens fight
	aim_tween = create_tween()
	aim_tween.set_parallel(true)
	aim_tween.set_ease(Tween.EASE_IN_OUT)
	aim_tween.set_trans(Tween.TRANS_CUBIC)
	var target_transform = focused_aim_position.transform if aim_mode else standard_aim_position.transform
	aim_tween.tween_property(fps_arms_root, "transform", target_transform, AIM_TRANSITION_DURATION)
	if aim_mode:
		Global.active_camera_fov_changed.emit(focused_aim_fov)   # 60.0 default
```

Iron-sight alignment is therefore **authored, not computed**: you place `FocusedAimPosition` so the
sight line lands on the screen centre. Camera FOV is a *separate* channel emitted as a signal, so the
weapon transform and the camera zoom are independently tunable — which matters, because they need
different curves to feel right.

Two further details worth copying: `activate()` **snaps** to the correct pose (and kills any live tween)
when a weapon is drawn while already aiming, so swapping weapons mid-ADS doesn't animate from a stale
pose; and sway reduction is handled by ADS-specific recoil vectors (`aim_recoil_amount_x/y` in
`AxelReviron`) rather than by scaling the sway generator.

`Jeh3no` implements only the FOV half (`zoom_val = 40.0`, `zoom_duration = 0.2`, tweened on
`camera.fov`) with no weapon-pose change.

**Tier 3, independent corroboration: 2.**

⚠️ **Rejected source.** `GarbajYT/godot-ads` ranks highly in search for this exact question and is
**Godot 3.x** — `extends KinematicBody`, `deg2rad`, `linear_interpolate`, `move_and_slide(movement, Vector3.UP)`.
Do not port it. <https://github.com/GarbajYT/godot-ads>

---

### F7 — Reload: per-part progression and mid-reload cancel exist; tactical-vs-empty does not

`Jeh3no/...` `reload_manager_script.gd` is the only surveyed implementation with real reload structure.
It reloads in `nb_parts_needed` discrete chunks — which is how you get shell-by-shell shotgun reloads
(directly relevant to your Olympia and Stakeout):

```gdscript
# "for a shotgun that can contain 8 shells, the number of parts to reload possible are : 1, 2, 4, 8"
if (total_ammo_in_mag_ref % nb_parts_needed) != 0:
	push_error("The number of parts set is not correct...")
```

Each part re-triggers the sound and animation (`play_sound_and_anim = true`), so the per-shell chunk
loops naturally. **Mid-reload cancel** is a single flag checked in `_process`:

```gdscript
func _process(delta: float) -> void:
	if current_weapon.resources.is_reloading and start_reload_timer and !force_reload_stop:
		reload_follow(delta)
	elif force_reload_stop:
		current_weapon.resources.is_reloading = false
		start_reload_timer = false
		return
```

Ammo is credited **per completed part**, so cancelling keeps the shells already loaded — the correct
behaviour, and it falls out of the structure rather than needing special-casing.

**Contrast — two implementations that get this wrong**, worth knowing so you don't copy them:

- `matiturock/fps-tutorial` `Weapon_State_Machine.gd:113-129` credits the **entire** magazine the instant
  the reload animation is *queued*. Cancel by weapon-swap and you keep the ammo for free. It does have a
  distinct `Out_Of_Ammo_Anim`, but that is "no reserve left", not "chamber was empty".
- `AxelReviron/...` `reloading_weapon_state.gd` reads the animation length into `duration` and then
  ignores it: `await get_tree().create_timer(1).timeout` — hardcoded 1 s regardless of weapon.

**Tactical (round in chamber) vs empty reload: found in zero surveyed projects.** No Godot 4 open-source
reference implements the mag+1 distinction or separate anim sets. **This is a genuine coverage gap**, not
a thing I failed to find — see Coverage gaps.

**Tier 3, independent corroboration: 1** (only Jeh3no does it properly).

---

### F8 — Draw / holster on weapon swap

Two patterns, both sound.

**Await-based, explicit timings** (`Jeh3no/...` `weapon_manager_script.gd`). `exit_weapon` → `enter_weapon`
chained with `await`, gated by two booleans, and — importantly — it force-clears in-flight shooting and
reloading state on both sides of the swap:

```gdscript
func exit_weapon(next_weapon: int) -> void:
	can_change_weapons = false
	can_use_weapon = false
	if current_weapon.resources.is_shooting:  current_weapon.resources.is_shooting = false
	if current_weapon.resources.is_reloading: current_weapon.resources.is_reloading = false
	anim_manager.play_animation("UnequipAnim%s" % ..., unequip_anim_speed, false)
	await get_tree().create_timer(current_weapon.resources.unequip_time).timeout
	current_weapon.model.hide()
	await enter_weapon(next_weapon)
```

Swap is refused outright while shooting or reloading (`change_weapon` guards on both). Weapons are
pre-instantiated and `hide()`/`show()`n rather than instantiated on demand — **relevant to you**: it
avoids a mid-gameplay scene instantiation, but it also means every weapon's material is resident, which
matters for shader compilation (see Measurement M3).

**Signal-based** (`matiturock/fps-tutorial`). Cleaner, no `await`:

```gdscript
func exit(_next_weapon: String) -> void:
	if _next_weapon != Current_Weapon.Weapon_Name:
		if Animation_Player.get_current_animation() != Current_Weapon.Change_Anim:
			Animation_Player.play(Current_Weapon.Change_Anim)
			Next_Weapon = _next_weapon

func _on_animation_player_animation_finished(anim_name) -> void:
	if anim_name == Current_Weapon.Change_Anim:
		Change_Weapon(Next_Weapon)          # holster finished → actually swap → play draw
```

**Tier 3, independent corroboration: 2.**

**Knife as an override.** `bukkbeek` models melee as a flag on the weapon resource
(`@export var is_melee_weapon: bool = false`) that short-circuits ammo consumption, muzzle flash and
bullet decals in the shared fire path — rather than as a separate weapon class. Your ancestor did the
equivalent at the render layer: `P.meleeT > 0` swaps the whole viewmodel canvas to the knife sprite and
drives a one-shot arc (`kriegsnacht.html:3130-3135`), restoring the previous weapon when the timer expires.
That "temporary override, auto-restore" shape is the right one for a quick-melee that does not change slots.

---

### F9 — Muzzle flash and shell ejection attachment

**Muzzle flash — well covered, two independent implementations.** Both attach to a `Marker3D` and
instantiate/enable a `GPUParticles3D`:

```gdscript
# Jeh3no — weapon_manager_script.gd
var muzzle_flash_ins: GPUParticles3D = current_weapon.resources.muzzle_flash_ref.instantiate()
add_child(muzzle_flash_ins)
muzzle_flash_ins.global_position = current_weapon.muzzle_flash_spawner.global_position
muzzle_flash_ins.emitting = true
```

```gdscript
# AxelReviron — muzzle_flash.gd: particles + a light, held for exactly one fire interval
muzzle_flash_light.visible = true            # OmniLight3D
muzzle_flash_emitter.emitting = true         # GPUParticles3D
await get_tree().create_timer(Global.player.WEAPON_CONTROLLER.fire_rate).timeout
muzzle_flash_emitter.emitting = false
muzzle_flash_light.visible = false
```

Note `Jeh3no` instantiates a node **per shot and never frees it** — a leak at 880 RPM. Prefer
`AxelReviron`'s persistent-emitter-toggled approach, which is also far better for a web build.

You already have the muzzle attachment data: `MUZZLE` at `kriegsnacht.html:2020` gives per-weapon
`[x, y]` offsets in the same 100×60 art space as `GUNART`, e.g. `m1911:[22,25]`, `rpk:[2,25]`,
`thundergun:[14,26]`. Those convert directly into `Marker3D` positions by the same transform you use to
build the mesh. The ancestor also varied flash colour per weapon — green `160,255,90` for the Ray Gun,
cyan `150,235,255` for the Thundergun, else `255,214,130` — and scaled radius by `2.2×` for cone weapons.

**Shell ejection — no reference implementation found.** Only unresolved forum threads, in which users
report `RigidBody3D` casings behaving erratically. **Tier 4, and I am not going to reconstruct an
implementation from it.** See Coverage gaps.

---

### F10 — Sprint-out / sprint-in and the fire gate

**Not implemented in any surveyed project.** `AxelReviron`'s `sprinting_player_state.gd` is the closest:
it swaps in sprint-specific bob constants and scales the animation speed by velocity, but it never blocks
firing — `GlobalInput.is_shooting()` remains live throughout sprint. `Jeh3no` has no sprint-out pose.
`bukkbeek` and `matiturock` have no sprint state at all.

The transferable structure that *does* exist is the gate pattern used for weapon swapping — a pair of
booleans (`can_use_weapon`, `can_change_weapons`) set false at the start of a transition and true at the
end, with the fire path checking them. Extending that to a `sprint_out` / `sprint_in` transition is
straightforward but is **your design work, not a port**.

**Tier 3 for the absence** (four repos read); see Coverage gaps.

---

## Recommendations for this project

### R1 — Do not use a SubViewport, and do not use the depth-hack shader. Constrain the geometry instead.

The clipping problem is usually framed as unavoidable because in most FPS games the gun is a large object
held close to the camera and the player can walk right up to a wall. **Your constraints remove the
premise.** `scripts/entities/player.gd:22` sets `RADIUS := 0.24` on the player capsule, so world geometry
can never come within 0.24 m of the camera origin. If the entire viewmodel mesh fits inside a sphere of
radius ~0.22 m centred on the camera, **wall clipping is geometrically impossible** — not mitigated, not
depth-tricked, impossible.

That is only useful if a 0.22 m gun still *looks* like a gun, and that is precisely what the FOV override
buys you. Write **only** the two scale terms of the projection matrix in `vertex()`, and write nothing else:

```glsl
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float viewmodel_fov : hint_range(20.0, 120.0) = 55.0;

void vertex() {
	float onetanfov = 1.0 / tan(0.5 * radians(viewmodel_fov));
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	PROJECTION_MATRIX[0][0] = onetanfov / aspect;
	PROJECTION_MATRIX[1][1] = onetanfov;   // SIGN IS UNVERIFIED ON gl_compatibility — see M1
}
```

Why this is the right call under your constraints:

- **No `POSITION` write, no `DEPTH` write.** You are therefore immune to the entire reverse-Z breakage
  described in F3, and you keep early-Z. The docs confirm `PROJECTION_MATRIX` is `inout` in `vertex()`
  and that the built-in transform uses it when `POSITION` is not written (tier 1).
- **You only touch `[0][0]` and `[1][1]`.** The depth terms `[2][2]`/`[2][3]` are untouched, so the
  viewmodel's depth stays consistent with the world — which is what makes the geometric no-clip guarantee
  hold rather than being papered over.
- **Zero extra passes, zero extra render targets, zero extra fill.** On a single-threaded WebGL2 build
  where you cannot background-load and cannot use threads, adding a full-screen viewport pass to solve a
  problem you can solve with a bounding-box budget is a bad trade.
- **The SubViewport route also costs you a second shader compile of every viewmodel material**, on the
  main thread, at whatever moment the player first draws that weapon — which is the failure mode your
  constraints care most about.

**Fallback ladder if the FOV override misbehaves on Compatibility** (see M1): (1) drop the shader
entirely and just tune the mesh scale and camera distance until it reads correctly at the world FOV of
74 — entirely viable for a stylised gun; (2) only then consider the SubViewport, and measure it.

### R2 — Build the viewmodel mesh procedurally from `GUNART`. Do not source models.

**Recommended: procedural extrusion.** `GUNART` (`kriegsnacht.html:1150`) is already a 3D-ready spec.
Every entry is `['r', x, y, w, h, colour]` — an axis-aligned rectangle in a 100×60 space — with a handful
of `'c'` circles (Ray Gun lens, RPK drum), `'p'` polygons (the knife blade) and one `'rr'` rotated rect
(MP40/PM63 stock). Weapons run 4–10 parts each:

```javascript
m1911:[ ['r',30,22,26,7,'#2A2C2E'], ['r',26,20,32,4,'#3E4245'],
        ['r',22,23,10,4,'#1F2123'], ['r',52,26,7,16,'#5A3B1E'], ... ]
```

Map each rect to a box: `x,y,w,h` become width/height in the gun's local XY, a constant depth becomes Z,
and the hex colour becomes a vertex colour. That is ~6 boxes × 12 tris = **~72 triangles per weapon**.
Circles become low-segment cylinders; the knife polygon becomes an extruded prism. Thirteen viewmodels,
one builder, no files.

Why this over the alternatives, specifically for this project:

- **You already have this exact pipeline.** `scripts/world/world_builder.gd` builds all world geometry
  with `SurfaceTool`, uses `vertex_color_use_as_albedo = true`, `TEXTURE_FILTER_NEAREST`,
  `roughness = 1.0` and `SPECULAR_DISABLED`. A weapon built the same way is stylistically identical to
  the level *by construction* — same lighting response, same flat unlit-ish read, same palette
  discipline. Nothing else you could source has that property.
- **It is the only option that makes the mechanics real.** Sway, recoil, ADS alignment and the muzzle
  `Marker3D` all need a thing that exists in 3D space. `MUZZLE` (`:2020`) already gives you per-weapon
  muzzle coordinates in the same coordinate space as the parts — the attachment point is *free*.
- **Pack-a-Punch is free.** The ancestor did the PaP variant as a `source-atop` composite tint pass
  (`makeViewmodel(art, 'rgba(96,64,200,.42)')`). In 3D that is one material with a tint uniform, or a
  vertex-colour multiply. No second asset.
- **Cost is bounded and one-time.** One ~150-line builder, then all 12 weapons plus the knife plus every
  future weapon are free. Compare with authoring or sourcing 12 models individually.

**Rejected: 12 CC0 models.** Kenney's kits are the only CC0 source with genuinely consistent style and a
permissive licence — Blaster Kit is CC0, 40 objects, no attribution required, multiple formats
(<https://kenney.nl/assets/blaster-kit>) — but they are **sci-fi blasters**. You need an M1911, an MP40,
an M14, an AK-74u, a China Lake. Kenney's `Starter-Kit-FPS` (CC0, Godot 4) ships `blaster.glb` and
`blaster-repeater.glb`; same mismatch. Assembling 12 era-correct WWII/Cold-War weapons at CC0 from mixed
authors gives you 12 different polycounts, texel densities and art styles, and anything photoreal fights
your nearest-neighbour billboard aesthetic head-on. This is the worst option, not merely a weaker one.

**Rejected but respectable: 2D sprite viewmodel.** This is what the ancestor did and what many retro
shooters still do, and it has real merits — zero clipping by construction, one textured quad of fill, no
shader risk, and `makeViewmodel()` ports almost literally to `Image`/`ImageTexture` on a `CanvasLayer`.
The ancestor even anticipated the flatness problem with a `-0.09` rad tilt "so it doesn't read as a flat
cutout." **Take this as your fallback if R1's measurements go badly**, or as a 2-hour stopgap to close
the "no viewmodel at all" gap immediately. But it caps you permanently: ADS becomes a fake zoom, recoil
cannot rotate in depth, and the muzzle flash is a screen-space blob rather than a world-space light.

### R3 — Port the ancestor's spring, not the two-lerp recoil

You have a properly-integrated damped oscillator already tuned (`kriegsnacht.html:2960`, stiffness 46,
damping 11) and a dead `_recoil` variable at `scripts/entities/player.gd:41` waiting for it. Restore it
as the **view kick**, then add `AxelReviron`'s **weapon kick** as a separate positional offset on the
viewmodel node at roughly half magnitude, back-and-up. Per-weapon patterns come from the `kick` value
already in your weapon table (`kriegsnacht.html:1459-1470`: `m1911` 1.3 … `thundergun` 4.2), which is
also already wired to screen shake at `:2526`.

### R4 — Layer procedural motion under authored animation, and keep the channels separate

Adopt `Jeh3no`'s additive structure (F5): sway, bob and tilt each own a persistent accumulator, summed
into `position`/`rotation` of a **weapon holder** node. Put authored clips (reload, draw, holster, knife
swing) on an `AnimationPlayer` targeting a **child** of that holder, so procedural and authored motion
compose instead of overwriting each other. `Jeh3no` applies both to the same node, which is a latent
conflict — fix it on the way in. Use `move_toward` (not `lerp`) for the return-to-rest of every channel.

### R5 — Drive bob and the fire gate from the movement state, and design sprint-out yourself

Use `AxelReviron`'s pattern of passing bob constants from the movement state (F5), and extend the
`can_use_weapon` gate pattern from `Jeh3no`'s weapon swap (F8) to cover sprint-out. Since no reference
implementation exists (F10), the CoD convention to implement is: sprint-out plays a lower-the-weapon
pose over ~0.2 s during which firing is refused; pressing fire during sprint-out **queues** the shot and
triggers sprint-in rather than dropping the input. You already have a queued-input idiom in
`scripts/entities/player.gd` (`_fire_queued`).

### R6 — Fix the renderer declaration before you touch any of this

`project.godot:20` declares `config/features=PackedStringArray("4.7", "Forward Plus")`, and the
`[rendering]` section (line 112) sets no `renderer/rendering_method` and no `.web` override. The docs are
unambiguous that web can only use Compatibility (*"You are developing for web. In this case, Compatibility
is the only choice."*, tier 1, <https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html>).
So **every editor run tests a renderer you do not ship**. For viewmodel work specifically this is
disqualifying: F3 establishes that projection-matrix and depth conventions are exactly where the two
renderers can diverge. Set `rendering_method` to `gl_compatibility` (or at minimum add the `.web`
override and test in-browser) *before* measuring anything in M1–M3.

---

## Coverage gaps

1. **Tactical vs empty reload — no implementation exists in any surveyed Godot 4 project.** I read the
   reload path in four templates (`Jeh3no`, `matiturock`, `AxelReviron`, `bukkbeek`). None distinguishes
   "round still in the chamber" (mag capacity + 1, shorter animation, no bolt-catch release) from a dry
   reload. `matiturock`'s `Out_Of_Ammo_Anim` is a *reserve-empty* case, which is a different thing. This
   must be designed, not ported.
2. **Shell / casing ejection — no reference implementation found.** Only two unresolved Godot forum
   threads (tier 4) in which users report `RigidBody3D` casings behaving inconsistently. I did not find
   working code and have not reconstructed any. Note that on your target you would likely want a
   `GPUParticles3D` one-shot or a small pooled `MultiMeshInstance3D`, never per-shot rigid bodies — but
   that is my reasoning from your constraints, not a cited finding.
3. **Sprint-out / sprint-in poses and the fire gate — absent from all four templates** (F10). The gate
   *pattern* is portable; the sprint-specific behaviour is not attested anywhere I looked.
4. **No measured cost for a SubViewport viewmodel on WebGL2.** The single data point I found
   (<1 FPS on HTML5) is a tier-4 unresolved forum thread with a confounded setup (many SubViewports,
   Control-based 2D game). I deliberately did **not** treat it as evidence about a single full-window
   viewmodel viewport. This is genuinely unmeasured — see M2.
5. **Whether the reverse-Z announcement's guidance was ever revised for Compatibility.** The article
   itself does not name any renderer (verified by fetch). I established Compatibility's reverse-Z status
   from engine source (`GL_GREATER`) instead, which is stronger — but I did not find a maintainer
   statement confirming that the *shader-authoring* guidance is identical across renderers.
6. **Godot 4.7-specific behaviour.** All code evidence is 4.2–4.4 era (`Jeh3no` targets 4.4+ per its use
   of typed `Dictionary[String, Vector2]`; `AxelReviron` states 4.4.1). Engine-source claims were checked
   against `godotengine/godot` master. **I found no 4.7-specific viewmodel material at all**, and no
   evidence of viewmodel-relevant changes between 4.4 and 4.7 — but I could not affirmatively verify
   their absence.
7. **`bukkbeek/GodotFPS-Template`'s renderer** could not be determined — its `project.godot` has no
   rendering section in the fetched copy, implying engine default (Forward+). None of the four templates
   shows any evidence of having been tested on Compatibility or web.

---

## What must be measured rather than researched

### M1 — Does the vertex-only `PROJECTION_MATRIX` FOV override behave identically on `gl_compatibility`?

**Why it cannot be researched.** Godot 4 flips clip-space Y relative to Godot 3, and the community
shaders disagree about the sign: `matiturock` uses `PROJECTION_MATRIX[1][1] = -onetanfov`, the Godot 3
original uses `+onetanfov`, and the godotshaders 4.3+ variant uses yet another arrangement
(`scale / (-VIEWPORT_SIZE.x / VIEWPORT_SIZE.y)` on `[0][0]`, `+scale` on `[1][1]`). Every one of those was
written against Forward+. Whether the Compatibility backend, which renders to an OpenGL framebuffer with
opposite texture-space Y convention, needs the same sign is **not documented anywhere I could reach**.

**Procedure.**
1. Set `renderer/rendering_method="gl_compatibility"` and `renderer/rendering_method.mobile="gl_compatibility"`
   in `project.godot` (R6).
2. Build a test scene: an asymmetric viewmodel mesh (deliberately non-mirror-symmetric — put a marker on
   the right side and a different one on top) parented to the camera at ~0.15 m forward.
3. Apply the R1 shader with `viewmodel_fov = 55`. Run in the **editor** (Forward+ before step 1 / Compatibility
   after) and in an **exported web build served over HTTP** — not `file://`.
4. Record for each: is the mesh upside-down? mirrored? correctly scaled relative to `viewmodel_fov`?
5. If the sign differs between renderers, gate it with a `uniform float y_sign` set from GDScript via
   `RenderingServer.get_video_adapter_api_version()` or simply `OS.has_feature("web")`.

**Decision rule.** If the override renders correctly on Compatibility → ship R1. If it renders wrong in a
way a sign flip fixes → ship R1 with the uniform. If it is wrong in any other way → drop the shader,
tune mesh scale at the native FOV of 74, and re-measure apparent size by eye against the reference
screenshots of the ancestor.

### M2 — What does a full-window SubViewport actually cost on your target hardware?

Only run this if M1 forces you toward the SubViewport fallback.

**Procedure.**
1. Build two exported web builds identical except for the viewmodel path: (A) direct-render with R1,
   (B) `SubViewport` + mirrored camera per F2.
2. Serve both from GitHub Pages (or any HTTP host) — **not** the editor, and not a desktop export.
   Compatibility-in-editor is still not WebGL2-in-browser.
3. On each, stand at a fixed spawn point looking at a fixed high-fill view (a wall at close range, to
   maximise overdraw), and capture 600 frames of `Performance.get_monitor(Performance.TIME_PROCESS)` and
   `RenderingServer.get_frame_setup_time_cpu()`, plus browser-side `performance.now()` deltas.
4. Repeat at 1× and 0.5× `SubViewport` resolution scale.
5. Test on the weakest device you intend to support, and in **both** Chrome and Firefox — WebGL2 driver
   paths differ materially between them.

**Decision rule.** If (B) costs more than ~1.5 ms/frame over (A) at your target resolution, the
SubViewport is not affordable and the answer is R2's 2D-sprite fallback.

### M3 — When does the viewmodel material's shader compile, and does it hitch?

**Why it matters more here than anywhere else.** Threads are off, so shader compilation is synchronous on
the main thread. A custom viewmodel shader compiled the first time the player draws the Ray Gun is a
visible hitch at exactly the worst moment.

**Procedure.**
1. In an exported web build, instrument weapon-draw with `Time.get_ticks_usec()` around the first
   `show()`/material assignment of each of the 13 viewmodels.
2. Log the delta for first draw vs subsequent draws of the same weapon.
3. If first-draw deltas exceed ~5 ms, force compilation during the loading screen by rendering every
   viewmodel material once off-screen (a 1-frame pass at 1×1, or `mesh.surface_get_material()` touch plus
   a forced draw) before gameplay starts.

**Note.** This is why R1's single shared shader for all 13 weapons matters: one shader variant compiled
once, rather than a per-weapon material zoo.

### M4 — Does the geometric no-clip guarantee actually hold?

**Procedure.** After building the mesh (R2), compute its AABB in camera space and assert
`aabb.get_longest_axis_size()` keeps every corner within 0.22 m of the camera origin — as a unit test, so
that adding a long-barrelled weapon (the RPK and China Lake are the risks) fails loudly rather than
silently reintroducing clipping. Then walk the player into every wall type, every door frame, and every
window board at every look angle, and confirm no intersection. Corners are the adversarial case: the
capsule permits the camera to get closer to a *convex corner* than to a flat wall, so test interior
corners explicitly.

---

## Source index

| # | Source | Tier | Used for |
|---|---|---|---|
| 1 | [Camera3D class ref](https://docs.godotengine.org/en/stable/classes/class_camera3d.html) | 1 | One active camera per viewport |
| 2 | [Spatial shader ref](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html) | 1 | `PROJECTION_MATRIX` is `inout`; `POSITION`/`DEPTH` semantics |
| 3 | [Renderers doc](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) | 1 | Compatibility is the only web renderer; unsupported feature list |
| 4 | `godotengine/godot` `drivers/gles3/rasterizer_scene_gles3.cpp`, `storage/light_storage.cpp` | 1 | `GL_GREATER` → reverse Z active in Compatibility |
| 5 | [Introducing Reverse Z](https://godotengine.org/article/introducing-reverse-z/) | 1 | 4.3 reverse Z; clip-space guidance; silent on renderers |
| 6 | [godot-proposals#956](https://github.com/godotengine/godot-proposals/issues/956) | 2 | Multi-camera unsupported; viewmodel use case |
| 7 | [Jeh3no/Godot-simple-FPS-weapon-system](https://github.com/Jeh3no/Godot-simple-FPS-weapon-system) | 3 | SubViewport, recoil, sway/bob/tilt, per-part reload + cancel, swap, muzzle |
| 8 | [AxelReviron/Godot-FPS-Template](https://github.com/AxelReviron/Godot-FPS-Template) | 3 | View kick vs weapon kick, per-state bob, muzzle flash, weapon states |
| 9 | [bukkbeek/GodotFPS-Template](https://github.com/bukkbeek/GodotFPS-Template) | 3 | ADS marker tween + FOV signal, melee flag, SubViewport |
| 10 | [matiturock/fps-tutorial](https://github.com/matiturock/fps-tutorial) | 3 | Shader *and* SubViewport variants side by side; swap via anim-finished |
| 11 | [vi4hu/godot-procedural-recoil](https://github.com/vi4hu/godot-procedural-recoil) | 3 | Two-lerp recoil, independent |
| 12 | [majikayogames gist](https://gist.github.com/majikayogames/94ac6c76650a609e4db09febb82ab197) | 3 | Reverse-Z-correct clip shader |
| 13 | [godotshaders 4.3+ viewmodel](https://godotshaders.com/shader/first-person-view-model-shader-updated-for-godot-4-3/) | 3 | Fragment `DEPTH` variant (not recommended) |
| 14 | [Braboware/...-annotated](https://github.com/Braboware/godot-viewmodel-render-test-annotated) | 3 | Godot 3.x origin of the shader; annotated intent |
| 15 | [Kenney Blaster Kit](https://kenney.nl/assets/blaster-kit) / [Starter-Kit-FPS](https://github.com/KenneyNL/Starter-Kit-FPS) | 3 | CC0 licensing confirmed; style mismatch |
| 16 | [SubViewport web perf thread](https://forum.godotengine.org/t/subviewport-rendering-performances-on-web/101434) | 4 | Unresolved, confounded — flagged not relied on |
| 17 | [GarbajYT/godot-ads](https://github.com/GarbajYT/godot-ads) | — | **Rejected: Godot 3.x** |
| 18 | `kriegsnacht.html` (local) | 1 | `GUNART` :1150, `MUZZLE` :2020, `drawViewmodel` :3106, recoil spring :2960, bob :2952, weapon table :1459 |
| 19 | Project source (local) | 1 | `player.gd:22` RADIUS, `:41` dead `_recoil`, `world_builder.gd` SurfaceTool pipeline, `project.godot:20` renderer |
