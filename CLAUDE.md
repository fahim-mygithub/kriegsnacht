# Working in this repository

A Godot 4.7 port of `kriegsnacht.html`, a single-file browser raycaster CoD-Zombies
demake, targeting the web. Four milestones are complete; the assertion suite is the
project's memory and `notes/` is its reasoning.

Everything below was learned the expensive way. `notes/analysis/2026-07-30-agent-workflow-audit.md`
has the incidents; this file has the rules that came out of them.

---

## The two sources, and they are not the same thing

- **The reference** is Call of Duty: Zombies, Black Ops 1 era. The project exists to
  get closer to it. Where it and the ancestor disagree, **the reference wins**.
- **The ancestor** is `kriegsnacht.html` in the repo root. It is **evidence, not
  authority** — often right about intent, occasionally wrong, and it contains at least
  one branch of outright dead code.

Cite line numbers. They drift: several citations in `notes/` were off by two to
thirty lines and were corrected by agents who checked. Check yours — and once you have
inserted lines into a file, check the citations pointing **into** it from everywhere
else, not only the ones you wrote. One package shifted `frame.gd` by +5 and `verify.gd`
by +23 and broke twelve live-code citations in five files it never opened, while
reporting that it had audited its own. One exception, and it bites: a **measured
runtime output** — the line a parse gate aborts at, say — names the file as it stands
and must not be shifted like a content reference. Mapping one mechanically is how the
audit itself introduced an error.

**A departure from the ancestor that is not recorded as a deliberate departure is
wrong even when the departure is right.** The mystery box drawing its result at
purchase instead of from the spin's frame count is better than the ancestor; without
its comment it reads as an accident.

---

## Hard constraints

1. **`gl_compatibility` is hard-locked** (web target, pinned per-platform in
   `project.godot`). Dead at runtime: `Decal`, volumetric fog, SSR/SSIL/SDFGI/VoxelGI,
   `CompositorEffect`, every AA except MSAA 3D, particle trails/sub-emitters/
   `emit_particle()`, `INSTANCE_CUSTOM` on a plain `MeshInstance3D`, and **every
   `AudioEffect`** — no reverb, no filters; bake variants instead. Working: SSAO,
   colour LUTs, `GPUParticles3D`, `SCREEN_TEXTURE`, `DEPTH_TEXTURE`, glow.
2. **Two GDScript diagnostics are hard parse errors** regardless of warning settings:
   type inference through a Variant (`var d := dict.get(k, 0.0)` fails — annotate
   `var d: float = ...`, and type loop variables `for x: Dictionary in arr:`), and a
   `const` that is not a constant *expression* (`PackedInt32Array([...])` is a call).
   General warnings are **not** errors here and cannot be made so from a headless run;
   type explicitly because those two are real, not because a linter is watching.
3. **A parse error in any script reachable from the main scene hangs Godot.** It does
   eventually exit 1, but it takes ~414 s against a healthy run's ~5 s.
4. **One writer per node.** The camera chain is
   `Player(yaw) → Head(pitch) → RecoilPivot(recoil/shake) → Camera3D(bob) → ViewmodelRoot`.
5. **`Rng` is the single RNG authority.** Gameplay draws use `SPAWN/BOX/DROPS/ROUNDS/AI`;
   cosmetic draws use `VISUAL`. A cosmetic roll that advances a gameplay stream breaks
   seed reproducibility, which the seeded-run layer depends on. No bare `randf()`.
   (Known outstanding violation: weapon spread draws from `VISUAL`. Left alone because
   changing it moves every sim baseline — but do not add a second.)
6. **Colour space.** Canvas-authored values are **display** space; the pipeline is
   linear → FILMIC → sRGB encode. This has shipped two black frames. The rule is not
   "never linearise", it is **know which space the pipeline expects**: an opaque
   unshaded surface *replaces* the pixel and must not be converted; a `BLEND_ADD`
   surface *is* a light contribution and must be.
7. **`scripts/world/los.gd` is the only line-of-sight test.** Four callers must agree;
   when they disagree it is invisible until something dies through a wall. Do not
   write a fifth.
8. **`core.autocrlf` is true and there is no `.gitattributes`.** Tracked text is LF in
   the index and CRLF in a fresh working copy; `kriegsnacht.html` is LF here only
   because it predates the setting, and `git ls-files --eol` shows it disagreeing with
   every `.gd` beside it. So **never pin the sha of raw file bytes** — a byte pin is
   green in this checkout and red on every clone, worktree and CI run, and
   `tools/build.ps1` gates the export on `--verify`, so it breaks the build for
   everyone but you. Fold `\r\n` to `\n` first, as `tools/gen/extract.js:436` already
   does. MEASURED: 139 769 bytes here against 143 245 from `git checkout-index`.

---

## Invocations, and their opposite footguns

