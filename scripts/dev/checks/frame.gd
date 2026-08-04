extends RefCounted

## The half of the rendered-frame gate that can run without a rendering device.
##
## ---------------------------------------------------------------------------
## THE BOUNDARY, stated plainly, because a fake version of this would be worse
## than an honest gap.
##
## `--verify` runs `--headless`. There is no rendering device, so
## `RenderingServer.frame_post_draw` never fires and NOTHING HERE RENDERS A
## FRAME. Not one assertion below looks at the game's pixels. What they cover is
## everything around the pixels:
##
##   - the statistics maths, against synthetic images with hand-computed answers,
##     including the one that pins the colour-space decision;
##   - the tolerance arithmetic and the comparator, bounded at BOTH ends — the
##     drift that must fail and the identity that must pass;
##   - the committed relation bounds, re-run against the MEASURED numbers from
##     the shipped rim defect, so the gate's own bounds are a regression test;
##   - the scenario registry being complete and every entry callable;
##   - the golden file existing, parsing, and carrying a row for every registered
##     scenario, with a reference PNG beside it.
##
## The last of those is a CROSS-HALF assertion in the audit's §5 sense: it fails
## until somebody has actually run the windowed pass and blessed the result. A
## scenario added here and never photographed shows up as a red assertion rather
## than as silence.
##
## What is NOT covered and must not be claimed: whether a scenario puts the world
## into the state its name says, and whether the frame it produces is correct.
## Both need `pwsh tools/frames.ps1`, which is windowed, which build.ps1 runs, and
## which fails loudly rather than skipping when a window cannot be opened.
##
## NOTHING BELOW IS A SOFT SKIP. Every check either asserts or fails; there is no
## `v.check("...", true, "not available headless")` in this file, because one such
## check passed for an entire wave while testing nothing (audit §3).

const FRAME_STATS := preload("res://scripts/dev/frame_stats.gd")
const SHOT_SETUP := preload("res://scripts/dev/shot_setup.gd")
## The reader, the comparator and the departure register for `kriegsnacht.html`'s own
## weapon table. It lives one level up rather than in `checks/` because this file
## cannot be parse-gated at all — see `_gun_ancestor` at the foot of the file.
const ANCESTOR_ART := preload("res://scripts/dev/ancestor_art.gd")
const ATMOSPHERE := preload("res://scripts/systems/atmosphere.gd")
const GUNART := preload("res://scripts/data/gunart.gd")
const LIGHTING := preload("res://scripts/world/lighting.gd")

## The scenarios the package was commissioned to cover, restated here from the
## brief rather than read back out of the registry. A registry checked against
## itself proves nothing — that is the tautology verify.gd's `_registered()` was
## written to avoid — so this list is the independent statement of the
## requirement and the registry is the thing under test.
const REQUIRED := ["spawn", "power", "trap_armed", "ads", "downed", "horde", "raygun",
	"flash_hip", "flash_ads"]

## MEASURED, not assumed: `Image.fill(Color(0.5,...))` on FORMAT_RGBA8 stores
## **127**, not 128 — 0.5*255 is 127.5 and Godot takes it down. Asserting against
## 128/255 failed five checks here by 1.7%, which is exactly the size of drift the
## gate is tuned to notice, so every expectation below reads the byte back out of
## the image rather than assuming what went in.
static func _stored(img: Image) -> float:
	return FRAME_STATS.luma(img.get_pixel(0, 0))


static func run(v: Verify, main: Node3D) -> void:
	_transfer(v)
	_statistics(v)
	_masks(v)
	_silhouette(v)
	_tolerance(v)
	_comparator(v)
	_relations(v)
	_registry(v)
	_golden(v)
	_flash_geometry(v)
	_flash_art(v, main)
	_flash_drawn(v, main)
	_gun_depth(v)
	_gun_bands(v)
	_gun_shade(v)
	_gun_sights(v)
	_gun_ancestor(v)


# --- part 1: the transfer functions -------------------------------------------

## The colour space is the whole reason this package exists — both shipped black
## frames were a display-space value used as a linear one — so the EOTF is
## asserted against published constants rather than against itself.
static func _transfer(v: Verify) -> void:
	# IEC 61966-2-1. 0.5 display encodes 0.21404 linear; this is the single most
	# quoted number in the standard and the one worth pinning.
	v.check("the sRGB EOTF matches the standard at 0.5",
		v.near(FRAME_STATS.srgb_to_linear(0.5), 0.214041, 0.00001),
		"got %.6f" % FRAME_STATS.srgb_to_linear(0.5))
	v.check("the sRGB EOTF is exact at both ends",
		v.near(FRAME_STATS.srgb_to_linear(0.0), 0.0, 1e-9)
			and v.near(FRAME_STATS.srgb_to_linear(1.0), 1.0, 1e-9))
	# The linear segment below 0.04045 — the part a pure 2.2 gamma gets wrong, and
	# the part every frame of this game lives in.
	v.check("the sRGB EOTF uses the linear toe below 0.04045",
		v.near(FRAME_STATS.srgb_to_linear(0.02), 0.02 / 12.92, 1e-9),
		"got %.8f" % FRAME_STATS.srgb_to_linear(0.02))
	var round_trip := true
	for i in 21:
		var u := float(i) / 20.0
		if not v.near(FRAME_STATS.linear_to_srgb(FRAME_STATS.srgb_to_linear(u)), u, 1e-6):
			round_trip = false
	v.check("encode(decode(x)) is the identity across the range", round_trip)

	# Rec.709 weights, one channel at a time. A luma that used Rec.601 or the
	# unweighted mean would pass every other check in this file.
	v.check("luma uses the Rec.709 weights",
		v.near(FRAME_STATS.luma(Color(1, 0, 0)), 0.2126, 1e-6)
			and v.near(FRAME_STATS.luma(Color(0, 1, 0)), 0.7152, 1e-6)
			and v.near(FRAME_STATS.luma(Color(0, 0, 1)), 0.0722, 1e-6))
	v.check("luma decodes before it weights",
		v.near(FRAME_STATS.luma(Color(0.5, 0.5, 0.5)), 0.214041, 0.00001),
		"got %.6f" % FRAME_STATS.luma(Color(0.5, 0.5, 0.5)))
	v.check("code() reports a linear luminance as its display value",
		v.near(FRAME_STATS.code(0.214041), 127.5, 0.5),
		"got %.2f" % FRAME_STATS.code(0.214041))


# --- part 2: the whole-frame statistics ---------------------------------------

static func _solid(c: Color, w := 64, h := 64) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


static func _statistics(v: Verify) -> void:
	var black := FRAME_STATS.of(_solid(Color(0, 0, 0)))
	v.check("a black frame reads as entirely black",
		v.near(black["mean"], 0.0, 1e-9) and v.near(black["median"], 0.0, 1e-9)
			and v.near(black["black"], 1.0, 1e-9) and v.near(black["blown"], 0.0, 1e-9),
		str(black))

	var white := FRAME_STATS.of(_solid(Color(1, 1, 1)))
	v.check("a white frame reads as entirely blown",
		v.near(white["mean"], 1.0, 1e-6) and v.near(white["blown"], 1.0, 1e-9)
			and v.near(white["black"], 0.0, 1e-9),
		str(white))

	var grey_img := _solid(Color(0.5, 0.5, 0.5))
	var grey := FRAME_STATS.of(grey_img)
	var want := _stored(grey_img)
	v.check("a flat frame's mean, median and every region agree",
		v.near(grey["mean"], want, 1e-6) and v.near(grey["median"], want, 1e-6),
		"mean=%.6f median=%.6f want=%.6f" % [grey["mean"], grey["median"], want])
	var flat := true
	var regions: PackedFloat32Array = grey["regions"]
	for r in regions.size():
		if not v.near(regions[r], want, 1e-6):
			flat = false
	v.check("the region grid is %dx%d and flat on a flat frame" % [
		FRAME_STATS.GRID, FRAME_STATS.GRID],
		regions.size() == FRAME_STATS.GRID * FRAME_STATS.GRID and flat,
		"cells=%d" % regions.size())

	# THE ASSERTION THAT PINS THE COLOUR SPACE, and the reason it is not
	# arithmetic trivia: half black and half mid-grey has a LINEAR mean of
	# 0.10702 and an ENCODED mean of 0.25098. Both are plausible-looking
	# numbers; only one of them is a mean over light, and a gate built on the
	# other would compress exactly the dark range where both shipped black
	# frames lived. If this ever fails, the statistics changed space.
	var split := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	split.fill(Color(0, 0, 0))
	split.fill_rect(Rect2i(0, 0, 64, 32), Color(0.5, 0.5, 0.5))
	var s := FRAME_STATS.of(split)
	var linear_answer := 0.5 * want
	var encoded_answer := 0.5 * split.get_pixel(0, 0).r
	v.check("the mean is a mean over LIGHT, not over encoded bytes",
		v.near(s["mean"], linear_answer, 1e-6)
			and not v.near(s["mean"], encoded_answer, 0.01),
		"got %.6f, linear=%.6f encoded=%.6f" % [
			s["mean"], linear_answer, encoded_answer])
	v.check("the black fraction counts only what is below the black code",
		v.near(s["black"], 0.5, 1e-6), "got %.6f" % s["black"])

	# The median is the order statistic and not the mean: a 3:1 split has to
	# report the majority value, which the mean never would.
	var lop := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	lop.fill(Color(0.5, 0.5, 0.5))
	lop.fill_rect(Rect2i(0, 0, 64, 16), Color(1, 1, 1))
	var l := FRAME_STATS.of(lop)
	v.check("the median is an order statistic and survives a bright quarter",
		v.near(l["median"], want, 1e-6) and l["mean"] > want,
		"median=%.6f mean=%.6f want=%.6f" % [l["median"], l["mean"], want])
	v.check("p99 sees the bright quarter and p01 does not",
		v.near(l["p99"], 1.0, 1e-6) and v.near(l["p01"], want, 1e-6),
		"p01=%.6f p99=%.6f" % [l["p01"], l["p99"]])

	# The region grid must actually localise. One bright cell in the top-left
	# must move cell (0,0) and leave (3,3) alone — a grid that averaged the whole
	# frame into every cell would pass everything above.
	var corner := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	corner.fill(Color(0, 0, 0))
	corner.fill_rect(Rect2i(0, 0, 16, 16), Color(1, 1, 1))
	var c := FRAME_STATS.of(corner)
	var cr: PackedFloat32Array = c["regions"]
	v.check("a bright top-left cell moves region 0,0 and nothing else",
		v.near(cr[0], 1.0, 1e-6) and v.near(cr[15], 0.0, 1e-9) and v.near(cr[3], 0.0, 1e-9),
		"c0=%.6f c3=%.6f c15=%.6f" % [cr[0], cr[3], cr[15]])

	_chroma(v)


# --- part 2b: chromaticity -----------------------------------------------------

## The statistic added because the luminance-only gate could not see a hue change:
## a room whose colour temperature inverted passed all ten relations. These pin
## the arithmetic; the committed BANDS are exercised in `_relations` below against
## the measured LAMP_COLOR sweep.
static func _chroma(v: Verify) -> void:
	# Deliberately not a neutral colour: a bug that returned 1.0, or that swapped
	# the numerator and denominator, or that never decoded, all read as "correct"
	# on grey.
	var tint := _solid(Color(0.5, 0.25, 0.75))
	var px := tint.get_pixel(0, 0)
	var lr := FRAME_STATS.srgb_to_linear(px.r)
	var lg := FRAME_STATS.srgb_to_linear(px.g)
	var lb := FRAME_STATS.srgb_to_linear(px.b)
	var s := FRAME_STATS.of(tint)
	v.check("chromaticity is red-over-green and blue-over-green, green-normalised",
		v.near(s["chroma_rg"], lr / lg, 1e-5) and v.near(s["chroma_bg"], lb / lg, 1e-5),
		"rg=%.5f want %.5f  bg=%.5f want %.5f" % [
			s["chroma_rg"], lr / lg, s["chroma_bg"], lb / lg])

	# THE COLOUR-SPACE PIN, the same one the mean carries. Encoded, this pixel's
	# r/g is about 2.0; in light it is about 4.2. A chromaticity computed over
	# stored bytes would be plausible-looking and wrong, and it is the exact
	# confusion that shipped both black frames.
	var encoded_rg := px.r / px.g
	v.check("chromaticity is a ratio of LIGHT, not of encoded bytes",
		not v.near(s["chroma_rg"], encoded_rg, 0.2),
		"got %.5f, encoded would be %.5f" % [s["chroma_rg"], encoded_rg])

	# CRUSHED BLACK MUST NOT VOTE. 72% of the spawn frame sits at or below display
	# code 8; if those pixels entered the sums, every chromaticity would be dragged
	# toward whatever the quantisation floor happens to be and the statistic would
	# measure the dither rather than the light. Half the frame crushed must leave
	# the chromaticity of the other half untouched.
	#
	# **THE DARK HALF IS NEAR-BLACK AND NOT BLACK, AND THAT IS THE WHOLE CHECK.**
	# It used to be `Color(0, 0, 0)`, and CONTROLLED 2026-07-31 that version
	# discriminated nothing: with the exclusion deleted — `csum_r/g/b` accumulated
	# inside the `l <= black_lin` branch as well — the suite still ran
	# `=== 560 passed, 0 failed ===`. A pure black pixel contributes (0, 0, 0) to
	# the channel sums, so including it is arithmetically a no-op and the fixture
	# could not tell the two implementations apart. That is the audit's §1 shape
	# exactly: a passing test named for a behaviour it never exercised.
	#
	# Real crushed black is not zero, it is the quantisation floor — a near-neutral
	# few display codes of dither — which is precisely why its chromaticity is
	# meaningless and why it has to be kept out. Display code 6 grey is below the
	# 8/255 floor and contributes a NEUTRAL (rg = bg = 1.0) vote, so admitting it
	# drags the 4.27 measured above toward 1.0. Measured with the exclusion
	# deleted: chroma_rg 4.26967 -> 4.15, a 2.7% move against a 1e-6 window.
	var half := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	half.fill(Color(0.5, 0.25, 0.75))
	half.fill_rect(Rect2i(0, 32, 64, 32), Color(6.0 / 255.0, 6.0 / 255.0, 6.0 / 255.0))
	var h := FRAME_STATS.of(half)
	# Bounded at the other end, and both halves are load-bearing. `> 0` is what
	# stops this quietly reverting to the no-op fixture above if the fill ever
	# rounds to zero; `black == 0.5` is what stops it passing because the dark half
	# was never crushed in the first place, which would make the exclusion moot for
	# a different reason.
	var dark_px := half.get_pixel(0, 63)
	v.check("crushed black is excluded from the chromaticity",
		dark_px.r > 0.0 and v.near(h["black"], 0.5, 1e-6)
			and v.near(h["chroma_rg"], s["chroma_rg"], 1e-6)
			and v.near(h["chroma_bg"], s["chroma_bg"], 1e-6),
		"dark half stored %.4f (must be > 0 and below the black code)  rg=%.5f vs %.5f  black=%.4f" % [
			dark_px.r, h["chroma_rg"], s["chroma_rg"], h["black"]])

	# ...and a frame with nothing lit at all must say so rather than divide 0 by 0
	# and read as perfectly neutral, which is the empty-mask failure again.
	var dark := FRAME_STATS.of(_solid(Color(0, 0, 0)))
	v.check("a frame with no lit pixel reports -1 chromaticity, not 0/0",
		dark["chroma_rg"] < 0.0 and dark["chroma_bg"] < 0.0,
		"rg=%.5f bg=%.5f" % [dark["chroma_rg"], dark["chroma_bg"]])

	_scale_invariance(v, tint, s)


