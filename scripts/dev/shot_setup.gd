extends RefCounted

## Named world states that can be PHOTOGRAPHED, and the measurements to take from
## the photograph.
##
## §4 of the workflow audit: "states that need input cannot be photographed at
## all. An armed trap needs power, 1000 points and an F press; ADS needs a held
## button; the downed state needs a death. Each agent that wanted one hand-patched
## `_tick_shot`, took its frames, and reverted. Three did this independently."
## This is that itch, scratched once.
##
## A scenario is two halves, and they belong in one file because the second is
## meaningless without the first: `apply()` puts the world into the state, and
## `probe()` says what to measure in the resulting frame. The rim/body ratio only
## means something if you know which zombie is the one standing 3 m dead ahead.
##
## ---------------------------------------------------------------------------
## DETERMINISM, which is the whole value of the thing. A scenario that renders
## differently on two runs is not a baseline, it is a random number. Four rules,
## and every scenario below obeys all four:
##
##   1. `Rng.new_run(SEED)` before anything else. A walker's starting animation
##      frame and phase are drawn from the VISUAL stream (zombie.gd:471-474), so
##      an unseeded horde is a different horde every run.
##   2. The player is TELEPORTED to an exact position and yaw. Never walked.
##   3. Systems are driven BY DIRECT CALL, never by waiting for a clock. Where a
##      real timed animation is the subject — the power-on ceremony — the settle
##      budget is set long enough to contain all of it, and where it is merely in
##      the way — the round title card — it is stepped out in one call.
##   4. Bodies that are only there to be looked at are FROZEN
##      (`PROCESS_MODE_DISABLED`) after placement. A walking horde is
##      reproducible under `--fixed-fps`, but it makes every measurement a
##      hostage to physics-tick accounting for no gain: the rim shader does not
##      care whether the zombie's legs are moving.
##
## ---------------------------------------------------------------------------
## THE SETTLE BUDGET IS SECONDS OF GAME TIME, AND IT USED TO BE FRAMES.
##
## That was a real defect and it made the two halves of this package disagree
## about what they were looking at. `tools/frames.ps1` passes `--fixed-fps 60`, so
## for the gate a frame count was N/60 seconds and everything was consistent — but
## CLAUDE.md documents a BARE `--shot out.png --shot-setup <name>` for the human
## pass, and a bare run is uncapped. Measured on this machine, 2026-07-31, all
## eight scenarios captured both ways:
##
##   scenario     bare fps   PNG identical to the --fixed-fps 60 capture?
##   spawn          ~141     YES, byte for byte
##   power_off      ~141     YES
##   horde          ~141     YES
##   trap_armed     ~141     no  (frame mean 0.052522 -> 0.053527, the arc is cyclic)
##   downed         ~141     no  (black 0.5053 -> 0.5578, the eye had not finished
##                                dropping)
##   ads            ~122     no  (gun_mean 0.02259 -> 0.02515, +11.3%)
##   raygun         ~113     no  (bolt_mean 0.18168 -> 0.10343, the bolt is 43% of
##                                the way somewhere else)
##   power          ~141     no, AND THIS IS THE ONE THAT MATTERS: the bare capture
##                           is BYTE-IDENTICAL TO `power_off`. At the shutter the
##                           ceremony had reached lamps 5, 6 and 7 of eight and the
##                           Lobby lamp — the only one in frame — was still at
##                           LAMP_ENERGY_OFF. A person doing the human pass would
##                           have compared `power.png` against its own control, seen
##                           no difference whatsoever, and concluded the reveal was
##                           broken.
##
## So the numeric gate and the reference image a human looks at could be different
## states, and for `power` they were opposite ones. Three of the eight are genuinely
## time-independent, which is why this went unnoticed: `notes/perf/frames/README.md`
## recorded "three plain --shot captures were byte-identical with and without
## --fixed-fps", and it was true — of those three.
##
## AFTER, RE-MEASURED THE SAME WAY, 2026-07-31, and the fix is not total — which is
## worth writing down rather than leaving for somebody to rediscover as a mystery:
##
##   spawn / power_off / horde   identical, as before
##   ads                         NOW IDENTICAL   (0.5000 s / 30 frames against
##                               0.5033 s / 83 frames — the pose has arrived and
##                               stopped moving, so 3 ms buys nothing)
##   power                       NOW IDENTICAL   (2.8500 s / 171 against 2.8526 s /
##                               469 — the headline defect; the ceremony is over in
##                               both, and the `until` predicate is what guarantees
##                               it rather than the budget)
##   raygun                      still differs, worst +0.67% (bolt_mean)
##   downed                      still differs, worst +1.36% (p99)
##   trap_armed                  still differs, worst -6.41% (arc_mean), frame mean
##                               -3.33% — OUTSIDE the gate's own 3% band
##
## The residual is structural and cannot be removed by making the budget better:
## `settle` is a FLOOR and a bare run's `dt` is ~1/141 s, so the shutter overshoots
## by up to one uncapped frame — 0.0017 s on `raygun`, 0.0030 s on `trap_armed`.
## For a state that has converged that is worth nothing; for a bolt in flight and a
## cyclic arc sheet it is worth a few per cent. The three that still differ are
## exactly the three whose subject is a MOMENT rather than a destination, which is
## also the reason none of them has an `until`. A human comparing `trap_armed.png`
## against `ref/trap_armed.png` by eye will see the arc at a different phase and
## that is expected; the GATE always runs `--fixed-fps 60`, so it is unaffected.
##
## `settle` is therefore SECONDS OF GAME TIME, accumulated from the real `dt`, which
## is the same quantity under both invocations. `until` is the other half: an
## ARRIVAL PREDICATE, so a state that has to arrive is photographed once it has
## rather than at a frame number somebody hoped would be enough, and main.gd fails
## loudly rather than shooting early if it never does. Both kinds are expressible
## because both kinds exist here — the bolt in flight is a moment, the sights are a
## destination.
##
## Every `settle` below is an exact multiple of 1/60 s, so under `--fixed-fps 60`
## the frame count is unambiguous and stated beside it.

const FRAME_STATS := preload("res://scripts/dev/frame_stats.gd")

## One seed for every scenario. Arbitrary, fixed, and it must never change
## without re-blessing every golden row — which is the point of writing it down.
const SEED := 20260730

## Where the game actually starts, restated rather than imported so that the
## `spawn` scenario is provably the same viewpoint every historical `--shot` in
## notes/perf/shots/ was taken from. (The frame is not identical to one of those:
## `_quiet` below puts the round ceremony in a defined state, which a plain
## `--shot` leaves to a race.)
const SPAWN_AT := Vector2(8.5, 8.5)

## One step long enough to retire the round title card, whose whole life is
## TITLE_TIME 2.1 + Sfx.ROUND_SILENCE 1.2 = 3.3 s (hud.gd:1330).
const HUD_SETTLE := 4.0

## Where `power` and `power_off` both stand, and NOT the spawn tile.
##
## The spawn tile is (8.5, 8.5) and the Lobby's lamp hangs at (9.0, 2.35, 8.5) —
## which is to say directly overhead and out of frame at every yaw. Photographing
## the ceremony from there measures the room's bounce and never once sees the
## thing that actually reads as the lights coming on, which is the FIXTURE
## crossing the glow threshold (lighting.gd FIXTURE_GAIN). From the south end of
## the room the same lamp sits 3.5 m ahead and 0.8 m up: 12.9 degrees above the
## horizon against a 37-degree half-FOV, comfortably in frame.
const LAMP_VIEW := Vector2(8.5, 12.0)

## The Lobby is ROOMS[0], so its lamp — and its fixture quad — is lamp index 0.
const LAMP_ROOM := 0

