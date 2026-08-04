class_name Verify
extends RefCounted

## Headless assertions over the rules this milestone changed.
##
## Every claim about balance in this project used to be checked by playing it,
## which meant nothing could be checked at all past about round five. These are
## the invariants that would silently rot first — the canon numbers, the two
## collision masks that make the game losable, the RNG determinism the run seed
## depends on. Run with:
##
##   Godot_v4.7-stable_win64_console.exe --headless --path . --verify
##
## What is deliberately NOT here, because a fake version of it is worse than an
## honest gap: anything needing a rendered frame (the vignette's *look*, glow,
## culling, the A16 pulse on screen — those are `--shot`), anything needing a
## real pointer lock (`_lock_seen` can never arm under DisplayServerHeadless,
## which reports MOUSE_MODE_VISIBLE forever), anything needing localStorage
## (`OS.has_feature("web")` is false here, so the save assertions exercise the
## desktop path and the shared validate ladder, never the browser backend), and
## anything needing wall-clock timing (the governor is driven with synthetic
## deltas instead). Those belong to M-BASE / M-SAVE / M-WARM.

## preload rather than the global class name: a freshly added script is not in
## the class registry until the editor rescans, and a headless run has no editor.
const SAVE_STORE := preload("res://scripts/autoload/save_store.gd")
const QUALITY := preload("res://scripts/world/quality_governor.gd")
const WEAPON := preload("res://scripts/entities/weapon.gd")
const VIEWMODEL := preload("res://scripts/entities/viewmodel.gd")
const GUNART := preload("res://scripts/data/gunart.gd")
const CHECK_SYSTEMS := preload("res://scripts/dev/checks/systems.gd")
## The interaction scan: the occlusion ray, the facing budget and the two buckets.
## Split out for the same reason CURVES is — it is the part of this suite that is
## about a rule of the game rather than about the engine.
const CHECK_INTERACT := preload("res://scripts/dev/checks/interaction.gd")
## The canon round curves, pinned with their sources. Split out because they are
## the one part of this suite a designer rather than an engineer has to read.
const CURVES := preload("res://scripts/dev/checks/curves.gd")
## The downed state, solo Quick Revive and the Thundergun's occlusion gate. None of it
## can be reached by playing: going down on purpose costs a run, and the blast's
## occlusion is invisible from inside the room the shot was fired in.
const DOWNED := preload("res://scripts/dev/checks/downed.gd")
## The economy: the payout table, the drop rules and the Insta-Kill branch.
const ECONOMY := preload("res://scripts/dev/checks/economy.gd")
## Settings persistence, the menu's focus graph, the accessibility toggles and the
## HUD's behaviour under a real pause.
const SHELL := preload("res://scripts/dev/checks/shell.gd")
## The map itself: the six connectivity invariants across all sixteen door states,
## the interior props and their colliders, the cost field, and a sweep of the seeded
## run layer. None of what it catches has a symptom at the moment it is introduced.
const MAPGEN := preload("res://scripts/dev/checks/mapgen.gd")
## The electric traps, the widened perk roster and the HUD's perk strip. The strip
## assertion is a regression test: `_refresh_perks()` hung off `weapon_changed` and
## nothing else, so a bought perk did not light its badge until the next shot.
## The 8-direction atlas, leg-shot crawlers, corpses and the walk cycle.
const ENEMIES := preload("res://scripts/dev/checks/enemies.gd")
const TRAPS := preload("res://scripts/dev/checks/traps.gd")
## Projectiles: swept integration, the shared explosion, ADS and the throwables.
const PROJECTILES := preload("res://scripts/dev/checks/projectiles.gd")
## The suite-side half of the frame gate. Renders NOTHING — headless has no
## rendering device — so it covers only what needs no frame: the luminance maths,
## the tolerance arithmetic, the scenario registry, and the golden file carrying a
## blessed row and a reference image for every scenario. The half that actually
## looks at pixels is `pwsh tools/frames.ps1`, and it is a windowed pass.
const FRAME := preload("res://scripts/dev/checks/frame.gd")

## The co-op net layer's headless half: framing, decode() normalisation, presence
## folding, the room-code alphabet and the Net autoload's contract. It opens NO
## socket and says so in its own header — the parts that need one were measured by
## hand and live in notes/net/2026-07-31-realtime-probe.md, which is evidence and
## not a gate. Same shape of problem as frame.gd: the interesting half needs
## hardware the suite does not have, so the boundary is stated rather than faked.
const NET := preload("res://scripts/dev/checks/net.gd")

## Every check module in scripts/dev/checks/, by filename, and the single place
## they are registered. `_registered()` walks the directory and fails if anything
## on disk is missing from this list.
##
## This exists because the floor below CANNOT catch the failure it is named for.
## A floor detects a section that STOPPED running — it is blind to one that never
## started, because the total it was set from never counted those assertions in the
## first place. Both downed.gd and economy.gd sat in that blind spot: written,
## committed, parse-clean, and never once executed. Thirty-four assertions that
## existed only as text. A green suite reported them as neither passing nor failing
## because it had no idea they were there.
const CHECK_MODULES := {
	"systems.gd": CHECK_SYSTEMS,
	"interaction.gd": CHECK_INTERACT,
	"curves.gd": CURVES,
	"downed.gd": DOWNED,
	"economy.gd": ECONOMY,
	"shell.gd": SHELL,
	"enemies.gd": ENEMIES,
	"traps.gd": TRAPS,
	"mapgen.gd": MAPGEN,
	"projectiles.gd": PROJECTILES,
	"frame.gd": FRAME,
	"net.gd": NET,
}

