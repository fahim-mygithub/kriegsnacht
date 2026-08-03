# M5 — Weapon feel: models, reload, bullet patterns, brass

Research brief for **Kriegsnacht**. Compiled 2026-08-02 from nine researchers — six on this
repository, three on the world. Every repo citation below was re-read; the ones that were wrong
are called out in **Where the corpus was wrong**.

**Revised 2026-08-02 after three adversarial reviews.** Every defect they raised was re-checked
against the source before anything moved here; the ones that did not survive that check are
recorded, with the evidence that killed them, in **What the critics found** at the end. Read that
table before trusting any number in this document that a reviewer disputed.

Evidence tiers: **1** engine source, shipped game assets, or this repo read directly ·
**2** maintainer statements, tracked issues, or a data file whose provenance has a known edit ·
**3** a well-maintained reference implementation or reputable secondary · **4** community anecdote.

---

## Bottom line

- **The guns read flat because of the shading, not the geometry, and that is the cheapest thing
  in this package to change.** The three face groups that fill the screen at the rest pose differ
  by 7.5% in brightness (top 1.0705, visible cap 1.0254, rear ends 0.9953 — computed from
  `gunart.gd:272-279`). Minecraft's axis ramp is 2:1 top-to-bottom and every blocky-FPS lineage
  read agrees on roughly that spread. **This is a hypothesis, not a measurement** — it must go
  through the frames gate before anything is built on it (M1).
- **Depth is a function of draw order and it is inverted.** `half = (BASE_HALF + i*LAYER)*UNIT`
  (`gunart.gd:456`) makes the M1911's 1.4-unit highlight rib 6.72 units thick against its
  5.20-unit receiver. Flan's Mod and OpenSpades both give each part its own depth and both put
  the receiver deepest. Fix it by authoring per-part depth **and keeping a monotone `+i*LAYER`
  tiebreak**, because that ramp is the z-fight fix (`gunart.gd:190-200`), not decoration.
- **Add BO1's spread bloom. It is one float on the player and four numbers per weapon, and this
  project has neither.** `_spread_rad` (`player.gd:862-872`) is a fixed cone with three static
  multipliers and no state at all. The part that gets dropped by every reimplementation is the
  **mutual exclusion**: in the shipped engine, movement suppresses decay entirely, so standing
  still is what recovers accuracy, not stopping firing. **But BO1's absolutes are 1.7× to 25×
  wider than the port's** — see the shipped-vs-proposed table under F18. Importing the *shape* and
  importing the *magnitudes* are two different decisions and R3 now makes you pick one.
- **The view kick points the wrong way and nothing in the suite can see it.**
  `player.gd:834` does `_kick_v -= def.kick * 0.55`; `viewmodel.gd:608` does `_kick_v += kick`
  with the same spring constants. The camera dips while the gun's muzzle rises. BO1 kicks the
  view up, the reference wins, and the fix is one character — but `RecoilPivot` sits above
  `Camera3D` and `_hitscan` reads `_cam.global_transform.basis`, so it moves where bullets go.
- **Do not add a CS-style memorised spray pattern.** BO1's recoil is a per-shot uniform draw
  inside a rectangle fed as a *velocity* into a spring that accelerates back to the original aim
  at `viewKickCenterSpeed`, clamped at ±10°. The ancestor already has that spring
  (`kriegsnacht.html:2960`) and the port already ports it. What is missing is the per-weapon
  bracket and the recentring term, not a table.
- **The Olympia's shell-by-shell reload is not canon and the Stakeout's is not shaped right.**
  BO1's `segmentedReload` is 1 on exactly the Stakeout and the China Lake; the Olympia is a
  3.30 s break-action. And a real segmented reload is start + N×shell + end (Stakeout 1.000 /
  0.567 / 0.767), not `reload / mag` (`weapon.gd:284-289`).
- **The shotgun pump cycles once per reload sequence, not once per shell.** `RELOAD_SHELL`
  re-enters itself (`weapon.gd:325-330`) and emits no state-change signal, so
  `viewmodel._on_weapon_state` never sees a shell land. This is the single most visible animation
  defect reachable from the signals that already exist.
- **Brass is a pooled `MultiMeshInstance3D` in `fx.gd`, physics-free, and it must draw from no
  `Rng` stream at all.** MultiMesh per-instance colour and custom data *do* work on
  gl_compatibility; `GPUParticles3D` cannot tumble a mesh casing at all. Four casing types cover
  the whole roster and four weapons eject nothing.
- **Nothing anywhere pins a `spread` or a `kick` value.** Multiply every one of them by ten and
  the whole suite stays green and the frames gate does not move, because the only spread assertion
  in the suite is a ratio. Closing that is the highest-value assertion work in the package — and
  the first draft of this document's own test plan did **not** close it, because every check in it
  was scale-invariant or measured against `_spread_rad`'s own output. A11 and A12 exist for that
  and nothing else.

**A number this document quotes and did not measure.** `ASSERTION_FLOOR` is 692 (`verify.gd:166`,
read directly). The green total of **693** is inherited from a prior note; nobody in the research
phase ran `--verify`, so "one assertion of slack" is a claim about a number that was not measured.
Measure it before sizing any floor raise (see Coverage gap 15).

---

## Where the weapon stands today

Art → mesh → pose → fire → damage, end to end.

