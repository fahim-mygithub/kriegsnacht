# R4 — Canon reference numbers for the World at War / Black Ops 1 era

Research date: 2026-07-27. Target era: **Call of Duty: World at War (T4)** and **Black Ops (T5)**, with
**Black Ops II (T6)** used only to show where a value changed.

**Primary evidence for this document is Treyarch's own shipped GSC**, extracted from the retail
fastfiles and mirrored publicly. Every number below that is tagged Tier 1 was read directly out of
those script files, not from a wiki. Where the community and the shipped scripts disagree, both
numbers are given and the disagreement is called out.

Script sources used (all read in full, locally, not summarised by a fetch tool):

| Title | Repo | Path used |
|---|---|---|
| WaW (T4) | `plutoniummod/t4-scripts` | `SP/ZM Maps/Der Riese/maps/_zombiemode*.gsc`, `SP/ZM Maps/Zombie Verruckt/maps/…`, `SP/Common/maps/_gameskill.gsc` |
| BO1 (T5) | `plutoniummod/t5-scripts` | `ZM/Common/maps/_zombiemode*.gsc` |
| BO2 (T6) | `plutoniummod/t6-scripts` | `ZM/Core/maps/mp/zombies/_zm*.gsc` |
| BO3 (T7) | `shiversoftdev/t7-source` | `scripts/zm/_zm_spawner.gsc`, `scripts/zm/_zm_perk_juggernaut.gsc` |

Independent mirrors that carry byte-identical copies of the same functions (used as corroboration
that these are the shipped scripts and not one person's edit): `JTAG7371/T5-RawFile-Dump`,
`nonsensation/CoDScriptArchive`, `InfinityLoader/IL-GSC`, `SyndiShanX/COD-GSC-Source`,
`JezuzLizard/T4ZM-Script-Overhaul`, `JBShady/COD5-Remastered`, `Divity/waw-gsc`,
`leafized/GSC-Functions`, `treminaor/ugx-mod-bo3` (which ports `set_run_speed` and labels it
"this is from WaW").

---

## Bottom line

1. **Zombie melee is 60 damage in BO1 and BO2 against 100 base / 160 Juggernog health — that is
   2 hits to down without Jugg and 3 with it, not 2 and 5.** The "100 → 250 HP, 5 hits" figure that
   the wikis repeat is a **BO3+** number and does not apply to this era. The port's 34 damage vs
   100/250 is wrong on both the damage and the Jugg health.
2. **Power-ups are not on a kill counter — they are on a lifetime-points-earned counter with a
   compounding threshold.** First drop at **2,000 points earned**, then each subsequent threshold is
   the current total plus `2000 × 1.14ⁿ`, never reset for the whole game. On top of that, every
   zombie death has a flat **3%** chance to force a drop. Both paths are capped at **4 per round**.
3. **Zombie speed is three discrete animation classes rolled per spawn, not a continuous scalar.**
   `rand = randomIntRange(base, base+35)`, `≤35 = walk`, `≤70 = run`, `else sprint`, where
   `base = 8 × (round − 1)`. That means walkers vanish after round 5, sprinters appear at round 6,
   and **from round 10 onward every zombie is a sprinter, forever**. The port's continuous speed
   scalar, which saturates at round 16, is the core reason **standard zombies** cannot close on the
   player. *(Verifier: the port's hounds are already faster than the player — see Recommendation 2.
   The round scalar is behaviourally, not byte-, identical across titles — see Finding 10.)*
4. **There is no zombie health cap.** Health is `150`, `+100/round` to round 9, then `×1.1` per round
   with no ceiling until 32-bit integer overflow at **round 163**, after which BO1 has zombies revert
   to round-1 health on every odd round. Nothing else escalates with round number except spawn delay
   (`×0.95`/round, floor ~0.08 s). *(Verifier: confirmed, and note the port **already** implements
   this correctly — the recommendation to "delete the health cap" was aimed at a cap that does not
   exist in the codebase. No action required.)*
5. **Hellhound rounds are randomised, and the dog-round Max Ammo is real, not a myth.** First dog
   round is `randomIntRange(5, 8)` → round 5, 6 or 7; subsequent gaps are `randomIntRange(4, 6)` →
   +4 or +5. The last dog killed force-drops a **guaranteed Max Ammo**, and the code explicitly
   resets `powerup_drop_count = 0` first so the per-round cap can't block it.
6. **Headshots have no damage multiplier in the zombie scripts at all** — only a **+50 point** score
   bonus. Head damage multipliers live per-weapon in the weapon asset files, so a flat global 1.5×
   is not canon for any of these titles.

---

## Findings

Evidence tiers: **1** = official docs / shipped game source · **2** = maintainer statement / issue ·
**3** = reputable secondary or well-maintained reference implementation · **4** = community anecdote.

### 1. Zombie melee damage vs base health and vs Juggernog

| Value | WaW | BO1 | BO2 | BO3 |
|---|---|---|---|---|
| Player base max health | 100 | 100 | 100 | 100 |
| `zombie_perk_juggernaut_health` | **160** | **160** | **160** | additive **+100** |
| Juggernog upgraded (Der Wunderfizz / Pack) | n/a | 190 | 190 | +150 |
| Zombie melee damage | `ai_meleeDamage × 0.4` (**see gap**) | **60** | **60** | **60** |
| Hits to down, no Jugg (arithmetic) | 2 (if 50 dmg) | **2** | **2** | 2 |
| Hits to down, with Jugg (arithmetic) | 4 (if 50 dmg) | **3** | **3** | **4** base / **5** upgraded |

> **Verifier correction (BO3 row).** The original row read "5 (if base 150)", which garbled the
> arithmetic. Re-read from `shiversoftdev/t7-source`, `scripts/zm/_zm_perk_juggernaut.gsc`:
> `set_zombie_var("zombie_perk_juggernaut_health", 100)` and
> `set_zombie_var("zombie_perk_juggernaut_health_upgrade", 150)`, applied in `_zm_perks.gsc` as
> `n_max_total_health = self.maxhealth + level.zombie_vars["zombie_perk_juggernaut_health"]`.
> So BO3 is **100 + 100 = 200** (4 hits at 60 dmg) with base Juggernog and
> **100 + 150 = 250** (5 hits) with *upgraded* Juggernog.
> This **strengthens** the document's central thesis rather than weakening it: the community's
> "250 HP, 5 hits" figure now has a positive, exact explanation — it is BO3 with upgraded
> Juggernog — instead of merely being asserted to be "a later-era number". Verified Tier 1.

- **Tier 1, independently re-verified by the verifier.** BO1: `self.meleeDamage = 60;	// 45` in
  `ZM/Common/maps/_zombiemode_spawner.gsc` (the brief cited `t5/_zombiemode_spawner.gsc:244`; the
  file and symbol are confirmed, the *line number* is not — see the Verification pass on line
  numbers generally). Applied in the player damage callback:
  `else if ( isdefined( eAttacker.meleeDamage ) ) { iDamage = eAttacker.meleeDamage; }` with a
  legacy fallback `else { iDamage = 50;		// 45 }` — `t5/_zombiemode.gsc:4601-4607`.
  <https://github.com/plutoniummod/t5-scripts>
- **Tier 1, verifier addition — the full damage path is now traced, and 60 is final.** The original
  brief asserted 60 was the applied damage without ruling out a later multiplier. I checked. In
  `ZM/Common/maps/_zombiemode.gsc`, the player damage callback **unconditionally overwrites**
  whatever damage the engine passed in, for any attacker flagged `is_zombie`:
  ```gsc
  if( (isDefined( eAttacker.is_zombie ) && eAttacker.is_zombie) || level.mutators["mutator_friendlyFire"] )
  {
      self.ignoreAttacker = eAttacker;
      self thread remove_ignore_attacker();
      if      ( isdefined( eAttacker.custom_damage_func ) ) iDamage = eAttacker [[ eAttacker.custom_damage_func ]]( self );
      else if ( isdefined( eAttacker.meleeDamage ) )        iDamage = eAttacker.meleeDamage;
      else                                                  iDamage = 50;   // 45
  }
  ```
  There is **no** `player_meleeDamageMultiplier` applied downstream of this on the zombie path, so
  `60` is the number that actually lands. **2 hits / 3 hits is confirmed at Tier 1 end-to-end.**
- **Tier 1, verifier addition — a second melee path exists, and it is a red herring.** BO1 also has
  `self.enemy doDamage( GetDvarInt( #"ai_meleeDamage" ), ... )`, which a careless reading would take
  as the real zombie swipe (and which would reopen the WaW `ai_meleeDamage × 0.4` question for BO1
  too). It is not: it lives in `zombiemode_melee_miss()` and is gated on
  `if( isDefined( self.enemy.curr_pay_turret ) )` — it is the case where a zombie swings at a
  **pay turret**, not at a player. Checked and excluded.
- **Tier 1.** BO2: identical — `self.meleedamage = 60;` `t6/_zm_spawner.gsc:257`;
  callback `t6/_zm.gsc:4117`. <https://github.com/plutoniummod/t6-scripts>
- **Tier 1.** BO3: still `self.meleedamage = 60;` (`scripts/zm/_zm_spawner.gsc`), but Juggernog
  became **additive**: `n_max_total_health = self.maxhealth + level.zombie_vars["zombie_perk_juggernaut_health"]`
  with the var set to **100** (upgraded 150). <https://github.com/shiversoftdev/t7-source>
- **Tier 1.** Juggernog health, WaW: `set_zombie_var( "zombie_perk_juggernaut_health", 160 );`
  `t4/_zombiemode_perks.gsc:69`, applied as `player.maxhealth = 160; player.health = 160;`
  (`:684-685`). Verrückt's copy hard-codes the same `160/160` (`Verruckt/_zombiemode_perks.gsc:348`).
- **Tier 1.** BO1/BO2 Juggernog: `SetMaxHealth( level.zombie_vars["zombie_perk_juggernaut_health"] )`
  with the var at **160** (`80` only under the `mutator_susceptible` mutator).
  `t5/_zombiemode_perks.gsc:55-61, 1475-1481`; `t6/_zm_perks.gsc:69-70, 2074-2101`.
- **Tier 3, independent corroboration ×1.** `Jbleezy/BO1-Reimagined` change notes, "Zombies"
  section: *"Decreased damage from 60 to 50"* — i.e. vanilla BO1 zombie melee damage is 60.
  <https://github.com/Jbleezy/BO1-Reimagined> (a meticulously documented BO1 rebalance built from
  the decompiled shipped scripts).
