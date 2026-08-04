extends RefCounted

## The ancestor's own `GUNART` table, read out of `kriegsnacht.html` at check time,
## and the register of every place ours deliberately departs from it.
##
## THE FIRST GDSCRIPT IN THIS PROJECT THAT READS THE ANCESTOR. Every other mention
## of `kriegsnacht.html` under `scripts/` is a comment citing a line number; until
## now the only machine reader was `tools/gen/extract.js`, in Node. That matters
## twice: the citation is verified here rather than trusted, and anyone who needs the
## ancestor's parts should preload this rather than write a second parser. Two
## readers of one file are two sets of bugs — the argument `gunart.gd:645-648` makes
## for `_parts()` being one function, applied to a file instead of a concatenation.
##
## HERE AND NOT IN `checks/`, for two reasons that were both measured.
## `verify.gd:352-364`'s `_registered()` walks `res://scripts/dev/checks` ONLY, so a
## helper one level up needs no registration line and cannot trip the registry audit.
## And `--headless --path . --check-only --script scripts/dev/checks/frame.gd` ABORTS
## at `frame.gd:1077` on the documented `Identifier not found: Rng` autoload false
## positive — hundreds of lines above the checks that call this — so nothing added
## down there is parse-gateable at all. This file names no autoload, gates clean on
## its own, and is where every non-trivial line of the package lives.
##
## SOURCE CHECKOUT ONLY, and that is a boundary rather than a gap. `*.html` is in the
## `exclude_filter` of BOTH export presets (`export_presets.cfg:11`, `:82`), so the
## ancestor is not in a packed build; `--verify` only ever runs from the editor binary
## (`verify.gd:357-360`), which `tools/build.ps1` calls before exporting. In a packed
## build this would fail, and it would fail looking like a missing file, so it is
## written down.


## The authority. CLAUDE.md's two-sources rule makes this evidence rather than the
## last word — where it and Black Ops 1 disagree the reference wins — but a departure
## from it has to be RECORDED, and `DEPARTURES` below is where.
const ANCESTOR_PATH := "res://kriegsnacht.html"

## Recomputed on every suite run, never trusted from an artefact. Corroborated three
## ways — `sha256sum kriegsnacht.html`, `tools/gen/README.md:37` ("verified
## 2026-07-27"), and `tools/gen/extract.js:42`'s own report line — BUT ALL THREE HASH
## RAW BYTES, so they agree with this pin only on an LF materialisation, which is to
## say only by the accident described below. On a fresh clone all three print
## `786f425f...` and this pin still passes, by design. Do not "correct" it to match
## them. The ancestor has one
## commit in its history, so this pin has no maintenance cost — and if it ever fires,
## the AUTHORITY moved, which is a stop-everything event and not a number to bump.
##
## OVER THE FILE WITH `\r\n` FOLDED TO `\n`, NOT OVER ITS BYTES, AND THAT IS A BUILD
## FIX RATHER THAN A CONVENIENCE. MEASURED: `git config core.autocrlf` is `true` here
## and there is no `.gitattributes`, so `git ls-files --eol kriegsnacht.html` reports
## `i/lf w/lf` while every other text file in the repo reports `w/crlf` — this working
## copy is LF only because it predates that setting. `git checkout-index` into a clean
## directory materialises the ancestor at 143 245 bytes with 3 476 CRLFs and a byte
## sha of `786f425f...`, so a byte pin is red on ANY clone, worktree, CI checkout or
## `git checkout -- kriegsnacht.html`; `tools/build.ps1:93` gates the export on
## `--verify`, so a fresh Windows checkout could not build. Folding the newlines makes
## the pin a statement about the ancestor's CONTENT, which is what it was always
## claiming to be, and it holds in both materialisations (MEASURED both ways: green on
## this LF tree, and green on a `git checkout-index` materialisation of the same
## commit, where the byte pin fails A1 alone with the anchors still at 1151/1207).
##
## NOT FIXED WITH A `.gitattributes`, deliberately. One would settle the question for
## future checkouts but does nothing for a checkout that already exists — including
## this one, which is the very tree that is inconsistent — and it changes the working
## copy of every text file in the repo for everyone. The fix belongs where the reader
## is.
##
## WHAT THE PIN THEREFORE NO LONGER DETECTS, said plainly: a change that consists
## solely of inserting or removing a CR immediately before an LF. That is the entire
## blind spot — every other byte still reaches the hash, including a lone CR, a
## trailing-whitespace edit and a BOM. Nothing in this suite reads the ancestor's line
## endings, and the only other machine reader splits on `/\r?\n/` already
## (`extract.js:436`), so a newline-only change cannot alter what anything downstream
## extracts. It is the same class of blind spot `strip_edges()` opens in the anchor
## scan below, and for the same reason.
##
## NOT the same hash as `extract.js:44`'s `EXPECTED_SHA`
## (`7a8550505720e46...`): that one covers the assembled ancestor MODULE, which is a
## slice of this file plus a shim. This one is the file.
const ANCESTOR_SHA := "0d48059a4a5efe5b7bc785f47c51791fa08d691d6e57019fde79912341af7e0d"

## `kriegsnacht.html:1151-1207`, the citation `gunart.gd:3`/`:34` and this suite have
## been making all along. SCANNED for and then asserted to be here, which is not the
## same as trusted: `extract.js:12-16` uses anchor regexes alone because "the numbers
## in notes/ have been wrong before", and CLAUDE.md says line numbers drift and to
## check yours. Scanning first means a reformatted ancestor still PARSES and exactly
## one named check reports the moved citation; pinning the number as well means the
## comment cannot rot silently.
const HEAD_TEXT := "const GUNART = {"
const TAIL_TEXT := "};"
const HEAD_LINE := 1151
const TAIL_LINE := 1207

## Above `checks/frame.gd:861`'s 20-character floor for a golden relation's `why`,
## because a departure's reason has a harder job than a relation's: it has to name
## what it departs TOWARD — the BO1 reference, a measurement, a notes/ citation. OUR
## DECISION, and it measures length rather than thought. It cannot adjudicate a
## departure and does not claim to; it makes an empty gesture fail.
const WHY_MIN := 40

## THE DEPARTURE REGISTER. Empty, and that is the current truth: `ART` and the
## ancestor agree part for part across 13 weapons and 101 parts.
##
## It exists because the check this package replaced had the inversion backwards. It
## compared `Array.size()` against thirteen hand-typed integers, so it refused every
## count change whether recorded or not and permitted every geometry, colour, kind and
## ORDER change whether recorded or not. CLAUDE.md asks for the record, not for
## obedience: "a departure from the ancestor that is not recorded as a deliberate
## departure is wrong even when the departure is right."
##
## To depart deliberately: edit `ART`, run `--verify`, and paste the two rows the
## failure prints into a row here with a reason. The failure detail is written in this
## notation for exactly that reason — recording a departure costs one paste and one
## sentence.
##
##     "rpk:3": {
##         "anc":  "r|52.0|21.0|14.0|9.0|33363aff",
##         "ours": "r|52.0|21.0|20.0|9.0|33363aff",
##         "why":  "BO1's RPK reads with a longer receiver than the ancestor's 14
##                  units; measured against notes/research/visual-corpus/.",
##     },
##
## BOTH SIDES ARE PINNED, which is the half that keeps this from becoming a blanket
## permission. A waiver is honoured only while it still describes a LIVE difference
## that matches on both sides — so a further edit behind an existing waiver fails as a
## stale waiver rather than hiding, and a reverted departure fails as a waiver for a
## difference that is not there. A skip must never pass, and a waiver nobody can
## falsify is a skip.
##
## WHAT A WAIVER DOES NOT COVER: cardinality. A part APPENDED to `ART` is refused with
## no waiver path, on purpose and on the ancestor's own line — `SIGHTS` exists
## precisely so new geometry goes somewhere `ART` is not (`gunart.gd:403-414`), and
## `SLIDE`'s positional indices depend on `ART`'s length being the ancestor's
## (`gunart.gd:432-436`). That has to be a visible design decision, not a waiver row.
##
## **BOTH REASONS SURVIVED THE BANDS PACKAGE INTACT, and that is worth writing down
## because the obvious version of that package would have dissolved the second one.**
## `SLIDE` still holds flat integers into `_parts()` and `DEPTH` still holds one flat
## row per weapon, so `SLIDE`'s dependence on `|ART[key]|` is exactly what it was. What
## the bands added is a third place for geometry to go (`gunart.gd`'s `DETAIL`) and an
## address space for naming it — neither of which touches this lock. A later agent
## reading `part_id` as permission to append to `ART` has read it backwards: the first
## reason is now stronger, because there are two homes that are not `ART` rather than
## one.
const DEPARTURES := {}


