extends RefCounted

## The enemy layer: the 8-direction atlas, the collider/sprite reconciliation, the
## two port regressions in the walk cycle, leg-shot crawlers and what a corpse does.
##
## THE POINT OF THIS FILE IS THAT IT MEASURES. Every number about how wide a
## zombie is comes out of the shipped PNG here, at the sprite's own alpha scissor,
## rather than out of a comment — because the figure this package was handed
## ("roughly 0.42 m per side of unhittable billboard") was the width of the CELL,
## the sprite inside it is a third narrower than that, and the two enemies nobody
## suspected turned out to have colliders WIDER than their art. A table of
## measurements that lives in a comment is a table that is right once.
##
## What is deliberately not here: whether the four new bearings look like the same
## zombie. No assertion can see that and pretending otherwise is worse than the
## gap — it is `--shot`, from several yaws, and the atlas has been through it.

const ZOMBIE := preload("res://scripts/entities/zombie.gd")

## The sprite's own discard threshold, as a byte. `Zombie.ALPHA_SCISSOR` is 0.35
## and the texture is 8-bit, so a texel is drawn when its alpha exceeds 89. Every
## width in this file is measured against exactly that, because a width measured
## at any other threshold is a width of something the player cannot see.
const CUT := 89

## What fraction of the HEAD-ON silhouette the capsule has to cover. A capsule
## cannot follow fingertips and a ray through the outermost 5% of a sprite is
## grazing air at least as often as it is grazing a zombie, so 95% of the view a
## chasing zombie presents is the floor.
##
## It is only a floor. The ceiling is NOT "does not stick out past the head-on
## silhouette" — that was tried and it is wrong: a radially symmetric capsule
## pinned to the narrowest bearing is a miss at every other one, which is the
## defect §4.2 is about. See WAS_RADIUS.
const COVER := 0.95

## The capsule this package replaced, per kind — `0.26 if kind != "hound" else
## 0.30` — and it is here as a RATCHET rather than as history.
##
## Coverage is monotonic in radius, so the whole question of what the radius
## should be is "which error do we accept": a round that lands on drawn pixels
## and registers nothing, or a round that lands beside a body and connects. The
## first is what a player perceives and is what §4.2 calls broken hit
## registration; the second is invisible at the ranges this game is fought at. So
## the radius may go up and may not go down — at ANY bearing, not just the one
## somebody happened to measure. An earlier M4 pass set 0.30/0.23/0.22 from the
## head-on view alone and took the hound's profile coverage from 57.5% to 40.2%.
const WAS_RADIUS := {"zombie": 0.26, "crawler": 0.26, "hound": 0.30}

## The five atlas rows, walked as the eight bearings they actually serve — rows
## 1, 2 and 3 each cover two. Coverage has to be measured over the bearings a
## player shoots at, not over the rows the art happens to be stored in.
const BEARING_ROWS := [0, 1, 2, 3, 4, 3, 2, 1]


static func run(v: Verify, main: Node3D) -> void:
	_atlas_shape(v)
	_anchor_is_the_ancestor(v)
	_collider_matches_the_sprite(v, main)
	_bearings(v)
	_eyes_from_behind(v, main)
	_walk_cycle(v, main)
	_leg_shots(v, main)
	_corpses(v, main)
	_lure(v, main)


# --- the atlas ---------------------------------------------------------------

static func _atlas_shape(v: Verify) -> void:
	var missing := ""
	var wrong := ""
	for k: String in SpriteLib.SPEC.keys():
		var spec: Dictionary = SpriteLib.SPEC[k]
		var pals: int = maxi(1, int(spec.pal))
		for p in pals:
			# Attack is in this loop now. The walker has its own attack atlas and
			# nothing measured it, so a strip generated at the wrong width would have
			# sliced every swing frame off-centre while the frame COUNT — all the
			# completeness check below reads — stayed right. Crawlers and hounds have
			# no attack PNG at all (`attack: walk.slice(0,2)`, html:1056); that is
			# what the `has` guard skips, not a missing file.
			for anim: String in ["walk", "attack", "death"]:
				if not spec.has(anim):
					continue
				if not SpriteLib.has_atlas(k, p, anim):
					missing += "%s%d_%s " % [k, p, anim]
					continue
				var tex := _strip(k, p, anim)
				if tex == null:
					missing += "%s%d_%s " % [k, p, anim]
					continue
				var want_h: int = int(spec.h) * SpriteLib.VIEW_COUNT
				var want_w: int = int(spec.w) * int(spec[anim])
				if tex.get_height() != want_h or tex.get_width() != want_w:
					wrong += "%s%d_%s is %dx%d, expected %dx%d " % [
						k, p, anim, tex.get_width(), tex.get_height(), want_w, want_h]
	v.check("every enemy has an 8-direction atlas on disk", missing.is_empty(), missing)
	v.check("every atlas is VIEW_COUNT rows of the strip's own cell", wrong.is_empty(), wrong)

	# The fallback is the reason this package can land before the art is
	# regenerated on a given machine, and it is only worth having if the animation
	# names exist either way — otherwise `_apply_anim` asks for "walk_3" and gets
	# a silent empty animation instead of the single view.
	var complete := true
	for k: String in SpriteLib.SPEC.keys():
		var frames := SpriteLib.frames_for(k, 0)
		for anim: String in ["walk", "attack", "death"]:
			for view in SpriteLib.VIEW_COUNT:
				var name := SpriteLib.anim_name(anim, view)
				if not frames.has_animation(name) or frames.get_frame_count(name) == 0:
					complete = false
	v.check("every kind has all five bearings of all three cycles", complete)

	# THE ONE THAT WAS MISSING, and it is the assertion the whole of PART 1 turns
	# on. Every check above reads the DISK — `has_atlas()` and `_strip()` both go
	# straight to `res://assets/sprites/`. `_add_set` decides SEPARATELY whether to
	# slice the atlas or stack the single view on all five rows, so "an atlas is on
	# disk" and "the game is drawing from it" were two independent facts and only
	# the first was tested.
	#
	# Measured, not reasoned: forcing `have_atlas := false` inside `_add_set` — so
	# that every zombie in the game draws its front view at every bearing, which is
	# precisely the defect this package exists to remove — left the suite at
	# 469 passed, and not one enemy assertion moved. A frame count cannot see it
	# and neither can a strip's dimensions; the atlas WINDOW can, because that is
	# the thing the Sprite3D samples.
	#
	# Not gated on `has_atlas`. A tree with no atlas fails the first check in this
	# function already, so this adds no new failure mode to a checkout without art
	# — but gating it would rebuild exactly the "passes because the thing is
	# absent" shape that let the Monkey Bomb ship inert for a whole wave.
	var sliced := ""
	for k: String in SpriteLib.SPEC.keys():
		var spec: Dictionary = SpriteLib.SPEC[k]
		var pals: int = maxi(1, int(spec.pal))
		for p in pals:
			var frames := SpriteLib.frames_for(k, p)
			for anim: String in ["walk", "attack", "death"]:
				for view in SpriteLib.VIEW_COUNT:
					var name := SpriteLib.anim_name(anim, view)
					var at := frames.get_frame_texture(name, 0) as AtlasTexture
					if at == null:
						sliced += "%s%d_%s has no atlas window " % [k, p, name]
						continue
					var want := view * int(spec.h)
					if int(at.region.position.y) != want:
						sliced += "%s%d_%s samples row y=%d, expected %d " % [
							k, p, name, int(at.region.position.y), want]
	v.check("the frames the game actually plays are cut one row per bearing",
		sliced.is_empty(), sliced)


