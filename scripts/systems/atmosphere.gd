extends Node3D

## Everything the level *wears*: the muzzle flash, and every billboard prop the
## browser build drew as a sprite — the machines, the chalk plaques, the perk
## markers, the mystery box's own art.
##
## Split out of main.gd, which was the composition root and this layer both. The
## seam is that a system which needs a prop asks for one here rather than growing
## its own loader: the pixel scales, the billboard policy and the alpha cut are one
## table in one file, so a new prop cannot quietly arrive at a different scale.
##
## A Node3D at the origin under main, so every sprite's `position` is still its
## world position — the arithmetic below is unchanged from when main.gd owned it.

## Props reuse the browser build's own art, exported to assets/props/ by
## replaying its canvas drawing code. They are billboards for the same reason
## the zombies are: the original had no 3D geometry for them either.
const PROP_DIR := "res://assets/props/"
const PROP_PX := 0.025          # metres per source pixel
const POWERUP_PX := 0.018
## 1.7 m of drawn machine over 64 source px — html:2092. The generic PROP_PX
## would render it 1.60 m, which is the perk machines' scale, not this one's.
const PAP_PX := 0.0265625

## Chalk wall-buy plaques, drawn from each weapon's own GUNART parts.
##
## The plaque hangs on the wall face, not at the interact point: html:2035 puts
## both at tile centre + face * 0.52, which is 0.02 m proud of the wall plane —
## enough to clear it without reading as a floating panel. Height and lift are the
## ancestor's, from html:2105 `add(CHALK[b.gun], b.x, b.y, 0.72, 1.30)`: 0.72 m of
## plaque with its bottom edge 1.30 m off the floor, under a 2.8 m ceiling.
const CHALK_PX := 0.018         # 0.72 m over 40 source px
const CHALK_LIFT := 1.30        # floor to the plaque's bottom edge
const CHALK_PROUD := 0.52       # tile centre to the drawing plane

## The weapon hovering out of an open mystery box — the reel while it spins and
## the offer once it lands. Same plaque art as a wall buy, drawn smaller and
## lower: html:2099-2102 is `add(CHALK[...], bs.x, bs.y, 0.62, 1.15, {glow:true})`,
## i.e. 0.62 m of plaque with its bottom edge 1.15 m off the floor.
const BOX_SHOW_PX := 0.0155     # 0.62 m over the same 40 source px
const BOX_SHOW_LIFT := 1.15

## The Pack-a-Punch machine mid-cycle. A multiply on the sprite's albedo, NOT a
## light energy and not an sRGB conversion of one — constraint 7. It reads as the
## machine coming alive without adding a second light to the Generator Hall, which
## already carries the only shadow-casting light in the game.
const PAP_WORK_TINT := Color(1.5, 1.18, 0.7)

## THE MUZZLE FLASH IS THREE LAYERS, NOT ONE — html:3144-3170, and the port kept
## only the tint. What shipped was a 0.34 m QuadMesh with an UNTEXTURED additive
## StandardMaterial3D: a flat fill of one colour across a square, which is what a
## player reported as "an obvious yellow square, jarring especially when you ads".
##
## The ancestor draws, all with globalCompositeOperation='lighter' (additive):
##
##   1. a RADIAL GRADIENT out to r*2.4, alpha .95 at 0, .45 at 0.35, 0 at 1
##      (html:3150-3156);
##   2. a SYMMETRIC FOUR-POINT BURST — eight vertices, radii alternating r*0.62
##      and r*0.20, filled rgba(255,248,225,.92), a near-WHITE hot colour and
##      NOT the tint (html:3158-3167);
##   3. a HOT CORE disc at r*0.22, the same near-white (html:3168).
##
## The absent white core is why the whole thing read as one flat mid-yellow: with
## the tint the only colour on screen there is nothing for the eye to read as the
## hot centre of a combustion.
##
## Two quads rather than one texture, because layers 2 and 3 are a different
## COLOUR from layer 1 and `albedo_color` multiplies the whole surface. Baking
## the tint into art would need one texture per entry in MUZZLE_COLOR and would
## move a runtime colour into a build step; two additive quads composite to
## exactly what the ancestor's two fillStyles composite to, for one extra draw
## call on the three frames a flash is alive.
##
## Both textures are WHITE with the whole shape in ALPHA, exactly as lighting.gd's
## lamp fixture is and for the same reason it gives: alpha carries no transfer
## function, so neither texture depends on whether an RGBA8 image is decoded as
## sRGB. See FLASH_HOT for where the colour-space decision actually lands.
const MUZZLE_COLOR := {
	"raygun": Color(0.63, 1.0, 0.35),
	"thundergun": Color(0.59, 0.92, 1.0),
}
## html:3151's third arm, `'255,214,130'`. The shipped `_setup_muzzle` seeded the
## material with Color(1.0, 0.86, 0.55) instead — 219,140, which is not in the
## ancestor and had no provenance — while `_on_fired` overwrote it with the right
## value on the first shot. One constant now, so the warm-up frame and the first
## shot are the same colour.
const MUZZLE_DEFAULT := Color(1.0, 0.84, 0.51)

