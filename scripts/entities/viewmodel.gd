extends Node3D

## The first-person weapon rig: a real 3D gun, in the world, in front of the lens.
##
## **The approach is geometric and it is not the usual one.** Every other answer to
## "the viewmodel clips through walls" fights the depth buffer — a second camera in
## a `SubViewport`, a `POSITION.z` squash, `no_depth_test` — and all three are
## either expensive or broken on this renderer (SYNTHESIS 4.1 lists them with the
## reason each was rejected). This one removes the premise instead: the player
## capsule has `RADIUS = 0.24`, so no solid surface can ever be within 0.24 m of
## the camera origin, and a weapon small enough stays in front of every wall by
## arithmetic rather than by trickery. Every number in the rest pose and every
## motion amplitude below is chosen against that budget, and `_measure()` checks
## the result so that adding a long-barrelled weapon later fails at build time
## instead of clipping in play.
##
## The gun is then made to read as full size by scaling **only** the two scale
## terms of the projection matrix in `vertex()`. No `POSITION` write, no `DEPTH`
## write, and the depth terms are untouched — which is what keeps the guarantee
## true rather than papered over, and what makes the whole technique immune to the
## reverse-Z breakage that invalidated every widely-copied viewmodel shader on
## 4.3+.
##
## **THE EXACT INVARIANT IS NOT "every vertex within 0.22 m", and getting that
## wrong is how this design fails silently.** The depth test happens per *pixel*,
## and the narrowed projection means a vertex at view-space `p` is drawn at the
## pixel a *world* point in the direction `(ratio*p.x, ratio*p.y, p.z)` would
## occupy, with `ratio = tan(74/2)/tan(55/2)` = 1.4476. Setting the gun's depth
## below the nearest world depth at that pixel and reducing gives one clean
## condition:
##
##     sqrt(p.z^2 + ratio^2 * (p.x^2 + p.y^2))  <  Player.RADIUS
##
## — an ordinary radius with the lateral terms stretched by the projection. At
## `ratio = 1` it collapses to the plain sphere the plan assumed, which is why the
## plain sphere looked sufficient and is not. Measured over every weapon, every
## pose and every sway the rig can reach, the worst is **0.232 m against 0.24**;
## the plain radius is 0.201 and the nearest depth 0.0575 m against a 0.05 m near
## plane. `max_screen_radius()` is the assertion that matters — the plain
## `max_corner_radius()` would pass a weapon that clips. 0.24 is itself the
## worst-case-over-all-directions figure (a wall the player is pressed flat
## against, seen along a horizontal ray); the corner that produces 0.232 is drawn
## 42 degrees below the view axis, where the nearest wall is 0.24/cos(42) = 0.32 m,
## so the margin in play is nearer 39% than 3%.
##
## Node chain, and rule "one writer per node" applies with full force:
##
##   Camera3D
##   └ ViewmodelRoot   (this node)  sway and bob — written only by _apply()
##     └ WeaponMesh                 rest pose, recoil, reload, swap, melee
##       ├ Slide                    the reciprocating group, z only
##       └ MuzzlePoint              static per weapon; read by flash_anchor()
##
## Everything is driven from the weapon state machine that already exists
## (`scripts/entities/weapon.gd`): `Player.weapon_state_changed` for the two things
## that are genuinely edges, and `state`/`state_t`/`state_len` read per frame for
## everything with a clock. There is no second notion anywhere in this file of what
## the weapon is doing.

## preload rather than the class name for both: a freshly added script is not in
## the class registry until the editor rescans, and a headless run has no editor.
const GUNART := preload("res://scripts/data/gunart.gd")
const WEAPON := preload("res://scripts/entities/weapon.gd")


# --- the projection override -------------------------------------------------

## Narrower than the world's 74, which is what makes a 10 cm object read as a
## 70 cm weapon. 55 is the value M1-viewmodel-systems.md R1 carries and it is what
## `GUNART.UNIT` was solved against; the two have to move together, because
## halving the apparent size by widening this is not the same as halving the mesh.
##
## The ratio between this and the camera's own field of view — `tan(74/2) /
## tan(55/2)` = 1.4476 — is the number the rest of the file keeps running into. It
## is how much wider the weapon is drawn than a world object at the same place,
## and therefore both the correction `flash_anchor()` applies and the reason the
## clip budget is anisotropic. It is never written down as a constant: the shader
## derives it from the matrix it is handed, and `flash_anchor` and `_measure`
## derive it from `_cam.fov`, so a camera whose FOV ever changes cannot leave a
## stale copy behind.
const VIEWMODEL_FOV := 55.0

## One `Shader` for every weapon in the game, and therefore one GLSL compile — the
## same bargain `zombie.gd`'s rim shader makes, and it matters here for the reason
## M1's own measurement M3 names: threads are off, so a shader compiled the first
## time the player draws the Ray Gun is a visible hitch at the worst possible
## moment.
##
## `unshaded`, and that is a decision rather than a shortcut. The torch is a
## `SpotLight3D` **at the camera origin** with `spot_attenuation = 1.25`, and
## Godot's distance term is `d^-decay`: at the 0.12 m this mesh sits at, that is a
## multiplier of about eleven, times an energy of 3.1. A lit viewmodel is a white
## silhouette in every frame of the game. The alternatives are a `light_cull_mask`
## change in `player.gd`, which this package does not own, or a custom `light()`
## whose built-ins cannot be checked without a rendered frame. Unshaded is also
## what the ancestor did — its viewmodel is a flat canvas with painted highlight
## strips, and `GUNART` still carries those strips — and it takes the eight-light
## fragment loop off the largest object on screen. The form comes from a key light
## baked into the vertex colours at build time; see `gunart.gd`'s `FILL`/`KEY`.
const VM_CODE := """shader_type spatial;
render_mode unshaded, cull_back;

uniform float viewmodel_fov : hint_range(20.0, 120.0) = 55.0;
uniform float flash = 0.0;

void vertex() {
	// Only the two scale terms, and *scaled* rather than assigned. The depth terms
	// [2][2] and [2][3] are deliberately untouched, so this mesh's depth stays
	// consistent with the world's and the no-clip argument stays a fact about the
	// geometry rather than a trick.
	//
	// Scaling instead of writing absolute values is what answers M-VMFOV rather
	// than deferring it. Every widely-copied version of this shader writes
	// 1/tan(fov/2) straight into [1][1], and they disagree with each other about
	// its sign because they were written against renderers that disagree; they
	// also rebuild the aspect from VIEWPORT_SIZE, which is wrong the moment a
	// camera uses KEEP_WIDTH. Multiplying both terms by
	// tan(camera_fov/2) / tan(viewmodel_fov/2), which is what the two lines below
	// work out to because abs([1][1]) is already 1/tan(camera_fov/2), inherits
	// whatever sign, aspect and keep-mode the engine put there. Nothing left to
	// measure, and nothing left to get wrong on a renderer nobody has run it on.
	//
	// (ASCII only in here on purpose: every other shader in this project is, and
	// the preprocessor is not a place to find out whether that mattered.)
	float k = 1.0 / tan(0.5 * radians(viewmodel_fov));
	float widen = k / abs(PROJECTION_MATRIX[1][1]);
	PROJECTION_MATRIX[0][0] *= widen;
	PROJECTION_MATRIX[1][1] *= widen;
}

void fragment() {
	ALBEDO = COLOR.rgb * (1.0 + flash);
}
"""