## The number of assertions this suite is known to run, minus a small margin for
## the ones that are conditional on a resource being present. See the floor check
## at the end of run() for why a count is worth asserting at all.
##
## HOW TO CHANGE IT, and the two cases are different.
##
## While work is in flight: raise it ADDITIVELY by the number of assertions you
## added, and do NOT read the current total and round down to it. This line is
## contended — four packages raised it in one session — and additive edits from
## concurrent authors compose to the right answer. "Set it to what I measured" does
## not: the measurer silently absorbs everyone else's margin, and the floor drifts
## further below the true total with every pass.
##
## At an integration point, on a quiescent tree: reconcile it to the real total less
## a small margin, which is what the number is supposed to mean. Additive raises are
## a concurrency discipline, not the definition; left unreconciled they accumulate
## exactly the slack they were protecting against. This value was reconciled at 306.
##
## Never lower it to make a run pass. A run that goes UNDER the floor has almost
## certainly lost a whole section to a runtime error, which is the failure this
## number exists to catch and the one that otherwise exits 0.
##
## The floor cannot see a section that never ran at all — a total it was never set
## from cannot shrink. That is `_registered()`'s job, and the two are complementary.
##
## Reconciled again at 560: a quiescent tree ran 561 assertions, and this check is
## itself counted AFTER its own comparison, so 560 is the count it sees on a fully
## green run and the largest honest floor.
##
## +26 for the muzzle-flash package and its review: checks/frame.gd's
## `_flash_geometry`, `_flash_art`, `_flash_materials` and `_flash_drawn`. A
## quiescent tree now runs 586, so 585 is the count this check sees on a fully
## green run. Raised ADDITIVELY.
##
## +91 for co-op multiplayer, reconciled at the integration point rather than by
## either package alone: +20 for the menu's four new screens (checks/shell.gd's
## `_menu_multiplayer`), +70 for the net layer's headless half (checks/net.gd), and
## +1 for splitting the send-budget check into its two halves — the ceiling cannot
## breach the free tier, AND it still clears the rates it has to carry. A budget of
## 1 would satisfy the first perfectly while shedding every snapshot in the game,
## which is why that one is two checks and not one.
##
## A quiescent tree now runs 677, so 676 is the count this check sees on a fully
## green run. Raised ADDITIVELY.
##
## +2 for the web pulse (checks/net.gd): a hidden tab still beats before the idle
## close, and the pulse is frequent enough to be what delivers that beat. Both are
## arithmetic — the BEHAVIOUR they stand for is only true in a browser, and is
## covered by the backgrounded-tab pass recorded in the probe note.
##
## +2 for the shell's click (checks/shell.gd `_shell_click_is_not_a_run`): the
## refusal, and the game-over acceptance that keeps the refusal from passing against
## a poll that has simply died. This one stands for a defect that reached a player.
##
## +12 for the zombie art pass (checks/enemies.gd): 5 for the walk cycle being six
## distinct poses rather than the three it shipped as — three palettes plus the
## attack and death cycles, which come from a code path the patch does not touch
## and are what stops "count the distinct frames" from passing against a build
## where everything collapsed; 5 for the per-body tint, driven through the writer
## the player sees and bounded at both ends (a spread wide enough to prove the roll
## is alive, a range narrow enough that it cannot invent a fourth palette, and the
## corpse fade asserted to BOTH darken and keep the tint); 2 for the tint being on
## the cosmetic stream, put as a differential rather than as a name so that moving
## it to Rng.AI fails rather than reads the same. The arm pose those changes exist
## for is NOT among them and enemies.gd's header says why.
##
## +20 for the weapon models (checks/frame.gd's `_gun_depth`, `_gun_shade` and
## `_gun_sights`): 9 for the per-part depth table — of which the one that matters
## is the committed `ArrayMesh` read back and compared against the corner walk,
## because M5 R2's trap is that the two walks disagree and no aggregate metric can
## see it, and the other eight bound the table at BOTH ends (a ceiling at the depth
## that already shipped, a floor that a table of all-1.0 fails, the glove
## coplanarity rule, and the two inversions M5 F1 named); 8 for the face ramp,
## seven of them arithmetic on the six constants and ONE that drives the real
## builder and reads the vertex colours back, which is the only one that can tell
## a live shading model from a dead helper; 3 for the iron sights, of which the
## second — the sight, not the receiver, is the top of the weapon — is the one
## that fails against a blade buried inside the part it is mounted on.
##
## +22 for the brass and the smoke (checks/systems.gd `_brass` and `_smoke`): 13
## for the casings, of which the ones that matter are the two REGISTRATIONS
## nothing else in the project can see — a MultiMesh missing from the warm pass
## costs a main-thread GLSL compile on the first trigger pull and is caught by no
## assertion at all, and a material missing from an accessor is absent from BOTH
## sides of :1039-1052's comparison — plus the roster bounded at both ends (the
## four weapons BO1 gives an empty eject field, AND the eight that must eject), the
## pellet discrimination that separates `fired` from `surface_impact`, and the four
## transform claims that are the only thing tying an invented effect to the four
## systems it was derived from. 9 for the smoke, written against a CONSTRUCTED
## inert version — a `_on_fired` that never touches the accumulator, with the quad
## and the material both present and registered — because this file has already
## shipped exactly that state green once (atmosphere.gd:438-445). MEASURED against
## that constructed inert version: FIVE of the nine stay green and FOUR go red. The
## five are the three material/registration claims, "it goes away" (an effect that
## never appears has certainly gone away) and the one-VISUAL-draw claim (an effect
## that does nothing spends nothing) — every one of which is a claim about
## declaration rather than about drawing, and none of them is counted as evidence
## the smoke works. The four that fail are the whole of the behavioural half.
##
## NET ZERO from the `_flash_materials` collapse in checks/frame.gd. The smoke made
## `atmosphere.materials()` three long and that file's `mats.size() == 2` went red
## for a correct change; the length test became a set test, which made the check at
## its foot a literal duplicate. It was RE-AIMED rather than deleted — it now
## asserts that no layer is declared twice, which is the failure its own comment
## always said it existed for and which neither the old size test nor the new set
## test can see. So: 22 added, 0 removed, and the count moves by exactly 22.
##
## +22 for the reciprocating group and the segmented reload (checks/systems.gd
## `_animation`). Before it, `grep -rn 'SLIDE_TRAVEL|_slide_offset|_cycle_slide|
## _locked' scripts/dev/` returned ZERO lines: the one animated part of the weapon
## had no assertion of any kind. The ones that matter are not the count. Two pin
## DECISIONS the geometry cannot settle — `SLIDE`'s roster (the predicate that
## looked obvious scores the AK-74u's deleted row and the MP40's kept row
## identically, so it would have passed its own control) and the two travel rows
## that break their own bounds, which are asserted to STILL break them so the
## exemption cannot outlive the departure. One is a READOUT rather than a refusal —
## `vm.swept_travels()` — because every component of the clip sweep is insensitive
## to slide travel by construction and deleting the travel endpoint outright left
## the whole suite green. One counts strokes off `_slide.position` through a real
## six-shell reload and reported ONE against seven before this package. And the
## sighted-pose pair is two jaws on one constant: some profile yaw has to survive
## `ADS_YAW`, and whatever survives has to stay inside the frames gate's own 80 px
## probe rect — which is what bounds `ADS_YAW` from below and is a constraint the
## research did not know about.
##
## EVERY ONE OF THE 22 WAS CONTROLLED, 21 sabotages over 18 runs, and three of them
## found something: the sign flip is caught by five checks rather than one, forcing
## the automatics back onto the fixed cycle fails on the MP40 ALONE because the
## PM-63's interval is exactly 0.06 s (so a PM-63-only check would have been
## decoration), and removing the arc inflation leaves `widest` IDENTICAL to six
## decimals while moving `nearest` — which is why the arc has two checks and not
## one.
##
## +1 for the ADS-asymmetry tripwire, and IT IS EXPECTED TO BE RED. It is the
## failing check a reported `player.gd` hunk needs in order not to be dropped
## silently, which is exactly how ADS shipped its camera half without its weapon
## half once already. It is NOT counted below.
##
## +1 because the ADS-asymmetry tripwire above is GREEN now. The `player.gd` hunk
## it was reported for has landed (`ADS_OUT_TIME`), so the one check this file
## deliberately shipped red is a real assertion again and counts like one. That is
## the mechanism working, not a floor adjustment: without it the hunk would have
## been dropped silently, which is exactly how ADS shipped its camera half and not
## its weapon half once already.
##
## +27 for the bullet patterns (`checks/projectiles.gd::_bullet_patterns`). This is
## the package M5's own bottom line asked for in as many words — *"nothing anywhere
## pins a spread or a kick value; multiply every one of them by ten and the whole
## suite stays green"* — and before it, `grep -rn '_spread_rad' scripts/dev/`
## returned two hits feeding ONE ratio assertion and `kick` appeared in
## `scripts/dev/checks/` only inside a comment.
##
## The count is not the interesting part. FOUR of the twenty-six are literals, and
## they are the only things in the suite that a uniform rescale cannot slip past: a
## cone width in radians, a saturated ceiling, a sighted floor, and one view-kick
## peak. MEASURED: sabotaging `_spread_rad`'s trailing `* 0.5` — the exact silent
## factor of two M5 warned about, which arrives the moment somebody drops BO1's
## own half-angle degrees into a field that holds a full cone — leaves every ratio
## and every ordering check in this suite green and fails those three alone.
##
## Three more exist because a check can see nothing without being scale-invariant.
## `spread = 0` makes `_spread_rad` return 0.0 and `_hitscan` skip the cone
## entirely, so "no round left the cone" evaluates 0 <= 0 and passes against a
## weapon that has stopped spreading; the inert case was CONSTRUCTED and the
## filled-cone and uniform-in-area claims both go red against it, which is what
## keeps the first one from standing in for them.
##
## And one of them carries the whole of R4: the recoil sign. It was `-=` from the
## port's first commit, so the camera dipped while the viewmodel raised the muzzle
## with the same spring constants, and because `RecoilPivot` is the parent of
## `Camera3D` that was a claim about where bullets go — a rising aim converts body
## shots into headshots at 1.5x damage. Nothing in the suite could see it.
##
## RAISED ADDITIVELY, per the contended-floor rule: 756 + 1 + 27. A quiescent tree ran
## 785 passing on 2026-08-02, which made 784 the largest honest floor AS OF THAT DATE.
## A dated ledger entry, not a live fact — the count this check sees is whatever the
## paragraphs below have added to it since (797 on a fully green run today, because
## `_pass + _fail >= ASSERTION_FLOOR` is evaluated before its own check registers).
## This number moves with every paragraph added below it; re-measure, do not map it.
##
## +5 NET for reading the ancestor instead of a statistic derived from it
## (checks/frame.gd's `_gun_ancestor`, with the reader, the sight record and the
## departure register in scripts/dev/ancestor_art.gd): SIX added and ONE removed. The
## one removed compared `ART`'s part counts against thirteen hand-typed integers under
## a name that claimed part-for-part fidelity, so every geometry, colour, kind and
## ORDER change passed it silently — and because its loop was keyed off `ART` itself,
## so did a weapon deleted from `ART` outright. The six compare `ART` against
## `kriegsnacht.html:1151-1207`, read at check time.
##
## Four of the six carry the package. The field-for-field comparison runs against
## `GUNART._parts()` — the walk `_build` and `_corners` actually make — and is the
## only assertion anywhere that can see a part's geometry, colour, kind or order
## change. TWO cover the tail, because they answer different questions: the record
## pins what `SIGHTS` IS, row by row, and is the only thing that can see a sight row's
## geometry, colour or order change — three such sabotages passed the entire suite
## before it existed. The relations assert what a sight MUST BE whatever the record
## says, so they are what survives the record being re-pasted to match a sabotage.
##
## The record does NOT see a row moved from `SIGHTS` into `ART`, and the draft of this
## paragraph that shipped with the first revision claimed it did. `sight_diff` slices
## the walk at the ANCESTOR's part count (`ancestor_art.gd:636`), not at `ART`'s, so a
## moved row lands back in the tail at the same index and matches the record byte for
## byte. MEASURED: check 2 reddens, on `ART` holding a part the ancestor never drew.
## And the liveness check is
## what keeps the other five honest, because `get_file_as_string()` returns "" for a
## missing file without raising and an empty departure register would otherwise read
## as agreement.
##
## RAISED ADDITIVELY: 784 + 5. Do not read this as a reconciliation.
##
## +7 for the BANDS package, which decouples a part's place in the PAINTING from its
## place in the walked ARRAY so that optional geometry becomes possible later without
## renumbering anything that ships today. Five in `checks/frame.gd`'s new `_gun_bands`
## — the rank pin, the walk-is-the-bands reconstruction, the two-sided ordinal
## stability property, the proud-of-host relation over the nested parts (27 when this
## paragraph was written, 65 today — the count moves with the detail band, so re-measure
## it rather than trusting this sentence), and the
## footprint reconstruction off the committed `ArrayMesh` — and two in `_gun_ancestor`:
## the per-band census (101 read out of `kriegsnacht.html` + 18 + 0, which the
## `parts_total == 119` it stands beside cannot decompose) and the detail band against
## its own record and rules. NOTHING WAS REMOVED and nothing was weakened; `sight_diff`
## was narrowed to the sight band, and the coverage that narrowing gave up is carried
## by `detail_rules()`'s `quiet` clause in the same commit.
##
## Two of the seven earn coverage nothing here had. The footprint check reads each
## part's vertices back out of the committed mesh and puts them against the box its own
## rank inflates — the `PROUD` half of the ordinal, which the lead |x| assertion is
## structurally blind to because |x| is the `LAYER` half alone. The proud-of-host
## relation is the first assertion anywhere that would notice `LAYER` going to zero.
##
## +1 for the SECOND DETAIL PASS, which took the band from 14 rows on four weapons to
## 38 across all thirteen. ONE assertion, and it is the one the first pass proved was
## missing: `checks/frame.gd`'s consumer-driven check that a weapon carrying detail
## rows is photographed by some scenario. Eleven of the first fourteen rows were not,
## and 22 of this pass's 24 would not have been either — legal, recorded, and invisible
## to every frame the project takes. Everything else the pass touched moved NUMBERS
## inside checks that already existed (133 to 157 parts walked, 41 to 65 nested pairs,
## `DETAIL_ROWS` 14 to 38), which is the shape a data change ought to have.
##
## RAISED ADDITIVELY: 796 + 1. Do not read this as a reconciliation.
const ASSERTION_FLOOR := 797

var _pass := 0
var _fail := 0
var _lines: Array[String] = []


func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
		_lines.append("  PASS  %s" % name)
	else:
		_fail += 1
		_lines.append("  FAIL  %s   %s" % [name, detail])


func near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


## Fails if a check module exists on disk but is not in CHECK_MODULES — i.e. if
## somebody wrote a set of assertions and nothing ever called them.
##
## Directory-driven rather than list-driven on purpose. A registry that only checks
## itself is a tautology: the whole failure being guarded against is that the author
## added the file and forgot the registration, so the disk has to be the authority
## and the list the thing under test.
##
## Editor-binary only. In an exported build these are `.gd.remap` and the listing
## does not mean what it means here — but `--verify` is a development gate that only
## ever runs from the editor binary (tools/build.ps1 calls it before exporting), so
## being unable to run it there would be a contradiction rather than a gap.
func _registered() -> void:
	var dir := DirAccess.open("res://scripts/dev/checks")
	if dir == null:
		check("the check-module directory is readable", false,
			"DirAccess.open failed — the registry cannot be audited")
		return
	var missing: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".gd") and not CHECK_MODULES.has(f):
			missing.append(f)
	check("every check module on disk is registered and actually runs",
		missing.is_empty(),
		"never executed: %s" % str(missing))


## Printed as each module STARTS, and printed straight out rather than buffered
## into `_lines`.
##
## Everything else in this suite is held until the end so the report reads as one
## block — which is right when it finishes and useless when it does not. A check
## that hangs produced NO output at all, so the only signal was "it never came
## back", and finding out which of eleven sections was responsible meant bisecting
## by hand. That cost several cycles in Milestone 4 alone. One line per section is
## a small price for knowing where it stopped.
func _mark(name: String) -> void:
	print("[verify] ", name)


