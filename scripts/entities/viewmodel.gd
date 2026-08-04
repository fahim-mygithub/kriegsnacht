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
## the plain radius is 0.201 and the nearest depth 0.0572 m against a 0.05 m near
## plane. Those three are a CIRCUMSCRIBED bound rather than a sampled one — see
## `_measure()` — so the margin they report is one the rig provably cannot exceed
## rather than one it was not caught exceeding.
## `max_screen_radius()` is the assertion that matters — the plain
## `max_corner_radius()` would pass a weapon that clips. 0.24 is itself the
## worst-case-over-all-directions figure (a wall the player is pressed flat
## against, seen along a horizontal ray); the corner that produces 0.232 is drawn
## 42 degrees below the view axis, where the nearest wall is 0.24/cos(42) = 0.32 m,
## so the margin in play is nearer 39% than 3%.
##
## Node chain, and rule "one writer per node" applies with full force:
##
##   Camera3D
##   └ ViewmodelRoot   (this node)  sway and bob — TRANSFORM written only by _apply()
##     └ WeaponMesh                 rest pose, recoil, reload, swap, melee
##       ├ Slide                    the reciprocating group, z only
##       └ MuzzlePoint              static per weapon; read by flash_anchor()
##
## Everything is driven from the weapon state machine that already exists
## (`scripts/entities/weapon.gd`): `Player.weapon_state_changed` for the two things
## that are genuinely edges, and `state`/`state_t`/`state_len` read per frame for
## everything with a clock. There is no second notion anywhere in this file of what
## the weapon is doing.

## preload rather than the class name for all three: a freshly added script is not
## in the class registry until the editor rescans, and a headless run has no editor.
const GUNART := preload("res://scripts/data/gunart.gd")
const WEAPON := preload("res://scripts/entities/weapon.gd")
## The reload timeline. Same relationship this file has to `GUNART`: that one says
## what the weapon is made of, this one says what it does while it is being
## reloaded, and neither of them knows a node exists.
const RELOAD := preload("res://scripts/data/reload.gd")


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
## design ceiling, the nearest 0.0572 m along it against the 0.05 m near plane, and
## the projection-widened radius the header derives at 0.232 m against
## `Player.RADIUS`'s 0.24. `_measure()` re-derives all three from the same corners
## the meshes are built from.
##
## All three are attained at `ads = 0`, and that is worth writing down because it is
## not obvious: the sighted pose now drops each weapon by up to 20 mm at the grip
## (`ADS_SIGHT_CLEAR`), which sounds like it should move the lateral term. It does
## not. Levelling the cant pulls the muzzle back onto the axis and `ADS_FORWARD`
## pushes the stock 8 mm away from the near plane, and both more than pay for the
## drop — the sighted extremes come out strictly inside the hip ones.
##
## MEASURED: **0.201372 / 0.057188 / 0.231964**. Re-measured 2026-08-04 on commit
## 2fc7422, out of `sweep(true)` — the call `_measure()` itself makes — rather than
## by re-deriving it, and the middle figure came back different from the one this
## line carried.
##
## THE CORRECTION, because "which number is it" turns out to have a real answer.
## This said 0.057368, and that is a genuine measurement of a DIFFERENT
## configuration: the interior samples with the circumscribing inflation switched
## off. `checks/systems.gd` measures exactly that on purpose, to separate the two
## mechanisms, and quotes 0.057368 correctly — confirmed here by forcing `grow` to
## 1.0 and re-running, which reproduces 0.201161 / 0.057368 / 0.231758. The shipped
## sweep has both mechanisms and both lower `nearest`, so what was pasted in here
## was the half-sabotaged figure and it overstated the near-plane clearance by
## 0.18 mm. `worst` and `widest` were exact.
##
## The record before this package was 0.201249 / 0.057540 / 0.231884, and that
## difference is not drift either: the sweep now CIRCUMSCRIBES four rotational arcs
## it used to sample at their endpoints (see `_measure()`), and `ADS_YAW` went to
## 0.95, which changes the size of one of those arcs. Against the same constants
## the endpoint-only sweep still reads 0.201161 / 0.057496 / 0.231758 exactly, so
## the construction is worth 0.21 mm on the widened radius and 0.31 mm on the near
## plane — the 0.13 mm quoted here before was the stale figure's own subtraction.
## Margin against `Player.RADIUS`: **8.036 mm**; against the 0.05 m near plane,
## 7.188 mm.
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
## `rot += s*0.5`, `x += s*cssW*0.03` (html:3121-3128). The three AMPLITUDES are
## still the ancestor's, converted through `M_PER_H`/`M_PER_W`, and they are all
## that is left of it here: the `sin(rel*PI)` that used to supply the 0..1 they
## multiply now comes out of `scripts/data/reload.gd`, per weapon and per segment.
## The departure is recorded there, at the head of the file.
const DIP := 0.03623            # 0.30 of screen height
const DIP_X := 0.00644          # 0.03 of screen width
const DIP_ROLL := 0.5           # radians, verbatim
## How fast the dip may unwind when it is *interrupted* — and, since the tracks
## landed, that is the ONLY thing it does. Firing cancels a shell reload mid-shell
## (`weapon.gd::can_fire`), which is most of the reason to load shell by shell at
## all, and a cancel is the one case with no clock left to read: there is no
## remaining phase to play the weapon back out on, so the pose has to come home on
## a rate. See `_settle` and `_drive`, which is the pair this constant now divides.
const DIP_RATE := 6.0

## A shell is not a magazine: the amplitude the whole `RELOAD_SHELL` family of
## tracks is scaled by, because a Stakeout's six shells at the full magazine arc is
## a weapon thrashing. Invented; the ancestor never distinguished the two reloads.
##
## **Read at exactly one site — `_drive` — and deliberately NOT folded into
## `reload.gd`'s tables.** The tables are pure shape so their rows stay comparable
## to each other; the moment an amplitude is baked into half of them, a reader
## comparing a `WHOLE` row against an `EACH` row is comparing two different units
## and will not notice.
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

