extends RefCounted

## The weapon state machine: every transition a gun can make, in one place.
##
## A gun is a Dictionary built by Weapons.make_gun(), and it stays one — main.gd,
## hud.gd and the assertion suite all read that dictionary directly, so promoting it
## to a class would be a four-file change that bought no behaviour. What was
## actually missing was arbitration. Fire, reload and swap were three independent
## floats that nobody reconciled: a swap cost nothing and cancelled nothing, a gun
## stowed mid-reload froze its own countdown, and an empty chamber re-triggered its
## click on every physics tick. The floats are still the wire format; the functions
## below are now the only writers of them.
##
## Everything is static and takes the gun as its first argument. Nothing here reads
## global state: the two things that scale a weapon's timing — Double Tap's rate
## multiplier and Speed Cola's reload multiplier — arrive as parameters, so a
## transition can be reasoned about, and asserted against, without a perk table
## existing. Sounds are likewise the caller's job; this module moves numbers.
##
## Fields owned here, and what a viewmodel should bind to:
##
##   state      one of State below — the animation that should be playing.
##   state_t    seconds left in the current state; 0.0 in a state with no natural
##              end (IDLE, EMPTY).
##   state_len  that state's full length, so `1.0 - state_t / state_len` is
##              normalised progress. RELOAD_SHELL resets it once per shell, which
##              gives an animation a sawtooth per shell out of the same expression
##              and means no second signal has to exist for it.
##   reloading  the reload clock's old public face. hud.gd:868-869 prints "--" for
##              the magazine while it is above zero and this package does not own
##              that file, so it is maintained as a mirror of state_t across the two
##              reload states and held at zero everywhere else.
##   next_shot  the fire cooldown. Allowed to run *past* zero inside a tick, which
##              is the whole of the fire-rate fix — see tick().
##   shell_unit the segmented reload's ratio unit in seconds, latched by
##              begin_reload so that every later segment scales by the same Speed
##              Cola multiplier the first one did. A perk bought mid-reload must not
##              shorten the reload it is already inside — that is a state machine
##              reading a clock it does not own — and there is nowhere else to keep
##              it: state_len is the CURRENT segment and the segments differ.


## The states a carried weapon can be in. Every one of them is either something a
## viewmodel has to draw differently or something that changes whether the trigger
## does anything, which is the test for whether it earns a value.
enum State {
	IDLE,          # up, loaded, waiting. The trigger works.
	FIRING,        # the cooldown between rounds. The trigger works; next_shot gates it.
	RELOADING,     # one magazine, one timer, no interruptions.
	RELOAD_SHELL,  # one shell into the tube, then a decision. Firing interrupts it.
	SWAPPING,      # coming up after a swap or a hand-over. The trigger is dead.
	SPRINT_OUT,    # coming back up after a sprint. The trigger is dead.
	EMPTY,         # bolt-lock: nothing chambered and nothing left to chamber.
}

## kriegsnacht.html:3293 — `P.slot=1-P.slot; P.swapT=0.42`, with firing gated on
## `P.swapT>0` at :2510 and the viewmodel rising out of frame over the same window
## at :3136. The ancestor has no lowering phase and neither does this: a lower would
## have to own the *outgoing* gun's state, and that gun has to stay free to carry on
## reloading while stowed.
const SWAP_TIME := 0.42

## html:2667 — `giveGun()` sets `P.swapT=0.45`. A weapon handed over by a wall buy,
## the box or Pack-a-Punch is drawn from nothing rather than swapped to, and the
## ancestor gave that its own slightly longer figure.
const DRAW_TIME := 0.45

## html:2515 — `g.nextShot = G.t + 0.28` on a dry fire. Without it an automatic held
## down on an empty chamber re-triggers the click every physics tick, sixty times a
## second, which is what the port did.
const DRY_FIRE_LOCK := 0.28

## The shell reload's three segments, as RATIOS.
##
## BO1's `stakeout_zm` weapon file gives 1.000 s to bring the gun over and start,
## 0.567 s per shell, and 0.767 s to close the action and bring it back up (M5 F13,
## Tier 1). **Carried as ratios and not as seconds** so the invariant `begin_reload`
## has always advertised survives: *"a reload from empty still costs exactly the
## figure in the table and only a partial top-up gets cheaper."* One ratio unit is
## `def.reload / (START + EACH*mag + END)`, so a Stakeout emptied and refilled still
## costs its tabled 3.4 s — and the balance surface does not move — while the
## segments inside it are BO1's proportions.
##
## **This closes a live exploit.** The old shape was `reload / mag` per shell and
## nothing else, i.e. perfectly linear: topping a Stakeout up by one shell cost
## 0.567 s, a sixth of a full reload, so a player who fired one round and tapped R
## paid a sixth of the price for a sixth of the benefit and there was never a reason
## not to. With the fixed overhead in place a one-shell top-up costs 1.53 s against
## a full 3.4 s — 45% of the price for 17% of the benefit — which is the shape a
## segmented reload has in the reference and the reason it has one.
##
## **The ancestor has no opinion here.** `shells` is declared at html:1460/:1465 and
## read by nothing in the browser build, so every number in this block is ours or
## BO1's; there is nothing to be faithful to.
const SHELL_START := 1.000
const SHELL_EACH := 0.567
const SHELL_END := 0.767

