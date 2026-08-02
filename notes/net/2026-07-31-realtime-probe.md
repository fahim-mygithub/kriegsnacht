# Supabase Realtime as a game relay — measured, not assumed

Everything the co-op design assumes about the transport was measured against the real
project (`qalanxifxfukkeqdhfqh`, region `us-east-1`) before any GDScript was written.
The two probe scripts are reproduced at the bottom so the numbers can be re-taken when
someone doubts them.

**Read this before changing the tick rate.** The rate is not a preference; it is derived
from the delivery figures below.

---

## What was in question

The whole host-authoritative-over-a-relay design rests on four claims. Each was tested
rather than reasoned about:

1. Two **anonymous** clients holding only the publishable key can join one **public**
   channel. (If this needed auth, the game would need accounts, and it does not have any.)
2. Presence can carry a lobby roster.
3. A host can broadcast to a peer at a usable rate without tripping a rate limit.
4. A realistic snapshot fits in a payload.

## What came back

| Claim | Result |
| --- | --- |
| Anonymous join, `private:false` | **Yes.** `phx_join` → `status: ok` with only `?apikey=<publishable>`. No RLS involved. |
| Presence roster | **Yes.** Both clients converged on `{HOST, PEER}` with custom metadata (`role`, `name`) intact. |
| Burst of 30 broadcasts | **30/30 delivered.** No `system` rate-limit event, no `phx_error`, socket stayed open. |
| 4 players + 24 zombies as JSON | **654 bytes**, delivered intact. |

### Delivery at 15 Hz, sustained 8 s (120 messages)

| | |
| --- | --- |
| Delivered | **120 / 120 — zero loss** |
| One-way, median | **23 ms** |
| One-way, p95 | 36 ms |
| One-way, max | 63 ms |
| Inter-arrival gap, median | 63 ms (against a 67 ms target) |
| Inter-arrival gap, p95 | 79 ms |
| Inter-arrival gap, max | 101 ms |

## What these numbers do and do not license

**They justify a 15 Hz host snapshot** with an interpolation buffer of ~100 ms, which
covers the p95 inter-arrival gap (79 ms) with margin for the max (101 ms).

**They are a floor, not a typical case.** Both endpoints were on one machine in one
country, so the measured path is `me → us-east-1 → me`. Two real players are
`A → us-east-1` plus `us-east-1 → B`, each of which can independently be worse than the
whole round trip measured here. Budget 40–160 ms for distant players and do not treat
23 ms as the number a player in Australia will see.

**A discarded figure, recorded so it is not re-derived.** The first probe reported
`broadcast_rtt_ms: 2514`. That was a measurement bug — the timer spanned the probe's own
`sleep(2500)` — and it measured the sleep, not the relay. It is quoted nowhere. The
second probe stamps the send inside the payload and resolves on the matching receive,
which is where the 23 ms comes from. Both endpoints share one process clock, so the
one-way figure is a real subtraction and not a halved round trip.

## The consequence for the schema

The probe settles a design question that would otherwise have gone the expensive way:
**a public channel needs no table and no RLS.** Broadcast and presence work with nothing
but the publishable key, so the transport requires zero database.

That leaves the `rooms` table doing exactly one job that presence cannot do atomically:
**claiming a code without a race.** Presence can answer "is anyone in room ABCD?", but
only after a round trip, which leaves a window in which two hosts both believe they own
the code. A `UNIQUE` constraint closes it in one statement. The table is therefore small
and deliberately not the source of truth for anything else — liveness stays with presence,
because a browser tab that dies never gets to update a row.

## The Godot half, verified against the same channel

The figures above were taken with a Node client. That proves the *service* works; it
does not prove **Godot's `WebSocketPeer` can speak to it**, which is a separate claim
and the one the game actually depends on. So the same channel was driven from
`scripts/net/realtime.gd` with the Node client sitting on it as an independent
listener — meaning a shared misreading of the protocol docs cannot pass, because two
separate implementations have to agree.

