class_name BalanceSim
extends RefCounted

## Headless round simulator: the only thing in this repository that can answer
## "did that change make round 12 harder or easier, and by how much".
##
## Before this, every balance claim was a claim about a game nobody could play
## past about round five, so a change to zombie speed, weapon damage or the round
## curve landed with no measurement at all behind it. Milestone 2 shipped a
## fire-rate fix that is a straight buff — the delivered cadence table this prints
## first is the evidence — against a round curve that was tuned while the rates
## were broken. This is the apparatus that puts a number on that.
##
## **What it is valid for: comparing two builds of THIS model against each other.**
## Both builds are driven from one seed, so the horde is bit-identical between
## them and every difference in the output is caused by the thing that was
## changed. **It is not valid as an absolute difficulty figure**, and the list of
## reasons is long enough to live in notes/balance/README.md rather than here.
## The short version: no map, no line of sight, no player movement, no barricade,
## no power-up effects, and a player who never misses for a reason the model does
## not know about. Read the ratios, never the levels.
##
## Everything that can be imported is imported. The curves come from the Game
## autoload, the weapon table and the state machine from scripts/data/weapons.gd
## and scripts/entities/weapon.gd, and every zombie's health, speed class, melee
## damage and cadence comes from a real `Zombie.create()` — a sim that copies the
## numbers tests the copy.
##
##   Godot_v4.7-stable_win64_console.exe --headless --path . --sim
##   pwsh tools/balance.ps1

## preload rather than the global class name: a freshly added script is not in the
## class registry until the editor rescans, and a headless run has no editor.
const WEAPON := preload("res://scripts/entities/weapon.gd")

## The flat per-death drop chance, imported rather than copied — it is 0.03 and it
## is R4 §2's `randomint(100) > 2`, and a second copy of it here would be a second
## place to change it and one place to forget.
const ROUND_DIRECTOR := preload("res://scripts/systems/round_director.gd")

## The physics tick the fire-rate fix is written against. `_update_fire` runs at
## Godot's default 60 Hz and the whole of the M2 cadence bug was the remainder
## inside one of these being thrown away, so this rate is not a sim convenience —
## change it and the thing being measured stops existing.
const TICK := 1.0 / 60.0

## A round that has not finished after this much simulated time is a stall, not a
## hard round: a weapon that cannot out-damage nothing (the Thundergun's `dmg` is
## 0 and its kill is the cone, which has no place in a positionless model) would
## otherwise spin forever inside a headless process that nobody is watching.
const ROUND_TIMEOUT := 3600.0

## Column order is declared once and every row is emitted through it, so a header
## and a row cannot drift apart. Consumers must look columns up BY NAME — see the
## key-order footgun documented at the top of tools/balance.ps1.
const ROUND_FIELDS: Array = [
	"gun", "pap", "cadence", "perks", "seed",
	"round", "dog", "count", "hp_each", "total_hp", "max_alive",
	"spawn_interval", "walk", "run", "sprint",
	"time_to_clear_s", "shots", "hits", "kills", "reload_s",
	"hp_per_s", "points", "drops", "refills",
	"damage_taken", "hp_bars", "contact_frac", "contact_zsec",
	"peak_alive", "first_contact_s",
]

const SUMMARY_FIELDS: Array = [
	"gun", "pap", "cadence", "perks", "seed", "band", "rounds",
	"clear_s", "shots", "kills", "points", "damage_taken",
	"contact_zsec", "mean_contact_frac", "refills",
]

const CADENCE_FIELDS: Array = [
	"gun", "stated_rpm", "legacy_rpm", "fixed_rpm", "legacy_err_pct", "fixed_err_pct",
	"delivered_gain_pct",
]

## Five-round bands, because that is the unit the round curve is discussed in
## ("rounds 1-5 got easier") and a per-round table is too wide to read as a whole.
const BAND := 5

var _rounds: Array[String] = []
var _summary: Array[String] = []
var _cadence: Array[String] = []
var _log: Array[String] = []