## The provenance claim, checked against the shipped bytes rather than against
## tools/gen/README.md. One row of every atlas is not new art: the walker's row 0
## is `zombieBody` called unmodified (html:973), and the crawler's and the hound's
## row 2 is their own baked frame mirrored, because both are authored in profile
## facing screen-left. If that ever stops being true, the view a player spends the
## whole game looking at has silently changed and nothing else would report it.
##
## NOT A BYTE COMPARISON, and it cannot be: the committed strips were rasterised
## by Chrome and the atlas by standalone Skia, which README.md measures at a mean
## delta of 2.64/255 over the enemy sheets and a worst case of 205 wherever
## `outlineSprite`'s hard threshold (html:965) flips a rim pixel on or off. A byte
## test would fail on a correct build.
##
## So this asserts a RATIO instead, which needs no tolerance to be argued about:
## the anchor row must be closer to the committed frame than any of the other four
## rows, by a wide margin. Rasteriser noise cannot fake that and a wrong anchor
## cannot survive it.
static func _anchor_is_the_ancestor(v: Verify) -> void:
	var report := ""
	var ok := true
	var checked := 0
	for k: String in SpriteLib.SPEC.keys():
		var spec: Dictionary = SpriteLib.SPEC[k]
		var row: int = int(SpriteLib.ANCHOR_VIEW[k])
		var flat := _flat_strip(k, 0, "walk")
		var atlas := _strip(k, 0, "walk")
		if flat == null or atlas == null:
			continue
		var a := flat.get_image()
		var b := atlas.get_image()
		if a == null or b == null:
			continue
		a.convert(Image.FORMAT_RGBA8)
		b.convert(Image.FORMAT_RGBA8)
		checked += 1
		# The same mirroring convention for every row, or the comparison is not
		# apples to apples — the question is which row wins, not which mirror does.
		var mirrored: bool = row != 0
		var deltas: Array[float] = []
		for r in SpriteLib.VIEW_COUNT:
			deltas.append(_row_delta(a, b, int(spec.w), int(spec.h), r, mirrored))
		var mine := deltas[row]
		var others := 1e9
		for r in deltas.size():
			if r != row:
				others = minf(others, deltas[r])
		if mine * 3.0 > others or mine > 6.0:
			ok = false
		report += "%s row %d delta %.2f vs next best %.2f | " % [k, row, mine, others]
	v.check("each atlas carries the ancestor's own frame on its anchor row",
		ok and checked == SpriteLib.SPEC.size(),
		"checked=%d %s" % [checked, report])


## Mean per-channel absolute difference between one atlas row and the committed
## single-view strip, in premultiplied space — because both rasterisers store
## premultiplied and unpremultiply on the way out, so a straight comparison
## reports a delta of 255 on a pixel that is 1% opaque and identical on screen.
## `mirror` flips inside each cell, not across the strip: frames stay in order.
static func _row_delta(flat: Image, atlas: Image, cell: int, h: int,
		row: int, mirror: bool) -> float:
	var w := flat.get_width()
	var aw := atlas.get_width()
	var da := flat.get_data()
	var db := atlas.get_data()
	var sum := 0.0
	for y in h:
		for x in w:
			var sx: int = x
			if mirror:
				sx = (x / cell) * cell + (cell - 1 - (x % cell))
			var ia := (y * w + sx) * 4
			var ib := ((row * h + y) * aw + x) * 4
			var aa := float(da[ia + 3])
			var ab := float(db[ib + 3])
			sum += absf(aa - ab)
			for c in 3:
				sum += absf(float(da[ia + c]) * aa - float(db[ib + c]) * ab) / 255.0
	return sum / float(w * h * 4)


# --- the collider, against the measured sprite -------------------------------

