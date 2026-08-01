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

## Message budget

At 15 Hz host snapshots plus 15 Hz per-client input, a 4-player session is
`15 + 3 × 15 = 60` messages/second — which the burst test cleared without throttling.
That is 216,000 messages an hour, so the free tier's monthly allowance is the binding
constraint on session hours, not the tick rate. Cutting the client input rate is the
cheapest lever if that ever bites: inputs are far more compressible than snapshots, and
a client sending at 10 Hz is not perceptibly worse.

## Reproducing

```
node rt_probe.mjs      # anon join, presence, burst, payload ceiling
node rt_latency.mjs    # 15 Hz sustained, one-way distribution, jitter
```

Both live in the session scratchpad rather than the repo: they hold a live project ref
and are throwaway diagnostics, not part of the build. Their substance is this file.