## Model dice — accuracy and headshot placement. Deliberately NOT one of Rng's
## streams. Constraint 6 forbids a cosmetic draw perturbing a gameplay one, and
## this is the same hazard one level up: if the player model drew from SPAWN or AI
## then firing more shots would change which zombies spawn, and the two cadence
## builds this whole harness exists to compare would face different hordes. Seeded
## off the run seed by the same name-hash Rng.stream() uses, so it is still wholly
## determined by `--sim-seed`.
var _dice := RandomNumberGenerator.new()


# --- entry point -------------------------------------------------------------

## Returns a process exit code: non-zero if any build stalled or was refused, so
## a sim run can gate a script the same way `--verify` gates a build.
func run(main: Node3D) -> int:
	var args := OS.get_cmdline_args()
	var out_dir: String = _arg(args, "--sim-out", "res://notes/balance")
	var seed_value: int = int(_arg(args, "--sim-seed", "20260729"))
	var rounds: int = int(_arg(args, "--sim-rounds", "20"))
	var guns: PackedStringArray = _arg(args, "--sim-gun", "mp40,ak74u,m16,rpk,pm63,m1911").split(",")
	var cadences: PackedStringArray = _arg(args, "--sim-cadence", "fixed,legacy").split(",")
	var perks: String = _arg(args, "--sim-perks", "")
	var pap: bool = "--sim-pap" in args
	var stamp: String = _arg(args, "--sim-stamp", Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "").replace("T", "-"))

	var model := {
		"accuracy": float(_arg(args, "--sim-accuracy", "0.78")),
		"headshot": float(_arg(args, "--sim-headshot", "0.30")),
		"retarget": float(_arg(args, "--sim-retarget", "0.12")),
		"entry": float(_arg(args, "--sim-entry", "0.0")),
		"splash": float(_arg(args, "--sim-splash", "0.0")),
		"perks": perks,
		"seed": seed_value,
		"rounds": rounds,
		"pap": pap,
	}
	# Derived from the real map rather than picked: the mean straight-line distance
	# from a live window to the player's start tile. It is a *straight line*, so it
	# is a lower bound on the walk a zombie actually makes — stated here because a
	# derived number that is quietly wrong is worse than an admitted guess.
	model["approach"] = float(_arg(args, "--sim-approach", "%.3f" % _mean_window_range(main)))

	_note("balance sim — seed %d, %d rounds, approach %.2f m, accuracy %.2f, headshot %.2f"
		% [seed_value, rounds, float(model.approach), float(model.accuracy), float(model.headshot)])
	_note("model: stationary player, no map, no line of sight, no barricade, no power-up effects.")
	_note("READ THE RATIOS BETWEEN BUILDS. The levels are not survivability figures.")

	_cadence_table()

	var failures := 0
	for gun_key: String in guns:
		var key := gun_key.strip_edges()
		if key.is_empty():
			continue
		if not Weapons.TABLE.has(key):
			_note("!! no such weapon '%s' — skipped" % key)
			failures += 1
			continue
		# Refused rather than reported. The Thundergun's listed damage is 0 and its
		# kill is `_cone_blast`, which needs positions this model does not have; a
		# row for it would read as "the Thundergun clears nothing", which is a lie
		# about the weapon rather than a measurement of it.
		var spec := Weapons.spec(key)
		if float(spec.cone) > 0.0 or float(spec.dmg) <= 0.0:
			_note("!! %s kills by cone, which a positionless model cannot represent — skipped" % key)
			failures += 1
			continue
		for cadence_name: String in cadences:
			var mode := cadence_name.strip_edges()
			if mode.is_empty():
				continue
			if mode != "fixed" and mode != "legacy":
				_note("!! unknown cadence '%s' — expected fixed or legacy" % mode)
				failures += 1
				continue
			var build := model.duplicate()
			build["gun"] = key
			build["cadence"] = mode
			if not _run_build(main, build):
				failures += 1

	var stem := "%s/sim-%s" % [out_dir.rstrip("/"), stamp]
	_write(stem + "-rounds.csv", ROUND_FIELDS, _rounds)
	_write(stem + "-summary.csv", SUMMARY_FIELDS, _summary)
	_write(stem + "-cadence.csv", CADENCE_FIELDS, _cadence)

	print("\n=== balance sim ===")
	for line: String in _log:
		print(line)
	print("=== %d row(s), %d failure(s) ===" % [_rounds.size(), failures])
	return failures