## The *design* budget: how big the weapon is allowed to be before anyone thinks
## about projections. `Player.RADIUS` is 0.24, so nothing solid can be closer than
## that to the camera origin, and 0.22 leaves two centimetres for the capsule's own
## skin and for a convex corner.
##
## Kept, and asserted, because it is the number a person adding a weapon can hold
## in their head — but it is **not** the guarantee. See the header: the guarantee
## is `max_screen_radius() < Player.RADIUS`, and a weapon can satisfy this constant
## and still fail that one.
const CLIP_RADIUS := 0.22


# --- the rest pose -----------------------------------------------------------

## Where the grip sits, in camera space. Right, below the centre, and far enough
## forward that the deepest stock in the table (the M14's, 42 art units behind its
## grip) clears the camera's 0.05 m near plane with a centimetre to spare even
## with the recoil pulling the weapon back.
##
## The z is what the whole budget turns on: at `GUNART.UNIT` the worst corner over
## every weapon and every pose lands 0.201 m from the lens against the 0.22 m
## design ceiling, the nearest 0.0575 m along it against the 0.05 m near plane, and
## the projection-widened radius the header derives at 0.232 m against
## `Player.RADIUS`'s 0.24. `_measure()` re-derives all three from the same corners
## the meshes are built from.
##
## All three are attained at `ads = 0`, and that is worth writing down because it is
## not obvious: the sighted pose now drops each weapon by up to 20 mm at the grip
## (`ADS_SIGHT_CLEAR`), which sounds like it should move the lateral term. It does
## not. Levelling the cant pulls the muzzle back onto the axis and `ADS_FORWARD`
## pushes the stock 8 mm away from the near plane, and both more than pay for the
## drop — the sighted extremes come out strictly inside the hip ones. Measured
## against the pose this replaced, all three agreed to six decimal places
## (0.201249 / 0.057540 / 0.231884, delta 0.000000), so these figures are unchanged
## by the sighted pose rather than merely still rounding to the same thing.
const REST_POS := Vector3(0.038, -0.032, -0.1161)

## -0.13 rad of muzzle-down cant, and both halves of it are the ancestor's:
## `-0.09` baked into the drawing (html:1216, "slight tilt so it doesn't read as a
## flat cutout") plus the `-0.04` its draw call adds every frame (html:3122). They
## carry across unchanged because under `gunart.gd`'s axis mapping a canvas
## `rotate(t)` is exactly a rotation of `t` about world +X.
const REST_PITCH := -0.13

## 12 degrees of inward yaw, so the barrel converges toward the crosshair.
##
## **Invented, and it is doing real work.** A viewmodel pointing straight down the
## view axis is seen almost end-on, and this art is a side profile: extruded flat
## plates viewed from behind read as a stack of rectangles. Twelve degrees opens
## the profile without moving the muzzle far enough off-axis for `flash_anchor()`
## to look wrong. It is the first number to change if a rendered frame says the
## weapon reads badly, and changing it cannot break the clip budget — a rotation
## about the grip does not move any corner further from the grip.
const REST_YAW := 0.2094


# --- turning the ancestor's screen fractions into metres ----------------------

## The ancestor moved a *sprite* by fractions of the screen. Those numbers still
## mean something here, because a fraction of the screen is an angle and an angle
## at a known depth is a distance: a point `d` in front of the lens moves through
## `2 * f * d / onetanfov` metres to travel `f` of the screen's height, and
## `2 * f * d * aspect / onetanfov` to travel `f` of its width.
##
## Evaluated once, at authoring time, at the grip's own depth (0.1161 m), at
## `VIEWMODEL_FOV` (`onetanfov` = 1.92098) and at 16:9. Every ancestor amplitude
## below is one of these two numbers times the fraction the ancestor used, and the
## fraction is quoted with the line it came from. Nothing recomputes this at
## runtime — the live aspect only has to be right in the shader, where it is.
const M_PER_H := 0.12088
const M_PER_W := 0.21489


# --- bob ---------------------------------------------------------------------

## `sway = sin(bobPhase) * cssW*0.005` and `bobY = |cos(bobPhase)| * cssH*0.012`
## (html:3116-3117). The vertical term is one-sided by construction — `|cos|` —
## so the weapon dips and returns rather than oscillating about its rest height,
## which is what the ancestor drew and is also what keeps the budget honest.
const BOB_X := 0.00107          # 0.005 of screen width
const BOB_Y := 0.00145          # 0.012 of screen height

## The amplitude follows the player's actual speed, and it eases rather than
## switching: a bob that appears the instant a key goes down reads as a stutter.
## Invented; the ancestor's bob had no amplitude term at all.
const BOB_AMP_RATE := 3.0
const BOB_AMP_MAX := 1.6