## THE VIEWMODEL'S SCREEN RECT AT 1280x720, MEASURED FROM A RENDERED FRAME.
##
## It cannot be unprojected. The viewmodel is drawn by `viewmodel.gd`'s VM_CODE
## shader, which re-projects the gun at its own VIEWMODEL_FOV of 55 degrees
## instead of the camera's 74 — so `Camera3D.unproject_position` on the gun's
## AABB gives a rect the gun is not in. A hard-coded rect is the honest answer,
## and the probe reports the fraction of it that is above black, so a rect that
## has stopped containing the gun moves the numbers and fails the gate rather
## than silently measuring wall.
##
## Two of them because ADS_CENTRE removes the whole of REST_POS at the sights:
## the gun crosses most of the screen between the two states.
## Both READ OFF THE REFERENCE FRAMES in notes/perf/frames/ref/ with a pixel
## ruler, not estimated. The first ADS rect was a guess and it put roughly half
## the gun outside and half a wall inside; `gun_lit_frac` said 0.535, the same as
## the hip rect's, which is exactly what a rect measuring the wrong thing looks
## like when only its mean is read.
##
## THE RULER IS NOW PRINTED, so neither of these has to be estimated again.
## `--frames <name>` prints the viewmodel's silhouette box every capture — located
## by difference, not by eye (main.gd::_bare_frame, frame_stats.changed_box) — and
## these rects are that box plus a pad. Measured 2026-07-31, 1280x720:
##
##   spawn  x 773..952  y 479..674   (20829 px over 196 rows)
##   ads    x 606..673  y 365..529   ( 9029 px over 165 rows)
##
## Only VM_RECT_ADS is re-read, and it is re-read because the sight-line fix moved
## the weapon down: the previous rect was y 280..525, which is eighty-five rows of
## bare wall above the weapon and the weapon's last four rows CROPPED OFF the
## bottom. The pad is 6 px, enough to keep the whole silhouette plus its glow
## inside without letting the wall dominate.
##
## VM_RECT_HIP IS DELIBERATELY LEFT ALONE even though the same measurement says it
## crops five rows (it ends at y 669, the weapon at 674). `spawn.probes.gun_mean`
## is the numerator of `the viewmodel is lit`, whose band [4.5, 12.0] carries a
## measured 7.52 taken through THIS rect; moving the rect would invalidate that
## provenance to recover five rows of a two-hundred-row weapon. The number is
## written down here so the next person re-reading it does not have to measure
## again — but changing it is a decision with a reason, not a tidy-up.
##
## AND THE "BISTABLE ADS POSE" IN THE PREVIOUS VERSION OF THIS COMMENT WAS THE
## SETTLE BUG. It recorded "two fully settled poses differing by 10.8% on
## `gun_mean`", differing in x 606..673 and nowhere else, and sized this rect for
## both. Measured 2026-07-31: a bare `--frames ads` and a `--fixed-fps 60` one
## differed by 11.3% on `gun_mean` for exactly that reason — the same frame count
## bought 0.42 s of game time instead of 1.0 s, so the weapon's raise (`_swap`,
## viewmodel.gd) had not finished in one of them. With the budget in seconds the
## two invocations now produce a byte-identical silhouette: `x 606..673 y 365..529,
## 9029 px` from both. The x range in that old note is the same x range measured
## here, which is what a weapon that moved only vertically looks like. It is a
## strong hypothesis rather than a closed case — the note also claimed the two
## poses were unchanged out to frame 240, and that part is not reproduced here.
const VM_RECT_HIP := Rect2i(770, 470, 190, 200)
const VM_RECT_ADS := Rect2i(600, 359, 80, 177)

## The hip viewmodel's silhouette with margin, for probes that must look at the
## WORLD and not at the gun in front of it. Deliberately a SECOND constant rather
## than a widened `VM_RECT_HIP`, and the distinction is the reason both exist:
## `VM_RECT_HIP` is the window `gun_px` and `gun_mean` are measured IN, so growing
## it changes what those probes report and re-blesses two scenarios; this one is a
## window other probes are measured OUTSIDE, so it wants margin and costs nothing
## by having it. Widening one to serve both would couple a viewmodel measurement to
## a zombie measurement, and the next weapon that changes size would move both.
##
## Measured, not guessed: differencing `ref/horde.png` against `current/horde.png`
## after the iron sights landed puts every changed pixel in the frame inside
## `x[774..944] y[464..584]` — 909 samples at a 2 px stride, and ZERO of them left
## of x = 700. Eight pixels of margin on each side of that, which also covers the
## `spawn` silhouette Stage 1 measured at `x 778..952 y 463..674`.
const VM_RECT_HIP_KEEPOUT := Rect2i(766, 455, 194, 226)

## Chroma margins for the two colour masks, in DISPLAY code fractions (the frame
## is sRGB-encoded and a hue test does not need decoding — it is a comparison
## between channels of the same pixel, and the encode is monotonic and identical
## on all three).
##
## Everything lighting this map is sodium (0.98, 0.72, 0.34) or torch
## (1.0, 0.94, 0.82): every lit surface in the game is WARM. The two additive
## effects worth measuring are the only cold things in it — the zombie rim
## (190, 200, 220, zombie.gd:1386) and the trap arc (0.58, 0.86, 1.0,
## traps.gd:209). So "b - r > margin" selects effect and "r - b > margin"
## selects lit surface, and the crosshair, which is neutral white, falls in
## neither.
## MEASURED, not picked, and 0.05 was measured and rejected. At 0.05 the rim
## registers no pixels at all below RIM_ENERGY 0.30 — 0.0 and 0.16 produce
## byte-identical probe values — so the mask goes blind exactly where the low
## bound needs to discriminate. At 0.02 the count is monotone across the whole
## sweep (see _probe_rim).
const COLD_MARGIN := 0.02
const WARM_MARGIN := 0.02
## The Ray Gun bolt is the one green thing in the game (0.63, 1.0, 0.35).
const GREEN_MARGIN := 0.06

## THE MUZZLE FLASH'S PROBE RINGS, in units of the halo quad's own projected
## HALF-WIDTH — which is the ancestor's `r*2.4`, the radius its radial gradient
## runs out to (html:3150). Every one of them is measured off the LIVE quad's
## transform, so the rings move with the flash instead of assuming where it is.
##
## All three are ROTATION-INVARIANT, which is what lets them be committed against
## a burst whose orientation advances every shot. `atmosphere.gd`'s star has its
## innermost vertices at 0.20/2.4 = 0.0833 of the halo half-width and its tips at
## 0.62/2.4 = 0.2583, so:
##
##   CORE_R  0.075   inside the star at EVERY orientation, and inside the hot
##                   core disc (0.22/2.4 = 0.0917) as well. This is the near-white
##                   layer html:3158-3168 draws and the port had lost.
##   RING    0.72..0.92  outside the star at every orientation, so it is pure
##                   gradient — the tinted halo the core is supposed to be hotter
##                   and whiter than.
##   CORNER  four discs of 0.10 centred 0.85 of the way from the middle to the
##                   quad's own projected corners, i.e. at 1.20 half-widths. That
##                   is INSIDE the quad (its diagonal reaches 1.414) and OUTSIDE
##                   the gradient (which is alpha 0 past 1.0). A radial flash
##                   cannot light them; a flat fill across the quad lights them
##                   exactly as brightly as its middle. This is the one statistic
##                   that says "disc, not square" rather than "bright, not dark".
const FLASH_CORE_R := 0.075
const FLASH_RING_LO := 0.72
const FLASH_RING_HI := 0.92
const FLASH_CORNER_AT := 0.85
const FLASH_CORNER_R := 0.10

## Below this display code a pixel is unlit background and belongs to no mask.
## Same 8/255 the black-pixel fraction uses, for the same reason.
const MASK_FLOOR := 8.0 / 255.0

## The scenario the horde frame measures its rim against. Set by `_horde`, read
## by `probe`. A static rather than a lookup because there is exactly one process
## per scenario — see `--frames` in main.gd for why.
static var _rim_target: Zombie = null
static var _bolt: Node3D = null
## Whether the flash scenarios' arrival predicate has already pulled the trigger.
## Reset by their own `fn`, so a scenario cannot inherit it — even though one
## process only ever runs one scenario (see `--frames` in main.gd).
static var _flash_fired := false

static var _reg: Dictionary = {}


