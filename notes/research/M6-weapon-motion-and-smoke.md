# M6 — Weapon motion and smoke

Research brief for **Kriegsnacht**, compiled 2026-08-02 from four researchers — three on the
reciprocating rig and the animation vocabulary, one on smoke. It **extends** `M5-weapon-feel.md`
and does not repeat it: model depth, the baked face bracket, spread bloom, view kick, brass and
the reload's *structure* are M5's and stay there. This document is about **what moves, when, and
whether anyone can see it** — plus the one visual effect M5 left entirely unscoped.

Every repo citation below was re-read line by line while writing. The ones that drifted are
called out in **Coverage gaps**. Evidence tiers as M5: **1** this repo, the ancestor, or engine
source read directly · **2** a maintainer statement or a data file with a known edit ·
**3** a reputable secondary or reference implementation · **4** community anecdote.

**Nothing in this document was measured in a running engine.** No `--verify`, no `--shot`, no
`--frames`, no `--sim` was run by any of the four researchers, by me, or in the review pass. Every
number is arithmetic over source, and the two that matter most disagree by 3× (see *Is the motion
even visible* — which also records that settling them needs no capture).

**Revised 2026-08-02 after two adversarial reviews**, one on mechanical truth and one on
constraints and testability. Thirty-one findings were verified and applied and three sub-claims
were rejected with evidence; the whole ledger, including two defects the reviewers did not find
and three of their claims I could not reproduce, is in **What the critics found** at the end.
Corrections are marked in place rather than silently folded in, because a wrong number that leaves
no scar comes back.

---

## Bottom line

- **"The guns feel static" is not one defect, it is four, and only one of them is the amount of
  motion.** The rig moves the right part on six of thirteen weapons; the peak of the motion is
  never rasterised; at the sights it collapses to sub-pixel on four of seven weapons that have it;
  and the two weapons the owner is most likely to be holding when he says it — the AK-74u and the
  RPK — are animating a **gas tube**, a part that does not move on the real gun.

- **The fact that decides eight of the thirteen rows has never been written down: the player sees
  each weapon's LEFT flank.** `REST_POS.x` is +0.038 and `REST_YAW` +0.2094 turn the muzzle inward
  (`viewmodel.gd:171`, `:189`), so the visible face is model −X — `gunart.gd:277-278` says so in
  passing (the sentence starts on `:277`, the phrase lands on `:278`) and nothing has ever
  reasoned from it. Every right-side reciprocating part on the roster
  (M14 op rod, AK-74u and RPK charging handles, M16 port cover and brass deflector) is on the face
  the camera never sees, and `_extrude` sweeps symmetrically about x = 0 (`gunart.gd:699-700`), so
  modelling one would mirror it onto the visible left where it does not belong.

- **`SLIDE` is right on 6 rows, wrong on 5, and correct-for-the-wrong-reason on 2** — and the two
  outright wrong rows animate the same drawn strip the MP40 uses for a bolt handle. One 8–14 × 3
  unit rect in `Color("3a3d40")` was given three different mechanical identities
  (`gunart.gd:65`, `:72`, `:85`). The audit rule the file states — *"a weapon gets a reciprocating
  part only when the art actually draws one"* (`:141-142`) — was applied to a **shape**, not to a
  **part**.

- **Two weapons have their cycle running backwards.** The MP40 and the PM-63 both fire from an
  **open bolt**: rest is bolt-rearward and the first motion on the trigger is *forward*.
  `_slide_offset()` returns 0 at rest and runs back-then-forward (`viewmodel.gd:808-817`), which
  is the closed-bolt cycle, and `_locked` pins an empty MP40's bolt to the rear when an MP40 has
  no hold-open device at all. That is a double inversion: the rig shows a ready gun in the empty
  pose and an empty gun in the ready pose.

- **The pump guns are racked at the instant the shot leaves**, which is the one thing a pump
  action definitely does not do (`viewmodel.gd:609`). The Stakeout has 0.414 s of interval and the
  China Lake 0.968 s — 3× to 16× the room needed to delay it.

- **Travel is one global constant across weapons drawn 37 to 86 art units long, and it is below
  the cartridge floor on five of the seven weapons that have a `SLIDE` entry.**
  `SLIDE_TRAVEL := 0.0042` = 4 art units (`viewmodel.gd:399`). A self-loader's breech face must
  out-travel the cartridge it feeds; scaled through each weapon's own drawn span the floors are
  m1911 5.55–5.71, stakeout 7.00, chinalake 8.78, ak74u 6.09, rpk 4.63 — all above 4 — against
  mp40 2.85 and pm63 2.55, which 4 clears. **The M1911 is not the only bounded row; it is the row
  where two independent derivations agree** (5.55 and 5.7). *Corrected 2026-08-02: the first
  version of this bullet claimed the M1911 was the only row with a lower bound, which its own
  floor table two pages down contradicted. See the travel table for the folded-stock correction
  that moved three of these numbers.*

- **The clip budget is not what stops any of this.** Rearward travel moves a group *toward* the
  grip, so `max_screen_radius` **falls** with travel (m1911 0.154927 → 0.148561 m at 12 mm). The
  binding constraint on travel is the **art** — what the moving part hits — and the binding
  constraint on idle motion is the **frames-gate probe rect**, not the 8 mm of clip margin.
  The one proposal here that can genuinely break the guarantee is a *rotation*, and endpoint
  sampling is unsafe for rotations by construction.

- **Nothing guards any of it.** `grep -rn 'SLIDE_TRAVEL|_slide_offset|_cycle_slide|_locked'
  scripts/dev/` returns **zero lines** — I ran it. Reverse the sign of the travel, empty every row
  of `SLIDE` but the M1911's, or set travel to zero, and all **692** assertions stay green
  (`verify.gd:166`; ~483 was a stale figure from CLAUDE.md and the true total is the floor). The
  frames gate is blind too: `flash_hip` and `flash_ads` are the only scenarios where a shot has
  been fired and they carry exclusively `flash_*` probes, while `spawn` and `ads` carry all seven
  `gun_*` probes and never fire — I parsed `golden.json` and confirmed both lists.

- **Smoke is one quad, not a particle system.** Fill rate is not the binding cost — one near-camera
  puff at 26% of screen height is 3.80% of a 1280×720 frame. The real cost is a
  `ParticleProcessMaterial`, which is one main-thread GLSL compile per page load, and which is why
  `fx.gd` caps its families at three (`fx.gd:40-43`, read). The ancestor's only smoke is
  `html:2581` — 14 particles of `rgb(70,64,58)` at gravity 1.5 — and it is **unported**, along
  with its 26-particle ember companion at `:2580`.

---

## The thirteen weapons, and what moves

Column 2 is the real firearm. Column 3 is what `gunart.gd`'s `ART` entry actually draws, by index.
Column 4 is `SLIDE` as it ships (`gunart.gd:146-160`, re-read; every index and comment below is
verbatim). Column 6 is the proposal, in art units at `GUNART.UNIT`.

| # | weapon | what really moves on the shot | what ART draws (index: what it is) | `SLIDE` today | verdict — travel / direction / duration / trigger |
|---|---|---|---|---|---|
| 1 | **m1911** | slide, full rearward stroke ≈23% of the weapon's length; locks back on the last round | 1 = slide plate (x26–58, y20–24), 6 = highlight rib on it (x26–56); 2 = the 10×4 at x22–32 | `[1, 6]` — **right** | **+z (rear), 7 units, 0.055 s, on the shot.** Raise from 4: 4 is below the cartridge floor (5.55–5.7, two derivations). **Bounded at both ends, and it is the only row that is:** floor 5.55–5.71, real stroke ≈8.4 units (Tier 4, see the travel table), proposal 7 = 83% of the stroke. Keep hold-at-travel on empty — BO1's own draw animation locks the slide back and releases it |
| 2 | **olympia** | **nothing external.** Break-action over/under, single trigger, internal hammers, auto-**ejectors** — which throw the hulls that were *fired* and merely lift unfired rounds for the hand (Tier 3, shotgunlife/NRA) | 0,1 = the two stacked barrels (confirming over/under), 6 = rib; 2 = the wrist under the hand (brown `4b3218`, x60–70, and `GRIP.olympia` (62,26) is inside it); **5 = the only grey metal at x44–54 and its identity is unsettled** — receiver/standing breech or fore-end iron; 3,4 = stock | `[]` — **right** | **Nothing on the shot.** All its motion is the reload: the barrel group hinges and **the fired hulls are thrown** — `weapons.gd:25` already flags the Olympia `"shells": true`, so the port loads it shell by shell and the ejection count is already a function of `mag` at reload start. Throwing a fixed two would be a deliberate simplification and must say so. A **rotational** channel, and the biggest risk in the package. **The hinge group depends on part 5's identity — see *Listed and not recommended*** |
| 3 | **m14** | op rod, **external, on the RIGHT**, full stroke every shot; holds open on empty | 4 = the 7×12 at x44–51, 5 = wrist/trigger group; **no op rod drawn** | `[]` — **right answer, wrong stated reason** | **Nothing on the shot, and do not add it.** Far side; symmetric extrusion would mirror it onto the visible left. Its shot-time motion is brass (M5 F27, `fx_rifle`) |
| 4 | **mp40** | **OPEN BOLT.** Rest = bolt fully rearward; the trigger sends it **forward**, it fires, blowback returns it. Handle on the **LEFT** — the visible side. **No hold-open** | 6 = the 10×3 strip at the receiver's front (x18–28, y20–23) = bolt handle; 2 = the 6×15 at the grip; 5 = folding stock strut | `[6]` — **right part, inverted cycle** | **Rest at 8 units back; on the shot run forward to 0 over 0.7 of the cycle, back over 0.3; cycle = the shot interval.** EMPTY must show it **forward** |
| 5 | **pm63** | **OPEN BOLT**, and it fires while the slide is still travelling **forward** (advanced primer ignition). The slide is the reciprocating mass | 1 = the slide (x30–52, y21–29); 2 = the 5×13 at the grip; 3 = folding stock (`rr` at 54,24); 4 = folding foregrip | `[1]` — **right part, inverted cycle** | **Rest at 5 units back, forward-then-back, cycle = the interval — and 5 is a recorded interpenetration, not a clearance.** *Corrected 2026-08-02.* Contact with the folding-stock strut is at **2 units**, not 5: part 1 is x30–52 y21–29 (`gunart.gd:66`), the strut's `rr` origin (54,24) is one of its corners by `_part_poly`'s stated convention (`gunart.gd:568-571`), and 24 lies inside the slide's y-band, so 52 + 2 = 54. But 2 units × 9.80 mm/unit = 19.6 mm against a 9×18 Makarov OAL of 25 mm, so **2 is below this weapon's own cartridge floor and the drawn art affords no valid stroke at all.** 5 is taken anyway because part 3 sits at half-depth 3.02 art units against part 1's 2.74 and is inflated by `3·PROUD` against `1·PROUD`, so the strut **encloses** the slide where they meet and renders proud of it on both flanks: the overlap is concealed by the same LAYER/PROUD stacking that exists to put a highlight over its plate. That is a departure and the comment must say so |
| 6 | **ak74u** | charging handle welded to the bolt carrier, reciprocating over the **rear** of the receiver — **on the RIGHT** | 7 = `["r",18,19,8,3]` — x18–26, y19–22, **entirely forward** of the receiver (part 1 = x24–50) and floating above the barrel = **gas tube / front sight base** | `[7]` — **WRONG: animates a static part** | **`[]`.** Nothing on the shot. Brass (`fx_pistol`) and the magazine on the reload are the honest wins |
| 7 | **stakeout** | **nothing on the shot.** Ithaca 37: pump, **bottom ejection**, slab sides, no side port. The fore-end strokes **between** shots. *One qualification the first draft missed:* the pre-1975 Model 37 has **no disconnector and slam-fires**, so under sustained fire the shot breaks at the *end* of the forward stroke and the pump motion **precedes** the shot (Tier 3/4: shotgunworld, Grokipedia). **BO1 overrides it** — the engine models a pump gun with a rechamber state entered after the fire animation, and the reference wins | 2 = fore-end (x20–36, y27–32); 0,1 = barrel + mag tube; 6 = grip panel (x50–57, y30–41) | `[2]` — **right part, wrong event** | **9 units, back-then-forward, starting ≈0.35 of the interval after the shot and lasting ≈0.55 of it** (0.145 s / 0.23 s at 145 rpm; expressed as fractions so Double Tap still fits). *The 12.51 alternative was withdrawn — see the travel table.* Plus once per shell in a segmented reload (M5 R6) |
| 8 | **m16** | charging handle does **not** reciprocate; carrier is internal; port cover and deflector are **on the RIGHT** | 2 = carry handle (x30–48, y17–20), 3 = the 6×14 at the grip, 6 = the 8×13 forward of it; nothing reciprocating drawn | `[]` — **right, and for a better reason than the comment gives** | **Nothing on the shot.** Its one left-side animated control is the bolt catch, and IMFDB records BO1's reload ending on "pressing the bolt release". Brass (`fx_rifle`) is its shot-time motion |
| 9 | **rpk** | carrier + handle, **on the RIGHT** | 8 = `["r",10,20,14,3]` — x10–24, **entirely forward** of the receiver (part 1 = x26–52), over the barrel = **gas tube**; 5 + 6 = the drum; 2 = the 6×14 at the grip | `[8]` — **WRONG: animates a static part** | **`[]`.** The weapon the owner named is the one weapon on the roster with *nothing* a first-person camera can see cycle. Its budget is the drum on the reload and brass (`fx_saw`) |
| 10 | **chinalake** | **nothing on the shot.** Pump-action 40 mm: pull the fore-grip rearward to eject and cock, push forward to chamber — **between** shots | 6 = pump under the tube (x26–44, y30–35); 2 = bore circle; 3 = pistol grip (x52–59, y27–41) | `[6]` — **right part, wrong event** | **8 units, back-then-forward, ≈0.25 s delay, ≈0.45 s duration** inside a 0.968 s interval. 8 is a **cap forced by the art**: part 6 (x26–44) meets part 3 (x52–59) at exactly 8 (44 + 8 = 52). *Corrected 2026-08-02: the first draft called 8 "~92% of the true stroke". It is 92% of derivation **A's floor**, not of a stroke.* 8 units × 11.207 mm/unit = **89.7 mm against a 98.4 mm grenade** — the pump stops 0.78 units short of the cartridge floor, which is the same class of violation this document raises the M1911 to fix. Either take 8 and record it as a departure forced by the drawn pistol grip, or move part 3 back two units and take 10 |
| 11 | **raygun** | fictional. BO1 shows no reciprocating part **on the shot**, and the magazine is "stuck into the barrel" — but **the reload flips the barrel open** to swap the batteries (Tier 4, callofduty/callofdutyzombies fandom; nazizombies.fandom carries no BO1-specific animation text, so single-sourced). That is the same rotational channel the Olympia hinge is, and `ART` already draws the front as a separate group of concentric rings (parts 2,3,4, all `c` at 16,26 — `gunart.gd:91-92`). It is the third weapon whose mechanism lives in the reload | 2,3,4 = concentric lens rings, 4 = hot core `#e8ffc0` | `[]` — **right for the shot** | **No motion on the shot; the reload hinge is scoped OUT of this package** and is counted in R8's warrant test rather than ignored. Its per-shot animation is the existing `_flash` (`FLASH_PEAK` 0.35, `viewmodel.gd:418`) — and M5's F36 applies: the core clears the 0.92 glow threshold on only three of its six faces, so "the Ray Gun's shot animation is its glow" is a claim that needs a rendered frame |
| 12 | **thundergun** | fictional. No cycling part. **Iron sights are modelled but non-functional** — *the source contradicts itself and both halves are on the same page*: nazizombies.fandom says "The Thundergun has visible iron sights, although the ability to use them was never featured in the game" **and** "has no iron sights, meaning it must be fired from the hip". Modelled-but-unusable is the only reading both sentences allow. Canon: **two red lights on the front of the canister show the rounds remaining**, and they belong to the **magazine**, not the gun body — hence the recorded bug that "the glowing lights will still be visible, even though the magazine is out". **Three** are visible when upgraded | 4, 5 = exactly two emitter circles at the muzzle end (`c` 14,22,3.6 and `c` 14,31,3.6, `#7adff0` — canon says red) | `[]` — **right** | **No motion.** The canon per-shot change is those two lights going dark across a 2-round magazine — a **colour** channel needing a third mesh group. If it is ever built they must go dark **with the magazine** on a reload and not only with the ammo count. Optional, costed below |
| 13 | **knife** | n/a | 0,1 = blade polygons | `[]` — **right** | Nothing. The whole model is the animation (`MELEE` channel) |

### The two rows that animate a part which does not move

`gunart.gd:152` reads `"ak74u": [7],          # the charging-handle strip above the gas tube`
and `:155` reads `"rpk": [8],            # the charging-handle strip above the gas tube`. Both
comments name the gas tube and then claim the part is a charging handle.

**The geometry settles the RPK and does NOT settle the AK-74u.** *Corrected 2026-08-02; the first
draft claimed it settled both, and the row above said part 7 was "entirely forward" of the
receiver.* Measured:

