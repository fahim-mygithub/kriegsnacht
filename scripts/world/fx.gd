extends Node3D

## Every combat effect except the muzzle flash: blood puffs, surface debris,
## bullet holes, blood pools and tracers. `bind(player, map)` wires it to the
## three signals it listens on; nothing else drives it.
##
## Four constraints shape all of it, and not one of them is a preference.
##
## **`GPUParticles3D.emit_particle()` does nothing on this renderer.** It is one
## of the calls that warns once in the editor and is silently absent in the
## browser, so a burst cannot be a call into a shared emitter — it has to be a
## whole emitter, repositioned and restarted. Every particle effect below is
## therefore a fixed pool with a rotating cursor, and every pool size is a
## constant rather than a function of how many zombies are alive.
##
## **There is no shader program cache on the web.** WebGL 2.0 exposes no
## program-binary API, so every visitor recompiles every variant from GLSL on the
## main thread the first time it is drawn. `warm()` is not optional, and it has
## to reach two things `shader_warmup.gd` structurally cannot: the particle
## *process* shaders, which only compile when an emitter actually runs, and the
## *instanced* draw variant, which is a different program from the same material
## on a plain `MeshInstance3D`. Warming a material is not warming a MultiMesh of
## it.
##
## **Allocation inside the fire loop is the thing being avoided.** At 880 RPM a
## node per hit is fifteen allocations a second, and a Thundergun cone can land
## eight hits in one frame. Nothing here calls `new()` after `bind()`.
##
## **Nothing here may draw from an `Rng` stream — not even `Rng.VISUAL`.**
## `player._hitscan` samples weapon spread from `VISUAL`, so a cosmetic draw
## taken here would move where a seeded run's shots land. Variation comes from a
## hash of the impact point and from a shot counter instead, both functions of
## what already happened rather than new entropy. `verify.gd` asserts this from
## the other end, and it is the reason there is not a single `randf` below.


# --- surface lookup ----------------------------------------------------------

## Debris families. Three, because the ancestor declared exactly three presets
## for solid matter — SPLINT, SPARK and the anonymous wall puff — and because the
## three differ in *physics*, not only in colour: dust hangs, wood flies, steel
## falls. One `ParticleProcessMaterial` each and no more, because each one is a
## process shader this platform recompiles on every page load.
const FAM_DUST := 0
const FAM_SPLINTER := 1
const FAM_SPARK := 2
const FAM_COUNT := 3

## The ancestor drew exactly one wall-impact puff, in one colour, for every
## surface in the game: `rgb(150,146,132)` (html:2502). That colour is its own
## concrete fill `#54544c` (html:606) scaled by 1.75 — 150/84 = 1.79,
## 146/84 = 1.74, 132/76 = 1.74. The dust *is* the wall it came out of, lifted
## until it reads against it.
##
## The same factor turns the theatre's plank fill `rgb(84,60,34)` (html:627) into
## the SPLINT preset `rgb(150,110,56)` (html:2131) to within four parts in 255.
## Two independent derivations of one constant is a rule the ancestor was
## following, not a coincidence in a single number — so every tint below is that
## rule applied to that texture's own base fill, and the only invented decision
## is to vary the colour at all. The ancestor could not: its raycaster reported a
## wall *distance*, never a wall *tile*, at the point the round stopped.
##
## The 1.75 is folded into the literals below rather than kept as a constant,
## because nothing multiplies by it at runtime and a constant nothing reads is a
## constant nobody maintains. Every row carries the source fill it came from.
##
## Wall textures, indexed by `MapData.TX_*`. Index 7 is `TX_WINDOW`, which
## `MapData.WALL_TEX` does not carry — that array is seven names long and the
## window tiles store an eighth id — so a lookup routed through `WALL_TEX` would
## read off the end of it on every shot into a barricade.
const WALL_FAM := [
	FAM_DUST,       # 0 concrete
	FAM_SPLINTER,   # 1 wood
	FAM_DUST,       # 2 brick
	FAM_SPARK,      # 3 metal
	FAM_DUST,       # 4 tile
	FAM_SPLINTER,   # 5 door
	FAM_DUST,       # 6 debris
	FAM_SPLINTER,   # 7 window barricade
]
const WALL_TINT := [
	Color(0.576, 0.576, 0.522),   # #54544c (html:606) x1.75 — the ancestor's own puff
	Color(0.576, 0.412, 0.233),   # plank rgb(84,60,34) (html:627) x1.75 == SPLINT
	Color(0.659, 0.357, 0.288),   # brick face rgb(96,52,42) (html:649) x1.75
	Color(1.000, 0.769, 0.376),   # SPARK rgb(255,196,96) verbatim (html:2132)
	Color(0.865, 0.837, 0.727),   # tile face rgb(126,122,106) (html:683) x1.75
	Color(0.508, 0.357, 0.192),   # door plank rgb(74,52,28) (html:696) x1.75
	Color(0.631, 0.604, 0.549),   # rubble chunk rgb(92,88,80) (html:723) x1.75
	Color(0.865, 0.618, 0.329),   # barricade plank rgb(126,90,48) (html:821) x1.75
]

## Floor textures, indexed by `MapData.FL_*`.
const FLOOR_FAM := [FAM_DUST, FAM_DUST, FAM_DUST, FAM_SPARK]
const FLOOR_TINT := [
	Color(0.453, 0.165, 0.151),   # carpet pile rgb(66,24,22) (html:737) x1.75
	Color(0.494, 0.487, 0.432),   # cement #48473F (html:746) x1.75
	Color(0.480, 0.467, 0.425),   # cobble stone rgb(70,68,62) (html:756) x1.75
	Color(1.000, 0.769, 0.376),   # steel grate — SPARK, as the metal wall
]

