# Kriegsnacht — Prioritised Implementation Backlog

**Date:** 2026-07-27
**Inputs:** 233 verified findings from nine domain specialists, plus an 18-point completeness critique that reframes them.
**Status of this document:** this is the spine of the next phase. It supersedes the raw finding list as the working artefact. The raw list remains the evidence base; this is the plan.

---

## Executive summary

### What state the port is honestly in

Kriegsnacht is a **structurally complete, mechanically hollow** port. That phrasing is deliberate and it is the single most important thing to understand before allocating any effort.

The structure is genuinely there and it is better than the nine domain reports collectively implied. Rounds escalate on a canon-exact HP curve (150, +100/round through 9, then ×1.1 compounding — `game_state.gd:122-128`). The points economy is canon-accurate down to the melee-kill bonus (60 + 70 = 130, `game_state.gd:21-23`). Twelve weapons exist with distinct synthesised voices, distinct ballistics and a full twelve-entry Pack-a-Punch rename table. Four perks exist with real mechanical effects, power gating and HUD badges. The Mystery Box has a three-state machine with teddy relocation. Dog rounds have their own count, cadence, HP multiplier and HUD treatment. A flow field, a boid separation pass, a barricade board-count system, five power-ups, doors that re-derive reachability — all present and all working.

What is hollow is everything *between* the systems. The port systematically dropped the **feedback and presentation layer** that makes those systems legible, and in a startling number of cases it dropped a layer the browser ancestor already shipped. That is the second critical framing: **roughly forty of the 233 findings are not gaps, they are deletions.** `kriegsnacht.html` sits in the repo root with a working barricade board-tear loop, a working hold-F rebuild-for-10-points interaction, positional stereo audio with distance rolloff, per-zombie idle groans, a recoil spring, screen shake, muzzle flash, blood particles, hit flinch, a round-change stinger that sweeps the correct direction, an ambient tension drone that rises with the round, a pause menu with real buttons, and a `prefers-reduced-motion` path. The port has none of it. There is a working reference implementation ten metres from the source tree and nobody diffed against it.

And then there is the finding that none of the 233 contained, which the critic surfaced and which I have independently verified in source:

> **The game cannot be lost.** Player sprint is `SPEED 3.15 × SPRINT_MULT 1.55 = 4.88 m/s` (`player.gd:16-17`), infinite, free, with no stamina and no fire penalty. `Game.zombie_speed()` saturates at **3.45 m/s at round 16 and never changes again** (`game_state.gd:131-134`); per-spawn jitter tops out at ×1.14, so the fastest regular zombie in the game moves at 3.93 m/s. The player has a permanent 1.24× margin over the fastest possible zombie, forever. There is also **no player↔zombie collision at all**: the player is `collision_layer 2 / mask 1` (`player.gd:47-48`) and zombies are `collision_layer 4 / mask 1` (`zombie.gd:70-71`), so neither body's mask contains the other's layer and `move_and_slide()` never resolves a contact. You can walk through a wall of 24 zombies to leave any corner.

The only enemy that can catch a sprinting player is a hellhound (3.45 × 1.55 × 1.14 ≈ 6.1 m/s), which appears on exactly one round in five. Between dog rounds, from round 16 to round 400, the correct play is to hold Shift and never stop, and nothing in the game can punish it. Round 40 is roughly 233 zombies at ~18,200 HP each against a flat 6.5-second intermission — a ten-minute round of holding the trigger with no new pressure of any kind.

So the honest summary is: **a competent 3D skeleton of Zombies that neither communicates nor threatens.** It does not tell you when you hit something, where anything is, or what state it is in; and it cannot kill you.

### The three changes that would move it most

**1. Make the game losable.** Give zombies a player-collision mask, make sprint finite, and reshape the post-round-16 threat curve so it escalates in something other than HP. This is a handful of lines across three files plus a tuning pass, and it converts the entire project from a shooting gallery into a survival game. Everything else in this backlog is decoration on top of a game that currently has no fail state. *(TIER 0.1)*

**2. Restore the feedback loop: positional audio, zombie vocals, hit confirmation.** Every sound in the project is a non-positional `AudioStreamPlayer` on a single Master bus (`sfx.gd:19-24`) — there is not one `AudioStreamPlayer3D` in the codebase. Zombies emit no idle vocalisation. Bullets that land produce no pixel of change anywhere on screen. Between them, these three absences remove the player's ability to perceive the horde at all, which is the actual core skill of Zombies. All three are days of work, not weeks, and the ancestor's implementations can be ported nearly verbatim. *(Vertical Slice)*

**3. Restore the barricade loop.** Round 1 to 5 in Zombies *is* the barricade: zombies work the boards while you shoot them, you rebuild for 10 points a plank, and that tension is the entire early economy. The port removes a board as an invisible side-effect of spawning and teleports the zombie to a position *inside the room* (`main.gd:195` → `map_data.gd:197-202`), sometimes directly inside the player's melee reach where `_attack_timer` initialised at 0.0 (`zombie.gd:26`) lands 34 damage on the very next physics tick. `Game.PTS_REBUILD := 10` is declared and referenced nowhere. A "board" sound is baked in `sfx.gd:99` and played by nothing. The ancestor had the whole loop working. *(TIER 1.3)*

### How to read the rest

- **TIER 0** — things that must be settled before feature work. Decisions, architecture and instrumentation. Roughly two weeks.
- **VERTICAL SLICE** — the first milestone. Eight cheap items that close most of the *perceived* gap in about a working week.
- **TIER 1-4** — ordered by impact per unit of effort on "does this read as Call of Duty Zombies", respecting dependencies.
- **RESEARCH AGENDA** — eight self-contained briefs for a web-research phase.

Effort scale for a solo developer: **S** ≤ 1 day · **M** 1-3 days · **L** 1-2 weeks · **XL** > 2 weeks.

---

## TIER 0 — Settle before any feature work

Eight entries. Each is here because starting feature work without it either wastes that work or makes it unmeasurable. Nothing in this tier is a feature.

---

### T0.1 — Make the game losable: zombie collision, finite sprint, post-16 threat curve

**Why it matters:** The player is permanently uncatchable and can walk through the horde; there is currently no positional way for the game to kill you, and no specialist noticed.

**Source domains:** systems (`no-player-zombie-collision`, `move-no-sprint-stamina`), zombie-ai (`ai-physical-crowding`, `spawn-hound-cap`, `round-speed-classes`, `round-hp-cap-and-cost`), critic items 1 and 11.

**Merged findings:** `no-player-zombie-collision`, `ai-physical-crowding`, `move-no-sprint-stamina`, `round-speed-classes`, `round-hp-cap-and-cost`, `spawn-hound-cap`, `health-damage-and-jug-math`.

**The defect, precisely:**

| Quantity | Source | Value |
|---|---|---|
| Player walk | `player.gd:16` | 3.15 m/s |
| Player sprint | `player.gd:16-17` | **4.88 m/s**, infinite, no fire penalty |
| Zombie speed cap | `game_state.gd:134` | **3.45 m/s** from round 16 onward, forever |
| Max zombie jitter | `zombie.gd:65` | ×1.14 → 3.93 m/s |
| Hound speed | `zombie.gd:53` | ×1.55 → up to 6.1 m/s (the only real threat) |
| Player↔zombie collision | `player.gd:47-48`, `zombie.gd:70-71` | **none** — masks do not intersect |
| Damage cap from any number of attackers | `player.gd:301-303` | one global 0.35 s cooldown → 24 zombies deal exactly one zombie's DPS |

**Godot approach:**
1. `zombie.gd:71` → `collision_mask = 1 | 2` and give the player `collision_mask = 1 | 4`. Both are `CharacterBody3D`, so mutually-colliding kinematic bodies need the existing boid separation (`zombie.gd:163-173`) retained as the symmetric-standoff tie-breaker; shrink `SEPARATION_RADIUS` to ~0.55 to match the 0.26 m capsule diameter and raise `SEPARATION_FORCE`. Add a small `safe_margin`.
2. Replace the global `_hurt_cooldown` with a per-attacker `Dictionary[instance_id → timestamp]` on the player so a five-deep pile actually kills you. Set `melee_damage = 50.0` (`zombie.gd:19`) so the canon 2-hits-to-down / 5-with-Juggernog counts hold against `BASE_HP 100` / `JUG_HP 250`.
3. `_stamina: float` drained while sprinting with a non-zero input vector, refilled after a short delay; ~4 s of sprint, ~4 s recovery, matching CoD. Stamin-Up later multiplies both. Gate `_update_fire` behind a `_sprint_out` timer of ~0.25 s.
4. Reshape the curve past round 16. HP inflation alone is not difficulty. Introduce discrete gait classes (`GAIT = {walk 1.05, run 2.20, sprint 3.45}`) rolled per spawn from a round-weighted table, so the horde has a legible speed spread and a distinct "everything sprints now" round; cap `zombie_hp` at 1,000,000 as canon does; make `MAX_ALIVE` a function returning 8 on dog rounds (they currently share the cap of 24 while spawning *faster*, `game_state.gd:148`).
5. Cache the HP curve into a `PackedFloat32Array` at `Game.reset()` so it is a table lookup and, critically, **inspectable and tunable from one place** — which is what the balance sim in T0.5 will read.

**Effort:** M (the code) + M (the tuning pass, which needs T0.5 to be honest)
**Depends on:** T0.5 for the tuning half. The collision and sprint half can land immediately.

---

### T0.2 — Write down what this is: design pillars, roguelike-vs-faithful, solo-vs-co-op, desktop-vs-mobile

**Why it matters:** Four unmade decisions each silently delete or resurrect large fractions of this backlog, and every specialist optimised for an unexamined goal.

**Source domains:** systems (`meta-roguelike-layer-absent`), ui (`ui-coop-absent`), critic items 2, 3, 6, 7, 18.

**The four questions, and what each answer costs:**

**(a) Faithful demake, or roguelike?** The project's own title picks a fight with the brief the analysis was written against. CoD Zombies is a *memorisation* game — the skill ceiling of Kino is knowing where the windows are, which corner the box favours, and the shape of your train. A roguelike is procedural variance and run-scoped build decisions. These are not compatible. If the map generates, then hand-authored chalk plaques on specific walls, a hand-built PaP room, authored perk placement and authored trap corridors all become dead work. Note the ancestor's pause menu already read "**Abandon run**" — somebody once had an intent here and never wrote it down.

**Recommendation:** commit to *faithful-first, roguelike-second* — a fixed, hand-authored map with a **seeded run layer** (which wall-buy is where, which box spot starts hot, door costs, an intermission draft). That preserves route memorisation while making runs distinguishable, and it keeps ~90% of this backlog live. It also makes T0.3 (seeded RNG) immediately valuable rather than speculative.

**(b) Solo, or co-op?** "Zero co-op UI surface" is the *only* line in 233 findings that touches multiplayer, and it is ranked polish. Base Zombies is a four-player co-op game in which solo is the variant. Revive-a-teammate is the entire reason the downed state exists; Quick Revive's solo self-revive is a concession. `Game.zombie_count()` has no player-count term, the flow field has one target, `main.gd` has no authority model, and `Game.points` is a single global int. Deciding this after implementing 200 systems is catastrophic.

**Recommendation:** commit to **explicitly single-player**, and say so on the page — but refactor the HUD to bind to a `PlayerState` object rather than reading `Game` globals directly (T0.4 does this anyway), so the shape stays N-player even if N is always 1. Cost: near zero. Cost of not deciding: every system built between now and the decision.

**(c) Desktop-only, or mobile too?** `export_presets.cfg` sets `vram_texture_compression/for_desktop=true` and `for_mobile=false` on a **Web** preset — desktop-only S3TC/BPTC, which mobile WebGL2 does not provide. There are zero touch inputs in the map; every event is `InputEventKey` or `InputEventMouseButton`. The design requires mouselook plus seven keys. The ancestor had a `@media (max-width:620px)` breakpoint. A meaningful share of traffic to a shared GitHub Pages link is mobile, and it is very likely broken.

**Recommendation:** commit to **desktop-only**, fix the texture compression flags so the build is at least correct for its target, and put a one-line "desktop, mouse + keyboard" notice on the loading shell. Revisit only if analytics justify it.

**(d) What is the deliverable for?** "Faithful demake of Kino", "roguelike inspired by Zombies", "portfolio piece demonstrating Godot 3D", and "a game a stranger enjoys for ten minutes in a browser tab" imply four different subsets of these findings.

**Deliverable:** a `docs/DESIGN-PILLARS.md` of three to four sentences plus the four decisions above with their rationale. Three or four pillars written down will delete more items from this backlog than any further analysis will add to it.

**Effort:** S (it is a day of thinking and an hour of writing)
**Depends on:** nothing. Do it first.

---

### T0.3 — Seeded RNG and run-state architecture

**Why it matters:** There are three uncorrelated entropy sources and no seed plumbing; a shareable or replayable seed cannot be retrofitted after 200 changes each add their own `randf()` call.

**Source domains:** systems (`meta-roguelike-layer-absent`, `meta-no-persistence`), critic item 3.

**The defect, precisely (all verified in source):**
- `main.gd:42` calls `_rng.randomize()` on a private `RandomNumberGenerator`.
- `game_state.gd:70` calls `rng.randomize()` on a *second*, independent generator.
- `player.gd:216-217` (bullet spread) and `zombie.gd:65, 96` (speed jitter, animation rate) use the **global** `randf_range()`, a third source entirely.