# --- the cadence table -------------------------------------------------------

## The M2 fire-rate fix, measured, before any round is simulated.
##
## `fixed` is the real state machine driven at 60 Hz. `legacy` is a MODEL of the
## code the fix replaced — that code no longer exists, so it cannot be re-run, and
## the model is the one line of arithmetic it reduced to: an absolute
## `next_shot = 60/rpm` counted down by a clamped-at-zero 60 Hz timer fires every
## `ceil(interval / tick)` ticks, so every rate quantises UP to a multiple of
## 1/60 s. The check that this model is right is that it reproduces the four
## collisions recorded in verify.gd's `_weapon_fsm` — MP40 and M16 both at 720,
## AK-74u and RPK both at 600 — from the table alone.
func _cadence_table() -> void:
	_note("")
	_note("delivered RPM: legacy (quantised to the 60 Hz tick) against the shipping fix")
	_note("  %-11s %6s %8s %8s %9s" % ["weapon", "stated", "legacy", "fixed", "gain"])
	for key: String in Weapons.TABLE:
		var stated: float = float(Weapons.spec(key).rpm)
		var fixed_rpm := _measure_rpm(key, "fixed")
		var legacy_rpm := _measure_rpm(key, "legacy")
		var gain := (fixed_rpm / legacy_rpm - 1.0) * 100.0 if legacy_rpm > 0.0 else 0.0
		_cadence.append(_row(CADENCE_FIELDS, {
			"gun": key, "stated_rpm": "%.1f" % stated,
			"legacy_rpm": "%.1f" % legacy_rpm, "fixed_rpm": "%.1f" % fixed_rpm,
			"legacy_err_pct": "%.2f" % ((legacy_rpm / stated - 1.0) * 100.0),
			"fixed_err_pct": "%.2f" % ((fixed_rpm / stated - 1.0) * 100.0),
			"delivered_gain_pct": "%.2f" % gain,
		}))
		_note("  %-11s %6.0f %8.1f %8.1f %8.1f%%" % [key, stated, legacy_rpm, fixed_rpm, gain])
	_note("")


## Rounds fired in one simulated minute with an infinite magazine, which is the
## same construction verify.gd uses — cadence and nothing else.
func _measure_rpm(key: String, mode: String) -> float:
	var gun := Weapons.make_gun(key, false)
	gun.mag = 1 << 30
	gun.res = 1 << 30
	var interval := 60.0 / float(gun.def.rpm)
	var quantum := ceili(interval / TICK)
	var cool := 0
	var shots := 0
	for i in 3600:
		WEAPON.tick(gun, TICK, true)
		cool -= 1
		if mode == "legacy":
			# Integer ticks, not a float countdown. The quantised interval is a whole
			# number of ticks by construction, and repeatedly subtracting 1/60.0 from
			# its float product lands either side of zero at random — which would put
			# a one-tick jitter on the exact quantity being measured.
			while cool <= 0:
				WEAPON.consume_shot(gun, 1.0)
				gun.next_shot = 0.0
				cool += quantum
				shots += 1
		else:
			while float(gun.next_shot) <= 0.0:
				WEAPON.consume_shot(gun, 1.0)
				shots += 1
	# Minus the round that goes out on tick zero: sixty seconds of firing contains
	# `shots - 1` intervals, and it is the interval that is the fire rate.
	#
	# This is exact only when the interval divides 60 s evenly (the MP40 at 880 and
	# the PM63 at 1000 do), and one low otherwise, because the last interval of the
	# window is cut off part-way through. So the `*_err_pct` columns carry a
	# counting artifact of up to one rpm — the M1911 reads 419 of a stated 420 and
	# the Stakeout 144 of 145 — and neither is a defect in the weapon. Left as it
	# is rather than tuned away: `delivered_gain_pct` is a ratio of two numbers
	# carrying the same artifact, so it survives it to 0.03%, and that ratio is the
	# only thing this table is read for.
	return float(maxi(0, shots - 1))