```
--headless --path . --verify      # the suite (~5 s healthy). NO `--` separator.
--headless --path . --sim         # balance sim -> notes/balance/
--path . --shot out.png [yaw]     # ONE FRAME. NEVER with --headless.
--path . --shot out.png --shot-setup <name>   # ...of a named world state
--path . --fixed-fps 60 --frames <name>       # capture + measure ONE scenario. NEVER --headless.
--headless --path . --frames-list             # the scenario names, one per line
--headless --path . --frames-report           # THE GATE. Compares, prints, exits non-zero.
--headless --path . --check-only --script <file>    # parse gate
```

- **`-- --verify` silently does nothing.** The flag lands in
  `get_cmdline_user_args()`, `main.gd` never sees it, and the game sits on the title
  screen looking exactly like a hang — leaving a Godot process spinning after you kill
  the shell. Two such orphans were found at 6696 s and 3591 s of CPU.
- **`--shot` under `--headless` hangs forever** — no rendering device, so
  `await RenderingServer.frame_post_draw` never returns. Windowed: 3.6 s.
- **The parse gate does not register autoloads**, so `Identifier not found: Game /
  Sfx / Rng / Settings` is a false positive — and it **aborts at the first error**, so
  everything below that line is unchecked. A clean gate on a long file means little.
- **`timeout` kills the shell, not Godot.** Check for orphans after any killed run.

---

## Sizing the work

The rules below are expensive. Applying them at full strength to a small fix has cost
this project hours for no visible change, and that is a defect in the process rather
than diligence.

**Say the price before paying it.** A change that meets the assertion standard in this
file — control, provenance, bounded at both ends — routinely costs several times the
fix it protects. That is the right trade for a subsystem the game depends on and the
wrong one for a comment. When the two readings differ by an order of magnitude, state
both and let the human pick. Choosing silently is how one hollow assertion became
~3.3 hours and 3.2M agent tokens against a suite that ended five assertions better and
a game that did not change at all.

**Prove the blocker before removing it.** Work justified by "X blocks Y" needs a
demonstration that removing X unblocks Y, and that demonstration is nearly always
cheap. `ANCESTOR_PARTS` was named as what blocked the weapon-model revisions. It was
replaced in full, correctly, and the models were still blocked — the actual barrier is
`ART`'s cardinality rule and always was. Five minutes of testing up front would have
replaced the whole package with a sentence.

**Count the cleanup.** A package that introduces a build break, a self-comparing
assertion and twelve stale citations spends its second half repairing its first. When
much of the effort is going into damage the work itself caused, stop and re-scope
instead of pressing on.

**Scale the machinery to the target.** Twelve agents on one assertion found two real
defects and manufactured three. More reviewers stops buying correctness once the
reviewers outnumber the thing reviewed.

---

## Testing: the rules that matter

The suite is ~483 assertions and it has been green while six real defects shipped.
These exist to close that gap.

### Every assertion ships with a control

Break the thing the assertion is named for, run the suite, confirm **that specific
check** fails, restore. If it does not fail, it is decoration.

This is not theoretical. Passing tests that discriminated nothing: a projectile
tunnelling test that passed with the sweep deleted; an atlas test that passed with the
atlas disabled; a trap orientation test that passed with the gate rotated into a wall;
perk tests that recomputed the implementation's own expression; a Monkey Bomb test
that passed while the throwable was completely inert.

**Restore in a wrapper that runs even if the command dies.** A sabotage left in a file
reachable from the main scene hangs Godot for everyone — that happened, for seven
minutes, and blocked another agent.

### Assert through the real path

Every one of those failures reached *around* the code under test — read the disk
instead of the loader, recomputed the formula instead of driving the function, queried
the getter instead of the consumer. **A test that does not call what the game calls is
testing a copy.**

### Both sides of a comparison may not be one source

An assertion whose expectation and whose subject come from the same constant cannot
fail. A check named for the iron sights passed `GUNART.SIGHTS` in as the expectation
against a walk that already *was* `ART + SIGHTS`, so every edit moved both sides
together — a destroyed M16 front tower, reversed RPK sight rows and a magenta M14
front post each passed the whole 789-assertion suite. Ask of every check where its
expected value comes from, and whether the edit you are guarding against moves that too.

The same shape hides in a check *named* for a structure that *implements* a scalar.
`ANCESTOR_PARTS` compared thirteen integers under a name claiming part-for-part
fidelity, so it saw a part added or removed and nothing else: blind to 406 numeric
fields, 101 colours and every reordering — and a reorder is not cosmetic, because
`SLIDE` indexes `ART` positionally and so it moves which part reciprocates.

### Provenance, not snapshots

State where an expected value comes from: an ancestor line, a canon source, or an
explicit "this is our decision, and here is why". A number with no provenance endorses
whatever the code did the day it was written — which is how two assertions came to
demand that the Thundergun score a headshot it should never have scored.

**If an assertion fails right after a fix, the assertion is a suspect too.** "It failed
because it was right before" is a finding; report it rather than working around it.

### A skip must never pass

`v.check("...", true, "the other package has not landed")` is invisible to both the
assertion floor and the registry audit, and reads as coverage. One such check passed
for a whole wave while testing nothing.