## html:3158 — `rgba(255,248,225,.92)`, and the .92 lives in the texture's alpha.
##
## ---------------------------------------------------------------------------
## THE COLOUR SPACE, DECIDED WITH A RENDERED FRAME, and it is the OPPOSITE call
## from gunart.gd's on rules that both apply.
##
## CLAUDE.md constraint 6 says a BLEND_ADD surface *is* a light contribution and
## must be converted; gunart.gd says converting an UNSHADED albedo shipped a
## near-black frame. Both are true, and they are about different mechanisms.
## gunart.gd writes per-VERTEX colours, which carry no `source_color` hint and get
## no automatic decode — so its hand conversion was the SECOND one and darkened
## twice. This file writes `albedo_color`, and the question is whether the engine
## decodes THAT. It does, measured rather than assumed.
##
## THE MEASUREMENT. `--frames flash_ads` at 1280x720 with the halo's albedo forced
## to a neutral grey, reading `flash_ring_mean` — the halo's own annulus at 0.72
## to 0.92 of its radius, which is pure gradient with no burst in it:
##
##   halo albedo (display)   ring_mean   over the 1.0 row   sRGB decode of it
##   0.00                     0.01304    —                  (this row is the floor:
##                                                          scene + muzzle light)
##   0.25                     0.02048    0.3221             0.0508
##   0.50                     0.03110    0.4890             0.2140
##   0.75                     0.04524    0.7115             0.5225
##   1.00                     0.06359    1.0000             1.0000
##
## FILMIC compresses and the floor is positive, and BOTH can only push a measured
## ratio ABOVE the true ratio of light. So 0.4890 against 0.500 and 0.7115 against
## 0.750 are impossible if the authored value reached the buffer unconverted,
## while every row sits above its decoded prediction by exactly the margin a tone
## curve puts there. The engine decodes; the conversion the rule demands is
## already made; this file must pass DISPLAY values and must not convert.
##
## AND THE A/B THAT MOTIVATED IT, same captures with `col.srgb_to_linear()` in
## front of both albedos:
##
##                           hip mean   halo ring   halo blue/red
##   passed through (ships)  0.014573   0.05750     0.43701
##   hand-converted          0.013355   0.05072     0.34342
##                           ads mean   halo ring   halo blue/red
##   passed through (ships)  0.013587   0.05284     0.16443
##   hand-converted          0.012242   0.04473     0.09337
##
## -9% of the frame's light, -13% of the halo's, and the halo's blue-over-red falls
## by a fifth at the hip and by nearly half at the sights: it darkens AND goes
## deeper amber, which is the same double-darkening in the same direction that
## gunart.gd records. See notes/perf/frames/README.md.
const FLASH_HOT := Color(1.0, 0.97255, 0.88235)

## html:3148 — `r = cssH*(0.05+Math.random()*0.035)*(cone?2.2:1)`, and the drawn
## disc runs out to `r*2.4` (html:3150), so the HALO's full width on screen is
## 4.8*r: 0.24 to 0.408 of SCREEN HEIGHT, times 2.2 for a cone weapon.
const FLASH_W_MIN := 0.24
const FLASH_W_SPAN := 0.168
## The ancestor's `cone` flag is set on exactly one weapon, `cone:.62` on the
## Thundergun (html:1470); every other entry is `cone:0` (html:1455). The light's
## omni_range already carried this (5.7 / 2.6 = 2.19); the quad never did.
const FLASH_CONE_MULT := 2.2

