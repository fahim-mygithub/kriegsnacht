extends RefCounted

## The canon curves, pinned so a refactor cannot move them in silence.
##
## **Every number here is justified, not snapshotted.** Each block says where its
## value comes from: a line of kriegsnacht.html, or the canon correction that
## deliberately departs from it and why. That distinction is the whole point — a
## test that records what the code currently does catches typos and endorses bugs,
## and this project has already shipped one balance value that was wrong in the
## ancestor and faithfully carried across.
##
## Where a number could NOT be justified it is deliberately left unpinned and the
## structure around it is pinned instead. The SPEED_MIX weights are the main case:
## they are neither the ancestor's (which had no classes at all) nor canon's
## (`set_run_speed`, which is 100% sprinters from round 10 — far harsher), so what
## is asserted is that the bands are a well-formed distribution that escalates,
## not that any particular weight is right.
##
## Called from scripts/dev/verify.gd. Nothing here needs a rendered frame, a
## pointer, or a scene — the curves are pure functions of the round number, which
## is exactly why they are worth pinning at this cost.

static func run(v: Verify, main: Node3D) -> void:
	_health(v)
	_counts(v)
	_speed_mix(v)
	_spawn_interval(v)
	_crawlers(v)
	_economy(v)
	_drops(v, main)
	_perks(v, main)
	_dog_rounds(v)
	_melee(v)


# --- health ------------------------------------------------------------------

## `let hp=150; for(let r=2;r<=G.round;r++) hp = r<=9 ? hp+100 : Math.round(hp*1.1)`
## — kriegsnacht.html:2178-2182, and R4 §4 confirms the same recurrence in
## Treyarch's shipped scripts with **no cap of any kind** (health runs to 32-bit
## overflow at round 163). The port is verbatim.
##
## The recurrence is asserted rather than a table of thirty numbers, because the
## recurrence is the thing the ancestor actually writes down; the anchors below it
## exist to catch the one bug the recurrence cannot see — an off-by-one in the
## `<= 9` boundary, which moves every value from round 10 up and nothing before it.
static func _health(v: Verify) -> void:
	var hp := 150.0
	var ok := v.near(Game.zombie_hp(1), 150.0)
	var worst := ""
	for r in range(2, 31):
		hp = hp + 100.0 if r <= 9 else round(hp * 1.1)
		if not v.near(Game.zombie_hp(r), hp):
			ok = false
			worst = "round %d: %.0f, recurrence says %.0f" % [r, Game.zombie_hp(r), hp]
	v.check("zombie health follows the ancestor's recurrence for rounds 1-30", ok, worst)

	# The boundary itself. 950 is the last additive round and 1045 the first
	# multiplicative one, so `i <= 9` reading `i < 9` shows up here and nowhere else.
	v.check("the +100 / x1.1 boundary sits between rounds 9 and 10",
		v.near(Game.zombie_hp(9), 950.0) and v.near(Game.zombie_hp(10), 1045.0),
		"r9=%.0f r10=%.0f" % [Game.zombie_hp(9), Game.zombie_hp(10)])

	# R4 §4, Tier 1: there is no health cap in any title of this era. A cap is the
	# single most tempting "fix" for late-round difficulty and it is not canon.
	v.check("health compounds past round 30 with no ceiling",
		Game.zombie_hp(60) > Game.zombie_hp(59) and Game.zombie_hp(120) > Game.zombie_hp(119))


# --- counts ------------------------------------------------------------------

