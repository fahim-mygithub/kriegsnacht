class_name Zombie
extends CharacterBody3D

## One undead. Nodes are built in code rather than from a .tscn so the whole
## entity — collider, billboard, hitbox split — lives in one readable place.

signal died(z: Zombie, was_headshot: bool, by_melee: bool)

## `ENTERING` was declared here from the first commit and assigned by nothing; it
## is the vault now, which is exactly what the name always meant. `TEARING_BOARDS`
## is appended rather than inserted because `player.gd`, `verify.gd` and this file
## all compare against `State.DYING` by value, and renumbering the four that
## already exist would move that comparison without moving any of them.
enum State { ENTERING, CHASING, ATTACKING, DYING, TEARING_BOARDS }

## preload rather than the class name: `barricade.gd` is new, so it is not in the
## class registry until the editor rescans and a headless run has no editor. Only
## the static `of()` is used from here — a zombie is handed a window index by the
## round director and finds its barricade from that alone.
const BARRICADE := preload("res://scripts/world/barricade.gd")

## The one line-of-sight test in the game, shared with the Thundergun's wedge and
## the interaction scan. This file used to carry its own copy; two visibility tests
## that have to agree is how they stop agreeing. preload rather than the `Los` class
## name, for the same reason as above.
const LOS := preload("res://scripts/world/los.gd")

const SEPARATION_RADIUS := 0.62
const SEPARATION_FORCE := 2.4

## The separation sum used to be unbounded: each neighbour contributes up to 1.0,
## summed over every neighbour, multiplied by 2.4, then added to a *unit-length*
## steering vector. With four or more crowded neighbours the push outweighed the
## steering five to ten times over, so a dense pack behaved like a repulsion gas
## and could drift away from the player and into walls. Clamped before scaling.
const SEPARATION_LIMIT := 0.6

## Line of sight beats the flow field, but only nearby. Unbounded it fired 24
## full-length raycasts per tick and funnelled the entire horde onto one point
## across a 16x14 room. Near-goal only, which is what the technique is for.
const LOS_RANGE := 9.0

const GROAN_MIN := 3.5
const GROAN_MAX := 9.0
const GROAN_RANGE := 20.0

## THE COLLIDER, RECONCILED WITH THE SPRITE (§4.2). ONE radius, for all three
## kinds, and it is the ancestor's own: `r: isDog?0.30:0.30` at
## kriegsnacht.html:2214, tested as `if(perp > z.r) continue` at html:2486.
##
## What was here before M4 was `0.26 if kind != "hound" else 0.30`, and 0.26 has
## a provenance too — it is `const R = 0.26` at html:2337, the radius the ancestor
## keeps a zombie's CENTRE off a WALL while it walks. Two quantities, two places;
## the port collapsed them into one and kept the wall one.
##
## The evidence note quotes the resulting gap as "~0.42 m per side of unhittable
## billboard", from 48 px x 0.02844 m/px = 1.365 m of drawn width. That is the
## CELL, not the sprite: measured at the sprite's own 0.35 alpha scissor the
## walker's ink spans at most 32 px, 0.910 m, and 0.26 already covered 85.5% of
## the head-on view.
##
## WHY ONE NUMBER AND NOT THREE. A capsule is radially symmetric and the drawn
## width is a function of bearing, so no single radius can match a silhouette at
## every bearing — the criterion has to name which error it is minimising. A shot
## that lands on visible pixels and registers nothing is what §4.2 calls broken
## hit registration and is what a player perceives; a shot that lands a few
## centimetres beside a body and connects is invisible. So the radius is chosen
## to minimise MISSES, and because coverage is monotonic in radius that means
## taking the largest figure either source supports rather than the smallest.
##
## Measured over all eight bearings of the shipped atlas, at the 0.35 scissor,
## every live cycle, every palette (scripts/dev/checks/enemies.gd re-measures
## from the PNGs rather than trusting this table):
##
##   kind     r=0.22   r=0.26   r=0.30   r=0.34    head-on ink half-width
##   walker    78.0%    84.5%    92.5%    94.6%    0.4550 m
##   crawler   84.8%    93.2%    97.5%    99.5%    0.2371 m
##   hound     65.2%    75.4%    80.2%    87.7%    0.2205 m
##
## An earlier M4 pass set these to the 95%-of-ink radius of the HEAD-ON view
## alone — 0.30/0.23/0.22 — which reads well for the walker and is a regression
## for the other two at six of the eight bearings: it took the hound from 80.2%
## to 65.2% covered and its profile from 57.5% to 40.2%, i.e. a round placed
## squarely on the middle of a dog's flank stopped registering. Going past 0.30
## is not supported by either source, so 0.30 it is.
##
## THE COST, RECORDED. This capsule is also the physics body (layer 4, mask 1|2),
## so it is the wall clearance as well, and moving it from 0.26 to 0.30 moves the
## ancestor's html:2337 clearance by 4 cm for walkers and crawlers. That is a
## deliberate departure: a doorway on this map is a whole tile, 0.60 m of body
## still passes one with 0.40 m to spare, and the alternative — a second shape
## for the hit volume — costs an Area3D per body and a `collide_with_areas`
## change in player.gd for four centimetres of wall hugging.
const HIT_RADIUS := 0.30

## Frames of walk cycle per metre travelled. `z.anim += dt*spd*2.6` (html:2340),
## where `anim` indexes the walk strip directly (`set.walk[(z.anim|0) % len]`,
## html:2074) — so 2.6 is frames per metre and it is the whole of the ancestor's
## animation timing. The port drove `speed_scale` off a one-shot random instead,
## which let a sprint-class zombie shuffle slower than a walker.
const ANIM_FRAMES_PER_METRE := 2.6

## The walk animation's authored rate in `sprite_lib.gd::frames_for`. `speed_scale`
## multiplies it, so the conversion from "frames per metre" to a scale factor
## needs this. Duplicated from there deliberately: a scale is meaningless without
## the rate it scales, and the assertion in enemies.gd reads the live
## SpriteFrames rather than this constant, so a drift is caught rather than
## mirrored.
const WALK_FPS := 8.0

## Everything below this fraction of the body's height is leg. The walker's hip
## joint is drawn at `base-20` on a 64 px cell standing 1.82 m (html:861), which
## is 0.626 m off the floor — 0.344 of the body. Rounded down, so the band never
## reaches into the coat.
const LEG_FRACTION := 0.34

## Damage into the leg band needed to take the legs off, as a fraction of the
## body's full health. Accumulated rather than tested per shot: a single
## threshold would let one M14 round at a walker's shin make a crawler, and BO1
## takes a burst. Half a zombie's health into its legs leaves it the other half,
## which is the whole point of the mechanic — a crawler is a zombie you chose not
## to finish.
const LEG_BREAK := 0.5

## What a walker keeps when its legs go. `_configure` gives a spawned crawler
## `base_speed * 0.62`, so this is that same factor applied to a speed that has
## already been rolled — a legged sprinter stays the fastest crawler on the map,
## which is both the reference's behaviour and the reason legging one is a
## decision rather than a free win.
const CRAWLER_SPEED := 0.62

## Seconds of delay per metre from the player before a nuked body actually
## collapses. Without it the whole horde hits the floor on one frame, which reads
## as a bug rather than as a detonation; with it the collapse leaves the player as
## a wave. Capped, because the map's far corner is 45 m away and a corpse that
## stands for two seconds after the toast is its own kind of wrong.
const NUKE_STAGGER := 0.045
const NUKE_STAGGER_MAX := 1.0

## The fake ragdoll, and it is deliberately a slide rather than a physics body:
## §2.1's frame budget has no room for 24 RigidBody3Ds and BO1 does not have them
## either — a zombie there is a canned death animation plus a shove. Metres per
## second at the moment of collapse, by what did the killing; the body decays to a
## stop over SHOVE_DECAY.
const SHOVE_BULLET := 0.55
const SHOVE_MELEE := 1.6
const SHOVE_BLAST := 2.4
const SHOVE_DECAY := 7.0

## How long a corpse stays after it has finished falling, and how long it takes to
## go. The ancestor removed the body at 0.75 s flat (html:2256) and the port held
## it for `frames/9 + 0.9`; this is that same total, re-apportioned so the last
## third of it is a fade instead of a corpse standing at full opacity and then
## being deleted between two frames. No extra draw calls, no extra lifetime.
const CORPSE_HOLD := 0.55
const CORPSE_FADE := 0.35

## What killed it. Threaded from the call sites, which have always had this and
## have always thrown it away: `_apply_hit` knows whether it was a bullet or the
## Thundergun, `_knife` knows it was a blade, and the Nuke sweep is bracketed by
## `Game.nuke_clearing`. The death reads as what caused it or it reads as one
## animation played 24 times.
enum Cause { BULLET, MELEE, BLAST, NUKE }

## Working the boards. `boardT: rnd(1.2,0.3)` at spawn (html:2212), then
## `z.boardT = z.type==='hound' ? 0.42 : rnd(1.5,0.9)` after each plank
## (html:2274). `rnd(a,b)` is `b + random()*(a-b)` (html:377), so both of those are
## ranges written with the larger number first.
##
## Note the interval is **0.9-1.5 s**, not the 0.9-1.4 the milestone plan quotes,
## and the hound's flat 0.42 s is not in the plan at all — a dog is through a
## barricade in two and a half seconds against a walker's seven, which is most of
## what makes a dog round feel like a different game.
const BOARD_FIRST_MIN := 0.3
const BOARD_FIRST_MAX := 1.2
const BOARD_MIN := 0.9
const BOARD_MAX := 1.5
const BOARD_HOUND := 0.42

