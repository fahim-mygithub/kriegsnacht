# The rendered-frame gate

`--verify` was 537 assertions when this gate was written (580 today, this package
included). Every one of them was green while **two milestones shipped a near-black
frame**, a zombie rim at 3.4x the brightness of the body it outlined was found
only because somebody opened a PNG, and **a muzzle flash shipped as a flat yellow
square 92% of the screen tall at the sights** — reported by a player, not by the
suite, because nothing in the gate had ever photographed a flash
(`notes/analysis/2026-07-30-agent-workflow-audit.md` §4). Nothing in the suite
looked at a rendered frame; the only pixel-level checks read *source textures*.

This directory is what closed that. It holds the committed numbers the gate
compares against, and the reference images for the human pass the numbers cannot
replace.

---

## Running it

```
pwsh tools/frames.ps1                      # capture, compare, exit non-zero on drift
pwsh tools/frames.ps1 -Only spawn,horde    # iterate on one or two
pwsh tools/frames.ps1 -Bless               # adopt this run as the new reference
pwsh tools/frames.ps1 -Spread 5            # re-measure run-to-run variation
```

`tools/build.ps1` runs it before every export. `-SkipFrames` opts out, and it is
a *separate* admission from `-SkipVerify` on purpose: they check disjoint things.

**The capture is windowed and the report is headless, and they must not be
swapped.** `--frames` awaits `RenderingServer.frame_post_draw`, which under
`--headless` never returns — no rendering device — so the process hangs forever
instead of failing. `--frames-report` renders nothing and reads JSON.

**A machine that cannot open a window fails the gate.** It does not skip it. A
visual check that quietly no-ops is worse than no check, because the build then
claims something it never ran.

Each scenario is its own Godot process. There is no supported way to reset the
scene between scenarios inside one run — `reload_current_scene()` needs a driver
that survives the reload, which means an autoload, which means editing
`project.godot` — and a pass where scenario N inherits scenario N-1's opened
doors, thrown generator and downed player is exactly the non-determinism this
gate exists to detect.

---

## What is in here

| Path | Committed | What it is |
|---|---|---|
| `golden.json` | yes | **the gate.** Per-scenario statistics, the tolerance block and the relation rules |
| `ref/*.png` | yes | the reference images, for the human pass |
| `current/*` | no | this run's output. Overwritten every run |

**The gate is the numbers, not the images**, and that is a deliberate departure
from the audit's own §7.8 ("store references, compare, fail on drift"):

- A pixel-exact comparison fails on things that are not defects. Frames on this
  machine are byte-identical across runs today (measured — see below); they will
  not be across a driver update, a different GPU, or the resolution change that
  `window/size/viewport_width` is one edit away from. A gate that cries wolf on a
  driver update is a gate somebody disables.
- A JSON of statistics is **reviewable**. `mean 0.0067 -> 0.0009` in a pull
  request is a finding; a changed PNG blob is a request to go and look.
- This repo already ships a 38 MB wasm. Eight 1280x720 PNGs per bless is 3 MB of
  history each time, for a comparison the numbers already make.

The reference PNGs are still written and still committed, because statistics
cannot replace a person looking — the 3.4x rim was found that way. They are
evidence for that pass, not the gate.

`current/` is transient and should be ignored by git; see the `.gitignore` line
reported with this package.

---

## The colour space, because it is the whole subject

The frame comes back **sRGB-encoded** — the pipeline is linear -> FILMIC ->
sRGB encode, and `Image.get_data()` returns those stored bytes with no transfer
function applied. So a byte of 128 is a *display code value*, not half the light.

**Every luminance in the gate is linear relative luminance in [0,1]**: each
channel decoded with the sRGB EOTF (IEC 61966-2-1) and combined with the Rec.709
weights. The two defects this exists to catch are both statements about *light*,
and a mean over encoded bytes is not a mean over light. On a scene this dark the
difference is not cosmetic — the encode lifts the bottom of the range hard, which
is exactly where every one of these bugs lived.

Two consequences:

- **The numbers are small.** A playable frame of this game means about `0.007`
  linear. Every row also carries `code`, the display value that mean re-encodes
  to, so it can be read against the "146/255 against 42" in the M4 review.
