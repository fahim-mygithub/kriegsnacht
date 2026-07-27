extends Node

## Round pacing, economy and perk state. Every curve here is copied from
## kriegsnacht.html sections 11-14 — this is the actual game design, and it is
## engine-independent, so it ports across unchanged.

signal points_changed(points: int)
signal round_changed(round_no: int, is_dog_round: bool)
signal state_changed(state: String)
signal toast(text: String)

enum { STATE_TITLE, STATE_PLAY, STATE_PAUSE, STATE_OVER }

const START_POINTS := 500
const MAX_ALIVE := 24
const INTERMISSION := 6.5
const FIRST_ROUND_DELAY := 2.6

# points
const PTS_HIT := 10
const PTS_KILL := 60
const PTS_HEADSHOT := 100
const PTS_MELEE_BONUS := 70
const PTS_REBUILD := 10
const PTS_NUKE := 400
const PTS_CARPENTER := 200

# perk effects
const JUG_HP := 250.0
const BASE_HP := 100.0
const SPEED_RELOAD_MULT := 0.5
const DTAP_RPM_MULT := 1.34
const DTAP_DMG_MULT := 1.15
const DOWNED_TIME := 7.0

var state := STATE_TITLE
var round_no := 0
var points := START_POINTS
var kills := 0
var headshots := 0
var perks := {}
var power_on := false

var insta_kill := 0.0
var dbl_points := 0.0
var drop_tick := 0
var next_drop_at := 6
var drop_count := 0

var box_uses := 0
var box_spot := 0

var rng := RandomNumberGenerator.new()


func reset() -> void:
	round_no = 0
	points = START_POINTS
	kills = 0
	headshots = 0
	perks.clear()
	power_on = false
	insta_kill = 0.0
	dbl_points = 0.0
	drop_tick = 0
	next_drop_at = 6
	drop_count = 0
	box_uses = 0
	box_spot = 0
	rng.randomize()
	points_changed.emit(points)


func set_state(s: int) -> void:
	state = s
	state_changed.emit(["title", "play", "pause", "over"][s])


func add_points(n: int) -> void:
	var mult := 2 if dbl_points > 0.0 else 1
	points += n * mult
	points_changed.emit(points)


func spend(n: int) -> bool:
	if points < n:
		return false
	points -= n
	points_changed.emit(points)
	return true


func has_perk(k: String) -> bool:
	return perks.has(k)


func max_health() -> float:
	return JUG_HP if has_perk("jug") else BASE_HP


func reload_scale() -> float:
	return SPEED_RELOAD_MULT if has_perk("speed") else 1.0


func rpm_scale() -> float:
	return DTAP_RPM_MULT if has_perk("dtap") else 1.0


func damage_scale() -> float:
	return DTAP_DMG_MULT if has_perk("dtap") else 1.0


# --- round curves ------------------------------------------------------------

func is_dog_round(r := -1) -> bool:
	if r < 0:
		r = round_no
	return r >= 5 and r % 5 == 0


## 150 to start, +100 a round through round 9, then compounding 10%.
func zombie_hp(r := -1) -> float:
	if r < 0:
		r = round_no
	var hp := 150.0
	for i in range(2, r + 1):
		hp = hp + 100.0 if i <= 9 else round(hp * 1.1)
	return hp


func zombie_speed(r := -1) -> float:
	if r < 0:
		r = round_no
	return minf(1.05 + r * 0.155, 3.45)


func zombie_count(r := -1) -> int:
	if r < 0:
		r = round_no
	if is_dog_round(r):
		return mini(30, roundi(5.0 + r * 0.85))
	return roundi(6.0 + (r - 1) * 3.2 + pow(r, 1.6) * 0.28)


func spawn_interval(r := -1) -> float:
	if r < 0:
		r = round_no
	var base := 0.9 if is_dog_round(r) else 1.5
	return maxf(0.22, base - r * 0.045) * rng.randf_range(0.7, 1.25)


## Crawlers start showing up in round 6.
func crawler_chance(r := -1) -> float:
	if r < 0:
		r = round_no
	return 0.09 if r >= 6 else 0.0


func tick_timers(dt: float) -> void:
	if insta_kill > 0.0:
		insta_kill = maxf(0.0, insta_kill - dt)
	if dbl_points > 0.0:
		dbl_points = maxf(0.0, dbl_points - dt)
