extends RefCounted

## The economy, asserted where it is actually spent rather than where it is
## declared.
##
## `curves.gd` already pins the points *table* — 60, 100, 130, 10, 400, 200, the
## 2,000-point drop threshold and its 1.14 compounding — and the perk constants.
## Nothing there touches a call site, and every defect this file was written for is
## a call site: a payout branch that ignores a modifier, a cap that eats the
## entitlement it was supposed to defer, a machine priced from the wrong table. Two
## numbers can both be canon and still be combined wrongly, and a constant test
## cannot see it.
##
## So the assertions here are driven through the real objects — the round director's
## death handler, the power-up manager's Nuke, the interaction table's own
## `_state_of` — and read the wallet afterwards. That costs a scene, which is why
## this runs from `--verify` rather than as a pure unit pass.
##
## **Run this before `curves.gd`.** `curves.gd::_drops` calls `Game.reset_run()` and
## drives a real `force_round(7)`, and it puts back only the four drop fields — the
## wallet, the perks, the power flag and both power-up timers are left wherever that
## section finished with them. Every section below saves and restores what it
## touches, so the order is not load-bearing for correctness; it is load-bearing for
## being able to read a failure, because a section running on top of a mangled run
## reports its own symptom.

## preload rather than the global class name: a freshly added script is not in
## the class registry until the editor rescans, and a headless run has no editor.
const POWERUPS := preload("res://scripts/systems/powerup_manager.gd")


static func run(v: Verify, main: Node3D) -> void:
	_payout(v)
	_payout_wiring(v, main)
	_nuke(v, main)
	_nuke_drops(v)
	_double_points(v)
	_drop_latch(v)
	_max_ammo(v, main)
	_machines(v, main)
	_pool(v)


# --- what a body is worth ----------------------------------------------------

## R4 §3, Tier 1 (`_zombiemode_score.gsc`): BO1 pays `50 + kill_bonus`, and
## Insta-Kill zeroes the *bonus* rather than doubling the total the way WaW did. An
## Insta-Kill bullet death is `MOD_UNKNOWN` and carries no hit-location bonus, so a
## gun kill drops to the bare 50; a knife death is `MOD_MELEE`, keeps its +80 and
## still totals 130. The ancestor pays `Math.max(pts,100)` (html:2233) and then adds
## its 70 on top (html:2658), i.e. 170 for a knife kill under Insta-Kill — the
## reference wins.
static func _payout(v: Verify) -> void:
	var insta_was := Game.insta_kill

	Game.insta_kill = 0.0
	var body := Game.kill_points(false, false)
	var head := Game.kill_points(true, false)
	var knife := Game.kill_points(false, true)
	v.check("an ordinary death pays the table: 60 body, 100 head, 130 knife",
		body == 60 and head == 100 and knife == 130,
		"body=%d head=%d knife=%d" % [body, head, knife])

	Game.insta_kill = 30.0
	var i_body := Game.kill_points(false, false)
	var i_head := Game.kill_points(true, false)
	var i_knife := Game.kill_points(false, true)
	v.check("Insta-Kill flattens a shot to 50 whether or not it was a headshot",
		i_body == Game.PTS_INSTAKILL and i_head == Game.PTS_INSTAKILL,
		"body=%d head=%d" % [i_body, i_head])
	# The one that is wrong at the call site. A knife under Insta-Kill paying the
	# flat 50 makes the most canonical points play in the game — Insta-Kill plus the
	# Bowie — worth 38% of what a knife is worth with no power-up up at all.
	v.check("Insta-Kill does not touch the melee bonus", i_knife == knife,
		"knife under insta-kill is %d, normally %d" % [i_knife, knife])
	v.check("Insta-Kill is a survival tool, not an economy: it can only pay less",
		i_body < body and i_head < head and i_knife <= knife)

	Game.insta_kill = insta_was