## **THIS WAS 1.0 AND THAT ZEROED THE YAW AT THE ONE POSE THE PLAYER STUDIES THE
## WEAPON IN.** Twelve degrees of profile yaw exists — see `REST_YAW`, four
## constants up — because "extruded flat plates viewed from behind read as a stack
## of rectangles", and removing all of it at the sights produced exactly that: the
## sighted silhouette of the M1911, the MP40 and the RPK is 66.7 px wide at 720p,
## the same 66.7 px, because what is left is the gloves' extrusion caps and no
## weapon at all. On-screen slide length collapses from 89 px to 4.4 px on the
## M1911 and to under a pixel on four of the seven weapons with a group.
##
## **AND IT CANNOT BE REDUCED AS FAR AS THAT ARGUMENT WANTS, for a reason nothing
## in the research anticipated: the frames gate's ADS probe rect is 80 px wide.**
## `shot_setup.gd:192` is `Rect2i(600, 359, 80, 177)`, sized around a silhouette
## measured at x 606..673 — 6 px of margin one side and 7 the other — and a
## silhouette that grows out of its own probe rect is not measured, it is CROPPED,
## and the gate then reports a number about the rectangle. Working the projection:
## the RPK's stock and muzzle open the profile at about 481 px per radian of
## residual yaw, asymmetrically, and the binding side is the muzzle at ~263 px/rad.
## Three pixels of margin buys 0.0114 rad, which is `ADS_YAW` 0.9456.
##
## **0.95 is that ceiling, taken, and it is not the value the argument wants.** It
## is 0.6 degrees of profile and it buys about 5 px. Getting to a sighted profile
## worth having — 30% of the hip silhouette — needs `ADS_YAW` near 0.62, and that
## needs `VM_RECT_ADS` widened to roughly `Rect2i(575, 359, 128, 177)` **and** a
## windowed `-Bless`, in one atomic step, in a file this package does not own.
## `checks/systems.gd::_ads_geometry` asserts both ends of this: that some yaw
## survives at the sights, and that whatever survives still fits the committed rect.
## Raise this the day the rect moves; the check will tell you when you have gone
## too far, which is the whole reason it computes the projection instead of
## trusting a photograph.
const ADS_YAW := 0.95           # fraction of REST_YAW removed at the sights

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

## **HOW FAR the group travels is `GUNART.slide_travel(key)` and is per weapon.**
## It used to be one 4-unit constant here; it is now a statement about the art —
## how far a part can move before it meets the part behind it — so it lives beside
## the rects. `_slide_offset()` and `_measure()` read it through that one accessor,
## which is the only thing standing between a longer stroke and a silently stale
## no-clip sweep.
##
## What is left here is the CLOCK, and it is not a `Tween`: at 880 RPM that would
## allocate about fifteen of them a second, which is exactly the
## allocation-inside-the-fire-loop this project keeps out of every other hot path.
## It is three floats.
##
## `SLIDE_TIME` is the hand-worked cycle — the bolt coming back at the start of a
## reload, the release at the end of one. **A self-cycling action's cycle is its
## own fire interval instead** (see `_fire_cycle`): the claim this constant used to
## carry, *"the whole cycle is shorter than the fastest weapon's interval, so a
## held automatic restarts it rather than compounding it"*, was false against the
## shipped table — the PM-63's interval is exactly 0.060000 s at 1000 rpm and
## 0.044776 s under Double Tap, so a held PM-63 restarted a cycle it had never
## finished and, simulated over 480 warm frames, never returned to battery.
const SLIDE_TIME := 0.06

## Where in the cycle the group reaches the far end of its stroke, as a fraction.
##
## `SLIDE_BACK` is the closed-bolt figure: **back fast, forward slower — a slide is
## thrown by gas and returned by a spring.** An open bolt is the time mirror of
## that and gets `1.0 - SLIDE_BACK`, because there the spring drives it forward and
## the shot drives it back; running the closed profile on an MP40 played the one
## prominent mechanism on the roster backwards *and* asymmetrically backwards. A
## pump is hand-worked, so nothing is throwing it either way and it is symmetric.
const SLIDE_BACK := 0.30
const PUMP_PEAK := 0.50

## A pump gun does not move at the instant of the shot; it is stroked **between**
## shots. Expressed as fractions of that weapon's own fire interval rather than in
## seconds, which is what keeps the whole stroke inside the window under Double Tap
## (the Stakeout's interval falls from 0.414 s to 0.309 s) without a second table.
##
## 0.35 and 0.55 are the Stakeout's derived pair — 0.145 s of delay and 0.23 s of
## stroke at 145 rpm. **Departure, recorded:** the research proposed a second pair
## for the China Lake (~0.25 s delay, ~0.45 s duration in a 0.968 s interval, i.e.
## 0.26 / 0.47). Both pairs are Tier-4 inventions with no source between them, and
## a per-weapon table for one weapon is a second thing to go stale, so the Stakeout's
## pair carries both: the China Lake gets 0.339 s and 0.532 s, which lands well
## inside its interval — the only constraint either figure ever had.
const PUMP_DELAY := 0.35
const PUMP_STROKE := 0.55


# --- how finely the clip sweep looks inside a rotation ------------------------

## How much of the clip margin one rotational channel's arc sampling is allowed to
## be wrong by, in metres. 0.2 mm a channel against the 8.036 mm of margin measured
## at `REST_POS`, four channels, so the whole construction can cost at most 0.8 mm
## — **a tenth of the margin, not the "1%" this said**; 4 x 0.2 / 8.036 is 9.9% and
## no reading of the numbers gives 1%, so the old figure is corrected rather than
## re-derived. It costs it in the SAFE direction, because the samples circumscribe
## the arc rather than being inscribed in it. See `_measure()`.
const ARC_TOL := 0.0002

## A bound on the sample-count solver's loop, not a tuning knob. The largest arc
## anything authors today is the knife's 0.85 rad and it solves to K = 6 against the
## knife's own `r_max` — MEASURED 2026-08-04 out of the live sweep; this said 7,
## which is what a radius of 0.06 m gives and no weapon that swings has. See `_arc`
## for why the count is per weapon at all. This binds only for an amplitude nobody
## has written, and if it ever bound the sweep would quietly stop being
## conservative — so `checks/systems.gd` asserts every solved count is strictly
## under it rather than trusting the loop to be generous.
const ARC_MAX_SAMPLES := 64


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
## The support hand, split out of the weapon mesh so a segmented reload can move it
## on its own. **INERT IN THIS STAGE**: `_apply()` writes it `Transform3D.IDENTITY`
## and nothing else ever writes it, so it draws exactly where `build_body` used to
## draw it and no frame changes. `checks/systems.gd` asserts that identity exactly —
## `==`, not `is_equal_approx` — on all thirteen weapons at both ends of the sights,
## because "it has not started animating yet" is a claim a tolerance cannot make.
var _support: MeshInstance3D
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
## Weapon key -> the support hand's `ArrayMesh`. Keyed by KEY ALONE and not by
## `_cache_key`, because `GUNART.build_support_hand()` takes no `pap` argument: the
## gloves are drawn after the ancestor's Pack-a-Punch composite (html:1220 against
## :1229-1237) so a tinted variant would be a mesh that is never correct to show.
## Absent for the three `ONE_HANDED` weapons, which is how `_show` hides it.
var _support_meshes := {}
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