## `z.atkAnim = 0.3` on every plank (html:2278) — the swing that pulls it off. The
## walk cycle resumes underneath it, which is what stops a zombie at a window
## reading as an idle prop between boards.
const BOARD_SWING := 0.3

## The tear cue, positioned. `Audio2.board(...)` (html:501-503, called at :2276) is
## the ancestor's own sound for this and the port has never played it: `main.gd`
## plays the same baked `board` buffer, but on the *rebuild* and on Carpenter,
## where the ancestor used a different sound entirely (`repair()`, :504). So the
## "baked and never played" note in the gap analysis is stale — the buffer is
## played — but this, the event it was written for, is genuinely new.
const BOARD_VOLUME := -7.0

## The traversal, once the last plank is off. The ancestor did not have one:
## `if(w.boards<=0){ z.state='chase'; z.x=w.ix+0.5; z.y=w.iy+0.5; }` (html:2271) is
## a teleport in a single statement. 1.2 s is the plan's figure and it is invented
## there too — but the hitbox stays live for every frame of it, which is the part
## that matters: a zombie that cannot be shot while it climbs in is a free entry,
## and free entry is the opposite of what a barricade is for.
const VAULT_TIME := 1.2

## Eye geometry, in the sprite's own pixels, read off the ancestor's draw calls
## so the quads land on the pixels the art already lights up: a `#F3E4A8` core
## inside a soft halo on every walker and crawler frame (kriegsnacht.html:939,
## 1044) and `#FF7A18` burning eyes on the hound (:1105). They are dark in the
## port only because the billboard is `shaded = true` and the map is dark.
##
## `y` is the row from the top of the cell, averaged over the vertical bob the
## ancestor applied per frame; `sep` the gap between the two eye centres; `x` how
## far the pair sits from the cell's horizontal centre — zero for a walker, well
## left for a crawler dragging its head and for the hound, which is drawn in
## profile; `glow` the footprint of one eye, taken from the halo rect where the
## ancestor drew one. Everything is converted through `SpriteLib.pixel_size(kind)`,
## so the eyes move with the body if `SpriteLib.HEIGHT` ever changes.
##
## `glow` rather than `size` because dot-access on a `Dictionary` is a key
## lookup and `size` is also a `Dictionary` method — not worth finding out which
## one wins on a build that hangs rather than reports a parse error.
const EYE_PX := {
	"zombie": {"y": 14.9, "sep": 5.9, "x": 0.0, "glow": 4.6},
	"crawler": {"y": 15.4, "sep": 4.6, "x": -13.2, "glow": 4.1},
	"hound": {"y": 10.6, "sep": 4.4, "x": -18.3, "glow": 6.0},
}

## The same geometry, per bearing. `EYE_PX` above is the row for the view the
## ancestor drew — 0 for a walker, 2 for the crawler and the hound, which are
## authored in profile — and every other row here is the projection of the same
## body-space eye positions that `tools/gen/views.js` draws through, so the
## additive quads land on the pixels the art lights up rather than beside them.
##
## `n` is how many eyes that bearing shows. Two facing you, ONE in profile
## (the far eye is behind the nose, and drawing two there is what would give a
## profile zombie a headlight), and NONE from behind. That last one is the whole
## reason this table exists: a zombie with its back to you must not glow at you,
## and until the atlas there was no bearing at which it did not.
##
## `x` is measured from the cell's horizontal centre in the un-mirrored art, so a
## mirrored row negates it — see `_eye_mesh`. Rows 0 and 4 are never mirrored, so
## their `x` is always 0 and the question does not arise.
const EYE_VIEW := {
	"zombie": [
		{"x": 0.00, "sep": 5.90, "n": 2},
		{"x": 3.25, "sep": 4.10, "n": 2},
		{"x": 4.60, "sep": 0.00, "n": 1},
		{"x": 0.00, "sep": 0.00, "n": 0},
		{"x": 0.00, "sep": 0.00, "n": 0},
	],
	# Row 2 is the ancestor's own frame for both of these, and the ancestor draws
	# TWO eyes on a head in profile — `fillRect(-16.4,...)` and `fillRect(-11.8,...)`
	# for the crawler (html:1044) and the same pair on the hound (html:1104). It is
	# loose anatomy and it is what is on the pixels, so the quads match the art
	# rather than the model. `views.js` culls the far socket on the bearings it
	# draws itself, which is why row 1 has two and the walker's row 2 has one.
	"crawler": [
		{"x": 0.00, "sep": 4.60, "n": 2},
		{"x": 12.16, "sep": 3.25, "n": 2},
		{"x": 13.20, "sep": 4.60, "n": 2},
		{"x": 0.00, "sep": 0.00, "n": 0},
		{"x": 0.00, "sep": 0.00, "n": 0},
	],
	"hound": [
		{"x": 0.00, "sep": 4.80, "n": 2},
		{"x": 15.13, "sep": 3.39, "n": 2},
		{"x": 18.30, "sep": 4.40, "n": 2},
		{"x": 0.00, "sep": 0.00, "n": 0},
		{"x": 0.00, "sep": 0.00, "n": 0},
	],
}


## One tint per palette. The three ZPAL bodies (html:844-848) are meant to read
## as three different corpses and the groan pitch already splits on `pal`, so the
## eyes split too — but only inside the authored amber band, because franchise
## undead eyes are warm and a cold-eyed zombie reads as a different game.
## Palette 0 is the ancestor's `#F3E4A8` unchanged; 1 is pushed warm to sit with
## its brown cloth, 2 paler and faintly green to sit with its blue-grey skin.
const EYE_TINT := [
	Color(0.953, 0.894, 0.659),
	Color(1.000, 0.816, 0.502),
	Color(0.886, 0.941, 0.753),
]

## `#FF7A18`, verbatim (html:1105). A hellhound is on fire and must not share an
## eye colour with a walker.
const EYE_TINT_HOUND := Color(1.000, 0.478, 0.094)

## Vertex colours are 8-bit and cannot carry a value over 1.0, so the overdrive
## that pushes the pixel past `env.glow_hdr_threshold` — 0.92, set at main.gd:149
## against an RGBA8 LDR colour buffer — has to live here, in the one shared
## albedo, rather than in the per-palette hue.
const EYE_GAIN := 1.15

## Pushed toward the camera so the additive quad is never coplanar with the
## billboard it sits on and loses the depth test to it. Depth resolution at 20 m
## is under a millimetre, so this is two orders of margin, and 2 cm of parallax
## on a 1.3 m sprite is invisible.
const EYE_FORWARD := 0.02

## One number, used twice, and the two uses have to agree or the rim outlines
## something the sprite does not draw: the sprite discards below this, and the
## rim shader calls an edge "the outermost texel the sprite still draws".
const ALPHA_SCISSOR := 0.35

var kind := "zombie"          # zombie | crawler | hound
var pal := 0
var hp := 150.0
var max_hp := 150.0
var speed := 1.2
var melee_damage := 60.0
var melee_cadence := 1.05
var melee_reach := 1.15
var state: int = State.CHASING

var _sprite: AnimatedSprite3D
var _eyes: MeshInstance3D
var _collider: CollisionShape3D
var _attack_timer := 0.0
var _death_timer := 0.0
var _last_headshot := false
var _last_melee := false
var _height := 1.82
var _hit_flash := 0.0
var _groan_timer := 0.0

## The atlas. `_anim` is the cycle without its bearing suffix, because every
## animation change has to be able to re-issue the same cycle on a new row.
var _anim := "walk"
var _view := 0
var _flip := false
## Which way the body is pointing, in world XZ. Steering writes it; the atlas
## reads it. Frozen at death so a corpse does not swing round to face you.
var _facing := Vector2(0.0, 1.0)

## Damage taken below `LEG_FRACTION` of the body's height, and how the walker
## turns into a crawler in place.
var _leg_damage := 0.0

## What killed it, which way the killing blow came from, and the collapse.
## `_death_delay` is the Nuke's outward wave: the payout, the director's live
## list and the eyes all happen at once, and only the fall is staggered.
var last_cause: int = Cause.BULLET
var _death_delay := 0.0
var _collapsed := false
var _shove := Vector3.ZERO
## Each zombie aims at a slightly different point around the player. Ten lines,
## and most of the difference between a horde and a conga line.
var _goal_offset := Vector2.ZERO
var _offset_timer := 0.0

## The barricade this one is working, and which of its standing slots it took.
## Untyped on purpose: `barricade.gd` carries no `class_name`, so a `Node3D`-typed
## local could not see `take_board()` — the same reason `main.gd` leaves `lighting`
## and `hud` untyped. Cleared the moment the vault finishes, so a chasing zombie
## holds no reference to a window.
var _barricade
var _slot := -1
var _board_timer := 0.0
var _swing_t := 0.0
var _vault_t := 0.0
var _vault_from := Vector3.ZERO

var flow: FlowField
var target: Node3D
var neighbours: Array = []


static func create(p_kind: String, p_pal: int, p_round: int, insta: bool) -> Zombie:
	var z := Zombie.new()
	z.kind = p_kind
	z.pal = p_pal
	z._configure(p_round, insta)
	return z


