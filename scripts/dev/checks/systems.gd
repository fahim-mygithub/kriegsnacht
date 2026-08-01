extends RefCounted

## Assertions for the systems split and for real engine pause.
##
## Two things arrived together and neither can be checked by looking at a frame.
## The split moved five concerns out of main.gd, and the only thing standing
## between "relocated" and "rewritten" is that a seeded run still produces the
## same spawns in the same order. The pause change replaced an early-return in
## every `_process` with `get_tree().paused`, which is a single boolean that has
## to be correct in **both** directions: too little and a tween keeps running
## behind the overlay, too much and the overlay itself stops drawing.
##
## **Run this LAST.** `_spawn_determinism` puts two dozen real zombies at real
## windows and kills them again, which draws the director's spawn queue down and
## moves the run counters (they are restored; the queue is not — nothing reads it
## after this and `--verify` quits on the next line).
##
## What is deliberately NOT asserted here, because a fake version is worse than an
## honest gap: nothing observes a frame actually elapsing under pause. `Verify.run`
## is synchronous, so there is no way to let the tree tick and then look. What is
## asserted instead is `Node.can_process()`, which is not a proxy — it is the exact
## boolean the engine itself consults, in `SceneTree::process_tweens` (via
## `Tween::can_process`, which for a bound tween reduces to the bound node's
## `can_process()`), in the `_process`/`_physics_process` dispatch, in
## `AudioStreamPlayer`'s pause notification and in `GPUParticles3D`'s. The one
## end-to-end behavioural assertion that *can* be made synchronously — driving a
## clock by hand and watching it not move — is made twice, on the mystery box and
## on the HUD.

## preload rather than the global class name: a freshly added script is not in
## the class registry until the editor rescans, and a headless run has no editor.
const MYSTERY_BOX := preload("res://scripts/systems/mystery_box.gd")

## Fixed, because the whole point is that the same number twice gives the same
## twelve spawns. Twelve is enough to cross a window's worth of weighting: the
## pick is biased away from windows that already have somebody at them, so a
## shorter sample would never exercise the divisor.
const SEED := 20260729
const SAMPLES := 12


static func run(v: Verify, main: Node3D) -> void:
	_composition(v, main)
	_moved_out(v, main)
	_pause_gate(v, main)
	_external_hold(v, main)
	_box_clock(v, main)
	_hud_clock(v, main)
	_muzzle(v, main)
	_spawn_determinism(v, main)


# --- the composition contract ------------------------------------------------

## main.gd is a composition root now, and every one of these names is something
## another package reaches for: the debug console goes through `main.rounds`, the
## rest of this suite goes through `main.player` / `main.fx` / `main.viewmodel`.
## A rename is free to the person doing it and breaks all of them at runtime.
static func _composition(v: Verify, main: Node3D) -> void:
	var missing := ""
	for k: String in ["map", "world", "flow", "player", "hud", "lighting", "fx",
			"viewmodel", "rounds", "powerups", "interact", "box", "atmos"]:
		if main.get(k) == null:
			missing += k + " "
	v.check("main exposes every member the contract names", missing.is_empty(), missing)

	var stray := ""
	for k: String in ["rounds", "powerups", "interact", "box", "atmos"]:
		var n: Node = main.get(k)
		if n == null or not n.is_inside_tree() or n.get_parent() != main:
			stray += k + " "
	v.check("every system is a live child of main", stray.is_empty(), stray)

	# The three the debug console is specified against, plus the two the round loop
	# itself needs. `has_method` rather than a call, because calling force_round()
	# here would emit round_changed — which checkpoints the profile to the player's
	# real save file.
	var rounds: Node = main.get("rounds")
	var api := ""
	for m: String in ["force_round", "spawn_one", "alive", "queued", "tick", "begin_run"]:
		if rounds != null and not rounds.has_method(m):
			api += m + " "
	v.check("RoundDirector exposes the wave contract", api.is_empty(), api)

	# The split is only worth anything if the pieces are actually separable, and
	# the way that rots is a system reaching back through main. Each of these is
	# handed its siblings at construction; a null one means a wiring line was lost.
	var unwired := ""
	var pu: Node = main.get("powerups")
	var it: Node = main.get("interact")
	if rounds != null and rounds.get("powerups") == null:
		unwired += "rounds.powerups "
	if pu != null and (pu.get("rounds") == null or pu.get("atmos") == null):
		unwired += "powerups.rounds/atmos "
	if it != null and (it.get("box") == null or it.get("atmos") == null or it.get("hud") == null):
		unwired += "interact.box/atmos/hud "
	v.check("the systems hold each other rather than reaching through main",
		unwired.is_empty(), unwired)