**Art.** `scripts/data/gunart.gd` is a 745-line const table plus one extrusion function.
`ART` holds 101 parts across 13 weapons in the ancestor's 100×60 space, muzzle left and stock
right — 84 axis-aligned rects, 13 circles, 2 rotated rects (`mp40`, `pm63`), 2 polygons (both the
knife's). `MUZZLE` (:111-117) and `GRIP` (:127-133) are the only per-weapon spatial anchors, both
transliterated from `kriegsnacht.html:2020` and `:1224`. `SLIDE` (:146-160) names, **by array
index**, which parts reciprocate; six weapons have none.

**Mesh.** `_build(key, pap, want_slide)` (:440-472) filters on `slide.has(i) != want_slide`,
converts each part to one convex 2D polygon via `_part_poly` (:560-599), and sweeps it along model
+X in `_extrude` (:688-721) — two cap fans and one quad per edge, `4n-4` triangles. Depth is
`half = (BASE_HALF + float(i)*LAYER)*UNIT` (:456) — **painter's order and nothing else**. Colour
is `FILL + KEY*max(n·KEY_DIR, 0)` baked into the vertex colour at `_tri` (:739-744). Hands are
extruded into the body mesh (:460-469), so they cannot move. `_corners` (:477-495) is a
**hand-maintained parallel walk** of `_build` and it feeds `sight_height()`, `max_screen_radius()`,
`min_corner_depth()`, the ADS pose and three suites of assertions. Whole table: 2080 triangles.
No UVs, no index buffer, no smooth normals, no per-part z-offset, no bevel, and no primitive whose
axis runs along the barrel.

**Pose.** `scripts/entities/viewmodel.gd` turns three published floats (`state`, `state_t`,
`state_len`) plus edges into **nine scalar channels** written to exactly three nodes:
`ViewmodelRoot.transform` (sway + bob), `WeaponMesh.transform` (rest + kick + dip + drop + melee +
ADS + sight), `Slide.position.z` (:751-773). There is no `AnimationPlayer`, no `Tween`, no clip.
`_mesh_pose` (:776-805) is **pure**, so `_measure()` (:910-975) can sweep its endpoints — 144 poses
per weapon over ~1398 corners, 218,016 transformed points — which is the entire proof that the
weapon cannot clip a wall (`verify.gd:1728-1730`). Measured worst case 0.232 m against
`Player.RADIUS` 0.24 (`viewmodel.gd:36-38`).

**Fire.** `_unhandled_input` latches `_fire_held` / arms an 0.18 s buffer → `_physics_process`
calls `_update_view(dt, spd)` **then** `_update_fire(dt)` (:570-571) → a bounded
`while shots < WEAPON.MAX_SHOTS_PER_TICK` loop calls `_shoot` (:822). `_shoot` (:826-850) spends
the round, pushes `_kick_v -= def.kick*0.55`, adds shake, plays the shot, emits `fired` at a fixed
0.35 m point, and branches three ways: `_cone_blast` (Thundergun), `_launch` (Ray Gun / China
Lake), else `for i in int(def.pellets): _hitscan(def)`.

**Spread.** `_spread_rad` (:862-872) is the single authority:
`deg_to_rad(spread × 1.5-if-moving × 1.4-if-downed × lerp(1, 0.45, ads)) × 0.5`. So `spread` in
the table is degrees of **full cone** and the return is a **half-angle in radians**. The cone is
sampled as a uniform disc with two `Rng.VISUAL` draws (:886-887); `_launch` uses half that cone
with two more (:937-941). There is no shot counter, no bloom, no first-shot term and no slot in
the data model for one.

**Damage.** `_apply_hit` is the single funnel. Headshot is decided by the ray's world-space height
against `z.head_threshold()`, not by a hitbox — so anything that walks the aim up converts body
shots into headshots and doubles the payout. No falloff over range; `range` is a hard cliff and a
`_hitscan` that hits nothing emits no signal at all (:899-900).

---

## Findings

### The model

**F1 — Depth is draw order, and on ten of thirteen weapons the thickest part is a hairline
highlight strip.** Tier 1. `gunart.gd:456` and the mirror at `:488`. Worked on the M1911
(`:50-53`): part 0 receiver `h=7` gets 5.20 units of half-depth; part 2 barrel `h=4` gets 5.76
(1.44× as deep as it is tall); part 6, a 30×1.4 highlight rib, gets 6.72 — **4.8× its own
height**. Flan's Mod's `ModelColt` inverts this: grip 5 deep, barrel 2. Real M1911 slide is
~25 mm tall and ~23 mm wide. The reference agrees with Flan's, not with us.

**F2 — There is no way to author thickness, and adding a part makes the inversion worse.**
Tier 1. `ART` rows are `[kind, geometry…, colour]`; there is no depth column, no z-offset, and
`_extrude`/`_prism_corners` both hardcode `+half`/`-half` so every part is symmetric about `x=0`.
Every **appended** part gets the deepest half-depth and the largest `PROUD` inflation by
construction. Every **inserted** part shifts `SLIDE`'s indices, every later part's depth, and
every later part's `PROUD` — and therefore that weapon's `sight_height()` and its ADS pose.

**F3 — The baked key light gives a box exactly four brightness values spanning 1.2448:1, and the
three that fill the screen span 7.5%.** Tier 1, computed from the shipped constants.
`f(n) = 0.86 + 0.30·max(n·normalize(-0.55, 0.70, 0.45), 0)`: +Y top **1.0705**, −X cap **1.0254**,
+Z stock-end **0.9953**, and −Y/+X/−Z all clamp to **0.8600**. 1.070527 / 0.860000 = **1.2448:1**
— that is the whole bracket available to an axis-aligned rect, which is 84 of the table's 101 parts.
**Corrected after review: the first draft quoted 1.29:1 here, which is 1.1103/0.8600 — the ratio
including an oblique side-facet ceiling that no box face ever reaches.** Three brackets, kept
distinct because R1 and its bevel rejection need different ones: box faces **1.2448:1**; parts with
non-axis-aligned side facets (13 circles, 2 rotated rects) **1.291:1**, ceiling 1.1103; and the
absolute ceiling for *any* facet, `FILL + KEY` = **1.16**, i.e. **1.349:1**, reachable only by a
normal with an x component — which is to say only by geometry this builder cannot currently emit.
`gunart.gd:264`'s own claim — "1.025 on a cap and 1.110 on a side facet" — reproduces to four
decimals, which is the check on the arithmetic. Against `REST_PITCH` −0.13 and `REST_YAW` 0.2094
(`viewmodel.gd:178`, `:189`) the visible faces are the ones shaded 1.0705 / 1.0254 / 0.9953.
Minecraft's `FaceBakery.getShade` is top 1.0 / N-S 0.8 / E-W 0.6 / bottom 0.5 — 2:1, with opposing
faces **equal**, so no visible face is ever the dark one. TerraFirmaCraft reimplements the same
table independently. **This is the strongest single explanation on offer for "stack of
rectangles", and it is unmeasured.**

**F4 — The file's own account of the glow margin is internally inconsistent, so the "seven
percent" headroom is of unknown size.** Tier 1, and it is a live trap for F3.
`gunart.gd:266-271` computes the knife blade in **linear** (`blue 0.839 linear` → 0.860 on its
caps → "does not bloom"); `_tint`'s comment at `:670-674` computes the same colour in **display**
(0.925 undecoded → ×1.02541 = 0.949, **above** `lighting.gd`'s 0.92 threshold → it *does* bloom).
Both cannot be right. Constraint 6 territory: any FILL/KEY change must re-derive this against a
rendered frame, not against the comment.

**F36 — And `gunart.gd:266-271` is wrong about the Ray Gun as well, not only about the knife.**
Tier 1, arithmetic on the shipped constants and re-read. The comment claims "the Ray Gun's lens
core (#E8FFC0, green 1.0) and the Thundergun's emitters (#DFF9FF) clear 0.92 on every face". They
do not. `f` floors at `FILL` = 0.860 on −Y, +X and −Z (`:739`), and 1.0 × 0.860 = **0.860**, which
is below `lighting.gd:215`'s `GLOW_THRESHOLD` 0.92. The brightest channel of an emissive part
clears the threshold on the three *lit* faces (1.0705, 1.0254, 0.9953) and misses it on the other
three. So the parts that are meant to be emitting bloom on **half** their faces. This matters to
R1 directly: R1 moves the floor as well as the ceiling, and the margin it is spending is the
distance from 0.860 to 0.920 on the dark faces at least as much as the distance from 1.0254 up.
**M2 must sweep the Ray Gun's lens core and the Thundergun's emitters, not only the knife blade.**

**F5 — At ADS the player looks down the one axis that has no art in it.** Tier 1.
`ADS_CENTRE` (`viewmodel.gd:334`), `ADS_YAW` (`:336`) and `ADS_LEVEL` (`:372`) are all 1.0 — the
first draft cited all three to `:334-336` and `ADS_LEVEL` is 36 lines below that — so at full ADS the camera sits
in the caps' own plane `x=0`, both caps go edge-on, and the only faces visible are +Z rear edges —
each one flat. There is no rear sight, no charging handle, no stock comb, and the art space has no
vocabulary for one. **Anything that improves the ADS read has to add geometry along +Z.**

**F6 — There is no triangle budget pressure and the brief's "~70 triangles per weapon" is wrong.**
Tier 1, derived from `_extrude`'s own loops. Per-weapon body+slide, **hands included**: m1911 108,
olympia 132, m14 132, mp40 144, pm63 120, ak74u 144, stakeout 144, m16 144, rpk 180, chinalake 156,
raygun **264**, thundergun 324, knife 88. Sum **2080**, mean **160.0**. (The first draft printed
raygun 240 — its ten `ART` parts, 5 rects × 12 + 5 circles × 36 — and dropped the two hand boxes
every other row includes. `raygun` is in `ONE_HANDED` (`gunart.gd:311`) so `_hands` returns two
rows (`:527-536`) at 12 triangles each: 240 + 24 = 264. The arithmetic check is the sum: with 240
the thirteen rows total 2056 against the prose's 2080; with 264 they total exactly 2080.)
`M1-viewmodel-systems.md:36` and `:540` estimate ~72; the
shipped builder exceeds it by 1.5× to 4.5×. An 8× increase would still be under 3k for the largest
weapon. **What *is* bounded is `_measure`**: it is linear in corner count, so an 8× corner increase
takes 218,016 transformed points to 1.7 M in GDScript inside a ~5 s suite.

**F7 — Depth is cheap against the clip budget; length is not; the near plane is the binding
constraint.** Tier 2 — these are conservative analytic bounds on the committed
0.231884 / 0.201249 / 0.057540, not re-measurements. Doubling every part's and every hand's
half-depth raises `max_screen_radius` by at most 0.48 mm of 8.12 mm of headroom (5.9%), and
`max_corner_radius` to at most 0.2066 against 0.22. But the added `x` rotated through
`REST_YAW + SWAY_MAX` costs up to **1.38 mm of the 7.54 mm near-plane clearance, 18%**.

**The 0.48 mm figure is disputed and must not be quoted as headroom.** A reviewer re-derived
∂widest/∂x from the committed pair 0.201249 / 0.231884 at `ratio` 1.4476 and got a sensitivity
between roughly 0.38 and 0.99, which puts a doubling of the deepest gun part (4.00 → 8.00 art
units, δ = 4.2 mm) in a **1.5–4 mm** band, not 0.48 mm. Neither number is a measurement — the
research phase ran nothing — and the two derivations disagree by up to 8×. **M3 is the arbiter and
must run before any `DEPTH` table is committed.** Until it does, treat screen-radius headroom as
unknown rather than as 94% free.

**And the hands' `PROUD` exemption is not the hazard the first draft said it was.** The
precondition at `gunart.gd:524-526` is that the hand outlines "share no edge **line** with any
`ART` part" — a statement about the 2-D outline in the y-z plane. `_inflate` (`:611-644`) takes a
`PackedVector2Array` and a scalar and never sees `half`; `_extrude` (`:688-721`) uses `half` only
for the x coordinate. **Depth is orthogonal to that precondition and cannot falsify it.** The
conclusion (do not raise a gun part to the hands' depth) is right; the mechanism is **cap
coplanarity**, which is what `LAYER` exists to fix (`gunart.gd:190-200`). The hands sit at fixed
`HAND_HALF` = 5.0 and `HAND_HALF + LAYER` = 5.14 (`:529-535`) and do **not** ride the
`BASE_HALF + i·LAYER` ramp, so a gun part landing on either value z-fights its ±X caps against a
glove. Today no part can: `half` = 2.6 + i·0.14 with i ≤ 10 tops out at 4.00. An authored `DEPTH`
multiplier removes that accident, which is precisely why R2's constraint (b) is now a rule over
the `DEPTH` table and an assertion, not a comment.

**F8 — The chalk wall plaques are baked from a second copy of the art table and nothing asserts
they agree.** Tier 1. `tools/gen/targets.js:150-162` calls `anc.makeChalk(w.art, …)` against
`tools/gen/ancestor.generated.js`, which carries its own `const GUNART` at line 634. Change `ART`
and the wall-buy outline stops matching the weapon the player is handed, silently.

### The reload

**F9 — Only four of seven states have any distinct appearance, and neither IDLE nor FIRING is one
of them.** Tier 1, `viewmodel.gd:689-727`. RELOADING → `_dip` amplitude 1.0; RELOAD_SHELL → `_dip`
× `SHELL_SCALE` 0.35; SWAPPING → `_swap`; SPRINT_OUT → `_sprint`; EMPTY → `_locked` pins the slide
back. IDLE is the bare rest pose. **All per-shot motion is edge-driven off `Player.fired`**
(`:605-610`), which is why holding an automatic does not strobe.

**F10 — The reload is one `sin(rel·PI)` arc of the whole gun and represents no sub-object motion
of any kind.** Tier 1. 36.2 mm down, 6.4 mm right, +0.5 rad muzzle-up (`viewmodel.gd:285-296`),
transliterated from `html:3121-3128`. **It is identical for all thirteen weapons in the ancestor
too** — only the duration varies. The magazines exist in the art (mp40 part 2, ak74u part 2,
m16 part 3, rpk part 2) but are welded into the body `ArrayMesh` at build time, and so are both
gloved hands. There is no bolt-hold-open release distinct from an ordinary reload.

**F11 — The pump cycles once per reload sequence, not once per shell, and the signal to fix it
does not exist.** Tier 1. `weapon.gd:325-330` re-enters `RELOAD_SHELL` with itself, so `state_t`
sawtooths but the ordinal never changes — and `player._weapon_state` (:732-735) emits only on an
ordinal change. `viewmodel._on_weapon_state` (:586-603) cycles the slide on *entering* a reload
and on a bolt-lock release, and nowhere else. The only per-shell edge anywhere is the magazine
delta at `player.gd:764-772`, which plays `reload_in` and re-emits `weapon_changed` — and the
viewmodel's handler for that records key/pap and nothing else.

**F12 — BO1 disagrees with the port about which weapons reload shell-by-shell.** Tier 1 (shipped
T5 weapon assets), Tier 2 on provenance (see **Source index** — these come from a modding mirror,
diffed across five years of history). `segmentedReload` is **1 on the Stakeout and the China Lake
only**; the Olympia (`rottweil72_zm`) is 0 — a break-action loading both barrels in one 3.30 s
animation (3.90 s from empty). The port gives the Olympia `shells: true` (`weapons.gd:26`).
`weapons.gd:13-16` already records the shells flag as *new design rather than a restoration*
(the first draft cited `:16-19`; `:17` opens `DEFAULTS`),
which is the right posture; what it does not yet record is that the reference disagrees.

**F13 — A real segmented reload is start + N×shell + end, and the port has only the middle term.**
Tier 1. Stakeout: `reloadStartTime` 1.000, `reloadTime` 0.567/shell, `reloadEndTime` 0.767,
`reloadStartAdd` 1 (the first shell goes in during the *start* animation), `reloadAmmoAdd` 1.
China Lake: 2.000 / 1.000 / 1.100. So a Stakeout reload from empty is 1.000 + 5×0.567 + 0.767 =
**4.60 s**, and a one-shell top-up is 1.000 + 0.767 = **1.77 s** — not 0.57 s.
`weapon.gd:284-289` derives per-shell time as `reload / mag`, which makes the top-up as cheap as
any other shell. That asymmetry is the whole feel of a tube gun.

**F14 — BO1 does distinguish tactical from empty reloads, per weapon, with separate ammo-credit
moments.** Tier 1 for `reloadTime`/`reloadEmptyTime`, Tier 2 for the `addTime` columns (the
modding repo's changelog names a global retune of exactly those two fields). M1911 1.63/1.80,
Olympia 3.30/3.90, M14 2.40/3.45, MP40 2.30/2.90, PM63 2.05/2.85, AK-74u 2.10/2.80, M16 2.03/2.36,
RPK 4.00/5.50. Two exceptions worth knowing: the Ray Gun (3.00 tactical / **2.00** empty) and the
Thundergun (2.10/**2.00**) invert the rule, and the Thundergun carries `noPartialReload = 1` —
it refuses a top-up entirely. M1-viewmodel-systems.md's Coverage Gap 1 stands and now stands wider:
none of Half-Life, CS 1.6, OpenSpades or Quake 3 distinguishes them either.

**F15 — Interrupting a segmented reload has a 40% ignore window nobody documents.** Tier 1
(decompiled T5/GoldSrc-lineage engine source), single-sourced. In `PM_Weapon_Reload*`:
`MY_RELOADSTART_INTERUPT_IGNORE_FRAC = 0.4f` — a fire press in the first 40% of the *start*
animation is ignored outright. Past that, firing sets `WEAPON_RELOAD_START_INTERUPT` and the
weapon must still play `reloadEndTime` before it can shoot. Shells already inserted are kept,
because the credit is per segment. Half-Life's `CShotgun` (`shotgun.cpp:265`) is the minimal
version of the same machine: one integer `m_fInSpecialReload`, ammo credited the instant each
shell goes in, and cancel implemented as `m_fInSpecialReload = 0` inside `PrimaryAttack` — the
"keep the shells" behaviour falls out of the structure rather than needing a special case. **This
is what the port already does**, and it is right.

**F16 — Speed Cola is exactly 2× and the port already has it exactly right.** Tier 1 engine
source + Tier 3 dvar default. The engine divides the weapon clock by `perk_weapReloadMultiplier`
(default 0.5) in **every** reload state including start, per-shell and end. `game_state.gd:53`
`SPEED_RELOAD_MULT := 0.5`. Leave it; add the provenance comment. Note the consequence for F13:
a Speed Cola Stakeout reload from empty is 2.30 s, not "the per-shell time halved".

### The bullet pattern

**F17 — BO1 spread is a growing bloom AND a fixed floor: one 0–255 scalar lerping between a
per-stance minimum cone and a maximum cone.** Tier 1, three functions read verbatim from a
decompiled T5 tree whose asserts still carry Treyarch's build path.
`BG_GetSpreadForWeapon` lerps min/max by view height (continuous, not a stance flag).
`PM_AdjustAimSpreadScale` integrates: `decrease = hipSpreadDecayRate × frametime`;
`increase = turn term + hipSpreadMoveAdd × |v| / speed` (only while a movement key is held and
speed exceeds `bg_aimSpreadMoveSpeedThreshold` = 11 units/s ≈ 0.28 m/s), **and the two are mutually
exclusive** — `if (increase <= 0) scale -= decrease×255; else scale += increase×255`.
`PM_Weapon_AddFiringAimSpreadScale` adds `hipSpreadFireAdd × 255` per shot and **adds nothing while
fully aimed down sight**. Cone = `lerp(min, max, scale/255)` hip, `lerp(adsSpread, max, scale/255)`
sighted.

**Units: OPEN ASSUMPTION, not a fact, and it is a silent factor of two on every number in F18.**
The first draft asserted "degrees from screen centre — a half-angle" flat. The three functions
named above compute and carry the value; **none of them turns it into a bullet direction**, and the
call site that does — the one function where a half-angle and a full cone become distinguishable —
was not read, and is not among the KisakBlack files listed in Source index row 10. Until someone
quotes that function with a file and a line, treat the half-angle reading as **Tier 2 inference**:
it is the reading consistent with `adsSpread = 0` meaning a perfectly centred sighted shot, and
with the ±10° view-kick clamp being described in the same units, but neither of those is the call
site. **If it is a full cone, every number in F18 is 2× too large and R3's widening factors halve.**
Closing this is the single cheapest thing that could change R3's size, and it must be closed before
R3's numbers are committed.

**F18 — Per-weapon BO1 spread numbers.** Tier 1 (shipped assets, parsed mechanically, spread
fields byte-identical across five years of the mirror's history for the six weapons diffed).
Degrees: StandMin/DuckedMin/ProneMin | StandMax/DuckedMax/ProneMax | FireAdd | MoveAdd | DecayRate
| adsSpread.

| weapon | min (S/D/P) | max (S/D/P) | FireAdd | MoveAdd | Decay | adsSpread |
|---|---|---|---|---|---|---|
| M1911 | 3 / 2.5 / 2 | 6 / 5 / 4 | 1.00 | 4.5 | 4.00 | 0 |
| Olympia | 5 / 5 / 5 | 8 / 7 / 6 | 0.60 | 2.0 | 4.00 | 4.25 † |
| M14 | 3 / 2.5 / 2 | 7 / 6 / 5 | 1.00 | 5.0 | 5.00 | 0 |
| MP40 | 2 / 1.75 / 1.5 | 5 / 4.5 / 4 | 0.52 | 4.0 | 4.00 | 0 |
| PM63 | 2 / 1.75 / 1.5 | 5 / 4.5 / 4 | 0.52 | 4.0 | 4.00 | 0 |
| AK-74u | 2 / 1.75 / 1.5 | 5 / 4.5 / 4 | 0.60 | 5.0 | 4.00 | 0 |
| Stakeout | 4 / 4 / 4 | 7 / 6 / 5 | 0.60 | 2.0 | 4.00 | 3 † |
| M16 | 3 / 2.5 / 2 | 7 / 6 / 5 | 0.60 | 5.0 | 4.00 | 0 |
| RPK | 2.5 / 2 / 1.5 | 7 / 5 / 5 | 0.60 | 5.0 | 4.00 | 0 |
| China Lake | 5 / 3.5 / 2 | 6 / 6 / 6 | 0.40 | 2.3 | 2.50 | 1.7 |
| Ray Gun | 1 / 1 / 1 | 2 / 2 / 2 | 1.00 | 0.5 | 3.25 | 0 |
| Thundergun | 2 / 1 / 1 | 4 / 3 / 2 | 1.00 | 0.5 | 2.25 | 0 |

† known modified by the mirror ("Shotguns: Decreased spread when aiming"); the vanilla values are
**higher** by an unknown amount. Do not treat those two cells as canon.

**F18b — What those numbers do to the shipped roster. Nobody had done this arithmetic, and it is
the difference between a fidelity restoration and a wholesale accuracy rebalance.** Tier 1
arithmetic on Tier 1 constants, both sides re-read: `weapons.gd:25-36` for `spread`,
`player.gd:872` `return deg_to_rad(s) * 0.5` for the conversion. The port's `spread` is a **full
cone in degrees**, so today's standing hip **half-angle is `spread / 2`**.

| weapon | shipped `spread` | shipped half-angle ° | BO1 StandMin ° | × | BO1 StandMax ° | × |
|---|---|---|---|---|---|---|
| M1911 | 0.85 | 0.425 | 3 | **7.1** | 6 | **14.1** |
| Olympia | 5.4 | 2.700 | 5 | 1.9 | 8 | 3.0 |
| M14 | 0.6 | 0.300 | 3 | **10.0** | 7 | **23.3** |
| MP40 | 1.7 | 0.850 | 2 | 2.4 | 5 | 5.9 |
| PM63 | 2.0 | 1.000 | 2 | 2.0 | 5 | 5.0 |
| AK-74u | 1.5 | 0.750 | 2 | 2.7 | 5 | 6.7 |
| Stakeout | 4.6 | 2.300 | 4 | 1.7 | 7 | 3.0 |
| M16 | 1.15 | 0.575 | 3 | **5.2** | 7 | **12.2** |
| RPK | 1.9 | 0.950 | 2.5 | 2.6 | 7 | 7.4 |
| China Lake | 0.4 | 0.200 | 5 | **25.0** | 6 | **30.0** |
| Ray Gun | 0.7 | 0.350 | 1 | 2.9 | 2 | 5.7 |
| Thundergun | 0.2 | 0.100 | 2 | 20.0 | 4 | 40.0 | 

Thundergun's row is dead data (`_cone_blast` returns before any spread code). **And the shipped
column is the ancestor's, unchanged** — `kriegsnacht.html:1459-1470` carries the identical twelve
`spread` and twelve `kick` values, re-read. That is itself a finding: the port has never made a
spread decision of its own, so R3 is the first one.

**Hit probability, which is what the multiplier actually means.** Cone radius at range `d` is
`d·tan(half)`; a zombie is `HIT_RADIUS` 0.30 (`zombie.gd:94`); the disc is uniform in area, so the
hit fraction is `min(1, (0.30 / (d·tan(half)))²)`. Standing, hip, M14:

| | 5 m | 10 m | 26 m (its `range`) |
|---|---|---|---|
| shipped 0.30° | 100% | 100% | 100% |
| BO1 floor 3° | 100% | 33% | 4.8% |
| BO1 ceiling 7° | 21% | 6.0% | 0.9% |

**A standing M14 that hits every shot at its stated range today would miss 19 of every 20 at that
range under BO1's floor.** This is `Bottom line`'s own "multiply every one of them by ten" example,
arriving as a recommendation. It may still be the right call — BO1's M14 really is that
inaccurate at range, and the reference wins — but it is a **balance** decision and R3 now says so
out loud rather than calling it a restoration.

**One nuance the multiplier overstates.** While *moving*, the aim already carries the bob's
±0.010 rad = 0.573° of sway on the same aim-bearing node (F23), which is nearly 2× the M14's whole
shipped half-angle, so the felt change while walking is much smaller than the table's ×10.
Standing still, `amp` is 0 (`player.gd:709-710`) and there is no bob at all, so the standing-still
row above is exact. That asymmetry is one more reason M5 has to be a measurement.

**F18c — `kick`, for the same reason.** R4 item 3 proposes a per-weapon bracket and the column it
would replace was never printed. Shipped `kick` (`weapons.gd:25-36`, identical to
`kriegsnacht.html:1459-1470`): m1911 1.3, olympia 3.4, m14 2.1, mp40 1.1, pm63 0.9, ak74u 1.4,
stakeout 3.0, m16 **1.5**, rpk **1.5**, chinalake 3.6, raygun 2.0, thundergun 4.2. Range 0.9 to
4.2, ratio 4.67. **Two weapons tie at 1.5**, which is why A3's "strictly ordered by kick" claim
could never have passed. And note against F20: BO1 gives the **M1911 no gun kick at all**, where
the port gives it 1.3 — so a faithful bracket is not a rescaling of this column.

Derived: full-bloom-to-floor decay time is `1 / DecayRate` — 0.25 s for most of the roster, 0.20 s
M14, 0.40 s China Lake. Shots to saturate is `ceil(1 / FireAdd)` — **one** for M1911/M14/Ray
Gun/Thundergun, two for the SMGs and rifles, three for the China Lake. Only the Ray Gun and
Thundergun have a nonzero `hipSpreadTurnAdd` (0.25); every conventional gun ignores how fast you
turn. Both shotguns' min is stance-invariant.

**F19 — There is no first-shot accuracy bonus in BO1's spread, and the recoil version of it is
inert on this roster.** Tier 1. No first-shot term exists in either spread function. What people
call BO1 pistol first-shot accuracy is a consequence of ordering: the fire-add runs *after* the
round leaves, so with `FireAdd = 1.0` a standing M1911's first shot is a 3° cone and every
subsequent one is 6°. The engine *does* have `weaponRestrictKickTime` and a
`GunKickReducedKickPercent`, but `hipGunKickReducedKickBullets` and its ADS twin are **0 on all
twelve**, so the window never opens. **A first-shot bonus here would be our design decision, not
a restoration.**

**F20 — BO1 recoil is a per-shot uniform draw fed as a velocity into a spring that accelerates
back to the original aim. It is not a memorised pattern.** Tier 1, corroborated independently by
DenKirson's reverse-engineering (Tier 3). `BG_WeaponFireRecoil` **assigns** (not accumulates)
`kickAVel[0] = -(Random()×(PitchMax-PitchMin) + PitchMin)`, likewise yaw, and
`kickAVel[2] = -0.5 × kickAVel[1]` — **roll is exactly half the yaw, negated**. `CG_KickAngles`
integrates in ≤5 ms slices: accelerate toward zero at `ViewKickCenterSpeed` deg/s², damp the
return leg to **0.06** of the outbound rate, snap on overshoot, clamp at ±10°. The reason BO1 guns
*feel* patterned is asymmetric yaw boxes — DenKirson: "if a weapon kicks left 10 and right 60, the
kick will almost always be to the right". **One disagreement:** DenKirson says the return runs at
1/16 (0.0625); the shipped constant is 0.06. Trust 0.06.

Selected hip view kick (deg/s | deg/s²): MP40 pitch −44…100, yaw 100…−100, centre **2538** (the
wildest box in the roster, bought back with by far the fastest recentre); Stakeout pitch 95…100,
yaw −75…−85 (**entirely one-sided — always left**), centre **800** (the slowest); M14 40…80,
±40, 1400; RPK 15…60, ±70, 1900. The M1911 has **no gun kick at all** (all four gun-kick fields 0).

**F21 — The port's view kick is ballistically live and points down.** Tier 1, re-read.
`RecoilPivot` sits between Head and Camera3D; `_hitscan` reads `_cam.global_transform.basis`
(`player.gd:877-879`); `player.gd:718` writes `_recoil_pivot.rotation = Vector3(_kick + slow, 0, roll)`;
`player.gd:834` does `_kick_v -=`. Positive `rotation.x` is look-up (`player.gd:426`:
`_head.rotation.x - event.relative.y * sens`). So the aim **dips** under fire — while
`viewmodel.gd:608` does `_kick_v +=` with the same constants, and `viewmodel.gd:268-270` comments
"The gun drops and the muzzle rises, which together are the weapon rocking back about the hand"
over `KICK_DOWN`/`KICK_PITCH` (`:271-272`), whose consumers are `:797` and `:803`. (The first
draft cited the comment to `:797-803`, which is the code, not the comment.) The two halves of one
recoil are 180° out of phase.
**In the ancestor this did not matter**: `isHeadshot` rebuilds the horizon as `H*0.5 + P.pitch`
(html:2467) with no `viewKick` term, so the ancestor's kick was purely cosmetic. Here it is not.

**F22 — The player's spring has no clamp; the viewmodel's does.** Tier 1. `viewmodel.gd:266`
`KICK_MAX := 1.2` with a comment that says exactly why ("an MP40 puts 1.1 into the velocity every
68 ms, faster than the spring bleeds it, so sustained fire climbs"), enforced at `:686`.
`player.gd` has no equivalent. **The aim excursion under sustained MP40 fire is unbounded by
construction**, and the two springs therefore diverge under exactly the load the comment describes.

**F23 — The view bob moves the aim, and it is larger than most weapons' entire cone.** Tier 1.
`player.gd:717-718` puts `slow = sin(_bob_phase*BOB_SLOW)*amp*0.5` on the same aim-bearing node,
with `amp = 0.020` walking. That is ±0.010 rad of aim sway against the M14's whole hip half-angle
of 0.00524 rad. **For precise weapons the dominant accuracy term is the bob, not `spread`.** And
`Settings.reduce_motion` zeroes it (`:709`) while damping the kick to 0.35 (`:116`, `:834`) — so
the accessibility toggle is an aim buff, twice over, and nothing asserts it.

**F24 — The port's cone is half the ancestor's and the departure is unrecorded.** Tier 1, both
sides re-read. `html:2568` is `(Math.random()-0.5)*spreadDeg*0.0175*2` → max deviation
±`deg_to_rad(spread)`. `player.gd:872` returns `deg_to_rad(s)*0.5` and `:887` uses it undivided as
the max radius → ±`deg_to_rad(spread)*0.5`. The **ratio** between the pellet and projectile arms is
faithful and commented; the **absolute** is not, and nothing asserts it. Caveat: the ancestor is
1-D and the port is a 2-D disc, so per-axis σ is `R/2` here against `R/√3` there — the port is
tighter by ≈2.3× per axis, not exactly 2×.

**F25 — The suite covers the ADS multiplier and nothing else about spread, and it covers it by
recomputing the implementation.** Tier 1. Grepping `scripts/dev/` for `_spread_rad` returns two
hits, both in `checks/projectiles.gd` (:559, :577), feeding one assertion
(`v.near(aim_spread, hip_spread * Player.ADS_SPREAD, 0.0001)`, :582-585). Multiply every `spread`
in the table by ten and both sides move identically. `_moving`, `is_downed`, the disc distribution,
the `sqrt()` weighting and the absolute cone are all unasserted, and `_kick`/`_kick_v`/`KICK_SPRING`
/`MAX_SHOTS_PER_TICK` appear nowhere in `scripts/dev/` at all.

**F35 — "Shell patterns" has a second reading and this document took the first one silently.
The pellet pattern does not exist, and the shotgun is a step function.** Tier 1.
`player.gd:849-850` is `for i in int(def.pellets): _hitscan(def)` — six *independent* draws, each
re-entering `_spread_rad` and sampling the whole cone afresh (`:884-888`). There is no pattern, no
centre pellet, no per-pellet damage or range differentiation, and `range` is a hard cliff with no
falloff (a `_hitscan` past it emits nothing, `:899-900`). Arithmetic: the Olympia's 2.70° half-angle
gives a disc radius of 0.141 m at 3 m — inside a zombie's 0.30 m `HIT_RADIUS`, so all six pellets
land — and 0.613 m at its 13.0 m `range`, where the expected count is 6·(0.30/0.613)² = **1.4
pellets**, and at 13.01 m it is zero. That cliff is what a player feels as "shotgun pattern", and
this document's brass section does not touch it. BO1's own per-shotgun base `shotCount` was in
hand — the Pack-a-Punch note quotes "Olympia → 8→12 pellets" — and was never reported against the
port's flat 6/6. See R12 for the ruling.

### The brass

**F26 — Neither the ancestor nor the port has shell casings in any form, including dead code.**
Tier 1, and the grep in the first draft did not reproduce. Run as written —
`grep -n -i -E 'casing|brass|eject|spent' kriegsnacht.html` — it returns **zero lines**, not "CSS
`Impact` font stacks". The three cited hits need `shell` in the alternation:
`grep -n -i -E 'casing|brass|eject|spent|shell'` returns exactly `:1455`, `:1460`, `:1465`, all
three the `shells` **reload** flag. `Impact` occurs 4 times in the file and on none of those lines.
File is 3476 lines. **The corrected result is stronger than the one first reported**: four
casing-specific terms match nothing at all in the ancestor. Nothing in `scripts/` either.
**Brass is 100% invented against the BO1 reference and must be commented as a deliberate
addition, not a restoration.**

**F27 — BO1 ships four casing effects for the whole roster and four weapons eject nothing.**
Tier 1 (weapon-file fields). `weapon/shellejects/fx_pistol` → M1911, MP40, PM63, AK-74u;
`fx_rifle` → M14, M16; `fx_shotgun` → Stakeout; `fx_saw` → RPK; **empty** → Olympia, China Lake,
Ray Gun, Thundergun. Every `viewLastShotEjectEffect` is empty. The spawn point is a model tag
(`TAG_SHELL`), and **there is no offset, velocity or spin field anywhere in the WEAPONFILE
format** — an exhaustive key scan of all 14 files returns only the four Effect keys. The physics
lives in a compiled `.efx` that is not in any public rawfile dump. **Anyone quoting BO1 casing
velocities is guessing.**

**F28 — Four complete casing systems exist outside Godot and they converge.** Tier 1 (all four
read as source). Every one of them: bounce-scaled velocity, an explicit rest threshold, lying flat
on the ground (zero pitch and roll), and a timed sink or fade rather than a pop.

> **UNITS, stated once because it is a silent factor of forty.** Every number below is in its
> **source engine's own units** and none of them is metres. This project is metric throughout —
> `Player.RADIUS` 0.24, `SPEED` 3.15. **Ported literally, ioq3's casing leaves the gun at 100 m/s
> and spawns 0.6 m above the shooter's eye.** The conversions that are safe to state:
>
> - **ioq3 / Quake lineage — 1 unit ≈ 1 inch = 0.0254 m**, the id convention. Offset
>   `{8, -4, 24}` → **{0.203, −0.102, 0.610} m**; velocity `{0, −50±40, 100±50}` → **{0,
>   −1.27±1.02, 2.54±1.27} m/s**. The cross-check that makes this trustworthy: 2.5 m/s of upward
>   ejection is the right order for a real casing, where 100 m/s is not. Angular rates
>   (`{2000, 1000, 0}` deg/s) are unitless in this sense and port directly.
> - **Half-Life / GoldSrc — same scale.** `right×(50..70) + up×(100..150) + forward×25` →
>   **right×(1.27…1.78) + up×(2.54…3.81) + forward×0.635 m/s**; offsets 20/−12/4 → **0.508 /
>   −0.305 / 0.102 m**. The *structural* finding — casings inherit the player's velocity — is
>   unit-free and is the one thing to copy without argument.
> - **OpenSpades — DO NOT CONVERT.** Its unit is a voxel block whose metric size this project has
>   not established, and the two plausible readings (Quake-inch vs block ≈ 0.7 m) put its
>   "gravity 32/s²" anywhere between 0.8 and 23 m/s². A reviewer offered 0.81 m/s²; that rests on
>   assuming the Quake convention for a Voxlap-derived game and **is not adopted here**. Take
>   OpenSpades for its *structure* — velocity along `flyDir`, tumble about `cross(-up, flyDir)`,
>   ×0.2 on bounce, re-orthonormalise flat at rest — and take none of its scalars.
>
> R7's bracket is stated in **metres and metres per second**, derived from the ioq3 column above,
> and every one of them is a starting point to be tuned against a frame.

- **ioq3** `cg_weapons.c:31` — spawn offset `{8, -4, 24}` in the shooter's own axes; velocity
  `{0, -50±40, 100±50}` (always to the shooter's right); spin `{2000, 1000, 0}` deg/s from a random
  0–31° initial orientation; life 2500–3125 ms; `bounceFactor` 0.4; a deliberate 0–15 ms sub-frame
  de-sync so a burst is not parallel. Shotgun (`:103`): **two** casings, one each side, life
  7500–10000 ms. Pool of 512, oldest recycled; swept trace per frame; 1000 ms sink at end of life.
- **Half-Life** `ev_common.cpp:152` — the detail hobby implementations miss:
  `ShellVelocity = player_velocity + right×(50..70) + up×(100..150) + forward×25`. **Casings
  inherit the player's velocity.** Per-weapon offsets `forward/up/right`: pistols and SMGs
  20/−12/4, shotgun 32/−12/6. Life 2.5 s. Spin (Xash reimplementation, Tier 3):
  pitch ±512, yaw and roll ±255 deg/s. Per-casing variation is a **random submodel**, not a tint.
- **OpenSpades** `GunCasing.cpp` — no rigid body. `vel = flyDir×10`, `rotSpeed = 40` rad/s about
  `cross(-up, flyDir)` (perpendicular to flight, which is what makes it tumble rather than spin),
  gravity 32/s². On bounce: `vel *= 0.2`, `rotSpeed *= 0.2`, fresh random axis, ±0.1 jitter. Rests
  below 0.5 speed, re-orthonormalises flat, sinks after 1 s, gone at 2 s. **The shotgun is
  deliberately omitted** — "don't want to show shotgun casing because it isn't ejected when
  firing".
- **Xonotic** `casings.qc` — client-side only, gated on a cvar, hard global count cap
  (`LimitedChildrenRubble`), alpha fade over the final second, physics on a **decoupled substep
  rate** independent of frame rate, and deletion if the trace starts solid (gun clipping a wall).

**F29 — `fx.gd` is already the right shape for this, and its one absolute rule is no `Rng` at
all.** Tier 1, `fx.gd:29-34` — *"Nothing here may draw from an `Rng` stream — not even
`Rng.VISUAL`… there is not a single `randf` below."* Variation comes from `_shot_no` (`:864-872`,
already incremented per shot) and `_hash01` (`:847-859`). `verify.gd:1005-1017` asserts it over
fifty impacts against all six streams — **but it drives `impact` and `_on_surface_impact` only, so
a casing hung off `fired` would slip past it while breaking the file's stated contract.**
`_hash01` is the wrong tool here: it quantises to the centimetre, and a standing player firing an
automatic ejects from the same centimetre every shot. The **counter**, not the hash.

**F30 — MultiMesh per-instance colour and custom data do work on gl_compatibility; particles
cannot tumble a casing.** Tier 1, engine source. `drivers/gles3/shaders/scene.glsl:164` declares
`instance_color_custom_data` under `#ifdef USE_INSTANCING` and unpacks both at `:653` and `:688`
via `unpackHalf2x16` — 16-bit halves, so ~3 significant digits, fine for a 0–1 factor or a small
index, **not** fine for a world coordinate. The `#else vec4 instance_custom = vec4(0.0)` at `:692`
is exactly why CLAUDE.md's "INSTANCE_CUSTOM is dead on a plain MeshInstance3D" is true — the
constraint is about non-instanced draws and a MultiMesh lifts it. Against that:
`ParticleProcessMaterial`'s `angular_velocity` is documented as applying **only** under
`particle_flag_rotate_y`, `disable_z`, or a billboard material, and `emit_particle()` is
unavailable on Compatibility. In GLES3 `particles.glsl` the SDF-collider branch is a literal empty
`{}`.

**F31 — Three ordering traps will each cost an afternoon.** Tier 1. (a) `use_colors` and
`use_custom_data` must be set **before** `instance_count`, or they silently fail. `fx.gd:773-784`
documents this **for `transform_format` and `use_colors` only**, and `_multimesh()` sets exactly
those two — it **never touches `use_custom_data`**, and `grep -rn 'use_custom_data|set_instance_custom_data' scripts/`
returns **no hits anywhere in the repo**. So following the first draft's "use it rather than
hand-rolling" gives silently-zero custom data, which is the very failure this finding warns about.
Two consequences for R7: build through **`_ring()`** (`fx.gd:746-758`), not `_multimesh()` —
`_ring` is what sets `custom_aabb` (`:756`), calls `add_child` (`:757`) and turns off shadows and
GI, and `_multimesh()` returns a bare `MultiMesh` with none of that. And if per-instance custom
data is genuinely wanted, `_multimesh()` must gain `mm.use_custom_data = true` **before**
`instance_count` — a change to a **shared** helper that resets every existing ring's buffer, so it
is a hunk with three other callers, not a free ride. **R7 does not need it**: a per-weapon tint
fits in the colour channel `_multimesh()` already enables.
(b) `custom_aabb` must be set, twice over: `mesh_storage.cpp:1755` skips the O(n) AABB rebuild
entirely when it is non-default, **and** `fx.gd:761-767` records that a ring whose instances are
all retired to a zero basis has a point-sized AABB at the origin, which is frustum-culled, which
means the warm probe never rasterises and compiles nothing. (c) Size an instance by rebuilding
the basis from its **columns**, never `Basis.scaled()`, which scales world axes and shears —
`fx.gd:830-834` and `:892-895` both document the same trap.

**F32 — Registration is asymmetric: one omission is caught, the other is not.** Tier 1. A new
material missing from `fx.materials()` (`:920-928`) fails `verify.gd:1050`. A new MultiMesh missing
from `fx.warm()` (`:944-990`) is caught by **nothing**, and costs a main-thread GLSL compile of the
`USE_INSTANCING` variant on the first trigger pull of every browser session — because
`shader_warmup.gd` draws on a plain `MeshInstance3D` and structurally cannot reach it.

**F33 — A world-space casing spawned at the real ejection port will not line up with the gun.**
Tier 1. The viewmodel is drawn through a 55° projection against the world's 74°, ratio 1.4476;
`viewmodel.flash_anchor()` (`:986-1006`) exists solely to undo that and works for a **point**, not
a mesh. `fired` carries a fixed 0.35 m camera-axis point (`player.gd:837`), not the muzzle.

**F34 — The rate is the sizing constraint, and it is worse than it looks.** Tier 1 arithmetic on
Tier 1 constants. PM63 1000 rpm × Double Tap 1.34 = **22.3 shots/s**. At the prior research's
1.2 s despawn that is ~27 live casings — more bodies than the 24 zombies `project.godot:154-157`
measured at 1.26 ms/tick under Jolt, **plus 22 broadphase inserts and 22 removes per second that
the zombie figure does not include**, on the single web thread at a fixed 60 Hz. A 16-slot ring
wraps in 0.72 s. Also: 14 positional voices exist (`sfx.gd:22`) with eviction by largest playback
position, so a per-shot tink would evict every other 3D voice in the game inside a second.

### Where the repo and the world disagree

| # | Repo says | World says | Winner |
|---|---|---|---|
| 1 | Olympia reloads shell-by-shell (`weapons.gd:26`) | BO1 `segmentedReload = 0`; break-action, 3.30 s | **BO1.** Reference wins. Either change it or record the departure. |
| 2 | Per-shell time is `reload / mag` (`weapon.gd:284-289`) | start + N×shell + end, first shell credited during start | **BO1**, and the asymmetry is the point. |
| 3 | View kick pitches down (`player.gd:834`) | BO1 kicks up; the ancestor also kicks down (`html:1748`) | **BO1.** Ancestor is evidence, not authority. |
| 4 | Double Tap = 1.34 rpm **and** 1.15 damage (`game_state.gd:54-55`) | BO1 Double Tap is 1/0.75 = 1.3333 fire rate and **nothing else**; the damage bonus is BO2's Double Tap 2.0. The ancestor did a third thing — 0.94 kick reduction (`html:2525`) | **BO1** on the number; all three sources disagree, so this is exactly the case the record-the-departure rule exists for. |
| 5 | `_measure`'s 218,016 points; 158 triangles/weapon mean | `M1-viewmodel-systems.md:36` estimates ~72 triangles/weapon | **The shipped builder.** M1's estimate predates it. |
| 6 | CLAUDE.md: spread on VISUAL is "left alone because changing it moves every sim baseline" | `balance_sim.gd` uses a flat `--sim-accuracy` on a private `RandomNumberGenerator` (`:93-100`, `:119`, `:290`); `_spread_rad` appears nowhere in it | **The auditor.** The conclusion (do not move it) stands; the stated reason does not. What it would actually break is seeded-run replay and the `raygun` frames row. |

---

## What BO1 actually does

The target, tagged. **Fact** = read out of a shipped asset or engine source. **Measurement** =
derived arithmetic on those. **Folklore** = community consensus with no primary behind it.

- **Spread is two systems, not one** (fact): a deterministic per-stance floor and ceiling, and a
  0–255 bloom scalar between them. Firing adds; moving adds; standing still decays; ADS is a hard
  floor that firing cannot raise.
- **Recoil is a third, independent system** (fact): a per-shot uniform draw in a rectangle, applied
  as an angular *velocity*, integrated against a constant acceleration back to the original aim,
  clamped at ±10°, with the return leg at 0.06 of the outbound rate and roll at −½ yaw.
- **CS:GO's five-number spray-pattern format exists** (fact — the shipped `weapons.vdata` carries
  `m_nRecoilSeed = 223`, `m_flRecoilAngleVariance = 70`, `m_flRecoilMagnitude = 30`,
  `m_flRecoilMagnitudeVariance = 0` for the AK-47) **but BO1 does not use it** (fact). Do not import
  it.
- **Decay times** (measurement, `1 / DecayRate`): 0.25 s for most of the roster; 0.20 s M14;
  0.31 s Ray Gun; 0.40 s China Lake; 0.44 s Thundergun.
- **Shots to saturate** (measurement, `ceil(1 / FireAdd)`): 1 for M1911/M14/Ray Gun/Thundergun;
  2 for MP40/PM63/AK-74u/M16/RPK/both shotguns; 3 for the China Lake.
- **Headshot multipliers are per weapon and enormous** (fact, `loc*Multiplier` fields — this closes
  `R4-canon-numbers.md`'s Coverage Gap 3): SMGs and rifles **4×**; M14 and RPK **3×**; M1911 3.5×;
  Ray Gun 4× head but **5× neck**; **both shotguns and the China Lake 1× — no headshot at all**.
- **Fire type**: the M16 in BO1 Zombies is a **3-round burst** (fact); the port has `auto: true`.
  The M14 is single-shot.
- **Ammo is counted in magazines** (fact — `ammoCountClipRelative = 1` on every ZM bullet weapon),
  which is why the reserve figures are round. AK-74u is **20/160** and the PM63 is **20** at
  937 rpm — both independently confirmed by the Nazi Zombies wiki against my prior and against the
  port's 30/270 and 25/200. The 30-round AK-74u is a BO2/BO3 figure.
- **Pack-a-Punch is a hand-authored second asset per weapon, not a formula** (fact): M1911 → 60×
  damage and a 6-round magazine (Mustang & Sally); Olympia → 8→12 pellets and 120→300; AK-74u →
  1.58× damage and a 40-round magazine. The port's flat `dmg×2.6 / mag×1.5 / reload×0.88` is an
  approximation, and a reasonable one — **out of scope for this package**, noted so nobody
  "discovers" it later.
- **No first-shot spread bonus** (fact); the apparent one is an ordering consequence (F19).
- **No recoil pattern to memorise** (fact); the apparent one is asymmetric yaw boxes (folklore
  explanation, fact mechanism).
- **Shell ejection physics: unknown** (gap). The weapon files name an effect asset and nothing
  else, and the `.efx` is not public.

---

## The style contract

**"Keep the voxel style" was the only stylistic constraint on this brief and the first draft never
defined it, never used it as a decision criterion, and never bounded it.** The word appeared twice,
both times incidentally. That is a real gap: delete the constraint from the request and almost
nothing in the first draft changed. Stated here as a **testable rule**, so R1 and R2's rejections
can be re-run against it and so a reviewer can say a proposal is off-style without arguing about
taste.

**What the pipeline actually is** (Tier 1, `gunart.gd`): each part is **one convex 2-D outline in
the y-z plane, swept along model +X** between `x = ±half` (`_extrude`, `:688-721`) — two cap fans
and one quad per outline edge. Depth is a scalar per part. There is no UV, no index buffer, no
smooth normal, no per-part z-offset. Shading is **one flat value per face**, baked into the vertex
colour by a single dot product (`_tri`, `:739-744`). This is a **sprite-extrusion** pipeline, not a
voxel one — the same shape as Minecraft's `ItemModelGenerator`, which extrudes an item sprite into
a 1/16-block plate, which is the closest published precedent to this file and which the first
draft left sitting unused in a source-index row.

**The contract, as five rules an implementer can check:**

1. **Rectangular prisms and extruded discs only.** No cylinder about the barrel axis, no sphere, no
   free-form mesh. A part is one convex outline swept along X, and `_part_poly` stays the single
   geometry source.
2. **No bevels, no chamfers, no rounded corners.** Every face is either a ±X cap or a quad raised
   on one outline edge.
3. **Flat shading only, one value per face, no interpolation across a face and no smooth normals.**
   This is what makes R1 a style-*preserving* change: a per-axis face ramp is more voxel-like than
   the dot-product key light it replaces, not less.
4. **No outline, no rim, no post effect that treats the weapon differently from the room.** This is
   the rule that already rejected the inverted hull, on style rather than on cost.
5. **Depth is quantised.** Authored depths come from a small table of multipliers on `BASE_HALF`,
   not from arbitrary floats, and the `+ i·LAYER` tiebreak survives.

**Where this changes the first draft's conclusions.** R1's Minecraft face ramp **is** the voxel
move, and the document never said so — it argued the case on contrast alone. The bevel rejection
(R1) and the cylinder rejection (R2) were both argued on *cost*; under rules 1 and 2 they are
**style** rejections first and cost rejections second, which is a stronger and cheaper argument.
And rule 1 is what makes R10 safe: adding a rear sight is three more rects, which is exactly what
the style permits, where a modelled sight aperture is not.

**What the contract does not license.** It is not an argument for keeping the guns flat. A voxel
weapon in any of the surveyed lineages is a *stack of boxes with visibly different depths*; this
one is a stack of boxes whose depths are assigned by draw index (F1). R2 is the change that makes
the style read as itself.

---

## Recommendations

Ordered by value per unit of risk. R1–R3 are the package; R4–R7 are the rest of it; R8 is the
cut list; R9–R12 were added after review and R9 is not optional.

### R1 — Widen the baked face bracket before touching any geometry

**Decision.** Replace `_tri`'s single directional dot product with a per-face value that separates
the three visible groups by materially more than 7.5%, measured against a rendered frame, and
keep the mean near today's so the tonemap and glow behaviour do not move.

**Rationale.** F3. It is one expression in one function, costs zero triangles, zero corners, zero
draw calls and zero clip budget, and it is the only proposal in this document that is invisible to
`_measure()` and therefore cannot break the no-clip guarantee. Every blocky-FPS lineage read —
Minecraft, TerraFirmaCraft, and by implication the whole modding corpus that copies them — uses a
2:1 axis ramp with **opposing faces equal**, so no visible face is ever the dark one. A dot-product
key light necessarily puts the floor value on a face somewhere, and here it puts it on three of the
six. Patrick Sutton (BO4 weapon artist, Tier 3) states the professional rule as three values at
roughly 70-20-10; we currently have one value wearing three hats.

**Numbers.** No number in this recommendation is proposed. Minecraft's 1.0/0.8/0.6/0.5 is the
reference *shape*, not a target — it is authored for a sky-lit voxel world, not for a weapon at
0.12 m under a narrowed projection. **The ramp must come out of M1's sweep**, and per CLAUDE.md a
number without provenance endorses whatever the code did that day.

**The rule for non-axis-aligned facets, which the first draft did not have and which M1 cannot
sweep without.** An axis ramp is defined on six normals. `_extrude` emits **one normal per side
quad** (`gunart.gd:711-718`) and `_tri` bakes one `f` from it (`:739`), so every one of the
**13 circles** at `CIRCLE_SEGS` 10 (36° per segment, `gunart.gd:234`) and both **rotated rects**
(`mp40` and `pm63`, −0.35 and −0.45 rad) hands the ramp a normal that is on no axis. Those are not
edge cases: the Ray Gun's five circles and the Thundergun's six are precisely the parts R1 exists
to give form to. **State the blend rule as part of the recommendation, before M1 sweeps anything.**
The cheapest rule that keeps the style contract's rule 3 intact is to keep the value flat per face
and interpolate only the *lookup*: `f = Σ|n·axis| · ramp(axis) / Σ|n·axis|` over the six axes,
which reduces exactly to the axis value on an axis-aligned face and degrades smoothly at 36° steps.
Whatever rule is chosen, it must be **written down and swept**, because a ramp that is undefined on
a third of the table's parts will be resolved silently by whoever implements it.

**Rejected: leave the bake and add a bevel.** *A style rejection first (contract rule 2), a cost
rejection second.* A 45° bevel ring is the only proposal that creates genuinely new normal
directions — a bevel normal has an x component, so it can reach `FILL + KEY` = 1.16, a **1.349:1**
emitted span against a box's 1.2448:1 (F3). That is the correct denominator for this argument;
the first draft quoted 1.29:1 and a reviewer proposed 1.2448:1, and **both are wrong here** — the
box bracket is the wrong ceiling to judge a bevel by, because a bevel is the one thing that
escapes it. It still does not survive: it roughly doubles the table's triangles and `_measure`'s
corner count for a bracket the face ramp can widen for free, and it breaks contract rule 2. Do the
shading first. **Caveat: the first draft's "lands around 1.048" is not reproducible** — a 45° bevel
between the −X cap and the +Y top computes to 1.1258 and between +X and +Y to 0.8919, and no
bevel orientation I evaluated gives 1.048. Treat that figure as withdrawn.

**Rejected: an inverted-hull outline.** `BaseMaterial3D.grow` + `CULL_FRONT` is documented and
carries no Compatibility exclusion note, but this builder emits per-face unwelded normals, so the
hull splits at every corner; it doubles triangles and adds a draw call on a web build; and it
would make the weapon the only outlined object in a scene whose whole art argument is that the gun
is built the same way as the room.

### R2 — Author per-part depth, in both `_build` and `_corners`, keeping the `+ i*LAYER` tiebreak

**Decision.** Add a parallel `DEPTH` table (weapon → array of multipliers) and compute
`half = (BASE_HALF*depth[i] + i*LAYER) * UNIT` at **both** `gunart.gd:456` and `:488`. Receivers
and magazines thick; ribs, sights and highlight strips thin.

**Rationale.** F1. It fixes an inversion that is visibly wrong and costs zero triangles, and it is
the change that makes appending detail parts safe — today every appended part becomes the thickest
thing on the gun. The `+ i*LAYER` term must survive because it is the coplanar-cap z-fight fix
(`gunart.gd:190-200`); two parts given equal authored depth reinstate that bug, and `PROUD` covers
side faces only.

**Numbers.** The **ratios** come from Flan's Mod's `ModelColt`/`ModelSten` (Tier 3, but true
proportions rounded to a coarse grid — Colt grip 6×12×5, slide 21×2×5, barrel 24×2×2; Sten
receiver 17×3×3): receiver depth ≈ receiver height for the massive parts, 0.18–0.24 of length,
and thin parts genuinely thin. A real M1911 is 216 mm long and 34 mm wide (16%). **The absolute
scale is our decision and must be bounded by F7**, not by the ratios.

**Hard constraints.** (a) Both call sites or the clip assertion measures a mesh that is not on
screen — `gunart.gd:502-505` was written for exactly this. (b) **Cap coplanarity, stated as a rule
over the `DEPTH` table and asserted, not left as a comment** (F7, corrected): **no authored
half-depth may equal `HAND_HALF` (5.0) or `HAND_HALF + LAYER` (5.14) art units, and no two parts
of one weapon may land on the same half-depth.** The hands are pinned at those two values
(`gunart.gd:529-535`) and do not ride the `BASE_HALF + i·LAYER` ramp, so a gun part on either one
z-fights its ±X caps against a glove — the exact bug `LAYER` exists to prevent (`:190-200`). The
first draft gave a different reason (the hands' `PROUD` exemption) and that reason is **wrong**:
`_inflate` never sees a depth, so no depth can falsify it. An implementer who checks the named
invariant would have found it intact and shipped a broken table. **A14 asserts this over the table
directly.** (c) The **near plane**, not the wall clip, is what bounds this — 18% of clearance for
a doubling. The corresponding screen-radius figure is **disputed** (F7): somewhere between 5.9%
and 50% for the same doubling, and M3 is the arbiter. Do not commit a `DEPTH` table on the 5.9%.

**Rejected: per-part z-offset (asymmetric extrusion).** This is the change that would turn a
nested slab into a real object — a magazine hanging off one side, a bolt handle on the right only.
It is the highest-value item in the whole art pipeline and it is **out of scope for this package**,
because it requires `_extrude` and `_prism_corners` to change together against the same parameter
and it is the single easiest way to end up with a builder and a corner walk that disagree. Do it
as its own package, after R2 has proved the two-site discipline holds.

**Rejected: a cylinder primitive about the barrel axis.** A round barrel is the most recognisable
"3D gun" cue and the pipeline cannot express it — circles are discs in the drawing plane extruded
sideways. But it breaks the one invariant the file has ("a part is one convex 2D outline swept
along model X"), so `_part_poly` stops being the single geometry source and `_inflate`,
`_prism_corners` and `_extrude` all need a second path. Same reason as above: not in this package.

### R3 — Add BO1's bloom to `_spread_rad`, with the mutual exclusion intact

**Decision.** One float on the player, `_bloom` in 0…1. Cone becomes
`lerp(min_deg, max_deg, _bloom)`. Per frame: **if moving above the threshold, grow; else decay** —
never both. Per shot, add `fire_add` — and add nothing while fully at the sights. Four new columns
per weapon plus a decay rate.

**Rationale.** F17. It is pure GDScript on the player, no renderer, no assets, no threads, and it
is the single highest fidelity-per-line change available in this area. It also fixes something the
current model gets structurally wrong: today `_moving` is a ×1.5 multiplier that vanishes the
instant you stop, so there is no recovery *time* at all.

**Numbers — and a decision that must be made explicitly, because "verbatim" is a rebalance.**
The first draft said "F18's table, verbatim" and never computed what that does. F18b does:
**BO1's standing floor is 1.7× to 25× the port's shipped half-angle**, and a standing M14 goes
from hitting every shot at 26 m to hitting one in twenty. That is the document's own
"multiply every one of them by ten and the suite stays green" example arriving as a
recommendation. **Pick one and record it:**

- **(a) Shape only.** Import the bloom machinery, the mutual exclusion, the fire-add ordering and
  the per-stance structure, but **rescale the magnitudes** so each weapon's standing hip floor
  equals today's half-angle and the ceiling keeps BO1's floor-to-ceiling *ratio* (2.0× M1911,
  2.33× M14, 2.5× MP40, 1.6× Olympia, 1.2× China Lake). Nothing in `notes/balance/` moves, the
  frames gate does not move, and the feel change is entirely the recovery *time* the port has
  never had. Provenance: BO1 for the shape, "our decision, because the port's absolutes are the
  ancestor's and the reference's are 10× wider" for the scale.
- **(b) Absolutes.** Take F18 as written and accept that the M14, M16, M1911 and China Lake become
  materially less accurate weapons. Defensible — the reference wins — but it is a **balance**
  change and belongs behind M5's measurement and a sim pass, not behind a feel package.

**The recommendation is (a) for the first landing, with (b) as an explicit follow-up gated on M5.**
Reason: R3's stated value is the mutual exclusion and the recovery time, both of which (a)
delivers in full; the absolutes are separable and carry all the risk. Whichever is chosen, the
departure gets recorded at the constant, per CLAUDE.md.

Two exclusions either way: the two shotgun `adsSpread` cells are known-modified and must not be
treated as canon, and the Thundergun's spread is dead data in this port (`_cone_blast` returns
before any spread code) so its row is decorative.

**And the unit question is still open.** F17's "half-angle" reading is a Tier 2 inference, not a
fact — the call site that decides it was never read. If it is a full cone, every multiplier in
F18b halves. **Close F17 before committing either (a) or (b).**

**Unit trap, stated once because it is a silent factor of two.** BO1's numbers are **degrees of
half-angle from screen centre**. `player.gd:872` currently returns `deg_to_rad(s) * 0.5`, i.e. it
treats the table's `spread` as a full cone. Dropping BO1 numbers into the existing field without
removing that `0.5` halves every cone. **Cite the unit at the constant.**

**And while you are there: record F24.** The port's cone is already half the ancestor's with no
comment and no assertion. Whether that is deliberate or an off-by-one-halving from carrying the
projectile arm's factor into the shared helper, it needs a line either way.

**Rejected: keep the flat cone and add first-shot accuracy instead.** BO1 has no first-shot spread
term (F19); the effect people remember is the fire-add ordering, which R3 reproduces for free with
`FireAdd = 1.0` on the M1911 and M14.

**Rejected: a CS:GO-style seeded pattern table.** The format is right and implementable (generate
once at load from a per-weapon integer seed on a dedicated stream, index by shot number, which is
strictly better for seeded runs than drawing per shot) — but BO1 does not have one, and a zombies
demake does not want a memorisable spray. Out of scope, recorded so the argument is not re-run.

### R4 — Flip the view kick, clamp it, and give it a bracket instead of a scalar

**Decision.** Three changes to `player.gd`, together or not at all:

1. `_kick_v -=` becomes `+=` at `:834`, so the aim rises. **Provenance: BO1, and the reference
   wins over the ancestor** (F20, F21). Record it as a deliberate departure from `html:1748`.
2. Add a clamp mirroring `viewmodel.gd:266`'s `KICK_MAX`. **Provenance: the comment at
   `viewmodel.gd:264-270` already argues the case and the player's spring is subject to the same
   impulse stacking** (F22). The value is our decision.
3. Optionally, a per-shot **bracket** rather than the flat `def.kick * 0.55`, per-weapon
   `[min, max]`. **Provenance: BO1's `ViewKickPitchMin/Max` (F20)**; the shape of the roster is in
   that finding, and the M1911's total absence of gun kick and the Stakeout's one-sided yaw box
   are the two most characterful rows. **Against F18c**: the shipped `kick` column is the
   ancestor's unchanged and ties m16 and rpk at 1.5, so a bracket is not a rescaling of it.

   **The bracket must be DRAWLESS. It must not touch `Rng.VISUAL`.** The first draft prescribed
   two VISUAL draws per shot and called them cosmetic. They are not. `_recoil_pivot` is a child of
   `_head` (`player.gd:299`) and the parent of `_cam` (`:305`); `player.gd:718` is its sole
   writer; `_hitscan` takes its aim from `_cam.global_transform.basis` (`:878`). **A per-shot
   recoil draw decides where the round goes** — that is a *gameplay* draw, and CLAUDE.md
   constraint 5 says do not add a second violation. R4's own preamble establishes the fact ("all
   three change where bullets go") and the first draft then prescribed the cosmetic stream anyway.
   Nor is there a stream that passes today: `checks/projectiles.gd:989-999` drives four real
   `p._shoot` calls (`:991-993`), which reach the kick line at `player.gd:834`, and asserts
   "four grenades and four Ray Gun rounds draw from no gameplay stream" — a gameplay-stream draw
   there goes **red on arrival**.

   **Derive it from the shot counter instead, exactly as R7 mandates for brass.** `fx.gd:864-872`
   already carries a `_shot_no`; the player needs its own. Per shot,
   `t := fposmod(shot_no * GOLDEN_ANGLE, TAU)` plus a cheap integer mix of `shot_no` gives a
   low-discrepancy pair in [0,1) with **zero draws on any stream**, so R4 adds nothing to VISUAL,
   nothing to the gameplay streams, and seeded replay is untouched. **It is not a memorisable
   spray pattern** — the counter is lifetime shots fired, not shots-since-trigger-pull, so no two
   magazines start at the same phase and there is nothing to learn. That distinction is what
   keeps this compatible with R3's rejection of a CS-style table; say it in the comment or the
   next reader will think the two contradict.

   If a real draw is wanted anyway, it must be stated as a **knowing second violation of
   constraint 5**, with the stream named and `checks/projectiles.gd:998`'s claim explicitly
   revised. The first draft offered neither.

**This is the highest-risk item in the package and the rationale has to carry that.** `RecoilPivot`
is above the camera and `_hitscan` reads the camera basis, so all three change where bullets go.
The sign flip in particular converts body shots into headshots at 1.5× damage and a larger points
payout — a *balance* change wearing a *feel* change's clothes. **It ships only with R9.**

**Which spring does the bracket land on?** Unstated in the first draft, and the two are coupled by
design. `player.gd:103-104` and `viewmodel.gd:258-259` carry the same `KICK_SPRING` 46 /
`KICK_DAMP` 11, and `viewmodel.gd:247-248` says why: "same stiffness and damping as the view kick
in `player.gd`, so the weapon and the camera settle together instead of beating against each
other." A bracketed *player* impulse against a flat `def.kick` *viewmodel* impulse
(`viewmodel.gd:608`) breaks that on purpose without saying so. **Decision: the bracket lands on
the player's impulse only, and the viewmodel keeps `def.kick`** — because `_measure()` sweeps the
viewmodel kick over `[0.0, KICK_MAX]` and nothing else (`viewmodel.gd:952`), so a viewmodel
bracket that ever exceeded `KICK_MAX` would be **unmeasured by the no-clip proof**. The cost is
that the two springs no longer settle in lockstep shot-for-shot; that is a deliberate departure
from `viewmodel.gd:247-248` and gets a comment there as a reported hunk.

**Rejected: leave the sign and flip the viewmodel instead.** That would make the gun dip while the
view rises, which is neither source's behaviour and is nobody's.

**Rejected: horizontal recoil.** `player.gd:718` hard-zeroes the Y slot and BO1 does have a yaw
component with roll at −½ yaw. But the bob already occupies the X channel at twice the M14's cone
width (F23), a yaw term would compete with mouse aim in a way the pitch term does not, and adding
it doubles the assertion surface of the riskiest item here. **Next package.**

### R5 — Make the Olympia a break-action and give the Stakeout a real segmented reload

**Decision.** (a) Drop `shells: true` from the Olympia, or keep it and record the departure with
`rottweil72_zm`'s `segmentedReload = 0` cited. (b) Give `RELOAD_SHELL` a start and an end segment,
credit the first shell during the start, and keep per-shell credit for the rest.

**Numbers.** Stakeout 1.000 / 0.567 / 0.767; China Lake 2.000 / 1.000 / 1.100 (F13, Tier 1).
Scaled by `SPEED_RELOAD_MULT` across **every** segment (F16). The port has no China Lake tube
reload today and probably should not acquire one in this package — `chinalake` has `mag: 4`
against BO1's 2, so its reload is a different weapon's.

**Bound the test at both ends.** CLAUDE.md's rule bites hardest here: assert that a one-shell
top-up costs the start+end overhead **and** that a full reload from empty reaches capacity. A check
that only asserts one of those passes against a subsystem that has stopped working.

**Rejected: importing the 40% ignore window (F15).** It is real, Tier 1, single-sourced, and it is
the reason a BO1 Stakeout "commits" to the first shell. But the port's cancel is currently clean
and correct, and adding an input-swallowing window to a game whose whole feel argument is the
0.18 s fire buffer is a decision that deserves its own argument. Recorded, not recommended.

### R6 — Cycle the reciprocating group per shell

**Decision.** Give the viewmodel a per-shell edge. Two options and they are not equivalent:
a magazine-delta latch inside the rig (no other file changes, but it re-derives a fact
`player.gd:764-772` already knows), or a new signal from `player.gd` (correct, but `player.gd` is
another package's file, so it is a reported hunk — **and per CLAUDE.md a reported hunk needs a
check that fails until it lands**).

**Rationale.** F11. This is the single most visible animation defect reachable without new
geometry, new nodes or new data: a Stakeout's six-shell reload currently racks the pump once.

**Rejected: splitting `RELOAD_SHELL` into sub-states.** `weapon.gd:40-48`'s own admission test
("either something a viewmodel has to draw differently or something that changes whether the
trigger does anything") would admit it — but `hud.gd:1491` compares against `RELOAD_SHELL` by
value to decide whether to print `--`, and `hud.gd` is not this package's file. A latch or a signal
costs nothing there.

### R7 — Brass: a pooled MultiMesh ring in `fx.gd`, physics-free, counter-driven

**Decision.** A fourth `MultiMeshInstance3D` beside `_holes` / `_splats` / `_tracers`, built in
`_setup_decals()` through the existing **`_ring()`** helper (`fx.gd:746-758` — **not**
`_multimesh()`, which returns a bare `MultiMesh` with no `custom_aabb`, no `add_child` and no
shadow/GI flags, and which would build exactly the frustum-culled un-warmed ring constraint (b)
below predicts; F31), spawned from `_on_fired`, integrated
in the existing `_process`. Per-slot position, velocity and spin in packed arrays; Euler
integration; retire via `_retire()`. Per-casing variation from `fposmod(_shot_no * GOLDEN_ANGLE,
TAU)` and a cheap integer mix of `_shot_no` — **the counter, not `_hash01`** (F29). Per-weapon
tint via per-instance colour, so one material and one program serves brass, steel and a red hull.

**Rationale.** F28 gives four independent, converging designs; F30 says MultiMesh instancing is the
one thing this renderer does well and that particles structurally cannot tumble a mesh casing;
F31/F32 give the four places it breaks silently; `notes/research/M3-combat-fx.md:213` already
reached this conclusion and ranked it item 12 of 12.

**Numbers, in METRES and METRES PER SECOND.** Take ioq3's recipe (F28) as the starting bracket,
because it is expressed in the shooter's own basis — but **converted**, not literal. The first
draft said it "ports directly"; the basis ports directly and the **scale does not**, and a literal
port ejects the casing at 100 m/s from 0.6 m above the eye. Converted at the id convention of
1 unit ≈ 0.0254 m: offset **{0.20 forward, −0.10 right, 0.61 up} m**, velocity **{0,
−1.27 ± 1.02, 2.54 ± 1.27} m/s** in the shooter's basis, i.e. offset forward/right/up, velocity dominated by
the shooter's right with a vertical component roughly 2× the lateral, tumble about an axis
perpendicular to flight (OpenSpades' `cross(-up, flyDir)` — this is what makes it tumble rather
than spin), lifetime ~2–3 s, bounce ~0.2–0.4, lie flat on rest, sink over the last second.
**Every one of these is a starting point to be tuned against a frame, not a canon value** — F27
establishes that BO1's own numbers are not public.

**The mesh — specified, because the first draft specified everything about the casing except what
it looks like, under a request whose only constraint is a style constraint.**

- **Source: `gunart._extrude`, not a `BoxMesh` primitive.** It is the project's mesh-authoring
  path, it is what the style contract's rules 1–3 describe, and it gives the casing the same
  `FILL + KEY·max(n·KEY_DIR, 0)` flat per-face bake as the gun that ejects it — one visual system,
  no second shading model to keep in sync. `_extrude` is a `static func` taking a `SurfaceTool`,
  an outline, a grip origin, a half-depth, a colour and the key direction, so it can be called
  once at bind time with a scratch `SurfaceTool` and no change to `gunart.gd`.
- **Shape and size:** one rectangular prism. A 9 mm case is 19 mm × 9.5 mm; at the world's metric
  scale that is `0.019 × 0.0095 × 0.0095 m`. A rect outline is 4 corners → `4n − 4` = **12
  triangles**, one draw for the whole ring. Rifle and shotgun variants differ only in the three
  numbers and the tint.
- **Material:** one unlit `StandardMaterial3D` with `vertex_color_use_as_albedo`, registered in
  `fx.materials()` (`:920-928`) — omission there fails `verify.gd:1050`, which is the one
  registration the suite already catches (F32).
- **Tint:** per-instance colour **multiplies** the baked vertex colour, which is how one program
  serves brass, steel and a red plastic hull. That is `use_colors`, which `_multimesh()` already
  sets; **no `use_custom_data` is needed and none should be added** (F31).
- **Colour space:** the tint is an authored display-space value on an *opaque unshaded* surface,
  so it is **not** linearised — CLAUDE.md constraint 6, same posture as `_tint` (`gunart.gd:648`).

**Sizing.** F34. Either the ring is 24–32 slots or the life is ≈0.7 s; a 16-slot ring wraps in
0.72 s under a Double-Tapped PM63.

**Editorial, from BO1 and OpenSpades independently: four casing types, and four weapons eject
nothing** — Olympia, China Lake, Ray Gun, Thundergun (F27). OpenSpades reached the same conclusion
about its own shotgun for the same physical reason. Ejecting nothing is a decision worth making
loudly.

**Hard constraints.** (a) No `Rng` draw of any kind, and the existing purity assertion does not
cover the `fired` path (F29) — extend it or the contract is unenforced. (b) `custom_aabb`, or the
warm probe compiles nothing and the effect hitches on first use while the warm-up *looks* like it
ran. (c) A `_warm_probe` call inside `fx.warm()` and a matching reset in its cleanup block — caught
by nothing. (d) `fx.gd`'s `_process` has no `Game.state` guard, and `STATE_TITLE` deliberately does
not pause, so casings will fly across the title screen during the warm-up pass unless guarded.
(e) Spawn in **world** space with the projection correction, or accept a fixed lateral offset from
the flash anchor — the real ejection port is not recoverable across a 1.4476 projection ratio
(F33).

**Rejected: `RigidBody3D` casings.** F34's arithmetic, plus: it would be the project's first, against
two written rejections (`zombie.gd:141`, `projectile.gd:10`); it violates `fx.gd:25-27`'s "nothing
here calls `new()` after bind"; and it needs a sixth collision layer, i.e. a `project.godot` edit
this package may not make.

**Rejected: `GPUParticles3D`.** Not on taste — on F30. `angular_velocity` applies only under
`rotate_y`, `disable_z` or a billboard material, so a casing either does not tumble or is a
screen-facing sprite. A custom `shader_type particles` process shader would work and costs a new
main-thread GLSL compile per page load for something a MultiMesh does with no new program at all.

**Rejected: a per-shot casing sound.** 14 positional voices, eviction by largest playback position
(F34). Either rate-limit hard, or ship no sound. Shipping no sound is fine and is what the first
version should do.

### R8 — Cut list, stated up front

If the package runs long, cut in this order: **brass (R7) first** — it is invented, it is the only
item with a renderer cost, and M3 already ranked it last. Then **R12**, then **R11**, then **R6**,
then **R5(b)**, then **R10**. Do not cut R1 or R9; R1 is the cheapest change with the largest
effect and R9 is the only thing standing between a retune and a silent regression.

**The branch the first draft did not have.** M1's own decision rule says "if **no** bracket
separates them — i.e. the flatness is silhouette, not shading — abandon R1". The cut list then
called R1 un-cuttable, so a plan built from R8 had no ordering for the world its own gating
measurement is designed to produce. **If M1 abandons R1: R2 becomes the lead item, R10 moves up to
second (silhouette is exactly what R10 addresses), R1's budget goes to R10, and A9 is deleted
rather than left as a passing skip.**

**Every cut subtracts a known number of assertions.** See R9's floor table. A cut *after* the floor
has been raised for the cut item turns `verify.gd:336-338` red for a deliberate decision, which is
the worst possible failure mode for a cut list. Subtract, do not skip.

### R9 — The assertion package (this is what R4 and R7 ship behind)

**Decision.** The checks in **How this gets tested** — A1 through A15 — are a numbered
recommendation, not an appendix. The first draft referred to "R9" twice (in R4's risk paragraph
and in R8's do-not-cut line) and **never wrote it**, so the highest-risk change in the package was
gated on a section that did not exist. It exists now and it is this one.

**Rationale.** R4 moves where bullets go and converts body shots into headshots. R3 changes every
cone in the game. Both are invisible to the shipped suite: `grep -rn '_spread_rad' scripts/dev/`
returns two hits, both feeding one ratio assertion, and `kick` appears in `scripts/dev/` only in a
comment. **A11 and A12 — the two absolutes with F18/F20 provenance — are the un-cuttable core**,
because without them the document's own headline finding is documented and unclosed.

**Floor deltas, so a cut subtracts rather than skips.** Approximate and to be reconciled at
integration, per CLAUDE.md's contended-floor rule: A1 +5, A2 +3, A3 +6, A4 +6, A5 +1, A6 +5,
A7 +2, A11 +2, A12 +2, A13 +2, A14 +2, A15 +2. Roughly **+38** if everything lands. Cut R7 and
subtract A6's 5 and A15's 2; cut R6 and subtract A5's 1; cut R5(b) and subtract 3 of A4's 6. Raise
the floor with the same itemised prose block `verify.gd:145-165` uses for the last two raises —
that file's house style is "+2 for the shell's click, +12 for the zombie art pass", and a bare
number would be the odd one out.

### R10 — Author the +Z geometry F5 says is mandatory

**Decision.** Add rear-sight, charging-handle and stock-comb parts to `ART` for the weapons that
should have them. Three to five new rects per weapon, no new part *kind*, no pipeline change.

**Rationale.** F5 states a hard requirement — "**Anything that improves the ADS read has to add
geometry along +Z**" — and the first draft's eight recommendations added **zero triangles**, so
the finding's own stated remedy was unbuilt and unlisted under a request that leads with "improve
the gun models". F6 removes the usual reason to defer: the largest weapon is 324 triangles and an
8× increase is still under 3k. The style contract's rule 1 permits this exactly (a sight is three
more rects); it is the *cheap* half of the model work, where R2's z-offset is the expensive half.

**Hard constraints, all of them already documented as traps.** (a) **Append, never insert** — an
inserted part shifts `SLIDE`'s **array indices** (F2, `gunart.gd:146-160`), and with them every
later part's depth and `PROUD`, and with those that weapon's `sight_height()` and its ADS pose.
Appending is safe once R2 lands and depth stops being draw order; **R10 therefore ships after R2,
not before.** (b) `_corners` (`:477-495`) is a hand-maintained parallel walk of `_build` and must
be checked, though for an appended rect it needs no edit — that is the point of (a). (c) `_measure`
is linear in corner count (F6): +4 corners per part × 144 poses per weapon is real time inside a
~5 s suite, so budget the parts and re-read M-VMCLIP's runtime. (d) `tools/gen/targets.js:150-162`
bakes the chalk plaques from a **second copy** of the art table and nothing asserts they agree
(F8) — new parts will silently desync the wall buy outline unless that copy is regenerated.

**Rejected: modelling the sight aperture as a hole.** No boolean, no concave outline — `_part_poly`
produces one *convex* outline and `_inflate`'s mitre assumes it. Two rects with a gap between
them reads as an aperture at 0.12 m and costs nothing.

### R11 — Give IDLE an appearance

**Decision.** A low-amplitude breathing offset on `WeaponMesh` inside `_apply()`'s existing single
writer. No new node, no new geometry, no `AnimationPlayer`.

**Rationale.** F9 names the defect — "**only four of seven states have any distinct appearance,
and neither IDLE nor FIRING is one of them**" — and the first draft never returned to it, so
"reload animation… animation etc." was silently reduced to "reload". IDLE is the state the player
spends most of the game in and it is the bare rest pose. This is the cheapest real animation win
in the document.

**Hard constraints.** (a) It is a **new channel into `_mesh_pose`**, so it must be added to
`_measure`'s sweep at `viewmodel.gd:952-974` or it becomes trap 2 in "four ways to void the
guarantee silently". (b) It must ride the existing single writer on `WeaponMesh`; a second write
to that node is the one-writer violation `viewmodel.gd` is built to avoid. (c) `Settings.reduce_motion`
must zero it, as it zeroes the bob (`player.gd:709`). (d) Amplitude has to be small enough that
`max_screen_radius` does not move — it is a pure lateral+vertical translation, so it adds
directly to the `bob` term in `_measure` (`viewmodel.gd:918`).

**Explicitly out of scope, listed so "animation" is not silently reduced again:** draw/holster,
the ADS transition (it is a lerp today and reads fine), a distinct bolt-hold-open release (F10
notes it does not exist), and a firing animation beyond the existing per-shot kick.

### R12 — Rule on "shell patterns", one way or the other

**Decision.** This document read "shell patterns" as **brass ejection** and that reading is not
obviously the right one. The other reading is the shotgun **pellet** pattern, and F35 shows it is
a live, undesigned area: six independent full-cone draws, no pattern, no per-pellet falloff, and a
hard `range` cliff where the Olympia goes from 1.4 expected pellets at 13.00 m to zero at 13.01 m.
**If the brief meant pellets, R12 replaces R7 in the package and R7 is cut, because pellets are
gameplay the player feels and brass is invented decoration (R8 already ranks R7 last).**

**If pellets are in scope, the shape of it:** a fixed ring-plus-centre placement instead of six
independent draws (one pellet on the axis is what makes a shotgun feel aimed, and it costs zero
draws — the ring positions are constants); per-pellet linear damage falloff over the last third of
`range` instead of the cliff; and BO1's base `shotCount` for `rottweil72_zm` and the Stakeout
reported against the port's flat 6/6 before any number is changed. **That last item is a research
task this document did not do** — the field was in hand (the Pack-a-Punch note quotes the
Olympia's 8→12) and was not reported, which is a gap, not a finding.

---

## The constraints that shape all of it

**gl_compatibility deaths that actually bite here.** Only one, and only for brass: particle trails,
sub-emitters and `emit_particle()` are dead, and `ParticleProcessMaterial` cannot rotate a mesh
particle about an arbitrary axis (F30). Everything else in this package — spread, recoil, reload
timing, per-part depth, the face bracket — is CPU-side scalar maths or vertex colours and touches
no dead feature. The two live *positives* worth knowing: MultiMesh per-instance colour and custom
data work (16-bit), and vertex colours are already the project's shading channel.

**The `Rng.VISUAL` spread violation: what it costs to fix, and to leave.** CLAUDE.md records this
as known and says do not add a second. Two corrections to the *reason*. (1) It does **not** move sim
baselines — `balance_sim.gd` never draws a spread; it rolls a flat `--sim-accuracy` on a private
`RandomNumberGenerator` deliberately outside `Rng` (`:93-100`). What moving it would actually break
is seeded-run replay and the `raygun` frames row, whose bolt spread is drawn from VISUAL
immediately after `fired`. (2) Six live assertions in five files exist *because* spread rides
VISUAL — `checks/projectiles.gd:989-999`, `checks/frame.gd:1123`, `checks/systems.gd:453`,
`verify.gd:1016`, `checks/shell.gd:881`, `checks/traps.gd:663` — and four source files carry
comments explaining that they must draw from no stream at all for the same reason. **Leave it.
Record the corrected reason.** **R3 adds no draw, R4 adds no draw, R7 adds no draw.** The first
draft said R4 "adds two per shot… and they must be VISUAL"; that was a second violation of
constraint 5 wearing a cosmetic label — a per-shot recoil draw sets the camera basis `_hitscan`
aims down — and R4 now derives the bracket from a shot counter instead. **Nothing in this package
adds a draw to any stream.**

**And a rule that is easy to miss, corrected — the first draft had this exactly backwards.**
`checks/frame.gd:1108` and `:1123` bound the draw count of **`fired` LISTENERS only**. They clone
the VISUAL stream as an oracle at `:1069-1073` and then call `_fire_once` (`:1141-1149`), which
**emits `player.fired` directly and never calls `_shoot`**. So:

- A VISUAL draw added inside a **`fired` listener** — atmosphere, fx, the viewmodel rig — fails
  `checks/frame.gd:1108`/:1123 loudly. **That is R7's hazard**, and it is why R7's counter matters.
- A VISUAL draw added inside **`_shoot`** — at `player.gd:834`, before `fired.emit` at `:837`, or
  anywhere after it — **is never executed by that check and cannot fail it**. And it shifts bullet
  placement either way, because `_hitscan`/`_launch` draw *last* in `_shoot` (`:844-850`,
  `:886-887`, `:939-940`); "before the emit is caught, after it is not" was wrong on both halves.

**Nothing in the suite bounds the VISUAL draw count inside `_shoot`.** A13 exists to close that:
drive `p._shoot` N times and diff `Rng.stream(Rng.VISUAL).state` against an expected count.

**The clip budget and `_measure()`.** The measured worst case is 0.232 m against `Player.RADIUS`
0.24 — **8.1 mm**, and lateral motion is weighted by `ratio² = 2.096`, so a 4 mm sideways addition
can consume the whole budget. Four ways to void the guarantee silently, all of which leave
`verify.gd:1728-1730` green:

1. A new pose channel applied anywhere other than as an argument to `_mesh_pose()`.
2. A channel added as a `_mesh_pose` parameter but not to the sweep at `viewmodel.gd:954-974`.
3. A new mesh group whose corners are never `_collect`ed — and **both ends of any travel** must be
   collected, as `_collect(slide, into, SLIDE_TRAVEL)` already does.
4. Geometry added in `_extrude` and not mirrored in `_prism_corners`.

Two live traps that predate this package and that it must not make worse: `_measure()` caches on
first call and bakes in `tan(_cam.fov/2)/tan(VIEWMODEL_FOV/2)` at that instant, so **suite ordering
decides what the safety assertion measures** — any new check that poses the viewmodel must run
after `verify.gd:262`. And the bob is swept at amplitude 1.0 but reaches 1.6 in a sprint
(`viewmodel.gd:920` vs `:670`), understating `max_screen_radius` by a bounded ≤1.57 mm. It still
passes; it means any increase in bob is unmeasured by construction.

**One writer per node.** `RecoilPivot.rotation` has exactly one writer, `player.gd:718`, and R4
must go through that line. `Slide.position` is a full `Vector3` write every frame
(`viewmodel.gd:773`), so anything wanting x or y on that node is clobbered — `_slide.rotation` is
the one free channel there. A second animated group cannot be a second write to `WeaponMesh`; it
has to be a new child with its own single writer inside `_apply()`.

**Sim baselines that move.** Fewer than CLAUDE.md implies. `balance_sim.gd` has no spread, no
recoil and no player position, so R1, R3, R4 and R7 move **nothing** in `notes/balance/`. What does
move it: `def.pellets`, `def.rpm`, and any new weapon state or changed timing, because `weapon.gd`
is driven headless by `balance_sim.gd` (`balance_sim.gd:249-263`, `:501-521` — the first draft
attributed both ranges to `weapon.gd`, which is **330 lines** and has no `:501`). So **R5 moves sim
baselines and the others do not** — re-verified: `_spread_rad` appears nowhere outside `player.gd`
and `checks/projectiles.gd`. **R12, if it lands, moves them too**: it changes `def.pellets`
semantics and per-pellet damage, which is exactly the column the sim reads.

**Frames-gate numbers that move.** `golden.json` carries seven viewmodel probes on `spawn` and
seven on `ads` at 5% probe tolerance; 5% of `spawn.gun_px` 20829 is 1041 px. **Any model change
blows them**, and that is the intended `-Bless` workflow, not a wall. The asymmetry that matters:
**`-Bless` rewrites `scenarios`, `resolution` and `captured` only** — `tolerance` and `relations`
are hand-set and survive. So an absolute probe that moves is silently adopted at the next bless,
and only a `relations` rule is durable evidence. There are **24** relations today (not the 12 or 22
two researchers reported), four of them about the weapon on screen. The one that must **not** move
is *"the viewmodel is lit"* (`spawn.probes.gun_mean / spawn.mean`, measured 7.5208) — it is the
guard against the second shipped black frame, and R1 aims directly at its numerator.

**`VM_RECT_HIP` / `VM_RECT_ADS`** (`shot_setup.gd:191-192`) are hand-measured pixel rects. Move the
weapon without re-reading them and `gun_mean` becomes a measurement of wall — the exact failure
`shot_setup.gd:152-156` records. `--frames <name>` prints the measured silhouette box, so
re-reading them is a log line, not an afternoon.

**Parse-gate discipline.** `gunart.gd`, `viewmodel.gd`, `weapon.gd` and `player.gd` are all
reachable from the main scene, and a parse error in any of them hangs Godot for ~414 s for every
other agent. Parse-gate individual files while others are working; do not run `--verify` on a tree
being written to.

**`ASSERTION_FLOOR` is 692** (`verify.gd:166`, read directly). The green total of **693 is
inherited, not measured** — nobody in the research phase ran `--verify` — so "one assertion of
slack" is an inference from a number this document did not check. **Measure the real total before
sizing the raise.** Raise it additively, itemised in `verify.gd:145-165`'s own prose style, per
R9's floor table.

**Where the six new `checks/*.gd` files sit in the registration order — a rule, not a paragraph.**
`_measure()` caches on first call and bakes `tan(_cam.fov/2)/tan(VIEWMODEL_FOV/2)` at that instant,
so the suite's *first* viewmodel caller decides what the no-clip safety assertion measures.
`checks/projectiles.gd:562-571` already documents that its own section would poison M-VMCLIP if it
ran before `verify.gd:262`. **A1 fires N real shots through `_hitscan`, A3 drives `_update_view`
sixty times, A5 runs a real six-shell reload, and A15 deliberately re-measures at fov 110** — all
four pose or perturb the rig. **Registration rule: every new check module in this package goes
AFTER `_viewmodel(main)` (`verify.gd:262`), and A15 goes last of all, after the four
state-leaving sections `verify.gd:263-266` already orders by what each leaves behind.** These are
`verify.gd` registration lines, so they are **reported hunks, not edits** (CLAUDE.md:206) — and a
new `checks/*.gd` on disk without them turns `--verify` red immediately (`verify.gd:198`
`_registered()` walks the directory), which is the reported-hunk rule enforcing itself. **That
free enforcement holds only for a NEW file**: appending A1–A7 to `checks/projectiles.gd` needs no
registration hunk and gets none of it. **Decision: new files.** `checks/spread.gd`,
`checks/recoil.gd`, `checks/reload_shape.gd`, `checks/brass.gd`.

---

## What must be measured rather than researched

### M1 — Does the face-value bracket actually explain "flat"?

**Why it cannot be researched.** F3 is arithmetic over the shipped constants plus a geometric
visibility argument. Whether a 7.5% spread across the three dominant face groups is *what the eye
is complaining about* is a question about a photograph. CLAUDE.md's own history is the warning:
`rim_mean / body_mean` turned out **non-monotone** and could only bound its defect from above.

**Procedure.**
1. `--path . --shot out.png --shot-setup spawn` at the shipped constants. Look at it.
2. Sweep the bracket over at least five points — today's `(FILL 0.86, KEY 0.30)`, plus a widened
   dot-product bracket, plus three axis-ramp variants at ~1.15:1, ~1.5:1 and ~2:1 top-to-bottom,
   each normalised so the *area-weighted mean over visible faces* is within 2% of today's.
3. For each: capture `spawn` and `ads`, record `gun_mean`, `gun_lit_frac`, `gun_over_frame`, and
   open the PNG.
4. Tabulate. Write the rejected rows into whatever rule ships.

**Decision rule.** Ship the narrowest bracket at which a human, shown the PNGs unlabelled, can
separate the top plane from the face plane. If **no** bracket separates them — i.e. the flatness is
silhouette, not shading — abandon R1, say so, and R2 becomes the package's lead item. If a bracket
works but pushes `the viewmodel is lit` outside `[4.5, 12.0]`, it is too bright regardless of how
it looks.

### M2 — Where is the glow threshold really, and does the knife blade already bloom?

**Why it cannot be researched.** F4: two comment blocks in one file reason in two colour spaces
about the same number and only one can be right. The margin R1 is spending is of unknown size.

**Procedure.** Sweep a single part's authored brightness across the claimed 0.92 boundary in ~2%
steps, capture `spawn` each time, and find the step at which `blown` or the glow visibly turns on.
Then locate the knife blade (`#E2E7EC`) against that measured boundary — `--shot-setup` has no
knife state, so this needs a scratch state or a temporary `_show("knife", false)`, restored in a
wrapper that runs even if the command dies.

**Decision rule.** If the blade already blooms, `gunart.gd:268` is wrong and must be corrected in
the same commit as R1 — and R1's ceiling is bounded by whatever the measurement says, not by "seven
percent". If it does not, record the measured boundary and the margin as a number, once, so the
next agent does not re-derive it in the wrong space.

### M3 — What does per-part depth cost in the three clip metrics?

**Why it cannot be researched.** F7's headroom figures are conservative analytic **bounds** on
committed values, not measurements — and **two derivations of the same bound disagree by up to 8×**
(0.48 mm against a 1.5–4 mm band for the same doubling; see F7). Nobody has run the sweep. That
disagreement is itself the argument for M3 being a gate rather than a formality: **the screen-radius
headroom is currently unknown, not 94% free**, and a `DEPTH` table committed on the 0.48 mm figure
would be committed on a number no one has checked.

**Procedure.** With the `DEPTH` table in place, run `--headless --path . --verify` and read the
M-VMCLIP block's three reported numbers (`max_screen_radius`, `max_corner_radius`,
`min_corner_depth`). Then re-run with `Settings` FOV at **110** — `_measure` derives its ratio from
`_cam.fov` at first call and `settings.gd:67` allows [60, 110], where the lateral weight goes from
2.0955 to 7.526. This exposure pre-dates the package; a depth pass makes it worse.

**Decision rule.** Near-plane clearance is the binding constraint, not screen radius. If
`min_corner_depth` drops below ~0.055 m at fov 74, thin the depth table rather than moving
`REST_POS`. If the fov-110 case fails at *today's* depths, that is a pre-existing defect and should
be reported separately rather than absorbed into this package.

### M4 — What does a moving MultiMesh cost per frame in a browser?

**Why it cannot be researched.** The tracer ring writes only on spawn and retire; a casing ring
rewrites every live instance every frame. Whether Godot uploads incrementally or re-uploads the
buffer decides whether the cost scales with live count or with `instance_count`. Engine source says
`MULTIMESH_DIRTY_REGION_SIZE` is 512 and that more than 32 dirty regions triggers a whole-buffer
`glBufferSubData` bounded by `visible_instance_count * region_size` — which suggests keeping live
casings packed at the front and setting `visible_instance_count` to the live count, but no
measurement exists in `notes/perf/` and this is the largest unknown in R7's cost model.

**Procedure.** `perf_probe.gd` already exercises MultiMesh instance colour on the real renderer.
Extend it: N live casings rewritten per frame, N over {0, 8, 16, 32}, `instance_count` fixed at 32,
with and without `visible_instance_count` tracking the live count. Measure in an exported web build
served over HTTP — not the editor.

**Decision rule.** If the cost is flat in N and scales with `instance_count`, size the ring to 24
and cut the lifetime instead of growing it. If it scales with N, the ring can be larger. If either
exceeds ~0.3 ms at 24 live casings, cut R7 (see R8).

### M5 — Does the bloom read at all, and at what decay rate?

**Why it cannot be researched.** F18's decay rates are BO1's, tuned for BO1's fire rates, movement
speed and target sizes. This game's `SPEED` is 3.15 and its zombies are 0.30 m capsules at hitscan
range; a 0.25 s recovery may be imperceptible or may be the whole feel.

**Procedure.** Not a frame capture — a firing-range measurement. Drive `p._hitscan` through the
real path against a wall at a fixed range, N = 2000, and record the impact scatter for: shot 1
standing, shots 2–10 standing, shot 1 after 0.5 s of standing still, and the same walking. Plot the
95th-percentile deviation against shot index.

**Decision rule — inverted after review, because it was pointed at the wrong risk.** The first
draft's rule was "if floor and ceiling differ by less than about 2× the bloom is not doing visible
work and its constants want **widening** beyond BO1's". But F18's own floor-to-ceiling ratios are
already 1.2×–2.5× across the whole roster (M1911 3→6 = 2.0, M14 3→7 = 2.33, MP40 2→5 = 2.5,
Olympia 5→8 = 1.6, China Lake 5→6 = 1.2), so that rule fires on nearly every weapon — while the
live risk, per F18b, is that the **absolute floors are 1.7×–25× too wide** and the weapons become
unusable. A measurement set up to detect "too narrow" against a change that is 10× too wide is
not a gate.

**The rule, both ends bounded:**

1. **Abort condition first.** If the standing hip floor costs more than **25% of today's hit rate
   at 10 m against `HIT_RADIUS` 0.30**, take R3 option (a): rescale to preserve today's floor and
   keep only BO1's shape and ratios. On F18b's arithmetic the M14 fails this by a wide margin
   (100% → 33%), so **expect (a) to be the answer** and treat (b) as the case needing evidence.
2. **Then the visibility end.** If, after whatever scaling is chosen, the floor and the saturated
   ceiling differ by less than about 2× in *screen* terms at typical engagement range, the bloom
   is not doing visible work and the *ratio* — not the absolute — wants widening.
3. Record whatever scaling happens as our decision with the measurement attached, not as canon.

**Baseline to measure against.** F18b's shipped half-angle column. A firing-range measurement with
no baseline is a snapshot.

---

## How this gets tested

Every assertion below ships with the sabotage that must make it fail. Run the control, record the
verdict. `ASSERTION_FLOOR` rises additively; `verify.gd`'s registration lines are reported hunks,
not edits (CLAUDE.md:206), and a new `checks/*.gd` on disk without them turns `--verify` red
immediately — which is the "reported hunk is not done" rule enforcing itself for free.

### What `--verify` can prove headlessly

**A1 — Spread distribution, through the real path.** Seed, stand still, hip, drive **`p._hitscan`**
N times against a wall, collect the impact points off `surface_impact`. Four claims:
(a) every sample's angle off the aim axis ≤ `_spread_rad(def)` + ε;
(b) the 95th percentile ≥ 0.90 × that — **the cone is actually filled**;
(c) the mean angle on the diagonals over the mean on the axes is within 2% of 1.0 — a **disc, not a
square**;
(d) the fraction inside half the max angle is 0.25 ± 0.03 — the `sqrt()`'s uniform-in-area.

**(e) `samples.size() == N`, asserted BEFORE any statistic is computed.** The sample set is
silently lossy: `_hitscan` emits nothing when the ray hits nothing (`player.gd:899-900`) and
nothing when it terminates on a Zombie (`:902-907`, with `pierce` 1 it falls out of the loop
without emitting). Wide-angle samples that miss the wall, or any ray a wandering zombie eats,
**vanish — truncating the distribution inward, which moves (b) and (d) in the passing direction**.
This is exactly the empty-mask failure `frame_stats.gd:252-258` documents and which A9 is told to
guard against; A1 needs the same guard. State in the comment that the wall must subtend far more
than the cone.

*Controls, one per claim, corrected:*
- (d) — delete the `sqrt()` at `player.gd:887`. **This one is exclusive and it is correct as
  written**: the 95th percentile goes 0.9747 → 0.95, still above (b)'s 0.90 floor; the
  distribution stays rotationally symmetric so (c) holds; and P(r < 0.5) goes 0.25 → 0.50, so (d)
  fails alone. Worth saying so, because none of the others is exclusive.
- (c) — replace the polar sample with two independent axis rotations, the bug
  `player.gd:881-883` records as having shipped once. **Drop the word "only".** The square
  sampler's corner radius is 1.41× the half-angle by that comment's own arithmetic, so it also
  fails (a) and (d). (c) is the **diagnostic** claim — the one that names the defect — not the
  exclusive one.
- (b) — **not** "set one weapon's `spread` to 0". That control **cannot fail (b)**: with
  `spread = 0`, `_spread_rad` returns 0.0, `_hitscan` skips the cone rotation entirely
  (`if spread > 0.0`, `:885`), every sample's angle is 0, and (b) evaluates `0 ≥ 0` and passes.
  The correct control breaks the **filling** without touching the width: replace
  `sqrt(Rng.randf(Rng.VISUAL))` at `:887` with a constant 0.3, so samples cluster well inside the
  cone and the 95th percentile falls below 0.90 × an unchanged `_spread_rad`.
- (a) — **not** "double the returned half-angle". Sabotaging `_spread_rad`'s return moves the
  sampler *and the test's reference* identically, so (a) stays green — the Stamin-Up/Mule Kick
  shape recorded at `2026-07-30-agent-workflow-audit.md:28`. Sabotage the **call site** instead:
  `var spread := _spread_rad(def) * 2.0` at `player.gd:884`.
- (e) — spawn a Zombie in the line of fire, or narrow the wall. The count must drop and the check
  must go red before any statistic is reported.

*Sizing.* State N and derive the tolerances from it rather than the other way round: (d)'s ±0.03
on p = 0.25 needs N ≈ 3300 at 4σ; (c)'s 2% ratio-of-means needs N ≈ 20000 against the sqrt
sampler's relative sd of 0.354.

*Entry point.* **`_hitscan` with an explicit `mag` reset, not `_shoot`.** M5's procedure and the
first draft of A1 disagreed ("drive `p._hitscan`" vs "fire N real shots"); `_shoot` spends a VISUAL
draw per shot via `atmosphere.gd:334` and starts a reload at `mag` 0. The precedent is
`checks/projectiles.gd:991-993`, which refills `mag` each iteration.

*Do not* sample by recomputing the rotation — that is testing a copy. Restore `Rng.stream(VISUAL)`
on the way out, as `checks/frame.gd:1131` does. **A1 and A6(c) contend for that restoration**: A1
spends thousands of VISUAL draws and A6(c) counts them exactly, so if either fails to restore, the
other's count is wrong and the `raygun` frames row moves. Both restore.

**A2 — Bloom, and specifically the mutual exclusion.** Drive the **integrator** — not
`_spread_rad`, which is a pure read of `_bloom` and would test the lerp instead — across a
synthetic timeline. Assert: firing grows the cone; **standing still shrinks it and reaches the
floor in `1/decay` seconds ±1 tick**; and **moving does not shrink it at all**, even with the
trigger released.

*Control, with the test case pinned.* Replace the exclusive branch with `s += grow*dt; s -= decay*dt`
— the natural wrong implementation. **Run it at a speed just above `bg_aimSpreadMoveSpeedThreshold`**
(11 units/s ≈ 0.28 m/s against `Player.SPEED` 3.15, i.e. |v|/speed ≈ 0.089), where the increase term
is ≈ 0.40 against a decay of 4.00 and the additive version unambiguously shrinks. **At full speed
the control bites on almost nothing** and this is why it must be pinned: MoveAdd vs Decay is
4.0 vs 4.0 on the MP40, 5.0 vs 5.0 on the M14, 4.5 vs 4.0 on the M1911 and 5.0 vs 4.0 on the
AK-74u/M16/RPK, so claim 3 stays **green on seven of twelve rows** under the wrong implementation.
Say in the comment that the low-speed case is the discriminating one, not an arbitrary one.

**A3 — Recoil pattern and direction.** `p._shoot(gun)` once, then step `p._update_view(1/60, …)`
sixty times, reading `p._recoil_pivot.rotation.x`.

**Set `p._moving = false` first.** `player.gd:718` writes `Vector3(_kick + slow, 0.0, roll)`, so
that component is **`_kick` plus the bob's slow sway** (`:717`), and F23 is this document's own
finding that the sway term is larger than most weapons' whole cone. Without pinning `_moving`,
A3 measures two systems. Assert `rotation.x == _kick` exactly on the first frame — that is a
one-writer check worth having on its own.

Claims: (a) the peak is in a stated band with provenance; (b) **the sign is up**; (c) |x| after 60
frames is under 2% of peak, so the spring does not leak; (d) frame-rate independence;
(e) **replaced, see below**; (f) `reduce_motion` damps to exactly `REDUCE_MOTION_KICK` of the peak
and does not zero it.

**(b)'s provenance and its control, both missing from the first draft** — and (b) is the single
most important claim in the package. Provenance for "up": `player.gd:426`
`_head.rotation.x - event.relative.y * sens` establishes that positive `rotation.x` is look-up, so
a positive peak on `_recoil_pivot.rotation.x` is the aim rising. **Control: after R4 lands, restore
the `-=` at `player.gd:834`.** A claim with no control is decoration, and this one was carrying
R4.

**(d) needs a measured tolerance, not 1e-3.** The integrator is semi-implicit Euler
(`player.gd:686-687`) and is O(dt)-accurate, not exact. At `KICK_SPRING` 46 the natural frequency
is 6.78 rad/s and ω·dt at 1/30 is 0.226, so 6 steps at 1/30 against 24 at 1/120 will **not** agree
to 1e-3 absolute on a peak of order 0.04 rad. **Measure the divergence first, then state the
tolerance as a relative bound with that measurement as its provenance** ("MEASURED <date>: 1/30 vs
1/120 over 0.2 s differ by X% of peak"). The lerp control fails a 5%-relative bound just as
loudly, and the check does not become a flake. An assertion that demands behaviour the code does
not have is the audit's §2 shape in reverse.

**(e) — replaced. The first draft's "the thirteen peaks are strictly ordered by the `kick` column"
is red on arrival, twice.** There are **twelve** firing weapons, not thirteen — thirteen is the
`ART` count and includes the knife, which has no `weapons.gd` row — and `m16` and `rpk` both carry
`kick: 1.5` (`weapons.gd:32`, `:33`), so a strict order is unsatisfiable. Relaxed to non-strict it
becomes decoration: its own control ("flatten every `kick` to 1.0") leaves a non-decreasing
sequence and still passes. **Replace with an identity and a range:**
(e1) `peak / def.kick` is constant across all twelve to within 1e-4 — an algebraic identity, blind
to the value, that fails the moment one weapon stops reading its own column; control: hardcode one
weapon's impulse.
(e2) `max(peak) / min(peak) ≥ 4.0` — provenance: thundergun 4.2 over pm63 0.9 = 4.67
(`weapons.gd:36`, `:29`); control: flatten every `kick` to 1.0, which now genuinely fails.
Correct "thirteen" to "twelve" everywhere it means firing weapons.

*Other controls:* delete the `-_kick*KICK_SPRING` term → (a) and (c). Replace the integrator with
`lerp(_kick, 0, 0.2)` → (d). Drop the `REDUCE_MOTION_KICK` factor → (f).

**Restore on the way out**: `_kick`, `_kick_v`, `_shake` and `RecoilPivot.rotation`. A3 leaves all
four perturbed for every later section, and `verify.gd:263-266` orders the last four sections
precisely by what state each leaves behind. `checks/frame.gd:1129-1134` is the pattern.

**A4 — Reload phase sequence, bounded at both ends.**

**Do not count `weapon_state_changed`. That event never fires per shell.** `weapon.gd:328`
re-enters `RELOAD_SHELL` with **itself**, so the ordinal never changes, and `player._weapon_state`
(`:732-735`) emits only on an ordinal change — which is F11, this document's own finding. From
empty a listener sees exactly **two** pairs (EMPTY→RELOAD_SHELL, RELOAD_SHELL→IDLE) no matter how
many shells load. The first draft's "`RELOAD_SHELL` re-entry exactly `def.mag` times" is
unobservable and would go red on arrival; written defensively as `count >= 1` it would pass against
a tube that loads all six shells at once, which is the exact sabotage it names.

**Count through an observable the re-entry actually moves.** `gun.mag` incrementing 0→1→2→…→6,
which is what `_load_shell` writes (`weapon.gd:320`) and what the player sees. Assert the per-shell
**arrival times**, which is what tests F13's asymmetry. Keep `weapon_state_changed` for the
magazine-weapon claim only — IDLE→RELOADING→IDLE — where it does fire.

**Timing claims against literals, not against the def.** The first draft asserted "partial at
0.5 × total, full at 1.05 × total" with the control "halve `def.reload`". If `total` is computed
from the def, halving `def.reload` halves the reload **and** the expectation and both claims stay
green — `weapon.gd:284-289` derives per-shell time as `float(def.reload) / maxf(1.0, float(def.mag)) * reload_scale`,
straight out of the table the test would read. **Use literals with F13 provenance:** Stakeout from
empty 1.000 + 5 × 0.567 + 0.767 = **4.60 s**; one-shell top-up 1.000 + 0.767 = **1.77 s**; Speed
Cola from empty **2.30 s** (F16). Halving `def.reload` then fails.

**And assert the asymmetry itself**, which is the whole point of F13 and which `reload / mag`
structurally cannot produce: `top_up_time / from_empty_time ≥ 0.35` (BO1: 1.77/4.60 = 0.385;
`reload / mag`: 0.567/3.40 = 0.167).

Firing mid-shell settles the state and **keeps the shells already loaded**.

*Controls:* make `_load_shell` fill the tube at once → the `gun.mag` arrival-time claims. Halve
`def.reload` → the literal timing claims. Make firing bank rather than cancel → the interruption
claim.

**If R5(b) is cut** (it is third on R8's list), A4's start/end claims are **DELETED and the floor
delta reduced by 3** — they do not become `v.check("...", true, "R5 did not land")`. That is the
soft skip CLAUDE.md forbids and the Monkey Bomb check did for a whole wave. **Same rule for A5 if
R6 is cut and A6/A15 if R7 is cut.**

**A5 — Per-shell cycle (R6).** Consumer-driven: run a real six-shell reload and count the
`_cycle_slide()` edges by reading `_slide_t` re-arming, or by a counter the rig owns. Six, not one.

*Control:* revert to the `_on_weapon_state` path alone (`viewmodel.gd:586-603` against `:621-622`)
→ one.

**Which of R6's two options this is written against matters.** "The thing that fails until the
reported hunk lands" is true only of the **signal** option. R6's other option is a magazine-delta
latch **inside the rig** — `player.gd:764-772` already computes the delta, so the latch is a
`viewmodel.gd`-only change — and under that option A5 passes the moment the rig lands and enforces
nothing across a package boundary. **Pick the latch, and drop the cross-package claim**; the
signal buys correctness the rig can get for free and costs another file's hunk.

**A6 — Brass, entirely headless (R7).** (a) One shot spawns exactly one casing. (b) Twenty shots
allocate no nodes and round-robin the pool, as `verify.gd:974-981` already asserts for impacts.
(c) **Twenty shots perturb no stream at all** — extend `verify.gd:1000-1017`'s pattern to drive
`fired`, accounting for the one VISUAL draw the muzzle flash legitimately spends
(`atmosphere.gd:334`), so the check counts rather than forbids. (d) Stepping the integrator moves
an instance away from the retired zero basis and returns it at end of life. **(d2) the casing
falls**: its y after 0.3 s is below its spawn y and its vertical velocity is strictly decreasing.

**(a)'s "and a six-pellet Olympia shot also spawns one" is decoration as written.** `fired` is
emitted **once** per `_shoot` at `player.gd:837`, *before* the branch at `:844-850` whose else-arm
is the pellet loop — so a casing hung off `fired` is **structurally incapable** of multiplying by
pellets and the claim cannot fail. **Make it real**: drive the whole `_shoot` for an Olympia and
assert the ring advanced by exactly 1 **while `surface_impact` fired 6 times**. That version
discriminates a casing accidentally hung off `surface_impact` — which `fx.gd:296` also connects —
which is the mistake actually available. (Moot if the Olympia ejects nothing, in which case assert
zero and six.)

*Controls:* return early from the spawn → (a). Allocate per shot → (b). Add one stray
`Rng.randf(Rng.VISUAL)` → (c). **Return early from the integration branch in `_process` → (d).**
**Zero the gravity term → (d2), and only (d2).** The first draft pointed the gravity control at
(d), where it **cannot fail**: a casing with zero gravity still leaves the zero basis (it has
launch velocity) and still returns to it at end of life, because retirement is by lifetime
(`_tracer_life[i]`, `fx.gd:899-903` is the same shape). Provenance for the fall: F28 — all four
surveyed systems integrate gravity and rest on the floor.

**A7 — The table obeys a rule, not a snapshot.** In the style of `verify.gd:1393-1402`'s "no two
weapons collide onto one cadence": every weapon declares a spread floor and ceiling with
floor < ceiling; **both shotguns' floors are stance-invariant** (Olympia 5/5/5 and Stakeout 4/4/4
against every other row varying by stance — F18, Tier 1); the ordering by `kick` is not flat.

**"The shotguns' floor is strictly the widest" is DELETED. It is falsified by the very table R3
imports** — F18 gives the China Lake, not a shotgun, StandMin **5**, equal to the Olympia's 5 and
wider than the Stakeout's 4. Post-R3 nothing is strictly widest and the Stakeout is not in the top
two, so the check would go red on the commit that lands R3's numbers, and a red suite on a
deliberate change reads as "the change broke something" (audit §2). It happens to hold against
*today's* table (`weapons.gd:26` olympia 5.4, `:31` stakeout 4.6), which is why it read as true.

*Control:* **not** "reorder two rows" — every A7 claim reads values by key and is invariant to
Dictionary literal order, so that sabotage is inert. **Swap the m1911's and the olympia's floor and
ceiling values**, and separately change one shotgun's DuckedMin.

### What needs the frames gate

*The first draft gave A8, A9 and A10 no sabotage at all, against this section's own opening
sentence. They have one each now. A9 in particular is the check guarding R1, the item R8 refuses
to cut.*

**A8 — A `relations` rule pinning the hip pose geometrically.** None exists. `spawn.probes`
`sight_top_over_centre` (1.33056) and `gun_cx_over_centre` (1.34766) are absolutes today and the
next `-Bless` adopts whatever replaces them with no argument. Derive bands by **sweeping** `REST_POS`
over at least four values and writing the rejected rows into the rule's `why` — a band from one
measurement is a snapshot, which CLAUDE.md rejects.
*Control:* move `REST_POS` by one sweep step in the rejected direction and re-capture. **The band
must reject it.** That is what makes it a band rather than a snapshot with error bars.

**A9 — R1's shading, as a ratio.** `the viewmodel is lit` (`gun_mean / spawn.mean`) already bounds
the numerator; R1 must not move it outside `[4.5, 12.0]`. If M1 produces a face-value ramp, the
durable evidence is a *new* ratio — a probe on the weapon's top-plane region over one on its face
region — not the absolute means. That needs two new probe rects and both must report a pixel count,
per `frame_stats.gd:252-258`: a masked mean with an empty mask is the shape of every test that
passes while testing nothing.
*Controls, two:* (i) set `KEY` to 0.0 in `gunart.gd` so every face bakes to `FILL` — the
top-over-face ratio must collapse to 1.0 and the rule must fail. (ii) blank one of the two new
probe rects so its pixel count goes to zero — **the count bound must fail**, rather than the
masked mean silently returning 0.0. Restore in a wrapper that runs even if the command dies:
`gunart.gd` is reachable from the main scene and a parse error there hangs Godot for every agent.

**A9b — the step the first draft flagged and did not put in the plan.** `VM_RECT_HIP` and
`VM_RECT_ADS` (`shot_setup.gd:191-192`) are hand-measured pixel rects, and **any R1, R2, R4, R10 or
R11 change moves the silhouette under them** — `gun_mean` then becomes a measurement of wall, the
exact failure `shot_setup.gd:152-156` records. **Gated step: after every such change, run
`--frames spawn` and `--frames ads`, read the printed silhouette box, re-derive both rects, and
only then bless.**

**A10 — A capture of a state the gate has never seen.** Today only `ads`, `flash_hip` and
`flash_ads` photograph the weapon deliberately and all three are static. A `reload_mid` scenario
(predicate: `gun.state_t / gun.state_len` crosses 0.5) or a `recoil_peak` one (side-effecting
predicate firing on the shutter frame, exactly as `_fire_for_flash` does at
`shot_setup.gd:435-446`) is the only way to bound R4 or R5 visually. **A scenario with a clock is
not time-independent the way `ads` is** — it needs an arrival predicate, not a settle budget, or the
capture lands at a different point of the arc every run and the gate becomes noise. Registry rows
are policed: settle an exact multiple of 1/60 and under 10 s, `why` ≥ 20 characters, `until` arity
1. And the row and `tools/frames.ps1 -Bless` must land together or `checks/frame.gd:816-818` fails.
*Control:* freeze the `until` predicate to `return true`, so the shutter fires on the settle floor
instead of on arrival. **The captured statistic must move outside tolerance** — if it does not, the
scenario has no clock and does not need a predicate, which is itself the finding.

### The absolutes, which are the point of the whole package

*Added after review. **Multiply every `spread` and every `kick` by ten and A1 through A10 all stay
green** — A1 measures against `_spread_rad`'s own output and says so, A2 tests rates and
exclusivity, A3's claims are algebraic identities, A7's are ordering. The document's stated
highest-value assertion work was still entirely open after its own test plan. These two close it,
and they are the part of R9 that must not be cut.*

**A11 — One absolute cone width, as a literal with provenance.** `p._spread_rad(Weapons.spec("m14"))`
at the standing hip floor equals a **literal in radians**, tolerance 1e-4. Post-R3 under option
(b): `deg_to_rad(3.0)` = 0.052360 (F18 M14 StandMin 3°, Tier 1). Under option (a): the rescaled
floor, whose literal is `deg_to_rad(0.30)` = 0.005236 and whose provenance is "today's value,
preserved deliberately". Add the saturated ceiling as a second claim, same shape.
*Controls:* change the m14 floor column from 3 to 4 → fails. Multiply every `spread` by ten →
fails. **This is also the only check that catches R3's own stated silent factor of two** — the
`* 0.5` at `player.gd:872` left in when BO1 half-angles are dropped into the field.

**A12 — One absolute view-kick peak, likewise.** The M1911's peak `_recoil_pivot.rotation.x`
against a literal derived from F20's `ViewKickPitchMin/Max`, with the arithmetic written out in the
comment so the next reader can re-derive it rather than trusting it.
*Controls:* multiply every `kick` by ten → fails. Halve the impulse coefficient at
`player.gd:834` → fails.

**A13 — The per-shot VISUAL draw count inside `_shoot`.** Nothing in the suite bounds it — 
`checks/frame.gd:1108`/:1123 bound `fired` **listeners** only, and `checks/projectiles.gd:989-999`
bounds the five gameplay streams only. Drive `p._shoot` N times with `mag` refilled and assert
`Rng.stream(Rng.VISUAL).state` moved by **exactly** the expected count (today: 1 flash + 2 spread
per hitscan shot; R4 must add **zero**).
*Control:* add one `Rng.randf(Rng.VISUAL)` at `player.gd:834` → fails. This is the check that makes
R4's drawless bracket enforceable rather than aspirational.

**A14 — The `DEPTH` table obeys R2's cap-coplanarity rule.** No authored half-depth equals
`HAND_HALF` (5.0) or `HAND_HALF + LAYER` (5.14) art units, and no two parts of one weapon land on
the same half-depth. Computed through the same expression `_build` uses, not re-derived.
*Controls:* set one weapon's depth multiplier so a part lands on 5.0 → fails. Give two parts of one
weapon equal authored depth with `LAYER` removed → fails. Provenance: `gunart.gd:190-200` (the
z-fight the ramp exists to fix) and `:529-535` (the hands' fixed depths).

**A15 — The fov-110 clip exposure, asserted rather than measured once.** The first draft filed this
under "cannot be asserted" on the grounds that `_measure()` bakes its ratio on first call and "no
assertion can un-bake it". **That is wrong**: `_measured` is a plain `bool` (`viewmodel.gd:911`)
and the suite reaches into privates everywhere already (`p._ads`, `fx._impact_next`,
`atmos._muzzle_t`). Set `vm._measured = false`, set `_cam.fov = 110.0` (`settings.gd:67`'s
maximum), call `_measure()`, assert `max_screen_radius() < Player.RADIUS` and
`min_corner_depth() > 0.055`, then restore the fov and re-measure at 74.
*Control:* raise one `DEPTH` multiplier so it passes at 74 and fails at 110 — precisely the
regression R2 can introduce.
*Caveats, both real:* it runs `_measure()` **twice more** at 218,016 transformed points each inside
a ~5 s suite, so time it before committing; and it **must be registered last of all**, after the
four state-leaving sections, because it leaves the cached ratio rebuilt.

### What needs a human eye

The face-value bracket (M1), the casing arc, and whether a weapon's silhouette reads. `--shot` and
open the PNG. "Rendered a frame" is not a check.

### What cannot be asserted, said out loud

The zombie package's four failed metrics are the precedent, and this package has its own:

- **"Does the gun read as three-dimensional."** No cheap pixel statistic separates a nested slab
  from a stepped object. `gun_px` bounds the silhouette; nothing bounds the *form*. What guards it
  is M1's tabulated sweep and the reference PNG a human looks at.
- **"Is the recoil pattern good."** A6-style checks pin the peak, the sign, the return and the
  ordering. None of them can tell you whether it feels like a gun.
- **The absolute cone width — WITHDRAWN as an impossibility.** A1 is blind to the value by
  construction, and the first draft concluded from that that the value could not be pinned. It can:
  **A11** compares `_spread_rad`'s output to a literal with F18 provenance, and **A12** does the
  same for the kick. What survives of the original claim is narrower and still true: *A1* cannot
  see the value, so do not let A1's greenness stand in for A11's.
- **Whether the casing lines up with the ejection port.** Across a 1.4476 projection ratio there is
  no ground truth to assert against; the port position is unrecoverable (F33). A frame and an eye.
  **But the spawn TRANSFORM is four cheap deterministic checks and the first draft conflated the
  two.** R7 is 100% invented (F26) and therefore has the weakest provenance in the package; these
  are the only checks that would bind it to the four sources it cites. (i) `dot(spawn_vel, cam.basis.x) > 0`
  — ejects to the shooter's right (ioq3 `{0, −50±40, 100±50}`, Half-Life `right×(50..70)`);
  control, negate the lateral term. (ii) spawning while the player moves offsets the casing
  velocity by **exactly** the player's velocity (Half-Life `ev_common.cpp:152`, the detail this
  document says hobby implementations miss); control, drop the inheritance. (iii)
  `abs(dot(spin_axis, vel.normalized())) < 0.05` — tumble perpendicular to flight (OpenSpades
  `cross(-up, flyDir)`, which F28 calls "what makes it tumble rather than spin"); control, spin
  about the flight axis. (iv) after integrating to rest, the instance basis' y column is within 5°
  of world up — all four surveyed systems lie flat; control, skip the re-orthonormalisation.
- **`_measure`'s FOV exposure at 110 — WITHDRAWN.** See **A15**. `_measured` is a plain bool with
  an early return and the suite already writes privates; the ratio can be un-baked and re-baked.
  What is true is that it is *expensive* and *ordering-sensitive*, not that it is impossible.
- **The ADS spread floor against firing** — not in the first draft's list at all, and not covered
  by any of A1–A10 either. R3's decision says "add nothing while fully at the sights" (F17, Tier 1)
  and nothing checks it. It is cheap: at `_ads == 1.0` fire ten shots through the real path and
  assert `_spread_rad` is unchanged to 1e-6; at `_ads == 0.0` assert it grew. Control: remove the
  ADS guard from the fire-add. Bounded at both ends by construction. **Without it R3 can ship with
  the guard missing and every proposed check stays green.** Add it to R9 as part of A2.
- **R4's bracket, filled at both ends** — likewise absent. Seed, fire N, assert every peak lies in
  `[min, max]` **and** that the observed extremes fill at least 90% of the bracket. The second half
  is what stops it passing against a bracket collapsed to its midpoint, which is the inert case.
  Provenance: F20's `ViewKickPitchMin/Max`. Controls: widen one weapon's draw past its max (first
  half); pin the draw to the midpoint (second half). Add to R9 alongside A12.
- **The second half of F23's `reduce_motion` aim buff** — A3(f) covers the kick damping; nothing
  covers the bob. `Settings.reduce_motion` zeroes `amp` (`player.gd:709-710`), which zeroes the
  `slow` term written to the aim-bearing `RecoilPivot` (`:717-718`). Check: with `_moving = true`,
  assert `_recoil_pivot.rotation.x != _kick` with reduce_motion off and `== _kick` with it on.
  Control: drop the `not _reduce_motion` clause at `:709`. F23 calls this an unasserted
  accessibility-to-balance interaction and the first draft's test plan did not answer it.

---

## Coverage gaps

**Does not exist** (searched and established, not merely unfound):

1. **Shell casings in the ancestor** — exhaustive case-insensitive grep over all 3476 lines returns
   only CSS font stacks and the `shells` reload flag. Not a restoration.
2. **Any casing, brass or ejection code in this repo.** Zero gameplay matches.
3. **Spread bloom, first-shot accuracy, recoil pattern data, or a horizontal recoil channel** in
   either source. `spreadDeg` is recomputed from a static table every shot in both.
4. *(Moved. See item 15b — it was misfiled here by this document's own criteria.)*
5. **Per-weapon reload animation.** The ancestor's arc is identical for all thirteen; only the
   duration varies. `SHELL_SCALE` is the only differentiation in the port and it is new design.
6. **Tactical-vs-empty reload in any surveyed codebase.** M1's Coverage Gap 1 now stands wider: not
   Half-Life, not CS 1.6, not OpenSpades, not Quake 3 — all four treat the magazine as one integer.
   BO1 *does* have it (F14), so the reference exists even though no implementation does.
7. **A recorded decision about which way recoil should pitch the view.** Nothing in `player.gd`,
   `notes/`, or `scripts/dev/checks/` mentions the kick's direction; `grep -rn kick scripts/dev/checks/`
   returns zero.

**Not found, which is different:**

8. **BO1's `.efx` shell-eject assets** — velocity, spin, lifetime, collision, ejection side. Not in
   any public rawfile dump (T5 compiles particles into fastfiles), and the WEAPONFILE format has no
   such fields. **Every casing number in R7 is borrowed from other engines, and says so.**
9. **Vanilla `adsSpread` for the two shotguns** and **vanilla `reloadAddTime` for everything** — both
   named as retuned in the mirror's own changelog, and both weapons post-date the change, so there
   is no earlier snapshot to diff.
10. **BO1's multiplayer weapon files**, wanted as an independent MP-vs-ZM cross-check. The ZM
    deviation finding therefore rests on the structural argument (separate `_zm` assets carrying
    `parentWeaponName`) rather than a field-by-field diff.
11. **How `specialty_rof` reaches `bRapidFire`.** The number (1/0.75) is corroborated twice; the
    plumbing is not traced, and `rapidFire = 0` in every ZM file parsed.
12. **CS:GO's recoil-table generation algorithm.** The data format and real AK-47 values are in hand;
    the code that turns seed+angle+variance into a table was not read, and the widely repeated
    description is **speculation** here. Moot given R3/R4 reject the format anyway.
13. **Whether Godot 4.7's `ArrayMesh` stores `ARRAY_COLOR` as float or RGBA8 unorm.** This decides
    whether the key light's 1.025–1.110 multipliers survive on the brightest table entries or are
    already being silently clipped. It bears directly on R1 and I could not settle it.
14. **Godot engine source was read on `master`, not the pinned 4.7 tag.** The MultiMesh 16-bit
    packing note and the empty SDF-collider branch are implementation details that can move.
15. **No measured performance number for a moving MultiMesh on WebGL2** (M4), and **no measurement of
    anything in this document** — no `--verify`, no `--shot`, no `--frames`, no `--sim` was run by
    any of the nine researchers, by me, or by any of the three reviewers. Every repo number here is
    arithmetic over source. **This includes the green assertion total of 693**: only
    `ASSERTION_FLOOR := 692` (`verify.gd:166`) was read directly, and every consequence drawn from
    "one assertion of slack" rests on a number nobody measured.
15b. **A Godot 4 shell-ejection reference implementation.** *Moved here from "Does not exist"
    after review, and the reviewer was right: the item's own text disqualified it.* Repository
    search returns 2 false positives; the one forum thread has a single reply and no code. But
    GitHub's code-search API returned `total_count 0` for queries with **known matches** throughout
    the session, grep.app was behind a challenge, and searchcode 404s — **three of the primary
    search surfaces were broken**, disclosed in the same sentence that filed the result as an
    established absence. Calling it a "bounded negative" does not change which half of this section
    it belongs in. It rests on repository search, web search and the four templates M1 read, and
    that is a soft absence.
16. **BO1's base `shotCount` for the Olympia and the Stakeout** — needed by R12 and never reported,
    despite the Pack-a-Punch figures ("Olympia → 8→12 pellets") being in hand from the same asset.
17. **The call site that turns `BG_GetSpreadForWeapon`'s degrees into a fire direction** (F17). Not
    among the KisakBlack files read. **Every number in F18 and F18b rests on it**, to a factor of
    two.
18. **The values behind four source-index credits that appear nowhere in the body.** Minecraft's
    `ItemModelGenerator` plate thickness and 25° first-person tilt (row 21) — the single most
    on-point voxel-style precedent in the corpus, and this document's own style contract now leans
    on the *structure* without having the numbers; OpenSpades' `cockFade` gate and timing (row 15),
    which is the reference implementation of exactly what **R6** proposes and which R6 cites
    nothing from; ReGameDLL's `DefaultShotgunReload` parameter list (row 17), absent from **R5**;
    and `V_DropPunchAngle`'s decay constants (row 14), absent from **R4**. Xonotic (row 16) is a
    softer case: it is quoted with four adjectives and zero parameters where ioq3, Half-Life and
    OpenSpades each get a full set. **The credits imply coverage the body does not have.** They are
    not deleted, because the sources really were read and are the right ones — but the
    implementation package must go back for those values, and until it does, treat those four rows
    as *leads*, not as evidence.

---

## Where the corpus was wrong

Expected to have content, per CLAUDE.md, and it does.

- **`golden.json` has 24 relations, not 12 and not 22.** Two researchers gave two different wrong
  counts. Verified by parsing the file.
- **`gunart.gd:197`'s "4.14 units" is off by one `LAYER`.** The Thundergun has 11 parts at indices
  0…10, so max half = 2.6 + 10×0.14 = **4.00**. The file contradicts itself — `PROUD`'s comment gets
  the same weapon right (10 × 0.04 = 0.4). `HAND_HALF`'s justification at `:313-315` cites the wrong
  figure too. Report both as one hunk; do not silently change the constants.
- **`player.gd:934`'s ancestor citation is off by one.** It cites `html:2567` for the pellet spread;
  the `*0.0175*2` line is **:2568**. The projectile citation (`:2553`) is exact.
- **`checks/projectiles.gd:562-569`'s own citation is stale** — it says `viewmodel.gd:829` for where
  the FOV ratio is baked; it is `:917`. The comment's *warning* is correct and important.
- **`projectile.gd:361-364` cites `game_state.gd:241`** for the no-pause rule; line 241 is
  `nuke_clearing = false`. The pause statement is `:299` and the `STATE_TITLE` comment `:285-287`.
- **The brief's `body` field is not a damage multiplier.** It is an audio synthesis parameter
  alongside `freq` and `thump` (`weapons.gd:21`, `player.gd:836`), flattened out of the ancestor's
  `snd:{}` sub-dictionary at `html:1454`.
- **CLAUDE.md's reason for leaving spread on VISUAL is wrong** (the sim never draws a spread). The
  rule stands; the reason should be corrected.
- **`M1-viewmodel-systems.md:36`/`:540`'s ~72 triangles per weapon** is 1.5×–4.5× low against the
  shipped builder (F6).
- **`M3-combat-fx.md`'s three in-tree citations are all stale** (`zombie.gd:85`→`:448`,
  `player.gd:73`→`:308`, `main.gd:90`→`lighting.gd:354`). Its reasoning is still good; its pointers
  need re-resolving.
- **`ancestor-diff.md`'s port-status column is four milestones stale** across the whole weapon
  area — it says the port has no viewmodel, no recoil spring, no muzzle flash and no projectiles.
  All four have shipped. Its **ancestor** citations, by contrast, checked out on every one tested.
- **`naxIO/cs16-recoil-godot`'s punchangle decay does not match Half-Life**, and its inline comment
  attributing the 0.0225 s recovery step to "community analysis, not primary source" is wrong — the
  constant is in ReGameDLL's `weapons.cpp` directly. Use its constants, not its decay.
- **DenKirson says the view-kick return runs at 1/16 (0.0625); the shipped constant is 0.06.**
  Superseded rather than rejected, noted so a later reader does not think one of us is wrong.
- **Teardown's voxel size could not be established** — the wiki says 10 cm, a search result says
  1 cm, and the official modding docs are silent. **Do not build on that number.**

*Added after review — three more in-tree citations that are stale, and two comments that are
wrong about behaviour:*

- **`weapon.gd:29`'s own citation is stale in exactly the way the four above are.** It says
  "hud.gd:868-869 prints `--` for the magazine"; the real comparison is **`hud.gd:1491-1492`**
  (`var by_shell: bool = gun.state == WEAPON.State.RELOAD_SHELL` / `var mag_txt := "--" if ...`).
  R6's rejected option turns on that exact line, so the package will read it.
- **`gunart.gd:266-271` is wrong about the emissive parts, not only about the knife** (F36). Green
  1.0 × the 0.86 floor is 0.860, which does not clear `lighting.gd:215`'s 0.92 on the −Y/+X/−Z
  faces, so "clear 0.92 on **every** face" is false for both the Ray Gun's lens core and the
  Thundergun's emitters.
- **`gunart.gd:524-526`'s precondition does not do the work F7 asked of it.** It is an assertion
  about the 2-D outline; `_inflate` never sees a depth. Report it alongside the `4.14` hunk: the
  comment is not wrong, it is just not the thing that bounds depth.

*And this document's own first draft, corrected in place. Recorded because a brief that overturns
other people's citations and not its own is not applying the rule:*

- **F3's "1.29:1"** was the oblique-facet span, not a box's. A box is **1.2448:1**.
- **F6's raygun 240** dropped the two hand boxes every other row includes. It is **264**, and the
  mean is **160.0**, which is what makes the prose's own 2080 total balance.
- **F5** cited `ADS_LEVEL` to `viewmodel.gd:334-336`; it is `:372`.
- **F12** cited the `shells` comment to `weapons.gd:16-19`; it is `:13-16`.
- **F21** cited "the gun drops and the muzzle rises" to `viewmodel.gd:797-803`; that is the code,
  the comment is `:268-270`.
- **F26's grep does not reproduce as written** — the four-term pattern returns **zero** lines and
  the three cited hits need `shell` in the alternation. The corrected result is stronger.
- **The "Sim baselines" paragraph** attributed `:249-263` and `:501-521` to `weapon.gd`, which is
  330 lines. Both belong to `balance_sim.gd`.
- **The "rule that is easy to miss" about `checks/frame.gd:1108` was backwards.** That check calls
  `_fire_once`, which emits `player.fired` directly and never enters `_shoot`, so it bounds `fired`
  **listeners** and cannot see a draw added inside `_shoot` at all.
- **"R9" was referenced twice and never written.** It is now a recommendation.
- **F7's 0.48 mm screen-radius bound is disputed** and neither figure is a measurement.
- **Four of the first draft's ten proposed assertions named a control that could not fail the
  check it was named for**, and three named no control at all. That is the failure mode
  CLAUDE.md's "every assertion ships with a control" section exists to catch, reproduced inside a
  document that quotes it.

---

## Source index

| # | Source | Tier | Used for |
|---|---|---|---|
| 1 | `scripts/data/gunart.gd` (read) | 1 | ART/SLIDE/MUZZLE/GRIP, `_build`/`_corners`/`_extrude`, `UNIT`/`BASE_HALF`/`LAYER`/`PROUD`, FILL/KEY/KEY_DIR, F1–F8 |
| 2 | `scripts/entities/viewmodel.gd` (read) | 1 | Nine channels, `_mesh_pose` purity, `_measure` sweep, clip budget, slide, `KICK_MAX`, F9–F11, F22 |
| 3 | `scripts/entities/player.gd` (read) | 1 | Fire path, `_spread_rad`, disc sampling, recoil spring and sign, bob-on-aim, F21–F25 |
| 4 | `scripts/entities/weapon.gd`, `scripts/data/weapons.gd` (read) | 1 | Seven states, `RELOAD_SHELL` re-entry, `_shell_time`, the whole weapon table |
| 5 | `scripts/world/fx.gd`, `shader_warmup.gd`, `quality_governor.gd` | 1 | Pooling idioms, the no-Rng rule, `_multimesh`/`_retire`/`custom_aabb`, warm registration, F29/F31/F32 |
| 6 | `scripts/dev/verify.gd`, `checks/*.gd`, `shot_setup.gd`, `frame_stats.gd` | 1 | Registration, `ASSERTION_FLOOR` 692, the two spread assertions, VM rects, `masked()` |
| 7 | `notes/perf/frames/golden.json` (parsed) | 1 | 24 relations, 7+7 viewmodel probes, tolerance block, the bless asymmetry |
| 8 | `kriegsnacht.html` (read) | 1 | GUNART :1151-1207, MUZZLE :2020, `drawViewmodel` :3106-3172, spring :2960, kick impulse :2525, shake :2526, spread :2531/:2553/:2568, reload speed :2942, `shells` :1460/:1465 |
| 9 | Shipped T5 `_zm` weapon assets, via `Jbleezy/BO1-Reimagined/weapons/sp/` | 1 data / 2 provenance | F12–F14, F18, F20, F27; ammo, reload, hit-location multipliers. **Not a Treyarch rawfile dump** — the only public text copies are Plutonium-era mods; spread and kick fields diffed byte-identical across five years for six weapons; known-modified fields listed in Coverage gaps 9 |
| 10 | `SwagSoftware/KisakBlack` `src/bgame/bg_weapons.cpp`, `src/cgame*/cg_view*.cpp` | 1 | `BG_GetSpreadForWeapon`, `PM_AdjustAimSpreadScale`, `PM_Weapon_AddFiringAimSpreadScale`, `BG_WeaponFireRecoil`, `CG_KickAngles`, the 0.4 interrupt-ignore fraction, Speed Cola and Double Tap clock multipliers |
| 11 | `wiki.zeroy.com` CoD7 dvar list | 3 | `perk_weapReloadMultiplier` 0.5, `perk_weapRateMultiplier` 0.75, `bg_aimSpreadMoveSpeedThreshold` 11, `jump_spreadAdd` 64 |
| 12 | DenKirson, *Kicks and Speeds: Recoil In-Depth* | 3 | Independent corroboration of the recoil model; the average-direction explanation; one disagreement (1/16 vs 0.06) |
| 13 | `ioquake/ioq3` `cg_weapons.c`, `cg_localents.c` | 1 | Casing spawn/velocity/spin/lifetime/bounce, swept trace, rest condition, sink despawn, 512-entity pool |
| 14 | `ValveSoftware/halflife` `ev_common.cpp`, `ev_hldm.cpp`, `shotgun.cpp`, `view.cpp` | 1 | Casing velocity inheriting player velocity; per-weapon eject offsets; `CShotgun` shell-by-shell + cancel; `V_DropPunchAngle` |
| 15 | `yvt/openspades` `GunCasing.cpp`, `ClientPlayer.cpp`, `Skin/*/View.as` | 1 | Casing integration, tumble axis, rest-and-flatten; no-AnimationPlayer multi-part weapon composition; the pump `cockFade` gate; the deliberately absent shotgun casing |
| 16 | `xonotic-data.pk3dir` `casings.qc` | 1 | Client-side-only casings, global cap, decoupled substep, alpha fade, delete-if-trace-starts-solid |
| 17 | `s1lentq/ReGameDLL_CS` `weapons.cpp`, `wpn_shared/*` | 3 | `KickBack` model and constants; the 0.4 s / 0.0225 s recovery ramp; `DefaultShotgunReload` parameterisation. Reimplementation, not Valve code |
| 18 | `SteamDatabase/GameTracking-CS2` `weapons.vdata`, `items_game.txt` | 2 | The five-number spray-pattern format and real AK-47 values — **rejected for use**, cited so the argument is not re-run |
| 19 | `godotengine/godot` `drivers/gles3/shaders/scene.glsl`, `particles.glsl`, `storage/mesh_storage.cpp` | 1 | MultiMesh instance colour/custom on Compatibility, 16-bit packing, the `#else vec4(0.0)` branch, dirty-region upload, empty SDF branch. **Read on `master`, not 4.7** |
| 20 | Godot `doc/classes/` (MultiMesh, ParticleProcessMaterial, GPUParticles3D, BaseMaterial3D) | 1 | 16-bit packing note, `angular_velocity` restriction, `emit_particle` unsupported, `grow`/`CULL_FRONT` |
| 21 | Minecraft `FaceBakery.java`, `ItemModelGenerator.java`, `item/handheld.json`; TerraFirmaCraft `RenderHelpers.java` | 1 | The 1.0/0.8/0.6/0.5 axis ramp, independently in two codebases; the 1/16 plate extrusion; the 25° first-person tilt |
| 22 | `FlansMods/FlansMod` `ModelColt.java`, `ModelSten.java` | 3 | Per-part box dimensions for blocky guns; depth varying 6× within one weapon; receiver deepest |
| 23 | 80.lv, *Weapon Art Tips* (Patrick Sutton, BO4) | 3 | The 70-20-10 three-value hierarchy; "increase the number of planes light can hit" |
| 24 | `notes/research/M1-viewmodel-systems.md`, `M3-combat-fx.md`, `R1-renderer-constraints.md`, `R4-canon-numbers.md`, `notes/analysis/ancestor-diff.md` | 1 | Prior art, and four sets of stale citations corrected above |

**Rows 14, 15, 16, 17 and 21 credit values that do not appear in the body.** See Coverage gap 18.
Treat them as leads, not as evidence, until the implementation package brings the numbers in.

---

## What the critics found

Three adversarial reviews — a constraints lens, a completeness lens and a testability lens. Every
defect was re-checked against the source before anything moved. Minor citation drift is folded into
**Where the corpus was wrong** and not repeated here; this table is the non-minor set.

| # | Defect | Verdict | What was done |
|---|---|---|---|
| 1 | **R4 put a ballistically-live per-shot draw on `Rng.VISUAL`** — a second instance of the one violation CLAUDE.md forbids adding | **Upheld.** `player.gd:299`/`:305` put `RecoilPivot` above `Camera3D`; `:718` is its sole writer; `_hitscan` aims off `_cam.global_transform.basis` (`:878`). A recoil draw decides where the round goes. And no stream passes: `checks/projectiles.gd:989-999` drives four real `p._shoot` calls through the kick line at `:834` | R4 item 3 rewritten: the bracket is **counter-derived and drawless**, per R7's precedent. **A13** added to enforce the draw count, since nothing in the suite bounds VISUAL inside `_shoot` |
| 2 | **The `checks/frame.gd:1108` guard offered for that draw cannot fire** | **Upheld, and it was backwards.** `_fire_once` (`:1141-1149`) emits `player.fired` directly and never calls `_shoot`; the oracle is cloned at `:1069-1073` before the emits. It bounds `fired` **listeners** only | The paragraph in "The constraints that shape all of it" replaced with what is true, including the second half: a draw anywhere in `_shoot` shifts bullet placement, because `_hitscan`/`_launch` draw last |
| 3 | **R3 recommends BO1's spread table "verbatim" without computing what it does** — 10–23× on the M14, 25–30× on the China Lake | **Upheld, and it is the largest defect in the document.** Verified against `weapons.gd:25-36` and `player.gd:872`; a standing M14 goes from 100% to 4.8% hit rate at its own 26 m range | **F18b** added: shipped half-angle, BO1 floor/ceiling, multiplier, and hit probability against `HIT_RADIUS` 0.30 at 5/10/26 m. R3 now forces an explicit choice between shape-only (recommended) and absolutes. **F18c** adds the same for `kick` |
| 4 | **"R9" is referenced twice and was never written** — the highest-risk change gated on a section that does not exist | **Upheld.** Eight headings, R1–R8 | **R9** written as the assertion package, with per-recommendation floor deltas so a cut subtracts rather than skips |
| 5 | **"Keep the voxel style" does no work anywhere in the document** | **Upheld in substance, one part rejected.** The constraint was never defined or used as a criterion. *Rejected:* "not one word changes if you delete it" — R1's inverted-hull rejection is already a style argument ("the only outlined object in a scene whose whole art argument is that the gun is built the same way as the room") | **The style contract** added as five testable rules, and R1's and R2's rejections re-run against it. The Minecraft plate-extrusion precedent is now named as what the pipeline actually is |
| 6 | **The package adds zero triangles under a request that leads with "improve the gun models"**, and F5's own stated remedy ("+Z geometry") is unbuilt | **Upheld.** Every geometry proposal was rejected or deferred, and F6 removes the budget objection | **R10** added: rear sight / charging handle / stock comb, with the `SLIDE` index hazard, the `_corners` parallel walk, the `_measure` cost and the chalk-plaque desync (F8) as constraints. Ordered **after R2** |
| 7 | **F9's headline animation defect (IDLE has no appearance) gets no recommendation** — "animation" was silently reduced to "reload" | **Upheld** | **R11** added (breathing offset inside the existing single writer), with draw/holster/ADS-transition/bolt-release explicitly listed out of scope |
| 8 | **"Shell patterns" was read as brass with no ruling on the pellet reading** | **Upheld.** `player.gd:849-850` is six independent full-cone draws; the Olympia is a step function from 1.4 expected pellets to zero across 1 cm of range | **F35** and **R12** added, including the ruling that R12 displaces R7 if pellets were what was meant |
| 9 | **Every foreign casing number is in its source engine's units and none is converted** — R7 ports at ~40× scale | **Upheld for ioq3 and Half-Life; the OpenSpades conversion is REJECTED.** The reviewer's 0.81 m/s² assumes the Quake inch for a Voxlap-derived game; the two plausible readings put it between 0.8 and 23 m/s² and this project has not established which | F28 gains a units box: ioq3 and Half-Life converted with the cross-check that makes the conversion trustworthy, **OpenSpades marked "do not convert, take structure only"**. R7's bracket restated in metres |
| 10 | **R7 specifies everything about the casing except what it looks like** | **Upheld** | Mesh spec added: `gunart._extrude`, 0.019 × 0.0095 × 0.0095 m, 12 triangles, one unlit vertex-colour material registered in `fx.materials()`, tint multiplies, display-space (constraint 6) |
| 11 | **F17's "half-angle" is asserted without the call site that decides it** — a silent factor of two under all of F18 | **Upheld** | F17 downgraded to a **Tier 2 open assumption** with the missing function named; R3 gated on closing it; Coverage gap 17 |
| 12 | **Coverage gap 4 is filed under "does not exist" while its own text discloses three broken search surfaces** | **Upheld** | Moved to "Not found, which is different" as **15b**, tool-failure disclosure verbatim |
| 13 | **A1(a)'s control sabotages `_spread_rad`, which moves the test's reference too** | **Upheld** — the audit's recorded perk-test shape | Control moved to the **call site** (`player.gd:884`); **A11** added as the absolute the identity structure cannot provide |
| 14 | **A1(b)'s control (`spread = 0`) cannot fail (b)** | **Upheld.** `_hitscan` skips the rotation at `:885`, every angle is 0, and `0 ≥ 0` passes | Control replaced: break the **filling** (`sqrt` → constant 0.3), leaving the width untouched |
| 15 | **A1(c)'s control is not exclusive** | **Upheld** by `player.gd:881-883`'s own 1.41× comment | "Only" dropped; (c) restated as the **diagnostic** claim. The `sqrt` control for (d) is confirmed genuinely exclusive and now says so |
| 16 | **A1 has no sample-count assertion and the sample set is silently lossy** | **Upheld.** `player.gd:899-900` and `:902-907` emit nothing on a miss or a zombie hit, truncating inward | **A1(e)** added, with sizing for N and the entry-point contradiction (M5 said `_hitscan`, A1 said `_shoot`) resolved to `_hitscan` |
| 17 | **A4 counts an event F11 proves is never emitted** | **Upheld.** `weapon.gd:328` re-enters the same ordinal; `player.gd:732-735` emits only on a change | Rewritten to count `gun.mag` arrivals (`weapon.gd:320`); `weapon_state_changed` kept only for the magazine claim |
| 18 | **A4's timing control (halve `def.reload`) moves both sides** | **Upheld.** `weapon.gd:284-289` derives per-shell time from the same def | Literals with F13/F16 provenance (4.60 / 1.77 / 2.30 s), plus the asymmetry ratio ≥ 0.35 as its own claim |
| 19 | **A3(e) "thirteen peaks strictly ordered by kick" is red on arrival, twice** | **Upheld.** Twelve rows in `TABLE`; `m16` and `rpk` both 1.5 | Replaced with an identity (`peak/kick` constant to 1e-4) plus a range (`max/min ≥ 4.0`, provenance 4.2/0.9), each with a control that bites |
| 20 | **A3(b) — the most important claim in the package — has no control** | **Upheld** | Control stated (restore the `-=`) and provenance for "up" given (`player.gd:426`) |
| 21 | **A3 reads `_kick + slow` and restores nothing** | **Upheld.** `player.gd:717-718` | `_moving = false` pinned, `rotation.x == _kick` asserted as a one-writer check, and all four perturbed fields restored |
| 22 | **A3(d)'s 1e-3 absolute may fail against a first-order integrator** | **Upheld.** `player.gd:686-687` is semi-implicit Euler; ω·dt = 0.226 at 1/30 | Restated as a **relative** bound whose provenance is a measurement that must be taken first |
| 23 | **A7's "shotguns' floor is strictly the widest" is falsified by R3's own imported table** | **Upheld.** China Lake StandMin 5 ties the Olympia; Stakeout is 4 | Claim deleted, replaced with "both shotguns' floors are stance-invariant" (F18, Tier 1). Control changed from the inert "reorder two rows" to swapping two weapons' values |
| 24 | **A6(a)'s pellet cross-check cannot fail** | **Upheld.** `fired` is emitted once at `player.gd:837`, before the pellet branch | Restated to assert ring +1 **while `surface_impact` fires 6**, which discriminates the mistake actually available (`fx.gd:296`) |
| 25 | **A6(d)'s control (zero gravity) cannot fail it** | **Upheld** — retirement is by lifetime | Split into (d) with an integration-branch control and **(d2)** "the casing falls" with the gravity control |
| 26 | **A2's control does not bite on most of the roster** | **Upheld.** MoveAdd ≥ Decay on seven of twelve rows at full speed | Test case pinned just above `bg_aimSpreadMoveSpeedThreshold`, and the comment must say why that is the discriminating case |
| 27 | **A8, A9, A10 name no sabotage at all**, against the section's own opening sentence | **Upheld** | One or two controls each, including the empty-probe-count case for A9 that `frame_stats.gd:252-258` exists to warn about |
| 28 | **The document's own headline gap is still open after all ten assertions land** | **Upheld.** Every A1–A10 claim is scale-invariant or measured against the implementation's own output | **A11** and **A12** added as the two absolutes, and named in R9 as the un-cuttable core |
| 29 | **`ASSERTION_FLOOR` plan states no delta and ignores the cut list** | **Upheld** | Per-recommendation deltas in R9; R8 now says a cut **subtracts**, and the itemised `verify.gd:145-165` prose style is required |
| 30 | **Nothing says where the new checks sit in the registration order**, though A1/A3/A5 all pose the rig | **Upheld.** `checks/projectiles.gd:562-571` already documents the hazard | Registration **rule** added: after `verify.gd:262`, A15 last, new files (not appended to `projectiles.gd`) so the directory audit enforces the hunk |
| 31 | **R4 item 3 says nothing about `viewmodel.gd:608`'s twin spring** | **Upheld.** Both carry 46/11 and `viewmodel.gd:247-248` says they are matched on purpose | Decision stated: the bracket lands on the **player's** impulse only, because `_measure` sweeps the viewmodel kick over `[0, KICK_MAX]` and nothing beyond it |
| 32 | **F7 blames the hands' `PROUD` exemption for a depth hazard it cannot have** | **Upheld.** `_inflate` (`:611-644`) takes a `PackedVector2Array` and never sees `half` | Restated as a **cap-coplanarity** rule over the `DEPTH` table (no depth may equal 5.0 or 5.14), and made **A14** rather than a comment |
| 33 | **F31 sends R7 through `_multimesh()`, which never sets `use_custom_data` and returns a bare `MultiMesh`** | **Upheld.** `fx.gd:773-784` names only two flags; `grep use_custom_data scripts/` → no hits; `custom_aabb`/`add_child` live in `_ring` (`:756-757`) | R7 rebuilt on **`_ring()`**; the shared-helper cost of adding `use_custom_data` stated; R7 declared not to need it |
| 34 | **F6's raygun row omits its gloved hands** | **Upheld.** 5 rects × 12 + 5 circles × 36 = 240, plus 2 `ONE_HANDED` hand boxes × 12 = **264**; the 2080 total only balances at 264 | Corrected; mean is **160.0** |
| 35 | **F3's 1.29:1 is not a box's bracket** | **Upheld for F3; the proposed fix for R1 REJECTED.** Four box values span **1.2448:1** and F3 is corrected. But R1's number governs a **bevel**, and a bevel normal has an x component, so it escapes both the box bracket and the 1.291 oblique ceiling — the real ceiling there is `FILL + KEY` = 1.16, i.e. **1.349:1**. Substituting 1.2448 would have made R1 *more* wrong | F3 states all three brackets; R1 uses 1.349:1 and the reasoning is written out. R1's unreproducible "1.048" bevel figure is **withdrawn** |
| 36 | **R1 has no rule for non-axis-aligned side facets** — undefined at 13 circles and 2 rotated rects | **Upheld.** `_extrude:711-718` emits one normal per side quad; `CIRCLE_SEGS` 10 | A blend rule proposed and mandated as part of R1 **before** M1 sweeps anything |
| 37 | **`gunart.gd:266-271` is wrong about the Ray Gun too, not only the knife** | **Upheld.** Green 1.0 × 0.86 = 0.860 < `GLOW_THRESHOLD` 0.92 (`lighting.gd:215`) | **F36** added; M2 must sweep the emissive parts as well as the blade |
| 38 | **F7's 0.48 mm screen-radius bound is not reproducible from the committed numbers** | **Recorded as an unresolved dispute, neither figure adopted.** The reviewer's 1.5–4 mm band and the document's 0.48 mm differ by up to 8× and **neither is a measurement** — the phase ran nothing | F7 and M3 both say the headroom is **unknown**, and M3 is a gate on committing any `DEPTH` table |
| 39 | **F26's grep does not reproduce** | **Upheld, and the corrected result is stronger** — the four-term pattern returns **0** lines; the three cited hits need `shell` | F26 rewritten with both greps stated separately |
| 40 | **M5's decision rule is pointed at "too narrow" when the risk is "far too wide"** | **Upheld.** BO1's own floor/ceiling ratios are already 1.2–2.5× | Rule inverted: an abort condition on hit-rate loss first, the visibility test second, F18b as the baseline |
| 41 | **R8 has no branch for the world M1's own decision rule produces** | **Upheld** | Branch added: if M1 abandons R1, R2 leads, R10 moves to second, A9 is deleted rather than skipped |
| 42 | **Four source-index rows credit values that appear nowhere in the body** | **Upheld; the proposed remedy partly declined.** I could not fetch the values in a read-only phase and will not invent them | Credits kept (the sources really are the right ones) but **Coverage gap 18** names all five rows and marks them leads rather than evidence |
| 43 | **The 693 assertion total is unverified** | **Upheld** | Flagged at the Bottom line, at the `ASSERTION_FLOOR` paragraph and in Coverage gap 15 |
| 44 | **`weapon.gd:29`'s citation is stale in the same way as the four the document corrects** | **Upheld.** `hud.gd:1491-1492`, not `:868-869` | Added to **Where the corpus was wrong**, where R6's rejected option will need it |
| 45 | **A5 is a cross-package tripwire under only one of R6's two options** | **Upheld.** The magazine-delta latch is a `viewmodel.gd`-only change | Option named (the latch), and the cross-package claim dropped with it |
| 46 | **A9 omits the `VM_RECT_*` re-derivation step the document flags elsewhere** | **Upheld** | **A9b** added as a gated step, not a paragraph |
| 47 | **Four "cannot be asserted" claims are wrong** — the fov-110 exposure, the absolute cone, the casing transform, plus three uncovered contracts | **Upheld.** `_measured` is a plain bool with an early return (`viewmodel.gd:911-913`) and the suite writes privates everywhere | **A15** written with its control and its two real caveats (runtime cost, must register last); the casing-transform four written out with sources and controls; the ADS-floor, bracket-fill and reduce-motion-bob checks added |

**Three rejections, restated so they are not re-litigated.** (i) Substituting the box bracket
**1.2448:1** into R1's bevel rejection would have been wrong — a bevel is the one geometry that
escapes it, and the governing figure there is 1.349:1. (ii) The claimed **OpenSpades metric
conversion (0.81 m/s²)** is not adopted; its unit is a voxel block of unestablished metric size and
the two readings differ by 28×. (iii) "Delete the voxel constraint and **not one word** of the
document changes" is an overstatement — the inverted-hull rejection was already a style argument —
though the constraint's absence everywhere else was real and is now fixed.

---

## Merged in afterwards: the scholar run, and the decisions taken

The nine researchers above ran alongside a separate `scholar-router` pass that this document's
synthesis phase never saw. Most of it converged — both found the CoD weapon files, both found the
segmented-reload structure, both found the Olympia is a break-action. **Five things did not
converge**, and they are recorded here rather than woven in, so the seam stays visible.

### S1 — ADS is symmetric here and asymmetric in the reference

`player.gd:186` is `const ADS_TIME := 0.22`, and its comment hand-waves it as "about a quarter of
a second". The MP40's weapon file gives `adsTransInTime = 0.22`. **That is an exact corroboration
of a number this project guessed**, and the comment should now cite it rather than hand-wave.

But `player.gd:642` is `_ads = move_toward(_ads, to, dt / ADS_TIME)` — **one rate both ways**. CoD
is consistently asymmetric: ~0.22 s in, ~0.4 s out. Coming out of the sights faster than the game
you are porting means the sighted pose has no commitment cost, which is most of what ADS is for as
a decision. One constant, and it is the cheapest real change in the whole package.

Not in R1–R12. It belongs with R3 as part of the same stage.

### S2 — The magazine must be found by a function, never a table

The scholar run appended a hand-read table of magazine part-indices and **four of seven rows were
wrong** — `pm63`, `ak74u`, `m16`, `m1911`, `rpk` all misidentified by pattern-matching "box below
the receiver" and taking the first hit, which grabs foregrips. Only the `mp40` row survived, and
the mag-drop finding rests on that one row.

`gunart.gd:402-418` already argues against exactly this shape, about sight heights:

> *"Thirteen hand-read top edges would be a second copy of the art, and it would go stale the
> first time a part moved by a unit — silently."*

So R5's magazine work needs a `magazine_index(key)` **derived from the art** — colour, tall-and-
thin aspect, grip-adjacent x — cached the way `sight_height()` caches. A hand-written table is
already demonstrated to be 57% wrong on first authoring, which is worse than the failure mode that
comment was written to prevent.

### S3 — The mag-detach evidence is contested and no number may be read off it

`notes/research/visual-corpus/` holds three JPEGs and a manifest. The reload card claims BO1's MP40
magazine visibly leaves the weapon, measured by connected-component labelling on the source PNG's
alpha (2 components, no opaque path between).

Two agents attacked it and one attack lands:

- **Rejected:** that the flat RGB(178,76,53) background at stdev 0.00 proves a synthetic render.
  The stored file is a JPEG re-encode of a *transparent* PNG over the wiki's page fill; the
  manifest's `_capture_method` says so, and the alpha measurement was not run on that fill.
- **Upheld:** there are **no hands** in the frame. Every CoD reload shows the off hand on the
  magazine, and the corpus's own third card proves this wiki keeps hands when present.
- **Upheld, and sharper:** the card's own bboxes show **both components clipped by the bottom
  edge** — detached object `(0,276)-(80,367)`, weapon `(39,0)-(659,367)` on a 661x368 canvas. So
  "no opaque path connects them" holds *within* the canvas and cannot exclude a connection below
  it. The topological claim is weaker than the card states; what actually carries it is the card's
  eye-judgement that the magazine housing is empty.

**Status: single-source, contested, and it stays in coverage gaps.** Beat structure — one arc or
two — is untouched by any of it. The design does not turn on this: a mag-drop is right for a
mag-fed weapon regardless. But no *number* comes off that image.

One measurement in the manifest was fabricated and has been corrected in place: the ADS card's
"sight column sits at about 0.70 of file width" was never measured; the subject spans 0.207-0.425,
centre **0.316**, left of centre.

### S4 — Bloom decay shape is a free choice, not a canon fact

The CoD files bleed spread linearly at `hipSpreadDecayRate`. MrCrayfish's `SpreadTracker.java` — an
independent lineage — **hard-resets instead**. Two sources, same convention, different decay.

So bloom itself is corroborated twice and its *decay shape* is corroborated by nobody. R3 must
record whichever it picks as our decision with its own reason, not cite it to BO1.

### S5 — An unexamined fork: where bullets originate

Phantom Forces (tier 3–4, its wiki returned HTTP 402, so this is a lead and not evidence) is
reported to originate bullets **from the muzzle at the hip and from the aim point at ADS**. This
project always originates at the camera (`player.gd:877`, `origin := _cam.global_position`).

Not a defect and not in scope — but it is a design fork nobody here has ever considered, and at
the hip it is the difference between a shot that clips the doorframe you are edging past and one
that does not. Recorded so the next package does not think it is new.

---

## The decisions taken, 2026-08-02

Three questions were put to the project owner before implementation. The answers are binding on
R1–R12 and they resolve two things this document left open.

**1. Bullet pattern: BO1-faithful bloom.** Not a CS-style memorised spray table. This agrees with
what the document already recommends at the Bottom line and it closes R3's "shape or magnitudes"
fork in favour of shipping the *model* — growing cone, decay suppressed by movement, separate ADS
absolutes, recoil as a per-shot random velocity into a recentring spring. Magnitudes are still
subject to M5's decision rule.

**2. The `Rng.VISUAL` spread violation: fix it.** Spread moves to a gameplay stream.

**AND THE STATED COST OF THIS IS WRONG.** CLAUDE.md constraint 5 says the violation was *"left
alone because changing it moves every sim baseline"*. It does not. Read directly:

- `balance_sim.gd` draws from `Rng.SPAWN` (`:422`, `:615`) and `Rng.DROPS` (`:717`). **It never
  draws from `VISUAL` at any line.**
- It never calls `_spread_rad` or `_hitscan`. It drives the state machine only — `WEAPON.tick`
  (`:503`), `can_fire` (`:509`), `consume_shot` (`:521`).
- Damage is analytic: `for i in pellets` at `:529` with `dmg_per_pellet` at `:536`. **Every pellet
  is assumed to hit.** There is no spread in the sim at all.

So moving the four draws at `player.gd:886-887` and `:939-940` off `VISUAL` cannot change a single
sim baseline, and neither can adding bloom. The carve-out's stated justification does not survive
reading the file it is about. **What does move is anything downstream of `VISUAL`'s sequence** —
cosmetic draws now arrive at different values because four draws per pellet stopped being taken —
which is a frames-gate question, not a balance question, and M4/M5 do not cover it. *That* is the
real cost and it was never the one on the books.

The destination stream is new. `rng.gd:60-61` makes this free:

> *"Hash name-with-seed rather than seed+index: adding or removing a stream then cannot shift the
> seeds of the streams around it."*

Adding `const COMBAT := &"combat"` perturbs no existing stream, and `stream()` builds lazily
(`:56-64`), so it costs nothing until drawn from. **CLAUDE.md constraint 5 should be amended once
this lands** — reported, not edited, per the working-alongside rules.

**3. Sequencing: one spec, staged implementation.** This document is the spec. Implementation goes
in four reviewable stages, each with its own assertions, controls and gate run:

| stage | content | gates |
|---|---|---|
| 1 | **models** — M1 first, then R1 (face bracket) and R2 (per-part depth) | M1, M2, M3 are hard gates *before* any `DEPTH` table is committed |
| 2 | **brass** — R7 pooled MultiMesh, R9's assertion package | M4 |
| 3 | **reload** — R5 break-action + segmented, R6 per-shell pump cycle, S1 asymmetric ADS | — |
| 4 | **patterns** — R3 bloom, R4 view-kick flip, the `COMBAT` stream, A11/A12 | M5 |

Stage 1 is gated on a measurement that can kill its own lead item: **if M1 shows no face-value
ramp separates the top plane from the face plane in a rendered frame, R1 collapses and R2 leads.**
R8 already carries that branch. Nothing in stage 1 gets built before M1 runs.

The staging is deliberate about one thing beyond review size: **stage 4 is the only stage that
changes where bullets go.** Keeping it last means every earlier stage's frames-gate drift has a
single cause, and the one stage that needs a balance re-read is not entangled with three that do
not.