func _configure(p_round: int, _insta: bool) -> void:
	_height = SpriteLib.HEIGHT[kind]
	var base_hp := Game.zombie_hp(p_round)
	# Discrete movement class rather than one continuous curve. Escalation past
	# round 16 now comes from the class mixture shifting, not from a speed value
	# that saturated and never moved again.
	var base_speed := Game.roll_speed_class(p_round)
	match kind:
		"hound":
			hp = base_hp * 0.62
			# Hounds are deliberately left alone: they already outrun the player.
			speed = base_speed * 1.55
			melee_damage = 36.0
			melee_cadence = 0.85
			melee_reach = 1.15
		"crawler":
			hp = base_hp * 0.8
			speed = base_speed * 0.62
			melee_reach = 1.05
		_:
			hp = base_hp
			# A23: `spd * (G.round>=14 && z.type==='z' ? 1.06 : 1)`
			# (kriegsnacht.html:2334). One 6% step at round 14, and only for
			# regular zombies — the ancestor's `type==='z'` excludes hounds and
			# crawlers, both of which already have their own multiplier above.
			# Deliberately not folded into roll_speed_class(), which feeds all
			# three kinds and is asserted against SPEED_SPRINT by value.
			speed = base_speed * Game.late_speed_scale(p_round)
	# A little off the class's nominal pace, but not so much that the three
	# classes stop reading as three distinct threats.
	speed *= Rng.randf_range(Rng.AI, 0.92, 1.08)
	max_hp = hp
	# Phase the attack clock per zombie. A single shared cooldown meant a pile of
	# six dealt exactly one zombie's damage.
	_attack_timer = Rng.randf_range(Rng.AI, 0.0, 0.6)


func _ready() -> void:
	collision_layer = 4
	# Walls and the player. Zombies still pass through each other — the boid
	# separation handles spacing far more cheaply than 24 mutually-colliding
	# capsules would, and that cost is unmeasured on this physics backend.
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(70)

	_collider = CollisionShape3D.new()
	_collider.shape = CapsuleShape3D.new()
	add_child(_collider)
	_shape_body()

	_sprite = AnimatedSprite3D.new()
	_sprite.sprite_frames = SpriteLib.frames_for(kind, pal)
	_sprite.pixel_size = SpriteLib.pixel_size(kind)
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.shaded = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = ALPHA_SCISSOR
	# Sprite origin is its centre, so lift it half a body to stand on the floor.
	_sprite.position.y = _height * 0.5
	_play("walk")
	add_child(_sprite)

	# The one thing that says "Call of Duty Zombies" from across a dark room.
	# It cannot be a second Sprite3D — `SpriteBase3D` exposes no blend mode, so
	# there is no way to make one additive. This is the same construction the
	# muzzle flash uses at main.gd:181-196, which is the working reference in
	# this project for an additive billboard on this renderer.
	_eyes = MeshInstance3D.new()
	_eyes.mesh = _eye_mesh(kind, pal, _view, _flip)
	_eyes.material_override = eye_material()
	_eyes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_eyes.position.y = _eye_height()
	# Billboarding is a vertex-shader rotation, so the mesh AABB never turns with
	# the geometry. Without a margin the hound's pair — which sits over half a
	# body-length off its own origin, because its head is drawn in profile — gets
	# culled early and blinks out at the edge of the screen.
	#
	# Twice the span, not once. The margin grows the AABB the mesh already has,
	# and the crawler's and the hound's sit wholly on one side of the origin
	# (x from -0.58 to -0.32 on a hound), so one span leaves the opposite side of
	# the swept circle short by however far the box is off-centre. Two covers any
	# offset, because that distance can never exceed the span itself.
	_eyes.extra_cull_margin = _eye_span() * 2.0
	add_child(_eyes)

	# `speed_scale` is not written here: `_apply_anim` owns it, because it is a
	# function of the cycle as well as of the speed. The `Rng.randf_range(VISUAL,
	# 0.85, 1.2)` roll that used to be on this line is gone rather than moved —
	# a deliberate one-off change to the VISUAL sequence, which weapon spread also
	# rides.

	# EVERY WAVE USED TO MARCH IN LOCKSTEP. Nothing set the starting frame, so
	# every body spawned in a round was on frame 0 together and a horde crossing a
	# room did it in step. The ancestor never had the bug — `anim: rnd(4)` at
	# html:2213 gives each one a random phase at spawn — so this is a port
	# regression, not a missing feature. Cosmetic, and it stays on VISUAL.
	var walk_frames := _sprite.sprite_frames.get_frame_count(SpriteLib.anim_name("walk", _view))
	if walk_frames > 1:
		_sprite.frame = Rng.randi_range(Rng.VISUAL, 0, walk_frames - 1)
		_sprite.frame_progress = Rng.randf(Rng.VISUAL)

	_groan_timer = Rng.randf_range(Rng.VISUAL, 1.0, GROAN_MAX)
	_reroll_offset()


## Metres per second converted to a multiplier on the walk strip's authored rate.
## `spd * 2.6` is the ancestor's frames-per-second (html:2340) and `WALK_FPS` is
## what `sprite_lib.gd` authored the cycle at, so the quotient is exactly what
## `speed_scale` has to be for a body to cover one stride per stride.
##
## Static and public because the assertion suite has to be able to ask "is this
## monotonic in speed" without standing a zombie up in a scene tree.
static func anim_scale_for(spd: float) -> float:
	return maxf(0.05, spd * ANIM_FRAMES_PER_METRE / WALK_FPS)


func anim_scale() -> float:
	return anim_scale_for(speed)


## The capsule, sized from `HIT_RADIUS`. Split out of `_ready` because the leg-shot
## conversion has to redo it: a crawler is a third the height of the walker it was
## a moment ago and a capsule left at 1.82 m would keep its head in the ceiling.
func _shape_body() -> void:
	var caps: CapsuleShape3D = _collider.shape
	var r := HIT_RADIUS
	caps.radius = r
	caps.height = maxf(_height, r * 2.0 + 0.05)
	_collider.position.y = caps.height * 0.5


## Every animation change goes through here, because the rim overlay and the
## animation cannot move independently: the rim reads the silhouette out of the
## strip the current animation is cut from, and walk, attack and death are three
## separate PNGs. A bare `_sprite.play()` anywhere would leave a zombie outlined
## by the pose it was in a moment ago.
func _play(anim: String) -> void:
	_anim = anim
	_apply_anim(false)


## Issues `_anim` on the current bearing. `keep_phase` re-seats the cycle where it
## already was instead of restarting it, which is what a bearing change needs: a
## zombie that turns while walking must not snap back to frame 0, and the atlas
## row is a different SpriteFrames animation, so `play()` alone would do exactly
## that four times a second on anything circling the player.
func _apply_anim(keep_phase: bool) -> void:
	var full := SpriteLib.anim_name(_anim, _view)
	var was_frame := _sprite.frame
	var was_progress := _sprite.frame_progress
	_sprite.play(full)
	if keep_phase:
		var n := _sprite.sprite_frames.get_frame_count(full)
		if n > 0:
			_sprite.set_frame_and_progress(mini(was_frame, n - 1), was_progress)
	_sprite.flip_h = _flip
	_sprite.material_overlay = rim_material(kind, pal, full)
	# THE ONE WRITER OF `speed_scale`, and the reason it is here rather than in
	# `_ready` is the death strip.
	#
	# Animation rate is a function of speed: what was here was
	# `speed_scale = Rng.randf_range(Rng.VISUAL, 0.85, 1.2)`, set once at _ready
	# and never touched again — so a sprint-class body at 3.45 m/s could play a
	# slower cycle than a walker at 1.05, and the three speed classes stopped
	# reading as three threats. `speed` is already a gameplay quantity drawn from
	# AI, so this is DERIVED from it rather than re-rolled; the per-body variation
	# is the +/-8% `_configure` already applied, carried through, and the VISUAL
	# draw that used to be here is gone rather than moved.
	#
	# But a corpse is not moving, and the ancestor agrees: `z.anim` indexes the
	# WALK strip (html:2073) and doubles into the attack pair (html:2072), while
	# the death frame is `(dieT * (len/0.55))|0` (html:2070) — a fixed 0.55 s clock
	# that `spd` never touches. Scaling it here would be worse than unfaithful: the
	# corpse budget in `_begin_collapse` is `frames / 9.0`, the strip's authored
	# rate, so at a walk-class 0.34 scale the fall took 1.30 s of a 1.34 s life and
	# a crawler's took 1.59 s of a 1.23 s one — it was deleted mid-topple.
	_sprite.speed_scale = 1.0 if _anim == "death" else anim_scale()


## Records which way the body is pointing. One writer, called from each of the
## four things that can turn a zombie, because "whatever velocity happened to be"
## is wrong at a window and wrong mid-swing — both are states in which the body
## does not move and must still face what it is doing.
func _face(dir: Vector2) -> void:
	if dir.length_squared() > 1e-6:
		_facing = dir.normalized()


## Picks the atlas row from where the body is pointing and where the camera is,
## and re-issues the animation when it changes. Cheap enough to run every tick on
## 24 bodies — one dot product and an acos — and it has to, because the row
## depends on the camera as much as on the zombie.
func _update_view() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var cp := cam.global_position
	var to_cam := Vector2(cp.x - global_position.x, cp.z - global_position.z)
	var pick := SpriteLib.view_for(_facing, to_cam)
	var flip := pick.y == 1
	if pick.x == _view and flip == _flip:
		return
	_view = pick.x
	_flip = flip
	_apply_anim(true)
	_refresh_eyes()


func _reroll_offset() -> void:
	var a := Rng.randf(Rng.AI) * TAU
	_goal_offset = Vector2.from_angle(a) * Rng.randf_range(Rng.AI, 0.0, 1.2)
	_offset_timer = Rng.randf_range(Rng.AI, 3.0, 5.0)