| weapon | strip | receiver | overlap in x |
|---|---|---|---|
| ak74u | part 7, x18–26 (`gunart.gd:72`) | part 1, x24–50 (`:70`) | **x24–26, two units** |
| mp40 | part 6, x18–28 (`:65`) | part 1, x26–56 (`:62`) | **x26–28, two units** |
| rpk | part 8, x10–24 (`:85`) | part 1, x26–52 (`:81`) | **none — disjoint** |

The AK-74u and the MP40 score *identically* on "forward of the receiver, above the barrel", so a
predicate built from that geometry either convicts both or acquits both. Only the RPK is caught.

**The argument that actually carries the AK-74u is mechanical, and it must be the one written into
the file.** An AK-74u and an RPK carry a **gas tube** in exactly that position — above the barrel,
forward of the receiver, bolted down — and an MP40 is **straight blowback with no gas system at
all**, so on an MP40 the same idiom cannot be a gas tube and an MP40's cocking handle is the only
thing it can be. An AK's charging handle is welded to the bolt carrier and travels over the
**rear** of the receiver, on the right side; nothing is drawn there.

Supporting and approximate: an MP40 is 833 mm over 80 drawn units (10.41 mm/unit) with a 251 mm
barrel (Wikipedia, fetched), which puts the end of the barrel near x32 and a bolt-forward cocking
handle near x32–42 rather than the drawn x18–28. That is a Tier 3 scale estimate against art that
was never drawn to scale, so it is a corroboration and not the argument.

**Without the gas-system sentence in the file, the next agent restores `"ak74u": [7]` by symmetry
with the MP40 and is arguing consistently.**

So the visible result today is a small grey strip sliding along the barrel, every shot, on the two
highest-fire-rate rifles in the game. Emptying both rows will read as a regression unless the
reason is written into the file, because the four weapons this leaves with nothing on the shot —
M14, AK-74u, M16, RPK — are exactly the four M5's F27 gives casing effects to. **Their shot-time
motion is brass; their mechanical motion belongs to the reload.** That is a design position when
written down and an omission when it is not, and the next agent will otherwise "fix" the comment
by animating the gas tube again.

### The same drawn strip, three mechanical identities

`gunart.gd:65` (`mp40` part 6, `["r",18,20,10,3]`), `:72` (`ak74u` part 7, `["r",18,19,8,3]`) and
`:85` (`rpk` part 8, `["r",10,20,14,3]`) are one idiom: an 8–14 × 3 unit rect in
`Color("3a3d40")`, at the top line, near the receiver's front. **The three are geometrically
indistinguishable except that the RPK's is disjoint from its receiver** (see the table above), so
the discriminator has to be what the weapon *is*: an MP40 has no gas system, so on an MP40 the
strip is a cocking handle; an AK-74u and an RPK both carry a gas tube exactly there, so on those
two it is a gas tube. The file's own audit rule — *"a weapon gets a reciprocating part only when
the art actually draws one"* — is stated over **parts** and was applied to a **shape**, and no
amount of rect arithmetic repairs that.

### The two rows whose cycle runs backwards

**MP40.** It fires from an open bolt, so its rest position is bolt-back and its first motion on the
trigger is *forward*. `_slide_offset()` (`viewmodel.gd:808-817`, re-read verbatim) returns `0.0` at
rest and runs back-then-forward. Worse, the asymmetry constant is explicitly justified as
`## Back fast, forward slower — a slide is thrown by gas and returned by a spring.`
(`viewmodel.gd:401`) — correct for the M1911, exactly mirrored for a gun the *spring* drives
forward and gas drives back. And the MP40's cocking handle is on the **left**, which makes it the
one weapon on the roster whose reciprocating part is both prominent and on the camera's side. The
rig plays the only visible mechanism it has backwards.

**PM-63.** The same case, with a primary description behind it: the slide is released and driven
forward by the return spring, and the gun fires while the slide is still moving forward, the firing
impulse retarding it and driving it back. **It also has a hold-open, and that is now cited rather
than asserted:** Wikipedia's `FB PM-63 RAK` article states that "after the last cartridge has been
fired from the magazine, the slide is locked open on the slide catch", engaged automatically by
the empty magazine (fetched 2026-08-02; the same claim is on modernfirearms.net, Source index row
14). So `_locked` returning `SLIDE_TRAVEL` is right here and wrong on the MP40, and `BOLT_HOLD`
ships as `["m1911", "pm63"]` — see R6. *This closes what was Coverage gap 13.*

### The bolt lock is wrong on five of seven, and unreachable on the one it is right for

`viewmodel.gd:809-812` returns `SLIDE_TRAVEL` for every weapon with a `SLIDE` entry whenever
`_locked`. Audited against the real weapons: **M1911** correct (slide stop). **AK-74u** and
**RPK** have no last-round hold-open — an AK's bolt runs forward. **MP40** has no hold-open device
at all. **Stakeout** and **China Lake** are pump actions whose fore-end rests forward; held back is
a pose no shotgun holds. **PM-63** has a cited hold-open (above) — but it is also bolt-back as its
*ready* state, so under R3's open-bolt mode the locked pose and the rest pose are the same pose and
the flag buys nothing visible. It is in `BOLT_HOLD` because it is true, not because it shows.
**Two of seven right, and only one of the two is observable.**

And on that one, the pose is essentially never seen. `_locked = state == WEAPON.State.EMPTY`
(`viewmodel.gd:726`, re-read) and `EMPTY` requires `mag <= 0 **and** res <= 0` (`weapon.gd:238-243`),
so the M1911's slide-lock first appears after 88 rounds with no Max Ammo — never on the empty
*magazine*, which is the state that precedes every reload and the only one the reference ever
shows it in. Its release branch at `viewmodel.gd:592-602` is correspondingly near-unreachable.

### The pumps: right part, and here the researchers disagree

`_on_fired` calls `_cycle_slide()` at `viewmodel.gd:609` (re-read; the function is five lines and
that is the fourth), unconditionally, for every weapon.

**Position A (two researchers):** *wrong event*. A pump does not move when the shot breaks; it is
stroked between shots. The trigger must be a timer with a start delay.

**Position B (one researcher):** *right trigger, wrong shape and duration*. Firing **is** the
correct edge — the shooter works the action after the shot — and what is wrong is that a 0.06 s
gas-driven profile with `SLIDE_BACK` 0.30 occupies 14% of the Stakeout's interval and 6% of the
China Lake's, using the asymmetry of a self-loading action for a hand-worked one.

They are not far apart in implementation — both end at a delayed, longer, more symmetric stroke
driven off `fired` — but they disagree about whether the *event* is a defect, and that decides
whether the fix is "add a delay to the existing call" or "stop calling it here". **Both positions
are recorded; neither was tested against a frame.** Position B additionally notes that the stroke
must survive a single shot with no follow-up, which makes it a timer either way.

### Travel: floors, ceilings, and the folded-stock error that moved three of them

Both researchers derived a floor from the same principle — *an action must open by at least one
cartridge length* — scaled through each weapon's own drawn art span. **Derivation B's method
reproduces exactly** — `floor = cartridge OAL / (weapon OAL / drawn span in art units)` — and I
re-ran it on three controls before touching anything: RPK 56 / (1040/86) = 4.631 against B's 4.63;
China Lake 98.4 / (876.3/78.2) = 8.781 against B's 8.80; M1911 32.4 / (216/37) = 5.550 against B's
5.55. Three exact hits, so the method is confirmed and the disagreements below are about **inputs**.

**The scale must come from the length of the weapon AS DRAWN.** Derivation B used stock-**folded**
overall lengths for all three folding-stock weapons, and all three are drawn with their stocks
**extended** — mp40 part 5 (`gunart.gd:64`, the `rr` whose far corner lands at x = 87.99, 36 units
behind the grip), pm63 part 3 (`:67`, far corner x = 71.51), ak74u part 4 (`:71`, x62–84). Feeding
the folded length reproduces B's three numbers to two decimals, which is how the error was
identified rather than guessed. Corrected with the extended lengths (Wikipedia infoboxes, all three
fetched 2026-08-02: MP 40 833/630, AKS-74U 730/490, FB PM-63 583/333):

| weapon | drawn span (art units) | OAL as drawn (mm) | mm/unit | cartridge | **floor** | was (B) | real stroke, **ceiling** (Tier 4) | free run in the art | proposed |
|---|---|---|---|---|---|---|---|---|---|
| m1911 | 37 (x22–59) | 210–216 | 5.68–5.84 | .45 ACP 32.4 | **5.55–5.71** | 5.55 | ≈8.4 (48 mm, *unreproduced* — see below) | none: nothing sits in its y20–24 band behind it | **7** |
| mp40 | 80 (x8–87.99) | **833** extended | 10.41 | 9×19 29.69 | **2.85** | 3.77 | ≈8.6 (90 mm) | 28 (part 3 at x56) | **8** |
| pm63 | 59.5 (x12–71.51) | **583** extended | 9.80 | 9×18 25.0 | **2.55** | 4.50 | ≈7.7 (75 mm) | **2** (the strut at x54) | **5**, a recorded interpenetration |
| stakeout | 84 (x4–88) | ≈838 *estimate* | 9.98 | 2¾″ 69.85 | **7.00** | 12.51 | ≈9.5 (95 mm pump stroke) | 14 (grip panel at x50) | **9** |
| chinalake | 78.2 (x5.8–84) | 876.3 | 11.21 | 40×46 98.4 | **8.78** | 8.80 | unsourced, > the floor | **8** (pistol grip at x52) | **8**, below the floor, a recorded cap |
| ak74u | 78 (x6–84) | **730** extended | 9.36 | 5.45×39 57 | **6.09** | 9.07 | — | — | row emptied |
| rpk | 86 (x2–88) | 1040 | 12.09 | 7.62×39 56 | **4.63** | 4.63 | — | — | row emptied |

**Every travel number needs a ceiling as well as a floor.** A stroke below the floor cannot feed;
a stroke above the real one is what actually reads as broken, and the first draft of this document
derived only floors. The ceiling column is Tier 4 throughout and the M1911's is worse than that: a
reviewer offered 1.90 in (48 mm) for a 5″ slide, and **I could not reproduce it** — a search
restricted to `1911forum.com` / `forum.m1911.org` returned discussion of slide travel and no
number. Treat the ceilings as bounds on the *proposal's plausibility*, never as provenance.

**The Stakeout's 12.51 was a units error and is withdrawn.** Back-solving B's own method,
69.85 / 12.51 = 5.584 mm/unit, which requires an overall length of 84 × 5.584 = **469 mm**. No
Ithaca 37 is 469 mm long; the shortest pistol-grip Stakeout is about 645 mm and BO1's carries a
full buttstock (drawn as parts 3/4/5, x56–88), putting it near 838 mm. At that scale the floor is
7.00 and a real ≈95 mm pump stroke is 9.5 units — which is A's 9, to within the estimate. 12.51
units is 14.9% of the drawn weapon against a real stroke of about 11.3%, so it was **the one
proposal in the package that moved a part further than the firearm does**. *The 838 mm is my
estimate, not a citation, and the conclusion survives any Ithaca 37 length in the 645–1003 mm band:
the floor runs 5.85–9.07 and 12.51 clears none of them.* **Take 9. No `--shot` pair is needed to
settle a number that was arithmetic.**

**The "free run" column is a different quantity from B's, and B's was measured against the wrong
thing.** B computed the gap to the **grip anchor** (`GRIP`), which is a hand position and not a
part. Measured against the parts that can actually be hit — non-slide parts that do *not* already
overlap the group at rest, whose y-span intersects the group's, ordered behind it — the numbers
move: Stakeout 14 rather than 16.92 (the grip panel is at x50, the fore-end's trailing edge at
x36), China Lake 8 rather than 9.76, PM-63 **2** rather than −4.04. B's own gap note is consistent
with 14 and not with 16.92 — it records 1.5 units of clearance at 12.51, and 14 − 12.51 = 1.49.
This is why R2's floor assertion computes the free run from `ART` instead of pasting it.

**Two rows still sit outside the floor, and both must ship as recorded departures.** The PM-63 at
5 (its drawn art affords **no** valid stroke: contact at 2, floor 2.55) and the China Lake at 8
(0.78 units short of a 40 mm grenade). Per the mystery-box rule they are wrong even when right
unless the comment says so.

Every mid-range travel figure in the corpus (M1911 ≈48 mm, MP40 ≈90 mm, PM-63 ≈75 mm, AK ≈125 mm,
Ithaca pump ≈95 mm) is a **Tier 4 estimate from mechanism and receiver length**; three searches for
a sourced M1911 slide-travel figure — two by the corpus, one by me — returned nothing usable.
Treat the *fractions of weapon length* as ±30%. What survives is the **method**, not the digits.

---

## Is the motion even visible

**At the hip, marginally. At the sights, no — and the peak of the motion is never drawn at all.**

### The peak is never rasterised

`SLIDE_BACK` 0.30 × `SLIDE_TIME` 0.06 = **0.018 s = 1.08 frames** at 60 Hz
(`viewmodel.gd:400`, `:404`, re-read). Stepping `_slide_offset()` at dt = 1/60, the first frame
sampled after a shot is already past the peak at u = 0.27778, f = 0.92593. So:

- the largest offset ever drawn is **3.89 mm**, not the nominal 4.20;
- the entire displayed animation is **four frames** — f = 0.9259, 0.6349, 0.2381, 0.0000;
- the rise is entirely sub-frame, so only the *return* is animated.

The gun reads as a flick-and-settle rather than as a reciprocation. **Any retune of `SLIDE_TIME`
must respect that a rise shorter than about two frames cannot be seen.**

### The two pixel calibrations disagree by 3×, and this is the largest open number in the package

Two researchers computed how far the shipped 4.2 mm travel moves on screen and got answers that
are not reconcilable:

- **25.0 px** at 720p. Method: `M_PER_H` 0.12088 (`viewmodel.gd:205`) gives 5956.3 px/m at the
  grip's depth; 0.0042 × 5956.3 = 25.0. The same constant reproduces `DIP` (215.8 px against its
  stated 0.30 × 720 = 216) and `SWAP_DROP` (302.1 against 302.4), which is what makes it
  trustworthy *for a screen-plane translation*.
- **8.88 px** at the M1911 slide's front edge, 14.98 px at its rear. Method: resolve model +Z
  through `REST_PITCH` −0.13 and `REST_YAW` 0.2094 into camera space, find it is **14.09° off the
  view axis**, so only **24.35%** of the travel (1.023 mm) is screen-plane and 96.99% is depth;
  then project the front and rear corners separately with K = (1/tan 27.5°)·(720/2) = 691.554 px.

**The discriminator is whether the travel is a screen-plane motion or a depth motion.** It is
model +Z, and `_to_local` (`gunart.gd:436-437`, read: `Vector3(0.0, -(p.y-g.y)*UNIT,
(p.x-g.x)*UNIT)`) makes model +Z the barrel axis, which the rest pose points nearly at the lens.
On that basis the second figure is the better-decomposed one and the first is a screen-plane
conversion applied to a depth-dominated motion. **I am naming both and not averaging them, and I
did not re-derive either basis.**

**It is not a `--shot` question, and calling it one was this document's own error.** *Corrected
2026-08-02.* The viewmodel's projection is fully determined in closed form: `viewmodel.gd:128`
forces `PROJECTION_MATRIX[1][1]` to ±1/tan(27.5°) and scales `[0][0]` by the same `widen`, so the
vertical half-angle is exactly 27.5° whatever the camera's FOV is, and at 720p a point projects at
`691.554 · (y / −z)` px. Take `GUNART.slide_corners(key)`, transform by `_mesh_pose(...)` at rest
and at travel, project both, subtract. That is a **headless** computation with its provenance in a
shader constant — assertable in `--verify`, not photographable. The `--shot` pair is a good
cross-check and is not the instrument. The same applies to the hip-versus-ADS collapse table below:
every row of it is that projection, and it should be a check rather than a photograph.

The second researcher also checked the thing that would have made a depth-dominated travel useless:
the on-screen displacement is **100.000% collinear** with the gun's own on-screen axis on all seven
weapons (cos = 1.00000 to five decimals), because the gun's screen axis passes through the same
vanishing point the perspective scaling works about. So the travel reads as *sliding backward*, not
as a dilation. **The axis is right and it looks right.** "The guns feel static" is not an axis bug.

### At the sights it collapses

`ADS_YAW := 1.0` (`viewmodel.gd:336`, re-read) removes **100%** of `REST_YAW` at the sighted pose.
Per the second calibration, on-screen slide length and travel, hip → ADS:

| weapon | hip: length / front-edge travel | ADS: length / front-edge travel |
|---|---|---|
| m1911 | 89.26 px / 8.88 px | **4.43 px / 0.44 px** |
| pm63 | 64.79 / 10.13 | 4.89 / 0.77 |
| chinalake | 45.71 / 9.13 | 9.63 / 1.93 |
| stakeout | 36.04 / 8.26 | 5.14 / 1.18 |
| rpk | 27.69 / 7.38 | **1.21 / 0.32** |
| ak74u | 17.36 / 8.43 | **0.75 / 0.36** |
| mp40 | 20.66 / 7.92 | **1.12 / 0.43** |