## name -> {fn, settle, why, until?}.
##
##   `fn`     Callable(main). Puts the world into the state.
##   `settle` SECONDS OF GAME TIME between the scenario landing and the shutter.
##            Always waited out in full — it is the floor, not the criterion.
##   `until`  OPTIONAL Callable(main) -> bool. The state has actually arrived.
##            When present the shutter waits for it as well as for `settle`, and
##            main.gd aborts the capture loudly if it never becomes true.
##   `why`    what the frame is for. Read by the registry audit, which rejects a
##            row that does not bother to say.
##
## A dictionary of Callables rather than a `match` with a parallel list of names,
## because a registry that is checked against a second copy of itself is the
## tautology verify.gd's `_registered()` was written to avoid. There is one list
## here and everything — `--frames-list`, the suite's completeness check, the
## golden file audit — reads it.
##
## WHICH SCENARIOS GET AN `until`, and why the other five do not. A predicate is
## worth writing where there is a crisp end state the scenario's own NAME claims:
## `power` is "the wave has finished", `ads` is "the sights are reached", `downed`
## is "the eye is on the floor", and `flash_hip`/`flash_ads` are "there is a
## muzzle flash on screen". Those five are also the five whose budget
## encodes a guess about somebody else's constant — raise ADS_TIME past `settle`
## and a frame count would silently photograph a half-raised gun, where the
## predicate photographs the sights or says it could not. The other five have no
## such state: `raygun` and `trap_armed` are MOMENTS in a continuing animation
## (a bolt 3.45 m out; an arc sheet that cycles forever), and `spawn`, `power_off`
## and `horde` are static — measured byte-identical between a 0.35 s budget and a
## 0.14 s one, which is what convergence looks like. For those five the seconds
## ARE the specification, and a predicate would be a second copy of it.
static func registry() -> Dictionary:
	if not _reg.is_empty():
		return _reg
	_reg = {
		"spawn": {
			"fn": _spawn, "settle": 0.35,   # 21 frames at 60
			"why": "the default view, byte-for-byte the frame plain --shot takes",
		},
		# THE THREE THE GATE COULD NOT SEE — see `_gun_view`. Same 0.35 s budget as
		# `spawn` and for the same reason: identical static pose, and it was measured
		# byte-identical between a 0.35 s budget and a 0.14 s one. Each is `spawn`
		# with one thing changed, so `mp40.mean / spawn.mean` isolates the weapon.
		"mp40": {
			"fn": _mp40, "settle": 0.35,
			"why": "the MP40 in the hand, so its detail rows are inside a gate",
		},
		"stakeout": {
			"fn": _stakeout, "settle": 0.35,
			"why": "the Stakeout in the hand, so its detail rows are inside a gate",
		},
		"rpk": {
			"fn": _rpk, "settle": 0.35,
			"why": "the RPK in the hand, so its detail rows are inside a gate",
		},
		# The powered/unpowered PAIR, and they exist as a pair on purpose. An
		# absolute golden row for "the lit map" has to be re-blessed every time
		# somebody retunes a lamp; the RATIO between these two does not, and the
		# ratio is what both shipped black frames destroyed. Same viewpoint, same
		# yaw, one difference — see LAMP_VIEW.
		"power_off": {
			"fn": _power_off, "settle": 0.35,
			"why": "the control for `power`: identical view, generator not thrown",
		},
		"power": {
			# 3*0.16 + 0.18 + 7*0.15 + 0.42 = 2.13 s of ceremony (lighting.gd
			# STAGGER/RAMP), so 2.85 s (171 frames at 60) is the whole wave plus
			# margin — and `until` is what actually decides, so lengthening the
			# ceremony moves the shutter with it instead of cropping the reveal.
			"fn": _power, "settle": 2.85, "until": _power_arrived,
			"why": "the same view with the generator thrown and the wave finished",
		},
		"trap_armed": {
			"fn": _trap_armed, "settle": 0.5,
			"why": "a live electric gate, the only cold additive surface in the level",
		},
		"ads": {
			# ADS_TIME is 0.22 s; 0.5 s (30 frames at 60) is arrived plus margin,
			# and `until` is the requirement rather than the margin.
			"fn": _ads, "settle": 0.5, "until": _ads_arrived,
			"why": "the sights, which is where the viewmodel is largest on screen",
		},
		"downed": {
			# DOWNED_EYE_RATE 3.2 takes (1.55-0.40)/3.2 = 0.36 s.
			"fn": _downed, "settle": 0.7, "until": _downed_arrived,
			"why": "on the floor: eye height dropped, overlay up, pistol forced",
		},
		"horde": {
			"fn": _horde, "settle": 0.35,
			"why": "eight round-12 walkers in a lit room — the frame the 3.4x rim was found in",
		},
		"raygun": {
			# RAY_SPEED 23 m/s, so 0.15 s (9 frames at 60) puts the bolt 3.45 m out;
			# FLASH_TIME 0.14 s, so the muzzle flash is out and what is left lighting
			# the room is the bolt itself, which is the subject. NO PREDICATE: the
			# subject is a moment in a flight, and 0.15 s is the specification.
			"fn": _raygun, "settle": 0.15,
			"why": "a Ray Gun bolt in flight with its own light on it",
		},
		# THE TWO THE GATE HAD NEVER SEEN. `raygun` fires a real shot and is the
		# closest anything came, and by its 0.15 s shutter the flash has been gone
		# for 0.10 s: `ref/raygun.png` shows the bolt downrange and no flash at all.
		# So the whole effect had no committed number against it until a player
		# reported it as "an obvious yellow square", which is the same shape of hole
		# that let an ADS sight line ship 64 px above the crosshair.
		"flash_hip": {
			# 0.35 s (21 frames at 60) is `spawn`'s budget, for the same reason —
			# it is the same pose, and it is a FLOOR here rather than the criterion.
			"fn": _flash_hip, "settle": 0.35, "until": _flash_hip_up,
			"why": "the muzzle flash at the hip, on the frame it is fired",
		},
		"flash_ads": {
			# ADS_TIME is 0.22 s; 0.5 s is `ads`'s budget and the predicate below
			# will not pull the trigger until `player.ads()` has actually reached 1.
			"fn": _flash_ads, "settle": 0.5, "until": _flash_ads_up,
			"why": "the muzzle flash at the sights, which is where the complaint was",
		},
	}
	return _reg


# --- the arrival predicates ---------------------------------------------------

## Every one of these asks the SYSTEM THAT OWNS THE STATE, not a clock and not a
## copy of the constant that drives it. `player.ads()` is the same accessor
## viewmodel.gd poses the weapon from, so a predicate that is satisfied is a
## viewmodel that is posed; a predicate written as `t >= ADS_TIME` would be a
## second statement of ADS_TIME that could drift from the first.

## Full ADS. `Player._update_ads` move_toward()s `_ads` to 1.0 over ADS_TIME and
## `_can_ads()` can refuse it outright — downed, or sprinting — so this is also
## the check that the synthetic `Input.action_press("ads")` in `_ads` was actually
## honoured. A capture that never reaches it fails rather than photographing hip.
static func _ads_arrived(main: Node3D) -> bool:
	var p: Player = main.player
	return p.ads() >= 1.0


## The wave has finished: every lamp at LAMP_ENERGY_ON, read off the lights
## themselves rather than off `_powered` (which is set on the FIRST frame of the
## ceremony, before a single lamp has moved) or off a copy of the schedule.
##
## This is the predicate the bare-`--shot` measurement above was crying out for.
static func _power_arrived(main: Node3D) -> bool:
	var lit: Node3D = main.lighting
	var on: float = lit.LAMP_ENERGY_ON
	var lamps: Array[OmniLight3D] = lit._lamps
	if lamps.is_empty():
		return false
	for l: OmniLight3D in lamps:
		if not is_equal_approx(l.light_energy, on):
			return false
	return true


## On the floor: the head has finished travelling to DOWNED_EYE. `is_downed` alone
## is true on the frame `_go_down` runs, 0.36 s before the camera gets there.
static func _downed_arrived(main: Node3D) -> bool:
	var p: Player = main.player
	return p.is_downed and is_equal_approx(p._head.position.y, Player.DOWNED_EYE)