## §4.2's reconciliation, and the assertion the whole package turns on.
##
## Measured over the live cycles — walk and attack, the states in which a zombie
## can be shot at all — of every one of the eight bearings, every palette, at the
## sprite's own alpha scissor. Three separate properties, because one number
## cannot express them:
##
##   1. the head-on view, which a chasing zombie presents, is 95% covered;
##   2. no bearing of any kind is covered LESS than it was before M4 (WAS_RADIUS);
##   3. the capsule never reaches outside the widest the body ever draws.
##
## (3) is the only ceiling there is, and it is deliberately loose. Pinning the
## ceiling to the head-on silhouette instead is what produced 0.23/0.22 and a
## hound whose flank stopped registering hits.
static func _collider_matches_the_sprite(v: Verify, main: Node3D) -> void:
	var report := ""
	var floor_ok := true
	var ratchet_ok := true
	var ceiling_ok := true
	var r: float = ZOMBIE.HIT_RADIUS
	for k: String in SpriteLib.SPEC.keys():
		var head_on := _measure_view(k, 0)
		if int(head_on.total) <= 0:
			floor_ok = false
			report += "%s: nothing measurable " % k
			continue
		if head_on.covered_by(r) < COVER - 0.0001:
			floor_ok = false
		var was: float = float(WAS_RADIUS[k])
		var sum := 0.0
		var widest := 0.0
		var worst := 1.0
		for row: int in BEARING_ROWS:
			var m := _measure_view(k, row)
			var now := m.covered_by(r)
			if now < m.covered_by(was) - 0.0001:
				ratchet_ok = false
			sum += now
			worst = minf(worst, now)
			widest = maxf(widest, m.full())
		if r > widest + 0.0005:
			ceiling_ok = false
		report += "%s r=%.2f head-on %.1f%% avg8 %.1f%% worst %.1f%% (was %.2f) | " % [
			k, r, 100.0 * head_on.covered_by(r), 100.0 * sum / 8.0, 100.0 * worst, was]
	v.check("every collider covers 95% of the view a zombie coming at you presents",
		floor_ok, report)
	v.check("no bearing of any kind lost coverage against the capsule M4 replaced",
		ratchet_ok, report)
	v.check("no capsule reaches outside the widest silhouette its body ever draws",
		ceiling_ok, report)

	# The measurement from the other end, and the one that would have caught the
	# original defect: 0.26 m is `const R = 0.26` at kriegsnacht.html:2337, the
	# radius a zombie's CENTRE is kept off a WALL, and it was being used as the
	# radius it is shot with. The ancestor's hit radius is `r: isDog?0.30:0.30`
	# (html:2214), tested at html:2486 — a different number in a different place.
	var walker := _measure_view("zombie", 0)
	v.check("the old 0.26 m capsule really did miss part of a walker",
		walker.covered_by(0.26) < COVER,
		"0.26 covered %.1f%% of the head-on walker; the floor is %.0f%%" % [
			100.0 * walker.covered_by(0.26), 100.0 * COVER])
	v.check("the collider is the ancestor's own hit radius, for every kind",
		v.near(r, 0.30), "got %.3f" % r)

	# And the live capsule has to actually be built from the constant, or the
	# constant is documentation. Read off the shape rather than off the table.
	var built := ""
	for k: String in SpriteLib.SPEC.keys():
		var z := Zombie.create(k, 0, 1, false)
		main.add_child(z)
		var caps: CapsuleShape3D = z._collider.shape
		if not v.near(caps.radius, r, 0.0001):
			built += "%s built %.3f " % [k, caps.radius]
		# A capsule has hemispherical caps, so a body shorter than its own diameter
		# would be a sphere with its feet in the floor.
		if caps.height < maxf(SpriteLib.HEIGHT[k], caps.radius * 2.0) - 0.0001:
			built += "%s is %.2f tall against r=%.2f " % [k, caps.height, caps.radius]
		z.queue_free()
	v.check("the capsule that is built is the one the constant declares",
		built.is_empty(), built)


# --- bearings ----------------------------------------------------------------

static func _bearings(v: Verify) -> void:
	var north := Vector2(0.0, -1.0)

	# Facing the camera is row 0; facing away is the last row. Everything else in
	# the mapping hangs off those two.
	var head_on := SpriteLib.view_for(north, north)
	var away := SpriteLib.view_for(north, -north)
	v.check("a body facing the camera draws its front row and is never mirrored",
		head_on == Vector2i(0, 0), str(head_on))
	v.check("a body facing away draws the last row and is never mirrored",
		away == Vector2i(SpriteLib.VIEW_COUNT - 1, 0), str(away))

	# The two profiles are the same row mirrored, which is the whole reason five
	# rows cover eight bearings.
	var left := SpriteLib.view_for(Vector2(-1.0, 0.0), north)
	var right := SpriteLib.view_for(Vector2(1.0, 0.0), north)
	v.check("the two profiles are one row and its mirror",
		left.x == 2 and right.x == 2 and left.y != right.y,
		"%s / %s" % [left, right])

	# Every bearing has to land on a row that exists, and the sweep has to be
	# monotonic through it — a mapping that jumps 0,1,3,2 would look like a zombie
	# spinning on the spot as the player walks around it.
	var rows: Array[int] = []
	var in_range := true
	for i in 9:
		var a := float(i) * PI / 8.0
		var f := Vector2(sin(a), -cos(a))
		var got := SpriteLib.view_for(f, north)
		if got.x < 0 or got.x >= SpriteLib.VIEW_COUNT:
			in_range = false
		rows.append(got.x)
	var monotone := true
	for i in rows.size() - 1:
		if rows[i + 1] < rows[i]:
			monotone = false
	v.check("the bearing sweep is in range and never goes backwards",
		in_range and monotone and rows[0] == 0 and rows[rows.size() - 1] == SpriteLib.VIEW_COUNT - 1,
		str(rows))

	# A zero facing is what a body standing still at a window has before anything
	# writes one, and acos of a NaN is a row index nobody wants.
	v.check("a body with no heading falls back to the front row rather than a NaN",
		SpriteLib.view_for(Vector2.ZERO, north) == Vector2i(0, 0))


