# Phase 2 research log — provenance, confidence, coverage gaps

**Date:** 2026-07-27
**Agent:** scholar-core
**Scope executed:** R8 (complete) and R1 (partial — one load-bearing finding, matrix not built).
**Scope not executed:** R2, R3, R4, R5, R6, R7.

**Capability probe:** browser tier live (Chrome, 1 local device); sandbox live; disk live.
No browser escalation was needed — nothing hard-blocked. Budget cap of 5 escalations unused.

---

## 1. R8 — ancestor diff

**Deliverable:** `docs/analysis/ancestor-diff.md`.

**Evidence tier: 1 (primary source).** Every claim is a direct read of source in this
repository — `kriegsnacht.html` and `scripts/**/*.gd`. No web source was involved and no
claim depends on one. Port-status negatives were established by search, and the searches
are printed in §7 of the deliverable so they can be re-run and falsified.

**Confidence: high** for presence/absence claims; **medium** for the "degraded vs present"
judgements in the audio table, which were made by comparing synthesis parameters on paper
rather than by listening. Those are flagged in the deliverable's own gaps section.

**Adversarial pass — what it changed.** One hypothesis was formed and then killed by
evidence, which is worth recording:

> *Hypothesis:* the README warns that the Godot MCP Pro plugin registers three autoloads
> which "ship into the build and try to open localhost WebSockets in the browser" unless
> the plugin is disabled before export. Those three autoloads are **still active** in
> `project.godot:26-28`. Therefore the live public build is probably shipping them.
>
> *Test:* extract strings from the shipped `docs/index.pck`.
>
> *Result:* **disconfirmed.** `godot_mcp` → 0 matches. `MCPScreenshot` → 0 matches. No
> `res://addons/` path appears in the pck at all. The four `mcp` byte hits are the
> absolute build path (`…glike/godot-mcp-pro-v1.15.1`) and a `.mcp.json` filename in build
> metadata — not shipped code. The export was done correctly.

**Residual risk worth acting on anyway:** the three MCP autoloads remain enabled in
`project.godot`, so the *next* export ships them unless someone remembers the manual step.
This is a live footgun that currently depends on human memory. Worth a `.gdignore`, an
export-preset exclude filter, or a pre-export check — cost S, and it protects a public URL.

---

## 2. R1 — renderer constraints (PARTIAL)

**No `docs/RENDERER-CONSTRAINTS.md` was written.** Writing one now would produce a document
that looks authoritative while resting on a single fetched page, which is exactly the
failure mode R1 exists to prevent. What follows is the one finding that is solid, plus an
honest statement of what remains.

### The finding: the project is configured for the wrong renderer

R1 was written on the premise that "the game actually ships on gl_compatibility." That
premise is right about the *shipped build* and wrong about the *project*:

- `project.godot:20` → `config/features=PackedStringArray("4.7", "Forward Plus")`
- The `[rendering]` section contains **no** `renderer/rendering_method` key and **no**
  `rendering_method.web` override — so the project runs on the Forward+ default.
- Godot's official web-export documentation states that Godot 4 can only target WebGL 2.0
  using the Compatibility rendering method, and that Forward+/Mobile are not supported on
  the web platform.
- The build at `docs/` demonstrably runs in a browser (per README), so the shipped build
  *is* Compatibility.

**Therefore: every time anyone opens this project in the editor or runs it on desktop,
they are testing against a different renderer than the one they ship.** That is R1's stated
hazard — "we will author effects nobody sees and debug them against the wrong renderer" —
and it is not hypothetical, it is the current configuration.

**Recommended action (cost S, do it before any VFX work):** set
`rendering/renderer/rendering_method="gl_compatibility"` project-wide, so the editor,
desktop runs, `perf_probe.gd` and the soak test all exercise the shipping renderer. Keeping
Forward+ for editing and Compatibility for shipping is the configuration that makes T0.7
and every VFX item unmeasurable. This finding should be promoted into T0.7, and arguably
into T0.2(c) alongside the texture-compression flags, since it is the same class of defect:
an export preset that does not match its target.

**Confidence: high.** Two independent legs — the local config files (tier 1, primary) and
the official Godot documentation (tier 1) — plus an empirical cross-check (the build runs,
so it cannot be Forward+).