# --- what main handed away ---------------------------------------------------

## THE HALF OF A SPLIT NOBODY TESTS. `_composition` above proves the new homes
## exist; this proves the old ones are gone, which is the half that breaks other
## files. Three tools reach into these by name — perf_probe.gd freezes the round
## loop before every measurement by writing `_to_spawn` / `_intermission` /
## `_round_timer`, and console.gd and balance_sim.gd read the horde — and a write
## to a property that no longer exists is a *runtime* error GDScript swallows:
## only the innermost function unwinds. The probe carries on, every row after it
## is measured against a round that quietly kept spawning, and nothing anywhere
## reports a failure. That is exactly how perf_probe's three lines survived the
## split unnoticed.
##
## Asserted from both ends deliberately. "The director has it" alone would pass a
## half-done split where main kept a stale copy that the tools would still find
## and still write to — silently, into a field nothing reads any more.
static func _moved_out(v: Verify, main: Node3D) -> void:
	var rounds: Node = main.get("rounds")
	var wrong := ""
	# The round loop's own clock, in the order perf_probe writes them.
	for f: String in ["_to_spawn", "_intermission", "_round_timer", "_alive"]:
		if rounds == null or not _has_prop(rounds, f):
			wrong += "director lacks " + f + " "
	# Everything main.gd used to own and does not any more. A name reappearing here
	# means the split came apart, not that a feature came back.
	for f: String in ["_to_spawn", "_intermission", "_round_timer", "_alive",
			"_interactables", "_powerups", "_box_state", "_box_node", "_muzzle_mat",
			"_muzzle_light", "_perk_nodes", "_gen_node", "_pap_node"]:
		if _has_prop(main, f):
			wrong += "main still has " + f + " "
	v.check("every member main handed away lives on exactly one side of the split",
		wrong.is_empty(), wrong)


## `get()` cannot answer this: a missing property and a property holding `false`
## both come back falsy, and `_intermission` is a bool that is `false` for most of
## a round. The property list is the only reading that distinguishes them.
static func _has_prop(o: Object, prop: String) -> bool:
	for d: Dictionary in o.get_property_list():
		if String(d.name) == prop:
			return true
	return false


# --- the pause gate ----------------------------------------------------------