**Four of seven are sub-pixel at the sights.** And this contradicts the file's own stated reason for
the yaw existing. `viewmodel.gd:180-188`, read verbatim:

> **Invented, and it is doing real work.** A viewmodel pointing straight down the view axis is seen
> almost end-on, and this art is a side profile: extruded flat plates viewed from behind read as a
> stack of rectangles.

The docstring gives the reason for twelve degrees of profile yaw and the next constant zeroes all
of it, at the one pose where the player is studying the weapon hardest. The projection is
FOV-invariant (`viewmodel.gd:125-128` forces `PROJECTION_MATRIX[1][1]` to ±1/tan(27.5°) whatever
the camera's FOV is), so this is entirely geometric and not a zoom artefact.

**Tripling the travel does not fix it.** At ADS the barrel is on the view axis, so 100% of any
travel is depth and the on-screen motion is a pure dilation of a 1–5 px object: 0.44 px becomes
1.3 px. Nothing recovers a slide read at the sights except putting the gun back off-axis.

### The cycle time is shorter than the fastest interval — except it is not

`viewmodel.gd:401-403` claims *"The whole cycle is shorter than the fastest weapon's interval, so a
held automatic restarts it rather than compounding it."* Against `weapons.gd:25-36` (re-read; pm63
rpm 1000 at `:29`, mp40 880 at `:28`) and `game_state.gd:54` (`const DTAP_RPM_MULT := 1.34`, read):

| weapon | interval | ÷ 0.06 s cycle | interval under Double Tap |
|---|---|---|---|
| pm63 | **0.06000 s** | **1.00×** | **0.04478 s** |
| mp40 | 0.06818 | 1.14× | 0.05088 |
| ak74u | 0.08451 | 1.41× | 0.06306 |
| rpk | 0.08571 | 1.43× | 0.06397 |
| m1911 | 0.14286 | 2.38× | — |
| stakeout | 0.41379 | 6.90× | — |
| chinalake | 0.96774 | 16.13× | — |

The PM-63's interval is **exactly equal** to the cycle at base rate and 25% shorter under a shipped
perk; all four automatics are at or under the cycle with Double Tap. Simulated at 60 Hz against
`weapon.gd`'s remainder-carrying cooldown over 480 warm frames, a held PM-63 with Double Tap
**never returns to battery** — min f 0.2381, mean 0.6418. That happens to resemble a real 1000 rpm
open-bolt SMG, but it is an accident of a reset-not-accumulate cycle meeting a fire interval it was
never sized against, and it is recorded nowhere.

The right fix is not a smaller constant. **For a self-cycling action the reciprocating cycle length
*is* the fire interval, by definition.** That also makes Double Tap visibly speed the bolt up,
which is feel the perk currently buys nothing of.

---

## The animation vocabulary

### What this pipeline can express

Exactly one thing: **a rigid transform of a partition of the existing parts.** `Slide` is the only
instance of it. `_build(key, pap, want_slide)` filters on `slide.has(i) != want_slide`
(`gunart.gd:440`, `:452`) and `_corners` mirrors that filter at `:477`, so a "group" is a boolean.
The rig writes nine scalar channels to three nodes, and the group's channel is one `Vector3` write
at `viewmodel.gd:773`.

### What it cannot express, and why that is mostly fine

There is no `AnimationPlayer`, no `Tween`, no clip, and there should not be: `_mesh_pose` is
**pure** precisely so `_measure()` can sweep it (`viewmodel.gd:776-805`, `:910-975`), and that
sweep is the entire proof the weapon cannot clip a wall. Any animation authored outside a pure
function of scalars is outside the guarantee.

What it genuinely cannot do:

- **Asymmetric geometry.** `_extrude` sweeps ±`half` about x = 0 (`gunart.gd:699-700`, read) and
  `_prism_corners` does the same. A right-side charging handle would appear on the visible left.
  M5's R2 already deferred per-part z-offset, and that deferral is precisely what blocks modelling
  an AK, M14 or M16 handle correctly. "Add the charging handle" is not a 12-triangle change.
- **Rotation about anything but the grip, today.** `_slide` is added under `_mesh` at
  `viewmodel.gd:518` and its mesh is built in the same grip-relative space as the body
  (`gunart.gd:458`, `:698` both call `_to_local(poly[i], g)` with the same grip). So **`_slide`'s
  origin IS the grip**: any rotation written to `_slide.rotation` swings the slide about the hand.
  M5's note that "`_slide.rotation` is the one free channel there" is true as a channel and
  misleading as a capability. The fix needs no extra node — `Transform3D(R, c - R*c)` maps p to
  c + R(p−c) and stays a pure function of one scalar — but it does need the pose to go through a
  transform rather than an offset.

### The generalised n-group design, and whether it is warranted

Four independent places enumerate "body plus slide" and must agree:

| site | what it is |
|---|---|
| `gunart.gd:411-416` | `sight_height()`'s corner walk |
| `viewmodel.gd:939-945` | `_measure()`'s corner pool |
| `checks/projectiles.gd:834-839` | `_mesh_top`'s top-edge walk |
| `verify.gd:1718` | body only |

`gunart.gd:388-394` already documents what a missed group costs: `body_corners` alone reads the
M1911's sight height as 8.00 art units against the real 10.24 and puts the sight line 13 px through
the crosshair. **The hazard is known and the structure that produces it was not removed.** A second
group added the way the first one was costs a second index table, a second build/corners pair, a
second cache, a second node, two more `_collect` lines — and three of those four sites going stale
in silence.

The generalisation is: `group_names()`, `group_map(key)`, `build_group(key, pap, group)`,
`group_corners(key, group)`, with the empty `StringName` meaning the body. The filter
`slide.has(i) != want_slide` becomes `group_of(key, i) != group`, one line, mirrored in `_corners`;
`build_body`/`build_slide`/`body_corners`/`slide_corners` stay as thin wrappers so the four
external callers keep compiling. Cost: **zero triangles**, +1 draw call per animated group on the
weapon in hand, +2 `SurfaceTool.commit()` per weapon per group at prebuild (39 today: 25 bodies +
14 slides).

**It is warranted if and only if a second group ships.** The candidates are now **three**: a
magazine group on five weapons, an Olympia hinge group, and a **Ray Gun barrel hinge** — BO1's Ray
Gun reload flips the barrel open, which is the same rotational channel and which the first draft
missed entirely (row 11). Any two of the three warrant it. If only the `SLIDE` fixes ship, it is
not warranted.

### The rotation-and-`_measure()` problem, and its answer

This is the subtle one and it has a clean answer.

`_measure()`'s three metrics are `worst` = |v|, `widest` = √(v.z² + ratio²·lat²) and `nearest` =
−v.z (`viewmodel.gd:968-974`, read). The first two are **norms**, hence convex; the third is
**linear**. A maximum of a convex function over a set is attained at an extreme point of that set's
convex hull.

- A **translated** point's reachable set is a *segment*, which is its own convex hull. So
  `_collect(slide, into, SLIDE_TRAVEL)` at `viewmodel.gd:945` is **exact**, and the file's comment
  there — *"both ends of its travel are places a vertex genuinely reaches"* — understates its own
  correctness: it is not merely reasonable, it is provably sufficient.
- A **rotated** point's reachable set is an *arc*, whose hull's extreme points are the whole arc.
  Any inscribed sample is an **under-estimate** — the direction a safety assertion may not err in.

**The answer is a circumscribed polygon.** Sample K+1 angles across the arc and scale each sample
radially about the pivot by 1/cos(step/2); the resulting polygon provably contains the arc, so its
max is a safe over-estimate, and the excess shrinks as step². The sample count is a closed form:

> `ratio · r_max · (1 − cos(step/2)) ≤ 0.0002 m`

For a 0.10 rad hinge at r = 0.03 m that is **K = 1** — the endpoints are already safe, excess
0.054 mm. For a 0.25 rad hinge at r = 0.049 m, **K = 2**, excess 0.055 mm. For the existing
0.5 rad dip roll at r = 0.06 m, **K = 4**, over-estimate 0.117 mm. Each sample is one
`Transform3D`, the same shape as the existing offset.

**And that test indicts the shipped sweep — on four channels, not one.** *Widened 2026-08-02.*
Every channel that enters `_mesh_pose`'s **basis** traces an arc rather than a segment, because
`pitch` and `yaw` are linear in the channels inside `Basis.from_euler` (`viewmodel.gd:802-805`).
Four do:

| channel | amplitude in the basis | swept at | interior sample? |
|---|---|---|---|
| `dip` | `DIP_ROLL` 0.5 rad (`:291`) | `[0.0, 1.0]` (`:955`) | no |
| `ads` | removes 0.2094 rad of yaw and 0.13 rad of pitch (`:189`, `:178`, `:336`) | `[0.0, 1.0]` (`:961`) | no |
| `kick` | `KICK_PITCH` | `[0.0, KICK_MAX]` (`:954`) | no |
| `melee` | `MELEE_ROT` −0.85 rad | `[0.0]` for guns (`:926`, `:951`) — `[0.0, 0.5, 1.0]` for the knife (`:929`) | knife only |

The knife's interior sample is justified in the comment by *"The knife is on screen across the
whole swing"* — a **visibility** argument, not an arc argument, so it lands in the right place for
the wrong reason. Sagitta = r(1 − cos θ/2); at r = 0.06 m the dip's 0.5 rad gives 1.87 mm of
position and up to **2.7 mm of metric** against 8.116 mm of margin, and the ads channel's 0.2094 rad
gives ≈0.33 mm of position at that radius before the ratio² lateral weighting. The file's own claim
at `:903-906` — *"a dense sweep does not beat the endpoints by more than 0.2 mm on any of the
three"* — is a **measurement**, and if it is right the guarantee holds. But it is not true by
**construction**, nothing re-runs it, and any amplitude increase invalidates it silently. **R10
changes `ADS_YAW`, which changes the size of exactly one of these unsampled arcs.**

**This is a live finding against shipped code, and it is now R12** rather than a paragraph with no
recommendation and no assertion behind it.

### One more thing the vocabulary already has and does not use

The reload's per-shell edge. `weapon.gd:326-327` says the sawtooth exists for exactly this — *"Re-
entered rather than continued, so `state_t` sawtooths back to `state_len` once per shell and an
animation gets its cycle for free"* — and **nothing consumes it**. Two routes exist:

- **(a) Derive it in the rig.** `_tick_states` already reads `gun.state_t` every frame
  (`viewmodel.gd:692`). A frame in `RELOAD_SHELL` where `state_t` increased is a shell boundary.
  No signal, no cross-file hunk.
- **(b) `Player.weapon_changed`,** which is already re-emitted on every magazine delta
  (`player.gd:764-772`) — the edge M5's F11 says does not exist is on the wire. But it is emitted
  **inside `for i in guns.size()`**, so a magazine delta on *any* carried gun emits the signal
  naming the gun in hand. It is safe today only because `stow_cancels` (`player.gd:1134`, `:1261`)
  kills a stowed reload — an invariant maintained in a different file.

**Route (a).** And a naive latch gated on `state == RELOAD_SHELL` **misses the last shell**: on the
final one `_load_shell` calls `settle` before the emit (`weapon.gd:318-330`), so the state is
already IDLE/FIRING and a state-gated latch cycles five times in a six-shell reload — a defect that
looks exactly like the one it was written to fix. The latch must gate on the state the rig read on
the *previous* frame.

The end-of-reload chambering stroke a pump gun needs has an existing, unused edge for free:
`RELOAD_SHELL → IDLE/FIRING` via `settle` is an ordinal change and does emit, and
`_on_weapon_state` (`viewmodel.gd:589-602`) handles only `to == RELOADING/RELOAD_SHELL` and
`from == EMPTY`. That is also the mechanically correct place for it — shells go into a tube
without working the pump, and one stroke chambers the first round.

---

## Smoke

### Scope: three of the five candidates are already done or are not ours

| candidate | status |
|---|---|
| **impact dust** | **ships.** `fx.gd:142-151` (the DUST preset, burst 6, grav 4.0, life 0.35) with `FAM_DUST` at `:44`, ported from `html:2502` with per-surface tints the ancestor could not do. Proposing it again would be redoing shipped work |
| **ambient haze** | **ships** as Environment depth fog — `fog_density` 0.030, `fog_light_color` (0.035, 0.040, 0.048), `lighting.gd:68`, `:78`, `:349-351`. A quad-based haze layer is a **second writer of the same visual quantity in a different file**, and `lighting.gd:9-12` states it is step 2 of an eight-step chain where every step changes what the next looks like. **Reject on ownership before cost.** Volumetric fog is dead on this renderer anyway |
| **explosion smoke** | **unported, and it is a real gap** — but it is not weapon feel. See below |
| **muzzle smoke** | **in scope, and new** |
| **barrel heat** | **in scope, and it should be the same mechanism as muzzle smoke, not a second one** |

`fx.gd:3-5` names its own contents exhaustively — *"blood puffs, surface debris, bullet holes,
blood pools and tracers"* — and smoke is not on the list. I read the header; it is accurate.

### The one smoke the ancestor has, and it is unported

`kriegsnacht.html:2580-2581`, read directly:

```js
spawnParticles(x,y,1.0,26,{r:255,g:170,b:60,spd:6,up:3,life:.5,size:.07,glow:true,grav:6});
spawnParticles(x,y,1.0,14,{r:70,g:64,b:58,spd:3,up:2,life:.9,size:.09,grav:1.5});
```

The second is smoke by every property — gravity 1.5 against `spawnParticles`' default of 11, life
0.9 s, no glow — although **the ancestor never uses the word**. I ran `grep -c -i smoke
kriegsnacht.html`: **0**. `notes/analysis/ancestor-diff.md:305` labels it "smoke" in a table of
ancestor *facts*; the inference is good and the presentation is an interpretation wearing a quote's
clothes. **Nobody may later cite "the ancestor's SMOKE preset" as a peer of BLOOD / SPLINT / SPARK
/ EMBER. There is no such constant.**

Both bursts are unported: `projectile.gd:539-569` spends an `OmniLight3D`, a pitched-down `death`
cue, `_splash` and `_self_damage`, and **no particles at all**. That is a genuine fidelity gap and
it belongs to `projectile.gd`'s owner and to an explosion package — it happens at range, it has
none of the viewmodel-projection problem that makes muzzle smoke interesting, and it would import
the particle-shader cost the muzzle design exists to avoid. **Filed as a defect, not fixed here.**

### The cost model, which the framing had backwards

**Fill rate is not the binding cost.** Screen-height fraction of a quad is S / (2·d·tan(fov/2))
(the form `atmosphere.gd:380-381` already uses for `flash_size`). At d = 0.35 m and fov 74, one
screen height spans 0.5275 m, so a puff at 26% of screen height is 187 px tall — if square,
35,044 px, or **3.80% of a 1280×720 frame, for one quad**. At the quality governor's 0.5 render
scale it is 3.80% of 230,400 px. Seven of them would not register.

**The real cost is a `ParticleProcessMaterial`** — one main-thread GLSL process-shader compile on
every page load. `fx.gd:40-43` says so in its own words: *"One `ParticleProcessMaterial` each and
no more, because each one is a process shader this platform recompiles on every page load."* Smoke
cannot share `FAM_DUST`'s, because gravity lives on the process material and dust falls at +4.0
while smoke must hang. So particles cost **+1 process shader**; a quad costs **+0**. That, and not
fill, is what should decide the implementation.

A quad is also fully reachable by the ordinary warm-up pass — `shader_warmup.warm()` draws each
registered material on a plain `MeshInstance3D`, which is exactly what a quad is — while a particle
system needs `fx.gd`'s bespoke ~40-line `warm()` treatment that nothing asserts.

Fire-rate concurrency: the fastest weapon is 1000 rpm = 16.67 shots/s (`weapons.gd:29`), so a
per-shot puff with a 0.45 s life would put 7.5 quads on screen. **A single persistent quad re-kicked
per shot puts 1 on screen at any fire rate**, which removes the question rather than bounding it.

### The `flash_anchor` problem, and it is worse than "it drifts"

`flash_anchor(distance)` (`viewmodel.gd:996-1006`, read and re-derived) equates screen X through the
two projections and returns `_cam.to_global(Vector3(m.x*s, m.y*s, -distance))` with
`s = distance·ratio/−m.z`. The derivation is correct. But it returns a **world point that happens to
project onto the drawn barrel for the camera pose at the instant of the call.** It solves screen
*position* and says nothing about *persistence*.

The flash gets away with that because `FLASH_TIME` is 0.05 s. A puff living 0.45 s is **9× the
flash's life**, and the dominant error term is not drift, it is **camera rotation**: the anchor is a
world point and the weapon is a view-space object re-projected in a vertex shader
(`viewmodel.gd:100-129`). A 180° flick in 0.3 s sweeps a world point at 0.35 m clean off the screen
while the barrel does not move at all. Drift is amplified too — 0.21 m of rise at 0.35 m depth is
40% of screen height, and the ancestor's own `up: 2` m/s over 0.9 s would be 190% of it.