# --- sway --------------------------------------------------------------------

## Weapon sway from view movement, as a lag rather than a translation: the rig
## rotates about the camera origin, so a turn leaves the gun behind and it catches
## up. Rotating about the origin also happens to be the one motion that cannot
## change how far any vertex is from the lens, which is why the sway is here and
## not on the mesh.
##
## Invented in its numbers — the ancestor has no mouse sway — but the *shape* is
## M1-viewmodel-systems.md F5, including the detail that earns its place there:
## the return is `move_toward` and not `lerp`, because `lerp` is asymptotic and
## produces the weapon that never quite re-centres.
##
## Driven from the camera's own basis rather than from input events. The player
## owns the mouse; reading where the camera actually ended up costs nothing, needs
## no event plumbing, and stays correct for any other thing that ever turns the
## view.
const SWAY_PER_RATE := 0.030    # radians of lag per radian/second of turn
const SWAY_MAX := 0.05          # about 2.9 degrees, and the clip budget assumes it
const SWAY_RATE := 0.9          # radians/second toward the target, both ways


# --- recoil ------------------------------------------------------------------

## The ancestor's damped oscillator (html:2960), same stiffness and damping as the
## view kick in `player.gd`, so the weapon and the camera settle together instead
## of beating against each other. The impulse is the weapon's own `kick` from the
## table, which is what the ancestor fed it too (`viewKickV += d.kick`, html:2525).
##
## This is the *weapon* kick, and it is separate from the view kick on purpose —
## M1 F4: view kick rotates a camera ancestor and changes where bullets go, weapon
## kick moves the weapon and is pure cosmetics. `player.gd` already owns the first
## on `RecoilPivot`, and this rig inherits it through the node chain.
const KICK_SPRING := 46.0
const KICK_DAMP := 11.0

## A bound, not a behaviour. The spring is impulsive and the impulses stack: an
## MP40 puts 1.1 into the velocity every 68 ms, faster than the spring bleeds it,
## so sustained fire climbs. Something has to cap that for the no-clip guarantee to
## be provable rather than empirical, and a weapon that stops climbing after about
## two and a half single-shot peaks is also what a braced weapon does.
const KICK_MAX := 1.2

## `y += viewKick*cssH*0.03` and `rot += viewKick*0.05` (html:3119, :3122) — the
## ancestor's own coefficients, converted through M_PER_H. The gun drops and the
## muzzle rises, which together are the weapon rocking back about the hand.
const KICK_DOWN := 0.003626     # 0.03 of screen height per unit of kick
const KICK_PITCH := 0.05        # radians per unit of kick, verbatim

## Straight back toward the shoulder. **Invented** — the ancestor's viewmodel was a
## 2D sprite and had no depth to travel in. Sized against the near plane rather
## than by eye: the deepest stock in the table already sits 7 mm clear of it once
## the sway has been rotated through, and a kick that spends more than 6 mm of
## that is a weapon whose butt is sliced open by the near plane under sustained
## fire. `min_corner_depth()` is what holds this honest.
const KICK_BACK := 0.005


# --- reload, swap, sprint, melee ---------------------------------------------

## `rel = 1-(reloading/reloadMax); s = sin(rel*PI)` then `y += s*cssH*0.30`,
## `rot += s*0.5`, `x += s*cssW*0.03` (html:3121-3128). A single arc down and back
## with a half-radian roll at its peak. `state_t`/`state_len` give exactly the same
## `rel` for free, which is what those two fields were added for.
const DIP := 0.03623            # 0.30 of screen height
const DIP_X := 0.00644          # 0.03 of screen width
const DIP_ROLL := 0.5           # radians, verbatim
## How fast the dip may unwind when it is *interrupted*. Only reachable through
## `RELOAD_SHELL` — firing cancels a shell reload mid-shell, which is most of the
## reason to load shell by shell at all — and it is the one place a pose has to
## return to rest without a clock telling it how.
const DIP_RATE := 6.0

## A shell is not a magazine. `RELOAD_SHELL` re-enters itself once per shell, so
## `state_t` sawtooths and the same `sin(rel*PI)` arc repeats — at a third of the
## amplitude, because a Stakeout's six shells at the full magazine arc is a weapon
## thrashing. Invented; the ancestor never distinguished the two reloads.
const SHELL_SCALE := 0.35

## `if(P.swapT>0) y += (P.swapT/0.45)*cssH*0.42` (html:3136) — the weapon rises
## into frame out of the bottom of the screen over the swap window. The port reads
## the fraction off `state_t/state_len` instead of off a hard-coded 0.45, which is
## also a bug fix: the ancestor divides a 0.42 s swap by 0.45 and starts it 7%
## short of the bottom.
const SWAP_DROP := 0.05072      # 0.42 of screen height

## Lowered while sprinting. Invented — the ancestor has no sprint pose — and small
## on purpose: this is a cue that the weapon is not ready, not a holster.
const SPRINT_DROP := 0.012
const SPRINT_RATE := 0.08       # metres/second, eased both ways

## The sighted pose: the weapon comes to the centre line, levels off, and drops
## until the eye is looking along the top of it.
##
## Invented — the ancestor has no ADS — and sized against the clipping budget rather
## than by eye. Removing the rest pose's lateral offset entirely can only REDUCE
## max_screen_radius (whose lateral terms are weighted by `ratio`), and 8 mm forward
## sits well inside the 7 mm of near-plane clearance plus the 12 mm the kick does not
## spend. `_measure()` sweeps both ends, so the budget is measured at the sights too.
##
## `Player.ads()` drives it rather than a clock of this file's own: ADS owns the
## camera's field of view, and the pose has to arrive with the zoom or the gun swims.
##
## **`ADS_CENTRE` ALONE PUTS THE GRIP ON THE VIEW AXIS, AND THE SIGHTS ARE NOT AT
## THE GRIP.** They sit on top of the weapon, and this rig shipped without noticing:
## the M1911's whole sight line sat 66 px above the crosshair in a 720 px frame — the
## weapon raised by exactly its own sight height, and the player aiming underneath
## it. Measured off the `ads` scenario at 1280x720, --fixed-fps 60, as the top of the
## silhouette differenced against the same frame with the viewmodel hidden.
const ADS_CENTRE := 1.0         # fraction of REST_POS.x/y removed at the sights
const ADS_FORWARD := 0.008
const ADS_YAW := 1.0            # fraction of REST_YAW removed at the sights

