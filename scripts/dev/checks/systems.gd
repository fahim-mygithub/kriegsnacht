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
const FX := preload("res://scripts/world/fx.gd")
const ATMOS := preload("res://scripts/systems/atmosphere.gd")
const GUNART := preload("res://scripts/data/gunart.gd")
const VIEWMODEL := preload("res://scripts/entities/viewmodel.gd")
const WEAPON := preload("res://scripts/entities/weapon.gd")
## Read-only, and for one constant: the frames gate's own ADS probe rect. The
## sighted silhouette has to stay inside it or the gate measures a clipped weapon
## and reports a number about the rectangle. This package does not own that file.
const SHOT_SETUP := preload("res://scripts/dev/shot_setup.gd")

## player.gd:837's own emit depth, so a hand-fired `fired` lands where a real shot
## lands and `_on_fired`'s `dist` comes out exactly this.
const FIRE_DEPTH := 0.35
## The frame this suite steps at. Everything below drives `_process` by hand —
## `Verify.run` is synchronous and no frame ever elapses inside it.
const STEP := 1.0 / 60.0

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
	_brass(v, main)
	_smoke(v, main)
	_animation(v, main)
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


# --- the brass, and the smoke ------------------------------------------------
#
# WHY THESE LIVE HERE. Ejected casings and muzzle smoke are not "the systems
# split", and on any other week each would be a `checks/*.gd` with its own two
# registration lines. Those lines belong to `verify.gd`, which this package owns
# only as far as the floor constant, and a new module on disk without them turns
# `--verify` red for every other agent working in the tree. So they sit beside
# `_muzzle`, which is the other cosmetic effect this file already inherited from
# the same split, and the placement is recorded as a constraint rather than left
# to read as a filing accident.
#
# WHAT THEY EXIST TO CATCH. Both features can be COMPLETELY INERT while the
# obvious checks pass, and this file has the receipt for that failure at
# `atmosphere.gd:438-445`: the muzzle flash's burst layer shipped created,
# materialled and never drawn, with `--verify` 580 green and no failed frame
# relation behind it. So every check below is written against a constructed inert
# version — `_eject` returning early, `_on_fired` never touching `_smoke` — and
# each one names the sabotage that must make it, specifically, go red.
#
# AND THE RNG CONTRACT, from the end nothing reached. `fx.gd`'s header forbids it
# any `Rng` draw at all, and `verify.gd:1005-1017` asserts that over `impact` and
# `_on_surface_impact` only — it never emits `fired`, so until this section
# existed anything hung off the fired path was outside the file's own stated rule.


## Equip one weapon and nothing else, so `current_gun()` answers with it.
static func _arm(main: Node3D, key: String) -> void:
	var p: Player = main.player
	p.guns = [Weapons.make_gun(key, false)]
	p.slot = 0


## Where a real shot's `fired` lands: player.gd:837 emits a fixed point on the
## camera axis, not the muzzle.
static func _shot_at(main: Node3D) -> Vector3:
	var cam: Camera3D = main.player.camera()
	return cam.global_position - cam.global_transform.basis.z * FIRE_DEPTH


## Clear the ring without touching the cursor's arithmetic: this is the state
## `warm()`'s cleanup block leaves, reached the same way.
static func _brass_clear(fx: Node3D) -> void:
	for i in FX.BRASS:
		fx._brass_life[i] = 0.0
		fx._retire(fx.brass_ring().multimesh, i)
	fx._brass_live = 0
	fx._brass_next = 0


## Step the real integrator until the casing in slot `i` stops moving, or give up.
## The cap is 1.5 s, which is comfortably inside the 1.6 s before the sink begins —
## a rested casing that has started sinking is no longer at its rest height and the
## two claims would contend.
static func _settle(fx: Node3D, i: int) -> int:
	var steps := 0
	while steps < 90 and fx._brass_vel[i] != Vector3.ZERO:
		fx._process(STEP)
		steps += 1
	return steps


static func _brass(v: Verify, main: Node3D) -> void:
	var fx: Node3D = main.fx
	var p: Player = main.player
	var guns_was: Array = p.guns
	var slot_was: int = p.slot
	var vel_was: Vector3 = p.velocity
	var shot_was: int = fx._shot_no
	var streams: Array[StringName] = [Rng.SPAWN, Rng.BOX, Rng.DROPS, Rng.ROUNDS,
		Rng.AI, Rng.VISUAL]
	# Every `fired` below also runs the muzzle flash, which legitimately spends one
	# VISUAL draw a shot. Restored on the way out, as `checks/frame.gd:1131` does,
	# so nothing downstream sees a hundred draws it did not make.
	var vis := Rng.stream(Rng.VISUAL)
	var vis_was: int = vis.state

	_brass_registration(v, fx)
	_brass_roster(v, main, fx)
	_brass_spawn(v, main, fx, streams)
	_brass_flight(v, main, fx)

	_brass_clear(fx)
	p.velocity = vel_was
	p.guns = guns_was
	p.slot = slot_was
	fx._shot_no = shot_was
	vis.state = vis_was
	# The flash rode along on every one of those emits and its clock only clears in
	# a `_process` this suite never reaches.
	var atmos: Node3D = main.atmos
	atmos._muzzle_t = 0.0
	atmos._smoke = 0.0
	atmos.flash_quad().visible = false
	atmos.burst_quad().visible = false
	atmos.smoke_quad().visible = false
	atmos._muzzle_light.visible = false


## The two omissions that are caught by nothing else in the project.
##
## A material missing from `fx.materials()` fails `verify.gd:1050` — that much was
## already true. A MULTIMESH missing from the warm pass is caught by nothing at
## all: `shader_warmup.gd` draws on a plain `MeshInstance3D` and structurally
## cannot compile the USE_INSTANCING variant, so the omission costs every visitor
## a main-thread GLSL compile on the first trigger pull of the session and shows up
## as a hitch rather than as a failure. `fx.warm()` walks `rings()` for exactly
## that reason, and this is what makes the list an assertion rather than a habit.
static func _brass_registration(v: Verify, fx: Node3D) -> void:
	var found: Array = []
	for c in fx.get_children():
		if c is MultiMeshInstance3D:
			found.append(c)
	var loose := ""
	for mi in found:
		if not fx.rings().has(mi):
			loose += String(mi.name) + " "
	v.check("every MultiMesh under fx is in the list warm() walks",
		loose.is_empty() and found.size() >= 4
			and fx.rings().has(fx.brass_ring())
			and fx.rings().size() == found.size(),
		"unwarmed [%s]; %d children, %d registered" % [loose, found.size(),
			fx.rings().size()])

	# Consumer-driven: the mesh and the material the RENDERER was handed, off the
	# live ring, rather than the accessor asked whether it holds itself. The
	# instance COUNT is asserted here too because it is the one thing about the ring
	# that is readable headlessly — see `_brass_flight`'s check 8 for why the
	# transforms are not — and a ring sized 0 would satisfy every other claim in
	# this section while drawing nothing.
	var mm: MultiMesh = fx.brass_ring().multimesh
	var mat: Material = mm.mesh.surface_get_material(0)
	v.check("the brass material the renderer was handed is declared for the warm pass",
		mat != null and fx.materials().has(mat) and mm.instance_count == FX.BRASS,
		"mat=%s declared=%d instances=%d" % [mat, fx.materials().size(),
			mm.instance_count])


## BO1 ships four eject effects for the whole roster and gives four weapons an
## empty one. BOUNDED AT BOTH ENDS deliberately: the refusal alone would pass
## against a `_eject` that had stopped working entirely, which is the shape of the
## Monkey Bomb check that ran a whole wave testing nothing.
static func _brass_roster(v: Verify, main: Node3D, fx: Node3D) -> void:
	var p: Player = main.player
	var at := _shot_at(main)
	var wrong := ""
	var ejected := 0
	# Per-key, in the failure message: a total alone cannot say WHICH weapon
	# stopped ejecting, and this check has twelve of them.
	var tally := ""
	for key: String in Weapons.TABLE.keys():
		_arm(main, key)
		_brass_clear(fx)
		p.fired.emit(at)
		var n: int = fx.brass_live()
		var want := 1 if FX.CASING_OF.has(key) else 0
		if n != want:
			wrong += "%s got %d want %d " % [key, n, want]
		ejected += n
		tally += "%s:%d/%d " % [key, n, want]
	# The four with an empty field, named rather than counted, so removing a row
	# from the table cannot be absorbed by the total.
	var silent := ""
	for key: String in ["olympia", "chinalake", "raygun", "thundergun"]:
		if FX.CASING_OF.has(key):
			silent += key + " "
	v.check("the four weapons BO1 gives an empty eject field eject nothing, and every other weapon ejects one",
		wrong.is_empty() and silent.is_empty() and ejected == 8,
		"%s/ wrongly mapped: %s (%d of the roster ejected) %s" % [wrong, silent, ejected, tally])