## THE PREDICATE THAT PULLS THE TRIGGER, and it is the honest answer to a 0.05 s
## effect rather than a way around one.
##
## `atmosphere.FLASH_TIME` is 0.05 s — three frames at 60, one at a bad web frame
## rate — so there is NO settle budget that lands inside it. The three ways out
## were: lengthen the flash, which is tuning the game to fit the harness and was
## refused; freeze the clock, which needs a hook in main.gd that this package does
## not own; or fire the shot at the moment the frame is wanted, which is this.
##
## So the scenario body puts the world into the pose and the PREDICATE fires the
## weapon, on the first frame after the settle floor at which the pose it is named
## for has actually arrived. `_shoot()` emits `fired` synchronously, atmosphere's
## listener places the flash inside that call, and `flash_visible()` is therefore
## already true when this returns — so the shutter is the SAME frame as the shot
## and the flash is photographed at its full life, whatever `dt` happens to be.
## That makes these two scenarios time-independent in the way `raygun` is not.
##
## A SIDE-EFFECTING PREDICATE IS UNUSUAL AND IT EARNS ITS KEEP AT THE FAILURE
## END. Fired once and no flash appeared — a `fired` signal nobody listens to, a
## flash quad that never became visible, a weapon that refused the shot — and this
## returns false forever, so main.gd's ARRIVAL_GRACE expires and the capture dies
## with "never arrived" instead of quietly photographing an empty barrel. A frame
## count could not tell those apart from a mistimed shutter.
##
## Through `_shoot`, which is what `_update_fire` calls on a trigger pull, and NOT
## through an input event: fire is event-driven here (player.gd:482) and a queued
## InputEventAction lands on whichever frame the flush reaches it. Same call, and
## the same reasoning, as `_raygun`.
static func _fire_for_flash(main: Node3D, want_ads: bool) -> bool:
	var atmos: Node3D = main.atmos
	if bool(atmos.flash_visible()):
		return true
	if _flash_fired:
		return false
	if want_ads and not _ads_arrived(main):
		return false
	_flash_fired = true
	var p: Player = main.player
	p._shoot(p.current_gun())
	return bool(atmos.flash_visible())


static func _flash_hip_up(main: Node3D) -> bool:
	return _fire_for_flash(main, false)


static func _flash_ads_up(main: Node3D) -> bool:
	return _fire_for_flash(main, true)


## The scenario's arrival predicate, or an empty Callable when it has none.
## Empty rather than a `func(): return true` so main.gd can tell "this scenario
## does not have one" from "this scenario's has already fired" — only the first
## may skip the loud failure.
static func arrival_of(name: String) -> Callable:
	var reg := registry()
	if not reg.has(name):
		return Callable()
	var row: Dictionary = reg[name]
	if not row.has("until"):
		return Callable()
	var c: Callable = row["until"]
	return c


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in registry().keys():
		out.append(k)
	return out


## Puts the world into `name` and returns the SECONDS OF GAME TIME to advance
## before the shutter. -1.0 for an unknown name, which every caller must treat as
## fatal: a typo that silently photographs the default view is a golden row that
## means nothing.
static func apply(name: String, main: Node3D) -> float:
	var reg := registry()
	if not reg.has(name):
		return -1.0
	var row: Dictionary = reg[name]
	# A SCREENSHOT MUST NOT TOUCH THE PLAYER'S SAVE FILE. `Game` checkpoints the
	# profile on `round_changed` (game_state.gd) and two scenarios below drive a
	# real round change, so without this `--frames horde` writes best_round 12
	# into whoever's profile.json is on the machine. verify.gd:183-185
	# disconnects it for exactly this reason; the process exits straight after
	# the capture, so there is nothing to put back.
	if Game.round_changed.is_connected(Game._on_round_changed):
		Game.round_changed.disconnect(Game._on_round_changed)
	# Before the scenario body, not inside it, so no scenario can forget.
	Rng.new_run(SEED)
	var fn: Callable = row["fn"]
	fn.call(main)
	_quiet(main)
	var settle: float = row["settle"]
	return settle


## The round ceremony is the confound EVERY scenario shares, and it took a
## rendered frame to see it.
##
## `start_game()` opens a FIRST_ROUND_DELAY intermission, so round one begins on
## the director's own clock — and the title card it raises is a 190 px numeral
## and a red full-screen wash held for TITLE_TIME + ROUND_SILENCE = 3.3 s
## (hud.gd:1330). Whether it is in a given capture depends on nothing but how
## that delay happens to line up with the scenario's settle budget. The first
## `power` capture was a photograph of the card: mean 0.0111, and none of it was
## the lamps.
##
## So the round is begun HERE, deterministically, and the card is stepped out in
## one call rather than waited out — the audit's "drive systems by direct call
## rather than by waiting", applied to the one system every scenario inherits.
static func _quiet(main: Node3D) -> void:
	if Game.round_no <= 0:
		main.rounds.force_round(1)
	# Parked, not drained. `_to_spawn = 0` with nothing alive makes the very next
	# `tick()` call `_end_round()`, which opens the intermission for round TWO
	# and raises a second card partway through a long settle. An intermission
	# whose timer nothing can reach stops the director dead without rewriting any
	# of its state, and leaves a scenario's own placed bodies alone.
	main.rounds._intermission = true
	main.rounds._round_timer = 1.0e9
	main.hud._process(HUD_SETTLE)


static func settle_of(name: String) -> float:
	var reg := registry()
	if not reg.has(name):
		return -1.0
	var row: Dictionary = reg[name]
	var s: float = row["settle"]
	return s


# --- the camera pose ----------------------------------------------------------

## Yaw and pitch, latched when the scenario lands and re-asserted by
## `main.gd::_tick_shot` on every frame from there to the shutter.
##
## The camera chain is `Player(yaw) -> Head(pitch) -> ...`, so the two live on
## different nodes; both are written here because both are things a stray mouse
## can move, and a capture whose pitch drifted is as wrong as one whose yaw did.
static var _pose := Vector2.ZERO


static func aim(main: Node3D, yaw: float, pitch: float) -> void:
	var p: Player = main.player
	p.rotation.y = yaw
	p._head.rotation.x = pitch
	_pose = Vector2(yaw, pitch)


static func latch(main: Node3D) -> void:
	var p: Player = main.player
	_pose = Vector2(p.rotation.y, p._head.rotation.x)


static func hold(main: Node3D) -> void:
	var p: Player = main.player
	p.rotation.y = _pose.x
	p._head.rotation.x = _pose.y


# --- the scenarios ------------------------------------------------------------

## Teleport, square up, and stop dead. `velocity` is cleared because
## CharacterBody3D keeps it across a position write, and a scenario that arrives
## sliding is a scenario whose settle frames move the camera.
static func _place(main: Node3D, at: Vector2, yaw_deg: float) -> void:
	var p: Player = main.player
	p.global_position = Vector3(at.x, 0.0, at.y)
	p.velocity = Vector3.ZERO
	p.rotation.y = deg_to_rad(yaw_deg)
	# The pitch lives on Head, one node down (see the camera chain in CLAUDE.md).
	p._head.rotation.x = 0.0


## The powered state WITHOUT the ceremony.
##
## `lighting.power_on()` is a 2.13 s tween, and three of the scenarios below want
## a lit room rather than the reveal. Driving the tween would make each of them
## wait out the whole wave and would make every one of their golden rows a
## hostage to tween scheduling. So this writes the end state the wave arrives at,
## and marks the node powered so a later real `power_on()` is the no-op it is
## already written to be. The `power` scenario, whose subject IS the ceremony,
## goes through `_do_interact` instead.
static func _power_now(main: Node3D) -> void:
	Game.power_on = true
	main.world.set_power_on()
	main.atmos.light_perks()
	var lit: Node3D = main.lighting
	lit._powered = true
	var on_e: float = lit.LAMP_ENERGY_ON
	lit._set_all(on_e)


static func _spawn(main: Node3D) -> void:
	_place(main, SPAWN_AT, 0.0)


## THE THREE WEAPONS THE GATE COULD NOT SEE. `give_gun` was called exactly once in
## this whole file — by `_raygun` — so every other scenario ran the starting M1911,
## and the Ray Gun is the one weapon carrying no detail rows. MEASURED when the
## detail band landed: with the MP40, Stakeout and RPK rows in the table and only the
## M1911's removed, `downed` reproduced its committed golden row bit for bit. Eleven
## of fourteen rows sat outside every gate the project has, verified only in a
## painter mock with no FILMIC, no lighting and no perspective.
##
## Framed exactly like `spawn` — same tile, same yaw, same light — so each is that
## weapon's own A/B against a frame the gate already holds, and the only difference
## between the four is which gun is in frame.
static func _gun_view(main: Node3D, key: String) -> void:
	_place(main, SPAWN_AT, 0.0)
	var p: Player = main.player
	p.give_gun(key, false)


static func _mp40(main: Node3D) -> void:
	_gun_view(main, "mp40")


static func _stakeout(main: Node3D) -> void:
	_gun_view(main, "stakeout")


static func _rpk(main: Node3D) -> void:
	_gun_view(main, "rpk")


static func _power_off(main: Node3D) -> void:
	_place(main, LAMP_VIEW, 0.0)