- **Tier 1, relevant mechanic.** A given zombie can only damage a given player once per
  `level.ignore_enemy_timer = 0.4` seconds (`t4/_zombiemode.gsc:2559`, `t5/_zombiemode.gsc:4520`).
  Health regen in vanilla BO1 restores full health 0.5 s after a 2.4 s delay (5 s if low) — Tier 3,
  BO1-Reimagined notes lines 32-35, which state the vanilla values it is changing.

**Community disagreement, stated plainly.** The Call of Duty wiki and Steam/Reddit threads
consistently say Juggernog gives "four hits before red, the fifth being death" and that Juggernog
raises health "from 100 to 250". Both are **Tier 3/4** and both are **contradicted by the shipped
scripts for WaW, BO1 and BO2**, where the value is 160 and the melee damage is 60 (→ down on the
3rd hit). The 250 figure is most plausibly a BO3-era number, where Juggernog became additive.
Sources for the community position: <https://callofduty.fandom.com/wiki/Juggernog>,
<https://callofduty.fandom.com/wiki/Forum:Juggernog_hits_required>,
<https://steamcommunity.com/app/212910/discussions/0/792923683972228024/>. The wiki also claims
WaW Verrückt/Shi No Numa Juggernog "keeps health at 100 and boosts regen instead" — the shipped
Verrückt script sets 160/160, so that claim is at best true only of an unpatched launch build and I
could not verify it.

**Conclusion for this port:** treat **2 hits / 3 hits** as the WaW-BO1 canon, and treat "5 hits" as
a later-era number. If the design wants the 5-hit feel, that is a deliberate BO3-flavoured deviation
and should be labelled as such, not as canon.

### 2. Power-up drop trigger and per-round cap

**Tier 1.** Two independent paths, both gated by the same cap.

**(a) Score threshold** — `watch_for_drop()`, `t4/_zombiemode_powerups.gsc:370-394`,
`t5/_zombiemode_powerups.gsc:526-550`, `t6/_zm_powerups.gsc:389-406`:

```gsc
score_to_drop = ( players.size * zombie_score_start ) + zombie_powerup_drop_increment;   // 500*N + 2000
while (1) {
    curr_total_score = Σ players[i].score_total;      // lifetime points EARNED, not current wallet
    if ( curr_total_score > score_to_drop ) {
        zombie_powerup_drop_increment *= 1.14;
        score_to_drop = curr_total_score + zombie_powerup_drop_increment;
        zombie_drop_item = 1;                          // next zombie killed drops
    }
    wait 0.5;
}
```

`score_total` is initialised to the starting score (`player.score_total = player.score;`
`t4/_zombiemode.gsc:975`, `t5/_zombiemode.gsc:1515`), so **solo the first drop lands at 2,000
points actually earned.** The increment compounds and is **never reset** — subsequent thresholds are
+2000, +2280, +2599, +2963, +3378, +3851, +4390, +5004, +5705, +6504 … points earned.

> **Verifier note — this claim is robust to the CSV override, and Coverage gap 4 does not threaten
> it.** The original brief worried (gap 4) that `mp/zombiemode.csv` could shift the starting score
> and therefore the first-drop threshold. It cannot, because the *same variable* appears on both
> sides and cancels. Verified in `ZM/Common/maps/_zombiemode.gsc`:
> `points = set_zombie_var( ("zombie_score_start_"+players.size+"p"), 3000, false, column );` →
> `player.score = points;` → `player.score_total = player.score;`, while
> `score_to_drop = ( players.size * level.zombie_vars["zombie_score_start_"+players.size+"p"] ) + zombie_powerup_drop_increment`.
> Starting score `S` contributes `N×S` to both the threshold and the initial `Σ score_total`, so the
> first drop fires at exactly **2,000 points earned whatever the CSV sets `S` to.** Confidence on
> "first drop at 2,000 earned" is therefore **raised**, not lowered. (Incidental evidence the mirror
> is a genuine dump and not a tidy-up: that `points = set_zombie_var(...)` line is **duplicated
> verbatim** in the shipped source — a Treyarch copy-paste.)

**(b) Flat random chance** — `powerup_drop()`, `t4/_zombiemode_powerups.gsc:451-478`,
`t5/_zombiemode_powerups.gsc:615-650`:

```gsc
rand_drop = randomint(100);          // 0..99
if (rand_drop > 2) { if (!zombie_drop_item) return; }   // else: forced drop, "random"
```

→ values 0, 1, 2 pass, i.e. a **3%** chance per zombie death independent of score.