static func _brass_spawn(v: Verify, main: Node3D, fx: Node3D,
		streams: Array[StringName]) -> void:
	var p: Player = main.player
	var at := _shot_at(main)
	p.velocity = Vector3.ZERO
	_arm(main, "m1911")

	# 1. ONE shot, ONE casing, and the cursor advanced by one.
	_brass_clear(fx)
	p.fired.emit(at)
	v.check("one shot ejects exactly one casing",
		fx.brass_live() == 1 and fx._brass_next == 1,
		"live=%d next=%d" % [fx.brass_live(), fx._brass_next])

	# 2. THE MISTAKE ACTUALLY AVAILABLE. This file connects `surface_impact` too,
	# and a casing hung off the terminal event instead of off `fired` would
	# multiply by pellets and by pierce depth. Driving a real six-pellet `_shoot`
	# proves the count is one; emitting six terminal impacts by hand proves the
	# other listener does not eject at all, and that half is world-independent —
	# it does not care whether any pellet found a wall.
	_arm(main, "stakeout")
	_brass_clear(fx)
	p.guns[0].mag = 6
	p.guns[0].next_shot = 0.0
	var vis := Rng.stream(Rng.VISUAL)
	var vis_was: int = vis.state
	p._shoot(p.guns[0])
	var from_shot: int = fx.brass_live()
	vis.state = vis_was
	_brass_clear(fx)
	for i in 6:
		p.surface_impact.emit(Vector3(3.5 + float(i) * 0.01, 1.2, 4.0), Vector3.LEFT)
	v.check("a six-pellet shot ejects one hull, and six terminal impacts eject none",
		from_shot == 1 and fx.brass_live() == 0,
		"shoot=%d impacts=%d" % [from_shot, fx.brass_live()])

	# 3. Twenty shots allocate nothing and round-robin, the same claim
	# `verify.gd:974-981` already makes for the impact pool — a ring that grew a
	# node per shot would be fifteen allocations a second at 880 rpm.
	_arm(main, "mp40")
	_brass_clear(fx)
	var children_was := fx.get_child_count()
	for i in 20:
		p.fired.emit(at)
	v.check("twenty shots allocate nothing and round-robin the ring",
		fx.get_child_count() == children_was and fx.brass_live() == 20
			and fx._brass_next == 20 % FX.BRASS,
		"children %d->%d live=%d next=%d" % [children_was, fx.get_child_count(),
			fx.brass_live(), fx._brass_next])

	# 4. THE CONTRACT THE FILE STATES ABOUT ITSELF, from the end nothing reached.
	# `fx._on_fired` is driven directly rather than through the signal, exactly as
	# `verify.gd:1005-1017` drives `fx._on_surface_impact` directly: the signal
	# would also run atmosphere.gd's flash, which legitimately spends one VISUAL
	# draw, and the claim here is about THIS file. Bounded at the other end by the
	# casing count, so it cannot pass against an `_eject` that does nothing.
	_brass_clear(fx)
	var was: Array[int] = []
	for s: StringName in streams:
		was.append(Rng.stream(s).state)
	for i in 20:
		fx._on_fired(at)
	var moved := ""
	for i in streams.size():
		if Rng.stream(streams[i]).state != was[i]:
			moved += str(streams[i]) + " "
	v.check("twenty shots through fx's own fired path draw from no rng stream at all",
		moved.is_empty() and fx.brass_live() == 20,
		"perturbed [%s] live=%d" % [moved, fx.brass_live()])

	# 5. ioq3 `{0, -50+-40, 100+-50}` and Half-Life `right*(50..70)`: a casing
	# always leaves to the SHOOTER'S RIGHT. Both ends: every one of eight goes
	# right, and no two of them go identically — a mixer stuck on a constant would
	# satisfy the first half forever.
	_brass_clear(fx)
	var cam: Camera3D = p.camera()
	var right := cam.global_transform.basis.x
	var leftward := 0
	var same := 0
	var prev := Vector3.ZERO
	for i in 8:
		p.fired.emit(at)
		var vel: Vector3 = fx._brass_vel[i]
		if vel.dot(right) <= 0.0:
			leftward += 1
		if i > 0 and vel.is_equal_approx(prev):
			same += 1
		prev = vel
	v.check("every casing leaves to the shooter's right, and no two leave identically",
		leftward == 0 and same == 0,
		"leftward=%d identical=%d" % [leftward, same])

	# 6. Half-Life `ev_common.cpp:152`, the detail this document says hobby
	# implementations miss. The SHOT COUNTER is rewound between the two shots so
	# the counter-derived jitter is bit-identical and the only difference between
	# them is the shooter's motion — which is the only way to assert an exact
	# equality here rather than a fuzzy one.
	_brass_clear(fx)
	var n_was: int = fx._shot_no
	var drift := Vector3(1.7, 0.0, -0.9)
	p.velocity = drift
	p.fired.emit(at)
	var moving: Vector3 = fx._brass_vel[0]
	fx._shot_no = n_was
	_brass_clear(fx)
	p.velocity = Vector3.ZERO
	p.fired.emit(at)
	var still: Vector3 = fx._brass_vel[0]
	v.check("a moving shooter's velocity is inherited by the casing exactly",
		(moving - still).is_equal_approx(drift),
		"delta %s want %s" % [moving - still, drift])

	# 7. OpenSpades' `cross(-up, flyDir)`. Perpendicular to flight is what makes a
	# casing tumble end over end rather than spin about its own long axis, which is
	# the one property of the four surveyed systems that a still frame can show.
	_brass_clear(fx)
	var worst := 0.0
	for i in 8:
		p.fired.emit(at)
		var d: float = absf(fx._brass_axis[i].dot(fx._brass_vel[i].normalized()))
		worst = maxf(worst, d)
	v.check("the tumble axis is perpendicular to the casing's flight",
		worst < 0.05, "worst |axis.flight| = %.6f" % worst)