## The real purchase path, driven from the interaction table rather than by
## calling `lighting.power_on()` — because the thing most likely to break here is
## one of the four side effects that hang off the same branch (the metal plate,
## the perk machine lights, `Game.power_on`), and a scenario that calls only the
## lamps could not see any of them go missing.
##
## The switch itself is free in this build and in the reference (BO1's generator
## costs nothing), so no points are needed; `_state_of` returns cost 0
## (interaction_system.gd:338-341).
static func _power(main: Node3D) -> void:
	_place(main, LAMP_VIEW, 0.0)
	var it := _item(main, "power")
	if it.is_empty():
		push_error("[shot-setup] no 'power' item in the interaction table")
		return
	main.interact._do_interact(it, main.interact._state_of(it))


## The Corridor gate (traps.gd SPOTS[0], rect x 20..22), seen from 3 m west.
## Yaw -90 degrees because Godot's forward is -Z, so -90 about Y turns it to +X.
static func _trap_armed(main: Node3D) -> void:
	_power_now(main)
	_place(main, Vector2(17.4, 8.6), -90.0)
	# Through `arm()`, which re-checks the power and the cycle for itself, rather
	# than by writing the trap dictionary — the refusal rules are part of what a
	# frame of an "armed" trap is asserting.
	if not main.traps.arm("corridor"):
		push_error("[shot-setup] traps.arm('corridor') refused")


## The sights. `Input.action_press` and not a hand-written `_ads = 1.0`: ADS is
## POLLED (`player.gd::_wants_ads` reads `Input.is_action_pressed`), so a
## synthetic press drives the real transition through the real `_update_ads`, the
## real FOV write and the real viewmodel pose. Assigning `_ads` would skip all
## three and photograph a state the game cannot reach.
static func _ads(main: Node3D) -> void:
	_place(main, SPAWN_AT, 0.0)
	Input.action_press("ads")


## Downed, not dead. `_go_down` requires the perk — without it `take_damage`
## emits `died`, main.gd turns that into STATE_OVER and the tree pauses, and the
## scenario photographs a death screen while claiming to photograph a crawl.
static func _downed(main: Node3D) -> void:
	_place(main, SPAWN_AT, 0.0)
	var p: Player = main.player
	Game.perks["revive"] = true
	Game.revives_left = 1
	p.hp = Game.max_health()
	p.take_damage(9999.0, 424242)


## Eight round-12 walkers in a lit Lobby: the frame the M4 review measured the
## rim in ("a lit frame of eight walkers... mean luminance of 146/255 against a
## body mean of 42").
##
## The one at 3.0 m dead ahead is the rim probe's subject and it is placed alone:
## every other body is at least 1.2 m off the centre line and a metre further
## back, so none of them can put a pixel inside its rect. The seven exist so the
## frame is a horde rather than a portrait — the defect was found in a crowd.
static func _horde(main: Node3D) -> void:
	_power_now(main)
	_place(main, SPAWN_AT, 0.0)

	# The real round change, so the HUD numeral, the tally pips and the round-12
	# HP and speed class are all what a round 12 actually is. `_quiet` retires the
	# card it raises — which lands exactly where the rim probe's rect is — and
	# parks the director so nothing else walks into the shot.
	main.rounds.force_round(12)

	# Facing -Z from z=8.5, so a smaller z is further ahead. The Lobby is
	# x 3..14, z 3..13 (map_data.gd:46), so all of these are indoors.
	var at := [
		Vector2(8.5, 5.5),    # 3.0 m dead ahead — the probe's subject
		Vector2(7.3, 4.2), Vector2(6.3, 4.2), Vector2(5.3, 4.3),
		Vector2(9.7, 4.2), Vector2(10.7, 4.2), Vector2(11.7, 4.3),
		Vector2(8.5, 4.2),
	]
	var made: Array[Zombie] = []
	for i in at.size():
		var pos: Vector2 = at[i]
		# Palette cycled rather than rolled: `Rng.randi_range` here would advance
		# VISUAL between the per-zombie animation draws inside `_configure` and
		# make the horde depend on the order this loop happens to run in.
		var z := Zombie.create("zombie", i % 3, 12, false)
		main.add_child(z)
		z.global_position = Vector3(pos.x, 0.0, pos.y)
		made.append(z)
	# Frozen only after every one of them exists, so `_configure`'s VISUAL draws
	# all happen in one uninterrupted block.
	for z in made:
		z.process_mode = Node.PROCESS_MODE_DISABLED
	_rim_target = made[0]


## A bolt in the air with its own OmniLight3D on it.
##
## Fired through `_shoot`, which is what `_update_fire` calls on a trigger pull:
## it spends the round, kicks the camera, emits `fired` for the muzzle flash and
## calls `_launch`. Not through the input event, because fire is EVENT-driven
## here (`_unhandled_input`, player.gd:482) rather than polled like ADS, and a
## queued InputEventAction lands on whichever frame the flush reaches it.
## Deliberately UNPOWERED and framed exactly like `spawn`, so the pair is a clean
## A/B: one identical view, one extra light source. `raygun.mean / spawn.mean` is
## then the bolt's whole contribution to the frame and nothing else's, which is
## the relation the gate holds it to.
static func _raygun(main: Node3D) -> void:
	_place(main, SPAWN_AT, 0.0)
	var p: Player = main.player
	p.give_gun("raygun", false)
	p._shoot(p.current_gun())
	for c in main.get_children():
		if c.name.begins_with("Proj_"):
			_bolt = c


## The two flash poses. Deliberately framed exactly like `spawn` and `ads` — same
## tile, same yaw, same weapon — so each has a blessed control one relation away:
## whatever the flash does to `mean`, `black` and the chromaticity is the whole
## difference between these and the pair they were copied from.
##
## The trigger is NOT pulled here. It is pulled by the arrival predicate, on the
## frame the pose has arrived and the shutter is ready — see `_fire_for_flash`.
static func _flash_hip(main: Node3D) -> void:
	_flash_fired = false
	_place(main, SPAWN_AT, 0.0)


static func _flash_ads(main: Node3D) -> void:
	_flash_fired = false
	_place(main, SPAWN_AT, 0.0)
	# Polled, not evented — see `_ads` for why this is a synthetic press and not
	# an assignment to `_ads`.
	Input.action_press("ads")


static func _item(main: Node3D, kind: String) -> Dictionary:
	for it: Dictionary in main.interact.table():
		if String(it.get("kind", "")) == kind:
			return it
	return {}


# --- the probes ---------------------------------------------------------------

## Scenario-specific scalars measured off the captured frame. Whole-frame
## statistics come from frame_stats.of(); these are the things that need to know
## WHERE to look.
##
## Every one of them ships its own denominator so the gate can be relational.
## `rim_mean` on its own would have to be re-blessed every time a lamp moved;
## `rim_over_body` would not have moved at all, and it is the number that was
## 3.48 when the defect shipped and 1.59 after it was fixed.
## Which scenarios MUST produce probe values.
##
## Separate from `probe()` on purpose. Every one of the probes below returns `{}`
## when the thing it was pointed at is missing — no rim target, no trap row, no
## bolt — and `{}` is indistinguishable from "this scenario has no probes" unless
## something says which is which. Without this, a Ray Gun that stopped launching
## anything would produce an empty probe dict, a clean golden row and a green
## gate. `downed` is the ONE scenario with no probe of its own: its whole subject
## is the frame's own statistics — dropped eye height, red overlay, forced pistol
## — and none of those has a rect worth naming.
static func probes_expected(name: String) -> bool:
	return name in ["spawn", "ads", "horde", "trap_armed", "raygun",
		"power", "power_off", "flash_hip", "flash_ads"]


## EVERY PROBE HERE READS THE LIVE SCENE, so it must run on the frame it is
## measuring and not one later. That is not hypothetical: the silhouette probe
## needs a SECOND rendered frame with the viewmodel hidden, and taking it before
## these ran moved `raygun`'s bolt_mean by 2.8% and bolt_frac by 1.9% on a frame
## whose every whole-frame statistic was bit-identical — because `_probe_bolt`
## unprojects `_bolt.global_position` and the bolt had advanced a tick while the
## extra frame was drawn. (Pausing the tree does not stop it; see `_bare_frame`.)
## So the split is deliberate: this runs first, against the world that produced
## `img`, and `probe_silhouette` runs after, against two images and nothing else.
static func probe(name: String, main: Node3D, img: Image) -> Dictionary:
	match name:
		"spawn":
			return _probe_viewmodel(img, VM_RECT_HIP)
		"ads":
			return _probe_viewmodel(img, VM_RECT_ADS)
		"horde":
			return _probe_rim(main, img)
		"trap_armed":
			return _probe_arc(main, img)
		"raygun":
			return _probe_bolt(main, img)
		"power", "power_off":
			return _probe_fixture(main, img)
		"flash_hip", "flash_ads":
			return _probe_flash(main, img)
	return {}