# --- eyes --------------------------------------------------------------------

static func _eyes_from_behind(v: Verify, main: Node3D) -> void:
	# THE ONE THAT MATTERS. Until the atlas there was no bearing at which a
	# zombie's eyes were not aimed at the camera, so a horde walking away lit the
	# wall in front of it — the single clearest tell that a billboard is a
	# billboard. Two rear rows, no eyes, for every kind.
	var lit := ""
	for k: String in SpriteLib.SPEC.keys():
		for view in [3, 4]:
			var geo := Zombie.eye_geo(k, view)
			if int(geo.n) != 0:
				lit += "%s row %d shows %d " % [k, view, int(geo.n)]
	v.check("no enemy glows at you with its back turned", lit.is_empty(), lit)

	# One eye in profile, not two on top of each other: `sep` is zero there, so a
	# pair would stack two additive quads on the same texels and make the bearing
	# that shows least of a face the brightest thing on the map.
	var geo2 := Zombie.eye_geo("zombie", 2)
	v.check("a walker in profile shows exactly one eye",
		int(geo2.n) == 1 and v.near(float(geo2.sep), 0.0),
		str(geo2))

	# EYE_PX is the tuned geometry for the bearing the ancestor drew, and it is
	# still what the no-atlas fallback uses, so the atlas row for that same bearing
	# has to agree with it — in magnitude. The sign differs for the crawler and the
	# hound BY CONSTRUCTION: their frame is authored facing screen-left and the
	# atlas mirrors it into row 2.
	var drift := ""
	for k: String in SpriteLib.SPEC.keys():
		var base: Dictionary = Zombie.EYE_PX[k]
		var rows: Array = Zombie.EYE_VIEW[k]
		var anchor: Dictionary = rows[int(SpriteLib.ANCHOR_VIEW[k])]
		if not v.near(absf(float(anchor.x)), absf(float(base.x)), 0.001) \
				or not v.near(float(anchor.sep), float(base.sep), 0.001):
			drift += "%s: EYE_VIEW %s vs EYE_PX x=%.2f sep=%.2f " % [
				k, anchor, float(base.x), float(base.sep)]
	v.check("the atlas eye row and the tuned EYE_PX row are the same geometry",
		drift.is_empty(), drift)

	# ...and on a live body of every kind, because the table being right is not the
	# same as the node reading it: `_refresh_eyes` only fires when `_update_view`
	# decides the row moved, and a body that never turns must keep the pair it
	# spawned with. Walk one round the compass and count.
	var counted := ""
	for k: String in SpriteLib.SPEC.keys():
		var z := Zombie.create(k, 0, 1, false)
		main.add_child(z)
		z.global_position = Vector3(4.0, 0.0, 4.0)
		var shown := 0
		var dark := 0
		for i in 8:
			var a := float(i) * TAU / 8.0
			z._facing = Vector2(sin(a), cos(a))
			z._update_view()
			z._refresh_eyes()
			if z._eyes.visible:
				shown += 1
			else:
				dark += 1
		# Rows 3 and 4 are eyeless and row 3 serves two of the eight bearings, so
		# three of a full turn are dark and five are lit. Pinned exactly, because
		# "at least one" would pass on a body that only ever showed its back.
		if shown != 5 or dark != 3:
			counted += "%s lit=%d dark=%d " % [k, shown, dark]
		z.queue_free()
	v.check("turning any live body puts its eyes out for three bearings of eight",
		counted.is_empty(), counted)


# --- the walk cycle ----------------------------------------------------------

static func _walk_cycle(v: Verify, main: Node3D) -> void:
	# `z.anim += dt*spd*2.6` (html:2340). The port replaced it with a one-shot
	# `Rng.randf_range(Rng.VISUAL, 0.85, 1.2)` at _ready, so a sprint-class body
	# could play a slower cycle than a walker and the three speed classes stopped
	# reading as three threats.
	var last := -1.0
	var monotone := true
	for i in 20:
		var spd := 0.4 + float(i) * 0.25
		var s := Zombie.anim_scale_for(spd)
		if s <= last:
			monotone = false
		last = s
	v.check("animation rate is strictly monotonic in movement speed", monotone)

	v.check("the rate is the ancestor's 2.6 frames per metre",
		v.near(Zombie.anim_scale_for(2.0) * Zombie.WALK_FPS, 2.0 * 2.6, 0.0001),
		"got %.4f fps at 2 m/s" % (Zombie.anim_scale_for(2.0) * Zombie.WALK_FPS))

	# WALK_FPS is a copy of a number that lives in sprite_lib.gd, so read the live
	# SpriteFrames rather than trusting the copy — a drift there would silently
	# scale every cycle in the game by the ratio.
	var frames := SpriteLib.frames_for("zombie", 0)
	var authored := frames.get_animation_speed(SpriteLib.anim_name("walk", 0))
	v.check("the constant the rate divides by is the rate the strip is authored at",
		v.near(authored, Zombie.WALK_FPS, 0.0001),
		"strip=%.2f constant=%.2f" % [authored, Zombie.WALK_FPS])

	# On live bodies, across the two classes that actually differ. Re-seeded either
	# side so the +/-8% variance and the class roll are identical and the only
	# thing left that can move is the speed itself.
	var slow := _spawn(main, "zombie", 2)
	var fast := _spawn(main, "zombie", 30)
	v.check("a faster class plays a faster cycle",
		(fast.speed > slow.speed) == (fast._sprite.speed_scale > slow._sprite.speed_scale)
			and fast.speed > slow.speed,
		"slow %.2f/%.3f fast %.2f/%.3f" % [
			slow.speed, slow._sprite.speed_scale, fast.speed, fast._sprite.speed_scale])
	v.check("the scale is derived from the speed, not rolled beside it",
		v.near(slow._sprite.speed_scale, Zombie.anim_scale_for(slow.speed), 0.0001)
			and v.near(fast._sprite.speed_scale, Zombie.anim_scale_for(fast.speed), 0.0001))
	slow.queue_free()
	fast.queue_free()

	# EVERY WAVE USED TO MARCH IN LOCKSTEP: nothing set the starting frame, so a
	# round's worth of bodies were all on frame 0 together. The ancestor never had
	# the bug — `anim: rnd(4)` at html:2213.
	var starts := {}
	var made: Array[Zombie] = []
	for i in 16:
		var z := Zombie.create("zombie", 0, 1, false)
		main.add_child(z)
		starts[z._sprite.frame] = true
		made.append(z)
	for z in made:
		z.queue_free()
	v.check("a wave does not spawn in lockstep on frame 0", starts.size() >= 3,
		"16 spawns started on %d distinct frames" % starts.size())


