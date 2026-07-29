# R5 — Pathfinding architecture for a 24-agent horde on a single thread

Research date: 2026-07-27 · Target: Godot 4.7, single-threaded HTML5/WASM, gl_compatibility, 24 agents, 42×34 tile grid.

Capability line for this run: browser tier live but unused (no source hard-blocked); sandbox live (used to extract two PDFs and to read Godot source); disk live.

---

## Bottom line

- **Keep the BFS flow field. Do not migrate to `NavigationRegion3D` + `NavigationAgent3D`.** Not because 24 queries are too many — they probably are not — but because Godot's navigation module *hard-disables* its async path in non-threaded builds (`use_async_iterations` is compiled to `false`, `WorkerThreadPool` runs every task inline on the caller), so every door purchase becomes a fully synchronous main-thread navmesh rebuild, and every unreachable-target frame becomes an exhaustive polygon search × 24. Both of those are structural to *this* game (door-gated rooms, a moving player) and neither exists with a flow field. Tier 1 + Tier 2, corroborated 3×.
- **The canonical published architecture is the one you already half-have.** Emerson's *Crowd Pathfinding and Steering Using Flow Field Tiles* (Supreme Commander 2, Game AI Pro ch. 23) specifies exactly: an integration pass, an **LOS pass with Bresenham corner-shadow lines**, an 8-neighbour flow pass, **cost stamps** for placed props, and a **blur pass that adds a cost gradient near walls**. Your LOS override and prop-stamping requirement are both named features of the reference design, not improvisations. That chapter also explicitly lists *"Support 3D spaces by connecting portal graph nodes across overlapping sectors"* as **future work** and *"Multiple goal flow fields are perfect for zombies chasing heroes"* as future work — i.e. the canonical flow-field paper punts on verticality. There is no well-known published layered-flow-field write-up to copy. Tier 1 (primary text), corroborated 0× on verticality — that is a genuine gap, not an oversight.
- **For verticality, do not build a layered flow field first.** Build **single-layer grid + an explicit list of vertical link edges** (≈30 lines: the BFS neighbour loop gains `+ links[i]`). That covers stairs, ramps and drop-downs whose footprints do not overlap in plan — which is every WaW-era Zombies staircase. Only if you need genuinely *stacked* floors do you go to the multi-level-surface model (per-column list of `(height, dist)` spans + explicit connections), which is exactly what Recast's `rcHeightfieldLayer`/`rcHeightfieldLayerSet` already is, and is the only battle-tested reference implementation of that data structure I found. Tier 1.
- **Your real crowd bug is not the pathfinder, it is the force balance.** `SEPARATION_FORCE = 2.4` multiplies a per-neighbour push that reaches magnitude 1.0 as separation → 0, and it is summed over *all* neighbours, then added to a **unit-length** flow direction before normalising (`zombie.gd:153-154`). With 4+ crowded neighbours the separation term is 5-10× the steering term, so a dense pack becomes a repulsion gas that can move *away* from the player and into walls. Clamp the separation vector's magnitude to ≤ ~0.6 before adding. This is a code reading, not a citation — verify it by logging `_separation(here).length()` under a pack.
- **Layout invariants you can check programmatically, derived from your own constants** (collider radius 0.26 m, `SEPARATION_RADIUS` 0.62 m, 1 tile = 1 m): agents abreast in a corridor of width `W` metres = `floor((W − 0.52) / 0.62) + 1` → **1 tile = single file (guaranteed conga line), 2 tiles = 3 abreast, 3 tiles = 5 abreast**. Every door and opening in `map_data.gd` is already 2 tiles wide, so the shipped map passes. Throughput per portal from the pedestrian fundamental diagram (Weidmann) is ≈1.2 persons/(m·s) at capacity → **a 2-tile door passes ~2.4 zombies/s**; that number, not vibes, sets the max simultaneously-active spawn windows.
- **Two numbers must be measured, not researched, before any of this is decided:** (a) the wall-clock cost of one 1428-tile GDScript BFS sweep in the *exported WASM build*, and (b) the cost of 24 `NavigationServer3D.map_get_path` calls against your baked mesh in the same build. Nobody has published either. Procedure at the end.

---

## Findings

### F1. In a non-threaded build, Godot's navigation async path is compiled off and every task runs inline on the main thread

`NavMap3D`'s constructor:

```cpp
#ifdef THREADS_ENABLED
	use_async_iterations = GLOBAL_GET("navigation/world/map_use_async_iterations");
#else
	use_async_iterations = false;
#endif
```

and `set_use_async_iterations()` is a no-op without `THREADS_ENABLED`. `_build_iteration()` therefore takes the `else` branch and calls `NavMapBuilder3D::build_navmap_iteration(iteration_build)` **synchronously**, inside `NavMap3D::sync()`, which `GodotNavigationServer3D` runs during `physics_process`.

