extends RefCounted

## Numbers about a RENDERED FRAME, and the tolerance arithmetic that turns them
## into a gate.
##
## This exists because of §4 of the workflow audit: two milestones shipped a
## near-black frame that every one of 483 assertions passed, and a zombie rim at
## 3.4x the brightness of the body it outlined was found only because somebody
## opened a PNG. The only pixel-level checks in the suite read SOURCE textures.
## Nothing read a frame.
##
## ---------------------------------------------------------------------------
## THE COLOUR SPACE, because this project has shipped two bugs from exactly this
## confusion and a statistic in the wrong space is worse than no statistic.
##
## `get_viewport().get_texture().get_image()` comes back FORMAT_RGBA8 holding the
## pipeline's OUTPUT: linear radiance -> FILMIC -> sRGB encode. `Image.get_pixel`
## and `Image.get_data` return those stored bytes verbatim; Godot applies no
## transfer function on the way out. So a byte of 128 is a DISPLAY CODE VALUE,
## not half the light.
##
## **Every luminance in this file is LINEAR relative luminance in [0,1].** Each
## channel is decoded with the sRGB EOTF (IEC 61966-2-1) and combined with the
## Rec.709 weights. The reason is that the two defects this file exists to catch
## are both statements about LIGHT — "this frame emits far less light than it
## used to", "this edge emits 3.4x the light of the body it outlines" — and a
## mean over encoded bytes is not a mean over light. On a scene as dark as this
## one the difference is not cosmetic: the encode lifts the bottom of the range
## hard, so an encoded mean compresses exactly the range where every one of these
## bugs lived.
##
## Two consequences, both deliberate:
##
##   - The numbers are SMALL. A playable frame of this game means about 0.01
##     linear. That is not a bug in the measurement; it is what a dark room
##     emits. Every stat dict therefore also carries `code`, the display code
##     value that mean re-encodes to, so a human can compare it against the
##     "146/255 against 42" in the M4 review without doing the maths.
##   - RATIOS ARE LINEAR RATIOS and are therefore LARGER than the display-space
##     ratios quoted in that review. The shipped rim at 0.62 measured 146 vs 42
##     in display code, a ratio of 3.48; the same pixels in linear light are
##     0.2747 vs 0.0219, a ratio of 12.5. Both describe the same defect. Linear
##     is used here because it is the one that means something physically, and
##     because it discriminates harder.
##
## ---------------------------------------------------------------------------
## WHY RATIOS AT ALL. Absolute brightness drifts every time somebody retunes a
## lamp, and a gate that has to be re-blessed after every tuning pass is a gate
## somebody eventually deletes. The two defects that actually shipped were both
## RELATIONAL: a frame far darker than every other frame, and an outline far
## brighter than its body. `relations` below is the half of the gate that
## survives a retune, and it is the half worth trusting.
##
## ---------------------------------------------------------------------------
## AND WHY LUMINANCE IS NOT ENOUGH. A luminance is one number out of three, and
## the first version of this file kept only that one. MEASURED, by swapping
## lighting.gd's AMBIENT_COLOR from (0.30, 0.32, 0.36) to (0.36, 0.32, 0.30) —
## the room's colour temperature inverted from cold to warm at a Rec.709
## luminance 2.6% away from the original — and re-running the whole gate:
##
##   ALL TEN RELATIONS PASSED. The only objections were six absolute rows
##   (`spawn.median`, `trap_armed.p01`, `ads.median` and three raygun probes),
##   all of them 8-bit quantisation at the very bottom of the range, and all of
##   them in the half of the golden file that `-Bless` REGENERATES.
##
## So the durable half of the gate could not see a hue inversion at all, and the
## fragile half's objection would be erased by the next bless. That is a bad
## place for a project whose only two shipped rendering defects were BOTH colour
## errors, and whose whole palette is a single sodium illuminant.
##
## `chroma_rg` and `chroma_bg` close it: the ratios of the summed LINEAR channels
## over the lit pixels, i.e. the frame's average chromaticity. They are invariant
## to a uniform scale of all three channels — which is what a lamp-energy retune
## is — and they move hard under a hue error. Bounded in `relations`, which
## `-Bless` never rewrites, so a hue change has to be re-argued by hand.
const CHROMA_KEYS := ["chroma_rg", "chroma_bg"]