## `Math.round(6 + (r-1)*3.2 + Math.pow(r,1.6)*0.28)`, dog rounds
## `Math.min(30, Math.round(5 + r*0.85))` — kriegsnacht.html:2186-2190, verbatim.
##
## The anchors are the formula evaluated by hand at five points; they are here so
## that someone who changes 3.2 or 1.6 has to change a number a reader can check
## against html:2189 rather than a number that silently follows the code.
static func _counts(v: Verify) -> void:
	# Rounds where the dog roll cannot interfere: is_dog_round() reads run state,
	# and the first hound round is somewhere in 5-7, so the anchors avoid 5-7 and
	# every multiple that a later roll could land on. Pinning next_dog_round to a
	# value outside the sample makes that independent of the seed.
	var was := Game.next_dog_round
	Game.next_dog_round = 9999
	var anchors := {1: 6, 2: 10, 9: 41, 10: 46, 20: 101, 30: 163}
	var wrong := ""
	for r: int in anchors:
		var want: int = anchors[r]
		if Game.zombie_count(r) != want:
			wrong += "r%d=%d(want %d) " % [r, Game.zombie_count(r), want]
	v.check("the zombie count matches the ancestor's curve at every anchor",
		wrong.is_empty(), wrong)

	var rising := true
	for r in range(2, 31):
		if Game.zombie_count(r) <= Game.zombie_count(r - 1):
			rising = false
	v.check("the count rises strictly every round from 1 to 30", rising)

	# `Math.min(30, ...)`. The cap binds from round 30 (5 + 30*0.85 = 30.5 -> 31),
	# so a run that reaches it must not keep growing the pack.
	Game.next_dog_round = 30
	var at30 := Game.zombie_count(30)
	Game.next_dog_round = 40
	var at40 := Game.zombie_count(40)
	Game.next_dog_round = 10
	var at10 := Game.zombie_count(10)
	v.check("a hound pack is capped at 30 and is smaller than the walker count",
		at30 == 30 and at40 == 30 and at10 == 14,
		"r10=%d r30=%d r40=%d" % [at10, at30, at40])
	Game.next_dog_round = was

	# html:2248 `const maxAlive=24` and :2880 `alive<24`. The dog cap has no
	# ancestor and no canon source — it is this port's own correction, recorded in
	# game_state.gd — so only the relationship between the two is pinned.
	v.check("the concurrent cap is the ancestor's 24, and hounds are capped lower",
		Game.MAX_ALIVE == 24 and Game.MAX_ALIVE_DOGS < Game.MAX_ALIVE,
		"alive=%d dogs=%d" % [Game.MAX_ALIVE, Game.MAX_ALIVE_DOGS])


# --- the speed mixture -------------------------------------------------------

## THE HONEST ONE. These weights have no source.
##
## The ancestor has no classes at all — `zombieSpeed()` is one continuous curve
## that saturates at 3.45 m/s from round 16 (html:2183-2185) — and canon's
## `set_run_speed()` (R4 §10, Tier 1) rolls three classes with a mixture that is
## **100% sprinters from round 10**, which is far harsher than the bands below.
## The port's bands are therefore invented, sitting between the two, and pinning
## any individual weight would be recording an opinion as a fact.
##
## What IS assertable is that the table is a well-formed distribution that
## escalates monotonically, because every one of those properties is a bug if it
## fails: a band that does not sum to 1 silently biases toward whichever class the
## remainder falls into, and a non-monotonic band makes a later round easier.
static func _speed_mix(v: Verify) -> void:
	var bad := ""
	var last_to := -1
	var prev_walk := 2.0
	var prev_sprint := -1.0
	for band: Dictionary in Game.SPEED_MIX:
		var w: Array = band.w
		var to: int = band.to
		var sum := 0.0
		for x: float in w:
			sum += x
			if x < 0.0:
				bad += "negative weight in band %d; " % to
		if not v.near(sum, 1.0):
			bad += "band %d sums to %.3f; " % [to, sum]
		if to <= last_to:
			bad += "band %d is out of order; " % to
		var walk: float = w[0]
		var sprint: float = w[2]
		if walk > prev_walk:
			bad += "band %d has more walkers than the band before it; " % to
		if sprint < prev_sprint:
			bad += "band %d has fewer sprinters than the band before it; " % to
		last_to = to
		prev_walk = walk
		prev_sprint = sprint
	v.check("every speed band is a distribution and the mixture only ever escalates",
		bad.is_empty(), bad)

	# The last band has to swallow every remaining round or roll_speed_class falls
	# through its loop and silently uses whatever `w` was initialised to.
	var last: Dictionary = Game.SPEED_MIX[Game.SPEED_MIX.size() - 1]
	v.check("the final speed band covers every round a run can reach",
		int(last.to) >= 9999, "last band ends at %d" % int(last.to))

	# The two endpoints that DO have a source. Canon's round 1 is 100% walkers
	# (R4 §10 table) and the port agrees; canon has no walkers at all from round 6
	# and the port holds them until round 17, which is the deliberate softening.
	# Asserted as "walkers are gone by the late game" rather than at a specific
	# round, so retuning the bands does not break a test that is really about the
	# shape.
	var early: Array = Game.SPEED_MIX[0].w
	v.check("round 1 is walkers only, exactly as canon",
		v.near(early[0], 1.0), "walk weight %.2f" % float(early[0]))
	v.check("walkers are extinct and sprinters dominate by the last band",
		v.near(float(last.w[0]), 0.0) and float(last.w[2]) > 0.5,
		str(last.w))

	# The three class speeds must stay ordered and distinct, or the mixture is a
	# distribution over one behaviour wearing three names.
	v.check("the three movement classes are ordered and distinct",
		Game.SPEED_WALK < Game.SPEED_RUN and Game.SPEED_RUN < Game.SPEED_SPRINT
			and Game.SPEED_RUN - Game.SPEED_WALK > 0.5,
		"%.2f %.2f %.2f" % [Game.SPEED_WALK, Game.SPEED_RUN, Game.SPEED_SPRINT])