## Bounds the sub-tick catch-up below. Nothing in the table comes close to a 1/60 s
## interval — the fastest is the PM63 under Double Tap at 1340 rpm, or 0.045 s — so
## the loop this guards runs exactly once today. It exists so that a faster weapon,
## or a physics tick rate someone lowers later, cannot empty a magazine inside one
## tick before anybody notices.
const MAX_SHOTS_PER_TICK := 4


## Advances one gun by one physics tick. Called for *every* gun the player carries,
## not just the one in hand: a stowed weapon used to freeze its reload countdown and
## resume it on swap-back, so an RPK's 4.6 s reload could be parked indefinitely and
## then finished for free in the two hundred milliseconds after you swapped to it.
##
## `hold_cadence` is true only when the trigger is actually demanding rounds from
## this weapon, and it decides whether the cooldown may hold a debt — see below.
static func tick(gun: Dictionary, dt: float, hold_cadence: bool) -> void:
	# THE FIRE-RATE FIX. This runs at a fixed 60 Hz, so a weapon whose interval is
	# not a whole number of ticks used to lose its remainder to `maxf(0.0, ...)` on
	# every shot and round *up* to the next tick boundary: the MP40's 880 rpm was
	# delivered as 720, the PM63's 1000 as 900, the AK-74u's 710 and the RPK's 700
	# both as 600 — so two pairs of weapons that are supposed to feel different
	# fired at literally identical cadences. Letting the cooldown cross zero and
	# adding the interval to whatever is left carries that remainder forward, and
	# the delivered rate becomes the stated one on average.
	var cooldown: float = gun.next_shot
	cooldown -= dt
	if hold_cadence:
		# The remainder can never legitimately exceed one tick, because the cooldown
		# is spent the moment it crosses zero. Flooring it there means a weapon that
		# is *blocked* rather than firing cannot quietly bank cadence and then open
		# with a double.
		gun.next_shot = maxf(cooldown, -dt)
	else:
		# Nothing is asking this weapon for rounds, so there is no cadence to keep.
		gun.next_shot = maxf(cooldown, 0.0)

	var state: int = gun.state
	if state == State.FIRING:
		# FIRING has one clock and it is next_shot; state_t is its readable mirror.
		_set_timer(gun, maxf(float(gun.next_shot), 0.0))
		# A weapon whose trigger is still down stays in FIRING across the moment the
		# cooldown expires — the round goes out later in the same tick. Dropping to
		# IDLE first would strobe the state, and anything animating off it, once per
		# round fired. An *empty* one is the exception and has to be let go, or a
		# weapon held down on a dead reserve never reaches EMPTY at all: the reload
		# it tries to start is refused, so nothing else would ever move it.
		if float(gun.next_shot) <= 0.0 and (not hold_cadence or int(gun.mag) <= 0):
			settle(gun)
		return

	var left: float = gun.state_t
	if left <= 0.0:
		return
	left -= dt
	if left > 0.0:
		_set_timer(gun, left)
		return

	_set_timer(gun, 0.0)
	match state:
		State.RELOADING:
			_finish_magazine(gun)
		State.RELOAD_SHELL:
			_load_shell(gun)
		_:
			settle(gun)


## Whether the trigger is connected at all. FIRING counts as connected: the rate
## limit is next_shot's job rather than the state's, and a semi-auto press during
## the cooldown still has to reach the input buffer instead of being swallowed.
static func can_fire(gun: Dictionary) -> bool:
	match int(gun.state):
		State.RELOADING, State.SWAPPING, State.SPRINT_OUT:
			return false
		State.RELOAD_SHELL:
			# Interruptible — but only into something there is actually a round for.
			return int(gun.mag) > 0
	return true


## The gun has just put a round downrange; the caller owns the ballistics, this owns
## the ammunition, the cadence and the state.
static func consume_shot(gun: Dictionary, rpm_scale: float) -> void:
	var interval := _interval(gun, rpm_scale)
	gun.mag = int(gun.mag) - 1
	# `+=`, not `=`. See tick().
	gun.next_shot = float(gun.next_shot) + interval
	gun.state = State.FIRING
	gun.state_len = interval
	_set_timer(gun, maxf(float(gun.next_shot), 0.0))