## Puts this one outside the barricade it was assigned, with the boards still on.
##
## The round director used to decrement the board count on the frame a zombie
## spawned and drop the body on the *room* side of the wall — so "working the
## boards" was a number that ticked, the barricade never had anything standing at
## it, and a spawn could land inside the player's melee reach. All of that is
## replaced here: the zombie arrives in the exterior pocket, and the only ways in
## are through six planks it has to pull off itself or through a window somebody
## already stripped.
func set_entering(window_id: int) -> void:
	# `_window_id` used to be recorded here and read by nothing at all. The
	# barricade node is the identity now, and it is cleared the moment the vault
	# lands — a chasing zombie has no window.
	_barricade = BARRICADE.of(window_id)
	if _barricade == null:
		# No barricade node for this window, which is what any harness that runs the
		# game logic without building a world sees. Land on the room tile and chase,
		# which is what this function did before the barricade existed — stranding
		# the body in an unreachable pocket instead would be a silent stall.
		var w: Dictionary = MapData.WINDOWS[window_id]
		global_position = Vector3(float(w.ix) + 0.5, 0.0, float(w.iy) + 0.5)
		state = State.CHASING
		return

	_slot = _barricade.claim()
	var stand: Vector3 = _barricade.stand_point(_slot)
	global_position = stand
	# Facing the window from the moment it arrives, so the first frame drawn is
	# not a body standing outside with its back to the boards it is about to pull.
	var cue: Vector3 = _barricade.cue_point()
	_face(Vector2(cue.x - stand.x, cue.z - stand.z))
	var left: int = _barricade.boards
	if left <= 0:
		# A window somebody already stripped is a door. The ancestor made the same
		# check at the top of its window state (html:2271), so a zombie sent to a
		# boardless barricade went straight through on its first tick.
		_begin_vault()
		return
	state = State.TEARING_BOARDS
	_board_timer = Rng.randf_range(Rng.AI, BOARD_FIRST_MIN, BOARD_FIRST_MAX)


## One plank at a time, and nothing else: no steering, no attack test, no
## `move_and_slide`. **This is the asymmetry the whole barricade exists for — a
## zombie here is fully shootable and completely harmless**, and rounds one to five
## are the seconds that buys you.
func _tick_boards(dt: float) -> void:
	if _swing_t > 0.0:
		_swing_t -= dt
		if _swing_t <= 0.0 and _anim != "walk":
			_play("walk")

	if _barricade == null or not is_instance_valid(_barricade):
		# The level was torn down under a live zombie (a scene reload does exactly
		# this). Fall back to chasing rather than standing outside forever.
		#
		# Released on the way out even though the release can no longer reach the
		# map — `_release_window` needs a live barricade to decrement
		# `window_workers`, and there is none — so that "every exit from
		# TEARING_BOARDS gives the slot back" holds without an exception a reader
		# has to find. What it does do here is clear `_slot`, which is what stops a
		# later `_die()` from asking a dead node for anything.
		_release_window()
		state = State.CHASING
		return

	var left: int = _barricade.boards
	if left <= 0:
		_begin_vault()
		return

	_board_timer -= dt
	if _board_timer > 0.0:
		return
	if kind == "hound":
		# Flat, and no draw at all — the ancestor's ternary short-circuits the same
		# way, so a dog round consumes a different number of AI draws than a walker
		# round does and always has.
		_board_timer = BOARD_HOUND
	else:
		# Gameplay, not cosmetic: how fast a barricade comes apart decides when the
		# round arrives on you, so this draw belongs to the AI stream.
		_board_timer = Rng.randf_range(Rng.AI, BOARD_MIN, BOARD_MAX)
	_barricade.take_board()
	var at: Vector3 = _barricade.cue_point()
	# A body at a window faces the window, not its own zero velocity — which is
	# what it would face if the atlas read the steering, and a zombie tearing
	# planks with its back to the boards is the one pose that cannot happen.
	_face(Vector2(at.x - global_position.x, at.z - global_position.z))
	Sfx.play_at("board", at, BOARD_VOLUME)
	_swing_t = BOARD_SWING
	if _anim != "attack":
		_play("attack")


## Hands the standing slot back and starts the climb.
func _begin_vault() -> void:
	_release_window()
	state = State.ENTERING
	_vault_t = 0.0
	_vault_from = global_position
	_swing_t = 0.0
	if _anim != "walk":
		_play("walk")


## The climb. Position is written straight rather than driven through
## `move_and_slide`, which is what lets a body cross a tile the flow field and the
## player both still see as solid — and it is also why the collision mask is left
## exactly as configured. Zeroing the layer for the traversal, which is the obvious
## way to pass through a wall, would take the zombie out of the hitscan's mask as
## well and hand the player a target it cannot shoot.
func _tick_vault(dt: float) -> void:
	if _barricade == null or not is_instance_valid(_barricade):
		state = State.CHASING
		return
	_vault_t = minf(1.0, _vault_t + dt / VAULT_TIME)
	var on_curve: Vector3 = _barricade.vault_sample(_vault_t)
	var start: Vector3 = _barricade.vault_start()
	# Blended off this body's own starting point rather than snapped to the curve's.
	# One curve serves a window and two zombies work it from two slightly different
	# spots, so the second one would otherwise jump sideways on its first frame.
	var was := global_position
	global_position = on_curve + (_vault_from - start) * (1.0 - _vault_t)
	_face(Vector2(global_position.x - was.x, global_position.z - was.z))
	velocity = Vector3.ZERO
	if _vault_t >= 1.0:
		state = State.CHASING
		_barricade = null


## Idempotent, because both of its callers can fire for the same zombie: it dies at
## the window, or it starts the climb. A slot released twice would let a barricade
## believe it is emptier than it is and stack the next arrivals on one spot.
func _release_window() -> void:
	if _slot >= 0 and _barricade != null and is_instance_valid(_barricade):
		_barricade.release(_slot)
	_slot = -1


func _physics_process(dt: float) -> void:
	if Game.state != Game.STATE_PLAY:
		return

	if state == State.DYING:
		_tick_death(dt)
		return

	_tick_flash(dt)
	_update_view()

	if target == null:
		return

	_tick_groan(dt)

	# Above the steering and below the vocalisation, which is the ancestor's own
	# ordering (html:2260-2282): a zombie at a window still groans, and that is
	# what tells you a barricade you cannot see is being worked.
	if state == State.TEARING_BOARDS:
		_tick_boards(dt)
		return
	if state == State.ENTERING:
		_tick_vault(dt)
		return

	_offset_timer -= dt
	if _offset_timer <= 0.0:
		_reroll_offset()

	var here := Vector2(global_position.x, global_position.z)
	var goal := _goal_point()
	var to_target := goal - here
	var dist := to_target.length()

	# Reach is measured on the player whatever the horde is currently walking
	# toward: a Monkey Bomb pulls zombies off you, it does not make them harmless
	# to anything they brush past on the way.
	var to_player := Vector2(target.global_position.x, target.global_position.z) - here
	if to_player.length() <= melee_reach:
		state = State.ATTACKING
		_face(to_player)
		if _anim != "attack":
			_play("attack")
		_attack_timer -= dt
		if _attack_timer <= 0.0:
			_attack_timer = melee_cadence
			if target.has_method("take_damage"):
				# Identify the attacker so the player can apply a per-attacker
				# grace window instead of one global cooldown for the whole horde.
				target.take_damage(melee_damage, get_instance_id())
			Sfx.play_at("melee", centre(), -8.0)
		velocity = Vector3.ZERO
		move_and_slide()
		return

	if state == State.ATTACKING:
		state = State.CHASING
	if _anim != "walk":
		_play("walk")

	# Direct line of sight beats the flow field near the goal — it stops a horde
	# in an open room from filing along tile centres like a conga line.
	var aim := goal + _goal_offset
	var dir: Vector2
	if dist < LOS_RANGE and _has_los(here, goal):
		dir = (aim - here).normalized()
	else:
		dir = flow.direction_at(here) if flow else Vector2.ZERO
		if dir == Vector2.ZERO:
			dir = to_target.normalized()

	dir += _separation(here) * SEPARATION_FORCE
	dir = dir.normalized()

	velocity.x = dir.x * speed
	velocity.z = dir.y * speed
	velocity.y = 0.0
	move_and_slide()
	# After the slide, so a body pressed into a wall faces where it is actually
	# going rather than where the steering wished it were going.
	_face(Vector2(velocity.x, velocity.z))


## What the horde is walking toward. The player, unless a Monkey Bomb is on the
## floor — `Game.lure_position` is package PROJ's contract and this is the whole
## of the zombie side of it, because the flow field already re-solves on demand
## (`flow.invalidate()`) and nothing else in the AI cares who the goal belongs to.
##
## Read through `in` rather than directly so that this file parses, loads and runs
## on a tree where the property has been renamed out from under it, at the cost of
## one lookup on a path that already does an acos.
##
## THE GUARD IS ONLY SAFE BECAUSE THE CONTRACT IS ASSERTED. It is not free: while
## the throwable published its lure as a static on `throwables.gd` instead, this
## fell through to the player on every tick and the Monkey Bomb moved nothing,
## and neither package's assertions said a word — one tested `flow_goal()`, the
## other reported "PROJ has not landed" and passed. `enemies.gd::_lure` now fails
## if `Game.lure_position` is absent, which is what turns this from a silent
## fallback into a caught one.
func _goal_point() -> Vector2:
	if "lure_position" in Game:
		var lure: Variant = Game.lure_position
		if typeof(lure) == TYPE_VECTOR3:
			# `Vector3.INF` is "no lure", so that the contract is one property
			# rather than a position plus a boolean somebody can forget to clear.
			var lp: Vector3 = lure
			if is_finite(lp.x) and is_finite(lp.z):
				return Vector2(lp.x, lp.z)
	return Vector2(target.global_position.x, target.global_position.z)


## Brief bright tint on damage, plus a standing warm tint while Insta-Kill is up
## so the power-up is visible on the horde rather than only in a HUD toast.
func _tick_flash(dt: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - dt * 11.0)
	var c := Color(1.0, 1.0, 1.0)
	if Game.insta_kill > 0.0:
		c = c.lerp(Color(1.6, 0.55, 0.42), 0.35)
	if _hit_flash > 0.0:
		c = c.lerp(Color(2.4, 2.1, 1.9), _hit_flash)
	_sprite.modulate = c