## The reciprocating group's clock, in three parts. `_slide_t` is what is left of
## the current stroke and `_slide_len` is that stroke's own length — per weapon
## now, so `1 - _slide_t/_slide_len` is still the normalised progress it always
## was. `_slide_delay` is a pump's wait before its stroke starts, holding
## `_slide_pend` until it expires.
var _slide_t := 0.0
var _slide_len := 0.0
var _slide_delay := 0.0
var _slide_pend := 0.0
## Where in the cycle the group reaches the far end of its stroke — `SLIDE_BACK`
## for a closed bolt, its mirror for an open one, `PUMP_PEAK` for a hand-worked
## action.
var _slide_peak := SLIDE_BACK
## The stroke's three positions, in units of this weapon's travel: where it began,
## the far end of the excursion, and where it lands. Three rather than one ramp
## because the landing pose is not always the starting pose — an M1911 that has
## just fired its last round starts at battery and ENDS held back, and an MP40 that
## has just fired its last round starts held back and ends forward.
var _slide_a := 0.0
var _slide_b := 1.0
var _slide_c := 0.0
## The pose the group rests in when no stroke is running, in the same units. Read
## per frame rather than latched on an edge: every route to ammunition — a reload
## landing, a Max Ammo, a wall buy — has to be able to release a held-open bolt,
## and only one of those three is a state change anyone signals.
var _slide_rest := 0.0
## Latched by `_show`, because both are per weapon and neither may cost a table
## lookup per frame. Travel is metres and is zero for a weapon with no group at all.
var _slide_travel := 0.0
var _slide_mode := GUNART.CLOSED
## How many strokes have been started. The only thing in this file that exists for
## an assertion: `checks/systems.gd` drives a real six-shell Stakeout reload and
## counts, because "the group cycled once per shell" is a claim about events and
## the drawn offset alone cannot separate seven strokes from one long one.
var _slide_cycles := 0

## The previous frame's weapon state and state clock, for the per-shell edge.
## `RELOAD_SHELL` re-enters itself, so a shell landing is a `state_t` that went UP
## while the state did not change — see `_tick_slide`.
var _state_last := -1
var _state_t_last := 0.0

var _flash := 0.0
var _flash_sent := -1.0

## (plain radius, nearest depth, projection-widened radius) — see `_measure()`.
var _extreme := Vector3.ZERO
var _measured := false
## Weapon key -> the travel `sweep()` actually collected the group's far end at.
## See `swept_travels()` for why a readout and not a refusal.
var _swept := {}
## Weapon key -> how many NEW points the support hand's corners added to that
## weapon's pool. See `swept_support()`, and see `_swept` for the shape of the bug
## both of these exist to catch.
var _swept_support := {}
## Rotational channel name -> the circumscribing factor the last INTERIOR `sweep()`
## actually folded into that weapon's `grow`. Written by the fold itself, one entry
## per multiply; see `arc_growth()` for why a readout and not a refusal.
var _arc_grew := {}


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

	# Beside the group and under the weapon mesh, so it inherits the whole pose and
	# its own transform is a DEPARTURE from the weapon rather than a pose of its own —
	# which is what makes `Transform3D.IDENTITY` the meaningful rest value and what
	# will make a reload keyframe readable when one lands.
	#
	# `material_override = _mat` and not a second material, deliberately: `materials()`
	# is the shader warm-up's whole input and `verify.gd` asserts that every material
	# the game owns is in that list. A hand with its own `ShaderMaterial` would be a
	# main-thread GLSL compile on the first frame a two-handed weapon is drawn, on the
	# web, and the assertion that would have caught it would have had to be edited to
	# let it through. Same shadow and GI settings as everything else here, for the
	# torch reason given above.
	_support = MeshInstance3D.new()
	_support.name = "SupportHand"
	_support.material_override = _mat
	_support.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_support.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mesh.add_child(_support)

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
		# Once per weapon and outside the `pap` loop, for the reason `_support_meshes`
		# gives: there is no tinted support hand and there must not be one.
		var hand: ArrayMesh = GUNART.build_support_hand(key)
		if hand != null:
			_support_meshes[key] = hand
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
	if from != WEAPON.State.RELOAD_SHELL and (to == WEAPON.State.RELOADING
			or to == WEAPON.State.RELOAD_SHELL):
		# The bolt comes back at the start of a reload. Guarded on `from` because
		# `RELOAD_SHELL` now re-enters itself for the closing segment as well as per
		# shell, and `_tick_slide` owns every one of those — this edge is the entry
		# into the reload and nothing else.
		_cycle_slide()
	# The release at the END of a reload used to live here as `from == EMPTY`, and
	# it has moved into `_tick_slide`. `EMPTY` is `mag <= 0 AND res <= 0`
	# (`weapon.gd:238-243`), so on the M1911 — the one weapon whose lock is real —
	# that edge first arrives after 88 rounds with no Max Ammo, and never on the
	# empty MAGAZINE that precedes every reload, which is the only state the
	# reference ever shows the lock in. Now that the lock is reachable there, the
	# release has to be too, and it has three sources rather than one.


func _on_fired(_at: Vector3) -> void:
	var gun := _player.current_gun()
	var def: Dictionary = gun.def
	var kick: float = def.kick
	_kick_v += kick
	_fire_cycle(def)
	_flash = FLASH_PEAK


## The knife swing, bound to `Player.knifed`. That signal exists because
## `_knife()` is the only place that knows a melee actually *happened* — the
## 0.55 s cooldown refuses most presses, and a rig driven by the key instead would
## animate half of them for nothing and desynchronise from the damage.
func swing_knife() -> void:
	_melee_t = MELEE_TIME


## A hand-worked stroke: the bolt coming back at the start of a reload, a shell
## landing, the release at the end. `SLIDE_TIME` and not the fire interval, because
## none of those is the action cycling itself.
func _cycle_slide() -> void:
	_begin_stroke(SLIDE_TIME)