# --- spawn interval ----------------------------------------------------------

## `Math.max(0.22, (G.dogRound?0.9:1.5) - G.round*0.045)` (html:2879) scaled by
## `rnd(1.25,0.7)` (html:2881), where `rnd(a,b)` is `b + Math.random()*(a-b)`
## (html:377) — so the jitter band is [0.7, 1.25) and the port's
## `randf_range(0.7, 1.25)` is the same interval.
##
## Sampled rather than reasoned about, because the deterministic base and the
## random scale are multiplied in one expression and it is the *product* that has
## to stay inside the band.
static func _spawn_interval(v: Verify) -> void:
	var was := Game.next_dog_round
	Game.next_dog_round = 9999
	var out := ""
	for r: int in [1, 5, 12, 20, 29, 40]:
		var base := maxf(0.22, 1.5 - float(r) * 0.045)
		for i in 200:
			var got := Game.spawn_interval(r)
			if got < base * 0.7 - 0.0001 or got > base * 1.25 + 0.0001:
				out = "round %d gave %.4f outside [%.4f, %.4f]" % [r, got, base * 0.7, base * 1.25]
	v.check("every spawn interval lands inside the ancestor's jitter band", out.is_empty(), out)

	# 0.22 is a floor, not an asymptote: (1.5 - 0.22) / 0.045 = 28.4, so it binds
	# from round 29 and the interval must stop shrinking there. Without the clamp
	# the base goes negative around round 34 and every spawn lands on one frame.
	Game.next_dog_round = 9999
	var floor_hit := true
	for i in 200:
		if Game.spawn_interval(40) > 0.22 * 1.25 + 0.0001:
			floor_hit = false
	v.check("the interval floors at 0.22 s rather than running negative", floor_hit)

	# html:2879's dog branch starts at 0.9 against 1.5, so hounds arrive faster at
	# every round — which, with the lower concurrent cap, is what makes a dog round
	# a different rhythm rather than simply a smaller one.
	Game.next_dog_round = 12
	var dog_mean := 0.0
	var walk_mean := 0.0
	for i in 400:
		dog_mean += Game.spawn_interval(12)
	Game.next_dog_round = 9999
	for i in 400:
		walk_mean += Game.spawn_interval(12)
	v.check("hounds spawn faster than walkers at the same round",
		dog_mean < walk_mean * 0.75,
		"dog %.3f walker %.3f" % [dog_mean / 400.0, walk_mean / 400.0])
	Game.next_dog_round = was