## The ancestor's table, the anchors it was found at, the file's hash, and the reason
## if any of that failed.
##
##     {"art": {key: [[kind, num..., "rrggbb"], ...]}, "head": int, "tail": int,
##      "sha": String, "why": String}
##
## `why` is empty exactly when `art` is trustworthy. Shaped after
## `frame_stats.load_golden()` (`frame_stats.gd:586-593`), the house precedent for a
## check reading a file — PLUS the reason, because `get_file_as_string()` returns ""
## for a missing file WITHOUT raising anything (only `get_open_error()` records it),
## and "the ancestor was renamed" must never be indistinguishable from "the ancestor
## agrees". One read, one hash, one scan: the caller asserts on these fields rather
## than reopening the file, so there is no second reader to disagree with this one.
static func read(path := ANCESTOR_PATH) -> Dictionary:
	var out := {"art": {}, "head": -1, "tail": -1, "sha": "", "why": ""}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		out["why"] = "%s is unreadable (open error %d)" % [path, FileAccess.get_open_error()]
		return out
	# ONE NORMALISATION, AND EVERYTHING BELOW READS IT. `core.autocrlf` is true here
	# with no `.gitattributes`, so the ancestor arrives LF in this working copy and
	# CRLF in every fresh materialisation of the same commit (MEASURED via
	# `git checkout-index`: 139 769 bytes against 143 245). Folding here rather than at
	# each use means the hash, the anchor scan and the JSON body are all statements
	# about one text — see `ANCESTOR_SHA` for exactly what that costs the pin.
	var lf := text.replace("\r\n", "\n")
	# Recomputed here so the caller never opens the file a second time. `sha256_text()`
	# over the folded string rather than `FileAccess.get_sha256(path)` over the bytes,
	# which is the whole R2 fix; MEASURED identical to `sha256sum` on this LF working
	# copy, so the pinned digest did not have to move. Left "" by the early return
	# above when the read failed, which is why the caller checks the length.
	out["sha"] = lf.sha256_text()
	# `strip_edges()` rather than a bare compare: the newline fold above handles CRLF,
	# so what this buys is tolerance of indentation and trailing whitespace. A
	# reformatted ancestor must still PARSE — so that exactly one named check reports
	# "the citation moved" — rather than falling out here as "the file is unreadable",
	# which is a different failure with a different response.
	var lines := lf.split("\n")
	var head := -1
	for i in lines.size():
		if String(lines[i]).strip_edges() == HEAD_TEXT:
			head = i + 1
			break
	if head < 0:
		out["why"] = "no line in %s reads [%s]" % [path, HEAD_TEXT]
		return out
	var tail := -1
	for i in range(head, lines.size()):
		if String(lines[i]).strip_edges() == TAIL_TEXT:
			tail = i + 1
			break
	if tail < 0:
		out["why"] = "no [%s] after line %d of %s" % [TAIL_TEXT, head, path]
		return out
	out["head"] = head
	out["tail"] = tail
	var body := "{\n"
	for i in range(head, tail - 1):     # the 0-based interior of the block
		body += String(lines[i]) + "\n"
	body += "}"
	# JS object literal -> JSON in two edits, and NEITHER CAN REACH INSIDE A STRING:
	# the only string literals between the anchors are `'#RRGGBB'` and the four kind
	# tags `'r' 'rr' 'c' 'p'`, and not one of them contains a colon or an apostrophe.
	# That is the whole safety argument, and what bounds it if it ever stops being
	# true is the caller's exact roster and per-weapon counts — a mis-quote cannot
	# come out the far end as thirteen weapons of the right lengths.
	#
	# Built at call time and not as a `const`: `RegEx.create_from_string(...)` is a
	# CALL, and a `const` that is not a constant expression is a hard parse error.
	var re := RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_]*)\\s*:")
	body = re.sub(body, "\"$1\":", true)
	body = body.replace("'", "\"")
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) != TYPE_DICTIONARY:
		out["why"] = "lines %d-%d of %s did not parse as an object literal" % [head, tail, path]
		return out
	var art := {}
	var doc: Dictionary = parsed
	for key: String in doc:
		var src: Array = doc[key]
		var rows: Array = []
		for p: Array in src:
			rows.append(p.duplicate(true))
		art[key] = rows
	out["art"] = art
	return out


## One part in one notation, whichever side it came from, for FAILURE MESSAGES and
## for the values a waiver pins. It is not the verdict — `part_reason()` is, and it is
## numeric — because a canonical string is only as fine as its rounding and a verdict
## must not be.
##
## The colour is read at `part[part.size() - 1]` and NOT at a per-kind index, because
## that is what the ancestor itself does (`const col = mono ? mono : pt[pt.length-1]`,
## `kriegsnacht.html:1133`) and `gunart.gd:1274-1278` records why: the four shapes
## carry the colour at four different indices (`r` 6 elements, `rr` 7, `c` 5, `p` 3).
static func row_text(part: Array) -> String:
	if part.is_empty():
		return "<empty>"
	var out := String(part[0])
	for i in range(1, part.size() - 1):
		var field: Variant = part[i]
		if typeof(field) == TYPE_ARRAY:      # a polygon's flat vertex list; both knife rows
			var poly: Array = field
			var s := ""
			for j in poly.size():
				var value: float = poly[j]
				s += ("," if j > 0 else "") + _num(value)
			out += "|[" + s + "]"
		else:
			var n: float = field
			out += "|" + _num(n)
	return out + "|" + hex_of(part)


## Canonical enough that a JSON float `21.0` and an `ART` int `21` render alike.
## `JSON.parse_string` hands back FLOAT for every number in that block, including the
## integer literals, while `ART` holds ints — a comparator or a pin written on raw
## values would report all 101 parts as drifted on its first run and read as a live
## defect rather than a type artefact.
##
## Four decimals is three orders of magnitude finer than anything the ancestor
## authored (its finest values are 1.2, 1.4, 3.5, 3.6, 4.4, 24.5, -0.35, -0.45), so
## nothing in the table is near the rounding. It is still COARSER THAN THE VERDICT,
## which matters in one place: a departure edited behind an existing waiver by less
## than 0.0001 would still match the waiver's pinned text. `part_reason()` compares at
## 1e-9 and is what decides whether a part has drifted at all.
static func _num(value: float) -> String:
	return String.num(snappedf(value, 0.0001), 4)


## A part's colour, un-hashed and lower case, EIGHT DIGITS ON BOTH SIDES. Ours arrives
## as a `Color`, theirs as `'#3A3D40'`. `Color("3a3d40").to_html()` round-trips
## 8-bit -> float -> 8-bit losslessly, which is measured rather than assumed: the diff
## over all 101 parts is empty, and a lossy round trip would have shown up as ~90
## colour mismatches on the first run.
##
## RRGGBB**AA**, because a `Color` has four channels and a check named "field for
## field" that silently drops one is the same shape of claim this package was written
## to remove. `to_html(false)` was the first draft and it was MEASURED blind: an `ART`
## colour's alpha driven to 0 on disk passed all 789 assertions of the suite. The
## ancestor writes six digits and has no alpha of its own, so its side is padded with
## `ff` — which is exactly what `Color("#3A3D40")` parses to, so the padding states the
## ancestor's own value rather than assuming one.
##
## HONEST SCOPE, because the reason this was first written off is nearly right.
## `_tint` (`gunart.gd:1427-1431`) does pass the `Color` through unmodified — but
## `_tri` (`:1290`) then builds `Color(col.r * f, col.g * f, col.b * f, 1.0)`, so alpha
## is discarded before it reaches a vertex and NO alpha edit can move a pixel today.
## This is therefore a claim about the TABLE, not about the frame: it keeps `ART` a
## faithful transcription in every channel it stores, and it is what makes the sight
## record below able to pin a colour without a second renderer.
static func hex_of(part: Array) -> String:
	if part.is_empty():
		return ""
	var last: Variant = part[part.size() - 1]
	if typeof(last) == TYPE_COLOR:
		return (last as Color).to_html(true).to_lower()
	var hex := String(last).trim_prefix("#").to_lower()
	return (hex + "ff") if hex.length() == 6 else hex


## THE VERDICT. "" when `ours` is the part `theirs` is, else the first field that
## differs, named. Numeric at 1e-9 rather than a string or a `==`, per the type
## artefact `_num()` describes.
##
## Covers everything a part is: kind, arity, every numeric field in order (x, y, w, h,
## and the `rr` rotation and the `c` radius, which live at different indices per kind
## and so are walked positionally), the polygon vertex list element by element, and
## the colour. Order is not a field — it falls out of comparing index against index.
static func part_reason(ours: Array, theirs: Array) -> String:
	if ours.is_empty() or theirs.is_empty():
		return "empty part"
	if String(ours[0]) != String(theirs[0]):
		return "kind %s/%s" % [String(ours[0]), String(theirs[0])]
	if ours.size() != theirs.size():
		return "arity %d/%d" % [ours.size(), theirs.size()]
	for i in range(1, theirs.size() - 1):
		var mine: Variant = ours[i]
		var mirror: Variant = theirs[i]
		if typeof(mirror) == TYPE_ARRAY:
			var pa: Array = mirror
			if typeof(mine) != TYPE_ARRAY:
				return "field %d is not a polygon" % i
			var po: Array = mine
			if po.size() != pa.size():
				return "polygon %d/%d vertices" % [po.size(), pa.size()]
			for j in pa.size():
				var a: float = pa[j]
				var o: float = po[j]
				if absf(o - a) > 1e-9:
					return "poly[%d] %s/%s" % [j, _num(o), _num(a)]
		else:
			var a2: float = mirror
			var o2: float = mine
			if absf(o2 - a2) > 1e-9:
				return "field %d %s/%s" % [i, _num(o2), _num(a2)]
	if hex_of(ours) != hex_of(theirs):
		return "colour %s/%s" % [hex_of(ours), hex_of(theirs)]
	return ""


## The keys both sides declare, in the ancestor's own order. The roster is one
## check's business and the fields are another's; without this split, erasing a weapon
## from `ART` turns both red and neither control can prove which check did the work.
static func shared_keys(anc: Dictionary, art: Dictionary) -> Array:
	var out: Array = []
	for key: String in anc:
		if art.has(key):
			out.append(key)
	return out


## The roster and the cardinality, against `ART` itself — which has to be read
## directly here, because the walk `_parts()` makes legitimately holds MORE parts than
## the ancestor drew.
##
## ORDERED, not sorted. `ART` declares its weapons in the ancestor's own declaration
## order today, so pinning the order is free discrimination over a sorted comparison.
##
## Both key sets are compared, so a weapon in `ART` the ancestor never drew fails as
## loudly as one missing. The check this replaced iterated `GUNART.keys()` — which is
## `ART.keys()` (`gunart.gd:1000-1001`) — and asked its own table about each, so a
## weapon DELETED from `ART` was never asked about at all and it stayed green.
static func roster_diff(anc: Dictionary, art: Dictionary) -> String:
	var theirs := anc.keys()
	var ours := art.keys()
	if theirs != ours:
		return "roster ancestor=%s ours=%s" % [str(theirs), str(ours)]
	var bad := ""
	for key: String in theirs:
		var a: Array = anc[key]
		var o: Array = art[key]
		if o.size() != a.size():
			bad += "%s %d/%d " % [key, o.size(), a.size()]
	return bad


