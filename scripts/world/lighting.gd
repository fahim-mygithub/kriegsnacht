extends Node3D

## Everything that decides how dark the map is: the `Environment`, the eight room
## lamps and their fixtures, and the ceremony that brings them up when the
## generator is thrown.
##
## It is one node because the numbers below only mean anything together. Dropping
## the ambient without dropping the lamps moves the flat grey somewhere else
## rather than removing it, and every step changes what the next one looks like —
## so they are applied in a fixed order and numbered `step 1` to `step 8` in
## `_make_environment` and `_build_lamps`. Read them in that order; the reasoning
## for each number is the previous step having already landed.
##
## The organising principle, from SYNTHESIS 4.3: **contrast comes from what is
## unlit, not from how bright the lights are.**

## preload rather than the class name: neither script carries a `class_name`, and
## a freshly added one is not in the class registry until the editor rescans.
const QUALITY := preload("res://scripts/world/quality_governor.gd")


# --- step 1: ambient ---------------------------------------------------------

## Unchanged from Milestone 1. The blue bias is what makes an unlit surface read
## as shadow rather than as underexposure, and it is the one part of the ambient
## that was already right.
const AMBIENT_COLOR := Color(0.30, 0.32, 0.36)

## 0.22 -> 0.15.
##
## The mandate asks for 0.10 and Milestone 1 refused it, correctly at the time:
## with the lamps also coming down there was then *nothing else* lighting a
## surface neither the torch nor a lamp reached, so 0.10 was a black screen with
## a cone in it. That is no longer true. `world_builder` now bakes a per-vertex
## ambient-occlusion and lamp-fill term into the vertex colours (see
## `_shade_at`), so every surface carries a static lighting term that survives
## the lamps being off and costs nothing at runtime. The ambient no longer has to
## carry room legibility; it only has to keep a surface that *no* lamp reaches
## off pure black.
##
## 0.15 is the ancestor's own answer to that question. `litLUT` is
## `v = 0.145 + 1.25/(1 + d*d*0.05)` (html:1698) — a torch term that decays to
## nothing plus a constant 0.145 floor, and that floor is precisely "the part of
## the map nothing is lighting". Taking the ancestor's number for the ancestor's
## question beats both 0.10 and 0.30, and it lands about halfway from 0.22 to the
## mandate's 0.10 on a log scale.
##
## **The units are not the same, and borrowing the digits is a starting point
## rather than a proof.** The ancestor's 0.145 multiplied an already-sRGB texel
## and went straight to the framebuffer; this is linear radiance with FILMIC and
## the sRGB encode still in front of it, and both of those lift a small number,
## so the same digits land *brighter* on screen here than they did there. That is
## the intended direction and not an oversight — the port also has fog, the
## vertex bake and SSAO subtracting from the same surface, and the ancestor had
## none of the three — but nobody has looked at a frame. See the report's risks.
const AMBIENT_ENERGY := 0.20

## Near-black, so geometry that fogs out has somewhere to fog *to*. Unchanged.
const VOID_COLOR := Color(0.02, 0.024, 0.02)


# --- step 2: fog -------------------------------------------------------------

## Already at the mandate's 0.030 since Milestone 1, and it stays there: at this
## density the far wall of the Theatre sits about 45% of the way to the fog
## colour, which is the depth cue the ancestor got for free from `litLUT`'s
## falloff and the port has no other source for.
const FOG_DENSITY := 0.030

## 0.06,0.07,0.075 -> 0.035,0.040,0.048, and this is the half of step 2 that
## actually moved. Fog is a lerp *toward* this colour, so it darkens a surface
## brighter than itself and **lifts** one darker. With step 1 taking the ambient
## down, the unlit far field now sits below the old fog colour, which would have
## turned the fog into a grey wash over exactly the darks it exists to deepen —
## the same failure the density drop from 0.055 was fixing. This sits just above
## VOID_COLOR, so distant geometry still separates from the void instead of
## vanishing into it, and below the ambient floor, so fog keeps subtracting.
const FOG_COLOR := Color(0.035, 0.040, 0.048)