### What is NOT answered

The actual R1 deliverable is a feature matrix, and it does not exist yet. The general
limitation list surfaced during search — no volumetric fog, no SDFGI, no screen-space
reflections, no decals, simplified shadows, reduced particle features — came from **search
snippets that were not independently fetched and verified**, and is therefore
low-corroboration and version-unqualified. It must not be treated as the matrix.

Specifically unanswered, all still blocking: `GPUParticles3D` behaviour on WebGL2 without
compute (and whether `CPUParticles3D` is the only safe option — directly relevant, since
§3 of the ancestor diff makes particles a vertical-slice dependency); `MAX_LIGHTS_PER_OBJECT`
and whether exceeding it silently drops lights on `WorldBuilder`'s map-wide batched
surfaces; `MultiMeshInstance3D` draw-call collapse; `INSTANCE_CUSTOM` on plain
`MeshInstance3D`; `SCREEN_TEXTURE` in spatial shaders; `Environment` glow affordability;
`OccluderInstance3D`; `no_depth_test` sorting against alpha-scissor.

Two sources are already identified for the next pass and were not fetched:
the Godot GitHub tracker issue **#66458** "[TRACKER] 4.x OpenGL Compatibility renderer
issues", and issue **#88214** "Rendering discrepancies between forward_plus and
gl_compatibility" — the latter is close to a purpose-built answer for this project's
situation and should be the first fetch.

---

## 3. Coverage gaps (whole run)

| Gap | Expected contribution | Why not closed |
|---|---|---|
| R1 feature matrix | Gates ~40 backlog items proposing visual techniques | Partial run; only the config-mismatch finding is solid. Two named GitHub issues unfetched. |
| R2 perf envelope | Caps for 3D voices, ragdolls, particles, payload | Not started. Note `perf_probe.gd` exists (208 lines) and its result was never recorded — cheapest first move is to run it, not to search. |
| R3 web persistence / input | `user://` durability, the Escape-key pause question | Not started. The Escape question is a *shipped functional bug* still unconfirmed and is testable against the live `docs/` build with the browser tier. |
| R4 canon WaW/BO1 numbers | Gates T0.1 curve reshape and T1.5 economy | Not started. Highest risk of low-quality sourcing — fan wikis are tier 3-4 and the doc already caught misattributed BO2/BO3-era claims, so this one needs the triangulation discipline most. |
| R5 pathfinding | Gates T4.1 (XL) | Not started. |
| R6 Godot 4.x patterns | Gates T2.2, T1.2, T1.6, T2.5 | Not started. Dominant failure mode is Godot 3.x answers ranking well — needs version-qualified sourcing. |
| R7 art/audio/licensing | Hard prerequisite for the art half; contains an open legal question on a live public URL | Not started. Largest unowned blocker in the plan. |

**Note on R8's own gaps:** listed in §8 of `ancestor-diff.md` — art generation (564-1450)
and the raycaster (1744-1985) were deliberately not inventoried, and projectile/splash
internals (2593-2660) were skimmed rather than line-verified.

---

## 4. Untrusted-content handling

No fetched content contained instructions, and none altered the research plan. The one
fetched page (Godot documentation) was treated as a claim to verify and was cross-checked
against local config files and the observable fact that the deployed build runs.

---

## Sources

- [Exporting for the Web — Godot documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html) (tier 1, fetched)
- [[TRACKER] 4.x OpenGL Compatibility renderer issues — godotengine/godot#66458](https://github.com/godotengine/godot/issues/66458) (tier 2, identified, **not fetched**)
- [Rendering discrepancies between forward_plus and gl_compatibility — godotengine/godot#88214](https://github.com/godotengine/godot/issues/88214) (tier 2, identified, **not fetched**)
- [About Godot 4, Vulkan, GLES3 and GLES2 — Godot Engine](https://godotengine.org/article/about-godot4-vulkan-gles3-and-gles2/) (tier 1-2, snippet only, **not fetched**)
- Primary source, tier 1: `kriegsnacht.html`, `scripts/**/*.gd`, `project.godot`, `export_presets.cfg`, `docs/index.pck` in this repository.