- **Ratios are linear ratios** and are therefore larger than the display-space
  ratios in that review. The 0.62 rim measured 146 vs 42 in display code, a ratio
  of 3.48; the same pixels in linear light are 0.2747 vs 0.0219, a ratio of 12.5.
  Both describe the same defect.

---

## Where the tolerances came from

**Step 1 — measure the noise.** `pwsh tools/frames.ps1 -Spread 5`, 40 windowed
captures, 2026-07-30, NVIDIA RTX 5090 / driver 591.86, Godot 4.7.stable:

```
== worst relative spread across every statistic: 0.000000% ==
```

Zero. Not "small" — every statistic of every scenario was **bit-identical across
five runs**, including the region grid and every probe. Re-measured 2026-07-31
after the silhouette probes landed, `-Spread 4 -Only spawn,ads`, and it is still
`0.000000%` with `gun_px`, `sight_top_over_centre` and `gun_cx_over_centre` in the
sample.

> **The next sentence used to read "three plain `--shot` captures were
> byte-identical as PNGs too, with and without `--fixed-fps`." That was true of
> the three it tested and false as a general claim, and a design leaned on it.**
> All eight, measured 2026-07-31 — bare against `--fixed-fps 60`:
>
> | scenario | identical? | what moved |
> |---|---|---|
> | `spawn` | **yes** | — |
> | `power_off` | **yes** | — |
> | `horde` | **yes** | — |
> | `trap_armed` | no | frame mean `0.052522 -> 0.053527`; the arc sheet cycles |
> | `downed` | no | `black 0.5053 -> 0.5578`; the eye was still dropping |
> | `ads` | no | `gun_mean 0.02259 -> 0.02515`, +11.3% |
> | `raygun` | no | `bolt_mean 0.18168 -> 0.10343`; the bolt is elsewhere |
> | `power` | no | **byte-identical to `power_off`** |
>
> That last row is the one that mattered. A bare capture of the power-on ceremony
> — the invocation this file and CLAUDE.md both document for the human pass —
> photographed the room three lamps of eight into the wave, with the only lamp in
> frame still at `LAMP_ENERGY_OFF`. The numeric gate and the picture a person
> looks at were not merely different states; for `power` they were opposite ones.
>
> The cause: `settle` was a FRAME COUNT and every state it photographs is timed in
> SECONDS. The runner passes `--fixed-fps 60` so the gate was self-consistent; a
> bare run is uncapped and measured 113–141 fps on this machine, so the same
> frame count bought a third to a half of the game time. See "The settle budget"
> below.
>
> **AFTER, re-measured the same way, 2026-07-31 — and the fix is not total.**
>
> | scenario | identical now? | worst statistic |
> |---|---|---|
> | `spawn`, `power_off`, `horde` | **yes** | — |
> | `ads` | **yes** (was +11.3%) | — |
> | `power` | **yes** (was its own control) | — |
> | `raygun` | no | `bolt_mean` +0.67% |
> | `downed` | no | `p99` +1.36% |
> | `trap_armed` | no | `arc_mean` **-6.41%**, frame mean -3.33% |
>
> The residual is structural. `settle` is a **floor**, and a bare run's `dt` is
> ~1/141 s, so the shutter overshoots it by up to one uncapped frame — 0.0017 s on
> `raygun`, 0.0030 s on `trap_armed`. For a state that has converged that buys
> nothing, which is why `ads` and `power` are now exact; for a bolt in flight and
> an arc sheet that cycles forever it buys a few per cent, and `trap_armed` lands
> outside the gate's own 3% `mean` band. The three that still differ are exactly
> the three whose subject is a **moment** rather than a destination — the same
> three that have no `until` for the same reason. The gate itself always passes
> `--fixed-fps 60` and is unaffected; what this bounds is how much a human's bare
> `--shot` may legitimately differ from `ref/*.png`.

So run-to-run noise does not constrain the tolerance from below at all, and a
tolerance "derived from the measured spread" would be zero — which is the
byte-exact gate this design rejects. The floor has to come from somewhere else:
what the spread measurement *cannot* see, namely a different GPU, a driver
update, or a Godot point release.

