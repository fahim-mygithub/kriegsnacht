extends RefCounted

## The reload timeline: what the weapon *does*, in phase, while
## `scripts/entities/weapon.gd` counts the seconds.
##
## That split is the whole design. A segment's LENGTH is balance — a Stakeout's
## 3.4 s lives in `weapons.gd`'s table, the sim reads it, and nothing here may move
## it — and a segment's SHAPE is animation. Before this file the shape was one line
## of trigonometry in the rig with no opinion about which weapon it was moving or
## which part of the reload it was in.
##
## **This is the `TRAVEL` / `MODE` / `BOLT_HOLD` idiom from `scripts/data/gunart.gd`,
## deliberately**: a map from weapon key to an archetype, per-archetype tables, a
## documented fallback that is a safety net and NOT a supported state, and static
## accessors that are the only way anything reads it. Nothing here touches the
## scene tree, an `Rng` stream or global state; `scripts/entities/viewmodel.gd` is
## the rig.
##
## **THE DIP COLUMN IS AUTHORED. THE HAND COLUMN IS NOT, AND IT IS HERE ANYWAY.**
## Every knot is `[phase, dip, hand]` and every `hand` is 0.0. That is deliberate
## and it is the cheapest insurance in this package: a later stage that animates the
## off hand then adds DATA to rows that already exist, rather than a SCHEMA to a
## table that by then has four readers. `sample()` already returns both columns.
##
## ---
##
## **THE DEPARTURE FROM THE ANCESTOR, RECORDED, because a departure that is not
## recorded is wrong even when it is right.** kriegsnacht.html:3121-3128 has exactly
## one reload pose, for every weapon and for every stage of every reload:
## `rel = 1-(reloading/reloadMax); s = sin(rel*PI)`, one symmetric arc down and
## back, `y += s*cssH*0.30`. The port carried it verbatim and then applied it *per
## segment*, which the ancestor never had to consider because the ancestor has no
## segmented reload at all (`shells` is declared at html:1460/:1465 and read by
## nothing). Three things here are not the ancestor and each has its own reason:
##
##   1. The arc is not symmetric. A magazine reload spends its middle with the
##      weapon already down and the hands working; the fall and the rise are the
##      short parts. `sin(rel*PI)` puts the deepest point at exactly the halfway
##      mark on every weapon, which is the one instant the hands are *between*
##      jobs.
##   2. The shape is per archetype. A break-action shotgun, a box magazine and a
##      tube fed one shell at a time are three different motions, and the ancestor
##      drew none of them — its viewmodel is a flat canvas translated as a whole.
##   3. **A shell reload no longer returns to rest between shells.** This is the
##      one that fixes a measured defect rather than restyling one; see
##      `viewmodel.gd::_drive` for the measurement. A Stakeout reload runs seven
##      segments and the shipped rig ran `sin(done*PI)` in each of them, so the
##      weapon came all the way back up to the eye line six times in the middle of
##      a reload it had not finished. BO1 holds the weapon down across the whole
##      feed and racks it once at the end, and so does this: `OPEN` ends at `HELD`,
##      `EACH` starts and ends at `HELD`, and only `CLOSE` comes back to zero.
##
## The knot VALUES are ours. They are reasoned from how each weapon is actually
## loaded and from the reference's habit of holding a segmented reload down, and
## there is no file to be faithful to — so they are decisions, and the reason for
## each is on its own row.

## The ratios that define a shell segment, read through the state machine that
## authors them and NEVER copied. `SHELL_START` / `SHELL_EACH` / `SHELL_END` are
## the numbers `begin_reload` and `_load_shell` build their segment lengths out of;
## a pasted copy here would classify correctly right up until somebody retuned
## them, and then classify silently wrongly forever.
const WEAPON := preload("res://scripts/entities/weapon.gd")


# --- the four segment kinds ---------------------------------------------------