## The display code at or below which a pixel reads as crushed black, and at or
## above which it reads as blown. Stated in DISPLAY code because "this pixel
## looks black on a screen" is a display-space claim; converted to linear once,
## here, so nothing downstream has to think about it again.
const BLACK_CODE := 8.0 / 255.0
const BLOWN_CODE := 250.0 / 255.0

## A 4x4 tiling of the frame. Coarse on purpose: the point is "the left half of
## the frame went dark", not a per-pixel diff, and a fine grid would make every
## cell a tiny sample that jitters on its own.
const GRID := 4

## Rec.709 luminance weights, applied to LINEARISED channels.
const LUM_R := 0.2126
const LUM_G := 0.7152
const LUM_B := 0.0722

## The sRGB EOTF for all 256 byte values, built once. A pow() per channel per
## pixel is 2.8 million pow() calls on a 1280x720 frame; a table is three array
## reads.
static var _decode: PackedFloat32Array


# --- transfer functions -------------------------------------------------------

## IEC 61966-2-1. Godot's own `Color.srgb_to_linear()` uses a pure 2.2 gamma
## approximation, which is wrong by up to 1.6 code values at the bottom of the
## range — precisely where every frame of this game lives. Written out rather
## than borrowed for that reason.
static func srgb_to_linear(u: float) -> float:
	if u <= 0.04045:
		return u / 12.92
	return pow((u + 0.055) / 1.055, 2.4)


static func linear_to_srgb(l: float) -> float:
	if l <= 0.0031308:
		return l * 12.92
	return 1.055 * pow(l, 1.0 / 2.4) - 0.055


## Linear relative luminance of one stored (i.e. sRGB-encoded) pixel.
static func luma(c: Color) -> float:
	return (LUM_R * srgb_to_linear(c.r)
		+ LUM_G * srgb_to_linear(c.g)
		+ LUM_B * srgb_to_linear(c.b))


## A linear luminance expressed as the 0..255 display code it encodes to. For
## reading, never for comparing — the gate always compares linear values.
static func code(l: float) -> float:
	return linear_to_srgb(clampf(l, 0.0, 1.0)) * 255.0


static func _table() -> PackedFloat32Array:
	if _decode.size() == 256:
		return _decode
	var t := PackedFloat32Array()
	t.resize(256)
	for i in 256:
		t[i] = srgb_to_linear(float(i) / 255.0)
	_decode = t
	return t


# --- whole-frame statistics ---------------------------------------------------

## Every number the gate holds about one frame.
##
## One pass over the bytes for the sums and the counts, then one native sort for
## the order statistics. The sort is 3.7 MB and a C++ qsort; doing it this way
## instead of a histogram keeps the median EXACT, which matters because the
## median is the statistic that survives a muzzle flash or a power-up sitting in
## frame while the mean does not.
static func of(img: Image) -> Dictionary:
	var im := img
	if im.get_format() != Image.FORMAT_RGBA8:
		im = img.duplicate()
		im.convert(Image.FORMAT_RGBA8)
	var w := im.get_width()
	var h := im.get_height()
	var n := w * h
	var data := im.get_data()
	var lut := _table()

	var ys := PackedFloat32Array()
	ys.resize(n)
	var sum := 0.0
	var black := 0
	var blown := 0
	var black_lin := srgb_to_linear(BLACK_CODE)
	var blown_lin := srgb_to_linear(BLOWN_CODE)

	# Region accumulators. Row-major, GRID*GRID cells; the last column and row
	# absorb the remainder so a width that does not divide by 4 cannot drop a
	# strip of pixels out of every cell.
	var rsum := PackedFloat64Array()
	rsum.resize(GRID * GRID)
	var rcount := PackedInt32Array()
	rcount.resize(GRID * GRID)

	# Channel sums over the LIT pixels only. Crushed black is (0,0,0) plus 8-bit
	# noise, and its chromaticity is meaningless — 72% of the spawn frame sits at
	# or below display code 8, so including it would drag every chromaticity
	# toward whatever the quantisation floor happens to be and make the statistic
	# a measurement of the dither rather than of the light.
	var csum_r := 0.0
	var csum_g := 0.0
	var csum_b := 0.0

	var i := 0
	for y in h:
		var gy: int = mini(y * GRID / h, GRID - 1)
		var row := gy * GRID
		for x in w:
			var cr: float = lut[data[i]]
			var cg: float = lut[data[i + 1]]
			var cb: float = lut[data[i + 2]]
			var l: float = LUM_R * cr + LUM_G * cg + LUM_B * cb
			i += 4
			ys[y * w + x] = l
			sum += l
			if l <= black_lin:
				black += 1
			else:
				if l >= blown_lin:
					blown += 1
				csum_r += cr
				csum_g += cg
				csum_b += cb
			var cell: int = row + mini(x * GRID / w, GRID - 1)
			rsum[cell] += l
			rcount[cell] += 1

	var regions := PackedFloat32Array()
	regions.resize(GRID * GRID)
	for c in GRID * GRID:
		regions[c] = float(rsum[c] / float(maxi(rcount[c], 1)))

	var sorted := ys.duplicate()
	sorted.sort()
	var mean := sum / float(n)

	return {
		"w": w,
		"h": h,
		"mean": mean,
		"median": float(sorted[n / 2]),
		"p01": float(sorted[int(float(n) * 0.01)]),
		"p99": float(sorted[mini(int(float(n) * 0.99), n - 1)]),
		"black": float(black) / float(n),
		"blown": float(blown) / float(n),
		"regions": regions,
		# The frame's average chromaticity over its lit pixels, green-normalised
		# because green carries 72% of Rec.709 luminance and is therefore the
		# steadiest denominator. `ratio()` and not a bare divide: a frame with no
		# lit pixel at all returns -1.0, which is outside every band, rather than
		# a 0/0 that would read as "perfectly neutral" — the empty-mask failure
		# this file is careful about everywhere else.
		"chroma_rg": ratio(csum_r, csum_g),
		"chroma_bg": ratio(csum_b, csum_g),
		# Display-code convenience only. Never compared.
		"code": code(mean),
	}