- Tier 1 — https://github.com/godotengine/godot/blob/master/modules/navigation_3d/nav_map_3d.cpp (lines ~338-465, ~843-890); mirrored at the `4.7-stable`, `4.6-stable`, `4.5-stable` tags (all three return HTTP 200 for the same path — I read `master`; see coverage gaps).
- Corroboration 1: `main/main.cpp` — under `#else` (no `THREADS_ENABLED`) the engine calls `WorkerThreadPool::get_singleton()->init(0, 0)`, i.e. **zero worker threads**. Tier 1, https://github.com/godotengine/godot/blob/master/main/main.cpp (~line 2076).
- Corroboration 2: `WorkerThreadPool::_post_tasks()` — *"Fall back to processing on the calling thread if there are no worker threads."* `bool process_on_calling_thread = threads.is_empty() && !p_pump_task;` and `wait_for_group_task_completion()` is entirely `#ifdef THREADS_ENABLED` (a no-op otherwise). So RVO avoidance group tasks also execute inline. Tier 1, https://github.com/godotengine/godot/blob/master/core/object/worker_thread_pool.cpp
- Corroboration 3: the PR that introduced async iterations says it is *"slightly slower on simple maps or single-threaded builds"* because sync now requires extra operations, and the main benefit *"wouldn't apply without threading support."* Tier 2 (maintainer smix8), https://github.com/godotengine/godot/pull/100497
- Corroboration 4 (docs, independent): `NavigationRegion3D.bake_navigation_mesh(on_thread = true)` — *"Baking on separate thread is useful because navigation baking is not a cheap operation"* and **"Baking on a separate thread is automatically disabled on systems that do not support threads (such as Web)."** Tier 1, https://docs.godotengine.org/en/latest/classes/class_navigationregion3d.html

**Independent corroboration count: 4.**

Consequence for Kriegsnacht specifically: opening a door (four purchasable doors + debris) invalidates the navmesh. On desktop that rebuild is hidden on a worker thread; on GitHub Pages it is a main-thread hitch at the exact moment the player is spending 750-1250 points and expecting responsiveness. The flow field's equivalent cost is one 1428-cell BFS.

### F2. Unreachable targets are the documented catastrophic failure mode of Godot navigation — and this game creates them by design

Godot's own optimisation page: *"A common problem is a sudden performance drop when a target position is not reachable in a path query."* The search cannot early-exit and must exhaust the polygon set.

- Tier 1 — https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_optimizing_performance.html
- Corroboration: maintainer smix8 on a report of 2000-3000 fps → **40-60 fps** on an RTX 4070 caused solely by agents targeting unreachable positions; his advice is *"Stop calling `get_next_path_position()` every physics process when the position and path has not changed and only try a new query after some time."* Tier 2, https://forum.godotengine.org/t/godot-terrible-performance-on-navigationagent3d/64567
- Corroboration: the same page warns *"Divide the total number of NavigationAgents into update groups or use random timers so that they do not all request new paths in the same frame."* Tier 1, same URL.

**Independent corroboration count: 3.**

Zombies is a genre where the player is routinely on the other side of an unpurchased door, and zombies spawn in unopened rooms. Your BFS gets unreachability *for free* (`dist == -1`, and `FlowField.reachable()` already exposes it) at zero marginal cost. Emerson's chapter names the same idea and calls it an **island field** — per-sector island IDs, per-cell only where a sector contains more than one island — used in SupCom2 to grey out the cursor over unreachable ground. Tier 1, Game AI Pro ch. 23 §23.14.

### F3. There are no published performance numbers for Godot navigation under WASM single-thread

