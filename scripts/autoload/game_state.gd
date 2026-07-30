extends Node

## Round pacing, economy and perk state.
##
## The curves came from kriegsnacht.html sections 11-14 and are engine-independent
## design data. Where a value has since been corrected against Treyarch's shipped
## BO1 scripts, the old value and the reason are recorded inline — this file is the
## balance surface, so it should explain itself.
##
## State here is split in two. RUN STATE is everything a single run owns and
## `reset_run()` clears; it is reproducible from `Rng.seed_value`. PROFILE STATE
## outlives the run. Keeping the boundary explicit is what makes a run-based mode
## cheap to add later — a run is a seed plus the block below it.

signal points_changed(points: int)
signal round_changed(round_no: int, is_dog_round: bool)
signal state_changed(state: String)
signal toast(text: String)

enum { STATE_TITLE, STATE_PLAY, STATE_PAUSE, STATE_OVER }

const START_POINTS := 500
const MAX_ALIVE := 24
const INTERMISSION := 6.5
const FIRST_ROUND_DELAY := 2.6

## Hounds arrive in packs and are much faster; the full 24 cap turns a dog round
## into an unsurvivable wall rather than a change of pace.
const MAX_ALIVE_DOGS := 8

# points — verified canon (body 60 / head 100 / melee 130) and left unchanged
const PTS_HIT := 10
const PTS_KILL := 60
const PTS_HEADSHOT := 100
const PTS_MELEE_BONUS := 70
const PTS_REBUILD := 10
const PTS_NUKE := 400
const PTS_CARPENTER := 200

## What a SHOT kill pays while Insta-Kill is up. Not a knife kill — that keeps the
## full 130, because BO1 zeroes the hit-location bonus and not the melee one. Read
## by kill_points() and by nothing else; the sentence that used to be here said
## "rather than the full headshot/melee payout", which is half wrong and is exactly
## the reading the death handler was written from.
const PTS_INSTAKILL := 50

# perk effects
## Was 250. BO1's Juggernog is 160 (the upgraded BO3 version is 250, which is
## where the widely-repeated "5 hits" figure comes from — a different era).
## With 60 melee damage this gives the canon 2 hits unperked, 3 with Jug.
const JUG_HP := 160.0
const BASE_HP := 100.0
const SPEED_RELOAD_MULT := 0.5
const DTAP_RPM_MULT := 1.34
const DTAP_DMG_MULT := 1.15
const DOWNED_TIME := 7.0

## Solo Quick Revive is cheap, available from round 1 without power, and grants
## exactly one self-revive per purchase. The machine leaves after three buys.
const REVIVE_COST := 500
const REVIVE_MAX_USES := 3

## Canon allows four perks at once in this era.
const PERK_CAP := 4

## Discrete movement classes, rolled per spawn. The old model was one continuous
## speed that saturated at 3.45 m/s from round 16 and never changed again — which,
## against a 4.88 m/s sprint, meant no regular zombie could ever catch the player.
## Escalation now comes from the *mixture* shifting toward the faster classes.
const SPEED_WALK := 1.05
const SPEED_RUN := 2.20
const SPEED_SPRINT := 3.45

## Cumulative weights per class by round band: [walk, run, sprint].
const SPEED_MIX := [
	{"to": 4, "w": [1.00, 0.00, 0.00]},
	{"to": 8, "w": [0.70, 0.30, 0.00]},
	{"to": 12, "w": [0.30, 0.60, 0.10]},
	{"to": 16, "w": [0.10, 0.55, 0.35]},
	{"to": 20, "w": [0.00, 0.40, 0.60]},
	{"to": 9999, "w": [0.00, 0.20, 0.80]},
]

## A23, from kriegsnacht.html:2334 — `z.spd * (G.round>=14 && z.type==='z' ? 1.06 : 1)`.
## Flat, not compounding: the ancestor re-evaluates it every frame against the
## current round, so it is one 6% step at round 14 and nothing afterwards. Regular
## zombies only, exactly as there — hounds already top out near 6.10 m/s against a
## 4.88 m/s sprint and must not be scaled (R4, §1.4 correction 3).
const LATE_SPEED_ROUND := 14
const LATE_SPEED_MULT := 1.06

# --- RUN STATE — cleared by reset_run(), reproducible from the run seed --------