## `Color(c.r * k, c.g * k, c.b * k)` on a Color destined for a FORMAT_RGBA8 fill
## scales the DISPLAY CODE VALUES, and that is not a uniform scale of the light.
## This builds the image whose LIGHT is `k` times the source's, by decoding the
## bytes the source actually stored, scaling, and re-encoding through the same two
## transfer functions the statistic uses.
static func _lit_by(src: Image, k: float) -> Image:
	var px := src.get_pixel(0, 0)
	var out := Image.create_empty(src.get_width(), src.get_height(), false,
		Image.FORMAT_RGBA8)
	out.fill(Color(
		FRAME_STATS.linear_to_srgb(FRAME_STATS.srgb_to_linear(px.r) * k),
		FRAME_STATS.linear_to_srgb(FRAME_STATS.srgb_to_linear(px.g) * k),
		FRAME_STATS.linear_to_srgb(FRAME_STATS.srgb_to_linear(px.b) * k)))
	return out


## INVARIANT TO A BRIGHTNESS SCALE — the whole reason chromaticity can live in the
## relations block, which `-Bless` never rewrites.
##
## ---------------------------------------------------------------------------
## THIS TEST SHIPPED RED AND THE TEST WAS THE THING THAT WAS WRONG, not the
## metric. Recording that here because the next person to read a failing
## invariant will reach for the metric first, as this file's author did.
##
## The version that failed built its scaled image as
## `Color(0.5, 0.25, 0.75)` -> `Color(0.25, 0.125, 0.375)` and called it "a
## uniform scale of all three channels". It is not. Those Colors are DISPLAY code
## values on their way into a FORMAT_RGBA8 fill, and halving a display code is not
## halving light: the sRGB EOTF has an offset and a 2.4 exponent, so the light
## ratio it produces depends on where on the curve each channel started. Swept,
## on the tint below (stored bytes 127/63/191, chroma_rg 4.26967):
##
##   scale k     LIGHT scaled (this test)      DISPLAY CODES scaled (the old one)
##               chroma_rg   mean ratio        chroma_rg   mean ratio
##   0.750       4.30911 (+0.92%)  0.7446      4.02572 (-5.71%)   0.5452
##   0.500       4.33058 (+1.43%)  0.4917      3.62766 (-15.04%)  0.2420
##   0.250       4.30234 (+0.77%)  0.2487      2.86837 (-32.82%)  0.0709
##   0.125       4.33823 (+1.61%)  0.1233      -                  -
##
## 3.62766 against 4.26967 is exactly what the red run reported. The metric was
## answering the question it was asked; the question was in the wrong space —
## which is the same confusion that shipped both black frames, arriving this time
## in the test rather than in the shader.
##
## The residual on the LIGHT column is 8-bit re-quantisation of the fill and not a
## bias: it does not grow with k, it changes sign between rg and bg, and the worst
## of it over both statistics and all four scales on this tint is +2.21%. The band
## is 3%, which is that with headroom and still eight times tighter than the
## smallest display-space scale error above.
##
## The second check is the control, and it is why the pair discriminates. A
## chromaticity computed over STORED BYTES instead of light would be nearly
## invariant to the display-code scale (127/63 = 2.016 against 63/31 = 2.032, a
## drift of 0.8%) and would fail the light scale. Asserting only the first would
## pass a byte-space statistic; asserting both cannot.
static func _scale_invariance(v: Verify, tint: Image, s: Dictionary) -> void:
	var worst := 0.0
	var mean_ok := true
	var detail := ""
	for k: float in [0.75, 0.5, 0.25, 0.125]:
		var d := FRAME_STATS.of(_lit_by(tint, k))
		for key: String in FRAME_STATS.CHROMA_KEYS:
			var got: float = d[key]
			var want: float = s[key]
			worst = maxf(worst, absf(got / want - 1.0))
		# Bounds the test at the other end. Without it a `_lit_by` that had stopped
		# scaling anything would hand back the source image and pass on chromaticity
		# alone, which is the shape of every green test in this project that
		# discriminated nothing.
		var got_k: float = float(d["mean"]) / float(s["mean"])
		if not v.near(got_k, k, 0.02 * k):
			mean_ok = false
		detail += " k=%.3f rg=%.5f meanratio=%.4f" % [k, d["chroma_rg"], got_k]
	v.check("chromaticity survives a uniform scale of the LIGHT",
		worst <= 0.03 and mean_ok,
		"worst drift %.3f%%, mean scaled correctly: %s —%s" % [
			worst * 100.0, mean_ok, detail])

	# ...and the same factor applied to the CODE VALUES must NOT leave it alone,
	# because that is a different physical change. Measured -15.04% at k = 0.5; the
	# bound is 10%, well above the 3% quantisation band above and well below the
	# measurement.
	var codes := _solid(Color(0.25, 0.125, 0.375))
	var c := FRAME_STATS.of(codes)
	var moved: float = absf(float(c["chroma_rg"]) / float(s["chroma_rg"]) - 1.0)
	v.check("...and a uniform scale of the display CODES is not the same thing",
		moved >= 0.10,
		"halving the codes moved chroma_rg by %.3f%% (%.5f vs %.5f); under 10%% "
			% [moved * 100.0, c["chroma_rg"], s["chroma_rg"]]
			+ "means the statistic is being computed over bytes, not light")


# --- part 3: rectangles and masks ---------------------------------------------

static func _masks(v: Verify) -> void:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0))
	img.fill_rect(Rect2i(0, 0, 32, 64), Color(1, 1, 1))

	v.check("rect_mean measures the rectangle it is given",
		v.near(FRAME_STATS.rect_mean(img, Rect2i(0, 0, 32, 64)), 1.0, 1e-6)
			and v.near(FRAME_STATS.rect_mean(img, Rect2i(32, 0, 32, 64)), 0.0, 1e-9)
			and v.near(FRAME_STATS.rect_mean(img, Rect2i(0, 0, 64, 64)), 0.5, 1e-6))
	v.check("a rectangle outside the image is clipped rather than crashing",
		v.near(FRAME_STATS.rect_mean(img, Rect2i(-20, -20, 40, 40)), 1.0, 1e-6),
		"got %.6f" % FRAME_STATS.rect_mean(img, Rect2i(-20, -20, 40, 40)))

	var lit := FRAME_STATS.masked(img, Rect2i(0, 0, 64, 64),
		func(p: Color) -> bool: return p.r > 0.5)
	v.check("a mask reports its mean AND how many pixels it matched",
		v.near(float(lit["mean"]), 1.0, 1e-6) and int(lit["count"]) == 32 * 64
			and v.near(float(lit["frac"]), 0.5, 1e-6),
		str(lit))

	# THE EMPTY-MASK CASE, which is the shape of a test that passes while testing
	# nothing: a rim at zero energy matches no pixel, the mean of nothing is 0.0,
	# and a naive "ratio below 2.0" check goes green on a frame with no rim in it.
	# The count is what makes that visible, so the count is asserted.
	var none := FRAME_STATS.masked(img, Rect2i(0, 0, 64, 64),
		func(p: Color) -> bool: return p.g > 2.0)
	v.check("an empty mask reports count 0 rather than a silent zero mean",
		int(none["count"]) == 0 and v.near(float(none["frac"]), 0.0, 1e-9)
			and v.near(float(none["mean"]), 0.0, 1e-9),
		str(none))

	v.check("ratio() names the divide-by-zero instead of returning inf",
		FRAME_STATS.ratio(1.0, 0.0) < 0.0 and v.near(FRAME_STATS.ratio(3.0, 1.5), 2.0),
		"%.3f" % FRAME_STATS.ratio(1.0, 0.0))


# --- part 3b: the silhouette difference ---------------------------------------

## `changed_box` is the gate's only GEOMETRIC statistic and the one that would have
## caught the ADS sight line, so it gets the same treatment as the luminance maths:
## hand-built images with hand-computed answers, bounded at both ends.
##
## CLAUDE.md: "a frame comparison metric must be checked before it is trusted",
## after a naive row-delta reported two distinct atlas rows as near-identical. The
## specific way this one could lie is by returning a plausible box for a frame with
## nothing in it, so the empty case is asserted first and hardest.
static func _silhouette(v: Verify) -> void:
	var base := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	base.fill(Color(0.1, 0.1, 0.1))

	# THE EMPTY CASE. Two identical frames must report nothing — not a box at the
	# origin, which is what a naive min/max over an untouched accumulator returns
	# and what would read as "the weapon is at the very top of the screen".
	var same := FRAME_STATS.changed_box(base, base.duplicate())
	v.check("two identical frames report no changed box rather than one at 0,0",
		int(same["count"]) == 0 and int(same["y0"]) < 0 and int(same["x0"]) < 0,
		str(same))
	v.check("a null or mismatched frame reports no changed box",
		int(FRAME_STATS.changed_box(base, null)["count"]) == 0
			and int(FRAME_STATS.changed_box(null, base)["count"]) == 0
			and int(FRAME_STATS.changed_box(base,
				Image.create_empty(32, 32, false, Image.FORMAT_RGBA8))["count"]) == 0)

	# A known rectangle, and the box must be EXACTLY it — a box one row tall or one
	# row short is a sight line off by a pixel, which is the resolution this is
	# being asked to work at.
	var with_thing := base.duplicate()
	with_thing.fill_rect(Rect2i(20, 12, 15, 30), Color(0.9, 0.9, 0.9))
	var box := FRAME_STATS.changed_box(with_thing, base)
	v.check("the changed box is exactly the rectangle that changed",
		int(box["x0"]) == 20 and int(box["y0"]) == 12 and int(box["x1"]) == 34
			and int(box["y1"]) == 41 and int(box["count"]) == 15 * 30
			and int(box["rows"]) == 30,
		str(box))

	# ...and it is symmetric, because a caller that passed the two frames the other
	# way round would otherwise get a different answer for the same pair.
	var flipped := FRAME_STATS.changed_box(base, with_thing)
	v.check("differencing is symmetric in its two frames",
		int(flipped["y0"]) == int(box["y0"]) and int(flipped["x1"]) == int(box["x1"])
			and int(flipped["count"]) == int(box["count"]), str(flipped))

	# min_run: a row with fewer changed pixels than the minimum does not get to
	# claim the top edge. Without this one pixel of driver dither anywhere above the
	# weapon is the weapon's new top row, and the geometric rules would report a
	# sight line at whatever height the noise happened to be.
	var speckled := with_thing.duplicate()
	speckled.set_pixel(5, 2, Color(1, 1, 1))
	speckled.set_pixel(40, 3, Color(1, 1, 1))
	var srun := FRAME_STATS.changed_box(speckled, base)
	v.check("a row under the pixel minimum cannot claim the edge of the box",
		int(srun["y0"]) == 12 and int(srun["x0"]) == 20, str(srun))
	# ...and the same speckle IS found when the minimum is lowered to admit it, so
	# the check above is discriminating rather than describing a function that
	# never sees anything.
	var loose := FRAME_STATS.changed_box(speckled, base, 3, 1)
	v.check("...and it is found when the minimum is lowered to admit it",
		int(loose["y0"]) == 2 and int(loose["x0"]) == 5, str(loose))

	# The threshold, both ways. A change of two display codes is below the default
	# of three and must not register; the same change registers at a threshold of
	# two. Asserting only the rejection would pass against a function that had
	# stopped finding anything at all.
	var faint := base.duplicate()
	var px := base.get_pixel(0, 0)
	var lifted := Color(px.r + 2.0 / 255.0, px.g, px.b)
	faint.fill_rect(Rect2i(10, 10, 20, 20), lifted)
	v.check("a change below the threshold is not a change, and one above it is",
		int(FRAME_STATS.changed_box(faint, base)["count"]) == 0
			and int(FRAME_STATS.changed_box(faint, base, 2, 4)["count"]) == 400,
		"at 3: %s   at 2: %s" % [
			str(FRAME_STATS.changed_box(faint, base)),
			str(FRAME_STATS.changed_box(faint, base, 2, 4))])


# --- part 4: the tolerance arithmetic -----------------------------------------

## Bounded at BOTH ends throughout. A tolerance test that only asserts the
## acceptance passes equally well against a comparator that accepts everything.
static func _tolerance(v: Verify) -> void:
	v.check("within() accepts a drift inside the band and rejects one outside",
		FRAME_STATS.within(1.0, 1.02, 0.0, 0.03)
			and not FRAME_STATS.within(1.0, 1.05, 0.0, 0.03))
	v.check("the absolute term is what makes a zero-valued statistic comparable",
		FRAME_STATS.within(0.0, 0.001, 0.002, 0.0)
			and not FRAME_STATS.within(0.0, 0.003, 0.002, 0.0))
	# max(|a|,|b|) and not |a|: with the golden on the small side, a relative-only
	# window computed from the golden would admit an arbitrarily large capture.
	v.check("the relative term is taken against the larger of the two",
		not FRAME_STATS.within(0.001, 0.01, 0.0, 0.5)
			and FRAME_STATS.within(0.001, 0.0014, 0.0, 0.5))


# --- part 5: the comparator ---------------------------------------------------

## The comparator's fixture: a REAL golden row, the measured `spawn` one, so the
## values it is asked to compare are the size of values the gate actually meets.
##
## chroma_rg/chroma_bg are here because `compare()` treats a chromaticity absent
## from the golden as a FAILURE — a golden file blessed before the statistic
## existed has never been argued about, and passing it quietly is the
## invisible-coverage failure of audit §3. That rule is right, and it is also what
## made four checks in this section red the day the statistic landed: this fixture
## had not been given the two keys, so every `compare()` below reported them
## missing from its own hand-built "golden" and the checks that count failures
## counted two extra. The golden file itself was never at fault. Both values are
## the measured `spawn` row, same as everything else here.
static func _row() -> Dictionary:
	return {
		"w": 1280, "h": 720,
		"mean": 0.006660, "median": 0.000498, "p01": 0.000088, "p99": 0.069375,
		"black": 0.722447, "blown": 0.0,
		"chroma_rg": 1.719722, "chroma_bg": 0.685074,
		"regions": [0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08,
			0.09, 0.10, 0.11, 0.12, 0.13, 0.14, 0.15, 0.16],
		"probes": {"gun_mean": 0.05009},
	}