# --- crawlers ----------------------------------------------------------------

## `const isCrawler = !isDog && G.round>=6 && Math.random()<0.09` (html:2205).
## The `!isDog` half of that lives at the call site — `round_director.gd`'s
## `spawn_one()` tests the dog round first and never reaches the crawler roll — so
## this function is only the other two clauses and must not acquire the third.
static func _crawlers(v: Verify) -> void:
	var early := true
	for r in range(1, 6):
		if not v.near(Game.crawler_chance(r), 0.0):
			early = false
	var late := true
	for r in range(6, 31):
		if not v.near(Game.crawler_chance(r), 0.09):
			late = false
	v.check("crawlers are absent before round 6 and a flat 9% after it",
		early and late,
		"r5=%.3f r6=%.3f r30=%.3f" % [Game.crawler_chance(5), Game.crawler_chance(6),
			Game.crawler_chance(30)])


# --- the points table --------------------------------------------------------

## `addPoints(10)` on a non-lethal hit (html:2241) and `let pts = head?100:60` on
## the kill (html:2232). Both agree with canon: BO1 pays 50 for the kill plus the
## 10 for the round that landed it, and 100 for a headshot kill.
##
## The melee bonus is the one number here with no ancestor line — html:2232 pays a
## melee kill exactly what a body shot pays. 60 + 70 = 130 is the canon melee
## payout, which is why the constant is 70 and not something rounder.
static func _points(v: Verify) -> void:
	v.check("the kill payouts are the ancestor's 60 and 100",
		Game.PTS_KILL == 60 and Game.PTS_HEADSHOT == 100,
		"kill=%d head=%d" % [Game.PTS_KILL, Game.PTS_HEADSHOT])
	v.check("a non-lethal hit pays 10", Game.PTS_HIT == 10)
	v.check("a melee kill totals the canon 130",
		Game.PTS_KILL + Game.PTS_MELEE_BONUS == 130,
		"got %d" % (Game.PTS_KILL + Game.PTS_MELEE_BONUS))
	# R4 §Perks, Tier 1: Insta-Kill pays a flat 50 rather than the full payout, so
	# it is a survival tool and not an economy multiplier. It must therefore be
	# strictly worse than a headshot or the correction did nothing.
	v.check("Insta-Kill pays a flat rate below the headshot payout",
		Game.PTS_INSTAKILL == 50 and Game.PTS_INSTAKILL < Game.PTS_HEADSHOT,
		"got %d" % Game.PTS_INSTAKILL)
	# html:1635 / :1654 — `points:500`, and canon's `zombie_score_start` solo is
	# also 500 (R4 §2, where it appears on both sides of the drop threshold).
	v.check("a run starts on 500 points", Game.START_POINTS == 500)
	# html:2985 `w.boards++; addPoints(10)` — repairing a barricade pays the same
	# as a non-lethal hit, which is the whole of the rounds 1-3 economy.
	v.check("a rebuilt plank pays the same as a hit", Game.PTS_REBUILD == Game.PTS_HIT)
	# html:2420 `addPoints(400)` inside the Nuke branch and html:2425
	# `addPoints(200)` inside the Carpenter branch — the two flat power-up payouts,
	# verbatim. Pinned here rather than left to the power-up layer because they are
	# points-table numbers and this is the points table; the layer that pays them
	# out is a different package's and has moved once already this wave.
	v.check("the Nuke and the Carpenter pay the ancestor's 400 and 200",
		Game.PTS_NUKE == 400 and Game.PTS_CARPENTER == 200,
		"nuke=%d carp=%d" % [Game.PTS_NUKE, Game.PTS_CARPENTER])


static func _economy(v: Verify) -> void:
	_points(v)
	# html:2886 `G.roundTimer = 6.5` and html:1652 `G.roundTimer=2.6`. Both are the
	# player's whole breathing space and both are trivially easy to "tidy" into one
	# constant, which would make the first round of a run arrive 4 s late.
	v.check("the intermission is 6.5 s and the first round opens after 2.6 s",
		v.near(Game.INTERMISSION, 6.5) and v.near(Game.FIRST_ROUND_DELAY, 2.6),
		"inter=%.2f first=%.2f" % [Game.INTERMISSION, Game.FIRST_ROUND_DELAY])


