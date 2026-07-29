# R1 — What actually works in Godot 4.7 `gl_compatibility` on WebGL2

**Research date:** 2026-07-27 · **Adversarially verified:** 2026-07-27 (see [Verification pass](#verification-pass))
**Target:** Godot 4.7, Compatibility rendering method, WebGL 2.0 driver, single-threaded web export, GitHub Pages (no COOP/COEP, no SharedArrayBuffer).
**Primary evidence:** the engine's own `drivers/gles3/` source and `servers/rendering/renderer_scene_cull.cpp`, plus the official renderer feature-comparison tables. Where a claim comes only from an issue or a community post it is tagged as such.

> ### ⚠️ Version-methodology correction (applied throughout)
>
> The first draft read every source claim from `godotengine/godot@master` and `godotengine/godot-docs@master`, on the stated assumption that "the docs site labels master `4.7 (latest/unstable)`". **That assumption was false.** As of 2026-07-27:
>
> - `godotengine/godot@master` → `version.py` = **4.8.0-dev**. It is *not* 4.7.
> - `godotengine/godot@4.7` exists → `version.py` = **4.7.2-rc** (so 4.7.0/4.7.1 are released; the project's `project.godot` declares `config/features=PackedStringArray("4.7", "Forward Plus")`).
> - `godotengine/godot-docs@4.7` exists as a real docs branch.
>
> Every load-bearing claim below has been **re-verified against the `4.7` branch** of engine and docs. In this instance nothing flipped — the GLES3 driver is stable between 4.7 and 4.8-dev on all points checked — but the original document was one merged PR away from asserting an unreleased 4.8 feature as shipping. Two claims (`light_inst_score`, `uses_additive_lighting`) could only be byte-verified on the default branch, because GitHub code search does not index non-default refs; they are flagged individually.
>
> **Rule going forward: read `4.7`, not `master`.** Replace `.../godot/master/...` with `.../godot/4.7/...` in every URL in the Source index.

---

## Bottom line

1. **`Decal` is not supported and will silently do nothing in 4.7.** All `TextureStorage` decal functions in the GLES3 driver are empty stubs (verified on the `4.7` branch). A PR (godot#118070) implements it but is **open and milestoned 4.8** — plan as if decals do not exist. Use quad meshes (see the *revised* Recommendation R1 — the splat-into-`SubViewport` idea has a known Compatibility blocker).
2. **The map's whole-level `MeshInstance3D`s leave you with zero positional-light headroom.** Per-object light selection first gates on *AABB intersection*, then scores survivors by `distance(instance_AABB_center, light_center) / (range × energy)` and silently keeps only the best **8 omni + 8 spot per *instance***. **Corrected project fact:** `world_builder.gd::_commit()` does *not* build one map mesh — it builds **one `MeshInstance3D` per texture** (up to 7 wall + 4 floor + 4 ceiling). But every one of them spans the entire 42×34 map, so they all share the same AABB, the same map-centre score, and therefore the same light list. The project currently spawns **exactly 8 `OmniLight3D`s** (one per `MapData.ROOMS` entry, `main.gd:97-104`) + 1 player `SpotLight3D`. So nothing is being dropped *today* — but the margin is **zero**, and the 9th omni (muzzle flash, Pack-a-Punch, perk machine, powered generator) starts a silent, *stable*, map-centre-scored dropout that is identical across the whole level. **Split into per-room `MeshInstance3D` nodes.** Splitting *surfaces* inside one mesh does not help; pairing is per instance.
3. **Every shadow-casting omni/spot light re-draws each affected instance.** Compatibility puts non-shadowed lights in the single base pass but gives each *shadow-casting* light its own additive pass over the instance. 3 shadowed lights on one giant map surface = 4 full-map draws. Budget shadow-casting lights in single digits, and keep them attached to small instances. (All current lights are `shadow_enabled = false`, so this is a future cost, not a present one.)
4. **`GPUParticles3D` genuinely works** in Compatibility (full transform-feedback implementation in `drivers/gles3/storage/particles_storage.cpp`), **but** trails, sub-emitters, manual `emit_particle()`, vector-field attractors and SDF colliders are hard-unsupported (warning printed, no effect). `draw_order = VIEW_DEPTH` is **reported** to cause GPU→CPU readback stalls on web (single open issue, 4.3/4.4-era, unconfirmed on 4.7 — Tier 3, not Tier 1). Default to `INDEX`/`LIFETIME` because it costs nothing to do so, not because the stall is proven.
5. **There is no shader pre-compilation mechanism on web, and no shader cache either.** The GLES3 program-binary cache is compiled out with `#ifdef WEB_ENABLED // not supported in webgl` — so **every page load recompiles every shader variant from GLSL source**. The official and only remedy is the legacy one: display every material/particle/effect in the camera frustum for at least one frame during a loading screen. Verified verbatim in the `4.7` docs and the `4.7` engine source.
6. **Pleasant surprises — one confirmed, two new:** **SSAO *is* supported in Compatibility as of Godot 4.6** (implemented by GH-109447, shipped in 4.6 beta 1 — attribution now sourced, not inferred). **`SCREEN_TEXTURE`/`DEPTH_TEXTURE` work in spatial shaders.** And, missed by the first draft: **`Environment.adjustment_*` (brightness/contrast/saturation) and colour-correction LUTs (3D or 1D) are fully supported in the Compatibility post pass** — the project already relies on this (`main.gd:89-91`) and it is the cheapest grading tool available to a project with no art team.
7. **Two things the first draft got materially wrong about SSAO, now corrected in F3:** it is not a separate SSAO pass with tunable quality settings — it is *S4AO*, fused into the single post/tonemap fullscreen triangle, and **`ssao_half_size`, `ssao_blur_passes`, `ssao_fadeout_*` and `ssao_adaptive_target` are silently discarded**. Worse for this project: the AO factor is applied as `color.rgb *= s4ao(UV)` on the **fully composited, post-glow scene colour** — so it darkens emissives, muzzle flashes, glow and transparents, not just ambient.

---

## Findings

### F1 — `Decal` nodes: NOT supported in 4.7

| | |
|---|---|
| **Verdict** | Unsupported. Placing a `Decal` node produces nothing. |
| **Tier** | 1 (engine source + official docs table) |
| **Corroboration** | 3 independent |

- Official feature table, `master` (= 4.7): `| Decals | ❌ Not supported. | ✔️ Supported. | ✔️ Supported. |` — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/rendering/renderers.rst (Tier 1)
- Engine source: `drivers/gles3/storage/texture_storage.cpp` lines ~2519-2555, the entire `/* DECAL API */` block (`decal_allocate`, `decal_set_texture`, `decal_set_albedo_mix`, …) consists of empty function bodies. `RasterizerSceneGLES3::render_scene()` accepts `p_decals` and ignores it. — https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/storage/texture_storage.cpp (Tier 1)
- PR "Add decal support to compatibility renderer" godot#118070 is **open**, milestone **4.8**; when it lands its limits will be 8 decals per surface and a default cap of 64 decals in view (`rendering/textures/decals/filter` project setting). — https://github.com/godotengine/godot/pull/118070 (Tier 2)
- Maintainer guidance in the linked discussion, for bullet holes specifically: use individual `QuadMesh` objects positioned near surfaces rather than `Decal`. — https://github.com/godotengine/godot-proposals/discussions/12903 (Tier 2). A third-party plugin (`DecalCompatibility` / `DecalInstanceCompatibility`, by AntzGames) claims ~1000 instanced decals in one draw call; **unverified by me** — see Coverage gaps.

**Fallback techniques (ranked for this project):** see Recommendation R1.

### F2 — Volumetric fog / `FogVolume`: NOT supported. Depth+height fog only.

| | |
|---|---|
| **Tier** | 1 · **Corroboration** 2 |

- `| Volumetric Fog | ❌ Not supported. |` and `| Fog (Depth and Height) | ✔️ Supported. |` in the `master` renderer table (Tier 1, URL as F1).
- `RasterizerSceneGLES3::render_scene()` takes `p_fog_volumes` and does not use it (Tier 1).

`Environment.fog_enabled` (depth + height fog, `fog_light_color`, `fog_sun_scatter`, `fog_aerial_perspective`, `fog_density`, `fog_height`) is fully functional and costs essentially nothing — it is a per-fragment analytic term in the scene shader. This is your atmosphere budget.

### F3 — SSAO: **SUPPORTED** (since 4.6). SSIL and SSR: NOT supported.

| | |
|---|---|
| **Tier** | 1 · **Corroboration** 3 |

- `master` table: `| Screen-Space Ambient Occlusion (SSAO) | ✔️ Supported. | ❌ Not supported (Mobile). | ✔️ Supported. |` (Tier 1)
- Version bisect of the docs table across doc branches (Tier 1):
  - `4.4` → `❌ Not supported`
  - `4.5` → `❌ Not supported`
  - `4.6` → `✔️ Supported`
  - `master` (4.7) → `✔️ Supported`
  (fetched from `https://raw.githubusercontent.com/godotengine/godot-docs/<branch>/tutorials/rendering/renderers.rst`)
- **Attribution now sourced (closes original coverage gap 2):** the implementation is **GH-109447, "simple SSAO in GLES3", listed in the Godot 4.6 beta 1 dev-snapshot release notes** (https://godotengine.org/article/dev-snapshot-godot-4-6-beta-1/, Tier 1). The first draft inferred "since 4.6" from a docs-branch bisect alone; it now has a named PR and a release note.
- SSIL and SSR are `❌ Not supported` in both the Global Illumination and Post-processing tables (Tier 1).

This finding is the single most likely thing to be got wrong: every search result from before mid-2026 (forum threads, proposal godot-proposals#12059, blog posts) says SSAO is unavailable in Compatibility. **That is 4.5-and-earlier information.**

#### F3a — CORRECTED: what the Compatibility SSAO actually *is*, and what it ignores

The first draft said SSAO was "a fullscreen pass" implemented in `rasterizer_scene_gles3.cpp` that you tune by sweeping `quality` and `half_size`. **That is wrong in ways that change the recommendation.** Verified by reading the whole of `drivers/gles3/effects/post_effects.cpp` and `drivers/gles3/shaders/effects/post.glsl` on the `4.7` branch (both small enough to read in full — the original's partial fetch of the 4,000-line `rasterizer_scene_gles3.cpp` is what produced the error). All Tier 1.

**It is "S4AO", and it is fused into the post/tonemap pass — not a separate pass.**
`drivers/gles3/shaders/s4ao_micro_inc.glsl` header: `// S4AO (Stupid Simple Screen Space Ambient Occlusion) - Jonathan Dummer (O1S)`. There are three implementations (`s4ao_micro_inc.glsl` = 3 depth samples; `s4ao_inc.glsl` = an N×N grid with notched corners; `s4ao_mega_inc.glsl` = concentric rings) `#include`d into **`post.glsl`**, the same fullscreen-triangle shader that already does tonemapping, glow compositing, BCS and colour correction. `PostEffects::post_copy()` draws **one** screen triangle. **Marginal cost of SSAO = extra depth taps in an existing pass. No extra render target, no extra draw, no blur pass.** This is materially *cheaper* than the first draft implied, and cheaper than Forward+ SSAO.

**Only two parameters reach the shader. Four are silently discarded.**
```cpp
// drivers/gles3/rasterizer_scene_gles3.cpp
// This SSAO is not implemented the same way, but uses the intensity and radius
// in a similar way.  The parameters are scaled so the SSAO defaults look ok.
ssao_strength = environment_get_ssao_intensity(p_render_data->environment) * 2.0;
ssao_radius   = environment_get_ssao_radius(p_render_data->environment) * 0.5;
```
```cpp
void RasterizerSceneGLES3::environment_set_ssao_quality(RSE::EnvironmentSSAOQuality p_quality, bool p_half_size,
        float p_adaptive_target, int p_blur_passes, float p_fadeout_from, float p_fadeout_to) {
    ssao_quality = p_quality;   // <-- everything else is dropped on the floor
}
```
→ **`rendering/environment/ssao/half_size`, `.../blur_passes`, `.../fadeout_from`, `.../fadeout_to`, `.../adaptive_target` do nothing in Compatibility.** `Environment.ssao_intensity` and `ssao_radius` are the *only* live knobs, at ×2.0 and ×0.5 respectively vs. their Forward+ meaning. (The original's M2 measurement plan told you to sweep `half_size` — delete that step.)

**Quality maps to five shader specialization constants, i.e. five separate program compiles.**
```cpp
VERY_LOW -> USE_SSAO_ABYSS   (s4ao_micro, 3 samples)
LOW      -> USE_SSAO_LOW     (sample_width 2)
MEDIUM   -> USE_SSAO_MED     (default / else-branch)
HIGH     -> USE_SSAO_HIGH    (s4ao_mega, rings)
ULTRA    -> USE_SSAO_MEGA    (s4ao_mega, rings = 4)
```
Relevant to R6: **pick one quality level and never change it at runtime**, or you pay a fresh `glLinkProgram` of the post shader mid-game with no cache to catch it.

**⚠️ The AO is applied to the whole composited image, not to ambient light.** From `post.glsl::main()`:
```glsl
#ifdef USE_GLOW
    color.rgb = color.rgb + glow.rgb - (color.rgb * glow.rgb / srgb_white);
#endif
    color.rgb = srgb_to_linear(color.rgb);
#if defined(USE_SOME_SSAO)
    // Putting SSAO after the conversion to linear color, though it might be better before the glow.
    color.rgb *= s4ao(uv_interp);
#endif
    color.rgb = apply_tonemapping(color.rgb);
```
This is a **screen-space multiply on the final scene colour, after glow has already been added**. Consequences for *this* game specifically:
- Muzzle flashes, the Pack-a-Punch/perk-machine glow, and any emissive material get darkened in creases and near geometry — AO will eat your glow. The engine's own source comment concedes this ordering is questionable.
- Transparent geometry and particles are darkened by the AO of whatever is behind them (they do not write depth, so `s4ao` reads the opaque depth).
- It is *not* physically an ambient term, so it will stack multiplicatively with `ambient_light_energy = 0.30` and the dark fog already configured in `main.gd` — the map is already dark; SSAO on top can crush it to black.
- It reads the depth buffer, so enabling SSAO forces depth-buffer allocation.

**Verdict change:** SSAO stays *recommended* (it is cheap and it is the intended fix for untextured procedural geometry), but it is **a grading decision, not a lighting one**, it must be tuned against the already-dark environment, and it will interact badly with glow. Turn it on *after* the glow pass is dialled in, not before.

**Disconfirming evidence I hunted and what it turned out to be.** godot#62812 "SSAO not working in GLES3 HTML5 Chrome/Firefox" (`GL_INVALID_OPERATION: Feedback loop formed between Framebuffer and active Texture`) looks like a direct refutation and is the first hit for the obvious search. **It is Godot 3.5, milestone `3.x`** — the exact 3.x-as-current trap. It does not apply. I also checked whether the 4.7 code could reproduce that class of WebGL2 feedback-loop bug: it cannot structurally, because `post_copy()` binds `p_source_depth` as a texture while rendering into a *different* framebuffer (`p_dest_framebuffer`), so source and destination are never the same attachment. **No WebGL2-specific SSAO defect found for 4.6/4.7.** (Absence of evidence: the feature is ~6 months old and web-specific reports would be thin either way. Still measure — M2.)

### F4 — `GPUParticles3D`: works, with three hard holes and one web-specific trap

| | |
|---|---|
| **Tier** | 1 for support/holes; 2 for the web readback trap · **Corroboration** 3 |

- `drivers/gles3/storage/particles_storage.cpp` is a complete 1,523-line implementation. Simulation runs in a GLSL vertex shader with **transform feedback** (the GLES3 shader system has a `feedback_count`/`Feedback` mechanism, and `Config::disable_transform_feedback_shader_cache` exists as a driver workaround). This is *not* compute-shader based, which is exactly why it works without compute support. (Tier 1) — https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/storage/particles_storage.cpp
- Hard holes, each an explicit `WARN_PRINT_ONCE_ED` with no effect at runtime (Tier 1):
  - `"The Compatibility renderer does not support particle trails."` (×2 call sites)
  - `"The Compatibility renderer does not support particle sub-emitters."`
  - `"The Compatibility renderer does not support manually emitting particles."` → **`GPUParticles3D.emit_particle()` does nothing.** If you want scripted one-shot emission (impact sparks at an exact position), you must either pre-place emitters and toggle `emitting`, or use `CPUParticles3D`.
  - **Two more the first draft missed**, both explicit warnings in the same `4.7` file: `"Vector field particle attractors are not available in the Compatibility renderer."` and `"SDF Particle Colliders are not available in the Compatibility renderer."` / `"The Compatibility renderer does not support SDF collisions in 3D particle shaders"`. Sphere/box/heightfield attractors and colliders *are* implemented.
  - Hardware exclusion: `ERR_FAIL_COND_MSG(... disable_particles_workaround, "Due to driver bugs, GPUParticles are not supported on Adreno 3XX devices. Please use CPUParticles instead.")` — irrelevant for desktop web, relevant if mobile browsers matter.
- **Web trap — confidence DOWNGRADED (Tier 2 → Tier 3, "reported, magnitude unverified").** With `draw_order = VIEW_DEPTH`, Chrome emits `"performance warning: READ-usage buffer was read back without waiting on a fence. This caused a graphics pipeline stall."` and `"...written again before being read back."` — https://github.com/godotengine/godot/issues/107633.
  What the first draft omitted, all verified from the issue itself:
  - **Tested versions are 4.3.stable and 4.4.1.stable.** Nobody has retested on 4.6 or 4.7. This is exactly the staleness class this document is supposed to catch, and the first draft's own source was two minor versions behind.
  - These are **browser performance *warnings***, not errors. The issue reports console spam; **it contains no frame-time measurement**. "Causes pipeline stalls" is the browser's wording, not a measured cost.
  - **Open, unassigned, 2 comments, zero maintainer confirmation, zero reactions** since Aug 2025. One reporter, one corroborator. This is a single-origin claim, not corroborated evidence.
  - Reported by `antzGames` — **the same author as the `DecalCompatibility` plugin cited in F1**. Not disqualifying, but the two "independent" community data points in this document trace to one person.
  Practical rule is unchanged but the *reason* is: **default to `INDEX`/`LIFETIME` because the sort order is irrelevant for additive muzzle flashes/sparks and costs you nothing** — not because a stall is proven. If you ever need `VIEW_DEPTH` for correctly-sorted alpha-blended smoke, measure it yourself on 4.7 rather than treating this issue as settled.

**Is `CPUParticles3D` the only safe choice?** No — GPU particles are the better default here, because their per-frame CPU cost is ~zero and your bottleneck on a single-threaded wasm build is the main thread. `CPUParticles3D` simulates every particle in C++ on the main thread and re-uploads a `MultiMesh` buffer each frame. Use `CPUParticles3D` only where you need `emit_particle`-style one-shots or trails. **Its practical ceiling is a measurement, not a research result** — see "What must be measured".

### F5 — `Environment` glow / bloom: supported, with a fixed 4-level chain and ignored per-level weights

| | |
|---|---|
| **Tier** | 1 · **Corroboration** 2 |

- `| Glow | ✔️ Supported. |` in the `master` table (Tier 1).
- `drivers/gles3/storage/render_scene_buffers_gles3.cpp::check_glow_buffers()` allocates **exactly 4 levels**, each a half-resolution step from `internal_size`, floored at 4px: `for (int i = 0; i < 4; i++) { level_size = Size2i(level_size.x >> 1, level_size.y >> 1).maxi(4); … }` (Tier 1)
- `drivers/gles3/effects/glow.cpp::process_glow()` runs a fixed pipeline: 1 threshold/filter pass into level 0, then `for (int i = 1; i < 4; i++)` downsample, then `for (int i = 2; i >= 0; i--)` upsample. **8 fullscreen-ish passes total, all at ≤ half resolution.** (Tier 1)
- Parameters actually consumed by the Compatibility path: `glow_intensity`, `glow_bloom`, `glow_hdr_bleed_threshold`, `glow_hdr_bleed_scale`, `glow_hdr_luminance_cap`. **`Environment.glow_levels/1..7` are never read** — there is no `environment_get_glow_level` call anywhere in `rasterizer_scene_gles3.cpp`. Tweaking the level sliders in the inspector will appear to do nothing on web. (Tier 1)
- **`glow_blend_mode`: RESOLVED — it is ignored (closes original coverage gap 3).** `drivers/gles3/shaders/effects/post.glsl` states it outright in a source comment and hard-codes the maths:
  ```glsl
  // Glow always uses the screen blend mode in the Compatibility renderer:
  glow.rgb = clamp(glow.rgb, 0.0, srgb_white);
  color.rgb = color.rgb + glow.rgb - (color.rgb * glow.rgb / srgb_white);
  ```
  So `Environment.glow_blend_mode` joins `glow_levels/*` on the list of inspector sliders that do nothing on web. Screen blend only. (Tier 1)
- **Glow is composited in the same fullscreen triangle as tonemap/SSAO/BCS**, sampling `glow_buffers[0]` with a fixed 12-tap kernel — the 8 downsample/upsample passes of `effects/glow.cpp` produce that buffer, then `post.glsl` does the final combine. Note the ordering: **glow is added *before* `srgb_to_linear` and before SSAO**, which is why SSAO multiplies your bloom down (F3a).
- **Colour precision caveat**: Compatibility renders to **RGBA8, low dynamic range** (`master` table, "Other features"). Glow therefore has very little headroom above 1.0 — `glow_hdr_bleed_threshold` near or below 1.0 is what makes bloom visible at all, and heavy bloom will band (debanding is `❌ Not supported` in Compatibility).

Cost is *not* configurable — you get 4 levels or no glow. It is one on/off decision.

### F6 — Omni/spot shadow maps: SUPPORTED, but multi-pass and expensive with big instances

| | |
|---|---|
| **Tier** | 1 · **Corroboration** 3 |

- Official table: `| Lighting approach | Forward single-pass. Lights with shadows use a multi-pass approach and less accurate blending. |` for Compatibility (Tier 1).
- Full positional shadow implementation in `rasterizer_scene_gles3.cpp`: shadow atlas with quadrants, `_render_shadow_pass()`, `positional_shadow_quality` including `SHADOW_QUALITY_SOFT_LOW`/`SOFT_HIGH` spec constants. (Tier 1)
- **Omni shadow mode restriction (hard error, line ~2307):** `ERR_FAIL_MSG("Dual paraboloid shadow mode not supported in the Compatibility renderer. Please use CubeMap shadow mode instead.")`. `OmniLight3D.omni_shadow_mode` defaults to CubeMap, so this only bites if you deliberately choose Dual Paraboloid — but a cubemap shadow is **6 render passes per light**. (Tier 1)
- **Multi-pass mechanics, from `_render_list_template` (lines ~3326-3400):**
  ```
  bool uses_additive_lighting = (inst->light_passes.size() + p_render_data->directional_shadow_count) > 0;
  uses_additive_lighting = uses_additive_lighting && !shader->unshaded;
  for (int32_t pass = 0; pass < MAX(1, int32_t(inst->light_passes.size() + p_render_data->directional_shadow_count)); pass++) { … }
  ```
  and the split, from `_fill_render_list` (lines ~1351-1395):
  ```
  if (light_storage->light_has_shadow(light) && shadow_id >= 0) {
      … inst->light_passes.push_back(pass);
  } else {
      // Lights without shadow can all go in base pass.
      inst->omni_light_gl_cache.push_back(...);
  }
  ```
  **Non-shadowed omni/spot lights are free-ish (one base pass, up to 8 each). Every shadow-casting light adds one full additional draw of every instance it touches.** (Tier 1)
- Also note `, shadows_disabled` and `, ambient_light_disabled` render modes exist on `BaseMaterial3D` (`FLAG_DONT_RECEIVE_SHADOWS`, `FLAG_DISABLE_AMBIENT_LIGHT`) — a cheap way to exempt big surfaces from additive passes. (Tier 1, `scene/resources/material.cpp`)

### F7 — `MAX_LIGHTS_PER_OBJECT` = 8, silently drops, and **this forces a per-room instance split**

| | |
|---|---|
| **Tier** | 1 · **Corroboration** 2 |
| **This is the most important finding for this project.** | |

- Project setting `rendering/limits/opengl/max_lights_per_object`, **default `8`**. Official description, verbatim: *"Max number of omnilights and spotlights renderable per object. At the default value of 8, this means that each surface can be affected by up to 8 omnilights and 8 spotlights. This is further limited by hardware support and `rendering/limits/opengl/max_renderable_lights`. Setting this low will slightly reduce memory usage, may decrease shader compile times, and may result in faster rendering on low-end, mobile, or web devices."* + *"**Note:** This setting is only effective when using the Compatibility rendering method."* — https://raw.githubusercontent.com/godotengine/godot-docs/master/classes/class_projectsettings.rst (Tier 1)
- Companion limits: `rendering/limits/opengl/max_renderable_lights` = **32** (per light type, per view), `rendering/limits/opengl/max_renderable_elements` = **65536**. `Config::init()`: `max_lights_per_object = MIN(max_lights_per_object, max_renderable_lights)`. (Tier 1)
- **The selection algorithm** (`servers/rendering/renderer_scene_cull.cpp`, `_cull_convex_from_pair` inner loop, lines ~3028-3150), verbatim:
  ```cpp
  Vector3 mesh_center = idata.instance->transformed_aabb.get_center();
  ...
  // Large scores are worse, so linear with distance, inverse with energy and range.
  float light_range_energy = light_get_param(RANGE) * light_get_param(ENERGY);
  float light_inst_score = mesh_center.distance_to(light_center) / MAX(0.01f, light_range_energy);
  // Of the N lights (on a per-light-type basis, Omni or Spot) keep only the M "best" lights.
  ```
  Lights beyond the best 8 are dropped through a max-heap **with no warning of any kind**. (Tier 1)
- **Granularity is the instance, not the surface.** `pair_light_instance()` is a method on `GeometryInstanceGLES3` (one per `MeshInstance3D`); the cull code calls `geom->geometry_instance->pair_light_instance(light->instance, light_type, omni_count++)` and `RasterizerSceneGLES3::pair_light_instance` gates on `if (placement_idx < Config::get_singleton()->max_lights_per_object)`. `mesh_center` comes from `idata.instance->transformed_aabb`. All surfaces of one mesh share one light list. (Tier 1)
  - ⚠️ **Official class docs contradict this wording.** `doc/classes/OmniLight3D.xml` and `SpotLight3D.xml` both say *"only 8 omni lights can be displayed on each **mesh resource**"*. The code says per **geometry instance**. The code is decisive here — but note the discrepancy, because it means two `MeshInstance3D`s sharing one `Mesh` resource get **independent** light lists (good for the split), contrary to what the class reference implies.
- **NEW, and stronger than the distance argument: pairing is gated on AABB *intersection* first.** Same class docs, verbatim: *"When using the Mobile or Compatibility rendering methods, omni lights will only correctly affect meshes whose visibility AABB intersects with the light's AABB."* (Tier 1, `doc/classes/OmniLight3D.xml` / `SpotLight3D.xml`.) A map-spanning instance intersects **every** light in the level, so **all** lights compete for its 8 slots. A per-room instance is only ever a candidate for the handful of lights that physically reach it. This is a cleaner mechanism than the distance-score argument and it is the real reason the split works.

**Corrected project facts (the first draft described code that does not exist).** `scripts/world/world_builder.gd::_commit()` builds **one `MeshInstance3D` per texture name**, grouped under three `Node3D`s (`Walls`, `Floors`, `Ceilings`) — so up to 7 + 4 + 4 = 15 instances, each with `material_override` and `gi_mode = GI_MODE_DISABLED`. It is *not* "one `MeshInstance3D` for the whole map", and it is not "one mesh with N surfaces" either. **The conclusion survives unchanged**, because every one of those 15 instances still spans the full 42×34 grid: identical AABBs, identical map-centre score, identical light lists. But get the premise right before quoting this at anyone.

**Corrected severity — the first draft overstated the *present* damage and understated the *cost*.** `scripts/main.gd:97-104` creates **exactly one `OmniLight3D` per `MapData.ROOMS` entry, and `ROOMS` has 8 entries**, plus one `SpotLight3D` torch on the player (`player.gd:67`). All have `shadow_enabled = false`.
- Omni count = 8, cap = 8. **Nothing is currently being dropped.** The claim "lights will be permanently wrong" is not true today.
- What *is* true today: **zero headroom.** Light #9 — a muzzle flash, a Pack-a-Punch glow, a perk machine, a lit generator, a mystery-box beam — silently evicts a room lamp. Because the score is computed from the map centre for all 15 instances, the eviction is identical everywhere and does not change as the player moves. You will get a room that is dark, in the same way, forever, with no warning printed.
- **The unstated cost the first draft missed:** `OMNI_LIGHT_COUNT` is a uniform, so every fragment of every wall, floor and ceiling **anywhere on the map** currently loops over all 8 omnis, because all 8 are paired to every map-spanning instance. On a fill-rate-limited WebGL2 target this is pure waste. Splitting per room drops most instances to 1-3 paired lights and cuts the base-pass fragment cost proportionally. **This is a present-tense performance win, not just future-proofing** — and it is a better argument for the split than "light selection is arbitrary", which is currently false.
- Additionally, every future shadow-casting light triggers a full re-draw of every map-spanning instance it touches (F6).

**Yes: this forces a split.** Per-room `MeshInstance3D` nodes, each still one surface per texture. The room list already exists (`MapData.ROOMS`, 8 entries) and `world_builder.gd` already iterates tiles with room-derived texture ids, so the change is localised to `_build_static()`/`_commit()`. You keep almost all of the batching win and you regain local light selection, cheaper base-pass fragments, per-room frustum culling, and cheap additive shadow passes.

**Unrelated but adjacent, found while verifying:** every world material sets `mat.cull_mode = BaseMaterial3D.CULL_DISABLED` (`world_builder.gd:44`, with the comment "disabling culling keeps a wrong winding from ever producing an invisible wall"). That disables backface culling on every wall, floor and ceiling in the level. On a fill-rate-bound WebGL2 build this is a self-inflicted ~2× rasterisation cost on all static geometry, taken to avoid debugging winding order. Fix the winding, restore `CULL_BACK`. Not a renderer *constraint*, so it is out of this document's scope — but it is the cheapest frame-time win visible in the codebase and it belongs in the backlog.

### F8 — `MultiMeshInstance3D`: one draw call, custom data available (half-precision). `INSTANCE_CUSTOM` on a plain `MeshInstance3D`: **always zero.**

| | |
|---|---|
| **Tier** | 1 · **Corroboration** 2 |

- Hardware instancing confirmed: `drivers/gles3/storage/mesh_storage.cpp` calls `glVertexAttribDivisor(p_attrib_base_index + 0..3, 1)` for the instance transform / colour / custom-data attributes → a single `glDrawElementsInstanced`. (Tier 1)
- Per-instance custom data supported: `multimesh->uses_custom_data`, `multimesh_instance_set_custom_data`, and stride bookkeeping for it. (Tier 1)
- **Precision warning:** in `drivers/gles3/shaders/scene.glsl`, colour and custom data arrive as one `uvec4` and are unpacked as **half floats**:
  ```glsl
  layout(location = 15) in highp uvec4 instance_color_custom_data; // Color packed into xy, Custom data into zw.
  ...
  vec4 instance_custom;
  instance_custom.xy = unpackHalf2x16(instance_color_custom_data_input.z);
  instance_custom.zw = unpackHalf2x16(instance_color_custom_data_input.w);
  ```
  16-bit float per channel: fine for 0..1 factors and small counters, **not** fine for large integers or precise world coordinates. (Tier 1)
- **`INSTANCE_CUSTOM` on a non-instanced `MeshInstance3D` is hardcoded to zero.** Same shader, the `#else` branch of `#ifdef USE_INSTANCING`:
  ```glsl
  #else
      vec4 instance_custom = vec4(0.0);
  #endif
  ```
  `USE_INSTANCING` is a shader *variant* (`mode_color_instancing`, `mode_depth_instancing`) selected only for MultiMesh/particle geometry. For per-`MeshInstance3D` variation use `GeometryInstance3D.set_instance_shader_parameter()` (a real uniform, full float precision) — but note that gives each instance its own uniform set, so it does not batch. (Tier 1)

### F9 — `SCREEN_TEXTURE` / `DEPTH_TEXTURE` in a spatial shader: **supported**, with two important caveats

| | |
|---|---|
| **Tier** | 1 · **Corroboration** 2 |

- Official table, Shader features: `| Screen texture | ✔️ Supported. |` and `| Depth texture | ✔️ Supported. |` for Compatibility. `| Normal/Roughness buffer | ❌ Not supported. |` (Tier 1)
- Mechanism, `rasterizer_scene_gles3.cpp` ~line 2886: when any visible material sets `uses_screen_texture` or `uses_depth_texture`, the renderer does **one** backbuffer blit (`check_backbuffer` → `glBlitFramebuffer`) **before the transparent pass**, then binds it. (Tier 1)

Caveats:
1. **One snapshot per frame, taken before the transparent queue.** Two overlapping heat-haze quads cannot see each other, and neither can see any other transparent object. Layered distortion will look wrong.
2. **No mipmaps.** `RenderSceneBuffersGLES3::check_backbuffer()` creates the backbuffer colour texture with a single `glTexImage2D` at level 0 and never calls `glGenerateMipmap`. `hint_screen_texture, filter_linear_mipmap` will not give you a blur — you'd get level 0 regardless. Blur must be done by hand-rolled taps. (Tier 1)
3. Using `SCREEN_TEXTURE` forces the material into the transparent queue (`has_read_screen_alpha` → `FLAG_PASS_ALPHA`, see F10) and forces the backbuffer allocation for the whole frame.

**So: no, you do not need a fullscreen `CanvasItem` pass for distortion.** A world-space quad with a spatial shader reading `SCREEN_TEXTURE` works. A fullscreen `CanvasItem`/`ColorRect` pass is still the right tool for *whole-screen* effects (damage vignette, drug-perk warp), and the official table confirms `| Custom post-processing with fullscreen quad | ✔️ Supported. |` while `| Custom post-processing with CompositorEffects | ❌ Not supported. |` — **`CompositorEffect` is Forward+/Mobile only, do not plan around it.**

### F10 — `no_depth_test` vs alpha-scissor surfaces: behaviour is well-defined, and it means `no_depth_test` *always* draws over your billboards

| | |
|---|---|
| **Tier** | 1 · **Corroboration** 1 (source read directly; no secondary source found) |

From `RasterizerSceneGLES3::_geometry_instance_add_surface_with_material()` (lines ~230-260):

```cpp
bool has_base_alpha = ((p_material->shader_data->uses_alpha && !p_material->shader_data->uses_alpha_clip) || has_read_screen_alpha);
...
if (has_alpha || has_read_screen_alpha
    || p_material->shader_data->depth_draw == DEPTH_DRAW_DISABLED
    || p_material->shader_data->depth_test != DEPTH_TEST_ENABLED) {
    ...
    flags |= GeometryInstanceSurface::FLAG_PASS_ALPHA;
```

and in `_render_scene()`: `render_list[RENDER_LIST_ALPHA].sort_by_reverse_depth_and_priority();`

Consequences, all deterministic:

- **Alpha-scissor materials stay in the OPAQUE queue** (`uses_alpha && !uses_alpha_clip` is false when scissoring). They depth-write and self-sort perfectly via the depth buffer. This is why alpha-scissor billboards are the correct choice for your entity sprites, and why they are cheap.
- **Any material with `render_mode depth_test_disabled` (or `depth_draw_never`) is *forced* into the transparent queue**, which runs *after* the entire opaque queue.
- Therefore a `no_depth_test` quad is drawn after — and with depth testing off, unconditionally on top of — every alpha-scissor billboard and every piece of level geometry, **regardless of actual distance**. There is no bug here; the sorting is doing exactly what it says. But it means `no_depth_test` is only correct for things that should genuinely always be visible: the viewmodel, x-ray objective markers, screen-anchored UI-in-world.
- Within the transparent queue, ordering is by reverse depth then `render_priority`, computed **per surface via its instance AABB** — so two large interpenetrating transparent quads will still pop. `render_priority` is your only manual override.
- Corollary trap: **`SCREEN_TEXTURE` users get dragged into the transparent queue too** — so a heat-haze quad cannot be occluded by an alpha-scissor sprite in front of it unless you keep depth *test* enabled (only depth *write* needs to be off).

### F11 — `OccluderInstance3D` / occlusion culling: functions on web, but runs on your one thread

| | |
|---|---|
| **Tier** | 1 for availability; 2 for the cost characterisation · **Corroboration** 2 |

- Occlusion culling is renderer-agnostic — it is a **CPU** system in `servers/rendering/renderer_scene_cull.cpp` (`OCCLUSION_CULLED` macro, `cull_data.occlusion_buffer->is_occluded(...)`), not a GPU feature, so the Compatibility renderer does not exclude it. (Tier 1)
- The implementation is `modules/raycast` (Embree). Its `config.py` explicitly allows the web architecture:
  ```python
  if env["arch"] in ["x86_64", "arm64", "wasm32"]:
      return True
  ```
  → **the module builds for `wasm32`**, so occlusion culling is present in official web export templates. — https://raw.githubusercontent.com/godotengine/godot/master/modules/raycast/config.py (Tier 1)
- **But** `modules/raycast/raycast_occlusion_cull.cpp` parallelises both camera-ray generation and vertex transformation via `WorkerThreadPool::add_template_group_task(...)` with `thread_count = WorkerThreadPool::get_singleton()->get_thread_count()`. On a single-threaded web build that thread count is 1, so all of it executes inline on the main thread, and the `wait_for_group_task_completion` is a no-op wait. Occlusion culling is not free here — it is a main-thread CPU tax traded against GPU draw work. (Tier 1 for the code; the "cost is net-negative on web" conclusion is a hypothesis to measure, not a finding.)
- Relevant tunable: **Rendering → Occlusion Culling → Occlusion Rays Per Thread** (docs, Tier 1).

### F12 — Shader compilation stalls: no cache, no baking, no ubershaders on web

| | |
|---|---|
| **Tier** | 1 · **Corroboration** 3 |

This is the sharpest constraint in the whole document, and the docs state it plainly.

**Official guidance, verbatim** (`tutorials/performance/pipeline_compilations.rst`, `master`):

> **warning**
>
> This page only applies to the Forward+ and Mobile renderers, not Compatibility. Ubershaders and pipeline precompilation rely on functionality only available in modern low-level graphics APIs (Vulkan, Direct3D 12, Metal). The Compatibility renderer uses OpenGL 3.3, OpenGL ES 3.0, or WebGL 2.0 depending on the platform. These versions lack the functionality to effectively implement ubershaders and pipeline precompilation.
>
> To avoid shader stutters in Compatibility, you need to use the legacy approach of **preloading materials, shaders, and particles by displaying them for at least one frame in the view frustum when the level is loading.**

and, on the shader baker:

> It will have no effect if the project uses the Compatibility renderer, or for users who make use of the Compatibility fallback due to their [hardware]. … This also means **the shader baker is not supported on the web platform**, as the web platform only supports the Compatibility renderer.

— https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/performance/pipeline_compilations.rst (Tier 1)

**Worse than that: there is no on-disk shader cache on web either.** In `drivers/gles3/shader_gles3.cpp` the entire program-binary cache (`glGetProgramBinary` / `GL_PROGRAM_BINARY_LENGTH`, save and load) is wrapped in `#ifndef WEB_ENABLED` / early-returns under `#ifdef WEB_ENABLED // not supported in webgl`. WebGL 2.0 exposes no program-binary API. **Every visitor, on every page load, recompiles every shader variant from GLSL source.** (Tier 1) — https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/shader_gles3.cpp

**Why the first muzzle flash hitches specifically.** GLES3 "specialization constants" are not real spec constants — they are `#define`s baked into the GLSL at compile time:

```cpp
for (int i = 0; i < specialization_count; i++) {
    if (p_specialization & (uint64_t(1) << uint64_t(i))) {
        builder.append("#define " + String(specializations[i].name) + "\n");
```

and each unseen `(variant, specialization-mask)` pair triggers `_compile_specialization()` → `glCompileShader` + `glLinkProgram` **inline, mid-frame**. The scene-shader specializations that matter for a shooter are exactly the ones a muzzle flash turns on for the first time: `BASE_PASS`, `USE_ADDITIVE_LIGHTING`, `ADDITIVE_OMNI`, `ADDITIVE_SPOT`, plus the soft-shadow quality tiers and multiview. So the first frame in which a shadow-casting omni light touches a given material is a brand-new program compile.

Good news, though: `OMNI_LIGHT_COUNT` / `SPOT_LIGHT_COUNT` are set with `version_set_uniform(...)`, i.e. they are **uniforms, not defines** — so having 3 vs 7 non-shadowed lights on an object does *not* multiply the variant count. Only the boolean feature toggles do.

**Also note the "hidden node" trick from the docs does NOT work in Compatibility.** The docs say Godot 4.4+ can precompile from a scene instantiated but invisible — that is a RenderingDevice pipeline feature. In Compatibility the geometry must actually be *drawn* (in frustum, visible) for one frame.

### F14 — NEW (added in verification): `Environment` adjustments and colour-correction LUTs are supported

| | |
|---|---|
| **Tier** | 1 · **Corroboration** 1 (engine source read in full; not cross-checked against docs, which do not list these rows) |

Missed entirely by the first draft, and directly relevant to a project whose constraint is "no art team".

`drivers/gles3/shaders/effects/post.glsl` (`4.7`) declares these specializations and implements all of them:
```
USE_MULTIVIEW · USE_GLOW · USE_LUMINANCE_MULTIPLIER · USE_BCS
USE_COLOR_CORRECTION · USE_1D_LUT · USE_SSAO_{ABYSS,LOW,MED,HIGH,MEGA}
```
- **`USE_BCS`** → `Environment.adjustment_brightness` / `adjustment_contrast` / `adjustment_saturation`. Applied after tonemapping; brightness in linear, contrast and saturation in sRGB (the source explains this is deliberate, for project compatibility). **The project already uses this** (`main.gd:89-91`).
- **`USE_COLOR_CORRECTION`** → `Environment.adjustment_color_correction`, sampled as a `sampler3D` LUT, or as a `sampler2D` per-channel 1D LUT when `USE_1D_LUT`. Applied last, on sRGB-encoded values.

**Why this matters here:** a colour-correction LUT is the single highest-leverage art tool available to a solo developer with procedurally-generated textures — it restyles the entire game from one small image, costs one texture fetch in a pass that already runs, and needs no shader authoring. It should be in the backlog, not absent from it.

**Warm-up consequence (R6):** the post shader's variant count is the product of these flags. In practice this project will use exactly one combination (`USE_GLOW | USE_BCS | USE_SSAO_MED | USE_COLOR_CORRECTION`) — **as long as you never toggle glow, SSAO, adjustments or the LUT at runtime.** Every toggle is a new `glLinkProgram` mid-frame with no cache. Decide the post-processing configuration once, at build time.

### F13 — Miscellaneous confirmed limits worth writing down

All Tier 1, from the `master` renderer table unless noted:

| Feature | Compatibility (4.7) | Note |
|---|---|---|
| `ReflectionProbe` | ✔️ **2 per mesh** | vs 8 (Mobile) / unlimited (Forward+) |
| `LightmapGI` | ⚠️ rendering yes, **baking requires RenderingDevice hardware** | bake on desktop Forward+, ship the result |
| `VoxelGI`, SDFGI | ❌ | |
| MSAA 3D | ✔️ | MSAA **2D** is ❌ |
| FXAA, SMAA, TAA, FSR2 | ❌ | Only **SSAA** (render-scale >1) is available — expensive but works |
| Debanding | ❌ | combined with RGBA8, expect banding on gradients/fog |
| Depth of field blur | ❌ | |
| Sub-surface scattering | ❌ | |
| Light projector textures | ❌ | no cookie/gobo textures on spotlights |
| PCSS (all light types) | ❌ | soft shadows limited to the `SHADOW_QUALITY_SOFT_*` blur tiers |
| Compute shaders / `RenderingDevice` | ❌ | any `RenderingDevice` code path is dead on web |
| `CompositorEffect` | ❌ | |
| Colour buffer | **RGBA8, LDR** | no HDR viewport, no HDR output |
| Depth buffer | **24-bit, no reverse-Z** | worse precision than Forward+ → z-fighting risk for offset decal quads |
| Max directional lights | 8 | same everywhere |
| `max_renderable_lights` | 32 (per type, per view) | project setting |
| `max_renderable_elements` | 65536 | project setting |
| Depth prepass | available | `rendering/driver/depth_prepass/enable`, with `disable_for_vendors` list (Tier 1, `drivers/gles3/storage/config.cpp`) |
| **Env. adjustments (BCS)** | ✔️ | **added in verification** — `USE_BCS` in `post.glsl` (F14) |
| **Colour-correction LUT (3D or 1D)** | ✔️ | **added in verification** — `USE_COLOR_CORRECTION` / `USE_1D_LUT` (F14) |
| **`glow_blend_mode`** | ❌ ignored | **added in verification** — screen blend hard-coded (F5) |
| **SSAO `half_size` / `blur_passes` / `fadeout_*` / `adaptive_target`** | ❌ ignored | **added in verification** — discarded by `environment_set_ssao_quality` (F3a) |
| **Particle vector-field attractors** | ❌ | **added in verification** (F4) |

**Project-setting defaults, re-verified against engine source rather than the docs prose** (`servers/rendering/rendering_server.cpp`, `4.7`) — all three original figures are correct:
```cpp
GLOBAL_DEF_RST(PropertyInfo(Variant::INT, "rendering/limits/opengl/max_renderable_elements", ..."1024,65536,1"), 65536);
GLOBAL_DEF_RST(PropertyInfo(Variant::INT, "rendering/limits/opengl/max_renderable_lights",   ..."2,256,1"),      32);
GLOBAL_DEF_RST(PropertyInfo(Variant::INT, "rendering/limits/opengl/max_lights_per_object",   ..."2,1024,1"),      8);
```

**Confirmed: the web build really is Compatibility, and the project has not overridden it.** `main/main.cpp` (`4.7`):
```cpp
GLOBAL_DEF_RST_BASIC(PropertyInfo(Variant::STRING, "rendering/renderer/rendering_method.web",
        PROPERTY_HINT_ENUM, "gl_compatibility"), "gl_compatibility"); // This is a bit of a hack until we have WebGPU support.
```
`gl_compatibility` is both the default **and the only permitted value** for `.web` — the enum hint has exactly one entry. `project.godot` sets no `rendering/renderer/rendering_method` key at all, so desktop/editor runs use `forward_plus` (matching `config/features=PackedStringArray("4.7", "Forward Plus")`) while the web export uses `gl_compatibility`. **The brief's framing premise is correct, and it is not overridable — so every ❌ in this document is unconditional for the shipped build.** Corollary: *the editor is lying to you.* Anything you tune in the editor is being rendered by Forward+; validate every visual decision in an exported web build.

---

## Recommendations for this project

### R1 — Bullet holes and blood splats: **splat-into-texture**, not projected quads

Given "no art team, all art procedural, map batched into ~15 whole-level `MeshInstance3D`s (one per texture)", the ranked options are:

> ### 🛑 RANKING REVERSED BY VERIFICATION
>
> The first draft ranked splat-into-`SubViewport` first and instanced quads second, and did not check whether the `SubViewport` mechanism works in Compatibility. **It has a known, open, Compatibility-specific blocker.**
>
> **godot#86940 — "SubViewport with `CLEAR_MODE_NEVER` does not render when using the Compatibility renderer."** Filed by **rburing, a Godot organisation MEMBER**, with an MRP. Reproducible in 4.1.3.stable, 4.2.1.stable and 4.3.dev1. *"Changing the Clear Mode to Always or Next Frame makes it render something, and so does changing the renderer to Mobile or Forward+."* **State: open. Zero comments. Untouched since 2024-01-07.**
> — https://github.com/godotengine/godot/issues/86940 (Tier 2; reporter is a maintainer, which is as strong as a bug report gets)
>
> An accumulation buffer **requires** `CLEAR_MODE_NEVER` (or `CLEAR_MODE_ONCE`, which decays to `NEVER`): with the default `CLEAR_MODE_ALWAYS` every `UPDATE_ONCE` wipes the previous splats and you get one bullet hole per room, forever. So the recommendation's core mechanism is precisely the combination reported broken on precisely this renderer. Related: godot#86258 reports `SubViewport`-textures-on-meshes failing in *exported* builds unless update mode is `ALWAYS` — which would defeat the whole "render once, cost nothing" premise.
>
> **Not verified on 4.7** — the issue is 2.5 years stale and nobody has retested. It may well be fixed. But it is unrefuted, and it is the kind of thing that costs a solo developer a weekend.
>
> **Revised ranking: build the MultiMesh option (now first) as the default. Treat splat-into-`SubViewport` as a one-hour spike, not a plan.** The spike: `SubViewport` 256×256, `CLEAR_MODE_NEVER`, `UPDATE_ONCE`, draw two quads on two separate frames, sample the texture on a mesh — **in an exported web build, not in the editor** (godot#86258 says editor and export differ). If both quads survive, promote it back. If not, you have lost an hour instead of a redesign.

**Fallback if the spike passes — render splats into a per-room lightmap-style splat texture (a `SubViewport` + `CanvasItem` accumulation buffer).**
Give each room chunk a second UV channel (or reuse UV2, which you can generate at the same time you generate the geometry) mapping the whole room onto one small texture (e.g. 256×256 or 512×512). At runtime, when a bullet hits, convert the hit point to that room's splat-UV, and draw a small textured quad into the room's `SubViewport` with `render_target_update_mode = UPDATE_ONCE`. The room's spatial shader samples the splat texture and blends it over the albedo. Costs: one extra texture sample in the surface shader, one tiny `CanvasItem` draw per bullet hole, zero extra draw calls, zero transparency, zero z-fighting, and the decals are permanently baked so there is no per-decal budget. This composes perfectly with the per-room instance split from R3, and it is entirely procedural — exactly the constraint profile here. It also sidesteps the RGBA8/24-bit-depth z-fighting risk (F13) completely.
*Caveats:* it cannot decal across a room boundary; it needs a UV2 unwrap (trivial for an axis-aligned tile map); it must survive the godot#86940 spike above; and each room needs its own `SubViewport` node kept alive for the whole session (8 rooms × 256² RGBA8 ≈ 2 MB VRAM — fine, but they are real `Viewport`s with real per-frame bookkeeping on your one thread, so set `UPDATE_DISABLED` between hits, not `UPDATE_WHEN_VISIBLE`).

**FIRST (promoted) — instanced quads in one `MultiMeshInstance3D` per room.**
One `MultiMesh` of unit quads, `use_custom_data = true`, `instance_count` sized to your ring buffer (e.g. 128 per room). Push each hole as a transform (position + normal-aligned basis + random roll/scale) and use custom data for `(age, variant_index, alpha, unused)` — remembering the **half-float** precision limit (F8). One draw call per room. Material: `TRANSPARENCY_ALPHA_SCISSOR` (keeps it in the opaque queue, self-sorts by depth, no transparent-queue popping — F10), offset ~2-5 mm along the surface normal. Recycle the oldest slot instead of allocating.
*Do not* use `no_depth_test` for these — F10 shows it would force them into the transparent queue and make them draw through walls.
*Do not* rely on `render_priority` for correctness; with depth-write-on alpha scissor you don't need it.

**Third — vertex-painted / decal-in-material.**
Only viable for coarse ambient grime baked at map-gen time, not for gameplay-driven hits, since your surfaces are large batched quads with few vertices.

**Not viable:** `Decal` nodes (F1). Revisit if and when the project moves to Godot 4.8 and PR #118070 lands — but note even then the limit is 8 decals per surface, which is another reason to have already split the map per room.

### R2 — Atmosphere: depth+height fog, plus SSAO, plus glow. That's the whole budget.

- **Enable `Environment.fog_enabled`** with height fog. It is analytic, per-fragment, and effectively free. Combined with a low `fog_light_color` this is what will sell "dark bunker" without any volumetrics. Fake god-rays with **camera-facing additive cone meshes** with an alpha-gradient shader (`depth_draw_never`, depth *test* on, `render_priority` set) — that is the standard Forward-renderer light-shaft trick and needs no engine support.
- **Enable SSAO** (F3, F3a) — contact shadowing that makes untextured procedural geometry read as solid, which is exactly this project's weakness, and it costs only extra depth taps in the post pass that already runs. **Corrected guidance:** the *only* knobs are `Environment.ssao_intensity` (×2.0) and `ssao_radius` (×0.5); `half_size`, `blur_passes`, `fadeout_*` and `adaptive_target` are discarded. Pick one `ssao/quality` level and never change it at runtime (each level is a separate shader compile with no cache — F3a, F12). **Order of operations matters:** SSAO multiplies the composited, post-glow image, so dial in glow first, then SSAO, then re-check that muzzle flashes and machine glows have not been darkened into the background. The map is already very dark (`ambient_light_energy = 0.30`, `fog_density = 0.055`, near-black clear colour); start `ssao_intensity` low.
- **Enable glow** at a low `glow_intensity` with `glow_hdr_bleed_threshold` around 0.9-1.0 (RGBA8 has almost no headroom). Ignore the `glow_levels/*` **and `glow_blend_mode`** sliders — both do nothing; Compatibility hard-codes screen blend (F5). Use it for muzzle flashes, the Pack-a-Punch machine, Perk machines, mystery-box beam.
- **Keep and lean on `Environment.adjustment_*`** — `adjustment_enabled`/`brightness`/`contrast`/`saturation` (already set in `main.gd:89-91`) and **colour-correction LUTs** (`adjustment_color_correction`, 3D texture or 1D gradient) are genuinely supported in the Compatibility post pass (`USE_BCS`, `USE_COLOR_CORRECTION`, `USE_1D_LUT` in `post.glsl` — Tier 1, F14). For a project with no art budget, a hand-authored 1D/3D LUT is the highest visual-return-per-hour tool available, and it costs one texture lookup in a pass that already runs. The first draft never mentioned this.
- Do **not** put SSR, SSIL, volumetric fog, DoF, FXAA/SMAA/TAA, or any `CompositorEffect` in the backlog. Delete those entries.

### R3 — **Split the batched map into per-room `MeshInstance3D` nodes.** This is the highest-value change in this document.

Concretely:
- Keep the "one surface per texture" batching, but scope it to a **room / chunk**, not the whole 42×34 grid. Each room becomes one `MeshInstance3D` with N surfaces (one per texture).
- **Why — corrected and strengthened (F7).** Light pairing gates on AABB *intersection* first, then scores by distance-from-instance-AABB-centre. A whole-map instance intersects **every** light in the level, so all of them compete for its 8 slots and all of them are evaluated per fragment everywhere. The project is at **exactly 8 omni lights against a cap of 8** — nothing is dropped *yet*, so the original "light selection is meaningless" claim is not true today. The two real reasons to split are:
  1. **Present-tense fill-rate win.** `OMNI_LIGHT_COUNT` is a uniform bounded by the paired count, so every wall/floor/ceiling fragment on the map currently loops over all 8 omnis. Per-room instances drop most to 1-3.
  2. **Headroom.** Light #9 (muzzle flash, Pack-a-Punch, perk machine, generator) silently and *stably* evicts a room lamp, identically across all 15 map-spanning instances, with no warning. Splitting removes the cliff instead of postponing it.
- Second-order wins: per-room frustum culling; per-room occluder geometry; per-room splat textures (R1, *if* the godot#86940 spike passes); shadow additive passes (F6) that re-draw one room, not the map; and it makes `OccluderInstance3D` actually able to reject something.
- **Draw-call arithmetic — corrected.** The real map is **8 rooms** (`MapData.ROOMS`), not ~20, over 7 wall / 4 floor / 4 ceiling texture ids. Today: ≤15 draw calls, all always-visible. After a per-room split: worst case 8 × ~3 distinct textures per room ≈ 24-40 before culling, typically single digits after frustum + room-graph culling. `max_renderable_elements` is 65536; this is noise either way. **The split costs you nothing in draw calls and buys back fragment cost.**
- Consider *also* raising `rendering/limits/opengl/max_lights_per_object` — but be aware the docs note it "may decrease shader compile times" when *lowered*, i.e. raising it costs compile time and per-fragment work. With a per-room split, the default 8 should be ample and **8 is the right answer**; the split is the fix, not the setting.

### R4 — Lighting budget: many cheap lights, very few shadow-casters

- Ambient/fill lights on machines, signs, and windows: `OmniLight3D`/`SpotLight3D` with **`shadow_enabled = false`**. These cost one base-pass iteration each and are near-free up to 8 per room instance (F6).
- Reserve `shadow_enabled = true` for **at most 1-2 lights at a time**, and prefer `SpotLight3D` (single shadow render) over `OmniLight3D` (**6 faces** in CubeMap mode, and Dual Paraboloid `ERR_FAIL`s outright — F6).
- Give large surfaces `FLAG_DONT_RECEIVE_SHADOWS` where the shadow adds nothing, to keep them out of additive passes.
- The muzzle flash should be a **non-shadowed** `OmniLight3D` (plus glow + a sprite), toggled by `visible`. A shadow-casting muzzle flash on a single-threaded web build is not affordable, and it is also a guaranteed first-use shader compile (F12).

### R5 — Particles: `GPUParticles3D` by default, `CPUParticles3D` for scripted one-shots

- Default to `GPUParticles3D` — the CPU is your scarce resource on a single-threaded wasm build, and the GLES3 implementation is real (F4).
- **Set `draw_order` to `INDEX` or `LIFETIME`. Never `VIEW_DEPTH` on web** (F4, issue #107633).
- Design around: no trails, no sub-emitters, no `emit_particle()`. For impact bursts, pre-place a small pool of one-shot emitters and reposition + `restart()` them, or use `CPUParticles3D` where you need the API.
- Use alpha-scissor or additive-with-`depth_draw_never` materials on particles; additive avoids sorting problems entirely and suits muzzle flashes/sparks/embers.
- Enable `local_coords = false` for world-space smoke so it doesn't drag with the emitter.

### R6 — Shader pre-warm is mandatory, and must run on **every** page load

Because there is no shader cache on web (F12), build a `ShaderWarmup` scene shown behind your loading screen that, for **at least one full rendered frame each**:

1. Puts one instance of **every material in the game** inside the camera frustum, actually visible (not just instantiated).
2. Puts one instance of **every particle effect** in frustum, `emitting = true`.
3. Turns on **every lighting configuration you will ever use**, so that the `BASE_PASS`, `USE_ADDITIVE_LIGHTING`, `ADDITIVE_OMNI`, `ADDITIVE_SPOT` and soft-shadow-quality specializations all get compiled: a shadow-casting omni, a shadow-casting spot, and a non-shadowed light, each touching a warm-up quad using each material.
4. Renders with the **same `Environment` resource** the game uses, with SSAO and glow enabled, so the post-process shaders compile too.
5. Uses the same MSAA / render-scale settings as gameplay.

Sequence it across several frames (one material group per frame) and drive a progress bar off it — this makes the compile cost *visible and expected* instead of a hitch. Budget it as real time: this is the load screen. Set `rendering/shader_compiler/shader_cache/enabled` however you like; it is inert on web.

Corollary: **keep the material count small and deliberate.** Every unique `ShaderMaterial` is compile time on every player's first load. Prefer one uber-material with `set_instance_shader_parameter` / MultiMesh custom data over ten near-identical shaders.

### R7 — Occlusion culling: try it, but measure; it is not obviously a win here

`OccluderInstance3D` works on web (F11), but it runs single-threaded on your main thread. For a 42×34 tile map made of large batched surfaces with a per-room split, per-room frustum culling plus a simple room-graph visibility scheme (you already know the room topology from map generation — that is strictly better information than an occlusion rasteriser can derive) will likely beat Embree occlusion culling at a fraction of the CPU cost. Implement portal/room-visibility toggling of `MeshInstance3D.visible` first; only reach for `OccluderInstance3D` if profiling shows GPU-bound overdraw.

### R8 — Backlog entries to delete outright

`Decal` nodes · `FogVolume` / volumetric fog · SSR · SSIL · SDFGI · `VoxelGI` · `CompositorEffect` · depth-of-field · FXAA/SMAA/TAA/FSR2 · debanding · light projector textures · sub-surface scattering · particle trails · particle sub-emitters · `emit_particle()` on `GPUParticles3D` · `GPUParticles3D` SDF collision · HDR viewport/output · anything using `RenderingDevice` or compute shaders · shader baker / pipeline precompilation · `MSAA 2D` · `Environment.glow_levels/*` tuning · `OmniLight3D` dual-paraboloid shadows · `INSTANCE_CUSTOM` on plain `MeshInstance3D` · **`Environment.glow_blend_mode` tuning** · **SSAO `half_size` / `blur_passes` / `fadeout_*` / `adaptive_target` tuning** · **vector-field particle attractors** *(last three added by the verification pass)*.

**Backlog entries to ADD, from the verification pass:**
- **Colour-correction LUT** (`Environment.adjustment_color_correction`) — supported, cheap, and the best art-budget-free visual lever available (F14).
- **Spike godot#86940** (`SubViewport` + `CLEAR_MODE_NEVER` in an exported web build) before committing to any splat-texture design (R1).
- **Restore `CULL_BACK`** on world materials by fixing quad winding in `world_builder.gd` (F7 note) — likely the cheapest frame-time win in the codebase.
- **Re-check `vram_texture_compression/for_desktop=true`** on both web export presets against 64px nearest-filtered pixel-art textures (coverage gap 14).

---

## Coverage gaps

Things I could not verify and why. **None of these are guesses presented as facts.**

1. ~~**Whether the project's Godot 4.7 build exactly matches `master`.**~~ **RESOLVED, AND IT DID NOT.** `master` is 4.8.0-dev; the project is on 4.7. All load-bearing claims re-read against the `4.7` branch — see the version-methodology box at the top. Residual: `light_inst_score` (F7) and `uses_additive_lighting` (F6) were byte-verified only on the default branch, because GitHub code search does not index non-default refs. Both are long-standing code paths and the 4.7 docs describe the same behaviour, but they are the two lines in this document I would re-check first if something behaves unexpectedly.
2. ~~**Godot 4.6 release status.**~~ **RESOLVED.** SSAO in Compatibility is **GH-109447**, listed in the Godot 4.6 beta 1 dev-snapshot release notes as "simple SSAO in GLES3". Godot 4.6 shipped in January 2026. The "since 4.6" attribution is now sourced.
3. ~~**`Environment.glow_blend_mode`**~~ **RESOLVED: ignored.** `post.glsl` comment: `// Glow always uses the screen blend mode in the Compatibility renderer:`, followed by hard-coded screen-blend maths. See F5.
4. **The `DecalCompatibility` third-party plugin** (AntzGames, claimed 1000 instanced decals / 1 draw call). Reported in godot-proposals discussion #12903; I did not retrieve the plugin's repository, licence, or Godot-version compatibility. If you pursue it, check its licence against the "genuinely permissive" constraint first. Tier 4.
5. **MSAA 3D on WebGL2 specifically.** The docs table says Compatibility supports MSAA 3D; I did not find web-specific confirmation or known issues. WebGL2 does support multisampled renderbuffers, so it should work, but the cost on integrated GPUs at 1080p is unknown. Untested.
6. **Whether `Config::disable_transform_feedback_shader_cache` is ever set on web**, and whether any browser/driver blocklist disables GPU particles in practice. The Adreno 3XX block is explicit; nothing web-specific was found.
7. **Actual behaviour of `AlphaAntiAliasing` (`alpha_to_coverage`) on WebGL2.** `BaseMaterial3D` emits `, alpha_to_coverage` render modes for alpha-scissor materials; whether WebGL2 honours `SAMPLE_ALPHA_TO_COVERAGE` consistently across browsers is untested. Relevant because your entity sprites are alpha-scissor billboards and this is the cheapest way to soften their edges.
8. **`ReflectionProbe` "2 per mesh" interaction with the per-room split** — the limit is documented but I did not read the GLES3 reflection-probe pairing code to see whether it uses the same AABB-centre scoring as lights. Assume it does.
9. **Real numbers for anything.** No performance figures in this document are measured. See below.
10. **(added) Whether godot#86940 (`SubViewport` + `CLEAR_MODE_NEVER` broken in Compatibility) still reproduces on 4.7.** Last tested 4.3.dev1, January 2024. Unrefuted and unfixed as far as the tracker shows, but genuinely unknown on 4.7. This gates R1's fallback option — spike it.
11. **(added) Whether godot#107633 (`VIEW_DEPTH` readback stall) still reproduces on 4.7**, and what it actually costs in milliseconds. Last tested 4.4.1. The issue contains no measurement at all.
12. **(added) `SubViewport` cost on a single-threaded web build.** Community reports of severe `SubViewport` performance degradation specific to web exports exist (Godot forum), but I found no controlled measurement and no engine-source explanation. Tier 4. Relevant only if R1's fallback is revived.
13. **(added) Whether the 4.7 GLES3 SSAO has any web-specific defect.** None found. But the feature is ~6 months old and web-specific bug reports for a young feature are thin either way, so "no issues found" here is weak evidence, not a clean bill of health.
14. **(added) `vram_texture_compression/for_desktop=true` on both web export presets** (`export_presets.cfg`). S3TC on WebGL2 requires the `WEBGL_compressed_texture_s3tc` extension, and block compression is actively destructive to the 64px nearest-filtered pixel-art textures this project uses. I did not chase this down — it is outside this document's topic — but it is a plausible latent visual bug and belongs in someone's backlog.

---

## What must be measured rather than researched

Four questions in the brief have no research answer — they are properties of *this* scene on *this* hardware in *this* browser.

### M1 — `CPUParticles3D` practical particle-count ceiling

**There is no published number and there cannot be one**: the cost is (particles × per-particle CPU update) + (per-frame `MultiMesh` buffer upload) on a single wasm thread, competing with your game logic.

Procedure:
1. Export a web build to a local static server (`python -m http.server`, not `file://`).
2. Scene: your actual gameplay scene, plus a script that spawns `CPUParticles3D` emitters of a fixed `amount` (start at 64) on a timer.
3. Instrument with `Performance.get_monitor(Performance.TIME_PROCESS)` and `TIME_FPS`, logged to the browser console each second. Also watch `Performance.RENDER_TOTAL_OBJECTS_IN_FRAME` and `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`.
4. Step `amount` and the concurrent emitter count until frame time crosses 16.6 ms with the game running (not an empty scene — an empty-scene number is useless).
5. Repeat for `GPUParticles3D` with identical visuals to get the real trade ratio. Expect GPU particles to win by a large margin on the CPU axis; the point of the measurement is to find where GPU particles start costing *fill rate* instead.
6. Repeat in both Chrome and Firefox — their WebGL2 implementations and wasm JITs differ enough to move the number materially.

Record the answer as a hard budget constant in code (`MAX_CONCURRENT_PARTICLE_EMITTERS`), not as a habit.

### M2 — SSAO cost on WebGL2, and whether it is worth its frame time

SSAO in Compatibility is new, is a different algorithm from the Forward+ one (S4AO), and forces a depth buffer allocation.

Procedure: same harness as M1. Toggle `Environment.ssao_enabled` at runtime with a debug key and record `Performance.get_monitor(Performance.TIME_PROCESS)` plus wall-clock FPS over 10 seconds in a representative room, at your shipping resolution and render scale. Sweep `rendering/environment/ssao/quality` across its five levels — **but note each level is a distinct shader compile, so warm up or discard the first second of each sample.** Decide against a fixed budget (e.g. "SSAO may cost at most 2 ms"). Do this on a low-end integrated GPU, not your dev machine.

**Corrected — do NOT sweep these, they are discarded by the Compatibility path (F3a):** `half_size`, `blur_passes`, `fadeout_from`, `fadeout_to`, `adaptive_target`. The first draft told you to sweep `half_size`; that measurement would have produced a flat line and you would have drawn the wrong conclusion about noise floor.

**Also measure the visual regression, not just the cost.** Because S4AO multiplies the composited post-glow image, take before/after screenshots of (a) a muzzle flash, (b) a perk machine's glow, (c) a smoke particle in front of a wall corner. If AO is visibly eating emissives, lower `ssao_intensity` rather than disabling it.

### M3 — Shadow-casting light budget

The multi-pass cost (F6) is `instances_touched × shadow_casting_lights` extra draws, and its real cost depends entirely on how big your split instances are.

Procedure:
1. Build the per-room split (R3) first — measuring before the split measures the wrong thing.
2. Add shadow-casting omni lights one at a time in the busiest room.
3. Watch `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` — you should see it jump by roughly (rooms in frustum × surfaces) per added shadowed light. Confirm the model, then read frame time.
4. Also compare `OmniLight3D` (cubemap, 6 shadow renders) vs `SpotLight3D` (1) at equivalent visual coverage.
5. Set `positional_shadow_atlas_size` (Viewport) as low as looks acceptable — on a dark, low-fidelity map, 1024 or 2048 is likely plenty and directly reduces shadow-pass fill.

### M4 — Actual shader-compile stall profile on first load

Procedure:
1. Export web, serve locally, open with the browser devtools **Performance** profiler recording, and hard-reload with cache disabled (this is the honest first-visit case, since there is no shader cache — F12).
2. Play through: fire the weapon, trigger every particle, walk into a room with a shadow-casting light, buy from a machine, take damage (post-process).
3. In the flame chart, look for long main-thread tasks inside the wasm frame; each one is a `glLinkProgram`. Note **which action** triggered each.
4. Add exactly those cases to the R6 warm-up scene, re-export, re-profile with cache disabled, and confirm the stalls have moved into the loading screen.
5. Iterate until no single in-game frame exceeds ~30 ms.
6. Repeat after **every** new material or particle effect is added. This is a permanent maintenance task, not a one-time fix — put it in the release checklist.

There is no substitute for this. There is no API to enumerate the variants Godot will need, no baker, and no cache to fall back on.

---

## Source index

| # | URL | Tier |
|---|---|---|
| 1 | https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/rendering/renderers.rst (and the `4.4`/`4.5`/`4.6` branches of the same path) | 1 |
| 2 | https://raw.githubusercontent.com/godotengine/godot-docs/master/classes/class_projectsettings.rst | 1 |
| 3 | https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/performance/pipeline_compilations.rst | 1 |
| 4 | https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/rasterizer_scene_gles3.cpp | 1 |
| 5 | https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/storage/particles_storage.cpp | 1 |
| 6 | https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/storage/texture_storage.cpp | 1 |
| 7 | https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/storage/mesh_storage.cpp | 1 |
| 8 | https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/storage/config.cpp | 1 |
| 9 | https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/storage/render_scene_buffers_gles3.cpp | 1 |
| 10 | https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/effects/glow.cpp | 1 |
| 11 | https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/shaders/scene.glsl | 1 |
| 12 | https://raw.githubusercontent.com/godotengine/godot/master/drivers/gles3/shader_gles3.cpp | 1 |
| 13 | https://raw.githubusercontent.com/godotengine/godot/master/servers/rendering/renderer_scene_cull.cpp | 1 |
| 14 | https://raw.githubusercontent.com/godotengine/godot/master/scene/resources/material.cpp | 1 |
| 15 | https://raw.githubusercontent.com/godotengine/godot/master/modules/raycast/config.py + raycast_occlusion_cull.cpp | 1 |
| 16 | https://github.com/godotengine/godot/pull/118070 (decals in Compatibility, open, 4.8) | 2 |
| 17 | https://github.com/godotengine/godot/issues/107633 (GPUParticles3D VIEW_DEPTH readback stall on web, open) | 2 |
| 18 | https://github.com/godotengine/godot-proposals/discussions/12903 (decal workarounds) | 2/4 |
| 19 | https://github.com/godotengine/godot/issues/66458 ([TRACKER] 4.x OpenGL Compatibility renderer issues) | 2 — indexed, not read in full |

> **⚠️ Sources 1-15 above cite the `master` branch, which is 4.8.0-dev, not 4.7.** They are retained for traceability of the original draft. For 4.7, substitute `/godot/4.7/` and `/godot-docs/4.7/` in each URL. Sources added during verification are listed below and all cite `4.7` or a version-dated release note.

**Sources added by the verification pass**

| # | URL | Tier | What it settled |
|---|---|---|---|
| 20 | https://raw.githubusercontent.com/godotengine/godot/master/version.py | 1 | `master` = **4.8.0-dev** — invalidated the original's version premise |
| 21 | https://raw.githubusercontent.com/godotengine/godot/4.7/version.py | 1 | `4.7` branch = **4.7.2-rc**; 4.7 is released |
| 22 | https://raw.githubusercontent.com/godotengine/godot-docs/4.7/tutorials/rendering/renderers.rst | 1 | Feature table re-verified on the correct branch |
| 23 | https://raw.githubusercontent.com/godotengine/godot-docs/4.7/tutorials/performance/pipeline_compilations.rst | 1 | F12 re-verified on 4.7 |
| 24 | `godotengine/godot@4.7:drivers/gles3/effects/post_effects.cpp` (read in full) | 1 | SSAO fused into post pass; only intensity+radius consumed; 5 quality specializations |
| 25 | `godotengine/godot@4.7:drivers/gles3/shaders/effects/post.glsl` (read in full) | 1 | `color.rgb *= s4ao(UV)` on composited colour; glow screen-blend hard-coded; `USE_BCS`/`USE_COLOR_CORRECTION`/`USE_1D_LUT` |
| 26 | `godotengine/godot@4.7:drivers/gles3/shaders/s4ao_{micro,,mega}_inc.glsl` | 1 | Algorithm identity: "S4AO — Jonathan Dummer (O1S)" |
| 27 | `godotengine/godot@4.7:{texture_storage,particles_storage,shader_gles3}.cpp` | 1 | F1, F4, F12 re-verified on 4.7 |
| 28 | `godotengine/godot@4.7:modules/raycast/config.py` | 1 | F11 `wasm32` build re-verified on 4.7 |
| 29 | `godotengine/godot:servers/rendering/rendering_server.cpp` | 1 | Project-setting defaults 8 / 32 / 65536 verified in source, not prose |
| 30 | `godotengine/godot:main/main.cpp` | 1 | `rendering_method.web` = `gl_compatibility`, single-value enum |
| 31 | `godotengine/godot:doc/classes/{OmniLight3D,SpotLight3D}.xml` | 1 | AABB-intersection gate on light pairing; "mesh resource" wording discrepancy |
| 32 | https://godotengine.org/article/dev-snapshot-godot-4-6-beta-1/ | 1 | SSAO in GLES3 = **GH-109447**, 4.6 beta 1 |
| 33 | https://github.com/godotengine/godot/issues/86940 | 2 | **`SubViewport` + `CLEAR_MODE_NEVER` broken in Compatibility** — reverses R1's ranking |
| 34 | https://github.com/godotengine/godot/issues/86258 | 3 | `SubViewport`-on-mesh fails in exported builds unless `UPDATE_ALWAYS` |
| 35 | https://github.com/godotengine/godot/issues/62812 | — | **Rejected as evidence: Godot 3.5, milestone `3.x`.** Retained to document the trap |
| 36 | Project source: `project.godot`, `export_presets.cfg`, `scripts/world/world_builder.gd`, `scripts/main.gd`, `scripts/data/map_data.gd`, `scripts/entities/player.gd` | 1 | Every project-fact claim in this document |

**Untrusted-content note:** no fetched page contained text addressed to me or attempting to direct my behaviour. All quoted material is engine source, official documentation, or issue/PR text quoted as data. This note is reaffirmed for the verification pass.

---

## Verification pass

**Date:** 2026-07-27 · **Role:** adversarial verifier, independent of the author.
**Method:** re-derive every load-bearing claim from primary sources; check each source for version drift (3.x-as-4.x, Forward+-as-Compatibility, master-as-release) and for single-origin claims wearing the clothes of corroboration; actively hunt disconfirming evidence for the claims the project would most regret; check every project-fact claim against the actual files.

### What was wrong

| # | Claim as written | Status | Correction |
|---|---|---|---|
| V1 | "`master` docs + `master` engine source, which the docs site labels 4.7 (latest/unstable)" | **FALSE — methodology defect** | `godot@master` is **4.8.0-dev**; real `4.7` branches exist for both engine and docs. Every claim re-verified against `4.7`. **Nothing flipped**, but the document was one merged PR from asserting an unreleased feature. Fixed in the header box. |
| V2 | "the whole 42×34 map as one `MeshInstance3D`" / "one surface per texture inside one `MeshInstance3D`" | **FALSE — codebase not read** | `world_builder.gd::_commit()` creates **one `MeshInstance3D` per texture** (≤15), each map-spanning. The *conclusion* (split per room) survives because all 15 share an AABB, but the premise was invented. F7 rewritten. |
| V3 | "light selection becomes effectively random… lights will be permanently wrong" | **OVERSTATED** | The project has **exactly 8 omni + 1 spot**; the cap is 8 omni + 8 spot. **Nothing is dropped today.** The real finding is *zero headroom* plus a per-fragment cost (all 8 omnis evaluated on every map fragment everywhere). F7 reframed — and the corrected argument for the split is *stronger*, not weaker. |
| V4 | "SSAO… is a fullscreen pass… tune by eye… sweep quality and `half_size`" | **WRONG ON MECHANISM** | It is **S4AO**, fused into the existing post/tonemap triangle (cheaper than implied). **`half_size`, `blur_passes`, `fadeout_*`, `adaptive_target` are silently discarded.** Only `ssao_intensity` (×2.0) and `ssao_radius` (×0.5) are live. New section F3a; M2's sweep instruction corrected. |
| V5 | SSAO presented as "free contact shadowing" | **INCOMPLETE — material omission** | `post.glsl` applies `color.rgb *= s4ao(UV)` to the **composited, post-glow** image. It darkens emissives, muzzle flashes, glow and transparents — the engine's own comment concedes the ordering is dubious. For a game whose set pieces are glowing machines and muzzle flashes, this is the difference between "enable it" and "enable it last, and check your bloom". |
| V6 | R1 ranked splat-into-`SubViewport` **best fit** | **BLOCKED — mechanism never checked** | **godot#86940: `SubViewport` with `CLEAR_MODE_NEVER` does not render in the Compatibility renderer.** Open, filed by a Godot **member** with an MRP, untouched since Jan 2024. An accumulation buffer *requires* `CLEAR_MODE_NEVER`. Ranking reversed: MultiMesh alpha-scissor quads promoted to first; the splat buffer demoted to a one-hour spike **in an exported web build**. |
| V7 | `VIEW_DEPTH` stall stated as a hard rule, Tier 2, "Corroboration 3" | **OVER-CONFIDENT** | One open issue, **tested on 4.3/4.4.1 only**, no maintainer confirmation, no measurement, and its reporter is **the same person** as the `DecalCompatibility` plugin author cited in F1 — so two of the document's "independent" community points share an origin. Downgraded to Tier 3. Recommendation unchanged; its justification replaced with "costs nothing to avoid". |
| V8 | Coverage gap: "`glow_blend_mode` — unknown, test it" | **ANSWERABLE, NOT ANSWERED** | `post.glsl`: `// Glow always uses the screen blend mode in the Compatibility renderer:`. Ignored. Gap closed. |
| V9 | Coverage gap: "'since 4.6' attribution is second-hand" | **ANSWERABLE, NOT ANSWERED** | **GH-109447**, in the 4.6 beta 1 release notes. Gap closed. |
| V10 | *(omission)* | **MISSING FINDING** | `Environment.adjustment_*` (BCS) **and colour-correction LUTs** are fully supported in Compatibility (`USE_BCS`, `USE_COLOR_CORRECTION`, `USE_1D_LUT`). The project already uses BCS. For a no-art-budget project this is the best visual-return-per-hour tool available and it was absent from the document. New finding F14. |
| V11 | *(omission)* | **MISSING LIMITS** | Vector-field particle attractors and SDF particle colliders are also explicitly unsupported (F4). |
| V12 | "2,000 lines of GDScript" (project framing) | **STALE** | `find scripts scenes -name '*.gd' | wc -l` → **2,701**. Trivial, but it is the kind of number that gets repeated. |

### What survived unchanged

Re-verified against the **`4.7`** branch and found correct as written: **F1** (decal API is empty stubs; godot#118070 open, milestone 4.8, 8-decals-per-surface limit confirmed from the PR body) · **F2** (volumetric fog ❌, depth+height fog ✔️) · **F4** support/holes (transform feedback via `glBeginTransformFeedback`; trails/sub-emitters/`emit_particle` warnings verbatim; Adreno 3XX `ERR_FAIL`) · **F6** (dual-paraboloid `ERR_FAIL_MSG` verbatim; the shadow/base-pass split in `_fill_render_list` verbatim) · **F9** · **F10** · **F11** (`config.py` allows `wasm32` — verified on `4.7`) · **F12** (`#ifdef WEB_ENABLED // not supported in webgl` appears three times in `shader_gles3.cpp`, gating `_load_from_cache` and `_save_to_cache`; the docs' Compatibility warning, shader-baker exclusion, and "hidden node trick is Forward+/Mobile only" all quoted correctly from the `4.7` docs) · **F13** table and all three project-setting defaults (8 / 32 / 65536, verified in `rendering_server.cpp` rather than from docs prose) · and the SSAO docs-branch bisect **4.4 ❌ / 4.5 ❌ / 4.6 ✔️ / 4.7 ✔️** (I re-ran it, including the `4.7` branch the author did not check).

**The headline correction stands.** SSAO *is* supported in Compatibility in 4.7. Every pre-2026 source saying otherwise is 4.5-or-earlier. The author was right about the thing they said they were most likely to be wrong about — and wrong about several things they were confident in, which is the usual shape.

### Disconfirming evidence hunted, and what it produced

- **SSAO on WebGL2 specifically.** The top search hit, godot#62812 "SSAO not working in GLES3 HTML5 Chrome/Firefox" with `GL_INVALID_OPERATION: Feedback loop formed between Framebuffer and active Texture`, reads as a direct refutation. **It is Godot 3.5, milestone `3.x`.** Rejected. I then checked whether 4.7 could reproduce that *class* of bug and it structurally cannot: `post_copy()` samples `p_source_depth` while rendering into a different framebuffer. **Net: no disconfirmation found; SSAO claim strengthened.**
- **`SubViewport` accumulation.** Hunted specifically because it was R1's top recommendation and its mechanism was unverified. **Found godot#86940 — a direct, maintainer-filed, Compatibility-specific blocker.** This is the single highest-value result of the verification pass.
- **Decals in 4.7.** Checked whether #118070 had merged into `master` (which, being 4.8-dev, would have shown it). It has not; the 4.7 stubs are empty. **No disconfirmation.**
- **Light-pairing granularity.** Found that the official `OmniLight3D`/`SpotLight3D` class docs say "per **mesh resource**" while the code says per **geometry instance**. Code wins, and the discrepancy is in the project's favour (instances sharing a mesh still get independent light lists) — but the author claimed "Corroboration 2" for a point where the second source actually says something different. Noted inline.

### What remains uncertain (ranked by what it would cost to be wrong)

1. **godot#86940 on 4.7.** Gates R1's fallback. One-hour spike, in an exported web build, before any splat-texture work. *(Coverage gap 10.)*
2. **`light_inst_score` / `uses_additive_lighting` on the `4.7` branch specifically.** Verified only on default-branch (4.8-dev) because GitHub code search cannot target refs. Long-standing code, 4.7 docs agree, but not byte-verified. *(Coverage gap 1 residual.)*
3. **Every performance number.** Still zero measurements in this document. M1-M4 stand; M2 has been corrected. Nothing here licenses a budget decision.
4. **SSAO's visual interaction with glow at this project's darkness level.** Predicted from source-reading, not observed. Cheap to check, and it decides whether SSAO ships.

### One-line verdict

The document's engine facts are, after correction, unusually good — the author read real source rather than blogs, and their flagship claim survived an honest attempt to kill it. Its failure mode was elsewhere: **it did not verify the branch it was reading, it did not read the codebase it was making architectural recommendations about, and it ranked first a recommendation whose central mechanism it had never checked.** Trust the ❌/✔️ tables. Re-derive anything that touches this project's own code.
