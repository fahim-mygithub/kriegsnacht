extends Node

## Single random-number authority, split into named sub-streams.
##
## Before this there were three uncorrelated generators (`main.gd`, `game_state.gd`)
## plus bare `randf_range()` calls in `zombie.gd` and `player.gd`, all drawing from
## unrelated sequences. The practical consequence: a purely cosmetic roll — a
## zombie's animation speed jitter — advanced the same global state that decided
## which window the next zombie spawned from. Changing a visual detail silently
## changed the game.
##
## Named sub-streams fix that. Each stream is seeded by hashing its own name
## together with the run seed, so streams are independent of each other but wholly
## determined by that one seed. Cosmetic churn in `visual` can never perturb
## `spawn`, and a run replays identically from its seed alone.
##
## This is also the piece that keeps a run-based (roguelike) mode cheap later: a
## reproducible run is exactly a seed plus the streams below.

## Gameplay streams. Draws from these decide what actually happens, so they must
## stay reproducible for a given seed.
const SPAWN := &"spawn"        # which window, which kind of enemy
const BOX := &"box"            # mystery box rolls and the teddy bear
const DROPS := &"drops"        # power-up type and drop cadence
const ROUNDS := &"rounds"      # dog-round cadence, barricade regrowth
const AI := &"ai"              # per-zombie speed class, attack phase, goal offset
## Where a round actually goes: the spread cone sampled by `player.gd::_hitscan`
## and `::_launch`.
##
## **THIS STREAM EXISTS TO CLOSE A KNOWN VIOLATION, and the reason recorded for
## leaving it open was wrong.** Weapon spread drew from `VISUAL` from the port's
## first commit, and CLAUDE.md's constraint 5 justified that as "changing it moves
## every sim baseline". It does not: `balance_sim.gd` draws only from `SPAWN`
## (`:422`, `:615`) and `DROPS` (`:717`), never calls `_spread_rad` or `_hitscan`,
## and computes damage analytically over `for i in pellets` (`:529`) with every
## pellet assumed to hit — there is no spread anywhere in it. Verified by reading
## the file, 2026-08-02, and re-verified by running `--sim` on both sides of the
## move (see M5's stage-4 report). What the move *does* perturb is everything
## downstream of `VISUAL`'s sequence, because two draws per pellet stopped being
## taken from it — a frames-gate question, which is where it was checked.
##
## Adding a stream is free here and `stream()` below is why: seeds are hashed from
## the name together with the run seed, so a new name cannot shift any existing
## stream's seed, and the generator is not built until something draws from it.
const COMBAT := &"combat"      # weapon spread — where the round actually goes

## Cosmetic stream. Draws here must never influence a gameplay outcome, which is
## what lets art and feel be retuned without invalidating a seed.
const VISUAL := &"visual"      # sprite speed jitter, groan timing, FX variation

var seed_value: int = 0

var _streams: Dictionary = {}


func _ready() -> void:
	# A seed always exists, so a stream requested before new_run() still works.
	new_run()


## Begins a new run. Pass a seed to reproduce a previous one; omit it for a fresh
## random run. Returns the seed actually used so it can be shown or recorded.
func new_run(s: int = -1) -> int:
	if s < 0:
		var boot := RandomNumberGenerator.new()
		boot.randomize()
		s = int(boot.randi())
	seed_value = s
	_streams.clear()
	return seed_value


## Fetches a sub-stream, creating it on first use. Streams are lazily built so
## adding one costs nothing until something draws from it.
func stream(name: StringName) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = _streams.get(name)
	if r == null:
		r = RandomNumberGenerator.new()
		# Hash name-with-seed rather than seed+index: adding or removing a stream
		# then cannot shift the seeds of the streams around it.
		r.seed = hash("%d/%s" % [seed_value, name])
		_streams[name] = r
	return r


# --- convenience wrappers ----------------------------------------------------
# Call sites read better as Rng.randf(Rng.SPAWN) than Rng.stream(Rng.SPAWN).randf().

func randf(name: StringName) -> float:
	return stream(name).randf()


func randf_range(name: StringName, from: float, to: float) -> float:
	return stream(name).randf_range(from, to)


func randi_range(name: StringName, from: int, to: int) -> int:
	return stream(name).randi_range(from, to)


## Uniform pick from a non-empty array.
func pick(name: StringName, arr: Array):
	return arr[stream(name).randi() % arr.size()]