**Godot approach:** collapse to one authority. A `Rng` autoload (or a `Game.rng` promoted to the single source) seeded from a run seed, with named sub-streams derived deterministically — `rng.stream("spawn")`, `rng.stream("box")`, `rng.stream("cosmetic")` — so that adding a cosmetic `randf()` cannot desync the spawn sequence. Replace all three global `randf_range` call sites. Store the seed on `Game`, surface it on the game-over screen, and accept `--seed=N` on the command line (which the debug layer in T0.5 will use constantly). Split `Game` into **run state** (seed, round, points, kills, perks — reset per run) and **profile state** (best round, settings, unlocks — persisted), because they have different lifetimes and conflating them is why `Game.reset()` currently wipes things that should survive.

This is cheap now and impossible later. Even under a fully faithful design (T0.2a), a deterministic seed is the prerequisite for the balance sim in T0.5 and for reproducing any bug report.

**Effort:** S
**Depends on:** T0.2 (the answer shapes how much run-state variance there is, but the plumbing is identical either way — do not block on it).

---

### T0.4 — Break up the `main.gd` god object

**Why it matters:** 586 lines and 30 functions own rounds, spawning, power-ups, interactables, props, the box, perk lighting and the environment; roughly a third of this backlog edits this one file, and they will collide.

**Source domains:** cross-cutting; implied by every domain's `godot_approach`.

**What is actually in there (verified):** `_setup_environment`, `_process`, `_begin_round`, `_end_round`, `_spawn_one`, `_on_zombie_died`, `_on_player_died`, `_spawn_powerup`, `_update_powerups`, `_collect`, `_build_interactables`, `_prop_sprite`, `_spawn_perk_marker`, `_light_perks`, `_place_box`, `_set_box_art`, `_update_interact`, `_prompt_for`, `_owns`, `_do_interact`, `_use_box`, `_update_box`, `_relocate_box`, `restart`.

**Godot approach:** extract along the seams that already exist in the function names. Minimum viable split:
- `RoundDirector` — `_begin_round`, `_end_round`, `_spawn_one`, `_to_spawn`, `_alive`, the spawn clock. This is where T1 spawn-director work lands.
- `PowerupManager` — `_spawn_powerup`, `_update_powerups`, `_collect`, `POWER_POOL`.
- `InteractionSystem` — `_build_interactables`, `_update_interact`, `_prompt_for`, `_do_interact`, `_owns`. Change the flat `Array` of dictionaries into typed `Interactable` nodes so that owned/unavailable ones can deregister instead of winning nearest-object selection and silently eating the interact key (`level-dead-interactables-swallow-input`).
- `MysteryBox` — `_use_box`, `_update_box`, `_relocate_box`, `_place_box`, `_set_box_art`, the whole `_box_*` state block.
- `Atmosphere` — `_setup_environment`, the room light array, `_light_perks`. This is where the power-on lighting event lands.
- `main.gd` retains wiring and `_process` dispatch only.

**Also fix while in here:** pause is implemented as an early-return in each node (`main.gd:118`, `player.gd:127`, `zombie.gd:107`) rather than `get_tree().paused`. That pattern already leaks (HUD toast/flash timers keep decaying while paused, `hud.gd:180-186`) and it **will not survive** the tweens, particles and AnimationPlayers this backlog adds. Switch to real `get_tree().paused` with `PROCESS_MODE_WHEN_PAUSED` on the HUD subtree.

**Effort:** M
**Depends on:** nothing. Do it before Tier 1, not during.

---

### T0.5 — Iteration harness: debug console + headless balance sim

**Why it matters:** Every item in this backlog is a feel change needing dozens of iterations, and the entire dev-tooling surface is a `_debug` flag that prints round state every two seconds.

**Source domains:** cross-cutting; critic items 9 and 10.

**Current state:** `main.gd:37, 74, 149-152` — a `_debug` bool set by `--autostart` that prints round/alive/points every 2 s. `perf_probe.gd` exists (208 lines) but no result from it is recorded anywhere in the repo. There are no unit tests, no GUT, no golden-value tests on the curves, and no telemetry. To evaluate a change to round-30 pacing you must play to round 30; the documented soak run (`--quit-after 2400`) gets nowhere near it.

**Godot approach, part 1 — in-game debug layer.** A `Debug` autoload behind a build flag, bound to keys or a small console `LineEdit`:
- `round N` — warp directly to round N (calls `Game.round_no = N` then `_begin_round`).
- `give <weapon> [pap]`, `points N`, `perk <key>`, `power`, `maxammo`, `god`, `noclip`.
- `timescale N` — `Engine.time_scale`, the single highest-value entry on this list for pacing work.
- `freecam`, `spawn <kind> N`, `killall`.
- A live tuning panel over the constants in `game_state.gd` and `weapons.gd` — sliders writing straight into the dictionaries, so a recoil or speed curve can be dialled in one session instead of twenty rebuilds.
- An on-screen readout: alive count, spawn interval, current zombie speed vs player sprint speed, seed.

**Godot approach, part 2 — headless balance sim.** A scene run with `--headless` that plays N rounds against a scripted damage model (fixed DPS with a headshot ratio, fixed reload downtime, a kiting-vs-holding behaviour switch) and reports per round: wall-clock length, zombies killed, points earned, points/minute, damage taken, and a pass/fail on "could a player be caught". Emit CSV. This is roughly a day of work and it makes the entire balance half of the backlog falsifiable — right now, if someone changes zombie speed to add gait classes, **nothing in this repo can answer whether round 12 got harder or easier.** It is also the only way to see the round-16 flatline as a graph rather than as an argument.

Add golden-value tests on the curves (`zombie_hp(1) == 150`, `zombie_hp(9) == 950`, `zombie_hp(10) == 1045`) so the canon curve cannot be broken silently by a refactor.

**Effort:** M
**Depends on:** T0.3 (the sim needs a seed to be reproducible).

---

### T0.6 — Diff against the ancestor: `kriegsnacht.html` feature inventory

**Why it matters:** ~40 of the 233 findings are deletions with a working, tuned reference implementation sitting in the repo root; re-deriving them from scratch is the single largest avoidable waste in this plan.

**Source domains:** all nine; critic item 1.

**What is already known to be in the ancestor and absent from the port** (each with an html line reference from the verification pass, so this is a starting inventory, not a hypothesis):

| Ancestor feature | html reference | Port status |
|---|---|---|
| Barricade board-tear loop, per-plank timer, splinter particles | 2212, 2268-2282 | deleted |
| Hold-F rebuild, 0.34 s/plank, +10 points, `repair()` sound | 2978-2989 | deleted (`PTS_REBUILD` is dead code) |
| Distance-weighted spawn window selection | 2196-2201 | replaced with a uniform pick |
| Per-zombie idle groans, 3.5-9 s re-roll, distance-culled, pitched by palette, panned | 2214, 2260-2266 | deleted |
| Hound `bark()` | 498-500 | deleted |
| Positional gain + pan helpers | 452-456, 483-503 | deleted |
| Hit flinch (`z.hitT = 0.09`) + blood particles on every hit | 2223, 2227, 2235 | deleted |
| Recoil spring (`viewKickV += -viewKick*46*dt - viewKickV*11*dt`) | 2960-2961 | deleted (`_recoil` is dead code) |
| Screen shake (`G.shake`) | 2354, 2526 | deleted |
| View bob (`bobPhase` at 9.4 / 13 / 2.2 rad/s) + gun sway | 2952-2956, 3116-3117 | deleted |
| Muzzle flash, 8-point star, per-weapon colour + muzzle anchor table | 2020, 3141-3168 | deleted |
| Bullet-hole decal array | 1638 | deleted |
| Round-change stinger: two detuned saws 320→52 Hz + noise swell + delayed sub | 519-526 | replaced with one rising sine |
| Rising ambient tension drone (`setTension(round/16)`) | 541-554, 2868 | deleted |
| Round title card with per-round subtitle | 2867, 3093-3100 | deleted |
| `powerOn()` — 40→120 Hz saw, noise swell, three harmonic tones | 513-518 | replaced with the generic buy blip |
| Box jingle `boxOpen` (12-note melody), `boxTake`, `teddy` (descending motif) | 527-534 | deleted |
| Down / revive stingers + global `setMuffled()` biquad | 463-467, 536-539 | deleted |
| Weapon gain scaled by `body` (Thundergun genuinely louder than M1911) | 470-473 | deleted (flat -4 dB) |
| Knife swing arc + separate `knife()` sound | 1204-1208, 3128-3133, 481 | deleted |
| PaP tinted viewmodel variant | 3432 | deleted |
| `GUNART` — all 12 weapons + knife as flat 2D part lists | 1151-1207 | unused (but this is the seed for procedural viewmodels) |
| `buildSprites` / `outlineSprite` sprite generators | ~950-1440 | unused (this is the entire art pipeline) |
| Three-option render-quality selector, pause menu with focusable buttons, keybind table, onboarding hint | 216-340 | deleted |
| `prefers-reduced-motion` honoured (scanline + durations disabled) | 223-226, 394 | deleted |
| Dry-fire two-tone square, dog spawn embers, per-round late tweak `round>=14 && type==='z' ? 1.06` | 478, 2216, 2334 | deleted |

**Deliverable:** `docs/analysis/ancestor-diff.md` — a table of every ancestor behaviour, its html line range, its port status (present / degraded / deleted), and a port-cost estimate. Several of these are literal transliterations of ten to thirty lines of JS. This document reprices roughly forty backlog items downward, and it should be produced **before** Tier 1 scheduling is finalised.

**Effort:** S (half a day of reading, with html line references already in hand)
**Depends on:** nothing.

---

### T0.7 — Pin the renderer and take a real web performance baseline

**Why it matters:** The editor runs Forward+ and the shipped build silently runs Compatibility, so every VFX in this backlog is being authored against a renderer no player sees — and the only performance number anyone has was measured natively on an RTX 5090.

**Source domains:** fx (`render-web-renderer-tier`, `perf-no-lod-culling-or-instancing`), zombie-visuals, critic item 14.

**The defect:** `project.godot:20` declares `config/features=PackedStringArray("4.7", "Forward Plus")`, and the `[rendering]` block (lines 112-116) contains only `default_texture_filter`, `directional_shadow/soft_shadow_filter_quality` (tuning a filter for a `DirectionalLight3D` that does not exist anywhere in the project) and `default_clear_color`. There is **no** `rendering/renderer/rendering_method` key and no `.web` override, so Godot uses forward_plus in the editor and the gl_compatibility default on web. `variant/thread_support=false`, so the shipping target is a single-threaded WebGL2 build on unknown consumer hardware.

**The consequence:** `Decal`, `FogVolume`/volumetric fog, SSAO/SSIL and SSR are Forward+ only and will silently no-op. Several `godot_approach` sections in the raw findings propose exactly these. Meanwhile the README's headline 6.06 ms / 47 MB / never-a-missed-frame number describes a different renderer on different hardware, and `perf_probe.gd` was written to get a real number but no result is recorded in the repo.

**Godot approach:**
1. Set `rendering/renderer/rendering_method="gl_compatibility"` (or at minimum the explicit `.web` override) and switch the editor to Compatibility while authoring, so the viewport is the shipping target.
2. Run `perf_probe.gd` in the *exported web build* on median hardware and commit the number to the repo. Every VFX, particle, shadow and mesh proposal in Tiers 1-4 draws down a budget that currently does not exist as a measurement.
3. Add `rendering/anti_aliasing/quality/msaa_3d` or `screen_space_aa` — the entire game is alpha-scissor billboards at threshold 0.35 (`zombie.gd:88-89`, `main.gd:369-370`) with `mipmaps/generate=false` in every `.png.import`, so sprite edges and distant 64 px wall textures crawl under any camera motion. This is a settings change that visibly upgrades the image.
4. Write the resulting constraint list into `docs/RENDERER-CONSTRAINTS.md`: no `Decal`, no `FogVolume`, no SSAO, verify `GPUParticles3D`, prefer offset quads and `MultiMeshInstance3D` for everything decal-shaped.

**Effort:** S (the change) + S (the measurement)
**Depends on:** nothing. Blocks correct scheduling of every VFX item.

---

### T0.8 — Decide the enemy representation: billboard or rigged mesh

**Why it matters:** One unmade call gates roughly thirty findings, is the most expensive decision in the project, and every specialist wrote around it rather than making it.

**Source domains:** zombie-visuals (the whole domain), fx, gunplay, zombie-ai; critic item 4.

**What is downstream of this single decision:** dismemberment, walker→crawler conversion by leg-shot, glowing eyes, back-of-head silhouettes, ragdoll with directional impulse, per-limb hitboxes, gait variants, headgear knock-off and skull pop, contact shadows, LOD, body/clothing variants, directional facing, upper-body flinch layered over locomotion, barrier-tear and vault animations, and the collider-vs-sprite-width hit registration problem. That is XL-scale work in every direction, and its value is entirely contingent on the answer.

**The case for staying on billboards:** it is the established art style, all 17 sprite strips exist, the Doom/Wolf3D lineage reads perfectly well, and the README's framing is a deliberate 1:1 port of a 2D canvas demo into real 3D. Critically, an **8-direction billboard atlas** (effort M) delivers most of the CoD read — you can see a zombie's back, you can tell it has aggroed someone else — for a small fraction of a skeletal rebuild. And the honest diagnosis from the verification pass is that what breaks the read today is *facing plus feedback*, not the absence of bones.

**The case for rigged meshes:** dismemberment and the leg-shot→crawler conversion are genuinely central to Zombies and are essentially unreachable on billboards without a large volume of new art that cannot currently be produced (see T1.0 / the asset pipeline problem). Ragdoll, layered upper-body animation and per-limb hitboxes all come nearly free once a skeleton exists.

