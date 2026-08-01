# Co-op multiplayer: menu, rooms, and a host-authoritative relay

Status: **design, approved for implementation in the stated slice.** Four research passes
fed this (engine limits, BO1 co-op canon, replication surface, Supabase limits). Where a
researcher was overruled it is marked **OVERRULE** with the reason. Every line citation
below was re-read against the working tree on 2026-07-31, not copied forward.

The transport already exists and is not speculative: `scripts/net/phoenix.gd` (337 lines,
pure framing), `scripts/net/realtime.gd` (306 lines, one channel), `scripts/net/session.gd`
(rooms, lobby, presence). Task #19 closed while this document was being written. Nothing
below asks for that layer to be rewritten; it asks for a **replication layer above it** and
a **game underneath it that can hold two players**.

---

## 1. Scope, and the scope cut

### 1.1 What the user asked for

"A menu and multiplayer using room host and codes." Rooms and codes are already provisioned
(`public.rooms`, five `SECURITY DEFINER` functions, a 28-glyph alphabet) and already wired
(`session.gd::host_room` / `join_room`). The unstated part — the part that is nine tenths
of the work — is *what happens after both players are in the room*.

### 1.2 The recommended slice

> **Two players. Host-authoritative over one Supabase Realtime public channel. The guest
> owns its own body and nothing else. 15 Hz snapshots, 15 Hz state reports, exactly one
> message type in each direction. Downs and revives are in. Drop-in, prediction, and the
> third and fourth player are out.**

### 1.3 The scope cut, stated plainly

**I am cutting the player count from four to two, and I am overruling
`session.gd:MAX_PLAYERS := 4` to do it.** This is the most important sentence in the
document, so here is the whole argument:

| | 2 players | 4 players |
|---|---|---|
| Free-tier session hours/month | **~9.3 h** | ~2.3 h (240 msg/s, over the documented 100/s cap) |
| Flow-field solves, worst frame | 2 × 1.585 ms = **3.2 ms** | 4 × 1.585 ms = 6.3 ms = 38% of a 16.67 ms frame |
| Shadow-casting torches | **2** | 4, against a renderer where each one re-draws every instance it touches (`player.gd:310-313`) |
| Canon count multiplier at r20 | **1.60×** → 162 spawns | 4.00× → 404 spawns, ~17 refills of a 24-alive cap |
| Balance evidence | 1.6× is inside the range `--sim` has explored | nothing in `notes/balance/` has ever modelled a 4× round |

Two is not merely cheaper. It is **the only count at which the message quota, the frame
budget, and the existing balance curves all stay in a regime this project has evidence
for.** Four players is a retune of every curve plus a rendering investigation plus a paid
Supabase plan, and it would land on top of a replication layer that has never run in a
browser. `MAX_PLAYERS` stays a constant and the protocol stays N-generic, so four is a
future retune rather than a future rewrite.

**Also cut, each with its reason:**

| Cut | Why |
|---|---|
| **Client-side prediction and reconciliation** | It is the single largest refactor in the project — `Player` reads `Input` in five places on the physics tick (`player.gd:536, 580, 621, 666, 672`) plus every edge in `_unhandled_input:420-493`, and reconciliation means re-running a `_physics_process` that also emits signals, plays sounds and mutates `Game`. Replaced by trusted-client movement (§2.3), which deletes the requirement rather than deferring it. |
| **Join-in-progress** | BO1 has none. `difficulty_init()` hands out starting points once behind `flag_wait("all_players_connected")` (`_zombiemode.gsc:1411-1432`); a late joiner would get zero and never be topped up. The lobby locks at START. Cutting this is *free correctness*. |
| **Seeded-run reproducibility inside a co-op session** | A client that applies host state has, by construction, an `Rng` sequence the host does not share. Recorded as a deliberate departure (§6.7) rather than discovered later. |
| **Dog rounds in co-op** | `_zombiemode_ai_dogs.gsc` was downloaded but its per-player count logic was never read. `MAX_ALIVE_DOGS := 8` (`game_state.gd:29`) has no canon N-term this project can cite. Co-op sessions skip dog rounds until someone reads that file. |
| **A remote first-person viewmodel** | `viewmodel.gd:536` parents to `_cam`. A remote avatar has no camera and needs no gun rig; it needs a third-person sprite with a muzzle flash. |
| **Voice, chat, emotes, names longer than 12 characters** | Not in scope, and a text channel is a moderation surface a hobby game should not open. |
| **Reconnect into a running match** | `realtime.gd` reconnects the *channel*; re-entering a *match* needs a full-world resync that is a package of its own. A dropped guest returns to the title screen. |
| **Anti-cheat** | Anyone holding a room code can already broadcast as the host (§8.7). PvE, no leaderboard, no persistence beyond a local profile. Not a threat model worth engineering against; the one cheap mitigation is listed as a risk fallback. |

### 1.4 What "genuinely fun and genuinely correct" means here

The emotional core of BO1 co-op is not four players. It is **training a horde together and
picking each other up.** Two players who can share a map, split doors, buy their own perks,
go down, and revive each other have all of it. Two players where one of them is a laggy
puppet with no revive verb have none of it.

So the slice keeps: shared world, shared power, shared box (with an owner lock), per-player
wallets, per-player perks, per-player weapons, downs, bleedout, revives, the co-op Quick
Revive, and the death/respawn cycle. It cuts everything whose absence a player would not
notice in a thirty-minute session.

### 1.5 The assumption this document proceeds under

The user asked for multiplayer without naming a count. **I proceed on the assumption that
two-player co-op satisfies "multiplayer using room host and codes",** and I have designed
the room/code/lobby layer to be N-generic so that raising `MAX_PLAYERS` later is a balance
and budget decision rather than a protocol one. If the user specifically wants four, the
answer is: ship two first, measure it in a browser, then reopen §1.3 with real numbers.

---

## 2. Topology

### 2.1 The decision

**Host-authoritative simulation, relayed through one public Supabase Realtime channel, with
trusted-client movement for the guest's own body and server-side lag compensation for the
guest's shots.**

There is no peer-to-peer link. Both clients hold a WebSocket to `us-east-1`; the host
simulates; the guest renders. The relay is a dumb pipe that neither validates nor stores.

### 2.2 Justified against the alternatives the researchers found