## The stroke a SHOT produces, which is three different things.
##
## A pump gun does not move when the shot breaks — it is stroked between shots — so
## its stroke is a delay and then a longer, symmetric excursion. A self-cycling
## action's cycle length **is** its own fire interval, which is both the mechanical
## truth and the fix for a claim this file used to make and get wrong: the PM-63's
## interval is exactly 0.060000 s against a 0.06 s cycle, so a held PM-63 restarted
## a stroke it had never finished and never came back to battery, and under Double
## Tap it had a quarter of a cycle's worth of time to run a whole one in. Tying the
## two together also makes Double Tap visibly speed the bolt up, which is feel the
## perk bought nothing of.
func _fire_cycle(def: Dictionary) -> void:
	var interval := 60.0 / maxf(float(def.rpm) * Game.rpm_scale(), 1.0)
	if _slide_mode == GUNART.PUMP:
		# A TIMER and not an edge, and that is the part that matters: you rack after
		# every shot, not only when you fire again, so a single shot with nothing
		# behind it still has to rack.
		_slide_t = 0.0
		_slide_len = 0.0
		_slide_delay = interval * PUMP_DELAY
		_slide_pend = interval * PUMP_STROKE
		return
	_begin_stroke(interval if bool(def.auto) else SLIDE_TIME)


func _begin_stroke(span: float) -> void:
	# From wherever the group is resting, out to the far end, and back to wherever
	# it belongs by the time it gets there. `_slide_c` is refreshed every frame in
	# `_tick_slide`, so ammunition arriving mid-stroke changes the landing rather
	# than being ignored until the next one.
	_slide_a = _slide_rest
	_slide_b = 0.0 if _slide_mode == GUNART.OPEN else 1.0
	_slide_c = _slide_rest
	_slide_peak = _stroke_peak()
	_slide_len = maxf(span, 0.0001)
	_slide_t = _slide_len
	_slide_delay = 0.0
	_slide_pend = 0.0
	_slide_cycles += 1


func _stroke_peak() -> float:
	match _slide_mode:
		GUNART.OPEN:
			return 1.0 - SLIDE_BACK
		GUNART.PUMP:
			return PUMP_PEAK
	return SLIDE_BACK


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

	# THE RELOAD DIP, and the two halves are now different mechanisms rather than one
	# with a special case. A segment that is running has a clock and a track, so the
	# track IS the pose (`_drive`). A reload that has been cancelled has neither, so
	# the pose comes home on a rate (`_settle`). `segment()` is the only thing that
	# decides which, and it decides from the state machine's own clock — see there.
	var seg := RELOAD.segment(gun)
	if seg == RELOAD.NONE:
		_dip = _settle(_dip, 0.0, DIP_RATE, dt)
	else:
		_dip = _drive(RELOAD.script_for(gun.key), seg, done)

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
	_tick_slide(dt, gun, state, t)


## The reciprocating group's whole clock, and the two edges nothing else provides.
##
## **THE PER-SHELL EDGE.** `weapon.gd:326-328` re-enters `RELOAD_SHELL` rather than
## continuing it, and says in as many words that the point is for `state_t` to
## sawtooth "once per shell so an animation gets its cycle for free" — and until
## this package nothing consumed it, so a Stakeout's six-shell reload racked the
## pump exactly once, at the start. The latch gates on the state the rig read on the
## **previous** frame, not this one, and that is not a stylistic choice: on the
## closing segment `_load_shell` calls `settle` before the emit, so a latch gated on
## the current frame's state cycles one time short and looks exactly like the defect
## it was written to fix.
##
## **THE REST-POSE EDGE.** The pose a group rests in is a function of the magazine,
## and the magazine changes without any state transition at all — a Max Ammo, a wall
## buy, a shell landing mid-tube. Deriving the release from the pose rather than
## from a signal covers all of them, and it is why `_on_weapon_state`'s old
## `from == EMPTY` branch could go.
func _tick_slide(dt: float, gun: Dictionary, state: int, t: float) -> void:
	var rest := _rest_pose(gun)
	if _slide_delay > 0.0:
		_slide_delay = maxf(0.0, _slide_delay - dt)
		if _slide_delay <= 0.0:
			_begin_stroke(_slide_pend)
	elif _slide_t > 0.0:
		_slide_t = maxf(0.0, _slide_t - dt)
	elif (state == _state_last and state == WEAPON.State.RELOAD_SHELL
			and t > _state_t_last) or not is_equal_approx(rest, _slide_rest):
		# `_slide_rest` is still the OLD pose here and that is load-bearing:
		# `_begin_stroke` reads it as the stroke's starting point, so a bolt release
		# runs FROM held-open rather than snapping to battery and then cycling.
		_cycle_slide()
	_slide_rest = rest
	# Refreshed every frame rather than latched at the start of the stroke, so a
	# magazine that arrives mid-stroke changes where the group comes to rest instead
	# of being ignored until something else moves it.
	_slide_c = rest
	_state_last = state
	_state_t_last = t


## Where the group sits when nothing is driving it, in units of this weapon's own
## travel. Zero is battery — fully forward — and one is the back of the stroke.
##
## **The empty case is an empty MAGAZINE and not `State.EMPTY`**, which is R6's
## whole point: `EMPTY` is `mag <= 0 and res <= 0`, so the M1911's slide lock used
## to be unreachable until 88 rounds had gone with no Max Ammo, and BO1 shows it on
## every empty magazine and releases it during the reload.
##
## **And it is per weapon**, which is R6's other half: the code this replaces pinned
## the group fully rearward for all seven weapons that have one, and five of them
## have no hold-open. On the MP40 that was a double inversion — a weapon with no
## hold-open device at all, held open, in the one position an open bolt is NOT in
## when the magazine runs dry.
func _rest_pose(gun: Dictionary) -> float:
	if _slide_travel <= 0.0:
		return 0.0
	if int(gun.mag) <= 0:
		return 1.0 if GUNART.bolt_holds(_shown_key) else 0.0
	# An open bolt's READY position is the back of its stroke: the sear holds it
	# there and the trigger releases it forward.
	return 1.0 if _slide_mode == GUNART.OPEN else 0.0


## Snap toward a pose the state is actively driving, ease back to rest when it
## stops driving it. `move_toward` and never `lerp`, exactly as the brief for this
## package and M1 F5 both insist: `lerp` is asymptotic and produces the weapon
## that never quite re-centres.
##
## **It no longer carries the DRIVEN reload dip; `_drive` does.** It still carries
## the CANCEL, which is the case it was always right for, and the swap drop, which
## has a clock but reads its own fraction directly.
static func _settle(cur: float, target: float, rate: float, dt: float) -> float:
	if target > cur:
		return target
	return move_toward(cur, target, rate * dt)