**Step 2 — measure the smallest defect the gate must catch,** and set the
tolerance an order below it. Both sabotages, measured:

| sabotage | statistic | shipped | sabotaged | move |
|---|---|---|---|---|
| `LAMP_ENERGY_OFF 2.0 -> 0.34` | `spawn.black` | 0.7224 | 0.9522 | **+31.8%** |
| (the M1 black frame) | `spawn.median` | 0.000498 | 0.000110 | **-77.9%** |
| | `spawn.mean` | 0.006660 | 0.004789 | **-28.1%** |
| `RIM_ENERGY 0.30 -> 0.62` | `horde.probes.rim_over_body` | 0.395 | 1.247 | **+215%** |
| (the M4 rim) | `horde.probes.rim_frac` | 0.00409 | 0.00633 | **+55%** |
| | `horde.mean` | 0.021754 | 0.025854 | **+18.8%** |

The weakest signal any real defect produced is **18.8%**.

**Step 3 — the block that follows.**

| key | abs | rel | why |
|---|---|---|---|
| `mean` (mean/median/p01/p99) | 5e-6 | **3%** | six times below the weakest defect signal. The absolute term is 5e-6 linear, about a fifth of a display code value at the dark end, so a statistic that is legitimately near zero (`ads.median` is 0.000174) is not compared with a 3%-of-nothing window |
| `frac` (black/blown) | 0.002 | 2% | 0.002 is 1843 pixels of 921600. `blown` is exactly 0.0 in five scenarios and 0% of 0 admits nothing at all |
| `region` | 5e-5 | 5% | a sixteenth of a frame is a smaller sample, and the darkest cells sit where 8-bit quantisation is coarsest |
| `probe` | 5e-5 | 5% | `rim_frac` is 0.00409, so this is a 6.2% window on it against a 26% move for the smallest rim change the gate must catch |

If a tolerance ever has to be widened, **re-run `-Spread` first**. A number that
started moving is evidence, not noise.

---

## The settle budget

Two things decide when the shutter fires, and both are in
`scripts/dev/shot_setup.gd`'s registry:

- **`settle`** — **seconds of game time**, accumulated from the real `dt`. The same
  quantity under `--fixed-fps 60` and under a bare `--shot`, which a frame count is
  not. Every budget is an exact multiple of 1/60 s so the frame count under the
  runner is unambiguous, and `checks/frame.gd` asserts that.
- **`until`** — an optional **arrival predicate**, `Callable(main) -> bool`. Where
  present the shutter waits for it as well, and `main.gd` refuses the capture with
  exit code 3 rather than photographing a state the scenario did not reach.

`power`, `ads`, `downed`, `flash_hip` and `flash_ads` have one, because their
names are destinations: "the wave has finished", "the sights are reached", "the
eye is on the floor", "there is a muzzle flash on screen". Each asks the system
that owns the state — `player.ads()`, the lamps' own `light_energy`,
`atmosphere.flash_visible()` — rather than a copy of the constant that drives it,
so raising `ADS_TIME` past the budget moves the shutter instead of cropping the
transition.

`raygun` and `trap_armed` deliberately have none: their subject is a MOMENT in a
continuing animation (a bolt 3.45 m out, an arc sheet that cycles forever), and
0.15 s *is* the specification. `spawn`, `power_off` and `horde` are static — the
three that were byte-identical above.

Controls, run 2026-07-31 on `ads` with the budget cut to 0.05 s, well under
`ADS_TIME` 0.22:

| | fired at | silhouette |
|---|---|---|
| predicate present | 0.2333 s, 14 frames | `x 606..673 y 365..529`, the arrived pose |
| predicate removed | 0.0500 s, 3 frames | the whole frame; a half-raised weapon |
| predicate unsatisfiable | never | `exit 3`, "refusing to photograph a state the scenario did not reach" |

---

## Where the weapon is

Every rule in the file was **photometric** until 2026-07-31, and that is how an ADS
pose with the M1911's whole sight line **66 px above the crosshair** — the player
aiming underneath the weapon — passed the gate without moving a committed number.
`the sights keep the frame` read 0.909 for the defect and 0.909 for the fix.

