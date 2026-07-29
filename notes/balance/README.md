# Balance

Raw simulator output lives beside this file as `sim-<stamp>-rounds.csv`,
`-summary.csv` and `-cadence.csv`. `scripts/dev/balance_sim.gd` produces them; it
is reachable only from `main.gd`'s `--sim` flag, the same way `--verify` reaches
the assertion suite. `tools/balance.ps1` is the normal way to run it.

It is *unreachable* in a shipped build, not *absent* from one:
`export_presets.cfg` exports `all_resources` and excludes only `addons/*`,
`*.html`, `*.md` and `*.bak`, and `main.gd` holds a `preload()` on this script, on
`verify.gd` and on `console.gd` — so all three are in the web PCK as dead weight.
Nothing can start them there (the console additionally gates on
`OS.is_debug_build()`), but if the payload ever needs trimming, `scripts/dev/*` is
the first thing to exclude. That belongs to whoever owns the export preset.

Before this existed, nothing in this repository could answer whether a change made
round 12 harder or easier. That is not a small gap: Milestone 2 shipped a
fire-rate fix that is a straight buff, against a round curve that had been tuned
while the rates were broken, and the size of that buff was unknown.

---

## What this can answer, and what it cannot

**It is valid for exactly one thing: comparing two builds of this model against
each other.** Both builds are driven from one seed through the real `Rng`
sub-streams, so the horde is bit-identical between them — same count, same health,
same speed class per spawn, same crawler rolls, same spawn intervals. Every
difference in the output is therefore caused by the thing that was changed. Read
the ratios.

**It is not valid as an absolute difficulty figure.** The model has:

| Missing | Consequence |
|---|---|
| **No map** | Zombies close a single straight-line distance — the mean range from a live window to the spawn tile, 6.98 m — instead of walking a route. Real approach paths are longer and vary by window, so arrivals are earlier here than in the game. The distance is closed to *zero*, not to `melee_reach`, which pushes arrivals about 1.1 s later for a walker and 0.3 s for a sprinter — the one term in the approach that errs the other way |
| **No player movement** | The player stands still and shoots. There is no kiting, no training a horde in a circle, no backing through a door. This is the single largest distortion, and it is why `damage_taken` is enormous in late rounds — a stationary player in round 20 is standing inside 24 zombies |
| **No line of sight** | Every zombie is shootable the moment it exists. No corners, no reloading behind cover, no losing a target |
| **No barricade** | The window teardown — six planks at 0.9-1.5 s each, or a hound's flat 0.42 s — is the whole of the rounds 1-5 rhythm and is not modelled. `--sim-entry <s>` adds a flat per-spawn delay to stand in for it; it is 0 by default, so the default run is the version with no barricade at all |
| **No power-up effects** | Drop *cadence* is real (it drives `Game.check_points_drop()` and the flat 3% roll), but a Nuke does not clear the map, an Insta-Kill does not kill, and a Max Ammo does not refill. Every drop the sim reports is pressure the model never received |
| **No splash by default** | The China Lake's and the Ray Gun's blasts need positions to know how many bodies were in them. `--sim-splash <n>` assumes `n` extra bodies were caught and applies the full splash to each; it is 0 by default, so those two weapons are badly understated — the China Lake clears round 12 in 1156 s at `--sim-splash 0` and in 155 s at `--sim-splash 3` |
| **Reloads between waves are free** | With nothing standing, the model reloads. It is not interruptible, so a spawn arriving mid-reload is a lockout the player did not choose — round times therefore carry a little of the model's reload policy as well as the weapon's reload length. Both builds carry the same policy, so it cancels in a ratio |
| **No Thundergun** | Refused outright rather than reported. Its listed damage is 0 and its kill is a cone — a row for it would read "the Thundergun clears nothing", which is a lie about the weapon rather than a measurement of it |
| **No player skill** | Accuracy and headshot rate are two flat parameters (0.78 and 0.30 by default). A real player's accuracy varies with range, panic and weapon |
| **Free ammunition** | The reserve is topped up at every round boundary and again whenever it runs dry mid-round. The `refills` column counts the mid-round ones, so the cost the model is *not* charging is at least visible |