## The driven reload pose: the track IS the pose, sampled at the segment's own
## phase and written straight through with no filter between them.
##
## **WHY THIS IS NOT `_settle`, and it is a measured defect and not a retiming.**
## `_settle` is a rate-limited follower — it snaps UP outright and limits the way
## DOWN to `DIP_RATE` — and both halves of that are wrong for a shape somebody
## authored. The snap makes every authored rise a step, so a keyframe that exists
## to make a shell read as a *push* arrives as a glitch instead. The limit makes
## the fall a straight ramp whenever the shape descends faster than 6.0/s, which is
## a rate with no relationship to any track and is already exceeded by the code
## this replaces. MEASURED on commit 2fc7422, driving the real state machine:
##
##   base Stakeout, no perks     EACH segment 0.372954 s, limiter binds  0 of 208 ticks
##   PaP Stakeout + Speed Cola   EACH segment 0.123469 s, limiter binds 17 of  96 ticks,
##                               worst |pose - shape| 0.038186, i.e. 10.9% of SHELL_SCALE
##
## The 0.123469 s is exact and it is the shortest segment the game can reach:
## `papify` takes the Stakeout to mag 9 and reload 2.992 s (`weapons.gd:289-291`),
## `SPEED_RELOAD_MULT` halves it (`game_state.gd:53`), and `shell_unit * SHELL_EACH`
## is 0.217758370 * 0.567. Across a segment that short the shipped
## `sin(done*PI)*SHELL_SCALE` reaches a peak SLOPE of `SHELL_SCALE*PI/0.123469` =
## **8.905535/s against DIP_RATE 6.0**.
##
## **AND A CORRECTION TO THE CLAIM THAT SENT ME LOOKING.** The brief for this stage
## said those arcs "merge into one held dip". They do not, and the arithmetic says
## why: merging needs the whole descent to outrun the limiter, i.e.
## `EACH < 2*SHELL_SCALE/DIP_RATE` = 0.116667 s, and the shortest reachable EACH is
## 0.123469 s — clear by 6.8 ms. Measured rather than argued: the shipped rig
## returns the weapon all the way to rest **7 times** in a base six-shell reload and
## **10 times** in a Pack-a-Punched nine-shell one, once per segment, every time.
## That count is the actual defect and it is what `checks/systems.gd` asserts on;
## the rate limit is a real but secondary distortion of the shape on the way there.
static func _drive(script: int, seg: int, phase: float) -> float:
	# THE ONE SITE `SHELL_SCALE` IS READ. A magazine reload is authored at full
	# amplitude and a shell reload is the same tables scaled, so the two families
	# stay comparable row for row in `reload.gd` — see the constant.
	var amp := 1.0 if seg == RELOAD.WHOLE else SHELL_SCALE
	return RELOAD.sample(script, seg, phase).x * amp


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
	#
	# TWO CORRECTIONS TO THE HEADER'S CHAIN, both checked 2026-08-04, because "one
	# writer per node" gets read as more than it says and this line is where it is
	# read. The node is called `Viewmodel` at runtime and not `ViewmodelRoot`
	# (`main.gd:125`); `ViewmodelRoot` is the role, and it is the name CLAUDE.md's
	# camera chain and the M5/M6 notes use, so the two do not resolve to each other
	# by grep. And the rule that actually holds is about the TRANSFORM: the line
	# below is its only writer anywhere in the project, but `main.gd:_bare_frame()`
	# writes `viewmodel.visible` either side of a second draw (`main.gd:776` and
	# `:779`) to photograph the room without the gun in it. That is not a second
	# pose writer and it cannot move a vertex, which is why the clip argument is
	# untouched by it — but "written only by `_apply()`" is not literally true of
	# the node, and a reader auditing the guarantee should not have to find that out
	# from `main.gd`.
	transform = Transform3D(Basis.from_euler(Vector3(_sway.x, _sway.y, 0.0)),
		Vector3(_bob.x, _bob.y, 0.0))

	var melee := 0.0
	if _melee_t > 0.0:
		melee = sin((1.0 - _melee_t / MELEE_TIME) * PI)
	_mesh.transform = _mesh_pose(_kick, _dip, _swap + _sprint, melee, _player.ads(),
		_sight)
	_slide.position = Vector3(0.0, 0.0, _slide_offset())
	# THE SUPPORT HAND IS ANIMATION-INERT IN THIS STAGE, and this line is the claim.
	# Written rather than left at whatever `MeshInstance3D.new()` happened to give,
	# because "nobody has touched it" and "one writer writes it, and writes identity"
	# are different guarantees and only the second survives a second writer appearing.
	# It is also the seam the reload keyframes land on: when a segment pose arrives it
	# replaces THIS expression, so the check that pins it to identity is the check that
	# will go red the day it starts moving — which is exactly when someone should look.
	_support.transform = Transform3D.IDENTITY


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