## Which nodes the engine will and will not run, per state. The asymmetry IS the
## feature: the world stops, the screen that says it stopped does not.
static func _pause_gate(v: Verify, main: Node3D) -> void:
	var tree := main.get_tree()
	var was: int = Game.state

	Game.set_state(Game.STATE_PLAY)
	var play_paused := tree.paused
	var play := _gate(main)

	Game.set_state(Game.STATE_PAUSE)
	var pause_paused := tree.paused
	var paused := _gate(main)
	# THE PLATE MOVED, AND THIS HAS TO FOLLOW IT RATHER THAN NAME ONE OWNER.
	#
	# `main.hud._overlay` was the only pause screen in the game when this was
	# written. It is not any more: main.gd now builds menu.gd, and `hud.set_menu()`
	# turns the HUD's own overlay off outright — hud.gd:1540-1552 says so in as
	# many words, because the menu draws the title, pause and game-over plates with
	# buttons on them and two of each would be worse than none.
	#
	# So reading the HUD alone asserted a true thing about the build that had no
	# menu and reports a MISSING PAUSE SCREEN on the build that has one. The check
	# is unchanged in intent — something that says "paused" is on screen — and the
	# menu is asked first because when it exists it is the authority.
	var overlay_up: bool = main.hud._overlay.visible
	if main.get("menu") != null:
		overlay_up = String(main.menu.current()) == "pause"

	Game.set_state(Game.STATE_TITLE)
	var title_paused := tree.paused
	Game.set_state(Game.STATE_OVER)
	var over_paused := tree.paused
	Game.set_state(was)

	# The warm-up pass runs behind the title card and is the only free moment it
	# has, so TITLE must not pause. OVER must, and for the opposite reason: it is
	# the one state a player leaves running by walking away from the tab.
	v.check("the tree pauses on pause and on game over, and on neither of the others",
		not play_paused and not title_paused and pause_paused and over_paused,
		"play=%s title=%s pause=%s over=%s" % [play_paused, title_paused,
			pause_paused, over_paused])

	# THE HALF THAT MAKES THE PAUSE REAL.
	var running := ""
	for k: String in ["main", "rounds", "powerups", "interact", "box", "atmos",
			"fx", "lighting", "head", "viewmodel", "emitter"]:
		if paused[k]:
			running += k + " "
	v.check("everything that simulates the world stops when the tree pauses",
		running.is_empty(), running)

	# THE HALF THAT MAKES IT SURVIVABLE. PROCESS_MODE_WHEN_PAUSED here would leave
	# the HUD dead during play — no bars, no marker, no ammo readout — which reads
	# as a broken HUD rather than as a pause bug, so it is asserted in both states.
	v.check("the overlay and the input path keep running in both states",
		play["hud"] and paused["hud"] and play["player"] and paused["player"],
		"play hud=%s player=%s / paused hud=%s player=%s" % [play["hud"],
			play["player"], paused["hud"], paused["player"]])
	v.check("the pause overlay is actually on screen while paused", overlay_up)

	# ...and the same nodes have to come back. A pause that never ends is the
	# other way this fails, and it fails silently at exactly the moment the player
	# clicks to resume.
	var stopped := ""
	for k: String in ["main", "rounds", "powerups", "interact", "box", "atmos",
			"fx", "lighting", "head", "viewmodel", "emitter"]:
		if not play[k]:
			stopped += k + " "
	v.check("all of it runs again in play", stopped.is_empty(), stopped)

	# Stated as the property rather than inferred from the gate, because this is
	# the line somebody will "simplify" to WHEN_PAUSED.
	v.check("the HUD's process mode is ALWAYS, not WHEN_PAUSED",
		main.hud.process_mode == Node.PROCESS_MODE_ALWAYS,
		"mode=%d" % main.hud.process_mode)
	# Input propagation is gated on can_process() exactly as _process is, and the
	# resume click has to reach the player's _unhandled_input — pointer lock needs
	# transient activation, so it cannot be asked for from anywhere else.
	v.check("the player is ALWAYS so the resume click can reach it",
		main.player.process_mode == Node.PROCESS_MODE_ALWAYS,
		"mode=%d" % main.player.process_mode)
	# ...but process_mode is inherited, so ALWAYS on the player would hand it to
	# the whole camera chain and the viewmodel hanging off the end of it.
	v.check("the camera chain under the player is pausable again",
		main.player._head.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"mode=%d" % main.player._head.process_mode)
	# A pausable AudioStreamPlayer fades to silence on NOTIFICATION_PAUSED, which
	# would clip the last hurt cue in half at the instant the death screen appears.
	v.check("the mixer does not freeze with the world",
		Sfx.process_mode == Node.PROCESS_MODE_ALWAYS, "mode=%d" % Sfx.process_mode)


## `can_process()` for one node of every kind that has to be on one side of the
## line or the other. `lighting` stands in for the tween: the power-on ceremony is
## the only `create_tween()` in the project and it is bound to that node, and
## `Tween::can_process` for a bound tween is exactly `bound_node->can_process()`.
## `emitter` is a real GPUParticles3D out of the impact pool.
static func _gate(main: Node3D) -> Dictionary:
	var pool: Array = main.fx._impacts
	var emitter: GPUParticles3D = pool[0]
	return {
		"main": main.can_process(),
		"rounds": main.rounds.can_process(),
		"powerups": main.powerups.can_process(),
		"interact": main.interact.can_process(),
		"box": main.box.can_process(),
		"atmos": main.atmos.can_process(),
		"fx": main.fx.can_process(),
		"lighting": main.lighting.can_process(),
		"head": main.player._head.can_process(),
		"viewmodel": main.viewmodel.can_process(),
		"emitter": emitter.can_process(),
		"hud": main.hud.can_process(),
		"player": main.player.can_process(),
	}


# --- somebody else holding the tree ------------------------------------------

