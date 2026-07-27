class_name Weapons
extends RefCounted

## Weapon table ported verbatim from kriegsnacht.html section 4.
## Every number is engine-independent design data, so it transfers unchanged.

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

const PERKDEF := {
	"jug": {"name": "Juggernog", "cost": 2500, "col": Color("b4302c"), "col2": Color("5e1412"), "letter": "J", "blurb": "you can take much more"},
	"speed": {"name": "Speed Cola", "cost": 3000, "col": Color("6bae3e"), "col2": Color("2e5418"), "letter": "S", "blurb": "reload twice as fast"},
	"dtap": {"name": "Double Tap", "cost": 2000, "col": Color("c98a22"), "col2": Color("5e3c08"), "letter": "D", "blurb": "fire faster, hit harder"},
	"revive": {"name": "Quick Revive", "cost": 1500, "col": Color("3e7fc0"), "col2": Color("173a60"), "letter": "Q", "blurb": "get back up once"},
}


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


static func make_gun(key: String, pap: bool) -> Dictionary:
	var def := spec(key)
	if pap:
		def = papify(def)
	return {
		"def": def, "key": key, "pap": pap,
		"mag": int(def.mag), "res": int(def.res),
		"reloading": 0.0, "next_shot": 0.0,
	}


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