# --- one build ---------------------------------------------------------------

## True on success. Every build re-seeds the world, so build A and build B face
## the same horde down to the last zombie's speed roll — that identity is the
## whole basis on which the two are allowed to be compared.
func _run_build(main: Node3D, p: Dictionary) -> bool:
	Rng.new_run(int(p.seed))
	Game.reset_run()
	Game.perks.clear()
	for k: String in String(p.perks).split(",", false):
		Game.perks[k.strip_edges()] = true
	_dice.seed = hash("%d/simplayer" % int(p.seed))

	var gun := Weapons.make_gun(String(p.gun), bool(p.pap))
	var label := "%s%s/%s" % [p.gun, "+pap" if bool(p.pap) else "", p.cadence]

	var band_acc := {}
	var total := _blank_totals()
	var rounds: int = int(p.rounds)
	for r in range(1, rounds + 1):
		var row := _sim_round(main, p, gun, r)
		if bool(row.stalled):
			_note("!! %s stalled in round %d after %.0f s of sim — build abandoned"
				% [label, r, ROUND_TIMEOUT])
			return false
		# main._end_round rolls the next hound round the moment one finishes, so the
		# cadence has to be driven from here too or every run after the first dog
		# round is dog-free and the sim quietly measures an easier game.
		if bool(row.dog):
			Game.advance_dog_round()
		_rounds.append(_row(ROUND_FIELDS, _format_round(p, r, row)))
		_accumulate(total, row)
		var band := "%d-%d" % [((r - 1) / BAND) * BAND + 1, ((r - 1) / BAND + 1) * BAND]
		if not band_acc.has(band):
			band_acc[band] = _blank_totals()
		_accumulate(band_acc[band], row)

	for band: String in band_acc:
		_summary.append(_row(SUMMARY_FIELDS, _format_totals(p, band, band_acc[band])))
	_summary.append(_row(SUMMARY_FIELDS, _format_totals(p, "all", total)))

	var clear: float = total.clear_s
	var contact: float = total.contact_zsec
	_note("%-16s  clear %7.1f s   contact %8.1f z·s   points %7d   taken %9.0f"
		% [label, clear, contact, int(total.points), float(total.damage_taken)])
	return true


# --- one round ---------------------------------------------------------------