# --- step 3: the room lamps --------------------------------------------------

## Sodium. Unchanged — the hue was never the problem.
const LAMP_COLOR := Color(0.98, 0.72, 0.34)

## The mandate says 1.2 -> 0.80. **Measured, and the mandate is wrong about this
## one** — not about the direction, about the arithmetic being transferable.
##
## Five things in this pass multiply the same surface: the energy cut, the ambient
## cut, a darker fog colour (fog lerps *toward* its colour, so a darker one lifts
## the darks less), the new per-vertex AO and fill bake, and SSAO. On a wall near
## the floor line they compound to about 0.37 of what shipped before — and 0.37
## after FILMIC and the sRGB encode, down at the bottom of the range where both
## curves are steepest, is not "a bit dimmer", it is gone. At 0.80 the Lobby
## rendered as a black frame with the torch cone in it.
##
## 3.0 is the rendered-frame answer (--shot, 960x540, yaw 0 and 90). It is above
## the old 1.2 in the constant and still darker on screen than the old 1.2 was,
## because the bake and SSAO now take their cut downstream of it. The lesson is
## the one the mandate's own ordering was trying to teach: every step changes what
## the next one looks like, so a target set before the earlier steps landed is a
## starting point and never a destination.
##
## This also fixes a live defect it replaces: `main.gd` built the lamps at 1.2 and
## the "power" interaction then set them to 1.15, so throwing the generator made
## every room in the level four percent *darker*. It cannot recur here — the build
## value and the powered value are now the same constant rather than two literals
## in two functions that have to be kept in agreement by hand.
const LAMP_ENERGY_ON := 3.0

## What a lamp sits at before the generator. **Not zero** — see `power_on()` for
## why the "lamps start dark" premise does not survive contact with the ancestor.
##
## Derived rather than picked: with Godot's `(1 - (d/range)^4)^2 * d^-decay` and
## the default decay of 1.0, a lamp 2.35 m above the floor of a room whose range
## works out at 14 m — the Lobby — lands 0.4248 of its energy on the floor
## directly beneath it. 0.145 / 0.4248 = 0.341, so 0.34 is the energy that puts
## the ancestor's own far-field floor figure (html:1698) under an unpowered lamp.
##
## MEASURED, and the derivation above is exactly why it had to be. Its own closing
## caveat — "the ancestor's 0.145 was a display-space multiply and this is linear
## radiance before FILMIC" — is not a footnote, it is the whole error. A number
## handed to FILMIC as linear radiance and then sRGB-encoded lands far below the
## same number used as a display-space multiply, because both transfer functions
## crush the bottom of the range a second time. 0.34 rendered the Lobby at spawn
## as a black frame with one lit barricade in it. The ancestor's arithmetic was
## right; the colour space it was applied in was wrong.
##
## 2.0 is what a rendered frame says. Two things it has to satisfy at once:
##
##   - The unpowered map must be *playable*, because the generator sits deep in
##     the level behind bought doors and the first several rounds happen without
##     it. A map that is unreadable until the player finds the switch is a worse
##     failure than a ceremony that lands softly.
##   - The ratio must stay under the glow bracket, so the fixtures cross the bloom
##     threshold only once powered — see FIXTURE_GAIN. 2.0/3.0 = 0.67, against a
##     ceiling of 0.84. That bracket, not the room brightness, is what actually
##     reads as the lights coming on, and it still holds.
##
## So the lift is 1.5x rather than 2.35x, and the reveal rides the fixtures, the
## three-flicker preamble and the staggered wave. That is also the more faithful
## answer: the ancestor's world brightness did not depend on the generator at all
## (html:1695-1702, and G.power appears in its renderer exactly once, at :1801),
## so a big pre-power darkness was this port's invention in the first place.
const LAMP_ENERGY_OFF := 2.0

## How far below the ceiling a lamp hangs. Unchanged.
const LAMP_DROP := 0.45