## The HUD is PROCESS_MODE_ALWAYS, so it is the one node that keeps running while
## a *second* author holds `get_tree().paused`. The debug console is that author:
## `console._sync_hold()` takes the tree and releases the pointer so its LineEdit
## can be typed into, then gives both back on close.
##
## Unguarded, the HUD's lost-pointer watchdog reads that release as an alt-tab and
## pauses the run underneath the console. Closing the console then restores the
## tree to `_paused_was` — false — and leaves the state machine in STATE_PAUSE
## against a pointer it never lost, which neither resume branch can leave: the
## overlay sits over a running tree until the player clicks. Reproduced exactly,
## which is why this drives the console's two writes verbatim rather than opening
## a console the release build does not have.
##
## Headless can never really capture a pointer, so `_lock_seen` is armed by hand.
## On desktop and on web it is simply true from the first frame after the click
## that starts the run.
##
## Only the *during* half is asserted, and that is the whole bug: the state moving
## to STATE_PAUSE underneath the hold is what nothing could undo afterwards. The
## after half is not assertable here because it turns on the console's
## `Input.set_mouse_mode(_mouse_was)` actually re-capturing, and a headless
## DisplayServer grants no lock — the first draft of this check asserted it anyway
## and failed against a correct fix, which is the same vacuity in the other
## direction.
static func _external_hold(v: Verify, main: Node3D) -> void:
	var h: Node = main.hud
	var tree := main.get_tree()
	var state_was: int = Game.state
	var lock_was: bool = h._lock_seen
	var armed_was: bool = h._resume_armed

	Game.set_state(Game.STATE_PLAY)
	h._lock_seen = true

	# console opens: the tree is taken, the pointer is given up
	var paused_was := tree.paused
	tree.paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	h._process(0.016)
	h._process(0.016)
	var held_ok: bool = Game.state == Game.STATE_PLAY
	tree.paused = paused_was

	v.check("a debug tool holding the tree does not pause the run under it",
		held_ok, "state=%d (1==PLAY)" % Game.state)

	# ...and the watchdog is stood down, not deleted: with nobody holding the tree
	# the same released pointer still has to pause, or this fix would be
	# indistinguishable from removing the branch — and losing it silently un-pauses
	# every alt-tab and every browser that drops the lock.
	Game.set_state(Game.STATE_PLAY)
	h._lock_seen = true
	h._process(0.016)
	v.check("the lost-pointer watchdog still pauses when nobody is holding the tree",
		Game.state == Game.STATE_PAUSE, "state=%d" % Game.state)

	Game.set_state(state_was)
	h._lock_seen = lock_was
	h._resume_armed = armed_was


# --- a gameplay clock, driven by hand ----------------------------------------

## The behavioural half of the pause argument, on the one gameplay clock that can
## be driven synchronously and read back through a public accessor.
##
## The box spins for BOX_SPIN seconds and then offers. Ticking it moves it; the
## tick comes from main.gd and nowhere else, and main.gd cannot process while the
## tree is paused — which is the second assertion, made above. Together those two
## are the whole of "pause stops a gameplay timer".
static func _box_clock(v: Verify, main: Node3D) -> void:
	var box: Node = main.get("box")
	var points_was: int = Game.points
	var uses_was: int = Game.box_uses
	var spot_was: int = Game.box_spot
	var state_was: String = box.state()

	Game.points = 1000000
	# Cleared so the teddy roll below cannot come back true — a relocation would
	# move the box's real spot and the sprite with it.
	Game.box_uses = 0
	var opened: bool = box.use() and box.state() == "spinning"
	box.tick(MYSTERY_BOX.BOX_SPIN * 0.5)
	var mid: bool = box.state() == "spinning"
	box.tick(MYSTERY_BOX.BOX_SPIN * 0.5 + 0.01)
	var landed: bool = box.state() == "offering"
	# Back to idle without taking the weapon, which would hand the player a gun.
	box.tick(MYSTERY_BOX.BOX_OFFER + 0.01)
	# A timed-out offer goes to `closing`, not straight to idle — the lid takes its
	# 0.6 s to come down (html:2841-2842). Asserted rather than merely ticked past:
	# a machine that dropped the state entirely would still arrive at idle, and a
	# check that only looked at the destination would pass through the hole.
	var closing: bool = box.state() == "closing"
	box.tick(MYSTERY_BOX.BOX_CLOSING + 0.01)

	v.check("the box's clock is a clock: it only moves when it is ticked",
		opened and mid and landed and closing and box.state() == "idle",
		"opened=%s mid=%s landed=%s closing=%s end=%s" % [
			opened, mid, landed, closing, box.state()])

	Game.points = points_was
	Game.box_uses = uses_was
	Game.box_spot = spot_was
	v.check("the box clock check put the box back", box.state() == state_was)