## The half of the viewmodel probe that needs the SECOND frame. Separate from
## `probe()` for the ordering reason stated there, and named per scenario here
## rather than inferred from `bare != null` so that a scenario which has no
## viewmodel measurement cannot silently acquire one.
##
## `spawn` and `ads` are the two poses the rig has, and between them they cover
## every screen position the weapon ever occupies.
static func silhouette_expected(name: String) -> bool:
	return name in ["spawn", "ads"]


static func probe_silhouette(name: String, img: Image, bare: Image) -> Dictionary:
	if not silhouette_expected(name):
		return {}
	return _probe_silhouette(img, bare)


## The lamp fixture, which is what the power-on ceremony actually reads as.
##
## lighting.gd is explicit that the room getting brighter is NOT the reveal —
## "the fixtures cross the glow threshold, which nothing in the pre-power map
## does" — so a gate that only watched the frame mean would pass a build where
## the ceremony had stopped happening and the rooms had merely been lifted. The
## whole point of the `power` / `power_off` pair is that this one number can be
## divided by its own control.
static func _probe_fixture(main: Node3D, img: Image) -> Dictionary:
	var lit: Node3D = main.lighting
	var at: Vector3 = lit.lamp_position(LAMP_ROOM)
	# HALF of FIXTURE_SIZE, because the quad is centred on the lamp position and
	# FIXTURE_SIZE is its full width. A box of the full size around it projects to
	# 13209 px against the quad's own 2100, and 84% ceiling in the denominator
	# drags the measurement toward the room it is supposed to be measured against.
	var half: float = float(lit.FIXTURE_SIZE) * 0.5
	var cam: Camera3D = main.player.camera()
	var pts := PackedVector3Array()
	for i in 8:
		pts.append(at + Vector3(
			half if (i & 1) else -half,
			half if (i & 2) else -half,
			half if (i & 4) else -half))
	var r := _rect_of(cam, pts, 2)
	var whole := FRAME_STATS.of(img)
	var m := FRAME_STATS.rect_mean(img, r)
	var ref: float = whole["mean"]
	return {
		"fixture_mean": m,
		"fixture_px": float(r.size.x * r.size.y),
		"fixture_over_frame": FRAME_STATS.ratio(m, ref),
	}


## The viewmodel black-frame regression, as a number.
##
## The second of the two shipped black frames was the viewmodel: a display-space
## value used as a linear one left the gun almost invisible against a dark room,
## and the suite had 483 assertions and no way to see it. `gun_over_frame` is the
## gun's own light divided by the frame's, so it survives a lighting retune and
## does not survive the gun going out.
##
## Divided by the MEAN and not the median, measured: this game's median frame
## pixel is 0.0005 linear — 72% of the spawn frame is at or below display code 8
## — so a median denominator produces a ratio of 100 whose every digit is
## quantisation noise in the darkest pixel of a black room. The mean is 0.0065,
## thirteen times larger and dominated by lit surface, which is the thing the gun
## should be compared against.
static func _probe_viewmodel(img: Image, r: Rect2i) -> Dictionary:
	var lit := FRAME_STATS.masked(img, r, _above_floor)
	var whole := FRAME_STATS.of(img)
	var ref: float = whole["mean"]
	var mean: float = lit["mean"]
	var frac: float = lit["frac"]
	var cy: float = lit["cy"]
	return {
		"gun_mean": mean,
		# Bounds the rect at both ends. A gun that has gone dark drops this
		# toward zero; a rect that has stopped containing the gun and is
		# measuring wall drops it too, and neither can hide behind the mean.
		"gun_lit_frac": frac,
		# WHERE the gun is, as a fraction down its rect. A brightness statistic
		# cannot see a viewmodel that slid, and a viewmodel that slides is a real
		# defect class here: the ADS pose is bistable across sessions (see
		# VM_RECT_ADS) and `gun_mean` alone reports that as "the frame drifted",
		# which is a mystery rather than a bug report. It is also the only number
		# in the gate that would move if the gun clipped into the near plane or
		# drifted off the bottom of the screen.
		"gun_cy": cy,
		"gun_over_frame": FRAME_STATS.ratio(mean, ref),
	}


## WHERE THE WEAPON IS, and it is the number the gate did not have.
##
## `the sights keep the frame` (ads.mean / spawn.mean, 0.909, band [0.78, 1.10])
## is PHOTOMETRIC, and so is every other rule in the file. Nothing constrained
## geometry — which is why a shipped ADS pose that put the M1911's whole sight line
## 66 px ABOVE the crosshair, with the player aiming underneath the weapon, passed
## the gate without moving a single committed number. A frame can be the right
## brightness and the wrong picture.
##
## The silhouette is located by DIFFERENCE, against the same instant with the
## viewmodel hidden (main.gd::_bare_frame). Not by a colour mask: viewmodel.gd
## rejected that when it derived ADS_SIGHT_CLEAR — "the M1911's slide is the only
## blue-grey thing in the table and a mask tuned to it cannot tabulate the other
## twelve" — and in the ADS rect a brightness mask is worse than useless, because
## `gun_lit_frac` is 0.95 there and the topmost lit row is the top of the RECT.
##
## THE THRESHOLD AND THE ROW MINIMUM, MEASURED rather than picked. With the
## viewmodel visibility left alone, the two frames differ in ZERO pixels at
## thresh = 1 on all eight scenarios: the noise floor is exactly nothing, because
## the tree is paused across the second draw. thresh = 3 and min_run = 4 are
## therefore not fitted to noise that exists — they are there so that a future
## driver that dithers, or a scenario with a shader that reads TIME, degrades into
## a slightly smaller box rather than into a box the size of the frame.
##
## Both numbers are RATIOS AGAINST THE FRAME CENTRE, not pixel rows, so they mean
## the same thing if `window/size/viewport_width` ever changes:
##
##   `sight_top_over_centre`   1.0 is the top of the weapon exactly on the
##                             crosshair; above 1.0 is below it, which is what
##                             looking down an iron sight looks like; below 1.0 is
##                             the weapon covering the aim point, which is the
##                             defect.
##   `gun_cx_over_centre`      1.0 is the weapon centred on the aim point.
##
## -1.0 when nothing changed at all, which is the empty-mask case this file is
## careful about everywhere: a viewmodel that stopped drawing must fail the gate,
## not report a top edge of row zero. `gun_px` bounds it at the other end.
##
## THE DIFFERENCE IS ONLY CLEAN ON A SETTLED FRAME, and that is worth knowing
## rather than discovering. Pausing the tree stops `_process` for a pausable node,
## but the camera's ADS zoom is still in flight if the shutter fired mid-transition,
## and then the two draws differ in FOV and the box is the whole frame. MEASURED,
## by forcing the shutter 0.05 s into the ADS transition: `x 0..1279 y 0..719,
## 320490 px`, `sight_top_over_centre` 0.0. That is the RIGHT answer — a capture
## taken before its state arrived fails the geometric rule loudly — but it means
## this statistic is a check on the whole capture and not only on the weapon.
static func _probe_silhouette(img: Image, bare: Image) -> Dictionary:
	var box := FRAME_STATS.changed_box(img, bare)
	var found: bool = int(box["count"]) > 0
	var half_h := float(img.get_height()) * 0.5
	var half_w := float(img.get_width()) * 0.5
	var cx := float(int(box["x0"]) + int(box["x1"])) * 0.5
	return {
		"gun_px": float(box["count"]),
		"sight_top_over_centre": FRAME_STATS.ratio(float(box["y0"]), half_h) if found else -1.0,
		"gun_cx_over_centre": FRAME_STATS.ratio(cx, half_w) if found else -1.0,
	}


