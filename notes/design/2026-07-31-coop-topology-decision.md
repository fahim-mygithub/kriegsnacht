# Co-op topology: why the players are client-authoritative

This overrules the brief I wrote for the research pass, which specified a
**host-authoritative** topology throughout. The replication survey came back and the
survey is what changed my mind. Recording the reversal here because CLAUDE.md is
right that an undocumented departure reads as an accident.

---

## What the survey found

`notes/` has the full inventory. The three findings that decide the topology:

1. **`Player` reads `Input` directly, in five places, on the physics tick**
   (`player.gd:536`, `:580`, `:621`, `:666`, `:672`, plus every edge in
   `_unhandled_input` `:420-493`). Host authority means every one of those becomes
   "read this tick's input frame", and *then* means prediction and reconciliation,
   which means `_physics_process` has to be re-runnable — while it currently also
   emits signals, plays sounds and writes `Game`. The survey called this "the single
   largest refactor in the package" and it is not wrong.

2. **`Game.points` and `Game.perks` are globals with 57 call sites**
   (player.gd 18, interaction_system.gd 17, hud.gd 10, weapons.gd 5, and the rest).
   `weapons.gd`'s five statics take no player argument at all. Host authority makes
   every one of those per-player.

3. **WebSocket is TCP.** A dropped packet head-of-line-blocks the next snapshot, so
   an authoritative 20 Hz stream becomes a 100 ms hitch on one retransmit — felt
   directly as input lag, because under host authority the player's *own* movement is
   waiting on that stream.

Together those are multiple weeks, and the failure mode of getting them half-right is
a game that feels broken for everyone rather than one that is missing a feature.

## The decision

**Each client simulates its own player. The host simulates the zombies.**

| | Authority |
| --- | --- |
| Your own player: movement, aim, shooting, reload, stamina | **you** |
| Your own points, perks, weapons, ammo | **you** |
| Every zombie: spawn, path, attack, death | **host** |
| Round number, power, doors, box position | **host** |
| Damage you deal to a zombie | you claim it, host applies it |

## Why this is the right call and not merely the cheap one

**It deletes problems 1 and 2 outright rather than deferring them.** If a client owns
its player, the player keeps reading `Input` exactly as it does today — no input
frames, no prediction, no reconciliation, no re-runnable physics. And `Game.points`
and `Game.perks` stay one-per-process, so all 57 call sites keep working unmodified.
The refactor the survey ranked hardest simply does not arise.

**Per-player economy is canon anyway.** BO1 co-op gives each player their own points
and their own perks; there is no shared wallet. So the thing that falls out of this
topology for free is also the thing the reference asks for. `Game.points` being
local to each client *is* the correct model — it was never a global that needed
splitting, it was a per-player value that happened to have one player.

**Your own movement never waits on the network.** Under host authority, TCP
head-of-line blocking is felt as your own character stuttering. Here a retransmit
delays other people's avatars and the zombies, which interpolation absorbs, while
your own input stays at 60 Hz and local. On a relay we measured at 23 ms median but
which will be 40–160 ms for distant players, that difference is the whole feel of the
game.

**The zombies stay authoritative, which is where authority actually matters.** A
horde that disagrees between clients is the one desync a player cannot tolerate —
being hit by something that is not on your screen. Keeping the horde on one simulator
solves that, and the survey notes zombies are already puppet-capable: `target == null`
makes `Zombie` render without simulating (`zombie.gd` §2.3), and derived state
(`_view`/`_flip`, `speed_scale`, the corpse clock, plank colliders) is a pure function
of what is already on the wire and must never be sent.

## What this costs, honestly

**Cheating is possible.** A modified client can teleport, claim kills it did not make,
or award itself points. This is a co-op PvE hobby game played with friends over a code
you read aloud; there is no ladder and no reward to protect. Spending the complexity
budget on anti-cheat here instead of on the game would be the wrong trade. Stated
plainly rather than left for someone to discover.

**The host is a real host.** If the host leaves, the horde stops. Host migration is
deferred; the session ends and says so, which is at least honest and is what BO1
itself does when a host drops in local play.

**Damage is a claim, not a fact.** Client says "I hit zombie 7 for 210"; the host
applies it and broadcasts the result. That is one relay round trip between your shot
and the zombie dying on your screen. Hit *feedback* — blood, the hitmarker, the
sound — fires locally and immediately off the local raycast, so the shot feels
instant even though the death is confirmed late. This is the standard trick and it is
the reason the delay is acceptable.

## What is deferred, explicitly

Not "left out" — deferred, ranked, and none of it is load-bearing for a session that
works:

1. Downs and revives. There is no "teammate stands over you" verb anywhere in the
   project today (`player.gd:1191-1215` self-revives on a global perk), and
   `Game.DOWNED_TIME = 7.0` is a solo self-revive window, not a co-op bleedout.
   Co-op also inverts the perk rule — all perks lost on down — and `player.gd:1184-1187`
   already says so in a comment. The co-op Quick Revive price of 1500 is already
   sitting unused at `weapons.gd:78`.
2. Shared world interaction: doors, power, barricades, the box. Event replication is
   designed for but the box is a single-slot machine with no owner
   (`mystery_box.gd:46`), so two players pulling it is undefined until it has one.
3. Remote-player audio and FX. 42 `Sfx.play*` sites sit inside host-only paths, and
   `fx.gd` binds to `player.impact` / `player.fired` (`main.gd:21-23`), which only
   fire locally. Without this, other players shoot silently.
4. Four shadow-casting torches. `player.gd:310-313` records that the torch is the one
   shadow-casting light in the game and why; four of them is a `gl_compatibility`
   budget problem with no cheap out. Remote avatars get `shadow_enabled = false`.
5. Power-up sharing. `powerup_manager.gd:63` collects on distance to the single bound
   player.

## Tick rates, from measurement

`notes/net/2026-07-31-realtime-probe.md` has the numbers and how they were taken.
20 Hz snapshots with 12 Hz coalesced input keeps a 4-player room at ~56 messages a
second, inside the burst the relay was measured to absorb without throttling. Remote
entities interpolate on a 100 ms buffer, which covers the measured 79 ms p95
inter-arrival gap.