## The rule above only matters if the one thing that pays for a death agrees with
## it. This is deliberately the *only* assertion in this file that compares the
## handler against `Game.kill_points()` rather than asserting a number: the point is
## that there is one rule and not two, and a second copy is exactly how the melee
## bonus went missing under Insta-Kill in the first place.
static func _payout_wiring(v: Verify, main: Node3D) -> void:
	var state := _save(main)
	Game.dbl_points = 0.0
	Game.nuke_clearing = false
	# Pinned at the cap so nothing here can spawn a power-up. The DROPS draw inside
	# the handler still happens on every death, which is the point — see
	# Game.try_drop.
	Game.drop_count = Game.DROP_CAP

	var wrong := ""
	for insta: float in [0.0, 30.0]:
		Game.insta_kill = insta
		# Melee and headshot are never both true: player.gd damages one notch under
		# the head threshold, exactly as html:2657 does.
		for combo: Array in [[false, false], [true, false], [false, true]]:
			var headshot: bool = combo[0]
			var by_melee: bool = combo[1]
			var want := Game.kill_points(headshot, by_melee)
			var got := _pay(main, headshot, by_melee)
			if got != want:
				wrong += "insta=%.0f head=%s melee=%s paid %d want %d; " % [
					insta, headshot, by_melee, got, want]
	v.check("the death handler pays exactly what Game.kill_points() says",
		wrong.is_empty(), wrong)

	_restore(main, state)


## One death through the real handler, returning what the wallet moved by.
static func _pay(main: Node3D, headshot: bool, by_melee: bool) -> int:
	var z := Zombie.create("zombie", 0, 1, false)
	main.add_child(z)
	var before := Game.points
	main.rounds._on_zombie_died(z, headshot, by_melee)
	var paid := Game.points - before
	z.queue_free()
	return paid


# --- the Nuke ----------------------------------------------------------------

## `addPoints(400)` and nothing else: html:2411-2419 sets `z.state='dying'` inside
## `grabPowerup`, so the ancestor's Nuke never reaches `zombieDamage` and never pays
## for a body. Canon lands in the same place from the other direction — the sweep
## kills with no attacker credited, so there is nobody to score against.
##
## The port routes the sweep through `take_damage`, which is right (it is what
## erases the horde from the director's live list and starts the death animation)
## and which is exactly why the payout has to be suppressed explicitly. Before this,
## a round-10 Nuke on a full horde paid 400 + 24x60 = 1,840 points — more than the
## round it was picked up in.
static func _nuke(v: Verify, main: Node3D) -> void:
	var state := _save(main)
	Game.dbl_points = 0.0
	Game.insta_kill = 0.0
	Game.drop_count = Game.DROP_CAP

	var horde: Array[Zombie] = []
	for i in 5:
		var z := Zombie.create("zombie", 0, 1, false)
		main.add_child(z)
		z.died.connect(main.rounds._on_zombie_died)
		main.rounds.alive().append(z)
		horde.append(z)

	var before := Game.points
	var earned_before := Game.points_earned
	main.powerups._collect("nuke")
	var paid := Game.points - before
	var standing := 0
	for z: Zombie in horde:
		if z.state != Zombie.State.DYING:
			standing += 1
		main.rounds.alive().erase(z)
		z.queue_free()

	v.check("a Nuke clears the horde and pays its flat 400, not 400 plus a body count",
		paid == Game.PTS_NUKE and standing == 0,
		"paid %d for 5 bodies, %d still standing" % [paid, standing])
	# The threshold counter is the half that decides the pace of a run: a Nuke worth
	# 1,840 was most of a drop threshold on its own, so Nukes were buying the next
	# Nuke.
	v.check("a Nuke's bodies feed the drop threshold nothing either",
		Game.points_earned - earned_before == Game.PTS_NUKE,
		"threshold gained %d" % (Game.points_earned - earned_before))
	# A flag that survives its own function turns every later kill into a freebie,
	# and nothing on screen would say so.
	v.check("the Nuke's suppression flag does not outlive the sweep",
		not Game.nuke_clearing)

	_restore(main, state)