# --- the HUD's own clocks ----------------------------------------------------

## The leak this change exists to close. Every transient on screen used to decay
## while the pause overlay was up, so a toast raised on the frame you hit P was
## gone by the time you came back and a hit marker faded behind the menu.
##
## Driven by hand rather than by frames, which is also the only way to test the
## *wrong* direction: a gate that never lets anything decay looks identical to a
## working pause until someone plays the game.
static func _hud_clock(v: Verify, main: Node3D) -> void:
	var h: Node = main.get("hud")
	var flash_was: float = h._flash
	var toast_was: float = h._toast_time
	var marker_was: float = h._marker_t
	var state_was: int = Game.state

	Game.set_state(Game.STATE_PLAY)
	h._flash = 0.6
	h._toast_time = 2.0
	h._marker_t = 0.20
	h._process(0.1)
	var decays: bool = h._flash < 0.6 and h._toast_time < 2.0 and h._marker_t < 0.20

	Game.set_state(Game.STATE_PAUSE)
	h._flash = 0.6
	h._toast_time = 2.0
	h._marker_t = 0.20
	# Five seconds is more than twice the toast's whole life and eight times the
	# marker's, so a gate that leaks at all leaks visibly here.
	h._process(5.0)
	var holds: bool = v.near(h._flash, 0.6) and v.near(h._toast_time, 2.0) \
		and v.near(h._marker_t, 0.20)

	Game.set_state(state_was)
	h._flash = flash_was
	h._toast_time = toast_was
	h._marker_t = marker_was

	v.check("the HUD's transients decay in play and hold through a pause",
		decays and holds, "decays=%s holds=%s" % [decays, holds])


# --- the muzzle flash, in its new home ---------------------------------------

## The flash moved out of main.gd into Atmosphere and nothing else reaches it:
## `--shot` captures frame 60, which is before the first round even starts and has
## no shot in it, and a headless soak has no input to fire with. So fire the
## signal by hand — that also proves the connection survived the move, which is
## the part of a relocation most likely to be silently dropped.
##
## The second assertion is constraint 6 from the cosmetic side. The flash's SIZE
## is a VISUAL draw and has to stay one (atmosphere.gd's `_on_fired`; the roll it
## replaced was discarded by the billboard): it happens once per shot, immediately
## before the two VISUAL draws that pick the bullet's spread, so promoting it to a
## gameplay stream would shift every seeded run's aim.
##
## NOTE THE EMIT BELOW IS AT THE CAMERA'S OWN POSITION, so `_on_fired` computes
## dist = 0 and `flash_size` returns 0.0: this fires a ZERO-SIZE flash and only
## reads `visible`, which is all it claims. Anything needing a size fires at a real
## depth instead — checks/frame.gd::_flash_drawn, `FIRE_DEPTH`.
static func _muzzle(v: Verify, main: Node3D) -> void:
	var atmos: Node3D = main.get("atmos")
	var streams: Array[StringName] = [Rng.SPAWN, Rng.BOX, Rng.DROPS, Rng.ROUNDS, Rng.AI]
	var was: Array[int] = []
	for s: StringName in streams:
		was.append(Rng.stream(s).state)
	var visual_was: int = Rng.stream(Rng.VISUAL).state

	atmos._muzzle_quad.visible = false
	atmos._muzzle_light.visible = false
	main.player.fired.emit(main.player.camera().global_position)
	var lit: bool = atmos._muzzle_quad.visible and atmos._muzzle_light.visible

	var perturbed := ""
	for i in streams.size():
		if Rng.stream(streams[i]).state != was[i]:
			perturbed = str(streams[i])

	v.check("the muzzle flash still fires from its new home", lit,
		"quad=%s light=%s" % [atmos._muzzle_quad.visible, atmos._muzzle_light.visible])
	v.check("...and rolls it on VISUAL, disturbing no gameplay stream",
		perturbed.is_empty() and Rng.stream(Rng.VISUAL).state != visual_was,
		"perturbed=%s visual_moved=%s" % [perturbed,
			Rng.stream(Rng.VISUAL).state != visual_was])

	atmos._muzzle_quad.visible = false
	atmos._muzzle_light.visible = false
	atmos._muzzle_t = 0.0


