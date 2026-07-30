# Agent workflow audit — Milestones 2, 3 and 4

**Date:** 2026-07-30. **Scope:** the multi-agent development of M2–M4, roughly 30
agents across six workflow runs, ending at 483 assertions and a live build.
**Audience:** whoever writes the next brief, and the agents who answer it.

This is not a list of things that went wrong. It is a list of things that went wrong
**in a way that would repeat**, plus the specific counter-measure for each. Where a
defect was a one-off it is omitted; where it recurred across packages it is here even
if it was individually small.

The headline number is the useful one: **six defects reached a "green" suite and were
caught by something other than the suite** — by a reviewer running a control, by
someone opening a PNG, or by a tool built for an unrelated purpose. That ratio is the
thing to improve.

---

## 1. The dominant failure: tests that cannot fail

Every one of these was written by a competent agent, reviewed, and passing.

| Test | What it actually discriminated | Found by |
|---|---|---|
| Projectile tunnelling | "a wall test exists" vs "no wall test" — **passed with the sweep deleted** | reviewer ran the control |
| 8-direction atlas | the PNG on disk, not the code path — **passed with `have_atlas := false`** | reviewer ran the control |
| Trap `axis` orientation | nothing; the sweep is a point-in-rect that cannot see rotation — **passed with the gate transposed into a wall** | reviewer ran the control |
| Stamin-Up / Mule Kick | recomputed the implementation's own expression — **passed with the multiplier deleted** | reviewer ran the control |
| Monkey Bomb lure | a getter against its own setter — **passed while the throwable was completely inert** | reviewer read the contract |
| Shell reload (M2) | a 4 s window against a 3.4 s reload; the magazine was always full | orchestrator, by arithmetic |

**The counter-measure is not "write better tests". It is mechanical:**

> **Every assertion ships with a control.** Break the thing the assertion is named
> for, run the suite, confirm *that specific check* fails, restore. If it does not
> fail, the assertion is decoration and must be rewritten or deleted.

This is cheap — a sabotage-and-restore is two edits and one run — and it is the single
highest-yield change available. Four of the six above were caught only because *one*
reviewer adopted it unprompted; the other reviewers who did not adopt it shipped their
packages with untested assertions.

**Corollary — assert through the real path.** Every failure above shares one shape:
the test reached around the code under test. It read the disk instead of the loader,
recomputed the formula instead of driving the function, queried the getter instead of
the consumer. A test that does not call what the game calls is testing a copy.

---

## 2. Tests that encode the bug they sit next to

The Thundergun pair asserted that the cone **should** score a headshot — the exact
defect. Both were detailed, well-commented, and one carried a paragraph explaining
that losing it would "silently downgrade every cone kill from 100 points to 60". 60 is
the correct payout. The tests then failed when the bug was fixed, and the natural
reading of a red suite is "the change broke something".

Same shape, twice more: the downed-state check asserted the counter-based gate that
*was* the bug, and the interaction check asserted `is_blocked()` after its meaning had
silently widened from "masonry" to "masonry or prop or machine".

> **When writing an assertion, state where the expected value comes from** — an
> ancestor line, a canon source, or an explicit "this is our decision and here is
> why". A number with no provenance is a snapshot, and a snapshot endorses whatever
> the code did on the day it was written.
>
> **When an assertion fails after a fix, the assertion is a suspect too.** "It failed
> because it was right before" is a legitimate finding and must be reported rather
> than worked around.

---

## 3. Entire test files that never ran

`downed.gd` (14 assertions) and `economy.gd` (25) were written, committed,
parse-clean — and called by nothing. Thirty-nine assertions existing only as text
while the suite reported green. A third (`shell.gd`) and a fourth (`enemies.gd`, whose
registration was pulled to work around a parse error and never restored) followed.

The `ASSERTION_FLOOR` guard added after the first incident **could not see this**: a
floor detects a total that shrank, and these totals never counted. That is now closed
by a directory-driven audit in `verify.gd` (`_registered()`), which has since caught
three real orphans.

**The remaining hole, which nothing catches yet:** a check that passes as a *soft
skip* — `v.check("...", true, "the other package has not landed")` — is invisible to
the floor, invisible to the registry audit, and reads as coverage. The Monkey Bomb
check did this for an entire wave.

> **A skip must fail, or be counted separately. Never pass.** If a check cannot run,
> the suite should say so in a way that shows up in the total.

---

## 4. Visual verification is the weakest surface in the project

**Two milestones shipped a near-black frame that every assertion passed** — the
lighting pass and the viewmodel, both from the same root cause (a display-space value
used as a linear one). A third defect, the zombie rim at **3.4× the brightness of the
body it outlined** (mean 146/255 against 42), was found by an agent opening a PNG and
looking. No assertion in the project could have caught any of them.

The reason is structural, and worth stating plainly: **the only pixel-level checks in
the suite read source textures** — the vignette gradient, sprite-sheet geometry —
**and nothing asserts anything about a rendered frame.** `--shot` writes a PNG and
stops. Whether that PNG is correct is a human judgement made once, by whoever
happened to look, with no baseline and no record.

Secondary problems that made looking expensive:

- `--shot` **hangs forever under `--headless`** (no rendering device, so
  `await RenderingServer.frame_post_draw` never returns). Cost one agent a 180 s
  timeout before it tried windowed. Now documented in the README.
- **States that need input cannot be photographed at all.** An armed trap needs power,
  1000 points and an F press; ADS needs a held button; the downed state needs a death.
  Each agent that wanted one hand-patched `_tick_shot`, took its frames, and reverted.
  Three did this independently.