## Deliberately does NOT re-seed. Round 2 is walkers only and round 30 has no
## walkers (`Game.SPEED_MIX`), and the +/-8% per-body variance cannot close a gap
## from 1.05 to 2.20 m/s — so the classes are separated whatever the stream is
## sitting on, and this module can be dropped anywhere in the suite's order
## without moving a seeded run.
static func _spawn(main: Node3D, kind: String, round_no: int) -> Zombie:
	var z := Zombie.create(kind, 0, round_no, false)
	main.add_child(z)
	return z


# --- leg shots ---------------------------------------------------------------

static func _leg_shots(v: Verify, main: Node3D) -> void:
	var insta_was := Game.insta_kill
	Game.insta_kill = 0.0

	# Half a body's health into the legs takes them off and leaves the other half.
	var z := Zombie.create("zombie", 0, 1, false)
	main.add_child(z)
	var full := z.max_hp
	var leg_y := z.leg_threshold() * 0.5
	var per := full * Zombie.LEG_BREAK * 0.5
	var killed_a := z.take_damage(per, leg_y)
	var still_walking := z.kind == "zombie"
	var killed_b := z.take_damage(per, leg_y)
	var hp_after := z.hp
	v.check("enough damage into the legs makes a crawler, and one shot does not",
		still_walking and z.kind == "crawler" and not killed_a and not killed_b,
		"kind=%s killed=%s/%s" % [z.kind, killed_a, killed_b])
	v.check("a legged zombie keeps the health it had left",
		v.near(hp_after, full - per * 2.0, 0.01),
		"hp=%.1f expected %.1f" % [hp_after, full - per * 2.0])

	# ...and is a crawler in every way the rest of the game asks about, not just by
	# name. Height, capsule, sprite scale and head band all key off `kind`.
	var caps: CapsuleShape3D = z._collider.shape
	v.check("the conversion rebuilds everything that keys off the kind",
		v.near(z._height, SpriteLib.HEIGHT["crawler"])
			and v.near(caps.radius, ZOMBIE.HIT_RADIUS, 0.0001)
			and v.near(z._sprite.pixel_size, SpriteLib.pixel_size("crawler"), 0.00001)
			and v.near(z.head_threshold(), SpriteLib.HEIGHT["crawler"] * 0.58, 0.001)
			and z._sprite.sprite_frames == SpriteLib.frames_for("crawler", 0),
		"h=%.2f r=%.3f px=%.5f" % [z._height, caps.radius, z._sprite.pixel_size])
	# ...including the cull margin, which `_ready` derives from the kind and the
	# conversion silently did not. The margin is sized for whichever bearing puts
	# the eyes furthest off the origin, and a crawler's pair sits 13 px out against
	# a walker's 5 — so a converted body kept a margin 0.21 m short and its eyes
	# blinked out at the edge of the frame, which is the exact failure the margin
	# exists for. Compared against a crawler that was BORN one rather than against
	# a recomputed number, so the two paths cannot drift apart.
	var born := Zombie.create("crawler", 0, 1, false)
	main.add_child(born)
	v.check("a converted crawler carries a crawler's cull margin, not a walker's",
		v.near(z._eyes.extra_cull_margin, born._eyes.extra_cull_margin, 0.0001),
		"converted %.4f vs born %.4f" % [
			z._eyes.extra_cull_margin, born._eyes.extra_cull_margin])
	born.queue_free()
	v.check("a crawler made from a walker is slower than the walker was",
		z.speed > 0.0 and z.speed < SpriteLib.HEIGHT["zombie"],
		"speed=%.3f" % z.speed)
	z.queue_free()

	# The same damage in the chest must not do it, or every fight ends in crawlers.
	var body := Zombie.create("zombie", 0, 1, false)
	main.add_child(body)
	body.take_damage(body.max_hp * 0.9, body._height * 0.55)
	v.check("body shots never take the legs off", body.kind == "zombie",
		"kind=%s" % body.kind)
	body.queue_free()

	# A leg shot that kills is a kill. Without the ordering, Insta-Kill would
	# carpet the map in crawlers instead of clearing it.
	var lethal := Zombie.create("zombie", 0, 1, false)
	main.add_child(lethal)
	var died := lethal.take_damage(1e9, lethal.leg_threshold() * 0.5)
	v.check("a lethal leg shot kills rather than converting",
		died and lethal.kind == "zombie" and lethal.state == Zombie.State.DYING,
		"died=%s kind=%s" % [died, lethal.kind])
	lethal.queue_free()

	# Crawlers and hounds have nothing to take off.
	var crawler := Zombie.create("crawler", 0, 1, false)
	main.add_child(crawler)
	crawler.take_damage(crawler.max_hp * 0.9, crawler.leg_threshold() * 0.5)
	v.check("a crawler cannot be legged again", crawler.kind == "crawler")
	crawler.queue_free()

	Game.insta_kill = insta_was