## Idle vocalisation, positioned in the world. This is the channel that answers
## "what is behind me" — the one question a billboard can never answer, because
## the thing behind you is not on screen.
func _tick_groan(dt: float) -> void:
	_groan_timer -= dt
	if _groan_timer > 0.0:
		return
	_groan_timer = Rng.randf_range(Rng.VISUAL, GROAN_MIN, GROAN_MAX)
	if target.global_position.distance_to(global_position) > GROAN_RANGE:
		return
	if kind == "hound":
		Sfx.play_at("bark", centre(), -10.0,
			Rng.randf_range(Rng.VISUAL, 0.94, 1.08), GROAN_RANGE)
	else:
		Sfx.play_at("groan%d" % pal, centre(), -12.0,
			Rng.randf_range(Rng.VISUAL, 0.92, 1.10), GROAN_RANGE)


## Boid-style push so bodies spread out instead of stacking on one tile.
func _separation(here: Vector2) -> Vector2:
	var push := Vector2.ZERO
	for other in neighbours:
		if other == self or not is_instance_valid(other):
			continue
		var o := Vector2(other.global_position.x, other.global_position.z)
		var d := here - o
		var l := d.length()
		if l > 0.001 and l < SEPARATION_RADIUS:
			push += d / l * (1.0 - l / SEPARATION_RADIUS)
	return push.limit_length(SEPARATION_LIMIT)


## Delegated, not reimplemented. `clear_flat`'s default height is this function's own
## 1.2 m and its mask is the same 1, so the chase-versus-flow-field decision below is
## bit-for-bit what it was — the move is about there being one implementation, not
## about changing what the AI can see.
func _has_los(from: Vector2, to: Vector2) -> bool:
	return LOS.clear_flat(get_world_3d(), from, to)


## Real 3D headshots. The browser build could only test whether screen-centre
## fell inside the top band of the billboard; here the hit point's height is
## compared against the actual head region of the body.
func head_threshold() -> float:
	return _height * (0.70 if kind == "zombie" else 0.58)


## The other end of the body. Everything under this is leg, and enough damage
## into it takes the legs off rather than the zombie — §4.2 item 1.
func leg_threshold() -> float:
	return _height * LEG_FRACTION


## `cause` and `from_dir` are new and both are optional, because every existing
## call site already knew them and threw them away: `_apply_hit` knows whether the
## round came out of a barrel or the Thundergun, `_knife` knows it was a blade,
## and the Nuke sweep is bracketed by `Game.nuke_clearing`. Defaulted so that a
## caller which has not been updated behaves exactly as it did.
##
## `from_dir` points FROM the killer TOWARD the body, which is the direction the
## body is pushed. Zero means "no direction", and the collapse falls straight down.
func take_damage(amount: float, hit_y: float, by_melee := false,
		cause: int = -1, from_dir := Vector3.ZERO) -> bool:
	if state == State.DYING:
		return false
	var headshot := hit_y >= head_threshold()
	if Game.insta_kill > 0.0:
		amount = 1e9
	if headshot:
		amount *= 1.5
	hp -= amount
	_last_headshot = headshot
	_last_melee = by_melee
	last_cause = _resolve_cause(cause, by_melee)
	_hit_flash = 1.0
	# Play the impact before the kill check. The killing shot used to be the one
	# event in the game with no impact sound at all — a headshot kill was silent
	# apart from the death rattle.
	Sfx.play_at("headshot" if headshot else "hit", centre(), -10.0)
	if hp <= 0.0:
		_die(from_dir)
		return true
	# Legs, and only after the kill test: a shot that kills is a kill, not a
	# conversion, or Insta-Kill would leave a floor of crawlers.
	if kind == "zombie" and hit_y > 0.0 and hit_y < leg_threshold():
		_leg_damage += amount
		if _leg_damage >= max_hp * LEG_BREAK:
			_become_crawler()
	return false


## The Nuke does not pass a cause and cannot easily be made to: the sweep is a
## bare `take_damage(1e9, 0.0)` inside powerup_manager.gd, and `Game.nuke_clearing`
## is ALREADY the authoritative "this death belongs to the sweep" flag — the
## economy reads it to suppress the per-body payout (game_state.gd:275). A second
## channel carrying the same fact is the duplication this codebase keeps paying
## for, so the flag is read here instead of threaded a second time.
func _resolve_cause(cause: int, by_melee: bool) -> int:
	if Game.nuke_clearing:
		return Cause.NUKE
	if cause >= 0:
		return cause
	return Cause.MELEE if by_melee else Cause.BULLET


## A walker whose legs have gone, in place, with whatever health it had left. Not
## a new body: re-parenting would drop it out of the director's live list and pay
## the kill twice, and BO1's crawler is the same zombie with a different animation
## set. Everything that is a function of `kind` or `_height` is rebuilt here, and
## the list is exactly the set of things `_ready` derives from them.
func _become_crawler() -> void:
	kind = "crawler"
	_height = SpriteLib.HEIGHT[kind]
	speed *= CRAWLER_SPEED
	melee_reach = 1.05
	_leg_damage = 0.0

	_shape_body()
	_sprite.sprite_frames = SpriteLib.frames_for(kind, pal)
	_sprite.pixel_size = SpriteLib.pixel_size(kind)
	_sprite.position.y = _height * 0.5
	# Through _play rather than _apply_anim: the rim overlay is cut from the strip
	# the animation lives in and the crawler's is a different PNG, so an overlay
	# left pointing at the walker's would outline a body that is not there. It also
	# re-derives `speed_scale`, which has just changed with CRAWLER_SPEED.
	_play("walk" if _anim != "attack" else "attack")

	_eyes.position.y = _eye_height()
	_refresh_eyes()
	# Rebuilt with everything else that is a function of the kind. The margin is a
	# function of `_eye_span()`, which is a function of `EYE_VIEW[kind]` and of the
	# kind's pixel size — a crawler's pair sits 13 px off its own origin against a
	# walker's 5, so a walker's 0.43 m margin on a crawler is 0.21 m short and its
	# eyes blink out at the edge of the frame. That is the exact failure the margin
	# exists to prevent, reintroduced by the conversion.
	_eyes.extra_cull_margin = _eye_span() * 2.0

	# There is no "legs off" clip in the bank and synthesising one belongs to the
	# audio package, so this is the death rattle pitched down and quiet — a body
	# coming apart without dying. Silence would make the most dramatic thing a
	# player can do to a zombie the only thing in the game that makes no sound.
	Sfx.play_at("death", centre(), -16.0, 0.72)


## Everything that happens the instant a body dies: the slot goes back, it stops
## colliding, it stops being shootable, the payout fires and the eyes go out.
##
## What does NOT happen here is the fall. `_death_delay` holds it for a Nuke —
## and only the fall, deliberately: `died` is emitted synchronously so the
## director erases the body and pays it inside `Game.nuke_clearing`, which is what
## suppresses the per-body payout (economy.gd). Deferring the emission instead
## would let the flag clear underneath 24 pending deaths and pay a round-10 Nuke
## 1,840 points, which is the exact bug that flag exists to prevent.
func _die(from_dir := Vector3.ZERO) -> void:
	# Before the state changes, because the release is keyed on holding a slot and
	# a corpse holding one would keep a standing place at a window occupied for the
	# rest of the run.
	_release_window()
	state = State.DYING
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	# The light goes out on the frame of death even when the body has not fallen
	# yet — a staggered corpse standing with its eyes lit is a zombie, not a
	# corpse, and --verify asserts the two lights are out the moment it dies.
	_eyes.visible = false
	_collapsed = false
	_death_delay = 0.0
	if last_cause == Cause.NUKE and target != null:
		_death_delay = minf(NUKE_STAGGER_MAX,
			global_position.distance_to(target.global_position) * NUKE_STAGGER)
	# A headshot drops a body where it stands. No stagger, no shove worth the
	# name: the difference between a headshot and a body shot is that one of them
	# does not stumble.
	if _last_headshot:
		_death_delay = 0.0

	var push := Vector3(from_dir.x, 0.0, from_dir.z)
	var strength := SHOVE_BULLET
	match last_cause:
		Cause.MELEE: strength = SHOVE_MELEE
		Cause.BLAST: strength = SHOVE_BLAST
		Cause.NUKE: strength = SHOVE_BLAST
	if push.length_squared() < 1e-6 and target != null:
		# NO DIRECTION GIVEN, AND ONE IS STILL KNOWN: away from the player. Every
		# damage source the player can aim originates at their own camera — the
		# hitscan, the knife, both throwables, the Ray Gun — so the line from the
		# player to the body is the line the blow came along, to within the width
		# of the room. A Nuke has the same direction by construction and that is
		# what makes its collapse read as a shockwave rather than as the horde
		# tripping over.
		#
		# It is a FALLBACK and not the answer: `_apply_hit` and `_knife` know the
		# real aim vector and should pass it (see the hunks in this package's
		# report). Until they do, this is the difference between a shove that
		# exists and one that is dead code — which is what it was, because not one
		# call site in the game passes `from_dir` and every non-Nuke corpse
		# therefore fell straight down with `_shove` at zero. An electric trap is
		# the one source this gets wrong, and a trap kill is not a kill the player
		# is watching the body of.
		push = global_position - target.global_position
		push.y = 0.0
	_shove = push.normalized() * strength if push.length_squared() > 1e-6 else Vector3.ZERO

	Sfx.play_at("death", centre(), -12.0)
	died.emit(self, _last_headshot, _last_melee)
	if _death_delay <= 0.0:
		_begin_collapse()


