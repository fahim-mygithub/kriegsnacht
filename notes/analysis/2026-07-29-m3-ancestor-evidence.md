# M3 design questions, resolved against the sources

**Date:** 2026-07-29. **Audience:** whoever writes or reviews the Milestone 3 economy,
downed-state and mystery-box work.

Two sources, and they are not the same thing:

- **The reference** is Call of Duty: Zombies, Black Ops 1 era. The project's stated
  aim is to get closer to it. Where it and the ancestor disagree, it wins.
- **The ancestor** is `kriegsnacht.html` in the repo root — the browser raycaster this
  is a port of. It is *evidence*, not authority: it is frequently right about intent,
  occasionally wrong, and in one case below contains outright dead code.

The gap analysis (`2026-07-27-gap-analysis.md`) and `SYNTHESIS.md` list the Milestone 3
economy defects. **Several are already fixed** and one prescription is wrong. Checked
line by line below, so the next pass corrects what is actually broken rather than
re-fixing what is not.

---

## Already fixed — do not re-fix, do not re-report

| Claimed defect | Reality |
|---|---|
| "the knife hits an arbitrary group-order target rather than the nearest" | Fixed. `player.gd:623-636` picks the nearest by `best_d`. |
| "the knife can never headshot, by construction" — listed as a defect | Correct *and intended*. `player.gd:639` damages one notch under the threshold, and the ancestor agrees: `zombieDamage(best, P.meleeDmg, false)` at html:2650 passes `false` for headshot. Not a bug in either. |
| "the square-not-conical spread distribution" (listed under M4) | Fixed. `player.gd:543-547` samples in polar coordinates with a `sqrt` radius, which is the correct uniform-disc sample. |
| "`drop_tick` never resets so drops land earlier the longer a run goes" | Fixed, by replacing the model rather than patching it. The ancestor's counter (html:2380-2383) *does* reset — `G.dropTick=0` on each drop — so the never-resetting counter was a port regression. It is now points-earned with a compounding threshold (`game_state.gd:351-356`), which is the BO1 model. |

## Still broken — confirmed present

**Thundergun scores 100% headshots.** `player.gd:595` aims `_apply_hit` at
`head_threshold() + 0.01`, so every kill in the wedge is credited as a headshot at 100
points instead of 60. The ancestor passes `false` (html:2543). The comment at
`player.gd:588-594` says this "keeps its headshot payout exactly as it was" — which is
true, and the payout it preserves is the wrong one.

**Thundergun ignores line of sight.** `_cone_blast` has no occlusion test, so the wedge
kills through walls. The ancestor gates it: `if(!hasLOS(P.x,P.y,z.x,z.y)) continue;`
(html:2541). The port has `_has_los` already — this is a one-line restoration.

**Explosive splash ignores line of sight.** Same defect, same fix, same ancestor
precedent: `explode()` gates on `hasLOS` at html:2589.

**A teddy-bear pull is strictly better than a normal pull.** `main.gd:908-915`: on
`offering` the player is handed `_box_gun` and *then* the box relocates if
`_box_teddy`. So a teddy costs 950, yields a weapon, and moves the box. The ancestor
never reaches an offer on a teddy — `boxState` goes straight to `'teddy'`, plays the
jingle, toasts `THE BOX HAS MOVED`, and the 950 buys nothing (html:2826-2828). The
ancestor is right and matches the reference: the teddy *is* the loss.

---

## Design questions, answered

### The Thundergun cone: narrow it

The ancestor authors `cone: .62` (html:1470) and tests `dot < 1 - d.cone`, i.e.
`dot >= 0.38`. That is a half-angle of `acos(0.38) = 67.7°` — a **135.3° wedge**,
which is what the gap analysis's "134.8°" figure was pointing at. So the wide cone is
the ancestor's, not a port invention.

**Narrow it anyway.** The reference is BO1, where the Thundergun is a directed blast,
not a 135° sweep that clears everything in front of and beside the player. At 135° the
weapon deletes a room; the whole point of a wonder weapon is that positioning it well is
a skill. This is a deliberate departure from the ancestor and must be recorded as one.

### The downed state: follow the ancestor, which already matches solo BO1

The ancestor implements this fully and the port implements none of it —
`Player.revive()` is defined and called by nothing. The ancestor's model
(html:2359-2376):

