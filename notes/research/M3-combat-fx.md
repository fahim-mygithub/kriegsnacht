# M3 — Combat FX, particles, decals and lighting mood on WebGL2 (Godot 4)

Research date: 2026-07-27 · Target: Godot 4.7, `gl_compatibility` / WebGL2, single-threaded web export, solo dev, procedural art only.

Evidence tiers: **1** official docs / engine source · **2** maintainer statement or engine issue/PR · **3** reputable secondary or a maintained reference implementation · **4** community anecdote.

---

## Bottom line

1. **You have exactly one shadow-casting light budget, and it should be the flashlight.** In the Compatibility renderer, all shadowless lights plus *one* shadowed light are done in the base pass; **every additional shadowed light re-draws every affected object with additive blending** ([clayjohn, PR #77496](https://github.com/godotengine/godot/pull/77496), Tier 2). Turn on `shadow_enabled` for the player's `SpotLight3D` torch only; leave the ten room omni-lamps shadowless forever. A spot light needs one shadow map render; an omni needs a cube (6) or dual-paraboloid (2).

2. **Your merged level geometry is silently capping you at 8 lights for the entire map.** `world_builder._commit()` commits one `MeshInstance3D` per texture spanning the whole level, so every one of those meshes has a map-sized AABB. Compatibility allows **8 omni + 8 spot per *mesh resource*** ([OmniLight3D docs](https://github.com/godotengine/godot/blob/master/doc/classes/OmniLight3D.xml), Tier 1) — with 10 room lamps + the torch you are already over, and which 8 win is view-dependent (the documented symptom is "lights flickering in and out as the camera moves"). **Chunk the level mesh per room** before you touch anything else in this document. This is a correctness bug, not an optimisation.

3. **`Decal` does not exist on gl_compatibility. Use pooled unshaded `QuadMesh` "stickers".** Confirmed unsupported in the renderer feature table (Tier 1) and tracked as an unimplemented feature ([#98259](https://github.com/godotengine/godot/issues/98259), Tier 2). The working, current-Godot-4 pattern is a quad offset `0.005–0.01 m` along the hit normal, `SHADING_MODE_UNSHADED`, `render_priority = 1`, `cast_shadow = OFF`, random roll for variety, FIFO-capped pool, tween the alpha out. Two independent open-source implementations do exactly this (see Findings F6).

4. **GPU particles *do* work on WebGL2 — the "Compatibility falls back to CPU particles" claim you will find on blogs is false.** The GLES3 backend simulates particles with **OpenGL transform feedback**; only the depth *sort* falls back to CPU ([`drivers/gles3/storage/particles_storage.cpp`](https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/storage/particles_storage.cpp), Tier 1). Use `GPUParticles3D`, but **never set `draw_order = VIEW_DEPTH` on web** — it triggers a documented pipeline stall ([#107633](https://github.com/godotengine/godot/issues/107633), Tier 2).

5. **There is no shader precompilation on web, at all, ever.** Ubershaders and pipeline precompilation "rely on functionality only available in modern low-level graphics APIs" and the 4.5 shader baker "has no effect on web platforms" (Tier 1). The *only* mitigation is the legacy one the docs name explicitly: display every material, shader and particle system for at least one frame during load. Build a `PreloadManager` that renders every FX scene in a 16×16 `SubViewport` for 4 frames at boot (working reference in F10).

6. **Screen effects should mostly not be shaders.** `Environment` adjustments (`adjustment_saturation`, `adjustment_contrast`, `adjustment_color_correction`) are **supported on Compatibility** (Tier 1) and you already drive them in `main.gd`. Downed-grayscale = tween `adjustment_saturation → 0`. Blood vignette, damage direction, nuke whiteout = plain alpha-blended `TextureRect`/`ColorRect` on a `CanvasLayer` with **no screen texture read**. Reserve `hint_screen_texture` (which forces a full-screen back-buffer copy) for nothing at all if you can help it.

---

## Findings

### F1 — Renderer feature matrix for gl_compatibility (the hard constraints)

**Tier 1** · [`godot-docs/tutorials/rendering/renderers.rst`](https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/rendering/renderers.rst) · corroborated by [rendered docs page](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html) (same source, so **1 independent source**; cross-checked against engine source for the light limits, below).

Verbatim rows relevant to this brief:

| Feature | Compatibility |
|---|---|
| Decals | ❌ Not supported |
| LightmapGI | ⚠️ "Rendering of baked lightmaps is supported. Baking requires hardware with RenderingDevice support" |
| VoxelGI / SDFGI | ❌ Not supported |
| Volumetric fog | ❌ Not supported |
| SSAO | ✔️ Supported |
| SSR / SSIL | ❌ Not supported |
| Glow | ✔️ Supported |
| **Adjustments (color correction)** | **✔️ Supported** |
| Depth of field blur | ❌ Not supported |
| Particle trails | ❌ Not supported |
| Particle SDF collision | ❌ Not supported |
| PCSS (omni/spot and directional) | ❌ Not supported |
| MSAA 3D | ✔️ Supported |
| MSAA 2D / TAA / FXAA | ❌ Not supported |
| OmniLights / SpotLights | **8 per mesh** |
| DirectionalLights | 8 max |

And: *"Compatibility is the only choice"* for web.

**What this changes for you:** no FXAA means your nearest-filtered procedural textures will alias badly at distance — MSAA 3D is your only AA. No volumetric fog means the CoD-Zombies "god rays through a window" look is off the table; you already use `Environment` exponential fog, which is the correct substitute. Glow being supported is the single most valuable entry in this table: it is what makes a muzzle flash and an emissive rim read as *bright* rather than just *pale*.

### F2 — Light limits are engine-source-verifiable, and one of them will bite you

**Tier 1** · [`servers/rendering/rendering_server.cpp`](https://github.com/godotengine/godot/blob/master/servers/rendering/rendering_server.cpp) and [`drivers/gles3/storage/config.cpp`](https://github.com/godotengine/godot/blob/master/drivers/gles3/storage/config.cpp) · **2 independent corroborations** (engine source + `OmniLight3D.xml` / `SpotLight3D.xml` class docs).

```cpp
// OpenGL limits
GLOBAL_DEF_RST(PropertyInfo(Variant::INT, "rendering/limits/opengl/max_renderable_elements", PROPERTY_HINT_RANGE, "1024,65536,1"), 65536);
GLOBAL_DEF_RST(PropertyInfo(Variant::INT, "rendering/limits/opengl/max_renderable_lights",  PROPERTY_HINT_RANGE, "2,256,1"),      32);
GLOBAL_DEF_RST(PropertyInfo(Variant::INT, "rendering/limits/opengl/max_lights_per_object",  PROPERTY_HINT_RANGE, "2,1024,1"),      8);
```

- `max_renderable_lights` default **32** — total positional lights the renderer will consider in a frame. Your 10 room lamps + 1 torch + N muzzle flashes is comfortably inside this. Fine.
- `max_lights_per_object` default **8** — per *mesh resource*. This is the one that bites (see Bottom Line #2). It is raisable, but the class docs warn raising it costs "performance and longer shader compilation times" — and on web you cannot precompile, so raising it is actively harmful. **Chunk the geometry instead.**
- All three are `GLOBAL_DEF_RST` → **restart required**, so they cannot be tuned at runtime from a settings menu.

Also from `OmniLight3D.xml` (Tier 1): *"When using the Mobile or Compatibility rendering methods, omni lights will only correctly affect meshes whose visibility AABB intersects with the light's AABB."* — this is what makes per-room chunking work: a chunked wall mesh intersects 1–3 lamp AABBs, not 11.

### F3 — How Compatibility shadows actually cost

**Tier 2** · [clayjohn, "Implement 3D shadows in the GL Compatibility renderer", PR #77496](https://github.com/godotengine/godot/pull/77496) · **1 primary source** (the implementing maintainer), corroborated in direction by [proposal #8050](https://github.com/godotengine/godot-proposals/issues/8050) on single-pass lighting.

Direct quote from the PR:

> "All lights without shadows are rendered during base pass as well as one light with shadows. Each additional light with a shadow requires drawing the object again with additive blending."

> "Lights with shadows are blended in sRGB space instead of linear, so the colors blow out very quickly (i.e. lights with shadows look like they do in the Godot 3.x GLES2 renderer)."

> "There is still one outstanding bug where shadow atlas textures are getting out of date with multiple shadowed lights in the scene."

Consequences, in order of importance to you:

- **One shadowed light is nearly free. Two is a full extra geometry pass.** This is a hard architectural fact, not a tuning knob.
- **A shadowed light looks brighter than an unshadowed one of the same energy** (sRGB blending). You will need to re-tune `light_energy` after enabling shadows, not just flip the flag. There is a corresponding open issue: [#90259 "Compatibility renderer: lights seem brighter when their shadows are enabled"](https://github.com/godotengine/godot/issues/90259) (Tier 2).
- Godot 4.3 also had a general omni-shadow perf regression vs 4.2 ([#97472](https://github.com/godotengine/godot/issues/97472), Tier 2) — another reason to prefer spot over omni for the one shadowed light.
- PCSS is unsupported on Compatibility, so shadows will be hard-edged PCF. **For CoD Zombies this is a feature, not a limitation** — hard shadows are the aesthetic.

### F4 — LightmapGI is usable on web, but not for *this* level

**Tier 1** · [`using_lightmap_gi.rst`](https://docs.godotengine.org/en/latest/tutorials/3d/global_illumination/using_lightmap_gi.html) + renderers.rst · **2 independent corroborations**.

> "Baking lightmaps in the web editors is not supported due to graphics API limitations." — but rendering pre-baked lightmaps on web **is** supported if baked on another platform.

> Compatibility: "Rendering of baked lightmaps is supported. Baking requires hardware with RenderingDevice support."

So the pipeline *would* be: bake on your desktop in Forward+ → export → the Compatibility web build renders the lightmaps at essentially zero runtime cost. That is genuinely the cheapest possible "pooled darkness".

**But it does not apply to Kriegsnacht as written.** `world_builder.gd` builds the level with `SurfaceTool` at runtime and sets `mi.gi_mode = GI_MODE_DISABLED`. LightmapGI needs static `MeshInstance3D`s present in the editor with a UV2 unwrap. You would have to convert the generation into a `@tool` script, run it once, save the result as a `.tscn`, unwrap UV2, and bake — abandoning runtime generation. Given "roguelike" is in the project name and the map may become procedural, that trade is probably wrong.

**The cheaper equivalent you already half-built:** `world_builder._quad()` writes a per-face `shade` into vertex colours and the material sets `vertex_color_use_as_albedo = true`. That *is* a baked lighting channel. Upgrade it from per-face constant to **per-vertex**: at generation time, for each vertex, compute (a) a cheap ambient-occlusion term from neighbouring solid tiles in the grid, and (b) sum of `1/d²` falloff from each room lamp position. Write the result to the vertex colour. Cost at runtime: **zero** — it is already in the vertex stream. Cost at load: a few thousand GDScript iterations, single-digit milliseconds. This gives you the pooled-darkness gradient without a single extra light, and it composes with the one real shadowed flashlight on top.

### F5 — Muzzle flash

**Composition (Tier 4 consensus, converged across ~6 independent open-source repos found via GitHub code search):** a pre-existing `OmniLight3D` at the muzzle toggled on for a fixed short duration, plus a camera-facing quad or `GPUParticles3D` one-shot with a random flipbook frame, plus a random roll/scale per shot.

Representative real code:

- [`asmarton/Arachnomisia` `scripts/gun.gd`](https://github.com/asmarton/Arachnomisia/blob/master/scripts/gun.gd) — a pre-made `Timer` whose `timeout` hides the flash: `light_timer.timeout.connect(func (): muzzle_flash.visible = false)`. This is the right shape: **one persistent Timer, not `await create_timer()` per shot**, which allocates a `SceneTreeTimer` and a coroutine on every trigger pull.
- [`henliz/equinox` `muzzle_flash_1.gd`](https://github.com/henliz/equinox/blob/main/resource/Puzzles/VFX/EffectBlocks/source_files/scripts/muzzle_flash_1.gd) — `var random_frame = randi() % NUM_FRAMES`, flipbook frame randomisation.
- [`ZeromaXHe/MyGitRepository` `muzzle_flash.gd`](https://github.com/ZeromaXHe/MyGitRepository/blob/master/GodotDemo/FpsDemo/scripts/muzzle_flash.gd) — `light.visible = true; emitter.emitting = true; await …(flash_time).timeout`.

**Duration.** Observed values in the wild: `0.1 s` (Arachnomisia-style, `project-hillbilly/Weapon.gd`), `0.08 s` (`Gruntz.gg/_player.gd`), and one repo tying it to `fire_rate`. All Tier 4. **Recommendation: 0.05 s (3 frames @ 60 Hz) for the light, 0.06–0.08 s for the quad.** Longer than ~0.1 s reads as a flare, not a flash; shorter than ~2 frames risks being skipped entirely on a dropped frame in a web build. Per-weapon variation is the cheapest "feel" win available: pistol 0.04 s / small quad, shotgun 0.08 s / wide quad + higher light energy, SMG 0.035 s / offset toward the barrel.

**Is the light flash a per-shot spike?** **No — and this is the correction that matters.** From [`drivers/gles3/shaders/scene.glsl`](https://github.com/godotengine/godot/blob/master/drivers/gles3/shaders/scene.glsl) and [`rasterizer_scene_gles3.cpp`](https://github.com/godotengine/godot/blob/master/drivers/gles3/rasterizer_scene_gles3.cpp) (**Tier 1**):

```glsl
uniform uint omni_light_indices[MAX_FORWARD_LIGHTS];
uniform uint omni_light_count;
```
```cpp
global_defines += "\n#define MAX_FORWARD_LIGHTS " + itos(config->max_lights_per_object) + "u\n";
```

`MAX_FORWARD_LIGHTS` is a **global** compile-time define derived from the project setting; the *actual* light count is a **uniform**. So varying how many unshadowed lights touch a mesh changes a uniform, **not a shader variant** — toggling a muzzle-flash omni on and off cannot trigger a shader recompile. What *would* cause a variant switch is the additive path (`SceneShaderGLES3::ADDITIVE_OMNI` is a spec constant, set only for extra *shadowed* lights) — so keep `shadow_enabled = false` on the muzzle light and you are safe.

**Rules to follow anyway:** create the muzzle `OmniLight3D` once in `_ready()`, parent it to the muzzle, and toggle `visible`. Give it a small `omni_range` (1.5–3 m) so its AABB intersects as few meshes as possible — remember every mesh it touches spends one of that mesh's 8 slots. Never `add_child` a new light per shot.

### F6 — Bullet holes and blood splats: pooled quad stickers

`Decal` is unavailable (F1). Two options exist; the first is the one to use.

**Option A — quad stickers (recommended). Tier 3, 2 independent reference implementations:**

1. [`aaabattery650/not-or-ready` — `scripts/vfx/impact_effect.gd`](https://github.com/aaabattery650/not-or-ready/blob/main/scripts/vfx/impact_effect.gd) — the better of the two. Notable, directly reusable details:
   - Static FIFO pool: `static var _decals: Array[MeshInstance3D]`, `const MAX_DECALS := 30`; on overflow it pops index 0 and frees it.
   - `QuadMesh`, `TRANSPARENCY_ALPHA`, `SHADING_MODE_UNSHADED`, `render_priority = 1`, `cast_shadow = SHADOW_CASTING_SETTING_OFF`.
   - Z-fighting fix: `decal.global_position = pos + normal * 0.005  # tiny offset to avoid z-fighting`.
   - Random roll: `decal.rotate_object_local(Vector3.FORWARD, randf() * TAU)`.
   - Fade-out: a `Tween` with `tween_interval(fade_time - 1.0)` then `tween_method` driving `dmat.albedo_color.a` to 0 over 1 s, then `queue_free`.
   - **It already ships a web budget:** `fx.amount = 8 if is_web else (24 if is_blood else 16)`, and it skips decals entirely on web (`if not is_web:`). You should *not* skip them — you should pool them — but the precedent that web needs a separate budget is worth noting.
   - **The `look_at` up-vector guard, which you must copy:**
     ```gdscript
     var up := Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > 0.99 else Vector3.UP
     decal.look_at(pos + normal, up)
     ```

2. [`ssube/zombie-game` — `scripts/singletons/DecalManager.gd`](https://github.com/ssube/zombie-game/blob/main/scripts/singletons/DecalManager.gd) — a surface-type→`PackedScene` dictionary, `decal_lifetime = 30.0`, `decal_fade = 5.0`, parents the decal **to the collider** so it moves with a moving object, offsets by `normal * 0.01`. **Contains a bug you must not copy:** `decal.look_at(hit_pos + normal, Vector3.UP)` with no guard — this throws/degenerates when you shoot a floor or ceiling (normal parallel to UP). Reference #1 has the fix.

**Godot 4 has no polygon-offset / depth-bias property on `BaseMaterial3D`** (verified against [`class_basematerial3d.rst`](https://raw.githubusercontent.com/godotengine/godot-docs/master/classes/class_basematerial3d.rst), Tier 1 — no such property exists). The positional offset along the normal is genuinely the standard fallback, corroborated by both implementations above at 0.005 and 0.01 m. **Use 0.008 m**; your walls are axis-aligned so you will not fight curved-surface clipping.

**Pool budget.** Both references cap at 30. For a web build with 24 zombies alive and an SMG, 30 is too few to feel persistent and too many to be free if each is a separate `MeshInstance3D` + `StandardMaterial3D`. **Recommendation: two `MultiMeshInstance3D` ring buffers — one for bullet holes (48 slots), one for blood splats (32) —** and move the write cursor rather than allocating. One draw call each instead of 80. Fade via `set_instance_color` alpha (see Coverage gaps — instance colours on Compatibility need measuring) or, failing that, via scaling the instance transform to zero.

**Option B — projected box decals via a depth-reconstruction shader.** [CarpenterBlue, "Decal Shader for 4.3 compatibility renderer", godotshaders.com, MIT](https://godotshaders.com/shader/decal-shader-for-4-3-compatibility-renderer-transparency-support-no-repeat/) (Tier 3). Reconstructs world position from `hint_depth_texture`, transforms into the decal box's local space, `discard`s outside the box, samples the albedo from the projected XZ. Correct for uneven geometry, but: one full depth-texture sample per decal fragment, a `discard` (which defeats early-Z), needs `inverse(MODEL_MATRIX)` in the vertex shader, and does not trivially multimesh. **Not worth it for a grid-aligned level.** Keep it in your back pocket only if you later add non-planar geometry.

### F7 — Surface-type lookup from a raycast

Three patterns exist in real Godot 4 code. Ranked for this project:

1. **Node metadata on the collider** (Tier 3, **2 independent repos**): `g3dfps` (both the [`feivegian`](https://github.com/discover3d/big_repos_072) and [`borfei`](https://github.com/discover3d/big_repos_052) mirrors) does exactly:
   ```gdscript
   var surface = %SurfaceRaycast.get_collider()
   var type = surface.get_meta("surface_type", "tile")
   ```
   Cheap, one dictionary lookup, works with a default. **This is the right one for you** — but note your collision bodies are also built at runtime, so you would `set_meta("surface_type", &"concrete")` in `world_builder` at the same place you pick the texture. You already know the surface type there; it costs nothing to record it.

2. **A dictionary keyed by surface name → effect scene**, as in `ssube/zombie-game`'s `DecalManager.decal_scenes` and `ZS_Projectile.impact_sounds`. Combine with (1).

3. **Groups** (`collider.is_in_group("wood")`) — a linear scan per group, and you cannot carry extra data. Avoid.

**A fourth option specific to you:** `RayCast3D`/`intersect_ray` returns `face_index` and, via `get_collider_shape()`, the shape. Since your level is one merged `ConcavePolygonShape3D` per group with a known face→tile mapping, you can derive the surface type from the *hit position* by quantising to the grid and reading `MapData` — no metadata, no per-node storage, exact. `apply_decal()` already has `ray.get_collision_point()`. This is the cheapest possible lookup and it is available only because your world is a grid. **Recommend this for walls/floor, metadata for doors/windows/props, and a `Zombie` type-check for flesh.**

**What each impact should look like** (Tier 4, genre convention; no authoritative source found):

| Surface | Particles | Decal | Notes |
|---|---|---|---|
| Concrete / stone | 6–8 grey dust puff, `spread ≈ 80°`, low velocity (0.5–1.5 m/s), gravity −1, damped hard | dark chipped hole | dust is the readable part, not the hole |
| Wood | 5–6 tan splinters, higher velocity (2.5–6 m/s), gravity −12, elongated mesh | hole + light halo | |
| Metal | 8–10 **emissive** sparks, `emission_energy_multiplier ≈ 2.5`, short lifetime (0.25 s), gravity −12 | bright scuff | glow is supported on Compatibility — sparks are the one place it pays for itself |
| Flesh / zombie | 10–14 dark-red droplets, `spread ≈ 55°`, gravity −12, damping 2–5 | splat on the wall *behind* (second raycast) | |

`impact_effect.gd` (F6, ref #1) has literal `ParticleProcessMaterial` values for the dust, blood and debris variants — copy them as a starting point and halve `amount` for web.

### F8 — Particles on WebGL2: what is and is not true

**Tier 1** · [`drivers/gles3/storage/particles_storage.cpp`](https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/storage/particles_storage.cpp).

`_particles_process()` uses transform feedback:
```cpp
glBindBufferBase(GL_TRANSFORM_FEEDBACK_BUFFER, 0, p_particles->front_process_buffer);
glBeginTransformFeedback(GL_POINTS);
glDrawArrays(GL_POINTS, 0, p_particles->amount);
glEndTransformFeedback();
```
with an in-source comment in `_particles_update_instance_buffer()`: *"Sort will be done on CPU since we don't have compute shaders."*

**So: simulation is on the GPU; only depth sorting is on the CPU.** The widely repeated claim that "in Compatibility, GPUParticles3D nodes fall back silently to CPU simulation" (found on [slicker.me](https://slicker.me/godot/renderers.html), Tier 3) is **wrong**, and I am flagging it because it is exactly the kind of plausible secondary-source claim that would push you into `CPUParticles3D` for no reason.

Caveats that *are* real:
- `draw_order = VIEW_DEPTH` on web produces WebGL warnings and a pipeline stall: *"READ-usage buffer was read back without waiting on a fence. This caused a graphics pipeline stall."* — [#107633](https://github.com/godotengine/godot/issues/107633), reproduced in 4.3.stable and 4.4.1.stable, still open (Tier 2). **Use `DRAW_ORDER_INDEX` or `DRAW_ORDER_LIFETIME`.**
- Particle **trails** and **SDF collision** are unsupported (F1) — no ribbon tracers via trails.
- Each `GPUParticles3D` node is its own draw call and its own process shader. **Pool a small fixed set of emitters** (say 8 impact emitters, 4 blood emitters, 1 muzzle) and `restart()` them, rather than instancing a node per hit as both reference implementations do.

### F9 — Tracers and shell casings

No authoritative source; this is a judgement call, so here is the reasoning rather than a citation.

**Tracers: yes, but cheap and not every shot.** A hitscan tracer is a single quad or thin box stretched from muzzle to hit point, shown for 1–2 frames, unshaded and emissive. Because it is a one-frame object, it belongs in the same `MultiMeshInstance3D` ring buffer discipline as the decals — 8 slots is plenty. Do **not** use `GPUParticles3D` trails (unsupported, F1) and do not use a moving projectile node for a hitscan weapon. Genre convention is roughly 1-in-3 to 1-in-5 rounds carry a visible tracer; showing all of them looks like a laser. **Cost: one extra draw call, negligible.** High value in a dark level because the tracer briefly lights the path your eye should follow.

**Shell casings: marginal. Do them last, and without physics.** A `RigidBody3D` per casing at SMG fire rates is a real physics cost in a single-threaded web build and buys almost nothing in a first-person game where the casing leaves the frame in 200 ms. If you do them: integrate a simple ballistic arc in GDScript (`v += g*dt; p += v*dt`) into a `MultiMesh` of 16 instances, no collision, despawn at 1.2 s. That is a handful of float ops per frame. Note `influenza-dotcom/3D-RPG` (F10) has a `bullet_casing.tscn` in its preload list — precedent that even projects that do casings treat them as a preload-critical hitch source.

### F10 — Shader warm-up is mandatory, and there is a working reference

**Tier 1 for the constraint** · [`pipeline_compilations.rst`](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html):

> "This page only applies to the Forward+ and Mobile renderers, not Compatibility."
> "Ubershaders and pipeline precompilation rely on functionality only available in modern low-level graphics APIs (Vulkan, Direct3D 12, Metal)."
> Compatibility uses APIs that "lack the functionality to effectively implement ubershaders and pipeline precompilation."
> The recommended fallback: "you need to use the legacy approach of preloading materials, shaders, and particles by displaying them for at least one frame in the view frustum when the level is loading."
> The 4.5 shader baker "has no effect on web platforms, as the web platform only supports the Compatibility renderer."

Corroborated by a community report of exactly this symptom on web ([Godot forum: "Handling particle shader compilation lag in Godot 4 web (compatibility renderer)"](https://forum.godotengine.org/t/handling-particle-shader-compilation-lag-in-godot-4-web-compatibility-renderer/36170), Tier 4).

**Tier 3 reference implementation** · [`influenza-dotcom/3D-RPG` — `managers/PreloadManager.gd`](https://github.com/influenza-dotcom/3D-RPG/blob/main/managers/PreloadManager.gd). It does both halves properly:

1. Holds a reference to every runtime-`load()`ed `PackedScene` in a dictionary owned by an autoload, so Godot's resource cache stays hot for the session.
2. `_prewarm_gpu_particles()` — creates a `SubViewport` of `Vector2i(16, 16)` with `own_world_3d = true` and `render_target_update_mode = UPDATE_ALWAYS`, adds a `Camera3D` at `(0,0,3)`, instantiates each particle effect with `one_shot = false; emitting = true`, `await get_tree().process_frame` **four times**, then `vp.queue_free()`. The comments explain the design: *"isolated world: the warm-up particles never touch gameplay physics/lighting"* and *"keep emitting across the warm-up frames so the pipeline actually draws"*.

This is the pattern to copy verbatim, extended to cover **every** FX material you will ever show: muzzle quad, each impact particle variant, decal material, tracer material, blood material, and — critically — **the shadowed variant of your torch**, since enabling shadows on a light changes the shader path (F3). Warm it during the pre-round intermission you already have (`_intermission` / `FIRST_ROUND_DELAY` in `main.gd`), not on the first trigger pull.

### F11 — Screen effects

**Tier 1 for the mechanism** · [`renderers.rst`](https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/rendering/renderers.rst) confirms `Adjustments` are supported on Compatibility. **Tier 3/4** for the node pattern · [The Shaggy Dev, "The fix for UI and post-processing shaders in Godot 4"](https://shaggydev.com/2025/04/09/godot-ui-postprocessing-shaders/), [ArseniyMirniy/Godot-4-Color-Correction-and-Screen-Effects](https://github.com/ArseniyMirniy/Godot-4-Color-Correction-and-Screen-Effects) (visual-shader based, 4.3/4.4).

The standard pattern is `CanvasLayer → ColorRect` (Full Rect anchors) with a `canvas_item` shader. Two important gotchas from those sources:

- A shader that reads `hint_screen_texture` forces a **full-screen back-buffer copy** the first time it is encountered in the draw order (Tier 1, [screen-reading_shaders.rst](https://github.com/godotengine/godot-docs/blob/master/tutorials/shaders/screen-reading_shaders.rst)). On WebGL2 that is a real bandwidth cost every frame the effect is active.
- Anything deriving from `Window` (popups, `OptionButton` dropdowns) renders on layer 1024 and will *not* be covered by your CanvasLayer unless you set the layer above it.

**Which technique for which effect:**

| Effect | Technique | Screen read? | Cost |
|---|---|---|---|
| Damage-direction indicator | `TextureRect` (an arc/chevron) on a `Control` pivoted at screen centre, `rotation = angle to attacker`, alpha tween | no | ~free |
| Blood vignette | one radial-gradient `TextureRect` (procedural `GradientTexture2D`), modulate alpha ∝ (1 − health) | no | ~free |
| Low-health treatment | same vignette + a slow `alpha` sine pulse driven from `_process`; optionally tween `Environment.adjustment_saturation` to ~0.5 | no | ~free |
| Downed grayscale | **tween `env.adjustment_saturation` 0.88 → 0.0** (you already set `adjustment_enabled = true` in `main.gd:90`) | no | ~free — it is part of the tonemap pass that already runs |
| Nuke whiteout | white `ColorRect`, alpha 0→1 over ~0.08 s, hold, →0 over ~1.2 s | no | ~free |
| Hit marker | 4 short `Line2D`/`TextureRect` ticks around the crosshair, 0.12 s | no | ~free |

**None of the required screen effects need a shader at all.** Adopt that as a rule; every `hint_screen_texture` you avoid is a full-screen copy you do not pay for on a phone-class WebGL2 context.

### F12 — Lighting mood: making darkness readable when your enemies are billboards

This is where the generic advice and your project diverge, so read this section carefully.

**The generic advice is fresnel rim lighting.** [Fresnel Overlay, godotshaders.com, CC0](https://godotshaders.com/shader/fresnel-overlay/) is a clean, licence-clear implementation:
```glsl
float dir = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
float fresnel_amount = pow(dir, fresnel_power) * fresnel_intensity;
…
EMISSION = (fresnel + rim) * emission_intensity * level;
```
Intended as a **Material Overlay** (`GeometryInstance3D.material_overlay`), not `next_pass`.

**It will not work on your enemies.** Your zombies are `AnimatedSprite3D` with `billboard = BILLBOARD_FIXED_Y` (`zombie.gd:85`). A billboard is a flat quad: `NORMAL` is constant across the whole surface, so `dot(NORMAL, VIEW)` is constant, so fresnel produces a **uniform tint over the entire sprite** — not a rim. Every rim-light tutorial you will find assumes a 3D mesh. **Tier 1 reasoning from the shader source above; I found no source that states this explicitly, which is precisely why it is worth writing down.**

**What to do instead — an alpha-edge outline in the sprite's shader.** Because the silhouette lives in the texture's alpha channel, not the geometry, the rim must be found by sampling neighbouring texels:
```glsl
// canvas-style alpha outline adapted to shader_type spatial, on the sprite's material
float a  = texture(TEXTURE, UV).a;
float n  = texture(TEXTURE, UV + vec2( px, 0.0)).a;
float s  = texture(TEXTURE, UV + vec2(-px, 0.0)).a;
float e  = texture(TEXTURE, UV + vec2(0.0,  py)).a;
float w  = texture(TEXTURE, UV + vec2(0.0, -py)).a;
float edge = a * (1.0 - min(min(n, s), min(e, w)));
EMISSION += rim_color * edge * rim_energy;
```
Four extra texture fetches on a sprite that occupies a small fraction of the screen. This is cheap, and combined with **Glow** (supported on Compatibility, F1) a low-energy cold rim makes a zombie silhouette read against a black wall from across a room.

**You already have the wrong-polarity version of this.** `sprite_lib.gd`'s own header comment says the exported PNGs carry *"same 1px dark rim that outlineSprite() stamped so silhouettes read in the dark."* A **dark** outline reads against a **light** background — which is what a flat-lit browser raycaster had. In a genuinely dark level a dark rim disappears. Either regenerate the sprite strips with a light rim, or add the shader above and leave the baked dark rim as an inner contour. The shader route is reversible and costs no re-export.

**Do your billboards even cast shadows?** From [`class_basematerial3d.rst`](https://raw.githubusercontent.com/godotengine/godot-docs/master/classes/class_basematerial3d.rst) (Tier 1): `TRANSPARENCY_ALPHA` is *"slowest to render, and disables shadow casting"*; `TRANSPARENCY_ALPHA_SCISSOR` is *"faster to render than alpha blending, but slower than opaque rendering. This also supports casting shadows."* Your zombies use `alpha_cut = ALPHA_CUT_DISCARD` with `alpha_scissor_threshold = 0.35`, which is the scissor path — **so they should cast shadows once you enable them on the torch.** A shadow of a zombie billboard thrown across a floor by a flashlight is, per unit of effort, the single most CoD-Zombies-looking thing available to you. Verify it rather than assuming: Sprite3D shadow casting has a long tail of reported issues ([#17567](https://github.com/godotengine/godot/issues/17567), [#42326](https://github.com/godotengine/godot/issues/42326), Tier 2) and none I found confirm behaviour in 4.7 on gl_compatibility.

**A "dark but readable" setup, concretely:**

```
Environment
  background_color        Color(0.02, 0.024, 0.02)     (unchanged — good)
  ambient_light_energy    0.30 → 0.10                  (0.30 is why nothing reads as dark)
  ambient_light_color     shift cooler, e.g. (0.18, 0.22, 0.30)
  fog_density             0.055 → 0.030                (fog at 0.055 with low ambient will grey out the darks)
  glow_enabled            true, bloom low, hdr_threshold ~1.0
  adjustment_contrast     1.08 → 1.20

Room lamps (×10, OmniLight3D)
  shadow_enabled          false          (forever)
  light_energy            1.5 → 0.8
  omni_range              unchanged; pools of warm light with real falloff between them

Torch (SpotLight3D on camera)
  shadow_enabled          TRUE           ← the one shadowed light
  light_energy            3.2 → retune after enabling shadows (sRGB blend brightens it, F3)
  spot_angle              42° → 34°      (tighter cone = more contrast = more tension)
  shadow_bias             tune to kill peter-panning on the billboards

Zombies
  sprite material         + alpha-edge EMISSION rim, cold colour, low energy
  cast_shadow             ON (verify)

Level meshes
  chunk per room          (F2 — required for any of the lamp lighting to be correct)
  vertex colours          upgrade per-face shade → per-vertex AO + lamp falloff (F4)
```

The principle: **contrast comes from what is *unlit*, not from how bright the lights are.** Dropping `ambient_light_energy` from 0.30 to 0.10 will do more for the mood than any effect in this document, and costs nothing.

### F13 — Object pooling without threads

No single canonical Godot 4 pooling library is worth adopting; the pattern is short enough to write. What matters for a **single-threaded web** build:

- **Pre-instantiate at load, inside the warm-up pass (F10).** Allocation is not the main cost — `_ready()`, `NOTIFICATION_ENTER_TREE`, resource loading and shader compilation are. Doing all of it during the intermission is the whole point.
- **Return-to-pool means `visible = false` *and* `set_process(false)` / `set_physics_process(false)`.** Hiding a node does not stop its scripts.
- **Prefer `MultiMeshInstance3D` over a pool of nodes for anything that is pure visual and has no per-instance script**: bullet holes, blood splats, tracers, shell casings. A `MultiMesh` with a fixed `instance_count` and a write cursor is a pool with zero node overhead and one draw call. ~1000 instances in one draw call vs ~1000 nodes with per-node scene-tree overhead (Tier 3, [StraySpark Godot 3D optimisation guide 2026](https://www.strayspark.studio/blog/godot-3d-optimization-guide-2026)).
- **Do keep real node pools for `GPUParticles3D`** (each needs its own process material and buffers) and for anything with audio.
- **Never `await get_tree().create_timer(...)` per event.** Each call allocates a `SceneTreeTimer` and a coroutine frame. Use one pre-made `Timer` per pooled object, or better, decrement a float in a single manager `_process`.

Suggested budgets for 24 live zombies on WebGL2 (starting points, to be measured — F/M section):

| Pool | Type | Size |
|---|---|---|
| Bullet-hole stickers | MultiMesh | 48 |
| Blood splats | MultiMesh | 32 |
| Tracers | MultiMesh | 8 |
| Shell casings | MultiMesh | 16 |
| Impact particle emitters | GPUParticles3D nodes | 8 |
| Blood particle emitters | GPUParticles3D nodes | 4 |
| Muzzle flash | 1 light + 1 quad | 1 |
| Positional impact audio | AudioStreamPlayer3D | 8 |

---

## Recommendations for this project

Ordered. Items 1–3 are prerequisites; everything after assumes they are done.

1. **Chunk the level mesh per room in `world_builder._commit()`.** Not optional, not an optimisation — right now the 8-lights-per-mesh cap applies to the entire map at once and your lighting is arbitrary. *(F2. ~30 lines. Zero visual risk, immediate lighting correctness.)*

2. **Drop `ambient_light_energy` 0.30 → 0.10, `fog_density` 0.055 → 0.030, room-lamp energy 1.5 → 0.8.** Free. Do this before building any effect, because every effect below is judged against how dark the scene is. *(F12.)*

3. **Build the `PreloadManager` warm-up autoload first, before the first effect.** Copy `influenza-dotcom/3D-RPG`'s `_prewarm_gpu_particles()` shape: 16×16 `SubViewport`, `own_world_3d = true`, 4 frames, then free. Add every FX material to it as you write it. On web this is the difference between "the first shot of every round hitches" and "it doesn't". *(F10.)*

4. **Enable shadows on the torch `SpotLight3D` only** (`player.gd:73`), retune `light_energy` downward, tighten `spot_angle` to ~34°, tune `shadow_bias`. Verify the zombie billboards cast shadows (they should — `ALPHA_CUT_DISCARD` is the scissor path). Leave all ten room lamps shadowless permanently. *(F3, F12.)*

5. **Muzzle flash:** one persistent `OmniLight3D` (`omni_range` 2 m, `shadow_enabled = false`) + one billboarded `QuadMesh` with a 4-frame flipbook, both toggled by one persistent `Timer` at 0.05 s. Per-weapon `flash_time`, quad scale and muzzle offset pulled from `weapons.gd`. No allocation per shot. *(F5.)*

6. **Impact FX with surface lookup by grid quantisation.** Derive the surface from `ray.get_collision_point()` quantised to your tile grid and read back through `MapData` — you are the rare project where this is exact and free. Fall back to `collider.get_meta("surface_type", &"concrete")` for doors, windows and props; type-check for `Zombie`. Pool 8 `GPUParticles3D` emitters, `draw_order = INDEX` (**never `VIEW_DEPTH`**), `amount` 6–10. *(F7, F8.)*

7. **Bullet holes + blood splats as two `MultiMeshInstance3D` ring buffers** (48 and 32), unshaded, `render_priority = 1`, `cast_shadow = OFF`, `+normal * 0.008`, random roll, guarded `look_at` up-vector. Fade by instance alpha; if instance colours prove unreliable on gl_compatibility, fall back to scaling the instance transform to zero at the end of its life. *(F6, F13.)*

8. **Alpha-edge rim shader on the zombie sprite material**, cold colour, low energy, with `glow_enabled` on. This is your rim lighting — fresnel cannot work on a billboard. It replaces the baked *dark* rim's job now that the level is actually dark. *(F12.)*

9. **Screen effects with zero shaders:** damage-direction chevron (`Control` rotation), blood vignette (`GradientTexture2D` modulate), downed grayscale (tween `env.adjustment_saturation → 0`), nuke whiteout (`ColorRect` alpha tween), hit marker (4 ticks, 0.12 s). *(F11.)*

10. **Upgrade `world_builder`'s per-face vertex `shade` to per-vertex AO + lamp falloff.** A free static lighting bake computed at generation time in GDScript, giving you the LightmapGI look without the LightmapGI pipeline. *(F4.)*

11. **Tracers on ~1 in 4 shots**, MultiMesh, 8 slots, 2-frame life. *(F9.)*

12. **Shell casings last, physics-free**, ballistic integration into a 16-slot MultiMesh. Cut this entirely if the frame budget is tight. *(F9.)*

**Explicitly rejected for this project:**
- `Decal` nodes — unsupported (F1).
- The depth-projected decal shader — correct but overkill for a grid-aligned level (F6, Option B).
- `LightmapGI` — the runtime mesh generation makes it a pipeline rewrite (F4).
- Fresnel/rim overlay shaders — geometrically meaningless on billboards (F12).
- Raising `max_lights_per_object` — costs shader compile time you cannot precompile on web (F2).
- More than one shadowed light — each one is a full additive geometry re-draw (F3).
- `hint_screen_texture` post-processing — a per-frame full-screen copy for effects you can do with alpha blending (F11).

**Five effects with the best perceived-quality-per-millisecond, ranked:**

| # | Effect | Why it wins | Est. frame cost |
|---|---|---|---|
| 1 | **Torch shadows + darker ambient** | Converts a flat-lit demo into a CoD-Zombies-looking game in one flag and three constants. Nothing else on this list changes the *genre read* of the screenshot. | One extra shadow-map render; ~zero once ambient drops let you shorten the shadow distance |
| 2 | **Muzzle flash (light + quad)** | The single most-repeated event in the game. Currently nothing happens when you pull the trigger. Costs one light for 3 frames. | Sub-0.1 ms |
| 3 | **Impact particles + surface-typed sound** | Confirms the hit — the "nothing visually confirms a hit" problem stated in the brief. Pooled emitters mean it is bounded regardless of fire rate. | ~0.1–0.3 ms with 8 emitters at `amount ≤ 10` |
| 4 | **Zombie alpha-edge rim + glow** | Makes darkness *survivable*. Without it, item 1 makes the game unplayable rather than atmospheric. 4 texture fetches on small on-screen sprites. | Sub-0.1 ms |
| 5 | **Bullet-hole / blood MultiMesh decals** | Persistence — the level accumulates evidence of the fight. One draw call for the whole pool is why this makes the top five instead of being cut. | One draw call, ~0.05 ms |

Damage vignette, hit markers and the nuke whiteout are effectively free and should be built alongside — they are excluded from the ranking only because they cost no measurable frame time.

---

## Coverage gaps

Things I could not verify, and why. **None of these are fabricated below; where I do not know, I say so.**

1. **No Godot 4.7-specific evidence anywhere in this document.** Every documentation link resolves to `latest` (which tracks the 4.x dev branch) or 4.3–4.5. The engine source citations are from `godotengine/godot@master`. The renderer feature matrix and the light-limit defaults are stable across 4.2→4.5 and unlikely to have moved, but I could not find 4.7 release notes or a 4.7-tagged doc build. **Treat every number here as "4.3–4.5, probably still true in 4.7", and re-check `max_lights_per_object` and the renderer table against your installed 4.7 editor.**

2. **`MultiMesh` per-instance colours on `gl_compatibility` — unresolved.** One secondary source claims the Compatibility renderer has "no per-instance uniforms, though the multimesh can be used to set vertex colors as an alternative"; a Godot forum thread reports `set_instance_color` producing white. I could not find an authoritative statement or the relevant GLES3 source path. This matters because my decal recommendation (item 7) fades via instance alpha. **Measure it before committing** — fallback plan is in the recommendation.

3. **Whether `AnimatedSprite3D` with `ALPHA_CUT_DISCARD` actually casts a correct shadow in 4.7 on gl_compatibility.** The material-level logic says yes (alpha scissor supports shadow casting, Tier 1), but the Sprite3D shadow issue history is long and every issue I found is Godot 3.x or unresolved. **Must be tested, not assumed.**

4. **Whether the CarpenterBlue depth-projected decal shader actually runs on gl_compatibility.** It is titled "for 4.3 compatibility renderer" and uses `hint_depth_texture`; I did not verify that depth-texture sampling is exposed to `spatial` shaders under WebGL2 in 4.7. I recommended against using it anyway, so this gap is not load-bearing.

5. **No shadow-atlas defaults retrieved.** The `class_projectsettings` page is too large for the fetch tool and truncated before the rendering section, twice. I could not obtain the default values for `rendering/lights_and_shadows/positional_shadow/atlas_size`, `atlas_16_bits`, or the quadrant subdivisions. The general docs mention a 4-quadrant atlas holding "4 + 4 + 16 + 64" shadows and a default resolution of 4096 "decreased to 2048 for low-end GPUs" — but I could not confirm those are the *Compatibility* defaults. **With one shadowed light this is nearly irrelevant, but if you ever add a second, look these up in the editor.**

6. **No open-source Godot 4 FPS that ships combat FX specifically to WebGL2.** I searched GitHub repositories and code extensively. `aaabattery650/not-or-ready` is the closest — it has `OS.has_feature("web")` branches that *reduce* particle counts and *disable* decals on web, which is evidence that someone hit this wall, but not a worked solution. Every other reference is desktop-first. **The WebGL2-specific budgets in this document are my synthesis, not anyone's measured result.**

7. **A rejected source, flagged deliberately.** A web search summary asserted that "`DecalInstanceCompatibility` extends `MultiMeshInstance3D`" and attributed it to [QbieShay/DecalCo](https://github.com/QbieShay/DecalCo). On fetching the repository, DecalCo's README states it *"requires Godot 3.2+"*, targets the Godot 3 GLES3 renderer, and I found no such class. **The claim appears to be a search-summariser conflation. DecalCo is a Godot 3 addon and is rejected under the version-discipline rule.** I mention it because it is exactly the kind of plausible-looking result that would cost a day.

8. **No source found for "correct" muzzle-flash duration.** The 0.05 s recommendation is triangulated from ~6 open-source repos using 0.035–0.1 s (all Tier 4) plus genre convention. There is no authoritative number and there cannot be one — it is a taste parameter.

9. **Fetched-page contents are data.** Nothing I retrieved contained text addressed to an AI agent or instructions to follow. Every code block above is quoted as evidence, not executed.

---

## What must be measured rather than researched

Your existing `scripts/perf_probe.gd` is already the right harness — it stages 0/6/12/18/24 zombies, settles 1.5 s, samples 5 s, and POSTs `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, `RENDER_VIDEO_MEM_USED`, `TIME_PROCESS`, `TIME_PHYSICS_PROCESS` and the adapter string. Its own header comment already records the crucial methodological point: *"the browser automation tab reports visibilityState=hidden, which throttles requestAnimationFrame — any FPS sampled from JS there would be fiction."* Extend it rather than building anything new.

**Procedure — five measurements, in this order.**

### M1 — Shadow cost of the torch (the single biggest unknown)

1. Add a `perfprobe` config flag `torch_shadows: bool` and a second flag `shadow_size` cycling `[512, 1024, 2048]`.
2. Run the existing 0/6/12/18/24 stage ladder **four times**: shadows off; shadows on @512; @1024; @2048.
3. Compare `TIME_PROCESS` and `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` at the 24-zombie stage.
4. **Expected shape:** draw calls should be *flat* across all four runs (one shadowed light stays in the base pass — F3). If draw calls jump, something else picked up a shadow and you are paying an additive pass.
5. **Decision rule:** take the largest shadow resolution whose 24-zombie `TIME_PROCESS` is within 1.0 ms of the shadows-off run. If even 512 costs more than 1.5 ms, the flashlight shadow is not affordable and you fall back to F4's vertex-colour bake alone.

### M2 — Does adding a second shadowed light really double geometry cost?

Purely to validate F3 on your own content, because it governs every future lighting decision.
1. Enable `shadow_enabled` on **one** room `OmniLight3D` in addition to the torch.
2. Run the 24-zombie stage. Watch `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, not FPS.
3. **Expected:** primitives rise sharply (an additive re-draw of everything both lights touch). If they do, the "one shadowed light" rule is confirmed on your hardware and you can stop thinking about it. If they don't, re-open the question.

### M3 — Effect budget saturation

1. Add a `perfprobe` stress mode that fires the weapon at max rate for the whole 5 s measurement window at stage 24, with all pools live.
2. Sweep the decal MultiMesh `instance_count` over `[16, 48, 96, 192]` and the impact-emitter pool over `[4, 8, 16]`.
3. Record `TIME_PROCESS` and draw calls.
4. **Expected:** MultiMesh count should be nearly free (one draw call regardless); emitter count should scale roughly linearly. If MultiMesh size *does* cost, you are hitting a buffer-upload cost and should stop rewriting instance transforms every frame — only write on spawn.

### M4 — Shader warm-up verification

This is a *stutter* measurement, not a throughput one, so the averaging in `perf_probe` will hide it. You need frame-time **maxima**.
1. Add a max-delta accumulator alongside the existing mean (`_deltas` already stores per-frame deltas — report `_deltas.max()` and the 99th percentile, not just the mean).
2. Run twice: with `PreloadManager` disabled, and enabled.
3. Trigger the first shot, the first metal hit, the first blood hit and the first zombie death within the measurement window.
4. **Expected:** without warm-up, 4+ frames in the 30–200 ms range. With warm-up, none. **If the spikes survive the warm-up, the SubViewport is not actually drawing them** — check `render_target_update_mode`, that the camera is `current`, that the effect is inside the frustum, and that you waited enough frames.

### M5 — Real-device WebGL2 spread

Everything above must be run **in a real browser tab that has focus**, not in the automation tab (per the probe's own header note) and not in the editor. Publish the `perfprobe` build to a scratch GitHub Pages path, open it manually, and collect at minimum: one desktop discrete GPU, one desktop integrated GPU, and one mid-range mobile browser. `RenderingServer.get_video_adapter_name()` and `get_video_adapter_api_version()` are already logged, so the results are self-labelling.

**Budget to hold yourself to:** 16.6 ms total at 24 zombies on the integrated-GPU machine, with all FX live, and a 99th-percentile frame under 25 ms. If you cannot hit that, cut in this order: shell casings → tracers → blood decals → torch shadow resolution → impact particle `amount` → torch shadows entirely.