## Was +6.0 on the room's longer side. The point of cutting it is that six metres
## of every lamp's range — and six metres of its AABB — spilled into the corridors
## and the neighbouring room, and a corridor no lamp is in should be dark; that is
## most of what "contrast comes from what is unlit" means on this map.
##
## +3.0 was too far. A 16x14 room's half-diagonal is 10.6 m, so it still nominally
## reached every corner, but at the retuned energies the corners went dark with
## the corridors and rooms read as pools rather than as rooms. +5.0 splits it: a
## corridor still falls away, a corner does not. Invented, and set from a rendered
## frame rather than from the half-diagonal.
const LAMP_RANGE_MARGIN := 5.0


# --- step 5: the power-on ceremony -------------------------------------------

## Three flickers, all lamps together, before the wave — the generator catching
## rather than the lights coming on.
##
## At full brightness, not half. A flicker held below LAMP_ENERGY_ON leaves the
## fixtures under GLOW_THRESHOLD, and a lamp that does not bloom is the one thing
## in this scene that does not read as a lamp — the preamble would be a 29% nudge
## on an omni 2.35 m up, through fog, against a torch, which is to say invisible.
## Full brightness is also the closer reading of the only power-on *visual* the
## ancestor has: `G.flash = max(G.flash, 1.2)` (html:2786) decaying at 7/s
## (html:3365) is a bright stab of about a sixth of a second, not a gentle lift.
## Three 45 ms stabs total 0.135 s against a 2.13 s sweep, so they cannot spoil a
## reveal whose content is the *order* the rooms come up in.
const FLICKERS := 3
const FLICKER_LEVEL := 1.0
const FLICKER_ON := 0.045
const FLICKER_STEP := 0.16

## A beat between the last flicker and the first room.
const FLICKER_SETTLE := 0.18

## One room per 0.15 s in distance-from-generator order, each taking 0.42 s to
## come up. 3*0.16 + 0.18 + 7*0.15 + 0.42 = **2.13 s**, against the 2.2 s
## sawtooth sweep the ancestor's `powerOn()` plays over it
## (`tone(40, 2.2, {to:120, decay:2})`, html:515). The ceremony is the length of
## its own cue, which is the only tuning constraint that was available.
const STAGGER := 0.15
const RAMP := 0.42

## The whine is a map-wide event — the ancestor played it non-positionally — but
## it belongs to the machine you are standing at, so it goes out positionally
## with a distance cap wide enough to cover the level's 54 m diagonal.
const WHINE_DIST := 60.0


# --- step 6: glow ------------------------------------------------------------

## 0.7 -> 0.9, and `glow_bloom` 0.1 -> **0.0**, which is the change that matters.
##
## `glow_bloom` feeds a fraction of *every* pixel into the bloom buffer
## regardless of the threshold. On a scene this dark that is a flat grey lift
## across the whole frame — precisely the wash steps 1 to 3 exist to remove. All
## of the glow budget moves to the threshold-gated term, so the only things that
## bloom are things that are actually emitting: the zombies' eyes, the muzzle
## flash, the power-up drops, and the lamp fixtures once the power is on.
const GLOW_INTENSITY := 0.9
const GLOW_BLOOM := 0.0

## Unchanged. The colour buffer is RGBA8 LDR on this renderer, so a threshold far
## below 1.0 blooms the whole image; and `zombie.gd`'s eye gain (1.15) and the
## fixture gain below are both authored to clear *this* number.
const GLOW_THRESHOLD := 0.92


# --- steps 7 and 8: SSAO and the colour LUT ----------------------------------

## Half the engine default. `post.glsl` applies SSAO as `color.rgb *= s4ao(UV)`
## on the fully composited, **post-glow** image, so it darkens emissives, the
## muzzle flash and the bloom itself — which is why the mandate puts it after
## glow and why it starts low. The large-scale occlusion is already in the vertex
## bake; SSAO is only the contact term on top of it.
## Live value is `ssao_intensity * 2.0` (R1 F3a).
const SSAO_INTENSITY := 0.9