- `goDown()` sets `hp = 0`. If the player holds Quick Revive: **consume that perk only**,
  `downed = true`, `downT = 7`, and force `P.slot = 0`. Otherwise, game over immediately.
- While downed: speed `1.15` instead of `3.15` (html:2940), no sprint (html:2935),
  the horizon drops by `H*0.17` (html:1748), spread ×1.4 (html:2531).
- `reviveUp()` restores **full** health and clears the damage overlay.

**Two corrections to the plan.** SYNTHESIS.md prescribes "perk loss on down (the single
biggest economic punishment in Zombies)". That is the **co-op** rule. In solo — which is
the only mode this game has — you keep your other perks and lose only Quick Revive.
The ancestor has this right; the plan does not. Do not implement blanket perk loss.

And the plan's "forced M1911" is `P.slot = 0` here: the ancestor forces the first slot,
which on a fresh run is the M1911 but need not be later. Forcing the *slot* is the
faithful reading and is also the cheaper one.

**One ancestor bug not to reproduce.** `hurtPlayer` early-returns on `P.downed`
(html:2349), so the downed-crawl attack that calls `hurtPlayer(24)` at html:2331 is
**dead code** — nothing can damage a downed player. That happens to match the reference,
where a downed player bleeds out on a timer rather than being finished off, so the
*behaviour* is correct. But the 24-damage branch is a wasted distance test in the hot
per-zombie loop and should not be ported as though it did something.

### The mystery box: the ancestor's state machine is the theatre

The port has three states (`idle | spinning | offering`); the ancestor has five, and the
two extra ones are the theatre T2.9 asks for (html:2818-2843):

- **`spin`** cycles a *displayed* weapon at an accelerating rate —
  `0.09 + max(0, 2.9 - timer) * 0.055` seconds per swap — so the reel visibly slows into
  its result. The result is whatever was last shown (`G.boxWeapon = G.boxSpinShow`),
  which is why the reel does not lie.
- **`teddy`** (2.2 s) replaces the offer entirely, as above.
- **`closing`** (0.6 s) runs after a take or a timed-out offer, so the lid animates shut
  instead of snapping.

The teddy roll is `boxUses >= 4 && random() < 0.16 * (boxUses - 3)`, which the port
already matches exactly (`main.gd:927`).

### Wall-buy ammo

The ancestor refills **only the owned gun's reserve**, not its magazine, and charges
`round(cost/2)` flat (html:2764). The port's 4500-for-a-PaP'd-weapon is a deliberate
BO1 canon addition and is correct.

The claim that the wall-buy "refills every gun including a PaP'd Ray Gun" is **already
fixed**: `player.gd:766` is `refill_gun(key)` and it matches on `g.key == key`, so it
touches exactly the one weapon. `refill_ammo()` — the one that does touch every gun —
is Max Ammo, which is supposed to.

### Line of sight — **resolved: `scripts/world/los.gd`**

~~There is no player-side LOS helper. `_has_los` exists only on `zombie.gd:547` and
works in grid space over `Vector2`s.~~ **Both halves of that were wrong** and package
INTERACT caught it. `Zombie._has_los` takes `Vector2`s but is *not* a grid walk — it is
already a physics ray on collision mask 1, between two points pinned at `y = 1.2`. The
sentence described the signature and mistook it for the implementation.

It is also an instance method (it needs `get_world_3d()`), so it cannot be lifted to a
static without passing the world in, and its baked 1.2 m eye height is wrong for
anything originating at the camera.

Resolved by extracting it to **`scripts/world/los.gd`**, reached by preload:

```gdscript
const LOS := preload("res://scripts/world/los.gd")
LOS.clear(world, a: Vector3, b: Vector3) -> bool          # true == nothing in the way
LOS.clear_flat(world, from: Vector2, to: Vector2, height := 1.2) -> bool
```

Four callers have to agree about what "can see" means — the AI's chase-vs-flow choice,
the Thundergun wedge, explosive splash, and the interaction scan. When they disagree
the disagreement is invisible until something dies through a wall, which is what
shipped. `MASK_WORLD = 1` only: enemies and the player are excluded so a body cannot
shield the body behind it, matching how the ancestor gates each splash target on its
own independent ray (html:2589).