func run(main: Node3D) -> int:
	# THE SUITE MUST NOT TOUCH THE PLAYER'S SAVE FILE, and left alone it does.
	#
	# Game checkpoints the profile on `round_changed` (game_state.gd), and half the
	# checks below drive real rounds through the real director. So every `--verify`
	# run on a developer's machine was writing `user://profile.json`. It shows: the
	# file on this machine reads best_round 26 with best_points 500 — 500 is
	# START_POINTS, so that is not a run anyone played, it is a test that happened to
	# reach round 26 while holding the opening balance.
	#
	# Disconnected here, once, rather than in each check that drives a round. A check
	# that has to remember is a check that will forget, and the one that remembered
	# did it with an unconditional `disconnect()` that would itself have thrown the
	# moment anything else disconnected first.
	var checkpointing := Game.round_changed.is_connected(Game._on_round_changed)
	if checkpointing:
		Game.round_changed.disconnect(Game._on_round_changed)

	_canon()
	_losable(main)
	_progression()
	_determinism()
	_flow(main)
	_persistence()
	_late_speed()
	_eyes(main)
	_lighting(main)
	_level_materials(main)
	_impacts(main)
	_screen(main)
	_pointer_lock(main)
	_input_latch(main)
	_weapon_fsm(main)
	_hit_geometry(main)
	_quality(main)
	_probe_contract(main)
	_viewmodel(main)
	# These four are last because each leaves state behind, and they are in this
	# order because of what each one needs from the state the others leave.
	#
	# CHECK_INTERACT first, and it restores everything it touches. It reads the live
	# map's colliders and drives the Pack-a-Punch clock through the player's real
	# loadout, so it wants the world and the guns in the state the sections above
	# left them — DOWNED puts the player on the floor and CHECK_SYSTEMS mangles the
	# director. It draws from no rng stream at all.
	#
	# DOWNED next: it kills real zombies through the director's real payout path, so
	# it draws from the DROPS stream. CHECK_SYSTEMS re-seeds with Rng.new_run(SEED)
	# before it samples anything and CURVES sweeps its own seeds, so neither can see
	# the disturbance. It also fires the Thundergun along the map's real bearings,
	# which wants the level un-mangled.
	#
	# CHECK_SYSTEMS spawns and kills 24 real zombies and leaves the director's spawn
	# queue drawn down; CURVES sweeps 300 seeds, re-seeds Rng and drives reset_run().
	# CURVES reads nothing but the curves on Game, so it survives a mangled director —
	# CHECK_SYSTEMS would not survive a reset_run() underneath it.
	_mark("interact")
	CHECK_INTERACT.run(self, main)
	_mark("downed")
	DOWNED.run(self, main)
	_mark("economy")
	ECONOMY.run(self, main)
	_mark("shell")
	SHELL.run(self, main)
	# After SHELL because it drives the HUD's `_process` and SHELL's pause section
	# leaves Game.state where it wants it; before CHECK_SYSTEMS because that one
	# mangles the director and this one spawns bodies of its own. It mounts a
	# private traps node rather than main's, so it can run whether or not main.gd
	# has been wired for traps yet.
	_mark("enemies")
	ENEMIES.run(self, main)
	_mark("traps")
	TRAPS.run(self, main)
	_mark("systems")
	CHECK_SYSTEMS.run(self, main)
	_mark("curves")
	CURVES.run(self, main)
	# Anywhere would do — it touches no global state and renders nothing — so it
	# sits before the two sections that DO have an ordering constraint.
	_mark("frame")
	FRAME.run(self, main)
	# Same reasoning as `frame` above, and it earns it the same way: it restores the
	# rng streams and the session state it drives, so it touches no global state and
	# has no ordering constraint.
	_mark("net")
	NET.run(self, main)
	# Dead last, and it has to be: the seed sweep rolls MapData's static layout
	# tables 48 times and re-seeds Rng on every iteration. It puts both back on the
	# way out, but anything downstream holding a cached wall-buy position would be
	# reading it across the churn.
	_mark("mapgen")
	MAPGEN.run(self, main)
	_mark("projectiles")
	PROJECTILES.run(self, main)

	_registered()

	# Put the checkpoint back, so a suite run leaves the autoload exactly as it found
	# it. Nothing after this point drives a round, but a Verify instance is not
	# guaranteed to be the last thing that ever touches Game.
	if checkpointing:
		Game.round_changed.connect(Game._on_round_changed)

	# A floor on the total, not a target. A runtime error inside any check function
	# above unwinds only that function: run() carries on, the suite prints a smaller
	# number and STILL EXITS 0. That is how a rename silently deleted the "every
	# material is reachable from the warm-up" assertion and left the build gate
	# green. Nothing else reads this count, so nothing else would have noticed.
	# Raise it when sections are added; never lower it to make a run pass.
	check("no assertion section was silently dropped",
		_pass + _fail >= ASSERTION_FLOOR,
		"ran %d, floor is %d — a check function probably errored out" % [
			_pass + _fail, ASSERTION_FLOOR])

	print("\n=== verify ===")
	for l in _lines:
		print(l)
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	return _fail


# --- canon numbers -----------------------------------------------------------

func _canon() -> void:
	Game.perks.clear()
	check("unperked health is 100", near(Game.max_health(), 100.0))
	# 60 damage against 100 is two hits; the old 34 against 100 was three.
	var z := Zombie.create("zombie", 0, 1, false)
	check("zombie melee damage is 60", near(z.melee_damage, 60.0),
		"got %.1f" % z.melee_damage)
	check("2 hits to down unperked",
		ceili(Game.max_health() / z.melee_damage) == 2,
		"got %d" % ceili(Game.max_health() / z.melee_damage))

	Game.perks["jug"] = true
	# 160, not 250 — the 250/5-hits figure is BO3 with upgraded Juggernog.
	check("Juggernog health is 160", near(Game.max_health(), 160.0),
		"got %.1f" % Game.max_health())
	check("3 hits to down with Juggernog",
		ceili(Game.max_health() / z.melee_damage) == 3,
		"got %d" % ceili(Game.max_health() / z.melee_damage))
	Game.perks.clear()
	z.free()

	check("perk cap is 4", Game.PERK_CAP == 4)
	for k in ["jug", "speed", "dtap", "revive"]:
		Game.perks[k] = true
	check("5th perk refused", not Game.can_take_perk("mule"))
	Game.perks.clear()


# --- the game must be losable ------------------------------------------------

func _losable(main: Node3D) -> void:
	var p: Player = main.player
	# Neither mask used to contain the other's layer, so move_and_slide never
	# resolved a contact and the player could walk through the entire horde.
	check("player collides with enemy layer", (p.collision_mask & 4) != 0,
		"mask=%d" % p.collision_mask)
	var z := Zombie.create("zombie", 0, 1, false)
	main.add_child(z)
	check("zombie collides with player layer", (z.collision_mask & 2) != 0,
		"mask=%d" % z.collision_mask)
	z.queue_free()

	# Sprint is finite, so a player can no longer outrun the horde indefinitely.
	check("sprint is finite", Player.SPRINT_DRAIN > 0.0)
	var sprint_speed := Player.SPEED * Player.SPRINT_MULT
	var top_class: float = Game.SPEED_SPRINT
	check("sprinting still outpaces the fastest class (by design, but bounded)",
		sprint_speed > top_class,
		"sprint=%.2f class=%.2f" % [sprint_speed, top_class])
	check("walking is slower than the sprint class",
		Player.SPEED < top_class,
		"walk=%.2f class=%.2f" % [Player.SPEED, top_class])

	# Per-attacker damage gating: six attackers must be able to deal six hits.
	check("per-attacker hurt window exists", Player.HURT_IGNORE > 0.0)
	p.hp = 1000.0
	Game.perks.clear()
	var before := p.hp
	for i in 6:
		p.take_damage(10.0, 1000 + i)
	check("six distinct attackers all land", near(p.hp, before - 60.0, 0.01),
		"dealt %.1f, expected 60" % (before - p.hp))
	# The same attacker twice inside the window must only land once.
	before = p.hp
	p.take_damage(10.0, 7777)
	p.take_damage(10.0, 7777)
	check("same attacker gated inside the window", near(p.hp, before - 10.0, 0.01),
		"dealt %.1f, expected 10" % (before - p.hp))

	# Quick Revive was defined and called by nothing at all.
	#
	# GATED ON HOLDING THE PERK, not on `revives_left`. This pair used to set the
	# counter alone, which passed for as long as `_go_down` read the counter — and
	# `_go_down` reading a counter no machine, badge or purchase rule consults was
	# itself the bug. With the gate corrected to `Game.perks`, the old setup fell
	# through to `died.emit()`, and main.gd turns that into `Game.record_run()`:
	# every --verify run was writing +1 to the player's REAL profile.json and
	# leaving the tree paused in STATE_OVER for every section below.
	#
	# The full downed contract lives in scripts/dev/checks/downed.gd; this pair
	# stays because _losable is where a reader looks for "can the run still end".
	Game.perks["revive"] = true
	Game.revives_left = 1
	p.hp = 1.0
	p.take_damage(500.0, 4242)
	check("lethal damage downs rather than kills when a revive is held", p.is_downed)
	p.revive()
	check("revive() restores health", near(p.hp, Game.max_health()) and not p.is_downed)
	Game.perks.clear()


# --- progression -------------------------------------------------------------

func _progression() -> void:
	# Three discrete classes, mixture shifting with the round — replacing one
	# continuous curve that saturated at round 16 and never moved again.
	var seen_early := {}
	var seen_late := {}
	for i in 400:
		seen_early[Game.roll_speed_class(2)] = true
		seen_late[Game.roll_speed_class(30)] = true
	check("round 2 is walkers only",
		seen_early.size() == 1 and seen_early.has(Game.SPEED_WALK),
		str(seen_early.keys()))
	check("round 30 has no walkers", not seen_late.has(Game.SPEED_WALK),
		str(seen_late.keys()))
	check("round 30 includes the sprint class", seen_late.has(Game.SPEED_SPRINT))

	# HP curve is canon and deliberately untouched.
	check("round 1 zombie HP is 150", near(Game.zombie_hp(1), 150.0))
	check("round 9 zombie HP is 950", near(Game.zombie_hp(9), 950.0),
		"got %.0f" % Game.zombie_hp(9))
	check("HP keeps compounding past round 9 (no cap)",
		Game.zombie_hp(40) > Game.zombie_hp(39))

	# Power-ups are earned by points now, not by an unreset kill counter.
	Game.reset_run()
	check("no drop before the first threshold", not Game.check_points_drop())
	Game.points_earned = 2000
	check("drop at 2000 points earned", Game.check_points_drop())
	check("threshold grows after a drop", Game.next_drop_at > 2000,
		"next=%d" % Game.next_drop_at)

	# Dog rounds are rolled, not a fixed multiple of five.
	var first := Game.next_dog_round
	check("first dog round lands in 5..7", first >= 5 and first <= 7,
		"got %d" % first)
	Game.advance_dog_round()
	var gap := Game.next_dog_round - first
	check("subsequent dog rounds are 4-5 apart", gap >= 4 and gap <= 5,
		"got %d" % gap)
	check("dog rounds cap concurrent enemies lower",
		Game.max_alive(Game.next_dog_round) < Game.MAX_ALIVE)


# --- rng ---------------------------------------------------------------------

func _determinism() -> void:
	Rng.new_run(12345)
	var a: Array[float] = []
	for i in 12:
		a.append(Rng.randf(Rng.SPAWN))
	Rng.new_run(12345)
	var b: Array[float] = []
	for i in 12:
		b.append(Rng.randf(Rng.SPAWN))
	check("same seed replays the same spawn sequence", a == b)

	# The point of sub-streams: cosmetic draws must not disturb gameplay ones.
	Rng.new_run(12345)
	var c: Array[float] = []
	for i in 12:
		Rng.randf(Rng.VISUAL)      # cosmetic churn between gameplay draws
		Rng.randf(Rng.VISUAL)
		c.append(Rng.randf(Rng.SPAWN))
	check("cosmetic draws do not perturb the spawn stream", a == c)

	Rng.new_run(999)
	var d: Array[float] = []
	for i in 12:
		d.append(Rng.randf(Rng.SPAWN))
	check("a different seed gives a different sequence", a != d)


# --- flow field --------------------------------------------------------------

func _flow(main: Node3D) -> void:
	var f: FlowField = main.flow
	var m: MapData = main.map
	var spawn := Vector2(MapData.SPAWN_TILE.x + 0.5, MapData.SPAWN_TILE.y + 0.5)
	f.update(spawn)

	# The theatre sits behind door 0 and must be unreachable until it is bought.
	var theatre := Vector2(30.5, 8.5)
	var before := f.reachable(theatre)
	m.open_door(0)
	# Without invalidate() the field early-returns on an unchanged player tile,
	# so a door bought while standing still would never enter the graph.
	f.invalidate()
	f.update(spawn)
	var after := f.reachable(theatre)
	check("theatre is unreachable before the door is bought", not before)
	check("invalidate() lets a door purchase re-solve the field", after)