## A trigger pull on an empty chamber. The lockout is the ancestor's, and it is not
## decoration: an automatic weapon polls this path every physics tick, so without it
## the dry click plays sixty times a second for as long as the button is held.
static func dry_fire(gun: Dictionary) -> void:
	gun.next_shot = DRY_FIRE_LOCK


## Starts a reload if the weapon can take one. Returns whether it did, so the caller
## can decide what to play — a refusal is not always silence, and the bolt-lock case
## in particular used to produce no feedback of any kind.
static func begin_reload(gun: Dictionary, reload_scale: float) -> bool:
	var def: Dictionary = gun.def
	match int(gun.state):
		State.RELOADING, State.RELOAD_SHELL, State.SWAPPING:
			return false
	if int(gun.mag) >= int(def.mag) or int(gun.res) <= 0:
		return false
	if bool(def.shells):
		# The `shells` flag has been declared in the ancestor (html:1465) and read by
		# absolutely nothing — there or here. Shell-by-shell loading is therefore new
		# design rather than a restoration.
		#
		# **The first segment is the start AND the first shell**, which is R5's
		# "credit the first shell during the start": a Stakeout's opening motion
		# brings the gun over and puts a shell in, and splitting them would need a
		# fourth segment that credits nothing and refuses the trigger.
		var unit := _shell_unit(gun, reload_scale)
		gun.shell_unit = unit
		_enter(gun, State.RELOAD_SHELL, unit * (SHELL_START + SHELL_EACH))
	else:
		_enter(gun, State.RELOADING, float(def.reload) * reload_scale)
	return true


## Bringing a weapon up, after a swap or after being handed one. The raise
## overwrites a reload that was in progress, which is the whole of `stow_cancels`
## below — see it for why.
static func begin_swap(gun: Dictionary, duration: float) -> void:
	_enter(gun, State.SWAPPING, duration)


## Holstering. Called on the weapon being put away, not the one coming up.
##
## **Swapping cancels a reload, and the reload restarts from the beginning.** That
## is Call of Duty's rule, and it is the reason the ammunition counts survive: a
## magazine reload credits nothing until it completes, so abandoning it costs the
## time and nothing else, and a shell reload has already credited every shell it
## finished, so abandoning that one keeps them. Neither needs a special case,
## which is the point of crediting per shell in the first place.
##
## Note this is NOT what the ancestor does, and the difference is a bug rather
## than a decision on its side. html:2966 reads `const g = P.guns[P.slot]` and
## ticks only that one, so a stowed reload in the browser build neither completes
## nor cancels — it *freezes*, indefinitely, and resumes exactly where it stopped
## when you switch back. Nothing at html:3293 clears it. The port inherited that
## verbatim, so "the stowed-gun reload freeze" was never a porting mistake.
##
## Both available fixes are therefore departures from the ancestor, and the choice
## between them is a choice about which source is authoritative. Completing a
## stowed reload makes a swap strictly free — start a 4.6 s RPK reload, switch to
## the M1911, fight with it, and the RPK is full when you come back. Cancelling
## makes the swap cost something, which is what the real game charges for it.
static func stow_cancels(gun: Dictionary) -> void:
	match int(gun.state):
		State.RELOADING, State.RELOAD_SHELL:
			settle(gun)


## The weapon coming back up out of a sprint. Only from a settled state: a reload or
## a draw already owns the weapon, is longer than this is, and refuses the trigger
## on its own.
static func begin_sprint_out(gun: Dictionary, duration: float) -> void:
	match int(gun.state):
		State.IDLE, State.FIRING, State.EMPTY:
			_enter(gun, State.SPRINT_OUT, duration)


## The resting state a weapon falls back to when a timed state ends, and the way a
## shell reload is cancelled. Derived rather than remembered: EMPTY is exactly
## "nothing chambered and nothing to chamber", so it cannot drift out of step with
## the ammunition counts the way a stored flag would.
static func settle(gun: Dictionary) -> void:
	gun.state_len = 0.0
	if int(gun.mag) <= 0 and int(gun.res) <= 0:
		gun.state = State.EMPTY
		_set_timer(gun, 0.0)
		return
	if float(gun.next_shot) > 0.0 and int(gun.mag) > 0:
		# Reached when a cooldown outlives the state that interrupted it — a swap
		# finishing while the previous weapon's interval is still running. There is
		# no interval to quote here, so the remaining cooldown is the whole length
		# and a viewmodel sees a partial cycle rather than a wrong one.
		#
		# The magazine check matters because next_shot does double duty: the dry-fire
		# lockout lives in it too, and calling a bolt-locked weapon FIRING because it
		# just clicked would put a viewmodel into a recoil cycle for a round that was
		# never there.
		gun.state = State.FIRING
		gun.state_len = float(gun.next_shot)
		_set_timer(gun, float(gun.next_shot))
		return
	gun.state = State.IDLE
	_set_timer(gun, 0.0)