## ...so the whole rig drops by the weapon's own sight height as well, and the cant
## comes out with it.
##
## At full ADS the weapon's TOP PLANE — its sighting surface, whichever part of that
## weapon happens to be highest — sits `ADS_SIGHT_CLEAR` art units BELOW the view
## axis, and `ADS_LEVEL` removes `REST_PITCH` so the barrel runs level to that axis
## instead of 7.4 degrees under it. The eye then looks along the top of the weapon
## straight to the crosshair, which is what a hard scope is, and every weapon shows
## the same hairline of its own top plane however tall it is.
##
## The height is `GUNART.sight_height()`, PER WEAPON and derived from the corner walk
## the mesh is built from — 5.05 art units on the knife against 19.24 on the Ray Gun,
## so a single constant would bury the Olympia and float the M16. See that function.
##
## **ONE ART UNIT IS OUR DECISION.** The ancestor has no ADS, so there is nothing to
## transliterate and no number to be faithful to; the provenance is the sweep below,
## run with the cant already levelled, and read off the frames rather than argued.
## The silhouette is located by differencing the capture against the same scenario
## with the viewmodel hidden, so the number is the weapon and not a colour guess —
## the M1911's slide is the only blue-grey thing in the table and a mask tuned to it
## cannot tabulate the other twelve.
##
##   clear   top of silhouette   read at 6x
##   0       row 360, on it      the crosshair's ticks merge into the top edge; the
##                               lower tick disappears into the metal
##   1       5 px below          the ticks read as ticks against the background and
##                               the top plane is a hairline directly under them
##   2       9 px below          an obvious band of background between the two
##   3       14 px below         the weapon has detached from the aim point and
##                               reads as held low
##
## 1 is the smallest clearance at which the crosshair is still legible against the
## background, which is what looking down an iron sight looks like. For scale, the
## shipped pose put this top edge at row 294 — 66 px ABOVE the crosshair.
const ADS_LEVEL := 1.0          # fraction of REST_PITCH removed at the sights
const ADS_SIGHT_CLEAR := 1.0    # art units of clear air under the top plane

## Every lowering channel shares one budget, because the no-clip guarantee is a
## bound on the sum and not on each. In play only one is ever meaningfully lit —
## the states are mutually exclusive — so this bites for at most the one frame
## after a reload is interrupted by a swap.
const DROP_MAX := 0.05072
const DROP_RATE := 0.5          # metres/second, on the way back to rest only

## `mt = P.bowie?0.42:0.55; s = sin((1-P.meleeT/mt)*PI)` then `x -= s*cssW*0.24`,
## `y -= s*cssH*0.06`, `rot -= s*0.85` (html:3129-3135). The knife sweeps left
## across the screen and turns over as it goes. 0.55 rather than the ancestor's
## two-value table because `player.gd:611` sets a flat `_knife_cooldown = 0.55`
## whether or not the Bowie is held, and the pose has to end when the swing does.
const MELEE_TIME := 0.55
const MELEE_X := -0.0515        # 0.24 of screen width, left
const MELEE_Y := 0.00725        # 0.06 of screen height, up
const MELEE_ROT := -0.85        # radians, verbatim


# --- the reciprocating group -------------------------------------------------

## Four art units of travel at `GUNART.UNIT`, back along the weapon's own axis.
## Not a `Tween`: at 880 RPM that would allocate about fifteen of them a second,
## which is exactly the allocation-inside-the-fire-loop this project keeps out of
## every other hot path. It is one float.
const SLIDE_TRAVEL := 0.0042
const SLIDE_TIME := 0.06
## Back fast, forward slower — a slide is thrown by gas and returned by a spring.
## The whole cycle is shorter than the fastest weapon's interval, so a held
## automatic restarts it rather than compounding it. Invented.
const SLIDE_BACK := 0.30


# --- muzzle flash ------------------------------------------------------------

## The gun lights up when it fires. Multiplies the baked albedo for the same
## 0.05 s `main.gd` holds the muzzle light for, so the two agree without either
## knowing about the other. Invented.
##
## 1.35x is small enough that no gun metal in the table reaches `lighting.gd`'s
## 0.92 glow threshold under it — the brightest highlight strip in the table gets
## to 0.27 — so the only things that bloom on a shot are the Ray Gun's lens and the
## Thundergun's emitters, which bloom anyway. The knife's blade *would* cross it at
## 1.16, and does not matter: a knife cannot fire.
const FLASH_PEAK := 0.35
const FLASH_TIME := 0.05


## Unambiguously sprinting: halfway between the walk speed and the sprint speed,
## both of which are public constants on `Player`. Derived from `velocity` rather
## than from an input poll or a private flag, so it stays true for anything that
## ever moves the player, and so this file keeps no second opinion about what the
## player is doing.
const SPRINT_TEST := (Player.SPEED + Player.SPEED * Player.SPRINT_MULT) * 0.5


var _player: Player
var _cam: Camera3D
var _mesh: MeshInstance3D
var _slide: MeshInstance3D
var _muzzle: Marker3D
var _mat: ShaderMaterial

## "<key>|<pap>" -> ArrayMesh. Built eagerly, all of them, at bind(), including the
## twelve the player will never pick up: a `SurfaceTool.commit()` on the frame the
## mystery box hands over a Thundergun is a stall nobody scheduled, and it lands in
## the one second of the round where the player is standing still by choice.
##
## The clip measurement deliberately does *not* read these — it walks
## `GUNART.body_corners()` instead, for the reason given at `_measure()` — so this
## is a load-time decision on its own and not a prerequisite of the assertion.
var _body := {}
var _slides := {}
## What is currently on the mesh, so `_show` is two comparisons on a frame where
## nothing changed. Deliberately not a valid key on the first frame, so the first
## `_show` always lands.
var _shown_key := ""
var _shown_pap := false
## The shown weapon's own sight height, in metres — latched by `_show()` so the
## pose costs no corner walk per frame. See ADS_SIGHT_CLEAR.
var _sight := 0.0