var state := STATE_TITLE
var round_no := 0
var points := START_POINTS
var kills := 0
var headshots := 0
var perks := {}
var power_on := false

var insta_kill := 0.0
var dbl_points := 0.0
var drop_count := 0
var box_uses := 0
var box_spot := 0

## Set only for the duration of a Nuke's sweep through the horde, so the deaths it
## causes can be told apart from the ones the player shot. Read by add_points() and
## by try_drop(), which are the two things a death is worth — a body the Nuke
## deleted pays neither. A flag rather than a fourth argument on `Zombie.died`: that
## signature is fixed by the wave contract, and every listener would have to carry a
## value only one of them reads.
var nuke_clearing := false

## The Monkey Bomb's lure, and the one thing the whole throwable does.
##
## `Vector3.INF` means "no lure", so this is one property rather than a position
## plus a boolean somebody can forget to clear. Written only by
## `scripts/systems/throwables.gd`; read by `zombie.gd::_goal_point` and by the
## round director when it re-solves the flow field.
##
## It lives here rather than as a static on throwables.gd because the consumer had
## already been written against `Game.lure_position` — and the two halves were
## published in different places, so `"lure_position" in Game` was false, every
## zombie fell back to the player, and the headline throwable of this milestone did
## nothing at all. Neither side was wrong on its own; there was simply no contract
## either of them could see.
var lure_position := Vector3.INF

## Set only for the duration of an electric trap's kill sweep (traps.gd).
##
## SEPARATE FROM `nuke_clearing`, and the two are not interchangeable. Both gate
## the payout — canon awards nothing for a trap kill, which is the whole of what
## stops a 1000-point switch out-earning itself — but the Nuke also suppresses the
## DROP roll, because the ancestor's Nuke never reaches `zombieDamage` at all
## (html:2411-2419) and therefore never reaches `maybeDrop` either. A trap does
## reach it: canon's drop roll lives in the zombie's own death callback and does
## not care what killed it. So this flag is read by `add_points()` and deliberately
## NOT by `try_drop()`.
var trap_clearing := false

## Power-ups are earned by points, not by a kill counter (see next_drop_at).
var points_earned := 0
var next_drop_at := 2000
var drop_index := 0

## A threshold crossing that could not be paid out — see try_drop().
var drop_pending := false

var revives_left := 0
var revive_uses := 0

## Rolled at the start of each run and after each dog round.
var next_dog_round := 5

# --- PROFILE STATE — outlives the run ----------------------------------------

## preload rather than the global class name: a freshly added script is not in the
## class registry until the editor rescans, and a headless run has no editor.
const SAVE_STORE := preload("res://scripts/autoload/save_store.gd")

var profile := {
	"best_round": 0,
	"best_points": 0,
	"runs": 0,
}


## Read once, at boot. The profile is three integers, so there is no reason to
## re-read it and no reason to cache anything the store hands back.
func _ready() -> void:
	_load_profile()
	# Checkpointing at each round boundary as well as on death is not
	# belt-and-braces. record_run() fires only when the player is killed, and the
	# ordinary way a browser game ends is the tab closing — so on its own it means
	# a player who reaches round 20 and walks away keeps nothing. That is the same
	# lost write §1.4b is about, arriving by a different route.
	round_changed.connect(_on_round_changed)


## Everything the store returns is untrusted. On web the profile lives in
## localStorage, which is one devtools line away from hand-edited, and a truncated
## write parses cleanly into a shorter dictionary. So copy key by key with a type
## check per key: a bad blob can then neither introduce a key nor change the type
## of one, and the defaults above survive anything that fails.
func _load_profile() -> void:
	var saved: Dictionary = SAVE_STORE.restore()
	for key: String in profile.keys():
		var v: Variant = saved.get(key)
		# JSON gives back int for whole numbers and float for anything edited to
		# carry a decimal point; both are accepted, everything else is dropped.
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			# Clamped at zero because a negative best round would render, and sort,
			# as a real result.
			profile[key] = maxi(0, int(v))


## main.gd emits round_changed from _begin_round() *after* round_no is
## incremented, so `r` is the round just reached. Writes only when a number
## actually moved, which means replaying rounds 1-10 on a profile that already
## reads 20 costs no writes at all.
func _on_round_changed(r: int, _is_dog: bool) -> void:
	var best: int = profile.best_round
	var bank: int = profile.best_points
	if r <= best and points <= bank:
		return
	profile.best_round = maxi(best, r)
	profile.best_points = maxi(bank, points)
	# A refused write is reported once, from record_run(). Repeating it at every
	# round boundary would spam a console the player in incognito cannot act on.
	SAVE_STORE.save(profile)