# --- corpses -----------------------------------------------------------------

static func _corpses(v: Verify, main: Node3D) -> void:
	var insta_was := Game.insta_kill
	Game.insta_kill = 0.0
	var nuke_was := Game.nuke_clearing

	# A NUKE IS A WAVE, NOT A FLOP. Two bodies at two distances, killed on the same
	# frame by the same sweep: the near one must be on the floor while the far one
	# is still standing.
	var p: Player = main.player
	var near := Zombie.create("zombie", 0, 1, false)
	var far := Zombie.create("zombie", 0, 1, false)
	main.add_child(near)
	main.add_child(far)
	near.target = p
	far.target = p
	near.global_position = p.global_position + Vector3(1.0, 0.0, 0.0)
	far.global_position = p.global_position + Vector3(14.0, 0.0, 0.0)

	# Through the flag rather than through a new argument, because the flag is
	# already the authority on "this death is the sweep" — powerup_manager.gd sets
	# it and the economy reads it.
	var paid: Array[int] = [0]
	var on_death := func(_z: Zombie, _hs: bool, _melee: bool) -> void:
		paid[0] += 1
	near.died.connect(on_death)
	far.died.connect(on_death)
	Game.nuke_clearing = true
	near.take_damage(1e9, 0.0)
	far.take_damage(1e9, 0.0)
	Game.nuke_clearing = false

	v.check("a nuke pays and de-lists every body on the frame it detonates",
		paid[0] == 2 and near.state == Zombie.State.DYING and far.state == Zombie.State.DYING,
		"deaths=%d" % paid[0])
	v.check("both nuked bodies put their eyes out at once",
		not near._eyes.visible and not far._eyes.visible)
	v.check("the far body collapses later than the near one",
		near._death_delay < far._death_delay and far._death_delay > 0.0,
		"near=%.3f far=%.3f" % [near._death_delay, far._death_delay])
	v.check("the stagger is the distance times 0.045, capped",
		v.near(far._death_delay, minf(Zombie.NUKE_STAGGER_MAX, 14.0 * Zombie.NUKE_STAGGER), 0.001),
		"got %.4f for 14 m" % far._death_delay)

	# ...and the far one really is still upright, not merely holding a number.
	near._tick_death(0.05)
	far._tick_death(0.05)
	v.check("the near body is falling while the far one has not started",
		near._collapsed and not far._collapsed)
	# Cap, so the map's far corner does not leave a corpse standing for two
	# seconds after the toast has gone.
	far.global_position = p.global_position + Vector3(120.0, 0.0, 0.0)
	far._death_delay = 0.0
	far._collapsed = false
	Game.nuke_clearing = true
	far.state = Zombie.State.CHASING
	far.hp = 1.0
	far.take_damage(1e9, 0.0)
	Game.nuke_clearing = false
	v.check("the stagger is capped rather than unbounded",
		far._death_delay <= Zombie.NUKE_STAGGER_MAX + 0.0001,
		"got %.3f at 120 m" % far._death_delay)
	near.queue_free()
	far.queue_free()

	# A bullet does not stagger at all: the wave belongs to the detonation.
	var shot := Zombie.create("zombie", 0, 1, false)
	main.add_child(shot)
	shot.target = p
	shot.global_position = p.global_position + Vector3(9.0, 0.0, 0.0)
	shot.take_damage(1e9, 0.0, false, Zombie.Cause.BULLET, Vector3(1.0, 0.0, 0.0))
	v.check("an ordinary kill falls immediately",
		shot._collapsed and v.near(shot._death_delay, 0.0),
		"delay=%.3f collapsed=%s" % [shot._death_delay, shot._collapsed])

	# THE FAKE RAGDOLL, and it is a single capsule on purpose: §2.1's budget has no
	# room for 24 rigid bodies. The direction has to come from what killed it, or
	# every corpse slides the same way and the shove is decoration.
	var went := shot.global_position
	shot._tick_death(0.05)
	var moved := shot.global_position - went
	v.check("a corpse is pushed along the direction the killing blow came from",
		moved.x > 0.0 and absf(moved.z) < 0.0001 and absf(moved.y) < 0.0001,
		str(moved))
	shot.queue_free()

	var back := Zombie.create("zombie", 0, 1, false)
	main.add_child(back)
	back.target = p
	back.take_damage(1e9, 0.0, false, Zombie.Cause.BULLET, Vector3(-1.0, 0.0, 0.0))
	var was2 := back.global_position
	back._tick_death(0.05)
	v.check("a shot from the other side pushes the other way",
		back.global_position.x < was2.x, str(back.global_position - was2))
	back.queue_free()

	# ...and how hard, by what did it. A knife shoves a body; a rifle round barely
	# moves one; a blast throws it.
	v.check("cause decides how hard a corpse is thrown",
		Zombie.SHOVE_BLAST > Zombie.SHOVE_MELEE and Zombie.SHOVE_MELEE > Zombie.SHOVE_BULLET
			and Zombie.SHOVE_BULLET > 0.0)
	var knifed := _shove_of(main, p, Zombie.Cause.MELEE)
	var shot_by := _shove_of(main, p, Zombie.Cause.BULLET)
	v.check("a knife kill throws a body further than a bullet does",
		knifed > shot_by and shot_by > 0.0, "melee=%.3f bullet=%.3f" % [knifed, shot_by])

	# A headshot drops a body where it stands rather than stumbling it.
	var head := Zombie.create("zombie", 0, 1, false)
	main.add_child(head)
	head.target = p
	head.global_position = p.global_position + Vector3(20.0, 0.0, 0.0)
	Game.nuke_clearing = true
	head.take_damage(1e9, head._height * 0.95)
	Game.nuke_clearing = false
	v.check("a headshot collapses immediately even inside a nuke",
		head._last_headshot and head._collapsed and v.near(head._death_delay, 0.0))
	head.queue_free()

	# The corpse budget did not change. The old life was `frames/9 + 0.9`; the new
	# one re-apportions that same 0.9 into a hold and a fade so the body is not
	# deleted between two frames at full opacity. No extra draw calls and no extra
	# lifetime is the whole claim, so it is asserted rather than asserted-to.
	v.check("a corpse lives exactly as long as it used to",
		v.near(Zombie.CORPSE_HOLD + Zombie.CORPSE_FADE, 0.9, 0.0001),
		"hold+fade=%.3f" % (Zombie.CORPSE_HOLD + Zombie.CORPSE_FADE))

	# A CORPSE FALLS ON ITS OWN CLOCK, and nothing above would have noticed it did
	# not. `speed_scale` became a function of movement speed in M4 and a corpse is
	# not moving; the ancestor agrees, indexing the death strip off `dieT` and a
	# flat 0.55 s (html:2070) while `z.anim` drives only walk (html:2074) and the
	# attack pair (html:2072). Driving the fall off the walk clock gave a
	# walk-class body 1.30 s of topple inside a 1.34 s corpse and a crawler 1.59 s
	# inside 1.23 s — deleted mid-fall, on every enemy in the early rounds, and
	# invisible to a check that ticks `_tick_death` and reads a flag.
	#
	# The crawler is the worst case, so it is the one measured.
	var slow := Zombie.create("crawler", 0, 1, false)
	main.add_child(slow)
	slow.target = p
	slow.take_damage(1e9, 0.0)
	var death_fps := slow._sprite.sprite_frames.get_animation_speed(
		SpriteLib.anim_name("death", slow._view))
	var frames: int = int(SpriteLib.SPEC["crawler"].death)
	var need := float(frames) / (death_fps * slow._sprite.speed_scale)
	v.check("a corpse finishes falling before it is deleted",
		need <= slow._death_timer + 0.0001,
		"the fall needs %.2f s of a %.2f s corpse at scale %.3f" % [
			need, slow._death_timer, slow._sprite.speed_scale])
	v.check("the fall is not played at the speed the body was walking at",
		v.near(slow._sprite.speed_scale, 1.0, 0.0001) and slow.anim_scale() < 0.9,
		"death scale %.3f against a walk scale of %.3f" % [
			slow._sprite.speed_scale, slow.anim_scale()])
	slow.queue_free()

	# THE TOPPLE MUST NOT TURN THE BODY. `flip_h` decides which way the death strip
	# leans and, since the atlas, which of two bearings rows 1-3 are showing — so
	# overriding it on a mirrored row does not lean a corpse, it spins it a quarter
	# turn on the frame it dies. Both signs, because the camera's own heading
	# decides which one would have flipped and this must hold either way.
	var kept := true
	for sx: float in [1.0, -1.0]:
		var t := Zombie.create("zombie", 0, 1, false)
		main.add_child(t)
		t.target = p
		t.global_position = p.global_position + Vector3(6.0, 0.0, 0.0)
		t._view = 2
		t._flip = true
		t._sprite.flip_h = true
		t.take_damage(1e9, 0.0, false, Zombie.Cause.MELEE, Vector3(sx, 0.0, 0.0))
		if not t._flip or not t._sprite.flip_h:
			kept = false
		t.queue_free()
	v.check("a corpse on a mirrored row keeps the bearing it died on", kept)

	# ...and on the two rows `view_for` never mirrors, the flag is spare and is
	# still spent on the lean, which is what it was for.
	var leaned: Array[bool] = []
	for sx: float in [1.0, -1.0]:
		var t := Zombie.create("zombie", 0, 1, false)
		main.add_child(t)
		t.target = p
		t.global_position = p.global_position + Vector3(6.0, 0.0, 0.0)
		t._view = 0
		t.take_damage(1e9, 0.0, false, Zombie.Cause.MELEE, Vector3(sx, 0.0, 0.0))
		leaned.append(t._flip)
		t.queue_free()
	v.check("...and on a row that is never mirrored it still falls away from the blow",
		leaned[0] != leaned[1], str(leaned))

	# THE SHOVE HAD NO CALLERS AT ALL. `take_damage` grew a cause and a direction
	# and not one call site in the game passes either — `_apply_hit` takes three
	# arguments, `_knife` passes three, the splash passes two — so every corpse in
	# the game fell straight down with `_shove` at zero and SHOVE_BULLET, _MELEE
	# and _BLAST were constants nothing read. Every assertion above still passed,
	# because every one of them passes the arguments by hand.
	var plain := Zombie.create("zombie", 0, 1, false)
	main.add_child(plain)
	plain.target = p
	plain.global_position = p.global_position + Vector3(3.0, 0.0, 1.0)
	plain.take_damage(1e9, 0.0)
	var away := plain.global_position - p.global_position
	away.y = 0.0
	v.check("a kill that names no direction still throws the body, away from the player",
		plain._shove.length() > 0.01
			and plain._shove.normalized().dot(away.normalized()) > 0.99,
		"shove=%s" % plain._shove)
	plain.queue_free()

	# ...and through the path the game actually shoots down, rather than through
	# the API. This is the one the API-only assertions could not see.
	var real := Zombie.create("zombie", 0, 1, false)
	main.add_child(real)
	real.target = p
	real.global_position = p.global_position + Vector3(4.0, 0.0, 0.0)
	p._apply_hit(real, 1e9, real.centre())
	v.check("a kill through the player's own hit path throws the body too",
		real.state == Zombie.State.DYING and real._shove.length() > 0.01,
		"shove=%s" % real._shove)
	real.queue_free()

	Game.insta_kill = insta_was
	Game.nuke_clearing = nuke_was