static func _comparator(v: Verify) -> void:
	var tol := {
		"mean": {"abs": 0.000005, "rel": 0.03},
		"frac": {"abs": 0.002, "rel": 0.02},
		"region": {"abs": 0.00005, "rel": 0.05},
		"probe": {"abs": 0.00005, "rel": 0.05},
		"chroma": {"abs": 0.001, "rel": 0.02},
	}
	var g := _row()
	v.check("a row compared against itself reports no drift",
		FRAME_STATS.compare(g, _row(), tol).is_empty(),
		str(FRAME_STATS.compare(g, _row(), tol)))

	# The chromaticity band, bounded at both ends. The `scenarios` block is the
	# SNAPSHOT half of the gate — `-Bless` rewrites it — so its band is sized to
	# notice, not to survive a retune; that job belongs to the two chroma rules in
	# `relations`. Measured: pushing LAMP_COLOR deeper amber moves `power.chroma_rg`
	# from 2.0787 to 2.5303 (golden.json, "the lit room is not pushed deeper amber
	# or cold"), which is +21.7%, and the run-to-run spread of every statistic on
	# this machine is 0.000000% over five runs (README.md). So the low end asserted
	# here is the 2% band itself, not a measured jitter: half of it must pass.
	var hue := _row()
	hue["chroma_rg"] = 1.719722 * (2.5303 / 2.0787)
	var hbad := FRAME_STATS.compare(g, hue, tol)
	var inside := _row()
	inside["chroma_rg"] = 1.719722 * 1.01
	v.check("a hue shift is reported as chroma drift and a 1% wobble is not",
		hbad.size() == 1 and hbad[0].begins_with("chroma_rg")
			and FRAME_STATS.compare(g, inside, tol).is_empty(),
		"hue: %s  inside: %s" % [str(hbad), str(FRAME_STATS.compare(g, inside, tol))])

	var dim := _row()
	dim["mean"] = 0.004789      # the measured LAMP_ENERGY_OFF = 0.34 black frame
	dim["median"] = 0.000110
	dim["black"] = 0.952200
	var bad := FRAME_STATS.compare(g, dim, tol)
	var named := {"mean": false, "median": false, "black": false}
	for line: String in bad:
		for k: String in named.keys():
			if line.begins_with(k):
				named[k] = true
	v.check("the measured black frame drifts on mean, median AND black fraction",
		bad.size() == 3 and named["mean"] and named["median"] and named["black"],
		str(bad))

	var one_cell := _row()
	var rr: Array = one_cell["regions"].duplicate()
	rr[5] = 0.03
	one_cell["regions"] = rr
	var rbad := FRAME_STATS.compare(g, one_cell, tol)
	v.check("a single drifted region cell is reported, and only that cell",
		rbad.size() == 1 and rbad[0].begins_with("region 1,1"), str(rbad))

	# A MISSING GOLDEN ROW MUST FAIL, NOT SKIP. A scenario nobody has ever
	# photographed has no evidence behind it, and passing it quietly is the exact
	# invisible-coverage failure of audit §3.
	var missing := FRAME_STATS.compare({}, _row(), tol)
	v.check("a scenario with no golden row fails rather than passing quietly",
		missing.size() == 1 and "never been blessed" in missing[0], str(missing))

	# ...and so must a probe the golden has and the capture does not: that is a
	# probe whose subject vanished from the scene.
	var no_probe := _row()
	no_probe["probes"] = {}
	var pbad := FRAME_STATS.compare(g, no_probe, tol)
	v.check("a probe that stopped being measured fails rather than passing",
		pbad.size() == 1 and "was not measured" in pbad[0], str(pbad))


# --- part 6: the relations, against the real committed bounds -----------------

static func _relations(v: Verify) -> void:
	v.check("path() resolves a nested statistic and reports a missing one as NAN",
		v.near(FRAME_STATS.path({"a": {"b": 2.5}}, "a.b"), 2.5)
			and is_nan(FRAME_STATS.path({"a": {"b": 2.5}}, "a.c"))
			and is_nan(FRAME_STATS.path({"a": {"b": 2.5}}, "a.b.c")))

	var rule := [{"name": "t", "num": "x.mean", "den": "y.mean", "min": 1.1, "max": 2.0}]
	v.check("a relation inside its band passes and one outside fails",
		FRAME_STATS.relations({"x": {"mean": 1.5}, "y": {"mean": 1.0}}, rule).is_empty()
			and FRAME_STATS.relations({"x": {"mean": 3.0}, "y": {"mean": 1.0}}, rule).size() == 1
			and FRAME_STATS.relations({"x": {"mean": 1.0}, "y": {"mean": 1.0}}, rule).size() == 1)
	v.check("a relation whose path does not resolve fails rather than reading zero",
		FRAME_STATS.relations({"x": {"mean": 1.5}}, rule).size() == 1,
		str(FRAME_STATS.relations({"x": {"mean": 1.5}}, rule)))

	# THE REGRESSION TEST, and the reason this file is worth its length.
	#
	# The numbers below are MEASURED, by capturing the `horde` scenario with
	# zombie.gd's RIM_ENERGY sabotaged to each value and reading the probe back.
	# They are run against the REAL relation rules out of the committed
	# golden.json — not a copy — so the bounds themselves are what is under test.
	# 0.62 is the value that shipped; 0.16 is the value the sweep rejected as
	# "the silhouette stops reading at all"; 0.0 is the effect switched off.
	var golden := FRAME_STATS.load_golden()
	var rules: Array = golden.get("relations", [])
	var rim: Array = []
	for r: Dictionary in rules:
		if String(r.get("num", "")).begins_with("horde.probes.rim"):
			rim.append(r)
	v.check("the golden file declares the rim relations the gate turns on",
		rim.size() == 2, "found %d" % rim.size())

	# RE-MEASURED 2026-08-03, all four rows, after `_probe_rim` started excluding the
	# viewmodel. They are not a retune: the old rows were read through a probe whose
	# rect contained 18 px of the gun's grey slide, and `_is_cold` counts gun metal as
	# rim. See `shot_setup._probe_rim` for the before-and-after sweep and the arithmetic.
	#
	# THE ROW THAT MATTERS IS `switched_off`, AND IT IS WHY THIS RE-MEASUREMENT WAS
	# WORTH DOING. It used to read rim_frac 0.002600 — two thirds of the shipped
	# 0.004090 — so "the rim is switched off entirely" and "the rim is working" were
	# 1.6x apart and a band had to thread between them. It is now EXACTLY 0.000000
	# against a shipped 0.000854, so the gate fails on a build with no rim by an
	# infinite margin rather than a hairline one.
	var shipped := {"horde": {"probes": {
		"rim_mean": 0.055360, "body_mean": 0.187351,
		"rim_frac": 0.000854, "body_frac": 0.517469}}}
	var too_bright := {"horde": {"probes": {
		"rim_mean": 0.306957, "body_mean": 0.197800,
		"rim_frac": 0.002776, "body_frac": 0.483479}}}
	var too_dim := {"horde": {"probes": {
		"rim_mean": 0.010884, "body_mean": 0.177399,
		"rim_frac": 0.000225, "body_frac": 0.518538}}}
	var switched_off := {"horde": {"probes": {
		"rim_mean": 0.000000, "body_mean": 0.173901,
		"rim_frac": 0.000000, "body_frac": 0.511935}}}
	v.check("the committed bounds accept the shipped RIM_ENERGY of 0.30",
		FRAME_STATS.relations(shipped, rim).is_empty(),
		str(FRAME_STATS.relations(shipped, rim)))
	v.check("the committed bounds reject the 0.62 rim that shipped as a defect",
		not FRAME_STATS.relations(too_bright, rim).is_empty(),
		"3.4x brighter than its body and the gate said nothing")
	v.check("the committed bounds reject a rim dimmed to the rejected 0.16",
		not FRAME_STATS.relations(too_dim, rim).is_empty())
	v.check("the committed bounds reject the rim being switched off entirely",
		not FRAME_STATS.relations(switched_off, rim).is_empty())

	# The same shape for the black frame, against the real committed bound. The
	# numbers are the measured `spawn` row with lighting.gd's LAMP_ENERGY_OFF put
	# back to the 0.34 that shipped a black screen with one lit barricade in it.
	var dark_rule: Array = []
	for r: Dictionary in rules:
		if String(r.get("num", "")) == "spawn.median":
			dark_rule.append(r)
	v.check("the golden file declares the black-frame relation", dark_rule.size() == 1)
	v.check("the committed bound accepts the shipped spawn frame",
		FRAME_STATS.relations({"spawn": {"median": 0.000498, "mean": 0.006660}},
			dark_rule).is_empty())
	v.check("the committed bound rejects the measured near-black spawn frame",
		not FRAME_STATS.relations({"spawn": {"median": 0.000110, "mean": 0.004789}},
			dark_rule).is_empty(),
		"95% of the frame at or below display code 8 and the gate said nothing")


# --- part 7: the scenario registry --------------------------------------------

static func _registry(v: Verify) -> void:
	var reg := SHOT_SETUP.registry()
	var names := SHOT_SETUP.names()
	v.check("the scenario registry is not empty and names() reads it",
		not reg.is_empty() and names.size() == reg.size(),
		"reg=%d names=%d" % [reg.size(), names.size()])

	var absent: Array[String] = []
	for want: String in REQUIRED:
		if not reg.has(want):
			absent.append(want)
	v.check("every scenario the package was commissioned for is registered",
		absent.is_empty(), "missing: %s" % str(absent))

	# Callable, not merely present. A registry row whose function was renamed
	# would still look complete to the check above.
	var broken := ""
	for name: String in names:
		var row: Dictionary = reg[name]
		if not row.has("fn") or not row.has("settle") or not row.has("why"):
			broken += "%s(shape) " % name
			continue
		var fn: Callable = row["fn"]
		if not fn.is_valid() or fn.get_argument_count() != 1:
			broken += "%s(callable) " % name
		var settle: float = row["settle"]
		# Zero would capture on the frame the scenario landed, before a single
		# tween, particle or move_toward had advanced.
		if settle <= 0.0:
			broken += "%s(settle=%.3f) " % [name, settle]
		# SECONDS, not frames, and every budget is an exact multiple of 1/60 so
		# that the frame count under `--fixed-fps 60` is unambiguous. A budget of
		# 20 would once have meant a third of a second and now means twenty
		# seconds, so this is also the check that catches a row left un-migrated.
		if settle > 10.0:
			broken += "%s(settle=%.1f s looks like a frame count) " % [name, settle]
		if absf(settle * 60.0 - roundf(settle * 60.0)) > 1e-6:
			broken += "%s(settle=%.4f is not a whole frame at 60) " % [name, settle]
		if String(row["why"]).length() < 20:
			broken += "%s(why) " % name
		if not v.near(SHOT_SETUP.settle_of(name), settle, 1e-9):
			broken += "%s(settle_of) " % name
		# An `until` is optional; one that is present and not callable with exactly
		# the argument main.gd hands it would abort every capture of that scenario.
		var until := SHOT_SETUP.arrival_of(name)
		if row.has("until") != until.is_valid():
			broken += "%s(arrival_of) " % name
		if until.is_valid() and until.get_argument_count() != 1:
			broken += "%s(until arity %d) " % [name, until.get_argument_count()]
	v.check("every registered scenario is callable and carries a settle and a why",
		broken.is_empty(), broken)

	# THE SCENARIOS WHOSE NAME IS A DESTINATION MUST SAY HOW THEY KNOW THEY GOT
	# THERE. Stated here, from the requirement, rather than read back out of the
	# registry — the same reason REQUIRED above is not `reg.keys()`. `power` is the
	# one that proves it: photographed on a frame count under a bare `--shot` it
	# came back byte-identical to `power_off`, three lamps of eight into a ceremony
	# whose only lamp in frame had not moved.
	var no_arrival: Array[String] = []
	for want: String in ["power", "ads", "downed", "flash_hip", "flash_ads"]:
		if not SHOT_SETUP.arrival_of(want).is_valid():
			no_arrival.append(want)
	v.check("every scenario whose subject is an arrived state declares a predicate",
		no_arrival.is_empty(), "no `until`: %s" % str(no_arrival))

	# An unknown name must be fatal, not a silent fall-through to the default
	# view — a typo that photographs `spawn` under the name `horde` blesses a
	# golden row that certifies nothing.
	v.check("an unknown scenario name is refused rather than defaulted",
		SHOT_SETUP.settle_of("no_such_scenario") < 0.0
			and SHOT_SETUP.apply("no_such_scenario", null) < 0.0
			and not SHOT_SETUP.arrival_of("no_such_scenario").is_valid())

	var declared := 0
	for name: String in names:
		if SHOT_SETUP.probes_expected(name):
			declared += 1
	v.check("more than half the scenarios declare a probe of their own",
		declared * 2 > names.size(), "%d of %d" % [declared, names.size()])

	# The silhouette is the second-frame half and it has its own list. Both poses
	# the rig has must be on it, and everything on it must also be on the ordinary
	# probe list — main.gd merges the two dicts, so a scenario on one and not the
	# other would produce a probe row nothing declared it should have.
	var sil_bad := ""
	for name: String in names:
		if SHOT_SETUP.silhouette_expected(name) and not SHOT_SETUP.probes_expected(name):
			sil_bad += "%s " % name
	v.check("both viewmodel poses are measured for silhouette, and only declared probes",
		SHOT_SETUP.silhouette_expected("spawn") and SHOT_SETUP.silhouette_expected("ads")
			and not SHOT_SETUP.silhouette_expected("horde") and sil_bad.is_empty(),
		"undeclared: %s" % sil_bad)


# --- part 8: the golden file --------------------------------------------------

## THE CROSS-HALF ASSERTIONS. Every one of these fails until somebody has run the
## windowed pass and blessed its output, which is the audit's §5 remedy for a
## contract whose two halves can drift: "a reported hunk is not done — add a check
## that fails until it lands."
static func _golden(v: Verify) -> void:
	var g := FRAME_STATS.load_golden()
	v.check("the golden file exists and parses",
		not g.is_empty() and g.has("scenarios") and g.has("tolerance")
			and g.has("relations"),
		"at %s" % FRAME_STATS.GOLDEN)
	if g.is_empty():
		return

	v.check("the golden file records the run that produced it",
		String(g.get("captured", "")).length() >= 8
			and int(g.get("seed", -1)) == SHOT_SETUP.SEED,
		"captured='%s' seed=%s vs %d" % [
			g.get("captured", ""), g.get("seed", "?"), SHOT_SETUP.SEED])

	var res: Array = g.get("resolution", [])
	v.check("the golden file pins the resolution it was captured at",
		res.size() == 2 and int(res[0]) > 0 and int(res[1]) > 0, str(res))

	var scen: Dictionary = g.get("scenarios", {})
	var names := SHOT_SETUP.names()
	var unblessed: Array[String] = []
	var incomplete := ""
	for name: String in names:
		if not scen.has(name):
			unblessed.append(name)
			continue
		var row: Dictionary = scen[name]
		for k: String in ["mean", "median", "p01", "p99", "black", "blown",
				"regions", "w", "h", "settle", "chroma_rg", "chroma_bg"]:
			if not row.has(k):
				incomplete += "%s.%s " % [name, k]
		var rg: Array = row.get("regions", [])
		if rg.size() != FRAME_STATS.GRID * FRAME_STATS.GRID:
			incomplete += "%s.regions=%d " % [name, rg.size()]
		if res.size() == 2 and (int(row.get("w", 0)) != int(res[0])
				or int(row.get("h", 0)) != int(res[1])):
			incomplete += "%s.size " % name
		var probes: Dictionary = row.get("probes", {})
		if SHOT_SETUP.probes_expected(name) and probes.is_empty():
			incomplete += "%s.probes " % name
	v.check("every registered scenario has been photographed and blessed",
		unblessed.is_empty(),
		"never captured: %s — run `pwsh tools/frames.ps1 -Bless`" % str(unblessed))
	v.check("every golden row carries every statistic the comparator reads",
		incomplete.is_empty(), incomplete)

	# A relation whose path is a typo prints "cannot resolve" in a windowed run
	# and is otherwise invisible; resolved here, headlessly, against the golden's
	# own rows.
	var rules: Array = g.get("relations", [])
	var unresolved := ""
	var unbounded := ""
	for r: Dictionary in rules:
		for side: String in ["num", "den"]:
			# An absent `den` is legal and means "bound `num` itself" — see
			# frame_stats.relations(). An absent `num` never is.
			var p := String(r.get(side, ""))
			if p.is_empty() and side == "den":
				continue
			if is_nan(FRAME_STATS.path(scen, p)):
				unresolved += "%s:%s " % [r.get("name", "?"), p]
		var lo: float = r.get("min", 0.0)
		var hi: float = r.get("max", INF)
		if lo >= hi or String(r.get("why", "")).length() < 20:
			unbounded += "%s " % r.get("name", "?")
	v.check("every relation resolves against the golden rows it names",
		unresolved.is_empty(), unresolved)
	v.check("every relation is bounded and carries its provenance",
		not rules.is_empty() and unbounded.is_empty(),
		"%d rules, bad: %s" % [rules.size(), unbounded])

	# Every relation must actually PASS against the committed rows. Otherwise the
	# gate ships red and the first person to run it concludes their own change
	# broke it.
	v.check("the committed golden rows satisfy every committed relation",
		FRAME_STATS.relations(scen, rules).is_empty(),
		str(FRAME_STATS.relations(scen, rules)))

	# The reference images are not the gate — the numbers are — but they are the
	# evidence for the human pass that statistics cannot replace, and a missing
	# one means somebody blessed numbers without keeping the picture.
	var no_png: Array[String] = []
	for name: String in names:
		if not FileAccess.file_exists("%s/%s.png" % [FRAME_STATS.REF, name]):
			no_png.append(name)
	v.check("every registered scenario has a committed reference image",
		no_png.is_empty(), "missing PNGs: %s" % str(no_png))