**Design the problem out: re-anchor every frame and carry all apparent motion as growth, fade and a
small camera-local rise.** Both failure modes vanish; nothing integrates.

### Depth, which the first draft left unstated and this file has already measured

*Added 2026-08-02.* A quad at `flash_anchor`'s depth is at a **fake** depth: the anchor solves
screen position by undoing the viewmodel's narrower projection and has no way to also be in front
of a gun drawn through a different frustum. `atmosphere.gd:280-293` records the measurement —
without `no_depth_test`, `--frames flash_ads` had *"the M1911's slide covered the whole burst and
the whole core"*, core/ring 2.518 at ADS and 0.592 at the hip, because the probe was reading the
slide's blue-grey. **A depth-tested smoke quad at 0.35 m is swallowed the same way.**

But `no_depth_test` is not free either, and this is where smoke differs from the flash. The flash
gets away with drawing over the room because it lives 0.05 s. A 0.45 s puff at 26% of screen height
would paint over walls, zombies and everything else for nine times as long.

**The call: `no_depth_test = true`, matching the flash and matching the ancestor drawing the effect
inside the same `save()`/`restore()` as the gun (`html:3142-3170`) — and the SIZE becomes the
binding constant rather than a free one.** 0.16–0.26 of screen height was invented against fill
rate, which this document has already shown is not the binding cost; it must be re-derived against
"how much of the room may a muzzle puff repaint", and that ceiling has not been derived. **This is
the one smoke constant whose *kind* changed, and it is flagged rather than guessed.**

Two further properties are decisions and not details, and each gets an assertion rather than a
frame: `shading_mode` and the sort order against the flash quad. **Unshaded** — style rule 3 is
flat values, the flash's own material is `SHADING_MODE_UNSHADED` (`atmosphere.gd:261`), and a *lit*
puff would be the authored colour times the room's lighting, which would push the brightest channel
above the authored 0.2745 and invalidate the `GLOW_THRESHOLD` argument below. **Sort order:** two
transparent quads at the same anchor and the same depth, one `BLEND_MIX` and one `BLEND_ADD`, sort
by AABB centre, and nothing states which lands first. `render_priority` decides it and must be set
explicitly — smoke **behind** the flash, because the flash is the brighter, shorter event.

**And do not solve it by parenting the quad to the viewmodel.** `_measure()` sweeps authored
`gunart` corners and **never walks the scene tree** (`viewmodel.gd:939-945`), so smoke under
`WeaponMesh` or `ViewmodelRoot` would add geometry near the lens that `max_screen_radius()` cannot
see — the assertion would stay green while being false. With lateral terms weighted by ratio² =
2.096, a 5 cm quad is 25 mm of lateral half-width against 8 mm of total margin. The per-frame
re-anchor keeps smoke out of the hierarchy **by construction**, which is the point.

### The colour-space call, stated so nobody has to re-derive it

**Smoke is alpha-blended, is NOT a light contribution, and must be written as a DISPLAY-space value
with no conversion.** Constraint 6's *"a `BLEND_ADD` surface IS a light contribution and must be
converted"* does not apply, because smoke **occludes** rather than emits. And `atmosphere.gd:91-135`
already **measured** that `albedo_color` on a `StandardMaterial3D` is decoded by the engine — a
five-row sweep whose ratios (0.4890 against 0.500, 0.7115 against 0.750) are impossible if the value
reached the buffer unconverted — and states the conclusion: *"The engine decodes; the conversion the
rule demands is already made; this file must pass DISPLAY values and must not convert."*

So: write `Color(0.2745, 0.2510, 0.2275)` — that is `rgb(70,64,58)` from `html:2581` — straight, and
call **no** `srgb_to_linear`. Same posture as `FLASH_HOT` and as `gunart`'s `_tint`. This is the
exact confusion that shipped both black frames.

**It also cannot bloom, and it should not.** `GLOW_THRESHOLD` is 0.92 (`lighting.gd:209-215`) with
`glow_bloom` 0.0, so only threshold-passing pixels bloom. Smoke's brightest channel is 0.2745, and
`BLEND_MIX` can only pull a pixel *toward* that value. No action needed. **The failure mode to
reject explicitly** is making the puff `BLEND_ADD` to fake it catching the muzzle flash: that pushes
overlapping pixels across 0.92 and puts a bloomed grey blob on the muzzle. `fx.gd:613` uses
`BLEND_ADD` for sparks, which is right for sparks and wrong for smoke.

**One caveat the first draft did not state: the measurement at `atmosphere.gd:91-135` was made on
an UNSHADED material.** The decode happens on `albedo_color` either way, so the display-space call
holds regardless — but a *lit* puff would show the authored colour times the room's lighting, its
brightest channel would no longer be pinned at 0.2745, and the "it cannot bloom" argument above
would need re-deriving under a torch. **Unshaded, therefore, and asserted rather than assumed.**

### The smallest version that reads

**One persistent alpha-blended quad at the muzzle, driven by a single scalar heat accumulator,
re-anchored every frame.** Muzzle smoke and lingering barrel heat are one mechanism, not two: each
shot does `_smoke = maxf(_smoke, PUFF) + HEAT_GAIN` clamped to 1.0, and every frame does
`_smoke -= DECAY * dt`. A single shot reaches the `PUFF` floor and shows a brief wisp; sustained
fire accumulates past it and lingers after the trigger releases — which is the RPK/M16 read that is
wanted. Size and alpha are functions of `_smoke`. It reuses `atmosphere._halo_texture()` verbatim
(a white radial gradient with the whole falloff in alpha, already static, already shared).

**Where: `scripts/systems/atmosphere.gd`.** It already owns the muzzle, already owns
`flash_anchor`'s only caller, already has a counter-driven no-draw variation idiom
(`_flash_n` with `GOLDEN_ANGLE`), and — decisively — `checks/frame.gd:1113-1127` already asserts
that a `fired` listener spends **exactly one VISUAL draw and zero gameplay draws**, with a
**recorded control**: *"MEASURED: a second `Rng.randf(Rng.VISUAL)` added to `_on_fired` left the
suite 580 green and both flash captures unchanged."* Smoke placed there is protected for free.

**But `_process` is a structural edit, not a free amenity.** *Corrected 2026-08-02: the first draft
listed "already has the pausable `_process`" among the reasons, which is backwards.*
`atmosphere.gd:414-416` reads `func _process(dt): if _muzzle_t <= 0.0: return` and **the entire body
is inside that guard**. A smoke decay written after it freezes the instant `FLASH_TIME` (0.05 s)
elapses — the puff appears on the shot and then hangs on screen forever. The guard has to become
per-effect, or `_process` must return only when **both** clocks are spent. Check (c) in the smoke
assertion block below is precisely the check that catches this, and its control is `DECAY = 0.0`.

`fx.gd` gets none of that: `verify.gd:1005-1017` drives `p0.impact.emit` and `fx._on_surface_impact`
fifty times and **never emits `fired`**, so `fx._on_fired` (`fx.gd:864-872`) is unasserted for
stream purity. Anything hung off the `fired` path in `fx.gd` inherits no protection.

**Tally: +2 triangles, +1 draw call (only while `_smoke > 0`), +1 `StandardMaterial3D`, 0 textures,
0 particle process shaders, 0 `Shader` objects, 0 `Rng` draws, 0 clip-budget impact, 1 concurrent
quad at any fire rate.**

**Every constant in it is invented**: `PUFF` ≈ 0.25, `HEAT_GAIN` ≈ 0.05, `DECAY` ≈ 1.4/s, size
0.16 → 0.26 of screen height. Only the colour is sourced, and even that is **borrowed across
effects** — the ancestor uses it for explosions, not for muzzles. Per the provenance rule every one
ships with an explicit "this is our decision, and here is why", and they are tuned against a
rendered frame rather than adopted from this document.

### Do not share machinery with M5's brass

They look like the same architectural question and they are not. **The discriminator is coordinate
space.** Brass *must* be world-space — a casing that turns with the camera is absurd, and it has to
bounce off a floor that stays put; M5's R7 gives it a 2–3 s life with Euler integration and a bounce
coefficient. Smoke *must* be view-welded, with a 0.45 s life and no integration at all. They also
differ in primitive (a 24–32 slot MultiMesh of 12-triangle prisms versus one quad), in lifetime by
5×, and in owning file. Shared machinery would force one of the two into the wrong space. What is
genuinely shared is the constraint that neither may draw from an `Rng` stream, and the
counter-derived-variation idiom that answers it — **a three-line pattern, not machinery.**

---

## Recommendations

Ordered by value per unit of risk. R1–R4 are the package. R5–R7 are the rest of it. R8–R10 are
optional and R11 is not.

### R1 — Empty `SLIDE` for `ak74u` and `rpk`, and replace four comments with the real reason

**Decision.** `"ak74u": []` and `"rpk": []`. Rewrite the M14's, M16's, AK's and RPK's comments to
say: *the cycling part is on the model's +X side and the camera sees −X.*