## The other half of what a body is worth. Suppressing the points and leaving the
## drop roll would have left the Nuke buying the next Nuke by the other route: the
## flat 3% over 24 bodies is a coin flip per late-round sweep and one of the seven
## entries in the bag is `nuke`. The ancestor rolls nothing for a nuked body —
## `maybeDrop` is called from inside `zombieDamage` (html:2237) and the Nuke never
## reaches it (html:2411-2419).
##
## Driven through `Game.try_drop` with `lucky` forced true rather than by nuking a
## real horde and counting the floor. Five bodies at 3% produce no drop 86% of the
## time, so a horde-and-count version of this would pass without the rule existing —
## which is the failure mode that put a dead Nuke guard in `kill_points()` in the
## first place.
static func _nuke_drops(v: Verify) -> void:
	var count_was := Game.drop_count
	var pending_was := Game.drop_pending
	var nuking_was := Game.nuke_clearing
	var earned_was := Game.points_earned
	var next_was := Game.next_drop_at
	var idx_was := Game.drop_index

	Game.drop_count = 0
	Game.drop_pending = false
	Game.points_earned = 0
	Game.next_drop_at = 2000
	Game.drop_index = 0

	Game.nuke_clearing = true
	var rolled: bool = Game.try_drop(true)
	v.check("a body deleted by a Nuke cannot hand over a power-up either",
		not rolled and Game.drop_count == 0,
		"granted=%s count=%d" % [rolled, Game.drop_count])

	# The suppression sits after the latch, not in front of it, so the Nuke's own 400
	# is still allowed to carry the threshold past its line. Losing that would make
	# collecting a Nuke actively worse for the drop pace than not collecting it.
	Game.points_earned = Game.next_drop_at
	var during: bool = Game.try_drop(false)
	var owed: bool = Game.drop_pending
	Game.nuke_clearing = false
	var after: bool = Game.try_drop(false)
	v.check("a threshold the Nuke's own 400 crossed is owed to the next real death",
		not during and owed and after and Game.drop_count == 1,
		"during=%s owed=%s after=%s count=%d" % [during, owed, after, Game.drop_count])

	Game.drop_count = count_was
	Game.drop_pending = pending_was
	Game.nuke_clearing = nuking_was
	Game.points_earned = earned_was
	Game.next_drop_at = next_was
	Game.drop_index = idx_was


# --- Double Points -----------------------------------------------------------

## The wallet and the drop threshold have to move by the same amount or the two
## halves of the economy disagree about what was earned. Canon adds the awarded
## points to `score` and `score_total` in the same call and the awarded points are
## already doubled, so Double Points does earn drops twice as fast — deliberately,
## and R4 §2 is explicit that the threshold reads `score_total`. What must not
## happen is either half doubling twice, or the threshold taking the undoubled
## figure while the wallet takes the doubled one.
static func _double_points(v: Verify) -> void:
	var points_was := Game.points
	var earned_was := Game.points_earned
	var dbl_was := Game.dbl_points
	var nuking_was := Game.nuke_clearing

	Game.nuke_clearing = false
	Game.dbl_points = 0.0
	var p0 := Game.points
	var e0 := Game.points_earned
	Game.add_points(100)
	var plain_wallet := Game.points - p0
	var plain_earned := Game.points_earned - e0

	Game.dbl_points = 30.0
	p0 = Game.points
	e0 = Game.points_earned
	Game.add_points(100)
	var dbl_wallet := Game.points - p0
	var dbl_earned := Game.points_earned - e0

	v.check("Double Points doubles exactly once, in both halves of the economy",
		plain_wallet == 100 and plain_earned == 100
			and dbl_wallet == 200 and dbl_earned == 200,
		"plain %d/%d doubled %d/%d" % [plain_wallet, plain_earned, dbl_wallet, dbl_earned])

	# Spending is the other direction and must not touch the threshold at all, or a
	# player could farm drops through anything with a refund path.
	Game.dbl_points = 0.0
	Game.points = 1000
	e0 = Game.points_earned
	var bought: bool = Game.spend(400)
	var refused: bool = Game.spend(10000)
	v.check("spending never credits the drop threshold and never overdraws",
		bought and not refused and Game.points == 600 and Game.points_earned == e0,
		"points=%d earned+%d" % [Game.points, Game.points_earned - e0])

	Game.points = points_was
	Game.points_earned = earned_was
	Game.dbl_points = dbl_was
	Game.nuke_clearing = nuking_was


# --- the per-round cap, and what it must not eat -----------------------------