static func _brass_flight(v: Verify, main: Node3D, fx: Node3D) -> void:
	var p: Player = main.player
	var at := _shot_at(main)
	p.velocity = Vector3.ZERO
	_arm(main, "m1911")

	# 8. THE INTEGRATION BRANCH ITSELF.
	#
	# MEASURED 2026-08-02, AND IT COST THIS CHECK ITS FIRST DRAFT. The obvious
	# version of this — and the one M5's A6(d) specifies in as many words, "an
	# instance moves away from the retired zero basis and returns at end of life" —
	# reads `multimesh.get_instance_transform(i)`. THAT CANNOT BE DONE HEADLESSLY.
	# A MultiMesh's instance data lives on the RenderingServer, `--headless` runs
	# the dummy one, and it stores nothing: driven against a ring with a live
	# casing in slot 0 the readback returned the IDENTITY transform and
	# `multimesh.buffer` came back `size() == 0`. The same probe against `_holes`,
	# which by that point in the suite has had real bullet holes written into it,
	# also returned identity. So no assertion in this project can read back what
	# ANY MultiMesh was handed, and a check written that way is not merely blind —
	# it is worse than blind, because an identity basis has a y column of exactly
	# world up and would have passed the lie-flat claim below while proving
	# nothing.
	#
	# What is asserted instead is everything up to the buffer write: the state the
	# integrator advances, and `_brass_basis()` — the function `_tick_brass` hands
	# to `set_instance_transform`, driven rather than re-derived. The one gap left
	# is whether that result reaches the server, and it belongs to the frames gate.
	_brass_clear(fx)
	p.fired.emit(at)
	var spawn: Vector3 = fx._brass_pos[0]
	var born: Basis = fx._brass_basis(0)
	fx._process(STEP)
	var pos_a: Vector3 = fx._brass_pos[0]
	for i in 12:
		fx._process(STEP)
	var pos_b: Vector3 = fx._brass_pos[0]
	var steps := 0
	while steps < 400 and fx.brass_live() > 0:
		fx._process(STEP)
		steps += 1
	v.check("stepping the integrator flies a casing and retires it at end of life",
		born.x.length() > 0.0 and born.y.length() > 0.0 and born.z.length() > 0.0
			and not pos_a.is_equal_approx(spawn)
			and not pos_b.is_equal_approx(pos_a)
			and fx.brass_live() == 0 and fx._brass_life[0] == 0.0,
		"born columns %.5f/%.5f/%.5f, first step moved %.5f m, next twelve %.5f m, live=%d after %d steps" % [
			born.x.length(), born.y.length(), born.z.length(),
			spawn.distance_to(pos_a), pos_a.distance_to(pos_b), fx.brass_live(),
			steps])

	# 9. IT FALLS. Gravity is asserted as a monotone claim over the first twenty
	# steps (0.333 s, and the fastest this ring can put a casing on the floor from
	# eye height is 0.70 s, so no bounce can land inside the window) and as a
	# destination: it ends on the floor at half its own thickness, which is where
	# all four surveyed systems put it. Provenance: F28, unanimous.
	_brass_clear(fx)
	p.fired.emit(at)
	var spawn_y: float = fx._brass_pos[0].y
	var last: float = fx._brass_vel[0].y
	var rises := 0
	for i in 20:
		fx._process(STEP)
		var vy: float = fx._brass_vel[0].y
		if vy >= last:
			rises += 1
		last = vy
	_settle(fx, 0)
	var rest_y: float = fx._brass_pos[0].y
	var want_y: float = fx._brass_scale[0].y * 0.5
	v.check("the casing falls, and comes to rest on the floor",
		rises == 0 and v.near(rest_y, want_y, 1e-4) and spawn_y - rest_y > 0.5,
		"non-falling steps=%d, rest y %.5f want %.5f, spawned at %.5f" % [
			rises, rest_y, want_y, spawn_y])

	# 10. AND IT LIES FLAT, which is the other thing all four surveyed systems agree
	# on and the only one a still frame can show. Through `_brass_basis()`, for the
	# reason check 8 records at length: the MultiMesh readback is dead headless, and
	# its identity return would have made this check green against ANY implementation
	# — including one with no re-orthonormalisation at all — because an identity
	# basis' y column IS world up. That is the shape of the atlas test that passed
	# with the atlas disabled, and it took a diagnostic run to catch.
	#
	# Eight casings rather than one: the tumble angle at the moment of rest is
	# effectively arbitrary, so a single sample could land within five degrees of
	# upright by luck.
	_brass_clear(fx)
	var worst := 0.0
	var tilted := 0.0
	for i in 8:
		p.fired.emit(at)
	for i in 8:
		# Sampled MID-FLIGHT first, which is the acceptance half. The refusal alone
		# passes against a casing whose tumble rate is zero: it would lie flat from
		# the instant it left the gun and never fail a claim about lying flat at
		# rest. So the arc has to be seen to bend before the rest is worth asserting.
		tilted = maxf(tilted, rad_to_deg(
			fx._brass_basis(i).y.normalized().angle_to(Vector3.UP)))
		_settle(fx, i)
	for i in 8:
		var up: Vector3 = fx._brass_basis(i).y
		worst = maxf(worst, rad_to_deg(up.normalized().angle_to(Vector3.UP)))
	v.check("a rested casing lies flat, having tumbled on the way down",
		worst < 5.0 and tilted > 20.0,
		"worst tilt at rest %.4f degrees; worst in flight %.4f" % [worst, tilted])


# --- the muzzle smoke ---------------------------------------------------------

## Everything here drives the LIVE quad — `visible`, a basis column's length,
## `global_position`, `material_override` — for the reason `atmosphere.gd`'s own
## `burst_quad()` comment gives: the art can be right, the material can be right,
## and whether the layer ever reaches the screen can be covered by nothing. That
## has already happened once on this exact file.
static func _smoke(v: Verify, main: Node3D) -> void:
	var atmos: Node3D = main.atmos
	var p: Player = main.player
	var guns_was: Array = p.guns
	var slot_was: int = p.slot
	var yaw_was: float = p.rotation.y
	var vis := Rng.stream(Rng.VISUAL)
	var vis_was: int = vis.state
	_arm(main, "mp40")

	# DRAWS FIRST, AND THAT IS LOAD-BEARING. `_smoke_material` reads `albedo_color`
	# off the live material, and the value it must read is the one `_tick_smoke`
	# wrote — not the one the constructor seeded. Run the other way round, the
	# colour-space claim would be green against a `_tick_smoke` that converted on
	# every frame, which is precisely the defect it exists to catch.
	_smoke_draws(v, main, atmos)
	_smoke_material(v, atmos)
	_smoke_streams(v, atmos, main)
	_smoke_anchor(v, main, atmos)

	atmos._smoke = 0.0
	atmos._smoke_quad.visible = false
	atmos._muzzle_t = 0.0
	atmos.flash_quad().visible = false
	atmos.burst_quad().visible = false
	atmos._muzzle_light.visible = false
	p.rotation.y = yaw_was
	p.guns = guns_was
	p.slot = slot_was
	vis.state = vis_was


static func _smoke_material(v: Verify, atmos: Node3D) -> void:
	var mat: StandardMaterial3D = atmos.smoke_quad().material_override

	# THE ASYMMETRY THIS EXISTS FOR. `verify.gd:1039-1052` builds `wanted` from the
	# declared accessors and `seen` from the warm pass, and reports members of
	# `wanted` missing from `seen` — so a material never DECLARED is never in
	# `wanted` and is never missed, and `main.gd:174` feeds the warm pass from the
	# same accessor, which means an undeclared material is absent from both sides
	# and no existing assertion in the project can see it. Asked from the live node
	# outward, which is the direction that catches it.
	v.check("the smoke material the renderer was handed is declared for the warm pass",
		mat != null and atmos.materials().has(mat),
		"mat=%s declared=%d" % [mat, atmos.materials().size()])

	# The four calls that are decisions rather than details. BLEND_MIX is the one
	# with a named failure mode: additive smoke would push overlapping pixels past
	# GLOW_THRESHOLD 0.92 and put a bloomed grey blob on the muzzle.
	var flash_pri: int = atmos.flash_quad().material_override.render_priority
	v.check("the smoke quad is mixed, unshaded, depth-free and sorted behind the flash",
		mat.blend_mode == BaseMaterial3D.BLEND_MODE_MIX
			and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
			and mat.no_depth_test
			and mat.render_priority < flash_pri,
		"blend=%d shading=%d no_depth=%s priority %d vs flash %d" % [
			mat.blend_mode, mat.shading_mode, mat.no_depth_test,
			mat.render_priority, flash_pri])

	# THE COLOUR SPACE, which is what shipped two black frames. The expectation is
	# built from the ancestor's own bytes — html:2581's `{r:70,g:64,b:58}` — rather
	# than pasted as decimals, so it is provenance and not a snapshot. Wrapping the
	# authored value in `srgb_to_linear()` drops it to about (0.061, 0.051, 0.042)
	# and this goes red.
	var want := Color(70.0 / 255.0, 64.0 / 255.0, 58.0 / 255.0)
	var c: Color = mat.albedo_color
	v.check("the smoke carries the ancestor's own display-space grey, unconverted",
		v.near(c.r, want.r, 1e-4) and v.near(c.g, want.g, 1e-4)
			and v.near(c.b, want.b, 1e-4),
		"albedo (%.5f, %.5f, %.5f) want (%.5f, %.5f, %.5f)" % [
			c.r, c.g, c.b, want.r, want.g, want.b])