## Live value is `ssao_radius * 0.5`, so 0.35 m. The level is a 1 m grid with
## 2.8 m ceilings and the creases worth occluding are wall-to-floor and
## wall-to-wall contacts; a radius much past a third of a metre starts shading
## whole walls, which is the vertex bake's job and not this one's.
## `half_size`, `blur_passes`, `fadeout_*` and `adaptive_target` are silently
## discarded in Compatibility — do not add them (R1 F3a).
const SSAO_RADIUS := 0.7

## The ancestor added a flat **+5/255 of blue** to every world pixel after the
## light multiply and before its vignette (walls html:1813, floors and ceilings
## html:1871, where the night branch gets +9 instead of +5 — the framebuffer is
## little-endian RGBA, so the `<<16` byte those lines write really is blue).
## That is a lift of the blacks toward blue that clips away in the
## highlights, and it is why its shadows read cold. The port cannot reproduce it:
## vertex colour multiplies, `StandardMaterial3D` has no additive channel but
## emission, and adding one to every world material would be seven shader
## variants for two thousandths of a unit.
##
## A 1D colour-correction LUT is exactly this transform and costs one texture
## fetch in a pass that already runs. `post.glsl` samples it per channel
## (`out.r = lut(in.r).r`, and so on) on sRGB-encoded values after tonemapping —
## the same 8-bit display space the ancestor's `+5` operated in.
const LUT_BLUE_LIFT := 5.0 / 255.0


# --- fixtures ----------------------------------------------------------------

## A lamp with no visible source is a light nobody can point at. One additive
## billboard per lamp, driven past the glow threshold once the power is on, so a
## dark corridor screenshot has a bloomed sodium bulb at the end of it — which is
## most of what makes that screenshot read as the genre.
##
## Billboarded, not a downward-facing quad: at 1.55 m of eye height against a
## 2.35 m lamp you look at a ceiling fixture almost edge-on from across a room,
## and a flat quad would be invisible from exactly the distance it matters at.
const FIXTURE_SIZE := 0.34

## Pushes the lit fixture's red channel to 1.10, clear of GLOW_THRESHOLD, and
## leaves the unpowered one at 0.47 — under it. So an unpowered lamp is a dim
## orange dot and a powered one blooms, and the difference between the two states
## is legible in a still frame.
const FIXTURE_GAIN := 1.12

var _env: Environment
var _lamps: Array[OmniLight3D] = []
var _fixture_mats: Array[StandardMaterial3D] = []
## Lamp indices ordered by distance from the generator — the order the wave runs
## in. Computed once at build, because the map never moves.
var _order := PackedInt32Array()
var _powered := false

static var _fixture_tex: GradientTexture2D


## Takes no map argument on purpose. Everything here is derived from
## `MapData.ROOMS`, `MapData.GENSPOT` and `MapData.WALL_H`, all of them
## constants, so a `MapData` instance would be a parameter nothing reads — and
## the one thing that could genuinely use it, ordering the wave by *walked*
## distance from the generator rather than straight-line distance, needs the flow
## field and every door open and is not worth a dependency.
func build() -> void:
	_env = _make_environment()
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = _env
	add_child(we)
	_build_lamps()


## The live `Environment`. `verify.gd` reads the glow threshold through this
## rather than hunting the scene tree for a `WorldEnvironment`, and anything that
## wants to grade the screen (the downed desaturation is the next one) writes
## through it instead of building a second one.
func env() -> Environment:
	return _env


## The materials this node owns, for the shader warm-up pass. Eight rather than
## one: the wave lights the fixtures a room at a time, which needs eight
## independently-writable albedos. They share one texture and one feature set, so
## they are eight uniform sets against a single compiled variant.
func materials() -> Array:
	var out: Array = []
	out.append_array(_fixture_mats)
	return out