# --- power-up drops ----------------------------------------------------------

## R4 §2, Tier 1, `t5/_zombiemode_powerups.gsc:526-550`: the first drop lands at
## **2,000 points earned**, the increment compounds by **1.14** on every drop and
## is **never reset for the whole game**. R4 line 177 publishes the resulting
## sequence of increments — +2000, +2280, +2599, +2963, +3378 … — and the first
## three of those are pinned here exactly.
##
## The fourth diverges by one point and that is deliberate: canon multiplies a
## float, the port truncates with `int()`, so 2000 x 1.14^4 = 3377.92 becomes 3377
## here and 3378 there. One point on a four-thousand-point threshold is not worth
## a float in the save state, so what is pinned past the third is the *ratio*.
##
## This block also replaces the port's original model outright — the old one
## counted kills and never reset the counter, so drops arrived EARLIER the longer
## a run went. That is the failure this pins against coming back.
static func _drops(v: Verify, main: Node3D) -> void:
	var pts_was := Game.points_earned
	var next_was := Game.next_drop_at
	var idx_was := Game.drop_index
	var count_was := Game.drop_count

	Game.points_earned = 0
	Game.next_drop_at = 2000
	Game.drop_index = 0
	v.check("the first drop threshold is canon's 2000 points earned",
		Game.next_drop_at == 2000 and not Game.check_points_drop())

	var deltas: Array[int] = []
	for i in 10:
		Game.points_earned = Game.next_drop_at
		var before := Game.next_drop_at
		var fired := Game.check_points_drop()
		if not fired:
			break
		deltas.append(Game.next_drop_at - before)
	var head_ok := deltas.size() >= 3 and deltas[0] == 2280 and deltas[1] == 2599 \
		and deltas[2] == 2963
	v.check("the first three threshold steps are canon's 2280 / 2599 / 2963",
		head_ok, str(deltas))

	var ratio_ok := deltas.size() == 10
	for i in range(1, deltas.size()):
		var got := float(deltas[i]) / float(deltas[i - 1])
		if absf(got - 1.14) > 0.001:
			ratio_ok = false
	v.check("every later step compounds by 1.14 and the threshold never resets",
		ratio_ok, str(deltas))

	Game.drop_count = 3
	Game.reset_run()
	v.check("a new run clears the drop counter", Game.drop_count == 0)

	# The per-ROUND reset, which is the one that was missing. Canon clears
	# `powerup_drop_count` in `powerup_round_start()` and the ancestor does the same
	# at html:2862; without it the four-a-round cap is four a RUN, because nothing
	# else clears the counter between rounds. The balance sim is what surfaced it.
	#
	# Driven through the real `force_round()` rather than by poking the field,
	# because the point is that BEGINNING A ROUND clears it — a test that set the
	# counter and read it back would pass against the bug. `round_changed` is
	# disconnected across the call for the duration: Game checkpoints the profile on
	# that signal, and a headless assertion has no business writing to whatever real
	# save file happens to be on the machine running it.
	if main != null and main.rounds != null:
		var round_was: int = Game.round_no
		Game.round_changed.disconnect(Game._on_round_changed)
		Game.drop_count = 4
		main.rounds.force_round(7)
		var cleared := Game.drop_count == 0
		Game.round_changed.connect(Game._on_round_changed)
		Game.round_no = round_was
		Game.drop_count = 0
		v.check("beginning a round clears the drop counter, so the cap is per round",
			cleared, "drop_count survived _begin_round()")

	Game.points_earned = pts_was
	Game.next_drop_at = next_was
	Game.drop_index = idx_was
	Game.drop_count = count_was


# --- perks -------------------------------------------------------------------