func reset_run() -> void:
	round_no = 0
	points = START_POINTS
	kills = 0
	headshots = 0
	perks.clear()
	power_on = false
	insta_kill = 0.0
	dbl_points = 0.0
	drop_count = 0
	nuke_clearing = false
	trap_clearing = false
	lure_position = Vector3.INF
	box_uses = 0
	box_spot = 0
	points_earned = 0
	next_drop_at = 2000
	drop_index = 0
	drop_pending = false
	revives_left = 0
	revive_uses = 0
	next_dog_round = Rng.randi_range(Rng.ROUNDS, 5, 7)
	points_changed.emit(points)


## Kept so existing call sites continue to work.
func reset() -> void:
	reset_run()


func record_run() -> void:
	profile.best_round = maxi(profile.best_round, round_no)
	profile.best_points = maxi(profile.best_points, points)
	profile.runs += 1
	# `runs` only ever moves here, so this write happens even when the round
	# checkpoint already stored the same best_round. It is also the one place a
	# refused write is reported: on web every write is a synchronous localStorage
	# commit on the main thread, and the death screen is the only moment at which
	# telling the player is worth anything.
	if not SAVE_STORE.save(profile):
		# Incognito and third-party-cookie-blocked iframes refuse storage outright.
		# Losing the record is not a reason to interrupt the death screen.
		push_warning("profile save unavailable — storage refused the write")


## The one place the run's state moves, and therefore the one writer of
## `get_tree().paused`. Pause used to be a flag every `_process` re-read and
## early-returned on, which leaked by construction: the HUD's timers kept
## decaying, and Milestone 2's tweens, particle emitters and hand-sampled curves
## had no early return to add one to. A node that must keep running while paused
## says so with its own `process_mode` (the HUD, the player's input, Sfx) instead
## of every other node in the game having to remember it might not be running.
##
## STATE_TITLE does NOT pause: the shader warm-up pass runs behind the title card
## and is the only free moment it has, and `--shot` and `--autostart` both start
## from there.
##
## STATE_OVER does. Nothing behind the death screen is worth simulating — the
## overlay is 92% opaque — and it is the one state a player can leave running for
## an hour by walking away from the tab, which is exactly when a still-emitting
## particle pool costs the most. `restart()` clears the flag itself, because the
## incoming scene's `_ready` is what would otherwise have to.
##
## Set before the signal so every listener sees a tree that already agrees with
## the state it is being told about.
func set_state(s: int) -> void:
	state = s
	get_tree().paused = s == STATE_PAUSE or s == STATE_OVER
	state_changed.emit(["title", "play", "pause", "over"][s])


## Every point the player earns passes through here — and so does the one case in
## which they earn nothing.
##
## A Nuke pays its flat 400 and the bodies it deletes pay nothing. The ancestor is
## explicit: html:2411-2419 sets `z.state='dying'` directly inside `grabPowerup`, so
## the sweep never reaches `zombieDamage` and therefore never reaches `addPoints` at
## all; canon lands in the same place from the other direction, killing with no
## attacker credited. The port routes the sweep through `Zombie.take_damage`, which
## is right — that is what erases the horde from the director's live list and starts
## the death animation — and is exactly why the payout has to be suppressed
## explicitly. Before this, a round-10 Nuke on a full horde paid 400 + 24x60 = 1,840
## points, more than the round it was picked up in, and fed every one of them to the
## drop threshold, so Nukes were quietly buying the next Nuke.
##
## The suppression is here rather than at the kill site because there are three
## payout call sites and a synchronous sweep drives whichever one the death handler
## happens to use today. A guard at one of them is a guard the next one walks past.
func add_points(n: int) -> void:
	if nuke_clearing or trap_clearing:
		return
	var mult := 2 if dbl_points > 0.0 else 1
	var gained := n * mult
	points += gained
	# Only positive income counts toward the drop threshold.
	if gained > 0:
		points_earned += gained
	points_changed.emit(points)