## THE RIM, which is the defect this whole package was commissioned by.
##
## The rect is the rim target's own sprite quad, unprojected through the real
## camera — zombies are drawn with the main projection, unlike the viewmodel, so
## this one can be computed rather than measured. Inside it, the two masks are
## the colour split described at COLD_MARGIN: the rim is the only cold thing in a
## sodium-lit room, and the body is what the rim is supposed to be outlining.
##
## `rim_frac` IS THE PRIMARY NUMBER AND `rim_over_body` IS NOT. That is a
## measurement, not a preference, and it is the reason this comment is long.
##
## Swept by sabotaging RIM_ENERGY in zombie.gd and re-capturing this scenario,
## which is how the shipped value was chosen in the first place (zombie.gd:1396):
##
## RE-SWEPT 2026-08-03 with the viewmodel excluded (see the keep-out below). The
## numbers moved by a factor of three and the OLD ONES ARE KEPT UNDERNEATH,
## because the difference between them is the finding.
##
##   RIM_ENERGY  rim_frac   rim_mean   rim_over_body   rim_frac/body_frac
##   0.00        0.000000   0.0000     0.0000          0.000000
##   0.16        0.000225   0.0109     0.0614          0.000434
##   0.30        0.000854   0.0554     0.2955          0.001649   <- shipped
##   0.62        0.002776   0.3070     1.5519          0.005742   <- the defect
##
## **WITH THE RIM SWITCHED OFF, `rim_frac` IS NOW EXACTLY ZERO**, and every one of
## the four columns is strictly monotone. That is the whole point of the keep-out
## and it is worth more than the drift that led to it.
##
## What it replaced, and why that mattered:
##
##   RIM_ENERGY  rim_frac   rim_mean   rim_over_body   frame mean
##   0.00        0.00260    0.0718     0.480           0.019876
##   0.16        0.00302    0.0630     0.407           0.020561
##   0.30        0.00409    0.0654     0.395           0.021754
##   0.62        0.00633    0.2138     1.247           0.025854
##
## The old note read those and concluded that `rim_over_body` and `rim_mean` were
## NON-MONOTONE at the bottom — the ratio being 0.480 with the rim off, HIGHER than
## the shipped 0.395 — and blamed "a hundred stray pixels of something else whose
## mean has nothing to do with the effect". **That something else was the gun.** The
## rim rect is x[495..783]; the hip viewmodel starts at x = 774; the 18 px of grey
## slide inside the rect is 3.7% of its area and was supplying 59% of every pixel
## the probe called rim, because `_is_cold` cannot tell gun metal from a cold rim.
##
## So the non-monotonicity was never a property of the effect. It was an object in
## front of it, and the old floor of 0.00260-with-the-rim-off was that object's
## silhouette. The diagnosis in the old note was right about the symptom and wrong
## about the cause, and it cost the gate its ability to fail on a build with no rim.
##
## `rim_frac` — how much of the sprite's own rect reads cold — is monotone across
## the whole sweep and moves by 36% when the rim goes out and 55% when it doubles.
## The ratio `rim_frac / body_frac` is monotone too and is immune to a lighting
## retune, because both terms are fractions of the same rect; that is the relation
## the golden file bounds at both ends. `rim_over_body` is bounded ABOVE only, and
## the bound is the shipped defect.
static func _probe_rim(main: Node3D, img: Image) -> Dictionary:
	if _rim_target == null or not is_instance_valid(_rim_target):
		return {}
	var cam: Camera3D = main.player.camera()
	var r := _sprite_rect(cam, _rim_target, 4)
	# THE GUN IS NOT THE ZOMBIE. Both masks skip the viewmodel's own keep-out, or a
	# weapon that merely got BIGGER reads here as a rim that got DIMMER — which is
	# what happened when the iron sights landed and is the one drift in that package
	# that looked like a regression and was not. The sweep at the top of this comment
	# is what `rim_frac` means; a number contaminated by an object in front of the
	# zombie does not sit anywhere on it.
	var cold := FRAME_STATS.masked(img, r, _is_cold, VM_RECT_HIP_KEEPOUT)
	var warm := FRAME_STATS.masked(img, r, _is_warm, VM_RECT_HIP_KEEPOUT)
	var cm: float = cold["mean"]
	var wm: float = warm["mean"]
	var cf: float = cold["frac"]
	var wf: float = warm["frac"]
	return {
		"rim_mean": cm,
		"body_mean": wm,
		"rim_frac": cf,
		"body_frac": wf,
		"rim_over_body": FRAME_STATS.ratio(cm, wm),
	}


static func _probe_arc(main: Node3D, img: Image) -> Dictionary:
	var t := _trap_row(main, "corridor")
	if t.is_empty():
		return {}
	var cam: Camera3D = main.player.camera()
	var c: Vector3 = t["centre"]
	# A box around the gate's centre wide enough to hold the posts (POST_H 1.9)
	# and the sheet between them.
	var pts := PackedVector3Array([
		c + Vector3(-1.2, -1.2, -1.2), c + Vector3(1.2, 1.2, 1.2),
		c + Vector3(-1.2, 1.2, 1.2), c + Vector3(1.2, -1.2, -1.2),
		c + Vector3(-1.2, -1.2, 1.2), c + Vector3(1.2, 1.2, -1.2),
		c + Vector3(-1.2, 1.2, -1.2), c + Vector3(1.2, -1.2, 1.2),
	])
	var r := _rect_of(cam, pts, 4)
	var cold := FRAME_STATS.masked(img, r, _is_cold)
	var all := FRAME_STATS.rect_mean(img, r)
	var cm: float = cold["mean"]
	var cf: float = cold["frac"]
	return {
		"arc_mean": cm,
		"arc_frac": cf,
		"arc_over_gate": FRAME_STATS.ratio(cm, all),
	}


static func _probe_bolt(main: Node3D, img: Image) -> Dictionary:
	if _bolt == null or not is_instance_valid(_bolt):
		return {}
	var cam: Camera3D = main.player.camera()
	var c := _bolt.global_position
	var pts := PackedVector3Array([
		c + Vector3(-0.9, -0.9, -0.9), c + Vector3(0.9, 0.9, 0.9),
		c + Vector3(-0.9, 0.9, 0.9), c + Vector3(0.9, -0.9, -0.9),
		c + Vector3(-0.9, -0.9, 0.9), c + Vector3(0.9, 0.9, -0.9),
		c + Vector3(-0.9, 0.9, -0.9), c + Vector3(0.9, -0.9, 0.9),
	])
	var r := _rect_of(cam, pts, 2)
	var green := FRAME_STATS.masked(img, r, _is_green)
	var whole := FRAME_STATS.of(img)
	# The frame mean, not the median, for the reason _probe_viewmodel gives.
	var ref: float = whole["mean"]
	var gm: float = green["mean"]
	var gf: float = green["frac"]
	return {
		"bolt_mean": gm,
		"bolt_frac": gf,
		"bolt_over_frame": FRAME_STATS.ratio(gm, ref),
	}