# --- part 9: the muzzle flash's geometry --------------------------------------

## THE FLASH IS IN THIS FILE BECAUSE THE GATE IS WHERE IT BELONGS AND THE GATE
## CANNOT RUN HEADLESS. `flash_hip` and `flash_ads` photograph the effect and the
## relations in golden.json bound its shape, but that is a windowed pass; these
## are the parts of the same argument that need no frame, so that a build whose
## flash had gone back to a flat square fails `--verify` too and not only
## `tools/frames.ps1`.
##
## Both halves drive atmosphere.gd's own functions. Nothing below restates the
## implementation's arithmetic in the implementation's form: the expectations are
## written out in the ANCESTOR's form, from html:3148-3168, so a constant edited
## in one place has to be re-argued rather than merely re-copied.
static func _flash_geometry(v: Verify) -> void:
	# html:3148 `r = cssH*(0.05+Math.random()*0.035)*(cone?2.2:1)`, drawn out to
	# `r*2.4` (html:3150), so the halo's WIDTH is 4.8*r of screen height. Written
	# here in that form; atmosphere.gd carries it pre-multiplied.
	var frac_bad := ""
	for u: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for cone: bool in [false, true]:
			var want := 4.8 * (0.05 + 0.035 * u) * (2.2 if cone else 1.0)
			var got := ATMOSPHERE.flash_frac(u, cone)
			if not v.near(got, want, 1e-6):
				frac_bad += "u=%.2f cone=%s got %.5f want %.5f  " % [u, cone, got, want]
	v.check("the flash's size roll is the ancestor's fraction of screen height",
		frac_bad.is_empty(), frac_bad)
	# ...and the endpoints as numbers, because a range is the thing a reader
	# actually needs and 0.24 / 0.898 are checkable against the frame.
	v.check("the flash spans 24%% to 41%% of screen height, and 2.2x that for a cone",
		v.near(ATMOSPHERE.flash_frac(0.0, false), 0.240, 1e-6)
			and v.near(ATMOSPHERE.flash_frac(1.0, false), 0.408, 1e-6)
			and v.near(ATMOSPHERE.flash_frac(1.0, true), 0.8976, 1e-6),
		"%.4f %.4f %.4f" % [ATMOSPHERE.flash_frac(0.0, false),
			ATMOSPHERE.flash_frac(1.0, false), ATMOSPHERE.flash_frac(1.0, true)])

	# THE ADS DEFECT, AS ARITHMETIC. The shipped quad was a fixed 0.34 m at
	# flash_anchor()'s 0.35 m, so it grew with the camera's zoom while the weapon
	# it is attached to — redrawn through viewmodel.gd's own fixed 55-degree
	# projection — did not: 64% of the frame height at the hip FOV of 74 and 92% at
	# the sights. 1.432271 is tan(37) / tan(27.75), i.e. the ratio of the two
	# half-FOVs from player.gd's `_cam.fov = 74.0` and `ADS_FOV_MULT = 0.75`, and
	# it is written as a number here so this cannot pass by recomputing the
	# function under test.
	#
	# IT WAS WRITTEN AS 1.43110 FIRST AND THIS CHECK SHIPPED RED, and the check was
	# the thing that was wrong: 1.43110 was a linear interpolation of a tangent
	# table between 27 and 28 degrees, which a tangent does not obey. The measured
	# 1.432271 is the value, to seven figures, and the implementation had it right.
	var hip := ATMOSPHERE.flash_size(0.3, 0.35, 74.0)
	var ads := ATMOSPHERE.flash_size(0.3, 0.35, 55.5)
	v.check("the flash's world size shrinks at the sights by exactly the zoom",
		v.near(hip / ads, 1.432271, 0.0002),
		"hip %.5f m, ads %.5f m, ratio %.6f (want tan(37)/tan(27.75) = 1.432271)" % [
			hip, ads, hip / ads])
	# Bounded at the other end, and both ends are load-bearing: a `flash_size` that
	# ignored `frac` or `distance` would still pass the ratio above, because both
	# of its arguments would be wrong in the same way on both sides.
	v.check("the flash's size is proportional to its roll and to its depth",
		v.near(ATMOSPHERE.flash_size(0.6, 0.35, 74.0), hip * 2.0, 1e-9)
			and v.near(ATMOSPHERE.flash_size(0.3, 0.70, 74.0), hip * 2.0, 1e-9),
		"2x roll %.6f, 2x depth %.6f, 1x %.6f" % [
			ATMOSPHERE.flash_size(0.6, 0.35, 74.0),
			ATMOSPHERE.flash_size(0.3, 0.70, 74.0), hip])
	# And the absolute, once, against the shipped defect it replaces: a 0.3 roll at
	# the hip is 0.158 m, less than half the 0.34 m square that shipped.
	v.check("a mid-roll flash is 0.158 m at the hip, against the 0.34 m that shipped",
		v.near(hip, 0.15825, 0.0005), "%.5f m" % hip)


## THE ART, and the assertion the human pass would otherwise be the only holder
## of. `burst_image()` is the generator the material's texture is built from, not
## a copy of it, so a burst that became a disc — or a flat fill — fails here.
static func _flash_art(v: Verify, main: Node3D) -> void:
	var img: Image = ATMOSPHERE.burst_image()
	v.check("the burst mask is a square RGBA8 image at the declared size",
		img != null and img.get_width() == ATMOSPHERE.BURST_PX
			and img.get_height() == ATMOSPHERE.BURST_PX
			and img.get_format() == Image.FORMAT_RGBA8,
		"%dx%d fmt=%d" % [img.get_width(), img.get_height(), img.get_format()])

	# WHITE, WITH THE WHOLE SHAPE IN ALPHA. That is what makes this texture
	# independent of whether an RGBA8 image is decoded as sRGB — the same bargain
	# lighting.gd's lamp fixture makes — so it is asserted rather than assumed.
	var rgb_ok := true
	for p: Vector2i in [Vector2i(0, 0), Vector2i(64, 64), Vector2i(127, 127),
			Vector2i(10, 100), Vector2i(100, 10)]:
		var c := img.get_pixel(p.x, p.y)
		if not (v.near(c.r, 1.0, 1e-6) and v.near(c.g, 1.0, 1e-6)
				and v.near(c.b, 1.0, 1e-6)):
			rgb_ok = false
	v.check("the burst mask is white everywhere and carries its shape in alpha only",
		rgb_ok, "a pixel of the mask is not white — the colour belongs to the material")

	# THE FOUR POINTS, WHICH IS THE WHOLE DIFFERENCE FROM A DISC. Sampled along a
	# TIP direction and along a NOTCH direction at the same radius: a disc, a flat
	# fill and a radial gradient all light both, and only a star lights one.
	# Radii are fractions of the mask's half-width; the tips reach 0.62/0.66 =
	# 0.9394 and the notches 0.20/0.66 = 0.3030 (html:3163).
	var tip_far := _burst_a(img, 0.0, 0.85)
	var notch_far := _burst_a(img, PI / 4.0, 0.85)
	var tip_out := _burst_a(img, 0.0, 0.98)
	v.check("the burst has points: lit along a tip at 0.85 and dark along a notch",
		tip_far > 0.9 and notch_far < 0.01 and tip_out < 0.01,
		"tip@0.85=%.3f notch@0.85=%.3f tip@0.98=%.3f" % [tip_far, notch_far, tip_out])
	# ...and it is lit along the notch CLOSE IN, so the check above is a statement
	# about the shape rather than about a mask that has stopped covering anything.
	v.check("...and lit along that same notch inside its own radius",
		_burst_a(img, PI / 4.0, 0.20) > 0.9,
		"notch@0.20=%.3f" % _burst_a(img, PI / 4.0, 0.20))

	# FOUR-FOLD SYMMETRY, which is what makes the per-shot spin invisible to every
	# probe ring in shot_setup.gd and what "symmetric four-point burst"
	# (html:3157) means. Equal under a quarter turn, unequal under an eighth.
	# Radius 0.40 on purpose: outside the core (0.3333) and it lands INSIDE the
	# star at 0.0, 0.3 and 1.3 radians and OUTSIDE it at 0.7, so the equality below
	# is a mix of lit and dark rather than four pairs of zeroes agreeing.
	var sym_ok := true
	var sym := ""
	for a: float in [0.0, 0.3, 0.7, 1.3]:
		var lo := _burst_a(img, a, 0.40)
		var hi := _burst_a(img, a + PI * 0.5, 0.40)
		sym += "%.1f:%.2f/%.2f " % [a, lo, hi]
		if absf(lo - hi) > 0.02:
			sym_ok = false
	var eighth := absf(_burst_a(img, 0.0, 0.40) - _burst_a(img, PI * 0.25, 0.40))
	v.check("the burst is symmetric under a quarter turn and not under an eighth",
		sym_ok and eighth > 0.5,
		"quarter-turn pairs %s  eighth-turn delta %.3f" % [sym, eighth])

	# THE HOT CORE, which is the layer the port had lost and the reason the flash
	# read as one flat mid-yellow. html:3158 fills the burst at alpha .92 and
	# html:3168 fills the core disc over it at .92 again, which the canvas clips —
	# so the core is a strictly brighter tier than the star around it, and 0.92 is
	# what the star alone must read.
	var centre := _burst_a(img, 0.0, 0.0)
	var star_only := _burst_a(img, 0.0, 0.60)
	v.check("the core disc is a brighter tier than the star it sits inside",
		v.near(centre, 1.0, 0.005) and v.near(star_only, 0.92, 0.01)
			and centre > star_only + 0.05,
		"centre=%.3f star=%.3f (want 1.00 and 0.92)" % [centre, star_only])
	# The core's EDGE, from html:3168's r*0.22 against this mask's 0.66 half-width
	# = 0.3333. Bounded either side of it, so a core that swelled to fill the star
	# or shrank to a point moves this.
	v.check("the core disc ends where the ancestor's r*0.22 does",
		_burst_a(img, 0.0, 0.30) > 0.99 and _burst_a(img, 0.0, 0.37) < 0.93,
		"inside=%.3f outside=%.3f" % [
			_burst_a(img, 0.0, 0.30), _burst_a(img, 0.0, 0.37)])

	_flash_materials(v, main)


## THE LAYER THAT WAS ASSERTED EVERYWHERE EXCEPT WHERE IT MATTERED.
##
## Added on review, 2026-07-31, after a control found the hole. `burst_image()` is
## driven by `_flash_art` above, the material by `_flash_materials`, the size roll
## by `_flash_geometry` — and with the second `_place_flash` call in
## `atmosphere._on_fired` replaced by `_burst_quad.visible = false`, so that the
## four-point burst and the white hot core never reached the screen at all,
## MEASURED: `--verify` ran **580 passed, 0 failed** and `pwsh tools/frames.ps1`
## failed **zero relations** (7 blessed-row drifts, all of them numbers a
## `-Bless` erases). The ancestor's layers 2 and 3 — html:3158-3168, and the
## thing the complaint this package answers was actually about — were ungated.
##
## Same shape as the second control: `atmosphere`'s size draw pinned to a constant
## (html:3148's per-shot roll gone) also ran 580 green and failed no relation.
##
## So this drives the CONSUMER. It emits the real `fired` signal, which is the
## path the game uses and the one systems.gd's `_muzzle` already established is
## reachable headlessly, and then reads the two live nodes the renderer is handed.
## "Set the lure, then step a real zombie and see where it goes", for a flash.
##
## THE SHOT IS FIRED AT A REAL DISTANCE, and that is not cosmetic. systems.gd's
## `_muzzle` emits at the camera's OWN position, so `_on_fired` computes
## `dist = 0.0` and `flash_size` returns 0.0 — the quad is made visible at zero
## size and that check still passes, because all it reads is `visible`. Everything
## below needs a size, so it fires at FIRE_DEPTH along the view axis instead.
const FIRE_DEPTH := 8.0

## The ancestor's star reaches `r*0.62` (html:3163) inside a halo drawn to `r*2.4`
## (html:3150), so the burst quad can be no smaller than 0.62/2.4 = 0.2583 of the
## halo. atmosphere.gd pads that by a declared antialiasing margin; the margin has
## to stay a margin, so the upper bound is 15% over the ancestor rather than a
## restatement of `FLASH_BURST_FRAC`, which would make this an identity.
## SWEPT 2026-07-31 against `FLASH_BURST_R`: 0.45 -> 0.1875 and 0.55 -> 0.2292
## fail low, 0.66 -> 0.2750 passes, 0.80 -> 0.3333 and 1.00 -> 0.4167 fail high.
const BURST_OVER_HALO_MIN := 0.62 / 2.4
const BURST_OVER_HALO_MAX := (0.62 / 2.4) * 1.15