Two rules now measure the **sight picture**:

- `the sight line sits below the crosshair` — the topmost row of the viewmodel
  silhouette over the frame's centre row. 1.0 is the top of the weapon exactly on
  the aim point; above 1.0 is below it.
- `the sight picture is centred on the aim point` — the same for the horizontal.

The silhouette is located **by difference**, against the same instant with the
viewmodel hidden (`main.gd::_bare_frame`, `frame_stats.changed_box`) — the
technique `viewmodel.gd` used to derive `ADS_SIGHT_CLEAR` in the first place, and
not a colour mask, because a mask tuned to the M1911's blue-grey slide cannot
tabulate the other twelve weapons. In the ADS rect a brightness mask is worse than
useless: `gun_lit_frac` is 0.99 there, so the topmost lit row is the top of the
rect.

**The metric was checked before it was trusted**, as CLAUDE.md requires. With the
hide patched out — the second draw taken with the viewmodel still visible — the box
comes back `x -1..-1 y -1..-1 (0 px)` at a threshold of 1 as well as at the shipped
3, on both scenarios. The noise floor is exactly nothing.

Measured, by re-running each pose:

| ADS pose | silhouette top | rule reads | verdict |
|---|---|---|---|
| shipped defect, no sight compensation at all | row 294 | **0.81667** | rejected |
| `ADS_SIGHT_CLEAR` 0, `ADS_LEVEL` 0 | row 357 | **0.99167** | rejected |
| **shipped, `ADS_SIGHT_CLEAR` 1** | row 365 | **1.01389** | ok |
| `ADS_CENTRE` 0.5 (lateral control) | row 437 | 1.21389 / cx **1.17266** | rejected |

Row 294 reproduces `viewmodel.gd`'s own record of the shipped defect — "row 294,
66 px above the crosshair" — to the pixel. The band's upper end is that file's
sweep, which read `clear=2` at 1.02500 as acceptable and `clear=3` at 1.03889 as
"the weapon has detached from the aim point and reads as held low".

`--frames <name>` now **prints the silhouette box in pixels** on the two scenarios
that measure it. `VM_RECT_HIP` and `VM_RECT_ADS` were read off a reference frame
with a pixel ruler; that ruler is now a line in the log.

---

## The relations, and why they are the half worth trusting

Absolute rows have to be re-blessed every time somebody retunes a lamp, and a
gate with a maintenance tax is a gate that gets deleted. The two defects that
actually shipped were both **relational** — a frame far darker than every other
frame, an outline far brighter than the body it outlines — so `golden.json`
carries twenty-four declared ratios with hand-set bands and a `why` on each. They
survive a retune; they do not survive the defect.

Two of them are worth reading before touching the rim:

- **`rim is not brighter than its body`** is bounded **above only**. Measured with
  the rim switched off entirely, `rim_mean / body_mean` is **0.480 — higher than
  the shipped 0.395** — because what is left in the cold mask is a hundred stray
  pixels whose mean has nothing to do with the effect. A lower bound on that
  ratio would be a lower bound on nothing, and a gate built on it would pass a
  build with no rim at all. This was found by running the control, not by
  trusting the metric.
- **`rim covers its silhouette`** (`rim_frac / body_frac`) is the monotone one and
  is what bounds the low end: 0.005197 (rim off), 0.005976 (0.16, which the sweep
  in `zombie.gd` rejected as "the silhouette stops reading at all"), 0.008111
  (0.30, shipped), 0.013446 (0.62, the defect). Its low bound has only ten points
  of headroom over the 0.16 case. **If it ever trips, re-run the sweep — do not
  widen the band.**

---

## The muzzle flash

**Nothing in the gate had ever seen it.** The flash lives `FLASH_TIME` 0.05 s —
three frames at 60 — and `raygun`, the only scenario that fired a real shot,
settles 0.15 s, so `ref/raygun.png` shows the bolt downrange and no flash at all.
The whole effect had no committed number against it until a player said *"the
muzzle flash is an obvious yellow square. It looks jarring especially when you
ads."* That is the same shape of hole that let a sight line ship 64 px high.

