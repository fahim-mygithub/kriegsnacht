# M2 — Enemy animation, dismemberment, gore and death in Godot 4

Research brief for **Kriegsnacht** (Godot 4.7, single-threaded HTML5/WebGL2 on GitHub Pages, solo dev, procedural pixel-art billboards).
Answers gap-analysis item **T0.8 — Decide the enemy representation: billboard or rigged mesh**.

Date: 2026-07-27 · Evidence tiers: **1** official docs/source · **2** maintainer statement/tracked issue · **3** reputable secondary or maintained reference implementation · **4** community anecdote.

---

## Bottom line

- **Stay on billboards. The blocking constraint is not fidelity, it is the platform.** Two Tier-1 facts settle it: the Compatibility renderer is *the only* renderer on web, and **the shader baker and pipeline precompilation explicitly do not work on web or on Compatibility** — "This page only applies to the Forward+ and Mobile renderers, not Compatibility… The shader baker is not supported on the web platform." Every new material a 3D zombie introduces (skinned body, gib, blood, decal) compiles **on the main thread, mid-round, on first sight**, and you have no thread to hide it on. The documented mitigation is the 1998 one: draw everything once, invisibly, during load.
- **Do not hand-draw 8 directions. Generate 5 and mirror.** DOOM's own convention packs rotations 2↔8, 3↔7, 4↔6 as horizontal mirrors of one drawing; only rotations 1 (front) and 5 (back) are unique. That is **5 unique columns for full 8-direction coverage**, a 37.5 % saving. At 3 palettes × 5 columns × 15 frames of 48×64 RGBA8 the whole zombie atlas is **≈ 2.8 MB VRAM / ≈ 300 KB of PNG** — a non-issue. The cost was never memory; it is authoring, and `sprite_lib.gd` tells us the sprites are *replayed canvas drawing code*, so five views is **five draw routines, not 225 hand-drawn cells**.
- **The two headline gore beats are already nearly free and need zero new art.** Walker→crawler is `SpriteLib.frames_for("crawler", pal)` + swap `pixel_size` (0.62/34 vs 1.82/64) + shrink the collider + drop the speed — all three crawler palettes exist. Glowing eyes are a child `Sprite3D` with `shaded = false`; **glow *is* supported in Compatibility** (docs table: ✔️ all three renderers), correcting the stale 2022 tracker entry that says otherwise.
- **`Decal` does not exist on this platform, but blood decals are still cheap.** Official guidance: "If using the Compatibility renderer, consider using Sprite3D as an alternative for projecting decals onto (mostly) flat surfaces." For volume, `antzGames/Godot-Compatibility-Decal-Node` renders "thousands of decals… with one draw call" and is tested on 4.4.1–4.6.2.
- **If you ever want 3D animation richness, buy it offline, not at runtime.** Render a Mixamo-rigged zombie through a Blender 8-direction batch renderer (`chronicleroflegends/DirectionalSpriteBatchRender` is literally built for ZDoom-convention billboards), quantise to the existing palette, ship sprites. You get run/sprint/climb/crawl/death-variant animation *and* keep the pixel-art identity, at zero runtime skinning cost. This is the third option the gap analysis did not consider and it dominates both named branches.
- **"Something is behind me" is an audio problem, not an art problem.** No enemy-facing artwork tells you about an enemy that is off-screen. 8-direction sprites answer "which way is that one looking"; they do not answer "what is behind me". The backlog already has the right fix (VS-1/VS-2: `AudioStreamPlayer3D` groans) — do not spend the enemy-art budget trying to solve a spatial-audio problem.

---

## Findings

### Platform constraints (these dominate everything else)

**F1 — No shader precompilation on web or Compatibility. Tier 1. Corroboration: 1 (single authoritative source, unambiguous).**
> "This page only applies to the Forward+ and Mobile renderers, not Compatibility. Ubershaders and pipeline precompilation rely on functionality only available in modern low-level graphics APIs (Vulkan, Direct3D 12, Metal)." … "The shader baker is not supported on the web platform, as the web platform only supports the Compatibility renderer."
Recommended fallback, verbatim: "use the legacy approach of preloading materials, shaders, and particles by displaying them for at least one frame in the view frustum when the level is loading."
https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html
*Consequence:* every distinct material/shader permutation you add is a one-time main-thread hitch the first time it is visible. This scales with **material variety**, not entity count — which is a direct argument against a 3D zombie with per-limb materials, gib meshes and a separate decal shader.