## Part for part, against the walk the MESH BUILDER makes rather than against the
## const. `_parts()` is what `_build` (`gunart.gd:1168`) and `_corners` (`:1003`) both
## iterate, so asserting the ancestor's parts are its PREFIX is a claim about the
## table the game actually reads — and `checks/frame.gd:1412-1423` already ties that
## walk to the committed `ArrayMesh`, so the chain reaches from this file's authority
## all the way to the vertices on screen.
##
## Live waivers are skipped and NOT counted; the caller asserts a positive count, so a
## register that named every part would drive the count to zero and fail rather than
## quietly switching the check off. Returns `{"diff": String, "n": int}`.
static func part_diff(anc: Dictionary, walk: Dictionary, keys: Array,
		live: Dictionary) -> Dictionary:
	var bad := ""
	var n := 0
	for key: String in keys:
		var a: Array = anc[key]
		var o: Array = walk.get(key, [])
		if o.size() < a.size():
			bad += "%s walks %d parts, the ancestor drew %d; " % [key, o.size(), a.size()]
			continue
		for i in a.size():
			if live.has("%s:%d" % [key, i]):
				continue
			n += 1
			var why := part_reason(o[i], a[i])
			if why.is_empty():
				continue
			# Written in `row_text` notation on purpose: these two strings are exactly
			# what a `DEPARTURES` row wants, so recording a deliberate change is a
			# paste rather than a transcription.
			bad += "%s:%d %s — ancestor %s, ours %s; " % [
				key, i, why, row_text(a[i]), row_text(o[i])]
	return {"diff": bad, "n": n}


# --- the tail: what this project appends past the ancestor's parts --------------
#
# THE CHECK THIS REPLACES WAS A SELF-COMPARISON AND THAT IS WHY THERE IS A RECORD
# HERE. It passed `GUNART.SIGHTS` in as the EXPECTATION against a walk that IS
# `ART + SIGHTS`, so both sides of every `==` were the same const. Algebraically its
# size clause collapsed to `ART[key].size() == anc[key].size()` — the roster check's
# own clause, written twice — and its element loop compared `SIGHTS[j]` against
# `SIGHTS[j]`. MEASURED: a destroyed M16 front tower, reversed RPK sight rows and a
# magenta M14 front post all passed the whole 789-assertion suite untouched.
#
# The claim it was NAMED for is still worth making, so it is made against something
# `SIGHTS` cannot move: a recorded decision in this file, and a set of rules about
# what a sight has to BE.


## `SIGHTS` is ours, so the ancestor cannot arbitrate it — but `_part_box()` can say
## what each row is mounted on, and `kriegsnacht.html:1150`'s own "muzzle at the left,
## stock right" is what makes a front post a front post.
##
## Preloaded HERE rather than handed down from `checks/frame.gd` because that file is
## unparseable by the gate (see the header) and this one is not. MEASURED: the only
## occurrence of an autoload's name anywhere in `gunart.gd` is the word `Rng` inside a
## comment at `gunart.gd:28`, so `--check-only --script scripts/dev/ancestor_art.gd`
## still exits 0 with this here — which is what keeps every non-trivial line of this
## package out of the ungateable file.
const GUNART := preload("res://scripts/data/gunart.gd")

## THE SIGHT RECORD: every field of every iron sight this project draws, and the
## decision behind each row.
##
## **There is no ancestor to read here, and that is the whole point.** `ART` has an
## authority upstream of it in this repo, which is why the check this package deleted
## was wrong to hand-type a statistic derived from it — the fix there was to read
## `kriegsnacht.html`. `SIGHTS` has no upstream: `gunart.gd:405-414` says it is
## INVENTED and kept out of `ART` on purpose, and the ancestor's viewmodel was a flat
## baked canvas with no sights to be faithful to. CLAUDE.md allows three provenances —
## an ancestor line, a canon source, or "this is our decision, and here is why" — and
## only the third is available. A decision that is not written down is not a decision,
## so this is where it is written.
##
## **Why this is not `ANCESTOR_PARTS` again.** That was a LOSSY pin (thirteen integers
## standing in for 101 parts of six fields each) with NO provenance, on a table that
## had a readable authority. It rotted invisibly for four milestones. This is a
## LOSSLESS pin — every field of all 18 rows — so it cannot go stale quietly; it goes
## red on the first edit. The failure mode moves from "silently wrong" to "loudly out
## of date", which is the trade `notes/perf/frames/golden.json` already makes for the
## entire visual gate, and `sight_rules()` below is this package's `relations` block:
## the half a re-paste cannot satisfy.
##
## **What it costs to change a sight.** Edit `SIGHTS`, run `--verify`, paste the row
## the failure prints — it is printed in this notation for exactly that reason — and
## write the sentence. `WHY_MIN` makes the sentence mandatory.
##
## Rows are `row_text()`'s own output, GENERATED AND PASTED rather than transcribed:
## `self_test()` below records that hand-typing this notation went wrong on its first
## attempt, because `String.num(1.0, 4)` renders "1.0" and not "1".
const SIGHT_RECORD := {
	"m1911": {
		"rows": ["r|28.0|17.6|1.8|2.4|1a1c1eff", "r|54.5|16.6|2.2|3.4|1a1c1eff"],
		"why": "A 1911's sights are milled into the slide and travel with it, which is why "
			+ "both rows are named by SLIDE (7 and 8, gunart.gd:186 — ART holds 7 parts, "
			+ "so those two indices ARE these two rows) and why the rear blade sits at x 54.5, "
			+ "behind the grip at 52. Both stand on the slide plate (part 1, top y 20), 2.4 "
			+ "and 3.4 units proud.",
	},
	"olympia": {
		"rows": ["r|8.0|17.0|1.6|2.5|1a1c1eff"],
		"why": "A break-action shotgun carries a bead and no rear blade (gunart.gd:442-443), so "
			+ "one row at the muzzle end is the entire sight. It stands 2.5 units above the "
			+ "top barrel (part 0, top y 20) and nothing on this weapon reciprocates.",
	},
	"m14": {
		"rows": ["r|12.0|19.5|1.8|2.5|1a1c1eff", "r|56.0|17.0|2.2|3.0|1a1c1eff"],
		"why": "Post on the gas cylinder over the barrel (part 0, top y 22, 2.5 proud), rear "
			+ "on the receiver (part 1, top y 20, 3.0 proud) and well behind it — an M14's "
			+ "rear aperture is at the back of the receiver, not on the stock comb.",
	},
	"mp40": {
		"rows": ["r|10.0|20.5|1.6|2.5|1a1c1eff", "r|50.0|17.6|2.0|2.4|1a1c1eff"],
		"why": "The hooded post rides the barrel (part 0, top y 23, 2.5 proud); the rear leaf "
			+ "sits on the receiver (part 1, top y 20, 2.4 proud), forward of the folding "
			+ "stock hinge the ancestor drew at x 64.",
	},
	"pm63": {
		"rows": ["r|13.5|21.5|1.5|2.5|1a1c1eff", "r|46.0|18.4|1.8|2.6|1a1c1eff"],
		"why": "The smallest pair on the roster, because the PM63 is the smallest weapon: 1.5 "
			+ "and 1.8 wide. Post on the barrel (part 0, top y 24); the rear sits on the "
			+ "receiver that IS the bolt on a PM63, which is why part 1 is also SLIDE[\"pm63\"].",
	},
	"ak74u": {
		"rows": ["r|8.0|19.0|1.8|4.0|1a1c1eff", "r|52.0|17.0|2.0|4.0|1a1c1eff"],
		"why": "The only matched-height pair, 4.0 and 4.0: an AK's front post stands in a tall "
			+ "block of protective ears and its rear leaf on a raised sight base, so neither "
			+ "is the low blade the other weapons carry. Post on the barrel (part 0, top y 23), "
			+ "rear on the dust cover (part 3, top y 21).",
	},
	"stakeout": {
		"rows": ["r|6.0|18.0|1.6|4.0|1a1c1eff"],
		"why": "A bead and no rear blade like the Olympia (gunart.gd:442-443), but 4.0 tall rather "
			+ "than 2.5 for the reason gunart.gd:464-466 already records: this weapon's "
			+ "receiver tops out above its own barrel, so a bead level with the barrel would "
			+ "not be the top of the weapon and sight_height() would go on reading the receiver.",
	},
	"m16": {
		"rows": ["r|6.0|18.5|2.2|4.5|1a1c1eff", "r|46.0|15.6|2.0|2.0|1a1c1eff"],
		"why": "The front tower is the M16's whole silhouette cue (gunart.gd:468) and at 4.5 it "
			+ "is the tallest sight row on the roster, which is what the `cue` rule pins. The "
			+ "rear blade stands on the CARRY HANDLE (part 2, top y 17) rather than on the "
			+ "receiver, which is what makes its 1.4 units of protrusion the tightest here and "
			+ "the reason SIGHT_PROUD is 1.0 rather than 2.0.",
	},
	"rpk": {
		"rows": ["r|5.0|19.5|2.0|3.5|1a1c1eff", "r|54.0|18.0|2.0|3.0|1a1c1eff"],
		"why": "The longest post-to-blade gap on the roster, 47.0 units, because the RPK has "
			+ "the longest barrel: post at x 5 on the barrel (part 0, top y 23), rear leaf at "
			+ "x 54 on the dust cover (part 3, top y 21).",
	},
	"chinalake": {
		"rows": ["r|9.0|16.0|1.8|3.0|1a1c1eff", "r|50.0|15.0|2.0|4.0|1a1c1eff"],
		"why": "A ladder sight, which is what a China Lake carries (gunart.gd:474). Its rear "
			+ "leaf reaches art y 15.0, the highest point any sight row reaches, and its front "
			+ "post is the only row on the roster seated on a CIRCLE — part 2, the launcher's "
			+ "tube mouth, whose box tops out at y 18.6034.",
	},
}

