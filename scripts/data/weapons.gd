class_name Weapons
extends RefCounted

## Weapon table ported verbatim from kriegsnacht.html section 4.
## Every number is engine-independent design data, so it transfers unchanged.

## The state machine that reads all of this. preload rather than the class name: a
## freshly added script is not in the class registry until the editor rescans, and a
## headless run has no editor. Nothing flows back the other way — weapon.gd knows
## about gun dictionaries and about nothing else — so there is no cycle here.
const WEAPON := preload("res://scripts/entities/weapon.gd")

## `shells` finally does something. It has been declared here and in the ancestor
## (kriegsnacht.html:1460, :1465) since the beginning and read by nothing in either;
## it now selects a shell-by-shell reload that firing can interrupt, which is the
## behaviour the flag was always named for. See Weapon.begin_reload.
const DEFAULTS := {
	"mag": 8, "res": 80, "dmg": 60, "rpm": 400, "auto": false, "pellets": 1,
	"spread": 1.0, "reload": 1.8, "kick": 1.0, "range": 26.0,
	"proj": "", "splash": 0.0, "splash_dmg": 0.0, "cone": 0.0, "shells": false,
	"freq": 1500.0, "thump": 150.0, "body": 1.0,
}

const TABLE := {
	"m1911": {"name": "M1911", "mag": 8, "res": 80, "dmg": 65, "rpm": 420, "spread": 0.85, "reload": 1.5, "kick": 1.3, "freq": 1700.0, "thump": 170.0, "body": 0.7},
	"olympia": {"name": "Olympia", "mag": 2, "res": 60, "dmg": 105, "rpm": 170, "pellets": 6, "spread": 5.4, "reload": 2.5, "kick": 3.4, "range": 13.0, "shells": true, "freq": 900.0, "thump": 110.0, "body": 1.5},
	"m14": {"name": "M14", "mag": 8, "res": 120, "dmg": 185, "rpm": 420, "spread": 0.6, "reload": 2.3, "kick": 2.1, "freq": 1250.0, "thump": 130.0, "body": 1.2},
	"mp40": {"name": "MP40", "mag": 32, "res": 256, "dmg": 100, "rpm": 880, "auto": true, "spread": 1.7, "reload": 2.3, "kick": 1.1, "freq": 1600.0, "thump": 150.0, "body": 0.85},
	"pm63": {"name": "PM63", "mag": 25, "res": 200, "dmg": 85, "rpm": 1000, "auto": true, "spread": 2.0, "reload": 2.1, "kick": 0.9, "freq": 1850.0, "thump": 160.0, "body": 0.75},
	"ak74u": {"name": "AK-74u", "mag": 30, "res": 270, "dmg": 132, "rpm": 710, "auto": true, "spread": 1.5, "reload": 2.5, "kick": 1.4, "freq": 1400.0, "thump": 140.0, "body": 1.05},
	"stakeout": {"name": "Stakeout", "mag": 6, "res": 60, "dmg": 88, "rpm": 145, "pellets": 6, "spread": 4.6, "reload": 3.4, "kick": 3.0, "range": 14.0, "shells": true, "freq": 850.0, "thump": 100.0, "body": 1.45},
	"m16": {"name": "M16", "mag": 30, "res": 270, "dmg": 158, "rpm": 740, "auto": true, "spread": 1.15, "reload": 2.6, "kick": 1.5, "freq": 1550.0, "thump": 145.0, "body": 1.1},
	"rpk": {"name": "RPK", "mag": 100, "res": 400, "dmg": 142, "rpm": 700, "auto": true, "spread": 1.9, "reload": 4.6, "kick": 1.5, "freq": 1300.0, "thump": 135.0, "body": 1.2},
	"chinalake": {"name": "China Lake", "mag": 4, "res": 30, "dmg": 120, "rpm": 62, "spread": 0.4, "reload": 3.4, "kick": 3.6, "proj": "grenade", "splash": 2.6, "splash_dmg": 1150.0, "freq": 700.0, "thump": 90.0, "body": 1.5},
	"raygun": {"name": "Ray Gun", "mag": 20, "res": 160, "dmg": 180, "rpm": 320, "spread": 0.7, "reload": 2.6, "kick": 2.0, "proj": "ray", "splash": 1.7, "splash_dmg": 620.0, "freq": 2200.0, "thump": 220.0, "body": 0.9},
	"thundergun": {"name": "Thundergun", "mag": 2, "res": 6, "dmg": 0, "rpm": 52, "spread": 0.2, "reload": 3.6, "kick": 4.2, "cone": 0.62, "range": 11.0, "freq": 420.0, "thump": 60.0, "body": 2.0},
}