Two things it does get exactly right, because they are imported rather than
reimplemented: every curve comes from the `Game` autoload, and every zombie is a
real `Zombie.create()` — so health, the discrete speed class, the ±8% per-spawn
variance, A23's round-14 nudge, melee damage, cadence and reach are the game's own
values. The weapon is a real `Weapons.make_gun()` driven through the real
`scripts/entities/weapon.gd` state machine at the real 60 Hz, so magazine size,
reload length, shell-by-shell loading and the fire-rate remainder carry are the
shipping behaviour and not a formula that approximates it.

---

## Reproducing a run

Every run is a seed. The default is 20260729 and it is printed in the header line
and stamped into every CSV row, so a row always carries the run that produced it.

```powershell
pwsh tools/balance.ps1 -Rounds 25 -Seed 20260729 -Stamp m2cadence
```

`-Stamp` names the output files. The committed run used `m2cadence`; without it the
files are stamped with the wall clock, which tells a later reader nothing about
what the run was for.

or, without the wrapper:

```powershell
& "$env:USERPROFILE\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . `
  --sim --sim-rounds 25 --sim-seed 20260729 `
  --sim-gun mp40,ak74u,m16,rpk,pm63,m1911 --sim-cadence fixed,legacy `
  --sim-out res://notes/balance --sim-stamp mystamp
```

**`notes/balance/.gdignore` is load-bearing.** Godot's importer treats every `.csv`
under `res://` as a *translation* file: the first run without it produced a
`.import` plus one binary `.translation` per column — 46 files from three CSVs —
and would have carried all of them into the web export. `.gdignore` takes this
directory out of the resource filesystem. `FileAccess` still reads and writes
`res://notes/balance/` at runtime, because `res://` resolves against the project
directory rather than against the import database. Do not tidy the empty file away.

The same seed gives byte-identical CSVs. The player model's own dice — accuracy
and headshot placement — are a separate generator seeded off the run seed by the
same name-hash `Rng.stream()` uses, deliberately: if they drew from `SPAWN` or
`AI`, firing more shots would change which zombies spawn, and the two builds being
compared would face different hordes.

Flags: `--sim-rounds`, `--sim-seed`, `--sim-gun`, `--sim-cadence`, `--sim-perks`,
`--sim-pap`, `--sim-accuracy`, `--sim-headshot`, `--sim-retarget`, `--sim-entry`,
`--sim-splash`, `--sim-approach`, `--sim-out`, `--sim-stamp`.

## Reading the columns

| Column | Meaning |
|---|---|
| `time_to_clear_s` | Round start to last kill. In early rounds this is spawn-gated rather than damage-gated — see below |
| `contact_frac` | Fraction of the round with at least one zombie inside melee reach |
| `contact_zsec` | Zombie-seconds inside melee reach. The intensity figure; `contact_frac` is the incidence figure |
| `damage_taken` / `hp_bars` | What a **stationary** player takes, and how many times over their health bar that is. Past round 6 it is not a survivability number and is not meant to be one — it is a pressure ratio |
| `hp_per_s` | Round throughput: total spawned health divided by wall time. Not weapon DPS — it includes spawn gaps, reloads and travel |
| `first_contact_s` | When the first zombie reached the player, or −1 if none ever did |
| `refills` | Mid-round reserve refills the model granted for free |
| `drops` | Power-ups the real drop rules produced. See the note below |
| `walk` / `run` / `sprint` | Realised class counts, recovered from each spawn's own roll |

`-cadence.csv`'s `legacy_err_pct` and `fixed_err_pct` carry a counting artifact of
up to one rpm: delivered rate is measured as `shots - 1` over a 60 s window, which
is exact only when the interval divides 60 s evenly, so the M1911 reads 419 of a
stated 420 and the Stakeout 144 of 145. Neither is a defect in the weapon. Do not
pin a golden value on those two columns; `delivered_gain_pct` is a ratio of two
numbers carrying the same artifact and survives it to 0.03%, which is why the
headline uses it.

A round that has not cleared after 3,600 s of simulated time is called a stall and
the whole build is abandoned with a non-zero exit. The committed run comes within
13% of that: `m1911/legacy` round 25 takes 3,132.7 s. `-Rounds 26` with the
default gun list will very likely abandon the M1911, which is the harness working,
not breaking — drop the pistol or raise the constant.

---

## The Milestone 2 fire-rate fix, measured

`sim-m2cadence-*.csv`, six weapons × two cadences × 25 rounds, seed
20260729.

`fixed` is the shipping code. `legacy` is a model of what it replaced: an absolute
`next_shot = 60/rpm` counted down by a clamped-at-zero 60 Hz timer fires every
`ceil(interval / tick)` ticks, so every rate quantises **up** to a multiple of
1/60 s. That model is checked rather than assumed — it reproduces the four
collisions `verify.gd::_weapon_fsm` records, from the weapon table alone.