## The three that fail against the inert version — the one where `_on_fired` never
## touches `_smoke`, the quad is built and never made visible, and the material is
## built and registered. Against the material checks above, that version is
## perfectly green.
static func _smoke_draws(v: Verify, main: Node3D, atmos: Node3D) -> void:
	var q: MeshInstance3D = atmos.smoke_quad()
	var at := _shot_at(main)

	atmos._smoke = 0.0
	q.visible = false
	atmos._on_fired(at)
	var before: bool = q.visible
	atmos._process(STEP)
	var after: bool = q.visible
	var w0: float = q.global_transform.basis.x.length()
	v.check("a shot puts smoke on the muzzle one frame later",
		not before and after and w0 > 0.0,
		"visible %s -> %s, width %.6f" % [before, after, w0])

	# It ANIMATES. Both size and alpha, because pinning either one alone would leave
	# the other still moving and a check on one of them green.
	var w_last := w0
	var a_last: float = atmos._smoke_mat.albedo_color.a
	var stuck := 0
	for i in 10:
		atmos._process(STEP)
		var w: float = q.global_transform.basis.x.length()
		var a: float = atmos._smoke_mat.albedo_color.a
		if w >= w_last or a >= a_last:
			stuck += 1
		w_last = w
		a_last = a
	v.check("the puff shrinks and fades on every frame",
		stuck == 0, "%d of 10 steps did not shrink or did not fade" % stuck)

	# It GOES AWAY, and this is also the check that catches the `_process`
	# early-return trap: with the smoke tick written after the flash clock's guard
	# it freezes the instant FLASH_TIME's 0.05 s elapses and the puff hangs on
	# screen for the rest of the match. One over DECAY is the longest a saturated
	# bore can take, so it bounds every start value.
	var steps := int(ceil(1.0 / ATMOS.SMOKE_DECAY / STEP)) + 1
	for i in steps:
		atmos._process(STEP)
	v.check("the smoke clears within one over its decay rate",
		not q.visible and atmos.smoke_heat() == 0.0,
		"visible=%s heat=%.6f after %d steps" % [q.visible, atmos.smoke_heat(),
			steps])

	# HEAT ACCUMULATES, and this is the one thing separating the design from "a
	# puff". Without it HEAT_GAIN can be zero and the three checks above stay green.
	# 0.06 s is the PM-63's own shot interval — weapons.gd:29, 1000 rpm.
	atmos._smoke = 0.0
	atmos._on_fired(at)
	atmos._process(STEP)
	var one: float = q.global_transform.basis.x.length()
	atmos._smoke = 0.0
	for i in 20:
		atmos._on_fired(at)
		atmos._process(0.06)
	var many: float = q.global_transform.basis.x.length()
	v.check("sustained fire grows the puff past what a single shot reaches",
		many > one * 1.05,
		"twenty shots %.6f m against one shot %.6f m" % [many, one])


## Constraint 6 from the cosmetic side, with smoke now in the same handler. The
## flash's own draw is the ONE the fired path is allowed; the smoke may add none,
## and the sixty frames it then lives may add none either — which is where a
## "turbulence" roll would go.
static func _smoke_streams(v: Verify, atmos: Node3D, main: Node3D) -> void:
	var at := _shot_at(main)
	var gameplay: Array[StringName] = [Rng.SPAWN, Rng.BOX, Rng.DROPS, Rng.ROUNDS,
		Rng.AI]
	var was: Array[int] = []
	for s: StringName in gameplay:
		was.append(Rng.stream(s).state)
	var vis := Rng.stream(Rng.VISUAL)

	# THE ORACLE, and a subtraction will not do. `RandomNumberGenerator.state` is a
	# 64-bit UNSIGNED counter surfaced through a signed int, so `after - before` is
	# meaningless the moment it crosses the sign bit — the first draft of this check
	# reported "kick spent -221314142572561958". A clone advanced by exactly the
	# draws the handler is allowed is the only sound comparison, and it is the idiom
	# `checks/frame.gd:1074-1079` already uses.
	atmos._smoke = 0.0
	var oracle := RandomNumberGenerator.new()
	oracle.seed = vis.seed
	oracle.state = vis.state
	oracle.randf()
	var after_one: int = oracle.state
	atmos._on_fired(at)
	var kick_ok: bool = vis.state == after_one
	var vis_mid: int = vis.state
	for i in 60:
		atmos._process(STEP)
	var tick_ok: bool = vis.state == vis_mid

	var moved := ""
	for i in gameplay.size():
		if Rng.stream(gameplay[i]).state != was[i]:
			moved += str(gameplay[i]) + " "
	v.check("adding smoke leaves the fired path at exactly one VISUAL draw, and its frames spend none",
		moved.is_empty() and kick_ok and tick_ok,
		"perturbed [%s]; one-draw kick %s, sixty drawless frames %s" % [moved,
			kick_ok, tick_ok])


## THE LOAD-BEARING IDEA IN THE WHOLE SMOKE DESIGN, and without this check the
## rejected "place it once and let it drift" alternative and the shipped design are
## indistinguishable to the suite.
##
## `flash_anchor()` returns a world point that projects onto the drawn barrel for
## the camera pose AT THE INSTANT OF THE CALL. The flash gets away with calling it
## once because it lives 0.05 s; a puff living most of a second shears off the
## barrel at the camera's angular rate. Bounded at both ends: the quad has to have
## MOVED with the camera, and it has to have landed exactly on the fresh anchor.
static func _smoke_anchor(v: Verify, main: Node3D, atmos: Node3D) -> void:
	var p: Player = main.player
	var q: MeshInstance3D = atmos.smoke_quad()
	var at := _shot_at(main)

	atmos._smoke = 0.0
	atmos._on_fired(at)
	atmos._process(STEP)
	var before: Vector3 = q.global_position

	p.rotation.y += PI * 0.5
	atmos._process(STEP)
	var after: Vector3 = q.global_position
	var want: Vector3 = main.viewmodel.flash_anchor(FIRE_DEPTH)

	v.check("the smoke re-anchors to the barrel every frame rather than once at the shot",
		after.distance_to(want) < 1e-6 and before.distance_to(after) > 0.05,
		"after a 90 degree flick the quad is %.8f m from the anchor and %.5f m from where it was" % [
			after.distance_to(want), before.distance_to(after)])


# --- the reciprocating group, and the reload that drives it -------------------
#
# WHY THESE LIVE HERE, for the same reason the brass and the smoke do one section
# up: a new `checks/*.gd` needs two registration lines in `verify.gd`, this package
# owns that file only as far as the floor constant, and a module on disk without
# them turns `--verify` red for every other agent in the tree. The ordering
# constraint the research note gave for them is satisfied anyway — `_measure()`
# caches its FOV ratio on first call, and `verify.gd::_viewmodel` has already made
# that call by the time CHECK_SYSTEMS runs.
#
# WHAT THEY EXIST TO CATCH. Before this package `grep -rn
# 'SLIDE_TRAVEL|_slide_offset|_cycle_slide|_locked' scripts/dev/` returned ZERO
# lines: the animated group had no assertion of any kind, on any weapon, in any
# state. The one place `scripts/dev` touched it at all was
# `checks/projectiles.gd:837`, which reads `slide_corners()` for a top-edge walk and
# never applies the group's own offset — so `SLIDE` could have had every row but the
# M1911's emptied, and travel set to zero, with the whole suite green.

## The frame the projection puts a viewmodel point at, in pixels, at 1280x720.
##
## The rig's projection is FULLY DETERMINED IN CLOSED FORM and this is not an
## approximation of it. `viewmodel.gd`'s shader forces `PROJECTION_MATRIX[1][1]` to
## +/-1/tan(VIEWMODEL_FOV/2) whatever the camera's own field of view is, and scales
## `[0][0]` by the same factor, so the vertical half-angle is exactly 27.5 degrees
## and a point at view-space `p` lands at `(H/2)/tan(27.5) * p.x / -p.z` from the
## frame's centre column. VERIFIED against a rendered capture: this predicts the
## `ads` scenario's silhouette at x 606..673 and `shot_setup.gd` records it measured
## at exactly x 606..673.
const SHOT_W := 1280.0
const SHOT_H := 720.0

## How many pixels of the M1911's reciprocating group must NOT be end-on at the
## sights, at 720p.
##
## **Zero is what shipped, and zero is not an estimate — it is exact.** At the
## sighted pose `ADS_CENTRE` and `ADS_LEVEL` are both 1.0, so the lateral offset and
## the cant are gone and the profile yaw is the ONLY thing left that can separate
## the front of the group from the back of it on screen. With `ADS_YAW` at 1.0 the
## two project onto the same column, to the bit, on every weapon.
##
## MEASURED through the projection at the shipped `ADS_YAW` 0.95: the M1911 reads
## 1.71 px and the MP40 0.41 px, the difference being that the MP40's cocking-handle
## strip is 10 art units long against the M1911's 32-unit slide. So the floor is
## stated on the M1911, the flagship and the weapon the frames gate photographs, and
## every other group is only required to be off zero — which is still the whole
## claim, because zero is exactly what the defect produced.
##
## **A RATIO WAS TRIED FIRST AND IS THE WRONG SHAPE HERE, which is worth recording
## because "prefer a ratio" is this project's own rule.** The obvious denominator is
## the same separation at the hip — but the hip pose carries `REST_POS.x`, 38 mm of
## lateral offset, and PERSPECTIVE on that offset spreads the group's ends by 56 px
## before any yaw is involved. The hip figure is therefore 90.8 px where the yaw is
## worth 40 of them, and the ratio understates the survival by 2.5x. The rule holds
## generally and did not hold here; the ceiling is supplied by the probe-rect check
## instead, which is the other jaw.
const ADS_GROUP_MIN_PX := 1.0