## Ammunition has arrived from outside — a Max Ammo, a wall buy, a fresh magazine.
## Two states have to answer for it and no others, because settling anything else
## would silently cancel a reload that still has work to do.
static func on_ammo_added(gun: Dictionary) -> void:
	var state: int = gun.state
	if state == State.EMPTY:
		# The bolt has to come off the lock, or the weapon sits dead holding ammo.
		settle(gun)
	elif _is_reload(state) and int(gun.mag) >= int(gun.def.mag):
		# A Max Ammo landing mid-reload fills the magazine outright, and what is left
		# is a reload with nothing to load: it would run its clock down, take zero
		# rounds, and refuse the trigger the whole time for nothing.
		settle(gun)


# --- internals ---------------------------------------------------------------

static func _interval(gun: Dictionary, rpm_scale: float) -> float:
	var def: Dictionary = gun.def
	return 60.0 / (float(def.rpm) * rpm_scale)


## One segment ratio unit, in seconds. See SHELL_START.
##
## maxf rather than a bare divide: a magazine of zero is not reachable from the
## table, but a division that produces INF here would hang the reload forever
## rather than failing loudly.
static func _shell_unit(gun: Dictionary, reload_scale: float) -> float:
	var def: Dictionary = gun.def
	var n := maxf(1.0, float(def.mag))
	var ratios := SHELL_START + SHELL_EACH * n + SHELL_END
	return (float(def.reload) / ratios) * reload_scale


static func _enter(gun: Dictionary, to: int, duration: float) -> void:
	gun.state = to
	gun.state_len = duration
	_set_timer(gun, duration)


static func _is_reload(state: int) -> bool:
	return state == State.RELOADING or state == State.RELOAD_SHELL


## The single writer of state_t, and therefore the single place the legacy
## `reloading` mirror can fall out of step — which is why there is only one.
static func _set_timer(gun: Dictionary, t: float) -> void:
	gun.state_t = t
	gun.reloading = t if _is_reload(int(gun.state)) else 0.0


static func _finish_magazine(gun: Dictionary) -> void:
	var def: Dictionary = gun.def
	var want: int = int(def.mag) - int(gun.mag)
	var take: int = mini(want, int(gun.res))
	gun.mag = int(gun.mag) + take
	gun.res = int(gun.res) - take
	settle(gun)


static func _load_shell(gun: Dictionary) -> void:
	var def: Dictionary = gun.def
	# A floor rather than a bare read. RELOAD_SHELL is only reachable through
	# begin_reload, which always latches the unit — but a zero here would enter a
	# zero-length segment, and tick() refuses to advance one, so the reload would
	# FREEZE rather than fail. Same reasoning as `_shell_unit`'s own maxf.
	var unit: float = maxf(float(gun.get("shell_unit", 0.0)), 0.001)
	# THE CLOSING SEGMENT, AND IT IS IDENTIFIED RATHER THAN FLAGGED. The tube can
	# only be full — or the reserve dry — at the top of this function if the segment
	# that just ended was the one entered after the last shell went in, because every
	# other path leaves at least one round to load. So there is no shell in the hand
	# and nothing to credit, and no fourth State value and no second flag are needed
	# to know it. (A new state was the obvious answer and is the wrong one:
	# `hud.gd:1491` compares against RELOAD_SHELL by value to decide whether to print
	# `--`, and hud.gd is not this package's file.)
	if int(gun.mag) >= int(def.mag) or int(gun.res) <= 0:
		settle(gun)
		return
	gun.mag = int(gun.mag) + 1
	gun.res = int(gun.res) - 1
	# Credited as it goes in, which is what makes cancelling honest: interrupt the
	# reload and you keep every shell already in the tube and lose only the one that
	# was on its way. Nothing has to be special-cased for that to hold — and note the
	# closing segment credits nothing, so an interrupt during it costs the player
	# nothing at all, which is the whole reason it is a segment and not a shell.
	#
	# Re-entered rather than continued in BOTH arms, so state_t sawtooths back to
	# state_len once per shell AND once more for the close. Nothing consumed that
	# sawtooth until this package: a six-shell Stakeout reload racked the pump once.
	if int(gun.mag) < int(def.mag) and int(gun.res) > 0:
		_enter(gun, State.RELOAD_SHELL, unit * SHELL_EACH)
	else:
		_enter(gun, State.RELOAD_SHELL, unit * SHELL_END)