## Ceiling textures, indexed by `MapData.CE_*`.
##
## Nothing can reach these today: `world_builder._build_static` appends wall and
## floor triangles to the level's `ConcavePolygonShape3D` and never a ceiling
## quad, so a round fired at the roof passes through it and terminates on
## nothing. The branch is here because *which table to read* is a function of the
## hit normal, not of which surfaces happen to carry a collider this week — and
## on the day a ceiling gets one, a shot into it must not spray carpet.
const CEIL_FAM := [FAM_DUST, FAM_DUST, FAM_SPLINTER, FAM_SPARK]
const CEIL_TINT := [
	Color(0.522, 0.501, 0.446),   # plaster #4C4941 (html:772) x1.75
	Color(0.069, 0.089, 0.137),   # night sky #0A0D14 (html:779) x1.75 — nearly black
	Color(0.604, 0.480, 0.336),   # joist #584631 (html:790) x1.75
	Color(1.000, 0.769, 0.376),   # metal — SPARK
]

## A face is a floor or a ceiling only when its normal is essentially vertical.
## Every wall in this level is axis-aligned and exactly vertical, so the split is
## never a near-miss judgement; 0.7 puts it at 45 degrees and leaves no band in
## which a surface is neither.
const VERTICAL_DOT := 0.7


# --- particle presets --------------------------------------------------------

## `spawnParticles` (html:2117-2128) threw each mote at a random heading with
## `rnd(spd, 0.4)` across the ground and `rnd(up, -0.4)` vertically, applied
## `grav`, and killed it after `rnd(life, 0.22)`. `rnd(a, b)` is
## `b + random()*(a-b)` (html:377), so all three of those are ranges.
##
## Translated the same way the blood puff below already was: a cone about the
## emitter's forward axis carries the heading, `initial_velocity_min/max` carries
## the speed range, and `lifetime_randomness` carries `rnd`'s lower bound as a
## fraction of the lifetime. The one thing that could not be transliterated is
## the ancestor's ground bounce (`if(p.z<0.04){ vz*=-0.3; ... }`, html:2141),
## which a `ParticleProcessMaterial` has no expression for and which nobody will
## miss on a mote that lives a third of a second.
##
## `px` rather than `size`, and `burst` rather than `count`: dot access on a
## `Dictionary` is a key lookup and `size` is also a `Dictionary` method — the
## same trap `zombie.gd`'s EYE_PX table records.
const DUST := {
	# 3 at 0.03 m is the ancestor's own wall puff (html:2502) and it is the one
	# number here that does not survive the port. Its particles were screen-space
	# quads on a 640x360 backbuffer; three centimetres at eight metres through a
	# 74-degree vertical FOV at 1080p subtends three pixels. Doubled to six with
	# the size jitter widened to 1.0-2.6x, which is the least that makes a missed
	# shot visible at all. Invented, and the first thing to cut if fill rate bites.
	"burst": 6, "px": 0.03, "vmin": 0.4, "vmax": 1.2, "grav": 4.0,
	"life": 0.35, "life_rand": 0.37, "spread": 70.0, "smin": 1.0, "smax": 2.6,
}
const SPLINTER := {
	# SPLINT (html:2131). The ancestor spent 6 of them every time a zombie tore a
	# plank off a barricade (html:2277) — the only place it ever called the
	# preset, and the closest thing it has to a "wood was hit" burst.
	"burst": 6, "px": 0.085, "vmin": 0.4, "vmax": 3.4, "grav": 11.0,
	"life": 0.8, "life_rand": 0.275, "spread": 55.0, "smin": 0.7, "smax": 1.4,
}
const SPARK := {
	# SPARK (html:2132) is declared in the ancestor and called from nowhere: dead
	# data sitting between the three presets that are used. Its name, its 0.35 s
	# lifetime, its gravity of 13 and its `glow:true` say exactly what it was cut
	# before doing, and riveted steel plate is the only surface in this map that
	# wants it. The burst of 8 is the low end of M3-combat-fx.md F7's 8-10 for
	# metal; every other number is the preset verbatim.
	"burst": 8, "px": 0.06, "vmin": 0.4, "vmax": 5.6, "grav": 13.0,
	"life": 0.35, "life_rand": 0.37, "spread": 40.0, "smin": 0.8, "smax": 1.6,
}

## Emitters per family. Concrete, brick and tile are most of the level so dust
## gets most of the pool; steel is two rooms. Fourteen emitters in total with the
## six inherited blood ones, against SYNTHESIS section 2.1's estimate of twelve —
## the blood pool was already six when this file took it over, and shrinking a
## working effect while moving it is exactly what the move was told not to do.
const POOL_PER_FAM := [4, 2, 2]

## Pushed off the surface along its normal so a burst is not born inside the wall
## it came out of. Larger than the decal lift because a particle then moves.
const DEBRIS_LIFT := 0.02


# --- decal ring buffers ------------------------------------------------------

## Two rings, sized as SYNTHESIS section 2.1 specifies. Rings rather than
## pools-with-lifetimes because a bullet hole has no reason to expire: the
## forty-ninth shot overwrites the first, which is both the cheapest eviction
## policy available and the right one. The level should carry the evidence of the
## last forty-eight rounds, not of the last twelve seconds.
const HOLES := 48
const SPLATS := 32
const TRACERS := 8