**F2 — `Decal` is unsupported in Compatibility; `Sprite3D` is the sanctioned substitute. Tier 1. Corroboration: 2.**
Renderer comparison table: Decals — Compatibility ❌ / Mobile ✔️ / Forward+ ✔️.
https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
> "Decals are only supported in the Forward+ and Mobile renderers, not the Compatibility renderer." … "If using the Compatibility renderer, consider using Sprite3D as an alternative for projecting decals onto (mostly) flat surfaces."
https://github.com/godotengine/godot-docs/blob/master/tutorials/3d/using_decals.rst
Open proposal discussion confirming the gap: https://github.com/godotengine/godot-proposals/discussions/12903 (Tier 2)

**F3 — Glow *is* supported in Compatibility. Tier 1. Corroboration: 2 (docs + a 2025 bug report that presupposes it works).**
The stable (4.7) renderer table lists Glow as ✔️ Supported for Compatibility, Mobile and Forward+.
https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
**This corrects a widely-repeated stale claim.** The 2022 Compatibility tracker (https://github.com/godotengine/godot/issues/66458, Tier 2) still lists "Environment glow" as unimplemented; that entry is four years old. A 2025 issue — "Glow lights up the WorldEnvironment Sky in Compatibility Renderer" (https://github.com/godotengine/godot/issues/106702, Tier 2) — reports glow *misbehaving*, which only makes sense if it exists. Caveat: it is the least-exercised glow path; expect to tune `glow_hdr_threshold` and watch the sky.

**F4 — MSAA 3D *is* supported in Compatibility. Tier 1. Corroboration: 1.**
Renderer table: MSAA 3D — ✔️ on all three. This validates gap-analysis item **T0.7** (turning on MSAA to stop alpha-scissor billboard edges crawling) as a pure settings win with no renderer caveat.
https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html

**F5 — `GPUParticles3D` works in Compatibility, but has a known web-specific stall. Tier 1 + 2. Corroboration: 3.**
The renderer table marks *particle trails* and *particle SDF collision* as unsupported while saying nothing against base particles (Tier 1). Godot 4.3 release notes claim a Compatibility 3D frame-rate gain "and more if you heavily use GPUParticles" (https://godotengine.org/releases/4.3/, Tier 1). A maintainer-triaged benchmark issue compares `GPUParticles3D` throughput *between* Compatibility and Forward+ (https://github.com/godotengine/godot/issues/97903, Tier 2).
**But:** on web + Compatibility, setting `GPUParticles3D.draw_order = VIEW_DEPTH` produces WebGL pipeline stalls — "READ-usage buffer was read back without waiting on a fence. This caused a graphics pipeline stall." Reported on 4.3.stable and 4.4.1.stable, still "Up for grabs", no fix, no maintainer workaround stated.
https://github.com/godotengine/godot/issues/107633 (Tier 2)
*Inference (mine, not sourced):* use `draw_order = INDEX` or `LIFETIME` for blood, or use `CPUParticles3D`, which sidesteps both this bug and F1's first-emission compile.

**F6 — Compatibility skeleton rendering has open correctness bugs. Tier 2. Corroboration: 2.**
Incorrect skeleton + UV under `gl_compatibility` (https://github.com/godotengine/godot/issues/67522); incorrect shading on normal-mapped skinned models under GLES3, reproducible in 4.2.2, 4.3 and 4.4 (https://github.com/godotengine/godot/issues/94500). Neither is fatal, but skinned meshes are demonstrably the less-travelled path on the renderer you are forced to ship.

---

### Branch A — stay 2D, go deeper

**F7 — DOOM's 8-direction convention needs only 5 unique drawings. Tier 3 (reference wiki, mechanically verifiable). Corroboration: 2 (doomwiki + two independent Godot implementations that follow the same 8-bucket scheme).**
> "The graphic 1 is used to draw a thing looking head-on; 2 through 8 are used as the thing is rotated in 45-degree steps clockwise (as viewed from above)." … "TROOA2A8 defines a graphic with prefix TROO for animation frame A rot 2. The same graphic, drawn in mirror image, is used for animation frame A rot 8."
https://doomwiki.org/wiki/Sprite
**Arithmetic correction:** an automated summary of this page told me "only 4 unique drawn rotations are necessary". That is wrong. Rot 1 (front) and rot 5 (back) are self-facing and cannot be mirrored to anything; 2↔8, 3↔7, 4↔6 are the three mirror pairs. **1 + 3 + 1 = 5 unique columns.** Do not budget for 4.

**F8 — Facing-index computation: two working open-source formulations. Tier 3. Corroboration: 3 independent implementations.**
*(a) Dot-product buckets* — `DataPlusProgram/GodotWadImporter`, `addons/godotWad/scenes/enemies/npc.gd`, verbatim:
```gdscript
func closesOrdinal(target, targetToMe):
    var cameraForward : Vector3 = targetToMe
    var forward : Vector3 = -target.global_transform.basis.z
    var left : Vector3 = target.global_transform.basis.x
    var forwardDot : float = forward.dot(cameraForward)
    if forwardDot < -0.85:   return Vector3.BACK
    elif forwardDot > 0.85:  return Vector3.FORWARD
    else:
        var leftDot : float = left.dot(cameraForward)
        ...
```
https://github.com/DataPlusProgram/GodotWadImporter — a full DOOM WAD importer for Godot; the closest thing to a canonical reference for this exact problem.
*(b) Signed-angle buckets* — `Hornost/GOOM`, `addons/squash/billboard_mesh.gd`:
```gdscript
func get_angle(pos1:Vector3, pos2:Vector3, forward):
    return rad_to_deg((Vector3(pos1.x, pos2.y, pos1.z) - pos2).signed_angle_to(forward, Vector3.UP))
# then: if angle > -22.5 and angle < 22.6: idx = 0 ... if angle >= 67.5 and angle < 112.5: idx = 6
```
plus `crop_to_smaller()` which slices the atlas into 8 equal horizontal regions.
https://github.com/Hornost/GOOM
*(c) Third corroboration:* `AleksLitynski/Tombworld-Public`, `TombWorld/entities/facing_sprite.gd` — same pattern (`BILLBOARD_FIXED_Y` + `angle_to` between facing and camera-direction, swizzled to XZ).
**The idiomatic 4.x one-liner** (mine, derived from the above — verify by running it, not by trusting me):
```gdscript
var to_cam := cam.global_position - global_position
var rel := wrapf(atan2(to_cam.x, to_cam.z) - atan2(-basis.z.x, -basis.z.z) + PI / 8.0, 0.0, TAU)
var dir := int(rel / (TAU / 8.0)) % 8          # 0 = front, 4 = back
var col := dir if dir <= 4 else 8 - dir        # 5 unique columns
sprite.flip_h = dir > 4                        # mirror the other three
```
Note `AnimatedSprite3D` exposes `flip_h`, so mirroring costs nothing — no second atlas.

**F9 — Off-the-shelf Godot 4 8-direction addons exist. Tier 3.**
- `styr0x/2.5D-Sprite-Rotator--Godot-4-` — MIT, "8-directional sprite rotation system like the ones of classic 90's FPS games". https://github.com/styr0x/2.5D-Sprite-Rotator--Godot-4-
- `23Bluemaster23/GodotSprite3DPlus` — MIT; provides `SimpleSprite3DBillBoard` (Doom-style 8-direction) and `Sprite3DBillBoard` (multi-animation via an `AnimationData` resource); shader-based rather than script-based. Godot version unstated — **verify before adopting.** https://github.com/23Bluemaster23/GodotSprite3DPlus
- Non-open-source but proven, for reference only: RNB Games "8 directional Sprite + FPS Controller" (itch.io, updated for 4.3), FelixarStudio "Ultimate Retro Shooter Template".

**F10 — Atlas / VRAM budget (computed, not retrieved).**
Assume 15 frames per direction (6 walk + 2 attack + 4 death + 3 flinch/limbless), 3 palettes, cells 48×64 RGBA8.

| Layout | Cells | Pixels | VRAM (RGBA8) |
|---|---|---|---|
| 8 directions, no mirroring | 3 × 8 × 15 = 360 | 1,105,920 | **4.42 MB** |
| **5 columns + `flip_h`** | 3 × 5 × 15 = 225 | 691,200 | **2.76 MB** |
| + crawler (48×34, 7 frames) | 105 | 171,360 | 0.69 MB |
| + hound (56×40, 7 frames) | 35 | 78,400 | 0.31 MB |
| **Total enemy sprite VRAM** | | | **≈ 3.8 MB** |

Sheet layout: 15 frames wide × 5 rows = **720 × 320 per palette**; three stacked = one 720 × 960 texture. WebGL2 supports non-power-of-two textures with `CLAMP_TO_EDGE` and no mipmaps, and the project already sets `mipmaps/generate=false` in every `.png.import`, so **no POT padding is required**.
Download size: existing strips run ≈ 1.3 KB/frame of PNG (measured: `zombie0_walk.png` = 8,560 B for 6 frames). 225 frames ≈ **300 KB**, negligible on GitHub Pages.
**Conclusion: memory was never the constraint. Authoring is.** And `scripts/world/sprite_lib.gd` documents that the PNGs "were generated by replaying the browser build's own canvas drawing code" — so the deliverable is *five view-specific draw routines in the generator*, not 225 hand-drawn cells. This is the single most important fact about Branch A's real cost.

**F11 — 2D dismemberment: the limbless-variant + gib-burst pattern. Tier 3 (technique), Tier 1 (mechanism).**
No Godot-specific open-source 2D dismemberment implementation surfaced (see Coverage gaps). The genre-standard structure, and the one your codebase is already shaped for:
1. **Limbless variant** — a second `SpriteFrames` set drawn without the arm/leg. Because the generator is code, this is a boolean passed into the draw routine, not a new art pass. Swap `AnimatedSprite3D.sprite_frames` and re-seek to the current frame so the gait does not pop.
2. **Gib burst** — `CPUParticles3D` (F5) with a small gib texture, or 3–6 pooled `Sprite3D` nodes on ballistic arcs. Reuse the existing 1 px dark rim so gibs read against the floor.
3. **Crawler transition** — see F12.
`AnimatedSprite3D` supports runtime `sprite_frames` reassignment; `SpriteLib._cache` already memoises per `kind+pal`, so the swap is a dictionary lookup, no load hitch.

**F12 — The walker→crawler conversion is ~20 lines and needs zero new art. Tier 1 (your own code).**
`scripts/world/sprite_lib.gd` already ships `crawler` at 48×34 with `walk: 4, death: 3, pal: 3` and `HEIGHT["crawler"] = 0.62`. On a legs-destroyed event:
```gdscript
_sprite.sprite_frames = SpriteLib.frames_for("crawler", pal)
_sprite.pixel_size    = SpriteLib.pixel_size("crawler")   # 0.62 / 34
_sprite.position.y    = 0.62 * 0.5                        # re-seat on the floor
_collider.shape.height = ...                              # shrink capsule
speed *= CRAWLER_SPEED_MUL
head_threshold_override = ...                             # headshots must still work
```
Everything the conversion needs already exists. **This is the highest value-per-line item in the entire enemy-representation question and it is available today on billboards.**

---

### Branch B — go 3D skeletal

**F13 — Retargeting from Mixamo is a solved, first-party workflow. Tier 1. Corroboration: 2 (docs + many repos using `mixamorig_*` bone names).**
Godot has built-in humanoid retargeting: a `BoneMap` paired with `SkeletonProfileHumanoid`, plus a Rest Fixer (Apply Node Transform, Normalize Position Tracks, Overwrite Axis, Fix Silhouette for A-pose→T-pose) and a Bone Renamer. "When you use SkeletonProfileHumanoid, auto-mapping will be performed when the SkeletonProfile is set"; auto-mapping is name-pattern based, so "common English names for bones" work.
https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html
**The docs never mention Mixamo.** Corroboration that it works anyway: multiple live Godot 4 repos carry Mixamo-named bones through to physical bones, e.g. `duehringadam/husk` → `"Skeleton3D/PhysicalBoneSimulator3D/Physical Bone mixamorig_Hips_24"` (Tier 3).

**F14 — Mixamo licence: usable, with one clause that matters here. Tier 2 (Adobe community/FAQ). Corroboration: 3 (Adobe FAQ, Adobe community FAQ thread, third-party licence guide).**
Free, royalty-free, unlimited commercial or non-commercial use — **but** "Characters and animations cannot be redistributed as standalone assets — they must be incorporated into a project." Bulk downloading for ML training is also prohibited.
https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html · https://community.adobe.com/t5/mixamo-discussions/mixamo-faq-licensing-royalties-ownership-eula-and-tos/td-p/13234775
**Applied to this project:** a Godot web export is "incorporated into a project", so shipping is fine. Worth knowing that a `.pck` served from GitHub Pages is trivially extractable, which is closer to the redistribution line than a native binary — not a violation, but a fact to be aware of on a publicly-deployed page under your own name.
**Maintenance risk (Tier 3/4):** the auto-rigger has been intermittently broken since a June 2025 backend auth failure; Adobe stopped active development years ago (no new animations, no new rig types). Treat Mixamo as a frozen archive you should mirror locally, not a live service.

**F15 — Dismemberment in Godot 4: scale the bone pose to near-zero. Tier 3 (two independent working implementations) + Tier 1 (API).**
The technique both reference implementations use:
- `Aegistus/Joes-Jungle` (a Godot 4 zombie shooter with a real dismemberment system):
  `general_skeleton.set_bone_pose_scale(bone.get_bone_id(), Vector3.ONE * .0001)`, tracked in `already_dismembered_parts`, re-applied on death after `physical_bones_start_simulation()`, with `remove_all_child_bones(bone)`. Hit state: `@export var dismember_chance = .3`, gated by `zombie.allow_dismember`, followed by a stagger animation seeked partway in (`animation_player.seek(.3)`).
  https://github.com/Aegistus/Joes-Jungle/blob/main/scripts/zombie.gd · `scripts/zombie%20states/hit_state.gd` · `scripts/zombie%20states/dead_state.gd`
- `Alenvei/Dismemberment_Tutorial_Godot4.2` (a purpose-built minimal tutorial project):
  hides the bone, then `dis_limb.set_as_top_level(true)` and `dis_limb.global_transform = bone_pos` to spawn a free-standing severed limb at the bone's global transform, then instantiates a blood particle scene at `bone_pos.origin` and sets `emitting = true`.
  https://github.com/Alenvei/Dismemberment_Tutorial_Godot4.2
- Larger reference: `Vaximous/DeltaBullet` — per-bone `ragdollBone.gd` with `bloodSpurt` particles, `headDismember` weapon flag, `getBoneChildren()` walking `skeleton3d.get_bone_children()`. https://github.com/Vaximous/DeltaBullet

**F16 — ⚠️ The tutorial's API is deprecated in 4.7, and the naive fix has a trap. Tier 1.**
`Alenvei`'s 4.2 tutorial uses `set_bone_global_pose_override(...)`. In current stable (4.7) `get_bone_global_pose_override` / `set_bone_global_pose_override` / `clear_bones_global_pose_override` are **deprecated** — "may be changed or removed in future versions". `Skeleton3D.physical_bones_start_simulation(bones: Array[StringName] = [])` is likewise deprecated on `Skeleton3D` (it lives on `PhysicalBoneSimulator3D` now).
https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html
**The trap:** the current replacement, `set_bone_pose_scale()`, writes the *local* pose — which the `AnimationMixer` overwrites every frame if the playing clip has a scale track for that bone. The correct 4.3+ structure is to implement dismemberment as a **`SkeletonModifier3D`**, because "Since `AnimationMixer` is applied before the `Skeleton3D` update process, `SkeletonModifier3D` is guaranteed to run after `AnimationMixer`", and modifiers execute in child-list order with each receiving the previous step's output. That is precisely why `global_pose_override` was deprecated: "the processing order between `Skeleton3D` and `AnimationMixer` is changed depending on the `SceneTree` structure."
https://godotengine.org/article/design-of-the-skeleton-modifier-3d/ (Tier 1, official blog, 4.3)
*The alternative — one `MeshInstance3D` per limb, `.visible = false` on severance — is dumber, immune to this ordering problem, and adds draw calls. On a WebGL2 target where draw calls are the scarce resource, the bone-scale approach is still preferable, but it must be a modifier.*

**F17 — Ragdolls: `PhysicalBoneSimulator3D`, and partial simulation is supported. Tier 1 + 3.**
Official demo: `godotengine/godot-demo-projects` → `3d/ragdoll_physics/characters/mannequiny_ragdoll.gd`:
```gdscript
$root/root_001/Skeleton3D/PhysicalBoneSimulator3D.physical_bones_start_simulation()
# then iterate get_children() to apply an initial velocity to every bone
```
https://github.com/godotengine/godot-demo-projects/tree/master/3d/ragdoll_physics (Tier 1)
Blend-into-ragdoll-on-death, the pattern every repo uses: stop/deactivate the `AnimationTree`/`AnimationPlayer`, `physical_bones_start_simulation()`, then `apply_central_impulse(dir * force)` on the hips/torso bone — e.g. `sjgillGit/GWJ82` `$Armature/Skeleton3D/PhysicalBoneSimulator3D/Torso.apply_central_impulse(impulse)`; `3deric/Godot_Skate`; `cgsdev0/neon-drift`; `Lakamfo/Zombies-Must-Die`. Note the recurring `await get_tree().physics_frame` before starting simulation (`SimusDev`, `blugart-dev/kickback`) — a real gotcha.
**Partial ragdoll is first-class:** `physical_bones_start_simulation(bones)` takes an optional `Array[StringName]`, so you can simulate only an arm chain and leave the rest animated. `blugart-dev/kickback` does exactly this: `_simulator.physical_bones_start_simulation(chain)`.

**F18 — Physics-driven hit reactions exist as a Godot 4.7 addon, but the budget is the problem. Tier 3.**
`blugart-dev/kickback` — MIT, "Physics-based reactive characters for Godot 4.6+ (Euphoria-like hit reactions)". README says **Godot 4.7+** (repo topic metadata says 4.6+ — discrepancy, verify). Architecture: "16 RigidBody3D physics skeleton tracks animation via velocity-based springs. Hits reduce spring strength so physics temporarily wins", with a stagger state where the "character visibly wobbles but stays on feet". Ships a 20-character stress-test scene and a "budget system"; **no published performance numbers**.
https://github.com/blugart-dev/kickback
**Arithmetic against your target:** 16 `RigidBody3D` × 24 concurrent zombies = **384 rigid bodies plus their joints**, stepped by single-threaded Godot Physics 3D inside single-threaded WASM, on top of the existing 24 `intersect_ray` LOS calls per physics tick the gap analysis already flagged. This is very unlikely to hold 60 fps. If Branch B ever happens, the honest configuration is **animated death clips as the default, with a pool of 2–3 ragdolls reserved for the most recent corpses** — not per-zombie ragdoll.

---

### Both branches

**F19 — Hit flinch.** 2D: tween `AnimatedSprite3D.modulate` to white for ~60 ms plus a small positional punch along the shot vector; optionally a 2-frame flinch strip. 3D: either a one-shot upper-body clip layered over locomotion via `AnimationNodeBlendTree` + `AnimationNodeAdd2`, or the partial-ragdoll chain of F17/F18. The 2D version is minutes of work and, per the gap analysis's own verification pass, "what breaks the read today is *facing plus feedback*, not the absence of bones". Tier 1 (Godot animation blending docs) / Tier 3 (Joes-Jungle's `hit_state.gd` stagger-with-`seek()` pattern).

**F20 — Blood spray on impact.** `CPUParticles3D` is the safe default here — it dodges F5's `VIEW_DEPTH` WebGL stall *and* F1's first-emission compile, and a dozen 8-particle bursts is nothing for a CPU already doing flow-field steering. If you use `GPUParticles3D`, set `draw_order` to `INDEX` or `LIFETIME`, and emit one invisible burst during the loading screen per F1.

**F21 — Persistent blood decals.** No `Decal` node (F2). Two viable routes:
1. **Official**: `Sprite3D` laid flat on the floor, `shaded = false` or lightly shaded, `alpha_cut`, a small Y offset to beat z-fighting, oriented by the raycast normal. Cap with a ring buffer (e.g. 64 splats, oldest recycled).
2. **Volume**: `antzGames/Godot-Compatibility-Decal-Node` — `DecalCompatibility` (single) and `DecalInstanceCompatibility`, which allows "thousands of decals to be drawn with one draw call"; tested Godot 4.4.1–4.6.2 across all three renderers; supports flipbook animation and uneven surfaces; **limitations: unshaded, opaque-only, no normal/roughness/metallic; licence not stated in the README — check before use.**
https://github.com/antzGames/Godot-Compatibility-Decal-Node · https://www.youtube.com/watch?v=8XnH3mT1C-c (Tier 3)

**F22 — Glowing eyes.** Cheapest correct answer for this project: a child `Sprite3D` (or the existing sprite duplicated) with `shaded = false` — unshaded renders at full texture brightness regardless of scene lighting, which is exactly the "dark corner, two eyes" read. The gap analysis already established the eye pixels exist in frame 0 at (20,14)/(26,14) as the brightest pair in the sprite and are dark only because `zombie.gd:87` sets `shaded = true`. **Adding actual bloom is optional and now known to be available** (F3) — enable `Environment.glow` with a high `glow_hdr_threshold` so only the eye pixels bloom, and watch for the sky-lighting bug (#106702). For additive blending specifically, `SpriteBase3D` does not expose a blend mode; use a small `MeshInstance3D` `QuadMesh` with a `StandardMaterial3D` set to unshaded + `BLEND_MODE_ADD` + `BILLBOARD_ENABLED`. Tier 1 (`SpriteBase3D.shaded`, `BaseMaterial3D`) + Tier 1 (your own asset inspection).

**F23 — Spawn-from-window climb.** 2D: a 3–4 frame vault strip, or — cheaper and used by the whole genre — no animation at all, just a `Tween` on the sprite's Y and Z through the window plane plus a plank-break SFX. The gap analysis notes the ancestor `kriegsnacht.html` already has barricade teardown logic to port. 3D: a Mixamo "Jumping Over Obstacle"/"Climbing" clip, root-motion-free, driven by a tween on the parent body. **No open-source Godot reference found for the vault-through-barricade specifically** — see Coverage gaps.

**F24 — "How do I know something is behind me".** Enemy-facing artwork does not address this; the enemy behind you is not on screen. The genuine channels, in order of value per hour:
1. **Positional audio** — `AudioStreamPlayer3D` idle groans, distance-culled, voice-capped. Already scoped as VS-1/VS-2 in the gap analysis and explicitly called "the single biggest change in the list".
2. **Directional damage indicator** — a `Control` arc drawn toward the attacker on hit.
3. 8-direction sprites, which help you read *aggro* on enemies you can already see (is that one coming for me or for the window?), which is a different and lesser problem.
Tier 1 (Godot `AudioStreamPlayer3D`) / Tier 3 (genre convention).

---

## Recommendations for this project

**R1 — Formally close T0.8 as: stay on billboards. Do not revisit.**
The gap analysis's provisional recommendation was correct, and the research strengthens it beyond the reasons it gave. The decisive new argument is not aesthetic and not effort — it is **F1**: on web + Compatibility there is *no* shader precompilation and *no* thread to compile on, so a 3D zombie's material variety converts directly into mid-round frame hitches that you cannot engineer away. Add F2 (no decals), F6 (skinned-mesh bugs on the exact renderer you must ship), F18's arithmetic (384 rigid bodies), and F14's frozen-asset-source risk. Billboards are not the compromise here; they are the platform-correct choice.

**R2 — Sequence the work so the cheap wins land first. Concrete order:**

| # | Item | Effort | Why first |
|---|---|---|---|
| 1 | Hit flash + positional punch on `modulate` (F19) | XS | The verification pass says feedback, not bones, is what breaks the read |
| 2 | Unshaded eye overlay, `shaded = false` (F22) | XS | Zero new art; the pixels already exist |
| 3 | Walker→crawler conversion (F12) | S | ~20 lines, zero new art, buys the single most CoD-Zombies beat available |
| 4 | `CPUParticles3D` blood burst + ring-buffered `Sprite3D` floor splats (F20, F21) | S | Both dodge the two web landmines |
| 5 | 5-column + `flip_h` directional atlas, generator-side (F7, F8, F10) | M | The real Branch-A investment; **write the generator, not the art** |
| 6 | Limbless sprite variants as a generator flag (F11) | M | Only worth it once #5's generator refactor exists |

**R3 — Build the directional sprites as five draw routines in the generator, not as art.**
`sprite_lib.gd` documents that the PNGs come from replaying canvas drawing code. Extend that generator with a `view` parameter (front / front-3⁄4 / side / back-3⁄4 / back), emit a 720×320 sheet per palette, and let `flip_h` cover the other three directions. Extend `SpriteLib.SPEC` with a `dirs: 5` field and make `_add_strip` compute `Rect2(frame * w, dir_row * h, w, h)`. This keeps the entire pipeline procedural, which is both the project's stated constraint and its actual advantage.

**R4 — If you later want richer motion, use the pre-render escape hatch, not runtime 3D.**
Rig a free/CC0 humanoid with Mixamo (F13/F14), batch-render 8 directions × N frames through `chronicleroflegends/DirectionalSpriteBatchRender` (built for ZDoom billboard conventions) or `GraesonB/Blender-Isometric-Renderer` (4/8/16 directions), then quantise to the existing three palettes at 48×64 and stamp the same 1 px dark rim `outlineSprite()` already applies. You get Mixamo's walk/run/sprint/attack/crawl/death library **and** the pixel-art identity **and** zero runtime skinning, zero new materials, zero ragdoll physics. This is the correct answer to "a realistic 3D zombie would clash with the world it stands in": pass the 3D through the existing art filter and it stops being a 3D zombie.
https://github.com/chronicleroflegends/DirectionalSpriteBatchRender · https://github.com/GraesonB/Blender-Isometric-Renderer · https://github.com/chrishayesmu/Blender-Spritesheet-Renderer · https://github.com/theloneplant/blender-spritesheets

**R5 — Do not buy 8-direction art hoping it fixes situational awareness.** Spend that budget on VS-1/VS-2 positional audio first (F24). Directional sprites are worth doing for *aggro legibility*, which is real but secondary; sell them to yourself on that basis, not on threat awareness.

**R6 — Two settings changes to make before anything else, both now confirmed safe on Compatibility:** enable MSAA 3D (F4 — validates T0.7), and add a hidden warm-up frame during load that instantiates every particle system, decal material and sprite material once inside the frustum (F1's verbatim official mitigation). The second one is the only defence you have against first-sight hitches on this platform.

**R7 — If Branch B is ever revisited, these are the non-negotiables** (recorded so a future you does not relearn them): dismemberment must be a `SkeletonModifier3D`, not `set_bone_pose_scale` called from `_process`, or the `AnimationMixer` will stomp it (F16); `global_pose_override` is deprecated, do not copy the 4.2 tutorial verbatim (F16); ragdoll must be a pool of 2–3, driven by `PhysicalBoneSimulator3D.physical_bones_start_simulation()` after `await get_tree().physics_frame`, with animated death clips as the default (F17/F18); and the whole thing must be perf-gated on a measured web build, not on desktop editor frame rates.

---

## Coverage gaps

1. **No open-source Godot implementation of the legs-shot→crawler transition was found**, in either 2D or 3D. `Aegistus/Joes-Jungle` has dismemberment and a state machine but its `hit_state.gd` transitions only to `follow_state` or `dead_state` — no crawler state. The structure in F12 is my design against your existing `SpriteLib`, not a retrieved reference implementation.
2. **No open-source Godot 2D/billboard dismemberment implementation was found.** F11 is genre convention (DOOM/Blood/Duke 3D gib frames) plus reasoning from your codebase, not a repo I can point at. Retrieval was Class-C "don't bother" after two negative searches — sprite-based gore is old enough that its implementations predate GitHub.
3. **No measured numbers for skinned-mesh throughput on WebGL2/Compatibility.** I found correctness bugs (F6) but no benchmark of N skinned humanoids in a Godot web build. This is inherently a measure-not-research question (see below).
4. **`blugart-dev/kickback` publishes no performance figures**, and its Godot version is stated inconsistently (README 4.7+, repo topics 4.6+). The 384-rigid-body arithmetic in F18 is mine and is an estimate, not a measurement.
5. **Godot 4.7-specific release notes were not read.** All renderer-capability claims come from `docs.godotengine.org/en/stable`, which the `Skeleton3D` page confirms is currently 4.7 — but I did not read a 4.7 changelog, so a 4.7-only Compatibility improvement (e.g. decals landing) could exist and be missed. Verify F2 against 4.7 release notes before committing to the Sprite3D decal route.
6. **`23Bluemaster23/GodotSprite3DPlus` does not state a Godot version**; the shader source was not read. Do not adopt without opening the addon.
7. **`antzGames/Godot-Compatibility-Decal-Node` states no licence in its README.** Must be resolved before use in a publicly deployed project under your own name.
8. **No open-source reference for the vault-through-barricade / climb-through-window animation** was located in either representation (F23).
9. **Mixamo's current operational state is Tier 3/4 only** (a vendor-neutral blog and a Grokipedia entry). Adobe has published no statement I could retrieve about the auto-rigger outage. If Mixamo matters to a decision, mirror the clips you need locally now rather than trusting availability.

---

## What must be measured rather than researched

### M-1 — Does the current billboard build have headroom at all? (Prerequisite for every other number here.)
This is gap-analysis **T0.7** and nothing below is meaningful without it.
1. Export a **web** build (`gl_compatibility`, the real target) and serve it locally: `python -m http.server` from the export directory.
2. Open in the target browser. In the JS console, confirm `SharedArrayBuffer === undefined` (proves you are measuring the single-threaded path).
3. Use the existing `scripts/perf_probe.gd`; if it does not already, log `Engine.get_frames_per_second()`, `Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)`, `RENDER_TOTAL_OBJECTS_IN_FRAME`, `Performance.get_monitor(Performance.TIME_PROCESS)` and `TIME_PHYSICS_PROCESS`, sampled every 0.5 s to a `PackedFloat32Array`, dumped on round end.
4. Force `MAX_ALIVE` to 24 and run round 20 in the largest opened area. Record the **1 % low** frame time, not the mean — hitches are the failure mode, means hide them.
5. Repeat on the weakest device you care about. Browser + integrated GPU, not the dev machine.

### M-2 — Cost of the 5-column directional atlas.
Measure the delta, not the absolute. Before/after M-1's harness with the directional atlas in place. Expected delta ≈ 0 (same draw calls, one larger texture, `flip_h` is free) — **if it is not ≈ 0, you have an atlas-thrash or texture-format problem, not a sprite problem.** Confirm `VIDEO_MEM_TEXTURE_MEM_USED` moves by roughly the 2.8 MB predicted in F10; a much larger jump means Godot padded or converted the format.

### M-3 — First-sight shader hitch (the F1 risk), per new material.
1. Instrument: log `Time.get_ticks_usec()` deltas per frame, flag any frame > 33 ms.
2. Cold-load the web build (hard refresh, disable cache), enter a round, and trigger each effect for the first time in isolation: first blood particle, first floor splat, first eye overlay, first crawler swap.
3. Record the spike per effect.
4. Then add the warm-up frame from R6 and re-run cold. **The measurement is the difference.** If warm-up removes the spikes, the mitigation works; if it does not, the compile is happening on a code path the warm-up misses.

### M-4 — `CPUParticles3D` vs `GPUParticles3D` for blood, on web specifically.
Because F5 documents a real web-only stall, do not choose on theory. Build both, 12 concurrent bursts of 16 particles, measure `TIME_PROCESS` (CPU path) and 1 % low frame time (GPU path) in the browser. Test `GPUParticles3D` with `draw_order` at `INDEX` **and** at `VIEW_DEPTH` — reproducing (or failing to reproduce) issue #107633 on 4.7 is itself a useful result and worth reporting upstream.

### M-5 — Only if Branch B is ever seriously reconsidered: skinned-humanoid ceiling.
Minimal probe, one afternoon: a scene with N instances of one Mixamo-retargeted GLB playing one clip, no AI, no gameplay, `gl_compatibility`, **web export**. Sweep N = 4, 8, 16, 24, 32. Record 1 % low frame time and draw calls. Then repeat with a 15-bone `PhysicalBoneSimulator3D` active on 3 of them. Two numbers decide it: the N at which you drop below 60 fps, and whether that N is comfortably above 24. Do this **before** any modelling work, not after.