### Delivered rounds per minute (`-cadence.csv`)

| weapon | stated | legacy | fixed | gain |
|---|---|---|---|---|
| MP40 | 880 | **720** | 880 | **+22.2%** |
| AK-74u | 710 | **600** | 709 | **+18.2%** |
| RPK | 700 | **600** | 699 | **+16.5%** |
| PM63 | 1000 | 900 | 1000 | +11.1% |
| Ray Gun | 320 | 300 | 319 | +6.3% |
| M1911 / M14 | 420 | 400 | 419 | +4.8% |
| Olympia | 170 | 163 | 169 | +3.7% |
| M16 | 740 | 720 | 739 | +2.6% |
| China Lake | 62 | 61 | 62 | +1.6% |
| Stakeout | 145 | 144 | 144 | 0.0% |

The brief's "+22% MP40 / +18% AK-74u" is confirmed to a tenth of a percent. Note
what the legacy column really shows: MP40 and M16 both delivered 720, AK-74u and
RPK both delivered 600. Two pairs of weapons that are supposed to feel different
fired at literally identical cadences.

### What that is worth in a round

`time_to_clear_s`, fixed against legacy, by five-round band. Negative means the
fix made the round faster.

| gun | 1-5 | 6-10 | 11-15 | 16-20 | 21-25 | all |
|---|---|---|---|---|---|---|
| MP40 | **+2.3%** | −6.1% | −9.5% | −8.9% | −9.2% | −8.9% |
| AK-74u | −2.6% | −5.7% | −7.6% | −7.8% | −7.9% | −7.7% |
| RPK | −2.3% | −5.0% | −8.5% | −9.1% | −9.3% | −8.8% |
| PM63 | +0.5% | −3.9% | −4.1% | −4.1% | −4.1% | −4.0% |
| M16 | −0.7% | −1.2% | −1.4% | −1.3% | −1.2% | −1.3% |
| M1911 | −1.2% | −1.3% | −1.3% | −1.4% | −1.4% | −1.3% |

`contact_zsec`, same comparison. "both 0" means neither build let anything reach
the player at all in that band — a ratio there would be a divide by zero dressed
up as a −100%, which is exactly the kind of number that gets quoted later.

| gun | 1-5 | 6-10 | 11-15 | 16-20 | 21-25 | all |
|---|---|---|---|---|---|---|
| MP40 | both 0 | **−27.3%** | −12.7% | −9.6% | −9.6% | −10.0% |
| AK-74u | both 0 | **−36.0%** | −11.8% | −8.5% | −8.2% | −8.7% |
| RPK | 0.0% | −25.2% | −18.3% | −10.3% | −9.8% | −10.6% |
| PM63 | +14.3% | −13.7% | −5.4% | −4.4% | −4.2% | −4.5% |
| M16 | both 0 | −12.4% | −2.9% | −1.5% | −1.3% | −1.5% |
| M1911 | −5.0% | −1.8% | −1.4% | −1.4% | −1.4% | −1.4% |

`damage_taken` tracks `contact_zsec` to within a tenth of a percent in the `all`
column, which is what it should do — a stationary player's damage is contact time
times a fixed cadence. **Per band it does not**, and the difference is real rather
than noise: 6-10 reads −25.2% contact against −20.5% damage on the RPK and −12.4%
against −14.3% on the M16, because which *kind* of thing is standing on you
changes with the mixture (a hound swings every 0.85 s for 36, a walker every
1.05 s for 60) and the two builds do not kill them in the same order. Read
`contact_zsec` for pressure and `damage_taken` for damage; do not substitute one
for the other inside a band.

### The reading

**Rounds 1-4 did not get easier, because they were never damage-limited.** On
every automatic in the table, in both builds, `contact_zsec` for rounds 1-4 is
exactly zero and `first_contact_s` is −1: nothing reaches the player at all. Round
1 is six zombies arriving 1.4 s apart behind a 1.2 s beat of silence, so the round
takes 8.9 s whatever the gun is doing — the clock is `Sfx.ROUND_SILENCE` plus five
spawn intervals, not the time to kill anything. The ±2% swings in that band are
the two builds killing in a slightly different order and are not a difficulty
signal. The premise in the brief — that the fix "made rounds 1-5 easier" against a
curve tuned on the broken rates — **does not survive measurement.** The early
rounds are paced by `Game.spawn_interval()` and by the barricade, and the
barricade is exactly what this model does not have, so if anything the real early
rounds are *less* sensitive to fire rate than these numbers already say.