static func _flash_drawn(v: Verify, main: Node3D) -> void:
	var atmos: Node3D = main.atmos
	var vis: RandomNumberGenerator = Rng.stream(Rng.VISUAL)
	# Constraint 10, from the same direction traps.gd and systems.gd take it.
	var gameplay: Array[StringName] = [Rng.SPAWN, Rng.BOX, Rng.DROPS, Rng.ROUNDS, Rng.AI]
	var gp_was: Array[int] = []
	for s: StringName in gameplay:
		gp_was.append(Rng.stream(s).state)
	var vis_was: int = vis.state

	# THE ORACLE. A clone of the VISUAL stream at its current state, so the size
	# each shot below must produce is PREDICTED from `flash_frac` — whose own form
	# is pinned against html:3148 in `_flash_geometry` — instead of being read back
	# out of the quad under test. Rng's seed is per-run, so `u1` and `u2` are not
	# fixed numbers; the assertion is the relation between them and the drawn size,
	# which holds for any pair.
	var oracle := RandomNumberGenerator.new()
	oracle.seed = vis.seed
	oracle.state = vis.state
	var u1 := oracle.randf()
	var u2 := oracle.randf()
	var after_two: int = oracle.state

	var cam: Camera3D = main.player.camera()
	var cone: bool = String(main.player.current_gun().key) == "thundergun"
	var want1: float = ATMOSPHERE.flash_size(
		ATMOSPHERE.flash_frac(u1, cone), FIRE_DEPTH, cam.fov)
	var want2: float = ATMOSPHERE.flash_size(
		ATMOSPHERE.flash_frac(u2, cone), FIRE_DEPTH, cam.fov)

	var a := _fire_once(main)
	var b := _fire_once(main)

	# 1. BOTH LAYERS, which is the assertion that did not exist. A halo without a
	# burst is the flat mid-yellow the ancestor's layers 2 and 3 were added to
	# break up, and it passed everything.
	v.check("a shot lights both flash layers and not just the halo",
		bool(a["halo_lit"]) and bool(a["burst_lit"]),
		"halo=%s burst=%s" % [a["halo_lit"], a["burst_lit"]])

	# 2. ...at the ancestor's proportion, concentric and coplanar with it. Without
	# the ratio a burst placed at the halo's own size would pass check 1.
	var ratio: float = float(a["burst"]) / maxf(float(a["halo"]), 1e-9)
	v.check("the burst is drawn inside the halo at the ancestor's r*0.62 over r*2.4",
		ratio >= BURST_OVER_HALO_MIN and ratio <= BURST_OVER_HALO_MAX,
		"burst/halo %.5f, want [%.5f, %.5f]" % [
			ratio, BURST_OVER_HALO_MIN, BURST_OVER_HALO_MAX])
	v.check("...and concentric with it, on the same plane",
		float(a["gap"]) < 1e-6 and v.near(float(a["axis"]), 1.0, 1e-6),
		"centres %.6f m apart, |n1.n2| %.6f" % [a["gap"], a["axis"]])

	# 3. THE PER-SHOT SIZE ROLL, html:3148, through the real handler. Two shots,
	# because one would pass against a size that had stopped moving: with the draw
	# pinned to a constant this reads the same number twice and neither matches its
	# own `u`. The equality is exact — `flash_size` is arithmetic, not a fit.
	v.check("each shot's flash is sized by that shot's own roll",
		v.near(float(a["halo"]), want1, 1e-6) and v.near(float(b["halo"]), want2, 1e-6),
		"shot 1 %.6f m (want %.6f, u=%.5f), shot 2 %.6f m (want %.6f, u=%.5f)" % [
			a["halo"], want1, u1, b["halo"], want2, u2])

	# 4. Constraint 10. The gameplay streams must not move at all, and VISUAL must
	# move by EXACTLY the two draws the two shots are allowed — a third draw per
	# shot would shift `_launch`'s spread and with it every seeded run, which is
	# the departure atmosphere.gd's golden-angle comment claims to have avoided and
	# which nothing was checking. MEASURED: a second `Rng.randf(Rng.VISUAL)` added
	# to `_on_fired` left the suite 580 green and both flash captures unchanged.
	var moved := ""
	for i in gameplay.size():
		if Rng.stream(gameplay[i]).state != gp_was[i]:
			moved += str(gameplay[i]) + " "
	v.check("a shot's flash spends exactly one VISUAL draw and no gameplay stream",
		moved.is_empty() and vis.state == after_two,
		"perturbed [%s]; VISUAL at %d, two draws would leave it at %d" % [
			moved, vis.state, after_two])

	# Put the world back. The stream first, so nothing downstream sees two draws it
	# did not make; then the nodes, because `_process` only clears them once
	# FLASH_TIME has elapsed and a headless suite may never get there.
	vis.state = vis_was
	atmos._muzzle_t = 0.0
	atmos.flash_quad().visible = false
	atmos.burst_quad().visible = false
	atmos._muzzle_light.visible = false


## One real shot, and what the renderer was handed afterwards. Both quads are
## blanked FIRST, so "visible" below means this shot lit them rather than a
## previous one having left them on.
static func _fire_once(main: Node3D) -> Dictionary:
	var atmos: Node3D = main.atmos
	var halo: MeshInstance3D = atmos.flash_quad()
	var burst: MeshInstance3D = atmos.burst_quad()
	halo.visible = false
	burst.visible = false
	var cam: Camera3D = main.player.camera()
	main.player.fired.emit(
		cam.global_position - cam.global_transform.basis.z * FIRE_DEPTH)
	var hb := halo.global_transform.basis
	var bb := burst.global_transform.basis
	# The mesh is a shared 1x1 quad and the size lives in the transform, so a
	# basis column's length IS the drawn width. Read off the node rather than
	# recomputed, for the reason shot_setup.gd's probe gives.
	return {
		"halo_lit": halo.visible,
		"burst_lit": burst.visible,
		"halo": hb.x.length(),
		"burst": bb.x.length(),
		"gap": halo.global_position.distance_to(burst.global_position),
		"axis": absf(hb.z.normalized().dot(bb.z.normalized())),
	}


## Alpha of the burst mask at polar (angle, radius), radius in fractions of the
## mask's half-width. Nearest texel — the mask is 128 across and every radius
## asserted above is well clear of an edge, so interpolation would only blur what
## is being asserted.
static func _burst_a(img: Image, ang: float, rad: float) -> float:
	var n := img.get_width()
	var x := int((cos(ang) * rad + 1.0) * 0.5 * float(n))
	var y := int((sin(ang) * rad + 1.0) * 0.5 * float(n))
	return img.get_pixel(clampi(x, 0, n - 1), clampi(y, 0, n - 1)).a


## THE LIVE MATERIALS, off the running Atmosphere — not a freshly built pair.
## These are the objects main.gd hands to the warm-up pass and the renderer draws
## with, so a flag lost between `_flash_material` and the node fails here.
## NOTHING BELOW EARLY-RETURNS PAST A CHECK. Written that way first, and the
## control caught it: with `albedo_texture` sabotaged to null the run reported
## `574 passed, 2 failed` — four assertions had not run at all, because the
## gradient block bailed out on the first red. A suite that quietly gets SMALLER
## when something breaks is the invisible-coverage failure of audit §3 wearing a
## different hat; the assertion floor would catch the count, but the checks
## themselves should fail rather than vanish. Every guard below is folded INTO a
## `v.check` instead.
static func _flash_materials(v: Verify, main: Node3D) -> void:
	var atmos: Node3D = main.atmos
	var mats: Array = atmos.materials()
	# THE SET, NOT THE LENGTH — corrected 2026-08-02, when the muzzle smoke made
	# `materials()` three long and this went red for a correct change. `mats.size()
	# == 2` and the `mats[0]` below were a length check and an array-order read on a
	# list whose whole job is to grow; verify.gd:1098-1101 makes exactly this
	# argument about exactly this kind of list, in its own words — "a length check
	# breaks the moment a seventh is added, which is exactly when it should still be
	# useful". What has to be true is that BOTH flash layers are declared, that they
	# are distinct, and that each carries the flags below. It is strictly stronger:
	# a `materials()` that returned the halo twice failed the old size test only by
	# luck and fails this by name.
	var halo_mat: Material = atmos.flash_quad().material_override
	var burst_mat: Material = atmos.burst_quad().material_override
	var pair := mats.has(halo_mat) and mats.has(burst_mat) and halo_mat != burst_mat
	v.check("atmosphere hands the warm-up pass both flash layers", pair,
		"materials() returned %d; halo declared %s, burst declared %s, distinct %s" % [
			mats.size(), mats.has(halo_mat), mats.has(burst_mat),
			halo_mat != burst_mat])
	var bad := "" if pair else "a flash layer is undeclared "
	# THE TWO FLASH LAYERS ONLY. `materials()` also carries the muzzle smoke, which
	# is BLEND_MIX by design — smoke occludes, it does not emit — so sweeping the
	# whole list would demand the smoke be additive, which atmosphere.gd names as
	# the failure mode to reject.
	for m: StandardMaterial3D in [halo_mat, burst_mat]:
		if m.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			bad += "shaded "
		if m.blend_mode != BaseMaterial3D.BLEND_MODE_ADD:
			bad += "not-additive "
		if m.albedo_texture == null:
			bad += "UNTEXTURED "
		# The billboard flag is what discarded the per-shot roll — see
		# atmosphere._place_flash — and the depth test is what buried the burst
		# behind the weapon the ancestor draws it on top of (html:3142 then :3144).
		if m.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
			bad += "billboarded "
		if not m.no_depth_test:
			bad += "depth-tested "
	v.check("both flash layers are unshaded, additive, TEXTURED, unbillboarded and drawn over the weapon",
		bad.is_empty(), bad)

	# ...AND THEY ARE THE MATERIALS THE QUADS ARE ACTUALLY DRAWN WITH. Identity,
	# not equality: everything above reads whatever `materials()` hands back, so a
	# `materials()` returning a fresh, correctly-flagged pair satisfies all of it
	# while main.gd's warm-up pass compiles two variants nothing draws with, and
	# the first shot of a match compiles the real ones mid-fight.
	#
	# AND THIS WAS NOT AN OPEN HOLE, which is worth saying rather than implying
	# otherwise. Added on review 2026-07-31 and controlled the same hour: with
	# `materials()` rebuilding its pair, `every material in the game is reachable
	# from the warm-up pass` ALREADY fails, because that audit walks the tree and
	# finds the two the quads really carry unreachable. This is the narrower
	# statement of the same contract, kept for its failure message — the audit says
	# "missing: <StandardMaterial3D#...>" and this says which layer — and because it
	# is the one that would still bite if `materials()` returned one layer twice.
	# SINCE 2026-08-02 THE IDENTITY CLAIM IS `pair` ITSELF, which is built from these
	# same two live handles — so restating it here would be two checks asserting one
	# fact, which is decoration however good the comment is. What is left over and
	# genuinely unasserted is the other half of the paragraph above: `materials()`
	# handing back ONE LAYER TWICE. `pair` cannot see that (both `has` calls succeed
	# and the two handles are still distinct), the size test that could see it is
	# gone with the smoke's arrival, and the warm pass would then compile two
	# variants where the game needs three. So this check keeps its slot and changes
	# its claim: every material this file declares is a live, DISTINCT object.
	var seen_mats := {}
	var dupes := ""
	for m: Material in mats:
		if m == null or seen_mats.has(m):
			dupes += "%s " % m
		seen_mats[m] = true
	v.check("...and every layer atmosphere declares is a distinct live material",
		dupes.is_empty() and seen_mats.size() == mats.size()
			and mats.has(halo_mat) and mats.has(burst_mat),
		"halo %s / burst %s, %d declared and %d distinct, repeats [%s]" % [
			halo_mat, burst_mat, mats.size(), seen_mats.size(), dupes])

	# Layer 1's falloff, sampled out of the real Gradient rather than out of a
	# rendered texture: `Texture2D.get_image()` goes through the RenderingServer
	# and there is not one under --headless. html:3152-3154. Off the LIVE halo quad
	# rather than off `materials()[0]`, which was only the halo by array order.
	var tex: Texture2D = halo_mat.albedo_texture if pair else null
	var gt := tex as GradientTexture2D
	v.check("the halo is a radial gradient filled from its own centre",
		gt != null and gt.fill == GradientTexture2D.FILL_RADIAL
			and gt.fill_from == Vector2(0.5, 0.5) and gt.fill_to == Vector2(1.0, 0.5),
		"albedo_texture is %s" % str(tex))
	# A missing gradient reads as -1 rather than skipping the two checks below, so
	# the halo losing its texture fails them instead of deleting them.
	var g: Gradient = gt.gradient if gt != null else null
	var a0 := g.sample(0.0).a if g != null else -1.0
	var a35 := g.sample(0.35).a if g != null else -1.0
	var a1 := g.sample(1.0).a if g != null else -1.0
	v.check("the halo's alpha is the ancestor's .95 / .45 / 0 at 0, 0.35 and 1",
		v.near(a0, 0.95, 0.001) and v.near(a35, 0.45, 0.001) and v.near(a1, 0.0, 0.001),
		"%.3f %.3f %.3f" % [a0, a35, a1])
	# The corner of the quad sits at t = 1.414 and must contribute NOTHING, which
	# is what makes the flash a disc rather than a square — the `flash is a disc`
	# relation in golden.json is the same statement measured off a frame.
	var a12 := g.sample(1.2).a if g != null else -1.0
	var acorner := g.sample(1.414).a if g != null else -1.0
	v.check("the halo contributes nothing past its own radius, so the quad is a disc",
		v.near(a12, 0.0, 1e-6) and v.near(acorner, 0.0, 1e-6),
		"%.5f %.5f" % [a12, acorner])

	# ...and the tint, which is the one value in the effect that is a canvas
	# DISPLAY colour handed to a source_color uniform. html:3151's third arm is
	# '255,214,130'; the shipped material seeded itself with 219,140 instead.
	var tint: Color = ATMOSPHERE.MUZZLE_DEFAULT
	v.check("the halo's default tint is the ancestor's 255,214,130",
		v.near(tint.r, 1.0, 0.002) and v.near(tint.g, 214.0 / 255.0, 0.002)
			and v.near(tint.b, 130.0 / 255.0, 0.002), str(tint))
	# html:3158's 255,248,225 — and it must NOT be the tint, which is the whole
	# point of layers 2 and 3 having their own fillStyle and the reason the port
	# read as one flat mid-yellow without them.
	var hot: Color = ATMOSPHERE.FLASH_HOT
	v.check("the burst's hot colour is the ancestor's near-white 255,248,225",
		v.near(hot.r, 1.0, 0.002) and v.near(hot.g, 248.0 / 255.0, 0.002)
			and v.near(hot.b, 225.0 / 255.0, 0.002) and hot.b - tint.b > 0.3,
		str(hot))


# --- part 11: the weapon meshes -----------------------------------------------
#
# These render nothing either, and they are here rather than in `verify.gd`'s
# M-VMCLIP for one reason: M-VMCLIP asks whether the weapon can touch a wall, and
# these ask whether the mesh on screen is the mesh the corner walk measured. Two
# different questions about the same table, and the second one is the reason the
# first is trustworthy.
#
# THE COMMITTED MESH IS READ BACK. `gunart.gd:1195-1200` argues, correctly, that a
# safety assertion must not hang on `surface_get_arrays()` — a silently empty
# result under the dummy driver would make it pass by measuring nothing. That
# argument is about `_measure()`, which has no way to notice an empty set. It does
# not apply here, because these checks *compare* the round trip against the corner
# walk and assert a positive count on both sides, so an empty round trip fails
# loudly. MEASURED 2026-08-02: under `--headless` on the dummy driver
# `build_body("m1911")` returns a mesh with one surface and 252 vertices, so the
# round trip is live and this is a real readback rather than a hopeful one.