## Mean linear luminance over a rectangle, clipped to the image.
static func rect_mean(img: Image, r: Rect2i) -> float:
	var m := masked(img, r, func(_c: Color) -> bool: return true)
	var v: float = m["mean"]
	return v


## Mean linear luminance over the pixels of `r` that `pred` accepts, plus how
## many there were.
##
## THE POINT OF THIS FUNCTION IS THE `count`. A masked mean with an empty mask is
## the shape of every test that passes while testing nothing: the rim goes to
## zero energy, no pixel matches "cold", the mean of nothing is 0.0, and a naive
## `ratio < 2.0` check goes green on a frame with no rim in it at all. Callers
## MUST bound the count at both ends. `frac` is there so they can.
##
## `pred` is a Callable per pixel, so this is for RECTANGLES, not for frames: a
## full 1280x720 pass would be 921600 Callable invocations. Every caller here
## passes a rect a few hundred pixels on a side.
static func masked(img: Image, r: Rect2i, pred: Callable) -> Dictionary:
	var clip := r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var sum := 0.0
	var hits := 0
	var ysum := 0.0
	var total := maxi(clip.size.x * clip.size.y, 0)
	for y in range(clip.position.y, clip.position.y + clip.size.y):
		for x in range(clip.position.x, clip.position.x + clip.size.x):
			var c := img.get_pixel(x, y)
			if pred.call(c):
				sum += luma(c)
				ysum += float(y - clip.position.y)
				hits += 1
	return {
		"mean": sum / float(maxi(hits, 1)),
		"count": hits,
		"total": total,
		"frac": float(hits) / float(maxi(total, 1)),
		# WHERE the matched pixels sit, as a fraction down the rect. A mean says
		# how bright a thing is and a frac says how much of the rect it fills;
		# neither says whether it MOVED, and an element that slid down the screen
		# keeps both. 0.5 is centred. -1.0 when nothing matched, so an empty mask
		# cannot read as "perfectly centred".
		"cy": (ysum / float(hits)) / float(maxi(clip.size.y, 1)) if hits > 0 else -1.0,
	}


# --- where a thing IS, rather than how bright it is --------------------------