## The whole model, in one function, deliberately: every simplification is visible
## from one screen and none of them is buried behind an abstraction.
func _sim_round(main: Node3D, p: Dictionary, gun: Dictionary, r: int) -> Dictionary:
	Game.round_no = r
	var dog := Game.is_dog_round(r)
	var count: int = Game.zombie_count(r)
	var cap: int = Game.max_alive(r)
	var approach: float = float(p.approach)
	var entry: float = float(p.entry)
	var accuracy: float = float(p.accuracy)
	var headshot_frac: float = float(p.headshot)
	var retarget_len: float = float(p.retarget)
	var splash_targets: int = int(float(p.splash))
	var legacy: bool = String(p.cadence) == "legacy"
	var drop_chance: float = ROUND_DIRECTOR.DROP_CHANCE

	var def: Dictionary = gun.def
	var pellets: int = int(def.pellets)
	var dmg_per_pellet: float = float(def.dmg) * Game.damage_scale()
	var splash_dmg: float = float(def.splash_dmg) * Game.damage_scale()
	var reload_scale: float = Game.reload_scale()
	var rpm_scale: float = Game.rpm_scale()
	var quantum := ceili((60.0 / (float(def.rpm) * rpm_scale)) / TICK)
	# The reserve is topped up at the round boundary, which stands in for the wall
	# buy or the Max Ammo an actual run would have made between rounds. `refills`
	# counts the ones it needed mid-round on top of that — an ammo economy the model
	# grants for free, and therefore a cost it is not charging the player.
	gun.res = int(def.res)
	WEAPON.on_ammo_added(gun)

	# What RoundDirector._begin_round() does at the top of a round, and the only part
	# of it this model has any use for. Without it the four-per-round cap silently
	# becomes four per run and the `drops` column reads zero from round five onward.
	Game.begin_round_drops()

	# hp, speed, arrive_t, next_atk, melee_dmg, melee_cadence, last_landed_t, class
	var alive: Array[Array] = []
	var to_spawn := count
	var spawn_timer: float = Sfx.ROUND_SILENCE
	var intervals: Array[float] = []
	var classes := [0, 0, 0]
	var total_hp := 0.0

	var t := 0.0
	var cool := 0
	var retarget := 0.0
	var target := -1
	var shots := 0
	var hits := 0
	var kills := 0
	var reload_ticks := 0
	var contact_ticks := 0
	var contact_zsec := 0.0
	var damage_taken := 0.0
	var points := 0
	var drops := 0
	var refills := 0
	var peak_alive := 0
	var first_contact := -1.0
	var hp_each: float = Game.zombie_hp(r)

	while (to_spawn > 0 or not alive.is_empty()) and t < ROUND_TIMEOUT:
		# --- spawning: the real interval, the real cap, the real crawler roll ----
		spawn_timer -= TICK
		if to_spawn > 0 and spawn_timer <= 0.0 and alive.size() < cap:
			var kind := "zombie"
			if dog:
				kind = "hound"
			elif Rng.randf(Rng.SPAWN) < Game.crawler_chance(r):
				kind = "crawler"
			var z := _spawn(kind, r, t, entry, approach)
			classes[_class_of(z[7])] += 1
			total_hp += z[0]
			alive.append(z)
			to_spawn -= 1
			spawn_timer = Game.spawn_interval(r)
			intervals.append(spawn_timer)
			peak_alive = maxi(peak_alive, alive.size())

		# --- what is inside melee reach, and what that costs --------------------
		var in_contact := 0
		for z: Array in alive:
			if t < z[2]:
				continue
			in_contact += 1
			if t >= z[3]:
				# Player.HURT_IGNORE gates each attacker separately. Every melee
				# cadence in the table is longer than the gate, so it never refuses a
				# hit today — it is applied anyway because the day one of them drops
				# under 0.4 s is the day this model would silently overstate the
				# damage by the ratio between them.
				if t - z[6] >= Player.HURT_IGNORE:
					damage_taken += z[4]
					z[6] = t
				z[3] = t + z[5]
		if in_contact > 0:
			contact_ticks += 1
			contact_zsec += float(in_contact) * TICK
			if first_contact < 0.0:
				first_contact = t

		# --- the gun ------------------------------------------------------------
		if target >= 0 and target >= alive.size():
			target = -1
		if target < 0 and not alive.is_empty():
			target = _nearest(alive)
		retarget = maxf(0.0, retarget - TICK)
		var want := target >= 0 and retarget <= 0.0
		var state: int = gun.state
		if state == WEAPON.State.RELOADING or state == WEAPON.State.RELOAD_SHELL:
			reload_ticks += 1
		WEAPON.tick(gun, TICK, want and WEAPON.can_fire(gun))
		# Clamped at zero exactly as the legacy cooldown was, which is also what
		# stops a weapon that has had nothing to shoot at for ten seconds banking
		# six hundred ticks of cadence and opening with a six-hundred-round burst.
		cool = maxi(cool - 1, 0)

		while want and WEAPON.can_fire(gun):
			if not ((cool <= 0) if legacy else (float(gun.next_shot) <= 0.0)):
				break
			if int(gun.mag) <= 0:
				if int(gun.res) <= 0:
					gun.res = int(def.res)
					WEAPON.on_ammo_added(gun)
					refills += 1
				WEAPON.dry_fire(gun)
				WEAPON.begin_reload(gun, reload_scale)
				cool = 1
				break
			WEAPON.consume_shot(gun, rpm_scale)
			if legacy:
				gun.next_shot = 0.0
				cool += quantum
			shots += 1
			# Every pellet is an independent draw, which is what makes a shotgun's
			# six-pellet spread behave differently from one round of six times the
			# damage: the surplus on an overkilled body is thrown away per pellet.
			for i in pellets:
				if _dice.randf() >= accuracy:
					continue
				hits += 1
				var head := _dice.randf() < headshot_frac
				# Zombie.take_damage: a headshot is 1.5x, and the payout on the
				# killing blow is 100 rather than 60.
				var landed: float = dmg_per_pellet * (1.5 if head else 1.0)
				var t_row: Array = alive[target]
				t_row[0] -= landed
				if t_row[0] > 0.0:
					points += Game.PTS_HIT
					Game.points_earned += Game.PTS_HIT
					continue
				var pay: int = Game.PTS_HEADSHOT if head else Game.PTS_KILL
				points += pay
				# Game.add_points() would be the real path, but it emits
				# points_changed and the HUD is bound to it — a hundred thousand
				# signal dispatches for a number no headless run will ever draw. The
				# accumulator it feeds is what check_points_drop() reads, so that is
				# the part kept.
				Game.points_earned += pay
				kills += 1
				if _kill(alive, target, drop_chance):
					drops += 1
				# After the primary rather than before it: the blast lands on the
				# bodies left standing once the round has done its work, and the reap
				# inside needs a list no other index is pointing into.
				if splash_dmg > 0.0 and splash_targets > 0:
					var blast := _splash(alive, splash_dmg, splash_targets, drop_chance)
					kills += int(blast[0])
					points += int(blast[1])
					drops += int(blast[2])
				target = -1
				retarget = retarget_len
				break
			if int(gun.mag) <= 0:
				WEAPON.begin_reload(gun, reload_scale)
			if target < 0:
				break

		if alive.is_empty() and int(gun.mag) < int(def.mag) and int(gun.res) > 0:
			# Nothing left standing, so the magazine goes back in — which is what a
			# player does in the gap between the last kill and the next arrival, and
			# what makes an early round's reload downtime free rather than paid.
			#
			# Gated on the horde being EMPTY, not on `want`. Keyed on `want` it also
			# fired during the 0.12 s of retargeting after every kill, and since a
			# magazine reload is not interruptible that bought a full 2.3 s reload per
			# corpse: round 12 came out at 182 s against a true 120, and reload_s at
			# 127 s of it. The tell was reload_s tracking the kill count rather than
			# the shot count.
			WEAPON.begin_reload(gun, reload_scale)

		t += TICK

	var ticks: float = maxf(1.0, t / TICK)
	return {
		"stalled": t >= ROUND_TIMEOUT,
		"dog": dog, "count": count, "hp_each": hp_each, "total_hp": total_hp,
		"max_alive": cap,
		"spawn_interval": _mean(intervals),
		"walk": float(classes[0]), "run": float(classes[1]), "sprint": float(classes[2]),
		"clear_s": t, "shots": shots, "hits": hits, "kills": kills,
		"reload_s": float(reload_ticks) * TICK,
		"points": points, "drops": drops, "refills": refills,
		"damage_taken": damage_taken,
		"contact_frac": float(contact_ticks) / ticks,
		"contact_zsec": contact_zsec,
		"peak_alive": peak_alive,
		"first_contact_s": first_contact,
	}