# `ANCESTOR_PARTS` — thirteen hand-typed part counts — STOOD HERE, and `_gun_ancestor`
# at the foot of this file is what replaced it. The reasoning is recorded there,
# because the table's own defence is the thing that failed. A plain `#` and a blank
# line below on purpose: as a `##` run this attached itself to `SHIPPED_MAX_HALF` and
# gave an unrelated depth constant a doc string about a deleted table.

## The deepest half-depth reachable under the draw-order expression this package
## replaced: `BASE_HALF + i*LAYER` at the largest index in the table, the
## Thundergun's part 10. In art units.
const SHIPPED_MAX_HALF := 4.00


## Every distinct |x| in a weapon's committed meshes, in art units.
static func _mesh_halves(key: String) -> Array:
	var out := {}
	for m: ArrayMesh in [GUNART.build_body(key, false), GUNART.build_slide(key, false)]:
		if m == null:
			continue
		var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for p: Vector3 in vs:
			out[snappedf(absf(p.x) / GUNART.UNIT, 0.0001)] = true
	var k := out.keys()
	k.sort()
	return k


## The same, off the corner walk that feeds `viewmodel._measure()`.
static func _corner_halves(key: String) -> Array:
	var out := {}
	for c: PackedVector3Array in [GUNART.body_corners(key), GUNART.slide_corners(key)]:
		for p: Vector3 in c:
			out[snappedf(absf(p.x) / GUNART.UNIT, 0.0001)] = true
	var k := out.keys()
	k.sort()
	return k


static func _gun_depth(v: Verify) -> void:
	# A missing row silently falls back to a multiplier of 1.0 — the pre-package
	# behaviour — so a weapon with no `DEPTH` entry would build, ship and look
	# exactly like the defect this table exists to remove. Bounded at both ends:
	# the row has to exist AND be the right length, because a short row falls back
	# on its tail alone, which is the half that is hardest to see.
	var bad_rows := ""
	var parts_total := 0
	for key: String in GUNART.keys():
		var parts: Array = GUNART._parts(key)
		parts_total += parts.size()
		var row: Array = GUNART.DEPTH.get(key, [])
		if row.size() != parts.size():
			bad_rows += "%s %d/%d " % [key, row.size(), parts.size()]
	v.check("every part of every weapon has an authored depth",
		bad_rows.is_empty() and parts_total == 133,
		"%d parts across the roster, rows off: %s" % [parts_total, bad_rows])

	# THE LEAD ASSERTION OF THE PACKAGE. `_build` and `_corners` are two walks over
	# the same table and M5 R2 names the trap in as many words: author per-part
	# depth at one of them and the clip measurement measures a mesh that is not on
	# screen. No aggregate metric catches it — `max_screen_radius()` is a single
	# number and would simply be the wrong one, silently, and still pass.
	#
	# So the two are compared directly: the distinct |x| of the COMMITTED ArrayMesh
	# against the distinct |x| of the corner walk, per weapon. They share an
	# accessor today (`GUNART.part_half`) and this is what would notice if one of
	# them stopped calling it.
	var disagree := ""
	var empty := ""
	for key: String in GUNART.keys():
		var mesh_h := _mesh_halves(key)
		var corner_h := _corner_halves(key)
		if mesh_h.is_empty() or corner_h.is_empty():
			empty += key + " "
		if mesh_h != corner_h:
			disagree += "%s mesh=%s corners=%s " % [key, mesh_h, corner_h]
	v.check("the builder and the corner walk extrude every part to the same depth",
		disagree.is_empty() and empty.is_empty(),
		"empty: %s; disagreeing: %s" % [empty, disagree])

	# ...and there are exactly as many distinct depths as there are parts, plus the
	# gloves' two. That single count carries three claims at once — no part shares a
	# depth with another (the caps would be coplanar again and `LAYER` undone by
	# hand), no part shares one with a glove, and neither side of the comparison
	# above is a degenerate set that happens to match.
	var wrong_count := ""
	for key: String in GUNART.keys():
		var want: int = GUNART._parts(key).size() + 2
		var got: int = _mesh_halves(key).size()
		if got != want:
			wrong_count += "%s %d/%d " % [key, got, want]
	v.check("...and every one of them is a distinct depth, gloves included",
		wrong_count.is_empty(), wrong_count)

	# M5 A14, stated over the table rather than over the mesh, and computed through
	# the same `part_half()` the builder calls rather than re-derived. The gloves
	# are pinned at HAND_HALF and HAND_HALF + LAYER (`gunart.gd:1163` and `:1421-1429`,
	# where `_hands` assigns those two literally) and do NOT ride the ramp, so a gun
	# part landing on either z-fights its caps against a glove. Provenance:
	# `gunart.gd:841-851`, the z-fight the ramp exists to fix.
	#
	# BOTH CITATIONS ON THIS LINE WERE WRONG BEFORE THE BANDS PACKAGE TOUCHED THE FILE,
	# and neither was caught by mapping them forward — they were checked. `529-535`
	# was `BASE_HALF`/`LAYER` and the head of the `DEPTH` tier doc, which never
	# mentions a glove; `190-200` was the tail of the `SLIDE` table, which never
	# mentions a z-fight. Recorded rather than silently corrected, because "the
	# citation was already wrong" is a finding.
	#
	# The first draft of F7 gave a different mechanism for this rule — the hands'
	# `PROUD` exemption — and that mechanism is false: `_inflate` never sees a
	# depth, so no depth can falsify it. An implementer who checked the named
	# invariant would have found it intact and shipped a broken table.
	var on_glove := ""
	var collide := ""
	for key: String in GUNART.keys():
		var seen := {}
		for i in GUNART._parts(key).size():
			var h: float = GUNART.part_half(key, i) / GUNART.UNIT
			if absf(h - GUNART.HAND_HALF) < 0.005 or absf(h - GUNART.HAND_HALF - GUNART.LAYER) < 0.005:
				on_glove += "%s %s %.2f " % [key, GUNART.part_id(key, i), h]
			var q := snappedf(h, 0.0001)
			if seen.has(q):
				collide += "%s %s %.2f " % [key, GUNART.part_id(key, i), h]
			seen[q] = true
	v.check("no weapon part is extruded to a glove's depth",
		on_glove.is_empty(),
		"gloves sit at %.2f and %.2f art units; on them: %s" % [
			GUNART.HAND_HALF, GUNART.HAND_HALF + GUNART.LAYER, on_glove])
	v.check("no two parts of one weapon are extruded to the same depth",
		collide.is_empty(), collide)

	# The ceiling, and it is a bound rather than a taste. M5 F7 puts the
	# screen-radius cost of a depth change somewhere between 5.9% and 50% of an
	# 8.1 mm margin — two derivations that disagree by up to 8x — and the
	# measurement that would settle it was never run. Until it is, the table may
	# not exceed the deepest half-depth that already shipped.
	var deepest := 0.0
	var thinnest := 1e9
	var over := ""
	for key: String in GUNART.keys():
		for i in GUNART._parts(key).size():
			var h: float = GUNART.part_half(key, i) / GUNART.UNIT
			deepest = maxf(deepest, h)
			thinnest = minf(thinnest, h)
			if h > SHIPPED_MAX_HALF:
				over += "%s %s %.2f " % [key, GUNART.part_id(key, i), h]
	v.check("no part is extruded deeper than the draw-order expression already did",
		over.is_empty(),
		"ceiling %.2f art units, deepest %.2f, over: %s" % [
			SHIPPED_MAX_HALF, deepest, over])
	# BOUNDED AT THE OTHER END, and this is the half that matters: every check
	# above passes perfectly against a `DEPTH` table of all-1.0, which is the
	# draw-order defect with a data structure in front of it. Under the old
	# expression nothing could be thinner than `BASE_HALF` = 2.60; something has to
	# be genuinely thin now or the table has done nothing.
	v.check("...and something on the roster is genuinely thin",
		thinnest < 0.6 * GUNART.BASE_HALF,
		"thinnest %.2f art units against BASE_HALF %.2f" % [thinnest, GUNART.BASE_HALF])

	# The inversion M5 F1 named, on its own worked example. Flan's Mod's `ModelColt`
	# puts the grip 5 deep against a barrel at 2, and a real M1911 is 34 mm across
	# the grip panels against a 23 mm slide; under draw order this table gave the
	# grip 3.02 and a 1.4-unit highlight rib 3.44, so the deepest thing on the
	# flagship weapon was a painted specular.
	var m_grip: float = GUNART.part_half("m1911", 3) / GUNART.UNIT
	var m_rib: float = GUNART.part_half("m1911", 6) / GUNART.UNIT
	var m_barrel: float = GUNART.part_half("m1911", 2) / GUNART.UNIT
	v.check("the M1911's grip is thicker than its barrel and than its slide rib",
		m_grip > m_rib and m_grip > m_barrel,
		"grip %.2f, rib %.2f, barrel %.2f art units" % [m_grip, m_rib, m_barrel])
	# And the clearest case in the table: a knife blade is not five sixths as thick
	# as the handle it folds out of, which is what draw order made it (2.60 against
	# 3.02). Our decision on the ratio; the direction is not a decision.
	var k_blade: float = GUNART.part_half("knife", 0) / GUNART.UNIT
	var k_handle: float = GUNART.part_half("knife", 3) / GUNART.UNIT
	v.check("the knife's blade is at most half the thickness of its handle",
		k_blade <= 0.5 * k_handle,
		"blade %.2f against handle %.2f art units" % [k_blade, k_handle])


# --- part 11b: the walk, decomposed -------------------------------------------
#
# `gunart.gd`'s walk is `ART + SIGHTS + DETAIL` and a part's place in the PAINTING
# used to be read straight off its place in the ARRAY, at five separate sites. Those
# two are the same number today and stop being the same number the first time
# something ahead of a part can be absent — which is what optional geometry is. The
# checks below pin the seam that separates them, and one of them (the footprint)
# covers the half of the ordinal nothing here could see at all.
#
# EVERY WALK BELOW LIVES IN `ancestor_art.gd`, not here. This file aborts its parse
# gate at `:1077` on the documented `Identifier not found: Rng` false positive,
# hundreds of lines above this point, so nothing written down here is gateable;
# `ancestor_art.gd` names no autoload and gates clean on its own. What is left in
# this file is a driver line and a `v.check`, which is as much as an ungateable file
# should be trusted with.

static func _gun_bands(v: Verify) -> void:
	# 1. THE RANK PIN, and it is honest about being a pin: `RANK` is empty, so
	# `part_rank` is the identity and the only control is deleting the identity. What
	# it is FOR is the day a band becomes conditional — it is the only assertion that
	# says an optional part may not renumber the M1911's slide, and every vertex of
	# every weapon rests on that. The acceptance guard stops it passing having walked
	# nothing.
	var rk := ANCESTOR_ART.rank_faults()
	v.check("every part of every band still ranks at its own place in the paint order",
		String(rk["diff"]).is_empty() and int(rk["n"]) == 133,
		"ranked %d parts; %s" % [int(rk["n"]), rk["diff"]])

	# 2. ...and the walk really is the bands, every part of it is addressable, and the
	# read-only aliasing this file MEASURED still holds for exactly three weapons.
	# Closes `_parts` from the side the distinct-|x| count above cannot reach: drop a
	# band from `_bands()` and `_parts`, written over it, silently loses those rows
	# while every count derived from `_parts` moves down with them.
	var wk := ANCESTOR_ART.walk_faults()
	v.check("the walk is exactly the bands concatenated, and every part it walks has an address",
		String(wk["diff"]).is_empty() and int(wk["n"]) == 133,
		"walked %d parts; %s" % [int(wk["n"]), wk["diff"]])

	# 3. THE ORDINAL-STABILITY PROPERTY, driven through the real `_band_base` against
	# censuses the tables do not hold — which is how "a band growing moves no earlier
	# part" is tested with no detail or attachment row invented. BOUNDED AT BOTH ENDS:
	# the refusal half alone passes perfectly against a `_band_base` that always
	# returns zero, so growing an EARLIER band must move the later base by exactly as
	# much.
	var bs := ANCESTOR_ART.base_faults()
	v.check("no band's base moves when a later band grows, and it moves exactly when an earlier one does",
		String(bs["diff"]).is_empty() and int(bs["n"]) == 195,
		"made %d claims over 13 weapons; %s" % [int(bs["n"]), bs["diff"]])

	# 4. A PAINTED HIGHLIGHT IS PROUD OF EVERYTHING IT IS PAINTED ON
	# (`gunart.gd:903-911`), and until now nothing said so: the depth checks above
	# assert that no two parts SHARE a depth, never that the one on top is the deeper.
	# MEASURED 2026-08-03 through the real accessors: 27 parts across the roster are
	# drawn strictly inside an earlier part's box, all 27 come out deeper than every
	# host, and fifteen of them are separated by exactly one `LAYER` step — which is
	# `LAYER` doing the only job it has left since the `DEPTH` table landed, and makes
	# this the first assertion anywhere that would notice `LAYER` going to zero. It is
	# also the roster-side control on `detail_rules()`'s `proud` clause.
	var ns := ANCESTOR_ART.nest_faults()
	v.check("every part drawn inside another is extruded proud of it",
		String(ns["diff"]).is_empty() and int(ns["n"]) == 41,
		"%d nested parts; %s" % [int(ns["n"]), ns["diff"]])

	# 5. AND THE TWO ORDINALS ARE ONE ORDINAL, ASSERTED OFF THE COMMITTED MESH. Depth
	# ramps by `LAYER` and the polygon grows by `PROUD`; before `part_rank` those were
	# separate expressions in separate functions, and nothing here could see them
	# disagree — the lead assertion above compares |x| only, which is the `LAYER` half
	# alone. A part's |x| identifies it uniquely (that is what "no two parts are
	# extruded to the same depth" buys), so its footprint is pulled back out of the
	# `ArrayMesh` and put against the box its own rank inflates. MEASURED: 119 parts
	# matched, worst delta 3.8e-6 art units against a 0.04 `PROUD` step, and a +1 rank
	# shift moves the box of all 119 — so there is no part this cannot see.
	var fp := ANCESTOR_ART.footprint_faults()
	v.check("every part's footprint in the committed mesh is its own art box grown by its own rank",
		String(fp["diff"]).is_empty() and int(fp["n"]) == 133,
		"matched %d parts; %s" % [int(fp["n"]), fp["diff"]])