## 18 = eight weapons with a post and a blade, plus the Olympia's and the Stakeout's
## bead (`gunart.gd:442-443`), plus nothing for the Ray Gun, the Thundergun and the
## knife (`:443`).
##
## TRIANGULATED, not typed off a run — which is what separates it from the thirteen
## integers this package deleted. `record_faults()` requires it to equal the record's
## own row total; `checks/frame.gd:1399` independently pins `_parts()`'s roster total
## at 119 while check 2 reads 101 parts out of `kriegsnacht.html` (MEASURED: "ancestor
## parts total: 101 over 13 weapons"), and 119 - 101 = 18. Three statements authored at
## three different times, and the check is red unless all three agree.
const SIGHT_ROWS := 18

## Every sight row is this one colour and there are no others — MEASURED over the walk,
## `{"1a1c1eff": 18}`.
##
## OUR DECISION: a sight reads as a silhouette against the target and not as a painted
## feature, so the whole roster is the darkest gunmetal in the ancestor's own palette,
## `'#1A1C1E'` at `kriegsnacht.html:1166`. Eight digits because `hex_of()` renders
## eight on both sides now; see there for what alpha does and does not protect.
const SIGHT_HEX := "1a1c1eff"

## How far a sight has to stand clear of the art it is mounted on, in art units.
##
## `gunart.gd:438-440` states the rule — every post and blade sits above the top edge
## of everything under it, so no depth assignment can hide one behind the part it is
## mounted on — and then admits it is "checked by eye against the table above". This is
## that eye. The number is `checks/frame.gd:1789`'s own "a full art unit clear", reused
## so this project has one margin and not two. MEASURED headroom: the tightest row is
## the M16's rear blade on its carry handle at 1.4, the loosest the M16's own tower at
## 4.5, and every one of the 18 rows overlaps at least one `ART` part, so the "mounted
## on nothing" clause has no false positive today.
const SIGHT_PROUD := 1.0

## Field names for a six-field rect, so a failure says `colour` and not `field 5`.
const SIGHT_FIELDS := ["kind", "x", "y", "w", "h", "colour"]


## The first field of a recorded row the walked row does not match, named.
static func _sight_field(want: String, got: String) -> String:
	var a := want.split("|")
	var b := got.split("|")
	if a.size() != b.size():
		return "%d fields, not %d" % [b.size(), a.size()]
	for i in a.size():
		if String(a[i]) == String(b[i]):
			continue
		var field: String = String(SIGHT_FIELDS[i]) if i < SIGHT_FIELDS.size() else "field %d" % i
		return "%s %s, not %s" % [field, String(b[i]), String(a[i])]
	return ""


## The rows the weapon builder walks PAST the ancestor's parts, against the record.
##
## SLICED AT THE ANCESTOR'S COUNT AND NOT AT `ART`'s, which is what makes this the
## non-circular form of the sentence the deleted check was named for: the actual side
## is `_parts()` — the array `_build` (`gunart.gd:1168`) and `_corners` (`:1003`) both
## iterate — and the slice index comes out of `kriegsnacht.html`. It does mean a roster
## failure reddens this too; check 2 is the one that names it, and the coupling is
## correct because the claim being made is about where the ANCESTOR's parts end.
##
## COUNTS ROWS, NOT WEAPONS. The check this replaced counted weapons, so `SIGHTS`
## emptied outright would have reported n=13 having compared nothing at all.
##
## **SPLIT AT THE RECORD'S OWN LENGTH, not taken as the whole remainder**, which is
## what makes room for `gunart.gd`'s `DETAIL` band. The walk used to be `ART + SIGHTS`
## and one slice covered both our tables; it is now `ART + SIGHTS + DETAIL`, so the
## sight band is `[|ancestor|, |ancestor| + |record|)` and everything past it is the
## detail band, returned separately for `detail_rules()`. **Neither slice point is
## circular**: the first comes out of `kriegsnacht.html`, the second out of this
## file's own record — never out of `SIGHTS`, which is the side under test.
##
## Provably a no-op while `DETAIL` is empty (the two slices name the same rows), and
## strictly stronger the moment it is not: a detail row can no longer land in the
## sight band and be mistaken for a sight, and a sight row that goes MISSING still
## reddens here on the count rather than reappearing as a short detail band. A row
## that overflows the record's length lands in the detail band, where check 4c's
## `DETAIL_ROWS` pin is red on it.
##
## Returns `{"diff": String, "n": int, "tails": Dictionary, "details": Dictionary}`.
static func sight_diff(anc: Dictionary, walk: Dictionary, keys: Array) -> Dictionary:
	var bad := ""
	var n := 0
	var tails := {}
	var details := {}
	for key: String in keys:
		var a: Array = anc[key]
		var o: Array = walk.get(key, [])
		var rec: Dictionary = SIGHT_RECORD.get(key, {})
		var want: Array = rec.get("rows", [])
		if o.size() < a.size():
			bad += "%s walks %d parts, fewer than the %d the ancestor drew, so it has no tail; " % [
				key, o.size(), a.size()]
			tails[key] = []
			details[key] = []
			continue
		var tail: Array = o.slice(a.size(), a.size() + want.size())
		tails[key] = tail
		details[key] = o.slice(a.size() + want.size())
		if tail.size() != want.size():
			bad += "%s walks %d rows past the ancestor's %d parts, the record pins %d; " % [
				key, tail.size(), a.size(), want.size()]
			continue
		for j in want.size():
			n += 1
			var got := row_text(tail[j])
			var pin := String(want[j])
			if got == pin:
				continue
			# In the record's own notation, so re-recording a deliberate change is a
			# paste and a sentence rather than a transcription.
			bad += "%s sight[%d] %s — recorded %s, walked %s; " % [
				key, j, _sight_field(pin, got), pin, got]
	return {"diff": bad, "n": n, "tails": tails, "details": details}


## The record itself: rows for every sighted weapon, a reason for each, and a total
## that agrees with `SIGHT_ROWS`. Without this the constant would be a free integer and
## the table one nobody validates — which is the shape of the check this package
## deleted. Returns "" when the record is well formed.
static func record_faults() -> String:
	var bad := ""
	var total := 0
	for key: String in SIGHT_RECORD:
		var rec: Dictionary = SIGHT_RECORD[key]
		var rows: Array = rec.get("rows", [])
		if rows.is_empty():
			bad += "%s: the record pins no rows; " % key
		total += rows.size()
		if String(rec.get("why", "")).length() < WHY_MIN:
			bad += "%s: no reason given for these rows; " % key
	if total != SIGHT_ROWS:
		bad += "the record holds %d rows, SIGHT_ROWS says %d; " % [total, SIGHT_ROWS]
	return bad


## THE HALF A RE-PASTE CANNOT SATISFY.
##
## The record above is a table of absolutes and absolutes are what get re-pasted;
## CLAUDE.md's answer to that everywhere else in this project is `golden.json`'s
## `relations` block — rules that survive a retune, each carrying its own provenance.
## This is that block for the sights, asserted over the WALK's tail rather than over
## `SIGHTS`. MEASURED: sabotage `SIGHTS` and then update the record to match — exactly
## what a hurried agent does — and each of the four sabotages this package was written
## against still fails here.
##
##   shape   a sight is a six-field rect WITH AREA. A row zeroed to 0x0 keeps its
##           count, its index, its `DEPTH` row and its position, and draws nothing.
##   colour  `SIGHT_HEX`, alpha included. See there.
##   proud   `SIGHT_PROUD` above the top of every `ART` part it overlaps in x, measured
##           through `_part_box()` — the builder's own bounds helper, so a circle and a
##           rotated rect are bounded by what is actually extruded rather than by rect
##           maths written a second time here. THE SEAT IS IMMOVABLE: `ART` is the
##           ancestor's, byte-pinned by check 1 and compared part for part by check 3,
##           so this rule cannot be satisfied by lowering the gun under the sight.
##   order   the front row ends before the rear row begins. `kriegsnacht.html:1150`
##           authors this space "muzzle at the left, stock right", so forward means
##           smaller x, and `gunart.gd:421-422` states the picture as "a tall near blade
##           with a small far post beyond it". Reversing a weapon's rows swaps which
##           one the eye looks through. MEASURED margins 24.7 (m1911) to 47.0 (rpk).
##   cue     the M16's front tower is the tallest sight row on the roster
##           (`gunart.gd:468`, "the M16's whole silhouette cue"). MEASURED 4.5 against
##           a runner-up of 4.0. This is the rule a shortened-but-still-legal tower
##           fails, and it is deliberately a claim about the WHOLE roster: raising
##           another weapon's sight past 4.5 is a design decision about the M16 and
##           ought to stop.
##
## **NARROWED TO THE SIGHT BAND, DELIBERATELY, and it cost real coverage.** The code
## below has not changed; what changed is that `sight_diff` now hands it the SIGHT
## band rather than the whole walked tail. Both the `count` cap and the roster-wide
## `cue` claim always MEANT the sights — before a third band existed the distinction
## was free — and without the narrowing a heat-shield vent would fail as "a third
## sight row" and a bipod taller than 4.5 units as "out-towering the M16", which is
## the blocker `DETAIL` exists to remove. A NO-OP TODAY: `DETAIL` is empty, so the
## band and the tail are the same rows.
##
## THE COVERAGE LOST, named so it cannot go quiet: `cue` no longer bounds the height
## of anything outside the sight band. `detail_rules()`'s `quiet` clause carries that
## for the detail band — a detail row may not become the top of the weapon — and if
## that clause is ever deleted the loss is silent, because the assertion that watches
## the ADS drop asserts an algebraic identity in `ADS_SIGHT_CLEAR` and is blind to its
## value (`checks/projectiles.gd`'s own comment says so).
##
## COUNTS ROWS AND RETURNS THE COUNT, so this has its own acceptance guard and cannot
## pass having looked at nothing. Not redundant with `sight_diff`'s guard: this one
## walks the tails, so a tail that was somehow non-empty but unrecorded makes the two
## counts disagree and reddens both. Returns `{"diff": String, "n": int}`.
static func sight_rules(art: Dictionary, tails: Dictionary) -> Dictionary:
	var bad := ""
	var n := 0
	var tallest := ""
	var tall := -1.0
	for key: String in tails:
		var rows: Array = tails[key]
		# An empty tail is a weapon with no sights, which is the record's business: the
		# Ray Gun, the Thundergun and the knife are recorded as carrying none.
		if rows.is_empty():
			continue
		var parts: Array = art.get(key, [])
		if rows.size() > 2:
			bad += "count: %s walks %d sight rows, and no weapon carries more than a post and a blade; " % [
				key, rows.size()]
		var span: Array = []          # [x, x + w] per row, for the `order` rule
		for i in rows.size():
			var row: Array = rows[i]
			n += 1
			if row.size() != 6 or String(row[0]) != "r":
				bad += "shape: %s[%d] is not a six-field rect; " % [key, i]
				span.append(null)
				continue
			var x: float = row[1]
			var y: float = row[2]
			var w: float = row[3]
			var h: float = row[4]
			span.append(Vector2(x, x + w))
			if w <= 0.0 or h <= 0.0:
				bad += "shape: %s[%d] is %s x %s and draws nothing; " % [key, i, _num(w), _num(h)]
			if h > tall:
				tall = h
				tallest = key
			var hex := hex_of(row)
			if hex != SIGHT_HEX:
				bad += "colour: %s[%d] is %s, not the sight black %s; " % [key, i, hex, SIGHT_HEX]
			# Art y counts DOWNWARD, so the smallest top is the highest part, and the
			# exposed height of a sight is `min(h, top - y)` — which goes negative for a
			# blade buried inside the part it is nominally mounted on.
			var top := 1e9
			for p: Array in parts:
				var box: Rect2 = GUNART._part_box(p, 0.0)
				if box.end.x <= x or box.position.x >= x + w:
					continue
				top = minf(top, box.position.y)
			if top > 1e8:
				bad += "proud: %s[%d] overlaps no part of the weapon and is mounted on nothing; " % [
					key, i]
			elif minf(h, top - y) < SIGHT_PROUD:
				bad += "proud: %s[%d] stands %s units above the art it is mounted on, not %s; " % [
					key, i, _num(minf(h, top - y)), _num(SIGHT_PROUD)]
		if span.size() >= 2 and span[0] != null and span[1] != null:
			var f: Vector2 = span[0]
			var r: Vector2 = span[1]
			if f.y > r.x:
				bad += "order: %s's front post ends at x %s, behind its rear blade at x %s; " % [
					key, _num(f.y), _num(r.x)]
	if n == 0:
		bad += "cue: there is no sight row on the roster at all; "
	elif tallest != "m16":
		bad += "cue: the tallest sight row on the roster is %s's %s units, not the M16's tower; " % [
			tallest, _num(tall)]
	return {"diff": bad, "n": n}