### Photographing a 0.05 s effect

A settle budget cannot land inside 0.05 s. The three ways out were: lengthen the
flash, which is tuning the game to fit the harness and was refused; freeze the
clock, which needs a hook in `main.gd`; or **fire the shot at the moment the frame
is wanted**, which is what `flash_hip` and `flash_ads` do. Their `until` predicate
pulls the trigger on the first frame past the settle floor at which the pose the
scenario is named for has arrived, and `_shoot()` emits `fired` synchronously, so
`atmosphere.flash_visible()` is already true when the predicate returns.

The shutter is therefore the **same frame** as the shot, whatever `dt` is — which
makes these two scenarios time-independent in the way `raygun` is not. Fired once
with no flash appearing, the predicate stays false forever and `main.gd` exits 3
with "never arrived", so a `fired` signal nobody listens to fails the capture
instead of photographing an empty barrel.

Each is framed exactly like an existing blessed scenario with no trigger pulled —
`flash_hip` against `spawn`, `flash_ads` against `ads` — so the pair is a clean
A/B the way `power`/`power_off` is.

### The rules, and the controls that set their bands

Three sabotages, all captured on this machine 2026-07-31 at 1280x720 with
`--fixed-fps 60`, each restored from a hash-verified copy:

- **`square`** — the shipped file restored out of git: a flat untextured 0.34 m
  `QuadMesh`, `BILLBOARD_ENABLED`, one layer, no albedo texture anywhere. The
  whole defect.
- **`flat`** — this build with both `albedo_texture`s dropped and *nothing else*
  changed: same size, same placement, same depth behaviour. The **shape alone**,
  which `square` confounds with the size.
- **`linear`** — this build with `col.srgb_to_linear()` in front of both albedo
  colours. The colour-space A/B.

| rule | band | ships | `flat` | `square` |
|---|---|---|---|---|
| the flash is the ancestor's size at the sights | [0.11, 0.22] | **0.15699** | 0.15699 ok | **0.46160** |
| the flash does not grow at the sights | [0.98, 1.02] | **1.00000** | 1.00000 ok | **1.43227** |
| the flash falls off from its core (ads) | [4, 60] | **18.9267** | **1.0411** | **0.3125** |
| ...at the hip too | [4, 60] | **17.3903** | **1.0883** | **0.2719** |
| the flash is a disc and not a square (ads) | max 0.20 | **0.02009** | **0.96884** | 0.85355 / **0.00510** |
| ...at the hip too | max 0.20 | **0.00187** | **0.89177** | 0.89680 / **0.00128** |
| the flash lights the frame without swallowing it | [1.4, 4.0] | **2.3151** | **10.0573** | **72.5195** |

Five of seven fail against `flat` and the two that survive `flat` are exactly the
two that measure size — which is the point of having both controls.

### The `square` column has two numbers in it, and that is a finding

Re-run on review, 2026-07-31, from **git HEAD verbatim** — mesh 0.34,
`BILLBOARD_ENABLED`, `no_depth_test` off, `global_position` + `rotation.z` — the
gate fails **68** rows and **five** relations, but the two *disc* rules **pass**,
at 0.00510 and 0.00128. The first number in each cell above is a camera-oriented
flat 0.34 m fill, which fails them; the second is the real thing, which does not.

The cause is worth writing down because it bounds what this probe can ever say.
`BILLBOARD_ENABLED` replaces the model-view basis in the vertex shader, so the
**node transform `_probe_flash` takes its four diagonals from is not the
orientation that was drawn**. The corner discs land off the drawn square and read
the room. The two disc rules separate a shaped flash from a flat fill *at the same
orientation*, which is what they are for; a build whose material has gone back to
a billboard is caught by the other five relations and by `checks/frame.gd`
asserting `BILLBOARD_DISABLED` headlessly.

### Two holes the relations do not cover, and where they were closed

Also found on review, by running the controls the rules are named for:

| sabotage | `--verify` | gate relations | gate rows |
|---|---|---|---|
| the burst layer never placed (`_burst_quad.visible = false`) | **580 green** | **0 fail** | 7 drift |
| the size roll pinned to a constant | **580 green** | **0 fail** | 16 drift |
| a second `Rng.randf(Rng.VISUAL)` per shot | **580 green** | **0 fail** | 0 drift |
| the burst's core disc deleted from the mask | 2 fail | 0 fail | 0 drift |
| the burst flattened to a plain disc | 4 fail | 0 fail | 0 drift |

The last two are covered: `burst_image()` is driven by `checks/frame.gd`, so the
**art** is gated. The first three were not covered by anything that survives a
`-Bless` — the ancestor's layers 2 and 3, html:3158-3168, could stop reaching the
screen entirely and every relation stayed green. **A row drift is not a gate**;
it is a snapshot, and snapshots are what `-Bless` erases.

Statistics could not close it: with the burst gone, `flash_core_over_ring` moves
17.39 → 16.61 and `flash_corner_over_core` not at all, because the halo's own
centre saturates. Only `flash_core_br` (1.0000 → 0.6379 hip, 0.8742 ads) and
`flash_white_core` (2.2883 → 1.4597, 6.0817 → 5.3164) move, and the ADS margin on
both is under 15% against a statistic whose ceiling is a saturation — the
non-monotone trap the rim rule already records.

So it was closed **headlessly and through the consumer** instead:
`checks/frame.gd::_flash_drawn` emits the real `fired` signal and reads the two
live nodes, asserting both layers lit, the burst concentric with the halo at the
ancestor's `r*0.62` over `r*2.4`, each shot's size equal to that shot's own roll,
and exactly one `VISUAL` draw spent. Each of those was controlled and each turns
its own check red and no other.

Two more measure **where** the flash is, and they are the rendering half of a
hole `checks/projectiles.gd::_ads_flash` cannot close. That assertion claims "the
muzzle flash lands on the barrel at the hip and at the sights" and is an
algebraic identity twice over: `flash_anchor()` scales by `tan(F/2)/tan(V/2)` and
the check unprojects through `V`, so the ratio cancels — and **both of its sides
read `_muzzle.global_position`**, so a marker moved to the grip moves both. These
read the flash quad's own projected centre against the frame's, which is a
constant, so nothing cancels. Controlled by sabotaging the marker itself
(`viewmodel.gd:837`) and restoring:

| | `flash_ads` cy | `flash_ads` cx |
|---|---|---|
| **ships** | **1.08089** (29 px under the crosshair) | **1.00000** |
| `_muzzle.position = Vector3.ZERO` | **1.18269** (66 px under) | 1.00000 — blind |
| marker +4 cm along x | 1.08089 — blind | **1.27778** (178 px right) |

Each rule is blind to the other's defect and neither is enough alone, which is
the same shape as the two sight-picture rules above it. `1.43227` is `tan(37)/tan(27.75)` to five figures: the
shipped quad was a fixed world size at a fixed depth, so it grew with the camera's
ADS zoom while the weapon it is attached to, redrawn through `viewmodel.gd`'s own
fixed 55-degree projection, did not.

**`0.46160` is the complaint as a number.** It is the flash's projected
half-width over the frame height, so the square was 92% of the screen tall at the
sights and 64% at the hip. The ancestor's own range (html:3148 rolls
`r = cssH*(0.05+random*0.035)`; html:3150 draws out to `r*2.4`) is 0.12 to 0.204.

### A metric that was checked and rejected

`flash_white_core` — the core's blue-over-red over the halo ring's — reads
**2.2883** shipped at the hip against **1.8012** for `flat` and **1.3149** for
`square`. It looks like a rule and it is not one: the core saturates to pure
white in *every* variant that is bright at all, so the statistic is really
measuring how tinted the ring is, which is the falloff rule again. A band that
separated 2.2883 from 1.8012 would be 27% wide with no headroom. It stays in the
golden row as a snapshot and is **not** a relation; the white core is asserted
headlessly instead, off `atmosphere.burst_image()`'s own core tier and off
`FLASH_HOT` against `MUZZLE_DEFAULT`. CLAUDE.md: *"a frame comparison metric must
be checked before it is trusted."*

### The colour space