## The depth buffer is 24-bit and `BaseMaterial3D` has no polygon-offset or
## depth-bias property in Godot 4, so a positional offset along the normal is the
## standard fallback — 0.008 m is what both reference implementations surveyed in
## M3-combat-fx.md F6 converged on, and the walls here are axis-aligned so there
## is no curved-surface clipping to fight.
const DECAL_LIFT := 0.008

const HOLE_SIZE := 0.11        # invented: a hole has to read on a 1 m tile
const SPLAT_SIZE := 0.50       # invented: a body's worth of pooled blood

## A bullet hole is a shadowed pit, so it has to be darker than the dust that
## came out of it or it reads as a sticker. Invented; the tint being multiplied
## is sourced, the darkening is not.
const HOLE_DARKEN := 0.22
const HOLE_ALPHA := 0.85

## `rgba(72,8,10, t*0.55)` — the pool the ancestor's own death animation grows
## under a falling corpse (html:1001-1002), at the alpha it reaches on the last
## frame. Taking it from there means the persistent floor pool and the corpse
## that made it are the same colour, which they would not have been if this had
## been picked rather than read.
const SPLAT_TINT := Color(72.0 / 255.0, 8.0 / 255.0, 10.0 / 255.0, 0.55)

## `255,214,130` — the ancestor's default muzzle-flash tint (html:3151). A tracer
## is the same burning propellant seen from behind, so it is the same colour. The
## Ray Gun's and Thundergun's flash tints stay with the flash in `main.gd`:
## neither fires a bullet, and neither gets a tracer here.
const TRACER_TINT := Color(1.0, 214.0 / 255.0, 130.0 / 255.0)
const TRACER_WIDTH := 0.022
## Two frames at 60 Hz is 0.033 s; 0.04 survives one dropped frame and is still
## short enough that the streak never reads as a laser.
const TRACER_LIFE := 0.04
## Real linked ammunition carries a tracer every fourth or fifth round, loaded at
## a fixed interval in the belt — so this is a counter and not a die roll. Which
## is also the only way to have it at all, since nothing in this file may touch
## an `Rng` stream (see the header).
const TRACER_EVERY := 4
## Below this a tracer is a dot at the muzzle and costs a slot for nothing.
const TRACER_MIN_LEN := 0.6

## Knuth's multiplicative constant and the shift `map_data.build()` already uses
## for its per-tile shade jitter, reused so there is one hash in the project, and
## masked to 32 bits for the same reason it is there: the browser build's `>>> 0`.
const HASH_MUL := 2654435761

## Big enough to rasterise. A sub-pixel primitive compiles no fragment stage,
## which is the failure mode `shader_warmup.gd`'s own comment warns about; this
## is that file's `SIZE`, for the same reason.
const WARM_SIZE := 0.012


# --- state -------------------------------------------------------------------

var _player: Player
var _map: MapData

var _impacts: Array[GPUParticles3D] = []
var _impact_next := 0
var _blood_mat: StandardMaterial3D

var _debris: Array = []                 # family -> Array[GPUParticles3D]
var _debris_next := PackedInt32Array()
var _wall_mesh: Array = []              # MapData.TX_* -> QuadMesh
var _floor_mesh: Array = []             # MapData.FL_* -> QuadMesh
var _ceil_mesh: Array = []              # MapData.CE_* -> QuadMesh
var _debris_meshes := {}                # "family|tint" -> QuadMesh, deduped
var _debris_mats: Array = []            # for the warm-up pass

var _holes: MultiMeshInstance3D
var _hole_next := 0
var _splats: MultiMeshInstance3D
var _splat_next := 0
var _tracers: MultiMeshInstance3D
var _tracer_next := 0
var _tracer_life := PackedFloat32Array()
var _tracer_live := 0
var _hole_mat: StandardMaterial3D
var _splat_mat: StandardMaterial3D
var _tracer_mat: StandardMaterial3D

var _shot_no := 0
var _tracer_from := Vector3.ZERO
var _tracer_armed := false


func _ready() -> void:
	_setup_impacts()
	_setup_debris()
	_setup_decals()


## Called by `main.gd` once the player and the map exist.
##
## `surface_impact` is connected by name rather than as `p.surface_impact`
## deliberately. A typed member access is resolved at *parse* time, and a parse
## error in a script reachable from the main scene makes Godot hang rather than
## report — so if that signal is ever renamed or removed, the failure has to be a
## runtime error that names it, not a build that never finishes.
func bind(p: Player, m: MapData) -> void:
	_player = p
	_map = m
	p.impact.connect(_on_flesh_hit)
	p.fired.connect(_on_fired)
	p.connect(&"surface_impact", _on_surface_impact)


# --- blood -------------------------------------------------------------------
#
# Everything from here to _on_impact() was lifted out of main.gd unchanged. The
# comments came with it because they encode constraints, not intent.

## Blood puffs, from a pool, for the same reason the muzzle flash is one
## persistent light: a node per hit is an allocation inside the fire loop, and
## the first draw of a new material is an uncached shader compile on the web.
##
## The pool is also forced rather than chosen. `emit_particle()` does not exist
## under gl_compatibility — it is one of the calls that warns once in the editor
## and silently does nothing in the browser — so a burst cannot be a call into a
## shared emitter. It has to be a whole emitter, repositioned and restarted.
const IMPACT_POOL := 6
## Fixed, because changing `amount` reallocates the particle buffer. The per-hit
## count rides on `amount_ratio` instead, which costs nothing. 21 is the largest
## burst in the ancestor's blood table (see _on_impact), so it is the allocation.
const IMPACT_AMOUNT := 21
## kriegsnacht.html's BLOOD preset: rgb 126,16,18, life 0.72 s, size 0.10 m,
## gravity 11 m/s^2 — not 9.8; it is deliberately heavier than the world's.
const BLOOD := Color(126.0 / 255.0, 16.0 / 255.0, 18.0 / 255.0)
const IMPACT_LIFE := 0.72
const IMPACT_GRAVITY := 11.0