## What one death is worth, in one place, because the rule has two exceptions that
## interact and both of them used to live at the call site.
##
## R4 §3 is Tier 1 and decides the Insta-Kill case. WaW doubled the whole payout;
## BO1 moved the multiply onto the *bonus* only, and an Insta-Kill bullet death is
## dealt as `MOD_UNKNOWN`, which carries no hit-location bonus — so a gun kill under
## Insta-Kill pays the bare 50. A knife kill is `MOD_MELEE`, keeps its +80 and still
## totals 130; R4 says so in as many words. The ancestor disagrees on both counts —
## html:2233 is `pts = Math.max(pts,100)` and html:2658 adds its 70 on top, making a
## knife kill under Insta-Kill worth 170 there — and the reference wins. Insta-Kill
## is a survival tool, not an economy: it can only ever pay less than the shot it
## replaced.
##
## Canon's decomposition is 50 base + 50 head / +80 melee; the port's is 60/100/130
## as flat totals. Same three numbers, and the flat form is what the ancestor and
## every other file here already speak.
func kill_points(headshot: bool, by_melee: bool) -> int:
	# Tested before the head case rather than added to it. Canon's melee bonus is a
	# `mod` bonus and the head bonus a `hit_location` one, and
	# `player_add_points_kill_bonus` returns one or the other — they do not stack,
	# even in a build where a knife could reach a head. This one cannot: player.gd
	# damages one notch under the threshold, exactly as html:2657 does.
	if by_melee:
		return PTS_KILL + PTS_MELEE_BONUS
	if insta_kill > 0.0:
		return PTS_INSTAKILL
	return PTS_HEADSHOT if headshot else PTS_KILL


func spend(n: int) -> bool:
	if points < n:
		return false
	points -= n
	points_changed.emit(points)
	return true


func has_perk(k: String) -> bool:
	return perks.has(k)


func perk_count() -> int:
	return perks.size()


func can_take_perk(k: String) -> bool:
	return not has_perk(k) and perks.size() < PERK_CAP


func max_health() -> float:
	return JUG_HP if has_perk("jug") else BASE_HP


func reload_scale() -> float:
	return SPEED_RELOAD_MULT if has_perk("speed") else 1.0


func rpm_scale() -> float:
	return DTAP_RPM_MULT if has_perk("dtap") else 1.0


func damage_scale() -> float:
	return DTAP_DMG_MULT if has_perk("dtap") else 1.0


func max_alive(r := -1) -> int:
	if r < 0:
		r = round_no
	return MAX_ALIVE_DOGS if is_dog_round(r) else MAX_ALIVE


# --- round curves ------------------------------------------------------------

## Dog rounds are no longer every fifth round. Canon rolls the first at 5-7 and
## each subsequent one 4-5 rounds later, so their arrival cannot be counted on.
func is_dog_round(r := -1) -> bool:
	if r < 0:
		r = round_no
	return r == next_dog_round


func advance_dog_round() -> void:
	next_dog_round += Rng.randi_range(Rng.ROUNDS, 4, 5)


## 150 to start, +100 a round through round 9, then compounding 10%.
## Verified against canon and deliberately unchanged — there is no health cap in
## any title of this era, so none is imposed here.
func zombie_hp(r := -1) -> float:
	if r < 0:
		r = round_no
	var hp := 150.0
	for i in range(2, r + 1):
		hp = hp + 100.0 if i <= 9 else round(hp * 1.1)
	return hp


## Rolls one of the three discrete movement classes for a spawn.
func roll_speed_class(r := -1) -> float:
	if r < 0:
		r = round_no
	var w: Array = SPEED_MIX[SPEED_MIX.size() - 1].w
	for band in SPEED_MIX:
		if r <= band.to:
			w = band.w
			break
	var pick := Rng.randf(Rng.AI)
	if pick < w[0]:
		return SPEED_WALK
	if pick < w[0] + w[1]:
		return SPEED_RUN
	return SPEED_SPRINT


## A23's late-round nudge, kept out of roll_speed_class() rather than folded into
## it for two reasons: that function must keep returning one of the three named
## classes by value (the mixture test compares its result against SPEED_SPRINT
## directly), and it is called for hounds and crawlers too, which the ancestor
## excludes. Multiply a *regular* zombie's speed by this at spawn.
func late_speed_scale(r := -1) -> float:
	if r < 0:
		r = round_no
	return LATE_SPEED_MULT if r >= LATE_SPEED_ROUND else 1.0


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
	return maxf(0.22, base - r * 0.045) * Rng.randf_range(Rng.SPAWN, 0.7, 1.25)