## The group's displacement along the weapon's own axis, in metres.
##
## Three positions and one peak rather than one ramp and one constant. A closed bolt
## starts and ends at battery and peaks a third of the way in; an open bolt starts
## and ends held back and peaks at the mirror of that; a pump starts and ends
## forward, peaks in the middle and does not start until `_slide_delay` has run. And
## the ends need not agree with the start — the last round out of an M1911 begins at
## battery and ends held open, the last round out of an MP40 begins held back and
## ends forward — which is the case the old single ramp could not express at all.
func _slide_offset() -> float:
	if _slide_travel <= 0.0:
		return 0.0
	var f := _slide_rest
	if _slide_t > 0.0:
		var u := 1.0 - _slide_t / _slide_len
		if u < _slide_peak:
			f = lerpf(_slide_a, _slide_b, u / _slide_peak)
		else:
			f = lerpf(_slide_b, _slide_c, (u - _slide_peak) / (1.0 - _slide_peak))
	return f * _slide_travel


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
	# **VISIBILITY FOLLOWS `ONE_HANDED` AND NOTHING ELSE, exactly as it did while the
	# hand was part of `build_body`.** No weapon gains or loses a hand in this stage:
	# the dictionary is missing precisely the three keys `GUNART.build_support_hand`
	# returned null for, so this is the same predicate the ancestor's `if(key!=='m1911'
	# && key!=='knife' && key!=='raygun')` is (html:1233), reached through the mesh
	# cache rather than restated here. Keyed off `key` and not `k`: there is no
	# Pack-a-Punched glove.
	var hand: Mesh = _support_meshes.get(key)
	_support.mesh = hand
	_support.visible = hand != null
	# Both latched off the key actually shown, for the same reason `_sight` is: a
	# per-frame dictionary lookup for a value that changes on the frames the mesh
	# changes and never otherwise. Travel is forced to zero when there is no group,
	# so `_rest_pose` cannot pose a mesh that does not exist — the knife shown over
	# a held MP40 is exactly that case.
	_slide_travel = GUNART.slide_travel(key) if slide != null else 0.0
	_slide_mode = GUNART.slide_mode(key)
	# The new weapon arrives already in its own resting pose rather than sliding
	# into it: `_tick_slide` reacts to a rest-pose CHANGE, and without this a swap
	# from a closed bolt to an open one would read as the MP40 racking itself on the
	# frame it came up. Any stroke the outgoing weapon was mid-way through is over.
	_slide_t = 0.0
	_slide_delay = 0.0
	_slide_rest = _rest_pose(_player.current_gun())
	_slide_c = _slide_rest
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
## **ENDPOINTS ARE SUFFICIENT FOR A TRANSLATION AND UNSOUND FOR A ROTATION, and
## four shipped channels are rotations.** `worst` and `widest` are norms, hence
## convex, and `nearest` is linear; a max of a convex function or a min of a linear
## one over a set is attained at an extreme point of that set's convex hull. A
## translated point's reachable set is a SEGMENT, which is its own hull — so
## `_collect(slide, ..., travel)` is not merely reasonable, it is provably
## sufficient. A rotated point's reachable set is an ARC, whose hull's extreme
## points are the whole arc, so any inscribed sample is an UNDER-estimate: the one
## direction a safety assertion may not err in. `dip`, `ads`, `kick` and the gun
## `melee` all enter `_mesh_pose`'s basis and all four were sampled at two points.
##
## The fix is a circumscribed polygon: sample K+1 angles across the arc and scale
## each sample radially about the pivot by `1/cos(step/2)`. The pivot IS the mesh
## origin — `_mesh_pose` returns `Transform3D(basis, origin)`, so the basis turns
## the point about the grip and the origin translates the result — which makes
## "scale radially about the pivot" exactly "scale `p`", because
## `B*(k*p) + o == k*(B*p) + o`. The resulting polygon provably CONTAINS the arc, so
## its max is a safe over-estimate and its min a safe under-estimate, and the excess
## shrinks as step². K comes from the closed form
## `ratio * r_max * (1 - cos(step/2)) <= ARC_TOL`, evaluated per weapon against that
## weapon's own furthest corner rather than against a global bound.
##
## What this replaces was a MEASUREMENT — "a dense sweep does not beat the endpoints
## by more than 0.2 mm on any of the three" — that nothing re-ran and that any
## amplitude increase would have invalidated in silence. `ADS_YAW` is exactly such
## an increase and it is in this package.
##
## Sway is still a 3x3 grid and still not arc-sampled: it is written to
## `ViewmodelRoot`, which sits AT the camera origin, so `worst` and `nearest` are
## invariant under it and only `widest` sees it at all — and there the 3x3 already
## brackets a 0.05 rad excursion whose sagitta at r = 0.23 m is 0.07 mm.
##
## Called once, from `verify.gd`, and cached; nothing in the game may call it per
## frame.
func _measure() -> void:
	if _measured:
		return
	_measured = true
	_extreme = sweep(true)


## The rotational channels of `_mesh_pose`'s basis, named, with the arc each one
## sweeps and the interval `sweep()` samples it over. **THE SINGLE SOURCE, because
## there used to be two and they could not disagree out loud.** `sweep()` enumerated
## these four by hand and `checks/systems.gd`'s "every rotational channel is sampled
## just finely enough to stay conservative" restated the same four literally in a
## second array — so a fifth channel added here and forgotten there would have left
## the check whose entire job is policing rotational sampling testing four channels
## while five were live, and NEITHER list would have reddened. Both read this one now.
##
## Everything else in the pose is a translation, whose reachable set is a segment and
## which endpoints already bracket exactly; only a rotation traces an arc, and an arc
## is what `_arc` and `_arc_grow` exist for. See `_measure()` for the derivation.
##
## `amp` is that arc in radians, which is what the sampler is solved against. `lo`
## and `hi` are the units `_mesh_pose` takes for the channel, which is why kick's
## interval is `[0, KICK_MAX]` and the other three are `[0, 1]` — the amplitude and
## the interval are different quantities and conflating them is how a channel gets
## sampled against the wrong arc. `knife_only` is the melee channel and nothing else:
## `_apply()` only ever shows the knife while it is lit, so pairing a rifle's muzzle
## with a full melee sweep would measure a frame the rig cannot draw, and it costs
## 4 mm of an 8 mm margin to do it.
##
## ADS's amplitude is a SUM because the sighted pose removes `REST_YAW`'s yaw and
## `REST_PITCH`'s cant together, so the arc it traces is neither of them alone.
##
## Static because it is a statement about the constants above and nothing about a
## live rig — `checks/systems.gd` reads it without an instance.
static func arcs() -> Array:
	return [
		{"name": "dip", "amp": DIP_ROLL, "lo": 0.0, "hi": 1.0, "knife_only": false},
		{"name": "ads", "amp": REST_YAW * ADS_YAW + absf(REST_PITCH) * ADS_LEVEL,
			"lo": 0.0, "hi": 1.0, "knife_only": false},
		{"name": "kick", "amp": absf(KICK_PITCH) * KICK_MAX,
			"lo": 0.0, "hi": KICK_MAX, "knife_only": false},
		{"name": "melee", "amp": absf(MELEE_ROT), "lo": 0.0, "hi": 1.0,
			"knife_only": true},
	]