Two exceptions, and neither weakens that:

- **Round 5 is a dog round on this seed** (they land on 5, 10, 15, 19, 23), and
  hounds at 1.55x speed do arrive: the RPK takes 2.2 z·s of contact and the PM63
  0.8, identically in both builds. A dog round is a travel-time round, not a
  fire-rate round.
- **The M1911 is damage-limited from round 3**, and badly — 20.2, 99.8 and 38.6
  z·s in rounds 3, 4 and 5, and 5,760 damage in round 4 alone. That is the wall-buy
  economy doing its job. It also means "rounds 1-5 never produce contact" is a
  statement about the automatics and not about the game: keep the starting pistol
  out of any early-round claim.

**The buff arrives at round 6-7 and peaks at 6-10.** That is where the count first
saturates the 24-alive cap: round 6 is 27 zombies against a cap of 24, and from
there the fight becomes damage-limited rather than spawn-limited. The band 6-10 is
where an extra 22% of MP40 rounds converts most directly into pressure that never
lands — 27% less time with something inside melee reach, and on the AK-74u 36%
less.

**Steady state from round 11 is about a 9% shorter round and 10% less contact** on
the three weapons the bug hit hardest. That is the number to hold against any
future retune of `zombie_count` or `zombie_hp`: the round curve as it stands is
being fought by weapons that are, at the top of the affected group, delivering a
tenth more damage per second of round than they were when the curve was last
looked at.

**It is a re-ranking, not a uniform buff.** M16 and M1911 gained 1.3%; MP40,
AK-74u and RPK gained 8-9%. Under the old code the MP40 and the M16 delivered the
same 720 rpm; the MP40 now delivers 19% more than the M16 does. The AK-74u and the
RPK were likewise pinned together at 600 and now sit 10 rpm apart, which is what
the table always said they should be. Any comparison of these weapons made before
Milestone 2 was a comparison of two guns wearing one cadence, and is stale.

**Caveat that cuts the other way.** This model has no barricade and no power-up
effects, both of which are worth more in early rounds than late ones, and no
kiting, which is worth more in late rounds than early ones. The direction of the
result (no effect early, growing to ~9% by round 11) is robust to all three; the
exact percentages are not.

---

## Things the sim surfaced that are not about fire rate

**The four-power-ups-a-round cap was actually four a run — FIXED.** This is the
sim's first real find, and it is the one that justifies the tool: the bug is
invisible in the code (two correct-looking lines in two different files) and
invisible in play (nobody notices a drop that never comes), but it is unmissable
as a column of zeros.

The `drops` column read 1, 1, 2 in rounds 2-4 and then **zero for the remaining
twenty-one rounds**. `Game.drop_count` was incremented in
`round_director.gd::_on_zombie_died` and cleared only by `Game.reset_run()` and by
the dog-round Max Ammo — nothing cleared it at a round boundary. The ancestor does
(`G.dropsThisRound=0`, kriegsnacht.html:2862) and so does canon
(`powerup_round_start()`, R4 §2).

Over twenty rounds that is **4 power-ups where there should be about 42** — an
order of magnitude, in the resource that decides whether a late round is
survivable.

The fix is not the one-line reset it looks like. The rule was written out twice,
once here and once in the director, and fixing the director alone left this sim
faithfully modelling a bug the game no longer had — which is the worst possible
state for a measuring instrument. The cap, the threshold check and the counter now
live in `Game.try_drop()` / `Game.begin_round_drops()`, and both callers go through
them. `scripts/dev/checks/curves.gd` asserts the reset by driving a real
`force_round()`, not by setting the field and reading it back — that version of the
test would have passed against the bug.

Note what did *not* change: every cadence number in the tables above. The sim models
drop *cadence* and not drop *effect*, so more power-ups do not feed back into clear
times or damage taken. That is a limitation, and it is why the fire-rate conclusion
survived the fix unaltered.

**The M1911 cannot hold a round past about 12.** It takes 17,006 s of simulated
time to clear 25 rounds against the MP40's 5,008 — three and a half times as long.
That is the wall-buy economy doing its job rather than a defect, but it does mean
the starting pistol is not a viable comparison baseline past the first few rounds.