## `segment()` answers one of these, and they are the second axis of `TRACKS`.
##
##   WHOLE  the single timed segment of `State.RELOADING` — one magazine, one
##          clock, no interruptions. Every weapon whose `def.shells` is false.
##   OPEN   `State.RELOAD_SHELL`'s first segment: the weapon comes over to the
##          loading port AND the first shell goes in. `weapon.gd:214-220` explains
##          why those are one segment and not two.
##   EACH   one more shell into the tube. Re-entered per shell, which is what makes
##          `state_t` sawtooth (`weapon.gd:383-385`).
##   CLOSE  the last segment: nothing left to load, the action is closed and the
##          weapon comes back to the eye. It credits nothing, so an interrupt
##          during it costs the player nothing (`weapon.gd:377-381`).
##   NONE   not reloading. The rig eases back to rest on its own; see
##          `viewmodel.gd::_tick_states`.
const NONE := -1
const WHOLE := 0
const OPEN := 1
const EACH := 2
const CLOSE := 3


# --- the archetypes -----------------------------------------------------------

## Five motions across twelve weapons, and the count is set by how the weapon is
## actually fed rather than by how many weapons there are.
##
##   PISTOL  a magazine out of the grip, one-handed, at the belt line. One weapon,
##           and it earns its own row because it is the only reload on the roster
##           the off hand can do without the weapon leaving the centre of the
##           screen — and the shortest, at 1.5 s.
##   BOX     a detachable box magazine off the underside of the receiver: rock or
##           slap it out, present a fresh one, seat it, and bring the charging hand
##           back over the top. Six weapons.
##   BREAK   the action hinges and both hulls come out together. One weapon, and
##           `checks/systems.gd::_segmented_reload` already argues in full why the
##           Olympia is not a tube.
##   TUBE    fed one round at a time through a port, with the weapon rolled over.
##           Two weapons, and only one of them is *segmented* — see `TRACKS`.
##   EXOTIC  a wonder weapon. Both are brought well down and across the body and
##           worked slowly with both hands; in the reference this is a showpiece
##           and not a chore, and their reload times (2.6 s and 3.6 s against a
##           2.1-2.6 s roster median) are the table already saying so.
const PISTOL := 0
const BOX := 1
const BREAK := 2
const TUBE := 3
const EXOTIC := 4

## Weapon key to archetype. Every key in `Weapons.TABLE`, and `checks/systems.gd`
## asserts that — see `FALLBACK` for why the assertion rather than the fallback is
## what makes this table complete.
##
## The knife is absent on purpose: it is a viewmodel `GUNART` row and not a carried
## weapon, it has no entry in `Weapons.TABLE`, and it cannot reach a reload state.
const SCRIPT := {
	"m1911": PISTOL,
	"olympia": BREAK,
	"m14": BOX, "mp40": BOX, "pm63": BOX, "ak74u": BOX, "m16": BOX, "rpk": BOX,
	"stakeout": TUBE,
	# Not `BOX`, and this is the one row worth arguing. The China Lake is a pump
	# launcher fed one grenade at a time through a port; it is a tube gun that this
	# project chose not to *segment* (`shells` is false on it in `weapons.gd:53`),
	# so its four rounds go in under a single `WHOLE` clock. `TUBE`'s `WHOLE` track
	# is exactly that motion — see there.
	"chinalake": TUBE,
	"raygun": EXOTIC, "thundergun": EXOTIC,
}

## What a weapon with no `SCRIPT` row animates as, and it is the same bargain
## `gunart.gd`'s `TRAVEL_DEFAULT` makes: a weapon added to `Weapons.TABLE` and
## forgotten here still reloads with a pose instead of standing dead at the eye
## line through four seconds of nothing. It is a SAFETY NET AND NOT A SUPPORTED
## STATE — `checks/systems.gd` fails if any weapon on the roster reaches it.
##
## `TUBE` and not `BOX`, which would be the likelier guess for a new weapon,
## because this constant has a second job: `TRACKS` authors the three shell kinds
## on `TUBE` alone, so `TUBE` is the only archetype that can answer all four
## segments, and therefore the only one that can be a total fallback.
const FALLBACK := TUBE