## The cap is four a round and the threshold compounds whether or not the cap let
## the drop through. Those two facts together are why the crossing has to be
## latched: R4's verification pass records that BO1 checks
## `zombie_powerup_drop_max_per_round` **before** the 3% roll, and the flag is
## cleared after it — so `powerup_drop()` returns on a capped round without ever
## reaching `zombie_drop_item = 0`, and the entitlement survives into the next
## round. The ancestor is not the model here: html:2380 returns on the cap before it
## even increments `dropTick`, which pauses its kill counter instead of latching.
##
## Driven through `Game.try_drop` rather than by reading the fields, because the
## defect was invisible in the fields — `drop_index` and `next_drop_at` both moved
## exactly as they should have and the drop simply never arrived.
static func _drop_latch(v: Verify) -> void:
	var earned_was := Game.points_earned
	var next_was := Game.next_drop_at
	var idx_was := Game.drop_index
	var count_was := Game.drop_count
	var pending_was := Game.drop_pending

	# The overshoot. R4 §2's `score_to_drop = curr_total_score + increment` measures
	# the next line from where the counter actually is, so the payout that carried it
	# past the last line is spent, not banked. Adding the increment to the old
	# threshold instead hands that overshoot back on every drop for the whole run.
	Game.points_earned = 0
	Game.next_drop_at = 2000
	Game.drop_index = 0
	Game.drop_pending = false
	Game.points_earned = 2130
	var crossed: bool = Game.check_points_drop()
	v.check("the next threshold is measured from the points earned, not from the line",
		crossed and Game.next_drop_at == 2130 + 2280,
		"next=%d, expected %d" % [Game.next_drop_at, 2130 + 2280])

	# Fill the round's cap on the flat roll alone, then cross the threshold while
	# capped. The crossing must be owed, not lost.
	Game.points_earned = 0
	Game.next_drop_at = 2000
	Game.drop_index = 0
	Game.drop_pending = false
	Game.begin_round_drops()
	var granted := 0
	for i in 8:
		if Game.try_drop(true):
			granted += 1
	v.check("the flat roll cannot beat the four-a-round cap",
		granted == Game.DROP_CAP and Game.drop_count == Game.DROP_CAP,
		"granted %d of 8 attempts" % granted)

	Game.points_earned = Game.next_drop_at
	var while_capped: bool = Game.try_drop(false)
	v.check("a threshold crossed inside a capped round is refused but owed",
		not while_capped and Game.drop_pending,
		"granted=%s pending=%s" % [while_capped, Game.drop_pending])

	Game.begin_round_drops()
	var deferred: bool = Game.try_drop(false)
	v.check("the owed drop lands on the first death of the next round",
		deferred and not Game.drop_pending and Game.drop_count == 1,
		"granted=%s pending=%s count=%d" % [deferred, Game.drop_pending, Game.drop_count])

	# One boolean, not a queue: canon holds a single flag, so two crossings inside a
	# capped round still owe exactly one drop. A counter here would hand back a burst
	# of four at the top of the next round.
	Game.begin_round_drops()
	Game.drop_count = Game.DROP_CAP
	for i in 3:
		Game.points_earned = Game.next_drop_at
		Game.try_drop(false)
	Game.begin_round_drops()
	var paid_back := 0
	for i in 4:
		if Game.try_drop(false):
			paid_back += 1
	v.check("three crossings inside one capped round still owe exactly one drop",
		paid_back == 1, "paid back %d" % paid_back)

	Game.points_earned = earned_was
	Game.next_drop_at = next_was
	Game.drop_index = idx_was
	Game.drop_count = count_was
	Game.drop_pending = pending_was


# --- the dog-round guarantee -------------------------------------------------