static func _gun_shade(v: Verify) -> void:
	# The six face values, read through the function the builder calls. Named
	# rather than derived: the whole failure mode of the model this replaced was
	# that three distinct orientations shared one number, so "the ramp has six
	# entries and they are these six" is the statement worth pinning.
	var top: float = GUNART.face_shade(Vector3.UP)
	var under: float = GUNART.face_shade(Vector3.DOWN)
	var cap_l: float = GUNART.face_shade(Vector3.LEFT)
	var cap_r: float = GUNART.face_shade(Vector3.RIGHT)
	var rear: float = GUNART.face_shade(Vector3.BACK)
	var front: float = GUNART.face_shade(Vector3.FORWARD)
	v.check("the face ramp hands each axis its own constant",
		v.near(top, GUNART.SHADE_TOP, 1e-9) and v.near(under, GUNART.SHADE_UNDER, 1e-9)
			and v.near(cap_l, GUNART.SHADE_CAP, 1e-9) and v.near(cap_r, GUNART.SHADE_CAP, 1e-9)
			and v.near(rear, GUNART.SHADE_REAR, 1e-9) and v.near(front, GUNART.SHADE_FRONT, 1e-9),
		"top %.4f under %.4f caps %.4f/%.4f rear %.4f front %.4f" % [
			top, under, cap_l, cap_r, rear, front])

	# The blend rule for the 13 circles and 2 rotated rects, which is the half of
	# M5 R1 the first draft did not have — a ramp undefined on a third of the
	# table's parts gets resolved silently by whoever implements it. Hand-computed
	# on a normal 36 degrees off +Y, which is one `CIRCLE_SEGS` step:
	#   w = 0.809017 + 0.587785 = 1.396802
	#   f = (0.809017*1.28 + 0.587785*0.9953) / w = 1.620564 / 1.396802 = 1.160196
	# Its value has to land strictly between the two axes it blends, which is the
	# statement that fails if the rule degenerates to a max, a min or an average.
	var obl: float = GUNART.face_shade(Vector3(0.0, 0.809017, 0.587785))
	v.check("an off-axis facet blends its two axes and lands between them",
		v.near(obl, 1.160196, 1e-5) and obl < GUNART.SHADE_TOP and obl > GUNART.SHADE_REAR,
		"got %.6f, between %.4f and %.4f" % [obl, GUNART.SHADE_REAR, GUNART.SHADE_TOP])

	# The bracket. Minecraft's `FaceBakery.getShade` is UP 1.0 / N-S 0.8 / E-W 0.6 /
	# DOWN 0.5 — a 2:1 top-to-bottom span that TerraFirmaCraft reimplements
	# independently — against the 1.2448:1 the clamped dot product could reach on a
	# box face (M5 F3, and `gunart.gd:264`'s own arithmetic reproduces it).
	v.check("the ramp spans the lineage's 2:1 from top face to bottom",
		v.near(top / under, 2.0, 0.02),
		"%.4f / %.4f = %.4f:1" % [top, under, top / under])
	# M5 R1's actual requirement: the visible groups separated by "materially more
	# than 7.5%". Under the shipped bracket the top stood 4.4% over the visible cap
	# and 7.6% over the stock end, which is the finding. 20% is our floor and it is
	# below what this table delivers (24.8% and 28.6%), so it is a bound rather
	# than a restatement of the current numbers.
	v.check("the top face stands materially clear of both the cap and the stock end",
		top / cap_l > 1.20 and top / rear > 1.20,
		"top/cap %.4f, top/rear %.4f" % [top / cap_l, top / rear])

	# AND THE BAKE ACTUALLY GOES THROUGH IT. Everything above is true of a function
	# nobody calls. This drives the real builder, reads the committed vertex colours
	# and normals back, and requires every vertex to be an authored colour times the
	# shade of its own normal — so a `_tri` that baked a constant, or that kept a
	# dot product, fails here rather than passing four checks about a dead helper.
	# 8-bit vertex colours, hence the 3/255 budget across the three channels — and
	# hence the `clampf`, which is not defensive: `SurfaceTool` stores colours as
	# RGBA8, so a channel driven past 1.0 by `SHADE_TOP` is TRUNCATED, not carried.
	# Found by this check failing on the Ray Gun's mid lens ring (green 0.878 x
	# 1.28 = 1.124, stored 1.0). It is why the ramp above 1.0 is only spendable on
	# art below 1/SHADE_TOP on a channel, which is every gunmetal in the table and
	# none of the four emissive colours.
	var unexplained := ""
	var verts := 0
	for key: String in GUNART.keys():
		var bases: Array[Color] = []
		for part: Array in GUNART._parts(key):
			bases.append(part[part.size() - 1])
		bases.append(GUNART.HAND_MAIN)
		bases.append(GUNART.HAND_CUFF)
		for m: ArrayMesh in [GUNART.build_body(key, false), GUNART.build_slide(key, false)]:
			if m == null:
				continue
			var arr := m.surface_get_arrays(0)
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			for i in cs.size():
				verts += 1
				var f: float = GUNART.face_shade(ns[i])
				var best := 1e9
				for b: Color in bases:
					best = minf(best, absf(cs[i].r - clampf(b.r * f, 0.0, 1.0))
						+ absf(cs[i].g - clampf(b.g * f, 0.0, 1.0))
						+ absf(cs[i].b - clampf(b.b * f, 0.0, 1.0)))
				if best > 3.0 / 255.0:
					if unexplained.length() < 120:
						unexplained += "%s n=%v c=%s off %.4f " % [key, ns[i], cs[i], best]
	v.check("every vertex colour in every weapon is its own art times its own face shade",
		unexplained.is_empty() and verts > 6000,
		"%d vertices, unexplained: %s" % [verts, unexplained])

	# THE GLOW SET, which is what bounds `SHADE_TOP` and `SHADE_CAP` from above.
	# `lighting.gd` thresholds Godot's glow filter on the BRIGHTEST CHANNEL, and
	# `_tint` passes the authored hex through unconverted onto an unshaded surface,
	# so what the filter sees is that channel times the face shade. Read the
	# threshold off `lighting.gd` rather than repeating 0.92, so moving it moves
	# this.
	#
	# Provenance for the expected set: it is the set the SHIPPED bracket produced,
	# face for face, on every face the camera can reach. The dot product put
	# 1.0705 / 1.0254 / 0.9953 on the top, the visible cap and the stock end and
	# clamped the other three to 0.8600; M5 F36 is right that `gunart.gd:266-271`
	# was wrong to claim an emissive part bloomed on all six.
	var thr: float = LIGHTING.GLOW_THRESHOLD
	var core := Color("e8ffc0")          # the Ray Gun's lens core, green 1.0
	var blade := Color("e2e7ec")         # the knife's, blue 0.925 — the brightest non-emissive
	var mid := Color("8fe04a")           # the Ray Gun's mid lens ring, green 0.878
	var rib := Color("7a8085")           # the Olympia's highlight strip, the brightest grey
	# Through `_stored`, because RGBA8 truncates at 1.0 and it is the STORED value
	# the filter sees. Reading the shade product raw would report 1.280 for a
	# channel the mesh carries as 1.000 — right about the verdict, wrong about the
	# margin, which is exactly how `gunart.gd:266-271` came to be wrong twice.
	v.check("the Ray Gun's lens core blooms on the faces it bloomed on before, and no others",
		_stored_ch(core.g, cap_l) > thr and _stored_ch(core.g, top) > thr
			and _stored_ch(core.g, rear) > thr and _stored_ch(core.g, under) < thr
			and _stored_ch(core.g, front) < thr,
		"cap %.3f top %.3f rear %.3f under %.3f front %.3f against %.3f" % [
			_stored_ch(core.g, cap_l), _stored_ch(core.g, top), _stored_ch(core.g, rear),
			_stored_ch(core.g, under), _stored_ch(core.g, front), thr])
	v.check("the knife's blade still catches a highlight on its caps and not underneath",
		_stored_ch(blade.b, cap_l) > thr and _stored_ch(blade.b, top) > thr
			and _stored_ch(blade.b, under) < thr,
		"cap %.3f top %.3f under %.3f against %.3f" % [
			_stored_ch(blade.b, cap_l), _stored_ch(blade.b, top),
			_stored_ch(blade.b, under), thr])
	# The two that bound the ramp from ABOVE. The mid ring sits 0.901 on the cap,
	# 2% under the threshold; raise `SHADE_CAP` by more than that and the Ray Gun
	# grows a second glowing ring nobody asked for. The Olympia's rib is the
	# brightest thing on the roster that is meant to be plain metal.
	v.check("no gunmetal highlight blooms, and the Ray Gun's mid ring stays a ring",
		_stored_ch(mid.g, cap_l) < thr and _stored_ch(mid.g, rear) < thr
			and _stored_ch(rib.b, top) < thr,
		"mid cap %.3f / rear %.3f, rib top %.3f against %.3f" % [
			_stored_ch(mid.g, cap_l), _stored_ch(mid.g, rear), _stored_ch(rib.b, top), thr])


## One channel as the mesh actually carries it: RGBA8, so 1.0 is the ceiling.
static func _stored_ch(channel: float, shade: float) -> float:
	return clampf(channel * shade, 0.0, 1.0)


static func _gun_sights(v: Verify) -> void:
	# M5 F5: at full sights `ADS_CENTRE` and `ADS_LEVEL` are 1.0 and `ADS_YAW` was
	# too, so both caps went edge-on and the only faces left were +Z rear edges of
	# flat plates. `ADS_YAW` is 0.95 now — 5% of the profile survives, worth 1.7 px
	# on the M1911's slide — and that is nowhere near enough to change the argument
	# below: the sights are still what carries the ADS read, and the reason the yaw
	# cannot be reduced further is `shot_setup.gd`'s 80 px probe rect, recorded at
	# viewmodel.gd's ADS_YAW.
	# "Anything that improves the ADS read has to add geometry along +Z" — this is
	# the roster of what got it. The three exclusions are as load-bearing as the
	# inclusions: a Ray Gun, a Thundergun and a Bowie knife have no iron sights and
	# giving them one would be worse than giving nobody one.
	var missing := ""
	for key: String in ["m1911", "olympia", "m14", "mp40", "pm63", "ak74u",
			"stakeout", "m16", "rpk", "chinalake"]:
		var rows: Array = GUNART.SIGHTS.get(key, [])
		if rows.is_empty():
			missing += key + " "
	var wrongly := ""
	for key: String in ["raygun", "thundergun", "knife"]:
		if not GUNART.SIGHTS.get(key, []).is_empty():
			wrongly += key + " "
	v.check("every weapon that should carry iron sights does, and the three that should not do not",
		missing.is_empty() and wrongly.is_empty(),
		"without: %s; wrongly with: %s" % [missing, wrongly])

	# AND THE SIGHT IS THE TOP OF THE WEAPON, which is the only reason to add it:
	# `viewmodel.gd` drops the whole rig by `sight_height()` so that what lands on
	# the view axis is the weapon's own sighting surface. A blade buried inside the
	# receiver would satisfy the roster check above and change nothing at all.
	#
	# Driven through `sight_height()` — the accessor the rig poses with — against
	# the top of the ancestor's own parts, computed from `ART` alone. Art y counts
	# DOWNWARD from the top of the canvas, so the smallest y is the highest point.
	var not_topmost := ""
	for key: String in GUNART.SIGHTS.keys():
		var grip: Vector2 = GUNART.GRIP[key]
		var art_top := 1e9
		for part: Array in GUNART.ART[key]:
			if part[0] == "r":
				art_top = minf(art_top, float(part[2]))
		var art_h: float = (grip.y - art_top) * GUNART.UNIT
		var sight: float = GUNART.sight_height(key)
		# A full art unit clear, and the margin is the point rather than the sign:
		# `sight_height()` walks INFLATED corners, so `PROUD` alone puts it about
		# 0.3 units above the art even when the sight is buried. A bare `>` would
		# pass against a blade sunk inside the receiver, which is the exact shape of
		# a check that discriminates nothing.
		if sight - art_h <= 1.0 * GUNART.UNIT:
			not_topmost += "%s sight %.2f, art %.2f units " % [
				key, sight / GUNART.UNIT, art_h / GUNART.UNIT]
	v.check("...and on every one of them the sight, not the receiver, is the top of the weapon",
		not_topmost.is_empty(), not_topmost)