## The burst quad's half-width, in the ancestor's `r` units. 0.62 is the star's
## own tip radius (html:3163) and the extra 6% is margin so the antialiased tips
## have a texel to fade into instead of being clipped by the texture edge.
const FLASH_BURST_R := 0.66
## ...and as a fraction of the halo quad, whose half-width is r*2.4. Derived
## rather than restated, so the margin above is the only place 0.66 appears.
const FLASH_BURST_FRAC := FLASH_BURST_R / 2.4

## The burst star and the core disc, in units of the burst quad's half-width.
const BURST_TIP := 0.62 / FLASH_BURST_R      # html:3163, `r*0.62`
const BURST_NOTCH := 0.20 / FLASH_BURST_R    # html:3163, `r*0.20`
const BURST_CORE := 0.22 / FLASH_BURST_R     # html:3168, `arc(mx,my,r*0.22)`
const BURST_ALPHA := 0.92                    # html:3158

## 128 texels each, 64 KB each, built once.
##
## The burst is the sharp one and it is the one that sets the number: at the top
## of the size draw it covers 76 screen px on an ordinary weapon and 167 on the
## Thundergun's 2.2x, so 128 never magnifies its points past 1.3x. The halo is a
## smooth radial gradient and could live at 32 like lighting.gd's lamp fixture;
## 128 is what keeps the falloff from banding across the 294 px an ordinary
## weapon's halo covers, and the Thundergun's 646 px is a 5x magnification of a
## gradient, which is what a gradient is for.
const BURST_PX := 128
const HALO_PX := 128

## The port's flash life, and A DELIBERATE DEPARTURE that was never written down.
## The ancestor sets `G.flash = max(G.flash, 1.35)` (html:2524), decays it at 7/s
## (html:3365) and draws while it is above 0.55 (html:3144) — so its flash is
## drawn for (1.35-0.55)/7 = 0.114 s, and 0.236 s for the cone weapons. This is
## less than half that. Left alone: it is the shipped feel, the complaint this
## package answers is about the flash's SHAPE and SIZE, and lengthening it is a
## separate argument with its own before/after. Recorded so the gap is a decision
## rather than a discovery.
const FLASH_TIME := 0.05

## PI * (3 - sqrt(5)), the golden angle, as the burst's per-shot turn. See
## `_on_fired` for why the spin is a counter and not a clock or a draw.
const GOLDEN_ANGLE := 2.39996322972865332

var _player: Player
## viewmodel.gd, for flash_anchor(). Untyped for the same reason main.gd's handle
## is: the script is attached at runtime, so the compiler only knows Node3D.
var _viewmodel: Node3D

var _muzzle_light: OmniLight3D
var _muzzle_quad: MeshInstance3D
var _muzzle_mat: StandardMaterial3D
var _burst_quad: MeshInstance3D
var _burst_mat: StandardMaterial3D
var _muzzle_t := 0.0
## Shots fired since this node was built, and nothing else reads it. The burst's
## orientation, and only that.
var _flash_n := 0

## Built once per process and shared, like lighting.gd's fixture texture: a
## texture generated at startup costs one upload and nothing after, where a
## `Shader` would cost a main-thread GLSL compile the first time it is drawn.
static var _halo_tex: GradientTexture2D = null
static var _burst_tex: ImageTexture = null

var _perk_nodes := {}
var _gen_node: Sprite3D
var _pap_node: Sprite3D
var _box_show: Sprite3D
## What set_box_display() was last asked for, whether or not a plaque existed to
## draw it with. The box's own assertions read this, so a missing texture is
## visible as a gap rather than as silence.
var _box_show_gun := ""


func bind(p: Player, vm: Node3D) -> void:
	_player = p
	_viewmodel = vm
	_setup_muzzle()
	# main.gd used to own this connection, which made it the first listener on
	# `fired`; it is the last one now. Nothing observable moved: neither of the
	# other two listeners draws from an Rng stream (fx.gd is forbidden to, by its
	# own header) and neither writes anything `flash_anchor()` reads — the
	# viewmodel's transform only moves in its own `_process`.
	p.fired.connect(_on_fired)