## The A1 failure message. Composed here rather than in `checks/frame.gd` because
## nothing in that file is parse-gateable (see the header), and because a message that
## prints the anchor TEXT beside the line it was found at is what separates "the
## citation moved" from "the file vanished" — two failures that otherwise read alike.
static func read_detail(res: Dictionary) -> String:
	var why := String(res.get("why", ""))
	var sha := String(res.get("sha", ""))
	return "%s[%s] at line %d (cited %d), [%s] at %d (cited %d); sha %s, pinned %s" % [
		"" if why.is_empty() else why + "; ",
		HEAD_TEXT, int(res.get("head", -1)), HEAD_LINE,
		TAIL_TEXT, int(res.get("tail", -1)), TAIL_LINE,
		"<none>" if sha.is_empty() else sha, ANCESTOR_SHA]


## The waivers that are live, exact on both sides and reasoned, as {"weapon:index":
## true}. Everything rejected lands in `bad` with its reason, and A REJECTED WAIVER
## SUPPRESSES NOTHING — so a bad waiver reddens the part comparison as well, rather
## than quietly hiding a real drift while a second check complains about the paperwork.
static func waivers(reg: Dictionary, anc: Dictionary, walk: Dictionary,
		bad: Array) -> Dictionary:
	var live := {}
	for key: String in reg:
		var row: Dictionary = reg[key]
		var bits := key.split(":")
		if bits.size() != 2 or not String(bits[1]).is_valid_int():
			bad.append("%s: key is not weapon:index" % key)
			continue
		var gun := String(bits[0])
		var idx := int(bits[1])
		var a_rows: Array = anc.get(gun, [])
		var o_rows: Array = walk.get(gun, [])
		if idx < 0 or idx >= a_rows.size() or idx >= o_rows.size():
			bad.append("%s: no such part on both sides" % key)
			continue
		var want_anc := String(row.get("anc", ""))
		var want_ours := String(row.get("ours", ""))
		var got_anc := row_text(a_rows[idx])
		var got_ours := row_text(o_rows[idx])
		if want_anc != got_anc:      # the authority moved under the waiver
			bad.append("%s: the ancestor is now %s, the waiver records %s" % [
				key, got_anc, want_anc])
			continue
		if want_ours != got_ours:    # we drifted further, behind the waiver
			bad.append("%s: ours is now %s, the waiver records %s" % [
				key, got_ours, want_ours])
			continue
		if part_reason(o_rows[idx], a_rows[idx]).is_empty():
			bad.append("%s: waives a difference that is not there" % key)
			continue
		if String(row.get("why", "")).length() < WHY_MIN:
			bad.append("%s: no reason given" % key)
			continue
		live[key] = true
	return live


## One rejection fixture: the register must be refused, AND REFUSED BY THE CLAUSE THE
## FIXTURE IS NAMED FOR.
##
## THE TAG MATCH IS NOT DECORATION, IT IS THE FIX FOR A FIXTURE THAT LIED. The first
## draft of `self_test()` had a case printing "a waiver for a difference that is gone
## was honoured" which never reached that clause at all — it was intercepted two
## clauses earlier by `ours is now`, so `part_reason(...).is_empty()` could be deleted
## outright and the whole suite stayed green while a fixture that read as covering it
## sat right there. A fixture that only asserts "something complained" is one refactor
## away from asserting nothing.
static func _rejected(reg: Dictionary, anc: Dictionary, walk: Dictionary,
		tag: String, what: String) -> String:
	var b: Array = []
	waivers(reg, anc, walk, b)
	if b.is_empty():
		return "%s was honoured; " % what
	if not String(b[0]).contains(tag):
		return "%s was refused by the wrong clause — [%s] does not name [%s]; " % [
			what, String(b[0]), tag]
	return ""


## The validator's own control, so the check that runs it is never vacuous while
## `DEPARTURES` is legitimately empty.
##
## THIS IS THE ANSWER TO "a skip must never pass". A validator run over an empty
## register asserts precisely nothing, and an empty register is the correct state of
## the project today — so the check ANDs the real register with these fixtures, which
## drive the same `waivers()` over cases the real one has none of. Returns "" when the
## validator behaves.
##
## ONE FIXTURE PER REJECTION CLAUSE, AND THAT IS AUDITED BY DELETING THEM. `waivers()`
## refuses on six conditions; MEASURED by deleting each in turn and running the suite,
## the first draft controlled only three — `key is not weapon:index`, `the ancestor is
## now` and `waives a difference that is not there` could all be removed with the suite
## still green at 789. The two silent ones were the two halves of the check's own name:
## the ANCESTOR side of "exact on both sides", and the clause that stops a waiver
## becoming a permanent blanket on a part that no longer differs. The pairs below split
## the two `or`ed halves of the key clause and the two halves of the range clause,
## because each half is separately deletable.
##
## The polygon fixtures are here because `row_text()`'s polygon branch is reached ONLY
## by the knife's two `p` rows, and while `DEPARTURES` is empty nothing else would
## notice it regressing.
static func self_test() -> String:
	var why := "a fixture reason long enough to satisfy the register's own minimum."
	var anc := {
		"fixture": [["r", 1.0, 2.0, 3.0, 4.0, "112233"]],
		"poly": [["p", [0.0, 0.0, 4.0, 0.0, 4.0, 2.0], "445566"]],
	}
	var departed := {
		"fixture": [["r", 1, 2, 9, 4, Color("112233")]],
		"poly": [["p", [0, 0, 5, 0, 4, 2], Color("445566")]],
	}
	var settled := {
		"fixture": [["r", 1, 2, 3, 4, Color("112233")]],
		"poly": [["p", [0, 0, 4, 0, 4, 2], Color("445566")]],
	}
	# The pinned text is `row_text()`'s own output and nothing else — MEASURED, because
	# the first draft of these fixtures wrote `r|1|2|3|4|...` and `self_test()` rejected
	# them: `String.num(1.0, 4)` renders "1.0", not "1". The fixtures caught the
	# author's transcription error before the register ever had a row in it, which is
	# the whole reason they are here. They carry eight hex digits for the same reason:
	# `hex_of()` renders RRGGBBAA on both sides now.
	var anc_txt := "r|1.0|2.0|3.0|4.0|112233ff"
	var ours_txt := "r|1.0|2.0|9.0|4.0|112233ff"
	var live_reg := {"fixture:0": {"anc": anc_txt, "ours": ours_txt, "why": why}}
	var poly_reg := {"poly:0": {
		"anc": "p|[0.0,0.0,4.0,0.0,4.0,2.0]|445566ff",
		"ours": "p|[0.0,0.0,5.0,0.0,4.0,2.0]|445566ff", "why": why}}
	var out := ""

	# THE ACCEPTANCE HALF. A control that only asserts the refusal passes equally well
	# against a validator that refuses everything, which would switch the register off.
	var b: Array = []
	var honoured := waivers(live_reg, anc, departed, b)
	if not b.is_empty() or not honoured.has("fixture:0"):
		out += "a live waiver was rejected: %s; " % str(b)
	b = []
	var poly_live := waivers(poly_reg, anc, departed, b)
	if not b.is_empty() or not poly_live.has("poly:0"):
		out += "a live waiver on a polygon part was rejected: %s; " % str(b)

	# 1a/1b. The key is `weapon:index` — no separator, and a non-integer index.
	out += _rejected({"fixture": {"anc": anc_txt, "ours": ours_txt, "why": why}},
		anc, departed, "key is not weapon:index", "a waiver whose key has no index")
	out += _rejected({"fixture:top": {"anc": anc_txt, "ours": ours_txt, "why": why}},
		anc, departed, "key is not weapon:index", "a waiver indexed by a word")

	# 2a/2b. The part exists on both sides — past the end, and before the start. The
	# register is legitimately empty, so nothing else exercises either branch.
	out += _rejected({"fixture:7": {"anc": anc_txt, "ours": ours_txt, "why": why}},
		anc, departed, "no such part", "a waiver naming a part that does not exist")
	out += _rejected({"fixture:-1": {"anc": anc_txt, "ours": ours_txt, "why": why}},
		anc, departed, "no such part", "a waiver on a negative index")

	# 3. THE ANCESTOR HALF of "exact on both sides" — the authority moved under the
	# waiver. `ours` is pinned correctly here so nothing downstream can intercept it.
	out += _rejected({"fixture:0": {
			"anc": "r|1.0|2.0|7.0|4.0|112233ff", "ours": ours_txt, "why": why}},
		anc, departed, "the ancestor is now",
		"a waiver whose record of the ANCESTOR moved")

	# 4. ...and ours: we drifted further, behind an existing waiver.
	out += _rejected({"fixture:0": {
			"anc": anc_txt, "ours": "r|1.0|2.0|5.0|4.0|112233ff", "why": why}},
		anc, departed, "ours is now", "a waiver whose record of OURS moved")

	# 5. IT IS STILL A LIVE DIFFERENCE. Pinned to the settled state on BOTH sides and
	# driven against the settled walk, so clauses 3 and 4 are satisfied and this is the
	# only one left that can fire — which is exactly what the mislabelled first draft
	# failed to arrange. Without it a waiver survives the departure being reverted and
	# becomes a permanent blanket on that part.
	out += _rejected({"fixture:0": {"anc": anc_txt, "ours": anc_txt, "why": why}},
		anc, settled, "waives a difference that is not there",
		"a waiver for a difference that is gone")

	# 6. ...and it is reasoned.
	out += _rejected({"fixture:0": {
			"anc": anc_txt, "ours": ours_txt, "why": "looks better"}},
		anc, departed, "no reason given", "a waiver with no reason")
	return out