var _want_key := ""
var _want_pap := false

var _bob_phase := 0.0
var _bob_amp := 0.0
var _bob := Vector2.ZERO
var _speed := 0.0
var _sway := Vector2.ZERO         # (pitch, yaw)
var _yaw_last := 0.0
var _pitch_last := 0.0
var _have_view := false

var _kick := 0.0
var _kick_v := 0.0

var _dip := 0.0                   # 0..1, the reload arc
var _swap := 0.0                  # metres
var _sprint := 0.0                # metres
var _melee_t := 0.0
var _slide_t := 0.0
var _locked := false

var _flash := 0.0
var _flash_sent := -1.0

## (plain radius, nearest depth, projection-widened radius) — see `_measure()`.
var _extreme := Vector3.ZERO
var _measured := false


# --- setup -------------------------------------------------------------------

## Parents itself under the camera, because that is the only correct parent and a
## caller should not have to know it. Everything is built before the node enters
## the tree, so nothing here depends on `_ready` ordering.
func bind(p: Player) -> void:
	_player = p
	_cam = p.camera()

	var sh := Shader.new()
	sh.code = VM_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("viewmodel_fov", VIEWMODEL_FOV)
	_mat.set_shader_parameter("flash", 0.0)

	_mesh = MeshInstance3D.new()
	_mesh.name = "WeaponMesh"
	_mesh.material_override = _mat
	# The torch sits at the camera origin and this mesh is twelve centimetres in
	# front of it, so a casting viewmodel would throw a gun-shaped hole across the
	# whole cone. It would also be rendered through the projection override in the
	# shadow pass, which is meaningless. Off on both counts.
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mesh)

	_slide = MeshInstance3D.new()
	_slide.name = "Slide"
	_slide.material_override = _mat
	_slide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_slide.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mesh.add_child(_slide)

	_muzzle = Marker3D.new()
	_muzzle.name = "MuzzlePoint"
	_mesh.add_child(_muzzle)

	_prebuild()

	p.weapon_changed.connect(_on_weapon_changed)
	p.weapon_state_changed.connect(_on_weapon_state)
	p.fired.connect(_on_fired)
	# By name, and deliberately: `knifed` is this package's one addition to
	# `player.gd`, and a typed member access is resolved at *parse* time — so if
	# the signal is ever missing or renamed, the failure has to be a runtime error
	# that names it and not a build that never finishes. Same call, and the same
	# reasoning, as fx.gd's `surface_impact`.
	p.connect(&"knifed", swing_knife)

	_cam.add_child(self)
	_on_weapon_changed(p.current_gun())
	_apply()


func _prebuild() -> void:
	for key: String in GUNART.keys():
		for pap: bool in [false, true]:
			# The knife is never Pack-a-Punched — it is not a slot — so its tinted
			# variant would be a mesh nothing can ever show.
			if pap and key == "knife":
				continue
			var k := _cache_key(key, pap)
			var body: ArrayMesh = GUNART.build_body(key, pap)
			if body != null:
				_body[k] = body
			var slide: ArrayMesh = GUNART.build_slide(key, pap)
			if slide != null:
				_slides[k] = slide


func _cache_key(key: String, pap: bool) -> String:
	return "%s|%d" % [key, 1 if pap else 0]


## The one material this file owns, for the shader warm-up pass. There is no
## program cache on the web, so the first draw of this shader is a main-thread
## GLSL compile; it happens to land behind the title card anyway because the
## weapon is on screen from frame one, but relying on that would make the timing a
## property of whether the title screen draws the 3D scene.
func materials() -> Array:
	return [_mat]


# --- signals -----------------------------------------------------------------

func _on_weapon_changed(gun: Dictionary) -> void:
	var key: String = gun.key
	var pap: bool = gun.pap
	_want_key = key
	_want_pap = pap


## Two things, and both are genuinely edges — everything else about the pose is a
## clock and is read per frame in `_tick_states`.
##
## `weapon_state_changed` fires for every gun the player carries, stowed ones
## included, so the one in hand has to be identified by reference. `is_same` and
## not `==`: a Dictionary compares by value, and two guns of the same kind with
## the same counters are a real state.
func _on_weapon_state(gun: Dictionary, from: int, to: int) -> void:
	if _player == null or not is_same(gun, _player.current_gun()):
		return
	if to == WEAPON.State.RELOADING or to == WEAPON.State.RELOAD_SHELL:
		# The bolt comes back at the start of a reload.
		_cycle_slide()
	elif from == WEAPON.State.EMPTY and (to == WEAPON.State.IDLE
			or to == WEAPON.State.FIRING):
		# ...and is released when ammunition finally arrives on a bolt-locked
		# weapon. Only observable as an edge: `EMPTY` is derived from the counts,
		# so by the time a frame reads the state it is already gone.
		#
		# Narrowed to the two states `Weapon.settle()` can land in, because those
		# are the ones that mean rounds turned up. `EMPTY` also exits into
		# `SWAPPING` (pulling out a dead weapon) and `SPRINT_OUT` (stopping while
		# holding one), and racking an empty gun on either of those is a lie.
		_cycle_slide()


func _on_fired(_at: Vector3) -> void:
	var def: Dictionary = _player.current_gun().def
	var kick: float = def.kick
	_kick_v += kick
	_cycle_slide()
	_flash = FLASH_PEAK


## The knife swing, bound to `Player.knifed`. That signal exists because
## `_knife()` is the only place that knows a melee actually *happened* — the
## 0.55 s cooldown refuses most presses, and a rig driven by the key instead would
## animate half of them for nothing and desynchronise from the damage.
func swing_knife() -> void:
	_melee_t = MELEE_TIME


func _cycle_slide() -> void:
	_slide_t = SLIDE_TIME


# --- per frame ---------------------------------------------------------------