# --- the tracks ---------------------------------------------------------------

## Where a segmented reload parks the weapon between shells, in shape units.
##
## Named rather than repeated because three tracks have to agree on it or the pose
## jumps at a segment boundary — `OPEN` ends here, `EACH` starts and ends here, and
## `CLOSE` leaves from here. 0.72 against `EACH`'s 0.90 peak means the per-shell
## beat is 0.18 of the shape, which through `viewmodel.gd`'s `SHELL_SCALE` is 6.3%
## of the magazine dip: a thumb pushing a shell in, not the weapon nodding.
const HELD := 0.72

## `archetype -> segment kind -> [[phase, dip, hand], ...]`.
##
## Phase runs 0..1 across the segment's own clock, so **nothing in this table is in
## seconds** and a Speed Cola reload plays the same shape at twice the rate rather
## than half the shape. `dip` is 0 at the eye line and 1 at the deepest the rig will
## take a weapon; the metres are `viewmodel.gd`'s `DIP`, and the amplitude a shell
## reload is scaled by is its `SHELL_SCALE`, read at one site there. **These tables
## are pure shape and neither constant is folded in** — fold one in and the table
## stops being comparable row to row, which is the only thing it is for.
##
## `hand` is authored zero everywhere in this stage; see the header.
##
## **ONLY `TUBE` AUTHORS THE THREE SHELL KINDS.** Exactly one weapon on the roster
## has `def.shells` true, so four more per-family variants of a motion nothing
## performs would be data fitted to the schema rather than to a gun — the shape
## this project has been bitten by before. `FALLBACK` is what answers for the rest,
## and it answers with the tube's motion, which is what the flag *means*.
const TRACKS := {
	PISTOL: {
		WHOLE: [
			[0.00, 0.00, 0.0],  # at the eye, and 1.5 s is the shortest reload on the roster
			[0.20, 0.90, 0.0],  # the weapon comes down and inboard as the magazine is dumped
			[0.52, 0.76, 0.0],  # ...and rides steady there while the fresh one is brought up
			[0.70, 1.00, 0.0],  # THE SLAP. The deepest point, and it is late rather than central
			[1.00, 0.00, 0.0],  # slide released, back to the eye
		],
	},
	BOX: {
		WHOLE: [
			[0.00, 0.00, 0.0],
			[0.16, 0.88, 0.0],  # rocked down and inboard; the old magazine clears the well
			[0.42, 0.70, 0.0],  # the reach. The weapon is steady precisely because the hand is away
			[0.62, 1.00, 0.0],  # the fresh magazine seated — deepest, and again late
			[0.80, 0.62, 0.0],  # the charging hand comes back over the top and the weapon lifts with it
			[1.00, 0.00, 0.0],
		],
	},
	BREAK: {
		WHOLE: [
			[0.00, 0.00, 0.0],
			[0.20, 1.00, 0.0],  # broken open in one motion, muzzles down, both hulls out together
			[0.68, 0.94, 0.0],  # held open — two shells go in together, so there is no second beat
			[0.86, 0.60, 0.0],  # snapped shut on the wrist, which lifts the weapon before the hands do
			[1.00, 0.00, 0.0],
		],
	},
	TUBE: {
		# The China Lake's whole reload under one clock: four rounds thumbed into the
		# tube with the weapon rolled over, so the shape is a long low dwell with a
		# beat per round rather than an arc. Four beats because the magazine is four
		# (`weapons.gd:53`); it is the only unsegmented weapon this track serves.
		WHOLE: [
			[0.00, 0.00, 0.0],
			[0.13, 0.84, 0.0],  # rolled over to the port
			[0.28, 0.96, 0.0],  # round one
			[0.42, 0.84, 0.0],
			[0.54, 0.96, 0.0],  # round two
			[0.64, 0.84, 0.0],
			[0.74, 0.96, 0.0],  # round three
			[0.82, 0.84, 0.0],
			[0.88, 0.96, 0.0],  # round four, and the beats crowd as the hand learns the reach
			[1.00, 0.00, 0.0],
		],
		OPEN: [
			[0.00, 0.00, 0.0],  # at the eye
			[0.34, 1.00, 0.0],  # rolled over and down to the port: the deepest the reload goes
			[0.68, 0.78, 0.0],  # the first shell in — `begin_reload` credits it in this segment
			[1.00, HELD, 0.0],  # AND THE WEAPON STAYS DOWN. It has five more to load
		],
		EACH: [
			[0.00, HELD, 0.0],  # already at the port; nothing has to travel
			[0.44, 0.90, 0.0],  # one shell thumbed in — a beat, not an arc
			[1.00, HELD, 0.0],  # back to the working pose, NOT to the eye
		],
		CLOSE: [
			[0.00, HELD, 0.0],
			[0.26, 0.82, 0.0],  # the fore-end is worked; the weapon sets down as it is racked
			[0.90, 0.00, 0.0],  # ...and back to the eye
			# THE FLAT TAIL, and it is load-bearing twice over. It makes the return to
			# rest independent of frame rate and of `reload_scale` — a track that
			# reaches zero only at phase 1.0 is only ever *sampled* near zero, because
			# `tick()` ends the segment on the first tick past it. And it is honest:
			# `CLOSE` credits nothing (`weapon.gd:377-381`), so the last tenth of it is
			# already over as far as the player's ammunition is concerned.
			[1.00, 0.00, 0.0],
		],
	},
	EXOTIC: {
		WHOLE: [
			[0.00, 0.00, 0.0],
			[0.28, 1.00, 0.0],  # all the way down and across the body — a showpiece, and slow
			[0.66, 0.88, 0.0],  # the cell comes out and the fresh one goes in; both hands, no rush
			[1.00, 0.00, 0.0],  # one long rise, and no second beat: nothing gets charged
		],
	},
}