## One spawn, built by the real entity so that health, the discrete speed class,
## the ±8% variance, A23's late-round nudge, the melee damage and the attack phase
## are the game's own values rather than this file's opinion of them. The node is
## never added to the tree, so `_ready()` never runs and no sprite, mesh or
## collider is ever built — `_configure()` is the whole of what is wanted.
func _spawn(kind: String, r: int, now: float, entry: float, approach: float) -> Array:
	var z := Zombie.create(kind, Rng.stream(Rng.SPAWN).randi() % 3, r, false)
	var speed: float = z.speed
	var row: Array = [
		z.hp,
		speed,
		# Straight-line approach at the class speed. `entry` stands in for the
		# barricade the model does not have and is zero unless asked for.
		now + entry + approach / maxf(0.01, speed),
		0.0,
		z.melee_damage,
		z.melee_cadence,
		-1e9,
		# The speed class this spawn landed on, recovered by dividing the kind
		# multiplier back out. Reading the draw back beats re-rolling it: a second
		# roll would consume an AI draw the game never makes and shift every
		# subsequent spawn in the run.
		0.0,
	]
	var kind_mult := 1.0
	match kind:
		"hound":
			kind_mult = 1.55
		"crawler":
			kind_mult = 0.62
		_:
			kind_mult = Game.late_speed_scale(r)
	row[7] = speed / kind_mult
	row[3] = row[2] + z._attack_timer
	z.free()
	return row