I could not find any. The docs page on optimising navigation contains **no concrete numbers at all**. Community reports are qualitative ("terrible performance", "lag spikes after exporting to the Web"). The one Godot benchmark harness I found with a pathfinding scene (kyboon's *Godot Test Bench*) publishes no result table.

- Tier 1 (absence): https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_optimizing_performance.html
- Tier 4: https://forum.godotengine.org/t/the-game-lagging-after-exported-to-the-web-html/41347 ; https://github.com/godotengine/godot/issues/86913

**This is a measurement problem, not a research problem.** See the last section.

### F4. The reference flow-field architecture (Supreme Commander 2) — and what of it you are missing

Primary source, read in full: Elijah Emerson, "Crowd Pathfinding and Steering Using Flow Field Tiles", *Game AI Pro* ch. 23, pp. 307-316. Tier 1 (primary published text). https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter23_Crowd_Pathfinding_and_Steering_Using_Flow_Field_Tiles.pdf

| SupCom2 feature | Your status | Verbatim detail worth copying |
|---|---|---|
| Cost field (8-bit, 255 = wall, 1-254 = cost) | **Missing** — you have a binary `is_blocked` | *"Cost fields have at least a cost of one for each grid location"* |
| Wall-adjacency blur | **Missing** | *"We would run a blur pass to add a cost gradient near walls to improve flow results when going down hallways and around jagged edges."* — this is the published fix for corner bunching |
| LOS pass with Bresenham corner shadows | **Partially present** (raw physics ray per agent per tick, ungated by range) | *"When an agent is within the LOS it can ignore the Flow field results altogether and just steer toward the exact goal position. Without the LOS pass, you can have diamond-shaped flow directions around your goal due to the integrator only looking at the four up, down, left, and right neighbors."* |
| 8-neighbour flow pass over a 4-neighbour integration | **Present** (`direction_at` checks 8, BFS uses 4) | Matches the reference exactly, including their advice *not* to integrate over 8 |
| Cost stamps for placed structures | **Missing** — this is your T3.4 prop requirement | *"Cost stamps record the original cost field values before replacing them with a new set of costs. After placing a cost stamp down, the overlapping sectors would be flagged as dirty"* |
| Wall cushioning for large agents | **Missing** | *"a special wall cushioning process was run over the map that moved the walls outward … closing off skinny gaps that are too small for large units"* — this is the programmatic corridor-width test, run as a preprocess |
| Island fields (reachability) | **Present in effect** (`dist == -1`) | §23.14 |
| Direction blending across cells | **Missing** | *"storing off a path direction vector and blending in new flow directions as you cross grid squares … smooths out the flow field directions"* |
| CPU cap | Not needed at 1428 cells | *"You can enforce low CPU usage by capping the number of tiles or grid squares you commit to per tick."* |
| 3D / multi-level | — | **Listed under §23.16 Future Work**: *"Support 3D spaces by connecting portal graph nodes across overlapping sectors."* |

Note the significance of that last row: the single most-cited flow-field architecture in games shipped without verticality and named it as unfinished work.

Two smaller corroborating implementations, both Tier 3, both consistent on the LOS point and the corner-cutting point:
- https://howtorts.github.io/2014/01/04/basic-flow-fields.html — notes *"there are grid squares which don't give the most efficient path"* from 8-direction-only flow, and that SupCom2's LOS tests are the fix.
- https://www.redblobgames.com/pathfinding/tower-defense/ — the flow field is *"the negative gradient of the distance field"*; BFS from the goal is the right tool *"when lots of enemy positions (sources)"* share one destination, and BFS marks reachability for free.

### F5. Local minima are impossible in your field; the failure modes are elsewhere

A BFS/Dijkstra integration field is, by construction, a monotone distance-to-goal function over the connected component containing the goal. Every non-goal cell has at least one 4-neighbour with strictly smaller distance (its BFS parent). So **there is no local minimum**, and `direction_at`'s `nd < best` descent can never stall inside the reachable set. This is a property of the algorithm, not a claim needing a citation — but it is worth stating because "flow fields have local minima" is a widespread confusion imported from *potential-field* methods, which are a different technique (sum-of-repulsors, which genuinely do trap).

The real failure modes at 24 agents, ranked, with sources:

1. **Conga lines / single-file at chokepoints.** The best-documented failure. jdxdev abandoned flow fields over exactly this: *"When 100 or so units all had to move around a corner to a common destination they tended to cluster quickly and end up forming into a single/double file line, like a line of ants."* Tier 3, https://www.jdxdev.com/blog/2020/05/03/flowfields/ — his fix was waypoints-with-per-unit-offsets, which is a *different* fix from Emerson's (blur + LOS). Both are real; the blur is far cheaper.
2. **Diamond artifacts near the goal** from 4-neighbour integration. Emerson, §23.6.2. Fixed by the LOS pass. Tier 1.
3. **Diagonal corner-cutting.** Already handled correctly in `flow_field.gd:63-66` (rejects a diagonal if either orthogonal is blocked). Matches howtorts' stated limitation, which you have already fixed. Tier 3.
4. **Agents piling at shared waypoints regardless of avoidance.** Pentheny: *"In high-density crowd situations, solely relying on local collision avoidance and idealized pathfinding will cause agents to pile up at popular, shared path waypoints. Collision avoidance algorithms only help avoid local collisions in the pursuit of following the ideal path."* Tier 1 (primary published text), *Game AI Pro 2* ch. 17, https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter17_Advanced_Techniques_for_Robust_Efficient_Crowds.pdf
5. **Stale field.** Already identified in your gap analysis (`flow_field.gd:22-27` early-returns on unchanged player tile; the door path never invalidates). Not a research finding — a bug.

### F6. The standard technique for "horde, not conga line", when everyone shares one destination

The published answer is a **congestion map**: a coarse grid holding aggregate crowd *density* and aggregate crowd *velocity*, folded into the traversal cost so that moving against or across the crowd costs more, and dense areas cost more.

Pentheny's traversal-cost kernel, quoted verbatim from the chapter (Listing 17.1):

```c
float congestionPenalty(Vec2 ideal, Vec2 aggregate, float density) {
    float cost = Vec2.dot(ideal, aggregate);
    cost /= ideal.mag() * ideal.mag();
    if (cost >= 1) return 0.0f;      // crowd already moving faster along ideal
    return (1 - cost) * density;      // positive ⇒ heuristic stays admissible
}
```

Key properties he states: the penalty *"is never negative, it maintains heuristic admissibility"*; *"the congestion map resolution can be much smaller than the world discretization resolution and still maintain much of its effectiveness"*; and the named drawback is oscillation — *"agents appearing to 'change their mind' as congestion eases"* — for which the stated remedy is **hysteresis** (§17.11): stay on the current path until congestion has exceeded a threshold *for a duration*.

- Tier 1 (primary text), https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter17_Advanced_Techniques_for_Robust_Efficient_Crowds.pdf
- Prior art he distinguishes it from: Direction Maps (Jansen & Sturtevant 2008 — temporally smoothed, slower to react, assume homogeneous agents), density constraints (Karamouzas 2009), density-based crowd simulation (van Toll 2012). Tier 1 (cited bibliography, not independently retrieved — see gaps).
- Corroboration on the negative case: Godot's own avoidance docs, *"Avoidance exists in its own space and has no information from navigation meshes or physics collision"* and *"RVO avoidance makes implicit assumptions about natural agent behavior … very clinical avoidance test scenarios will commonly fail."* Tier 1, https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html — i.e. RVO/ORCA is not the horde-feel solution either.

**Independent corroboration count: 3** (Pentheny primary; jdxdev's independent failure report; Godot docs' negative statement about avoidance).

The cheap version of this for a 24-agent horde is *not* full congestion maps. It is: **variance**. Per-agent speed jitter, per-agent goal offset (aim at `player + R·unit_random`, R ≈ 1.2 m, re-rolled every few seconds), staggered LOS override, and the wall-blur cost gradient. Congestion maps earn their complexity at "tens or hundreds of thousands of agents" (Pentheny's own framing), not at 24.

### F7. The 2.5D / layered representation: the reference implementation is Recast's layered heightfield

Recast — which is also Godot's own navmesh baker — represents multi-level worlds exactly the way your brief hypothesised: *"The rcHeightfield is the initial voxelization … representing space as a grid of columns, each containing a linked list of spans."* Then `rcHeightfieldLayer` is *"a heightfield layer within a layer set"*, with fields `heights` (w×h), `areas` (same size), **`cons` — packed neighbour connection information (same size)** — plus `hmin`/`hmax`, `minx`/`maxx`, `miny`/`maxy`, `cs`, `ch`. `rcHeightfieldLayerSet` *"represents a set of heightfield layers."*

That is precisely "tiles carrying a list of (height, distance) cells with explicit vertical links": `heights` is the height, `cons` is the explicit link set, and your `dist` is a parallel array of the same shape.

- Tier 1 — https://recastnav.com/structrcHeightfieldLayer.html and https://recastnav.com/structrcCompactHeightfield.html
- Tier 3 corroboration — https://deepwiki.com/recastnavigation/recastnavigation/2-recast:-navigation-mesh-generation
- Academic corroboration for the same data structure under a different name: **Multi-Level Surface (MLS) maps** — *"2.5D maps that incorporate level labels on vertical cells to represent the environmental structure … on multi-layered terrains."* Robotics literature, Tier 3 as retrieved (see gaps — I got this via search snippet from a 2025 arXiv path-planning survey, https://arxiv.org/pdf/2504.21622, and did not retrieve the original Triebel/Pfaff/Burgard MLS paper).
- Tier 3, robotics: HSGM keeps *"independent map representations for each floor"* with a state machine that switches floors on *"a valid platform and a significant vertical displacement"* — the floor-transition logic you would need. https://arxiv.org/pdf/2606.00095

**Independent corroboration count: 3.** But note: **no game-development write-up of a layered flow field was found.** The engineering pattern exists (Recast, MLS maps); the *game* write-up does not.

### F8. Godot's own answer for verticality, if you ever go hybrid

`NavigationLink3D` is Godot's explicit off-mesh connection primitive, and `NavigationRegion3D.enabled` (bool, default true) lets you toggle a whole region without rebaking — which would be the cheap way to model door purchases *if* you were on navmesh. Tier 1, https://docs.godotengine.org/en/latest/classes/class_navigationregion3d.html

Also relevant if you ever bake: *"a navigation mesh only describes a traversable area for an agent's center position. Any radius values an agent may have are ignored"*; `agent_radius` *"shrinks the baked navigation mesh to have enough margin for the agent (collision) size"*; `agent_height` and `agent_max_climb`/`agent_max_slope` exclude un-fitting or too-steep areas; and *"A too small `cell_size` or `cell_height` can create so many voxels that it has the potential to freeze the game or even crash."* Tier 1, https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationmeshes.html

Known open-ish quality issue: agents pathing outside the navmesh and sticking on static-collider corners (Godot 4.2.1; issue closed, no maintainer resolution visible in the thread). Tier 2, https://github.com/godotengine/godot/issues/88237

### F9. Layout invariants — derived, and checkable in code

These are **derivations from your own constants plus one cited empirical law**, not findings copied from a source. Treat the formulas as design tools to be validated by playtest.

Constants in play: 1 tile = 1 m (`map_data.gd` header); zombie capsule radius **0.26 m** (0.30 for hounds) (`zombie.gd:75`); `SEPARATION_RADIUS = 0.62` (`zombie.gd:11`); base speed 1.2 m/s (`zombie.gd`); grid 42×34.

**I1 — Corridor width vs agents abreast.** The separation force reaches equilibrium at centre-to-centre spacing = `SEPARATION_RADIUS`. Bodies need `radius` clearance at each wall. So

```
agents_abreast(W_metres) = floor((W - 2*0.26) / 0.62) + 1
```

| corridor width | agents abreast |
|---|---|
| 1 tile | **1** — guaranteed conga line |
| 2 tiles | 3 |
| 3 tiles | 5 |
| 4 tiles | 6 |

**Invariant: no tile on any spawn→player route may have a corridor width of 1.** Check by computing a Chebyshev/Manhattan distance transform of the blocked grid, then, for every reachable floor tile, `clearance[i] >= 1` (i.e. the tile has a non-blocked orthogonal partner perpendicular to the local flow direction). Every `DOORS` entry and every `OPENINGS` pair in the current `map_data.gd` is 2 tiles wide, so **the shipped map passes I1 at all portals** — verified by reading `map_data.gd:57-70`.

**I2 — Portal throughput and max simultaneously-active spawn points.** Pedestrian fundamental-diagram literature puts maximum *specific flow* at roughly **1.2-1.3 persons/(m·s)** with free speed ≈1.34 m/s and jam density ≈5.4 /m² (Weidmann's diagram, the standard validation reference in the field). Tier 3 review: https://etrr.springeropen.com/articles/10.1007/s12544-017-0264-6 ; parameters restated at https://www.accu-rate.de/en/innovation/modell-und-theorie/fundamentaldiagramm/ . Scaling to your 1.2 m/s zombies:

```
capacity(portal_width_metres) ≈ 1.1 * W  zombies/second
```

A 2-tile door passes ≈2.2-2.4 zombies/s. **Invariant: sum of spawn rates over simultaneously-active windows ≤ capacity of the narrowest portal on the aggregate route to the player.** With 14 `WINDOWS`, the practical rule is to cap *active* windows to those in the player's current region plus adjacent, and to hold total spawn cadence under ~2/s when the horde must funnel through one door. Above that, zombies queue behind the choke and the round reads as empty followed by a wall.

**I3 — Loop connectivity ("training").** CoD Zombies' dominant player strategy is circle-training; community strategy guides describe the figure-8/circle method as requiring *"an open area with few or no obstacles"* and explicitly recommend sketching *"their lane, loop, and two emergency exits"* per area. Tier 4 (community strategy guide), https://steamcommunity.com/sharedfiles/filedetails/?id=666657246 ; loop framing corroborated at Tier 3, https://www.gamedeveloper.com/design/feedback-and-loop-analysis-in-call-of-duty-zombies . The programmatic form:

- Build the floor-tile adjacency graph for a given door-open state.
- Compute **articulation points** (Hopcroft-Tarjan, O(V+E), ~50 lines). A room whose only interior tiles hang off an articulation point has no loop.
- **Invariant: at least one biconnected component of ≥ 36 floor tiles must exist in each purchasable region**, i.e. a 6×6-equivalent open cycle the player can run.
- **Invariant: every room must retain ≥ 2 distinct doorway tiles** after prop stamping. This is the single most important post-stamp check — it is what prevents a crate turning a trainable room into a death box.

**I4 — Dead-end depth.** For every articulation point `a`, the component it isolates must have ≤ K tiles (suggest K = 6). Larger isolated pockets are player traps: the horde plugs the mouth and there is no counterplay.

**I5 — No diagonal-only connections.** BFS is 4-connected and `direction_at` refuses diagonal corner-cuts, so a diagonal-only gap is *unreachable by the field* but *visible to the LOS override* — agents will walk into the corner forever. After any prop stamp: assert no pair of floor tiles is 8-connected but not 4-connected across a stamped footprint.

**I6 — Stamp monotonicity.** After stamping props, re-run the BFS from a canonical origin and assert (a) no previously-reachable tile became unreachable, (b) no window's `ix,iy` interior tile became unreachable, (c) no wall-buy / perk / box spot became unreachable. Emerson's cost stamps *"record the original cost field values before replacing them"* precisely so a failing stamp can be rolled back — copy that.

All six checks together are ~200 lines of GDScript, run once at map build in a debug build, and are the cheapest insurance in this whole document.

### F10. Fast sweeping, if you ever need a weighted (non-binary) field

If you adopt a cost field (F4) you cannot use plain BFS any more; the naive answer is a priority queue, which is slow in GDScript. The right answer for a raster grid is the **fast sweeping method**: upwind discretisation plus Gauss-Seidel iterations in alternating sweep orders, **O(N)** total, and *"2^n Gauss-Seidel iterations is enough for the distance function in n dimensions"* — i.e. **4 raster passes over a 2D grid**, no queue, no allocation, pure `PackedFloat32Array` indexing. Zhao, *Mathematics of Computation* 74 (2005). Tier 1 (primary), https://www.ams.org/journals/mcom/2005-74-250/S0025-5718-04-01678-3/viewer/ and https://www.math.uci.edu/~zhao/homepage/research_files/FSM.pdf ; Emerson independently cites the same author's eikonal work for SupCom2's integrator (§23.6, [Ki Jeong 08]). **Corroboration count: 2.**

For 1428 cells, 4 sweeps = 5712 cell updates — comparable to your current BFS and far cheaper than a GDScript heap.

---

## Recommendations for this project

Ranked. Cost estimates are for a solo dev already fluent in this codebase, and are **effort**, not calendar.

### R1 — Do NOT migrate to NavigationRegion3D. Cost avoided: 2-4 days + permanent hitch risk. Confidence: high.

Justification against the constraints: (a) threads are off and cannot be turned on, so F1's synchronous rebuild is permanent, not a version bug you can wait out; (b) door-gated rooms guarantee unreachable targets, which is F2's 40× framerate cliff; (c) you'd trade a 79-line file you fully understand for an engine subsystem whose async design is compiled out from under you; (d) it buys nothing you need — you have no dynamic obstacles, no multiple agent sizes, no huge world.

The one legitimate reason to bake a navmesh anyway is **verticality with overlapping floors** (F7/F8). If that day comes, the hybrid is: navmesh for the *static* multi-level topology, flow field per floor, `NavigationLink3D`-equivalent explicit edges between them. Do not put `NavigationAgent3D` nodes on 24 zombies under any circumstance.

### R2 — Harden the existing flow field. Cost: ~1 day, ~120 net lines. Do this first.

In dependency order:

1. **`invalidate()`** — one line; called from the door-purchase path (`main.gd:474-476`). Already in your gap analysis as a bug; it is also a correctness precondition for everything below.
2. **Range-gate the LOS override** to `dist < 9` (the ancestor's value). Removes 24 full-length `intersect_ray` calls per tick and stops the whole horde converging on a point in the 16×14 Theatre. Already identified in the gap analysis; F4 confirms the *purpose* of an LOS override is near-goal flow quality, not long-range steering — Emerson runs it as an integration pass around the goal, not as a global override.
3. **Clamp the separation vector.** `push = push.limit_length(0.6)` before `dir += push * SEPARATION_FORCE`, or drop `SEPARATION_FORCE` to ~0.8 and normalise per-neighbour contributions by neighbour count. Justification in Bottom Line bullet 4. **Measure before and after** with a 24-zombie pack in a 2-tile corridor.
4. **Replace the binary `is_blocked` with an 8-bit cost field**, 255 = wall, 1 = free, plus **a blur pass adding +2..+4 cost within 1 tile of a wall** (Emerson §23.10). Switch the sweep from BFS to 4-pass fast sweeping (F10). This is the single highest-leverage change for making the horde stop scraping corners, and it is what makes prop stamping meaningful (a crate can be cost 200 rather than 255 → "zombies squeeze past but slowly").
5. **`stamp(rect, cost) -> Stamp` / `unstamp(Stamp)`** with saved originals (Emerson §23.9). This is the T3.4 prop API.
6. **Per-agent goal offset + speed jitter.** `target + Vector2.from_angle(randf()*TAU) * randf_range(0.0, 1.2)`, re-rolled every 3-5 s per zombie; speed × `randf_range(0.92, 1.08)` at spawn. ~10 lines, and it is 80% of the "horde not conga line" feel at 24 agents. Cheaper and more legible than congestion maps.
7. **Direction blending** across cell boundaries (Emerson §23.12): keep `_last_dir`, `dir = _last_dir.lerp(new_dir, 1.0 - exp(-10.0*dt))`. Kills the visible snap when a zombie crosses a tile line.

### R3 — Verticality: explicit link edges, not layers. Cost: ~0.5 day, ~30 lines. Do when T4.1 lands.

Generalise the BFS neighbour loop from "4 orthogonal tiles" to "4 orthogonal tiles ∪ `links[i]`", where `links` is a sparse `Dictionary[int, PackedInt32Array]` of extra directed edges, plus a parallel per-tile `height: PackedFloat32Array` so agents can be placed at the right Y. Author stairs as: a run of tiles with increasing height, linked orthogonally as normal; a drop-down as a **one-way** link (which the BFS handles naturally if you build the *reverse* graph — remember the field is solved *from* the player, so a one-way drop toward the player is a link the sweep must traverse backwards; get this direction right or zombies will refuse to use drops).

**This covers every WaW-era Zombies staircase**, because none of them have a second walkable surface directly above another in plan. It does not require a new data structure, does not invalidate `direction_at`, and costs one extra `Dictionary` lookup per BFS pop.

Explicit test for whether you need R4 instead: *does any (x, z) column in the map need two walkable surfaces at different heights?* If no — and per your own gap analysis, "a single-storey map still reads as Zombies (Shi No Numa's boardwalk, Nacht's ground floor, each floor of Five)" — R3 is sufficient and R4 is waste.

### R4 — Full layered 2.5D field. Cost: 3-5 days, ~250-350 lines + authoring + a debug visualiser you will not be able to work without. Only if R3's test fails.

Shape it on `rcHeightfieldLayer` (F7):

```gdscript
# Per column (x,z): a small array of spans, sorted by height.
# span := { h: float, dist: int, cons: PackedInt32Array }  # cons = cell indices, incl. vertical
# Flatten to parallel PackedFloat32Array/PackedInt32Array + a per-column (offset, count)
# index array. Never allocate per-span objects — this is a WASM single-thread budget.
```

The BFS becomes a sweep over span indices instead of tile indices; `direction_at(pos)` becomes "find the span whose `h` is nearest below `pos.y`, then descend". Budget one extra binary search per agent per tick (spans per column will be 1 or 2 almost everywhere). Memory: 1428 columns × ~1.3 spans × 12 bytes ≈ 22 KB — irrelevant.

Be warned that **no game-side reference write-up exists** (F7): you are porting a robotics/navmesh-baker data structure into a gameplay pathfinder. Budget debugging time accordingly, and build the visualiser first.

### R5 — Map validator. Cost: ~200 lines, ~1 day. Highest value-per-line in this document.

Implement I1-I6 from F9 as a `map_validator.gd` that runs in debug builds at map build time and pushes errors. Run it for **every reachable door-open state** (you have 4 doors → 16 states; enumerate them all, it's 16 × ~0.5 ms). This is what makes procedural or hand-edited layouts safe to touch, and it is the only thing here that prevents a shipped map with a trap room.

### R6 — Congestion maps: skip for now. Cost if adopted: ~0.5 day, ~40 lines, plus a re-solve cadence you do not currently have.

Pentheny's technique is explicitly aimed at *"tens or hundreds of thousands of agents"*. At 24 you get most of the benefit from R2.6 (goal offsets) for a tenth of the complexity, and congestion maps introduce the oscillation drawback he documents. Revisit only if you raise the concurrent cap well past 24, and then implement it as a coarse (e.g. 7×6 sector) density+velocity grid folded into the cost field before the sweep, with hysteresis.

---

## Coverage gaps

1. **No published Godot navigation benchmark under single-threaded WASM exists, anywhere I could reach.** The official optimisation page contains zero numbers. This is the largest gap and it is unfixable by research (see next section).
2. **I read Godot's navigation source at `master`, not at a `4.7-stable` tag.** I verified the file path `modules/navigation_3d/nav_map_3d.cpp` exists at the `4.5-stable`, `4.6-stable` and `4.7-stable` tags (HTTP 200 on all three) but did **not** diff the `THREADS_ENABLED` block against the 4.7 tag. The async-iteration mechanism landed in 4.4 and the `#ifdef THREADS_ENABLED` guard has been present since; I rate the risk of divergence as low but non-zero. **Verify locally** with one `curl` against the 4.7 tag before betting on it.
3. **I did not verify what `OS::get_processor_count()` returns in a non-threaded web build.** It bounds `path_query_slots_max`, but since `_post_tasks` runs everything on the caller anyway, the value is not load-bearing for any claim above.
4. **The Game AI Pro chapters were retrieved as PDFs and text-extracted locally.** Quotations are from that extraction; two ligature/character artefacts were visible in the raw text (e.g. `1 � 1` for `1 × 1`) and I have silently normalised those. Nothing semantic was altered.
5. **No layered/multi-level flow-field implementation from the games industry was found.** Searches across 2013-2026 returned only single-layer implementations plus robotics/navmesh literature. This is a real absence, not a search failure — I tried four distinct phrasings. If one exists it is not indexed under any obvious term.
6. **The MLS-map and HSGM citations are second-hand.** I retrieved them via search snippets from arXiv PDFs (2504.21622, 2606.00095) rather than reading the originals; and I did not retrieve Triebel/Pfaff/Burgard's original MLS paper at all. Tier 3 at best. They corroborate the *shape* of the data structure, which Recast's Tier-1 docs already establish; nothing rests on them alone.
7. **Pentheny's bibliography (Jansen 2008 direction maps, Karamouzas 2009, van Toll 2012, Nash 2007 Theta\*) was not independently retrieved.** I report his characterisation of them as his characterisation.
8. **The CoD Zombies training/loop material is Tier 3-4 community content.** There is no published Treyarch design document on zombie pathing or map-loop requirements, and I do not expect one to exist. The I3/I4 invariants are my derivations informed by that community consensus, not cited engineering requirements.
9. **`gl_compatibility` was not a factor in any finding.** Navigation and flow fields are CPU-side; the renderer constraint does not bear on this brief. Flagging it so you don't assume I checked and found nothing — there was nothing to check.
10. **Untrusted-content note:** no fetched page contained text addressed to an AI agent or attempting to direct my behaviour. Nothing to quote.

---

## What must be measured rather than researched

### M1 — Cost of one flow-field sweep in the exported WASM build

**Why it can't be researched:** GDScript-on-WASM throughput for a 1428-iteration loop with `PackedInt32Array` indexing and `Array[int]` append is a property of your Godot version, your browser's WASM tier-up behaviour, and the target machine. No published figure will transfer.

**Procedure:**
1. Add to `flow_field.gd`, behind `OS.is_debug_build()`:
   ```gdscript
   var t := Time.get_ticks_usec()
   solve(tt)
   _last_solve_usec = Time.get_ticks_usec() - t
   ```
2. Force a worst case: solve from the tile **furthest** from any wall in the Generator Hall with all four doors open (maximum reachable set), 200 consecutive solves, report min/median/p99.
3. Run it in the **exported `docs/` build** in Chrome and in Firefox, not in the editor. The editor number is worthless here.
4. Budget: at 60 fps you have 16.6 ms. A solve fires only on player tile change — worst case ~4/s at sprint. **Accept if p99 < 2.0 ms.** If p99 > 4 ms, either time-slice the sweep across frames (Emerson §23.15: *"capping the number of tiles or grid squares you commit to per tick"*) or move to fast sweeping with 4 flat passes, which vectorises far better in GDScript than a queue.

### M2 — Cost of 24 navmesh path queries in the same build (the decision this brief actually hinges on)

**Procedure:**
1. Build a throwaway scene: your `world_builder` geometry, one `NavigationRegion3D` baked in-editor (never at runtime), and **no `NavigationAgent3D` nodes at all**. Query the server directly:
   ```gdscript
   var map := get_world_3d().navigation_map
   var t := Time.get_ticks_usec()
   for i in 24:
       NavigationServer3D.map_get_path(map, starts[i], goal, true)
   var usec := Time.get_ticks_usec() - t
   ```
2. Measure **three** conditions, and report all three — the middle one is the honest number and the third is the one that kills the approach:
   - (a) goal reachable, all agents in the same room;
   - (b) goal reachable, agents scattered across all 8 rooms with doors open;
   - (c) **goal UNREACHABLE** — put the goal in the Generator Hall with its door shut. This is F2's cliff. Expect a large multiple.
3. Separately measure the door-open hitch: call `NavigationServer3D.map_force_update(map)` after toggling a `NavigationRegion3D.enabled`, timed, in the web build. Per F1 this is synchronous main-thread work with no async fallback.
4. **Decision rule:** even if (a) and (b) are cheap, condition (c) or the step-3 hitch exceeding ~8 ms is disqualifying on its own, because both occur in normal play. R1 stands unless *all four* numbers are comfortable.

### M3 — Separation force balance

**Procedure:** log `_separation(here).length()` for every zombie for 30 s of a round-10 pack. If the p90 exceeds ~0.4 (so `× 2.4` ≈ 1.0, equal to the unit flow vector), the separation term is competitive with steering and R2.3 is mandatory, not optional. Re-measure after clamping and confirm the horde still spreads across a 2-tile corridor rather than filing.

### M4 — Perceived horde feel (the only one that isn't a number)

Record 30 s of round 12 in the Theatre before and after R2.4 + R2.6, side by side at the same seed. The acceptance criterion is qualitative and that is fine: *does the horde arrive as a mass with a leading edge, or as a queue?* Nothing in the literature substitutes for watching this.

---

## Source index

| # | Source | Tier |
|---|---|---|
| 1 | godot `modules/navigation_3d/nav_map_3d.cpp` (master) | 1 |
| 2 | godot `core/object/worker_thread_pool.cpp` (master) | 1 |
| 3 | godot `main/main.cpp` (master) | 1 |
| 4 | https://github.com/godotengine/godot/pull/100497 (smix8) | 2 |
| 5 | https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_optimizing_performance.html | 1 |
| 6 | https://docs.godotengine.org/en/latest/classes/class_navigationregion3d.html | 1 |
| 7 | https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html | 1 |
| 8 | https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationmeshes.html | 1 |
| 9 | https://forum.godotengine.org/t/godot-terrible-performance-on-navigationagent3d/64567 (smix8) | 2 |
| 10 | https://github.com/godotengine/godot/issues/88237 | 2 |
| 11 | Emerson, Game AI Pro ch. 23 (PDF, read in full) | 1 |
| 12 | Pentheny, Game AI Pro 2 ch. 17 (PDF, read in full) | 1 |
| 13 | https://recastnav.com/structrcHeightfieldLayer.html | 1 |
| 14 | Zhao, *A fast sweeping method for Eikonal equations*, Math. Comp. 74 (2005) | 1 |
| 15 | https://www.jdxdev.com/blog/2020/05/03/flowfields/ | 3 |
| 16 | https://howtorts.github.io/2014/01/04/basic-flow-fields.html | 3 |
| 17 | https://www.redblobgames.com/pathfinding/tower-defense/ | 3 |
| 18 | https://etrr.springeropen.com/articles/10.1007/s12544-017-0264-6 (fundamental diagrams review) | 3 |
| 19 | https://deepwiki.com/recastnavigation/recastnavigation/2-recast:-navigation-mesh-generation | 3 |
| 20 | https://arxiv.org/pdf/2504.21622 , https://arxiv.org/pdf/2606.00095 (MLS / multi-floor, snippet-level) | 3 |
| 21 | https://www.gamedeveloper.com/design/feedback-and-loop-analysis-in-call-of-duty-zombies | 3 |
| 22 | https://steamcommunity.com/sharedfiles/filedetails/?id=666657246 (training strategy) | 4 |