**Provenance — mechanical, and it must be written in those words.** *Corrected 2026-08-02: the
first draft rested this on geometry, and the geometry does not separate the AK-74u from the MP40
(both overlap their receiver by exactly two units; only the RPK's strip is disjoint). The sentence
that carries it is:* **an AK's gas tube sits above the barrel forward of the receiver and is bolted
to it; an MP40 is straight blowback and has no gas system at all, so the same idiom cannot be a gas
tube there.** Without that sentence the next agent restores `"ak74u": [7]` by symmetry with the
MP40 and is arguing consistently. Geometry is corroboration and settles the RPK alone: part 8
(x10–24) is disjoint from the RPK's receiver (x26–52) — `gunart.gd:81-85`, re-read. Plus the
left-flank fact from `viewmodel.gd:171`/`:189` and `gunart.gd:277-278`. `gunart.gd:149`'s stated reason
for the M14 — *"the op-rod runs inside the receiver and is not drawn"* — is **wrong about the
mechanism**; an M14's op rod is external and runs along the right of the barrel. The verdict
survives; the reason must be replaced or the next agent adds the part.

**Cost.** Negative: two fewer `build_slide` meshes, two fewer `MeshInstance3D` surfaces, ~24 fewer
triangles, and two weapons drop out of the slide half of `_measure`'s corner set.

**Rejected alternative.** *Add a rear-mounted charging handle to both.* Twelve triangles, and
blocked on M5's R2 deferral of asymmetric extrusion: `_extrude` sweeps ±half
(`gunart.gd:699-700`), so the handle would appear on the visible **left** as well, putting a part
on an AK's left side that no AK has. **Off-reference, not merely off-budget.**

**Rejected alternative.** *Leave them, because removing motion from two automatics makes the guns
feel more static.* This is a judgement, not a finding, and it is the one place the reference and
the owner's report point opposite ways. Resolved in favour of the reference **plus brass**, because
brass is already scoped (M5 R7) and lands on exactly these weapons. If anyone prefers the
departure, **it must be recorded as a deliberate departure** — which is the rule the mystery box
exists to illustrate.

### R2 — Per-weapon travel, in art units, beside `SLIDE`, read through one accessor

**Decision.** A `TRAVEL` dictionary in `gunart.gd` between `SLIDE` (`:146-160`) and the
`# --- how big, and how thick ---` header at `:163`, quantised to whole art units, read through
`GUNART.slide_travel(key) -> float` returning metres, called by **both** `_slide_offset()` and
`_measure()`.

**Provenance.** The **M1911 floor is derived twice and both derivations exceed the ship**: a
self-loader's breech face must out-travel the cartridge it feeds; .45 ACP is 32.4 mm on a
210–216 mm pistol drawn 37 art units long, giving **5.55** and **5.7** against a shipped **4**
(`viewmodel.gd:399`, `gunart.gd:50-53`). Travel belongs in `gunart.gd` because it is a statement
about the art — how far a part can move before it hits the part behind it — and the collision
reasoning must live where the rects are. The precedent for a hand-maintained per-weapon table there
is `SLIDE` itself, two lines above.

**Numbers.** m1911 7, mp40 8, pm63 5, stakeout **9**, chinalake 8. *The Stakeout's 12.51
alternative was withdrawn as a units error — see the travel table.* The PM-63's 5 and the China
Lake's 8 are **departures below the cartridge floor forced by the drawn art** and must carry that
comment with the numbers in it (pm63: contact at 2, floor 2.55, 5 taken as an interpenetration the
proud strut conceals; chinalake: 8 units = 89.7 mm against a 98.4 mm grenade). Every mid-range mm
figure behind them is Tier 4; the method is what is durable.

**Two GDScript shapes, because this file has both hard parse errors in reach.** Declare
`TRAVEL` and `BOLT_HOLD` as plain literals — `const BOLT_HOLD := ["m1911", "pm63"]`, the shape
`ONE_HANDED` already uses at `gunart.gd:311`; `PackedStringArray([...])` is a *call* and a const
that is not a constant expression is a hard error. And at the sweep, annotate before passing:
`var travel: float = GUNART.slide_travel(key)` and then `_collect(slide, into, travel)`, never
`_collect(slide, into, GUNART.slide_travel(key))` — `viewmodel.gd:936-938` states the rule twelve
lines above the call site, *"a call through a preloaded script constant is the kind of expression
this project builds as an error when its result is handed to a typed parameter unchecked"*.

**Rejected alternative.** *Keep one constant and raise it to 7.* Fixes the M1911, breaks the China
Lake (pump into the pistol grip at 8) and the PM-63 (slide into the folding stock past ≈5), and
still gives a 37-unit pistol and an 86-unit machine gun the same stroke.

**Rejected alternative.** *Put it in `weapons.gd` beside `rpm`.* That file declares itself
*"ported verbatim from kriegsnacht.html section 4… engine-independent design data"*
(`weapons.gd:4-5`) and slide travel is invented (`gunart.gd:137-139`: the ancestor has no weapon
animation at all), so it would break the file's stated contract on its first new column. It is also
art-space geometry in art units, and `weapons.gd`'s TABLE is read by `balance_sim.gd`, so a cosmetic
column would widen the sim's data surface for nothing.

**The trap, and the only formulation that catches it.** `_measure()` hardcodes the global constant
as the sweep's second endpoint (`viewmodel.gd:945`, read: `_collect(slide, into, SLIDE_TRAVEL)`).
**A per-weapon table that does not land here too silently voids the no-clip guarantee.**

*Added 2026-08-02, because the first draft named this trap and then proposed no check for it — and
its own analysis proves that no aggregate check can.* Rearward travel moves a group **toward** the
grip, so `widest` **falls** with travel (m1911 0.154927 → 0.148561 at 12 mm), and the near plane is
set by a body part (the M14 stock), not by any slide. All three components of `_extreme` are
insensitive to slide travel **by construction**, and the only public readouts are `_extreme.x/.y/.z`
(`viewmodel.gd:856-878`). So line `:945` is unfalsifiable through the public API today — **deleting
it outright leaves the whole suite green** — and shipping a 7–9 unit table behind a stale 4-unit
sweep would be invisible.

**The fix is a structural readout.** Have the sweep record what it actually collected at:
`_swept: Dictionary` mapping weapon key → the travel it used (and, under R8, group → travel),
exposed as `vm.swept_travels()`. The assertion is
`vm.swept_travels() == {key: GUNART.slide_travel(key) for every key}`, read through the same
accessor `_slide_offset()` uses. **Control:** revert `:945` to the bare `SLIDE_TRAVEL` — the
dictionary comes back 0.0042 for all thirteen and the check fails. One accessor, two callers, and
one assertion that can tell whether the second caller exists.

### R3 — Open-bolt mode for the MP40 and PM-63

**Decision.** A `mode` field of `CLOSED` / `OPEN` / `PUMP` alongside `TRAVEL`. For `OPEN`: rest
offset = travel, and on the shot run forward to 0 over 0.7 of the cycle and back over 0.3 — the
time-mirror of the closed-bolt ramp.

**Provenance.** Both weapons fire from an open bolt; the PM-63's forward-firing cycle is confirmed
against a primary description. The existing asymmetry constant is right for the direction it was
written for — *"a slide is thrown by gas and returned by a spring"* (`viewmodel.gd:401`) — and
exactly backwards for a gun the spring drives forward.

**Why it is worth more than its size.** This is the one change on the roster that makes a weapon's
mechanism read as a *different mechanism* rather than as the same slide at a different speed. And
the MP40's handle is on the visible side, so it is the one place the change is guaranteed to be
seen.

**Cost.** Zero triangles, zero nodes, one branch. `_measure` is **unchanged**: the two endpoints are
the same pair, only the resting one differs.

### R4 — Delayed, interval-scaled rack for the pump guns

**Decision.** A `_pump_t` started by `fired` with a per-weapon delay, running back-then-forward,
instead of `_cycle_slide()` firing at the instant of the shot. Stakeout: start at 0.35 of the
interval, last 0.55 of it (0.145 s / 0.23 s at 145 rpm). China Lake: ≈0.25 s delay, ≈0.45 s duration
inside a 0.968 s interval.

**Provenance.** `viewmodel.gd:609` (read) and the intervals from `weapons.gd:31`, `:34`. Both
researchers agree the result should be delayed and longer; **they disagree about whether the
`fired` edge itself is the defect** (see the table's note). Either way it must be a timer, because
you rack after every shot, not only when you fire again.

**Why fractions and not seconds.** Expressing the delay and duration as fractions of the interval is
what keeps the stroke inside the window under Double Tap (Stakeout 0.309 s) without a second table.

**Cost.** One float and one branch. Zero triangles. The travel endpoint is already covered by R2.

### R5 — Make the automatics' cycle length their own shot interval

**Decision.** `cycle = 60.0 / (rpm * rate_mult)` for `auto` weapons; keep `SLIDE_TIME` for the
semi-autos. And note that a rise shorter than ~2 frames at 60 Hz cannot be seen.

**Provenance.** `viewmodel.gd:401-403`'s claim is false against the shipped table: the PM-63's
interval is exactly 0.060000 s and 0.044776 s under `DTAP_RPM_MULT` 1.34 (`game_state.gd:54`, read).
**This is our decision on the fix, and here is why:** for a self-cycling action the reciprocating
cycle time *is* the fire interval, so the fidelity argument and the engineering argument agree for
once. It also makes Double Tap visibly speed the bolt up.

**Rejected alternative.** *Accumulate rather than reset `_slide_t`, so a fast automatic compounds.*
Rejected on the file's own reasoning at `:398` (*"It is one float"*) and because at PM-63 rates it
saturates rearward within three shots and stays there. The right fix is a cycle short enough to
finish, not a longer one that stacks.

### R6 — Fix `_locked` per weapon, and fire it on an empty magazine

**Decision.** `_locked = BOLT_HOLD.has(_shown_key) and int(gun.mag) <= 0`, with
`BOLT_HOLD := ["m1911", "pm63"]`. `BOLT_HOLD` beside `ONE_HANDED` (`gunart.gd:311`), whose shape it
copies — a plain `Array` literal, because `PackedStringArray([...])` is a call and a hard parse
error as a const. *The PM-63 was cited 2026-08-02 (Wikipedia `FB PM-63 RAK`: "after the last
cartridge has been fired from the magazine, the slide is locked open on the slide catch"), so it
ships rather than waiting; A6 gets a PM-63 half.*

**Provenance.** Two independent defects. **Correctness:** the current code pins the group fully
rearward for all seven weapons with a `SLIDE` entry (`viewmodel.gd:809-812`, read), and five of them
have no hold-open. On the MP40 it is a *double* inversion. **Reachability:** `EMPTY` is
`mag <= 0 and res <= 0` (`weapon.gd:238-243`), so on the one weapon the lock is right it never
appears on an empty magazine. BO1 shows the M1911's slide locked on every empty magazine and
releases it in the reload; the reference wins.

**Cost.** Zero. `_tick_states` already holds the gun dictionary (`viewmodel.gd:690`), so `gun.mag`
costs nothing and no signal or `player.gd` change is needed. It strictly *reduces* the time any
group spends at full travel, so `_measure`'s bound is unchanged and still conservative.

### R7 — Muzzle smoke and barrel heat as one quad in `atmosphere.gd`

**Decision.** As specified under *Smoke*. One persistent quad, one heat scalar, re-anchored every
frame through `flash_anchor`, `BLEND_MIX`, `SHADING_MODE_UNSHADED`, `no_depth_test = true` with an
explicit `render_priority` behind the flash, display-space colour, no `Rng` draw. **And it is not a
drop-in beside the flash:** `atmosphere.gd:414-416`'s `_process` early-returns on the flash clock,
so that guard becomes per-effect. Six assertions, not two — see *How this gets tested*.

**Provenance.** Colour `rgb(70,64,58)` from `html:2581` (read), **borrowed across effects and
commented as such**. Everything else is invented and says so. The placement argument is
`checks/frame.gd:1113-1127`'s existing exactly-one-VISUAL-draw assertion, which protects the
`fired` path in `atmosphere.gd` and does not protect it in `fx.gd`.

**Rejected alternative.** *A `GPUParticles3D` one-shot pool, as `fx.gd` does for dust.* +1 process
shader compiled on the main thread every page load, plus bespoke `warm()` coverage nothing asserts,
and it cannot share `FAM_DUST`'s material because gravity lives there.

**Rejected alternative.** *Place the puff once at `flash_anchor` and let it drift.* It shears off
the barrel at the camera's angular rate, which is a far larger term than the drift.

**Rejected alternative.** *Parent it to `WeaponMesh`, or give it the viewmodel's `VM_CODE`
projection.* Voids the no-clip guarantee silently (`_measure` never walks children) **and** violates
style rule 4 — a screen-space treatment applied to the weapon and to nothing else in the room.

### R8 — Generalise `SLIDE` into an n-group mechanism (only if a second group ships)

**Decision.** `group_names()` / `group_map(key)` / `build_group()` / `group_corners()`, the empty
`StringName` meaning the body, with the four current accessors kept as wrappers. `sight_height()`
becomes a **union over all groups**.

**Provenance.** Four independent "body plus slide" walks that must agree, and `gunart.gd:388-394`'s
record of what a missed one costs (the M1911's sight line 13 px through the crosshair). Magazines
are never the topmost part, so a mag group is safe **by luck**; a `pump`, `bolt` or `hinge` group
could take the top edge with it and narrow every weapon's ADS pose behind everyone's back.

**Cost.** Zero triangles. +1 draw call per animated group on the weapon in hand. +2 prebuilt meshes
per weapon per group (39 commits today). `_measure`: **+8 corners per pose** on each weapon that
gains a group — a magazine group on five weapons is +5,760 points of 218,016, **+2.6%**. Compare a
new *pose channel* at +218,016, **+100%**. That asymmetry is the existing design's best property and
the generalisation must preserve it.

**Rejected alternative.** *A second hand-written index table beside `SLIDE`.* `SLIDE` has no bounds
check (`SLIDE.get(key, [])` at `:444`, `slide.has(i)` at `:452` and `:485`) and no assertion
anywhere: an index past the end of a weapon's `ART` matches nothing, `_build` returns null, and
`_show` sets `_slide.visible = false` (`viewmodel.gd:836`) — **the weapon loses its bolt in
silence.** A second table doubles a known-defective pattern.

### R9 — Find the magazine by a function, and settle the identity question first

M5's S2 forbids a hand table. Two researchers proposed rules and they **contradict each other**:

- **Colour rule.** `#1F2123` appears exactly six times in `ART`; five are magazines and the sixth is
  the M1911's 10×4 part 2, which any "taller than wide" test throws out — a **2.6× discriminant**.
  Result: `mp40 2, pm63 2, ak74u 2, m16 3, rpk 2`, −1 elsewhere. Provenance is the ancestor's own
  convention.
- **Position rule.** The `#1F2123` rect sits at the **grip anchor** on all five (`GRIP.ak74u` =
  (47,31) against part 2 at x44–50; `GRIP.rpk` = (49,31) against part 2 at x46–52), and the drawn
  glove sits on it — so it is the **pistol grip**, and the magazine is the second hanging rect
  forward (`ak74u` part 5 at x30–39, `m16` part 6 at x34–42). The RPK is the decider: parts 5 + 6
  are unmistakably its **drum**, and a drum RPK has no box magazine.

The proposed settling test was the ancestor's own drawing code. **I ran it, and it does not settle
anything:** `kriegsnacht.html:1150-1210` is `const GUNART` with **zero `//` comments** in the whole
block (I counted: 0) — bare arrays, and byte-identical to `gunart.gd`'s `ART`. The only comment is
`:1150`, about the 100×60 space.

**So the magazine's identity is genuinely undecided, and it decides whether M5 F10's `ak74u part 2`
and `rpk part 2` attributions are right.** Nothing in M6's verdicts turns on it — it affects only
the reload column. **Resolve it with `--shot` on a magazine-drop prototype before writing the
predicate**, and record the reading as a decision either way.

### R10 — Reduce `ADS_YAW` below 1.0

**Decision.** One float at `viewmodel.gd:336`, then re-measure.

**Provenance.** The measured sub-pixel collapse above, against `viewmodel.gd:180-188`'s own
docstring, which states the reason for the yaw and is then zeroed at the pose where the player
studies the weapon. `viewmodel.gd:187-188` states that a rotation about the grip cannot move a
corner further from the grip, and `_measure` sweeps ads at both endpoints (`:961`), so the sighted
extremes stay inside the hip ones **by construction**.

**Why it is listed here and not higher.** It is one float and zero cost — but it moves three
hand-measured frames-gate numbers at once: `ads.probes.gun_cx_over_centre` (banded [0.985, 1.015]),
`sight_top_over_centre`, and `VM_RECT_ADS` (`shot_setup.gd:191-192`). `-Bless` rewrites only
`scenarios`, so **the relations must be re-argued rather than adopted**, and the header's 0.231884
was measured with `ADS_YAW` at 1.0. It is cheap to make and expensive to land.

### R11 — Close the two blind spots before retuning anything. Not optional.

This whole area is unbounded in both defences, and per the project's own rule a reported hunk
without a failing check gets dropped silently. **R11 ships before or with R1–R6, not after.** See
*How this gets tested*.

### R12 — Interior-sample the four rotational channels `_measure()` already sweeps at endpoints

*Added 2026-08-02. This was in the first draft as a finding with no recommendation and no
assertion behind it, which is how a finding gets dropped.*

**Decision.** Apply the circumscribed-polygon construction above to **`dip`, `ads`, `kick` and the
gun `melee`** — the four channels that enter `_mesh_pose`'s basis — not only to a hypothetical
hinge. Sample K+1 angles across each arc, scaled radially about the pivot by 1/cos(step/2). K comes
from the closed form `ratio · r_max · (1 − cos(step/2)) ≤ 0.0002 m`: K = 4 for the dip's 0.5 rad at
r = 0.06 m, K = 1 for the ads channel.

**Provenance.** The geometry is provable, not measured, and I checked it: samples at radius
r/cos(step/2) give chords tangent to the arc, the arc lies inside the hull of the samples, and
`worst`/`widest` (norms, hence convex) and `nearest` (linear) all attain their extremes at hull
vertices — so the result is a **guaranteed over-estimate**, which is the only direction a safety
assertion may err in. Against that, `viewmodel.gd:903-906`'s *"a dense sweep does not beat the
endpoints by more than 0.2 mm"* is a measurement nothing re-runs.

**Assertion, and it is what gives the arc sampler a live consumer.** `max_screen_radius()` under
the interior-sampled sweep is **≥** the endpoint-only value, and the gap is **≤** the closed-form
bound `ratio · r_max · (1 − cos(step/2))`. Control: revert the ads and dip loops to two endpoints —
the reported extreme must **drop**. Bounded at both ends, driven through the real `_measure()`.

**Cost.** `_measure()` is 218,016 points today. K = 4 on `dip` and K = 1 on `ads` multiplies the
pose loop by 5/2 × 2/2 ≈ 2.5×, so ~545,000 points, still one call from `verify.gd` and still
cached. **Why it is worth it:** R10 is *"one float at `viewmodel.gd:336`, then re-measure"*, and
"re-measure" is only a defence if the measurement covers the arc that float controls.

**Why it is not blocking.** If `:903-906`'s measurement is right, the guarantee holds today. R12
converts "holds by measurement" into "holds by construction", which is what the rest of `_measure()`
already is.

### Listed and not recommended

**The Olympia break-open** as a rotational channel, hinging during the reload and throwing the
**fired** hulls. It is canon, it is the only weapon whose entire animation is a reload motion, and
it is the visible half of M5's R5.

**The group and the pivot are unsettled, and the first draft's own two excursion figures imply two
different pivots.** *Corrected 2026-08-02.* On a break-open gun the barrels and the rib attached to
them rotate about a pin carried **by** the receiver; the receiver stays with the stock and the hand.
Part 2 is brown `4b3218` at x60–70 and `GRIP.olympia` is (62,26) — that is the **wrist under the
shooting hand**, not the receiver. The only grey metal mass is **part 5**, `["r",44,21,10,10,
Color("3a3d40")]` (`gunart.gd:56`), and its identity decides everything:

| if part 5 is… | group | pivot | muzzle radius | tip excursion at 25° |
|---|---|---|---|---|
| the receiver / standing breech | {0, 1, 6} | its **front face**, x = 54 | 48 units = 50.4 mm | **21.3 mm** |
| the fore-end iron | {0, 1, 5, 6} | behind it, x ≈ 64 | 58 units = 60.9 mm | **25.7 mm** |

The first draft asserts {0,1,5,6}, then quotes *"the barrel group is 58 art units long, so a full
break sweeps the muzzle ~36 mm down"* (r = 58 units, θ ≈ 36°) in one place and *"~21 mm of lateral
tip motion at 25°"* in another — and 21 mm at 25° requires r ≈ 48 units. **Two pivots, one
document.** Arguing for the receiver: `3a3d40` is this file's generic metal (it is also the MP40's
bolt handle and the AK strip), the position x44–54 sits at the breech, and its y21–31 spans **both**
barrels, which a fore-end under them would not. Arguing against: the breech of an over/under sits
just forward of the wrist, around x58–64, and x44–54 is forward of that. **Settle it before any
excursion number is used, because the excursion is what the verdict is computed from.**

It is **not recommended in this package** because it carries two independent ceilings that land in
the same place. Budget: at the larger pivot a full break sweeps the muzzle ~36 mm down and ~12 mm
toward the lens — the largest excursion anything here proposes against 7.5 mm of near-plane margin,
and the barrel tip is exactly the corner that sets the guarantee. Style: `KEY_DIR` is baked in
**model space** on purpose (`gunart.gd:275-279`, read: *"the shading then stays put as the weapon
moves, which is what makes it read as painted-on"*), so a face rotated 30° is 3.7% off its live
value — half M5's visible bracket — and one rotated 90° is 7.6% off, **a whole bracket**. So a
*hinted* hinge at ≤ 0.25 rad is in style and a fully broken action is not, and **that is a style
rejection, not a cost one.** If it is ever built it needs the circumscribed-arc sweep (K = 2 at
0.25 rad, excess 0.055 mm) and a re-run of `_measure`, which is the only authority.

**The Thundergun's two lights** darkening across its 2-round magazine. Canon (Tier 4 fan wiki, and
the colours disagree — canon red, ours cyan `#7adff0`), and the ART already drew exactly two emitter
circles at the muzzle end without knowing it (`gunart.gd:97`). Not recommended: the mesh is free but
it breaks `_corners(key, want_slide)`'s binary filter, which four callers and three assertion suites
read through — **that API change is the real cost**, and it is R8's cost paid for one weapon. If R8
lands anyway, this becomes cheap. **Rejected outright:** rebuilding the ArrayMesh per shot to change
two vertex colours — a `SurfaceTool.commit()` inside the fire path, on a weapon whose whole point is
being fired in a panic.

**Idle breathing.** *Mechanism corrected 2026-08-02 — the first draft said "folded into
`_mesh_pose`'s origin the way `bob` already is (`viewmodel.gd:918-920`)", which conflates two
different mechanisms and would silently void the guarantee if implemented as written.* `bob` is
**not in `_mesh_pose` at all**: it is a `ViewmodelRoot` write at `viewmodel.gd:765-766`, and
`_measure()` accounts for it by adding a **scalar bound** to the lateral term of each metric
(`:920` computes it, `:968-969` add it). `_mesh_pose` is `:780-805` and contains no bob term. So
breathing costs **zero swept points only if it is bounded the same way** — `bob` becomes
`Vector2(BOB_X, BOB_Y).length() + BREATHE_AMP` at `:920` — and costs **+100% of the sweep** if it is
written as a channel of `_mesh_pose`. A term added to `_mesh_pose`'s origin without either
treatment is inside the swept function and covered by **nothing**. The interesting result is
that **the clip budget is not what bounds it**: a whole-mesh translation costs at most ratio·|delta|,
so 8.116 mm buys 5.6 mm, while the frames-gate probe rect tolerates ~9.8 rows of drift
(1041 px of tolerance over 106 px of weapon per row) and `VM_RECT_HIP` already crops the bottom —
so the gate binds first, at roughly **1.7 mm**. Deferred to an idle package, not because it is
risky but because the period and amplitude must be **our decision with the reasoning attached**, and
nobody has looked at a frame.

---

## What this costs the clip budget

Current worst is `max_screen_radius()` = 0.232 m against `Player.RADIUS` 0.240 —
**8.116 mm** — with the swept figures 0.201249 / 0.057540 / 0.231884 quoted at `viewmodel.gd:169`.

**The single most important correction in this section: that 8.116 mm is not a global allowance.**
`max_screen_radius` is a max **over points**, set by one corner — a barrel tip or a stock tip — so a
group whose own corners sit far from that extreme has its own, much larger slack. Rest-pose
estimates in the widened metric: the MP40's magazine ~0.147, the Stakeout's pump ~0.166, the
Olympia's barrel tip ~0.188, against a swept global worst of 0.2319. **Sizing a magazine's travel
against 8 mm is wrong by an order of magnitude; sizing a break-action barrel's against it is right.**
The two failure modes are symmetric: rejecting a 20 mm magazine drop that was always safe, and
admitting a 6° hinge that was not.

| proposal | triangles | draw calls | `_measure` points | clip verdict |
|---|---|---|---|---|
| R1 empty two rows | **−24** | −2 | −2 weapons' slide corners | strictly improves |
| R2 per-weapon travel | 0 | 0 | unchanged (same two `_collect` calls) | **improves.** Rearward travel moves the group toward the grip, so `widest` **falls**: m1911 0.154927 → 0.148561 at 12 mm; mp40 0.162125 → 0.155620; rpk 0.166490 → 0.159900. Nearest slide-corner depth at 16 mm is 0.0946 m against a 0.05 m near plane and a measured global minimum of 0.057540 — **the near plane is set by a body part (the M14 stock), not by any slide.** Travel to at least 16 mm costs nothing |
| R3 open bolt | 0 | 0 | unchanged (same endpoint pair) | none |
| R4 pump delay | 0 | 0 | endpoint covered by R2 | none. Stakeout pump at 9 units back reaches art x45 against the receiver at x56 — no new extreme |
| R5 cycle length | 0 | 0 | 0 (timing never moves an endpoint) | none |
| R6 `_locked` | 0 | 0 | 0 | strictly reduces time at full travel; bound unchanged and still conservative |
| R7 smoke quad | +2 | +1 while alive | **0** | **none — the node is a child of `atmosphere.gd` at the world origin, never of `ViewmodelRoot`.** This is why the per-frame re-anchor is load-bearing and not merely tidy |
| R8 n-group | 0 | +1 per group | +8 corners per pose per weapon that gains one (+2.6% for a mag group on five) | none by itself |
| *Olympia hinge* | 0 | +1 (one weapon) | +72 corners per pose at K = 4 (+4.8%) | **the one proposal that can break it.** ~21 mm of lateral tip motion at 25°, weighted by ratio² → ~30 mm against 8.116 mm. Not recommended |
| *breathing* | 0 | 0 | **0 if folded like `bob`**, +218,016 if swept as a channel | 5.6 mm affordable; the frames rect binds first at ~1.7 mm |

**Two traps that must not be reasoned around.**

1. `_measure()` hardcodes `SLIDE_TRAVEL` as the second endpoint (`:945`). **Per-weapon travel must
   land there through the same accessor**, or the guarantee is void while the assertion is green —
   and **no aggregate metric can tell you whether it did**, because all three of `_extreme`'s
   components are insensitive to slide travel by construction. That is what `vm.swept_travels()`
   (R2, A8b) exists for; today, deleting `:945` outright leaves the whole suite green.
2. **A rotating channel makes endpoint sampling unsound**, and **four shipped channels are already
   in that position** — `dip`, `ads`, `kick` and the gun `melee` — with up to 2.7 mm of analytic
   interior excess on the dip alone. Any rotation added here needs the circumscribed-arc
   construction, and the four existing sweeps need it too: that is **R12**, and it is the reason
   R10's "one float, then re-measure" is only a defence once the measurement covers the arc.

None of these figures was measured. `_measure()` did not run. **The Olympia's 36 mm is hand-derived
and the rest-pose per-group numbers understate by roughly the ~44 mm that poses add.**

---

## How this gets tested

The state of play, verified: `grep -rn 'SLIDE_TRAVEL|_slide_offset|_cycle_slide|_locked'
scripts/dev/` returns **zero lines** (I ran it). The only slide reference anywhere in `scripts/dev`
is `checks/projectiles.gd:837`, which reads `GUNART.slide_corners(key)` for a top-edge walk and
applies `vm._mesh.transform` only, **never the slide's own offset** — so
`projectiles.gd:738`'s live assertion ("the M1911's sight height comes off its slide and not just
its body") would keep passing with every row of `SLIDE` emptied but the M1911's, and with travel at
zero.

### Headless — `--verify`

New file `scripts/dev/checks/animation.gd`, registered **after** `_viewmodel(main)` (`verify.gd:262`)
because `_measure` caches its FOV ratio on first call. The registration lines are a **reported
hunk**, and that hunk enforces itself: a new checks file on disk without them turns `--verify` red.

**Five of the twelve rows in the first draft had controls that did not fail the check they were
named for.** Each is corrected below with the arithmetic that condemned it, because "add a control"
without the arithmetic is how the same row comes back.

| # | assertion | the exact sabotage that must fail **that** check |
|---|---|---|
| A1 | **`SLIDE` equals a table written into the check, one provenance line per row.** *Rewritten 2026-08-02.* The first draft asserted "every index in `SLIDE` names a part whose art rect overlaps that weapon's receiver in x", with the control "restore `\"ak74u\": [7]`" — **and it overlaps.** AK-74u part 7 is x18–26 (`gunart.gd:72`) against receiver x24–50 (`:70`): two units. MP40 part 6 is x18–28 against x26–56: also two units. The predicate scores the row it deletes and the row it keeps identically, so the control leaves it green. Only the RPK (part 8 x10–24, receiver x26–52) is disjoint. **Assert the decision instead:** `ak74u: []` — *the drawn strip is the gas tube; an MP40 has no gas system so the same idiom cannot be one there; the cycling part is on model +X and the camera sees −X.* | Change **any** row of `SLIDE`. This one does discriminate, and it is honest about being a pinned decision rather than a discovered law. |
| A2 | **Direction, driven through the real path.** Set the driving gun to a **non-EMPTY** state first — `_tick_states` sets `_locked = state == WEAPON.State.EMPTY` (`viewmodel.gd:726`) and `_slide_offset()` short-circuits to full travel (`:809-812`), so an EMPTY test gun makes A3's "zero at rest" half fail for an unrelated reason. Then `vm._on_fired(Vector3.ZERO)`, `vm._tick_states(1.0/60.0)`, `vm._apply()`, read `vm._slide.position`. Assert `x == 0 and y == 0`; assert `z > 0`; assert **`sign(displacement.z) == -sign(GUNART.muzzle_local(key).z)`** — the group moves away from the muzzle end. | Flip the sign at `viewmodel.gd:817`. **Expected value anchored to the ancestor's `MUZZLE` table (`gunart.gd:111-117`, from `html:2020`), not to the implementation's own constant.** *The first draft's third clause demanded the displacement be **antiparallel** to `muzzle_local`, which is false against correct code on all seven weapons: the displacement is pure model +Z while every muzzle sits above its grip, so the angle is m1911 9.46°, stakeout 9.27°, ak74u 8.32°, rpk 7.27°, chinalake 7.13°, mp40 6.48°, pm63 6.34°. Written strictly it fails; written with a tolerance loose enough to pass it asserts nothing the first two clauses have not already pinned exactly. The sign test is exactly true and keeps the ancestor anchor.* |
| A3 | **Bounded at both ends:** zero at rest **and** non-zero one frame after a shot. | Make `_cycle_slide()` a no-op. Without the acceptance half, A2 passes against a rig whose slide has stopped moving entirely. |
| A4 | **Open bolt:** the MP40's offset at rest equals its travel and **decreases** on the first frame after a shot. | Set its mode to `CLOSED`. Must fail the MP40 check and leave the M1911's green. |
| A5 | **Pump delay:** the Stakeout's offset is **still zero** at the frame after the shot and non-zero later in the interval. | Restore the immediate `_cycle_slide()` at `viewmodel.gd:609`. |
| A6 | **Bolt hold-open, driven to the state the *player* reaches.** Fire the M1911 dry through `player`'s real fire loop, then read `vm._slide.position` — not by setting `gun.mag` directly, which is the getter and not the consumer, and which cannot catch `mag` reaching 0 before `_shown_key` has been latched (`_show` only runs when the mesh changes, `viewmodel.gd:824-828`). Then the same on the MP40, asserting **zero**, and on the PM-63, asserting **travel**. | Put `"mp40"` into `BOLT_HOLD`. The MP40 half must fail and the M1911 and PM-63 halves must not. |
| A7 | **Travel bounded at both ends, with the free run COMPUTED and not pasted.** Assert `floor ≤ TRAVEL[key] ≤ free_run(key)`, where only the floor is hardcoded (with its cartridge and its scale in the comment) and `free_run` is computed from `ART` through GUNART: the minimum over non-slide parts that do **not** already overlap the group at rest, whose y-span and `BASE_HALF + i·LAYER` depth range intersect the group's, of the x-gap between the group's trailing edge and that part's leading edge. *Rewritten 2026-08-02: the first draft pasted a free-run column the document itself flagged as unverified, and that column was measured to the grip **anchor** rather than to any part — Stakeout 16.92 where the grip panel gives 14, China Lake 9.76 where the pistol grip gives 8, PM-63 −4.04 where the strut gives 2.* | Set the M1911 back to 4 (floor half). Set the China Lake to 12 — it must fail on the pistol grip (acceptance half). This turns the three "arithmetic-only collisions" from an unanswered `--shot` request into a standing assertion. |
| A8a | **Refusal: `max_screen_radius()` is unchanged to six decimals** against the committed 0.231884 (`viewmodel.gd:169`). | A group whose travel is deliberately huge. |
| A8b | **Acceptance: `vm.swept_travels()` enumerates every name in `GUNART.group_names()` for every weapon**, and every value equals `GUNART.slide_travel(key)`. | Drop one `_collect` call, or revert `:945` to the bare `SLIDE_TRAVEL`. *Split 2026-08-02: the first draft's single A8 asserted a null result, so a group that is **not in `_measure()`'s corner pool at all** — the exact hazard R8 and the file header exist to prevent — changes nothing and passes under its own sabotage. A refusal cannot separate "safe" from "unmeasured"; only the readout can.* |
| A9 | **The arc sampler is conservative, AND it is the one `_measure()` calls.** Unit half: feed it a known arc against a dense reference; feed it a straight line and require the inflation to degrade to identity; remove the 1/cos and require the arc case to fail. Consumer half (**R12**): `max_screen_radius()` under the interior-sampled sweep is ≥ the endpoint-only value and the gap is ≤ `ratio · r_max · (1 − cos(step/2))`. | Revert the `ads` and `dip` loops to two endpoints — the reported extreme must **drop**. *The first draft's A9 had unit halves only, and its sampler existed solely for an Olympia hinge the document does not recommend — so a sampler that is perfectly correct and never called by `_measure()` passed it. That is the project's own "projectile tunnelling test that passed with the sweep deleted".* |
| A10 | **Segmented reload cycles once per shell:** drive a real six-shell Stakeout reload and **count group cycles**. Consumer-driven. | Delete the per-shell latch. And separately: gate the latch on the *current* frame's state instead of the previous frame's — it must report **five**, catching the settle-before-emit trap. |

**Smoke needs six checks, not two, and here is the construction that proves it.** *Added
2026-08-02.* Build the inert case: `_on_fired` never touches `_smoke`, the quad is created and never
made visible, the material is created and registered. Against the first draft's A11 and A12 —
which were the complete smoke plan — **every assertion passes**. A11 ("zero `Rng` draws, exactly one
VISUAL draw") passes trivially, because an effect that does nothing spends nothing. A12 passes,
because the material is registered. This is not hypothetical on this file: `atmosphere.gd:438-445`
records the burst quad shipping in exactly that state — *"the art was covered, the material was
covered, and the one thing between them, whether the layer ever reaches the screen, was covered by
nothing"* — `--verify` 580 green and no failed relation.

All six run **headless**, built on the shape `checks/frame.gd:1141` already uses (`_fire_once`
blanks both quads, emits `main.player.fired`, and reads `visible` plus a basis-column length off the
live node):

| # | assertion | control that must fail **that** check |
|---|---|---|
| A11 | **Zero gameplay `Rng` draws and exactly one VISUAL draw on `fired`.** Extends `checks/frame.gd:1113-1127`, which carries a recorded control. | Add a `Rng.randf(Rng.VISUAL)` to the smoke kick. |
| A12 | **The material the renderer was handed is in the declared list:** `atmosphere.materials().has(atmos.smoke_quad().material_override)`. Consumer-driven off the live node, the way `flash_quad()` / `burst_quad()` already are. | Delete the smoke material from `materials()`. *Rewritten 2026-08-02: the first draft asserted "the smoke material is registered in `atmosphere.materials()`" with the control "unregister it — `verify.gd:1049-1052` already catches this class". **It does not.** `verify.gd:1039-1052` builds `wanted` from the declared accessors and `seen` from the warm pass, then reports members of `wanted` missing from `seen`. A material never declared is never in `wanted` and never missed — and `main.gd:174` feeds the warm pass from the same accessor, so it is absent from both sides. **M5's F32 carries the same wrong claim** (`M5:603-605`, "a new material missing from `fx.materials()` fails `verify.gd:1050`") and should be corrected there too.* |
| A13 | **It draws.** The quad is invisible before the shot and visible with a non-zero basis-column width one `_process` step after. | `PUFF = 0.0`. |
| A14 | **It animates.** Size and alpha are monotone over the first N steps. | Pin size to a constant. |
| A15 | **It goes away.** Invisible again after `1.0/DECAY` seconds of stepped `_process`. | `DECAY = 0.0`. **This is also the check that catches the `_process` early-return trap** at `atmosphere.gd:414-416`. |
| A16 | **Heat accumulates.** Twenty shots at the PM-63's 0.06 s interval produce a strictly larger peak size than one shot. | `HEAT_GAIN = 0.0`, which must fail A16 and leave A13–A15 green. *Without this the one thing separating R7 from "a puff" — that sustained fire accumulates past the single-shot floor — can be zero and nothing notices.* |
| A17 | **The per-frame re-anchor, which is the load-bearing idea in the whole smoke design.** Fire, step, record `smoke_quad().global_position`; yaw the camera 90°, step one frame, assert the position equals `viewmodel.flash_anchor(dist)` to 1e-6. | Hoist the anchor out of `_process` so it is computed once. **Without A17 the rejected "place it once and let it drift" alternative and the recommended design are indistinguishable to the suite.** |
| A18 | **The material's four decisions, as properties rather than pixels:** `blend_mode == BLEND_MODE_MIX`, `shading_mode == SHADING_MODE_UNSHADED`, `no_depth_test == true`, `render_priority` behind the flash, and `albedo_color == Color(0.2745, 0.2510, 0.2275)` to 1e-4. | For the blend clause, set `BLEND_MODE_ADD` — the document names that as the failure mode to reject and the first draft proposed no check for it. For the colour clause, wrap it in `srgb_to_linear()`: the value drops to ≈(0.0612, 0.0513, 0.0423) and the check must fail. *This is the exact confusion that shipped both black frames, and it was called out in prose with nothing behind it.* |

**`ASSERTION_FLOOR`** (`verify.gd:166`, currently **692** — that is the true total, not a stale
floor: `notes/analysis/2026-08-02` records "680 → 692, raised additively") rises **additively**, and
the delta must be **named** rather than left to "whatever lands", because the floor is a `>=` and
under-raising it is silent. Counting the rows above — A2 is three asserts, A4/A5/A6/A7/A8/A9 are
matched pairs, A11–A18 are eight — **the estimate is +30**. And the raise ships with its own
paragraph in the docstring at `verify.gd:150-165`, in that file's voice, saying what it bought;
every previous raise on that const carries one. Do not reconcile while other work is in flight.

**Nothing here covers `Settings.reduce_motion`, and this package widens that gap.** Coverage gap 6
establishes that the viewmodel has no `reduce_motion` path at all while the camera has two
(`player.gd:709`, `:834`). This package adds a reciprocating group on seven weapons, a pump stroke,
and a persistent smoke quad, **all of it exempt from the accessibility toggle**. That is recorded
here as a **decision deferred to an accessibility package**, not as an oversight — but it is a
decision, and a package that widens a gap and does not name it has made it silently.

### The frames gate

Both halves of the defence are blind here and for different reasons. New scenarios go in
`shot_setup.gd`, a file this package does not own — a reported hunk, and **a bigger and more
dangerous one than the first draft implied.** *Corrected 2026-08-02.*

**A new scenario is five edit sites, not one:** the registry entry (`shot_setup.gd:292`),
`probes_expected()` (`:774`), the `probe()` match arm (`:788`), `silhouette_expected()` (`:814`) if
`gun_px`/`gun_cx` are wanted, and a probe rect. And **the moment the registry entry lands,
`--verify` turns RED for everyone** — `checks/frame.gd:20-27` asserts that the golden file carries a
row and a reference PNG for every registered scenario, and says so in its own words: *"A scenario
added here and never photographed shows up as a red assertion rather than as silence."* Clearing
that needs a windowed `tools/frames.ps1 -Bless`, which cannot be done from a headless run.

**So the scenario hunk and the bless are ONE ATOMIC STEP in a windowed session.** "A reported hunk
is not done until it lands" understates this: between landing and blessing, the hunk breaks the
suite for every other agent. And a new gun-probe scenario needs **its own rect** — `VM_RECT_HIP`
(`shot_setup.gd:191`) was sized for a settled hip pose, and a one-frame-after-the-shot capture is a
different pose.

The scenarios:

- **`slide_back`** — a weapon one frame after a shot, with `gun_*` probes, so the displaced group is
  photographed. Today no scenario has both: `flash_hip`/`flash_ads` fire and carry only `flash_*`;
  `spawn`/`ads` carry all seven `gun_*` and never fire. **I parsed `golden.json` and confirmed both
  probe lists and the 24 relations.**
- **`sustained`** — a held automatic, for the barrel-heat half of R7, which otherwise has no capture.
  **It has no probe and no relation yet, and one must not be committed until `PUFF` has been swept
  and tabulated.** The `rim_mean / body_mean` precedent applies with force here: a translucent grey
  puff over a grey wall is exactly the subject a luminance-mean probe reports as noise. A blessed
  row with a metric nobody checked is a row that discriminates nothing.
- **`empty_mag`** — for A6's pose, which no scenario captures.
- **`reloading`** — for A10, which no scenario captures.

**Prefer a ratio.** The rule that survives a retune is *slide displacement / slide on-screen length*,
per weapon, not an absolute pixel count — absolute brightness and absolute geometry both drift with
every tuning pass. Each new `relations` rule carries its own provenance line.

**And check the metric before trusting it.** The `rim_mean / body_mean` precedent is the warning:
sweep the travel constant, tabulate the probe, and only then decide what the number means. A
silhouette-centroid metric in particular may be non-monotone in travel, because the group moves
mostly in **depth**.

### The human eye

*Three items came off this list on 2026-08-02, because they were instrument errors: two are
closed-form headless arithmetic and one was a units error. A list of things that need a human eye
is only useful if everything on it actually does.*

- ~~The 3× pixel-calibration disagreement~~ and ~~the hip-versus-ADS collapse~~ — **both are the
  same closed-form projection and belong in `--verify`.** `viewmodel.gd:128` pins the vertical
  half-angle at 27.5° whatever the camera's FOV is, so the pixel figures are determined by
  `GUNART.slide_corners`, `_mesh_pose` and one shader constant. Assert them; photograph them as a
  cross-check if someone is in a windowed session anyway.
- ~~The three arithmetic-only collisions~~ — **A7 computes the free run from `ART` and asserts it**,
  so the PM-63's contact at 2, the China Lake's at 8 and the Stakeout's clearance are standing
  checks rather than an open `--shot` request. What is left for the eye is narrower and is the next
  bullet. (The Stakeout's 12.51 is gone: it was a units error, not a candidate.)
- **The PM-63's recorded interpenetration, specifically.** A7 asserts the *number*; only a frame
  says whether a slide disappearing under a proud stock strut reads as stacking or as a bug. This is
  the one genuinely visual item of the three, and it is visual precisely because the arithmetic says
  it will be concealed rather than shown.
- **Whether a longer travel leaves the `LAYER`/`PROUD` depth ordering intact** as a group slides
  rearward over a part with a higher index and therefore greater half-depth. Arithmetic says yes;
  only a frame answers it.
- **The smoke, entirely.** Every constant in R7 is invented and every performance figure is
  projected, not measured.

### What cannot be asserted, said out loud

- **"Does it feel static."** No pixel statistic separates a well-timed reciprocation from a badly
  timed one. This is the same wall `enemies.gd` hit on the zombie arm pose, where four metrics were
  tried and none discriminated. What can be asserted is direction, magnitude, event, and the
  *ratio* of displacement to on-screen length — not the read.
- **Whether removing the AK's and RPK's motion is right for feel.** It is a judgement between the
  reference and a player report. Assertions can pin the decision; they cannot validate it.
- **Frame time.** `frame_stats.gd`'s `mean`/`median`/`p01`/`p99` are **luminance percentiles, not
  milliseconds**, so the frames gate cannot catch an effect that is beautiful and slow. The only
  timing instrument is the separate perf probe, and it is not wired into `tools/build.ps1`. A smoke
  package needs a `relations` rule for its **appearance** and the perf probe for its **cost**, and
  those are two different runs.

---

## Coverage gaps

**Does not exist** (searched and established):

1. **Any assertion touching the reciprocating group.** `grep -rn
   'SLIDE_TRAVEL|_slide_offset|_cycle_slide|_locked' scripts/dev/` → **0 lines**, run by me.
2. **Any frames scenario capturing an animated state.** The registry is `spawn, power_off, power,
   trap_armed, ads, downed, horde, raygun, flash_hip, flash_ads` — no reloading weapon, no
   bolt-lock, no swap, no melee, no displaced slide.
3. **The word "smoke" in the ancestor.** `grep -c -i smoke kriegsnacht.html` → **0**, run by me.
4. **Any smoke, haze or fog effect in `fx.gd`.** Its header's contents list is exhaustive and
   accurate.
5. **Comments in the ancestor's `GUNART`.** `kriegsnacht.html:1150-1210` contains **zero** `//`
   comments — run by me. So the ancestor cannot arbitrate the magazine-versus-pistol-grip question,
   and the test proposed to settle it does not.
6. **Any `reduce_motion` path in the viewmodel.** `_tick_bob`, `_tick_sway` and `_tick_kick` all run
   at full amplitude while `player.gd:709` zeroes the camera bob and `:834` damps the camera kick.
   The accessibility setting stops the camera and leaves the weapon swinging, and
   `checks/shell.gd:970-1033` covers five effects, none of them the viewmodel. M5's R11 constraint
   (c) is written against a path that does not exist.

**Not found, which is different:**

7. **Real bolt and slide travel distances from a primary source.** Only hard *lower bounds* are in
   hand (cartridge overall lengths). Every mid-range figure is a Tier 4 estimate from mechanism and
   receiver length, **including the M1911's 48 mm, which I searched for on `1911forum.com` and
   `forum.m1911.org` and could not reproduce.** *Partly closed 2026-08-02:* the weapon overall
   lengths behind the floor table are no longer recalled — MP 40, AKS-74U, FB PM-63 and the China
   Lake were fetched from Wikipedia infoboxes and are in the travel table — and the
   folded-versus-extended question that this gap warned "changes their mm/unit by up to 1.75×"
   **turned out to have broken three of the seven floors**, which is why the table now carries the
   drawn-span and OAL columns it derives from. Still open: the Stakeout's overall length (838 mm is
   my estimate) and every ceiling.
8. **IMFDB's per-weapon BO1 sections for the Olympia, Stakeout, RPK, China Lake, Ray Gun and
   Thundergun.** Direct `WebFetch` to imfdb.org returns **HTTP 403** on both hosts; the r.jina.ai
   proxy worked but truncated partway through the AUG. So column 2 for those six leans on the real
   weapon plus fan wikis (Tier 4), not on a documented observation of the shipped viewmodel.
9. **BO1's own slide-travel proportions.** M5's F27 established that the WEAPONFILE format carries
   no offset/velocity/spin fields for shell ejection, which suggests animation travel is likewise
   baked into a compiled asset and absent from any public rawfile dump. **The reference may be
   unable to arbitrate the travel number at all**, in which case the cartridge-length floor is the
   best provenance available and must be labelled as our decision.
10. **BO1's muzzle-smoke behaviour from any primary source.** The R7 design is derived from this
    port's own constraints, not from the reference.
11. **Any measurement of alpha-blend fill cost on the actual target.** The only committed perf
    numbers are a 16-thread Windows desktop with an empty scene at 145 fps / 6.9 ms
    (`notes/perf/phys-20260727-165824.json`), which says nothing about single-threaded WebGL2 on
    consumer hardware — which R2 establishes is the real target. **Every cost claim about smoke,
    including this document's, is unvalidated.**
12. **Whether `_apply()` runs after `_cycle_slide()` within the `flash_hip` capture frame** —
    *narrowed 2026-08-02 by reading `main.gd`, which the first draft admitted it had not.*
    `_tick_shot(dt)` runs at the head of `main._process` (`:511-512`) and the capture `await`s
    `RenderingServer.frame_post_draw` (`:738`), so the image is the frame drawn at the end of the
    tick in which `_shot_ready()` returned true. The remaining unknown is the **node processing
    order between `Main` and the viewmodel**, which I did not establish. The actionable conclusion
    does not depend on it: `arrival_of` / `_shot_ready` already exist (`main.gd:725-727`), so a
    `slide_back` scenario should carry **its own arrival predicate** on the slide's offset rather
    than trust an ordering nobody has read.
13. ~~**The PM-63's hold-open behaviour.**~~ **Closed 2026-08-02.** Wikipedia's `FB PM-63 RAK`
    (fetched): "after the last cartridge has been fired from the magazine, the slide is locked open
    on the slide catch", engaged automatically by the empty magazine. `BOLT_HOLD` ships as
    `["m1911", "pm63"]` and A6 gets a PM-63 half. *What remains genuinely open is narrower and was
    the wrong question before: not whether the weapon has a hold-open, but whether BO1's viewmodel
    shows one — and under R3's open-bolt mode the locked pose and the rest pose coincide, so it is
    not observable either way.*
14. **A 25% discrepancy between two px-per-art-unit calibrations in `viewmodel.gd` itself.** The
    `ADS_SIGHT_CLEAR` ladder (`:360-367`) implies 4.67 px per art unit at 1280×720; `M_PER_H`
    (`:205`) implies 6.25, and `M_PER_H` is corroborated three ways. The ladder is the outlier and
    it is the only *empirical* calibration in the file. Unresolved without a capture; `--frames
    spawn` prints the silhouette box, so it is a log line for whoever runs the gate next.
15. **Whether the China Lake should be `shells: true`.** It is **not** flagged in `weapons.gd:34`
    (confirmed — the key is absent), so it takes a magazine reload, while M5's F12 reports BO1's
    `segmentedReload = 1` on exactly the Stakeout and the China Lake. R4's end-of-reload stroke plan
    depends on which way that goes.
16. **Whether an extra `MeshInstance3D` per animated group is free on the web target.** One more
    draw with the same material and no new program *should* be noise, but `notes/perf/` is the
    authority and it was not read for a draw-call budget.
17. **Whether a transparent quad at 0.35 m interacts badly with SSAO**, which `lighting.gd:220-226`
    notes is applied post-glow on the composited image and *"darkens emissives, the muzzle flash and
    the bloom itself"*. Smoke is not emissive so no issue is expected. R1's standing request for a
    before/after screenshot of "a smoke particle in front of a wall corner" predates this package
    and is still unanswered.

**Citations that drifted, corrected here:** the corpus cited `gunart.gd:436-437` for `_to_local`
(the signature is `:436`, the body `:437` — fine), `:276-279` and `:278` for the `KEY_DIR` block
(the comment runs `:275-279`, the const is `:279`), and `viewmodel.gd:945` for the sweep endpoint
(exact). `gunart.gd:699-700` for the symmetric extrusion is exact. `viewmodel.gd:171`, `:178`,
`:189`, `:266`, `:334`, `:336`, `:372`, `:399`, `:400`, `:404`, `:418`, `:605`, `:621`, `:726`,
`:808`, `:910`, `:996` and `weapons.gd:24-36` were all confirmed by direct grep.

---

## Source index

| # | Source | Tier | Used for |
|---|---|---|---|
| 1 | `scripts/data/gunart.gd` (read) | 1 | `ART` for all 13 weapons, `SLIDE` verbatim, `MUZZLE`/`GRIP`, `_to_local`, `_build`/`_corners`'s boolean filter, `_extrude`'s symmetric sweep, `KEY_DIR`'s model-space bake, `sight_height` |
| 2 | `scripts/entities/viewmodel.gd` (read) | 1 | `REST_POS`/`REST_PITCH`/`REST_YAW` and the yaw docstring, `ADS_*`, `SLIDE_TRAVEL`/`_TIME`/`_BACK` and the false comment, `DIP_ROLL`, `_on_fired`, `_cycle_slide`, `_locked`, `_slide_offset`, `_measure`'s three metrics and pose loops, `_collect`, `flash_anchor` |
| 3 | `scripts/data/weapons.gd` (read) | 1 | Every `rpm`, the `shells` flags, the "ported verbatim" contract at `:4-5` |
| 4 | `scripts/entities/weapon.gd`, `player.gd` (read) | 1 | `settle`'s EMPTY condition, `RELOAD_SHELL` re-entry and the sawtooth comment, `_load_shell`'s settle-before-emit, `weapon_changed` inside the carry loop, `stow_cancels` |
| 5 | `scripts/autoload/game_state.gd` (read) | 1 | `DTAP_RPM_MULT := 1.34` at `:54` |
| 6 | `scripts/world/fx.gd`, `lighting.gd`, `shader_warmup.gd`, `quality_governor.gd`, and **`scripts/systems/atmosphere.gd`** (a different directory — the first draft filed it under `scripts/world/`, where it is not, and R7's whole ownership argument hangs on that file) | 1 | The three-family process-shader cap, the DUST preset, depth fog as the shipped haze, the 0.92 glow gate, warm-pass reachability, the render-scale-only governor, the measured display-space finding |
| 7 | `scripts/entities/projectile.gd` (read) | 1 | `_explode` spends no particles |
| 8 | `scripts/dev/verify.gd`, `checks/frame.gd`, `checks/projectiles.gd`, `shot_setup.gd`, `frame_stats.gd` | 1 | `ASSERTION_FLOOR`, registration order, the `fired`-listener Rng assertion **and its recorded control**, the fx Rng loop that never emits `fired`, the VM rects, luminance-not-milliseconds |
| 9 | `notes/perf/frames/golden.json` (parsed by me) | 1 | The four scenarios' probe lists and the 24 relations — the proof the gate cannot see the slide |
| 10 | `kriegsnacht.html` (read) | 1 | `:1150-1210` GUNART, uncommented; `:2580-2581` the ember and smoke bursts; the negative grep for "smoke" |
| 11 | `notes/research/M5-weapon-feel.md` | 1 | The style contract's five rules, F10/F11/F12/F27/F36, R2's deferral of asymmetric extrusion, R5–R7, R11 |
| 12 | `notes/analysis/ancestor-diff.md:305` | 1 | The "smoke" label — corrected here as an interpretation |
| 13 | IMFDB, *Call of Duty: Black Ops* (via r.jina.ai; direct fetch 403) | 3 | BO1 animating the bolt/handle in **draw and reload**, not in fire: M14 "pulling the bolt", MP40 "pulling the bolt handle", AKS-74U "charging the weapon", M16 "pressing the bolt release", M1911 "locks the slide back and then releases it" |
| 14 | modernfirearms.net (PM-63), Wikipedia (`FB PM-63 RAK`, `MP 40`, `AKS-74U`, `China Lake grenade launcher`, `Ithaca 37`, `Cocking handle`), pewpewtactical (Ithaca 37) | 3 | Open-bolt cycles, the PM-63 firing while the slide moves forward and **its hold-open, now quoted**, the Ithaca's bottom ejection and slab sides, the China Lake's between-shots pump stroke, the MP40's reciprocating left-side handle. **Fetched 2026-08-02 for the travel-table rebuild:** MP 40 833/630 mm and a 251 mm barrel; AKS-74U 730/490 mm; FB PM-63 583/333 mm; China Lake 876.3 mm, pump-action, 40×46 mm, 3+1 (which also confirms `weapons.gd:34`'s mag 4) |
| 14b | shotgunlife.com / nrawomen.com (ejectors vs extractors), shotgunworld.com + Grokipedia (Ithaca 37 slam fire) | 3 | Auto-ejectors throw **fired** hulls and merely lift unfired ones; the pre-1975 Model 37 has no disconnector and slam-fires, so a real M37's pump stroke *precedes* the shot under sustained fire — recorded and then overridden by BO1 |
| 15 | guns.fandom (Rottweil Skeet Olympia 72), nazizombies.fandom (Thundergun, re-fetched 2026-08-02), callofduty/callofdutyzombies.fandom (Ray Gun, Olympia) | 4 | Auto-ejectors on the Olympia and BO1 ejecting only the fired shell; the two **red** canister lights showing rounds remaining, **three when upgraded**, riding the **magazine** (hence the recorded lights-visible-with-magazine-out bug); the Thundergun's iron sights, on a page that asserts both that it has them and that it has none; the Ray Gun's magazine "stuck into the barrel" **and its barrel-flip reload**. **None seen in a frame** |
| 16 | Godot `doc/classes/GPUParticles3D` | 1 | `restart()` restarts a one-shot reliably where `emitting = true` does not — which is what `fx.gd` already calls at `:416`, `:649`, `:960`, `:972`. Renderer-independent; the only Compatibility-specific particle note is that `emit_particle()` is Forward+/Mobile only |

**Rows 13, 14 and 15 are the only external evidence in this document, and rows 14 and 15 are doing
the work for column 2 of the weapon table.** Row 13 is the closest thing to a reference observation
and it is a text description of an animation, not the animation. Treat the mechanism claims as
Tier 3 and the two fan-wiki details as leads.

---

## What the critics found

Two reviewers read the first draft — one on mechanical truth, one on constraints and testability.
**Every finding below was re-verified against the source before it was applied**, per this project's
rule that receiving review is technical rigour and not agreement. Four survived that verification
only in part and are marked; three sub-claims were **rejected with evidence**. The verification
turned up two defects neither critic named, and those are in the table too.

Nothing in this pass was run in the engine either: no `--verify`, no `--shot`, no `--frames`. The
corrections are arithmetic over source and six web fetches, all cited in place.

### Applied

| # | where | what was wrong | what was done |
|---|---|---|---|
| 1 | travel table | Derivation B scaled the MP40, PM-63 and AK-74u through their stock-**folded** overall lengths while all three are drawn stock-**extended**. Reproducing B's method on three fixed-stock controls (RPK 4.631 vs 4.63, China Lake 8.781 vs 8.80, M1911 5.550 vs 5.55) confirmed the method; feeding the folded lengths reproduced B's three wrong numbers to two decimals. | Floors re-derived with the extended lengths (mp40 3.77 → **2.85**, pm63 4.50 → **2.55**, ak74u 9.07 → **6.09**), all four OALs fetched, and the table now carries the drawn span and the OAL it scales through so the next reader can see the input rather than the output. |
| 2 | table row 7, travel table, *human eye* | The Stakeout's 12.51-unit "floor" is unreproducible from any Ithaca 37 — back-solving needs a 469 mm weapon — and at 14.9% of the drawn length it exceeded the real ≈11.3% pump stroke. It was the one proposal in the package that moved a part **further** than the firearm does, and the document had escalated it to "do not split the difference, take a `--shot` at both". | 12.51 withdrawn as a units error. **9 adopted.** Removed from the disagreement framing and from *The human eye*. The derivation is recorded with its estimate flagged as an estimate. |
| 3 | table row 10 | The China Lake's 8 units = 89.7 mm against a 98.4 mm grenade — below the cartridge floor, the same violation the document raises the M1911 to fix — and "~92% of the true stroke" was 92% of derivation **A's floor**. | Rewritten as an explicit departure with both numbers, plus the alternative (move part 3 two units, take 10). |
| 4 | Bottom line | "the only travel number on the roster with a lower bound" was contradicted by the document's own floor table two pages later. | Restated as the stronger true claim: the shipped 4 is below the cartridge floor on **five of seven**, and the M1911 is the row where two derivations agree. |
| 5 | table row 5 | The PM-63 cap "5 and not more" was arithmetically wrong by its own stated reason: contact with the strut is at **2**, not 5 (52 + 2 = 54, the `rr` origin, which `_part_poly`'s convention at `gunart.gd:568-571` makes a corner). And 2 units × 9.80 mm = 19.6 mm is below the 25 mm 9×18 floor, so **no valid stroke fits the drawn art at all** — a conclusion the row never reached. | Cap corrected to 2, the real finding stated, and 5 kept as a **recorded interpenetration** with the LAYER/PROUD reasoning that makes it concealed. |
| 6 | R1, *the two rows that animate a part* | R1's geometric provenance convicts the MP40's part 6 on the same evidence it convicts the AK's part 7 — both overlap their receiver by exactly two units; only the RPK's strip is disjoint. The verdict was right; the written argument could not carry it. | Replaced with the mechanical argument: an AK carries a gas tube there, an MP40 is straight blowback and has none. The overlap table is in the document so nobody re-derives the wrong test. **Both critics found this independently.** |
| 7 | table row 2, *Listed and not recommended* | The Olympia's hinge group `{0,1,5,6}` and column 3's part identifications contradict each other, and the document's own two excursion figures (36 mm at 36° over 58 units; 21 mm at 25°) imply **two different pivots** — 21 mm at 25° requires r ≈ 48 units. *The second inconsistency is mine, not the critic's.* | Part 2 identified as the wrist under the hand (`GRIP.olympia` is inside it), part 5's identity flagged as unsettled with the arguments both ways, and both pivots' excursions tabulated. The style rejection is pivot-independent, so the verdict survives. |
| 8 | table row 2 | "auto-ejectors" and "both hulls are thrown" contradict each other: ejectors throw **fired** hulls and merely lift unfired ones. | Corrected, and grounded in the port: `weapons.gd:25` already flags the Olympia `"shells": true`, so the count is a function of `mag` at reload start. |
| 9 | table row 11 | The Ray Gun row quoted half its source. BO1's reload **flips the barrel open** — the same rotational channel as the Olympia hinge — and the Ray Gun was the one weapon given neither a shot animation nor a reload one. | Added to row 11, explicitly scoped out of this package, and counted in R8's warrant test, which now has three candidates. |
| 10 | table row 12 | "No iron sights" and the lights' ownership. | Corrected to modelled-but-non-functional; the lights ride the **magazine**, are **red**, and there are **three** when upgraded. |
| 11 | R6, gap 13 | The PM-63's hold-open was asserted in the body, withheld from `BOLT_HOLD` for want of a citation, and filed as indeterminate. It is citable. | `BOLT_HOLD := ["m1911", "pm63"]`, gap 13 closed, A6 extended — and the *narrower* question that remains (whether BO1 shows it, and whether R3's open-bolt rest pose makes it observable at all) recorded in its place. |
| 12 | table row 7 | The Model 37's fire control was described incompletely in exactly the direction the pump-timing dispute turns on: it slam-fires, so the pump stroke *precedes* the shot. | One sentence added, and BO1 recorded as the reference that overrides it. |
| 13 | table row 1, travel table | Only floors were derived; nothing asked whether a proposal exceeds the real stroke, which is the failure mode that reads as broken. | A **ceiling** column added for every row, and the M1911 stated with both bounds (floor 5.55–5.71, stroke ≈8.4, proposal 7 = 83%). |
| 14 | A1 | The control ("restore `\"ak74u\": [7]`") leaves the check green — the rects overlap. | A1 rewritten as a decision-pinning assertion over the whole `SLIDE` dictionary, with a provenance line per row and a control that discriminates. |
| 15 | A12 | The control ("unregister it — `verify.gd:1049-1052` already catches this class") leaves the check green: `verify.gd:1039-1052` reports members of the **declared** list missing from the warm pass, so a material never declared is never missed, and `main.gd:174` feeds the warm pass from the same accessor. | A12 made consumer-driven off the live node's `material_override`. **And `M5:603-605`'s F32 carries the same wrong claim about `fx.materials()` — reported for correction there.** |
| 16 | A11, A12 | The whole smoke feature could be **completely inert** and both assertions still pass — the precedent for which is recorded on this very file at `atmosphere.gd:438-445`. | Six checks (A11–A18) built on `checks/frame.gd:1141`'s existing `_fire_once` shape: it draws, it animates, it goes away, heat accumulates, the re-anchor happens, and the material's four decisions are pinned. Each with its own control. |
| 17 | R2 "The trap" | The trap was named and given no check — and the document's own analysis proves no *aggregate* check can find it, because all three of `_extreme`'s components are insensitive to slide travel by construction. Deleting `viewmodel.gd:945` outright leaves the suite green today. | `vm.swept_travels()` — a structural readout of what the sweep actually collected at, asserted against the same accessor `_slide_offset()` reads. |
| 18 | A8 | A8 asserted a null result, so a group **not in the corner pool at all** — the exact hazard — passes under its own sabotage. | Split into A8a (refusal against the committed 0.231884) and A8b (acceptance over `swept_travels()`). |
| 19 | A2 | The antiparallel clause is false against correct code on all seven weapons (6.34°–9.46°, because every muzzle sits above its grip). | Replaced with a sign test, which is exactly true and keeps the ancestor anchor. Plus the EMPTY-state trap that would have failed A3 for an unrelated reason. |
| 20 | Smoke | Depth-test behaviour was never stated, on a file that has **measured** what happens when a quad at that depth depth-tests (`atmosphere.gd:280-293`). | Decided: `no_depth_test = true`, which makes the **size** the binding constant rather than a free one — flagged as the one smoke constant whose *kind* changed. Sort order and `shading_mode` decided too, and all of it asserted in A18. |
| 21 | R7 | "already has the pausable `_process`" is backwards: `atmosphere.gd:414-416` early-returns on the flash clock, so a smoke decay written after it freezes at 0.05 s. | Recorded as a structural edit with A15 as its catcher. |
| 22 | *rotation and `_measure()`* | The one live safety finding against shipped code appeared in no recommendation and no assertion — and it was understated: **four** basis channels trace unsampled arcs, not one. | Promoted to **R12**, with the assertion and control the finding never had, and A9 given the live consumer it lacked. |
| 23 | A7 | The free-run half was a pasted snapshot of hand arithmetic the document itself flagged as unverified. Verifying it found something worse: B measured to the grip **anchor**, not to any part (Stakeout 16.92 where the panel gives 14, China Lake 9.76 where the grip gives 8). *That second half is mine.* | A7 computes the free run from `ART`, with only the floor hardcoded, and gets an acceptance control (China Lake at 12 must fail). |
| 24 | frames gate | "New scenarios in `shot_setup.gd`'s registry" is five edit sites, and the registry entry turns `--verify` **red for everyone** until a windowed bless. | The five sites named, the hunk-and-bless declared one atomic windowed step, and the new rect requirement stated. |
| 25 | `ASSERTION_FLOOR` | "rises additively by whatever lands" is unactionable, and the floor is a `>=`, so under-raising is silent. | Delta estimated at **+30**, and the raise required to ship with its paragraph in the `verify.gd:150-165` docstring, as every previous raise did. |
| 26 | *Idle breathing* | "folded into `_mesh_pose`'s origin the way `bob` already is" conflates two mechanisms — `bob` is a `ViewmodelRoot` write bounded as a scalar, and the cited lines are the bound inside `_measure`, not a line of `_mesh_pose`. As written it would void the guarantee. | Mechanism rewritten; the conclusion (defer) is unchanged. |
| 27 | R2 | The implementation walked into one of this project's two hard parse errors — a call through a preloaded script constant handed to a typed parameter, twelve lines below the comment saying not to. | One annotated line specified, plus the `const` literal shape for `TRAVEL` and `BOLT_HOLD`. |
| 28 | source index row 6 | `atmosphere.gd` filed under `scripts/world/`. It is `scripts/systems/`. | Corrected there and in R7. |
| 29 | *Is the motion even visible*, *The human eye* | The 3× pixel disagreement and the hip-vs-ADS table were consigned to "photograph it". They are **closed-form headless arithmetic** — `viewmodel.gd:128` pins the vertical half-angle at 27.5° regardless of camera FOV. | Both moved to `--verify`; the `--shot` demoted to a cross-check. Three items came off *The human eye*, which is only useful if everything on it needs an eye. |
| 30 | gap 12 | Filed as unresolved on a question closeable by reading a file. | Read: `_tick_shot` at `main.gd:511-512`, capture at `:738`. Narrowed to the Main-vs-viewmodel process order, with the actionable conclusion (use the existing arrival predicate) stated so it no longer costs anyone a windowed run. |
| 31 | *How this gets tested* | Nothing anywhere covered `Settings.reduce_motion`, and this package adds a reciprocating group on seven weapons, a pump stroke and a persistent quad — all exempt. | Recorded as a **deferred decision** rather than left as a widened gap nobody named. |

### Rejected, with the evidence that rejected them

| what the critic claimed | verdict | evidence |
|---|---|---|
| The PM-63's slide at 5 units "passes **visibly** through the stock rather than behind it", because the two parts' half-depths differ by only 0.28 art units. | **Rejected.** The cap correction stands; the visibility claim does not. | 0.28 units is the margin by which part 3 is **thicker**: half-depths are `BASE_HALF + i·LAYER`, so part 3 is 3.02 and part 1 is 2.74, and `_inflate` grows part 3 by `3·PROUD` against part 1's `1·PROUD`. Part 3 therefore **encloses** part 1 on both flanks and renders proud of it — the overlap is concealed by exactly the LAYER/PROUD stacking that exists to put a highlight over its plate (`gunart.gd:188-215`). This is why 5 is takeable at all; a *visible* interpenetration would not be. |
| The Thundergun's "no iron sights" is "contradicted by the document's own cited source". | **Rejected as framing; the correction applied.** | The source contradicts **itself**, on one page. nazizombies.fandom (re-fetched 2026-08-02) carries both "The Thundergun has visible iron sights, although the ability to use them was never featured in the game" **and** "has no iron sights, meaning it must be fired from the hip". The document quoted the second. Modelled-but-unusable is the only reading both sentences allow, and that is what row 12 now says — but a source that says both things cannot be cited as having contradicted anyone. |
| The M1911's real slide travel is "about 1.90 in = 48 mm for a 5-inch slide, 1.655 in for a compact T3", sourced to 1911forum / forum.m1911.org. | **Rejected as provenance; adopted as a Tier 4 estimate.** | I searched, including a search restricted to `1911forum.com` and `forum.m1911.org`, and got discussion of slide travel with **no number** — the same result the corpus's own two searches got, and the reason Coverage gap 7 exists. The ceiling **column** is the critic's real contribution and it is adopted throughout; the M1911's ceiling ships labelled Tier 4 and unreproduced, not as a citation. The same caveat attaches to the Stakeout's 838 mm overall length, which is an estimate of the critic's and is marked as one. |

### What the critics did not find

- **No constraint violation, in either lens.** Nothing here uses a `gl_compatibility`-dead feature,
  no proposal writes a node that already has a writer, no proposal draws from an `Rng` stream, and
  the display-space colour call is correct and backed by this repo's own measurement. Both critics
  checked independently and agreed.
- **The Olympia's two pivots** (applied #7) and **the free-run column measuring to the grip anchor**
  (applied #23) were found while verifying the critics' findings, not by the critics.
- **`M5:603-605`'s F32** carries the same wrong claim about `fx.materials()` that A12 did. That is a
  hunk in a file this package does not own, and it is reported in applied #15.

---

## MEASURED 2026-08-02: the slide travel question, settled

M6 named one open question above everything else — derivation A said the shipped 4.2 mm of slide
travel moves **25.0 px** on screen, derivation B said **8.9 px**, and the document said nothing
should be tuned before it was resolved.

**It is 9.6 px. Derivation B is right.**

### Method

Three windowed captures of `spawn` at 1280x720, M1911 in hand, with `_slide_offset()` pinned to a
constant so the shutter cannot land mid-cycle:

| capture | `_slide_offset()` returns |
|---|---|
| `sl_rest` | `0.0` |
| `sl_back` | `SLIDE_TRAVEL` |
| `sl_back10` | `SLIDE_TRAVEL * 10.0` |

`viewmodel.gd` was patched and restored under a `finally`, and confirmed byte-identical to HEAD
afterwards. (`Get-FileHash` reported a mismatch and it was a **false alarm** — `core.autocrlf` is
`true`, so every tracked file's working copy differs from its blob at byte 19 of line 1, including
files never touched. `git diff --stat` empty is the authoritative check, not the hash.)

Then the changed-pixel envelope between each pair, over x[700,1000] y[400,700], threshold
`|dR|+|dG|+|dB| > 10`:

```
  sl_rest vs sl_back     n= 1149  x[777..915] y[479..518]  w=139px h=40px
  sl_rest vs sl_back10   n= 7475  x[777..999] y[479..539]  w=223px h=61px
```

The envelope is the union of the two silhouettes, so for a part of on-screen length `L` displaced
by `d`, its width is `L + d`. Two captures at 1x and 10x give two equations:

```
  L +  d = 139        L + 10d = 223     =>  9d = 84   =>  d  = 9.33 px,  L = 129.7 px
  H + dy =  40        H + 10dy =  61    =>  9dy = 21  =>  dy = 2.33 px
  total displacement = sqrt(9.33^2 + 2.33^2) = 9.62 px
```

**Why this is a measurement and not another derivation.** It never converts metres to pixels, never
uses `M_PER_H`, and never decomposes the pose basis — the three things the two derivations disagreed
about. It reads the displacement off the frame the game actually draws. The 10x capture is what
makes it a measurement rather than a single reading: a systematic error in the region or the
threshold shifts both `L` and `d` together and cancels in the difference.

### What follows

- **Derivation A's 25.0 px is withdrawn**, and with it every judgement that rested on it. A applied
  `M_PER_H`'s screen-plane conversion to a translation that is not in the screen plane.
- **B's decomposition is vindicated**: model +Z sits 14.09 degrees off the view axis, so ~97% of
  the travel is depth and only about a quarter of it is lateral. A slide moving *away from the eye*
  barely moves on screen no matter how far it goes.
- **The travel is ~7.4% of the slide's own on-screen length** (9.62 of 129.7 px). It is not
  invisible — 9.6 px is above threshold — but it lasts `SLIDE_TIME` = 0.06 s, about 3.6 frames at
  60 fps, and it is a translation *along the part's own long axis*, which is the least perceptible
  direction a rigid part can move in. That is the quantitative answer to "the guns feel static":
  **the motion is real, brief, and pointed almost directly away from the camera.**
- **This reframes the fix.** Increasing `SLIDE_TRAVEL` buys screen motion at only 0.242 px per
  0.1 mm, and every millimetre of it also spends the clip budget's 8 mm of margin. Rotating the
  travel axis toward the screen plane, or lengthening `SLIDE_TIME`, are both cheaper per pixel of
  perceived motion than making the stroke longer. Any per-weapon travel table authored against
  derivation A's numbers would have been tuned against a figure 2.6x too large.

### Not measured

- Only the M1911, only `spawn`, only at 1280x720. The ratio should hold for any weapon whose slide
  runs along the same local axis, but the *fraction of its own length* differs per weapon.
- The perceptibility judgement ("is 9.6 px over 60 ms enough?") is not a measurement and is not
  settled here. It needs a human watching motion, which a still cannot provide.