func _process(dt: float) -> void:
	if _player == null:
		return
	_tick_sway(dt)
	_tick_bob(dt)
	_tick_kick(dt)
	_tick_states(dt)
	_tick_flash(dt)
	_apply()


func _tick_sway(dt: float) -> void:
	var f := -_cam.global_transform.basis.z
	var yaw := atan2(f.x, f.z)
	var pitch := asin(clampf(f.y, -1.0, 1.0))
	if not _have_view:
		_have_view = true
		_yaw_last = yaw
		_pitch_last = pitch
	# Wrapped, because yaw is an atan2 and a player who turns through south would
	# otherwise flick the weapon across the screen once per revolution.
	var d_yaw := wrapf(yaw - _yaw_last, -PI, PI)
	var d_pitch := pitch - _pitch_last
	_yaw_last = yaw
	_pitch_last = pitch

	# Angular velocity rather than per-frame delta, or the sway would be twice as
	# strong at 30 fps as at 60.
	var inv := 1.0 / maxf(dt, 0.0001)
	var t_yaw := clampf(-d_yaw * inv * SWAY_PER_RATE, -SWAY_MAX, SWAY_MAX)
	var t_pitch := clampf(-d_pitch * inv * SWAY_PER_RATE, -SWAY_MAX, SWAY_MAX)
	_sway.x = move_toward(_sway.x, t_pitch, SWAY_RATE * dt)
	_sway.y = move_toward(_sway.y, t_yaw, SWAY_RATE * dt)


func _tick_bob(dt: float) -> void:
	_speed = 0.0
	# `velocity` keeps its last value while the player's own physics step is
	# early-returning, so a paused game would otherwise bob forever.
	if Game.state == Game.STATE_PLAY:
		var v := _player.velocity
		_speed = Vector2(v.x, v.z).length()
	_bob_phase += dt * _speed
	var amp := clampf(_speed / Player.SPEED, 0.0, BOB_AMP_MAX)
	_bob_amp = move_toward(_bob_amp, amp, BOB_AMP_RATE * dt)
	# `Player.BOB_POS` is the same rate the camera's own bob runs at, so the two
	# stay in character together. X and Y ride different functions — that
	# asymmetry is what reads as a figure-eight rather than a pendulum.
	var phase := _bob_phase * Player.BOB_POS
	_bob = Vector2(sin(phase) * BOB_X * _bob_amp,
		-absf(cos(phase)) * BOB_Y * _bob_amp)


func _tick_kick(dt: float) -> void:
	_kick_v += (-_kick * KICK_SPRING - _kick_v * KICK_DAMP) * dt
	_kick += _kick_v * dt
	# Clamped at zero as well as at the ceiling: the spring's undershoot is about
	# one percent of its peak, and giving the weapon a hard floor is what makes
	# `min_corner_depth()` a bound rather than an observation.
	_kick = clampf(_kick, 0.0, KICK_MAX)


func _tick_states(dt: float) -> void:
	var gun := _player.current_gun()
	var state: int = gun.state
	var t: float = gun.state_t
	var span: float = gun.state_len
	# `1 - state_t/state_len` is the progress term weapon.gd documents, and the
	# guard is for the states that have no natural end and therefore no length.
	var done := 0.0
	var left := 0.0
	if span > 0.0:
		done = clampf(1.0 - t / span, 0.0, 1.0)
		left = clampf(t / span, 0.0, 1.0)

	var dip := 0.0
	if state == WEAPON.State.RELOADING:
		dip = sin(done * PI)
	elif state == WEAPON.State.RELOAD_SHELL:
		dip = sin(done * PI) * SHELL_SCALE
	_dip = _settle(_dip, dip, DIP_RATE, dt)

	var swap := 0.0
	if state == WEAPON.State.SWAPPING:
		swap = SWAP_DROP * left
	_swap = _settle(_swap, swap, DROP_RATE, dt)

	# The state and the speed are two views of the same fact — the weapon is down
	# because the player is running — so they combine as a maximum and not a sum.
	# The state half covers the way back up, which velocity cannot: by the time
	# `SPRINT_OUT` begins the player is already walking.
	var sprint_target := SPRINT_DROP if _speed > SPRINT_TEST else 0.0
	_sprint = move_toward(_sprint, sprint_target, SPRINT_RATE * dt)
	if state == WEAPON.State.SPRINT_OUT:
		_sprint = maxf(_sprint, SPRINT_DROP * left)

	_melee_t = maxf(0.0, _melee_t - dt)
	if _slide_t > 0.0:
		_slide_t = maxf(0.0, _slide_t - dt)
	_locked = state == WEAPON.State.EMPTY


## Snap toward a pose the state is actively driving, ease back to rest when it
## stops driving it. `move_toward` and never `lerp`, exactly as the brief for this
## package and M1 F5 both insist: `lerp` is asymptotic and produces the weapon
## that never quite re-centres.
static func _settle(cur: float, target: float, rate: float, dt: float) -> float:
	if target > cur:
		return target
	return move_toward(cur, target, rate * dt)


func _tick_flash(dt: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * FLASH_PEAK / FLASH_TIME)
	# Pushed only when it actually moves. A uniform set is cheap; sixty a second
	# for a value that is zero in almost every frame is still sixty a second.
	if not is_equal_approx(_flash, _flash_sent):
		_flash_sent = _flash
		_mat.set_shader_parameter("flash", _flash)


# --- pose --------------------------------------------------------------------

func _apply() -> void:
	# The knife is a temporary override of whatever is in hand, restored by the
	# timer running out — the same shape the ancestor used (html:3109-3110).
	if _melee_t > 0.0:
		_show("knife", false)
	else:
		_show(_want_key, _want_pap)

	# ViewmodelRoot: sway and bob, and nothing else, ever. Rotating here rather
	# than on the mesh is what keeps the sway out of `max_corner_radius()` — this
	# node sits at the camera origin, so its rotation cannot change any vertex's
	# distance from the lens. It is *not* free of `max_screen_radius()`, which
	# weighs the lateral terms more heavily than z and so is not rotation
	# invariant; that is why `_measure()` sweeps sway at all.
	transform = Transform3D(Basis.from_euler(Vector3(_sway.x, _sway.y, 0.0)),
		Vector3(_bob.x, _bob.y, 0.0))

	var melee := 0.0
	if _melee_t > 0.0:
		melee = sin((1.0 - _melee_t / MELEE_TIME) * PI)
	_mesh.transform = _mesh_pose(_kick, _dip, _swap + _sprint, melee, _player.ads(),
		_sight)
	_slide.position = Vector3(0.0, 0.0, _slide_offset())