# --- the bands: the walk decomposed, and what each band owes ---------------------
#
# `gunart.gd`'s walk is `ART + SIGHTS + DETAIL`, in that order, and everything below
# is a claim about that decomposition. It is HERE and not in `checks/frame.gd` for
# the reason this file's header gives: `frame.gd` aborts its parse gate at the
# documented `Rng` autoload false positive, hundreds of lines above these checks, so
# nothing added down there is gateable at all. `frame.gd` gets a driver line and a
# `v.check`; the walks live here, where `--check-only` can see them.


## The ancestor's own part total, and the constant the per-band decomposition leans
## on.
##
## **NOT A FREE INTEGER.** `checks/frame.gd`'s check 2 asserts the ancestor's OWN rows
## sum to this, out of the table read from `kriegsnacht.html` at check time — the one
## clause a re-paste cannot satisfy, and the reason 101 + 18 + 0 is strictly stronger
## than the `parts_total == 119` it strengthens. 119 is satisfied by 100 + 19 and by
## any other partition; three record-backed components are not. No second 140 KB read
## is paid: check 2 is already holding the parsed table.
const ART_ROWS := 101

## THE DETAIL RECORD: every field of every row of `gunart.gd`'s `DETAIL` band, and the
## decision behind each. Empty, because the band ships empty.
##
## Same shape and same bargain as `SIGHT_RECORD` above — a LOSSLESS pin that goes red
## on the first edit rather than rotting quietly — and deliberately NOT extended to the
## other two bands. `ART` has `kriegsnacht.html` upstream of it and needs no record
## here; `SIGHTS` already has one. Recording only the new band is the whole of what
## this package owes, and a 119-row roster record would be 119 rows of transcription
## surface bought for nothing.
const DETAIL_RECORD := {}

## Rows the detail band holds today. Zero, and the FIRST ROW REDDENS THIS — which is
## the intent, not an obstacle: new geometry of ours should be a loud, argued edit,
## exactly as an `ART` cardinality change is. Move it, and write the reason into
## `DETAIL_RECORD`.
const DETAIL_ROWS := 0

## The detail band's own record validator, mirroring `record_faults()`.
static func detail_faults() -> String:
	var bad := ""
	var total := 0
	for key: String in DETAIL_RECORD:
		var rec: Dictionary = DETAIL_RECORD[key]
		var rows: Array = rec.get("rows", [])
		if rows.is_empty():
			bad += "%s: the record pins no rows; " % key
		total += rows.size()
		if String(rec.get("why", "")).length() < WHY_MIN:
			bad += "%s: no reason given for these rows; " % key
	if total != DETAIL_ROWS:
		bad += "the record holds %d rows, DETAIL_ROWS says %d; " % [total, DETAIL_ROWS]
	return bad


## The record against the BAND, row for row — the half `detail_faults` above does not
## do and the check's name claims.
##
## `detail_faults` validates the record's own shape: rows present, a reason per weapon,
## a total agreeing with `DETAIL_ROWS`. None of that reads `GUNART.DETAIL`, so the
## record could disagree with every live row and still be "well formed". MEASURED
## before this existed: one real row in `DETAIL` against a `DETAIL_RECORD` that
## disagreed in x, y, w, h AND colour — `r|53|28|5|12|3a2512ff` live against
## `r|1|2|3|4|ff00ffff` recorded — left the suite GREEN at 797 with the detail check
## passing. The band being empty today is what kept that from being a live defect, and
## the band existing is the entire package, so the first row authored would have been
## pinned by a document nothing read.
##
## Deliberately the same loop as `sight_diff`'s, in the same notation, for the same
## reason: re-recording a deliberate change is a paste and a sentence.
static func detail_diff(details: Dictionary) -> Dictionary:
	var bad := ""
	var n := 0
	for key: String in GUNART.keys():
		var walked: Array = details.get(key, [])
		var rec: Dictionary = DETAIL_RECORD.get(key, {})
		var want: Array = rec.get("rows", [])
		if walked.size() != want.size():
			bad += "%s walks %d detail rows, the record pins %d; " % [
				key, walked.size(), want.size()]
			continue
		for j in want.size():
			n += 1
			var got := row_text(walked[j])
			var pin := String(want[j])
			if got != pin:
				bad += "%s detail[%d] — recorded %s, walked %s; " % [key, j, pin, got]
	return {"diff": bad, "n": n}


## WHAT MAKES A DETAIL ROW LEGITIMATE. `gunart.gd:759-765`'s own rule, written as a
## check for the first time, and the complement of `sight_rules` above: a sight stands
## `SIGHT_PROUD` ABOVE what it overlaps, a detail sits ON it. Neither can satisfy the
## other's rule, so a row filed in the wrong band fails the band it is in.
##
##   shape   one of the builder's kinds, WITH AREA. A row zeroed to 0x0 keeps its
##           count, its index, its `DEPTH` entry and its position, and draws nothing.
##   seat    its art box lies INSIDE the box of a part drawn before it. That single
##           geometric test is what separates a detail from a sight.
##   proud   its `part_half` exceeds the `part_half` of every part it is seated in.
##           `gunart.gd:757-765`: author a highlight thin and IT DISAPPEARS, because
##           the ancestor drew it OVER the plate it lies on. MEASURED over the shipped
##           roster through the real accessors: 27 parts are already drawn strictly
##           inside an earlier part's box, all 27 come out deeper than every host, and
##           the tightest margin is exactly one `LAYER` step (0.1400 art units) on
##           fifteen of them.
##   quiet   it may not become the TOP of the weapon. `sight_height()` is a max over
##           `_parts()`' INFLATED corners and the rig drops the whole viewmodel by it,
##           so a bipod that reads as the sight line moves the ADS pose on a weapon
##           nobody re-argued. THIS CLAUSE IS WHERE THE COVERAGE `sight_rules`'
##           narrowed `cue` GAVE UP LANDS; see there.
##
##           MEASURED OVER INFLATED BOXES AND NOT NOMINAL ONES, which is the whole
##           mechanism: a row seated inside a part is below that part's nominal top by
##           construction, so a nominal test could never fire behind `seat` — but it
##           carries a LATER rank, so `rank*PROUD` grows it further outward, and a row
##           laid flush along the top edge of the topmost part (which is exactly what a
##           highlight rib is) comes out ABOVE it and takes the sight line. THE COST,
##           stated because it is real: this refuses serrations laid flush with the top
##           edge of a weapon's highest part. Drop them a fraction of a unit, or move
##           `ADS_SIGHT_CLEAR`'s argument and record it.
##
## `seat` reads boxes at proud 0.0, like `sight_rules`, so it is a claim about the ART.
## `quiet` reads them at their own rank, because that is what `sight_height` walks.
## Returns `{"diff": String, "n": int}`.
static func detail_rules(art: Dictionary, details: Dictionary) -> Dictionary:
	var bad := ""
	var n := 0
	for key: String in details:
		var rows: Array = details[key]
		if rows.is_empty():
			continue
		var parts: Array = art.get(key, [])
		# The ceiling a detail row may not rise above: the highest INFLATED corner the
		# weapon already draws. Art y counts DOWNWARD, so that is the smallest top edge.
		var roof := 1e9
		for j in parts.size():
			var grown: Rect2 = GUNART._part_box(parts[j], GUNART.part_rank(key, j) * GUNART.PROUD)
			roof = minf(roof, grown.position.y)
		for i in rows.size():
			var row: Array = rows[i]
			n += 1
			if row.size() < 3:
				bad += "shape: %s[%d] is not a part row at all; " % [key, i]
				continue
			var at := _detail_index(key, i)
			var box: Rect2 = GUNART._part_box(row, 0.0)
			var mine: float = GUNART.part_half(key, at)
			if box.size.x <= 0.0 or box.size.y <= 0.0:
				bad += "shape: %s[%d] is %s x %s and draws nothing; " % [
					key, i, _num(box.size.x), _num(box.size.y)]
			var seated := false
			var host := -1.0
			for j in parts.size():
				if not GUNART._part_box(parts[j], 0.0).encloses(box):
					continue
				seated = true
				host = maxf(host, GUNART.part_half(key, j))
			if not seated:
				bad += ("seat: %s[%d] is not drawn inside any part of the weapon, "
					+ "so it is not a surface feature; ") % [key, i]
			elif mine <= host:
				bad += ("proud: %s[%d] is extruded to %s art units inside a part at %s, "
					+ "so the depth buffer hides it; ") % [key, i,
					_num(mine / GUNART.UNIT), _num(host / GUNART.UNIT)]
			var grown_top: float = GUNART._part_box(row, GUNART.part_rank(key, at)
				* GUNART.PROUD).position.y
			if grown_top < roof:
				bad += ("quiet: %s[%d] is inflated to art y %s, above the weapon's own %s, "
					+ "so it becomes the sight line the rig poses with; ") % [
					key, i, _num(grown_top), _num(roof)]
	return {"diff": bad, "n": n}