# --- persistence -------------------------------------------------------------

## Dictionary `==` is not a value comparison everywhere it looks like one, and a
## profile that came back with the right numbers as the wrong types is precisely
## the failure being tested for. So compare key, value and type by hand.
func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k: String in a.keys():
		if not b.has(k):
			return false
		var av: Variant = a[k]
		var bv: Variant = b[k]
		# JSON has one number type, so a stored int comes back a float and an
		# exact typeof match would fail a round trip that is in fact correct.
		# Widening is the backend's documented behaviour, not a defect — the type
		# policy lives in Game._load_profile(), which accepts INT or FLOAT and
		# narrows with int(), and there is a separate assertion below proving it.
		var numeric := (typeof(av) == TYPE_INT or typeof(av) == TYPE_FLOAT) \
			and (typeof(bv) == TYPE_INT or typeof(bv) == TYPE_FLOAT)
		if numeric:
			if not near(float(av), float(bv)):
				return false
		elif typeof(av) != typeof(bv) or av != bv:
			return false
	return true


## The profile is the only state that outlives a run and nothing about it is
## reachable from the editor. Restores the real file and the real profile on the
## way out, because this is the one section that writes to the player's disk.
func _persistence() -> void:
	var path: String = SAVE_STORE.FILE_PATH
	var had := FileAccess.file_exists(path)
	var was := FileAccess.get_file_as_string(path) if had else ""
	var profile_was: Dictionary = Game.profile.duplicate()
	var round_was := Game.round_no
	var points_was := Game.points

	# A FileAccess left open is a FileAccess that never flushed, and the symptom
	# is an empty file rather than an error — so the round trip has to go through
	# the real backend rather than through the dictionary it was handed.
	var blob := {"best_round": 7, "best_points": 1234, "runs": 3}
	var wrote: bool = SAVE_STORE.save(blob)
	var back: Dictionary = SAVE_STORE.restore()
	check("profile round-trips through the real store", wrote and _same(back, blob),
		"wrote=%s got=%s" % [wrote, back])

	# Every one of these is a real arrival shape: a truncated write, a blob from a
	# schema this build does not understand, a hand-edited value of the wrong type.
	# All of them must land on "no save" rather than on a crash or a half-profile.
	var damaged := ["{not json", "[]", "", "{\"v\":99,\"data\":{}}",
		"{\"v\":1,\"data\":[]}", "{\"data\":{}}", "{\"v\":\"1\",\"data\":{}}"]
	var survived := true
	var offender := ""
	for text: String in damaged:
		_write_raw(path, text)
		if not SAVE_STORE.restore().is_empty():
			survived = false
			offender = text
	check("every damaged blob degrades to an empty profile", survived,
		"accepted %s" % offender)

	# The load is a key-by-key copy with a type check per key for one reason: on
	# web the blob is one devtools line from hand-edited, and a merge or a
	# duplicate() would let it introduce keys and retype the ones it already has.
	Game.profile = {"best_round": 0, "best_points": 0, "runs": 0}
	SAVE_STORE.save({"best_round": "20", "best_points": true, "runs": -5, "cheat": 1})
	Game._load_profile()
	var clean := Game.profile.size() == 3 and not Game.profile.has("cheat")
	for k: String in ["best_round", "best_points", "runs"]:
		var v: Variant = Game.profile.get(k)
		if typeof(v) != TYPE_INT or v != 0:
			clean = false
	check("a hostile blob can neither inject a key nor retype one", clean,
		str(Game.profile))

	# The checkpoint is disconnected for the whole suite by run(), so that a check
	# which drives a real round cannot write to the machine's actual save file. This
	# is the one section that is ABOUT the checkpoint, so it puts it back for its own
	# duration and takes it away again — the exemption is local, visible, and owned
	# by the only tests that need it.
	#
	# Safe against the real file because this section is already operating on a saved
	# and restored copy of it: `path` is deleted and rewritten below, and the original
	# contents go back at the end of the function.
	var was_wired := Game.round_changed.is_connected(Game._on_round_changed)
	if not was_wired:
		Game.round_changed.connect(Game._on_round_changed)

	# record_run() fires only when the player is killed, and the ordinary way a
	# browser game ends is the tab closing — so on its own it means a player who
	# reaches round 20 and walks away keeps nothing.
	Game.profile = {"best_round": 20, "best_points": 5000, "runs": 4}
	Game.points = 100
	Game.round_changed.emit(21, false)
	check("a round boundary checkpoints the profile",
		Game.profile.best_round == 21 and Game.profile.runs == 4,
		str(Game.profile))

	# ...and replaying rounds 1-10 on a profile that already reads 21 must cost
	# nothing at all, or every round boundary is a synchronous localStorage commit
	# on the main thread for no gain. Deleting the file first makes "no write"
	# observable rather than inferred.
	DirAccess.remove_absolute(path)
	Game.round_changed.emit(3, false)
	check("a round below the record performs no write at all",
		not FileAccess.file_exists(path) and Game.profile.best_round == 21)

	# Two connections would double every write; none would lose the checkpoint
	# again, silently, with the death path still working so nothing looks wrong.
	var wired := 0
	for c: Dictionary in Game.round_changed.get_connections():
		var cb: Callable = c.callable
		if cb.get_method() == "_on_round_changed":
			wired += 1
	check("the round checkpoint is connected exactly once", wired == 1,
		"got %d" % wired)

	# Back to the suite-wide default: disconnected, so nothing after this point can
	# write to the machine's real profile by driving a round.
	if not was_wired and Game.round_changed.is_connected(Game._on_round_changed):
		Game.round_changed.disconnect(Game._on_round_changed)

	# `runs` moves in record_run() and nowhere else, and the other two are
	# monotone there — a bad run must never be able to lower a good record.
	Game.profile = {"best_round": 21, "best_points": 5000, "runs": 4}
	Game.round_no = 2
	Game.points = 10
	Game.record_run()
	check("record_run counts one run and never lowers a record",
		Game.profile.runs == 5 and Game.profile.best_round == 21
			and Game.profile.best_points == 5000, str(Game.profile))

	Game.profile = profile_was
	Game.round_no = round_was
	Game.points = points_was
	if had:
		_write_raw(path, was)
	else:
		DirAccess.remove_absolute(path)


func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


# --- A23, the late-round speed nudge -----------------------------------------

## `z.spd * (G.round>=14 && z.type==='z' ? 1.06 : 1)` (kriegsnacht.html:2334).
## The whole item is one multiply, which is exactly the kind of thing that gets
## written, reviewed, and then wired to nothing.
func _late_speed() -> void:
	check("A23 steps once at 14 and never compounds",
		near(Game.late_speed_scale(13), 1.0) and near(Game.late_speed_scale(14), 1.06)
			and near(Game.late_speed_scale(40), 1.06),
		"13=%.4f 14=%.4f 40=%.4f" % [Game.late_speed_scale(13),
			Game.late_speed_scale(14), Game.late_speed_scale(40)])

	# Re-seeding before each spawn makes the class roll and the +/-8% variance
	# identical, so the only thing left that can differ is the nudge itself.
	# Rounds 13 and 14 sit in the same SPEED_MIX band, so the class cannot move.
	var walk13 := _spawn_speed("zombie", 13)
	var walk14 := _spawn_speed("zombie", 14)
	check("a regular zombie is 6% faster at round 14",
		near(walk14, walk13 * 1.06, 0.0001),
		"r13=%.4f r14=%.4f ratio=%.4f" % [walk13, walk14, walk14 / walk13])

	# The ancestor gates on `z.type==='z'`, and R4 §1.4 correction 3 forbids
	# scaling hounds outright — they already top out well past a 4.88 m/s sprint.
	var hound13 := _spawn_speed("hound", 13)
	var hound14 := _spawn_speed("hound", 14)
	var crawl13 := _spawn_speed("crawler", 13)
	var crawl14 := _spawn_speed("crawler", 14)
	check("hounds and crawlers are not scaled",
		near(hound14, hound13, 0.0001) and near(crawl14, crawl13, 0.0001),
		"hound %.4f/%.4f crawler %.4f/%.4f" % [hound13, hound14, crawl13, crawl14])


func _spawn_speed(kind: String, r: int) -> float:
	Rng.new_run(777)
	var z := Zombie.create(kind, 0, r, false)
	var s := z.speed
	z.free()
	return s


# --- glowing eyes ------------------------------------------------------------

## The eyes are one material and seven meshes for the whole game. Everything here
## is about that staying true: a per-zombie material is 24 uniform sets and, on a
## platform with no program cache, 24 chances to recompile the same program in
## the middle of a fight.
func _eyes(main: Node3D) -> void:
	var mat := Zombie.eye_material()
	# "not a ShaderMaterial" is not asserted here because it cannot be: the
	# compiler rejects `mat is ShaderMaterial` outright now that eye_material()
	# declares -> StandardMaterial3D. That return type IS the guarantee, and it is
	# enforced at parse time rather than by this suite, which is strictly better.
	check("the eye material is one shared instance with a baked texture",
		mat == Zombie.eye_material() and mat.albedo_texture is GradientTexture2D)

	# Not compared against a hard-coded 0.92: the assertion has to fail loudly if
	# someone retunes the environment and silently switches the eyes off. Read
	# through lighting.gd's accessor rather than by walking the tree — the
	# WorldEnvironment is that node's child now, and an accessor cannot silently
	# come back empty the way a scan can.
	var lit_env: Environment = main.lighting.env()
	var thresh: float = lit_env.glow_hdr_threshold
	check("the eye core clears the live glow threshold",
		thresh > 0.0 and mat.albedo_color.r > thresh,
		"albedo=%.3f threshold=%.3f" % [mat.albedo_color.r, thresh])

	# The contract the eye geometry is pinned to. A new zombie kind with no row
	# here throws on the first spawn of it, mid-round, rather than at build time.
	var complete := true
	for k: String in SpriteLib.SPEC.keys():
		if not Zombie.EYE_PX.has(k):
			complete = false
			continue
		var row: Dictionary = Zombie.EYE_PX[k]
		for f: String in ["y", "sep", "x", "glow"]:
			if not row.has(f):
				complete = false
	check("every sprite kind has a complete EYE_PX row", complete)

	var kinds := ["zombie", "crawler", "hound"]
	var shared := true
	var lit_corpse := false
	var covered := true
	var worst := ""
	for kind: String in kinds:
		var z := Zombie.create(kind, 0, 1, false)
		main.add_child(z)
		if z._eyes.material_override != mat:
			shared = false
		# Billboarding is a vertex-shader rotation, so the AABB never turns with
		# the geometry, and the crawler's and the hound's quads sit wholly on one
		# side of the origin. The margin has to contain the whole swept sphere —
		# one span provably does not, which is what put the hound's eyes out at
		# the edge of the frame.
		var ab: AABB = z._eyes.mesh.get_aabb()
		var r := 0.0
		for i in 8:
			r = maxf(r, ab.get_endpoint(i).length())
		var m: float = z._eyes.extra_cull_margin
		if (ab.position.x - m > -r or ab.end.x + m < r
				or ab.position.y - m > -r or ab.end.y + m < r
				or ab.position.z - m > -r or ab.end.z + m < r):
			covered = false
			worst = "%s margin=%.3f needs r=%.3f from %s" % [kind, m, r, ab]
		# A corpse with two lights still burning in its skull is a bug, and the
		# death animation runs for a second and a half before queue_free.
		z.take_damage(1e9, 0.0)
		if z._eyes.visible or z.state != Zombie.State.DYING:
			lit_corpse = true
		z.queue_free()
	check("every zombie shares the one eye material", shared)
	check("the cull margin contains the swept billboard", covered, worst)
	check("a dying zombie's eyes go out", not lit_corpse)