static func _project(p: Vector3) -> Vector2:
	var k := (SHOT_H * 0.5) / tan(0.5 * deg_to_rad(VIEWMODEL.VIEWMODEL_FOV))
	var d := maxf(-p.z, 0.0001)
	return Vector2(SHOT_W * 0.5 + k * p.x / d, SHOT_H * 0.5 - k * p.y / d)


## Every corner of one weapon, body and group, in mesh space.
static func _all_corners(key: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var body: PackedVector3Array = GUNART.body_corners(key)
	var slide: PackedVector3Array = GUNART.slide_corners(key)
	out.append_array(body)
	out.append_array(slide)
	return out


## Put one weapon in hand and let the rig latch it, through `_show`, then let it
## SETTLE. Both halves are load-bearing and the second one was learned here.
##
## The latch: `_slide_travel` and `_slide_mode` are read on the frames the mesh
## changes and never otherwise, so a test that writes `p.guns` and reads the offset
## without stepping is reading the PREVIOUS weapon's mechanism.
##
## The settle: `_show` early-returns when the key has not changed, so handing the
## rig a FRESH gun of the SAME kind — a full magazine where the last section left an
## empty one — changes the rest pose without changing the mesh, and the rig
## correctly answers that with a release stroke. Reading the offset on the next
## frame then reads a weapon mid-cycle and calls it a resting pose. Twelve frames is
## 0.2 s against a 0.06 s hand-worked stroke.
static func _equip(main: Node3D, key: String, mag := -1) -> Node3D:
	var vm: Node3D = main.viewmodel
	_arm(main, key)
	if mag >= 0:
		main.player.current_gun().mag = mag
	main.player.weapon_changed.emit(main.player.current_gun())
	for i in 12:
		vm._process(STEP)
	return vm


## The group's drawn displacement, in units of that weapon's own travel. Read off
## `_slide.position` — the transform the renderer is handed — and not off any of the
## floats behind it.
static func _slide_f(vm: Node3D, key: String) -> float:
	var travel: float = GUNART.slide_travel(key)
	if travel <= 0.0:
		return 0.0
	return float(vm._slide.position.z) / travel


static func _animation(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var guns_was: Array = p.guns
	var slot_was: int = p.slot
	var held_was: bool = p._fire_held
	var buf_was: float = p._fire_buffer
	var vel_was: Vector3 = p.velocity

	_slide_table(v)
	_slide_travel_bounds(v)
	_slide_direction(v, main)
	_slide_modes(v, main)
	_slide_bolt_hold(v, main)
	_segmented_reload(v)
	_shell_cycles(v, main)
	_arc_sweep(v, main)
	_ads_geometry(v, main)
	_ads_asymmetry(v, main)

	p._fire_held = held_was
	p._fire_buffer = buf_was
	p.velocity = vel_was
	p.guns = guns_was
	p.slot = slot_was
	# THE POSE HAS TO GO BACK TOO, and finding that out cost three red assertions in
	# `checks/frame.gd`. Hundreds of driven frames of firing leave `_sprint` eased all
	# the way to SPRINT_DROP — 12 mm — and every later check that reads
	# `_mesh.transform` against REST_POS then measures a weapon that is still lowered.
	# `move_toward` at SPRINT_RATE 0.08 m/s would need 0.15 s of stepping to come back
	# and this suite steps no frames of its own, so the channels are put back by hand.
	var vm: Node3D = main.viewmodel
	vm._sprint = 0.0
	vm._swap = 0.0
	vm._dip = 0.0
	vm._kick = 0.0
	vm._kick_v = 0.0
	vm._melee_t = 0.0
	vm._slide_t = 0.0
	vm._slide_delay = 0.0
	# `_apply()` and NOT `_process()`: `_tick_states` would recompute `_sprint` from
	# whatever state the restored gun is in and put the drop straight back, which is
	# how this restore failed the first time it was written.
	vm._apply()


## THE DECISION, PINNED — not a law discovered from the rects, because the rects do
## not separate the rows this table deletes from the row it keeps.
##
## The obvious predicate ("every index in SLIDE names a part that overlaps its
## weapon's receiver in x") scores the AK-74u's part 7 and the MP40's part 6
## IDENTICALLY: two units of overlap each. It would leave `"ak74u": [7]` green under
## its own control. So this asserts the decision, with the reason beside each row,
## and it is honest about being a pin: change any row and it goes red, which is
## exactly what should happen to a mechanism claim nobody re-argued.
static func _slide_table(v: Verify) -> void:
	var want := {
		# The slide plate, its rib, and the two sights milled into it.
		"m1911": [1, 6, 7, 8],
		"olympia": [],      # break-action, and its motion is the reload
		"m14": [],          # op rod, external, on the far flank
		"mp40": [6],        # cocking handle: no gas system, so the strip cannot be a gas tube
		"pm63": [1],        # the slide IS the reciprocating mass
		"ak74u": [],        # part 7 is the gas tube; the handle is on the far flank
		"stakeout": [2],    # the pump fore-end
		"m16": [],          # carrier internal, port cover on the far flank
		"rpk": [],          # part 8 is the gas tube; the handle is on the far flank
		"chinalake": [6],   # the pump under the launcher tube
		"raygun": [],
		"thundergun": [],
		"knife": [],
	}
	var wrong := ""
	for key: String in GUNART.keys():
		var got: Array = GUNART.SLIDE.get(key, [])
		var mine: Array = want.get(key, [])
		if got != mine:
			wrong += "%s got %s want %s " % [key, got, mine]
	v.check("every weapon's reciprocating group is the one the mechanism argues for",
		wrong.is_empty() and want.size() == GUNART.keys().size(), wrong)

	# A group that names a part index its weapon does not have matches nothing,
	# `_build` returns null and `_show` hides the mesh — the weapon loses its bolt in
	# SILENCE. `SLIDE` has no bounds check anywhere: `SLIDE.get(key, [])`,
	# `slide.has(i)`, and no assertion until this one.
	var oob := ""
	for key: String in GUNART.keys():
		var n: int = GUNART._parts(key).size()
		for i: int in GUNART.SLIDE.get(key, []):
			if i < 0 or i >= n:
				oob += "%s:%d of %d " % [key, i, n]
	v.check("no group names a part its weapon does not have", oob.is_empty(), oob)


## Travel bounded at BOTH ends, and the ceiling is COMPUTED rather than pasted.
##
## The floor is one cartridge overall length through that weapon's own drawn scale —
## a breech that does not open by at least one cartridge cannot feed — and it is
## hardcoded here with its cartridge and its scale, because it comes from outside
## the repo. The ceiling is `GUNART.slide_free_run`, walked out of `ART` at the same
## `PROUD` inflation the mesh is built at, because a pasted ceiling was wrong on all
## three weapons the research had one for (it was measured to the `GRIP` ANCHOR,
## which is a hand position and not a part).
static func _slide_travel_bounds(v: Verify) -> void:
	# cartridge OAL / (weapon OAL / drawn span), in art units. Sources beside each.
	var floors := {
		"m1911": 5.55,      # .45 ACP 32.4 mm, 210-216 mm over 37 units
		"mp40": 2.85,       # 9x19 29.69 mm, 833 mm (stock EXTENDED, as drawn) over 80
		"pm63": 2.55,       # 9x18 25.0 mm, 583 mm (extended) over 59.5
		"stakeout": 7.00,   # 2.75in 69.85 mm, ~838 mm over 84 — the OAL is an estimate
		"chinalake": 8.78,  # 40x46 98.4 mm, 876.3 mm over 78.2
	}
	# The two rows the drawn art cannot honour, and WHY each is taken anyway. Listed
	# rather than tolerated, so a third one cannot arrive without an argument.
	var departures := {
		"pm63": "contact at 2 units against a 2.55 floor: the art affords NO valid stroke, and the folding-stock strut is proud of the slide, so the overlap is concealed by the same LAYER/PROUD stacking that puts a highlight over its plate",
		"chinalake": "8 units is 89.7 mm against a 98.4 mm grenade AND meets the drawn pistol grip: a cap forced by the art at both ends",
	}
	var missing := ""
	var low := ""
	var high := ""
	for key: String in GUNART.keys():
		var group: Array = GUNART.SLIDE.get(key, [])
		if group.is_empty():
			continue
		if not GUNART.TRAVEL.has(key):
			missing += key + " "
			continue
		var units: float = float(GUNART.TRAVEL[key])
		var floor_units: float = float(floors.get(key, 0.0))
		var run: float = GUNART.slide_free_run(key)
		if units < floor_units and not departures.has(key):
			low += "%s %.1f under floor %.2f " % [key, units, floor_units]
		if units > run and not departures.has(key):
			high += "%s %.1f over free run %.2f " % [key, units, run]
	v.check("no group travels less than one cartridge, except where it is recorded",
		missing.is_empty() and low.is_empty(), missing + low)
	v.check("no group travels further than the drawn art allows, except where it is recorded",
		high.is_empty(), high)

	# THE OTHER JAW, and it is what stops the exemption list outliving the thing it
	# exempts: a listed departure has to actually BE outside its bounds. Move the
	# China Lake's pistol grip back two units and this goes red until the row comes
	# off the list.
	var stale := ""
	for key: String in departures:
		var units: float = float(GUNART.TRAVEL[key])
		var run: float = GUNART.slide_free_run(key)
		var floor_units: float = float(floors.get(key, 0.0))
		if units >= floor_units and units <= run:
			stale += "%s %.1f is inside [%.2f, %.2f] and needs no exemption " % [
				key, units, floor_units, run]
	v.check("every recorded travel departure is still a departure", stale.is_empty(),
		stale)


## Direction, driven through the real path and anchored to the ANCESTOR.
##
## The gun is put in a non-EMPTY state first and that is not tidiness: with an empty
## magazine `_rest_pose` pins a bolt-hold weapon at full travel, so the "zero at
## rest" half would fail for a reason that has nothing to do with direction.
static func _slide_direction(v: Verify, main: Node3D) -> void:
	var vm := _equip(main, "m1911")
	var at := _shot_at(main)

	var rest: float = float(vm._slide.position.z)
	main.player.fired.emit(at)
	vm._process(STEP)
	var moved: Vector3 = vm._slide.position

	# The displacement is pure model +Z and the muzzle sits above the grip, so the
	# two are NOT antiparallel — the angle between them runs 6.3 to 9.5 degrees
	# across the seven weapons with a group. The SIGN is exactly true and keeps the
	# ancestor's own MUZZLE table (`gunart.gd:112`, from html:2020) as the anchor:
	# the group moves away from the barrel end, whichever way the barrel end is.
	var muzzle: Vector3 = GUNART.muzzle_local("m1911")
	v.check("the group moves back along the weapon's own axis, away from the muzzle",
		is_zero_approx(rest) and is_zero_approx(moved.x) and is_zero_approx(moved.y)
			and moved.z > 0.0 and signf(moved.z) == -signf(muzzle.z),
		"rest %.6f moved %s muzzle.z %.5f" % [rest, moved, muzzle.z])

	# BOUNDED AT BOTH ENDS. Without the acceptance half the clause above passes
	# perfectly against a rig whose group has stopped moving at all.
	var peak := 0.0
	for i in 8:
		peak = maxf(peak, absf(float(vm._slide.position.z)))
		vm._process(STEP)
	v.check("a shot actually displaces the group, and it comes back",
		peak > GUNART.slide_travel("m1911") * 0.5
			and is_zero_approx(float(vm._slide.position.z)),
		"peak %.6f of %.6f, settled at %.6f" % [peak, GUNART.slide_travel("m1911"),
			float(vm._slide.position.z)])


## The three mechanisms, told apart by what they do at rest and on the first frame
## after the shot. This is the check that separates a weapon whose cycle runs
## BACKWARDS from the same slide at a different speed.
static func _slide_modes(v: Verify, main: Node3D) -> void:
	var at := _shot_at(main)

	# CLOSED: rest at battery, first motion rearward.
	var vm := _equip(main, "m1911")
	var closed_rest := _slide_f(vm, "m1911")
	main.player.fired.emit(at)
	vm._process(STEP)
	var closed_first := _slide_f(vm, "m1911")

	# OPEN: rest HELD BACK, first motion FORWARD. The MP40's cocking handle is on
	# the near flank, so this is the one weapon on the roster where running the cycle
	# backwards is guaranteed to be seen.
	vm = _equip(main, "mp40")
	var open_rest := _slide_f(vm, "mp40")
	main.player.fired.emit(at)
	vm._process(STEP)
	var open_first := _slide_f(vm, "mp40")

	v.check("an open bolt rests held back and runs forward, and a closed one does the opposite",
		is_equal_approx(closed_rest, 0.0) and closed_first > 0.0
			and is_equal_approx(open_rest, 1.0) and open_first < 1.0,
		"closed %.4f -> %.4f, open %.4f -> %.4f" % [closed_rest, closed_first,
			open_rest, open_first])

	# PUMP: a pump gun does not move at the instant of the shot. Still at rest one
	# frame later, moved by the middle of the interval, home again by the end of it.
	vm = _equip(main, "stakeout")
	main.player.fired.emit(at)
	vm._process(STEP)
	var pump_first := _slide_f(vm, "stakeout")
	var interval := 60.0 / float(Weapons.TABLE["stakeout"].rpm)
	var pump_peak := 0.0
	var frames := int(interval / STEP) + 2
	for i in frames:
		vm._process(STEP)
		pump_peak = maxf(pump_peak, _slide_f(vm, "stakeout"))
	v.check("a pump racks between shots and not at the shot",
		is_equal_approx(pump_first, 0.0) and pump_peak > 0.5
			and is_zero_approx(_slide_f(vm, "stakeout")),
		"at the shot %.4f, peak over the interval %.4f, at the end %.4f" % [
			pump_first, pump_peak, _slide_f(vm, "stakeout")])

	# R5, and the reason it is not a smaller constant: at 1000 rpm the PM-63's
	# interval is 0.060000 s against the old 0.06 s cycle, so a held PM-63 restarted
	# a stroke it had never finished. A self-cycling action's cycle IS its interval,
	# which also makes Double Tap speed the bolt up. Asserted as the RELATION and not
	# as a number, so retuning any rpm cannot leave this behind.
	var wrong := ""
	for key: String in ["mp40", "pm63", "ak74u", "rpk", "m16"]:
		vm = _equip(main, key)
		if GUNART.slide_travel(key) <= 0.0 or GUNART.SLIDE.get(key, []).is_empty():
			continue
		main.player.fired.emit(at)
		var want := 60.0 / float(Weapons.TABLE[key].rpm)
		if not is_equal_approx(float(vm._slide_len), want):
			wrong += "%s cycle %.5f want %.5f " % [key, float(vm._slide_len), want]
	v.check("a self-cycling action's stroke lasts exactly its own fire interval",
		wrong.is_empty(), wrong)


## The hold-open, driven to the state a PLAYER reaches rather than by writing `mag`.
##
## `_show` only latches the weapon's mechanism on the frames the mesh changes, so a
## test that pokes `gun.mag` and reads the offset can pass while `_shown_key` still
## names the previous weapon. Firing the magazine dry through `player._update_fire`
## is the consumer, and it is also the only way to reach the state that matters:
## an empty MAGAZINE with a live reserve, which is what precedes every reload.
static func _slide_bolt_hold(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var wrong := ""
	# m1911 holds (slide stop). mp40 does not — no hold-open device of any kind, and
	# an open bolt runs FORWARD on an empty magazine. pm63 holds (Wikipedia, FB PM-63
	# RAK: locked open on the slide catch), and under OPEN its locked pose and its
	# ready pose coincide, which is why it is here for being true rather than visible.
	for row: Array in [["m1911", 1.0], ["mp40", 0.0], ["pm63", 1.0]]:
		var key: String = row[0]
		var want: float = row[1]
		var vm := _equip(main, key)
		p.velocity = Vector3.ZERO
		var gun: Dictionary = p.current_gun()
		var fired := 0
		for i in 600:
			if int(gun.mag) <= 0:
				break
			p._fire_held = true
			p._fire_buffer = 1.0
			p._update_fire(STEP)
			vm._process(STEP)
			fired += 1
		p._fire_held = false
		p._fire_buffer = 0.0
		# Let the last shot's own stroke finish; the pose under test is where the
		# group COMES TO REST, not where it is mid-cycle.
		for i in 10:
			p._update_fire(STEP)
			vm._process(STEP)
		var got := _slide_f(vm, key)
		if int(gun.mag) > 0 or not is_equal_approx(got, want):
			wrong += "%s mag=%d rested at %.4f want %.4f after %d ticks " % [
				key, int(gun.mag), got, want, fired]
	v.check("the two weapons with a last-round hold-open hold, and the one without does not",
		wrong.is_empty(), wrong)


## The segmented reload, bounded at both ends — which is exactly the bound this
## file's own rule was written for, because a check on the top-up alone passes
## against a reload that has stopped completing.
static func _segmented_reload(v: Verify) -> void:
	var gun := Weapons.make_gun("stakeout", false)
	var cap: int = int(gun.def.mag)
	var full: float = float(gun.def.reload)

	# A FULL reload from empty still costs exactly the tabled figure. That is the
	# invariant `begin_reload` has always advertised and it is what keeps the
	# segments out of the balance surface: the ratios redistribute the 3.4 s, they do
	# not add to it.
	gun.mag = 0
	WEAPON.begin_reload(gun, 1.0)
	var t := 0.0
	var loaded := 0
	while t < 20.0 and int(gun.state) == WEAPON.State.RELOAD_SHELL:
		WEAPON.tick(gun, STEP, false)
		t += STEP
	loaded = int(gun.mag)

	# ...and a ONE-SHELL top-up pays the whole fixed overhead. It used to be linear —
	# reload / mag — so topping up one shell cost a sixth of a full reload for a sixth
	# of the benefit, and there was never a reason not to tap R after every shot.
	var top := Weapons.make_gun("stakeout", false)
	top.mag = cap - 1
	WEAPON.begin_reload(top, 1.0)
	var t2 := 0.0
	while t2 < 20.0 and int(top.state) == WEAPON.State.RELOAD_SHELL:
		WEAPON.tick(top, STEP, false)
		t2 += STEP
	var linear := full / float(cap)

	# The window is one physics tick per SEGMENT and not a round tolerance: `tick`
	# ends a segment on the first tick its timer crosses zero, so a reload of N
	# shells runs N+1 segments and can overshoot by up to N+1 ticks. Bounded BELOW at
	# the tabled figure as well, because that is the half a shortened reload breaks.
	var segments := cap + 1
	v.check("a shell reload from empty fills the tube and still costs the tabled time",
		loaded == cap and t >= full - STEP and t <= full + float(segments) * STEP,
		"loaded %d of %d in %.3f s against %.3f (+%d ticks allowed)" % [loaded, cap, t,
			full, segments])
	v.check("a one-shell top-up pays the start and end segments rather than one shell's share",
		int(top.mag) == cap and t2 > linear * 2.0 and t2 < full,
		"top-up %.3f s against one linear shell %.3f and a full reload %.3f" % [
			t2, linear, full])

	# THE OLYMPIA IS NOT A TUBE. It hinges open, both hulls come out together and two
	# rounds go in together, so a per-shell cancel on it is incoherent rather than
	# merely inaccurate. BO1 agrees at the file level (`rottweil72_zm`,
	# `segmentedReload = 0`), and the ancestor's `shells:true` at html:1460 is what
	# this departs from.
	var oly := Weapons.make_gun("olympia", false)
	oly.mag = 0
	WEAPON.begin_reload(oly, 1.0)
	var t3 := 0.0
	while t3 < 20.0 and int(oly.state) == WEAPON.State.RELOADING:
		WEAPON.tick(oly, STEP, false)
		t3 += STEP
	v.check("the Olympia reloads as one break-open action and not shell by shell",
		not bool(oly.def.shells) and int(oly.mag) == int(oly.def.mag)
			and absf(t3 - float(oly.def.reload)) < 0.05,
		"shells=%s loaded %d in %.3f s against %.3f" % [bool(oly.def.shells),
			int(oly.mag), t3, float(oly.def.reload)])


## THE MOST VISIBLE ANIMATION DEFECT REACHABLE FROM SIGNALS THAT ALREADY EXIST: a
## six-shell Stakeout reload racked the pump exactly once.
##
## Counted off `_slide.position` — the transform the renderer is handed — by counting
## upward crossings of half travel, not off any counter the rig keeps. Driven
## through `player._start_reload` and `player._update_fire`, which are what the
## reload key reaches.
static func _shell_cycles(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var six := _count_reload_cycles(main, 0)
	var one := _count_reload_cycles(main, int(Weapons.TABLE["stakeout"].mag) - 1)
	# One at the start of the reload, then one per shell landing — the sawtooth
	# `weapon.gd` has emitted since it was written and nothing consumed until now,
	# with the closing segment supplying the last one.
	var want_six := int(Weapons.TABLE["stakeout"].mag) + 1
	v.check("a shell reload cycles the group once per shell and not once per reload",
		six[0] == want_six and one[0] == 2,
		"six shells cycled %d (want %d), one shell cycled %d (want 2); rig counted %d and %d" % [
			six[0], want_six, one[0], six[1], one[1]])
	p._fire_held = false
	p._fire_buffer = 0.0


## Drive one real reload and count how many times the group actually strokes.
## Returns [crossings of half travel, the rig's own stroke counter].
static func _count_reload_cycles(main: Node3D, start_mag: int) -> Array:
	var p: Player = main.player
	var vm := _equip(main, "stakeout")
	var gun: Dictionary = p.current_gun()
	gun.mag = start_mag
	p._fire_held = false
	p._fire_buffer = 0.0
	var before: int = int(vm._slide_cycles)
	p._start_reload()
	var half := GUNART.slide_travel("stakeout") * 0.5
	var crossings := 0
	var was_up := float(vm._slide.position.z) > half
	var guard := 0
	while guard < 1200:
		p._update_fire(STEP)
		vm._process(STEP)
		var up := float(vm._slide.position.z) > half
		if up and not was_up:
			crossings += 1
		was_up = up
		guard += 1
		if int(gun.state) != WEAPON.State.RELOAD_SHELL and float(vm._slide.position.z) <= 0.0:
			break
	return [crossings, int(vm._slide_cycles) - before]


## The arc construction, in three parts: it is CORRECT, it is SOLVED rather than
## tabulated, and it is the one `_measure()` actually calls.
##
## The third is the part that matters. A sampler that is perfectly correct and never
## reached by the sweep is this project's own "projectile tunnelling test that passed
## with the sweep deleted".
static func _arc_sweep(v: Verify, main: Node3D) -> void:
	var vm: Node3D = main.viewmodel

	# CORRECTNESS. Two samples across a 0.5 rad arc of unit radius: the chord between
	# them, pushed out by 1/cos(step/2), passes through radius exactly 1 at the
	# midpoint, so the arc is inside the polygon. Without the push it passes through
	# cos(0.25) = 0.9689 and the arc is OUTSIDE — which is an under-estimate, the one
	# direction a safety bound may not err in.
	var amp := 0.5
	var samples: Array[float] = [0.0, amp]
	var grow: float = VIEWMODEL._arc_grow(samples, amp)
	var a := Vector2(cos(0.0), sin(0.0))
	var b := Vector2(cos(amp), sin(amp))
	var chord_inflated := (a * grow + b * grow) * 0.5
	var chord_plain := (a + b) * 0.5
	v.check("the arc sampler circumscribes its arc rather than being inscribed in it",
		chord_inflated.length() >= 1.0 - 1e-9 and chord_plain.length() < 1.0,
		"inflated midpoint radius %.9f, plain %.9f" % [chord_inflated.length(),
			chord_plain.length()])

	# SOLVED, AND MINIMAL. The property, not a copy of the expression: at the count
	# the solver returns the excess is inside tolerance, and at one fewer it is not.
	# A solver that returned ARC_MAX_SAMPLES for everything would satisfy the first
	# half and fail the second.
	var ratio := tan(0.5 * deg_to_rad(main.player.camera().fov)) \
		/ tan(0.5 * deg_to_rad(VIEWMODEL.VIEWMODEL_FOV))
	var r := 0.06
	var bad := ""
	for arc: float in [VIEWMODEL.DIP_ROLL,
			VIEWMODEL.REST_YAW * VIEWMODEL.ADS_YAW
				+ absf(VIEWMODEL.REST_PITCH) * VIEWMODEL.ADS_LEVEL,
			absf(VIEWMODEL.KICK_PITCH) * VIEWMODEL.KICK_MAX,
			absf(VIEWMODEL.MELEE_ROT)]:
		var k: int = VIEWMODEL._arc_k(arc, r, ratio)
		var at_k := ratio * r * (1.0 - cos(arc / float(k) * 0.5))
		var at_less := ratio * r * (1.0 - cos(arc / float(maxi(k - 1, 1)) * 0.5))
		if k >= VIEWMODEL.ARC_MAX_SAMPLES or at_k > VIEWMODEL.ARC_TOL \
				or (k > 1 and at_less <= VIEWMODEL.ARC_TOL):
			bad += "arc %.4f -> K=%d excess %.6f (K-1 gives %.6f) " % [arc, k, at_k,
				at_less]
	v.check("every rotational channel is sampled just finely enough to stay conservative",
		bad.is_empty(), bad)

	# THE CONSUMER, in two halves, because the construction has two independent parts
	# and one check covering both would let either of them die quietly. MEASURED with
	# the inflation alone removed: `widest` came back IDENTICAL to the endpoint sweep
	# to six decimals, so the extra samples buy nothing on that metric and everything
	# it gains is the circumscription — while `nearest` moved from 0.057496 to
	# 0.057368, which is the extra samples and nothing else. Two mechanisms, two
	# metrics, two checks.
	var interior: Vector3 = vm.sweep(true)
	var endpoints: Vector3 = vm.sweep(false)
	# The SAMPLES. A rotated point's nearest approach to the lens is not at either
	# end of its arc, and this is the only number in the sweep that can say so.
	v.check("the interior samples find a corner the endpoints of the arc miss",
		interior.y < endpoints.y,
		"nearest %.6f interior against %.6f at the endpoints" % [interior.y,
			endpoints.y])
	# The CIRCUMSCRIPTION, which is what makes the result an over-estimate rather
	# than an under-estimate — the one direction a safety bound may not err in. And
	# the interior figure is the one the guarantee is stated against, so it still has
	# to clear the capsule.
	v.check("the circumscribed sweep bounds the endpoint one from above, and still fits",
		interior.z > endpoints.z and interior.x >= endpoints.x
			and interior.z < Player.RADIUS,
		"widened %.6f vs %.6f, plain %.6f vs %.6f, capsule %.3f" % [
			interior.z, endpoints.z, interior.x, endpoints.x, Player.RADIUS])

	# THE READOUT, and it is the only thing in the project that can tell whether the
	# group's far end is still in the corner pool at all. Every component of the
	# sweep is insensitive to travel by construction, so the refusal above passes
	# against a sweep that dropped the travel endpoint entirely.
	var swept: Dictionary = vm.swept_travels()
	var stale := ""
	for key: String in GUNART.keys():
		var want: float = GUNART.slide_travel(key)
		var got: float = float(swept.get(key, -1.0))
		if not is_equal_approx(got, want):
			stale += "%s swept %.6f want %.6f " % [key, got, want]
	v.check("the clip sweep collected every weapon's group at that weapon's own travel",
		stale.is_empty() and swept.size() == GUNART.keys().size(),
		"%s(%d of %d)" % [stale, swept.size(), GUNART.keys().size()])


## The sighted pose, as the closed-form projection rather than as a photograph.
##
## `viewmodel.gd:180-188` states in its own words why twelve degrees of profile yaw
## exists — "extruded flat plates viewed from behind read as a stack of rectangles"
## — and `ADS_YAW` at 1.0 removed all of it at the one pose where the player is
## studying the weapon hardest. Reducing it is R10; this is the bound that makes the
## reduction safe to make, because the frames gate's own `ads` probe rect is 80 px
## wide and a weapon that grows out of it stops being measured rather than failing.
static func _ads_geometry(v: Verify, main: Node3D) -> void:
	var vm: Node3D = main.viewmodel
	var rect: Rect2i = SHOT_SETUP.VM_RECT_ADS
	var narrow := ""
	var outside := ""
	for key: String in ["m1911", "mp40", "rpk"]:
		var sight: float = GUNART.sight_height(key)
		var hip: Transform3D = vm._mesh_pose(0.0, 0.0, 0.0, 0.0, 0.0, sight)
		var ads: Transform3D = vm._mesh_pose(0.0, 0.0, 0.0, 0.0, 1.0, sight)
		var lo := INF
		var hi := -INF
		for p: Vector3 in _all_corners(key):
			var s := _project(ads * p)
			lo = minf(lo, s.x)
			hi = maxf(hi, s.x)
		# THE METRIC, AND IT TOOK TWO TRIES. The first version measured the group's
		# projected WIDTH and it was a bad metric: 93% of that number is the
		# thickness of the group's own extrusion caps, which sit either side of x = 0
		# and barely move with yaw, so it read 38.6 px where the yaw was worth 1.7 of
		# them. This one takes every group corner ON THE MID-PLANE — x forced to zero,
		# which deletes the cap term outright — and measures how far apart the front
		# and the back of the group project. At the sighted pose that separation IS
		# the surviving profile yaw and nothing else, so the shipped defect reads
		# exactly zero rather than reading small.
		var s_lo := INF
		var s_hi := -INF
		var h_lo := INF
		var h_hi := -INF
		var group: PackedVector3Array = GUNART.slide_corners(key)
		for p: Vector3 in group:
			var mid := Vector3(0.0, p.y, p.z)
			var s := _project(ads * mid)
			s_lo = minf(s_lo, s.x)
			s_hi = maxf(s_hi, s.x)
			var h := _project(hip * mid)
			h_lo = minf(h_lo, h.x)
			h_hi = maxf(h_hi, h.x)
		var floor_px := ADS_GROUP_MIN_PX if key == "m1911" else 0.05
		if not group.is_empty() and s_hi - s_lo < floor_px:
			narrow += "%s group profile %.2f px at the sights (want %.2f), %.1f at the hip " % [
				key, s_hi - s_lo, floor_px, h_hi - h_lo]
		# ...and the whole weapon has to stay inside the rect the gate measures it
		# in. 3 px of margin, because a silhouette touching the edge is a silhouette
		# that may be clipped by it, and a clipped probe reports a number about the
		# rectangle rather than about the weapon.
		if lo < float(rect.position.x) + 3.0 or hi > float(rect.end.x) - 3.0:
			outside += "%s spans %.1f..%.1f against rect %d..%d " % [key, lo, hi,
				rect.position.x, rect.end.x]
	v.check("the sighted pose keeps some of its profile yaw rather than going edge-on",
		narrow.is_empty() and VIEWMODEL.ADS_YAW < 1.0,
		"ADS_YAW=%.3f %s" % [VIEWMODEL.ADS_YAW, narrow])
	v.check("the sighted weapon stays inside the frames gate's own probe rect",
		outside.is_empty(), outside)


## **THIS CHECK IS EXPECTED TO BE RED, AND THAT IS ITS ENTIRE JOB.** It is the
## tripwire for a hunk in `player.gd`, which this package does not own — and per
## this project's own rule a reported hunk without a failing check gets dropped
## silently. That is not hypothetical here: ADS shipped once with its camera half
## and not its weapon half in exactly this way, and this is the same subsystem.
##
## THE HUNK, `scripts/entities/player.gd`. Add beside `ADS_TIME` (`:186`):
##
##     ## ...and coming OUT of the sights is slower than going in. `move_toward`
##     ## with one rate both ways gave the sighted pose no commitment cost, which is
##     ## most of what ADS is for as a decision. BO1's own weapon files are
##     ## consistently asymmetric: the MP40's `adsTransInTime` is 0.22 — an exact
##     ## corroboration of the number above, which this file had guessed and
##     ## hand-waved as "about a quarter of a second" — against roughly 0.4 out.
##     const ADS_OUT_TIME := 0.40
##
## and at `:642` replace
##
##     _ads = move_toward(_ads, to, dt / ADS_TIME)
##
## with
##
##     _ads = move_toward(_ads, to, dt / (ADS_TIME if want else ADS_OUT_TIME))
##
## `want` is already in scope two lines above.
##
## DRIVEN THROUGH THE REAL FUNCTION and not through the constant: `_update_ads` is
## called with the sights released — `_wants_ads()` is false headless because it
## polls `Input` — so what is measured is the rate the player actually leaves the
## sights at. The way IN cannot be driven headlessly for the same reason, so it is
## compared against `ADS_TIME`, which is the rate the way in uses today and the
## number the hunk leaves alone.
static func _ads_asymmetry(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var was: float = p._ads
	p._ads = 1.0
	var steps := 0
	while p.ads() > 0.0 and steps < 600:
		p._update_ads(STEP)
		steps += 1
	var out_t := float(steps) * STEP
	p._ads = was
	p._update_ads(STEP)
	# 1.5x rather than the reference's 1.8x, so the hunk is not pinned to one exact
	# constant — what is being asserted is that leaving the sights COSTS something,
	# not that it costs 0.40 s.
	v.check("coming out of the sights is slower than going into them",
		out_t > Player.ADS_TIME * 1.5,
		"REPORTED HUNK, NOT YET LANDED (player.gd is another package's file): out %.3f s against ADS_TIME %.3f — see this function's docstring for the exact edit" % [
			out_t, Player.ADS_TIME])


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
