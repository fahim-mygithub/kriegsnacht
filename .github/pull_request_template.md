## What changed, and why it is what it is

<!-- The why, not the what. A diff already says what. CLAUDE.md: a departure
     from the ancestor that is not recorded as a deliberate departure is wrong
     even when the departure is right. -->

## Gates

CI runs `--verify` for you. It **cannot** run the frame gate — a GitHub runner
has no rendering device, and the capture half hangs rather than fails under
`--headless`. So that one is on the human:

- [ ] `--headless --path . --verify` green locally (CI re-checks this)
- [ ] `pwsh tools/frames.ps1` green, **or** N/A — nothing here can reach a pixel
- [ ] Touched `docs/`? It should almost always be **no** — see CONTRIBUTING.md

## Assertions

<!-- Delete if this PR adds none. -->

- [ ] Every new assertion has a **control**: I broke the thing it is named for,
      ran the suite, confirmed *that specific check* failed, and restored it
- [ ] Expected values have **provenance** — an ancestor line, a BO1 source, or a
      stated decision with its reasoning. Not a snapshot of what the code did today
- [ ] Expectation and subject are **not the same source** (the check can fail)
- [ ] `ASSERTION_FLOOR` raised additively by what I added

## Anything you are unsure of

<!-- CLAUDE.md treats an empty "unsure" section as a red flag. It usually is. -->