# --- level materials ---------------------------------------------------------

# --- lighting ----------------------------------------------------------------

func _lighting(main: Node3D) -> void:
	var lit: Node3D = main.lighting

	# THE ONE THAT PROTECTS THE BAKE. world_builder bakes a lamp-fill term into the
	# vertex colours, and it has to bake against the position the light is actually
	# at. Two copies of a centre-of-room formula in two files look equally
	# plausible on their own, and a bake that disagrees with its light reads as a
	# smear that no amount of retuning fixes — so this asserts the agreement rather
	# than trusting that nobody duplicated the arithmetic.
	var agree := true
	for r in MapData.ROOMS.size():
		var baked: Vector3 = main.world._lamp_pos[r]
		if not baked.is_equal_approx(lit.lamp_position(r)):
			agree = false
	check("the vertex bake and the lamps agree on where a lamp is", agree)

	# THE ONE THAT PROTECTS THE CEREMONY. What reads as the lights coming on is not
	# the room getting brighter — it is the eight lamp fixtures crossing the glow
	# threshold, which they must do on the powered side of it and only there. Both
	# energies were retuned from rendered frames after the first pass came out
	# black, so this bracket is the thing most likely to be closed by accident by
	# the next person who moves either one.
	var e: Environment = lit.env()
	var thresh: float = e.glow_hdr_threshold
	var gain: float = lit.FIXTURE_GAIN
	var lamp_col: Color = lit.LAMP_COLOR
	var on_e: float = lit.LAMP_ENERGY_ON
	var off_e: float = lit.LAMP_ENERGY_OFF
	var lit_peak := gain * lamp_col.r
	var dark_peak := gain * lamp_col.r * (off_e / on_e)
	check("a powered fixture blooms and an unpowered one does not",
		lit_peak > thresh and dark_peak < thresh,
		"on=%.3f off=%.3f threshold=%.3f" % [lit_peak, dark_peak, thresh])

	# A guard against "restoring the mandate" by setting the off value to zero
	# without reading why it is not zero. The ancestor's world brightness does not
	# depend on the generator at all (html:1695-1702; G.power appears in its
	# renderer once, at :1801), and the generator sits behind bought doors — so a
	# dark pre-power map is both an invention and several rounds of unplayability.
	check("the unpowered map is dimmer than the powered one, and still lit",
		off_e > 0.0 and off_e < on_e,
		"off=%.2f on=%.2f" % [off_e, on_e])

	# Every flip of one of these is a full-screen GLSL compile with no cache on the
	# web, so the policy is decided once at startup and never again. Asserting the
	# two unconditional ones are on is what stops the build quietly acquiring a
	# second post-processing variant that only some machines ever compile.
	check("the post chain is decided once and does not vary at runtime",
		e.adjustment_enabled and e.glow_enabled
			and e.ssao_enabled == QUALITY.heavy_post(),
		"ssao=%s heavy=%s" % [e.ssao_enabled, QUALITY.heavy_post()])



func _level_materials(main: Node3D) -> void:
	var w: WorldBuilder = main.world
	var night: StandardMaterial3D = w._material("night")
	# Unshaded is the whole of A21: it is what stops the torch visibly lighting
	# the stars, which read the Alley as an indoor room with a painted roof.
	# Vertex colour off with it, or the per-tile shade jitter becomes a
	# chequerboard of one-metre squares across the sky.
	check("the night sky is unshaded and takes no tile shade",
		night.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
			and not night.vertex_color_use_as_albedo)

	# The converse, and the one that matters: an unshaded material anywhere else
	# is a surface no light in the game can reach.
	var stray := ""
	for m in w.materials():
		var sm: StandardMaterial3D = m
		if sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and sm != night:
			stray = str(sm.albedo_texture)
	check("nothing else in the level is unshaded", stray.is_empty(), stray)

	# A20. The feature flag is what selects the shader variant, so emission is
	# armed at zero energy from the first frame and only the uniform moves. Arming
	# it inside set_power_on() instead would compile a variant mid-fight, on a
	# platform with no program cache — the failure this ordering exists to avoid.
	var metal: StandardMaterial3D = w._material("metal")
	var armed := metal.emission_enabled and near(metal.emission_energy_multiplier, 0.0)
	w.set_power_on()
	var lifted := near(metal.emission_energy_multiplier, 26.0 / 256.0)
	w.set_power_on()
	var idempotent := near(metal.emission_energy_multiplier, 26.0 / 256.0)
	check("metal emission is armed at zero, lifts on power, and is idempotent",
		armed and lifted and idempotent,
		"armed=%s lifted=%s again=%.4f" % [armed, lifted, metal.emission_energy_multiplier])
	metal.emission_energy_multiplier = 0.0


# --- impact fx ---------------------------------------------------------------

func _impacts(main: Node3D) -> void:
	# The whole layer moved out of main.gd into fx.gd, which main.gd owns as `fx`.
	# Both are plain Node3D here, so every constant read off one comes back Variant
	# and has to be annotated or the parse fails.
	var fx: Node3D = main.fx
	var pool: Array = fx._impacts
	var blood_pool: int = fx.IMPACT_POOL
	var blood_amount: int = fx.IMPACT_AMOUNT
	var one_shader: bool = pool.size() == blood_pool
	for p: GPUParticles3D in pool:
		# One process material and one mesh across the pool. A material per emitter
		# is six process shaders and six draw shaders for one effect, and there is
		# no program cache on the web to make the repeats free.
		if p.process_material != pool[0].process_material or p.draw_pass_1 != pool[0].draw_pass_1:
			one_shader = false
	check("the impact pool is one process shader and one draw shader", one_shader,
		"size=%d" % pool.size())

	# The debris pools are the same discipline one level up: one process material
	# per family shared by every emitter in it, and the per-surface *colour* moved
	# out to the draw material precisely so that a thirteenth wall texture cannot
	# quietly become a thirteenth process shader on a platform that recompiles all
	# of them on every page load.
	var fams: Array = fx._debris
	var per_fam: Array = fx.POOL_PER_FAM
	var fam_count: int = fx.FAM_COUNT
	var procs: Array = []
	var fam_ok: bool = fams.size() == fam_count
	for f in fams.size():
		var sub: Array = fams[f]
		var want_n: int = per_fam[f]
		if sub.size() != want_n:
			fam_ok = false
		for p: GPUParticles3D in sub:
			if p.process_material != sub[0].process_material:
				fam_ok = false
		if not procs.has(sub[0].process_material):
			procs.append(sub[0].process_material)
	check("each debris family is one fixed pool and one process shader",
		fam_ok and procs.size() == fam_count,
		"families=%d procs=%d" % [fams.size(), procs.size()])

	# Trails and sub-emitters are two of the things that work in the editor and
	# silently do not exist under gl_compatibility. Neither warns at runtime.
	var legal := true
	var every: Array = pool.duplicate()
	for f in fams.size():
		var sub: Array = fams[f]
		every.append_array(sub)
	for p: GPUParticles3D in every:
		if p.trail_enabled or not p.sub_emitter.is_empty():
			legal = false
		# VIEW_DEPTH is the one draw order that pays a CPU depth sort, which is the
		# only part of a GPUParticles3D that costs main-thread time.
		if p.draw_order != GPUParticles3D.DRAW_ORDER_INDEX:
			legal = false
	check("no emitter uses a feature that is dead on gl_compatibility", legal)

	# The ancestor's blood table is asymmetric and was reconstructed wrong once
	# already: `head ? 7 : 4` on every damage event (2227), a second burst of 14 on
	# a headshot kill only (2235), and 8 for a body death (2418). The count rides on
	# amount_ratio, so this also pins the half-particle of headroom that stops
	# 4/21*21 truncating to 3 in 32-bit float.
	var p0: Player = main.player
	var table := [[false, false, 4], [false, true, 8], [true, false, 7], [true, true, 21]]
	var got: Array[int] = []
	var want: Array[int] = []
	for row: Array in table:
		var idx: int = fx._impact_next
		p0.impact.emit(Vector3.ZERO, row[0], row[1])
		var e: GPUParticles3D = pool[idx]
		got.append(floori(e.amount_ratio * float(blood_amount)))
		want.append(row[2])
	check("the burst table survives the float round trip", got == want,
		"got %s want %s" % [got, want])

	# A puff is made inside the fire loop, so an allocation here is an allocation
	# per hit — and a Thundergun cone can hit eight zombies in one frame. The
	# emitters are fx's children now, so that is the node count to watch.
	var before_children := fx.get_child_count()
	var start: int = fx._impact_next
	for i in 20:
		p0.impact.emit(Vector3.ZERO, false, false)
	check("twenty impacts allocate nothing and round-robin the pool",
		pool.size() == blood_pool and fx.get_child_count() == before_children
			and fx._impact_next == (start + 20) % blood_pool,
		"next=%d expected=%d" % [fx._impact_next, (start + 20) % blood_pool])

	# One writer per node: an impact positions exactly one emitter and touches no
	# other, or a puff jumps across the map when the pool wraps.
	var was: Array[Vector3] = []
	for p: GPUParticles3D in pool:
		was.append(p.global_position)
	var at := Vector3(3.0, 1.1, 4.0)
	p0.impact.emit(at, false, false)
	var moved := 0
	var landed := false
	for i in pool.size():
		var p: GPUParticles3D = pool[i]
		if p.global_position != was[i]:
			moved += 1
			landed = p.global_position.is_equal_approx(at)
	check("one impact moves exactly one emitter, to the hit point",
		moved == 1 and landed, "moved=%d" % moved)

	# Constraint 7 from the other end. The FX layer is cosmetic and must draw from
	# no stream at all — not even VISUAL, because weapon spread currently rides
	# VISUAL and every cosmetic draw would shift a seeded run's shots. fx.gd has no
	# randf of any kind for exactly this reason: decal roll and scale come from a
	# hash of the hit point, tracer cadence from a counter.
	var streams := [Rng.SPAWN, Rng.BOX, Rng.DROPS, Rng.ROUNDS, Rng.AI, Rng.VISUAL]
	var state_was: Array[int] = []
	for s: StringName in streams:
		state_was.append(Rng.stream(s).state)
	for i in 50:
		p0.impact.emit(Vector3.ZERO, i % 2 == 0, i % 3 == 0)
		fx._on_surface_impact(Vector3(3.5 + float(i) * 0.01, 1.2, 4.0), Vector3.LEFT)
	var untouched := ""
	for i in streams.size():
		if Rng.stream(streams[i]).state != state_was[i]:
			untouched = str(streams[i])
	check("fifty impacts draw from no rng stream at all", untouched.is_empty(),
		"perturbed %s" % untouched)

	# The warm-up pass is the only thing standing between a first draw and a
	# mid-frame GLSL compile in the browser, and the way it fails is by omission:
	# a material added later, never added here, hitches the first time it is seen.
	# The quads live under the camera until three frames have been drawn, and
	# --verify runs at the end of the first, so they are still there.
	var warm: ShaderWarmup = null
	for c in main.get_children():
		if c is ShaderWarmup:
			warm = c
	var seen := []
	if warm != null:
		for n: Node in warm._spawned:
			if n is MeshInstance3D:
				var mi: MeshInstance3D = n
				seen.append(mi.material_override)
	# Every material the game owns, from all six places they are made: the level,
	# the muzzle flash, the zombies' eyes, the zombies' rim, fx.gd's blood / debris
	# / decal / tracer set, and the lamp fixtures. Asserting the *set* rather than
	# the array length is deliberate — a length check breaks the moment a seventh is
	# added, which is exactly when it should still be useful.
	var missing := ""
	var wanted: Array = main.world.materials()
	wanted.append_array(main.atmos.materials())
	wanted.append(Zombie.eye_material())
	wanted.append_array(Zombie.rim_materials())
	wanted.append_array(fx.materials())
	wanted.append_array(main.lighting.materials())
	wanted.append_array(main.viewmodel.materials())
	for m in wanted:
		if not seen.has(m):
			missing += "%s " % m
	check("every material in the game is reachable from the warm-up pass",
		warm != null and missing.is_empty(),
		"warmed=%d missing: %s" % [seen.size(), missing])