## THE MUZZLE FLASH, AND IT IS MEASURED AS A SHAPE RATHER THAN AS A BRIGHTNESS.
##
## "There are bright pixels near the barrel" is exactly what the old gate would
## have said about the yellow square, so none of the three numbers this feeds the
## relations is a brightness on its own. They are a falloff, a hue difference
## between two rings, and a corner test — and all three read 1.0, or near it, on a
## flat fill of any colour at any brightness.
##
## The geometry is the LIVE quad's: `atmos.flash_quad()`'s own mesh corners put
## through its own global transform and the real camera, the same way `_probe_rim`
## takes a zombie's rect off its sprite node. Nothing here reconstructs the size
## from atmosphere.gd's constants, so a flash that stopped being resized — or that
## went back to a fixed world size and ballooned at the sights — moves `r_frac`
## instead of moving the rings with it and measuring the same picture.
##
## `flash_r_frac` is that half-width over the frame HEIGHT, which is the unit the
## ancestor sizes the effect in (html:3148, a fraction of cssH). It is the number
## the complaint was actually about: the shipped 0.34 m quad measured 0.46 at the
## sights, a square nearly as tall as the screen.
static func _probe_flash(main: Node3D, img: Image) -> Dictionary:
	var atmos: Node3D = main.atmos
	var q: MeshInstance3D = atmos.flash_quad()
	# Both halves. `flash_visible()` is the clock and `q.visible` is what the
	# renderer was actually handed; a flash that is one and not the other is a
	# capture measuring a stale transform, and returning {} makes main.gd exit 1
	# rather than blessing it.
	if q == null or not is_instance_valid(q) or not q.visible:
		return {}
	if not bool(atmos.flash_visible()):
		return {}
	var mesh: QuadMesh = q.mesh
	var hx: float = mesh.size.x * 0.5
	var hy: float = mesh.size.y * 0.5
	var t := q.global_transform
	var cam: Camera3D = main.player.camera()
	var local := [
		Vector3(-hx, -hy, 0.0), Vector3(hx, -hy, 0.0),
		Vector3(hx, hy, 0.0), Vector3(-hx, hy, 0.0),
	]
	var corners := PackedVector2Array()
	for c: Vector3 in local:
		var w: Vector3 = t * c
		# A quad behind the camera is not a flash anybody saw. Refused rather than
		# unprojected, which would mirror it to the far side of the screen.
		if cam.is_position_behind(w):
			return {}
		corners.append(cam.unproject_position(w))
	var centre := (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
	# Half the mean edge, i.e. the projected half-width. Averaged over all four
	# edges rather than taken from one, so a quad seen slightly off-axis reports
	# its size rather than its nearest side's.
	var per := 0.0
	for i in 4:
		per += corners[i].distance_to(corners[(i + 1) % 4])
	var r := per * 0.125
	if r <= 1.0:
		return {}

	var core := _flash_ring(img, centre, 0.0, FLASH_CORE_R * r)
	var ring := _flash_ring(img, centre, FLASH_RING_LO * r, FLASH_RING_HI * r)
	# The four corner discs summed into one sample: they are the same distance out
	# along four different diagonals and a flat fill lights all four, so there is
	# nothing to learn from telling them apart.
	var cn := {"sum": 0.0, "count": 0, "r": 0.0, "g": 0.0, "b": 0.0}
	for c: Vector2 in corners:
		_flash_disc_into(cn, img, centre + (c - centre) * FLASH_CORNER_AT,
			FLASH_CORNER_R * r)

	var core_m: float = _flash_mean(core)
	var ring_m: float = _flash_mean(ring)
	var corner_m: float = _flash_mean(cn)
	var core_br := FRAME_STATS.ratio(float(core["b"]), float(core["r"]))
	var ring_br := FRAME_STATS.ratio(float(ring["b"]), float(ring["r"]))
	return {
		"flash_r_frac": r / float(img.get_height()),
		# WHERE THE FLASH IS, and it is the number checks/projectiles.gd's
		# `_ads_flash` could not supply. That assertion claims "the muzzle flash
		# lands on the barrel at the hip and at the sights" and is an algebraic
		# identity: flash_anchor() scales by tan(F/2)/tan(V/2) and the check
		# unprojects through V, so the ratio cancels — and BOTH of its sides read
		# `_muzzle.global_position`, so a muzzle marker moved to the grip moves
		# both and it still passes. This is the rendered-frame half: the flash
		# quad's own projected centre against the frame's, so at the sights — where
		# the barrel is on the aim point — anything but 1.0 is the flash having
		# come off the gun.
		"flash_cx_over_centre": FRAME_STATS.ratio(centre.x, float(img.get_width()) * 0.5),
		"flash_cy_over_centre": FRAME_STATS.ratio(centre.y, float(img.get_height()) * 0.5),
		"flash_core_mean": core_m,
		"flash_ring_mean": ring_m,
		"flash_corner_mean": corner_m,
		# Bounds every mask at the other end. A ring that has stopped containing
		# any pixel means the mean of nothing, which is 0.0 and reads as "dark".
		"flash_core_px": float(core["count"]),
		"flash_ring_px": float(ring["count"]),
		"flash_corner_px": float(cn["count"]),
		"flash_core_over_ring": FRAME_STATS.ratio(core_m, ring_m),
		"flash_corner_over_core": FRAME_STATS.ratio(corner_m, core_m),
		"flash_core_br": core_br,
		"flash_ring_br": ring_br,
		# Blue-over-red of the hot centre against blue-over-red of the halo. The
		# ancestor's core is 255,248,225 and its default tint is 255,214,130, so
		# this is 0.88 over 0.51 before the pipeline touches either. A flat fill
		# has ONE colour and reads 1.000 whatever that colour is.
		"flash_white_core": FRAME_STATS.ratio(core_br, ring_br),
	}


## Summed linear channels and linear luminance over an annulus, in pixels.
##
## Its own loop rather than FRAME_STATS.masked(), which takes a COLOUR predicate:
## every mask here is a statement about WHERE a pixel is, and a colour mask is
## exactly the tool the silhouette probe rejected for measuring a shape.
static func _flash_ring(img: Image, c: Vector2, lo: float, hi: float) -> Dictionary:
	var out := {"sum": 0.0, "count": 0, "r": 0.0, "g": 0.0, "b": 0.0}
	var w := img.get_width()
	var h := img.get_height()
	var x0 := maxi(int(floor(c.x - hi)), 0)
	var x1 := mini(int(ceil(c.x + hi)), w - 1)
	var y0 := maxi(int(floor(c.y - hi)), 0)
	var y1 := mini(int(ceil(c.y + hi)), h - 1)
	var lo2 := lo * lo
	var hi2 := hi * hi
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - c.x
			var dy := float(y) + 0.5 - c.y
			var d2 := dx * dx + dy * dy
			if d2 < lo2 or d2 > hi2:
				continue
			_flash_add(out, img.get_pixel(x, y))
	return out


static func _flash_disc_into(out: Dictionary, img: Image, c: Vector2, rad: float) -> void:
	var d := _flash_ring(img, c, 0.0, rad)
	out["sum"] = float(out["sum"]) + float(d["sum"])
	out["count"] = int(out["count"]) + int(d["count"])
	for k: String in ["r", "g", "b"]:
		out[k] = float(out[k]) + float(d[k])


static func _flash_add(out: Dictionary, p: Color) -> void:
	out["sum"] = float(out["sum"]) + FRAME_STATS.luma(p)
	out["count"] = int(out["count"]) + 1
	out["r"] = float(out["r"]) + FRAME_STATS.srgb_to_linear(p.r)
	out["g"] = float(out["g"]) + FRAME_STATS.srgb_to_linear(p.g)
	out["b"] = float(out["b"]) + FRAME_STATS.srgb_to_linear(p.b)


static func _flash_mean(d: Dictionary) -> float:
	return float(d["sum"]) / float(maxi(int(d["count"]), 1))


# --- masks and geometry -------------------------------------------------------

static func _above_floor(c: Color) -> bool:
	return FRAME_STATS.luma(c) > FRAME_STATS.srgb_to_linear(MASK_FLOOR)


static func _is_cold(c: Color) -> bool:
	return c.b - c.r > COLD_MARGIN and _above_floor(c)


static func _is_warm(c: Color) -> bool:
	return c.r - c.b > WARM_MARGIN and _above_floor(c)


static func _is_green(c: Color) -> bool:
	return c.g - c.r > GREEN_MARGIN and c.g - c.b > GREEN_MARGIN and _above_floor(c)


## The screen rect of a zombie's own sprite quad — the drawn geometry, taken from
## the node rather than reconstructed from `_height` and `pixel_size`, so a
## change to either moves the rect with it.
static func _sprite_rect(cam: Camera3D, z: Zombie, pad: int) -> Rect2i:
	var s: Node3D = z._sprite
	var ab: AABB = z._sprite.get_aabb()
	var pts := PackedVector3Array()
	for i in 8:
		pts.append(s.global_transform * ab.get_endpoint(i))
	return _rect_of(cam, pts, pad)


static func _rect_of(cam: Camera3D, pts: PackedVector3Array, pad: int) -> Rect2i:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector3 in pts:
		# A point behind the camera unprojects to a mirrored position on the far
		# side of the screen, which would silently inflate the rect to the whole
		# frame. Dropped rather than clamped.
		if cam.is_position_behind(p):
			continue
		var v := cam.unproject_position(p)
		lo.x = minf(lo.x, v.x)
		lo.y = minf(lo.y, v.y)
		hi.x = maxf(hi.x, v.x)
		hi.y = maxf(hi.y, v.y)
	if lo.x > hi.x:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(int(lo.x) - pad, int(lo.y) - pad,
		int(hi.x - lo.x) + pad * 2, int(hi.y - lo.y) + pad * 2)


static func _trap_row(main: Node3D, key: String) -> Dictionary:
	for t: Dictionary in main.traps._live:
		if String(t.get("key", "")) == key:
			return t
	return {}