- **Frame comparison was ad hoc.** One reviewer montaged PNGs and used a naive
  row-delta metric that reported two atlas rows as near-identical; the metric was
  averaging over a mostly-empty cell. A shared, correct comparison would have saved
  that.

The fix is in §7.

---

## 5. Cross-package contracts drift silently

**The Monkey Bomb shipped completely inert.** One package consumed
`Game.lure_position`; the other published to private statics. Neither was wrong on its
own. `"lure_position" in Game` was false, every zombie fell back to the player, and
the test passed by asserting one half against itself.

**ADS shipped half-done.** The camera zoomed; the weapon never moved, because four
`viewmodel.gd` hunks were reported and never applied.

**`Cause.BLAST` was unreachable in the shipped game.** Every splash call site passed
neither cause nor direction, so the enum value could only ever be produced by a Nuke.

**Three input actions did not exist**, so ADS and both throwables were dead at runtime
behind a `push_warning` nobody read.

The common factor: **a hunk reported for a file the package does not own is a hunk
that might not land.** Owning-agent reports it, orchestrator applies it, and anything
dropped in that handoff is invisible — the code still compiles and the tests still
pass, because the tests belong to the half that did land.

> **Every cross-package contract needs an assertion that spans BOTH halves**, driven
> from the consumer, not the publisher. "Set the lure, then step a real zombie and
> check where it goes" would have caught this on day one. The version that shipped —
> "set the lure, read the lure back" — could not.
>
> **A reported hunk is not done.** The reporting agent should add a check that fails
> until it lands, so the gap is loud rather than latent.

---

## 6. Orchestration mistakes (mine)

Recorded because they cost more time than any single agent defect.

1. **Running `--verify` while agents were writing.** It loads every script, so any one
   caught mid-edit hangs the run. I diagnosed four phantom hangs this way, twice
   concluding something was broken when the tree fixed itself minutes later.
   **`--verify` is a quiescent-tree tool; parse-gating individual files is the
   concurrent-safe check.**
2. **Resuming an agent whose pipeline had moved on**, which put an implementer back to
   work alongside its own reviewer — two writers on one package. It was handled well
   by the agent, who stopped and asked, but I created the hazard twice.
3. **Sabotage without a guaranteed restore.** My control test appended a parse error to
   a preloaded module; the run hung for 414 s and my restore was the line *after* the
   hanging command. A parse error sat in a file reachable from the main scene for seven
   minutes and blocked another agent. **Restore must be in a `finally`/`try` wrapper
   that runs even when the command dies.**
4. **Orphaned processes.** `timeout` kills the shell wrapper, not Godot. Two orphans
   ran for **6696 s and 3591 s of CPU**, pinning two cores under every measurement
   taken that night.
5. **Stale briefs.** I told one package "nothing in the repo says by how much" when a
   previous wave had already measured and documented it. Briefs must be refreshed
   between waves.
6. **Asserting a gate I had not tested** (warnings-as-errors), then reverting it.
7. **Substituting a convention for a lookup** — I bound the tactical throwable to Q by
   genre convention when the report specified T *and gave the reason*; Q was already
   `swap_weapon` and Godot fires both actions on a shared binding.

---

## 7. What to change, concretely

**Testing**

1. Every assertion ships with a control. Sabotage, run, confirm *that* check fails,
   restore in a wrapper that survives a hang.
2. Assert through the real path — the loader, the consumer, the function the game
   calls. Never recompute the implementation's own expression.
3. Every expected value carries its provenance in a comment.
4. Cross-package contracts get an assertion driven from the consumer.
5. A skip fails or is counted; it never passes.
6. Bound every test at both ends — the refusal *and* the acceptance.

**Visual** (the largest gap; see the harness work landing alongside this document)

7. **Frame statistics assertions, runnable in the suite.** Mean luminance, black-pixel
   fraction, per-region brightness, and brightness *ratios* between named elements.
   Both black-frame bugs and the 3.4× rim would have been caught by a numeric check;
   none needed a human.
8. **Golden frames with tolerance.** The project has already proved byte-identical
   frames are achievable (`--fixed-fps` plus a pinned seed reproduced a PNG exactly
   across a 1000-line refactor). Store references, compare, fail on drift.
9. **A `--shot-setup <scenario>` hook** so states needing input — armed trap, ADS,
   downed, power-on, a round-10 horde — can be photographed deterministically instead
   of hand-patched by each agent that wants one.
10. **A contact-sheet command**: N scenarios × M yaws in one run, for the human pass
    that statistics cannot replace.

**Process**

11. `--verify` only on a quiescent tree.
12. Never resume an agent whose workflow stage has completed.
13. Refresh briefs between waves; a stale brief invites an agent to prove you wrong at
    its own expense.
14. Kill orphaned Godot processes after any `timeout`-killed run.

---

## 8. What worked, and should be kept

Not everything needs changing. These were decisive:

- **Reviewers with write access who ran controls.** Four of the six undetectable
  defects were caught this way. The review stage earned its cost several times over;
  the implement stage alone would have shipped all of them.
- **File-disjoint ownership.** The one time it broke down (two writers on
  `mystery_box.gd`) was caused by orchestration, not by the model, and the agent
  handled it correctly by stopping and asking rather than clobbering.
- **"Verify, do not trust" in every brief.** Agents overturned the plan **six times**
  with evidence — including twice against claims I had personally written. The
  gap-analysis document was materially wrong about four already-fixed defects and two
  design prescriptions, and briefs that invited correction got it.
- **Reports that paste real command output.** The rule "if you did not run it, say so"
  surfaced several claims that would otherwise have been taken on trust.
- **Recording deliberate departures.** The mystery box's draw-at-purchase is better
  than the ancestor's frame-dependent version; without the note it would read as an
  accidental divergence to the next reader.