## Which of the three named classes a recovered speed came from. Thresholded at
## the midpoints rather than tested for equality because `_configure` multiplies
## every spawn by ±8%: the three bands are 0.97-1.13, 2.02-2.38 and 3.17-3.73, so
## the midpoints separate them with room to spare and an equality test would
## classify every zombie in the game as a sprinter by falling through.
func _class_of(speed: float) -> int:
	if speed < (Game.SPEED_WALK + Game.SPEED_RUN) * 0.5:
		return 0
	if speed < (Game.SPEED_RUN + Game.SPEED_SPRINT) * 0.5:
		return 1
	return 2


## The target is whatever will reach the player first, which for a stationary
## player is also whatever is nearest. Anything already in contact has an arrival
## time in the past, so it wins automatically — the player shoots what is on him.
func _nearest(alive: Array[Array]) -> int:
	var best := 0
	var best_t: float = alive[0][2]
	for i in alive.size():
		var at: float = alive[i][2]
		if at < best_t:
			best_t = at
			best = i
	return best


## Splash against the crudest term in the whole model. There are no positions, so
## "how many other bodies were in the blast" is a parameter rather than a fact;
## it is zero unless the caller asks for it, and the README says why.
##
## Two things it has to get right even so. The damage is spread over that many
## DISTINCT bodies at full strength rather than stacked on one body at n times
## the strength: three times 1150 on one corpse is thrown away as overkill and is
## not what a China Lake round is worth. And whatever the blast kills is reaped
## here, through the same payout and the same drop rules as any other death —
## leaving a body sitting at -400 hp in the live list would have it walk in and
## keep swinging, which is worse than not modelling splash at all.
##
## Returns [kills, points, drops].
func _splash(alive: Array[Array], amount: float, targets: int, drop_chance: float) -> Array:
	var hit := 0
	var i := 0
	var killed := 0
	var paid := 0
	var dropped := 0
	while i < alive.size() and hit < targets:
		alive[i][0] -= amount
		hit += 1
		if alive[i][0] > 0.0:
			i += 1
			continue
		# A blast kill pays the body-shot rate. It has no hit location, so it can
		# never be the headshot payout.
		paid += Game.PTS_KILL
		Game.points_earned += Game.PTS_KILL
		killed += 1
		if _kill(alive, i, drop_chance):
			dropped += 1
	return [killed, paid, dropped]


## Removes the body and runs the real drop rules over it. Returns whether this
## death produced a power-up — the cadence is modelled, the *effect* is not.
func _kill(alive: Array[Array], idx: int, drop_chance: float) -> bool:
	alive.remove_at(idx)
	Game.kills += 1
	# Game.try_drop rather than a second copy of the rule. The copy that used to be
	# here is precisely how this sim went on reporting four drops a RUN after the
	# game had been fixed to pay four a ROUND — the bug the sim itself had surfaced.
	var lucky := Rng.randf(Rng.DROPS) < drop_chance
	return Game.try_drop(lucky)


# --- reporting ---------------------------------------------------------------

func _format_round(p: Dictionary, r: int, row: Dictionary) -> Dictionary:
	var clear: float = row.clear_s
	var shots: int = row.shots
	var hp_bars: float = float(row.damage_taken) / maxf(1.0, Game.max_health())
	return {
		"gun": p.gun, "pap": "1" if bool(p.pap) else "0", "cadence": p.cadence,
		"perks": String(p.perks).replace(",", "+"), "seed": int(p.seed),
		"round": r, "dog": "1" if bool(row.dog) else "0",
		"count": row.count, "hp_each": "%.0f" % float(row.hp_each),
		"total_hp": "%.0f" % float(row.total_hp), "max_alive": row.max_alive,
		"spawn_interval": "%.3f" % float(row.spawn_interval),
		"walk": "%.0f" % float(row.walk), "run": "%.0f" % float(row.run),
		"sprint": "%.0f" % float(row.sprint),
		"time_to_clear_s": "%.2f" % clear,
		"shots": shots, "hits": row.hits, "kills": row.kills,
		"reload_s": "%.2f" % float(row.reload_s),
		"hp_per_s": "%.1f" % (float(row.total_hp) / maxf(0.001, clear)),
		"points": row.points, "drops": row.drops, "refills": row.refills,
		"damage_taken": "%.0f" % float(row.damage_taken),
		"hp_bars": "%.1f" % hp_bars,
		"contact_frac": "%.3f" % float(row.contact_frac),
		"contact_zsec": "%.1f" % float(row.contact_zsec),
		"peak_alive": row.peak_alive,
		"first_contact_s": "%.2f" % float(row.first_contact_s),
	}