The flash is `BLEND_MODE_ADD`, so constraint 6 says its albedo *is* a light
contribution and must be converted — while `gunart.gd` records that converting an
unshaded albedo shipped a near-black frame. Both are true of different
mechanisms, and the question is only whether the engine already converts
`albedo_color`. **It does**, measured by forcing the halo's albedo to a neutral
grey and reading `flash_ring_mean`, the annulus at 0.72–0.92 of its radius:

| halo albedo (display) | `ring_mean` | over the 1.0 row | sRGB decode of it |
|---|---|---|---|
| 0.00 | 0.01304 | — (the floor: scene + muzzle light) | — |
| 0.25 | 0.02048 | 0.3221 | 0.0508 |
| 0.50 | 0.03110 | **0.4890** | 0.2140 |
| 0.75 | 0.04524 | **0.7115** | 0.5225 |
| 1.00 | 0.06359 | 1.0000 | 1.0000 |

FILMIC compresses and the floor is positive, and both can only push a measured
ratio **above** the true ratio of light. So 0.4890 against 0.500 and 0.7115
against 0.750 are impossible if the authored value reached the buffer
unconverted, while every row sits above its decoded prediction by the margin a
tone curve puts there.

So `atmosphere.gd` passes display values and calls nothing. The `linear` control
is what that costs if you get it wrong:

| | frame mean | halo ring | halo blue/red |
|---|---|---|---|
| `flash_hip` passed through (ships) | 0.014573 | 0.05750 | 0.43701 |
| `flash_hip` hand-converted | 0.013355 | 0.05072 | 0.34342 |
| `flash_ads` passed through (ships) | 0.013587 | 0.05284 | 0.16443 |
| `flash_ads` hand-converted | 0.012242 | 0.04473 | 0.09337 |

-9% of the frame's light, -13% of the halo's, and the halo's blue-over-red falls
by a fifth at the hip and nearly half at the sights: it darkens **and** goes deeper
amber, which is the same double-darkening in the same direction `gunart.gd`
records. `gunart.gd`'s case differs because it writes per-*vertex* colours, which
carry no `source_color` hint and get no automatic decode.

### And the billboard was eating the roll

The shipped code rolled `_muzzle_quad.rotation.z` from `Rng.VISUAL` every shot.
`BILLBOARD_ENABLED` replaces the model-view basis with the camera's in the vertex
shader, so that roll never reached the GPU. **Controlled**: the shipped file
captured with the roll pinned to 0.0 and to `TAU/8`, nothing else changed —
`flash_hip.png` byte-identical both times (sha256 `b51229d6…`, 294177 bytes), and
`flash_ads.png` likewise (`24ad5033…`, 242157 bytes). The brief for this package
read the same symptom as "the square is featureless"; it was that *and* a draw
from the cosmetic stream being thrown away.

The quads are oriented by hand now, which also means their mesh AABB describes
what is drawn and they need no `extra_cull_margin` — and the roll's `Rng.VISUAL`
draw was **reused for the size**, not added to, so the stream advances by the same
one draw per shot it always did. That is why `raygun` did not move: `_launch`
takes its spread from `VISUAL` immediately after `fired` is emitted
(player.gd:939-940), and one extra draw here would have moved the bolt.

---

## Adding a scenario

1. Add it to `registry()` in `scripts/dev/shot_setup.gd`, with a `settle` budget
   **in seconds of game time** (an exact multiple of 1/60), a `why`, and — if the
   scenario's name is a destination rather than a moment — an `until` predicate.
2. If it needs a measurement of its own, add a branch to `probe()` and list it in
   `probes_expected()`. If it needs the viewmodel located, list it in
   `silhouette_expected()` instead; that half runs against a second rendered
   frame and must not touch the live scene.
3. `pwsh tools/frames.ps1 -Bless`.
4. Look at `ref/<name>.png`. The gate cannot tell you the scenario photographed
   the state its name claims.

Until step 3, `--verify` **fails** — `checks/frame.gd` asserts that every
registered scenario has a golden row and a reference image. That is deliberate: a
scenario nobody has ever photographed is a row of numbers nobody has ever seen.