## NOTE: these are Treyarch trademarks carried over from the browser demo.
## Fine for a private prototype; rename before distributing any build.
const PAP_NAMES := {
	"m1911": "Mustang & Sally", "olympia": "Hades", "m14": "Mnesia",
	"mp40": "The Afterburner", "pm63": "Tokyo & Rose", "ak74u": "AK-74fu2",
	"stakeout": "Raid", "m16": "Skullcrusher", "rpk": "R115 Resonator",
	"chinalake": "China Beach", "raygun": "Porter's X2 Ray Gun",
	"thundergun": "Zeus Cannon",
}

const BOX_POOL := ["olympia", "m14", "mp40", "pm63", "ak74u", "stakeout", "m16", "rpk", "chinalake", "raygun", "thundergun"]
const BOX_WEIGHT := {"raygun": 0.5, "thundergun": 0.32, "rpk": 0.8, "chinalake": 0.8}

## Costs are R4 §7's BO1 table (Tier 1, `_zombiemode_perks.gsc`), with one trap in
## it: `revive` carries the **co-op** 1500, and this game is solo-only, where canon
## charges 500. `Game.REVIVE_COST` is the authority and `interaction_system.gd`
## special-cases the row it builds from this one. The 1500 is left here rather than
## overwritten because it is the price the machine costs in the mode the port does
## not have, and deleting it would make the special case look like an arbitrary
## discount. Anything that prices a perk machine must read Game first.
## THE ROSTER IS LONGER THAN THE CAP, and that is the whole point of adding to it.
## `Game.PERK_CAP` has been 4 since Milestone 1 and has never bound: the map
## offered exactly four machines, so "four at once" described the inventory rather
## than constraining it, and `scripts/dev/checks/curves.gd::_perks` says so in as
## many words — "the cap only starts doing work the day a fifth is added. That is
## precisely when it will be forgotten." Six rows is that day. A player now gives
## something up, and the two new rows are chosen so that the thing given up is a
## real question rather than an obvious one: Mule Kick's third gun against
## Juggernog's third melee hit, Stamin-Up's legs against Speed Cola's reload.
##
## The four above are the ancestor's, verbatim (kriegsnacht.html:1265-1270,
## including the hex values and the one-line blurbs). THE TWO BELOW ARE NOT IN THE
## ANCESTOR AT ALL — `grep -i "stamin\|mule"` over kriegsnacht.html returns
## nothing — so they are designed against Black Ops rather than restored, and
## every number attached to them is the port's own.
const PERKDEF := {
	"jug": {"name": "Juggernog", "cost": 2500, "col": Color("b4302c"), "col2": Color("5e1412"), "letter": "J", "blurb": "you can take much more"},
	"speed": {"name": "Speed Cola", "cost": 3000, "col": Color("6bae3e"), "col2": Color("2e5418"), "letter": "S", "blurb": "reload twice as fast"},
	"dtap": {"name": "Double Tap", "cost": 2000, "col": Color("c98a22"), "col2": Color("5e3c08"), "letter": "D", "blurb": "fire faster, hit harder"},
	"revive": {"name": "Quick Revive", "cost": 1500, "col": Color("3e7fc0"), "col2": Color("173a60"), "letter": "Q", "blurb": "get back up once"},
	# Letter U rather than S: Speed Cola owns S, and the badge letter is the perk
	# strip's only colourblind-safe channel (see hud.gd::_refresh_perks).
	"stamin": {"name": "Stamin-Up", "cost": 2000, "col": Color("d8c33c"), "col2": Color("6b5f12"), "letter": "U", "blurb": "run further, walk quicker"},
	"mule": {"name": "Mule Kick", "cost": 4000, "col": Color("a2571f"), "col2": Color("4a2409"), "letter": "M", "blurb": "carry a third weapon"},
}

# --- what the two new perks actually do ---------------------------------------
#
# The four original effects live on `Game` (JUG_HP, SPEED_RELOAD_MULT, DTAP_*)
# because `Game` owns the accessors that read them. These two are here, next to
# the rows that name them, because their only consumer is player.gd and adding two
# more constants to the balance surface would have split one perk's definition
# across two files for no reader's benefit. If a later wave moves the roster's
# mechanics onto Game wholesale, these go with them.