**Cap.** `set_zombie_var( "zombie_powerup_drop_max_per_round", 4 )`
(`t4/_zombiemode_powerups.gsc:25`, `t5/…:33`, `t6/_zm_powerups.gsc:47`), reset in
`powerup_round_start()`. Per-map overrides exist (Der Riese/Factory lowers it to **3**:
`nazi_zombie_factory.gsc`, both T4 and BO1's `zombie_cod5_factory.gsc`).
`zombie_powerup_drop_increment` default is **2000** in all three titles.

**Corroboration, Tier 3 ×2:** BO1-Reimagined notes — *"Decreased initial chance for a powerup to drop
from 3% to 2%"* and *"Decreased multiplier added to next guaranteed powerup from points from 14% to
10%"*, which independently confirm both the 3% and the ×1.14.
`DoktorSAS/GSC` T6 dvar mod documents the same two vars with the same defaults
(<https://github.com/DoktorSAS/GSC>).

**Why the port's "16-29 kills" feels almost right:** at round 1 solo a zombie is worth ~10 per
non-lethal hit + 50 on kill (+50 head / +80 melee), so ~100-160 points per zombie → the first drop
lands around kill 15-20. The kill-counter approximation **breaks** as soon as points-per-kill rises
(Double Points, headshots, higher-DPS weapons) or as the compounding threshold outgrows the round.

### 3. Points awarded per kill during Insta-Kill — **this changed between WaW and BO1**

**Tier 1.**

- **WaW:** in `player_add_points()` the doubling is applied to the whole payout:
  ```gsc
  points  = zombie_score_kill;                       // 50
  points += player_add_points_kill_bonus(mod, hit_location);
  if ( zombie_powerup_insta_kill_on == 1 && mod == "MOD_UNKNOWN" ) points = points * 2;
  ```
  `t4/_zombiemode_score.gsc:26-48`. Insta-Kill kills are dealt as `MOD_UNKNOWN`
  (`player.last_kill_method = "MOD_UNKNOWN";` `t4/_zombiemode_powerups.gsc:1186`), which yields no
  hit-location bonus → **50 × 2 = 100 points per kill**.
- **BO1 / BO2:** the multiply was moved to apply only to the *bonus*, which is zero for
  `MOD_UNKNOWN`:
  ```gsc
  player_points = get_zombie_death_player_points();               // 50 solo
  points        = player_add_points_kill_bonus(mod, hit_location); // 0 for MOD_UNKNOWN
  if ( zombie_powerup_insta_kill_on == 1 && mod == "MOD_UNKNOWN" ) points = points * 2;  // 0*2
  player_points = player_points + points;
  ```
  `t5/_zombiemode_score.gsc:28-38`. → **50 points per kill, flat.** Melee kills during Insta-Kill
  still route through `MOD_MELEE` and keep the +80 melee bonus.

Base kill value is **50** in every configuration in all three titles
(`zombie_score_kill` / `zombie_score_kill_1player..4player` all = 50).
Rounding: WaW rounds payouts up to the nearest **10**; BO1/BO2 round up to the nearest **5**
(`round_up_score(points, 5)`, `t5/_zombiemode_utility.gsc:237`).

### 4. Headshot multiplier — **not a damage multiplier at all in these scripts**

**Tier 1.** Searching every zombie-mode script in T4, T5 and T6 for hit-location-based damage
scaling returns nothing: `hit_location` is passed only to the *scoring* functions and to FX/gib
code. The only head-specific number in the gameplay scripts is the **score** bonus:

```gsc
set_zombie_var( "zombie_score_bonus_melee", 80 );
set_zombie_var( "zombie_score_bonus_head",  50 );
set_zombie_var( "zombie_score_bonus_neck",  20 );
set_zombie_var( "zombie_score_bonus_torso", 10 );
set_zombie_var( "zombie_score_bonus_burn",  10 );
```
(`t4/_zombiemode.gsc:546-550`, `t5/_zombiemode.gsc:737-741`, `t6/_zm.gsc:882-890` — identical
in all three.)

Damage-by-hit-location is a **per-weapon** property of the weapon asset (the `loc*Multiplier` fields
of the CoD weapon file), so it varies weapon to weapon. **Tier 3/4:** the CoD wiki's *Damage
Multiplier* article states WaW multiplayer weapons use **1.4×** head/helmet, with the M14 at 1.5×
<https://callofduty.fandom.com/wiki/Damage_Multiplier>. I could not retrieve the zombie-mode weapon
files themselves — see Coverage gaps. **A flat 1.5× for everything is not canon for any title in
this era.**

### 5. Zombie health curve and the "cap"

**Tier 1.** `t4/_zombiemode.gsc:530-532`, `t5/_zombiemode.gsc:695-697`, `t6/_zm.gsc:860-862` — all
three titles use identical values:

```
zombie_health_start                = 150
zombie_health_increase             = 100     // rounds 2..9, additive
zombie_health_increase_multiplier  = 0.1     // round 10+, health += int(health * 0.1)
```

```gsc
ai_calculate_health( round_number ) {
    level.zombie_health = 150;
    for ( i = 2; i <= round_number; i++ ) {
        if ( i >= 10 ) level.zombie_health += Int( level.zombie_health * 0.1 );
        else           level.zombie_health  = Int( level.zombie_health + 100 );
    }
}
```
(`t5/_zombiemode.gsc`; T4's is the incremental equivalent, T6's adds an overflow guard.)

**There is no cap variable and no cap round.** Simulated from the exact integer code:

| Round | 1 | 5 | 9 | 10 | 15 | 20 | 25 | 30 | 40 | 50 | 55 | 100 | 150 | 162 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| HP | 150 | 550 | 950 | 1,045 | 1,679 | 2,701 | 4,348 | 7,000 | 18,151 | 47,073 | 75,809 | 5,525,295 | 648,618,590 | ~2.04 × 10⁹ |

At **round 163** the value exceeds `INT32_MAX` and wraps negative. WaW and BO1 have **no guard** —
BO2 added one (`if ( level.zombie_health < old_health ) { level.zombie_health = old_health; return; }`,
`t6/_zm.gsc:3578-3586`), which is the only real "cap" that exists anywhere in the series and it is
an overflow clamp, not a design number.

**Corroboration, Tier 3 ×1, exact round match:** BO1-Reimagined notes, line 18 — *"Insta kill rounds
(rounds where zombies have round 1 health) happen every odd round starting at **round 163**"*. That
is an independently derived confirmation of the same overflow arithmetic.

**What escalates after health saturates?** Nothing else scales with round number indefinitely:
- `zombie_spawn_delay` starts at **2.0 s** and is multiplied by **0.95** each round with a floor of
  ~0.08 s (`t4/_zombiemode.gsc:2085-2094`) → bottoms out around round 64.
- `zombie_move_speed` saturates at 100% sprinters at round 10 (below).
- `zombie_max_ai = 24`, `zombie_ai_per_player = 6` — fixed.
- BO2 additionally clamps `level.round_number` to **255** (`t6/_zm.gsc:3514`).

The **round 55 "health cap"** figure sometimes quoted in the community appears nowhere in any of
these scripts and should be treated as folklore.

### 6. Hellhound round cadence, and the Max Ammo guarantee

**Tier 1, identical in WaW and BO1.** `dog_round_tracker()`,
`t4/_zombiemode_dogs.gsc:465-505`, `t5/_zombiemode_ai_dogs.gsc:440-475`:

```gsc
level.dog_round_count = 1;
// PI_CHANGE_BEGIN - JMA - making dog rounds random between round 5 thru 7
// NOTE:  RandomIntRange returns a random integer r, where min <= r < max
level.next_dog_round = randomintrange( 5, 8 );        // → 5, 6 or 7
...
if ( level.round_number == level.next_dog_round ) {
    dog_round_start();
    level.next_dog_round = level.round_number + randomintrange( 4, 6 );   // → +4 or +5
}
```

So: **not** a fixed 5-round cadence. First dog round uniformly 5/6/7; each subsequent gap uniformly
+4 or +5. Treyarch's own comment in the shipped script documents the intent.

**Max Ammo guarantee: real.** `dog_round_aftermath()`:

- **WaW** (`t4/_zombiemode_dogs.gsc:261-285`) selects the `full_ammo` powerup index explicitly, sets
  `level.zombie_vars["zombie_drop_item"] = 1;`, and **sets `level.powerup_drop_count = 0;`** so the
  4-per-round cap cannot suppress it, then calls `powerup_drop( power_up_origin )` at the last dog's
  death position.
- **BO1** (`t5/_zombiemode_ai_dogs.gsc:245-260`) does the same via
  `specific_powerup_drop( "full_ammo", power_up_origin )`.

**Corroboration, Tier 3 ×1:** BO1-Reimagined explicitly changes the cadence — *"Initial hellhound
round always happens on round 5 or 6"* and *"4 round and 5 round special rounds happen more
equally"* — confirming that vanilla is randomised over 5-7 then +4/+5.

Dog rounds also carry their own melee value: `self.meleeDamage = 40;`
(`t5/_zombiemode_ai_dogs.gsc:625`), matching the WaW comment
`SetSavedDvar("dog_MeleeDamage","100")` *"this gets rounded down to 40 damage after the dvar
'player_meleeDamageMultiplier' runs its calculation"* — which pins `player_meleeDamageMultiplier`
at exactly **0.4** (`_gameskill.gsc`: `setsaveddvar("player_meleeDamageMultiplier", 100 / 250)`).

### 7. Quick Revive solo behaviour — **did not exist in WaW**

| | WaW | BO1 |
|---|---|---|
| Solo self-revive | **No** — no solo branch exists in the script | **Yes** |
| Solo cost | n/a | **500** |
| Co-op cost | **1500** | **1500** |
| Requires power | Yes | **No in solo** (the machine skips the `waittill(perk_power_on)`) |
| Solo uses | n/a | **3**, then the machine leaves permanently |
| Lives granted | n/a | `self.lives = 1` per purchase |

**Tier 1.** WaW `t4/_zombiemode_perks.gsc:563-565` — the cost switch has one entry,
`case "specialty_quickrevive": cost = 1500;`, and the file contains no `solo` concept at all.
BO1 `t5/_zombiemode_perks.gsc:1087-1132`:

```gsc
if ( perk == "specialty_quickrevive" ... ) {
    players = GetPlayers();
    if ( players.size == 1 ) { solo = true; flag_set("solo_game"); level.solo_lives_given = 0; players[0].lives = 0; ... }
}
...
case "specialty_quickrevive": cost = ( solo ? 500 : 1500 );
...
if ( !solo ) { level waittill( perk + "_power_on" ); }     // solo machine is live from round 1
```

and on purchase (`:1494-1508`):

```gsc
if ( players.size == 1 && perk == "specialty_quickrevive" ) {
    self.lives = 1;
    level.solo_lives_given++;
    if ( level.solo_lives_given >= 3 ) flag_set( "solo_revive" );   // machine expires
    self thread solo_revive_buy_trigger_move( perk );
}
```

Perk costs for the rest of the era (Tier 1, `t4/_zombiemode_perks.gsc:558-575`,
`t5/_zombiemode_perks.gsc:1116-1165`):

| Perk | script name | WaW | BO1 |
|---|---|---|---|
| Juggernog | `specialty_armorvest` | 2500 | 2500 |
| Quick Revive | `specialty_quickrevive` | 1500 | 1500 / **500 solo** |
| Speed Cola | `specialty_fastreload` | 3000 | 3000 |
| Double Tap | `specialty_rof` | 2000 | 2000 |
| Stamin-Up | `specialty_longersprint` | — | 2000 |
| PhD Flopper | `specialty_flakjacket` | — | 2000 |
| Deadshot Daiquiri | `specialty_deadshot` | — | **1000** (with a dev comment: *"Setting this low at first so more people buy it and try it (TEMP)"*) |
| Mule Kick | `specialty_additionalprimaryweapon` | — | 4000 |
| Default (`zombie_perk_cost`) | — | 2000 | 2000 |

### 8. Perk cap

- **WaW: no scripted cap.** No `num_perks` / `perk_purchase_limit` check exists anywhere in
  `t4/_zombiemode_perks.gsc`. The effective cap is 4 because only four perks exist (and only
  Der Riese ships all four machines). **Tier 1** (absence of code) — a weaker form of evidence than
  a positive value, so treat "4" for WaW as *de facto*, not *de jure*.
- **BO1: hard cap 4.** `if ( player.num_perks >= 4 ) { … deny … }`
  `t5/_zombiemode_perks.gsc:1315`. **Tier 1.**
- **BO2: hard cap 4, but parameterised.** `level.perk_purchase_limit = 4;` `t6/_zm_perks.gsc:23`,
  checked via `player get_player_perk_purchase_limit()` (`:1874`) so persistent upgrades / map
  scripts can raise it. **Tier 1.**
- **Corroboration Tier 3 ×1:** BO1-Reimagined "Perks" section opens with *"Removed perk limit"*,
  confirming vanilla BO1 had one.

### 9. Wall-buy ammo refill pricing

**Tier 1.** `add_zombie_weapon()`, `t4/_zombiemode_weapons.gsc:16-63`,
`t5/_zombiemode_weapons.gsc:28-73` — identical logic:

```gsc
table_ammo_cost = TableLookUp( table, 0, weapon_name, 2 );          // zombie weapon CSV, column 2
if ( IsDefined(table_ammo_cost) && table_ammo_cost != "" )
    ammo_cost = round_up_to_ten( int( table_ammo_cost ) );
...
if ( !IsDefined( ammo_cost ) )
    ammo_cost = round_up_to_ten( int( cost * 0.5 ) );                // fallback: half of buy price
```

So **half price is the *fallback*, not the rule** — the shipped weapon table carries an explicit
per-weapon ammo price for most wall weapons, which is what the CSV column 2 lookup is for. The one
hard-coded exception in both titles: buying ammo for a **Pack-a-Punched** weapon off a wall costs
**4500** (`t4/_zombiemode_weapons.gsc:2076`, `t5/_zombiemode_weapons.gsc:2731/2742`).

The port's "half the buy price, always" is the correct default and a defensible simplification;
just do not treat it as exact canon for any specific weapon.

### 10. Zombie movement speed classes — the important one

**Tier 1, and behaviourally identical across WaW, BO1, BO2 and (ported) BO3.**

> **Verifier correction — "byte-identical" is overstated for the round scalar.** `set_run_speed()`
> itself *is* character-for-character identical (verified in WaW's Der Riese, Verrückt, Shi No Numa
> and Nacht der Untoten spawners, and in BO1's `ZM/Common/maps/_zombiemode_spawner.gsc`). The
> **round scalar is not**. WaW hard-codes a literal:
> `level.zombie_move_speed = level.round_number * 8;` (in each map's own `_zombiemode.gsc`).
> BO1/BO2 parameterise it: `set_zombie_var( "zombie_move_speed_multiplier", 8, false, column )`.
> `zombie_move_speed_multiplier` **does not exist anywhere in the WaW scripts** — searching the T4
> repo for it returns zero hits.
> The resulting numbers are the same (×8), so every figure in the table below stands. But two
> consequences matter: (a) the `column` argument means BO1's ×8 is **CSV-overridable** and WaW's is
> not, so the WaW value is actually the *more* certain of the two — the inverse of what "byte
> identical" implies; (b) anyone grepping the WaW scripts for the var name to confirm this document
> will find nothing and wrongly conclude the finding is fabricated.

Per-spawn roll (`t4/_zombiemode_spawner.gsc:244-260`, `t5/_zombiemode_spawner.gsc:378-395`,
`t6/_zm_utility.gsc`, and `treminaor/ugx-mod-bo3` which copies it with the comment
`//@fixme this is from WaW`):

```gsc
set_run_speed()
{
    rand = randomintrange( level.zombie_move_speed, level.zombie_move_speed + 35 );
    if      ( rand <= 35 ) self.zombie_move_speed = "walk";
    else if ( rand <= 70 ) self.zombie_move_speed = "run";
    else                   self.zombie_move_speed = "sprint";
}
```

Then `set_zombie_run_cycle()` picks the actual animation: `walk1..walk7`, `run1..run5`,
`sprint1..sprint3` (`randomintrange(1,8)`, `(1,6)`, `(1,4)` respectively). **The speed is entirely
the root motion of the chosen animation** — there is no numeric speed anywhere in the scripts.

Round scalar (`t4/_zombiemode.gsc:2096`, `t5/_zombiemode.gsc:3965`, `t6/_zm.gsc:3510`):

```gsc
level.zombie_move_speed = level.round_number * level.zombie_vars["zombie_move_speed_multiplier"];  // ×8
level.round_number++;
```

set at the **end** of each round, and initialised to `1`
(`t4/_zombiemode_spawner.gsc:9`, `t5/_zombiemode.gsc:665`). Therefore **during round R the base is
`8 × (R − 1)`**, and `1` during round 1. Verified: `level.round_number++;` occurs **after** the
`zombie_move_speed` assignment in the same end-of-round block, and `level.zombie_move_speed = 1;`
is the initialiser in both titles.

> **Verifier correction — do not trust Treyarch's comment here; trust the code.** The original brief
> called this comment *"the canonical description"*:
> *"Multiply by the round number to give the base speed value. 0-40 = walk, 41-70 = run, 71+ =
> sprint"*. That comment **disagrees with the shipped code**, which tests `rand <= 35` for walk, not
> 40. The comment is stale. The brief's own per-round mix table below is computed from the code (35)
> and is correct — but a reader who implemented the quoted "canonical description" instead would
> build the wrong distribution. **The code is canon; the comment is a stale artefact.**

`randomIntRange(min, max)` returns `min ≤ r < max` (Treyarch's own note in
`t4/_zombiemode_dogs.gsc:468`), so the roll is uniform over 35 integers. Exact per-round mix:

| Round | base | walk | run | sprint |
|---|---|---|---|---|
| 1 | 1 | **100%** | 0 | 0 |
| 2 | 8 | 80.0% | 20.0% | 0 |
| 3 | 16 | 57.1% | 42.9% | 0 |
| 4 | 24 | 34.3% | 65.7% | 0 |
| 5 | 32 | 11.4% | 88.6% | 0 |
| 6 | 40 | 0 | 88.6% | **11.4%** |
| 7 | 48 | 0 | 65.7% | 34.3% |
| 8 | 56 | 0 | 42.9% | 57.1% |
| 9 | 64 | 0 | 20.0% | 80.0% |
| **10+** | ≥72 | 0 | 0 | **100%** |

Notes:
- The mix is **rolled per zombie at spawn**, so a round is a *mixture* of classes, not one speed.
- **BO2 added a difficulty setting**: `zombie_move_speed_multiplier_easy = 2` used when
  `level.gamedifficulty == 0` (`t6/_zm.gsc:865-906`), which pushes the all-sprint round from 10 to
  ~36. WaW and BO1 have no such option.
- Verrückt uses the identical `set_run_speed()` (verified in
  `SP/ZM Maps/Zombie Verruckt/maps/_zombiemode_spawner.gsc:359`); its reputation for fast zombies
  comes from a different **animation set**, not different logic — further evidence that the speeds
  are asset-side.
- `zombie_new_runner_interval = 10` ("Interval between changing walkers who are too far away into
  runners", `t5/_zombiemode.gsc:699`) is **declared but never read** in the BO1 scripts I retrieved
  — it appears to be vestigial. Do not build on it.
- A burning zombie is slowed: `self.moveplaybackrate = 0.8;` (`t4/_zombiemode_spawner.gsc:2795`,
  `t5/_zombiemode_spawner.gsc:3761`) — the only script-side speed modifier in the whole system.

**Absolute m/s: not in the scripts, and I could not source a credible measurement.** See "What must
be measured".

---

## Recommendations for this project

All of these are pure GDScript/number changes. None touch the renderer, none add assets, none need
threads — they are exactly the kind of fix that is cheap under the single-threaded WebGL2 /
gl_compatibility / solo-dev constraints, and they are the highest gameplay-value-per-line changes
available.

1. **Replace the continuous speed scalar with three discrete classes rolled per spawn.** Port
   `set_run_speed()` verbatim; it is ~8 lines:
   ```gdscript
   # during round R:  base = 1 if R == 1 else 8 * (R - 1)
   var r := rng.randi_range(base, base + 34)   # Godot randi_range is inclusive both ends
   speed_class = "walk" if r <= 35 else ("run" if r <= 70 else "sprint")
   ```
   Use the table in Finding 10 as your acceptance test: round 1 must be 100% walkers, round 6 must
   be the first round with any sprinters, round 10 must be 100% sprinters. This single change is
   what makes the game losable, because it removes the "one speed for everyone" property that lets
   a player kite the entire horde in a single train forever.
2. **Set the class speeds by ratio to the player, and pick sprint ≥ player sprint.** Since canon
   gives no m/s, define them relative to your 4.88 m/s player sprint. Suggested starting point,
   explicitly a *design* choice and not a canon claim:
   `walk ≈ 0.45× (2.2 m/s)`, `run ≈ 0.72× (3.5 m/s)`, `sprint ≈ 1.0× (4.85 m/s)`.
   Rationale: your current 3.45 m/s ceiling is 0.71× player sprint — i.e. your *maximum standard
   zombie* is canon's *middle* class. Round-10+ zombies must be able to hold station on a sprinting
   player or the training loop never closes.
   Expose the three values as exported constants so they can be tuned in one place after playtesting.

   > **Verifier correction — two overstatements here, both checked against the source.**
   > *Player sprint 4.88 m/s is correct*: `player.gd` `SPEED := 3.15` × `SPRINT_MULT := 1.55` =
   > 4.8825. *Saturation at round 16 is correct*: `game_state.gd` `zombie_speed()` is
   > `minf(1.05 + r * 0.155, 3.45)`, and `1.05 + r·0.155 = 3.45` at `r = 15.48` → round 16.
   > But:
   > (a) **"single continuous speed" is not quite true** — `zombie.gd` already applies
   > `speed *= randf_range(0.86, 1.14)` per spawn, so there *is* ±14% per-zombie variance today.
   > What the port lacks is the *discrete three-class* structure and the round-driven shift in the
   > class mixture, not variance as such. The recommendation stands; the diagnosis needed narrowing.
   > (b) **"your maximum zombie is canon's middle class" is false for hounds.** `zombie.gd`
   > `_configure()` gives `"hound"` `speed = base_speed * 1.55`. Actual top speed is therefore
   > `3.45 × 1.55 × 1.14 ≈ 6.10 m/s` — already **well above** the player's 4.88 m/s sprint. Hounds
   > can and do outrun the player now. So "the port's speed ceiling is why the game is unlosable"
   > is only true of **standard zombies**; do not let this recommendation cause you to also scale up
   > hounds, which are if anything already too fast. Crawlers are `base_speed * 0.62`.
3. **Fix melee damage and Juggernog to 60 / 100 / 160.** Your 34 damage vs 100/250 is wrong twice
   over. 60 against 100 gives the canonical 2-hit down; 160 gives 3. If you want more forgiveness,
   change *Juggernog* (e.g. to 250 for a BO3-flavoured 5 hits) and document it as a deliberate
   deviation — do not change the melee damage, because 60 vs 100 is what makes the unperked player
   feel correct. Also add the `0.4 s` per-attacker damage cooldown; without it a horde of six
   zombies can delete a full-health player in a single frame.
4. **Replace the 16-29 kill counter with the score threshold + 3% roll.** It is not more code:
   one accumulator on lifetime points earned, one threshold that starts at 2000 and multiplies by
   1.14 on each drop, one `randf() < 0.03` per death, and the shared `≤ 4 per round` cap. This
   automatically makes drops rarer in the late game (because the threshold compounds and never
   resets) which is a balancing lever you currently do not have, and it makes Double Points and
   headshot play feed the drop economy the way players expect.

   > **Verifier corrections to the premise.**
   > (a) **The port's first drop is at 6 kills, not 16-29.** `game_state.gd` declares
   > `var next_drop_at := 6` (and resets to 6); only *subsequent* drops use `main.gd`
   > `Game.next_drop_at = 16 + _rng.randi() % 14`. "16-29" is right for steady state, wrong for the
   > opening drop. This matters because the opening drop is the one the 2,000-point rule most
   > changes.
   > (b) **The `≤ 4 per round` cap already exists** — `main.gd` gates on `Game.drop_count < 4` and
   > resets `Game.drop_count = 0` each round. Only the *trigger* needs replacing, not the cap. Do
   > not re-implement it.
5. ~~**Delete the zombie health cap.**~~ **Verifier correction: there is no health cap in the port —
   this recommendation attacks something that does not exist.** `game_state.gd` `zombie_hp()` is
   already `150`, `+100` per round through round 9, then `round(hp * 1.1)` with **no ceiling**,
   which is canon. The only deviations from the shipped loop are cosmetic: the port uses
   `round()` where Treyarch uses `Int()` truncation, and floats where Treyarch uses int32. Both are
   harmless (and the float/int64 difference is what spares you the round-163 overflow).
   **No action required.** If you want the round-163 quirk it must be added deliberately; you will
   never inherit it.
6. **Randomise dog rounds and guarantee the Max Ammo.** First at `randi_range(5, 7)`, then
   `+randi_range(4, 5)`. Force the Max Ammo drop on the last dog and **bypass the per-round cap for
   it** (reset the counter first, exactly as the shipped script does) — otherwise a round where four
   power-ups already dropped will silently swallow the guarantee, which is the single most-noticed
   bug in fan reimplementations.
7. **Make the headshot multiplier per-weapon, not global.** Keep the flat **+50 point** score bonus
   (that part *is* canon and title-stable), but move the damage multiplier into your weapon
   definitions with a per-weapon default. A single global 1.5× flattens the weapon roster, which
   matters more in a roguelike than it did in the original.
8. **Quick Revive: pick an era and be consistent.** If the port is WaW-flavoured, Quick Revive is a
   1500-point co-op-only revive-speed perk and solo has no second chance at all. If it is
   BO1-flavoured (recommended for a solo-only roguelike), it is 500 points, available from round 1
   without power, grants exactly one extra life per purchase, and the machine leaves after the third
   purchase. Model the machine's disappearance — it is a real pacing beat.
9. **Keep the half-price wall ammo default**, but add an optional per-weapon override field so
   individual weapons can be priced independently later, and hard-code the upgraded-weapon wall ammo
   at a fixed premium (canon: 4500) rather than deriving it.
10. **Perk cap 4** matches both WaW's de-facto limit and BO1/BO2's explicit one. For a roguelike this
    is also the right number: it forces a build choice. Make it a constant, not a magic number, since
    "remove the perk limit" is the single most common mod to this era.

---

## Coverage gaps

1. **WaW's zombie melee damage number is not pinned.** WaW never sets `self.meleeDamage` in script;
   the damage comes from the engine's `ai_meleeDamage` dvar scaled by
   `player_meleeDamageMultiplier = 100/250 = 0.4` (verified via `_gameskill.gsc` and cross-checked
   against the dogs' `dog_MeleeDamage 100 → 40 damage` comment). I could not find a WaW dvar dump
   listing `ai_meleeDamage`'s default; the Steam WaW console-command guides do not list it. **Best
   inference (explicitly an inference, not a citation):** BO1's legacy fallback constant
   `iDamage = 50;  // 45` is the pre-`meleeDamage` value, implying WaW zombies dealt **50** (i.e.
   `ai_meleeDamage = 125`), which would give WaW 2 hits without Jugg and 4 with. Treat WaW = 50 as
   *probable*, BO1/BO2 = 60 as *certain*.
2. **Absolute zombie speeds in m/s or units/s.** Not present in any script — root motion lives in
   the `.xanim` assets. No credible community measurement was found; the search results that looked
   promising were about a modded BO3 build, not vanilla WaW/BO1. See below.
3. **Per-weapon head damage multipliers for zombie-mode weapons.** The weapon asset files
   (`loc*Multiplier` fields) were not retrieved. Only a Tier-3 wiki claim about WaW *multiplayer*
   (1.4×, M14 1.5×) was found, which may not transfer to zombie-mode weapon variants.
4. **`mp/zombiemode.csv` was not retrieved.** `set_zombie_var()` looks every variable up in that CSV
   first and the script literal is only the fallback (`t4/_zombiemode_utility.gsc:1260`). Confirmed
   consequence: BO1's script default for starting score is 3000 but the shipped game starts you at
   500, so the CSV **does** override in practice. Every Tier-1 number above is the script default;
   for the specific values I quote, the community-observed behaviour matches the script default in
   every case I could cross-check (50/kill, 2000 drop increment, 4/round, 2500 Jugg, 500 solo QR),
   but I cannot prove the CSV does not shift something I did not cross-check.
   **Verifier update — partially resolved, and the scope of the risk is now known.** The
   first-power-up-at-2,000-earned claim is *immune* to this gap (the starting score cancels on both
   sides of the threshold — see Finding 2). Separately, the gap does **not** apply at all to WaW's
   speed scalar, which is a hard-coded literal `× 8` rather than a table variable. It *does* remain
   live for every BO1/BO2 value declared with the trailing `column` argument — which, from the
   declarations I read, includes `zombie_health_start`, `zombie_health_increase`,
   `zombie_health_increase_multiplier`, `zombie_move_speed_multiplier`, `zombie_spawn_delay`,
   `zombie_max_ai` and `zombie_ai_per_player`. Values declared *without* `column` (the score
   bonuses, `zombie_powerup_drop_max_per_round`, the perk costs, `zombie_perk_juggernaut_health`)
   are script-literal and cannot be table-overridden. That is a sharper statement of the risk than
   the original gap and it exonerates the two headline numbers (60 melee, 160 Jugg).
5. **The wiki claim that WaW Verrückt/Shi No Numa Juggernog boosts regen instead of health** could
   not be verified or refuted; the shipped (patched) Verrückt script sets 160/160. It may describe
   a launch-day build.
6. **Fandom is hard-blocked to WebFetch** (HTTP 402 on `callofduty.fandom.com`). I did not escalate
   to the browser tier because the brief rates that source Tier 3 at best and the shipped scripts
   already answer every question it would have. The community positions quoted above come from
   search-result summaries of those pages, which is weaker than a direct read — treat the Fandom
   claims in Finding 1 as reported-secondhand.
7. **Round-count / spawn-rate formula per player count** was out of scope and is not covered here;
   only the raw vars (`zombie_max_ai 24`, `zombie_ai_per_player 6`, `zombie_spawn_delay 2.0 × 0.95`)
   were confirmed.

---

## What must be measured rather than researched

### Zombie walk / run / sprint speeds in absolute units

This genuinely cannot be researched: the values are root-motion properties of the `.xanim` assets,
they differ per animation *within* a class (`walk1..walk7` are not all the same speed), and Verrückt
proves they differ per map. Anyone who quotes you a single m/s number for "a zombie" is guessing.

**Procedure A — direct, if you can run WaW or BO1 (Plutonium t4/t5 or a retail copy):**
1. Load a zombie map in solo, open the console.
2. `/give` yourself nothing; instead spawn on a long straight (Der Riese's factory floor, Kino's
   theatre aisle) and use a known-length reference: place two `map_restart`-stable landmarks and
   measure the distance between them with `/viewpos` at each point (`viewpos` prints world units;
   1 unit = 1 inch = 0.0254 m).
3. Record 60 fps video. Force a class by round: **round 1** is 100% walk, **round 5** is 88.6% run
   (discard the ~11% walkers by eye), **round 10+** is 100% sprint.
4. Frame-count a zombie traversing the measured distance, ignoring the first and last 0.5 s
   (acceleration and pathing turns). speed = distance_units / (frames / 60) × 0.0254 m/s.
5. Repeat n ≥ 10 per class and report median and spread — the spread *is* part of the answer,
   because the per-animation variance is what makes a horde spread out into a train.
6. Simultaneously measure the player: `/g_speed` reports the base run speed (default **190**
   units/s = 4.83 m/s); confirm the sprint scale empirically the same way rather than trusting
   `player_sprintSpeedScale`.

**Procedure B — ratio-only, from public footage, if you cannot run the game:**
Use any clean 60 fps round-1 and round-15 solo clip on a map with known geometry. Rather than
absolute speed, measure **closure rate**: pick a stretch where the player sprints in a straight line
with a sprinting zombie behind and measure whether the gap opens, closes or holds, in pixels/second
normalised by a known-width doorway. That yields the ratio `v_sprint_zombie / v_sprint_player`,
which is the only number your design actually needs.

**Then, and this is the part that matters for the port:** whatever number you land on, tune against
the *invariant*, not the number. The invariant is: **a round-10+ sprinter must be able to hold or
close distance on a player sprinting in a straight line, and must lose distance only when the player
takes an efficient training loop.** Verify it in your own build with a repeatable test — spawn one
sprinter, sprint in a straight line for 10 seconds, log the gap. If the gap grows monotonically, the
game is unlosable no matter what the source numbers say.

### Hits-to-down

The arithmetic above (2 / 3 hits) is derived from the shipped values, but the community consistently
reports 4-5 with Juggernog. If that discrepancy matters to your tuning, it is settleable in ten
minutes and not by more reading: load BO1 solo on Kino, buy Juggernog, stand still against a single
round-6 zombie with the health bar mod or the on-screen blood overlay as your indicator, and count
swipes to downed. Repeat three times. Record whether the 2.4 s regen window ever fires between
swipes — that is the most likely explanation for the community's higher counts, since a single
zombie's swipe cadence may exceed the regen delay while a horde's does not.

*(Verifier: the BO3 arithmetic now supplies a second, better explanation for the community's "5
hits / 250 HP" — it is exactly BO3 with **upgraded** Juggernog: 100 + 150 = 250, and
⌈250/60⌉ = 5. That is an era conflation, not a measurement error, and it does not require the regen
hypothesis. The regen test is still worth ten minutes, but the discrepancy is now largely accounted
for.)*

---

## Verification pass

Adversarial verification performed 2026-07-27 by a second agent, against the shipped GSC and against
this repository's actual source. Method: rather than re-reading the original brief's citations, I
**independently re-derived** the load-bearing numbers from `plutoniummod/t4-scripts`,
`plutoniummod/t5-scripts` and `shiversoftdev/t7-source` via the GitHub API (repo-scoped code search
plus whole-file retrieval), and re-simulated the arithmetic. All port claims were checked against
the files in `scripts/`.

### Scope note on the "Godot 4.x vs 3.x" and "Forward+ vs gl_compatibility" traps

**Not applicable to this brief, by construction.** R4 contains no engine claims. Every number in it
is a game-design constant from 2008-2012 Treyarch GSC plus arithmetic; the only Godot-touching
content is Recommendation 1's four-line `randi_range` snippet and Recommendation 5's remark about
integer width. Both were checked: `RandomNumberGenerator.randi_range(from, to)` is inclusive at both
ends in Godot 4 (the brief's snippet correctly compensates with `base + 34` against Treyarch's
half-open `randomintrange`), and Godot 4 `int` is 64-bit, so the round-163 overflow genuinely cannot
be inherited. **No recommendation in this document touches the renderer, shaders, threading or
asset loading**, so the single-threaded WebGL2 / `gl_compatibility` / GitHub Pages constraints do
not bear on any of it. This is the cheapest research item in the set to act on.

### Confirmed at Tier 1 (re-read from shipped source by the verifier, not taken on trust)

| Claim | Verified where | Status |
|---|---|---|
| `self.meleeDamage = 60;	// 45` | T5 `ZM/Common/maps/_zombiemode_spawner.gsc` | **Confirmed**, exact text incl. the `// 45` comment |
| 60 is the *final* applied damage (no downstream multiplier) | T5 `_zombiemode.gsc` player damage callback | **Confirmed** — callback unconditionally overwrites `iDamage`; full path traced (new work) |
| `zombie_perk_juggernaut_health = 160`, `_upgrade = 190`; `80/95` under `mutator_susceptible` | T5 `ZM/Common/maps/_zombiemode_perks.gsc` | **Confirmed**, both branches read |
| WaW Juggernog `160` | T4 `SP/ZM Maps/Der Riese/maps/_zombiemode_perks.gsc` | **Confirmed** |
| BO3 Juggernog `100` / upgrade `150`, applied **additively** | T7 `scripts/zm/_zm_perk_juggernaut.gsc`, `_zm_perks.gsc` | **Confirmed** — and it corrects the brief's own table |
| `set_run_speed()` body, `rand <= 35` / `<= 70` / else | T5 spawner + T4 Der Riese, Verrückt, Shi No Numa, Nacht spawners | **Confirmed verbatim** |
| Round scalar `× 8`; `zombie_move_speed = 1` init; `round_number++` *after* the assignment | T4 per-map `_zombiemode.gsc` (literal 8); T5 `_zombiemode.gsc` (`zombie_move_speed_multiplier`, 8) | **Confirmed**, with the WaW/BO1 mechanism difference corrected above |
| `zombie_health_start 150`, `increase 100`, `increase_multiplier 0.1`; `ai_calculate_health()` loop | T5 `_zombiemode.gsc` | **Confirmed verbatim** |
| Health table (550 / 950 / 1045 / 1679 / 2701 / 4348 / 7000 / 18151 / 47073 / 75809 / 5,525,295 / 648,618,590) and **int32 overflow first at round 163** | Re-simulated from the exact integer loop | **Confirmed to the round and to the digit** |
| Power-ups: increment `2000`, `*= 1.14`, never reset; `score_to_drop` uses lifetime `score_total` | T5 `_zombiemode_powerups.gsc` `watch_for_drop()` | **Confirmed verbatim** |
| `randomint(100)`; `if (rand_drop > 2)` → **3%** forced drop | T5 `_zombiemode_powerups.gsc` `powerup_drop()` | **Confirmed** |
| `zombie_powerup_drop_max_per_round = 4`, reset in `powerup_round_start()`, and the cap is checked **before** the 3% roll so it gates both paths | T5 `_zombiemode_powerups.gsc` | **Confirmed** (the ordering detail is new work) |
| First drop at 2,000 points *earned*, independent of the CSV starting score | T5 `_zombiemode.gsc` + `watch_for_drop()` | **Confirmed and upgraded** — see Finding 2 note |
| Dog rounds `randomintrange( 5, 8 )` + Treyarch's `PI_CHANGE` comment | T5 `ZM/Common/maps/_zombiemode_ai_dogs.gsc` | **Confirmed verbatim** |
| Dog `self.meleeDamage = 40`; `SetSavedDvar("dog_MeleeDamage","100")` with the ÷0.4 comment; `player_meleeDamageMultiplier = 100/250` | T5 `_zombiemode_ai_dogs.gsc`, `SP/Common/maps/_gameskill.gsc` | **Confirmed verbatim** |
| Score: `zombie_score_kill_1player..4player = 50`; `bonus_head 50`, `bonus_melee 80` | T5 `_zombiemode.gsc` | **Confirmed** |
| `ignore_enemy_timer = 0.4` | T5 `_zombiemode.gsc` | **Confirmed** |
| `zombie_spawn_delay 2.0`, `× 0.95`/round, floor `0.08` | T5 `_zombiemode.gsc` | **Confirmed verbatim** |
| `zombie_max_ai 24`, `zombie_ai_per_player 6` | T5 `_zombiemode.gsc` | **Confirmed** |
| Perk cap `num_perks >= 4` (BO1) | T5 `_zombiemode_perks.gsc` | **Confirmed** |
| Perk costs 2500 / 1500 / **500 solo** / 3000 / 2000 / 2000 / 2000 / **1000** Deadshot / 4000 Mule Kick; default 2000 | T5 `_zombiemode_perks.gsc` | **Confirmed**, every value |
| Solo Quick Revive: `solo_lives_given >= 3` → `flag_set("solo_revive")` | T5 `_zombiemode_perks.gsc` | **Confirmed** |
| `zombie_new_runner_interval` declared but never read | Declared in T5 `_zombiemode.gsc`; **absent** from the T5 spawner | **Confirmed** as far as the two files go |

### Corrected

1. **BO3 hits-to-down row was garbled** ("5 (if base 150)"). Correct: BO3 Juggernog is additive,
   `100 + 100 = 200` (4 hits) base and `100 + 150 = 250` (5 hits) upgraded. This *strengthens* the
   document — the community's "250 HP / 5 hits" folklore now has an exact source rather than a
   hand-wave.
2. **"Byte-identical WaW→BO2" for the speed system was overstated.** `set_run_speed()` is identical;
   the round scalar is not. WaW hard-codes `round_number * 8`; `zombie_move_speed_multiplier` does
   not exist in the WaW scripts at all. Same numbers, different mechanism, and it inverts which
   title's value is more certain.
3. **Treyarch's own comment ("0-40 = walk") contradicts the shipped code (`rand <= 35`)** and was
   being quoted as "the canonical description". Demoted; the code is canon.
4. **Recommendation 5 ("delete the zombie health cap") attacked a strawman** — `game_state.gd`
   `zombie_hp()` already implements the canon curve uncapped. Struck; no action required.
5. **Recommendation 4's premise was partly wrong about the port**: the first drop is at **6** kills
   (`next_drop_at := 6`), not 16-29, and the `≤ 4 per round` cap **already exists** in `main.gd`.
6. **Recommendation 2's "your maximum zombie is canon's middle class" is false for hounds** —
   `zombie.gd` gives hounds `base_speed * 1.55`, so the real ceiling is ~6.10 m/s against a 4.88 m/s
   player sprint. The port also already has ±14% per-spawn speed variance. Narrowed to standard
   zombies, with an explicit warning not to scale hounds up.
7. **Coverage gap 4 (CSV override) sharpened**: it cannot affect the 2,000-point claim, does not
   apply to WaW's literal `× 8`, and applies only to values declared with the trailing `column`
   argument — which excludes the two headline numbers (melee 60, Jugg 160).
8. **All line numbers downgraded.** GitHub's code search returns fragments, not line numbers, so I
   verified *file + symbol + exact text* for everything above but could **not** verify a single one
   of the brief's line citations (`:244`, `:4601-4607`, `:69`, `:1475-1481` …). Treat every line
   number in this document as decorative. The file paths as given are also lightly wrong — the real
   T5 paths are `ZM/Common/maps/…`, not `t5/…`.

### Provenance audit — where the brief's corroboration is weaker than it looks

- **The Tier 1 spine is genuinely Tier 1 and genuinely independent of the wikis.** I re-derived it
  from the repos myself. This is the document's real strength and it survived every attack I made.
- **`Jbleezy/BO1-Reimagined` is doing a lot of work and is ONE source.** It is cited as
  "independent corroboration" for the 60 melee, the 3% drop chance, the ×1.14, the round-163
  overflow, the dog cadence and the perk limit — six times, always the same repo. It is a *good*
  source (a rebalance mod that documents the vanilla values it changes), but six citations of one
  author is **one** corroboration, not six. Since I independently re-derived all six from the
  shipped scripts, this no longer matters for those claims — but the document should not be read as
  having six independent confirmations.
- **One genuinely independent corroboration of Jugg = 160 was found** during this pass: a Plutonium
  forum thread on changing Juggernog health uses `getDvarIntDefault("juggHealthBonus", 160)` as the
  vanilla default, from a different community and toolchain than Jbleezy. Tier 3, but real.
- **The Fandom/Reddit "250 HP, 5 hits" position was never read directly** (the brief records a 402
  block on `callofduty.fandom.com` and did not escalate). My searches reproduced the same claim in
  summary form. This is unchanged: the community position is **reported secondhand**. It no longer
  matters much, because the BO3 arithmetic now explains it exactly.

### Still uncertain — do not treat these as settled

1. **WaW's zombie melee damage remains unpinned.** The brief's inference (WaW = 50, from BO1's
   `iDamage = 50; // 45` legacy fallback) is reasonable but is still an **inference, not a
   citation**. I additionally established that BO1's `ai_meleeDamage` dvar path is a pay-turret
   case, which means the "engine dvar scaled by 0.4" story cannot simply be transplanted to explain
   WaW's player swipe either. **If your port is WaW-flavoured rather than BO1-flavoured, this number
   is not sourced.** Recommendation: use BO1's 60, which *is* sourced, and label the port BO1-era.
2. **Absolute zombie speeds in m/s.** Unchanged and genuinely unresearchable — root motion in
   `.xanim` assets. The brief is right that this must be measured, and right that the *invariant*
   (a round-10+ sprinter must hold or close on a sprinting player) is the thing to tune against.
   This is the single most important open item and no amount of further reading will close it.
3. **Per-weapon head damage multipliers.** Unretrieved. The "no global 1.5×" conclusion is safe
   (it rests on the *absence* of hit-location damage scaling in the zombie scripts, which I did not
   re-verify exhaustively but which is consistent with everything I read). The positive per-weapon
   values are unknown.
4. **The "+4 or +5" dog-round gap.** I confirmed the *first* dog round (`randomintrange(5,8)`)
   verbatim; I did **not** independently confirm the subsequent `randomintrange(4,6)` increment.
   Tier 1 in the brief, unverified by me.
5. **Der Riese / Factory lowering the per-round cap to 3.** Not verified by me.
6. **The Verrückt "regen instead of health" wiki claim.** Still unresolved, as the brief says.
   Low stakes.
7. **BO1's `zombie_health_start` etc. are CSV-overridable** (they carry the `column` argument).
   The script defaults are certain; that the shipped CSV does not alter them is not.

### What the project would most regret trusting

In descending order of cost-if-wrong:

1. **That the port's speed problem is one number.** It is not. Fixing `zombie_speed()` without
   noticing that hounds are already at ~6.1 m/s, and that the port already has per-spawn variance,
   risks making hounds unplayable while fixing standard zombies. This is the correction most likely
   to cause real damage if missed.
2. **The line numbers and file paths.** None of them are real. Anyone opening `t5/_zombiemode.gsc:244`
   to check this document will not find it and may conclude the whole brief is fabricated — when in
   fact its substance is solid. Verify by symbol, not by line.
3. **"Byte-identical across titles."** If you later port a WaW-specific behaviour by grepping for
   `zombie_move_speed_multiplier`, you will find nothing and draw the wrong conclusion.
4. **Recommendations 4 and 5 as written**, which would have you re-implement a cap that already
   exists and delete one that does not.