func _setup_impacts() -> void:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.07
	proc.direction = Vector3(0, 1, 0)
	# The ancestor threw each drop at a random heading with 0.4-4.2 m/s across
	# the floor and -0.4-4.0 m/s upward (2117-2129). A wide cone around up with
	# the same speed range is the closest a process material can state that.
	proc.spread = 74.0
	proc.initial_velocity_min = 0.4
	proc.initial_velocity_max = 4.2
	proc.gravity = Vector3(0.0, -IMPACT_GRAVITY, 0.0)
	# Multiplies the 0.10 m draw quad, so this is jitter around the preset size.
	proc.scale_min = 0.65
	proc.scale_max = 1.35
	# life was rnd(0.72, 0.22): 0.7 randomness over a 0.72 s lifetime is the same
	# 0.216-0.72 s spread, and it is what stops a burst dying all at once.
	proc.lifetime_randomness = 0.7
	# Alpha was life/max in the ancestor — a straight linear fade.
	var grad := Gradient.new()
	grad.set_color(0, BLOOD)
	grad.set_color(1, Color(BLOOD.r, BLOOD.g, BLOOD.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	ramp.width = 32
	proc.color_ramp = ramp

	_blood_mat = StandardMaterial3D.new()
	_blood_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blood_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# BILLBOARD_PARTICLES, not BILLBOARD_ENABLED: the plain billboard mode
	# overwrites MODELVIEW_MATRIX with a camera basis plus the translation, which
	# throws away the per-particle scale. The particle mode rebuilds it.
	_blood_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Without this the colour ramp does nothing: a particle's colour arrives as
	# vertex colour, so the fade has to be read from there.
	_blood_mat.vertex_color_use_as_albedo = true
	_blood_mat.disable_receive_shadows = true

	var quad := QuadMesh.new()
	quad.size = Vector2(0.10, 0.10)
	quad.material = _blood_mat

	for i in IMPACT_POOL:
		var p := GPUParticles3D.new()
		p.name = "Impact%d" % i
		# One process material and one mesh across the pool, so the pool is one
		# process shader and one draw shader however many emitters it holds.
		p.process_material = proc
		p.draw_pass_1 = quad
		p.amount = IMPACT_AMOUNT
		p.lifetime = IMPACT_LIFE
		p.one_shot = true
		p.explosiveness = 1.0
		p.emitting = false
		# World space, so a puff stays where it was made when the emitter is
		# recycled to the far side of the map two hits later.
		p.local_coords = false
		# INDEX skips the CPU depth sort, which is the only part of a
		# GPUParticles3D that costs main-thread time.
		p.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(p)
		_impacts.append(p)


## `at` is the real intersection point. The ancestor pinned its puffs to fixed
## heights — 1.05 body, 1.58 head — because its raycaster had no height test at
## all, and that is one of the few places the port is already better than the
## thing it is porting.
##
## Counts come from the ancestor's blood call sites, and they are not symmetric:
## every damage event spends `head ? 7 : 4` (2227), and a *headshot* kill spends a
## second burst of 14 on top (2235) while a body kill spends nothing extra. A kill
## the player cannot distinguish from a graze is the one thing this effect exists
## to prevent, so the body-kill case borrows the ancestor's own body-death burst —
## the 8 its nuke spends per corpse (2418).
func _on_impact(at: Vector3, headshot: bool, killed: bool) -> void:
	var n := 7 if headshot else 4
	if killed:
		n = 21 if headshot else 8
	var p := _impacts[_impact_next]
	_impact_next = (_impact_next + 1) % _impacts.size()
	# This is the only thing that moves an emitter. The pool is round-robin
	# rather than least-recently-finished because a Thundergun cone can hit eight
	# zombies in one frame, and the honest answer there is that the last six win.
	p.global_position = at
	# Half a particle of headroom: the process shader turns the ratio back into a
	# count with a float multiply and a truncate, and 4.0/21.0*21.0 is not exactly
	# 4.0 in 32-bit float. Rounding the wrong way would silently drop a particle.
	p.amount_ratio = minf((float(n) + 0.5) / float(IMPACT_AMOUNT), 1.0)
	p.restart()


# --- everything below this line is new ---------------------------------------

## What a hit on flesh does now. `_on_impact` above is the blood puff exactly as
## `main.gd` owned it and is deliberately untouched; the two calls here are this
## package's additions, kept outside it so a diff can tell them apart.
func _on_flesh_hit(at: Vector3, headshot: bool, killed: bool) -> void:
	_on_impact(at, headshot, killed)
	_maybe_tracer(at)
	# Only a kill leaves a pool. A pool per *hit* would churn all thirty-two
	# slots in two seconds of automatic fire, and the floor would then read as
	# fog rather than as a body count.
	if killed:
		_splat(at)


# --- surface impacts ---------------------------------------------------------

## A round that terminated on world geometry. The surface is derived by
## quantising the hit point to the tile grid and reading `MapData` — exact, free,
## and available only because the world is a grid: no metadata to keep in sync,
## no per-node storage, and it stays correct if the world builder ever re-textures
## a tile.
func _on_surface_impact(at: Vector3, normal: Vector3) -> void:
	_maybe_tracer(at)

	# Concrete is the fallback for anything off the grid, which is what the whole
	# map is walled in with anyway.
	var fam: int = WALL_FAM[MapData.TX_CONCRETE]
	var tint: Color = WALL_TINT[MapData.TX_CONCRETE]
	var mesh: QuadMesh = _wall_mesh[MapData.TX_CONCRETE]

	if normal.y > VERTICAL_DOT:
		var t := _tile_tex(at, _map.ftex)
		if t >= 0 and t < FLOOR_FAM.size():
			fam = FLOOR_FAM[t]
			tint = FLOOR_TINT[t]
			mesh = _floor_mesh[t]
	elif normal.y < -VERTICAL_DOT:
		var t := _tile_tex(at, _map.ctex)
		if t >= 0 and t < CEIL_FAM.size():
			fam = CEIL_FAM[t]
			tint = CEIL_TINT[t]
			mesh = _ceil_mesh[t]
	else:
		# A wall face is the boundary between an open tile and a solid one and the
		# hit point sits exactly on it, so quantising the point itself lands on
		# whichever side floating point felt like. Step half a tile *into* the
		# wall along the inward normal first: that is unambiguously inside the
		# solid tile and nowhere near its far face.
		var t := _tile_tex(at - normal * 0.5, _map.wtex)
		if t >= 0 and t < WALL_FAM.size():
			fam = WALL_FAM[t]
			tint = WALL_TINT[t]
			mesh = _wall_mesh[t]

	_spray(fam, at, normal, mesh)
	_hole(at, normal, tint)


## The texture id one of `MapData`'s grids holds at a world point, or -1 if the
## point is off the map. The grids are `PackedByteArray`, so this is a byte index
## rather than a dictionary lookup.
func _tile_tex(at: Vector3, grid: PackedByteArray) -> int:
	var x := floori(at.x)
	var y := floori(at.z)
	if x < 0 or y < 0 or x >= MapData.MAPW or y >= MapData.MAPH:
		return -1
	return grid[MapData.ix(x, y)]


# --- debris ------------------------------------------------------------------

func _setup_debris() -> void:
	_debris_next.resize(FAM_COUNT)
	var presets: Array = [DUST, SPLINTER, SPARK]
	for fam in FAM_COUNT:
		var preset: Dictionary = presets[fam]
		var proc := _debris_process(preset)
		var pool: Array[GPUParticles3D] = []
		var n: int = POOL_PER_FAM[fam]
		var burst: int = preset.burst
		var life: float = preset.life
		for i in n:
			var p := GPUParticles3D.new()
			p.name = "Debris%d_%d" % [fam, i]
			p.process_material = proc
			# Every emitter starts on its own family's default mesh, so the first
			# burst after bind() cannot draw a null pass even if the surface
			# lookup somehow falls through.
			p.draw_pass_1 = _debris_mesh(fam, _default_tint(fam))
			p.amount = burst
			p.lifetime = life
			p.one_shot = true
			p.explosiveness = 1.0
			p.emitting = false
			# World space, so a burst stays on the wall it came off when the
			# emitter is recycled across the map two shots later.
			p.local_coords = false
			p.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			add_child(p)
			pool.append(p)
		_debris.append(pool)

	# Built eagerly so an impact is an array index and never a cache miss with a
	# QuadMesh.new() behind it.
	for t in WALL_FAM.size():
		var fam: int = WALL_FAM[t]
		var tint: Color = WALL_TINT[t]
		_wall_mesh.append(_debris_mesh(fam, tint))
	for t in FLOOR_FAM.size():
		var fam: int = FLOOR_FAM[t]
		var tint: Color = FLOOR_TINT[t]
		_floor_mesh.append(_debris_mesh(fam, tint))
	for t in CEIL_FAM.size():
		var fam: int = CEIL_FAM[t]
		var tint: Color = CEIL_TINT[t]
		_ceil_mesh.append(_debris_mesh(fam, tint))


func _default_tint(fam: int) -> Color:
	var t := MapData.TX_CONCRETE
	if fam == FAM_SPLINTER:
		t = MapData.TX_WOOD
	elif fam == FAM_SPARK:
		t = MapData.TX_METAL
	var c: Color = WALL_TINT[t]
	return c


## One process material per family and no more. A `ParticleProcessMaterial` is a
## whole process shader and this platform recompiles every one of them from
## source on every page load — so the colour cannot live here, where it would
## multiply the shader count by the number of textures in the level. It lives in
## the draw material instead, where a dozen of them share one program, because
## `BaseMaterial3D` caches its generated shader by feature flags and every one of
## those sets the same flags.
func _debris_process(preset: Dictionary) -> ParticleProcessMaterial:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.04
	# +Z, because `_face_basis` turns the emitter so that its +Z is the surface
	# normal. The ancestor could only throw debris at a random compass heading —
	# it had no normal to spray along, only a wall distance.
	proc.direction = Vector3(0, 0, 1)
	# Every one of these arrives from a Dictionary as Variant, so each is pinned
	# to a typed local rather than inferred — the compiler cannot see through a
	# subscript and a wrong guess here is a silent physics change, not an error.
	var spread: float = preset.spread
	var vmin: float = preset.vmin
	var vmax: float = preset.vmax
	var grav: float = preset.grav
	var smin: float = preset.smin
	var smax: float = preset.smax
	var life_rand: float = preset.life_rand
	proc.spread = spread
	proc.initial_velocity_min = vmin
	proc.initial_velocity_max = vmax
	# Gravity is world-space while `local_coords` is false, which is what makes
	# debris off a ceiling fall rather than continue outward.
	proc.gravity = Vector3(0.0, -grav, 0.0)
	proc.scale_min = smin
	proc.scale_max = smax
	proc.lifetime_randomness = life_rand
	# White with the whole fade in alpha: the hue rides on the draw material's
	# albedo, so one ramp serves every surface in the game.
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	ramp.width = 32
	proc.color_ramp = ramp
	return proc


## One mesh per (family, tint), carrying its own draw material. Deduped, because
## the steel plate, the steel grate and the metal ceiling are three texture ids
## and one spark.
func _debris_mesh(fam: int, tint: Color) -> QuadMesh:
	var key := "%d|%s" % [fam, tint.to_html(false)]
	if _debris_meshes.has(key):
		var cached: QuadMesh = _debris_meshes[key]
		return cached

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Sparks are the one place glow earns its keep on this renderer: additive
	# blending against `glow_hdr_threshold` is what makes a spark read as burning
	# steel rather than as an orange dot. `glow:true` on the SPARK preset
	# (html:2132) is the ancestor's own flag and this is the only thing it can
	# mean here.
	if fam == FAM_SPARK:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = tint
	mat.disable_receive_shadows = true
	# Deliberately left taking the depth fog, which is the opposite of the call
	# the zombies' eyes make and for the opposite reason: debris is lit matter
	# thrown off a wall, not light, so the air in front of it should grey it.
	_debris_mats.append(mat)

	var px: float = DUST.px
	if fam == FAM_SPLINTER:
		px = SPLINTER.px
	elif fam == FAM_SPARK:
		px = SPARK.px
	var quad := QuadMesh.new()
	quad.size = Vector2(px, px)
	quad.material = mat
	_debris_meshes[key] = quad
	return quad


func _spray(fam: int, at: Vector3, normal: Vector3, mesh: QuadMesh) -> void:
	var pool: Array = _debris[fam]
	var i: int = _debris_next[fam]
	_debris_next[fam] = (i + 1) % pool.size()
	var p: GPUParticles3D = pool[i]
	# Compared before assigning: consecutive shots usually land on the same
	# texture, and re-handing a GPUParticles3D the mesh it already has is work
	# for nothing.
	if p.draw_pass_1 != mesh:
		p.draw_pass_1 = mesh
	# The whole transform, not just the origin — the emitter's basis is what
	# points the spray cone out of the surface.
	p.global_transform = Transform3D(_face_basis(normal), at + normal * DEBRIS_LIFT)
	p.restart()


# --- decals ------------------------------------------------------------------

func _setup_decals() -> void:
	# A tight core with a soft scatter ring, baked once. A `Shader` here would be
	# a main-thread GLSL compile for every visitor on every page load; a gradient
	# is one 32x32 upload and nothing after — the same trade the zombies' eyes
	# already make.
	_hole_mat = _decal_material(_radial([0.0, 0.34, 0.62, 1.0],
		[1.0, 0.88, 0.30, 0.0]))
	# Broader and flatter: a pool rather than a pit.
	_splat_mat = _decal_material(_radial([0.0, 0.46, 0.80, 1.0],
		[0.92, 0.62, 0.18, 0.0]))

	_holes = _ring(_hole_mat, HOLE_SIZE, HOLES, "Holes")
	_splats = _ring(_splat_mat, SPLAT_SIZE, SPLATS, "Splats")

	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tracer_mat.vertex_color_use_as_albedo = true
	_tracer_mat.albedo_color = TRACER_TINT
	_tracer_mat.disable_receive_shadows = true
	# A tracer is light in the air. Depth fog would lerp it toward the fog colour
	# with distance, which is backwards for the one effect whose whole job is to
	# draw the eye down a dark corridor.
	_tracer_mat.disable_fog = true
	# Deliberately *not* `no_depth_test`: disabling the depth test forces the
	# surface into the transparent queue ahead of everything else and would draw
	# the streak through walls and through zombies.

	# A box rather than a quad. A flat streak vanishes at exactly the angle a
	# first-person shooter guarantees you will sometimes see it from — down the
	# barrel — and six faces of a 2 cm box is not a cost worth that trade.
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	box.material = _tracer_mat
	_tracers = MultiMeshInstance3D.new()
	_tracers.name = "Tracers"
	_tracers.multimesh = _multimesh(box, TRACERS)
	_tracers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tracers.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_tracers.custom_aabb = _map_aabb()
	add_child(_tracers)
	_tracer_life.resize(TRACERS)


func _decal_material(tex: GradientTexture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	# Unshaded, and dark. A lit decal would need the eight-light fragment loop on
	# a MultiMesh whose AABB spans the entire map; a dark alpha-blended sticker
	# darkens a lit wall and disappears on an unlit one, which is what a hole in
	# a dark room actually does. This is the one place the level's "nothing else
	# is unshaded" rule is knowingly set aside, and it is set aside because the
	# surface is subtractive rather than lit.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# The per-instance colour arrives as vertex colour, exactly as a particle's
	# ramp does, so both the tint and the opacity have to be read from there.
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	# Drawn after the other transparents at the same depth, so a floor pool and
	# the blood puff that made it do not argue about which lands on top.
	mat.render_priority = 1
	return mat


## A radial white gradient with the whole falloff in alpha, so nothing here
## depends on whether an RGBA8 texture is decoded as sRGB — the hue arrives from
## the instance colour.
func _radial(offsets: Array, alphas: Array) -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in offsets.size():
		var o: float = offsets[i]
		var a: float = alphas[i]
		offs.append(o)
		cols.append(Color(1.0, 1.0, 1.0, a))
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


func _ring(mat: StandardMaterial3D, size: float, count: int,
		node_name: String) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = _multimesh(quad, count)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.custom_aabb = _map_aabb()
	add_child(mi)
	return mi


## The whole level, given once, so the renderer never has to derive a bounding
## box from the instance transforms. Two reasons, and the second is the real one:
## a ring whose instances are all collapsed to zero has a point-sized AABB, and a
## point-sized AABB at the origin is frustum-culled — which would mean the
## warm-up probe below never rasterises and never compiles anything. Decals end
## up scattered across the map anyway, so nothing is lost to culling that would
## not have been lost regardless.
func _map_aabb() -> AABB:
	return AABB(Vector3(0.0, -1.0, 0.0),
		Vector3(float(MapData.MAPW), MapData.WALL_H + 2.0, float(MapData.MAPH)))


## Order is load-bearing: `transform_format` and `use_colors` each reset the
## buffer, so setting either of them after `instance_count` silently discards
## every instance already written.
func _multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		_retire(mm, i)
	return mm


## A `MultiMesh` has no per-instance visibility flag, so retiring a slot means
## collapsing its basis. Three zero-length columns rasterise no fragments at all
## and cost one buffer write, where a shrink-to-nothing animation would cost one
## write per slot per frame for something nobody can see.
func _retire(mm: MultiMesh, i: int) -> void:
	mm.set_instance_transform(i,
		Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO))


func _hole(at: Vector3, normal: Vector3, tint: Color) -> void:
	var mm := _holes.multimesh
	var i := _hole_next
	_hole_next = (_hole_next + 1) % HOLES
	var roll := _hash01(at) * TAU
	# 0.85-1.25, from a second draw on a displaced point, so two holes a
	# centimetre apart do not come out the same size as well as the same angle.
	var s := 0.85 + _hash01(at + Vector3(17.3, 0.0, 5.1)) * 0.40
	mm.set_instance_transform(i,
		Transform3D(_decal_basis(normal, roll, s), at + normal * DECAL_LIFT))
	mm.set_instance_color(i, Color(tint.r * HOLE_DARKEN, tint.g * HOLE_DARKEN,
		tint.b * HOLE_DARKEN, HOLE_ALPHA))


## The pool a corpse leaves. It goes on the floor rather than on the wall behind
## the shot, which would cost a second raycast per kill: the level has no height
## variation anywhere, so the floor under a zombie is at y=0 by construction and
## the pool can be placed without asking the physics server anything at all.
func _splat(at: Vector3) -> void:
	var mm := _splats.multimesh
	var i := _splat_next
	_splat_next = (_splat_next + 1) % SPLATS
	var on_floor := Vector3(at.x, DECAL_LIFT, at.z)
	var roll := _hash01(at) * TAU
	var s := 0.8 + _hash01(at + Vector3(3.7, 0.0, 11.9)) * 0.6
	mm.set_instance_transform(i,
		Transform3D(_decal_basis(Vector3.UP, roll, s), on_floor))
	mm.set_instance_color(i, SPLAT_TINT)


## Flat against a surface, rolled about its own normal so a wall does not end up
## tiled with identically-oriented stamps.
##
## The scale is applied by rebuilding the basis from its own columns rather than
## with `Basis.scaled()`, which multiplies the *rows* — a global-axis scale, and
## therefore a shear once the basis has been turned to face a wall.
func _decal_basis(normal: Vector3, roll: float, s: float) -> Basis:
	var b := _face_basis(normal) * Basis(Vector3(0, 0, 1), roll)
	return Basis(b.x * s, b.y * s, b.z)


## +Z along the surface normal. The up vector is guarded because
## `Basis.looking_at` is degenerate when the direction it is given is parallel to
## `up` — which, in a level built from axis-aligned tiles, is every floor and
## every ceiling. It is also the exact bug one of the two implementations
## surveyed in M3-combat-fx.md F6 ships.
func _face_basis(normal: Vector3) -> Basis:
	var up := Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > 0.99 else Vector3.UP
	return Basis.looking_at(-normal, up)


## Deterministic 0-1 from a world point, quantised to the centimetre. This is
## where the variation that would otherwise have been a `randf()` comes from —
## see the header: a cosmetic draw from `Rng.VISUAL` would move a seeded run's
## shots, because weapon spread is sampled from that same stream.
##
## The three odd multipliers only have to fold x, y and z into one integer
## without collapsing; they are kept small so the product below cannot overflow
## a 64-bit int, which is the one way a hash silently stops varying.
func _hash01(p: Vector3) -> float:
	var i := (roundi(p.x * 100.0) * 31 + roundi(p.y * 100.0) * 131
		+ roundi(p.z * 100.0) * 523) & 0x7FFFFFF
	var h := ((i * HASH_MUL) ^ (i << 7)) & 0xFFFFFFFF
	return float(h % 65536) / 65536.0


# --- tracers -----------------------------------------------------------------

func _on_fired(muzzle: Vector3) -> void:
	_shot_no += 1
	_tracer_from = muzzle
	# Cone weapons fire no round to trace, and the Thundergun's flash already is
	# the effect. `def` and `cone` come out of a Dictionary as Variant, so both
	# are annotated rather than inferred.
	var def: Dictionary = _player.current_gun().def
	var cone: float = def.cone
	_tracer_armed = cone <= 0.0 and (_shot_no % TRACER_EVERY) == 0


## Consumed by whichever terminal event the round produces first, so a shotgun's
## eight pellets and an M14's two-deep pierce draw one streak between them rather
## than eight. A shot that terminates on nothing at all leaves the flag armed and
## the *next* shot's terminus draws it — still a correct streak, one round late,
## and the only reason the counter is approximate rather than exact.
func _maybe_tracer(to: Vector3) -> void:
	if not _tracer_armed:
		return
	_tracer_armed = false
	var d := to - _tracer_from
	var span := d.length()
	if span < TRACER_MIN_LEN:
		return
	var mm := _tracers.multimesh
	var i := _tracer_next
	_tracer_next = (_tracer_next + 1) % TRACERS
	var b := _face_basis(d / span)
	# Local scale, rebuilt from the columns for the same reason `_decal_basis`
	# does it: `Basis.scaled()` would scale the world axes and shear the streak.
	mm.set_instance_transform(i, Transform3D(
		Basis(b.x * TRACER_WIDTH, b.y * TRACER_WIDTH, b.z * span),
		_tracer_from + d * 0.5))
	mm.set_instance_color(i, TRACER_TINT)
	if _tracer_life[i] <= 0.0:
		_tracer_live += 1
	_tracer_life[i] = TRACER_LIFE


## The only per-frame work in this file, and it does none at all while no tracer
## is in the air — which is most frames, since a tracer lives 40 ms and even the
## fastest weapon in the game produces one every 270 ms.
func _process(dt: float) -> void:
	if _tracer_live <= 0:
		return
	var mm := _tracers.multimesh
	for i in TRACERS:
		if _tracer_life[i] <= 0.0:
			continue
		_tracer_life[i] -= dt
		if _tracer_life[i] <= 0.0:
			_tracer_life[i] = 0.0
			_tracer_live -= 1
			_retire(mm, i)


# --- warm-up -----------------------------------------------------------------

## Every material this file owns, for the ordinary warm-up pass. That pass draws
## each one on a plain `MeshInstance3D`, which compiles the non-instanced draw
## variant — necessary, but not sufficient; see `warm()`.
func materials() -> Array:
	var out: Array = [_blood_mat, _hole_mat, _splat_mat, _tracer_mat]
	out.append_array(_debris_mats)
	return out


## The two things `shader_warmup.gd` structurally cannot reach.
##
## A particle **process** shader compiles the first time an emitter actually
## runs, and a **MultiMesh** draws with `USE_INSTANCING` defined, which is a
## different program from the same material on a plain mesh. Both are paid here,
## behind the title card, by putting one of everything half a metre in front of
## the lens for two frames.
##
## The burst has to be cleaned up rather than left to expire, because the title
## card is only 92% opaque: a real blood puff fired half a metre from the lens
## reads straight through it, so the first thing a visitor saw was gore floating
## over the title. Two frames is enough to have drawn it — which is what compiles
## the shader — and restart() drops the particles that are still in the air.
func warm() -> void:
	var cam := _player.camera()
	# `cb` rather than `basis`: Node3D carries a property of that name and a
	# local shadowing it is a warning, which here is a build failure.
	var cb := cam.global_transform.basis
	# +Z of the camera points back at the viewer, so this is the direction a
	# surface at `at` would have to face to be seen.
	var toward := cb.z
	var right := cb.x
	var at := cam.global_position - toward * 0.5

	_on_impact(at, false, false)
	for fam in FAM_COUNT:
		var pool: Array = _debris[fam]
		var p: GPUParticles3D = pool[0]
		p.global_transform = Transform3D(_face_basis(toward), at)
		p.restart()

	# Spread apart so none of the three is wholly hidden behind another: a
	# fragment that never rasterises compiles no fragment stage.
	_warm_probe(_holes, WARM_SIZE / HOLE_SIZE, at + right * 0.03, toward)
	_warm_probe(_splats, WARM_SIZE / SPLAT_SIZE, at, toward)
	_warm_probe(_tracers, WARM_SIZE, at - right * 0.03, toward)

	await get_tree().process_frame
	await get_tree().process_frame

	for p: GPUParticles3D in _impacts:
		p.restart()
		p.emitting = false
	for fam in FAM_COUNT:
		var pool: Array = _debris[fam]
		for p: GPUParticles3D in pool:
			p.restart()
			p.emitting = false
	for mi: MultiMeshInstance3D in [_holes, _splats, _tracers]:
		_retire(mi.multimesh, 0)

	_impact_next = 0
	for fam in FAM_COUNT:
		_debris_next[fam] = 0
	_hole_next = 0
	_splat_next = 0
	_tracer_next = 0
	_tracer_live = 0
	for i in TRACERS:
		_tracer_life[i] = 0.0


## Uniform scale, unlike a real decal: this has to serve the tracer's box as
## well as the two quads, and leaving that box's long axis unscaled would spear a
## one-metre needle through the near plane for the two frames this runs.
func _warm_probe(mi: MultiMeshInstance3D, s: float, at: Vector3,
		toward: Vector3) -> void:
	var b := _face_basis(toward)
	mi.multimesh.set_instance_transform(0,
		Transform3D(Basis(b.x * s, b.y * s, b.z * s), at))
	mi.multimesh.set_instance_color(0, Color(1.0, 1.0, 1.0, 1.0))