## Stamin-Up. ONLY MEANINGFUL SINCE MILESTONE 1: sprint became a finite resource
## then (player.gd's SPRINT_DRAIN / SPRINT_RECOVER / SPRINT_FLOOR), and before that
## a perk that lengthened it would have multiplied an unbounded quantity by two.
##
## 0.5 on the drain takes the bar from 4.2 s to 8.4 s and 1.5 on the recovery
## refills it in 2.67 s instead of 4.0 — so the duty cycle goes from 51% to 76%,
## which is the reference's "you can keep running" without being "you never stop".
const STAMIN_DRAIN_MULT := 0.5
const STAMIN_RECOVER_MULT := 1.5

## THE 1.07 IS A BOUND, NOT A FEEL, and it is the one number in this file that
## another assertion is already watching.
##
## `Player.SPEED` is 3.15 and `Game.SPEED_SPRINT` — the fastest zombie class — is
## 3.45, and --verify's "walking is slower than the sprint class" is what keeps the
## game losable. 3.15 x 1.07 = 3.371, still under 3.45. 3.15 x 1.10 = 3.465 is over
## it, and a *walking* player who cannot be caught by anything in the game is
## exactly the failure Milestone 1's finite sprint was introduced to close — it
## would arrive back through a 2000-point purchase instead of through a constant.
## Anything above 1.0952 re-opens it; scripts/dev/checks/traps.gd asserts the
## margin rather than the value, so retuning either speed cannot silently cross it.
const STAMIN_SPEED_MULT := 1.07

## Mule Kick's third slot. player.gd's `give_gun` caps `guns` at two; this is what
## that cap reads instead.
const BASE_SLOTS := 2
const MULE_SLOTS := 3


static func spec(key: String) -> Dictionary:
	var d := DEFAULTS.duplicate()
	d.merge(TABLE[key], true)
	d["key"] = key
	return d


## Pack-a-Punch turns any of them into something meaner.
static func papify(w: Dictionary) -> Dictionary:
	var u := w.duplicate()
	u.dmg = roundi(w.dmg * 2.6)
	u.splash_dmg = round(w.splash_dmg * 2.2)
	u.mag = roundi(w.mag * 1.5)
	u.res = roundi(w.res * 1.5)
	u.reload = w.reload * 0.88
	u.name = PAP_NAMES.get(w.key, w.name + " Upgraded")
	u["pap"] = true
	# A Pack-a-Punched round punches through two targets.
	u["pierce"] = 2
	return u


## The gun a player actually carries: the immutable spec above, plus the mutable
## counters, plus the state machine's own fields. Everything from `reloading`
## downward belongs to scripts/entities/weapon.gd and nothing else may assign it —
## `reloading` included, which survives as the reload clock's public face only
## because hud.gd binds to it.
static func make_gun(key: String, pap: bool) -> Dictionary:
	var def := spec(key)
	if pap:
		def = papify(def)
	return {
		"def": def, "key": key, "pap": pap,
		"mag": int(def.mag), "res": int(def.res),
		"reloading": 0.0, "next_shot": 0.0,
		"state": WEAPON.State.IDLE, "state_t": 0.0, "state_len": 0.0,
	}


# --- perk accessors -----------------------------------------------------------
#
# Same shape as Game.reload_scale() / rpm_scale() / damage_scale(): a caller asks
# for the scale and never asks whether the perk is held, so a perk cannot be
# half-applied by a call site that only remembered one of its two effects.
# Stamin-Up has three, which is precisely why.

static func sprint_drain_scale() -> float:
	return STAMIN_DRAIN_MULT if Game.has_perk("stamin") else 1.0


static func sprint_recover_scale() -> float:
	return STAMIN_RECOVER_MULT if Game.has_perk("stamin") else 1.0


## Multiplies the player's ground speed, walking and sprinting alike. See
## STAMIN_SPEED_MULT for why the ceiling on this number is not negotiable.
static func move_speed_scale() -> float:
	return STAMIN_SPEED_MULT if Game.has_perk("stamin") else 1.0


## How many weapons the player may hold at once.
##
## A function and not a constant because it is a function of what is held. Losing
## Mule Kick cannot happen in this port — solo keeps its perks through a down, and
## `_go_down` erases `revive` alone — so nothing has to decide what becomes of the
## third gun. The day a perk can be lost, this is where that question lands.
static func gun_slots() -> int:
	return MULE_SLOTS if Game.has_perk("mule") else BASE_SLOTS


static func roll_box(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in BOX_POOL:
		total += float(BOX_WEIGHT.get(k, 1.0))
	var pick := rng.randf() * total
	for k in BOX_POOL:
		pick -= float(BOX_WEIGHT.get(k, 1.0))
		if pick <= 0.0:
			return k
	return BOX_POOL[0]