## The fall itself. Split from `_die` so the Nuke can hold it.
func _begin_collapse() -> void:
	_collapsed = true
	# The rim follows the animation and deliberately survives the death: a corpse
	# still needs a silhouette while it falls, and the death strip is a different
	# PNG from the walk strip — outlining one with the other's alpha would trace a
	# figure that is no longer there.
	_play("death")
	_sprite.modulate = Color(1.0, 1.0, 1.0)
	# WHICH WAY IT TOPPLES. The death strip rotates the body one way only
	# (`g.rotate(t*1.32)`, html:995), so mirroring the row is the only lever
	# there is — and it is the right one: a body should fall away from what hit
	# it. `_shove` is the killing direction, so the sign of its component along
	# screen right decides, and it is frozen here rather than recomputed, because
	# a corpse that flips over when the player strafes is worse than one that
	# leans the wrong way.
	#
	# ONLY ON THE TWO ROWS WHERE THE MIRROR IS FREE. Since the atlas, `flip_h`
	# means something else as well: `view_for()` mirrors rows 1-3 to cover the
	# other three bearings, so overriding the flip there does not lean a corpse,
	# it turns it — a zombie dying in profile facing screen right would snap to
	# facing screen left on the frame it was shot, which is a far louder wrong
	# than a body leaning the wrong way. Rows 0 and 4 are never mirrored by
	# `view_for` (`row > 0 and row < VIEW_COUNT - 1`), so on those two the flag is
	# genuinely spare — and row 0 is the bearing a zombie killed while chasing the
	# player is nearly always on.
	var mirror_is_free := _view == 0 or _view == SpriteLib.VIEW_COUNT - 1
	if mirror_is_free and _shove.length_squared() > 1e-6:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam != null:
			var right := cam.global_transform.basis.x
			_flip = _shove.dot(right) < 0.0
			_sprite.flip_h = _flip
	var frames: int = SpriteLib.SPEC[kind].death
	_death_timer = float(frames) / 9.0 + CORPSE_HOLD + CORPSE_FADE


## The whole of a corpse's life: the hold before it falls, the fall, the slide,
## the time it lies there and the fade out. One function so that "how long is a
## body on screen" is answerable by reading one place.
func _tick_death(dt: float) -> void:
	if not _collapsed:
		_death_delay -= dt
		if _death_delay <= 0.0:
			_begin_collapse()
		return

	_death_timer -= dt
	if _death_timer <= 0.0:
		queue_free()
		return

	# The fake ragdoll. Position is written straight rather than pushed through
	# move_and_slide, for the same reason the vault is: the body has no collision
	# layers left, so a slide would resolve against nothing and cost a physics
	# query per corpse per frame for it.
	if _shove.length_squared() > 1e-6:
		global_position += _shove * dt
		_shove = _shove.move_toward(Vector3.ZERO, SHOVE_DECAY * dt)

	if _death_timer < CORPSE_FADE:
		# DARKENED, NOT MADE TRANSPARENT, and the constraint is the sprite's own
		# `ALPHA_CUT_DISCARD`: that mode renders the surface opaque with a discard,
		# so `modulate.a` does not blend — it only moves the discard threshold, and
		# a body whose texels are nearly all alpha 1.0 would sit there unchanged
		# and then vanish between two frames. Switching to a blended alpha_cut
		# mid-life is worse: it is a different render mode, which on the web target
		# is a main-thread GLSL compile in the middle of a fight. So the corpse
		# sinks into the dark instead, which on this map is what a body does.
		var a := _death_timer / CORPSE_FADE
		_sprite.modulate = Color(a, a, a)
		# The rim is a second draw of the same quad through an ADDITIVE shader, so
		# `modulate` cannot reach it and a faded body would keep a full-brightness
		# outline — a wireframe ghost. Its energy lives in a material shared by
		# every zombie in the game, so it cannot be dimmed per corpse either; the
		# overlay is dropped instead, once the body is more gone than not.
		if a < 0.55 and _sprite.material_overlay != null:
			_sprite.material_overlay = null


## Where a hitscan should aim to be "centre mass", used by the melee test.
func centre() -> Vector3:
	return global_position + Vector3(0, _height * 0.5, 0)


# --- co-op puppetry ----------------------------------------------------------
#
# THREE FUNCTIONS, AND THE REST OF THIS FILE DOES NOT CHANGE.
#
# The co-op topology (notes/design/2026-07-31-coop-topology-decision.md) puts every
# zombie on the host. A client renders the horde without simulating it, and the
# mechanism for that was already here before any of this was written: with `target`
# null, `_physics_process` above runs `_tick_death`, `_tick_flash` and
# `_update_view` — the death clock, the damage tint and the atlas row, which is the
# whole of how a zombie LOOKS — and then returns at `if target == null` before the
# groan, the barricade, the vault, the steering, the attack test and
# `move_and_slide`.
#
# So a puppet needs exactly two things this file did not expose: somewhere for the
# network to put it, and a way to end it that is the real death rather than a
# fabricated one. Both are written by scripts/net/session_runtime.gd and by nothing
# else, which is the one-writer rule applied across a network.


## Which way the body is pointing, in world XZ.
##
## On the wire because it is NOT derivable from two positions and the design note's
## rule is that only derived state may be dropped: a body tearing planks faces the
## window while standing perfectly still, and one pressed into a wall faces where
## it is going rather than where it is. Everything that IS derived from it — the
## atlas row, the mirror, which eye quads light — stays off the wire and is
## recomputed by `_update_view` on the client.
func facing() -> Vector2:
	return _facing


## Puts a client-side puppet where the host says it is.
##
## Position is written straight rather than through `move_and_slide` for
## `_tick_vault`'s reason: the host has already resolved this body against the
## world, and resolving it a second time against a different player's idea of where
## the walls are is how two clients end up disagreeing about a corner.
##
## `_face` and not `_facing =` directly, so the zero-length guard and the
## normalisation are the same ones every local caller gets.
func set_remote_pose(pos: Vector3, dir: Vector2) -> void:
	if target != null:
		# This body is being simulated locally. Something has both spawned it
		# through the round director and handed it to the replication layer, and the
		# two would fight for the transform every frame — a stutter that looks like
		# a network fault and is not one.
		push_error("set_remote_pose on a simulated zombie: it has a target")
		return
	global_position = pos
	_face(dir)


## Which way the killing blow pushed this body, and how hard.
##
## Read by the replication layer at the instant `died` fires, because it is the one
## thing in the collapse a client cannot derive: it decides which way the corpse
## slides AND whether the death row is mirrored (`_begin_collapse`, :1073-1096).
## Reconstructing it as "away from the player" — which is what `_die`'s own
## fallback does — stopped being right the moment `_apply_hit` began passing a real
## direction (player.gd:1044), so it has to be read rather than guessed.
func shove() -> Vector3:
	return _shove


## The host confirmed this body is dead.
##
## Routed through the real `_die` rather than through `take_damage`, deliberately.
## `take_damage` would play the impact cue for a bullet this machine never fired,
## re-apply the headshot multiplier the host has already applied, and consult
## `Game.insta_kill`, which is a per-client power-up state that has no business
## deciding whether somebody else's kill counts. `_die` is the part that is
## genuinely shared: the slot release, the collision going away, the eyes going
## out, the death rattle, the strip and the corpse clock that frees the body.
##
## The three flags are set BEFORE `_die` because it reads all three: `_last_headshot`
## suppresses the stagger, `last_cause` picks the shove strength, and `_last_melee`
## rides `died` out. They are the host's values off the wire, so a corpse falls the
## same way on every screen instead of falling the way each client would have
## guessed.
##
## `died` is emitted from in there with nothing connected — a puppet is never handed
## to `round_director._on_zombie_died`, because the payout and the DROPS draw belong
## to the machine that owns the horde.
func remote_die(headshot: bool, by_melee: bool, cause: int, from_dir: Vector3) -> void:
	if state == State.DYING:
		return
	hp = 0.0
	_last_headshot = headshot
	_last_melee = by_melee
	last_cause = clampi(cause, 0, Cause.NUKE)
	_die(from_dir)


# --- glowing eyes ------------------------------------------------------------

## Shared by every zombie alive. A `StandardMaterial3D` per zombie would be 24
## uniform sets and, on a platform with no shader program cache, 24 chances to
## compile the same program again in the middle of a fight.
static var _eye_mat: StandardMaterial3D

## Seven small meshes at most — three walker palettes, three crawler, one hound —
## also shared. The per-palette colour rides in the vertex stream because that is
## the only per-instance channel this renderer leaves open: `INSTANCE_CUSTOM`
## does nothing on a plain `MeshInstance3D` under Compatibility, and an
## `instance uniform` would mean a new shader, which is the one thing the web
## target charges most for.
static var _eye_meshes := {}