## Four at once is the WaW/BO1-era limit (R4 §Perks). The ancestor has no cap at
## all — html:2776 writes `P.perks[p.k]=true` with nothing testing the size — so
## the cap is a correction, and it is currently non-binding for a reason worth
## asserting: the map offers exactly four machines, so the cap only starts doing
## work the day a fifth is added. That is precisely when it will be forgotten.
static func _perks(v: Verify, main: Node3D) -> void:
	v.check("the perk cap is the era's four", Game.PERK_CAP == 4)
	v.check("the map offers exactly as many perk machines as a player can hold",
		MapData.PERKSPOTS.size() == Game.PERK_CAP,
		"%d machines, cap %d" % [MapData.PERKSPOTS.size(), Game.PERK_CAP])

	# R4 §1, Tier 1, traced end to end: 60 melee damage against 100 base and 160
	# Juggernog is 2 hits and 3 hits. The widely repeated "250 HP, 5 hits" is BO3
	# with *upgraded* Juggernog and belongs to a different era.
	Game.perks.clear()
	v.check("Juggernog is the era's 160, not BO3's 250",
		v.near(Game.JUG_HP, 160.0) and v.near(Game.BASE_HP, 100.0),
		"jug=%.0f base=%.0f" % [Game.JUG_HP, Game.BASE_HP])

	# Solo Quick Revive: 500 and three uses, from R4's perk-cost table (Tier 1,
	# `t5/_zombiemode_perks.gsc`) — a different price from the 1500 co-op machine
	# that PERKDEF still carries for the HUD.
	v.check("solo Quick Revive is 500 and leaves after three buys",
		Game.REVIVE_COST == 500 and Game.REVIVE_MAX_USES == 3,
		"cost=%d uses=%d" % [Game.REVIVE_COST, Game.REVIVE_MAX_USES])

	# Every perk spot must name a perk the definition table knows about, or the
	# interactable built from it throws on the first walk past it rather than at
	# build time. `revive` is priced by Game and the rest by PERKDEF, so both
	# lookups are exercised.
	var missing := ""
	for ps: Dictionary in MapData.PERKSPOTS:
		var k: String = ps.k
		if not Weapons.PERKDEF.has(k):
			missing += k + " "
	v.check("every perk machine on the map has a definition", missing.is_empty(), missing)

	# The round loop's own precondition, checked against the live map rather than
	# the constant table. `round_director.gd::spawn_one` returns without spawning
	# when `live_windows()` is empty, and `_end_round` only fires once everything
	# queued has died — so a map with no reachable window does not fail, it hangs the
	# round forever with the count sitting on screen.
	var m: MapData = main.map
	var live: Array[int] = m.live_windows()
	var in_range := true
	for wi: int in live:
		if wi < 0 or wi >= MapData.WINDOWS.size():
			in_range = false
	v.check("the horde always has at least one reachable window to arrive through",
		not live.is_empty() and in_range, "%d live of %d" % [live.size(), MapData.WINDOWS.size()])


# --- dog rounds --------------------------------------------------------------

## R4 §5, Tier 1: `level.next_dog_round = randomintrange(5, 8)` gives 5, 6 or 7,
## and each subsequent one is `+ randomintrange(4, 6)` — plus 4 or plus 5. Godot's
## `randi_range` is inclusive at both ends, so 5..7 and 4..5 are the same sets.
##
## This is a deliberate departure from the ancestor, which is `G.round>=5 &&
## G.round%5===0` (html:2858) — every fifth round, forever, countable from the
## title screen. Sampled across seeds rather than reasoned about, because the
## failure being guarded against is an inclusive/exclusive slip at one end, which
## only ever shows up as a boundary value that never appears.
static func _dog_rounds(v: Verify) -> void:
	var seed_was := Rng.seed_value
	var firsts := {}
	var gaps := {}
	for s in 300:
		Rng.new_run(s)
		Game.reset_run()
		var first := Game.next_dog_round
		firsts[first] = true
		var prev := first
		for i in 6:
			Game.advance_dog_round()
			gaps[Game.next_dog_round - prev] = true
			prev = Game.next_dog_round
	var first_keys: Array = firsts.keys()
	var gap_keys: Array = gaps.keys()
	first_keys.sort()
	gap_keys.sort()
	v.check("the first hound round is 5, 6 or 7 and all three occur",
		first_keys == [5, 6, 7], str(first_keys))
	v.check("every later hound round is 4 or 5 rounds on, and both occur",
		gap_keys == [4, 5], str(gap_keys))

	Rng.new_run(seed_was)
	Game.reset_run()