## One persistent light and two persistent quads, toggled by a timer. Allocating
## a flash per shot would mean fifteen node allocations a second at 880 RPM.
func _setup_muzzle() -> void:
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = MUZZLE_DEFAULT
	_muzzle_light.light_energy = 4.0
	_muzzle_light.omni_range = 2.6
	# Shadowless keeps it free: OMNI_LIGHT_COUNT is a uniform, not a shader
	# define, so toggling this cannot trigger a mid-fight shader recompile.
	_muzzle_light.shadow_enabled = false
	_muzzle_light.visible = false
	add_child(_muzzle_light)

	# ONE unit quad for both layers. The size is in the TRANSFORM now (see
	# `_place_flash`), so a shared 1x1 mesh is the whole geometry of the effect
	# and neither quad can be resized without the other's knowing.
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	_muzzle_mat = _flash_material(MUZZLE_DEFAULT, _halo_texture())
	_muzzle_quad = _flash_quad(quad, _muzzle_mat, "MuzzleHalo")
	_burst_mat = _flash_material(FLASH_HOT, _burst_texture())
	_burst_quad = _flash_quad(quad, _burst_mat, "MuzzleBurst")


## Unshaded, additive, and NOT billboarded — see `_place_flash` for why the
## billboard flag had to go. Everything else is lighting.gd's fixture material,
## which is the one other additive textured quad in the level.
func _flash_material(col: Color, tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = col
	m.albedo_texture = tex
	# No mipmaps. The burst is the sharp layer and it spans 76 to 167 screen px
	# against 128 texels — 0.6x to 1.3x — so a mip chain has nothing to do at the
	# small end and would only soften the star's points at the large one. LINEAR,
	# like lighting.gd's fixture, which is the same bargain on the same kind of
	# surface.
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.disable_receive_shadows = true
	# Depth fog on a light source lays fog grey over the thing making the light —
	# lighting.gd's fixture material gives the whole argument.
	m.disable_fog = true
	# The quad is planar and turned to face the camera, so only one of its two
	# triangles can be front-facing whichever way it is wound. Same call, and the
	# same reasoning, as the lamp fixture.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# THE FLASH IS DRAWN OVER THE WEAPON, WHICH IS WHERE THE ANCESTOR DRAWS IT.
	# html:3142 blits the gun and html:3144-3170 draws the flash after it, inside
	# the same save()/restore() — the burst and the hot core land ON the barrel,
	# not behind it. Here the weapon is opaque geometry and the flash is a
	# transparent at flash_anchor()'s 0.35 m, which is a FAKE depth: the anchor
	# undoes the viewmodel's narrower projection to get the screen position right
	# and has no way to also be in front of a gun drawn through a different
	# frustum. MEASURED without this flag, `--frames flash_ads`: the M1911's slide
	# covered the whole burst and the whole core, and the core probe read
	# core/ring 2.518 with a blue-over-red of 1.430 — it was measuring the slide's
	# blue-grey, not the flash. At the hip it was worse: core/ring 0.592, a hot
	# core DIMMER than the halo around it. Nothing is ever nearer than 0.35 m from
	# the eye but the weapon, and the HUD is a CanvasLayer and composites later.
	m.no_depth_test = true
	return m


func _flash_quad(mesh: QuadMesh, mat: StandardMaterial3D, n: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visible = false
	add_child(mi)
	return mi


func _on_fired(at: Vector3) -> void:
	var key: String = _player.current_gun().key
	var col: Color = MUZZLE_COLOR.get(key, MUZZLE_DEFAULT)
	var cone: bool = key == "thundergun"
	var cam: Camera3D = _player.camera()
	var dist: float = at.distance_to(cam.global_position)
	# The weapon is drawn through a narrowed projection (viewmodel.gd), so a flash
	# placed on the same ray as the barrel does NOT land on the barrel on screen —
	# the viewmodel's screen offset is the world's scaled by
	# tan(74/2)/tan(55/2) = 1.4476. And a 0.34 m quad at the barrel's actual 0.18 m
	# would subtend more than the whole frame. flash_anchor() is the point that
	# satisfies both: same screen position, survivable distance. It returns a point
	# at exactly `dist` along the camera's own axis, which is what `flash_size`
	# below needs for its depth.
	var flash_at: Vector3 = _viewmodel.flash_anchor(dist)
	_muzzle_light.light_color = col
	_muzzle_light.omni_range = 5.7 if cone else 2.6
	_muzzle_light.global_position = flash_at
	_muzzle_light.visible = true

	# html:3148, a fresh size every shot. THIS DRAW REPLACED THE ROLL THE SHIPPED
	# code spent on `rotation.z`, which the billboard threw away (`_place_flash`),
	# so the VISUAL stream advances by the same one draw per shot it always has and
	# `_launch`'s spread — which is drawn from VISUAL immediately after `fired` is
	# emitted, player.gd:939-940 — still lands on the same numbers.
	var u: float = Rng.randf(Rng.VISUAL)
	var halo: float = flash_size(flash_frac(u, cone), dist, cam.fov)
	# html:3159's `spin = (G.t*7)%TAU` is a CLOCK, and this is a per-shot advance
	# instead: A DELIBERATE DEPARTURE, twice over.
	#
	# The ancestor redraws the burst every frame of its 0.114 s life so the star
	# visibly turns; ours is placed once and lives 0.05 s, so all its spin can buy
	# is a different orientation from the last shot's. A wall clock would buy that
	# too — and would make every screenshot of this effect depend on when the
	# shutter fired, which is the class of non-determinism shot_setup.gd spends
	# forty lines apologising for. A second `Rng.randf` would buy it as well, and
	# would advance VISUAL one draw further per shot than the shipped code did,
	# which moves `_launch`'s spread (drawn from VISUAL immediately after `fired`
	# is emitted — player.gd:939-940) and with it every sim baseline. The golden
	# angle costs neither: successive shots land 137.5 degrees apart, which on a
	# shape with four-fold symmetry is as far from the last one as an orientation
	# can be, and it never repeats.
	_flash_n += 1
	var spin: float = fposmod(float(_flash_n) * GOLDEN_ANGLE, TAU)
	_muzzle_mat.albedo_color = col
	_place_flash(_muzzle_quad, cam, flash_at, halo, spin)
	_place_flash(_burst_quad, cam, flash_at, halo * FLASH_BURST_FRAC, spin)
	_muzzle_t = FLASH_TIME


## The halo's width as a fraction of SCREEN HEIGHT, for a size roll of `u` in
## [0, 1). Its own function so the suite can drive the real one headlessly — the
## windowed gate photographs one roll per capture and could never see the range.
static func flash_frac(u: float, cone: bool) -> float:
	return (FLASH_W_MIN + FLASH_W_SPAN * u) * (FLASH_CONE_MULT if cone else 1.0)


## A SCREEN FRACTION, not a world size, AND THAT IS THE FIX THE COMPLAINT ASKED
## FOR. The ancestor's `r` is a fraction of cssH and never changes with anything;
## ours is a world quad at `flash_anchor`'s depth, whose screen size therefore
## scales as 1/tan(fov/2) — while the weapon it is stuck to does NOT, because
## viewmodel.gd redraws the gun through its own fixed 55-degree projection.
##
## MEASURED on the shipped build: the 0.34 m quad at 0.35 m subtends
## 0.34 / (2 * 0.35 * tan(37)) = 64% of the frame height at the hip and 92% at the
## sights (74 * ADS_FOV_MULT 0.75 = 55.5 degrees) — a solid additive square nearly
## as tall as the screen, growing by 1.43x on a weapon that did not move. Undoing
## the projection here is both the bug fix and the ancestor's own specification.
##
## `distance` is a DEPTH along the camera axis, which is what flash_anchor()
## returns; `fov_deg` is Camera3D.fov, vertical under the default KEEP_HEIGHT.
static func flash_size(frac: float, distance: float, fov_deg: float) -> float:
	return frac * 2.0 * distance * tan(0.5 * deg_to_rad(fov_deg))


## THE BILLBOARD FLAG CANNOT CARRY THE SPIN, and that is why it is gone.
##
## `BILLBOARD_ENABLED` replaces MODELVIEW_MATRIX's whole basis with the camera's
## in the vertex shader, so a `rotation.z` written on the node is discarded before
## anything is drawn. CONTROLLED 2026-07-31 against the SHIPPED file out of git,
## `--frames flash_hip` and `--frames flash_ads` captured with the roll pinned to
## 0.0 and to TAU/8 and nothing else changed: both pairs of PNGs came back BYTE
## IDENTICAL (sha256 b51229d63e4b79c8… and 24ad5033bb9043e8…, 294177 and 242157
## bytes). The brief for this package read the same symptom — "the per-shot
## rotation.z spins a uniform square, which is why the randomisation reads as
## nothing" — as the square being featureless; a featureless square was only half
## of it, and the roll had never reached the GPU at all.
##
## So the quad is oriented here instead: the camera's basis (which is what the
## billboard would have written) turned about its own view axis by `spin`, with
## the size scaled into the two in-plane columns. The mesh AABB now describes the
## drawn geometry, which the billboard's never did — lighting.gd:454-459 pays
## `extra_cull_margin` for exactly that, and this does not have to.
func _place_flash(q: MeshInstance3D, cam: Camera3D, at: Vector3,
		size: float, spin: float) -> void:
	var b := cam.global_transform.basis * Basis(Vector3(0.0, 0.0, 1.0), spin)
	b.x *= size
	b.y *= size
	q.global_transform = Transform3D(b, at)
	q.visible = true


## The flash is the only thing in this file with a clock, and it is the reason
## this node processes at all. Pausable like the rest of the world: a 50 ms flash
## frozen behind the pause overlay is the same frozen frame everything else is.
func _process(dt: float) -> void:
	if _muzzle_t <= 0.0:
		return
	_muzzle_t -= dt
	if _muzzle_t <= 0.0:
		_muzzle_light.visible = false
		_muzzle_quad.visible = false
		_burst_quad.visible = false


## Is a flash up right now? The `flash_hip` / `flash_ads` capture scenarios wait
## on this rather than on a frame count, because a 0.05 s effect cannot be caught
## by a settle budget — see scripts/dev/shot_setup.gd.
func flash_visible() -> bool:
	return _muzzle_t > 0.0


## The halo quad, for the capture probes. The LIVE node, so a probe measures the
## transform and the mesh the renderer was handed rather than a reconstruction of
## them: a flash that stopped being resized moves the probe.
func flash_quad() -> MeshInstance3D:
	return _muzzle_quad


## The burst quad, and it exists because NOTHING ASSERTED THIS LAYER WAS DRAWN.
## Measured 2026-07-31, reviewing this package: with the `_place_flash` call for
## the burst replaced by `_burst_quad.visible = false` — the ancestor's layers 2
## and 3 gone, the white hot core with them — `--verify` ran 580 green and the
## frame gate failed NO relation. The art was covered (`burst_image()` is driven
## by checks/frame.gd), the material was covered (`materials()` returns both), and
## the one thing between them, whether the layer ever reaches the screen, was
## covered by nothing. checks/frame.gd's `_flash_drawn` reads this.
func burst_quad() -> MeshInstance3D:
	return _burst_quad


## The materials this file owns, for the warm-up pass. Same shape as
## fx.materials(), lighting.materials() and world.materials(), so main.gd can hand
## the pass every material in the game without knowing where any of them came from.
## BOTH layers, or the first shot of a match compiles the burst's variant
## mid-fight.
func materials() -> Array:
	return [_muzzle_mat, _burst_mat]


# --- the flash's art ----------------------------------------------------------

## Layer 1, html:3150-3156: `createRadialGradient(mx,my,0, mx,my,r*2.4)` with
## alpha stops .95 at 0, .45 at 0.35 and 0 at 1.
##
## FILL_RADIAL from the centre to the edge MIDPOINT, so gradient t = 1 lands
## exactly on the quad's inscribed circle and the quad's half-width IS the
## ancestor's r*2.4. The corners sit at t = 1.414 and clamp to the last stop,
## which is alpha 0 — an additive surface contributing nothing, which is what
## makes the flash a disc and not a square.
static func _halo_texture() -> GradientTexture2D:
	if _halo_tex != null:
		return _halo_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.95),
		Color(1.0, 1.0, 1.0, 0.45),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = HALO_PX
	t.height = HALO_PX
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_halo_tex = t
	return t


static func _burst_texture() -> ImageTexture:
	if _burst_tex != null:
		return _burst_tex
	_burst_tex = ImageTexture.create_from_image(burst_image())
	return _burst_tex


## Layers 2 and 3, html:3158-3168: the symmetric four-point burst and the hot
## core, as one alpha mask.
##
## SEPARATE FROM THE TEXTURE SO THE SUITE CAN ASSERT THE SHAPE. `--verify` is
## headless and cannot render, so without this the difference between a
## four-pointed star and a disc — or a flat fill — would be visible only to a
## person opening a PNG, which is the hole that let a sight line ship 64 px high.
## checks/frame.gd drives this function, not a copy of its maths.
##
## The star's boundary radius along a ray is solved rather than rasterised: with
## vertices every TAU/8 alternating BURST_TIP and BURST_NOTCH, the edge between
## the polar points (Ra, 0) and (Rb, d) crosses the ray at angle q at
## `Ra*Rb*sin(d) / (Ra*sin(q) + Rb*sin(d-q))`, which is exact at both ends. One
## quarter turn is folded onto one eighth because the shape is its own mirror
## about every vertex.
##
## `+ core` and not `max(star, core)`: the ancestor draws the two with 'lighter'
## at .92 each, so where they overlap the canvas accumulates 1.84 and clips. Ours
## clips to alpha 1.0 against a near-white albedo, so the innermost 33% of the
## burst reads (255,248,225) where the ancestor's reads (255,255,255) — 12% of
## one channel over a ninth of the flash's area, and the alternative is a second
## material for it.
static func burst_image() -> Image:
	var n := BURST_PX
	var data := PackedByteArray()
	data.resize(n * n * 4)
	# One texel, in the [-1, 1] span the radii above are measured in. The edge
	# tests below are a half-texel ramp, which is the antialiasing a canvas fill
	# gets for free and a nearest-neighbour rasteriser does not.
	var texel := 2.0 / float(n)
	var d := TAU / 8.0
	var i := 0
	for py in n:
		var y := (float(py) + 0.5) * texel - 1.0
		for px in n:
			var x := (float(px) + 0.5) * texel - 1.0
			var rho := sqrt(x * x + y * y)
			var q := fposmod(atan2(y, x), TAU * 0.25)
			if q > d:
				q = TAU * 0.25 - q
			var edge := BURST_TIP * BURST_NOTCH * sin(d) / (
				BURST_TIP * sin(q) + BURST_NOTCH * sin(d - q))
			var star := clampf(0.5 + (edge - rho) / texel, 0.0, 1.0)
			var core := clampf(0.5 + (BURST_CORE - rho) / texel, 0.0, 1.0)
			data[i] = 255
			data[i + 1] = 255
			data[i + 2] = 255
			data[i + 3] = int(roundf(minf(1.0, BURST_ALPHA * (star + core)) * 255.0))
			i += 4
	return Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)