| | |
| --- | --- |
| Godot completed the Phoenix handshake | **Yes** — `phx_join` → `status: ok` |
| Presence, both directions | Godot saw `NODE`; Node saw `GODOT1` carrying `{"name":"GodotHost","role":"host"}` intact |
| Broadcasts Godot → relay → Node | **5 / 5**, payloads byte-correct |
| `close_channel()` | produced a clean `presence leave` at the peer, so a quitting player disappears immediately instead of timing out |
| Dropped sends | 0 |

`WebSocketPeer` therefore works headless, over `wss://`, with a query string, sending
and receiving text frames. Nothing about the transport needs `JavaScriptBridge`.

### The trap that cost the first attempt

The first live run reported `joined: false` **and no failure at all**, which reads
exactly like a network fault and is not one.

Under `--script`, `root` is not yet in the tree during `_initialize()`. So
`root.add_child(node)` there leaves `is_inside_tree()` false, `set_process(true)` does
not stick, the node's `_process` never runs, the socket is never polled, and the whole
thing sits silent forever. It was diagnosed by driving a **raw `WebSocketPeer`
alongside** as a control: the raw peer connected and joined while the node never
processed, which localised the fault to node processing in one run instead of to the
network in several.

Attach on the first `_process` tick instead. In the shipped game this cannot arise —
the node lives in a live tree — but any future harness that drives the net layer from
a `SceneTree` script will hit it again.

## The web export, verified in a real browser — and the bug it exposed

Everything above was taken against the **desktop** binary. That proves the protocol
and the service; it does not prove the target. The shipped GitHub Pages build was
therefore driven by hand in Chrome, which settled the largest open risk in the
design and immediately found a defect nothing headless could have.

| | |
| --- | --- |
| `HTTPRequest` in the web export | **Works.** HOST A ROOM returned the code `ZK68G2`. |
| The claim reached the real database | **Yes** — `room_exists('ZK68G2')` answered `true` from an independent client. |
| `WebSocketPeer` in the web export | **Works.** The channel joined, presence resolved, and the lobby armed START THE RUN. |
| The lobby | Rendered `Takeo (host · you)` and one `— empty —` seat, reading `MAX_PLAYERS` correctly. |

So the web export can open a socket to Supabase Realtime. That risk is closed.

### A BACKGROUNDED TAB LOSES THE ROOM

Left alone for roughly a minute while unfocused, the session died and the menu
reported *"Lost the connection to the room."* An independent client that joined the
same code moments later saw `presence_state -> []` — the host was already gone.

The cause is not the relay and not the code. **Godot's web main loop runs on
`requestAnimationFrame`, and Chrome throttles or halts rAF on a tab that is not
foreground.** No main loop means `realtime.gd::_process` never runs, which means the
15 s heartbeat never goes out, and the server closes an idle socket at 25 s.

`PROCESS_MODE_ALWAYS` does not help here and it is worth being precise about why: it
defends against `get_tree().paused`, which is a *tree* state. This is the *engine*
not being ticked at all. The two failure modes look identical from inside GDScript
and only one of them is fixable from there.

Consequences, as found:

1. Alt-tabbing for ~30 seconds ended the session. For a co-op game people play while
   talking on Discord in another window, this is the difference between working and
   not.
2. The failure was at least *clean* — `realtime.gd` climbed its backoff ladder, gave
   up, and `session.gd` reported a player-facing sentence rather than hanging on a
   dead socket. That half behaved exactly as designed.

### FIXED — the heartbeat now runs off a JS timer

`realtime.gd::PULSE_MS` installs a `setInterval` through `JavaScriptBridge` that
polls the socket and beats if one is owed. `save_store.gd` is the precedent for
reaching the browser this way. Chrome *clamps* a hidden tab's timers to roughly 1 Hz
rather than halting them the way it halts rAF, so a beat still lands well inside the
25 s close.