func _blank_totals() -> Dictionary:
	return {
		"rounds": 0, "clear_s": 0.0, "shots": 0, "kills": 0, "points": 0,
		"damage_taken": 0.0, "contact_zsec": 0.0, "contact_frac": 0.0, "refills": 0,
	}


func _accumulate(into: Dictionary, row: Dictionary) -> void:
	into.rounds = int(into.rounds) + 1
	into.clear_s = float(into.clear_s) + float(row.clear_s)
	into.shots = int(into.shots) + int(row.shots)
	into.kills = int(into.kills) + int(row.kills)
	into.points = int(into.points) + int(row.points)
	into.damage_taken = float(into.damage_taken) + float(row.damage_taken)
	into.contact_zsec = float(into.contact_zsec) + float(row.contact_zsec)
	into.contact_frac = float(into.contact_frac) + float(row.contact_frac)
	into.refills = int(into.refills) + int(row.refills)


func _format_totals(p: Dictionary, band: String, tot: Dictionary) -> Dictionary:
	var n: float = maxf(1.0, float(tot.rounds))
	return {
		"gun": p.gun, "pap": "1" if bool(p.pap) else "0", "cadence": p.cadence,
		"perks": String(p.perks).replace(",", "+"), "seed": int(p.seed),
		"band": band, "rounds": tot.rounds,
		"clear_s": "%.2f" % float(tot.clear_s),
		"shots": tot.shots, "kills": tot.kills, "points": tot.points,
		"damage_taken": "%.0f" % float(tot.damage_taken),
		"contact_zsec": "%.1f" % float(tot.contact_zsec),
		"mean_contact_frac": "%.3f" % (float(tot.contact_frac) / n),
		"refills": tot.refills,
	}


func _row(fields: Array, values: Dictionary) -> String:
	var out := PackedStringArray()
	for f: String in fields:
		out.append(str(values.get(f, "")))
	return ",".join(out)


func _write(path: String, fields: Array, rows: Array[String]) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_note("!! could not write %s (%d)" % [path, FileAccess.get_open_error()])
		return
	f.store_line(",".join(PackedStringArray(fields)))
	for line: String in rows:
		f.store_line(line)
	f.close()
	_note("wrote %s (%d rows)" % [path, rows.size()])


func _note(line: String) -> void:
	_log.append(line)


# --- helpers -----------------------------------------------------------------

## `--sim-foo value`, in the same shape as main.gd's `--shot <path> [yaw]`.
func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	var i := args.find(name)
	if i < 0 or i + 1 >= args.size():
		return fallback
	return args[i + 1]


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v: float in values:
		sum += v
	return sum / float(values.size())


## Mean straight-line distance from a live window to the player's start tile, off
## the real map. Doors are shut at the start of a run, so this is the set of
## windows a round-one horde actually arrives through.
func _mean_window_range(main: Node3D) -> float:
	var m: MapData = main.map
	if m == null:
		m = MapData.new()
		m.build()
	var home := Vector2(MapData.SPAWN_TILE.x + 0.5, MapData.SPAWN_TILE.y + 0.5)
	var live: Array[int] = m.live_windows()
	if live.is_empty():
		return 9.0
	var sum := 0.0
	for wi: int in live:
		sum += m.window_stand_pos(wi).distance_to(home)
	return sum / float(live.size())