## The warm-up pass needs this by name. `main.gd::_ready` hands `shader_warmup.gd`
## an `extra` array of materials the world builder does not own, and any material
## missing from that list buys a mid-frame GLSL compile the first time it is
## drawn — here, the first time a zombie walks into view. Referenced by function
## rather than line number because the call site moves and a stale line sends the
## next reader to the wrong statement.
static func eye_material() -> StandardMaterial3D:
	if _eye_mat != null:
		return _eye_mat

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(EYE_GAIN, EYE_GAIN, EYE_GAIN)
	m.albedo_texture = _eye_texture()
	# Explicit, so the sampler never asks for a mip level this texture does not
	# carry, and so the variant is pinned rather than inherited from a default.
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.disable_receive_shadows = true
	# Depth fog is a lerp toward the fog colour in the fragment shader and it runs
	# on unshaded transparents like any other surface — which on an additive quad
	# is wrong twice over. It adds a disc of fog grey on top of a wall the same
	# fog already greyed, and it drags the eye colour down with distance: at 10 m,
	# with fog_density 0.030 (main.gd:151), the core falls to ~0.89 and stops
	# clearing the 0.92 bleed threshold — so the glow dies at exactly the range
	# this whole effect exists for. Light is not dimmed by the air in front of it.
	# This is the flag the engine documents for the case.
	m.disable_fog = true
	# The quad is planar and always turned to face the camera, so only one of its
	# two triangles can ever be front-facing whichever way it is wound. Disabling
	# the cull rasterises nothing extra and takes winding off the list of things
	# that can silently blank the effect on a build nobody can step through.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_eye_mat = m

	# Build the meshes here too. This is called from the warm-up pass, which runs
	# behind the title screen, so the first zombie of the run draws a vertex
	# buffer that is already resident instead of uploading one mid-round.
	for k in EYE_PX.keys():
		var eye_kind: String = k
		for p in EYE_TINT.size():
			for v in SpriteLib.VIEW_COUNT:
				_eye_mesh(eye_kind, p, v, false)
				_eye_mesh(eye_kind, p, v, true)
	return _eye_mat


## A baked gradient, not a shader. WebGL2 exposes no program-binary API, so every
## new `Shader` is a main-thread GLSL compile the first time it is drawn; a
## texture generated once at startup costs one upload and nothing after.
##
## The ramp is the ancestor's two nested rects — a solid core inside a halo at
## alpha 0.28 (html:940) — smoothed out, because a hard-edged square reads as a
## square once it is additive and blooming instead of four pixels of a 48x64
## sprite. The core lands at 40% of the radius, which on the 4.6 px walker
## footprint is the 2 px core the ancestor actually drew.
##
## White, with the whole falloff in alpha: nothing here then depends on whether
## an RGBA8 texture is decoded as sRGB, because the hue comes from the mesh.
static func _eye_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.40, 0.52, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.85),
		Color(1.0, 1.0, 1.0, 0.28),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


## Where the eyes sit for one bearing, and how many of them there are.
##
## `EYE_PX` is the row for the bearing the ancestor drew; `EYE_VIEW` is every row.
## The fallback matters and is not a formality: with no atlas on disk,
## `sprite_lib.gd` puts the ancestor's single frame on all five rows — so the
## crawler's and the hound's PROFILE art is what is on screen at every bearing,
## un-mirrored, and the eyes have to be back at `EYE_PX`'s negative x with both
## of them lit. Reading EYE_VIEW there would park two glowing dots in mid-air.
static func eye_geo(p_kind: String, p_view: int) -> Dictionary:
	var base: Dictionary = EYE_PX[p_kind]
	if not SpriteLib.has_atlas(p_kind, 0, "walk"):
		return {"x": float(base.x), "sep": float(base.sep), "n": 2}
	var rows: Array = EYE_VIEW[p_kind]
	var row: Dictionary = rows[clampi(p_view, 0, rows.size() - 1)]
	return {"x": float(row.x), "sep": float(row.sep), "n": int(row.n)}


## One mesh per kind, palette, bearing and mirror, cached forever. Hounds ignore
## `pal` for the same reason `SpriteLib.frames_for` does: `SPEC.hound.pal` is 0,
## so there is only one hound body and there should only be one pair of hound eyes.
##
## A bearing that shows no eyes still gets a mesh — the anchor row's — because
## `SurfaceTool.commit()` on an empty surface returns null, and a MeshInstance3D
## with a null mesh has no AABB for the cull-margin assertion in --verify to read.
## It is simply never made visible; see `_refresh_eyes`.
static func _eye_mesh(p_kind: String, p_pal: int, p_view: int, p_flip: bool) -> ArrayMesh:
	var body: String = p_kind if p_kind == "hound" else "%s%d" % [p_kind, p_pal]
	var key := "%s/%d/%d" % [body, p_view, 1 if p_flip else 0]
	if _eye_meshes.has(key):
		var cached: ArrayMesh = _eye_meshes[key]
		return cached

	var base: Dictionary = EYE_PX[p_kind]
	var geo := eye_geo(p_kind, p_view)
	var n: int = geo.n
	if n <= 0:
		geo = eye_geo(p_kind, int(SpriteLib.ANCHOR_VIEW[p_kind]))
		n = maxi(1, int(geo.n))
	var row_glow: float = base.glow
	var px := SpriteLib.pixel_size(p_kind)
	var half: float = float(geo.sep) * 0.5 * px
	# Mirroring a row mirrors where its eyes are. `sep` is symmetric about the
	# pair's own centre, so only the offset changes sign.
	var off: float = float(geo.x) * px * (-1.0 if p_flip else 1.0)
	var s := row_glow * 0.5 * px

	var tint: Color = EYE_TINT_HOUND if p_kind == "hound" else EYE_TINT[p_pal]
	# The material does not flag its vertex colours as sRGB, so convert here
	# instead of handing the renderer an sRGB hue it will read as linear.
	var col := tint.srgb_to_linear()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if n == 1:
		# One eye, not two coincident ones: `sep` is zero in profile and drawing
		# the pair anyway would stack two additive quads on the same texels and
		# double the brightness of exactly the bearing that shows the least of a
		# zombie's face.
		_eye_quad(st, col, off, s)
	else:
		_eye_quad(st, col, off - half, s)
		_eye_quad(st, col, off + half, s)
	var mesh := st.commit()
	_eye_meshes[key] = mesh
	return mesh


## Puts the right pair on the body for the bearing it is currently showing, and
## takes them off entirely on the two rear rows. That last part is the point of
## the whole table: until the atlas there was no bearing at which a zombie's eyes
## were not pointed at you, and a horde walking away lighting up the wall in front
## of it is the tell that a billboard is a billboard.
func _refresh_eyes() -> void:
	var geo := eye_geo(kind, _view)
	var n: int = geo.n
	_eyes.mesh = _eye_mesh(kind, pal, _view, _flip)
	_eyes.visible = n > 0 and state != State.DYING


## Two triangles centred on `ox`, in the billboard's local space: +X is camera
## right, +Y camera up, +Z toward the viewer. Both eyes live in one mesh so a
## zombie costs one draw call for the pair rather than two.
static func _eye_quad(st: SurfaceTool, col: Color, ox: float, s: float) -> void:
	var bl := Vector3(ox - s, -s, EYE_FORWARD)
	var br := Vector3(ox + s, -s, EYE_FORWARD)
	var tr := Vector3(ox + s, s, EYE_FORWARD)
	var tl := Vector3(ox - s, s, EYE_FORWARD)
	_eye_vertex(st, col, bl, Vector2(0.0, 1.0))
	_eye_vertex(st, col, br, Vector2(1.0, 1.0))
	_eye_vertex(st, col, tr, Vector2(1.0, 0.0))
	_eye_vertex(st, col, bl, Vector2(0.0, 1.0))
	_eye_vertex(st, col, tr, Vector2(1.0, 0.0))
	_eye_vertex(st, col, tl, Vector2(0.0, 0.0))


static func _eye_vertex(st: SurfaceTool, col: Color, p: Vector3, uv: Vector2) -> void:
	st.set_normal(Vector3(0.0, 0.0, 1.0))
	st.set_color(col)
	st.set_uv(uv)
	st.add_vertex(p)


## Height of the eye row off the floor. `SpriteLib.pixel_size()` is
## `HEIGHT[kind]` over the cell height, so this is the body's own geometry rather
## than a tuned number: 1.40 m on a 1.82 m walker, inside the head region
## `head_threshold()` opens at 1.27 m, and 0.34 m on a crawler — which drags its
## head along the floor, and would have had its eyes hovering somewhere over its
## back if the walker's fraction had simply been reused. The crawler's row sits a
## couple of centimetres under its own `head_threshold()`; that threshold is a
## hit-registration band, not a measurement of where the art put the skull.
func _eye_height() -> float:
	var geo: Dictionary = EYE_PX[kind]
	var row: float = geo.y
	return _height - row * SpriteLib.pixel_size(kind)


## Distance from the node origin to the furthest eye vertex, which is how far the
## billboard can swing the geometry outside the mesh's own AABB.
##
## Maximised over every bearing, because the margin is set once in `_ready` and
## the mesh under it is swapped every time the body turns — the crawler's profile
## row puts its pair 13 px off centre and its head-on row puts them at zero, and a
## margin sized for whichever one happened to be showing at spawn would clip the
## other at the edge of the frame.
func _eye_span() -> float:
	var px := SpriteLib.pixel_size(kind)
	var row_glow: float = float(EYE_PX[kind].glow)
	var worst := 0.0
	for v in SpriteLib.VIEW_COUNT:
		var geo := eye_geo(kind, v)
		worst = maxf(worst, absf(float(geo.x)) + float(geo.sep) * 0.5)
	return (worst + row_glow * 0.5) * px


# --- alpha-edge rim ----------------------------------------------------------

## The colour the ancestor already used for light that is not a lamp: the stars
## it stipples into the night ceiling, `rgba(190,200,220)` (html:781), which is
## also within ten parts of the ones behind every window barricade (html:809).
## Cold, because everything else lighting this map is sodium.
const RIM_TINT := Color(190.0 / 255.0, 200.0 / 255.0, 220.0 / 255.0)