## The bounding box of the pixels that DIFFER between two frames of the same world
## instant — for locating an element by removing it and seeing what changed.
##
## WHY A DIFFERENCE AND NOT A COLOUR MASK. The gate had no geometric statistic at
## all, which is how a sight line 64 px above the crosshair passed `the sights keep
## the frame` (photometric, 0.909, band [0.78, 1.10]) without moving it a
## thousandth. The obvious fix is a mask — the M1911's slide is the one cool
## desaturated thing in a sodium-lit room — and viewmodel.gd rejected exactly that
## when it derived ADS_SIGHT_CLEAR: "the M1911's slide is the only blue-grey thing
## in the table and a mask tuned to it cannot tabulate the other twelve". Its own
## sweep located the silhouette by differencing against the same frame with the
## viewmodel hidden. This is that technique, once, in the gate.
##
## It also cannot be fooled by the thing a mask is fooled by. The ADS probe rect
## reads `gun_lit_frac` 0.95 — nearly every pixel in it is above the black floor —
## so "the topmost lit row" in that rect is the top of the RECT and says nothing at
## all about where the weapon is. The difference says only where the weapon is.
##
## `thresh` is a per-channel display-code delta and `min_run` the number of
## qualifying pixels a row needs before it counts, so one stray pixel of dither
## cannot claim the top edge. Both MEASURED — see `_probe_silhouette` in
## shot_setup.gd for the numbers and the noise floor.
##
## A row is in or out as a whole: `x0/x1` are only widened by rows that qualify,
## because a box widened by a row that was itself rejected would describe a shape
## the caller was told did not exist.
static func changed_box(a: Image, b: Image, thresh := 3, min_run := 4) -> Dictionary:
	var empty := {"x0": -1, "y0": -1, "x1": -1, "y1": -1, "count": 0, "rows": 0}
	if a == null or b == null:
		return empty
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return empty
	var ia := a
	if ia.get_format() != Image.FORMAT_RGBA8:
		ia = a.duplicate()
		ia.convert(Image.FORMAT_RGBA8)
	var ib := b
	if ib.get_format() != Image.FORMAT_RGBA8:
		ib = b.duplicate()
		ib.convert(Image.FORMAT_RGBA8)
	var w := ia.get_width()
	var h := ia.get_height()
	var da := ia.get_data()
	var db := ib.get_data()

	var x0 := w
	var x1 := -1
	var y0 := h
	var y1 := -1
	var count := 0
	var rows := 0
	var i := 0
	for y in h:
		var rx0 := w
		var rx1 := -1
		var run := 0
		for x in w:
			var d0: int = absi(int(da[i]) - int(db[i]))
			var d1: int = absi(int(da[i + 1]) - int(db[i + 1]))
			var d2: int = absi(int(da[i + 2]) - int(db[i + 2]))
			i += 4
			if maxi(d0, maxi(d1, d2)) < thresh:
				continue
			run += 1
			if x < rx0:
				rx0 = x
			if x > rx1:
				rx1 = x
		if run < min_run:
			continue
		rows += 1
		count += run
		y0 = mini(y0, y)
		y1 = maxi(y1, y)
		x0 = mini(x0, rx0)
		x1 = maxi(x1, rx1)
	if rows == 0:
		return empty
	return {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "count": count, "rows": rows}


## `a / b`, with the degenerate case named rather than silently producing inf or
## a NaN that compares false against every bound and therefore fails open in some
## comparators and closed in others. -1.0 is outside every legitimate band, so a
## caller that forgets to check still fails.
static func ratio(a: float, b: float) -> float:
	if b <= 0.0:
		return -1.0
	return a / b


# --- the tolerance arithmetic -------------------------------------------------

## `|a - b| <= abs + rel * max(|a|, |b|)`.
##
## Both terms are needed and neither alone works here. A pure relative tolerance
## is meaningless on a statistic that is legitimately near zero — `blown` is
## 0.0000 in half these scenarios, and 0% of 0 admits nothing at all, so any
## driver dither at all trips it. A pure absolute tolerance either has to be
## sized for the brightest scenario, which makes it blind on the darkest, or
## sized for the darkest, which makes it trip constantly on the brightest.
static func within(a: float, b: float, abs_tol: float, rel_tol: float) -> bool:
	return absf(a - b) <= abs_tol + rel_tol * maxf(absf(a), absf(b))


static func _tol(tol: Dictionary, key: String) -> Array:
	var row: Dictionary = tol.get(key, {})
	var a: float = row.get("abs", 0.0)
	var r: float = row.get("rel", 0.0)
	return [a, r]