## The sweep itself, with the arc construction switchable — and the switch is here
## for one reason: **an assertion that the interior sampling is doing anything has
## to be able to ask for the sweep without it, and it must be THIS sweep and not a
## second copy of its arithmetic.** `checks/systems.gd` runs both and requires the
## interior one to report a strictly larger extreme; with `interior` false this is
## exactly the endpoint-only sweep that shipped.
##
## Uncached on purpose. `_measure()` is the cached entry point and the only one the
## game or `verify.gd` reaches for; this one is ~1 s of arithmetic and is called
## twice, by one check, once.
func sweep(interior: bool) -> Vector3:
	# From the camera rather than from a constant, so a field of view that ever
	# moves cannot leave a stale copy of this behind. See VIEWMODEL_FOV.
	var ratio := tan(0.5 * deg_to_rad(_cam.fov)) / tan(0.5 * deg_to_rad(VIEWMODEL_FOV))
	# A pure lateral translation, so it is added to the lateral term of each
	# metric rather than being swept as a channel of its own.
	var bob := Vector2(BOB_X, BOB_Y).length()
	var sways: Array[float] = [-SWAY_MAX, 0.0, SWAY_MAX]

	var worst := 0.0
	var nearest := 1e9
	var widest := 0.0
	_swept.clear()
	_swept_support.clear()
	for key: String in GUNART.keys():
		var into := {}
		# Annotated rather than inferred, all four: a call through a preloaded
		# script constant is the kind of expression this project builds as an error
		# when its result is handed to a typed parameter unchecked.
		var body: PackedVector3Array = GUNART.body_corners(key)
		var slide: PackedVector3Array = GUNART.slide_corners(key)
		# **THE OTHER HALF OF `body_corners`, AND THE WHOLE SAFETY ARGUMENT FOR THE
		# SPLIT.** Until the reload package these sixteen points per two-handed weapon
		# came out of `body_corners` itself; taking them separately at zero offset
		# makes the pool below IDENTICAL to the pre-split one, which is what keeps
		# every clip figure a statement about the same weapon it was measured on.
		# Zero offset because this stage poses the hand at identity — the day it moves,
		# this call gains that motion's endpoints and this comment is where to start.
		var support: PackedVector3Array = GUNART.support_corners(key)
		# THE TRAP THIS LINE EXISTS TO CLOSE. This used to be the global
		# `SLIDE_TRAVEL`, and travel is per weapon now. Every component of `_extreme`
		# is insensitive to slide travel BY CONSTRUCTION — rearward travel moves the
		# group toward the grip, so `widest` falls, and the near plane is set by a
		# body part (the M14's stock) and not by any group — so deleting this line
		# outright leaves the whole suite green and no aggregate metric can tell.
		# `swept_travels()` is the readout that can, and it is why one exists.
		var travel: float = GUNART.slide_travel(key)
		_collect(body, into, 0.0)
		_collect(slide, into, 0.0)
		# The readout is a MEASUREMENT OF THE POOL rather than a copy of
		# `support.size()`, for the reason `_swept` states one line down: a count taken
		# off the argument would go on reporting sixteen corners beside a deleted
		# `_collect`. `_collect` returns its offset and cannot answer this, so the
		# question is put to `into` itself, either side of the call.
		var pooled := into.size()
		_collect(support, into, 0.0)
		_swept_support[key] = into.size() - pooled
		# The readout is the RETURN of the collect and not a copy of its argument,
		# deliberately: a `_swept[key] = travel` beside a deleted `_collect` would go
		# on reporting a travel nothing swept, which is the exact shape of the bug
		# this readout exists to catch.
		_swept[key] = _collect(slide, into, travel)
		var pts := PackedVector3Array(into.keys())
		# THE WHOLE REASON THIS LOOP IS PER WEAPON. Through the same accessor the rig
		# poses with, so a sight height that stopped being derived from the mesh would
		# move the assertion and not just the picture.
		var sight: float = GUNART.sight_height(key)
		var r_max := 0.0
		for p: Vector3 in pts:
			r_max = maxf(r_max, p.length())

		# The channels that enter `_mesh_pose`'s BASIS, folded out of `arcs()` rather
		# than enumerated a second time here. Their samples and their inflation come
		# off ONE walk of that list, so a channel cannot be sampled without being
		# inflated for, nor inflated for without being sampled.
		var lanes := {}
		var grow := 1.0
		_arc_grew.clear()
		for ch: Dictionary in arcs():
			var id: String = ch["name"]
			var amp: float = ch["amp"]
			var lo: float = ch["lo"]
			var hi: float = ch["hi"]
			var lit: bool = key == "knife" or not bool(ch["knife_only"])
			# An unlit channel collapses to its own `lo`, which is the identity pose
			# for it — one point in the nest below, and `_arc_grow` reads 1.0 off a
			# single sample, so it costs nothing in the margin either. That is exactly
			# what the melee channel did on twelve of the thirteen weapons before.
			var s: Array[float] = [lo]
			if lit:
				if interior:
					s = _arc(lo, hi, amp, r_max, ratio)
				else:
					s.append(hi)
			lanes[id] = s
			if interior:
				# One inflation for the whole pose, and it is the PRODUCT of the
				# per-channel factors rather than the largest of them: the channels
				# compose into one basis, and a product of terms each >= 1
				# circumscribes every one of them.
				#
				# Recorded and then multiplied from the record, in that order and off
				# that one value: `grow` is a single float and every component of
				# `_extreme` clears its bound by millimetres, so a factor quietly
				# dropped moves the metrics by less than a retune does and no refusal
				# in this project can see it — melee's factor is exactly 1.0 on twelve
				# of thirteen weapons, so dropping THAT one moves nothing at all.
				# `arc_growth()` is what can see it, and it only can if the record and
				# the multiply cannot come apart.
				_arc_grew[id] = _arc_grow(s, amp)
				grow *= float(_arc_grew[id])
		# By name, out of the same walk. The nest below takes its channels as named
		# `_mesh_pose` arguments and so it cannot be written generically; a channel
		# renamed in `arcs()` and not here throws on this line rather than silently
		# sweeping an empty lane, which is the loud failure and the reason the nest
		# is allowed to go on naming its four.
		var dips: Array[float] = lanes["dip"]
		var adss: Array[float] = lanes["ads"]
		var kicks: Array[float] = lanes["kick"]
		var melees: Array[float] = lanes["melee"]
		var swept := PackedVector3Array()
		for p: Vector3 in pts:
			swept.append(p * grow)

		for kick: float in kicks:
			for dip: float in dips:
				for drop: float in [0.0, SWAP_DROP + SPRINT_DROP]:
					for melee: float in melees:
						# Both ends of the sights, because the clipping budget has to hold at the
						# sighted pose too — that pose moves the weapon 8 mm toward the near plane
						# and up to 20 mm down, and the drop is what puts the lateral term up.
						for ads: float in adss:
							var mp := _mesh_pose(kick, dip, drop, melee, ads, sight)
							for sx: float in sways:
								for sy: float in sways:
									var root := Basis.from_euler(Vector3(sx, sy, 0.0))
									for p: Vector3 in swept:
										var v := root * (mp * p)
										var lat := Vector2(v.x, v.y).length() + bob
										worst = maxf(worst, v.length() + bob)
										# The bob has no z component, so depth needs no
										# correction for it.
										nearest = minf(nearest, -v.z)
										widest = maxf(widest,
											sqrt(v.z * v.z + ratio * ratio * lat * lat))
	return Vector3(worst, nearest, widest)