# --- props -------------------------------------------------------------------

func _sprite(tex: String, px: float, pos: Vector2, sprite_name: String) -> Sprite3D:
	var s := Sprite3D.new()
	s.name = sprite_name
	s.texture = load(PROP_DIR + tex + ".png")
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.alpha_scissor_threshold = 0.35
	# Sprite origin is its centre, so lift it half its own height off the floor.
	s.position = Vector3(pos.x, s.texture.get_height() * px * 0.5, pos.y)
	add_child(s)
	return s


## A floor-standing machine at the shared prop scale — the mystery box.
func prop_sprite(tex: String, pos: Vector2, sprite_name: String) -> Sprite3D:
	return _sprite(tex, PROP_PX, pos, sprite_name)


## A dropped power-up. Its own scale, and the only prop that is a full billboard:
## drops hover and glow so they read across a dark room.
func powerup_sprite(tex: String, pos: Vector2, sprite_name: String) -> Sprite3D:
	var s := _sprite(tex, POWERUP_PX, pos, sprite_name)
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return s


func spawn_chalk(gun: String, tile: Array, face: Array) -> void:
	var s := Sprite3D.new()
	s.name = "Chalk_" + gun
	s.texture = load(PROP_DIR + "chalk_" + gun + ".png")
	s.pixel_size = CHALK_PX
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = true
	# Not a billboard: it is painted on a specific wall, and turning to face the
	# player would break the illusion the moment you walked past it.
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# The plaque's own ground is rgba(12,14,11,.74) across all 52x40 px
	# (html:1247), so every pixel clears a 0.35 scissor and ALPHA_CUT_DISCARD would
	# render it as an opaque slab. Blend it, so the wall reads through at 26% the
	# way the raycaster composited it.
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	var px: float = float(tile[0]) + 0.5 + float(face[0]) * CHALK_PROUD
	var pz: float = float(tile[1]) + 0.5 + float(face[1]) * CHALK_PROUD
	s.position = Vector3(px, CHALK_LIFT + s.texture.get_height() * CHALK_PX * 0.5, pz)
	# A Sprite3D's quad normal is local +Z, and rotating by this angle sends +Z to
	# (face[0], 0, face[1]) — out of the wall, into the room.
	s.rotation.y = atan2(float(face[0]), float(face[1]))
	add_child(s)