## Compares one scenario's fresh statistics against its golden row.
##
## Returns a list of human-readable failures; empty means it passed. A list
## rather than a bool because "the frame drifted" is not actionable and "region
## 5 is 0.0041 against a golden 0.0102" is.
##
## A MISSING GOLDEN ROW IS A FAILURE, not a skip. A scenario that has never been
## blessed has never been rendered by anybody, and letting it pass quietly is the
## exact failure mode §3 of the audit calls invisible coverage.
static func compare(golden: Dictionary, got: Dictionary, tol: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if golden.is_empty():
		out.append("no golden row — this scenario has never been blessed")
		return out

	for key: String in ["mean", "median", "p01", "p99"]:
		if not golden.has(key) or not got.has(key):
			out.append("%s: missing from %s" % [key, "golden" if not golden.has(key) else "capture"])
			continue
		var t := _tol(tol, "mean")
		var g: float = golden[key]
		var v: float = got[key]
		if not within(v, g, t[0], t[1]):
			out.append("%s %.6f vs golden %.6f (code %.1f vs %.1f)" % [
				key, v, g, code(v), code(g)])

	# Chromaticity gets its own band and not `mean`'s. It is an O(1) ratio rather
	# than a small linear value, so the 5e-6 absolute term that keeps `ads.median`
	# comparable is noise here, and a 3% window on a quantity that sits at 1.4 is
	# four times wider than the smallest hue error worth catching.
	for key: String in CHROMA_KEYS:
		if not golden.has(key) or not got.has(key):
			out.append("%s: missing from %s" % [key, "golden" if not golden.has(key) else "capture"])
			continue
		var t := _tol(tol, "chroma")
		var g: float = golden[key]
		var v: float = got[key]
		if not within(v, g, t[0], t[1]):
			out.append("%s %.4f vs golden %.4f" % [key, v, g])

	for key: String in ["black", "blown"]:
		if not golden.has(key) or not got.has(key):
			out.append("%s: missing" % key)
			continue
		var t := _tol(tol, "frac")
		var g: float = golden[key]
		var v: float = got[key]
		if not within(v, g, t[0], t[1]):
			out.append("%s %.4f vs golden %.4f" % [key, v, g])

	var gr: Array = golden.get("regions", [])
	var vr: Variant = got.get("regions", [])
	var vra: Array = Array(vr)
	if gr.size() != vra.size():
		out.append("region grid is %d cells, golden has %d" % [vra.size(), gr.size()])
	else:
		var t := _tol(tol, "region")
		for c in gr.size():
			var g: float = gr[c]
			var v: float = vra[c]
			if not within(v, g, t[0], t[1]):
				out.append("region %d,%d %.6f vs golden %.6f" % [
					c / GRID, c % GRID, v, g])

	# Scenario-specific scalars — the rim/body ratio and friends. Same treatment,
	# and the same rule: present in golden and absent from the capture is a
	# failure, because the probe that produced it has stopped running.
	var gp: Dictionary = golden.get("probes", {})
	var vp: Dictionary = got.get("probes", {})
	var t2 := _tol(tol, "probe")
	for key: String in gp.keys():
		if not vp.has(key):
			out.append("probe '%s' was not measured this run" % key)
			continue
		var g: float = gp[key]
		var v: float = vp[key]
		if not within(v, g, t2[0], t2[1]):
			out.append("probe %s %.4f vs golden %.4f" % [key, v, g])
	return out


# --- relations, the half that survives a retune -------------------------------

## Resolves "spawn.mean" or "horde.probes.rim_over_body" against a bag of
## per-scenario statistics. Returns NAN when the path does not exist, which
## `relations()` reports as a failure rather than treating as zero.
static func path(stats: Dictionary, p: String) -> float:
	var parts := p.split(".")
	var cur: Variant = stats
	for seg: String in parts:
		if typeof(cur) != TYPE_DICTIONARY:
			return NAN
		var d: Dictionary = cur
		if not d.has(seg):
			return NAN
		cur = d[seg]
	if typeof(cur) == TYPE_FLOAT or typeof(cur) == TYPE_INT:
		return float(cur)
	return NAN


## Evaluates the declared cross-scenario relations — "the powered frame is
## brighter than the unpowered one by between 1.1x and 3x", "no scenario is
## darker than a tenth of the spawn view".
##
## These are the assertions that do NOT need re-blessing when somebody retunes a
## lamp, and they are the ones that would have caught both black frames: a
## display-space value used as a linear one moved the whole frame by an order of
## magnitude, which no tolerance band on a ratio would absorb.
## A rule with NO `den` is a bound on `num` itself (denominator 1.0). That is not
## a loophole back to absolutes: the point of this block is not that everything in
## it is a ratio, it is that everything in it is HAND-SET WITH PROVENANCE and
## `-Bless` never rewrites it. A chromaticity is already a ratio of channels and
## has no meaningful second term; bounding it here rather than in `scenarios` is
## what stops a hue change riding in on the next bless (see CHROMA_KEYS).
static func relations(stats: Dictionary, rules: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for rule: Dictionary in rules:
		var name: String = rule.get("name", "?")
		var den_path := String(rule.get("den", ""))
		var num := path(stats, String(rule.get("num", "")))
		var den := 1.0 if den_path.is_empty() else path(stats, den_path)
		if is_nan(num) or is_nan(den):
			out.append("%s: cannot resolve %s / %s" % [
				name, rule.get("num", ""), den_path if not den_path.is_empty() else "1"])
			continue
		var r := ratio(num, den)
		var lo: float = rule.get("min", 0.0)
		var hi: float = rule.get("max", INF)
		if r < lo or r > hi:
			out.append("%s: %.3f outside [%.3f, %.3f]  (%s=%.6f / %s=%.6f)" % [
				name, r, lo, hi, rule.get("num", ""), num, rule.get("den", ""), den])
	return out


# --- serialisation ------------------------------------------------------------

## Where the gate's committed numbers and its reference images live.
##
## THE GATE IS THE NUMBERS, NOT THE IMAGES, and that is a deliberate choice
## against the audit's own §7.8 ("store references, compare, fail on drift").
## Three reasons, and the first is the one that decides it:
##
##   - A pixel-exact comparison fails on things that are not defects. It is
##     already true on this machine that the spawn frame is byte-identical across
##     runs; it will not be true across a driver update, a different GPU, or the
##     resolution change that `window/size/viewport_width` is one edit away from.
##     A gate that cries wolf on a driver update is a gate somebody disables.
##   - A JSON of statistics is REVIEWABLE. "mean 0.0081 -> 0.0009" in a diff is
##     a finding; a changed PNG blob is a request to go and look.
##   - This repo already ships a 38 MB wasm. 1280x720 PNGs of seven scenarios at
##     every bless would be tens of megabytes of history for a comparison that
##     the numbers already make.
##
## The reference PNGs are still written, and still committed, because statistics
## cannot replace the human pass — the 3.4x rim was found by a person looking at
## one. They are evidence for that pass, not the gate.
const DIR := "res://notes/perf/frames"
const GOLDEN := "res://notes/perf/frames/golden.json"
## Per-run output. Overwritten every run and deliberately NOT the reference: a
## failing run that overwrote its own baseline would erase the evidence of the
## failure on the way to reporting it.
const CURRENT := "res://notes/perf/frames/current"
const REF := "res://notes/perf/frames/ref"


static func load_golden() -> Dictionary:
	if not FileAccess.file_exists(GOLDEN):
		return {}
	var text := FileAccess.get_file_as_string(GOLDEN)
	var v: Variant = JSON.parse_string(text)
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return v


## Writes one scenario's capture to `current/`, both halves: the PNG for a human
## and the JSON for the gate.
static func record(name: String, stats: Dictionary, img: Image) -> void:
	DirAccess.make_dir_recursive_absolute(CURRENT)
	DirAccess.make_dir_recursive_absolute(REF)
	img.save_png("%s/%s.png" % [CURRENT, name])
	var f := FileAccess.open("%s/%s.json" % [CURRENT, name], FileAccess.WRITE)
	if f == null:
		push_error("[frames] cannot write %s/%s.json" % [CURRENT, name])
		return
	f.store_string(JSON.stringify(to_json_row(stats), "  "))
	f.close()


static func load_current(name: String) -> Dictionary:
	var p := "%s/%s.json" % [CURRENT, name]
	if not FileAccess.file_exists(p):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return v


## The gate. Reads every scenario's fresh capture out of `current/`, compares it
## against `golden.json`, evaluates the declared cross-scenario relations, prints
## a table and returns the number of failures.
##
## Headless — it renders nothing and only reads JSON, which is why it is a
## separate invocation from the windowed capture and why `checks/frame.gd` can
## exercise the same code path inside `--verify`.
static func report(names: PackedStringArray) -> int:
	var golden := load_golden()
	if golden.is_empty():
		print("[frames] NO GOLDEN FILE at %s — nothing to compare against." % GOLDEN)
		print("[frames] bless one with: pwsh tools/frames.ps1 -Bless")
		return 1

	var gscen: Dictionary = golden.get("scenarios", {})
	var tol: Dictionary = golden.get("tolerance", {})
	var want_w: int = int(Array(golden.get("resolution", [0, 0]))[0])
	var want_h: int = int(Array(golden.get("resolution", [0, 0]))[1])

	var fresh := {}
	var fails := 0
	var lines: Array[String] = []

	print("\n=== frames ===")
	print("%-12s %9s %7s %9s %8s %8s  %s" % [
		"scenario", "mean", "code", "median", "black", "blown", "verdict"])
	for name: String in names:
		var got := load_current(name)
		if got.is_empty():
			print("%-12s %s" % [name, "NO CAPTURE — the windowed pass did not produce one"])
			fails += 1
			continue
		fresh[name] = got
		var bad := PackedStringArray()
		# A capture at a different resolution is not a drift, it is a different
		# measurement — the viewmodel probe rect alone is pinned in pixels.
		var gw: int = int(got.get("w", 0))
		var gh: int = int(got.get("h", 0))
		if want_w > 0 and (gw != want_w or gh != want_h):
			bad.append("captured at %dx%d, golden is %dx%d" % [gw, gh, want_w, want_h])
		bad.append_array(compare(gscen.get(name, {}), got, tol))
		var mean: float = got.get("mean", 0.0)
		var median: float = got.get("median", 0.0)
		var black: float = got.get("black", 0.0)
		var blown: float = got.get("blown", 0.0)
		print("%-12s %9.6f %7.1f %9.6f %8.4f %8.4f  %s" % [
			name, mean, code(mean), median, black, blown,
			"ok" if bad.is_empty() else "DRIFT"])
		for b: String in bad:
			lines.append("  %-12s %s" % [name, b])
		fails += bad.size()

	var rules: Array = golden.get("relations", [])
	if not rules.is_empty():
		print("\n=== relations ===")
		var rel := relations(fresh, rules)
		for rule: Dictionary in rules:
			var num := path(fresh, String(rule.get("num", "")))
			# Same "no den means bound the value itself" rule the evaluator uses,
			# and it has to be the same here or the table would print `nan` beside
			# a rule the evaluator passed.
			var dp := String(rule.get("den", ""))
			var den := 1.0 if dp.is_empty() else path(fresh, dp)
			var r := ratio(num, den)
			# Five decimals, not two: `rim_frac / body_frac` lives at 0.008 and a
			# %.2f band prints as "[0.01, 0.01]", which reads as a broken rule.
			print("%-46s %10.5f  [%.5f, %.5f]  %s" % [
				rule.get("name", "?"), r,
				float(rule.get("min", 0.0)), float(rule.get("max", INF)),
				"ok" if (r >= float(rule.get("min", 0.0))
					and r <= float(rule.get("max", INF))) else "OUT OF BAND"])
		for e: String in rel:
			lines.append("  relation     %s" % e)
		fails += rel.size()

	if not lines.is_empty():
		print("\n=== drift ===")
		for l: String in lines:
			print(l)
	print("\n=== %d scenarios, %d failure(s) ===" % [names.size(), fails])
	return fails


## JSON cannot hold a PackedFloat32Array and `JSON.stringify` turns one into a
## string rather than an array, which then reloads as a string and compares
## unequal against every golden value forever. Widened here, once.
static func to_json_row(s: Dictionary) -> Dictionary:
	var out := s.duplicate()
	var regions: Array = []
	var r: Variant = s.get("regions", PackedFloat32Array())
	for v: float in Array(r):
		# Six decimals is about 1/4 of a display code value at the dark end of
		# this game's range — finer than anything the gate can distinguish, and
		# short enough that a golden file stays reviewable in a diff.
		regions.append(snappedf(v, 0.000001))
	out["regions"] = regions
	for k: String in ["mean", "median", "p01", "p99", "black", "blown", "code",
			"chroma_rg", "chroma_bg"]:
		if out.has(k):
			var v: float = out[k]
			out[k] = snappedf(v, 0.000001)
	return out