## What `sweep()` actually collected at, weapon key to travel in metres.
##
## **This exists because no aggregate metric can tell you whether the second
## `_collect` call is still there.** All three components of `_extreme` are
## insensitive to slide travel by construction — rearward travel moves the group
## toward the grip, so `widest` falls with it, and the near plane is set by the M14's
## stock — so deleting the travel endpoint outright leaves every clip assertion
## green. A refusal cannot separate "safe" from "unmeasured"; only a readout can.
func swept_travels() -> Dictionary:
	_measure()
	return _swept.duplicate()


## Weapon key -> how many points the support hand actually put into that weapon's
## pool: 16 on a two-handed weapon (two rects, four corners each, both extrusion
## caps) and 0 on the three `ONE_HANDED` ones.
##
## **THE SAME KIND OF READOUT `swept_travels()` IS, AND FOR THE SAME REASON.** The
## support hand sits thirty art units forward of the grip and five art units either
## side of it, which is inside every weapon's own barrel reach — so it sets none of
## `worst`, `nearest` or `widest` on any weapon on the roster, and dropping its
## `_collect` outright leaves all four clipping assertions green. A refusal cannot
## separate "the split kept every corner" from "the split lost sixteen of them and no
## metric noticed"; a count can. It is a delta measured across the call rather than a
## restatement of `support_corners().size()`, so it reads zero the moment the call
## goes away.
func swept_support() -> Dictionary:
	_measure()
	return _swept_support.duplicate()


## Rotational channel name -> the circumscribing factor the last interior `sweep()`
## folded into `grow` for the last weapon it swept.
##
## **THE THIRD READOUT, AND THE SAME ARGUMENT AS THE OTHER TWO.** `arcs()` is now the
## only list of rotational channels, which is what stops it disagreeing with
## `checks/systems.gd` — but a list is only worth anything if what reads it actually
## consumes all of it, and `grow` is one float that cannot say how many factors went
## into it. A channel declared and never folded in leaves every clip assertion green:
## the margins clear by millimetres, the factors are hundredths of a percent, and
## melee's is exactly 1.0 on every weapon but the knife. A count can see it.
##
## Deliberately does NOT call `_measure()`, unlike its two siblings: it reports the
## sweep the caller last drove and an interior sweep is the only kind that folds
## anything, so a caller that wants this has to ask for `sweep(true)` itself and read
## it before the next sweep overwrites it. Empty after `sweep(false)`, which applies
## no factors at all and says so rather than reporting stale ones.
func arc_growth() -> Dictionary:
	return _arc_grew.duplicate()


## The samples for one rotational channel: K+1 values across `[lo, hi]`.
##
## K is solved rather than tabulated — the smallest count whose circumscribing
## excess `ratio * r * (1 - cos(step/2))` is inside `ARC_TOL`. **It is therefore a
## property of the weapon and not of the channel**, because `sweep()` passes that
## weapon's own `r_max`, and this paragraph used to give one set of counts as though
## it were not. MEASURED 2026-08-04 on commit 2fc7422 by printing the solved counts
## out of the live sweep, over all thirteen weapons:
##
##   dip    0.50000 rad   K = 3 on the m1911 and the PM-63, K = 4 on the other 11
##   ads    0.32893 rad   K = 2 on the m1911 and the PM-63, K = 3 on the other 11
##   kick   0.06000 rad   K = 1 — i.e. the endpoints, unchanged — everywhere
##   melee  0.85000 rad   K = 6, on the knife, the only weapon it is ever lit for
##
## The two threes are the two smallest guns and nothing subtler: `r_max` is
## 0.032489 m on the m1911 and 0.038744 m on the PM-63 against 0.043401-0.059508 m
## across the other eleven, and a smaller radius reaches the same excess at a
## coarser step. The set this claimed before — 4 / 2 / 1 / 7 — is no weapon's
## solve: the 4 and the 7 are what a radius near 0.06 m gives (`checks/systems.gd`
## sweeps the solver at a synthetic `r = 0.06`, and the Olympia's 0.059508 is the
## nearest real one), while the 2 is what only the two smallest give.
##
## Solving it is what makes R10's "one float, then re-measure" an actual defence: a
## wider `ADS_YAW` buys itself another sample instead of quietly widening an arc
## nothing looks inside.
##
## `ARC_MAX_SAMPLES` is a bound on the loop and not a tuning knob. It is reached
## only by an amplitude nobody has authored; if it ever binds, the sweep silently
## stops being conservative, so `checks/systems.gd` asserts every channel's solved K
## is strictly under it.
static func _arc(lo: float, hi: float, amp: float, r: float,
		ratio: float) -> Array[float]:
	var k := _arc_k(amp, r, ratio)
	var out: Array[float] = []
	for i in k + 1:
		out.append(lerpf(lo, hi, float(i) / float(k)))
	return out


static func _arc_k(amp: float, r: float, ratio: float) -> int:
	var k := 1
	while k < ARC_MAX_SAMPLES:
		if ratio * r * (1.0 - cos(absf(amp) / float(k) * 0.5)) <= ARC_TOL:
			break
		k += 1
	return k


## How far a sample has to be pushed out along its own radius for the polygon
## through the samples to CONTAIN the arc they were taken off, rather than being
## inscribed in it. Derived from the sample count the caller actually got, so the
## two cannot drift apart; 1.0 for a channel with no arc to circumscribe.
static func _arc_grow(samples: Array[float], amp: float) -> float:
	if samples.size() < 2:
		return 1.0
	return 1.0 / cos(absf(amp) / float(samples.size() - 1) * 0.5)


## Returns the offset it used, so `sweep()` can record what it actually collected
## at rather than what it meant to. See `swept_travels()`.
static func _collect(pts: PackedVector3Array, into: Dictionary, z_off: float) -> float:
	var off := Vector3(0.0, 0.0, z_off)
	for p: Vector3 in pts:
		into[p + off] = true
	return z_off


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