### Bound tests at both ends

A check that only asserts the refusal passes equally well against a subsystem that has
stopped working. Assert the acceptance too. (A 4 s window against a 3.4 s reload
asserted nothing, because the magazine was always full.)

### Cross-package contracts get a consumer-driven assertion

"Set the lure, then step a real zombie and see where it goes" catches an inert
throwable. "Set the lure, read the lure back" does not.

---

## Visual verification

**This was the weakest surface in the project.** Two milestones shipped a near-black
frame that every assertion passed, and a zombie rim at 3.4× the brightness of the body
it outlined was found only because someone opened a PNG. There is now a gate.

```
pwsh tools/frames.ps1                   # capture every scenario, measure, compare, exit non-zero on drift
pwsh tools/frames.ps1 -Only spawn,horde # iterate on one
pwsh tools/frames.ps1 -Bless            # adopt this run as the new reference
pwsh tools/frames.ps1 -Spread 5         # re-measure run-to-run variation
```

`tools/build.ps1` runs it before every export; `-SkipFrames` opts out and is a
*separate* admission from `-SkipVerify`.

- **The gate is a windowed pass and `--verify` cannot do any of it.** Headless has no
  rendering device. `scripts/dev/checks/frame.gd` is the suite-side half and covers
  only what needs no frame: the statistics maths, the tolerance arithmetic, the
  scenario registry, and the golden file having a blessed row and a reference image
  for every scenario. It renders nothing and says so.
- **The gate is committed NUMBERS, not images** — `notes/perf/frames/golden.json`,
  which is diffable and survives a driver change. `notes/perf/frames/ref/*.png` are
  written for the human pass, which statistics do not replace.
- **`--shot-setup <name>`** puts the world into a named state before the shutter:
  `spawn, power_off, power, trap_armed, ads, downed, horde, raygun, flash_hip,
  flash_ads`
  (`scripts/dev/shot_setup.gd`). Three agents hand-patched `_tick_shot` for this
  before it existed. `--frames <name>` is the same capture plus the measurements.
- **`--shot` and actually look at the image** for anything the scenarios do not
  cover. "Rendered a frame" is not a check.
- **Prefer a RATIO to an absolute.** Absolute brightness drifts with every tuning
  pass, and a gate with a maintenance tax gets deleted; both defects that shipped
  were relational. `golden.json`'s `relations` block is the half that survives a
  retune, and each rule carries its own provenance.
- **A frame comparison metric must be checked before it is trusted.** One reviewer's
  naive row-delta reported two distinct atlas rows as near-identical because it
  averaged over a mostly-empty cell — and in this package `rim_mean / body_mean`
  turned out to be *non-monotone*: with the rim switched off completely it reads
  0.480 against the shipped 0.395, so it can only bound the defect from above.
  Sweep the constant, tabulate, and only then decide what the number means.
- **Luminance is linear**, decoded with the sRGB EOTF and weighted Rec.709. The frame
  arrives sRGB-encoded and a mean over encoded bytes is not a mean over light — which
  is the same confusion that shipped both black frames. See
  `notes/perf/frames/README.md`.

---

## Working alongside other agents

- **Stay inside your owned files.** For anything else, report an exact find/replace
  hunk with enough context to be unambiguous.
- **A reported hunk is not done.** Add a check that fails until it lands, or it will
  be dropped silently — ADS shipped with its camera half and not its weapon half
  exactly this way.
- **Never clobber a concurrent edit.** If a file changes under you, stop and ask. The
  one agent that did this saved a package.
- **`--verify` is a quiescent-tree tool.** It loads every script; any one caught
  mid-write hangs the run and you will spend twenty minutes diagnosing a phantom that
  fixes itself. Parse-gate individual files instead while others are working.
- **Do not edit `project.godot` or `verify.gd`'s registration lines** — report them.
  And **never open the project in the editor to make a change**: an editor pass
  rewrites `project.godot`, stripping every comment (32 → 7 once) and silently
  dropping the explicit `rendering_method.web` pin.
- **`ASSERTION_FLOOR` is contended.** Raise it *additively* by what you added while
  work is in flight; reconcile to the real total only at an integration point.

---

## Report format

Your final message is the return value. No preamble.

1. What changed, file by file, and **why each change is what it is**.
2. Every claim in your brief you **checked**, and the verdict, with line numbers.
3. Anything in the brief that was **wrong**, with evidence. Briefs on this project have
   been overturned six times; this section is expected to have content.
4. Exact hunks for files you do not own.
5. **Commands you ran and their real output.** Paste actual counts. If you did not run
   something, say so — do not imply you did.
6. What you did **not** do, and what you are **unsure** of. An empty section here is
   itself a red flag.

---

## House style

Comment the **why** — the constraint, the measurement, the ancestor line, the bug the
line prevents. A comment restating the code is noise. Read neighbouring files first;
this codebase has a voice and it is worth matching.