# --- melee -------------------------------------------------------------------

## What a zombie does when it reaches you. Every value is read off a real
## `Zombie.create()` rather than off the constants, because the constants are
## assigned inside a `match` on the kind and the failure worth catching is a kind
## falling through to the wrong arm of it.
static func _melee(v: Verify) -> void:
	var z := Zombie.create("zombie", 0, 1, false)
	var hound := Zombie.create("hound", 0, 1, false)
	var crawler := Zombie.create("crawler", 0, 1, false)

	# 60, from R4 §1 — the correction that makes the game losable. The ancestor is
	# `hurtPlayer(z.type==='hound'?36:34)` (html:2328), so 34 was carried across
	# verbatim and was wrong at the source.
	v.check("a walker hits for the canon 60", v.near(z.melee_damage, 60.0),
		"got %.1f" % z.melee_damage)
	# 36 is the ancestor's own hound figure (html:2328) and is kept. It has no
	# canon corroboration in R4 either way — BO1's dogs are not covered by the
	# `self.meleeDamage = 60` line, which is the walker spawner — so this pin
	# records the ancestor, not canon.
	v.check("a hound hits for the ancestor's 36", v.near(hound.melee_damage, 36.0),
		"got %.1f" % hound.melee_damage)

	# html:2326 `z.atkT = z.type==='hound' ? 0.85 : 1.05` and html:2322
	# `const reachDist = z.type==='crawler' ? 1.05 : 1.15`. Both verbatim.
	v.check("hounds swing faster than walkers, at the ancestor's rates",
		v.near(hound.melee_cadence, 0.85) and v.near(z.melee_cadence, 1.05),
		"hound=%.2f walker=%.2f" % [hound.melee_cadence, z.melee_cadence])
	v.check("a crawler has to get closer than a walker does",
		v.near(crawler.melee_reach, 1.05) and v.near(z.melee_reach, 1.15),
		"crawler=%.2f walker=%.2f" % [crawler.melee_reach, z.melee_reach])

	# Every melee cadence has to stay longer than the player's per-attacker grace
	# window or the window starts refusing hits the design intends to land, and the
	# horde silently caps its own damage the way one global cooldown used to.
	v.check("no melee cadence is shorter than the per-attacker grace window",
		hound.melee_cadence > Player.HURT_IGNORE and z.melee_cadence > Player.HURT_IGNORE,
		"gate=%.2f" % Player.HURT_IGNORE)

	# html:2210-2211 — `hp*0.62` / `spd*1.55` for a hound, `hp*0.8` / `spd*0.62`
	# for a crawler. The tolerance is half a hit point because the ancestor wraps
	# both fractions in `Math.round()` and the port does not; they agree exactly at
	# round 1 and can differ by under a point later, which is not worth a divergence
	# but is worth not asserting away. Speed carries a per-spawn +/-8%, so it is
	# bracketed rather than compared.
	var base := Game.zombie_hp(1)
	v.check("hound and crawler health are the ancestor's fractions",
		v.near(hound.hp, base * 0.62, 0.51) and v.near(crawler.hp, base * 0.8, 0.51),
		"base=%.0f hound=%.0f crawler=%.0f" % [base, hound.hp, crawler.hp])
	v.check("a hound outruns a walker and a crawler is slower than one",
		hound.speed > z.speed and crawler.speed < z.speed,
		"hound=%.2f walker=%.2f crawler=%.2f" % [hound.speed, z.speed, crawler.speed])

	z.free()
	hound.free()
	crawler.free()