## Crawlers start showing up in round 6.
func crawler_chance(r := -1) -> float:
	if r < 0:
		r = round_no
	return 0.09 if r >= 6 else 0.0


## Power-ups are driven by lifetime points earned, not a kill counter. The old
## counter made drops arrive *earlier* the longer a run went, because it was
## never reset. The threshold grows 14% per drop and never resets.
##
## The new threshold is measured from `points_earned` and not from the threshold
## just crossed, which is R4 §2's `score_to_drop = curr_total_score + increment`
## verbatim (Tier 1, `t5/_zombiemode_powerups.gsc:526-550`). The difference is the
## overshoot — the payout that carried the counter past the line, up to 130 points —
## and adding to the old threshold instead banks every one of those, so the lead
## accumulates over a run instead of being discarded at each crossing. It is about
## 1% over twenty drops, which is small; it is also free to be exactly right.
func check_points_drop() -> bool:
	if points_earned < next_drop_at:
		return false
	drop_index += 1
	next_drop_at = points_earned + int(2000.0 * pow(1.14, drop_index))
	return true


## The per-round power-up cap, and the whole drop decision, in one place.
##
## This is here rather than inline in the round director because the rule was
## written out twice — once in the director and once again in the balance sim — and
## the copies drifted the instant one of them was fixed. The missing per-round reset
## (html:2862, `G.dropsThisRound=0` inside startRound) was corrected in the director
## and the sim went on faithfully modelling four drops a RUN while the game paid four
## a ROUND. A sim that disagrees with the game is worse than no sim, so the rule the
## two have to agree about lives where both of them read it.
const DROP_CAP := 4


## Called at the top of every round. The cap is meaningless without it.
func begin_round_drops() -> void:
	drop_count = 0


## `lucky` is the flat per-death roll, made by the caller and passed in already
## resolved — deliberately, because the caller owns the Rng stream and that draw has
## to happen on every death whether or not it is used. Folding it in here as a
## short-circuited `or` would skip the draw whenever the points threshold had already
## fired, and a skipped draw desynchronises every seeded run after it.
##
## A threshold crossing is LATCHED rather than spent where it happens. Canon splits
## the two halves across two functions: `watch_for_drop()` compounds the threshold
## and sets `zombie_drop_item = 1`, and only `powerup_drop()` clears it — after
## returning early on the per-round cap, so a crossing that lands in a round already
## holding four power-ups survives into the next round. Spending it here instead
## compounded the threshold and threw the entitlement away, which is strictly worse
## than never having crossed the line. The cap is not a corner case: on the committed
## sim seed the `drops` column reads 4 in eight of twenty-five rounds.
##
## One flag and not a queue, because canon holds one boolean — two crossings inside
## a capped round still owe exactly one drop.
func try_drop(lucky: bool) -> bool:
	if check_points_drop():
		drop_pending = true
	# A body deleted by a Nuke cannot hand over a power-up, for the same reason it
	# cannot pay points. The ancestor's drop roll lives inside `zombieDamage`
	# (html:2237, `maybeDrop(z.x,z.y)` in the kill branch) and its Nuke never calls
	# `zombieDamage` at all — html:2411-2419 sets `z.state='dying'` inline. So a
	# nuked body rolls nothing there, and suppressing the payout while leaving the
	# roll would keep the exact thing the payout fix was for: a 3% roll over 24
	# bodies is a coin flip per late-round Nuke, and one of the seven entries in the
	# bag is another Nuke.
	#
	# AFTER the latch above, not before it, so the Nuke's own 400 can still carry the
	# threshold past its line — that crossing is owed to the next real death, which
	# is what canon's `zombie_drop_item` does with any crossing it cannot pay out.
	#
	# Here rather than at the call site so the caller still makes its DROPS draw:
	# that is the whole reason `lucky` arrives already resolved.
	if nuke_clearing:
		return false
	if drop_count >= DROP_CAP:
		return false
	if not (drop_pending or lucky):
		return false
	drop_pending = false
	drop_count += 1
	return true


func tick_timers(dt: float) -> void:
	if insta_kill > 0.0:
		insta_kill = maxf(0.0, insta_kill - dt)
	if dbl_points > 0.0:
		dbl_points = maxf(0.0, dbl_points - dt)