func spawn_perk_marker(ps: Dictionary) -> void:
	_perk_nodes[ps.k] = _sprite("perk_%s_off" % ps.k, PROP_PX,
		Vector2(ps.x, ps.y), "Perk_" + ps.k)


func spawn_generator() -> void:
	_gen_node = _sprite("gen_off", PROP_PX, MapData.GENSPOT, "Generator")


## The machine had no art at all until Milestone 2, and the reason turns out to be
## an extraction bug rather than an art decision: makePaP is at html:1986-2012,
## seven hundred lines outside the range the original export pass replayed.
func spawn_pap() -> void:
	_pap_node = _sprite("pap_off", PAP_PX, MapData.PAPSPOT, "PackAPunch")


## The reel, and the weapon the box holds out at the end of it.
##
## One persistent sprite whose texture is swapped, for the same reason the muzzle
## flash is one persistent light: a spin swaps the displayed weapon up to fifteen
## times in 2.9 s (html:2823), and a node per swap is fifteen allocations for one
## animation. Pass an empty key to put it away.
func set_box_display(gun: String, pos: Vector2) -> void:
	_box_show_gun = gun
	if gun.is_empty():
		if _box_show != null and is_instance_valid(_box_show):
			_box_show.visible = false
		return
	# tools/gen emits a plaque per WALL BUY and one for the Bowie (targets.js:119-131);
	# the ancestor also emits one per BOX_POOL entry it has not already covered
	# (html:3436). Until that gap is closed, four of the eleven box weapons have no
	# plaque — and `load()` on a missing path is an error spew *per swap*, fifteen
	# times a spin, rather than one blank frame.
	var path := PROP_DIR + "chalk_" + gun + ".png"
	if not ResourceLoader.exists(path):
		if _box_show != null and is_instance_valid(_box_show):
			_box_show.visible = false
		return
	if _box_show == null or not is_instance_valid(_box_show):
		_box_show = Sprite3D.new()
		_box_show.name = "BoxDisplay"
		_box_show.pixel_size = BOX_SHOW_PX
		_box_show.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_box_show.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		# Unshaded, unlike every other prop here. It hovers in the air out of the
		# lid with no surface to catch the torch, and the ancestor draws it with
		# `{glow:true}`. Unshaded is what reproduces "readable across a dark room"
		# without pushing an albedo past 1.0 and calling it emission — constraint 7.
		_box_show.shaded = false
		_box_show.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		add_child(_box_show)
	_box_show.texture = load(path)
	_box_show.position = Vector3(pos.x,
		BOX_SHOW_LIFT + _box_show.texture.get_height() * BOX_SHOW_PX * 0.5, pos.y)
	_box_show.visible = true


## The Pack-a-Punch mid-cycle, 0 at rest and 1 working.
##
## `light_perks()` owns this node's TEXTURE and this owns its MODULATE, so the
## power ceremony and the machine's own clock are never two writers of one value.
func pap_glow(amount: float) -> void:
	if _pap_node == null or not is_instance_valid(_pap_node):
		return
	_pap_node.modulate = Color.WHITE.lerp(PAP_WORK_TINT, clampf(amount, 0.0, 1.0))


## The machines only light up once the generator is thrown.
func light_perks() -> void:
	for k in _perk_nodes:
		var s: Sprite3D = _perk_nodes[k]
		if is_instance_valid(s):
			s.texture = load(PROP_DIR + "perk_%s_on.png" % k)
	if _gen_node and is_instance_valid(_gen_node):
		_gen_node.texture = load(PROP_DIR + "gen_on.png")
	# The machine is gated on power in the ancestor too — html:2092 tests G.power.
	if _pap_node and is_instance_valid(_pap_node):
		_pap_node.texture = load(PROP_DIR + "pap_on.png")
