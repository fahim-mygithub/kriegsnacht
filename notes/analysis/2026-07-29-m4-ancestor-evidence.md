# M4 design questions, resolved against the sources

**Date:** 2026-07-29. Companion to `2026-07-29-m3-ancestor-evidence.md`, same two sources
and the same rule: the **reference** is Call of Duty: Zombies (BO1 era) and wins; the
**ancestor** (`kriegsnacht.html`) is evidence, not authority.

Milestone 4 differs from 3 in one important way: **much of it has no ancestor at all.**
Traps, grenades, the Monkey Bomb, ADS and the 8-direction atlas are additions from the
reference, not restorations. Where there is no ancestor code, say so and design against
BO1 rather than inventing a provenance.

---

## Has a full ancestor implementation — port it

### Projectiles (T2.4)

The ancestor has the whole system and the port has none of it. `updateProjectiles`
(html:2594-2620) manually integrates position, applies gravity to the grenade and not to
the ray, and detonates on `blocked()`, on `z < 0.12`, or on life expiry.

The weapon data is already in the port's table verbatim and is currently **dead**:

| | `dmg` | `proj` | `splash` | `splash_dmg` |
|---|---|---|---|---|
| China Lake | 120 | `grenade` | 2.6 | 1150 |
| Ray Gun | 180 | `ray` | 1.7 | 620 |

Launch parameters, html:2555-2564: ray `spd 23`, `vz 0`, `grav 0`; grenade `spd 16`,
`vz 1.1`, `grav 2.6`. Both spawn at `0.35` in front of the player at `z = 1.42`,
lifetime 3 s, collision height `h = 0.30`.

`explode()` (html:2578-2592) is the shared detonation and it does three things the port
must not lose: falloff is `dmg * (1 - d/radius * 0.55)` — so the edge of the blast still
does 45%, not zero; it is **line-of-sight gated** (`hasLOS`, html:2589); and it hurts the
player inside `radius * 0.75` for `24 * (1 - pd/(radius*0.75))`, which is the only
self-damage in the game.

**Why this matters more than it looks:** with `proj` unimplemented, the Ray Gun is a
180-damage single-target hitscan — **strictly worse than the 500-point M14 at 185**. Its
declared 620 splash is dead data pointing at a subsystem that was never ported, and
nothing errors, so the weapon reads as merely disappointing rather than broken. The
travelling `OmniLight3D` is the point of the Ray Gun: it lights the corridor as it flies.

### Corpses and death variants (T2.6)

The ancestor already has per-palette death strips and plays them on a fixed clock:
`set.death[min(len-1, (dieT * (len/0.55))|0)]` (html:2070) — 0.55 s of animation, corpse
removed at 0.75 s (html:2256). The port has the strips (`sprite_lib.gd` SPEC: 4 death
frames for zombies, 3 for crawlers and hounds) and plays them.

What is missing is *variation*: `zombie.take_damage` receives the cause and the killing
direction at every call site and **discards both**. Threading them into `_die` is nearly
free and is what makes a nuke read as a wave rather than a simultaneous flop — stagger by
`distance_to(player) * 0.045`.

---

## No ancestor — design against the reference

Traps (T3.3), grenades and the Monkey Bomb (T3.1), ADS (T2.3), the perk roster beyond the
four in `PERKDEF`, and the 8-direction atlas do not exist in `kriegsnacht.html`. Two notes:

- The **Monkey Bomb needs no new systems** beyond a global `Game.lure_position` that
  zombies target instead of the player — the flow field already re-solves on demand.
- The ancestor draws exactly **one** view of each enemy (`makeZombieSet`, html:973). The
  8-direction atlas is five new draw routines plus `flip_h` for the other three.

---

## Confirmed by arithmetic, not by assertion

**The collider is a third of the drawn sprite.** `zombie.gd:229` sets `caps.radius = 0.26`
— a 0.52 m capsule. The walker sprite is 48 px wide at `1.82 / 64 = 0.02844` m/px, so it
draws **1.365 m** wide. Each side therefore carries ~0.42 m of billboard that `_hitscan`
cannot hit, which is ~31% of the drawn width per side before accounting for the
transparent margin inside the 48 px cell (measure that margin before quoting a final
figure — the widely-repeated "~40%" is an estimate, not a measurement). This reads in
play as broken hit registration, and it is the reconciliation §4.2 asks for.

**Every wave marches in lockstep.** Nothing randomises the starting walk frame, so every
zombie spawned in a round is on frame 0 together. Free variety, currently unused.

**Animation speed is decorrelated from actual speed.** `zombie.gd:274` sets
`_sprite.speed_scale = Rng.randf_range(Rng.VISUAL, 0.85, 1.2)` **once, at `_ready()`**.
It is never tied to velocity, so a *sprint*-class zombie can play a slower cycle than a
*walk*-class one. The ancestor ties it to speed directly — `z.anim += dt * spd * 2.6`
(html:2340) — so this is a port regression, not a missing feature.

Note the stream: `speed_scale` correctly draws from `VISUAL`. If it becomes a function of
the speed class it stops being cosmetic input and must not draw from a gameplay stream
either — derive it, do not re-roll it.