# --- screen effects ----------------------------------------------------------

func _walk(n: Node, out: Array[Node]) -> void:
	for c in n.get_children():
		out.append(c)
		_walk(c, out)


## The vignette, the damage wash, the low-HP pulse and the deny flash are four
## rects sharing one baked ramp. Nothing here is about how it looks — that is a
## `--shot` — and everything is about the ramp being the shape the ancestor's LUT
## is, and about the layer still costing zero shader compiles.
func _screen(main: Node3D) -> void:
	var h: Node = main.hud
	_ramp(h)

	# One ImageTexture for the whole layer. Four would be four uploads and four
	# copies of the same 64 KB for an effect that is one gradient.
	check("all four screen rects share one texture",
		h._vignette.texture == h._lowhp.texture and h._dmg.texture == h._lowhp.texture
			and h._deny_rect.texture == h._lowhp.texture)

	# The entire reason the layer is a baked texture and not a shader: WebGL2
	# exposes no program-binary API, so a ShaderMaterial here is a main-thread
	# GLSL compile for every visitor on every page load.
	var kids: Array[Node] = []
	_walk(h, kids)
	var shaded := ""
	for k: Node in kids:
		if k is CanvasItem:
			var ci: CanvasItem = k
			if ci.material != null:
				shaded += "%s " % ci.name
	check("no HUD node carries a material", shaded.is_empty(), shaded)

	# A browser composites an opacity:0 layer away; Godot still rasterises and
	# alpha-blends the quad. Three idle full-screen blends a frame is not free on
	# a target §1.4f already calls fill-rate-bound.
	h._flash = 0.0
	h._deny = 0.0
	h._last_hp = 100.0
	h._on_health(100.0, 100.0)
	h._process(0.016)
	var idle: bool = not h._dmg.visible and not h._lowhp.visible and not h._deny_rect.visible
	h._on_health(90.0, 100.0)
	var one_hit: float = h._flash
	h._on_health(80.0, 100.0)
	var two_hits: float = h._flash
	h._process(0.016)
	check("the transient rects are hidden at rest and shown on damage",
		idle and h._dmg.visible, "idle=%s shown=%s" % [idle, h._dmg.visible])

	# A17 accumulates rather than resetting, so a second hit inside the decay
	# window washes the screen harder than the first. It used to be recomputed
	# from the current health fraction on every emission — including the per-frame
	# regen ticks — so it sat on screen the whole time you were hurt.
	check("the damage wash accumulates rather than resetting",
		two_hits > one_hit and one_hit > 0.0,
		"one=%.3f two=%.3f" % [one_hit, two_hits])
	h._process(2.0)
	check("the wash decays back to nothing", near(h._flash, 0.0) and not h._dmg.visible)

	# Below a third health the pulse must actually be on screen; A16 is invisible
	# otherwise and the player gets no warning at all before going down.
	h._on_health(20.0, 100.0)
	h._process(0.016)
	check("the low-HP pulse lights below a third health", h._lowhp.visible)
	h._flash = 0.0
	h._on_health(main.player.hp, Game.max_health())
	h._process(0.016)

	# The resume click has to reach the player's _unhandled_input, and a Control
	# spanning the whole screen at the default MOUSE_FILTER_STOP swallows it — the
	# overlay did exactly that, and the four bars were eating clicks as well.
	var blockers := ""
	for k: Node in kids:
		if k is Control:
			var c: Control = k
			if (c.anchor_left == 0.0 and c.anchor_top == 0.0 and c.anchor_right == 1.0
					and c.anchor_bottom == 1.0 and c.mouse_filter != Control.MOUSE_FILTER_IGNORE):
				blockers += "%s " % c.name
	check("no full-screen HUD control swallows the mouse", blockers.is_empty(), blockers)
	check("the HUD bars do not swallow the mouse either",
		h._hp_back.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and h._hp_bar.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and h._stam_back.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and h._stam_bar.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and h._hold.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	# A18. The em dash is the only thing separating buying Quick Revive (green)
	# from bleeding out with it (red) — both toasts start with the same two words.
	check("the toast classes read the em dash, not just the first word",
		h._toast_class("Quick Revive") == h.TOAST_GOOD
			and h._toast_class("QUICK REVIVE — hold on") == h.TOAST_BAD,
		"%d / %d" % [h._toast_class("Quick Revive"), h._toast_class("QUICK REVIVE — hold on")])
	check("the rest of the toast table lands on the right colour",
		h._toast_class("NUKE") == h.TOAST_GOOD
			and h._toast_class("POWER ON") == h.TOAST_GOOD
			and h._toast_class(Weapons.PAP_NAMES["mp40"]) == h.TOAST_GOOD
			and h._toast_class("INSTA-KILL") == h.TOAST_BAD
			and h._toast_class("THE BOX HAS MOVED") == h.TOAST_BAD
			and h._toast_class("MAX AMMO") == h.TOAST_NEUTRAL
			and h._toast_class("DOUBLE POINTS") == h.TOAST_NEUTRAL
			and h._toast_class("CARPENTER") == h.TOAST_NEUTRAL)

	# The project configures no theme and no font, so this is stock Open Sans with
	# no fallback chain and the ancestor's ✦ (U+2726, Dingbats) is a notdef box on
	# every Pack-a-Punched weapon. Assert the invariant rather than the glyph, so
	# it survives a custom font being added later.
	var f: Font = h._ammo.get_theme_font("font")
	var has_star: bool = f != null and f.has_char(0x2726)
	check("the Pack-a-Punch mark is never a glyph the font cannot draw",
		h._pap_mark == (" ✦" if has_star else " *"),
		"mark=%s font_has_2726=%s" % [h._pap_mark, has_star])

	# The floating delta feeds this negatives and zero, neither of which the
	# points readout ever did.
	check("thousands separators survive the sign and the zero case",
		h._commas(-1234) == "-1,234" and h._commas(0) == "0"
			and h._commas(1000000) == "1,000,000",
		"%s %s %s" % [h._commas(-1234), h._commas(0), h._commas(1000000)])

	# The title card supersedes the toast for the round announcement; emitting
	# both put the same words on screen twice, 200 px apart.
	var toasts: Array[int] = [0]
	var counter := func(_t: String) -> void:
		toasts[0] += 1
	Game.toast.connect(counter)
	h._on_round(7, false)
	Game.toast.disconnect(counter)
	check("a round announcement raises no toast", toasts[0] == 0 and h._title_card.visible,
		"toasts=%d" % toasts[0])

	# The pop, the floating delta and the round card all run off the play clock,
	# so a state change mid-animation used to strand them: the death screen
	# carried a half-faded round numeral and a blood-red points readout into the
	# next run, with nothing able to clear either.
	h._on_points(Game.points - 500)      # a spend: red readout, pop, floating delta
	Game.set_state(Game.STATE_PLAY)
	check("a state change strands no animation",
		not h._title_card.visible and near(h._title_t, 0.0) and near(h._pop_t, 0.0)
			and near(h._gain.modulate.a, 0.0) and h._points.scale.is_equal_approx(Vector2.ONE)
			and h._points.get_theme_color("font_color") == h.SODIUM)
	h._last_points = Game.points


## The baked alpha ramp on its own. Guarded and separate because every assertion
## below dereferences the image: a null one would abort `run()` before the quit,
## and a headless process that never quits is worse than a red build.
func _ramp(h: Node) -> void:
	# Baked fresh at a known 16:9 so the assertion does not depend on whatever
	# resolution the harness happens to run at.
	var tex: ImageTexture = h._make_vignette_texture(Vector2(1280.0, 720.0))
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		check("the vignette bakes to a readable image", false, "get_image() gave null")
		return
	var n := img.get_width()
	var mid := n / 2 - 1
	var centre := img.get_pixel(mid, mid).a8
	var left := img.get_pixel(0, mid).a8
	var top := img.get_pixel(mid, 0).a8
	var corner := img.get_pixel(0, 0).a8

	# A17's wash rides this ramp, so an inverted one puts the damage flash over
	# the crosshair — which is the one place the effect must never touch.
	check("the ramp is clear at the crosshair and darkest at the corner",
		centre == 0 and corner > left and left > 0,
		"centre=%d left=%d corner=%d" % [centre, left, corner])

	# The ancestor normalises `d` by the half-DIAGONAL in pixels, which makes the
	# ramp aspect-dependent: wide, exactly as the CSS `#vig` (`ellipse 78% 68%`)
	# independently says. Normalising each axis to [-1,1] and letting the stretch
	# put the aspect back transposes the ellipse instead — which pooled the damage
	# wash at the ceiling and the floor rather than at the sides.
	check("the vignette is wider than it is tall, not transposed", left > top * 2,
		"left=%d top=%d" % [left, top])

	# 219 = round((1 - clamp(1.06 - 1^2.7 * 0.92, 0, 1)) * 255), the ancestor's
	# own constants at kriegsnacht.html:1711. Pins 1.06, 0.92 and the 2.7.
	check("the corner matches the ancestor's curve exactly", corner == 219,
		"got %d" % corner)

	# The bake is quadrant-folded to cut 16k sqrt+pow iterations to 4k, which is
	# hand-written index arithmetic into a PackedByteArray — one transposed
	# addend and three quarters of the screen are wrong.
	var symmetric := true
	var falls := true
	for y in n / 2:
		var prev := 256
		for x in n / 2:
			var a := img.get_pixel(x, y).a8
			if (img.get_pixel(n - 1 - x, y).a8 != a or img.get_pixel(x, n - 1 - y).a8 != a
					or img.get_pixel(n - 1 - x, n - 1 - y).a8 != a):
				symmetric = false
			# Along the middle row x runs from the left edge inward, so the ramp
			# must never rise: a bump anywhere in it is a band across the screen.
			if y == mid and a > prev:
				falls = false
			prev = a
	check("the baked quadrants are symmetric about both axes", symmetric)
	check("alpha falls monotonically from the edge to the crosshair", falls)


# --- pause and the pointer ---------------------------------------------------

## Losing the pointer lock IS the pause event, which makes the HUD's two
## watchdogs load-bearing for anything that runs without a pointer — every
## headless run, every `--shot` capture, every soak. Neither can be tested
## against a real lock here: DisplayServerHeadless reports MOUSE_MODE_VISIBLE
## forever, so `_lock_seen` never arms. That is exactly the condition worth
## asserting, because it is also what an automated run always sees.
func _pointer_lock(main: Node3D) -> void:
	var h: Node = main.hud
	h._lock_seen = false
	h._resume_armed = false
	Game.set_state(Game.STATE_PLAY)
	for i in 100:
		h._process(0.016)
	# Without the arming guard, a machine that never grants the lock — headless,
	# a sandboxed iframe, the MCP input service — pauses itself on the first frame
	# of play and can never leave. --verify, --autostart and --shot all depend on
	# this one branch not firing.
	check("a run that never captures the pointer never pauses itself",
		Game.state == Game.STATE_PLAY)

	h._pause()
	# Pausing never re-captures. Resume is a click, because that is the only
	# gesture carrying the transient activation requestPointerLock() demands.
	check("_pause releases the pointer and asks for nothing back",
		Game.state == Game.STATE_PAUSE and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)

	for i in 100:
		h._process(0.016)
	# exitPointerLock() is asynchronous exactly like requestPointerLock(), so
	# pausing with P while still locked leaves document.pointerLockElement set for
	# a frame or two. An unarmed check reads that as the resume gesture and the
	# pause flickers straight back to play.
	check("an armed resume watchdog does not, on its own, resume",
		Game.state == Game.STATE_PAUSE)

	Game.set_state(Game.STATE_PLAY)
	h._lock_seen = false
	h._resume_armed = false


# --- input -------------------------------------------------------------------

func _input_latch(main: Node3D) -> void:
	var p: Player = main.player

	# P is primary. Escape alone means pausing takes two presses (the user agent
	# swallows the first while the pointer is locked) and can never resume, since
	# the HTML spec excludes Escape from the events that grant activation.
	var codes: Array[int] = []
	for e: InputEvent in InputMap.action_get_events("pause"):
		var k := e as InputEventKey
		if k != null:
			codes.append(k.physical_keycode)
	check("pause is bound to P as well as Escape",
		codes.size() == 2 and codes.has(KEY_P) and codes.has(KEY_ESCAPE), str(codes))

	# A release delivered outside play used to be swallowed by the two early
	# returns above the fire block, leaving the latch armed. Hold an automatic,
	# pause, let go, take the pointer back with L — and the gun fires with nothing
	# held until the button is cycled again.
	p._fire_held = true
	Game.set_state(Game.STATE_PAUSE)
	var release := InputEventAction.new()
	release.action = &"fire"
	release.pressed = false
	p._unhandled_input(release)
	check("a trigger release outside play still clears the latch", not p._fire_held)

	# A wheel tick is an InputEventMouseButton too, and it grants no activation —
	# so resuming on one would set the state to play against a pointer that never
	# re-locked, and the HUD would pause again a frame later.
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	p._unhandled_input(wheel)
	check("a wheel tick is not a resume gesture", Game.state == Game.STATE_PAUSE)

	# The resume click must resume and must not also be a trigger pull: it was
	# aimed at an overlay, and an automatic held when the window lost focus would
	# otherwise fire the instant the state flipped back.
	p._fire_held = true
	p._fire_buffer = 0.18
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	p._unhandled_input(click)
	check("the resume click resumes without firing",
		Game.state == Game.STATE_PLAY and not p._fire_held and near(p._fire_buffer, 0.0),
		"state=%d held=%s buffer=%.3f" % [Game.state, p._fire_held, p._fire_buffer])
	Player.set_capture(false)


# --- hit geometry ------------------------------------------------------------

# --- the weapon state machine ------------------------------------------------

func _weapon_fsm(main: Node3D) -> void:
	var p: Player = main.player

	# DELIVERED FIRE RATE. `_update_fire` runs at a fixed 60 Hz, and the old code
	# set an absolute 60/rpm cooldown against a countdown clamped at zero — so
	# every remainder inside a tick was thrown away and every rate quantised up to
	# a multiple of 1/60 s. No automatic weapon fired at its stated RPM.
	#
	# The damage was not what the plan recorded. It does not invert the RPK against
	# the M16; it *collides* weapons that are supposed to feel different: MP40 (880)
	# and M16 (740) both delivered 720, AK-74u (710) and RPK (700) both delivered
	# 600. This is the assertion that would have caught it, and it needs no scene.
	var worst := ""
	var worst_err := 0
	var delivered := {}
	for key: String in Weapons.TABLE:
		var g := Weapons.make_gun(key, false)
		# Never reload; we are measuring cadence and nothing else.
		g.mag = 1 << 30
		g.res = 1 << 30
		var shots := 0
		for i in 3600:
			WEAPON.tick(g, 1.0 / 60.0, true)
			while float(g.next_shot) <= 0.0:
				WEAPON.consume_shot(g, 1.0)
				shots += 1
		delivered[key] = shots
		var want: int = int(Weapons.TABLE[key].get("rpm", Weapons.DEFAULTS.rpm))
		var err: int = absi(shots - want)
		if err > worst_err:
			worst_err = err
			worst = "%s delivered %d of %d" % [key, shots, want]
	check("every weapon delivers its stated RPM", worst_err <= 1, worst)

	# States the actual damage rather than the tolerance: two weapons may share a
	# cadence only if the table says they should.
	var collided := ""
	for a: String in delivered:
		for b: String in delivered:
			if a >= b:
				continue
			var ra: int = int(Weapons.TABLE[a].get("rpm", Weapons.DEFAULTS.rpm))
			var rb: int = int(Weapons.TABLE[b].get("rpm", Weapons.DEFAULTS.rpm))
			if delivered[a] == delivered[b] and ra != rb:
				collided = "%s and %s both fire %d" % [a, b, delivered[a]]
	check("no two weapons collide onto one cadence", collided.is_empty(), collided)

	# HOLSTERING CANCELS A RELOAD. Call of Duty's rule, and NOT the ancestor's —
	# html:2966 ticks only the current gun, so a stowed reload there freezes
	# indefinitely and resumes on the way back. Completing it instead would make a
	# swap a free reload: start a 4.6 s RPK, fight with the pistol, come back full.
	p.guns = [Weapons.make_gun("rpk", false), Weapons.make_gun("m1911", false)]
	p.slot = 0
	var rpk: Dictionary = p.guns[0]
	rpk.mag = 0
	WEAPON.begin_reload(rpk, 1.0)
	check("a reload is running before the swap",
		int(rpk.state) == WEAPON.State.RELOADING)
	p._swap_weapon()
	check("holstering cancels the reload rather than banking it",
		int(rpk.state) != WEAPON.State.RELOADING and float(rpk.reloading) == 0.0,
		"state=%d reloading=%.2f" % [int(rpk.state), float(rpk.reloading)])
	check("the cancelled reload credited no ammunition",
		int(rpk.mag) == 0, "mag=%d" % int(rpk.mag))

	# The shells already in the tube are kept: a shell reload credits each one as it
	# lands, so cancelling costs the shell in progress and nothing behind it. That
	# falls out of per-shell crediting rather than needing a special case, which is
	# the argument for crediting per shell in the first place.
	p.guns = [Weapons.make_gun("stakeout", false), Weapons.make_gun("m1911", false)]
	p.slot = 0
	var sg: Dictionary = p.guns[0]
	sg.mag = 0
	WEAPON.begin_reload(sg, 1.0)
	# 1.5 s against a 3.4 s tube of six, i.e. 0.567 s a shell — long enough to have
	# credited two and short enough to still be mid-reload. Running it to 4 s filled
	# the magazine and quietly tested nothing, which is the failure mode a
	# both-ends bound on `loaded` below exists to catch.
	for i in 90:
		WEAPON.tick(sg, 1.0 / 60.0, false)
	var loaded: int = int(sg.mag)
	p._swap_weapon()
	check("cancelling a shell reload keeps the shells already loaded",
		int(sg.mag) == loaded and loaded > 0 and loaded < int(sg.def.mag),
		"kept %d of %d" % [loaded, int(sg.def.mag)])



func _hit_geometry(main: Node3D) -> void:
	var p: Player = main.player
	var cam := p.camera()

	var seen: Array[int] = [0, 0]
	var where: Array[Vector3] = [Vector3.ZERO]
	var on_impact := func(at: Vector3, _hs: bool, _killed: bool) -> void:
		seen[0] += 1
		where[0] = at
	var on_conf := func(_hs: bool, _killed: bool) -> void:
		seen[1] += 1
	p.impact.connect(on_impact)
	p.hit_confirmed.connect(on_conf)

	var z := Zombie.create("zombie", 0, 1, false)
	main.add_child(z)
	z.add_to_group("zombies")
	var ahead := cam.global_position - cam.global_transform.basis.z * 3.0
	# These two used to assert the opposite, and they are worth leaving a note on:
	# they were careful, detailed, and they pinned a bug. The old pair required the
	# cone to headshot, with a comment warning that losing it would "silently
	# downgrade every cone kill from 100 points to 60" — treating 60 as the failure.
	# 60 is the correct payout. The Thundergun was crediting a headshot on every kill
	# in the wedge because `_cone_blast` aimed its synthetic hit point at the head,
	# and the ancestor passes `false` for headshot outright (html:2543).
	#
	# So the float knife-edge the old comment described is real but no longer load
	# bearing: the aim point is centre mass now, which is nowhere near the threshold,
	# and a ground snap or a step-up can no longer move the payout.
	#
	# The body is still deliberately stood off zero height, because that is what
	# makes the local-height recovery (`at.y - z.global_position.y`) meaningful — at
	# y == 0 the arithmetic is degenerate and the check proves nothing.
	z.global_position = Vector3(ahead.x, 0.01, ahead.z)
	p._cone_blast(Weapons.spec("thundergun"))
	var local_y: float = where[0].y - z.global_position.y
	check("the cone kills what stands in the wedge",
		z.state == Zombie.State.DYING,
		"y=%.3f state=%d" % [z.global_position.y, z.state])
	check("a cone kill is not credited as a headshot",
		not z._last_headshot,
		"headshot=%s" % z._last_headshot)
	check("the cone aims at centre mass, well clear of the head threshold",
		local_y < z.head_threshold() - 0.05,
		"local_y=%.4f threshold=%.4f" % [local_y, z.head_threshold()])

	# One event per zombie actually damaged, on both signals — the HUD binds to
	# hit_confirmed and the FX layer to impact, and a duplicate is a double marker
	# and a double blood puff.
	check("one impact and one hit_confirmed per damaged zombie",
		seen[0] == 1 and seen[1] == 1, "impact=%d confirmed=%d" % [seen[0], seen[1]])
	p.impact.disconnect(on_impact)
	p.hit_confirmed.disconnect(on_conf)
	z.queue_free()

	# The downed drop is a real camera move, and the node chain exists so that
	# each transform component has exactly one writer. Head's height is the drop,
	# Head's rotation is the mouse, RecoilPivot is the spring, Camera3D is the
	# bob — the recoil bug was one shared writer and no better maths would have
	# fixed it.
	var head: Node3D = p._head
	var pitch_was := head.rotation.x
	p.is_downed = true
	for i in 60:
		p._update_view(1.0 / 60.0, Player.SPEED)
	var dropped: float = head.position.y
	check("going down lowers the eye to DOWNED_EYE",
		near(dropped, Player.DOWNED_EYE, 0.001), "y=%.3f" % dropped)
	check("the drop writes nothing but Head's height",
		near(head.rotation.x, pitch_was) and p._recoil_pivot.position == Vector3.ZERO
			and near(p.camera().position.y, 0.0, 0.02))

	# move_toward integrates dt, so the fall has to land in the same place at any
	# frame rate. A per-frame lerp would not, and would fall faster on a fast
	# machine — which is the classic form of this bug. Sampled 0.2 s in, while the
	# drop is still in flight: the full 1.15 m takes 0.36 s at DOWNED_EYE_RATE, and
	# comparing two finished falls would prove nothing.
	head.position.y = Player.EYE
	for i in 6:
		p._update_view(1.0 / 30.0, Player.SPEED)
	var coarse: float = head.position.y
	head.position.y = Player.EYE
	for i in 24:
		p._update_view(1.0 / 120.0, Player.SPEED)
	check("the drop is frame-rate independent",
		near(coarse, head.position.y, 0.001),
		"30hz=%.4f 120hz=%.4f" % [coarse, head.position.y])

	p.is_downed = false
	for i in 60:
		p._update_view(1.0 / 60.0, Player.SPEED)
	check("standing up restores the eye height", near(head.position.y, Player.EYE, 0.001))


# --- quality governor --------------------------------------------------------

## Driven with synthetic deltas rather than by waiting: the whole mechanism is a
## rolling average of frame times, and a headless run's frame times describe
## nothing. What is being asserted is the state machine, not the measurement.
func _quality(main: Node3D) -> void:
	var vp := main.get_viewport()
	var live := main.get_node_or_null("QualityGovernor")
	# A --shot capture has to be reproducible frame for frame and a --verify run
	# is measuring something else entirely; neither may have the render scale
	# moved under it.
	check("the live governor is inert under --verify",
		live != null and not live.is_processing() and near(vp.scaling_3d_scale, 1.0),
		"processing=%s scale=%.2f" % [live != null and live.is_processing(), vp.scaling_3d_scale])

	var seen: Array[float] = []

	# Behind the title card the warm-up pass is deliberately compiling every
	# shader in the project, and behind the pause and death screens almost nothing
	# is drawn. Measuring through either demotes every machine on the planet.
	var g := _governor(main)
	Game.set_state(Game.STATE_TITLE)
	_drive(g, vp, 0.2, 50, seen)
	check("no demotion outside play", near(vp.scaling_3d_scale, 1.0),
		"scale=%.2f" % vp.scaling_3d_scale)

	Game.set_state(Game.STATE_PLAY)
	_drive(g, vp, 0.2, 12, seen)         # 2.4 s, just inside SETTLE
	check("no demotion inside the settle window", near(vp.scaling_3d_scale, 1.0),
		"scale=%.2f" % vp.scaling_3d_scale)

	# Two seconds of 30 fps a go: more than the 1.4 s window needs, so the last of
	# the settle frames cannot swallow one of them and leave the window a frame
	# short. 30 is under the ancestor's threshold of 38 and over the 4 fps floor
	# the spike cap imposes, so each pass is one unambiguous bad window.
	_drive(g, vp, 1.0 / 30.0, 60, seen)
	var first := vp.scaling_3d_scale
	_drive(g, vp, 1.0 / 30.0, 60, seen)
	var second := vp.scaling_3d_scale
	_drive(g, vp, 1.0 / 30.0, 60, seen)
	check("a sustained bad window steps down the ladder and clamps at the bottom",
		near(first, 0.75) and near(second, 0.5) and near(vp.scaling_3d_scale, 0.5),
		"%.2f -> %.2f -> %.2f" % [first, second, vp.scaling_3d_scale])

	# Statics live on the script, and main.gd holds a preload reference to it, so
	# the verdict outlives `reload_current_scene()`. Without it a bad machine
	# re-learns it after every death — four seconds of exactly the frame rate that
	# killed the player — and the two-promotion budget silently becomes per life.
	check("the verdict is recorded outside the scene", QUALITY._kept_step == 0,
		"kept=%d" % QUALITY._kept_step)
	g.queue_free()

	# One 700 ms hitch inside an otherwise healthy window is an uncached shader
	# compile, not a broken machine — but the cap that absorbs it must not make a
	# genuinely 3 fps machine unmeasurable. A fresh governor starts at the top of
	# the ladder, so the viewport is put back there with it.
	vp.scaling_3d_scale = 1.0
	var g2 := _governor(main)
	_drive(g2, vp, 0.2, 13, seen)           # settle out
	_drive(g2, vp, 1.0 / 60.0, 75, seen)    # 1.25 s of 60 fps
	_drive(g2, vp, 0.7, 1, seen)            # one compile hitch closes the window
	var survived := near(vp.scaling_3d_scale, 1.0)
	_drive(g2, vp, 0.34, 6, seen)           # ~3 fps, capped at 4, still under 38
	check("a single spike does not demote but a sustained 3 fps still does",
		survived and near(vp.scaling_3d_scale, 0.75),
		"survived spike=%s after 3fps=%.2f" % [survived, vp.scaling_3d_scale])
	g2.queue_free()

	# The ladder is the ancestor's three QUAL widths expressed as fractions. A
	# scale off it is a render-target size nothing was ever tested at.
	var off := ""
	for s: float in seen:
		if not QUALITY.STEPS.has(s):
			off += "%.3f " % s
	check("every scale it ever selects is a rung of the ladder", off.is_empty(), off)

	vp.scaling_3d_scale = 1.0
	Game.set_state(Game.STATE_PLAY)


## A fresh governor rather than the live one, which is inert by design. Its
## _ready() early-returns under --verify before touching the viewport, so it
## starts at the top of the ladder however the statics were left.
func _governor(main: Node3D) -> Node:
	var g: Node = QUALITY.new()
	main.add_child(g)
	return g


func _drive(g: Node, vp: Viewport, dt: float, frames: int, seen: Array[float]) -> void:
	for i in frames:
		g._process(dt)
		var s: float = vp.scaling_3d_scale
		if not seen.has(s):
			seen.append(s)


# --- what the perf probe assumes ---------------------------------------------

## scripts/perf_probe.gd is not in the shipped build and cannot assert anything
## from the inside. Three things it depends on live here, and one thing it must
## never become lives in project.godot. All four fail in the way that matters
## most: they produce a plausible number instead of an error.
func _probe_contract(main: Node3D) -> void:
	# The probe POSTs to 127.0.0.1:8970 and drives main.gd directly. It is
	# registered as an autoload only by tools/build.ps1 -Perf and by
	# tools/perf_native.ps1, both of which restore project.godot in a finally block
	# — so a surviving `PerfProbe=` line means a run was killed hard, and shipping
	# it would point every visitor's browser at a localhost socket.
	check("the perf probe is not a committed autoload",
		not ProjectSettings.has_setting("autoload/PerfProbe"))

	# perf_probe._freeze_governor() finds the render-scale governor by this exact
	# node name and takes it out of the frame loop, because a governor left running
	# can demote mid-ladder and hand two render scales one label. A rename here does
	# not break the game and does not break --verify; it silently unpins the render
	# target under every future benchmark.
	check("the live render-scale governor is named QualityGovernor",
		main.get_node_or_null("QualityGovernor") != null)

	# M-SEP records the RAW, pre-clamp separation sum, because _separation() returns
	# the value after limit_length() and the question is how far past the limit the
	# raw sum reaches. So the probe carries its own copy of the inner loop, and a
	# copy rots. Pin the three constants it reproduces.
	check("separation constants are what the perf probe reproduces",
		near(Zombie.SEPARATION_RADIUS, 0.62) and near(Zombie.SEPARATION_FORCE, 2.4)
			and near(Zombie.SEPARATION_LIMIT, 0.6),
		"radius=%.3f force=%.3f limit=%.3f" % [Zombie.SEPARATION_RADIUS,
			Zombie.SEPARATION_FORCE, Zombie.SEPARATION_LIMIT])

	# SYNTHESIS 4.5 item 3, asserted as behaviour rather than as the line that
	# implements it. Six neighbours crowded on one side sum to about four before
	# scaling; unclamped and multiplied by 2.4 that is nearly ten times the
	# unit-length flow vector it is added to, which is the repulsion-gas bug.
	var here := Vector2(8.5, 8.5)
	var subject := Zombie.create("zombie", 0, 1, false)
	main.add_child(subject)
	subject.global_position = Vector3(here.x, 0.0, here.y)
	var pack: Array = []
	for i in 6:
		var other := Zombie.create("zombie", 0, 1, false)
		main.add_child(other)
		other.global_position = Vector3(here.x - 0.05, 0.0, here.y - 0.05 * float(i + 1))
		pack.append(other)
	subject.neighbours = pack
	var mag: float = subject._separation(here).length()
	check("six crowded neighbours cannot outweigh the flow vector",
		mag <= Zombie.SEPARATION_LIMIT + 0.001,
		"got %.3f against limit %.3f" % [mag, Zombie.SEPARATION_LIMIT])
	subject.queue_free()
	for z: Zombie in pack:
		z.queue_free()


# --- M-VMCLIP ----------------------------------------------------------------

## The viewmodel's whole safety argument, asserted rather than assumed.
##
## The player capsule has RADIUS = 0.24, so world geometry can never come within
## 0.24 m of the camera origin. If every vertex of every weapon sits inside that,
## wall clipping is not mitigated or depth-tricked — it is geometrically
## impossible. That is why this rig needs no clip shader, no second viewport and no
## depth hack, and it is only true for as long as these hold.
func _viewmodel(main: Node3D) -> void:
	var vm: Node3D = main.viewmodel

	# BEFORE ANYTHING ELSE: prove the sweep measured something. Every check below
	# passes trivially against an empty point set, so a builder that silently
	# returned nothing would report a perfectly clean bill of health. That is not
	# hypothetical — the reviewer of this package hit exactly that bug, by filling a
	# PackedVector3Array passed as a parameter.
	# The per-weapon floor is the whole guard: a builder that returned nothing makes
	# EVERY weapon thin, so this cannot be satisfied by an empty set. An aggregate
	# total would need a magic number, and the first one tried here was wrong by a
	# factor of two — the real figure is ~1270 across thirteen entries — which is a
	# good argument for asserting the shape rather than the size.
	var pts := 0
	var thin := ""
	for key: String in GUNART.keys():
		var body: PackedVector3Array = GUNART.body_corners(key)
		if body.size() < 40:
			thin += key + " "
		pts += body.size()
	check("every weapon reports its own corners", thin.is_empty(),
		"%d corners total, thin: %s" % [pts, thin])

	# The real M-VMCLIP. Projection-aware — sqrt(z^2 + ratio^2*(x^2+y^2)) — because
	# the gun is drawn through a narrowed projection, so the plain radius is not
	# sufficient and would pass a weapon that clips.
	var screen: float = vm.max_screen_radius()
	check("no viewmodel vertex can reach a wall", screen < Player.RADIUS,
		"widest %.4f m against Player.RADIUS %.3f" % [screen, Player.RADIUS])

	# The design budget: weaker than the above, and kept because it is the number a
	# person adding a weapon can hold in their head. Read CLIP_RADIUS off the
	# preloaded script rather than the instance — a constant fetched through a
	# Node3D-typed variable is the unsafe property access this project builds as an
	# error.
	var r: float = vm.max_corner_radius()
	check("the viewmodel fits its design budget", r <= VIEWMODEL.CLIP_RADIUS,
		"worst corner %.4f m against %.3f" % [r, VIEWMODEL.CLIP_RADIUS])

	# The near plane fails the same way a wall clip does and would be misdiagnosed
	# as one — the barrel disappears into the camera rather than into a wall.
	var d: float = vm.min_corner_depth()
	var near_plane: float = main.player.camera().near
	check("no viewmodel vertex crosses the near plane", d > near_plane,
		"nearest %.4f m against near %.3f" % [d, near_plane])

	# The budget has to stay tied to the capsule rather than to a number somebody
	# liked. If RADIUS is ever lowered the entire argument evaporates in silence,
	# and this is the only place that would notice.
	check("the clip budget still fits inside the player capsule",
		VIEWMODEL.CLIP_RADIUS < Player.RADIUS,
		"%.3f vs %.3f" % [VIEWMODEL.CLIP_RADIUS, Player.RADIUS])

	# A weapon added to Weapons.TABLE with no art row leaves the player holding
	# nothing, mid-round, with no error at all — the mesh is simply null.
	var missing := ""
	for key: String in Weapons.TABLE:
		if not GUNART.ART.has(key):
			missing += key + ":art "
		if not GUNART.GRIP.has(key):
			missing += key + ":grip "
		if not GUNART.MUZZLE.has(key):
			missing += key + ":muzzle "
	check("every weapon in the table has viewmodel art", missing.is_empty(), missing)