# --- classification -----------------------------------------------------------

## The two boundaries between the three shell ratios, DERIVED and not pasted.
##
## `begin_reload` and `_load_shell` build every `RELOAD_SHELL` segment as
## `shell_unit * r` for exactly three values of `r`: `SHELL_START + SHELL_EACH` for
## the opening segment, `SHELL_EACH` for a shell and `SHELL_END` for the close.
## MEASURED out of the state machine rather than read off the source: **1.567 /
## 0.567 / 0.767**, and the closest pair of them is 0.200 apart (`|CLOSE - EACH|`;
## the other two gaps are 0.800 and 1.000). A midpoint between neighbours therefore
## has a hundred-to-one margin against float error, and `reload_scale` cannot
## disturb it at all — `state_len` and `shell_unit` are the same scale multiplied
## by the same number, so it cancels top and bottom and the ratio is exact at
## Speed Cola, at Pack-a-Punch and at both together.
## Midway between a shell's 0.567 and the close's 0.767, i.e. 0.667.
const CLOSE_MIN := (WEAPON.SHELL_EACH + WEAPON.SHELL_END) * 0.5
## Midway between the close's 0.767 and the opening segment's 1.567, i.e. 1.167.
const OPEN_MIN := (WEAPON.SHELL_END + (WEAPON.SHELL_START + WEAPON.SHELL_EACH)) * 0.5