## Where detail row `i` of `key` sits in the flat walk `part_half` indexes.
static func _detail_index(key: String, i: int) -> int:
	var counts := GUNART.band_census(key)
	return GUNART._band_base(counts, GUNART.B_DETAIL) + i


## The detail rules' own control, so the check that runs them is never vacuous while
## `DETAIL_RECORD` and the band itself are legitimately empty.
##
## THE SAME ANSWER `self_test()` GIVES FOR `DEPARTURES`, for the same reason: a
## validator run over an empty band asserts precisely nothing. ONE FIXTURE PER
## REJECTION CLAUSE, plus the acceptance half — a well-formed detail row must be
## HONOURED, or a rule set that refuses everything would pass the refusal half
## perfectly and switch the band off.
##
## The fixtures drive the REAL `detail_rules()` over a synthetic weapon, so they reach
## the same `_part_box` and the same `part_half` the roster does. `part_half` on a
## fixture key falls back to a multiplier of 1.0 (`gunart.gd`'s documented no-`DEPTH`
## behaviour) at rank 0, i.e. 2.60 art units — which is why the fixture host is a
## `D_THIN`-shaped 1.30 in the acceptance case and a deep host in the `proud` case.
static func detail_self_test() -> String:
	var out := ""
	# THE FIXTURE WEAPON IS THE KNIFE, and that is forced rather than arbitrary. The
	# rules read `band_census` and `part_half` off the REAL tables, so a synthetic key
	# has an empty census — which puts a fixture's detail row at rank 0, the same rank
	# as its own host, and `proud` could then neither pass nor fire honestly. The
	# knife's five `ART` parts put a detail row at rank 5, where `part_half` reads 3.30
	# art units under the documented no-`DEPTH`-entry fallback, against authored hosts
	# of 1.30 (part 0, `D_THIN`) and 3.42 (part 4, `D_FAT`). BOTH SIDES OF `proud` ARE
	# THEREFORE REACHABLE, which is the requirement a fixture exists to meet — the
	# first draft used a synthetic key and its acceptance case failed on its own
	# `proud` clause, which is precisely the interception `self_test()` above was
	# rewritten to remove.
	var host := ["r", 10.0, 20.0, 20.0, 10.0, Color("112233")]
	var away := ["r", 90.0, 50.0, 2.0, 2.0, Color("112233")]
	# The enclosing plate at index 0 (`D_THIN`, 1.30) — the detail row is proud of it.
	var thin_host := {"knife": [host, away, away, away, away]}
	# ...and at index 4 (`D_FAT`, 3.42) — deeper than the detail row's own 3.30.
	var deep_host := {"knife": [away, away, away, away, host]}

	# THE ACCEPTANCE HALF. A serration inside the plate, with area, clear of its top
	# edge. A rule set that refuses everything passes every refusal below perfectly and
	# switches the band off, which is the failure this half exists to catch.
	var ok := detail_rules(thin_host, {"knife": [["r", 12.0, 22.0, 6.0, 2.0, Color("445566")]]})
	if not String(ok["diff"]).is_empty() or int(ok["n"]) != 1:
		out += "a well-formed detail row was refused: %s; " % String(ok["diff"])

	# 1. shape — zero area. It keeps its count, its index and its position, and draws
	# nothing at all.
	out += _detail_rejected(thin_host, [["r", 12.0, 22.0, 0.0, 2.0, Color("445566")]],
		"shape", "a detail row with no area")

	# 2. seat — outside every part, which makes it a sight and not a surface feature.
	out += _detail_rejected(thin_host, [["r", 60.0, 22.0, 4.0, 2.0, Color("445566")]],
		"seat", "a detail row drawn on nothing")

	# 3. proud — seated inside a host DEEPER than it, so the depth buffer hides it.
	# 3.30 art units at rank 5 against the knife's part 4 at 3.42.
	out += _detail_rejected(deep_host, [["r", 12.0, 22.0, 6.0, 2.0, Color("445566")]],
		"proud", "a detail row sunk inside the part it is drawn on")

	# 4. quiet — laid FLUSH with the top edge of the topmost part. Seated, proud, with
	# area — and its later rank inflates it 0.20 units past the host it lies on, so it
	# becomes the top of the weapon and takes the sight line. This is the one that
	# could only ever fire on the inflated boxes; on nominal ones it is unreachable
	# behind `seat`.
	out += _detail_rejected(thin_host, [["r", 12.0, 20.0, 6.0, 2.0, Color("445566")]],
		"quiet", "a detail row that becomes the top of the weapon")
	return out


## One malformed detail row, refused BY THE CLAUSE IT NAMES. Keyed `knife` to match
## the fixture hosts — the first draft passed `{"fixture": rows}` against `{"knife":
## ...}` hosts, so every fixture found no parts at all and was intercepted by `seat`,
## which is the interception this whole shape exists to rule out.
static func _detail_rejected(art: Dictionary, rows: Array, tag: String,
		what: String) -> String:
	var res := detail_rules(art, {"knife": rows})
	var diff := String(res["diff"])
	if diff.is_empty():
		return "%s was honoured; " % what
	if not diff.begins_with(tag):
		return "%s was refused by the wrong clause — [%s] does not open with [%s]; " % [
			what, diff, tag]
	return ""


## THE RANK PIN. Every part of every band ranks at its own place in the paint order.
##
## HONEST ABOUT BEING A PIN: `RANK` is empty, so `part_rank` is the identity and this
## is textually a tautology whose only control is deleting the identity. What it is
## FOR is the day a band becomes conditional — it is the only assertion anywhere that
## says an optional part may not renumber the M1911's slide, and every vertex of every
## weapon rests on that. Exact equality and not `near`: a rank is authored, never
## computed, so there is nothing for a tolerance to absorb.
static func rank_faults() -> Dictionary:
	var bad := ""
	var n := 0
	for key: String in GUNART.keys():
		for i in GUNART._parts(key).size():
			n += 1
			var r: float = GUNART.part_rank(key, i)
			if r != float(i):
				bad += "%s %s ranks %s at position %d; " % [
					key, GUNART.part_id(key, i), _num(r), i]
	return {"diff": bad, "n": n}


## THE WALK IS THE BANDS, AND EVERY PART OF IT IS ADDRESSABLE.
##
## Three claims that close the walk from the side `checks/frame.gd`'s distinct-|x|
## count cannot reach. (1) `_parts()` IS the bands concatenated in order — drop a band
## from `_bands()` and `_parts`, written over it, silently loses those rows while every
## count that derives from `_parts` moves with it. (2) `part_id`'s `out-of-range` arm
## is unreachable, because a fallback that returns a silent wrong answer in the very
## failure messages the address space exists to improve is worse than no address space.
## (3) The read-only identity `checks/frame.gd` records as MEASURED still holds for
## exactly the three weapons with nothing appended — a band inserted BEFORE `art` in
## `_bands()` would change which three, and anything that later sorts or appends would
## then error on 3 of 13 and pass on the other 10.
static func walk_faults() -> Dictionary:
	var bad := ""
	var n := 0
	var frozen: Array = []
	for key: String in GUNART.keys():
		var want: Array = []
		for rows: Array in GUNART._bands(key):
			want.append_array(rows)
		var got: Array = GUNART._parts(key)
		if got.size() != want.size():
			bad += "%s walks %d parts, its bands hold %d; " % [key, got.size(), want.size()]
		else:
			for i in want.size():
				n += 1
				if not is_same(got[i], want[i]):
					bad += "%s walk[%d] is not the row its band holds; " % [key, i]
				if GUNART.part_id(key, i).begins_with("out-of-range"):
					bad += "%s walk[%d] has no address; " % [key, i]
		if got.is_read_only():
			frozen.append(key)
	# The three with no `SIGHTS` row and no `DETAIL` row, in `keys()` order.
	var want_frozen := ["raygun", "thundergun", "knife"]
	if frozen != want_frozen:
		bad += "the read-only walks are %s, not %s; " % [str(frozen), str(want_frozen)]
	return {"diff": bad, "n": n}