## The WeaponMesh's whole local transform, as a pure function of the five pose
## channels. Pure so that `_measure()` can walk the extremes of the same function
## rather than re-deriving them, which is the only way the clip assertion can be
## about the rig that shipped rather than about a second copy of its arithmetic.
func _mesh_pose(kick: float, dip: float, drop: float, melee: float,
		ads := 0.0, sight := 0.0) -> Transform3D:
	var down := minf(drop + dip * DIP, DROP_MAX)
	# The sights pull the grip onto the centre line and the muzzle straight ahead.
	# Multiplied into the rest offsets rather than added as a second translation, so
	# full ADS is exactly "no lateral offset, no inward yaw" and cannot overshoot into
	# a pose the clipping budget was never measured at.
	var centre := 1.0 - ads * ADS_CENTRE
	# ...and then the whole weapon down by its OWN sight height, so what arrives on
	# the view axis is the top of the gun and not the hand holding it. `sight` is
	# passed in rather than read here: `_show()` latches it off the key actually on
	# the mesh — which the melee override makes the knife's, not the held gun's — and
	# `_measure()` sweeps each weapon against its own. Reading GUNART here instead
	# would be a corner walk per frame and would pose the knife as a rifle.
	var sighted := ads * (sight + ADS_SIGHT_CLEAR * GUNART.UNIT)
	var origin := Vector3(
		REST_POS.x * centre + dip * DIP_X + melee * MELEE_X,
		REST_POS.y * centre - sighted - down + melee * MELEE_Y - kick * KICK_DOWN,
		REST_POS.z + kick * KICK_BACK - ads * ADS_FORWARD)
	# The cant leaves on the same fraction the offsets do, so the barrel arrives level
	# exactly when the pose arrives. Everything else still ADDS to it: a reload arc or
	# a knife swing taken at the sights is not a sighted pose and must not read as one.
	var pitch := REST_PITCH * (1.0 - ads * ADS_LEVEL) \
		+ dip * DIP_ROLL + melee * MELEE_ROT + kick * KICK_PITCH
	var yaw := REST_YAW * (1.0 - ads * ADS_YAW)
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), origin)


func _slide_offset() -> float:
	if _locked:
		# Bolt-lock. Nothing chambered and nothing left to chamber, and the weapon
		# says so without a single line of UI.
		return SLIDE_TRAVEL
	if _slide_t <= 0.0:
		return 0.0
	var u := 1.0 - _slide_t / SLIDE_TIME
	var f := u / SLIDE_BACK if u < SLIDE_BACK else (1.0 - u) / (1.0 - SLIDE_BACK)
	return f * SLIDE_TRAVEL


## Compared field by field rather than through `_cache_key`, because this runs
## every frame and the key is only needed on the frames where it changes: building
## the string first would be sixty String allocations a second to answer a
## question two comparisons already answer.
func _show(key: String, pap: bool) -> void:
	if key == _shown_key and pap == _shown_pap:
		return
	_shown_key = key
	_shown_pap = pap
	var k := _cache_key(key, pap)
	# A missing entry hides the mesh rather than throwing: a weapon with no art
	# should leave you holding nothing, not end the round.
	var body: Mesh = _body.get(k)
	var slide: Mesh = _slides.get(k)
	_mesh.mesh = body
	_slide.mesh = slide
	_slide.visible = slide != null
	_muzzle.position = GUNART.muzzle_local(key)
	# Latched off the key actually SHOWN, which the melee override above makes the
	# knife's rather than the held gun's — a knife swung at the sights has to be posed
	# against the knife's 5 art units and not the Ray Gun's 19. Here rather than in
	# `_mesh_pose` because `sight_height()` walks every corner of the weapon on a
	# cache miss, and this function only runs on the frames where the mesh changes.
	_sight = GUNART.sight_height(key)


# --- the geometric guarantee, measured ---------------------------------------

## The largest distance from the camera origin to any vertex of any weapon, in any
## pose the rig can reach — the plain sphere the design is budgeted against.
##
## **On its own this is not the no-clip guarantee**, and reading it as one is the
## trap this file exists to keep the next person out of: see `max_screen_radius()`
## below and the header. It is asserted against `CLIP_RADIUS` because it is the
## number an author can hold in their head while placing a weapon, and because a
## weapon that fails it is certainly wrong even though one that passes it may be.
func max_corner_radius() -> float:
	_measure()
	return _extreme.x


## The smallest forward distance from the lens to any vertex, for the same set. If
## this ever drops below the camera's `near`, the weapon starts being sliced open
## by the near plane — which looks exactly like the wall clipping this whole design
## exists to make impossible, and would be diagnosed as it for a day.
func min_corner_depth() -> float:
	_measure()
	return _extreme.y


## **This is M-VMCLIP.** `sqrt(z^2 + ratio^2 * (x^2 + y^2))` over the same set, the
## radius corrected for the fact that the weapon is drawn through a wider lens than
## the world it is composited against — derived in the header. Asserting it under
## `Player.RADIUS` is the whole reason the no-clip claim is a fact rather than a
## hope: a long-barrelled weapon added later fails here, at build time, instead of
## clipping through a wall in front of a player.
func max_screen_radius() -> float:
	_measure()
	return _extreme.z