**Recommendation:** **stay on billboards, add 8-direction facing, and buy the two highest-value gore beats with sprite tricks** — swap `sprite_frames` to the existing crawler set mid-life for the walker→crawler conversion (all three crawler palettes already exist, so this needs zero new art), and use an unshaded overlay for glowing eyes (the eye pixels are already authored — I confirmed frame 0 of `zombie0_walk.png` carries a symmetric pale-cream pair at (20,14) and (26,14), colour (246,230,168), the two brightest pixels in the sprite; they are dark only because `shaded = true` at `zombie.gd:87` and no glow is configured on the Environment). Defer skeletal meshes indefinitely, and revisit only if the asset pipeline question (Research Theme 7) returns a viable free source *and* the web perf baseline from T0.7 shows headroom for 24 skinned humanoids on a single-threaded WebGL2 build.

**Deliverable:** one paragraph in `docs/DESIGN-PILLARS.md`, and the corresponding re-scoping of the ~30 downstream findings from XL to M.

**Effort:** S (a decision, plus the re-scope)
**Depends on:** T0.7 (the perf budget informs it), Research Theme 7 (asset sourcing).

---

## ⭐ VERTICAL SLICE — Milestone 1: "It responds to me"

**Goal:** in one working week, close most of the *perceived* gap between this port and CoD Zombies without touching a single system's architecture. Every item is S, every item is independent of the others, and every item has a working reference implementation in `kriegsnacht.html`.

**The thesis:** the port's systems are fine; the player just cannot perceive them. These eight items give the player back sight and hearing.

| # | Item | Effort | What it buys |
|---|---|---|---|
| **VS-1** | **Positional audio foundation** — swap the 12-voice `AudioStreamPlayer` pool for `AudioStreamPlayer3D` where it matters, add `Sfx.play_at(id, Vector3)`, add a bus layout | S | The single biggest change in the list. Every zombie, gunshot, machine and barricade becomes locatable. |
| **VS-2** | **Zombie idle groans** — per-zombie `AudioStreamPlayer3D`, 3.5-9 s randomised timer, pitched per palette, distance-culled at 20 m, voice-capped at ~10 | S | Restores the primary threat-awareness channel. Port `groan()` from html:494-500 nearly verbatim. |
| **VS-3** | **Hit confirmation** — blood puff at `hit.position`, white `modulate` flash for 60 ms, 0.12 s flinch, HUD hitmarker (bone / sodium headshot / blood kill) | S | Closes the shoot→see→hit loop. Currently firing a weapon produces literally zero pixels of change anywhere. |
| **VS-4** | **Killing-blow audio reorder** — move `Sfx.play("hit"/"headshot")` above the `if hp <= 0` early-return at `zombie.gd:203-207` | S (one line) | Today the *killing* shot is the one event with no impact sound. A headshot kill is silent apart from the death rattle. |
| **VS-5** | **Muzzle flash + muzzle light** — pooled additive `Sprite3D` for 2 frames with random roll + a 0.05 s `OmniLight3D` at energy ~4, per-weapon colour from the ancestor's table | S | Transforms the dark-room read and makes every shot feel like an event. Ray Gun green, Thundergun blue. |
| **VS-6** | **Glowing eyes** — unshaded additive overlay `Sprite3D` at head height, `modulate` above 1.0, plus `env.glow_enabled` with `glow_hdr_threshold ≈ 0.85` | S | The most recognisable visual signature in the franchise. The eye pixels already exist in the art. |
| **VS-7** | **Barricade rebuild** — a `"window"` interactable per barricade, hold-to-repair at ~0.55 s/plank, +10 points, plays the already-baked-but-never-played `board` sound | S | Restores the round 1-3 economy and a core verb. `PTS_REBUILD` and the sound are both already in the repo, both dead. |
| **VS-8** | **Recoil spring + view bob + screen shake** — port the ancestor's `viewKickV += -viewKick*46*dt - viewKickV*11*dt`, `bobPhase` at 9.4/13/2.2 rad/s, and `G.shake` | S | Fixes an actual aim bug (recoil currently never recentres — a 100-round RPK mag walks the camera up ~30° permanently) and makes the camera feel embodied. |

**Sequencing note:** VS-1 is a hard prerequisite for VS-2 and improves VS-3/VS-5. Do it Monday. VS-4 is a one-line change; do it while waiting for anything to compile. VS-7 needs a hold-to-interact accumulator, which is the first half of the interaction refactor in T0.4 — land it there.

**Definition of done:** a stranger opens the page, shoots a zombie, and can tell they hit it; hears a groan behind them and turns around; sees a pair of eyes in an unlit corner; rebuilds a barricade for points. None of that is true today.

**Estimated total: 5-8 working days.**

---

## TIER 1 — Highest impact per unit of effort

These are the changes that most move "does this read as Call of Duty Zombies", at S-to-M effort.

---

### T1.1 — Spawn director: locality, per-window pacing, and stop spawning inside the player

**Why it matters:** Spawns are picked uniformly from every reachable window map-wide, so late-round pressure *drops* as you open the map — exactly backwards — and a zombie can materialise inside your melee reach and hit you for 34 on the next physics tick.

**Source domains:** zombie-ai (`spawn-zone-locality`, `spawn-per-barrier-pacing`, `missed-spawn-inside-melee-range`, `spawn-hound-cap`, `ai-stuck-recovery`, `missed-stale-flowfield-on-door`, `missed-los-ungated`), zombie-visuals (`spawn-lands-inside-the-room-past-the-barricade`), level (`level-spawn-zoning`).

**Merged findings:** eight.

**Godot approach:**
- **Locality (6 lines, the highest value in the group):** `flow.dist[MapData.ix(w.ix, w.iy)]` is *already* the exact BFS tile-distance from the player to every window. Weight the random pick by `1.0 / (1.0 + dist)` and reject windows beyond ~18 tiles. This is precisely what the ancestor did (`wt = (1/(1+d*0.14)) * rnd(1.6,0.4)`, best-of picked, html:2196-2201) and the port replaced it with `live[_rng.randi() % live.size()]`.
- **Minimum spawn distance:** reject any window within ~4 m of the player, and randomise `_attack_timer` on state entry (`melee_cadence * randf_range(0.5, 1.0)`) so the first swipe is never a zero-frame hit. The ancestor had `atkT:rnd(0.6)`.
- **Per-window cooldown:** a `{cooldown, working}` dict per window; pick only from `cooldown <= 0 and working < 2`. Note this becomes emergent once the barricade teardown loop lands (T1.3) — teardown time *is* the cooldown — so implement it as the cheap version now and let T1.3 subsume it.
- **`Game.max_alive()`** returning 8 on dog rounds instead of the flat 24.
- **Stale flow field:** `FlowField.update` early-returns when the player's tile is unchanged (`flow_field.gd:22-27`) and the door-purchase path never invalidates it, so a player who buys a door and stands still leaves every zombie steering on a graph where that door is still a wall. One line: expose `flow.invalidate()` and call it from `main.gd:474-476`.
- **LOS range gate:** `zombie.gd:143-151` runs `_has_los` unconditionally at any distance, so in the 16×14 Theatre the flow field is effectively never consulted and the horde converges on a point instead of spreading. The ancestor gated it at `dist < 9`. This also removes 24 full-length `intersect_ray` calls per physics tick — which the verification pass identified as the actual per-tick cost, not the boid loop.

**Effort:** M
**Depends on:** T0.4 (`RoundDirector` extraction)

---

### T1.2 — Weapon state machine: mutual exclusion, input latching, tick-quantised fire rate

**Why it matters:** Fire, reload, knife and swap are four independent floats with no arbitration — you can knife and full-auto in the same frame — and separately, several outright input bugs make the guns feel broken rather than tuned.

**Source domains:** gunplay (`gun-weapon-state-machine`, `gun-trigger-input-dropped`, `gun-firerate-quantised`, `gun-reload-monolithic`), weapon-models (`md-no-weapon-state-machine`, `vm-draw-holster`, `vm-empty-boltlock`), systems (`weapon-swap-instant-and-reload-persists`, `shells-flag-dead-no-shell-reload`).

**Merged findings:** nine.

**The concrete bugs, all verified:**
- `_update_fire` clears `_fire_queued` unconditionally at `player.gd:179` **before** the cooldown check at `:182-183`. The M1911 at 420 rpm has a 9-tick gap, so **roughly 8 of 9 semi-auto clicks are silently discarded.** The gun feels broken, not rate-limited. This is probably the single most player-visible bug in the project.
- The reload branch returns at `:174` **without** clearing the latch, so a click during reload is banked and auto-fires the instant the reload completes.
- `_unhandled_input` returns early on non-PLAY state at `:100-101`, before the `is_action_released("fire")` handler at `:108-109`, so releasing the mouse while paused leaves `_fire_held` true and an automatic weapon resumes firing on unpause.
- `_update_fire` runs in `_physics_process` and `maxf(0.0, ...)` at `:175` discards the sub-tick remainder while `:195` re-arms the full interval, so **no automatic weapon fires at its stated RPM**: MP40 880→720 (−18%), PM63 1000→900, AK-74u 710→600 (−15%), RPK 700→600 (−14%), M16 740→720. Note this *inverts* the RPK/M16 cadence relationship, which is a design regression, not just a number.
- `_update_fire` only ticks `current_gun()` (`:169-171`), so a gun stowed mid-reload **freezes** its countdown and resumes on swap-back — you can start an RPK's 4.6 s reload, swap away, fight, and swap back to finish it.
- `_knife_cooldown` is set at `:263` and decayed at `:131` but never consulted by `_update_fire`.

**Godot approach:** one `enum WeaponState {READY, FIRING, RELOADING, RAISING, LOWERING, MELEE, SPRINT_OUT}` with a single `_state_timer`, gating `_update_fire` on `READY`. Swap becomes `LOWERING(t) → set slot → RAISING(t)` with per-weapon times; entering `LOWERING` zeroes `gun.reloading` to cancel. Carry the fire-rate remainder (`gun.next_shot -= dt` allowing negative, `+= interval` on fire, clamped to one interval of debt) or move `_update_fire` to `_process` — it is a hitscan game with no projectile dependency and display rate is both smoother and higher. Clear the fire latch in the correct order. Add `fire_mode` (auto/semi/burst) so the M16 becomes the 3-round burst it is in every Treyarch title, and `reload_type` (mag/shell) so the `shells: true` flag on the Olympia and Stakeout — declared at `weapons.gd:16, 21` and read by nothing — finally does something and those reloads become cancellable.

**Effort:** M
**Depends on:** nothing (do it before the viewmodel, so the viewmodel binds to a real state machine).

---

### T1.3 — The barricade loop: teardown, vault, rebuild, shoot-through, exterior

**Why it matters:** Rounds 1-5 in Zombies *are* the barricade, and the port elides the entire verb — including a working ancestor implementation and an already-baked sound that nothing plays.

**Source domains:** zombie-ai (`spawn-barrier-teardown`, `spawn-vault-window`, `missed-barricade-rebuild`), zombie-visuals (`anim-no-barrier-teardown-vault`), level (`level-window-barricade-geometry`, `level-player-rebuild-barricades`, `level-barrier-vault-and-teardown`, `level-nothing-exists-outside-the-barricades`), systems (`econ-no-barricade-repair`), audio (`audio-barricade-boards`), ui (`ui-interaction-prompt` hold half).

**Merged findings:** eleven — the largest cluster in the backlog and the one with the clearest ancestor precedent.

**Godot approach, in dependency order:**
1. **Carve exterior pockets.** `MapData.build()` fills the grid solid (`:128`) and carves only ROOMS and OPENINGS, so the tile behind every barricade is solid rock. Nothing can stand outside, and making the barricade shoot-through would reveal the inside of a wall. Carve a 1-tile pocket behind each of the 14 windows, deliberately excluded from `compute_reach()` so no window ever spawns there.
2. **Rebuild the window tile as a frame.** Emit four border quads around a ~1.2 m aperture instead of one full quad, and drop the collider to the border only, so a stripped barricade is genuinely shoot-through and see-through. Build the 6 planks as separate thin `BoxMesh` instances at staggered angles with their own small colliders; `set_window_boards()` becomes `plank[i].visible = false` + `collider.disabled = true` + a one-shot splinter particle burst, instead of the current whole-tile `material_override` swap between seven pre-baked textures.
3. **`State.TEARING_BOARDS`.** The enum value `State.ENTERING` is declared at `zombie.gd:9` and assigned by nothing. Spawn zombies at the *exterior* pocket, steer them to the barrier with the flow field temporarily solved toward the window tile, then run a per-plank accumulator at `randf_range(0.9, 1.4)` s calling back into the round director. Play the **already-baked, never-played** `board` sound (`sfx.gd:99`) positionally at the window. The zombie is shootable and does not aggro while occupied — that is the entire tempo of rounds 1-5.
4. **Vault.** On zero boards, drive `global_position` along a short `Curve3D` through the aperture with a `Tween`, `collision_layer = 0` for the ~1.2 s traversal but the hitbox live so it stays shootable. Fake the clamber by tweening `_sprite.position.y` and a ~20° `rotation.z` lean.
5. **Player rebuild.** A `"window"` interactable per barricade at `map.window_stand_pos(wi)`, prompt suppressed at 6 boards, hold-to-repair on a `~0.55 s` accumulator (the ancestor used 0.34 s), `+Game.PTS_REBUILD` per plank, radial progress arc drawn on the crosshair `Control`. Gate it so you cannot rebuild while a zombie occupies the window. Then reduce or remove the free 50%-per-window between-round regrowth (`main.gd:172-174`) so rebuilding actually matters.

**Effort:** L (this is the big one in Tier 1, and it is worth it)
**Depends on:** T0.4, T1.1, VS-1 (positional audio for the splinter cue), the hold-to-interact accumulator.