# --- part 12: `ART` against the ancestor itself --------------------------------
#
# THE AUTHORITY IS READ, instead of a third copy of a statistic derived from it.
#
# There were three statements of one table: `kriegsnacht.html:1151-1207` (the
# authority), `gunart.gd:50`'s `ART` (what the game builds from), and
# `ANCESTOR_PARTS` — thirteen hand-typed integers in this file. The check named for
# part-for-part fidelity compared the second against the third on `Array.size()`, so
# it could only ever notice the two DERIVED copies disagreeing about a COUNT. Every
# geometry, colour, kind and ORDER change passed it silently, and because its loop
# walked `GUNART.keys()` — which is `ART.keys()` (`gunart.gd:1168-1169`) — a weapon
# deleted from `ART` outright was never even asked about.
#
# `ANCESTOR_PARTS` defended itself as "stated here rather than read out of `ART`,
# which would be the tautology `_registered()` exists to avoid". That argument holds
# against reading OURS. It does not hold against reading the ancestor:
# `extract.js:414`'s `sliceRange()` cuts the plaque's own copy out of this same file
# — the `art` range that carries `GUNART` is declared at `extract.js:61-72` and names
# it at `:65`, while `:22` is only the path constant — and `targets.js:150-162` bakes
# from that slice, so `kriegsnacht.html` is UPSTREAM OF BOTH COPIES and thirteen
# integers were a statistic derived from it.
#
# WHAT THIS PROTECTS, and the deleted check's name was wrong about it. It said "so the
# chalk plaques still match". The plaques are baked from the ANCESTOR by
# `targets.js:155`, never from `ART`, and the committed PNGs are byte-identical to a
# fresh bake — so they are a frozen fossil that cannot drift with `ART` at all, and
# only five of the six fields below are anything they could witness. MEASURED
# (2026-08-02, by replaying `makeChalk`): the plaque draws every part through a mono
# colour override (`html:1133`, `'#E8E3D2'` at `:1251`), so recolouring every
# part of all 13 weapons moves 0 of 2080 px; reversing a whole part list moves 28-83
# px at a worst channel-sum delta of 3-6 of 765, which is antialias rounding; and only
# 8 of the 13 keys have a plaque at all (m1911, rpk, chinalake, raygun and thundergun
# have none). So COLOUR and ORDER stand on `_tint` (`gunart.gd:1595-1599`) turning
# each hex into the mesh's vertex colours, on `SLIDE` indexing `ART` by position, and
# on CLAUDE.md's departure doctrine — NOT on the plaque. What this package protects is
# the RECORD and the viewmodel mesh; geometry and kind on the 8 plaqued weapons is the
# only half the plaque corroborates.
#
# AND IT IS DIRECTIONAL. A departure that is not recorded as a deliberate departure is
# wrong even when the departure is right, so a difference fails unless
# `ancestor_art.DEPARTURES` names it with both rows and a reason — and a waiver that
# no longer describes a live difference fails too, because a stale waiver is a skip
# that passes.
#
# TWO THINGS THIS CANNOT SEE, said plainly. It renders nothing, like everything else
# in this file: no frames scenario holds any weapon but the starting M1911 and the Ray
# Gun, so an `ART` drift is invisible to every pixel this project measures. And it
# compares `ART` against the ancestor, not against Black Ops 1 — where those two
# disagree the reference wins, and the register below is the only place that can be
# written down.
#
# THE PARSE GATE GIVES THIS ZERO COVERAGE. `--check-only --script
# scripts/dev/checks/frame.gd` aborts at `frame.gd:1077` on the documented
# `Identifier not found: Rng` autoload false positive, hundreds of lines above here,
# so everything below it is unparsed. Anyone who runs it, recognises the familiar
# autoload noise and concludes "clean apart from that" has checked nothing. That is
# why every non-trivial line lives in `scripts/dev/ancestor_art.gd`, which gates clean
# on its own (MEASURED: EXIT=0), and why what is left here is `v.check` calls.
#
# COST: one ~140 KB read (139 769 bytes here, 143 245 from a CRLF checkout), a newline
# fold, a regex substitution, a JSON parse and a sha256.
#
# MEASURED 2026-08-03 rather than asserted — the figure this replaces said "MEASURED at
# 1.3 ms" and no such measurement was ever run, which is the snapshot-without-provenance
# CLAUDE.md forbids wearing the word MEASURED. Method: `Time.get_ticks_usec()` around
# twenty `ANCESTOR_ART.read()` calls and around the rest of this function, temporarily
# spliced in, `--verify` run three times, then reverted. `read()` is 29.0 / 29.0 /
# 32.6 ms for twenty, i.e. 1.45-1.63 ms each (warm cache — the first of the twenty
# absorbs the cold read). THE TOTAL ONLY, deliberately: the first revision also quoted
# a read/checks SPLIT, and two independent re-measurements of the rest of this function
# got 0.65-1.03 ms against its claimed 1.79-2.27, so the decomposition did not
# reproduce and is not worth a number. The whole of `_gun_ancestor` is about 2.3-3.1 ms
# against a suite that takes about ten seconds, which is what the decision rests on.
static func _gun_ancestor(v: Verify) -> void:
	var res := ANCESTOR_ART.read()
	var anc: Dictionary = res["art"]
	var sha: String = res["sha"]

	# 1. THE AUTHORITY IS THERE, IT IS WHERE THIS SUITE SAYS, AND IT IS THIS ONE.
	# Everything below would pass vacuously against an ancestor that had been renamed:
	# `get_file_as_string()` returns "" for a missing file without raising, the diff
	# over an empty table is empty, and the register is legitimately empty too. So the
	# liveness is asserted here, by name, and the detail prints the anchor TEXT beside
	# the line it was found at — a reformatted ancestor has to read as "the citation
	# moved", not as "the file vanished".
	#
	# The anchors are SCANNED for and then asserted to be at 1151/1207, which makes
	# `gunart.gd:34`'s citation a thing the code enforces rather than a claim that
	# rots. The hash is what makes the citation unrottable in the other direction: a
	# content-pinned file cannot drift its line numbers unnoticed, and the pin catches
	# an ancestor edit the counts and anchors would both survive. CONTENT-pinned, not
	# byte-pinned: `read()` folds CRLF to LF before hashing (`ancestor_art.gd:161-173`),
	# which is what makes a fresh checkout pass — see there for the blind spot that
	# opens. `sha` is left "" by that function's early return when the file cannot be
	# read, hence the length clause; belt and braces with the `why` clause beside it.
	v.check("the ancestor's own weapon table is where this suite cites it, in the kriegsnacht.html this checkout pins",
		String(res["why"]).is_empty()
			and int(res["head"]) == ANCESTOR_ART.HEAD_LINE
			and int(res["tail"]) == ANCESTOR_ART.TAIL_LINE
			and sha.length() == 64 and sha == ANCESTOR_ART.ANCESTOR_SHA,
		ANCESTOR_ART.read_detail(res))

	# 2. The roster and the cardinality, ORDERED, against `ART` itself — which has to
	# be read directly, because the walk below legitimately holds more parts than the
	# ancestor drew. This is the one claim the deleted check actually made, kept and
	# taken from thirteen integers to the table they were counted from.
	var roster := ANCESTOR_ART.roster_diff(anc, GUNART.ART)
	v.check("ART holds exactly the ancestor's weapons, in its order, and exactly as many parts for each",
		roster.is_empty() and not anc.is_empty(), roster)

	# The keys both sides declare. Splitting them out is what lets a roster mistake and
	# a geometry mistake fail INDEPENDENTLY — without it, erasing a weapon from `ART`
	# reddens two checks for one defect and neither control can prove which did the
	# work.
	var keys := ANCESTOR_ART.shared_keys(anc, GUNART.ART)

	# `_parts()`, not `ART`: it is what `_build` (`gunart.gd:1336`) and `_corners`
	# (`:1003`) both walk, and :1411-1422 above already ties that walk to the committed
	# `ArrayMesh` — so the chain runs from `kriegsnacht.html` to the vertices on screen
	# with no copy in the middle. A test that does not read what the game reads is
	# testing a copy.
	#
	# READ ONLY, and it has to stay that way. MEASURED, and RE-MEASURED 2026-08-03
	# after `_parts` was rewritten over `_bands`: `_parts("raygun")` IS `ART["raygun"]`
	# itself and reports `is_read_only() == true`, because `_parts` still returns the
	# `B_ART` rows unchanged when every band after them is empty; `_parts("m1911")` is
	# a fresh concatenation and is not. Exactly three weapons — raygun, thundergun,
	# knife — are on the frozen side, the same three as before. Nothing below mutates
	# it. Anything that later sorts or appends to the result would error on 3 of the 13
	# and pass on the other 10, which is the worst shape a bug can have; a band
	# inserted BEFORE `art` in `_bands()` would silently change which three, and
	# `_gun_bands`' walk check is what watches for it — the property is no longer only
	# a comment.
	var walk := {}
	for key: String in keys:
		walk[key] = GUNART._parts(key)

	# 2b. THE WALK, DECOMPOSED INTO THE BANDS THIS PROJECT DECLARES, which is what
	# `parts_total == 119` above cannot do: 119 is satisfied by 100 ancestor parts plus
	# 19 sight rows, and by a row moved from one band into another in either direction.
	# Three components, each backed by a DIFFERENT authority — 101 against the rows
	# just read out of `kriegsnacht.html` (no second read is paid; `anc` is in hand),
	# 18 against `SIGHT_ROWS`, 0 against `DETAIL_ROWS` — plus two clauses no total
	# could make. Every band may name only weapons `ART` declares, because `keys()`
	# returns `ART.keys()` and a weapon existing only in a later band is invisible to
	# `viewmodel._prebuild`, to `sweep()` and to eleven loops in this suite, silently.
	# And the last band is where anything CONDITIONAL would have to go, which is what
	# the stability property rests on — so a fourth band reddens this and the detail
	# prints the handover list rather than a puzzle.
	var bands := ANCESTOR_ART.band_faults(anc)
	v.check("the roster's parts decompose into the three bands this project declares, and every band names only weapons ART declares",
		String(bands["diff"]).is_empty() and int(bands["n"]) == 133,
		"walked %d parts; %s" % [int(bands["n"]), bands["diff"]])

	var bad: Array = []
	var live := ANCESTOR_ART.waivers(ANCESTOR_ART.DEPARTURES, anc, walk, bad)

	# 3. THE LEAD ASSERTION: every part, field for field — kind, arity, x, y, w, h, the
	# `rr` rotation, the `c` radius, the polygon vertex list and the colour — and, by
	# comparing index against index, ORDER. None of which the deleted check could see.
	# The failure detail is written in the register's own notation, so recording a
	# deliberate departure costs one paste and one sentence.
	var pd := ANCESTOR_ART.part_diff(anc, walk, keys, live)
	var compared: int = pd["n"]
	v.check("every part the ancestor drew is the part the weapon builder walks, field for field",
		String(pd["diff"]).is_empty() and compared > 0,
		"compared %d parts; %s" % [compared, pd["diff"]])

	# 4a. ...and nothing of ours is mixed in AMONG them: everything past the ancestor's
	# parts is the iron sight this project RECORDED, row for row and channel for
	# channel. MEASURED: 101 ancestor parts + 18 recorded sight rows is exactly the 119
	# that `parts_total` pins above, and this asserts the per-weapon form of that sum,
	# which the sum cannot do.
	#
	# WHAT THIS DOES NOT DO, because the revision that shipped first claimed it did:
	# it does not see a row moved from `SIGHTS` into `ART`. The tail is sliced at the
	# ANCESTOR's part count, so a moved row lands back in the tail at the same index and
	# matches this record byte for byte. MEASURED: check 2 is what reddens, on `ART`
	# holding a part the ancestor never drew. `gunart.gd:432-436`'s "appended and never
	# inserted" — the rule `SLIDE`'s positional indices depend on — is enforced there
	# and by 4b's `proud` relation, not here.
	#
	# THE TAIL IS NOW TWO BANDS AND THIS ONE READS THE FIRST. `sight_diff` slices the
	# sight band at the RECORD's own length and hands everything past it to 4c below,
	# so a `DETAIL` row cannot land here and be mistaken for a sight — and a sight row
	# that overflows the record's length cannot hide here either, because it lands in
	# the detail band where `DETAIL_ROWS` is 0. Neither slice point comes from
	# `SIGHTS`, which is the side under test.
	#
	# THE EXPECTATION IS NOT `GUNART.SIGHTS`, AND THAT IS THE WHOLE REPAIR. The check
	# this replaces passed `SIGHTS` in as the expectation against a walk that IS
	# `ART + SIGHTS`, so both sides of every comparison were one const and every edit
	# moved them together — MEASURED, a destroyed M16 front tower, reversed RPK sight
	# rows and a magenta M14 front post each passed the whole suite as it then stood,
	# 789 green and nothing red, and so did an `ART` colour with its alpha at zero. The
	# expectation now lives in `ancestor_art.gd`, the tail is sliced at the ANCESTOR's
	# own part count, and the count is of ROWS rather than of weapons, so `SIGHTS`
	# emptied outright cannot report thirteen comparisons having made none.
	var sd := ANCESTOR_ART.sight_diff(anc, walk, keys)
	var rows: int = sd["n"]
	var faults := ANCESTOR_ART.record_faults()
	v.check("...and everything past the ancestor's parts is the iron sight this project recorded, field for field",
		String(sd["diff"]).is_empty() and faults.is_empty()
			and rows == ANCESTOR_ART.SIGHT_ROWS,
		"compared %d of the %d recorded sight rows; %s%s" % [
			rows, ANCESTOR_ART.SIGHT_ROWS, sd["diff"], faults])

	# 4b. AND THE HALF A RE-PASTE CANNOT SATISFY. A record is a table of absolutes and
	# absolutes are what get re-pasted by an agent in a hurry; `golden.json`'s
	# `relations` block is this project's standing answer to that, and these are the
	# same thing for the sights — five named rules over the same walked tail, each with
	# its own provenance in `gunart.gd`'s design comments. MEASURED: sabotage `SIGHTS`
	# AND update the record to match, and this still fails — `cue` for a shortened M16
	# tower, `order` for reversed RPK rows, `colour` for a magenta M14 post, `proud` for
	# a blade sunk into the carry handle it stands on.
	#
	# Its own row counter, deliberately not shared with 4a: 4b walks the tails while 4a
	# walks the record, so a tail that is somehow non-empty but unrecorded makes the two
	# counts disagree and reddens both.
	var sr := ANCESTOR_ART.sight_rules(GUNART.ART, sd["tails"])
	var seen: int = sr["n"]
	v.check("...and every one of them is still a sight: proud of what it is mounted on, post ahead of blade, one colour, the M16's tower the tallest",
		String(sr["diff"]).is_empty() and seen == ANCESTOR_ART.SIGHT_ROWS,
		"measured %d of the %d recorded sight rows; %s" % [
			seen, ANCESTOR_ART.SIGHT_ROWS, sr["diff"]])

	# 4c. AND EVERYTHING PAST THE SIGHTS IS THE DETAIL BAND, which is empty and is
	# recorded as empty. This is the band `gunart.gd`'s `DETAIL` opened so our own
	# non-sight geometry has somewhere to go that is neither a forged ancestor part nor
	# a lie about what a sight is — and the reason 4b above could be narrowed to the
	# sight band without the two rules it gave up going unwatched.
	#
	# THREE THINGS ANDED, because the live table is EMPTY and a validator run over an
	# empty band asserts precisely nothing — the shape CLAUDE.md calls a skip that
	# passes. The band matches its record; the record is well formed and totals
	# `DETAIL_ROWS`; and `detail_self_test()` drives the REAL `detail_rules()` over
	# fixtures — one well-formed row that must be HONOURED, and one malformed row per
	# rejection clause, each refused BY THE CLAUSE IT NAMES. That last requirement is
	# not tidiness: the first draft of those fixtures keyed the rows `fixture` against
	# hosts keyed `knife`, so all four found no parts at all and were intercepted by
	# `seat` two clauses early — the identical defect §5's own fixtures were rewritten
	# to remove, reproduced within one package of it being written down.
	var dets: Dictionary = sd["details"]
	var dn := 0
	for key: String in dets:
		dn += (dets[key] as Array).size()
	var dr := ANCESTOR_ART.detail_rules(GUNART.ART, dets)
	var df := ANCESTOR_ART.detail_faults()
	var dfx := ANCESTOR_ART.detail_self_test()
	# `detail_diff` is the half the name claims and `detail_faults` does not do: the
	# RECORD against the BAND. Without it the record validated only its own shape, and
	# a record disagreeing with every live row in x, y, w, h and colour passed green —
	# see `ancestor_art.detail_diff`. Harmless while the band is empty, and the band
	# existing is the whole package.
	var dd := ANCESTOR_ART.detail_diff(dets)
	v.check("...and everything past the sights is the detail band this project recorded, every row of it a surface feature",
		String(dr["diff"]).is_empty() and String(dd["diff"]).is_empty()
			and df.is_empty() and dfx.is_empty()
			and dn == ANCESTOR_ART.DETAIL_ROWS and int(dr["n"]) == dn
			and int(dd["n"]) == dn,
		"the band walks %d rows against DETAIL_ROWS %d, the rules measured %d, the record %d; %s%s%s%s" % [
			dn, ANCESTOR_ART.DETAIL_ROWS, int(dr["n"]), int(dd["n"]),
			dr["diff"], dd["diff"], df, dfx])

	# 5. And the register is honest. THIS IS THE ONE THAT WOULD OTHERWISE BE A SKIP
	# THAT PASSES: `DEPARTURES` is legitimately empty, so a validator run over it alone
	# asserts nothing at all. So the real register is ANDed with `self_test()`, which
	# drives the same validator over ten fixtures — a live waiver on a rect and on a
	# polygon must be honoured, and eight malformed, out-of-range, stale or unreasoned
	# ones must be refused BY THE CLAUSE EACH ONE NAMES. That last requirement is not
	# tidiness: the first draft had a fixture printing "a waiver for a difference that
	# is gone was honoured" which was intercepted two clauses earlier and never reached
	# the clause it named, so `part_reason(...).is_empty()` could be deleted with the
	# suite still green. MEASURED, three of the six rejection clauses were uncontrolled
	# that way; all six are controlled now, each by deleting it and watching this check
	# alone go red. It had already earned its place before that: it caught this author
	# pinning `r|1|2|3|4|...` when `row_text` renders `r|1.0|2.0|3.0|4.0|...`, before
	# the register had a single row in it.
	#
	# A rejected waiver suppresses nothing, so a bad waiver reddens check 3 as well
	# rather than hiding a real drift while this one complains about the paperwork.
	var fixtures := ANCESTOR_ART.self_test()
	v.check("every recorded departure from the ancestor is a live difference, exact on both sides and reasoned",
		bad.is_empty() and fixtures.is_empty(),
		"%s %s" % [str(bad), fixtures])