## Which segment this gun is in, from the gun the game is actually holding.
##
## **IDENTIFIED FROM THE CLOCK, NOT FROM THE AMMUNITION**, and that is the whole of
## the correction. The obvious classifier is "the close is the one where there is
## nothing left to load" — `mag >= def.mag or res <= 0` — and it is right on every
## reload that runs to completion, which is why it survives casual testing. It is
## wrong the moment ammunition arrives: `weapon.gd:305-309` settles a reload only
## when the MAGAZINE has been filled from outside, so a tube reload that entered
## `CLOSE` because the RESERVE ran dry keeps running when a Max Ammo lands, and an
## ammunition-driven classifier flips it back to `EACH` mid-segment — the weapon
## dives back down to the port for a shell that is never loaded. The segment length
## does not lie about which segment it is, so it is what this reads.
static func segment(gun: Dictionary) -> int:
	var state: int = gun.state
	if state == WEAPON.State.RELOADING:
		return WHOLE
	if state != WEAPON.State.RELOAD_SHELL:
		return NONE
	var unit: float = gun.get("shell_unit", 0.0)
	if unit <= 0.0:
		# Unreachable through `begin_reload`, which always latches the unit
		# (`weapon.gd:218-219`). Answering NONE lets the pose ease to rest, which is
		# visible and diagnosable; picking a segment out of a division by zero is not.
		return NONE
	var ratio := float(gun.state_len) / unit
	# DESCENDING, and the order is load-bearing rather than stylistic: the bands are
	# nested upward (EACH 0.567 < CLOSE 0.767 < OPEN 1.567), so a test against the
	# LOWER bound first swallows everything above it and leaves the second arm dead.
	# That is not hypothetical — it is the bug this line shipped with, and it read as
	# `OPEN/EACH x5/OPEN` on a six-shell Stakeout: the close's 0.767 cleared
	# CLOSE_MIN's 0.667 and returned OPEN, while `ratio >= OPEN_MIN` could never be
	# reached by any value that had not already returned.
	if ratio >= OPEN_MIN:
		return OPEN
	if ratio >= CLOSE_MIN:
		return CLOSE
	return EACH


## The archetype this weapon reloads as. See `FALLBACK`.
static func script_for(key: String) -> int:
	var s: int = int(SCRIPT.get(key, FALLBACK))
	return s


## One track, resolved through `FALLBACK` in both axes. The single reader of
## `TRACKS`, so there is one place a missing row is answered and one place an
## assertion has to walk.
static func track(script: int, seg: int) -> Array:
	var by_seg: Dictionary = TRACKS.get(script, TRACKS[FALLBACK])
	var knots: Array = by_seg.get(seg, TRACKS[FALLBACK].get(seg, TRACKS[FALLBACK][WHOLE]))
	return knots


## The pose at `phase` through `seg` of `script`: `x` is dip, `y` is hand.
##
## **Linear between knots, and that is a decision rather than the lazy option.** The
## knots ARE the authored shape; put an easing curve or a spline between them and
## the table stops saying what the pose is, so a reader nudging a knot is tuning
## through a filter. It also makes the bound exact: a linear blend of values in
## [0, 1] is in [0, 1], so `checks/systems.gd` walking the knots genuinely bounds
## the pose, which a spline's overshoot would quietly break.
static func sample(script: int, seg: int, phase: float) -> Vector2:
	var knots := track(script, seg)
	var p := clampf(phase, 0.0, 1.0)
	var prev: Array = knots[0]
	for i in range(1, knots.size()):
		var next: Array = knots[i]
		if p <= float(next[0]):
			var span := float(next[0]) - float(prev[0])
			var t := 0.0 if span <= 0.0 else (p - float(prev[0])) / span
			return Vector2(lerpf(float(prev[1]), float(next[1]), t),
				lerpf(float(prev[2]), float(next[2]), t))
		prev = next
	# Past the last knot, which `p <= 1.0` reaches only when the track's last phase
	# is below 1.0 — a malformed row `checks/systems.gd` refuses. Held rather than
	# extrapolated, because extrapolating a shape is how a bound stops being one.
	return Vector2(float(prev[1]), float(prev[2]))