# --- the split is a relocation, not a rewrite --------------------------------

## THE ASSERTION THE SPLIT IS FOR. Every draw the round director makes comes from
## a named Rng sub-stream, and the whole seeded-run design rests on those draws
## happening in the same order for the same seed. A refactor that reorders two
## lines inside `spawn_one` breaks that and changes nothing else visible.
##
## Two full runs of the real `spawn_one` — window pick, kind roll, palette, speed
## class, per-zombie variance — from the same seed, compared element by element.
static func _spawn_determinism(v: Verify, main: Node3D) -> void:
	var a := _sequence(main)
	var b := _sequence(main)
	v.check("a fixed seed replays the same spawn sequence through the director",
		a.size() == SAMPLES and a == b,
		"n=%d\n         a=%s\n         b=%s" % [a.size(), a, b])

	# ...and the sample has to have moved, or two empty arrays would agree
	# perfectly. The window index is the interesting one: a single-window sequence
	# would pass the comparison above while proving nothing about `_pick_window`.
	var kinds := {}
	var windows := {}
	for row: String in a:
		var parts := row.split("/")
		windows[parts[0]] = true
		kinds[parts[1]] = true
	v.check("the sampled sequence actually varies", windows.size() > 1,
		"windows=%s kinds=%s" % [windows.keys(), kinds.keys()])


static func _sequence(main: Node3D) -> Array:
	var rounds: Node = main.get("rounds")

	var round_was: int = Game.round_no
	var points_was: int = Game.points
	var kills_was: int = Game.kills
	var heads_was: int = Game.headshots
	var earned_was: int = Game.points_earned
	var next_was: int = Game.next_drop_at
	var index_was: int = Game.drop_index
	var drops_was: int = Game.drop_count
	var dog_was: int = Game.next_dog_round
	var insta_was: float = Game.insta_kill

	Rng.new_run(SEED)
	# Round 6 is the first round crawlers can appear in, so the kind roll is live
	# and actually draws. `next_dog_round` is pushed out of reach because a dog
	# round short-circuits that roll to "hound" and draws nothing at all.
	Game.round_no = 6
	Game.next_dog_round = 9999
	Game.insta_kill = 0.0
	# Four is the per-round drop cap, so none of the deaths below can spawn a
	# power-up. The teardown has to go through the real death path — `_die()` is
	# the only thing that gives a barricade slot back, and a slot left claimed
	# would weight the *next* run's window pick — and a real death pays out.
	Game.drop_count = 4

	var out: Array = []
	var made: Array[Zombie] = []
	for i in SAMPLES:
		var before: int = rounds.alive().size()
		rounds.spawn_one()
		var live: Array = rounds.alive()
		if live.size() <= before:
			break
		var z: Zombie = live[live.size() - 1]
		made.append(z)
		out.append("w%d/%s/%.5f" % [_window_of(z), z.kind, z.speed])

	for z: Zombie in made:
		z.take_damage(1e9, 0.0)
		z.queue_free()

	Game.round_no = round_was
	Game.points = points_was
	Game.kills = kills_was
	Game.headshots = heads_was
	Game.points_earned = earned_was
	Game.next_drop_at = next_was
	Game.drop_index = index_was
	Game.drop_count = drops_was
	Game.next_dog_round = dog_was
	Game.insta_kill = insta_was
	return out


## Which window a spawn came out of, recovered from where it is standing rather
## than from a field on the zombie: `set_entering` puts it at its barricade's
## stand slot, which is offset along the wall, so the nearest window centre is the
## answer and the slot offset is not part of what is being compared.
static func _window_of(z: Zombie) -> int:
	var here := Vector2(z.global_position.x, z.global_position.z)
	var best := -1
	var best_d := 1e9
	for wi in MapData.WINDOWS.size():
		var w: Dictionary = MapData.WINDOWS[wi]
		var d := here.distance_to(Vector2(float(w.ix) + 0.5, float(w.iy) + 0.5))
		if d < best_d:
			best_d = d
			best = wi
	return best