---

### T1.4 — Screen effect layer, and fix the inverted damage overlay

**Why it matters:** The red damage overlay is on a single channel shared between the hit flash and the low-health state, so at 30% HP a fresh hit is visually indistinguishable from standing still — and it clears right after you are mauled and returns while you heal.

**Source domains:** fx (`screen-effect-layer`, `missed-damage-overlay-inverted`, `fx-nuke-whiteout`, `post-grain-ca-vignette`), ui (`hud-health-blood-screen`), systems (`health-no-flinch-or-blood-overlay`), weapon-models (`md-no-damage-flinch`).

**Merged findings:** seven. Note two specialists reached **mutually contradictory** conclusions here and both were wrong — treat this as calibration on the rest of the report.

**The actual behaviour (verified):** `hud.gd:229` does `_flash = maxf(_flash, 1.0 - frac)` on every `health_changed`; `hud.gd:184-186` sets `_vignette.color.a = _flash * 0.45` decaying at 2.2/s. Because `player.gd:159-163` re-emits `health_changed` **every physics frame during regen**, the overlay decays away during the 3.4 s `REGEN_DELAY` (i.e. right after you were hit) and is then re-pinned for the entire heal. So it flashes correctly on the hit, goes clear while you are still in danger, and turns red again while you are recovering. The defect is *channel sharing plus inverted timing*, not "sticky" or "missing".

**Godot approach:** one fullscreen `ColorRect` with a `canvas_item` `ShaderMaterial` as the shared bus for every screen effect in the project — this single node then serves the nuke whiteout, power-up pickup flash, downed desaturation, teleport distortion, grain and static vignette. Uniforms: `hit_flash` (separate channel, spikes on impact, decays fast), `low_health` (driven from `hp/max_hp`, radial `smoothstep` masked by a procedurally-generated splatter noise so it is irregular, edges only, centre clear), `damage_dir` (a vec2 biasing the splatter toward the attacker — requires threading the attacker position through `Player.take_damage`, which `zombie.gd:132` already has in hand), `desat`, `whiteout`, `tint`. Add camera flinch on the same signal via a dedicated `Node3D` pivot between the player body and the camera, because `_cam.rotation.x` is the authoritative mouse pitch and must not be written by effects.

**Effort:** S
**Depends on:** VS-8 (the camera pivot).

---

### T1.5 — Economy correctness pass

**Why it matters:** Several exploits and mis-scorings quietly invert the intended risk/reward, and every one is a handful of lines.

**Source domains:** systems (`econ-max-ammo-and-wallbuy-refill`, `box-teddy-still-gives-a-gun`, `econ-drop-pool-and-fire-sale`, `round-no-dog-round-max-ammo`), gunplay (`gun-ammo-economy`, `gun-hitbox-fidelity` scoring half), zombie-visuals (`hit-headshot-classification-inconsistent`), zombie-ai (`dogs-max-ammo`, `missed-droptick-not-reset`), level (`level-box-teddy-still-pays-out`).

**Merged findings:** nine.

**The bugs:**
- **Teddy bear still pays out.** `_use_box` (`main.gd:533-538`) hands you the weapon and *then* consults `_box_teddy` to relocate. A teddy pull is therefore strictly better than a normal pull — free gun plus a relocation. The box's only downside does nothing. Fix: branch in `_update_box`, skip the offering state entirely on a teddy, set `_box_gun = ""`, guard `_prompt_for`/`_use_box`.
- **Wall-buy ammo refills everything.** `refill_ammo()` (`player.gd:345-349`) loops **every** gun setting both `res` and `mag` to max, and is the handler for both Max Ammo and the wall-buy re-buy branch (`main.gd:485`). So 250 points of Olympia ammo fully restocks a Pack-a-Punched Ray Gun in the other slot. Split into `refill_reserve()` (Max Ammo, reserve only, so dumping a mag first still matters) and `refill_gun(key)` (that weapon only). Refuse the purchase without charging when reserve is already full.
- **Headshot classification is per-weapon nonsense.** `_cone_blast` passes `z.global_position.y + z.head_threshold()` (`player.gd:250`) against a `>=` test (`zombie.gd:195`), so **100% of Thundergun kills score as headshots** — 100 points each and an inflated headshot counter on the death screen. The knife passes `head_threshold() - 0.01` (`:276`), so a knife can *never* headshot by construction. The Nuke passes 0.0.
- **Insta-Kill is pure upside.** `take_damage` overwrites `amount = 1e9` (`zombie.gd:196-197`) but the `headshot` flag is computed first at `:195`, so kills during Insta-Kill still pay the full 100-point headshot bonus. Canon is a flat 50 (130 on melee) — the point loss is the trade-off for free kills.
- **`Game.drop_tick` is never reset.** `_begin_round` resets `drop_count` (`main.gd:165`) but not `drop_tick`, which keeps accumulating leftover kills. The ancestor reset both (`html:2862`). Drops land earlier and earlier the longer a run goes.
- **No guaranteed dog-round Max Ammo.** `_on_zombie_died` has no round-type branch, and with only 9 dogs at round 5 against a `next_drop_at` of 16-29, a dog round frequently yields nothing at all.
- **AoE hits through walls.** `_cone_blast` and `_knife` both iterate the zombies group testing only distance and a dot product — no raycast. `Zombie._has_los` (`zombie.gd:176-182`) is the exact helper needed and already exists. Also tighten the Thundergun cone: `cone: 0.62` against `dot < 0.38` is a **134.8° total wedge**, roughly four times the real weapon, so it clears rooms behind your shoulders.
- **Knife cannot reach crawlers or hounds.** Reach is measured camera-to-body-centre in 3D from an eye height of 1.55 m. A crawler (centre 0.31 m) parked at its 1.05 m melee reach is 1.63 m away against a bare-knife reach of 1.5 m — permanently out of range. A hound lands at 1.53 m. Both become knifeable only after the 3000-point Bowie. Use a horizontal distance check.
- **Knife hits an arbitrary target.** `_knife` `return`s on the *first* node that passes (`player.gd:277`) — group insertion order, not proximity — so in a crowd you knife whichever zombie spawned earliest, possibly one standing behind another. Sort by distance.

**Effort:** S (each is small; the whole pass is one to two days)
**Depends on:** nothing.

---

### T1.6 — Round ceremony: stinger, title card, ambient tension

**Why it matters:** The round change is the most recognisable audio-visual beat in the franchise, and the port replaced a four-layer descending stinger with a single sine that sweeps the *wrong direction*.

**Source domains:** zombie-ai (`round-transition-presentation`), ui (`hud-round-change-sequence`), fx (`missed-no-round-transition-visual`), audio (`audio-round-sting`, `audio-ambience-tension`).

**Merged findings:** five.

**The defect:** `sfx.gd:104` is `_tone(120.0, 1.30, 2.4, 0.42, 1.6)` and `sfx.gd:86` computes `freq * pow(sweep, t)` — with `sweep = 1.6` the pitch **rises** to ~221 Hz. Canon is a low, lurching, *descending* cluster. The ancestor had it right: two detuned sawtooths 320→52 Hz and 322→50 Hz, a 1.7 s lowpassed noise swell, and a 70→32 Hz sub delayed 0.1 s (html:519-526). Additionally `decay 2.4` over 1.30 s leaves amplitude at 4% by the end, so the audible sting is really ~0.5 s. And `setTension(min(1, round/16))` drove a continuously rising ambient drone (html:541-554, 2868) that the port dropped entirely — between `_end_round` and the next `_begin_round` the game is **6.5 seconds of total silence**.

**Godot approach:** port the ancestor recipe as `_round_sting(round_no)`; sawtooth is trivial alongside the existing `sin(phase)` (`2.0 * fmod(phase/TAU, 1.0) - 1.0`). Bake three density tiers (rounds 1-5, 6-15, 16+) at startup and select on round. For the ambient bed, bake three looped stems (41 Hz saw through a 180 Hz lowpass, band-passed 340 Hz wind, a dissonant high stem) into an `AudioStreamSynchronized` on an `Ambience` bus, driving per-stream volume from a tension value tweened on `round_changed`, ducked during intermission so the sting lands against near-silence. For the visual, a splatter wipe `TextureRect` with a threshold-against-noise shader, the round numeral blooming from scale 3.0 with a saturation pulse, then settling to the corner label. Add a 1.2 s beat of silence between the last zombie dying and the stinger, and a distinct hound-round variant (thunder + distant howls) instead of the shared cue.

**Effort:** M
**Depends on:** VS-1, T1.4 (the screen effect layer for the desaturation pulse), T2.1 (bus architecture).

---

### T1.7 — Interaction system: facing, occlusion, hold-to-buy, affordability, dead-entry deregistration

**Why it matters:** You can buy a door through a wall, owned machines silently eat the interact key, and nothing is a hold — which blocks the barricade rebuild and every future hold interaction.

**Source domains:** level (`level-interaction-lookat-and-hold`, `level-dead-interactables-swallow-input`, `level-door-cost-signage`), ui (`ui-interaction-prompt`).

**Merged findings:** four.

**The defects:** `_update_interact` (`main.gd:403-415`) picks minimum 2D distance with no facing test and no occlusion test. Verified example: the MP40 wall-buy interact point is at (23.1, 11.5); the Corridor tile centre (21.5, 10.5) is 1.886 m away — inside `INTERACT_RADIUS 2.0` — with tiles (22,10) and (22,11) both solid between them. It is buyable through a wall corner. Separately, `_prompt_for` returns `""` for an owned bowie, an owned perk and a thrown power switch, but `_update_interact` still assigns them to `_current_interact`, creating a dead zone that masks any other interactable in range; the bowie branch is worse and plays the deny tone on every press once owned. Affordability is never checked when building the prompt — the text is identical with 5000 points or 0 — and a failed buy plays `deny` with no visual response at all.

**Godot approach:** keep the distance pre-filter, then add a dot-product facing test against the camera forward (require > ~0.55) and a short `PhysicsRayQueryParameters3D` on mask 1 to reject through-wall buys. Better still, give each interactable a real `Area3D` on layer 5 — already *named* `"interactable"` in `project.godot:110` and used by nothing — and resolve via the camera centre ray with `collide_with_areas = true`; that also gives a natural anchor for world-space signage. Deregister satisfied interactables instead of returning an empty prompt. Move prompt construction out of `main.gd` into a `PromptData` dict (`{verb, subject, cost, affordable, hold_time}`) rendered by the HUD as `RichTextLabel` BBCode so the cost turns red when unaffordable, and flash the points counter on a denial. Add the hold accumulator with a radial progress arc.

**Effort:** M
**Depends on:** T0.4 (`InteractionSystem` extraction)

---

### T1.8 — Melee correctness and telegraph

**Why it matters:** Zombie melee lands on the same frame contact begins with zero windup, and the player's knife plays its connect sound before the hit test.

**Source domains:** zombie-ai (`ai-attack-lunge-windup`), zombie-visuals (`melee-no-windup-instant-first-hit`, `anim-attack-is-two-frames-and-stops-dead`), gunplay (`gun-melee-shallow`, `gun-melee-unreachable-enemies`, `gun-no-los-on-aoe`), audio (`audio-melee-differentiation`).

**Merged findings:** seven. (Reach and target-selection bugs are handled in T1.5; this entry is the feel layer.)

**Godot approach:** add a ~0.35 s `_windup` before the attack strip plays, during which the zombie keeps closing at 40% speed — that both telegraphs and produces the lunge for free. Widen the entry test to a `_lunge_reach` of ~1.9 m while `melee_reach` stays the damage gate. Drive damage off `AnimatedSprite3D.frame_changed` at a designated strike frame rather than a bare float timer. Keep a small forward creep during the attack state (`velocity = dir * speed * 0.25`) so attackers press in rather than freezing dead. Randomise `melee_cadence` per zombie in `_configure` so a pile does not swing in lockstep. Alternate `_sprite.flip_h` per swing for a free left/right read. Split the audio into four ids — `knife_swing` (unconditional), `knife_flesh`, `knife_wall`, `zombie_claw` (positional, on the zombie) — since today `Sfx.play("melee")` fires *before* the hit-test loop at `player.gd:264` and is the *same* buffer the zombie uses for its claw at `zombie.gd:133`.

**Effort:** S
**Depends on:** VS-1.

---

### T1.9 — Downed state, and make Quick Revive actually revive

**Why it matters:** `Player.revive()` is defined and called by nothing, so a 1500-point perk purchases exactly seven extra seconds of crawling before an identical game over; and the `downed_changed` signal is emitted every physics frame into a listener that does not exist.

**Source domains:** ui (`hud-downed-bleedout-ui`), fx (`screen-downed-state`), systems (`down-quick-revive-never-revives`, `down-crawl-fidelity`, `down-no-perk-loss-or-down-counter`), weapon-models (`vm-downed-viewmodel`), gunplay (`gun-downed-loadout`), audio (`audio-down-bleedout-filter`).

**Merged findings:** eight.