## Where room `r`'s lamp hangs. Static because `world_builder` bakes the same
## position into its vertex colours and there must be exactly one statement of
## where a lamp is — a bake that disagrees with the light it is baking reads as a
## smear that no amount of retuning fixes.
static func lamp_position(r: int) -> Vector3:
	var rm: Dictionary = MapData.ROOMS[r]
	var x0: float = rm.x0
	var x1: float = rm.x1
	var y0: float = rm.y0
	var y1: float = rm.y1
	return Vector3((x0 + x1) * 0.5 + 0.5, MapData.WALL_H - LAMP_DROP, (y0 + y1) * 0.5 + 0.5)


static func lamp_range(r: int) -> float:
	var rm: Dictionary = MapData.ROOMS[r]
	var x0: float = rm.x0
	var x1: float = rm.x1
	var y0: float = rm.y0
	var y1: float = rm.y1
	return maxf(x1 - x0, y1 - y0) + LAMP_RANGE_MARGIN


func _make_environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = VOID_COLOR

	# step 1 — ambient down.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = AMBIENT_COLOR
	e.ambient_light_energy = AMBIENT_ENERGY

	# step 2 — fog. Density was already at the mandate; the colour follows it
	# down so it does not start lifting the darks step 1 just deepened.
	e.fog_enabled = true
	e.fog_light_color = FOG_COLOR
	e.fog_density = FOG_DENSITY

	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.88
	# The mandate also asks for contrast 1.20 and Milestone 1 refused it, and that
	# refusal gets *stronger* here rather than weaker: step 1 lowers the black
	# floor, step 7 multiplies it down again, and the vertex bake multiplies a
	# third time. Three new ways to crush the darks is the wrong moment to add a
	# fourth. Left at 1.10 deliberately.
	e.adjustment_contrast = 1.10

	# step 6 — glow, retuned now that steps 1-5 have decided what "bright" means.
	e.glow_enabled = true
	e.glow_intensity = GLOW_INTENSITY
	e.glow_bloom = GLOW_BLOOM
	e.glow_hdr_threshold = GLOW_THRESHOLD

	# steps 7 and 8 — SSAO, then the LUT, in that order and last.
	#
	# Asked once, here, before a single frame has been drawn. Every combination
	# of glow / BCS / SSAO / colour-correction is a separate specialisation of
	# `post.glsl`, and WebGL2 exposes no program-binary API, so flipping one of
	# these mid-session is a full-screen GLSL compile on the main thread with
	# nothing cached to fall back on. Deciding here means the compile lands
	# behind the title screen with the warm-up pass and every other one.
	if QUALITY.heavy_post():
		e.ssao_enabled = true
		e.ssao_intensity = SSAO_INTENSITY
		e.ssao_radius = SSAO_RADIUS
		e.adjustment_color_correction = _grade_lut()
	return e


## The ancestor's `b + 5` (html:1812) as a per-channel tone curve: red and green
## pass through untouched, blue is lifted by 5/255 and rides that lift until it
## would clip, exactly as `Math.min(255, b)` did.
##
## Three gradient stops describe it exactly, because the transform is piecewise
## linear. A `GradientTexture1D` is RGBA8 and un-decoded, so what is written here
## is what the sampler returns.
##
## The one thing that cannot be checked without running it: `post.glsl` samples
## this with the incoming channel value straight as the texture coordinate, so
## input 0.0 lands half a texel outside the image. Clamped, it reads texel 0 and
## is right; wrapped, it reads half of texel 255 and pure black comes back as
## mid-grey. **That is the signature to look for** — if the darks are washed and
## speckled rather than merely wrong in hue, it is the sampler and not the grade,
## and the fix is a 3D LUT (`sampler3D`, no wrap on the diagonal) rather than a
## retune. `--no-post-fx` is the A/B.
##
## One honest overreach: the ancestor applied the lift to walls, floors and
## ceilings only, and this hits sprites and particles too. The alternative is an
## additive channel on seven world materials, which is seven shader variants for
## two thousandths of a unit on a zombie.
static func _grade_lut() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0 - LUT_BLUE_LIFT, 1.0])
	g.colors = PackedColorArray([
		Color(0.0, 0.0, LUT_BLUE_LIFT),
		Color(1.0 - LUT_BLUE_LIFT, 1.0 - LUT_BLUE_LIFT, 1.0),
		Color(1.0, 1.0, 1.0),
	])
	var t := GradientTexture1D.new()
	t.gradient = g
	# One texel per 8-bit input level: the curve is sampled with the incoming
	# channel value as the coordinate, so anything coarser quantises the grade.
	t.width = 256
	return t