static func _shove_of(main: Node3D, p: Player, cause: int) -> float:
	var z := Zombie.create("zombie", 0, 1, false)
	main.add_child(z)
	z.target = p
	z.take_damage(1e9, 0.0, cause == Zombie.Cause.MELEE, cause, Vector3(1.0, 0.0, 0.0))
	var mag := z._shove.length()
	z.queue_free()
	return mag


# --- the lure ----------------------------------------------------------------

## The zombie side of the Monkey Bomb. Package PROJ owns `Game.lure_position`;
## this owns what the horde does about it.
##
## THE CONTRACT IS ASSERTED, NOT GUARDED. This check used to degrade to "PROJ has
## not landed yet" and pass, and `zombie.gd::_goal_point` reads the property
## behind an `in` — between them, when PROJ published the lure as a static on
## `throwables.gd` instead, the headline throwable of the milestone moved no
## zombie at all and every assertion on both sides still passed. A check whose
## failure mode is a green tick for the absence of the thing it tests is worse
## than no check. If the property is gone the horde cannot be lured, so that is a
## failure here whatever the reason for it.
static func _lure(v: Verify, main: Node3D) -> void:
	var z := Zombie.create("zombie", 0, 1, false)
	main.add_child(z)
	z.target = main.player
	var player_at := Vector2(main.player.global_position.x, main.player.global_position.z)

	var declared: bool = "lure_position" in Game
	v.check("the lure contract the horde reads actually exists on Game",
		declared, "Game.lure_position is not declared — nothing can lure the horde")
	if not declared:
		z.queue_free()
		return

	var was: Variant = Game.lure_position
	Game.lure_position = Vector3.INF
	var no_lure := z._goal_point()
	Game.lure_position = Vector3(7.5, 0.0, 3.5)
	var with_lure := z._goal_point()
	Game.lure_position = was
	v.check("a live lure pulls the horde off the player and clearing it gives them back",
		no_lure.is_equal_approx(player_at) and with_lure.is_equal_approx(Vector2(7.5, 3.5)),
		"none=%s lured=%s player=%s" % [no_lure, with_lure, player_at])
	z.queue_free()