Two things changed alongside it, and both are load-bearing:

- **The beat is on wall clock, not accumulated `dt`.** There are now two drivers —
  the frame loop and the pulse — and accumulating in both double-counts while
  accumulating in one leaves the other unable to tell whether a beat is owed.
  `_hb_at` is a `Time.get_ticks_msec()` stamp and `_beat_if_due()` is idempotent.
- **The pulse deliberately does not `_pump()`.** Dispatching game messages into a
  tab that is not rendering would drive the session from outside the frame loop with
  nothing to draw the result on. Packets queue and `_process` drains them on the
  first real frame back.

**WHAT IT DOES NOT BUY, stated plainly.** After roughly five minutes hidden, Chrome's
*intensive* throttling drops timers to about once a minute, which is not enough
against a 25 s budget. So this covers a tab backgrounded for minutes, not hours —
which is the case that actually happens, because the thing people do is alt-tab to
read the room code to somebody. A tab left hidden for ten minutes will still lose the
room, and nothing in the UI says so.

The arithmetic is asserted in `checks/net.gd` ("a hidden tab still beats before the
idle close", "the web pulse fires several times per heartbeat period"), both
controlled by sweeping `PULSE_MS`: at 20000 both fail; at 6000 only the frequency one
does. The arithmetic is all the suite can reach — the *behaviour* is a browser fact
and is verified by hand, below.

## Message budget — CORRECTED, and the first version was 4× low

**The original version of this section was wrong and the error decided the player
count, so it is worth stating plainly.** It costed a 4-player session at
`15 + 3 × 15 = 60` messages/second by counting only what each client *publishes*.

Supabase does not count publishes. Its
[limits page](https://supabase.com/docs/guides/realtime/limits) defines an **event**
as *"a WebSocket message delivered to, or sent from a client."* One broadcast into a
room of N therefore costs **1 send + (N−1) deliveries = N events**. Fan-out is the
whole cost and it was missing.

At 15 Hz in both directions, against the free tier's **100 events/second**:

| Players | Host snapshots | Client input | Total | |
| --- | --- | --- | --- | --- |
| 2 | 15 × 2 = 30 | 15 × 2 = 30 | **60/s** | fits |
| 3 | 15 × 3 = 45 | 2 × 15 × 3 = 90 | **135/s** | over |
| 4 | 15 × 4 = 60 | 3 × 15 × 4 = 180 | **240/s** | 2.4× over |

Exceeding it is not graceful degradation — `tenant_events` **disconnects the
sockets**, and the client library's automatic reconnect turns that into a loop.

**This is why the game is 2-player.** Four would need ~6 Hz, which is unusable for
aim even with interpolation, or the Pro plan's 500 events/second. `MAX_PLAYERS` in
`session.gd` carries the same arithmetic so nobody raises it casually.

### Why the burst test did not catch this

The burst test pushed 30 messages and saw no throttle, which was read as headroom. It
was not: one publisher and one subscriber makes 30 messages cost ~60 events spread
over three seconds — nowhere near 100/second. **The probe measured a 2-player load
and the note drew a 4-player conclusion from it.** The measurement was fine; the
extrapolation was not.

### Monthly quota, separately

The free tier also allows 2 million events a month. At the 2-player rate of 60
events/second that is ~9.3 hours of play a month, which is the real ceiling on a
hobby game and is worth knowing before anyone is surprised by it. Cutting the client
input rate is the cheapest lever: inputs compress far better than snapshots, and a
client sending at 10 Hz is not perceptibly worse.

## Reproducing

```
node rt_probe.mjs      # anon join, presence, burst, payload ceiling
node rt_latency.mjs    # 15 Hz sustained, one-way distribution, jitter
```

Both live in the session scratchpad rather than the repo: they hold a live project ref
and are throwaway diagnostics, not part of the build. Their substance is this file.