| Alternative | Verdict | Evidence |
|---|---|---|
| `ENetMultiplayerPeer` (Godot's normal answer) | **Impossible.** Every ENet socket goes through `NetSocket::create()` → `NetSocketWeb`, whose every method is `return ERR_UNAVAILABLE` (`platform/web/net_socket_web.h` @4.7). The shipped `docs/index.wasm` contains `NetSocketWeb` and zero hits for `getaddrinfo`. | engine-limits §2 |
| `WebSocketMultiplayerPeer` as a server | **Impossible.** `create_server()` calls `tcp_server->listen()` → the same stub. | `websocket_multiplayer_peer.cpp` @4.7 |
| `WebSocketMultiplayerPeer` as a client | **Alive but useless.** It runs its own peer-ID handshake and will only speak to another Godot WS server. It would connect to Supabase and then hang. Named separately because "the class works" is a trap here. | engine-limits §2 |
| **WebRTC DataChannel, unreliable/unordered** | **Alive on web** — `godot_js_rtc_*` glue is in `docs/index.js`, no GDExtension needed. Technically the *correct* transport: UDP semantics, no head-of-line blocking, direct peer path. **Rejected** because it needs a signalling server this project does not have, ICE/STUN/TURN that a GitHub Pages deploy cannot provide, and a NAT-traversal failure mode with no fallback. It would replace a known 23–160 ms with an unknown "works for some pairs of players". | engine-limits §2 |
| Dedicated authoritative server | **Rejected.** No host to run it on, and it makes the game's availability a bill. |
| Lockstep / deterministic simulation | **Rejected outright.** It would require every `Rng` draw on both machines to match, forever, including the known VISUAL-stream spread violation (CLAUDE.md constraint 5). One divergent float ends the match. |
| **WebSocket relay, host-authoritative** | **Chosen.** Proven end to end from Godot against this exact project: `phx_join` → ok, presence both ways, 5/5 broadcasts byte-correct, clean leave (`notes/net/2026-07-31-realtime-probe.md:76-94`). | the probe |

### 2.3 Trusted-client movement — the load-bearing choice

The guest runs its own `move_and_slide` locally against the same static map and **sends the
resulting position**, not an input frame. The host accepts it inside a sanity envelope
(§3.6). The host stays authoritative for zombies, damage, economy, world state and death.

This is worth stating as three consequences, because it is what makes the slice small:

1. **`Player`'s input path needs no refactor at all.** The replication researcher's §8.1 —
   correctly identified as "the single largest refactor in the package" — is deleted, not
   deferred.
2. **The guest's own movement has zero latency.** No prediction error, no rubber-band, no
   reconciliation, no re-runnable physics.
3. **The `Rng` spread problem dissolves.** The researcher called the VISUAL-stream spread
   draw (`player.gd:886-887, 939-940`) "the single concrete blocker to predicting fire
   locally". It is only a blocker if the guest sends "I fired" and the host re-draws the
   spread. **The guest draws its own spread and puts the resulting ray on the wire.** No
   stream parity is required anywhere in this design. *(OVERRULE — replication §5.3.)*

The cost is that a modified client can teleport. Against a PvE game where anyone with the
room code can already impersonate the host, that is not a cost.

### 2.4 The latency cost, stated honestly

| | |
|---|---|
| Measured one-way, same machine → `us-east-1` → same machine | **23 ms median, 36 ms p95, 63 ms max** |
| Realistic two-player one-way | **40–160 ms**, and the probe note says so at `:50-54` |
| Snapshot interval at 15 Hz | 66.7 ms |
| Measured inter-arrival at 15 Hz | 63 ms median, **79 ms p95, 101 ms max** |
| Interpolation buffer (must exceed max gap) | **120 ms** |
| **Guest's view of a zombie is behind the host's by** | **160–280 ms** |

At a zombie's top speed of 3.45 m/s (`SPEED_SPRINT`, `game_state.gd:72`), 200 ms of buffer
is **0.69 m of positional error** — more than a zombie's width. Without a correction, the
guest would aim at where a zombie was and miss.

**This is not hand-waved away; it is paid for.** The host keeps a 400 ms ring of zombie
transforms, the guest stamps every shot with the snapshot tick it was aiming at, and the
host rewinds before raycasting (§3.5). The guest's aim is then correct by construction. The
price is paid by the *host*, who can occasionally be killed by a zombie the guest shot
"after" it moved. That is the standard trade and it is the right way round: the guest, who
already suffers the latency, should not also suffer the aim penalty.

**Also honest:** WebSocket is TCP. A lost packet head-of-line-blocks the next snapshot, so a
single retransmit is a ~100 ms freeze of every remote entity, not a dropped frame. The
interpolation buffer absorbs one; it will not absorb a bad connection. There is no fix for
this short of WebRTC, and WebRTC was rejected above.

---

## 3. The wire protocol

### 3.1 The governing rule

> **The host sends exactly one message type in-run. The guest sends exactly one message
> type in-run. Everything else is a field inside them.**

Spawns, deaths, sound cues, purchase results, toasts, power-ups, revive progress — all of
it rides inside the periodic message as an array. Nothing in the game can raise the message
rate.

This exists because **Supabase bills and rate-limits messages, not bytes**
(`realtime-messages.md:11`: "one message sent plus one message per subscribed client";
enforced at `message_dispatcher.ex:98`). A Nuke firing 24 death events, or a round start
firing 24 spawns, would otherwise be a rate spike at exactly the moment the game is busiest.
With this rule the session is a flat **60 msg/s forever**, which is computable, quota-able
and cannot trip a limit.

**OVERRULE — replication §6.1.** The byte-packed binary snapshot (258 B, per-entity dirty
masks, u16 quantisation) optimises the wrong quantity. That researcher's own figures put the
stream at ~13 kB/s against a 256 KB payload ceiling — **400× of headroom on a resource
nobody charges for** — and the dirty-mask work buys 8%. We send JSON with short keys and
flat arrays: it is inspectable in the browser network tab, which is the only debugger this
target has; it round-trips through one testable pure function; and it costs nothing that
matters. Bytes are budgeted below only as a ceiling tripwire, never as an optimisation
target.

### 3.2 Transport framing (already built — do not re-invent)

Phoenix protocol **1.0.0**, one flat JSON object per frame, text frames only
(`phoenix.gd:13-19, 30`). Outbound goes through `realtime.gd::send(event, payload)`
(`:108-116`), which wraps into `broadcast_frame` and enforces a 40-message-per-second local
ceiling (`SEND_BUDGET`, `:61`). Inbound arrives via the `message(event, payload)` signal
(`:33`) already unwrapped from the broadcast envelope (`phoenix.gd:213-220`).

Three properties of this layer that the encoder author must internalise:

1. **Every number arrives as a float.** `phoenix.gd:172-176` states it and says two of its
   own probe assertions failed on it. `payload["id"] == 4` is *false* while
   `int(payload["id"]) == 4` is true. **Every integer field is `int()`-cast at the
   boundary, with no exceptions.**
2. **Never `put_packet()`.** `EMWSPeer::put_packet` always sends BINARY; Phoenix speaks
   text. `realtime.gd` correctly uses `send_text` throughout.
3. **The transport is reliable and ordered** (TCP under the WebSocket). Messages are not
   lost in transit — 120/120 and 30/30 measured. The only loss mode is a channel drop, and
   §3.4's periodic full world resend covers it. **Do not build UDP-style redundancy.**

### 3.3 Message A — `snap` (host → guest)

**Direction** host→guest · **Rate** 15 Hz fixed · **Reliability** none needed; each
supersedes the last · **Typical** ~760 B payload · **Worst case** ~2.6 kB

```jsonc
{
  "t":  12345,        // int. Host tick, increments once per snapshot, wraps at 65536.
                      //      The lag-compensation clock. NOT a physics tick.
  "a":  41,           // int. Highest guest event sequence the host has consumed. See 3.4.
  "r":  7,            // int. Game.round_no.
  "s":  1,            // int. Round phase: 0 intermission, 1 spawning, 2 clearing, 3 over.
  "h":  [...],        // array. Host player record.  Always present.
  "g":  [...],        // array. Guest player record. Always present.
  "z":  [[...], ...], // array. One record per LIVE zombie. Omit the key when empty.
  "ns": [[...], ...], // array. Zombies that spawned since the last snap. Omit when empty.
  "nd": [[...], ...], // array. Zombies that died  since the last snap. Omit when empty.
  "fx": [[...], ...], // array. One-shot cues. Omit when empty.
  "w":  {...}         // object. World state. Delta-on-change + full every 75 ticks.
}
```

#### Player record — `h` and `g`, 8 elements, fixed order

| # | Field | Encoding | Range | Notes |
|---|---|---|---|---|
| 0 | `x` | int centimetres | 0..4200 | `MAPW = 42` (`map_data.gd:11`) |
| 1 | `z` | int centimetres | 0..3400 | `MAPH = 34` (`map_data.gd:12`) |
| 2 | `yaw` | int tenths of a degree | 0..3599 | `Player.rotation.y` |
| 3 | `pitch` | int tenths of a degree | -850..850 | `Head.rotation.x`, clamped ±85° |
| 4 | `hp` | int | 0..160 | `JUG_HP` is the ceiling (`game_state.gd:51`) |
| 5 | `pts` | int | 0..16777215 | that player's wallet |
| 6 | `gun` | int | 0..95 | `weapon_index*8 + slot*2 + pap` — 12 weapons, 3 slots, 1 pap bit |
| 7 | `fl` | int bitfield | 0..255 | bit0 downed · 1 sprint · 2 ads · 3 fired-this-tick · 4 reloading · 5 knifing · 6 being-revived · 7 bled-out/spectating |

**Y is not sent.** `player.gd:560` pins `velocity.y = 0.0` every tick; the floor is flat.
Sending a constant zero fifteen times a second is the kind of thing that survives three
milestones.

**`h` is the host's own body and `g` is the host's authoritative view of the guest.** The
guest renders `h` interpolated, and *ignores* `g` for its own body — `g` exists so the guest
can see corrections it must accept (a teleport-back after a sanity rejection, an hp change,
a down). §3.6 defines when the guest snaps to `g`.

#### Zombie record — `z`, 6 elements, fixed order

| # | Field | Encoding | Range | Notes |
|---|---|---|---|---|
| 0 | `id` | int | 0..63 | pooled; see the pool-size note below |
| 1 | `x` | int cm | 0..4200 | |
| 2 | `z` | int cm | 0..3400 | |
| 3 | `y` | int cm | 0..100 | non-zero **only** mid-vault; arc apex is `VAULT_LIFT = 0.62` (`barricade.gd:189`) |
| 4 | `f` | int degrees | 0..359 | `_facing`, written only by `_face()` (`zombie.gd:558-561`) |
| 5 | `b` | int packed | 0..84 | `state + kind*8 + pal*32` — state 0..4 (`zombie.gd:14`), kind 0..2, pal 0..2 |

**`_view` and `_flip` are NOT on the wire and must never be.** `zombie.gd:567-580` derives
them from `_facing` plus `get_viewport().get_camera_3d()` — they are *per-viewer* by
construction, and the guest's camera is not the host's. Sending them would put the host's
sprite orientation on the guest's screen. This is the single most likely field for a
well-meaning implementer to add.

**`speed` is not per-tick.** It is constant from spawn except through `_become_crawler`
(`zombie.gd:967`), so it rides `ns` and the crawler entry in `fx`.

**Id pool = 64.** Peak node count is 24 alive plus up to 24 corpses (a Nuke produces exactly
that, each held 1.34–2.34 s by `_death_timer` + `NUKE_STAGGER_MAX`). 64 gives 16 slots of
churn margin. **Ids must be pooled, not monotonic** — a monotonic counter overflows one byte
inside a single round.

#### Spawn record — `ns`, 7 elements

`[id, kind, pal, speed_cms, window_index, x_cm, z_cm]` — `speed_cms` is int cm/s. The guest
constructs the puppet from these and **must not call `Zombie._configure`**, which draws AI
twice (`zombie.gd:404, 408`) and VISUAL three times (`:473, :474, :476`). ~30 B each.

#### Death record — `nd`, 6 elements

`[id, cause, headshot, dx, dz, delay_ms]` — `cause` is the `Cause` enum (`zombie.gd:163`),
`dx`/`dz` are the shove direction ×100, `delay_ms` is the staggered-collapse delay.

**These last two fields exist because of a real bug the replication pass found and I am
promoting to a required protocol field.** `zombie.gd:1022` and `:1037` both gate on
`target != null`, which is null on a puppet. Left alone, every guest-side Nuke collapses all
24 corpses on one frame (`zombie.gd:135-136` says in as many words that this reads as a bug)
and every guest-side corpse falls straight down instead of away. **The delay and the shove
are computed on the host and sent.** ~24 B each.

#### Cue record — `fx`, 3 elements

`[cue_id, x_cm, z_cm]` — a small closed enum in `protocol.gd` covering the 42 host-only
`Sfx.play*` sites (`zombie.gd` 7, `player.gd` 9, `interaction_system.gd` 12, `traps.gd` 4,
`mystery_box.gd` 3, `powerup_manager.gd` 3, `throwables.gd` 2, `round_director.gd` 1,
`projectile.gd` 1) plus the visual one-shots `fx.gd` binds to `player.impact` / `fired` /
`surface_impact` (`main.gd:21-23`). Without this the guest plays a game in silence with no
muzzle flashes and no blood. A fourth element `[.., arg]` is permitted for cues that carry a
small int (toast id, perk id, weapon id). ~25 B each, budget 8 per tick.

#### World block — `w`

Sent **only when a field changed**, plus a **full block every 75 ticks (5 s)** and on the
first snapshot after any (re)join. That is the entire reliability story for world state:
0.2 msg/s of insurance against a channel blip, no ack machinery.

| Key | Type | Source |
|---|---|---|
| `d` | int, 4 bits | door open mask (`map_data.gd:742` is the single writer) |
| `p` | int 0/1 | `Game.power_on` |
| `b` | array[14] int 0..6 | barricade boards; `barricade.gd:577` is "the single writer in every direction" |
| `x` | `[state, spot, gun_idx, timer_ds]` | mystery box; `_state` is 5-valued (`mystery_box.gd:44`), `_enter()` at `:276` is the single writer |
| `k` | int deciseconds | Insta-Kill remaining |
| `q` | int deciseconds | Double Points remaining |
| `tr` | array[3] `[state, timer_ds]` | traps |
| `pa` | `[state, gun_idx, timer_ds]` | Pack-a-Punch |
| `pu` | array `[id, kind, x_cm, z_cm]` | power-ups on the floor |

**Deliberately absent from `w`, because the guest computes them:** plank colliders
(`barricade.gd:584-588`, derived from board count), trap flicker (`traps.gd:574-575` — two
sines of `_phase`, and `:215-218` records that the file draws no random number at all),
power-up hover and blink (`powerup_manager.gd:57-59`, a pure function of `t`), zombie
`speed_scale` (`Zombie.anim_scale_for()` is static at `zombie.gd:487` precisely so it can be
called without a tree), and the whole corpse clock (`zombie.gd:1097-1141`). *This is the
replication researcher's best contribution and I am adopting it verbatim: **derived** is a
fourth bucket alongside every-tick / on-change / never, and putting derived state on the
wire would be the largest avoidable waste in the design.*

**Also absent:** `Game.nuke_clearing` and `trap_clearing`. They are set and cleared inside
one synchronous sweep (`powerup_manager.gd:104-108`, `traps.gd:523-537`). Putting a
within-frame flag on a 66 ms wire is a category error.

The guest must **run the side effects, not just set the flag.** `Game.power_on` going true
does five things at `interaction_system.gd:692-703` — `atmos.light_perks()`,
`world.set_power_on()`, `lighting.power_on()` (a timed per-room ceremony), a toast, and a
retirement. A guest that only assigns the boolean gets a lit level with no ceremony and a
generator row that never retires.

### 3.4 Message B — `me` (guest → host)

**Direction** guest→host · **Rate** 15 Hz fixed · **Reliability** state is fire-and-forget;
the event queue is retransmit-until-acked · **Typical** ~120 B · **Worst case** ~400 B

```jsonc
{
  "t": 12340,      // int. The last host tick the guest has APPLIED. The rewind reference.
  "p": [x, z, yaw, pitch, fl, mag, res],   // this client's own body, authoritative
  "q": [[seq, kind, ...args], ...]         // unacked event queue, oldest first. Omit when empty.
}
```

`p` fields 0..4 are encoded exactly as the player record above; `mag` and `res` are the
current magazine and reserve (the host needs them to refuse a shot from an empty gun).

**The event queue is the whole reason there is no third message type.** Each entry carries a
monotonic `seq`; the host echoes the highest consumed `seq` in `snap.a`; the guest drops
acked entries and re-sends the rest next tick. A queue is normally empty and never holds
more than three or four entries. This is ~20 lines and it is the correct amount of
machinery — it survives a channel blip without inventing an ack protocol.

**Guest event kinds:**

| `kind` | Args | Meaning | Host response |
|---|---|---|---|
| `0` FIRE | `[wi, ox,oy,oz, [dx,dy,dz]×n]` | *n* shots this tick. Directions are **already spread-jittered by the guest** — the host does not re-draw. Origin in cm, directions ×1000. Capped at n ≤ 8. | rewind to `me.t`, raycast, apply damage, pay points, emit `fx` |
| `1` MELEE | `[dx, dz]` | knife swing | same, with the melee bonus |
| `2` USE | `[action, target_id]` | buy door / wallbuy / perk / box / PaP / trap, or one rebuild tick | validate against the guest's wallet, mutate `w`, emit an `fx` confirm-or-deny |
| `3` NADE | `[kind, ox,oy,oz, vx,vy,vz]` | frag or Monkey Bomb launch | host owns the projectile from here |
| `4` REVIVE | `[0 start \| 1 cancel]` | begin/abort reviving the downed host | host runs the 3.0/1.5 s timer |
| `5` SWAP | `[slot]` | weapon swap | authoritative slot change |

**FIRE is capped at 8 directions per message and one FIRE per tick.** The fastest weapon is
the RPK; at 15 Hz a tick covers 66 ms, which no weapon in `TABLE` can fill with more than
two shots. The cap of 8 is a malformed-input guard, not a rate expectation.

**Reload and sprint are NOT events.** They are bits in `p[4]`; the host reads the state, not
the transition. One fewer thing to ack.

### 3.5 Lag compensation — exact

The host keeps `HistoryRing`: a fixed 8-entry ring of `{tick, PackedInt32Array positions}`
covering `8 / 15 Hz = 533 ms`. On a guest FIRE stamped `me.t`:

1. `age = host_tick - me.t`. If `age > 6` ticks (400 ms), clamp to 6 and continue — a very
   late shot is resolved slightly wrong rather than dropped.
2. Move every live zombie's collider to its position at `tick = host_tick - age`.
3. Raycast through the **real** weapon path — the same code a host shot takes. Do not
   reimplement the raycast; that is exactly the "assert through the real path" failure
   CLAUDE.md names.
4. Restore every collider.

**Zombies only.** Players are not rewound (both bodies are trusted-authoritative anyway) and
geometry is not rewound (doors change on the order of once a minute; a shot through a door
that closed 200 ms ago is not a bug anyone will see).

### 3.6 The sanity envelope on trusted movement

The host accepts `me.p` unless it fails one of three tests, in which case it keeps its own
last-known position and sets a `correct` bit in `snap.g[7]`; the guest hard-snaps to `g` on
that bit and only on that bit.

| Test | Bound | Provenance |
|---|---|---|
| Speed | `‖Δpos‖ / Δt` ≤ 6.0 m/s | sprint is 4.88 m/s; Stamin-Up scales it; 6.0 leaves headroom and still catches a teleport |
| Solid | the destination tile is not `map.solid` | `map_data.gd`'s grid, the same one the guest walked |
| Bounds | 0 ≤ x ≤ 42, 0 ≤ z ≤ 34 | `MAPW`/`MAPH` |

This is anti-*corruption*, not anti-cheat: it stops a decode bug from putting a player
inside a wall, which is a failure mode a JSON float and an `int()` cast can produce on their
own.

### 3.7 Lobby messages (already built)

`session.gd` owns these and this design does not change them: presence carries
`{name, host}` (`session.gd::_open`), and `EV_START := "start"` carries `{seed}`
(`session.gd:start_run`). Note that the seed is currently unnecessary — `MapData.roll_layout`
(`map_data.gd:870`) is called only from `scripts/dev/checks/mapgen.gd`, so every client boots
the canonical layout — but it is correct to send it and it costs one field. **If the seeded
layout is ever wired in, send the resolved layout, not the seed:** `roll_layout` consumes a
*variable* number of ROUNDS draws through its rejection loop (`:889`, `LAYOUT_TRIES = 64`),
so seed parity does not imply layout parity.

### 3.8 Budgets

**Bytes** (payload only; add ~130 B of Phoenix envelope per frame):

```
snap, quiet   : 22 hdr + 40 h + 40 g + 24x27 z                    =   750 B
snap, worst   : 750 + 24x30 ns + 24x24 nd + 180 w + 8x25 fx       = 2,626 B
me,   quiet   : 12 t/ack + 45 p                                   =    57 B
me,   firing  : 57 + one FIRE with 2 dirs                         =   135 B
```

Server ceiling is `max_payload_size_in_kb * 1000 + 500` = **256,500 B**, measured against
`:erlang.external_size` of the decoded term (`tenants.ex:533-536`). Worst case is **97×
under**. The assertion in §7 trips at 8 kB, which is 3× worst case — a real tripwire on a
careless field, nowhere near the real limit.

**Messages** — the only budget that binds. With `self:false` on one channel of *N* members,
one publish costs `1 send + (N-1) deliveries = N`:

```
total_msg_per_sec = snap_hz * N  +  me_hz * (N-1) * N

N=2, 15/15 :  15*2 + 15*1*2 =  60 msg/s   ->  216,000/h  ->  9.26 h/month
N=4, 15/15 :  15*4 + 15*3*4 = 240 msg/s   ->  864,000/h  ->  2.31 h/month
```

The N=4 row reproduces the Supabase researcher's independently derived 240, which is the
triangulation that makes me trust the formula. **Two-player co-op costs ~9.3 hours of the
2,000,000-message free tier per month, and that is the honest headline number.** Documented
per-second cap is 100 (project-wide, not per-channel — `tenants.ex:237-259`; there is no
per-channel counter). We sit at 60.

Two free savings, both worth taking: **drop `snap` to 5 Hz whenever `_alive` is empty and
the round phase is intermission** (~8% of session time at mid rounds), and **send nothing at
all in the lobby** beyond presence.

---

## 4. File plan and ownership

### 4.1 Ownership rule

One agent owns a file outright for the life of its package. Everything else is a reported
find/replace hunk **plus a check that fails until it lands** — ADS shipped with its camera
half and not its weapon half exactly this way.

**`project.godot` and `verify.gd`'s registration lines are REPORTED, never edited by the
implementing agent.** Opening the project in the editor to make a change is forbidden: an
editor pass rewrote `project.godot` once, stripping 32 comments down to 7 and silently
dropping the `rendering_method.web` pin.

### 4.2 Packages, in dependency order

#### Package P — per-player state *(does the most damage; goes first and alone)*

**Owns:** `scripts/autoload/game_state.gd`, `scripts/data/weapons.gd`,
`scripts/entities/player.gd`, `scripts/systems/interaction_system.gd`, `scripts/ui/hud.gd`,
`scripts/systems/powerup_manager.gd`, `scripts/systems/mystery_box.gd`,
`scripts/systems/round_director.gd`, `scripts/systems/traps.gd`,
`scripts/systems/throwables.gd`.

**Does:** turns `Game.points` and `Game.perks` from globals into per-player state. 57 call
sites (`player.gd` 18, `interaction_system.gd` 17, `hud.gd` 10, `weapons.gd` 5,
`powerup_manager.gd` 3, `mystery_box.gd` 1, `round_director.gd` 1, `traps.gd` 1,
`menu.gd` 1). The hard part is `weapons.gd`'s five `static` accessors (`:203, :206, :212,
:222`, plus `PERKDEF`), which take no player argument and are called from inside
`Player._physics_process` via `Game.max_health()` (`player.gd:566-568`), `rpm_scale()`
(`:829`), `damage_scale()` (`:892, :956`) and `reload_scale()` (`:1095`).

Also: `signal died(z, was_headshot, by_melee)` (`zombie.gd:7`) **grows an attacker
argument.** `game_state.gd:110-113` explicitly declined to do this for `nuke_clearing` and
was right to; canon now forces it, because the kill pays the killer only
(`_zombiemode_spawner.gsc:3290`) and the port has no way to know who that is. And the
director gains `spawned(z)` / `killed(z, cause, headshot, dir, delay_ms)` signals — the seam
Package R subscribes to without touching this file.

**The gate that makes this safe: Package P is a PURE REFACTOR.** With one player, behaviour
must be bit-identical. `--verify` green with no assertion count change beyond additions,
`--sim` baselines identical to the byte, `pwsh tools/frames.ps1` with zero drift. **If a sim
baseline moves, the refactor is wrong — the baseline is not negotiable here.** This is the
single most valuable property in the plan: the largest and riskiest change ships with a
mechanical correctness gate and no network anywhere near it.

#### Package C — co-op rules *(same agent as P, sequentially — it re-touches P's files)*

**Owns:** the same set, plus **new** `scripts/systems/revive.gd`.
**Does:** everything in §6 — the count ratio, per-player perk loss on down, 45 s bleedout,
3.0/1.5 s revive, the co-op Quick Revive variant, the −5%/−10%/0% penalties, next-round
respawn with the round-6 top-up, both-down-is-over. Guarded on `Net.is_online()` so solo is
untouched.

#### Package R — replication *(parallel with C after P lands)*

**Owns:** **new** `scripts/net/protocol.gd` (pure static encode/decode — the testable half),
**new** `scripts/net/host_link.gd`, **new** `scripts/net/guest_link.gd`, **new**
`scripts/entities/remote_player.gd`, and `scripts/entities/zombie.gd`.

`zombie.gd` gains `net_puppet: bool` and `net_id: int`, and `_die()` takes `_death_delay`
and the shove vector as optional arguments instead of computing them from a null `target`
(§3.3). Reuse `Zombie` rather than writing a puppet class: `_physics_process` already
returns at `:740-741` when `target == null`, after `_tick_flash` and `_update_view`, so a
target-less `Zombie` **is** a render-only puppet with the correct atlas row and no AI, no
physics and no RNG draws. That is a gift and it should be taken.

`remote_player.gd` is a `Node3D`, **not** a `Player`. `player.gd:301-305` creates a
`Camera3D` unconditionally and the last one added wins `current`; a second `Player` in the
tree steals the camera. The remote avatar is a sprite, a collider, a muzzle-flash socket and
a torch with `shadow_enabled = false`.

#### Package M — menu *(fully parallel; touches one file)*

**Owns:** `scripts/ui/menu.gd`. Reports one hunk against `scripts/dev/checks/shell.gd`.

#### Package T — tests *(parallel; lands last)*

**Owns:** **new** `scripts/dev/checks/net.gd` — a file `phoenix.gd:48` already promises
exists and which does not. Reports hunks for `verify.gd`'s `CHECK_NET` preload, its
`CHECK_MODULES` entry, its `_mark("net")` / `run()` line, and the `ASSERTION_FLOOR` raise.

Note `_registered()` (`verify.gd:157-169`) walks the checks directory and **fails** if a
`.gd` there is not in `CHECK_MODULES`. So `net.gd` landing before its registration hunk
turns the suite red — which is the correct behaviour and is exactly the "a reported hunk is
not done" guarantee. Land the file first, deliberately.

#### Already complete — do not touch

`scripts/net/phoenix.gd`, `scripts/net/realtime.gd`, `scripts/net/session.gd`. Task #19 is
closed. Three hunks are reported against them in §4.4 and nothing else.

### 4.3 Collision map

| File | Owner | Contended with |
|---|---|---|
| `game_state.gd` | P/C | one line reported to whoever owns it at integration (§4.4 H1) |
| `player.gd`, `interaction_system.gd`, `hud.gd`, `weapons.gd` | P/C | — |
| `round_director.gd` | P/C | R consumes its new signals only |
| `zombie.gd` | R | P/C changes only the `died` signature — **land that hunk before R starts** |
| `menu.gd` | M | — |
| `main.gd` | **integration only, single agent, last** | P, R and M all want a line here |
| `scripts/net/*` | closed | — |
| `project.godot`, `verify.gd`, `shell.gd` | **nobody** — hunks only | — |

`main.gd` is the one file three packages want (`_build_systems` for the links, `_process`
for the drive order, `_ready` for the remote avatar, `restart` for the room teardown). It is
reserved for a single integration pass after P, C, R and M are all in. Each package reports
its `main.gd` hunk and ships a check that fails until integration lands.

### 4.4 Hunks for files nobody owns

**H1 — `project.godot`, register the autoload.** Position is load-bearing:
`tools/build.ps1:167-174` injects `PerfProbe` after the line matching `^Sfx=` and **throws**
if that anchor is missing, and `tools/build.ps1:152-157` strips the three `MCP*` lines by
prefix before every export. Insert between `Settings=` and `MCPScreenshot=`.

```
FIND:
Settings="*res://scripts/autoload/settings.gd"
MCPScreenshot="*res://addons/godot_mcp/mcp_screenshot_service.gd"

REPLACE:
Settings="*res://scripts/autoload/settings.gd"
Net="*res://scripts/net/session.gd"
MCPScreenshot="*res://addons/godot_mcp/mcp_screenshot_service.gd"
```

The check that fails until it lands: an assertion in `net.gd` that
`Engine.has_singleton("Net")`, shaped exactly like `verify.gd:1592-1605`'s existing
assertion that `PerfProbe` is *absent*.

**H2 — `verify.gd`, register the check module.** Four separate edits, all in reported-hunk
territory: the `const CHECK_NET := preload("res://scripts/dev/checks/net.gd")` line beside
its siblings at `:26-65`; the `"net.gd": CHECK_NET,` entry in `CHECK_MODULES` at `:78-90`;
`_mark("net")` + `CHECK_NET.run(self, main)` in `run()` — placed **before** `MAPGEN`, which
`verify.gd:266-269` requires to stay dead last; and an **additive** raise of
`ASSERTION_FLOOR` (`:125`, currently 585) by exactly the number added. The comment at
`:96-125` is explicit that this line is contended and that "set it to what I measured"
silently absorbs other agents' margin.

**H3 — `scripts/dev/checks/shell.gd`, the new menu screens.** `_menu_tree` at `:309-446`
already walks *every* screen in `_screens` generically, so the coop and lobby screens are
covered for free by the focus-ring assertions at `:358-361`. What is **not** covered is the
click-anywhere hazard: `:428-437` asserts a click on the *options* screen is not a
click-to-start, from both `STATE_TITLE` and `STATE_OVER`, and the comment says the bug's
return shape is "a guard added to one of them". The new screens are two more of them.

```
FIND:
	v.check("a click on the options screen is not a click-anywhere-to-start",
		stub.starts == 1 and stub.restarts == 1,
		"starts=%d restarts=%d" % [stub.starts, stub.restarts])

REPLACE:
	v.check("a click on the options screen is not a click-anywhere-to-start",
		stub.starts == 1 and stub.restarts == 1,
		"starts=%d restarts=%d" % [stub.starts, stub.restarts])

	# The co-op screens live under STATE_TITLE exactly as the options screen does —
	# opening one does not move Game.state — so hud.gd's click-anywhere poll reaches
	# press_primary() from both of them too. Asserted per screen rather than in a
	# loop: press_primary()'s guard is a `match` on the state with a `_current` test
	# inside each arm, and the shape this bug returns in is one arm being fixed.
	for screen: String in ["coop", "lobby"]:
		if not menu.screens().has(screen):
			continue
		Game.state = Game.STATE_TITLE
		menu._acted = false
		menu.show_screen(screen)
		menu.press_primary()
		Game.state = Game.STATE_OVER
		menu._acted = false
		menu.press_primary()
	v.check("a click on a co-op screen is not a click-anywhere-to-start",
		stub.starts == 1 and stub.restarts == 1,
		"starts=%d restarts=%d" % [stub.starts, stub.restarts])
```

**H4 — `scripts/net/realtime.gd:37-38`, a wrong provenance.** The value is right and must
not change; the reason is measurably false and this repo treats a wrong provenance as a
defect.

```
FIND:
## Under 25 s, with room for a missed frame. The server closes an idle socket at 25 s;
## sending at 15 s means one dropped heartbeat is survivable and two are not.
const HEARTBEAT_PERIOD := 15.0

REPLACE:
## Under the server's idle close, with room for three missed frames. Phoenix closes a
## socket 60 s after the last frame RECEIVED FROM THE CLIENT (Phoenix.Endpoint socket/3
## `:timeout`, which realtime's endpoint.ex:16-35 does not override); measured on
## qalanxifxfukkeqdhfqh at 61.6 / 64.3 / 66.1 / 66.1 s across four runs. The 25 s this
## comment used to cite is realtime-js's own CLIENT heartbeat interval, not a server
## limit — a number copied from the wrong side of the protocol.
##
## Do NOT reach for WebSocketPeer.heartbeat_interval instead. It is honoured natively
## and INERT on web (`grep -c heartbeat`: wsl_peer.cpp 6, emws_peer.cpp 0 — browsers
## do not expose ping/pong to JS), so it would pass every desktop test and ship dead.
const HEARTBEAT_PERIOD := 15.0
```

The same class-comment claim at `realtime.gd:12-18` ("the server closes an idle socket after
25 seconds") needs the same correction; the *conclusion* — `PROCESS_MODE_ALWAYS` is
load-bearing — is right and gets more right at 60 s, not less.

**H5 — `notes/net/2026-07-31-realtime-probe.md:113-120`, a 4× error in a section whose own
header says "Read this before changing the tick rate".** It computes `15 + 3×15 = 60` msg/s
for four players by counting sends only. Supabase counts `1 sent + 1 per receiving
subscriber` (`realtime-messages.md:11`), so the real figure is **240 msg/s, 864,000/hour,
2.31 h/month** — not the implied 9.26. Its closing advice is inverted too: at that topology
the client inputs are 180 of the 240 because each fans out to peers who have no use for it.
Replace the section with §3.8's formula and table. **This document supersedes it; the note
must be corrected rather than left to be read by the next agent.**

**H6 — the `rooms` schema and `session.gd` heartbeat, which currently contradict each
other.** The Supabase pass proposes tightening `room_exists()` to a 3-minute liveness
predicate, because the reap is lazy (it only runs inside `claim_room`) and a dead room
answers `true` until somebody else creates one. That is a real UX defect and the patch is
right in principle — **but `session.gd:HEARTBEAT_PERIOD := 300.0` is five minutes, so
landing a 3-minute window would mark every live room dead.** Resolve in this direction:

- `session.gd`: `HEARTBEAT_PERIOD := 120.0` — 2 minutes, one tiny UPDATE per room.
- `room_exists()`: `last_seen > now() - interval '10 minutes'`.

Five missed beats of margin. The asymmetry is deliberate: a too-long window costs a player a
12 s `JOIN_TIMEOUT` and the message "that room did not answer"; a too-short window makes
live rooms unjoinable. Also worth landing from that pass: the `claim_room()` row cap (the
one genuinely open DoS — `EXECUTE` to `anon`, unbounded inserts) and the code-shape `CHECK`
constraint.

---

## 5. The menu flow

### 5.1 The contract, read from the file

`menu.gd` builds screens with `_screen(name, modal := false)` (`:189-211`), which registers
into `_screens` and returns the content `VBoxContainer`; and wires focus with
`_chain(name, controls)` (`:468-478`), which sets `focus_next`, `focus_previous`,
`focus_neighbor_bottom` and `focus_neighbor_top` cyclically and stores the ring.

`shell.gd::_menu_tree` (`:309-446`) then asserts, **for every screen in `_screens`
generically**:

- the chain is non-empty (`:334-336`),
- every control in it has `focus_mode == FOCUS_ALL` (`:337-339`),
- the ring closes and visits each control exactly once — walked by **resolving the
  NodePath**, not by trusting the array, and walked on **both** `focus_next` and
  `focus_neighbor_bottom`, because Tab uses one and the arrows use the other (`:340-357`).

New screens therefore need no new assertion to be covered — they need to *satisfy* one that
already exists. Four consequences for the implementer:

1. **Every control in a new chain must be `FOCUS_ALL`.** `LineEdit`, `Button` and
   `CheckButton` default to it; a `Label` does not and must never enter a chain.
2. **Ring index 0 must always be an ENABLED control**, because `show_screen` defers
   `_focus_first` onto `ring[0]` (`:513`, `:525-533`). In the lobby, START is disabled for
   the guest and while the roster is short — so **LEAVE is index 0**, not START.
3. **New screens must not be reachable from `_on_state`** (`:536-550`). They live *under*
   `STATE_TITLE`, exactly as "options" does. `_on_state` maps only title/pause/over and
   sends everything else to `show_screen("")`.
4. **`press_primary()` is already safe** — its `STATE_TITLE` arm returns unless
   `_current == "title"` (`:156-158`). The hazard is the *next* person to touch it, which is
   what hunk H3 pins down.

### 5.2 Screens and buttons, exactly

**`title`** *(existing — one button added, chain grows 2 → 3)*

```
KRIEGSNACHT / survive the night / [keys grid]
  [ ENTER THE BUNKER ]     -> _on_start()            (unchanged)
  [ PLAY WITH A FRIEND ]   -> _open_coop()           NEW
  [ OPTIONS ]              -> _open_options("title") (unchanged)
[points hint] [best]

chain("title") = [start, coop, opts]
```

Nothing asserts the chain's *length*, so this is safe. "PLAY WITH A FRIEND" rather than
"MULTIPLAYER" or "CO-OP": it is a two-player game and the button should say so.

**`coop`** *(new, `_screen("coop", true)` — modal, for the same reason options is: a click
on the backdrop would otherwise reach the player and resume the run)*

```
PLAY WITH A FRIEND
  Your name      [ LineEdit, 12 chars ]
  [ HOST A ROOM ]                      -> Net.host_room(name)
  Room code      [ LineEdit, 6 chars, sanitised as typed ]
  [ JOIN A ROOM ]                      -> Net.join_room(code, name)
  <status/error label — NOT in the chain>
  [ BACK ]                             -> show_screen("title")

chain("coop") = [name_edit, host_btn, code_edit, join_btn, back_btn]
```

The code field runs `text_changed` → `PHX.sanitise_code()` → `set_text` +
`caret_column = text.length()`. `LineEdit.set_text` does not re-emit `text_changed` in
Godot 4, so there is no re-entrancy guard needed — but say so in a comment, because it looks
like there should be. JOIN is disabled until `PHX.is_valid_code()` passes, which is a
`length() == 6` test after sanitising and costs no round trip (`phoenix.gd:306-313`).

Errors render into the status label, **not** a new screen. Fewer screens is fewer rings to
keep closed.

**`lobby`** *(new, modal)*

```
ROOM  B7K-4MQ                <- the code, 56 px, hyphenated for reading aloud
"Tell your friend this code."
  <roster: 1-2 rows, name + (host) + (you)>
  <status line: "waiting for a second player" / "ready">
  [ LEAVE ]                            -> Net.leave_room(); show_screen("coop")
  [ START RUN ]                        -> Net.start_run()   (host only; disabled otherwise)

chain("lobby") = [leave_btn, start_btn]      <- LEAVE FIRST. See 5.1 point 2.
```

START is `disabled = true` for the guest permanently and for the host until
`Net.players().size() >= 2`. It stays **in the chain and in the tree** — removing a control
from a live chain would need `_chain()` re-run, and a chain rebuilt at runtime is a chain
that can be rebuilt broken.

The code is displayed hyphenated (`B7K-4MQ`) and stored unhyphenated. The alphabet was
designed for reading aloud — 28 glyphs, no vowels so a code can never spell a word, no
L/0/1 (`phoenix.gd:45-56`) — and a 3-3 grouping is how people actually say six characters.

### 5.3 Transitions

```
title --[PLAY WITH A FRIEND]--> coop
coop  --[BACK]--> title            coop --[ui_cancel]--> title
coop  --[HOST]--> lobby   (Net: OFFLINE -> CLAIMING -> CONNECTING -> LOBBY)
coop  --[JOIN]--> lobby   (Net: OFFLINE -> CHECKING  -> CONNECTING -> LOBBY)
        ...or stays on coop with an error label if Net.error fires
lobby --[LEAVE]--> coop   (Net.leave_room())        lobby --[ui_cancel]--> coop
lobby --[START RUN]--> (host) Net.start_run()
lobby --(EV_START)---> (guest) Net.run_started
        both: main.start_coop_run(seed, is_host) -> Game.set_state(STATE_PLAY)
              -> _on_state("play") -> show_screen("")
```

The guest and the host reach play through **the same signal** — `Net.run_started` — because
`session.gd::start_run` emits it locally as well as broadcasting (`session.gd`, `start_run`).
One path, one place for it to be wrong.

`_unhandled_input` (`menu.gd:557-560`) currently special-cases exactly one screen. It becomes
a small set:

```gdscript
const BACKABLE := {"options": "", "coop": "title", "lobby": "coop"}
```
with `""` meaning "use `_options_from`", preserving the existing behaviour that the options
screen returns to whichever of three places opened it (`:86-87`).

### 5.4 Pause in co-op — the one change to an existing rule

`Game.set_state()` writes `get_tree().paused` at `game_state.gd:282`. In co-op that is
wrong twice over: one player pausing must not stop the other's world, and
`Player._physics_process` (`:507`) and `Zombie._physics_process` (`:730`) both early-return
when `Game.state != STATE_PLAY`, so a paused guest would freeze its own interpolation and
then snap 400 ms forward on resume.

**In co-op, P opens the pause plate and the world keeps running.** The player is vulnerable
while it is open. This is both the correct engineering answer and the canon one: BO1 co-op
has no pause — the game runs on.

```
FIND:
	get_tree().paused = s == STATE_PAUSE or s == STATE_OVER

REPLACE:
	# In co-op the tree must NOT pause: the other player's world is still running, and
	# Player/Zombie._physics_process both early-return off Game.state, so a paused
	# guest freezes its own interpolation and then snaps forward on resume. BO1 co-op
	# has no pause either — the game runs on while the menu is up, and the player is
	# vulnerable. Solo is untouched.
	get_tree().paused = (s == STATE_PAUSE or s == STATE_OVER) and not Net.is_online()
```

One line, and it is the whole of §8.6 of the replication survey. The pause plate gains a
co-op-only warning line ("the horde does not wait"), and ABANDON RUN calls
`Net.leave_room()` before `main.restart()`.

---

## 6. BO1 co-op canon decisions

Every row below is Tier 1 unless marked. Paths are `ZM/Common/maps/` in
`plutoniummod/t5-scripts` @ `70689b82`. **These citations were taken from full local
downloads of the files, not from search fragments** — worth saying, because
`notes/research/R4-canon-numbers.md`'s own `t5/…:NNN` citations are decorative and this
document's are not.

### 6.1 Zombies per round — apply canon's RATIO, not canon's formula

Canon: `max = 24; m = max(1, r/5); if r >= 10: m *= r*0.15; max += (N-1)*6*m` (solo is the
special case `0.5*6*m`), then the early-round ramp ×0.25/0.30/0.50/0.70/0.90 for rounds 1-5
(`_zombiemode.gsc:3103-3175`, `:3075-3101`, vars at `:702-703`).

**The port must not adopt that formula.** `Game.zombie_count()` (`game_state.gd:440`) is the
*ancestor's* curve (`kriegsnacht.html:2189`) and already runs hot against canon solo — r10:
46 vs 33, r20: 101 vs 60. Grafting canon's absolute on top would double-count. So:

```
zombie_count(r, n) = zombie_count(r, 1) * canon_total(r, n) / canon_total(r, 1)
```

| round | 1p (unchanged) | ×2p | → 2p |
|---|---|---|---|
| 1 | 6 | 1.167 | 7 |
| 5 | 22 | 1.125 | 25 |
| 10 | 46 | 1.273 | 59 |
| 20 | 101 | 1.600 | 162 |
| 30 | 163 | 1.771 | 289 |

**`zombie_count(r, 1)` must be bit-identical to today's for every r**, or every
`notes/balance/*.csv` moves and the seeded-run layer's baselines with them. That identity is
an assertion (§7.13), not a hope.

**`spawn_interval()` (`game_state.gd:448`) does NOT get an N term.** Canon does not scale it
either. A 2p round genuinely is longer, absorbed by two players killing in parallel.
Shortening it would make solo-tuned pacing unplayable at 2p — the researcher's warning here
is correct and I am hard-coding it as a prohibition.

### 6.2 Max simultaneously alive stays 24, at any player count

`level.zombie_ai_limit = 24; SetAILimit(24)` — `_zombiemode.gsc:85-86`, enforced in the
spawn loop at `:3196`. `Game.MAX_ALIVE := 24` (`game_state.gd:23`) is already right and
needs **no change** — but it gets a comment saying 24 is player-count-independent, because
of this:

> **`notes/research/SYNTHESIS.md:200` is wrong and it is dangerous for exactly this
> package.** It reads *"Concurrent alive zombies | 24 (`zombie_max_ai`, canon)"*. The number
> is right; the variable is not. `zombie_max_ai` is the **round-total base**, and its own
> inline comment at `:702` says "Base number of zombies per player". Anyone adding co-op who
> reads that line as the alive cap will scale the alive cap by `zombie_ai_per_player` and
> get 30 alive at 2p and 42 at 4p. **Correct the note.**

### 6.3 Zombie health does not scale with players

`ai_calculate_health(round_number)` — `_zombiemode.gsc:4017` — takes exactly one parameter
and no `players.size` appears in it or its inputs. `Game.zombie_hp(r)` (`:403`) is already
correct. No change.

### 6.4 Points are per-player. There is no shared wallet, and the var table lies about it.

`player_add_points()` computes both a `player_points` and a `team_points` and then calls
`add_to_team_score()` — which is **entirely commented out**, `_zombiemode_score.gsc:370-388`,
header `//MM (3/10/10) Disable team points`. The team HUD is commented out too (`:493`). So
`zombie_score_kill_2p_team 45 / 3p_team 35 / 4p_team 30` (`:729-732`) are **dead numbers in
the shipped game.** A faithful port of the var table would ship a shared wallet Treyarch
switched off eight months before release.

- Every damaging hit pays the **damager** (`_zombiemode_spawner.gsc:3545, 3574, 3678, 3707`).
- The kill pays the **killer only** (`:3290`, guarded on `IsPlayer(attacker)`).
- A zombie softened by A over four hits and killed by B pays **A 40, B 60** (port values). No
  split, no assist.

### 6.5 Doors and debris: buyer pays full, opens for both, once

`door_buy()` `_zombiemode_blockers.gsc:240-292`. The solo branch at `:263` says *"No pools in
solo game"*; the two team branches below it collapse because the pool is always zero, so the
buyer pays the full cost from their own wallet in every case. The door is level state
(`self._door_open = true`, `:787-788`). **Do not implement a team pool.**
`interaction_system.gd:627-648`'s `Game.spend(cost)` becomes `payer.spend(cost)` and nothing
else changes.

### 6.6 Mystery box: shared everything except the gun

`_zombiemode_weapons.gsc` — one active spot (`level.chest_index`, `:843-896`), level-scoped
`chest_moves` (`:809`) and `chest_accessed` (`:830`) incremented by any player's pull
(`:1261`), and **one spinner at a time**: `treasure_chest_think()` sets `self.chest_user` and
breaks out of the accept loop (`:1124-1131`), disabling the trigger for the duration
(`:1167`). **Only the payer may take the weapon** — `if (grabber == user || grabber == level)`
at `:1220` discards any other player's use. A teddy refunds the payer their 950 with
`add_to_player_score(cost, false)` (`:1170-1174`), and the `false` matters: the refund does
**not** feed `score_total` and therefore does **not** feed the power-up drop threshold.

Port: `Game.box_spot`/`box_uses` stay global (already correct). Add an owner field, refuse
the grab from anyone else, refund the payer on a teddy without crediting `points_earned`.

### 6.7 Power: one global flag

`flag_init("power_on")`, `_zombiemode.gsc:961`, waited on by every perk machine, electric
door and trap. `Game.power_on` is already this. No change beyond replicating the *side
effects* (§3.3).

### 6.8 Perks are per-player; both players may hold the same one

`give_perk()` does `self SetPerk(perk); self.num_perks++` (`_zombiemode_perks.gsc:1457-1459`).
The purchase gate is the per-player `player HasPerk(perk)` (`:1285`) and the per-player cap
`player.num_perks >= 4` (`:1315`). Nothing prevents both players buying Juggernog.
`Game.PERK_CAP := 4` (`game_state.gd:64`) already reads as per-player and becomes so.

### 6.9 Quick Revive is a DIFFERENT PERK in co-op — the largest behavioural fork

| | Solo *(port already correct)* | Co-op *(new)* |
|---|---|---|
| Cost | **500** — `_zombiemode_perks.gsc:1128`; `Game.REVIVE_COST` `:60` | **1500** — `:1132`, and the 1500 is **already sitting unused at `weapons.gd:78`** with a comment saying exactly why |
| Power | **not required** — `if (!solo) { SetHintString(&"ZOMBIE_NEED_POWER") }` `:1108` and `if (!solo) level waittill(perk+"_power_on")` `:1170`; port exempts it at `interaction_system.gd:298` | **required** |
| Effect | one self-revive per purchase (`self.lives = 1`, `:1498`) | **halves YOUR time to revive a teammate**: `reviveTime = 3; if (self HasPerk("specialty_quickrevive")) reviveTime /= 2` — `_laststand.gsc:648-652`, where `self` is the *reviver* |
| Uses | **3, then the machine leaves** (`:1500-1502`, trigger moves at `:1417-1430`); port has `REVIVE_MAX_USES := 3` `:61` | unlimited re-buys |
| On down | always lost (`do_retain = false` when solo, `:1583-1586`) | lost like every other perk |

Solo detection is latched once at `flag_wait("all_players_connected")` (`:1092-1102`) — which
is precisely why §1.3 cuts drop-in: a join after the latch leaves `flag("solo_game")` set with
two players present, the exact failure the shipped comment at `_zombiemode.gsc:4733-4737`
describes as having "led to SREs".

### 6.10 Perk loss on down inverts, and `player.gd` already knows it

`player.gd:1182-1186` states the solo rule and its reason: *"SYNTHESIS.md's 'perk loss on
down' is the CO-OP rule... This game is solo... so you keep Juggernog, Speed Cola and Double
Tap and lose only the perk that just saved you."* That comment is correct and **stays**. Co-op
takes the other branch: `perk_think()` waits on `"fake_death" | "death" | "player_downed"` and
does `self UnsetPerk(perk); self.num_perks--` for **every** perk
(`_zombiemode_perks.gsc:1579-1594`), with Juggernog additionally doing `SetMaxHealth(100)`
(`:1598`).

### 6.11 Downed, bleedout, revive

| | Value | Source |
|---|---|---|
| Co-op bleedout | **45 s** | `SetDvar("player_lastStandBleedoutTime","45")`, `_zombiemode.gsc:780`; consumed `_laststand.gsc:154`. Screen desaturates at the halfway mark (`:379-390`). |
| Revive time | **3.0 s**, **1.5 s** with Quick Revive | `_laststand.gsc:648-652`, whose comment notes it can no longer be a dvar because it must match the third-person animation |
| Revive radius / cone | 75 units, reviver facing within ~52° (`dotProduct > 0.9`) | `SetDvar("revive_trigger_radius","75")` `:779`; `_laststand.gsc:~370` |
| Solo self-revive | **10 s** | `_zombiemode.gsc:4848-4857` |

**Port `DOWNED_TIME := 7.0` (`game_state.gd:56`) is the ancestor's `downT`, not canon's 10 s.**
It **stays** — changing solo balance inside a co-op package would move
`scripts/dev/checks/downed.gd` for no co-op reason. It gets a provenance comment recording
the departure, because CLAUDE.md's rule is that an unrecorded departure is wrong even when
it is right. The constant splits: `DOWNED_TIME` (solo, 7.0) and a new `COOP_BLEEDOUT` (45.0).

A downed player **keeps** their weapons (switched to the last-stand pistol, restored by
`revive_give_back_weapons()`) and their points minus 5%; **loses** every perk immediately;
gets `self.ignoreme = true` so zombies stop targeting them; is **skipped by Max Ammo**
(`_zombiemode_powerups.gsc:1813`) and cannot pick up power-ups at all (`:1218`).

**There is no end-of-round auto-revive.** `last_stand_revive()` exists at
`_zombiemode.gsc:2405-2418` and its only call site is commented out —
`//level thread last_stand_revive();` at `:3946`. A downed player at round end stays down and
bleeds out. This contradicts a widespread community belief and it is the kind of thing that
gets "fixed" back in later, so it goes in the code as a comment.

### 6.12 Bleeding out, and the mercy rule

`spectators_respawn` (`_zombiemode.gsc:707`, threaded at `:3945`): a bled-out player becomes a
spectator and **respawns at the start of the next round** with the starting loadout and no
perks. Penalties, all from `_zombiemode.gsc:714-716`:

- `penalty_downed = 0.05` — you lose 5% of your own score when you go down. **Tier 3 caveat:**
  the shipped source carries `// ww: told to remove downed point loss` next to a live 0.05,
  and the value is CSV-overridable. This is the number I trust least in the whole table.
- `penalty_died = 0.0` — **you lose nothing for bleeding out.**
- `penalty_no_revive = 0.10` — **the OTHER player loses 10%** when you bleed out
  (`_zombiemode_score.gsc:421-434`, from `zombify_player()` at `_zombiemode.gsc:4189`). This
  is the co-op-only rule and it is the one that makes reviving feel obligatory.

And a mercy rule that appears nowhere in community documentation:

```gsc
if (isDefined(level.script) && level.round_number > 6 && players[i].score < 1500)
{ players[i].old_score = players[i].score; players[i].score = 1500; }   // :2801-2805
```

A respawning player after round 6 is topped **up** to 1500.

### 6.13 Both down is game over

Two independent paths: `if (player_all_players_in_laststand()) mission_failed_during_laststand()`
(`_laststand.gsc:123`, helper at `:68`), and the damage override at
`_zombiemode.gsc:4704-4775` which counts self/zombie/laststand/spectator players and fires
`level notify("end_game")` when the count equals `players.size`. Solo with `lives > 0` diverts
to `wait_and_revive()`.

### 6.14 Power-up drops: team-summed, and nearly free to port

`watch_for_drop()` `_zombiemode_powerups.gsc:528, 540`:
`score_to_drop = players.size * start + 2000`, compared against `Σ players[i].score_total`.
The starting score cancels on both sides, so **the first drop still fires at 2,000 points
earned by the team collectively** — it just arrives ~2× sooner in wall-clock at 2p. The port's
`Game.points_earned` (`:144`) is already a single global counter, so it becomes the team sum
by simply continuing to be what it is. `DROP_CAP := 4` (`:490`) stays global — it already is.
The 3%-per-death roll is unchanged.

### 6.15 Starting points, and drop-in

500 each. **Tier 3** — the script fallback is 3000 and the shipped CSV
(`set_zombie_var("zombie_score_start_"+players.size+"p", 3000, …)`, `_zombiemode.gsc:1421`)
was never retrieved, so "500 for all N" is inference. `START_POINTS := 500`
(`game_state.gd:22`) stays for both players.

**No drop-in.** Tier 1-*inference*, not Tier 1-positive: no source was found that states BO1
forbids join-in-progress, but `onPlayerConnect()` sets `player.score = 0`
(`_zombiemode.gsc:1499-1530`) while the 500 is handed out once behind
`flag_wait("all_players_connected")` (`:1411-1432`), so a late joiner would get zero
permanently. `round_spawning()` re-reads `get_players().size` every round (`:3155`), so a
*leave* is graceful; a *join* has no code path. Join-in-progress arrived in BO6.

### 6.16 Declared departures from canon

Per CLAUDE.md: a departure that is not recorded as deliberate is wrong even when the
departure is right.

1. **Two players, not four.** §1.3.
2. **Trusted-client movement and 400 ms lag compensation.** No canon analogue; a transport
   decision (§2.3, §3.5).
3. **`DOWNED_TIME` stays 7.0 in solo** against canon's 10 s. Pre-existing ancestor value,
   left alone; recorded here so the next reader does not find it undocumented.
4. **`INTERMISSION` stays 6.5 s** against canon's `zombie_between_round_time = 10`
   (`_zombiemode.gsc:709`). Pre-existing ancestor-vs-canon gap, not co-op's business.
5. **Dog rounds are skipped in co-op.** §1.3.
6. **Zombie count uses canon's ratio on the ancestor's curve**, not canon's absolute. §6.1.
7. **Seeded-run reproducibility does not survive a co-op session.** A guest that applies host
   state has an `Rng` sequence the host does not share; additionally `session.gd::_uuid()`
   draws 32 times from `Rng.VISUAL` at lobby open, and weapon spread also rides VISUAL (the
   known outstanding constraint-5 violation), so *hosting a room shifts the spread sequence*.
   Harmless under host authority — the host resolves every shot, and the guest sends its ray
   rather than its seed — but it means a co-op run cannot be replayed from a seed. Declared,
   not fixed.

---

## 7. The test plan

Multiplayer is hard to test headlessly, and the honest structure is three tiers: what the
suite can assert with no network, what only a human with two browsers can check, and — the
part that matters most — **nothing in between pretending to be either.**

> **A skip must never pass.** There is not one `v.check("...", true, "needs a network")` in
> this plan. `verify.gd:71-77` records that thirty-four assertions once existed only as text,
> and `_registered()` exists because a floor is blind to a section that never started.

Every item below ships with its **control**: break the named thing, run the suite, confirm
**that specific check** fails, restore. Restore in a wrapper that runs even if the command
dies — a sabotage left in a file reachable from the main scene hung Godot for seven minutes
once and blocked another agent.

### 7.1–7.12 `scripts/dev/checks/net.gd` — assertable with no network

| # | Assertion | Control (break this → THAT check must fail) |
|---|---|---|
| 1 | **Snapshot round-trip.** Build a full state (2 players, 24 zombies, 24 spawns, 24 deaths, full `w`, 8 `fx`), `encode → JSON.stringify → JSON.parse → decode`, assert every field equals its input **and every integer field is `TYPE_INT` not `TYPE_FLOAT`** (`phoenix.gd:172-176`). | Delete one `int()` cast in the decoder. |
| 2 | **Quantisation, swept.** Positions at 0.00, 0.005, 20.5, 41.995 m and the `MAPH` equivalents; assert ≤1 cm error. Angles at 0°, 0.05°, 179.99°, 359.95°. | Change cm to dm in the encoder. |
| 3 | **Bit packing, exhaustive.** All 12×3×2 = 72 `gun` combinations and all 5×3×3 = 45 zombie `b` combinations recover exactly. *Sweep the domain — the whole point of `_flicker`'s lesson is that one sample is not a test.* | Swap the two shifts in `b`. |
| 4 | **Payload ceiling.** Worst-case snapshot stringifies under 8,192 B. Provenance: 256,500 B server limit (`tenants.ex:533-536`), tripwire set at 3× measured worst case. | Add a 20 kB string field. |
| 5 | **Message-rate arithmetic.** `Protocol.msgs_per_sec(n, snap_hz, me_hz)` returns 60 at (2,15,15) and **240** at (4,15,15). The 240 is the triangulation: it reproduces the Supabase pass's independently derived figure, and the probe note's 60 is the value it must *not* return. | Drop the fan-out term → the N=4 case must fail and the N=2 case must **not** (it coincidentally survives at N=2, which is why the N=4 row is the load-bearing one). |
| 6 | **Room-code alphabet, both ends.** 28 glyphs, no duplicates, no vowel, no `L/0/1`; `28^6 == 481_890_304`. `is_valid_code` **accepts** `"BCDF23"`, `"bcdf23"`, `" BCDF23 "`; **rejects** `"BCDF2"`, `"BCDF234"`, `"BCDFA3"`, `""`. `sanitise_code("code: bcdf-23") == "CDBCDF"` — asserting the documented *behaviour*, because `phoenix.gd:321-327` records that an earlier comment claimed prose-rescue and a test asserting the claim rather than the behaviour caught it. | Add `"A"` to `ALPHABET`. |
| 7 | **Presence diff order.** A diff carrying the same key in `leaves` and `joins` (the update shape, with `phx_ref_prev` — the exact payload the Supabase pass captured live) leaves the JOIN meta present, not deleted. | Move the joins loop above the leaves loop in `phoenix.gd:263-280`. **This is the highest-value headless test in the file**: the invariant is currently asserted in a comment (`:257-262`) and by nothing else. |
| 8 | **`decode()` against hostile input.** `""`, `"{"`, `"[1,2,3]"`, `"null"`, a `phx_reply` with no `payload`, a `broadcast` whose inner `payload` is a string, a 64 kB junk string. All return a well-formed dictionary; none crash; the array case is `KIND_UNKNOWN`. | Remove the `typeof(j.data) != TYPE_DICTIONARY` guard at `:187-188`. |
| 9 | **Join-reply disambiguation.** A `phx_reply` bearing our join ref is `KIND_JOIN_OK`; the same frame with any other ref is `KIND_REPLY`. | Delete the `out["ref"] == join_ref_sent` test at `:209`. |
| 10 | **Session state machine.** With HTTP and channel stubbed, drive OFFLINE→CLAIMING→CONNECTING→LOBBY→IN_RUN. Assert refusals: `start_run()` as a guest is a no-op; `host_room()` when not OFFLINE is a no-op; `join_room("XXX")` emits `error` and stays OFFLINE. **Bound both ends** — also assert the legal transitions *do* fire, or the test passes equally against a session that has stopped working. | Delete `if not _is_host` in `start_run`. |
| 11 | **Lobby list maths.** `players()` puts the host first then sorts by key; exactly one entry has `me`. Sweep every ordering of `MAX_PLAYERS + 1` keys and assert the self-eject rule (`session.gd::_on_roster`) ejects the client whose key sorts last and never the first. | Change `ahead >= MAX_PLAYERS` to `>`. |
| 12 | **Lag-compensation ring.** `HistoryRing.query(tick)` returns the exact stored frame; a tick older than the ring returns the oldest **and reports it clamped**; a future tick returns the newest. | Off-by-one the modulo index. |

### 7.13–7.16 Assertions that belong in existing check files

| # | File | Assertion | Control |
|---|---|---|---|
| 13 | `checks/curves.gd` | **`zombie_count(r, 1)` is bit-identical to the committed solo table for r ∈ 1..40**, and `zombie_count(r, 2) / zombie_count(r, 1)` matches the canon ratio at r ∈ {1,5,10,20,30} within rounding. Provenance in the assertion text: `_zombiemode.gsc:3140-3163` + `:3075-3101` for the ratio, `kriegsnacht.html:2189` for the base. | Change the `n == 1` early-out → the identity check must fail. |
| 14 | `checks/downed.gd` | **The revive contract, bounded at both ends.** Put B down; stand A inside the radius and facing; step real ticks: assert B is **still down at 2.9 s** and **up at 3.0 s**, with zero perks and the correct HP. Repeat with A holding Quick Revive: **down at 1.4 s, up at 1.5 s.** *(The 4 s window against a 3.4 s reload asserted nothing because the magazine was always full. A revive test that only checks completion passes against a revive that is instant.)* | Set `reviveTime` to 1.0 unconditionally → the 2.9 s refusal must fail. |
| 15 | `checks/enemies.gd` | **Consumer-driven cross-package contract.** Set up two player bodies, spawn a real zombie through the real director, step it, and assert it **moves toward the nearer one** and re-targets when that one goes down. Not "read the target back" — CLAUDE.md names that failure explicitly, and it is what let a completely inert Monkey Bomb pass. | Pin `target` to player 0 → the re-target case must fail. |
| 16 | `checks/net.gd` | **Encode/decode through the real entities.** Take a live host world, encode a snapshot from the *real* `HostLink`, decode it into *real* puppets, and assert each puppet's `global_position` is within 1 cm and its atlas row matches the source zombie's for a fixed camera. This is the "assert through the real path" rule: a round-trip over hand-built dictionaries tests a copy. | Drop `f` (facing) from the encoder → the atlas-row half must fail while the position half still passes. |

### 7.17 What genuinely cannot be asserted, and the manual gate for it

**Not assertable, and no assertion will pretend otherwise:**

1. **That a real browser's `WebSocketPeer` reaches Supabase from the shipped `.pck`.** Every
   transport claim in this project rests on the *desktop editor binary*. The engine pass
   proved two things diverge silently between desktop and web —
   `WebSocketPeer.set_handshake_headers()` (`WARN_PRINT_ONCE` and discarded on web) and
   `heartbeat_interval` (0 hits in `emws_peer.cpp`, 6 in `wsl_peer.cpp`) — and that
   `EMWSPeer::connect_to_url` **rebuilds the URL** rather than passing it through. We are
   safe on the last one only because `phoenix.gd::socket_url` always emits a path
   (`/realtime/v1/websocket`); a pathless URL would have its query string lowercased into the
   host. **No web export has ever been built and loaded for this.**
2. **Real latency, jitter and loss between two machines.** Everything measured is
   `me → us-east-1 → me`.
3. **Whether 120 ms of interpolation looks right.** `tools/frames.ps1` cannot drive a
   network and `frame.gd` renders nothing.
4. **Whether the 100 msg/s cap binds.** It did not fire at 160 ev/s for 140 s.
5. **Whether two players find it fun.**

**The manual gate**, modelled on `tools/frames.ps1` — a documented human step, outside
`--verify`, not counted in `ASSERTION_FLOOR`:

```
--path . --netprobe            # WINDOWED. Never with --headless: no rendering device,
                               # and --shot under --headless hangs forever for that reason.
```

Opens two `Session` instances in one process against a real room, exchanges 200 snapshots,
and prints a pass/fail line with delivered count, one-way median/p95, and dropped sends. Run
it **from a web export in Chrome** before Package R is considered done, and record the output
in `notes/net/`. That single page load falsifies or confirms every claim in item 1 above, and
it is the cheapest high-value action in this entire plan.

**And a local loop that needs no network at all:**

```
--path . --netloop [--delay 120 --loss 2]
```

Runs `HostLink` and `GuestLink` in one process wired directly to each other through a
delay/loss queue, no socket. This is how interpolation and lag compensation get iterated on
without spending quota — and given that the free tier is ~9 h/month total and the Supabase
research pass already burned 2.15% of it on probes, **`--netloop` is not a nicety, it is the
development environment.**

### 7.18 Suite bookkeeping

`ASSERTION_FLOOR` is contended (`verify.gd:96-125`). Raise it **additively** by exactly what
each package adds; reconcile to the real total only at the integration point. Current value
585.

*(CLAUDE.md says "the suite is ~483 assertions"; the floor reads 585, reconciled at 560 and
raised additively since. Reported, not fixed — not my file.)*

---

## 8. Risks, ranked

Ranked by P(fails) × cost-of-failure, not by how interesting they are.

### 8.1 The web export has never opened a socket — **highest risk in the plan**

Every transport claim rests on the desktop editor binary. Two `WebSocketPeer` features are
proven to work on desktop and be inert on web; `connect_to_url` re-parses and rebuilds the
URL on web only; `Thread` is a silent no-op (`export_presets.cfg:26-29` disables it because
GitHub Pages cannot set COOP/COEP), so `HTTPRequest.set_use_threads(true)` does nothing.
There is also a free-to-mitigate hazard: `HTTPRequest.accept_gzip` defaults **true**, and
`scene/main/http_request.cpp:336-345` still gunzips a body the browser has already
decompressed — and PostgREST **exposes `Content-Encoding` via CORS**, which is exactly the
condition Godot's maintainer assumed could not occur when closing #79327.

**Fallbacks, in order:** (a) set `accept_gzip = false` on every `session.gd` request — free,
do it regardless; (b) if `WebSocketPeer` misbehaves in-browser, swap in the
`JavaScriptBridge` buffer-in-JS transport behind `realtime.gd`'s existing interface — one
`eval(..., true)` installs the socket and pushes frames onto a JS array behind a try/catch,
one `eval` per frame drains it with `arr.splice(0).join("")`. It matches
`save_store.gd`'s three conventions exactly (`:84-98`) and additionally fixes the 65,536-byte
inbound ring, which silently drops on overflow and gives roughly **6.7 s of not-draining**
before packets vanish.

**Mitigation, and this is the first action item of the whole package:** build a 20-line web
export and load it in Chrome **before Package R starts.** One page load.

### 8.2 Package P breaks solo

57 call sites, five `static` accessors with no player argument, inside a physics loop. If
this goes wrong it goes wrong everywhere and it is hard to bisect.

**Fallback / mitigation:** P is a pure refactor with a mechanical gate — `--verify` green,
`--sim` baselines byte-identical, `tools/frames.ps1` zero drift. **A moved sim baseline means
the refactor is wrong.** If the `weapons.gd` statics resist, the escape hatch is a
`Weapons.for_player(p)` façade returning a small bound object, which is uglier but local.

### 8.3 The quota runs out during development

~9.3 h/month total, and 2.15% is already spent on research probes. Two agents iterating on
interpolation would burn a month in an afternoon.

**Fallback:** `--netloop` (§7.17). Build it **first**, in Package R, before any live testing.

### 8.4 Interpolation feels bad, or lag compensation feels unfair to the host

120 ms of buffer plus 40–160 ms of network is a visible delay on remote zombies, and the host
will occasionally die to a zombie the guest shot "after" it moved.

**Fallback:** both are constants. Snapshots to 20 Hz costs 9.26 → 6.9 h/month. Rewind cap
from 400 ms to 200 ms trades guest accuracy for host fairness. Tune with `--netloop`, decide
with two humans, not with argument.

### 8.5 Two-player zombie targeting is bigger than it looks

`Zombie.target` is one `Node3D` (`:362`) read at five sites (`:767` melee reach, `:838` chase
goal, `:862` groan range, `:1022` nuke stagger, `:1054` shove fallback), and `FlowField`
early-returns unless *the* goal tile moved (`flow_field.gd:22-27`), then BFS's 42×34 = 1428
tiles. The canon pass called this "the item most likely to be underestimated" and I agree.

**Fallback ladder:** (a) two fields, one per player; each zombie picks the nearer player's
field and re-evaluates every 0.5 s — worst frame 3.2 ms, only on tile crossings, against a
measured 1.585 ms median / 2.223 ms p99 per solve; (b) if that measures badly, one
multi-source BFS plus a direct steer over the last few metres, losing the ability to target a
*specific* player; (c) if targeting still thrashes, add hysteresis (switch only when the
other player is 25% nearer).

### 8.6 Two shadow-casting torches

`player.gd:310-313` records that each shadowed light re-draws every instance it touches, and
that a spot was chosen over an omni because an omni needs six passes. `gl_compatibility`
offers no cheap out.

**Fallback:** the remote torch ships `shadow_enabled = false` by default. Decide with a new
`coop` frames scenario and a **ratio** rule in `golden.json`, never an absolute — absolute
brightness drifts with every tuning pass and a gate with a maintenance tax gets deleted.

### 8.7 Host spoofing

Anyone who knows a six-character code can join the public channel and broadcast frames
claiming to be the host. No RLS can prevent it because RLS is not in the path
(`realtime_channel.ex:485, 1012`); `host_token` protects the database row and nothing else.
Guessing is not the worry (50 live rooms out of 481,890,304 ≈ 1×10⁻⁷ per guess); a shared or
overheard code is.

**Fallback:** the host publishes `hash(host_token + code)` once at lobby start and the guest
pins the first host identity it sees, ignoring snapshots from any other sender. ~15 lines, in
`scripts/net/`, not in Postgres. Acceptable to defer for a PvE game with no persistence;
**not** acceptable the moment a shared leaderboard exists.

### 8.8 `room_exists` reports dead rooms, and the two proposed fixes contradict each other

The reap is lazy — it runs only inside `claim_room()` — so a room outlives its host until
someone else creates one anywhere on the project. A player types a dead code, is told it
exists, joins an empty channel and waits out a 12 s timeout. Meanwhile the proposed 3-minute
liveness window would mark every live room dead against `session.gd`'s 300 s heartbeat.

**Fallback:** land both halves of H6 together — heartbeat 120 s, window 10 minutes — or land
neither. A pg_cron reaper is *available* on this project (`pg_cron 1.6.4`, contradicting the
in-code comment that says it is not) but is still the wrong answer, because a Free-plan
project pauses after 7 days of inactivity and a paused project's cron does not run.

### 8.9 `main.restart()` strands the guest

`restart()` reloads the whole scene (`main.gd:675-681`). `Net` survives because it is an
autoload — deliberate, and `session.gd`'s header says why — but a host who dies and hits TRY
AGAIN leaves the guest sitting in a room whose host is rebuilding.

**Fallback:** `restart()` calls `Net.leave_room()` when `Net.is_online()`, and both players
land back on the title screen. A shared "play again" is a nice-to-have that needs a lobby
that survives a run, which is not in this slice.

### 8.10 A parse error in the net layer hangs the whole project

`Net` is an autoload, so it is reachable from the main scene, so a parse error in it takes
`--verify` from ~5 s to ~414 s before exiting 1 — and looks exactly like a hang. With several
agents in flight this blocks everyone.

**Fallback:** every package parse-gates its own files individually
(`--headless --path . --check-only --script <file>`) rather than running `--verify` while
others are working. Remember the gate **does not register autoloads**, so
`Identifier not found: Game / Sfx / Rng / Settings / Net` is a false positive, and it
**aborts at the first error**, so a clean gate on a long file means little.

---

## Appendix A — action order

1. **Web-export socket probe in Chrome.** One page, one load, before anything else. (§8.1)
2. **Package P**, alone, gated on identical sim baselines. (§4.2)
3. **`--netloop`**, first thing in Package R. (§8.3)
4. **Package C** and **Package R** in parallel; **Package M** and **Package T** throughout.
5. Hunks H1–H6 to their owners, each with a check that fails until it lands.
6. `main.gd` integration pass, single agent, last.
7. `--netprobe` from a real web export, two browsers, output recorded in `notes/net/`.

## Appendix B — researcher overrules, collected

| # | Overruled | Why |
|---|---|---|
| 1 | replication §6.1 — byte-packed binary snapshots with dirty masks | Optimises bytes; Supabase bills messages. 400× of payload headroom, 8% win, hand-rolled packer on both ends of an untestable link. JSON with short keys. (§3.1) |
| 2 | replication §8.1 — client prediction + input-frame replication at 20 Hz | Deleted, not deferred, by trusted-client movement. Also dissolves that report's "single concrete blocker" (VISUAL spread): the guest sends the ray, not the seed. (§2.3) |
| 3 | probe note `:113-120` — "60 messages/second" for 4 players | 4× low; sends counted, fan-out not. Real figure 240. The Supabase pass caught it and is right. (§3.8, H5) |
| 4 | `session.gd:MAX_PLAYERS := 4` | Cut to 2. Quota, frame budget and balance evidence all agree. (§1.3) |
| 5 | canon pass — change `DOWNED_TIME` 7.0 → canon's 10 s | Correct finding, wrong package. Solo balance does not move inside a co-op change. Recorded as a departure instead. (§6.16) |
| 6 | engine pass — `heartbeat_interval` as an active trap | Already avoided: `realtime.gd:193-198` sends an application-level Phoenix heartbeat and never touches the property. Kept as a prohibition, downgraded from a defect. |
| 7 | Supabase pass — `room_exists` 3-minute liveness window | Right defect, wrong constant: it contradicts `session.gd`'s 300 s heartbeat and would kill every live room. 120 s / 10 min instead. (H6, §8.8) |
| 8 | `notes/research/SYNTHESIS.md:200` — alive cap attributed to `zombie_max_ai` | Number right, variable wrong. `zombie_max_ai` is the round-total base; the cap is `zombie_ai_limit`. Reading it the documented way yields 30 alive at 2p. (§6.2) |