func _build_lamps() -> void:
	# step 3 — one shadowless omni per room, at the mandate's energy, held at the
	# pre-power level until the generator is thrown.
	#
	# Exactly one shadow-casting light is affordable on this renderer, and it is
	# the torch: every additional shadowed light re-draws every instance it
	# touches with additive blending, and an omni in cubemap mode needs six
	# shadow renders to a spot's one.
	var mesh := QuadMesh.new()
	mesh.size = Vector2(FIXTURE_SIZE, FIXTURE_SIZE)

	for r in MapData.ROOMS.size():
		var pos := lamp_position(r)

		var l := OmniLight3D.new()
		l.name = "Lamp%d" % r
		l.position = pos
		l.light_color = LAMP_COLOR
		l.light_energy = LAMP_ENERGY_OFF
		l.omni_range = lamp_range(r)
		l.shadow_enabled = false
		add_child(l)
		_lamps.append(l)

		var mat := _fixture_material()
		var mi := MeshInstance3D.new()
		mi.name = "Fixture%d" % r
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = pos
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# Billboarding is a vertex-shader rotation, so the mesh AABB never turns
		# with the geometry: a flat quad's box is zero-thickness on one axis and
		# the corner of the turned quad leaves it. One full span covers the swept
		# circle here, because the quad is centred on its own origin — unlike the
		# zombie eyes, which sit off theirs and need two.
		mi.extra_cull_margin = FIXTURE_SIZE
		add_child(mi)
		_fixture_mats.append(mat)

	_order = _generator_order()
	# Fixtures start matched to the lamps rather than to their own default.
	for i in _lamps.size():
		_set_lamp(LAMP_ENERGY_OFF, i)


func _fixture_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _fixture_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.disable_receive_shadows = true
	# Depth fog runs on unshaded transparents like anything else, and on a light
	# source it is wrong twice: it lays fog grey over a wall the same fog already
	# greyed, and it drags the fixture below GLOW_THRESHOLD with distance, so the
	# lamp stops blooming at exactly the range a beacon exists for. Same call, and
	# the same reasoning, as the zombie eye material.
	m.disable_fog = true
	# The quad is planar and always turned to face the camera, so only one of its
	# two triangles can be front-facing whichever way it is wound. Disabling the
	# cull rasterises nothing extra and takes winding off the list of things that
	# can silently blank the effect.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A baked radial gradient, not a shader — every new `Shader` is a main-thread