# --- measuring the shipped art -----------------------------------------------

class Ink extends RefCounted:
	var cols := PackedFloat32Array()
	var total := 0.0
	var px := 0.0
	var cell := 0

	## Fraction of the drawn pixels a capsule of this radius covers, head on.
	func covered_by(radius: float) -> float:
		if total <= 0.0:
			return 0.0
		var limit := radius / px
		var centre := float(cell) * 0.5
		var inside := 0.0
		for x in cols.size():
			if absf(float(x) + 0.5 - centre) <= limit:
				inside += cols[x]
		return inside / total

	## Half-width, in metres, containing all of the drawn pixels.
	func full() -> float:
		var centre := float(cell) * 0.5
		var worst := 0.0
		for x in cols.size():
			if cols[x] > 0.0:
				worst = maxf(worst, maxf(centre - float(x), float(x) + 1.0 - centre))
		return worst * px


## Decoding three palettes of two strips is not free and the collider section asks
## for the same five rows nine times over — once per compass bearing plus the
## head-on floor. Cached for the life of the run; the PNGs cannot change under it.
static var _ink_cache := {}


## Every drawn pixel of one bearing of one kind, summed over the cycles a live
## zombie can be shot in — walk and attack — and over every palette, because the
## three palettes differ and the collider is one number for all of them.
static func _measure_view(kind: String, view: int) -> Ink:
	var key := "%s/%d" % [kind, view]
	if _ink_cache.has(key):
		var hit: Ink = _ink_cache[key]
		return hit
	var spec: Dictionary = SpriteLib.SPEC[kind]
	var out := Ink.new()
	out.cell = int(spec.w)
	out.px = SpriteLib.pixel_size(kind)
	out.cols.resize(out.cell)
	var pals: int = maxi(1, int(spec.pal))
	for p in pals:
		for anim: String in ["walk", "attack"]:
			if not spec.has(anim):
				continue
			var tex := _strip(kind, p, anim)
			if tex == null:
				tex = _flat_strip(kind, p, anim)
			if tex == null:
				continue
			var img := tex.get_image()
			if img == null:
				continue
			img.convert(Image.FORMAT_RGBA8)
			var data := img.get_data()
			var w := img.get_width()
			var h := img.get_height()
			var rows: int = maxi(1, h / int(spec.h))
			var row: int = view if rows > 1 else 0
			var y0: int = row * int(spec.h)
			for y in int(spec.h):
				for x in w:
					var a := data[((y0 + y) * w + x) * 4 + 3]
					if a > CUT:
						out.cols[x % out.cell] += 1.0
						out.total += 1.0
	_ink_cache[key] = out
	return out


static func _strip(kind: String, pal: int, anim: String) -> Texture2D:
	return _load(kind, pal, anim, "_dir.png")


static func _flat_strip(kind: String, pal: int, anim: String) -> Texture2D:
	return _load(kind, pal, anim, ".png")


static func _load(kind: String, pal: int, anim: String, suffix: String) -> Texture2D:
	var spec: Dictionary = SpriteLib.SPEC[kind]
	var prefix: String = kind + str(pal) if int(spec.pal) > 0 else kind
	# Crawlers and hounds cut their swing out of the walk strip, exactly as the
	# ancestor did (`attack: walk.slice(0,2)`), so there is no attack PNG to find.
	var stem: String = anim
	if anim == "attack" and not spec.has("attack"):
		stem = "walk"
	var path := SpriteLib.DIR + prefix + "_" + stem + suffix
	if not ResourceLoader.exists(path):
		return null
	return load(path)