## THE ORDINAL-STABILITY PROPERTY, driven through the real `_band_base` against
## censuses the tables do not hold — which is what lets "a band growing moves no
## earlier part" be tested with no detail or attachment row invented.
##
## BOUNDED AT BOTH ENDS. The refusal half alone ("nothing moved") passes perfectly
## against a `_band_base` that always returns zero, which is the shape of a check that
## discriminates nothing — so growing an EARLIER band must move a later base by
## exactly as much.
static func base_faults() -> Dictionary:
	var bad := ""
	var n := 0
	for key: String in GUNART.keys():
		var base := GUNART.band_census(key)
		for k in [1, 2, 5]:
			# REFUSAL: the last band grows and nothing before it moves.
			var later := base.duplicate()
			later[GUNART.B_DETAIL] += k
			for b in [GUNART.B_ART, GUNART.B_SIGHT, GUNART.B_DETAIL]:
				n += 1
				if GUNART._band_base(later, b) != GUNART._band_base(base, b):
					bad += "%s band %d moved on +%d detail; " % [key, b, k]
			# ACCEPTANCE: an earlier band grows and the later base follows exactly.
			var earlier := base.duplicate()
			earlier[GUNART.B_SIGHT] += k
			n += 1
			if GUNART._band_base(earlier, GUNART.B_DETAIL) \
					!= GUNART._band_base(base, GUNART.B_DETAIL) + k:
				bad += "%s detail base did not follow +%d sight; " % [key, k]
			n += 1
			if GUNART._band_base(earlier, GUNART.B_ART) != GUNART._band_base(base, GUNART.B_ART):
				bad += "%s art base moved on +%d sight; " % [key, k]
	return {"diff": bad, "n": n}


## THE CENSUS AND THE HANDOVER, in one claim because they are one fact: the walk is
## these three bands, in this order, and the last one is where anything conditional
## would have to go.
##
## Replaces `checks/frame.gd`'s `parts_total == 119` with its decomposition — 101
## against the ancestor's own summed rows, 18 against `SIGHT_ROWS`, 0 against
## `DETAIL_ROWS` — plus two clauses the total could never make. Every band may name
## only weapons `ART` declares, because `keys()` returns `ART.keys()` and a weapon that
## existed only in a later band would be invisible to `viewmodel._prebuild`, to
## `sweep()` and to eleven loops in this suite, silently. And `B_DETAIL` is last, which
## is what `base_faults()`'s stability rests on.
##
## `detail` is the FOURTH-BAND TRIPWIRE and its detail message is a handover list, not
## a puzzle. It is a live fact about real tables rather than the
## `v.check("...", true, "the other package has not landed")` shape that is invisible
## to the floor and reads as coverage.
static func band_faults(anc: Dictionary) -> Dictionary:
	var bad := ""
	var got := PackedInt32Array([0, 0, 0])
	var total := 0
	for key: String in GUNART.keys():
		var c := GUNART.band_census(key)
		if c.size() != got.size():
			bad += "%s walks %d bands, this project declares %d; " % [key, c.size(), got.size()]
			continue
		for b in c.size():
			got[b] += c[b]
		total += GUNART._parts(key).size()
	var anc_rows := 0
	for key: String in anc:
		anc_rows += (anc[key] as Array).size()
	var want := PackedInt32Array([anc_rows, SIGHT_ROWS, DETAIL_ROWS])
	if got != want:
		bad += "census %s against %s; " % [str(got), str(want)]
	if anc_rows != ART_ROWS:
		bad += "the ancestor draws %d parts, ART_ROWS says %d; " % [anc_rows, ART_ROWS]
	if total != anc_rows + SIGHT_ROWS + DETAIL_ROWS:
		bad += "the walk holds %d parts, the bands hold %d; " % [
			total, anc_rows + SIGHT_ROWS + DETAIL_ROWS]
	# A weapon that exists only in a band above `ART` is invisible to `GUNART.keys()`.
	#
	# BOUNDED BY THE LITERAL, NOT BY `BAND_NAMES`, and that is the whole point. This
	# loop used to run `[ART, SIGHTS, DETAIL][b]` over `BAND_NAMES.size()`, ABOVE the
	# fourth-band tripwire below — so adding a band indexed out of range, `band_faults`
	# aborted to its type default, `frame.gd`'s `bands["diff"]` then errored, and checks
	# 2b/3/4a/4b/4c/5 never ran at all. MEASURED by applying this package's own handover
	# diff: 797 passed became 790 with the only diagnostic being the floor check saying a
	# check function probably errored out. The tripwire's handover list was unreachable
	# at exactly the moment it existed to be read.
	var tables: Array[Dictionary] = [GUNART.ART, GUNART.SIGHTS, GUNART.DETAIL]
	for b in tables.size():
		var table: Dictionary = tables[b]
		var band_name: String = (String(GUNART.BAND_NAMES[b])
			if b < GUNART.BAND_NAMES.size() else "band %d" % b)
		for key: String in table:
			if not GUNART.ART.has(key):
				bad += "%s is named by the %s band and not by ART; " % [key, band_name]
	if GUNART.BAND_NAMES.size() != 3 or GUNART.B_DETAIL != GUNART.BAND_NAMES.size() - 1:
		bad += ("the conditional band must be LAST and there must be no fourth without "
			+ "the work: widen viewmodel's `_show` (key, pap) guard and its mesh cache "
			+ "key, make `sweep()` enumerate configurations with a per-configuration "
			+ "readout, key `gunart._sight_cache` on the fitted set, re-argue "
			+ "SHIPPED_MAX_HALF (0.02 art units of headroom on the Thundergun), keep the "
			+ "new band SLOT-ADDRESSED rather than dense, and record the departure — "
			+ "BO1 Zombies has no player-chosen attachment system; ")
	return {"diff": bad, "n": total}


## A PAINTED HIGHLIGHT IS PROUD OF EVERYTHING IT IS PAINTED ON (`gunart.gd:757-765`),
## and until now nothing said so: the depth checks assert that no two parts SHARE a
## depth, never that the one drawn on top is the deeper.
##
## MEASURED 2026-08-03 through the real `_part_box` and `part_half`: 27 parts across
## the roster are drawn strictly inside an earlier part's box, all 27 come out deeper
## than every host, and the margin histogram is 0.1400 x15, 0.2800 x2, 0.3500 x1,
## 0.7000 x1, 0.8400 x2, 0.9800 x2, 1.2200 x1, 1.3600 x1, 1.5000 x2 — fifteen of them
## separated by exactly one `LAYER` step, which is `LAYER` doing the only job it has
## left since the `DEPTH` table landed.
##
## THIS IS THE RULE THE DETAIL BAND MUST OBEY, asserted on the roster that already
## obeys it, before there is any detail geometry to get it wrong — and it is the
## roster-side control on `detail_rules()`'s `proud` clause, which no fixture can reach
## (see `detail_self_test()`).
static func nest_faults() -> Dictionary:
	var bad := ""
	var n := 0
	for key: String in GUNART.keys():
		var parts: Array = GUNART._parts(key)
		for j in parts.size():
			var mine: Rect2 = GUNART._part_box(parts[j], 0.0)
			var worst := -1.0
			var host := -1
			for i in j:
				if not GUNART._part_box(parts[i], 0.0).encloses(mine):
					continue
				var h: float = GUNART.part_half(key, i)
				if h > worst:
					worst = h
					host = i
			if host < 0:
				continue
			n += 1
			var deep: float = GUNART.part_half(key, j)
			if deep <= worst:
				bad += "%s %s at %s is inside %s at %s; " % [key, GUNART.part_id(key, j),
					_num(deep / GUNART.UNIT), GUNART.part_id(key, host),
					_num(worst / GUNART.UNIT)]
	return {"diff": bad, "n": n}


## EVERY PART'S FOOTPRINT IN THE COMMITTED MESH IS ITS OWN ART BOX GROWN BY ITS OWN
## RANK — the PROUD half of the ordinal, which nothing here could see before.
##
## `checks/frame.gd`'s lead assertion compares the distinct |x| of the committed mesh
## against the distinct |x| of the corner walk, which is the `LAYER` half alone: a rank
## that drifted between `part_half` and `_part_poly` leaves both |x| sets identical and
## passes it. So each part's |x| — unique per weapon, which the depth-distinctness
## check buys — is used to pull its vertices back out of the `ArrayMesh`, mapped to art
## space through the inverse of `_to_local`, and put against the box its own rank
## inflates. Shares `_part_box` with the builder for the reason the depth checks share
## `part_half`: this is what notices if one of them stops calling it.
##
## MEASURED: 119 parts matched, worst absolute delta 3.8e-6 art units — the mesh is
## float32 and `part_half` is float64, so the round trip is not the identity — against
## a `PROUD` step of 0.04, four orders of margin. `is_equal_approx` and not `==` for
## exactly that reason. MEASURED discrimination: a +1 rank shift moves the box of all
## 119 parts, so there is no part this cannot see.
##
## The gloves are skipped by the `want.has(q)` guard: they are pinned at `HAND_HALF`
## and `HAND_HALF + LAYER`, ride neither ramp, and nothing on the roster reaches 5.0.
static func footprint_faults() -> Dictionary:
	var bad := ""
	var n := 0
	for key: String in GUNART.keys():
		var parts: Array = GUNART._parts(key)
		var grip: Vector2 = GUNART.GRIP[key]
		var want := {}
		for i in parts.size():
			var b: Rect2 = GUNART._part_box(parts[i], GUNART.part_rank(key, i) * GUNART.PROUD)
			want[snappedf(GUNART.part_half(key, i) / GUNART.UNIT, 0.0001)] = b
		for m: ArrayMesh in [GUNART.build_body(key, false), GUNART.build_slide(key, false)]:
			if m == null:
				continue
			var got := {}
			var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for p: Vector3 in vs:
				var q := snappedf(absf(p.x) / GUNART.UNIT, 0.0001)
				if not want.has(q):
					continue
				var a := Vector2(grip.x + p.z / GUNART.UNIT, grip.y - p.y / GUNART.UNIT)
				var seen: Rect2 = got.get(q, Rect2(a, Vector2.ZERO))
				got[q] = seen.expand(a)
			for q: float in got:
				n += 1
				var b: Rect2 = want[q]
				var r: Rect2 = got[q]
				if not b.is_equal_approx(r):
					bad += "%s at |x| %s spans %s, its rank inflates %s; " % [
						key, _num(q), str(r), str(b)]
	return {"diff": bad, "n": n}