## GLSL compile the first time it is drawn, and a texture generated once at
## startup costs one upload and nothing after. Shared across all eight fixtures;
## only the albedo colour differs, and that is a uniform.
##
## White, with the whole falloff in alpha, so the hue comes from the material and
## nothing here depends on whether an RGBA8 texture is decoded as sRGB.
static func _fixture_texture() -> GradientTexture2D:
	if _fixture_tex != null:
		return _fixture_tex
	var g := Gradient.new()
	# A small hot core inside a wide halo: a bare bulb behind a wire cage, not a
	# soft area light. The core is deliberately tighter than the zombie eyes' 0.40
	# because this quad is 0.34 m across rather than a few centimetres, and a
	# broad core at that size blooms into a featureless blob.
	g.offsets = PackedFloat32Array([0.0, 0.22, 0.45, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.72),
		Color(1.0, 1.0, 1.0, 0.22),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_fixture_tex = t
	return t


## Lamp indices sorted by straight-line distance from the generator. Eight
## elements, so this is a selection sort rather than a `sort_custom` — the
## ordering is the point and it should be readable.
##
## The order it produces on the shipped map is Generator Hall, Landing, Tunnel,
## Theatre, Corridor, Alley, Stairwell, Lobby: the wave sweeps out of the room
## you threw the switch in and reaches the room you spawned in last.
func _generator_order() -> PackedInt32Array:
	var d := PackedFloat32Array()
	for r in MapData.ROOMS.size():
		var p := lamp_position(r)
		d.append(Vector2(p.x, p.z).distance_to(MapData.GENSPOT))
	var out := PackedInt32Array()
	var used := PackedByteArray()
	used.resize(d.size())
	for _n in d.size():
		var best := -1
		for i in d.size():
			if used[i] == 1:
				continue
			if best < 0 or d[i] < d[best]:
				best = i
		used[best] = 1
		out.append(best)
	return out


## step 5 — the power-on ceremony.
##
## **The premise this was specified with does not survive the ancestor.**
## `kriegsnacht.html` has no room lamps at all: every lit surface in it comes from
## one player-centred distance table, `litLUT` (html:1695-1702), which does not
## mention `G.power` and does not change when the generator is thrown. All
## `powerOn` does to the lighting is set `G.flash = max(G.flash, 1.2)`
## (html:2786) — a one-off radial brightening around the player that decays at
## 7/s, so about a sixth of a second — and lift metal walls by 26/256
## (html:1801), which `world_builder.set_power_on()` already ports.
##
## So "the lamps were dark before the generator" is not a fidelity restoration.
## The lamps are a port invention to begin with, and starting them at zero would
## be a second invention stacked on the first, in the direction of making the
## first five minutes of every run — the part a stranger sees — navigable by
## torchlight alone, on the same pass that took the ambient down.
##
## The honest option, taken here: the lamps start **dim, not dark**, at the
## energy that reproduces the ancestor's own far-field floor beneath them
## (LAMP_ENERGY_OFF), and the ceremony is a 2.35x lift rather than a
## zero-to-full. The reveal survives — the fixtures cross the glow threshold and
## start blooming, which nothing in the pre-power map does — and the deviation
## from the ancestor stays at one invention rather than two.
##
## Idempotent: the interaction that calls this is removed from the scan once the
## power is on, but a tween chain half-run is a worse failure than a no-op.
func power_on() -> void:
	if _powered:
		return
	_powered = true
	Sfx.play_at("power_on", Vector3(MapData.GENSPOT.x, 1.2, MapData.GENSPOT.y),
		-3.0, 1.0, WHINE_DIST)

	var t := create_tween()
	# Parallel, so every delay below is measured from the start of the ceremony
	# and the schedule reads as the timeline it is.
	t.set_parallel(true)

	for f in FLICKERS:
		var at := float(f) * FLICKER_STEP
		t.tween_callback(_set_all.bind(LAMP_ENERGY_ON * FLICKER_LEVEL)).set_delay(at)
		t.tween_callback(_set_all.bind(LAMP_ENERGY_OFF)).set_delay(at + FLICKER_ON)

	var base := float(FLICKERS) * FLICKER_STEP + FLICKER_SETTLE
	for i in _order.size():
		var li: int = _order[i]
		# `bind` appends, so the callback is `_set_lamp(value, li)`. One tweener
		# per lamp drives the light and its fixture together — two properties that
		# must never disagree about whether a room is lit.
		t.tween_method(_set_lamp.bind(li), LAMP_ENERGY_OFF, LAMP_ENERGY_ON, RAMP) \
			.set_delay(base + float(i) * STAGGER) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_all(k: float) -> void:
	for i in _lamps.size():
		_set_lamp(k, i)


func _set_lamp(k: float, i: int) -> void:
	_lamps[i].light_energy = k
	var m: StandardMaterial3D = _fixture_mats[i]
	var g := FIXTURE_GAIN * k / LAMP_ENERGY_ON
	# Alpha held at 1.0 and the gain put entirely in the colour: on an additive
	# surface alpha scales the contribution too, so scaling both would square the
	# fade and the fixture would vanish long before its lamp did.
	m.albedo_color = Color(LAMP_COLOR.r * g, LAMP_COLOR.g * g, LAMP_COLOR.b * g, 1.0)