## Deliberately under the environment's `glow_hdr_threshold` (set in
## `main.gd::_setup_environment`, currently 0.92) rather than over it. The eyes
## are meant to bloom — they are two dots. A whole silhouette pushed past the
## bleed threshold smears the zombie into a lamp, and the point of the effect is
## the edge, not a halo.
##
## WAS 0.62, AND THAT WAS TOO BRIGHT — found by looking, because no assertion can
## see it. In a lit frame of eight walkers the rim came out at a mean luminance of
## 146/255 against a body mean of 42: the outline was **3.4x brighter than the
## thing it outlined**, and every zombie wore a hard white line that read as a
## cutout sticker rather than as a body in a dark room. Swept and re-measured on
## the same frame: 0.30 gives 62 vs 39, a ratio of 1.59, an edge that separates
## the figure from an unlit wall without becoming the loudest thing on it; 0.16
## gives 22 vs 33, dimmer than the body, and the silhouette stops reading at all —
## which is the one thing `outlineSprite` exists to prevent.
##
## The 0.62 note used to justify itself with "0.62 x the brightest channel is
## 0.535". That arithmetic is in DISPLAY space and the shader is not: `rim_color`
## is declared `source_color`, so the engine linearises it before the fragment
## runs — measured, by matching the shipped pixels against both paths. The real
## albedo was linear(0.863) * 0.62 = 0.444, and 0.444 of ADDITIVE light on a wall
## sitting near zero is a white line whatever it does at the bleed threshold. The
## threshold was never the binding constraint; the background was.
const RIM_ENERGY := 0.30

## Same 2 cm and the same reason as EYE_FORWARD: the overlay is a second draw of
## the *same* quad, so without an offset it is exactly coplanar with the sprite
## and loses the depth test to it on every fragment.
const RIM_FORWARD := 0.02

## A billboard cannot be rim-lit by fresnel. `NORMAL` is constant across a flat
## quad, so `dot(NORMAL, VIEW)` is constant, so every fresnel shader ever written
## for this produces a uniform tint over the whole sprite rather than an edge.
## The silhouette lives in the texture's alpha channel, so the edge has to be
## found by sampling neighbouring texels — four taps, thresholded at exactly the
## sprite's own alpha scissor so the rim traces the figure and not the quad.
##
## What it lights is already there. `outlineSprite()` (html:955-971) stamps a 1px
## ring of `rgba(6,6,5,205)` on the *transparent* side of every silhouette, and
## 205/255 clears the 0.35 scissor — so that ring is drawn, it is simply black. A
## black rim reads against a light background, which is what a flat-lit raycaster
## had and this map does not. The four-tap inner edge selects that exact ring, so
## this does not add an outline: it turns the one the art already carries from
## dark to cold.
##
## `INV_VIEW_MATRIX` rather than `MAIN_CAM_INV_VIEW_MATRIX`, which is what
## Godot's own generated billboard code uses. The two differ only during shadow
## and reflection passes, and an additively-blended surface enters neither; the
## trade is deliberate, because M-BILLBOARD records that whether the newer
## built-in even compiles under gl_compatibility is unverified, and a shader that
## fails to compile is a magenta zombie in a build nobody here can step through.
##
## The horizontal taps are clamped inside the current frame's own column of the
## strip, and since M4 the vertical ones inside its own ROW. Frames are packed
## edge to edge and the atlas stacks five bearings the same way, so an unclamped
## tap at either boundary samples a different pose's alpha and stamps a rim down
## the middle of nothing — vertically that is worse than horizontally, because the
## row above ends in the shadow ellipse under the boots and the row below starts
## in empty sky, so every corpse would wear a bar across its scalp.
const RIM_CODE := """shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform sampler2D rim_tex : filter_nearest, repeat_disable;
uniform vec3 rim_color : source_color = vec3(0.745, 0.784, 0.863);
uniform float rim_energy = 0.30;
uniform float cut = 0.35;
uniform float cols = 1.0;
uniform float rows = 1.0;
uniform vec2 texel = vec2(1.0);
uniform float push_z = 0.02;

void vertex() {
	// BILLBOARD_FIXED_Y, reproduced: material_overlay is a second draw of the
	// same surface with a different material, and the billboard lives in the
	// material, so the sprite's own orientation is not inherited here.
	mat4 face = mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	mat4 keep_scale = mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * face * keep_scale;
	// Local +Z is toward the viewer under that basis, so this is the same
	// coplanarity fix the eye quads bake into their vertices.
	VERTEX.z += push_z;
}

void fragment() {
	float hx = texel.x * 0.5;
	float hy = texel.y * 0.5;
	float fw = 1.0 / cols;
	float f0 = floor(UV.x * cols) * fw;
	float lo = f0 + hx;
	float hi = f0 + fw - hx;
	float rh = 1.0 / rows;
	float r0 = floor(UV.y * rows) * rh;
	float ylo = r0 + hy;
	float yhi = r0 + rh - hy;
	float xl = clamp(UV.x - texel.x, lo, hi);
	float xr = clamp(UV.x + texel.x, lo, hi);
	float yl = clamp(UV.y - texel.y, ylo, yhi);
	float yr = clamp(UV.y + texel.y, ylo, yhi);
	float a = step(cut, texture(rim_tex, UV).a);
	float l = step(cut, texture(rim_tex, vec2(xl, UV.y)).a);
	float r = step(cut, texture(rim_tex, vec2(xr, UV.y)).a);
	float u = step(cut, texture(rim_tex, vec2(UV.x, yl)).a);
	float d = step(cut, texture(rim_tex, vec2(UV.x, yr)).a);
	// Drawn, and with a transparent 4-neighbour: the outermost texel of the
	// figure, which is exactly the ring outlineSprite() stamped.
	float edge = a * (1.0 - min(min(l, r), min(u, d)));
	if (edge < 0.5) {
		discard;
	}
	ALBEDO = rim_color * rim_energy;
	// blend_add is SRC_ALPHA, ONE, so the contribution is ALBEDO * ALPHA and
	// the edge test above has already decided this fragment is on the rim.
	ALPHA = 1.0;
}
"""

## One `Shader` for every zombie in the game, and therefore one GLSL compile.
## This is the same bargain `eye_material()` makes and it matters more here: a
## ShaderMaterial per zombie would still be one program, but a *Shader* per
## zombie would be 24 compiles of identical source on a platform with no program
## cache, in the middle of a fight.
static var _rim_shader: Shader

## One ShaderMaterial per sprite strip — seventeen at most, and fewer, because
## crawlers and hounds cut their attack out of the walk strip. Keyed by the
## strip's own resource path, which is what makes that sharing fall out rather
## than have to be special-cased.
static var _rim_mats := {}


static func rim_shader() -> Shader:
	if _rim_shader != null:
		return _rim_shader
	var sh := Shader.new()
	sh.code = RIM_CODE
	_rim_shader = sh
	return sh


## The rim material for one animation of one body. Null when the strip is
## missing, which `SpriteLib._add_strip` already treats as a warning rather than
## a failure — a zombie with no art should still walk around, not crash the round.
static func rim_material(p_kind: String, p_pal: int, p_anim: String) -> ShaderMaterial:
	var frames := SpriteLib.frames_for(p_kind, p_pal)
	if frames.get_frame_count(p_anim) == 0:
		return null
	# The frames are AtlasTexture windows onto one strip, and Sprite3D bakes the
	# window into the quad's UVs — so handing the shader the whole strip and
	# reading UV straight off the mesh lands on exactly the texel the sprite
	# sampled, with no per-frame uniform to keep in step.
	var at := frames.get_frame_texture(p_anim, 0) as AtlasTexture
	if at == null or at.atlas == null:
		return null
	var strip := at.atlas
	var key := strip.resource_path
	if _rim_mats.has(key):
		var cached: ShaderMaterial = _rim_mats[key]
		return cached

	var spec: Dictionary = SpriteLib.SPEC[p_kind]
	var cell: float = spec.w
	var cell_h: float = spec.h
	var w := float(strip.get_width())
	var h := float(strip.get_height())

	var m := ShaderMaterial.new()
	m.shader = rim_shader()
	m.set_shader_parameter("rim_tex", strip)
	m.set_shader_parameter("rim_color", RIM_TINT)
	m.set_shader_parameter("rim_energy", RIM_ENERGY)
	m.set_shader_parameter("cut", ALPHA_SCISSOR)
	# Frames per strip, taken from the image rather than from the animation:
	# `SPEC.crawler` has no attack entry, so its attack animation holds two
	# frames of a strip that is four frames wide, and clamping to the animation's
	# count would put the frame boundary in the wrong place on every tap.
	m.set_shader_parameter("cols", w / cell)
	# Bearings per strip, from the image for the same reason — and it is 1 on a
	# machine with no atlas, which is what makes the clamp a no-op there rather
	# than a wrong answer.
	m.set_shader_parameter("rows", maxf(1.0, h / cell_h))
	m.set_shader_parameter("texel", Vector2(1.0 / w, 1.0 / h))
	m.set_shader_parameter("push_z", RIM_FORWARD)
	_rim_mats[key] = m
	return m


## Every rim material, built up front, for the warm-up pass — and, as a side
## effect, every sprite strip loaded and resident before the first spawn instead
## of on it. `frames_for` caches, so this costs one decode of each of the
## seventeen PNGs at load rather than one mid-round.
static func rim_materials() -> Array:
	var out: Array = []
	for k: String in SpriteLib.SPEC.keys():
		var spec: Dictionary = SpriteLib.SPEC[k]
		var pals: int = spec.pal
		# `SPEC.hound.pal` is 0 and `frames_for` ignores `pal` for it, exactly as
		# the eye meshes do, so one hound is one hound.
		for p in maxi(1, pals):
			for anim: String in ["walk", "attack", "death"]:
				# Every bearing, even though they collapse onto one material per
				# strip: the collapse is what is being relied on, and asking for all
				# five is how a future layout that does NOT share a strip would show
				# up here as more materials rather than as a mid-fight compile.
				for v in SpriteLib.VIEW_COUNT:
					var m := rim_material(k, p, SpriteLib.anim_name(anim, v))
					if m != null and not out.has(m):
						out.append(m)
	return out