## All three at once, because they are one sweep.
##
## **SWEPT ONE WEAPON AT A TIME, and that is a correctness condition rather than a
## tidiness.** This used to pool every weapon's corners into one point set and sweep
## the pose over it once, which was exactly right while the pose was the same for all
## thirteen. It is not any more: `ADS_SIGHT_CLEAR` drops each weapon by its own sight
## height, so a pooled sweep would pose the Olympia's barrel at the Ray Gun's 19-unit
## drop and the Ray Gun's lens at the knife's 5 — a chimera that is no weapon, and it
## would be reported as a safety margin. Thirteen sweeps of a couple of hundred
## points each is not a cost worth trading that for.
##
## Corners come from `GUNART.body_corners()` / `slide_corners()` rather than from
## the committed meshes — see the comment there for why a `surface_get_arrays()`
## round trip is the wrong thing to hang a safety assertion on, and why an `AABB`
## is too loose to be useful at this margin. They are deduplicated within the weapon
## (a slide at rest can land on a body corner), and the Pack-a-Punch variants are
## skipped outright: `pap` changes vertex colours and nothing else.
##
## The melee channel is lit for the knife alone, because `_apply()` only ever shows
## the knife while it is lit. Pairing a rifle's muzzle with a full melee sweep would
## measure a frame the rig cannot draw, and it costs 4 mm of an 8 mm margin to do it.
##
## Channels are sampled at their endpoints. Each is smooth in the pose and a dense
## sweep does not beat the endpoints by more than 0.2 mm on any of the three, which
## is two orders under every margin here. Sway is a 3x3 grid rather than the four
## corners because zero sway is the worst case for the near plane.
##
## 218,016 transformed points. Called once, from `verify.gd`, and cached; nothing in
## the game may call it per frame.
func _measure() -> void:
	if _measured:
		return
	_measured = true

	# From the camera rather than from a constant, so a field of view that ever
	# moves cannot leave a stale copy of this behind. See VIEWMODEL_FOV.
	var ratio := tan(0.5 * deg_to_rad(_cam.fov)) / tan(0.5 * deg_to_rad(VIEWMODEL_FOV))
	# A pure lateral translation, so it is added to the lateral term of each
	# metric rather than being swept as a channel of its own.
	var bob := Vector2(BOB_X, BOB_Y).length()
	var sways: Array[float] = [-SWAY_MAX, 0.0, SWAY_MAX]
	# Declared rather than assigned from a literal at the branch below: an array
	# literal is only reliably given its target's element type where it is the
	# initialiser of a typed declaration, and this is not a file to find out where
	# the edges of that are.
	var gun_melees: Array[float] = [0.0]
	# The knife is on screen across the whole swing, so the middle of the arc —
	# which is where it reaches furthest — has to be sampled too.
	var knife_melees: Array[float] = [0.0, 0.5, 1.0]

	var worst := 0.0
	var nearest := 1e9
	var widest := 0.0
	for key: String in GUNART.keys():
		var into := {}
		# Annotated rather than inferred, both of them: a call through a preloaded
		# script constant is the kind of expression this project builds as an error
		# when its result is handed to a typed parameter unchecked.
		var body: PackedVector3Array = GUNART.body_corners(key)
		var slide: PackedVector3Array = GUNART.slide_corners(key)
		_collect(body, into, 0.0)
		_collect(slide, into, 0.0)
		# The reciprocating group is a live translation of its own mesh, so both
		# ends of its travel are places a vertex genuinely reaches.
		_collect(slide, into, SLIDE_TRAVEL)
		var pts := PackedVector3Array(into.keys())
		# THE WHOLE REASON THIS LOOP IS PER WEAPON. Through the same accessor the rig
		# poses with, so a sight height that stopped being derived from the mesh would
		# move the assertion and not just the picture.
		var sight: float = GUNART.sight_height(key)
		var melees: Array[float] = gun_melees
		if key == "knife":
			melees = knife_melees
		for kick: float in [0.0, KICK_MAX]:
			for dip: float in [0.0, 1.0]:
				for drop: float in [0.0, SWAP_DROP + SPRINT_DROP]:
					for melee: float in melees:
						# Both ends of the sights, because the clipping budget has to hold at the
						# sighted pose too — that pose moves the weapon 8 mm toward the near plane
						# and up to 20 mm down, and the drop is what puts the lateral term up.
						for ads: float in [0.0, 1.0]:
							var mp := _mesh_pose(kick, dip, drop, melee, ads, sight)
							for sx: float in sways:
								for sy: float in sways:
									var root := Basis.from_euler(Vector3(sx, sy, 0.0))
									for p: Vector3 in pts:
										var v := root * (mp * p)
										var lat := Vector2(v.x, v.y).length() + bob
										worst = maxf(worst, v.length() + bob)
										# The bob has no z component, so depth needs no
										# correction for it.
										nearest = minf(nearest, -v.z)
										widest = maxf(widest,
											sqrt(v.z * v.z + ratio * ratio * lat * lat))
	_extreme = Vector3(worst, nearest, widest)


static func _collect(pts: PackedVector3Array, into: Dictionary, z_off: float) -> void:
	var off := Vector3(0.0, 0.0, z_off)
	for p: Vector3 in pts:
		into[p + off] = true


# --- attachment --------------------------------------------------------------

## Where to put a **world-projected** effect so that it lands on the barrel *on
## screen*, at `distance` metres in front of the lens.
##
## This is not the muzzle's own position and it must not be. Two things are true at
## once: the weapon is drawn through a narrowed projection, so its screen position
## is the world's scaled by `tan(fov/2) / tan(viewmodel_fov/2)` — put a flash on
## the same ray and it appears well inside the barrel; and a flash quad at the
## muzzle's actual 0.18 m would subtend more than the whole screen. Undoing the
## first at a sane value of the second is the only placement that satisfies both,
## and it needs the `Marker3D` to know where the barrel is.
func flash_anchor(distance: float) -> Vector3:
	var fwd := -_cam.global_transform.basis.z
	var back := _cam.global_position + fwd * distance
	if _muzzle == null:
		return back
	var m := _cam.to_local(_muzzle.global_position)
	if m.z >= -0.001:
		return back
	var ratio := tan(0.5 * deg_to_rad(_cam.fov)) / tan(0.5 * deg_to_rad(VIEWMODEL_FOV))
	var s := distance * ratio / -m.z
	return _cam.to_global(Vector3(m.x * s, m.y * s, -distance))