**Godot approach:** add a `_revive_delay` countdown in the downed branch calling the existing `revive()`, plus `Game.revives_left` (start 3) decremented in `_go_down()`; at zero, free the perk marker and deregister the interactable. Move Quick Revive off the power gate and set it to 500 (BO1 solo canon; note the port's stated WaW/Der Riese baseline had no solo self-revive at all, so this is a deliberate choice, not a fidelity fix). On going down: tween `_cam.position.y` from 1.55 to ~0.35, shrink the capsule, stash `guns` and force the M1911, early-return from `_knife` and `_update_fire`, clear `Game.perks` (the single biggest economic punishment in Zombies, currently absent), push `desat` and a hard vignette on the T1.4 shader, and connect `downed_changed` in `hud.bind()` to a radial bleedout countdown. Add a global low-pass ramp to ~420 Hz on the Master bus, snapping open on revive — the ancestor's `setMuffled()` (html:463-467) is the single most memorable audio moment in a Zombies death. Track `Game.downs` and surface it on the game-over card.

**Effort:** M
**Depends on:** T1.4, T2.1 (bus architecture for the muffle).

---

### T1.10 — Power-on as a lighting event

**Why it matters:** The map is at full sodium light from frame one, so the single biggest state change in a Zombies run currently changes five sprite textures.

**Source domains:** fx (`fx-power-on-moment`, `render-no-shadows-flat-lighting`, `missed-one-blob-light-per-room`, `missed-always-on-torch`, `render-no-glow-bloom`, `fx-perk-machine-glow`), ui (`ui-power-no-lighting-event`, `ui-perk-machine-beacon`), level (`level-power-switch-and-lighting-state`, `level-lighting-fixtures-and-atmosphere`).

**Merged findings:** ten.

**Godot approach:** `_setup_environment` builds all eight room omnis at full 1.5 energy unconditionally in `_ready()` (`main.gd:97-104`), before `Game.power_on` can exist, and nothing ever touches `light_energy` afterwards. Store them in an array and start them at zero. Before power the map is lit by the torch plus a very low cold ambient. On the switch, run a staggered `Tween` chain — one room every ~0.15 s in distance-from-generator order, each with a three-flicker preamble into steady state — with a relay thunk per room and the ancestor's `powerOn()` generator whine underneath (40→120 Hz saw over 2.2 s, a 1.6 s noise swell, three delayed harmonics at 220/440/660 Hz, html:513-518). Enable `env.glow_enabled` with `glow_hdr_threshold ≈ 0.85` (Compatibility has no HDR buffer by default, so the threshold must be low) and give the perk machines, box and power-ups unshaded emissive material overrides plus per-perk `OmniLight3D`s coloured from `PERKDEF[k].col` — which already exists and is currently consumed only by a 26×26 HUD swatch. Gate the always-on 3.2-energy head torch (`player.gd:67-74`) so it does not simply erase all of this; consider making it a toggle, or dimming it, or removing it entirely (WaW/BO1 give the player no flashlight — that constraint is what makes a pre-power map frightening).

**Effort:** M
**Depends on:** T0.7 (renderer constraints), T0.4 (`Atmosphere` extraction).

---

## TIER 2 — Substantial, well-understood, medium cost

---

### T2.1 — Audio architecture: buses, polyphony, variation, sample rate

**Why it matters:** One bus, a 12-voice round-robin pool with no priority that truncates its own sounds mid-buffer, bit-identical repeats, and an 11 kHz ceiling under everything.

**Source domains:** audio (`audio-bus-architecture`, `audio-voice-pool-starvation`, `audio-sample-variation`, `audio-22khz-mono-ceiling`, `audio-mass-death-stampede`, `audio-weapon-power-not-in-the-mix`, `audio-weapon-layering`, `audio-bake-hitch`), zombie-visuals (`impact-audio-is-one-identical-buffer`), gunplay (`gun-audio-nonpositional`).

**Merged findings:** ten.

**The defects:** every voice hard-codes `bus = "Master"` (`sfx.gd:21`) and there is no `default_bus_layout.tres` in the repo, so no ducking, no limiter, no volume options. `play()` grabs `_players[_next]` round-robin with no `is_playing()` check, so an RPK with Double Tap at ~15.6 shots/sec plus hit markers wraps the 12-voice pool every ~0.4 s — guaranteeing that a 1.3 s round sting is chopped. A Nuke fires up to 24 phase-coherent copies of the *same* 0.42 s death buffer into a 12-voice pool in one frame, summing ~21 dB hot instead of reading as a horde. `_rng.seed = 0x5EED` is fixed and `_stream()` caches one buffer per id forever, so the `hit` sound is literally the same 1985 samples every time, every run — and the `pitch` argument on `play()` is never passed by any of the 24 call sites. `sfx.gd:131` hard-codes `-4.0 dB` for every weapon, so the Thundergun (`body 2.0`) is merely *longer* than the M1911 (`body 0.7`), not louder — the ancestor scaled every layer's gain by `body` (html:470-473). `RATE := 22050` and `stereo = false` put a hard 11 kHz ceiling under every sound in the project, which caps layering, variation and reverb no matter what else is done.

**Godot approach:** author `default_bus_layout.tres` with Master ← {Music, SFX, Ambience, Voice, Weapons}; `AudioEffectHardLimiter` at −1 dB on Master; `AudioEffectCompressor` on Music/Ambience sidechained to Voice so announcer-class cues duck automatically. Replace the manual pool with `AudioStreamPolyphonic` (polyphony 32) per bus, which returns trackable stream ids so real priority and per-id instance caps become possible. Bake N=5 variants per repeatable id with fresh seeds into `AudioStreamRandomizer` (`PLAYBACK_RANDOM_NO_REPEATS`, `random_pitch 1.12`, `random_volume_offset_db 3.0`). Coalesce mass death into one scaled cue. Scale gunshot gain by `body`. Raise `RATE` to 44100 — the bake cost is a one-off at startup and the perceptual gain applies to every future sound. Pre-bake everything during the title screen from a coroutine that `await`s a process frame between bakes, spread over ~40 frames, so the first shot of each weapon does not hitch. Note `papify()` never touches `freq`/`thump`/`body`, so the `_p` cache key at `player.gd:198` currently produces a byte-identical buffer — add PaP overrides for those three fields and the wasted bake disappears with it.

**Effort:** M
**Depends on:** VS-1.

---

### T2.2 — Viewmodel rig

**Why it matters:** There is no first-person weapon on screen at all, which is the most persistent object in every CoD and the primary channel for weapon identity and state.

**Source domains:** weapon-models (`vm-no-viewmodel-rig`, `vm-asset-sourcing-12-guns`, `vm-render-layer`, `vm-bob-and-sway`, `vm-sprint-pose`, `vm-fire-cycling`, `vm-reload-animations`, `vm-draw-holster`, `vm-knife-swing`, `vm-pap-camo`, `vm-shell-ejection`, `vm-empty-boltlock`, `vm-inspect`, `vm-downed-viewmodel`, `vm-wonder-weapon-idle-fx`), gunplay (`gun-no-viewmodel`, `gun-no-muzzle-fx`), fx, ui.

**Merged findings:** seventeen — the second-largest cluster, and the one most in need of the merge.

**The asset answer, which is the whole reason this is L and not XL:** do not hand-model twelve guns. `kriegsnacht.html:1151-1207` already authors all 12 weapons plus a knife as flat part lists in a 100×60 space — axis-aligned rects (`'r'`), circles (`'c'`), rotated rects (`'rr'`) and one polygon (`'p'`), each with a hex colour. Port that table into a `weapon_art.gd` const and write a builder that extrudes each 2D primitive into a box/cylinder/prism along Z at a per-part depth, welded into one `ArrayMesh` via `SurfaceTool` with vertex colours and a single `StandardMaterial3D` with `vertex_color_use_as_albedo`. That yields twelve chunky low-poly guns in ~200 lines, zero external assets, one draw call each, and a look consistent with the flat-shaded world. The ancestor's `MUZZLE` anchor table (html:2020) becomes a `Marker3D` per weapon.

**Godot approach:** a `ViewmodelRig` `Node3D` child of the camera at roughly `(0.16, -0.14, -0.32)`, one `MeshInstance3D` per weapon with only the current one visible. Compose the transform from additive procedural offsets in `_process` — bob, sway, recoil spring, ADS lerp, sprint cant — rather than baked animation, so it costs one transform write per frame; keep an `AnimationPlayer` writing to a *child* node for the discrete clips (fire, reload, draw, holster) so procedural and keyed compose instead of fighting. For wall clipping, start with `no_depth_test = true` plus raised `render_priority` on a dedicated cull layer, not a second `SubViewport` camera (a second full-screen pass is a real fill-rate hit on weak WebGL2). Split the reciprocating part (the top rect in most `GUNART` entries) into its own child so the slide/bolt cycles on fire, driven by a plain float lerp — not a `Tween` node, because 880 RPM would allocate ~15 tweens a second. PaP camo is nearly free on a vertex-colour mesh: one `ShaderMaterial` remapping toward purple with a scrolling triplanar swirl and a cyan fresnel emission, one uniform toggle, all twelve weapons. Mustang & Sally is literally the m1911 mesh instanced twice, mirrored.

**Effort:** L
**Depends on:** T1.2 (bind to a real state machine), VS-5 (muzzle flash anchors), VS-8 (recoil spring).

---

### T2.3 — Aim-down-sights

**Why it matters:** CoD is an ADS-first shooter and Zombies' entire headshot economy assumes it; the port is hipfire-only with a fixed FOV and a fixed cone in every situation.

**Source domains:** systems (`no-ads`), gunplay (`gun-no-ads`, `gun-spread-model`), weapon-models (`vm-ads`).

**Merged findings:** four.

**Godot approach:** an `aim` action on mouse button 2; `_ads: float` eased by `1.0 - exp(-14.0 * dt)`; `_cam.fov` lerped 74→56; the spread term multiplied by `lerp(1.0, 0.15, _ads)`; bob and sway amplitude scaled down; crosshair faded out. Fix the spread distribution while here — `player.gd:214-217` applies two independent `randf_range` rotations about the camera's X and Y axes, which is a *square* distribution ~1.41× wider on the diagonals than on the axes, not a cone. Replace with a proper disc sample (`a = randf()*TAU; r = sqrt(randf()) * spread_rad`). Add state-dependent spread — a movement penalty term and a per-shot bloom float decayed each frame with a per-weapon ceiling — which is invisible today because there is no reference for cone size without a viewmodel or a reactive crosshair.

**Effort:** M
**Depends on:** T2.2, T1.2.

---

### T2.4 — Projectiles, splash damage and wonder-weapon identity

**Why it matters:** The Ray Gun is a 180-damage single-target hitscan — strictly *worse* than the 500-point M14's 185 — and its declared 1150 splash damage is thrown away.

**Source domains:** gunplay (`gun-no-projectiles`, `gun-no-explosive-reaction`, `gun-pap-uniform`), fx (`fx-wonder-weapon-signatures`), weapon-models (`vm-wonder-weapon-idle-fx`), zombie-ai (`crawler-from-dismemberment` — blocked on this), systems (`pap-generic-and-no-rack`).

**Merged findings:** seven.

**Godot approach:** a `Projectile` class extending `Area3D` (not `RigidBody3D` — you want deterministic cheap motion): integrate position manually with `velocity += gravity*dt` for the grenade and constant velocity for the orb, using swept `PhysicsRayQueryParameters3D` between last and current position so fast rounds do not tunnel. Visual is an unshaded emissive billboard `Sprite3D` plus an `OmniLight3D` child — *that travelling light is the whole point of the Ray Gun*, because it lights the corridor as it flies. A shared `_explode(pos, radius, colour)`: pooled particle burst, a `SphereMesh` flash scaled up and faded, an expanding floor ring, a light flash, camera trauma, and a splash query with a line-of-sight raycast so walls block it. Rebalance the raw numbers to canon (Ray Gun ~1000 direct). Add `Player.take_splash()` gated by a PhD check. Turn `papify` into a table lookup with an optional per-weapon `pap: {}` override merged over the base, so Mustang & Sally becomes `{proj: "grenade", splash: 2.4, splash_dmg: 1600, dual: true}` reusing this system rather than a special case. Tighten the Thundergun cone from 134.8° to ~63°.

**Effort:** L
**Depends on:** T1.2, T2.2.

---

### T2.5 — 8-direction billboard facing, contact shadows, per-instance variety

**Why it matters:** Every zombie permanently presents the same front-facing pose no matter which way it is moving, and nothing anchors any sprite to the floor.

**Source domains:** zombie-visuals (`anim-no-directional-facing`, `look-no-ground-contact-shadow`, `look-only-three-recolors-no-body-variants`, `anim-gait-pool`, `anim-no-gait-tiers`), fx (`missed-billboard-flat-lighting`), gunplay (`gun-collider-narrower-than-sprite`).

**Merged findings:** seven. **Scope is entirely determined by T0.8.** Under the recommended billboard answer:

**Godot approach:** regenerate the sprite strips as an 8-direction atlas (five drawn columns — front, front-¾, side, back-¾, back — mirrored to eight), which requires the asset pipeline reconstruction (T3.6). Store facing by setting `look_at()` on the body from its velocity, since a project-wide grep for `look_at|rotation.y` returns **zero hits** — there is currently no facing value anywhere to read. Add a shared blob contact shadow (a flat `QuadMesh` at y=0.02 with a radial-gradient alpha texture, one shared material across all zombies) — the correct answer for both billboards and a WebGL2 budget, and far cheaper than a shadow-casting `SpotLight3D`. Fix the free variety that is currently unused: `zombie.gd:92` starts every spawn on walk frame 0, so a wave marches in genuine lockstep — call `set_frame_and_progress(randi() % frames, randf())`. Tie `_sprite.speed_scale` to actual velocity rather than a one-shot `randf_range(0.85, 1.2)` set at `_ready()`, which currently decouples playback from ground speed and produces visible foot-skate where a *fast* zombie can play a *slower* cycle than a slow one. Note also `sprite_lib.gd:17` gives hounds `"pal": 0` so every hound is the same asset, yet `main.gd:190` still rolls `randi() % 3` for them — a dead roll. Finally, reconcile the collider with the sprite: the capsule is 0.52 m wide against 1.365 m of drawn, always-camera-facing billboard, so the outer ~40% of the visible zombie on each side is empty space to `_hitscan` — which reads as broken hit registration, not as a miss.

**Effort:** M (billboard path) / XL (skeletal path)
**Depends on:** T0.8, T3.6.

---

### T2.6 — Corpses, death variants and the nuke wave

**Why it matters:** Corpses pop out of existence at full opacity after 1.34 s, and every cause of death plays the identical four frames.

**Source domains:** zombie-visuals (`death-corpses-vanish-leave-nothing`, `death-no-cause-specific-variants`, `death-no-ragdoll-or-directional-impulse`), fx (`missed-corpses-pop`, `fx-nuke-whiteout`), audio (`audio-mass-death-stampede`).

**Merged findings:** six.

**Godot approach:** thread a `cause` enum (BULLET, MELEE, EXPLOSIVE, ENERGY, WIND, NUKE) and the killing direction — both already available at `player.gd:216-217, 232` and both currently discarded — through `take_damage` into `_die`. On the last death frame spawn a lightweight corpse (a `Sprite3D` frozen on the final frame, laid flat, `billboard = DISABLED`) held ~20 s then sunk through the floor, capped at ~20 with oldest-first recycling. NUKE: a whiteout on the T1.4 shader plus kills staggered by `distance_to(player) * 0.045` so the horde collapses as an outward wave rather than in a single frame, and one coalesced mass-death cue instead of 24 phase-coherent copies. WIND: a large backward impulse and a radial dust burst — the launch *is* the Thundergun's identity. ENERGY: a green tint and gib chunks. Electrocution (for later traps) is cheap and high-impact: strobe `modulate` white/blue over ~0.5 s while freezing velocity.

**Effort:** M
**Depends on:** VS-3, T2.4.

---

### T2.7 — Menus, options, persistence and accessibility

**Why it matters:** There are no `Button` nodes anywhere in the project, no settings of any kind, nothing is ever written to disk, and the plan actively adds screen shake, bob, cant, flashes and a whiteout with no way to turn any of it off.

**Source domains:** ui (`ui-main-menu`, `ui-pause-menu`, `ui-options-sensitivity`, `ui-gameover-stats`, `ui-hud-scaling-typography`), systems (`meta-no-persistence`), critic items 5 and 8.

**Merged findings:** seven.

**Godot approach:** a `Settings` autoload over `ConfigFile` at `user://` exposing sensitivity, FOV, invert-Y, master/SFX/music volumes routed to the T2.1 buses, plus **the accessibility toggles this plan makes mandatory**: reduce-motion (screen shake, view bob, sprint cant, landing dip — the ancestor honoured `prefers-reduced-motion` at html:223-226, 394 and the port dropped it), captions for every audio-only information channel (the audio plan adds directional threat cues and stings as *primary* channels with no visual equivalent, which makes the game strictly less playable deaf than it is today), a visual damage-direction indicator, and a colourblind path (perks are currently identified by colour plus a single letter, power-ups by colour alone). This is one small cheap workstream that nine specialists walked past.

Build a real `Control` menu with a shared `Theme` and focus neighbours so keyboard and pad navigation work. Switch pause to `get_tree().paused` with `PROCESS_MODE_WHEN_PAUSED` on the pause subtree, duck audio on pause, and clear the frozen prompt. **Verify the pause key at all** — `pause` is bound to Esc, and in a pointer-locked browser the user agent consumes the Escape keydown to exit pointer lock and does not deliver it to the page; the existence of an `L` `toggle_capture` binding suggests this was already hit once. Test against the shipped `docs/` build, not the editor.

Persist best round, best points, total kills and settings. Note `user://` on a web export is IndexedDB and, with `thread_support=false`, likely needs an explicit persistence flush — this is not the ten-minute task it looks like (Research Theme 6).

**Also here: own the first ninety seconds.** The README's first line is a public URL. A stranger currently gets Godot's default boot bar for a ~40 MB WASM download with no custom shell (`html/custom_html_shell=""`), then two Labels saying "click to begin", then a first-person view with no viewmodel, no control list, and no explanation that shooting earns points or that doors cost money. The ancestor shipped a keybind table and an onboarding paragraph explaining the points economy on its title screen. For a deliverable that is a link, retention in the first ninety seconds outranks about 200 items in this backlog: add a custom loading shell, a keybind list, and a one-paragraph hint.

**Effort:** M
**Depends on:** T0.3 (profile-vs-run state split), T2.1 (buses for the volume sliders).

---

### T2.8 — Pack-a-Punch as a real machine

**Why it matters:** The most theatrical object in Zombies is an invisible point on the floor that silently doubles your damage for 5000 points.

**Source domains:** fx (`fx-pap-machine-missing`), ui (`ui-pap-no-world-visual`), level (`level-pap-machine-and-cycle`), systems (`pap-generic-and-no-rack`), gunplay (`gun-pap-uniform`), weapon-models (`vm-pap-camo`).

**Merged findings:** six.

**Godot approach:** `main.gd:340-343` appends the pap interactable and — unlike the generator on the very next line, and unlike the perk machines and the box — never calls `_prop_sprite()`. Create the prop first (procedural geometry, or a 4-frame sprite strip closed/open/churning/ready in the established style). Then mirror the existing `_box_state`/`_box_timer` state machine, which is already the right shape: insert → ~5 s churn with the weapon removed from `player.guns`, sparks and a light ramp → a `racked` state where the upgraded gun must be collected, defaulting to loss on expiry. Electric arcs are the standard cheap Godot trick: 3-4 `ImmediateMesh` polylines regenerated every ~0.08 s between anchor points, unshaded additive. Add PaP camo via the T2.2 shader. Give it a `BoxShape3D` so it is trainable geometry.

**Effort:** M
**Depends on:** T0.4, T1.10 (glow), T2.2 (camo shader).

---

### T2.9 — Mystery Box theatre

**Why it matters:** A 2.9-second spin during which the on-screen prompt is literally the string `"..."`, a 7-second offer window with no countdown that silently expires and costs you 950 points, and a relocation with no beacon.

**Source domains:** fx (`fx-mystery-box-beam-teddy`), ui (`ui-mystery-box`), level (`level-mystery-box-presentation`), audio (`audio-box-jingle-teddy`).

**Merged findings:** four. (The teddy payout bug is in T1.5.)

**Godot approach:** a floating weapon silhouette above the box cycling through `Weapons.BOX_POOL` on a decelerating interval with a click per swap — which also fixes the dead `"..."` prompt. A shrinking ring on the HUD for the offer window. A tall additive `CylinderMesh` beam with a scrolling noise shader, permanently on at the box's current spot so it is findable from across the map after a relocation — reused verbatim for power-up drops and the teleporter if that ever lands. Teddy rises on a tween while the beam intensifies, then the box relocates. Port `boxOpen` (the 12-note `[0,3,7,10,12,10,7,3,0,7,12,15]` triangle melody), `boxTake` and `teddy` (descending `[12,10,7,3,0,-5]`) from html:527-534 — the melodies already exist. Randomise the starting spot: `Game.box_spot = 0` is hard-set at `main.gd:345-346`, so the box is *always* in the Theatre behind the 750 door on a fresh game, which removes the "where is the box this run" element entirely.

**Effort:** M
**Depends on:** VS-1, T1.10.

---

### T2.10 — Wall-buy chalk and world-space signage

**Why it matters:** Seven wall buys and the Bowie exist only as text prompts inside a 2 m radius; the primary navigational landmark of a Zombies map is invisible.

**Source domains:** ui (`ui-wallbuy-chalk`), level (`level-wallbuy-chalk`, `level-door-cost-signage`).

**Merged findings:** three.

**Godot approach:** **not** `Decal` — unsupported in gl_compatibility. Emit a quad 0.01 m proud of the wall plane at build time in `WorldBuilder`, `transparency = ALPHA_SCISSOR`, with a chalk texture generated procedurally by replaying the `GUNART` part list into an `Image` with a jittered white stipple, plus blitted price digits. Batch all chalk quads into one atlas surface so it stays one draw call. Since each wall-buy already stores `tile` and `face`, placement is pure derivation with no new data. Note the door-cost half of this is *not* a gap against the WaW/BO1 baseline — those games present door cost as a centred on-screen hint, which `_prompt_for` already does; floating world-space prices are a BO3-era embellishment. Scope this to chalk only.

**Effort:** M
**Depends on:** T3.6 (asset pipeline).

---

## TIER 3 — Large or deferred

### T3.1 — Grenades, Monkey Bombs and equipment
Four frags at spawn with a cookable fuse, a wall buy, and the Monkey Bomb — which needs no new systems beyond a global `Game.lure_position` that `Zombie._physics_process` targets instead of the player, since the existing flow field and LOS steering handle the rest. **Source domains:** gunplay (`gun-no-grenades`), weapon-models (`md-no-throwables`), systems (`weapon-no-grenades`). **Effort:** M. **Depends on:** T2.4.

### T3.2 — Walker→crawler by leg-shot, and per-limb hit zones
The mechanical basis of the entire between-round shopping meta. Under the billboard decision this is a mid-life `sprite_frames` swap to the existing crawler set plus a capsule resize — **zero new art** — gated behind a leg-band damage test and the splash system. Add child `Area3D` hitboxes on the layer already *named* `"hitbox"` at `project.godot:109` and used by nothing. **Source domains:** zombie-ai (`crawler-from-dismemberment`), zombie-visuals (`hit-no-per-limb-hitboxes`, `gore-dismemberment-and-crawler-transition`), fx (`fx-dismemberment-and-gibs`), gunplay (`gun-hitbox-fidelity`, `gun-flat-headshot-multiplier`). **Effort:** L. **Depends on:** T0.8, T2.4.

### T3.3 — Traps
The classic mid-game points sink and the second reason power exists. A `TRAPS` table, a new interactable kind, an armed `Area3D` on the enemy layer, a panel state machine mirroring `_light_perks`, and electric-arc `ImmediateMesh` visuals. The 2×1 `TX_METAL`/`FL_GRATE` Landing room between Theatre and Generator Hall is a natural trap corridor that currently does nothing. Note Nacht, Shi No Numa and Ascension have no traps, so this is a missing points sink rather than a missing identity. **Source domains:** level (`level-traps`), systems (`no-traps`). **Effort:** M. **Depends on:** T1.7, T1.10.

### T3.4 — Interior geometry: props, colliders, pillars, train loops
Every room is a bare extruded rectangle and every prop is a walk-through hologram (`_prop_sprite` creates a `Sprite3D` with no `StaticBody3D`). Give the perk machines, generator, box and PaP real box colliders so they act as training pivots as they do in CoD, then add a `PILLARS`/`BLOCKS` subtractive pass in `MapData.build()` — pure data, and the existing wall-face emitter and collision path pick it up for free. Procedural prop meshes (a crate is a bevelled box, a drum a 12-sided cylinder) via `MultiMeshInstance3D`, matching how the textures were made. **Source domains:** level (`level-interior-collision-and-props`, `level-room-shapes-and-train-loops`, `level-topology-is-a-closed-ring`). **Effort:** L.

### T3.5 — Perk roster expansion and the drink ritual
The four that exist — Juggernog, Quick Revive, Speed Cola, Double Tap — are precisely the WaW/Der Riese roster, i.e. **complete for the stated era**. Add Stamin-Up (which only becomes meaningful once sprint is finite, T0.1), Mule Kick (replace the `< 2` literal at `player.gd:337` with `Game.max_slots()`, drop the third gun on down), Deadshot (needs ADS), PhD (needs splash + dive). Add a `PERK_LIMIT` rule, a 2-3 s drink lockout gating fire/knife/reload, per-perk jingles on positional players, and machine idle hums — the navigational-by-ear property. Fix the HUD refresh bug while here: `_refresh_perks()` is called from exactly one site (`hud.gd:237`, inside `_on_weapon`), so **buying a perk does not update the strip until you next shoot, reload or swap.** **Source domains:** systems (`perk-roster-five-missing`, `perk-limit-and-ritual`), gunplay (`gun-perk-gaps`), level (`level-perk-machine-presence`), ui (`hud-perk-icons`), audio (`audio-perk-jingles`). **Effort:** L. **Depends on:** T0.1, T2.1, T2.3, T2.4.

### T3.6 — Reconstruct the asset pipeline as a committed tool
**This is a hard prerequisite for the entire art half of this backlog and nobody listed it.** 100% of the art was produced by replaying the browser build's Canvas2D drawing code and exporting PNGs. The generators survive — `buildSprites` at html:1439, `outlineSprite`, and the per-frame drawing code across ~950-1440 — but there is **no `tools/` directory, no export script, no documented procedure, and nothing in the Godot project that can produce a new frame.** Meanwhile the visual specialists collectively request a barrier-vault animation, a crawl cycle, ~8 gait variants, an 8-direction atlas, dismembered limb sprites, blood decals, chalk plaques, a PaP machine, headgear variants and per-weapon muzzle flashes — several dozen new assets, none of which can be made in the established 1 px-rim style until this exists. Extract the generators into a runnable, committed tool (Node script, or a Godot editor tool script using `Image`). **Source domains:** cross-cutting; critic item 15. **Effort:** M. **Blocks:** T2.5, T2.10, T3.2, and every future sprite.

### T3.7 — Release engineering: one-command reproducible build
Exporting currently requires manually disabling the MCP plugin and hand-mutating the `[autoload]` block in `project.godot` — the shipped `docs/index.pck` contains no `addons` or `mcp` strings, so it was done by hand, and the committed `project.godot` does not match what ships. `docs/` is a committed 39.5 MB build artefact; `.git` is already 13 MB against 664 KB of assets and grows by roughly that much per release. The live public build is already stale relative to the source. Before 200 changes start landing this needs to be one command: a `tools/build.sh` doing a clean export from a stripped project config, plus CI, plus a decision about whether `docs/` should be a committed artefact at all (GitHub Pages can deploy from an Actions artefact instead). **Source domains:** cross-cutting; critic item 17. **Effort:** M.

### T3.8 — Reverb, occlusion and per-room acoustics
Two or three reverb buses with an `Area3D` per `MapData.ROOMS` entry using `audio_bus_override` — Godot 4 reroutes any `AudioStreamPlayer3D` inside automatically, so per-room acoustics come with almost no code, reusing the same loop that already places the room lights. Cheap amortised occlusion raycasts dropping `attenuation_filter_cutoff_hz` for emitters behind walls. **Source domains:** audio (`audio-reverb-occlusion`, `audio-weapon-layering`). **Effort:** L. **Depends on:** T2.1.

### T3.9 — Impact response on world geometry
`_hitscan` discards the world hit entirely — a bare `return` at `player.gd:235` — so `hit.position` and `hit.normal` are thrown away. Derive the surface from the hit point via `MapData.ix()` plus the normal (wall vs floor) and index `wtex`/`ftex` into an impact table for per-material puffs, sparks and sounds. Bullet holes as a `MultiMeshInstance3D` ring buffer with per-instance custom data, since `Decal` is off the table. Note the puff and the sound are worth far more than the persistent holes on 64 px nearest-filtered walls under 0.055 fog. **Source domains:** fx (`fx-impact-decals-per-surface`, `fx-tracers-shells-smoke`), gunplay (`gun-no-muzzle-fx`), weapon-models (`md-no-impact-feedback`, `vm-shell-ejection`). **Effort:** M. **Depends on:** T0.7.

### T3.10 — Movement: gravity, jump, acceleration
`velocity.y = 0.0` is written unconditionally every tick (`player.gd:155`), no gravity is applied, and there is no `jump` action. Add gravity, a jump, and `move_toward`-based ground acceleration and friction so strafing has weight. **Mantling is not worth building yet** — `WALL_H` is a single constant and every tile is either solid or floor, so there is no ledge in the project to mantle. Likewise crouch/prone: with a uniform 2.8 m ceiling there is nothing to crouch under. Both become valuable only after T4.1. **Source domains:** systems (`move-no-jump-or-mantle`, `move-no-acceleration-or-viewbob`, `move-no-crouch-prone-dive`). **Effort:** M.

---

## TIER 4 — Deferred; revisit after the pillars decision

### T4.1 — Level verticality
The map is a single flat plane at y=0 with a ceiling at 2.8 m and no elevation channel in the grid at all. Verticality is what creates high-ground camping spots, one-way drops that break a train, and readable sightlines. But a single-storey map still reads as Zombies (Shi No Numa's boardwalk, Nacht's ground floor, each floor of Five), and this is XL work that invalidates the 2D flow field. **Source domains:** level (`level-verticality`, `level-outdoor-alley-is-a-roofed-box`, `render-alley-night-ceiling`). **Effort:** XL. **Depends on:** Research Theme 5.

### T4.2 — Seeded run layer / roguelike meta
Entirely contingent on T0.2(a). Under the recommended faithful-first answer this is the *cheap* version: seeded shuffle of `WALLBUYS`/`PERKSPOTS`/`BOXSPOTS`, randomised door costs, an intermission upgrade draft hooked into the existing 6.5 s window, and a persistent currency. `compute_reach()` already re-derives reachability so nothing downstream breaks. Full procedural layouts are XL and probably wrong. **Source domains:** systems (`meta-roguelike-layer-absent`). **Effort:** M (seeded variance) / XL (procedural). **Depends on:** T0.2, T0.3.

### T4.3 — Skeletal enemies, dismemberment, ragdoll
Only if T0.8 is answered the other way. **Effort:** XL.

### T4.4 — Teleporters, buildables, boss rounds, Nova crawlers
Map-specific set pieces on an original map with no matching fiction. `special-boss-round`'s one genuinely reusable part is the `ROUND_KIND` refactor next to `is_dog_round` — branching on a round *type* rather than a bool — which is worth landing on its own regardless. **Source domains:** level, zombie-ai. **Effort:** L-XL each.

### T4.5 — Music and the easter-egg song
Original compositions only; the real tracks are commercially licensed and would compound the trademark exposure already flagged in the README. Three hidden `kind: "secret"` interactables with no HUD prompt, a counter, a chime per find. **Source domains:** audio (`audio-music-system`). **Effort:** M + composition time. **Depends on:** Research Theme 8.

### T4.6 — Occlusion culling and LOD
Not a gap against CoD Zombies; a speculative enabling constraint. The README's own measurement (16-28 draw calls, ~1300 primitives) shows the current budget is nowhere near strained. **Revisit only after T3.4 lands, and with the T0.7 measurement rather than an assumption.** **Source domains:** level, zombie-visuals. **Effort:** M.

### T4.7 — Controller support and aim assist
Absent from the codebase *and* from all nine specialist reports. Every binding in `project.godot:41-102` is keyboard/mouse. Base CoD Zombies is a controller-first game, and a very large part of what "gunplay feel" actually means on console is **aim assist** — rotational slowdown near a target plus stick magnetism. The gunplay specialist wrote 27 findings about ballistics and never mentioned it. If reproducing the *feel* of the reference is the goal, hipfire aim assist contributes more than the recoil curve. Deferred only because T0.2(c) likely commits to desktop mouse-and-keyboard. **Source domains:** critic item 7. **Effort:** M.

---

## RESEARCH AGENDA

Eight themes. Each is a self-contained brief for a web-research phase: what we need to know, why it blocks implementation, and what a good answer looks like.

---

### R1 — What actually works in Godot 4.7's gl_compatibility renderer on WebGL2

**What we need to know.** An authoritative, version-specific feature matrix for the renderer the game actually ships on. Specifically: is `Decal` supported (assumed no)? `FogVolume` / volumetric fog (assumed no)? SSAO/SSIL/SSR (assumed no)? Does `GPUParticles3D` genuinely function on WebGL2 without compute shaders, or does it silently fall back — and is `CPUParticles3D` the only safe option? Does `Environment` glow work, and how many blur levels are affordable? Are omni/spot **shadow maps** available, and what is `MAX_LIGHTS_PER_OBJECT` — does exceeding it silently drop lights on the large map-wide batched surfaces `WorldBuilder` produces, forcing a per-room surface split? Does `MultiMeshInstance3D` with per-instance custom data still collapse to one draw call? Is `INSTANCE_CUSTOM` available on a plain `MeshInstance3D`? Does `SCREEN_TEXTURE` work in a spatial shader, or must distortion be faked in a `canvas_item` fullscreen pass? Does `no_depth_test` sort correctly against alpha-scissor surfaces? Does `OccluderInstance3D` function at all?

**Why it blocks.** Roughly forty entries in this backlog propose a visual technique, and several raw findings propose Forward+-only features that will silently no-op in the shipped build. Without this matrix we will author effects nobody sees and debug them against the wrong renderer.

**A good answer** is a table of feature → supported/unsupported/degraded in 4.7 gl_compatibility on WebGL2, each row sourced from official docs, the renderer compatibility matrix, or a tracked GitHub issue, plus the fallback technique for each unsupported feature. It becomes `docs/RENDERER-CONSTRAINTS.md`.

---

### R2 — The single-threaded WebAssembly performance envelope

**What we need to know.** Real numbers for the shipping target, not an RTX 5090 running Forward+ natively. How many concurrent `AudioStreamPlayer3D` voices can Godot 4.7's single-threaded WebAudio driver mix before dropout, and what does the per-voice attenuation-filter biquad cost? How many `AudioStreamPlaybackPolyphonic` voices, and does overflow fail silently or throw? What is the cost of 2-3 concurrent `AudioEffectReverb` buses? Is `Area3D.audio_bus_override` honoured under that driver? On physics: what does adding player↔zombie and zombie↔zombie collision cost for 24 mutually-colliding `CharacterBody3D` capsules piling in a doorway, against the README's 1.22 ms native figure? What is the realistic simultaneous cap for `PhysicalBone3D` ragdolls, and is a single-capsule "fake ragdoll" the better trade? What is the acceptable total `.pck` size for a GitHub Pages build before first-load time becomes prohibitive on a median connection?

**Why it blocks.** T0.1 makes zombies collide, T2.1 makes audio polyphonic and positional, and every VFX item draws down a budget that has never been measured on the shipping renderer or hardware. `perf_probe.gd` exists to answer part of this and its result was never recorded.

**A good answer** combines published benchmarks and issue-tracker evidence with a plan for measuring the rest ourselves in the exported build, and yields concrete caps to hard-code: max 3D voices, max ragdolls, max particles, target payload size.

---

### R3 — Web export persistence, input and platform reality

**What we need to know.** Does `user://` reliably persist across page loads on GitHub Pages without SharedArrayBuffer, and with `thread_support=false` does it need an explicit flush/sync before the tab closes — does a mid-write tab close lose the file? Is the Escape key deliverable to a pointer-locked page at all, or does the user agent consume it to exit pointer lock (which would mean the pause key is dead in the shipped build)? What is the correct alternate pause binding convention for browser FPS games? For mobile: what does `vram_texture_compression/for_mobile=false` on a Web preset actually break on mobile WebGL2, and what is the minimum viable touch-control scheme if T0.2(c) is ever revisited? What is the current best practice for a custom Godot web loading shell, and what does it cost to implement?

**Why it blocks.** T2.7 assumes persistence works; if it does not, the entire settings and high-score workstream needs a different backing store. The pause-key question is a *shipped functional bug* we have not confirmed. The mobile question is a scope decision that T0.2 must make with facts.

**A good answer** states definitively whether persistence works and what the flush incantation is, resolves the Escape question with a citation or a test plan against the live `docs/` build, and prices the mobile path.

---

### R4 — Canon reference numbers for the WaW/BO1 era

**What we need to know.** Authoritative values for the era this port targets, because several current numbers are demonstrably off and several "canon" claims in the specialist reports contradict each other. Specifically: exact zombie melee damage vs base and Juggernog health (the port uses 34 against 100/250, giving 3 and 8 hits where canon is 2 and 5); the real power-up drop trigger — kill counter, accumulated damage, or hybrid — and the per-round drop cap (the port uses a 16-29 kill counter capped at 4); the exact points award during Insta-Kill; per-weapon headshot multipliers (the port uses a flat 1.5× for everything); the zombie HP cap and the round it applies; the real hellhound round cadence (fixed every 5, or a randomised 4-5 gap); dog-round Max Ammo guarantee; Quick Revive solo behaviour per title (cost, use count, whether it existed at all in WaW); the perk cap; wall-buy ammo refill pricing convention; and the movement-class speed tiers with the rounds that unlock them.

**Why it blocks.** T0.1's curve reshape and T1.5's economy pass are both tuning work, and tuning against a wrong target is worse than not tuning. The verification pass already caught several specialist "canon" claims that were BO2/BO3/BO4-era features misattributed to the WaW/BO1 baseline.

**A good answer** is a table of value → source (Treyarch/Activision material, the Call of Duty wiki with corroboration, or datamined game files), with the title each value comes from explicitly noted, and a flag on anything that changed between WaW, BO1 and BO2.

---

### R5 — Pathfinding architecture for a horde on a single thread

**What we need to know.** The current `FlowField` is a single BFS sweep from the player's tile that solves all 24 agents at once — that one-sweep-solves-all property is why it was chosen, and it is genuinely good. But T4.1 (verticality) breaks the 2D grid assumption, and T3.4 (interior props) requires stamping footprints into the solidity grid. So: is a baked `NavigationRegion3D` with 24 `NavigationAgent3D` queries affordable in a single-threaded WASM build, or does it blow the frame budget? If not, what does a layered 2.5D flow field look like (tile → list of `(height, dist)` cells with explicit vertical links), and are there published implementations? Separately, what validity constraints must any generated or hand-authored layout satisfy so the flow field and the boid separation do not degrade — minimum corridor width in tiles, maximum simultaneously live windows, guaranteed training loop?

**Why it blocks.** T4.1 is XL and its cost is dominated by this answer. T3.4 is cheaper but still needs the soft-blocking model decided. Getting this wrong means rewriting the AI layer twice.

**A good answer** gives a clear recommendation with a cost estimate for each path, and a list of layout invariants we can validate a map against programmatically.

---

### R6 — Godot 4.7 architecture patterns for the systems this plan adds

**What we need to know.** The idiomatic, currently-correct patterns for several things this backlog needs and where a wrong first choice is expensive: composing procedural per-frame viewmodel offsets with keyed `AnimationPlayer` clips so they add rather than fight; the cleanest structure for a recoil accumulator that mouse look cannot overwrite (a dedicated `Node3D` pivot vs tracking `_look_pitch` in script and rewriting `_cam.rotation.x` each frame); an interruptible shell-by-shell shotgun reload (`AnimationNodeStateMachine` self-transition vs hand-driven `seek()`); whether `AudioStreamSynchronized` allows per-stream volume changes at runtime without restarting playback and whether it stays sample-locked under the web driver's variable buffer; whether `SpriteBase3D` with `BILLBOARD_FIXED_Y` respects a local Z rotation or whether the billboard shader overwrites the full basis (this determines whether the cheap vault-clamber trick works at all); and per-instance shader parameters on `Sprite3D`/`MeshInstance3D` without breaking batching.

**Why it blocks.** T2.2 (viewmodel), T1.2 (weapon state machine), T1.6 (ambient stems) and T2.5 (billboard facing) each have a fork in the road early, and the wrong branch is a rewrite rather than a refactor.

**A good answer** is a short pattern per question with a code sketch, sourced from official docs, engine source, or a credible 4.x-era community implementation — explicitly *not* a Godot 3.x answer, which is the dominant failure mode when searching for these.

---

### R7 — Where the art and audio actually come from for a solo fan project

**What we need to know.** This is the asset-pipeline and licensing question, and it is the largest unowned blocker in the plan.

**(a) The pipeline.** 100% of the existing art was generated by replaying the browser build's Canvas2D code. There is no `tools/` directory and nothing in the project that can produce a new frame. What is the best form for a reconstructed generator — a Node script replaying the extracted JS, a headless-browser capture, or a rewrite as a Godot editor `@tool` script using `Image`? What is the least-effort path that can produce an 8-direction atlas, a crawl cycle, gib chunks, headgear variants and chalk plaques in the established 1 px-rim style?

**(b) Sourcing.** If the generator route fails: what genuinely permissive (CC0 / CC-BY) sources exist in 2026 for a rigged low-poly humanoid suitable for a zombie (Quaternius, Kenney, Mixamo's licence terms for a *published* game), for gib/limb sprite strips matching a 48×64 three-palette pixel zombie, and for weapon sounds (Sonniss GDC bundles, Freesound) — and what does 12 weapons × 3 layers × 3 variants cost as mono Ogg Vorbis against the payload budget from R2? Is pure synthesis competitive with samples on perceived quality for this art style? For an announcer with no voice actor: is there a permissively-licensed TTS model that can be rendered offline to Ogg at build time, and does any of it survive heavy pitch-shift and ring-mod into a usable processed/child-ghost timbre?

**(c) Licensing.** The README correctly flags trademark exposure on "Juggernog", "Pack-a-Punch" and the twelve PaP names, but stops far short of what nine specialists just requested: rigged 3D zombies, twelve first-person models of *real firearms*, announcer voice lines, perk jingles (copyrighted **compositions**, not just recordings), and music. There is **no `LICENSE` file in the repository at all**, no `NOTICE`/attribution file for the CC-BY assets this will inevitably pull in, and the whole thing is publicly deployed at a real URL under the author's own GitHub account. What are the practical rules for a non-commercial fan project on: real firearm model names and shapes; recreating a copyrighted musical composition even as an original synthesis; parody/homage boundaries on trademarked perk names; and what a correct `LICENSE` + `NOTICE` pair looks like for a project mixing original code, ancestor-derived art and third-party CC assets?

**Why it blocks.** T3.6 is a hard prerequisite for the entire art half of this backlog and cannot start without (a). T2.2's procedural-`GUNART` approach is chosen specifically to sidestep (b) and (c) — confirming that it does sidestep them is load-bearing. And (c) is an unanswered legal question sitting on a live public URL.

**A good answer** yields a concrete pipeline recommendation with a first task, a shortlist of vetted asset sources with their exact licence terms and attribution requirements, and a drafted `LICENSE` + `NOTICE` + a short "what we will and will not name" policy.

---

### R8 — What the ancestor already had: extracting `kriegsnacht.html`

**What we need to know.** This is partly a code-archaeology task rather than a web search, but it is the highest-value research in the list and belongs here. A complete behavioural inventory of the 139 KB browser build: every gameplay behaviour, every audio recipe, every visual effect, every UI affordance, with its line range and its port status. The known-deleted list in T0.6 is a *starting* inventory assembled from the verification pass — it is certainly incomplete, and the parts nobody has read yet (the drawing code across ~950-1440, the interact scan around 2682, the HUD/prompt code around 3063-3100, the render-quality selector at 216-340) are exactly where the remaining surprises are.

**Why it blocks.** Roughly forty backlog items have a working, *tuned* reference implementation in that file. Several are literal transliterations of ten to thirty lines of JS. Without the inventory we will re-derive from scratch things that were already designed, tuned and shipped — and we will re-derive them worse, because the original was play-tested.

**A good answer** is `docs/analysis/ancestor-diff.md`: a table of behaviour → html line range → port status (present / degraded / deleted) → estimated port cost, sorted by value. It should also flag anything the ancestor did *badly* that the port correctly improved, so we do not regress those (mouse capture is the documented example; the port's 3D height-based headshot test is another).

---

## Appendix: merge index

For traceability — which raw finding ids collapsed into which backlog entry.

| Entry | Raw findings merged | Domains |
|---|---|---|
| T0.1 | `no-player-zombie-collision`, `ai-physical-crowding`, `move-no-sprint-stamina`, `round-speed-classes`, `round-hp-cap-and-cost`, `spawn-hound-cap`, `health-damage-and-jug-math` | systems, zombie-ai |
| T0.2 | `meta-roguelike-layer-absent`, `ui-coop-absent` + critic 2/3/6/7/18 | systems, ui |
| T0.3 | `meta-roguelike-layer-absent` (seed half), `meta-no-persistence` (split half) | systems |
| T0.4 | cross-cutting | all |
| T0.5 | critic 9, 10 | all |
| T0.6 | critic 1 | all |
| T0.7 | `render-web-renderer-tier`, `perf-no-lod-culling-or-instancing`, `missed-no-aa-on-pixel-billboards` | fx, zombie-visuals |
| T0.8 | `anim-no-skeletal-3d-model` + ~30 downstream | zombie-visuals, fx, gunplay |
| VS-1/2 | `audio-3d-spatialisation`, `audio-zombie-vocals`, `ai-positional-moans`, `audio-no-moan-bed-and-nonpositional`, `level-no-positional-audio-landmarks`, `gun-audio-nonpositional`, `audio-footsteps` | audio, zombie-ai, zombie-visuals, gunplay, level |
| VS-3/4 | `gore-no-blood-impact-vfx`, `ai-hit-flinch`, `anim-no-hit-flinch`, `fx-blood-spray-and-decals`, `gun-no-hit-feedback`, `hud-hitmarker`, `md-no-impact-feedback`, `vm-hipfire-crosshair-feedback`, `hud-crosshair-static`, `audio-killing-blow-has-no-impact-cue`, `no-damage-state-on-the-body` | 7 domains |
| VS-5 | `vm-muzzle-flash`, `fx-muzzle-flash`, `gun-no-muzzle-fx` | weapon-models, fx, gunplay |
| VS-6 | `look-no-glowing-eyes`, `fx-zombie-eye-glow-and-hitflash`, `render-no-glow-bloom` | zombie-visuals, fx |
| VS-7 | see T1.3 | 5 domains |
| VS-8 | `vm-recoil-dead-and-never-recovers`, `gun-recoil-dead`, `cam-recoil-and-shake`, `recoil-never-recovers`, `missed-no-view-bob`, `vm-bob-and-sway`, `md-no-damage-flinch` | weapon-models, gunplay, fx, systems |
| T1.1 | `spawn-zone-locality`, `spawn-per-barrier-pacing`, `missed-spawn-inside-melee-range`, `spawn-lands-inside-the-room-past-the-barricade`, `level-spawn-zoning`, `ai-stuck-recovery`, `missed-stale-flowfield-on-door`, `missed-los-ungated` | zombie-ai, zombie-visuals, level |
| T1.2 | `gun-weapon-state-machine`, `md-no-weapon-state-machine`, `gun-trigger-input-dropped`, `gun-firerate-quantised`, `gun-reload-monolithic`, `vm-reload-animations`, `vm-draw-holster`, `weapon-swap-instant-and-reload-persists`, `shells-flag-dead-no-shell-reload`, `gun-no-trigger-models`, `md-m16-fire-mode`, `vm-empty-boltlock` | gunplay, weapon-models, systems |
| T1.3 | `spawn-barrier-teardown`, `spawn-vault-window`, `anim-no-barrier-teardown-vault`, `level-window-barricade-geometry`, `level-player-rebuild-barricades`, `level-barrier-vault-and-teardown`, `level-nothing-exists-outside-the-barricades`, `missed-barricade-rebuild`, `econ-no-barricade-repair`, `audio-barricade-boards`, `gun-penetration-and-wallbang` | 6 domains |
| T1.4 | `screen-effect-layer`, `missed-damage-overlay-inverted`, `hud-health-blood-screen`, `health-no-flinch-or-blood-overlay`, `post-grain-ca-vignette`, `fx-nuke-whiteout` | fx, ui, systems |
| T1.5 | `econ-max-ammo-and-wallbuy-refill`, `gun-ammo-economy`, `box-teddy-still-gives-a-gun`, `level-box-teddy-still-pays-out`, `hit-headshot-classification-inconsistent`, `gun-hitbox-fidelity`, `missed-droptick-not-reset`, `dogs-max-ammo`, `round-no-dog-round-max-ammo`, `econ-drop-pool-and-fire-sale`, `gun-no-los-on-aoe`, `gun-melee-unreachable-enemies`, `gun-range-cliff` | systems, gunplay, zombie-ai, zombie-visuals, level |
| T1.6 | `round-transition-presentation`, `hud-round-change-sequence`, `missed-no-round-transition-visual`, `audio-round-sting`, `audio-ambience-tension`, `dogs-ceremony`, `audio-hellhound-cue` | zombie-ai, ui, fx, audio |
| T1.7 | `level-interaction-lookat-and-hold`, `level-dead-interactables-swallow-input`, `ui-interaction-prompt`, `ui-door-cost-signage`, `level-door-open-presentation` | level, ui |
| T1.8 | `ai-attack-lunge-windup`, `melee-no-windup-instant-first-hit`, `anim-attack-is-two-frames-and-stops-dead`, `gun-melee-shallow`, `audio-melee-differentiation` | zombie-ai, zombie-visuals, gunplay, audio |
| T1.9 | `hud-downed-bleedout-ui`, `screen-downed-state`, `down-quick-revive-never-revives`, `down-crawl-fidelity`, `down-no-perk-loss-or-down-counter`, `vm-downed-viewmodel`, `gun-downed-loadout`, `audio-down-bleedout-filter`, `audio-low-health-heartbeat` | ui, fx, systems, weapon-models, gunplay, audio |
| T1.10 | `fx-power-on-moment`, `ui-power-no-lighting-event`, `level-power-switch-and-lighting-state`, `missed-one-blob-light-per-room`, `render-no-shadows-flat-lighting`, `missed-always-on-torch`, `render-no-glow-bloom`, `fx-perk-machine-glow`, `ui-perk-machine-beacon`, `level-lighting-fixtures-and-atmosphere`, `audio-power-pap-stingers`, `fx-dust-motes-and-light-shafts` | fx, ui, level, audio |
| T2.1 | `audio-bus-architecture`, `audio-voice-pool-starvation`, `audio-sample-variation`, `audio-22khz-mono-ceiling`, `audio-mass-death-stampede`, `audio-weapon-power-not-in-the-mix`, `audio-weapon-layering`, `audio-bake-hitch`, `impact-audio-is-one-identical-buffer`, `audio-weapon-mechanics`, `audio-no-economy-feedback` | audio, zombie-visuals, gunplay |
| T2.2 | 17 `vm-*` and `gun-no-viewmodel` findings | weapon-models, gunplay, fx, ui |
| T2.3 | `no-ads`, `gun-no-ads`, `vm-ads`, `gun-spread-model` | systems, gunplay, weapon-models |
| T2.4 | `gun-no-projectiles`, `gun-no-explosive-reaction`, `gun-pap-uniform`, `fx-wonder-weapon-signatures`, `vm-wonder-weapon-idle-fx`, `pap-generic-and-no-rack` | gunplay, fx, weapon-models, systems |
| T2.5 | `anim-no-directional-facing`, `look-no-ground-contact-shadow`, `look-only-three-recolors-no-body-variants`, `anim-gait-pool`, `anim-no-gait-tiers`, `missed-billboard-flat-lighting`, `gun-collider-narrower-than-sprite` | zombie-visuals, fx, gunplay |
| T2.6 | `death-corpses-vanish-leave-nothing`, `missed-corpses-pop`, `death-no-cause-specific-variants`, `death-no-ragdoll-or-directional-impulse`, `fx-nuke-whiteout` | zombie-visuals, fx, audio |
| T2.7 | `ui-main-menu`, `ui-pause-menu`, `ui-options-sensitivity`, `ui-gameover-stats`, `ui-hud-scaling-typography`, `meta-no-persistence`, `hud-ammo-block`, `ui-powerup-hud-state`, `missed-powerup-states-invisible`, `ui-announcer-and-feedback-lines`, `hud-points-float-popup` + critic 5, 8 | ui, systems |
| T2.8 | `fx-pap-machine-missing`, `ui-pap-no-world-visual`, `level-pap-machine-and-cycle`, `pap-generic-and-no-rack`, `gun-pap-uniform`, `vm-pap-camo` | fx, ui, level, systems, gunplay, weapon-models |
| T2.9 | `fx-mystery-box-beam-teddy`, `ui-mystery-box`, `level-mystery-box-presentation`, `audio-box-jingle-teddy`, `fx-powerup-beam-and-pickup-flash`, `audio-powerup-announcer` | fx, ui, level, audio |
| T2.10 | `ui-wallbuy-chalk`, `level-wallbuy-chalk`, `level-door-cost-signage` | ui, level |
| T3.x/T4.x | see individual entries | — |

**Findings intentionally not scheduled:** `special-boss-round` (except the `ROUND_KIND` refactor, folded into T4.4), `special-nova-crawlers`, `level-buildables`, `vm-inspect`, `level-occlusion-and-draw-budget` (T4.6 pending measurement), `perf-no-lod-culling-or-instancing` (same). All are out-of-era, speculative, or dependent on a measurement we do not have.