## R4 §6, Tier 1: `dog_round_aftermath()` sets `powerup_drop_count = 0` before it
## force-drops the Max Ammo, precisely so the four-a-round cap cannot suppress the
## one power-up a dog round is supposed to be worth. The port does not route it
## through the drop rules at all — it refills directly — which is a stronger
## guarantee than canon's and is the thing asserted here: a round already holding
## four power-ups must still hand it over.
static func _max_ammo(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var gun: Dictionary = p.current_gun()
	var res_was: int = gun.res
	var mag_was: int = gun.mag
	var count_was: int = Game.drop_count

	Game.drop_count = Game.DROP_CAP
	gun.res = 0
	gun.mag = 0
	main.rounds._grant_max_ammo()
	var full: bool = int(gun.res) == int(gun.def.res) and int(gun.mag) == int(gun.def.mag)
	v.check("a dog round's Max Ammo arrives even with the round's cap already spent",
		full, "res=%d/%d mag=%d/%d" % [gun.res, gun.def.res, gun.mag, gun.def.mag])

	gun.res = res_was
	gun.mag = mag_was
	Game.drop_count = count_was


# --- the machines ------------------------------------------------------------

## Read through the interaction table's own `_state_of`, because the perk cap and
## the Quick Revive limit are both enforced there and nowhere else: `_do_interact`
## is only ever reached for an interactable the scan selected, and the scan skips
## anything that comes back `none`. A cap enforced only in a constant is a cap a
## second call site walks straight past — and `curves.gd` already pins the constants.
static func _machines(v: Verify, main: Node3D) -> void:
	var perks_was: Dictionary = Game.perks.duplicate()
	var uses_was: int = Game.revive_uses
	var power_was: bool = Game.power_on

	var revive_row := {}
	var other_row := {}
	for it: Dictionary in main.interact.table():
		if it.get("kind", "") != "perk":
			continue
		if it.perk == "revive":
			revive_row = it
		elif other_row.is_empty():
			other_row = it

	# Two prices exist for this one machine — `Game.REVIVE_COST` is the solo 500 and
	# `Weapons.PERKDEF.revive.cost` is the 1500 co-op machine the table still carries
	# for the mode this game does not have. The row has to be built from the first,
	# and the two being three times apart is exactly why a silent swap would never
	# look wrong on screen.
	v.check("the Quick Revive machine is priced from the solo table, not the co-op one",
		not revive_row.is_empty() and int(revive_row.cost) == Game.REVIVE_COST
			and Game.REVIVE_COST != int(Weapons.PERKDEF.revive.cost),
		"charging %d" % int(revive_row.get("cost", -1)))

	Game.perks.clear()
	Game.power_on = true
	Game.revive_uses = 0
	var offered_at_zero: bool = not main.interact._state_of(revive_row).get("none", true)
	Game.revive_uses = Game.REVIVE_MAX_USES
	var offered_at_max: bool = not main.interact._state_of(revive_row).get("none", true)
	v.check("the Quick Revive machine leaves after three buys",
		offered_at_zero and not offered_at_max,
		"uses=0 offered=%s uses=%d offered=%s" % [offered_at_zero,
			Game.REVIVE_MAX_USES, offered_at_max])

	# The cap branch is unreachable through the map as it stands — there are exactly
	# four machines and four is the cap, so a full player already owns every one of
	# them and every machine reads `none` for the simpler reason. Perks the map does
	# not sell are what make the branch observable, which is also the shape of the day
	# the cap starts mattering: a fifth machine added by someone who assumed the
	# constant was doing the work.
	Game.perks.clear()
	Game.revive_uses = 0
	for k: String in ["mule", "stamin", "phd"]:
		Game.perks[k] = true
	var under_cap: bool = not main.interact._state_of(other_row).get("none", true)
	Game.perks["deadshot"] = true
	var at_cap: Dictionary = main.interact._state_of(other_row)
	v.check("a machine offering a fifth perk is refused rather than sold",
		under_cap and at_cap.get("none", false) and not Game.can_take_perk(other_row.perk),
		"under=%s at cap=%s" % [under_cap, at_cap])

	# html:2764 charges `Math.round(cost/2)` for a wall-buy refill and the port charges
	# `int(cost / 2)`. They agree on every current price and disagree the day an odd
	# one is added, which would silently discount that refill by half a point.
	var odd := ""
	for wb: Dictionary in MapData.WALLBUYS:
		if int(wb.cost) % 2 != 0:
			odd += "%s=%d " % [wb.gun, int(wb.cost)]
	v.check("every wall-buy price halves exactly, so int() and round() agree",
		odd.is_empty(), odd)

	Game.perks = perks_was
	Game.revive_uses = uses_was
	Game.power_on = power_was


# --- the drop pool -----------------------------------------------------------

## The bag itself, which is the one part of the power-up layer with no behaviour to
## drive: `pick(['ammo','ammo','insta','nuke','points','points','carp'])`
## (html:2385). Two of seven are Max Ammo and two of seven are Double Points, and
## the weighting *is* the seven-entry array — a set-based tidy-up of it would
## silently halve the frequency of the two most valuable drops in the game.
static func _pool(v: Verify) -> void:
	var pool: Array = POWERUPS.POWER_POOL
	v.check("the drop bag is the ancestor's seven entries, doubles included",
		pool == ["ammo", "ammo", "insta", "nuke", "points", "points", "carp"],
		str(pool))

	# `_collect` matches on the kind and `spawn` indexes the colour table with it, so
	# a kind in the bag with no colour is a crash at the moment of the drop — in a
	# fight, several rounds into a run, and never in a test that only reads the bag.
	var uncoloured := ""
	for kind: String in pool:
		if not POWERUPS.POWER_COLOR.has(kind):
			uncoloured += kind + " "
	v.check("every kind in the bag has a colour to draw with", uncoloured.is_empty(),
		uncoloured)

	# The box is the other half of the economy and its pool has the same failure mode
	# one level up: a key here that is not in the weapon table throws inside
	# `Weapons.spec()` on the roll that picks it, 950 points after the player
	# committed.
	var unknown := ""
	var bad_weight := ""
	for key: String in Weapons.BOX_POOL:
		if not Weapons.TABLE.has(key):
			unknown += key + " "
		if float(Weapons.BOX_WEIGHT.get(key, 1.0)) <= 0.0:
			bad_weight += key + " "
	v.check("every mystery box entry is a real weapon with a positive weight",
		unknown.is_empty() and bad_weight.is_empty(), unknown + bad_weight)

	# 5,000 points has to buy something strictly better on every axis a player can
	# feel, or Pack-a-Punch is a trap for one of the twelve.
	var worse := ""
	for key: String in Weapons.TABLE:
		var base := Weapons.spec(key)
		var up := Weapons.papify(base)
		if int(up.mag) < int(base.mag) or int(up.res) < int(base.res) \
				or float(up.reload) > float(base.reload):
			worse += key + " "
		# The Thundergun's listed damage is 0 — its kill is the cone — so a damage
		# comparison has to be conditional or it reports the one weapon in the table
		# that is working as designed.
		if float(base.dmg) > 0.0 and float(up.dmg) <= float(base.dmg):
			worse += key + " "
	v.check("Pack-a-Punch is an upgrade on every axis for every weapon",
		worse.is_empty(), worse)


# --- shared save / restore ---------------------------------------------------

## The economy fields these checks move, plus the two counters a death handler
## bumps on the way past. Returned as a dictionary rather than restored by each
## section, because the sections that drive a real death touch all of it and a
## partial restore is how `--verify` starts depending on its own running order.
static func _save(main: Node3D) -> Dictionary:
	return {
		"points": Game.points, "earned": Game.points_earned,
		"next": Game.next_drop_at, "index": Game.drop_index,
		"count": Game.drop_count, "pending": Game.drop_pending,
		"insta": Game.insta_kill, "dbl": Game.dbl_points,
		"nuking": Game.nuke_clearing, "kills": Game.kills,
		"headshots": Game.headshots, "alive": main.rounds.alive().size(),
	}


static func _restore(main: Node3D, s: Dictionary) -> void:
	Game.points = s.points
	Game.points_earned = s.earned
	Game.next_drop_at = s.next
	Game.drop_index = s.index
	Game.drop_count = s.count
	Game.drop_pending = s.pending
	Game.insta_kill = s.insta
	Game.dbl_points = s.dbl
	Game.nuke_clearing = s.nuking
	Game.kills = s.kills
	Game.headshots = s.headshots
	# The director's live list is the one thing here that is not a scalar. Nothing
	# this file adds to it may survive, or the next section's round never ends.
	var live: Array = main.rounds.alive()
	while live.size() > int(s.alive):
		live.pop_back()
