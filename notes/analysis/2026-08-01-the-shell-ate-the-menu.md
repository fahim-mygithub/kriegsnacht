# The loading shell ate the title screen, and co-op with it

Reported by the player, against the live GitHub Pages build, the day after the
co-op package shipped:

> When you load the game in the github pages we might be using an old title screen
> scene I only have enter the bunker as an option

The build was not old. `docs/index.pck` on the live site hashed byte-identical to
the one committed at `e004521`, and the title screen in it has MULTIPLAYER on it.
The player never saw that screen.

---

## What actually happened

`web/shell.html` is the loading page. It exists because a browser resumes an
AudioContext only from inside a user gesture, so the port collects exactly one
deliberate click and spends it on the audio driver — by dispatching a synthetic
`mousedown` at the canvas, because it is DisplayServerWeb's mouse callback that
calls `OS_Web::resume_audio` and there is no other supported way in.

`hud.gd` had a click-anywhere-to-begin poll, inherited from Milestone 1 and from
the ancestor (html:1043, `canvas.onmousedown` starts a run from either overlay).
It read the Input singleton, so it could not tell the shell's synthetic gesture
from a real one — and by design it did not have to, because starting the run from
that click is what it was written for.

So: **the shell's audio click pressed ENTER THE BUNKER.** The game's title screen
was constructed, bound and then immediately left, in the same frame, without ever
being drawn. Every browser player went from the loading page into a solo run.

The three things on that screen — MULTIPLAYER, OPTIONS, and the best-round line —
were unreachable on the web except by starting a run and abandoning it:

```
shell: "Enter the bunker"  ->  solo run  ->  P  ->  ABANDON RUN  ->  title screen
```

which is how the previous session's browser-to-browser co-op pairing was done
without anyone noticing the front door was walled up.

## Reproduced before it was fixed

Live site, current build, four steps, screenshots at each:

1. `https://fahim-mygithub.github.io/kriegsnacht/` — the shell. One button.
2. Click it — round 1, 500 points, M1911, pointer locked. No title screen.
3. `P` — PAUSED / RESUME / OPTIONS / ABANDON RUN. No multiplayer.
4. ABANDON RUN — KRIEGSNACHT / **ENTER THE BUNKER / MULTIPLAYER / OPTIONS** /
   `best: round 9 · 11,400 points`.

Step 4 is the screen the player was told did not exist.

## What was ruled out first, and how

The obvious suspect was a stale service worker serving an old `index.pck`, and it
was wrong. Checked, in this order:

| Claim | Evidence | Verdict |
| --- | --- | --- |
| Pages is serving an old build | live `index.pck` sha256 `7bbf1127…` == committed | serving the current build |
| the export predates co-op | `docs/index.pck` last written by `e004521` | current |
| the SW cache key never changes | `CACHE_VERSION` differs across all 7 export commits | invalidation works |
| my own browser is stale | its cached pck hashes equal to the network's | already current |

Only after all four came back clean did it become worth reading what the shell's
click actually does.

**The service-worker trap is still real, just not this.** Godot's worker does not
call `skipWaiting()`, so a returning player runs the previous build until every tab
of the origin is closed — the engine exposes `JavaScriptBridge.pwa_needs_update()`
and `pwa_update()` for exactly this and nothing in the game calls either. Left
alone here because it is a different defect with a different fix, and mixing them
would have made this one impossible to verify. Filed.

## The fix

`hud.gd`'s poll now acts on the game-over screen and nowhere else.

That is a **deliberate departure from the ancestor**, and the reason is that the
ancestor's title screen had exactly one action on it — "click anywhere" and "press
the only button" were the same sentence there. This one has three buttons, and one
click that no player aimed.

It is also the third defect of one shape, and the first two are already commented
in `checks/shell.gd`:

1. the mouse-sensitivity slider: dragging it started the run;
2. every co-op screen: a click on JOIN A ROOM, on the code field, on LEAVE;
3. this one: the shell's audio click.

The first two were fixed by guards inside `press_primary()`, which have to
enumerate every screen that must not act — one new screen away from failing again
each time. The guards stay, and the source is removed as well.

Three supporting changes, all in `web/shell.html`:

- **The synthetic click moved to the canvas corner.** It now lands on a screen made
  of centred buttons, and a press at the middle of the canvas is a press on
  whichever one the window size happens to put there. Audio resume does not care
  where the click was, only that the engine saw one.
- **The button no longer says "Enter the bunker."** That is the game's own primary
  button, one screen further in, and this page wearing the same words is what made
  the report read as "the title screen is missing its multiplayer option". It says
  *Open the door*.
- **The ready line says what is behind it**: `Sound on. Solo and co-op are both on
  the menu inside.` The old line described a click that went straight into a run.

Pointer lock is not asked for from the shell any more and does not need to be: the
player's own click on ENTER THE BUNKER is a fresh gesture carrying its own
transient activation, which menu.gd spends from inside the button press.

## The assertions, and what they do not cover

`checks/shell.gd::_shell_click_is_not_a_run`, two checks in one drive:

```
PASS  a click the player did not aim at a button does not start a run
PASS  the same click still restarts from the game-over screen
```

Driven through `hud._menu_click()` — the caller — and not through
`press_primary()`, which was never the broken part and would have passed against
the shipped bug.

**The Input read is not covered, and that is measured rather than assumed.**
`is_action_just_pressed` is true only on the frame the press arrives, and a
`--verify` check is one synchronous call inside a physics frame. Probed in situ at
physics frame 1: `Input.action_press("fire")` leaves it reading `false`, and so
does `parse_input_event` + `flush_buffered_events`, while `is_action_pressed` reads
`true` in both cases. So `_poll_menu_click` was split — the uncoverable Input gate
on one side, the branch that decides what a click *means* on the other.

That split was forced by the acceptance half failing on its first run
(`restarts=0`). Had the check only asserted the refusal, it would have gone green
against a drive that never reached the function at all. Bounding it at both ends
is the only reason that was visible.

Controls, `scratchpad/menu-click-controls.ps1`, both sabotaging `_menu_click`:

| Control | What it restores or cuts | Verdict |
| --- | --- | --- |
| `title-acts-again` | the shipped bug, exactly | fails *a click the player did not aim…* (680/1) |
| `over-inert` | the game-over branch stops acting | fails *the same click still restarts…* (680/1) |

Each fails exactly one check, and it is the named one.

## Verified after the fix

Live Pages build at `cd71043`, service worker unregistered and CacheStorage
cleared first so the load is a first-time visitor's:

1. the shell shows **OPEN THE DOOR** and *Sound on. Solo and co-op are both on the
   menu inside.*
2. clicking it lands on the **game's title screen** — mouse free, no run started,
   ENTER THE BUNKER / MULTIPLAYER / OPTIONS, and the best-round line;
3. MULTIPLAYER → HOST A ROOM / JOIN A ROOM / BACK;
4. HOST A ROOM → *claiming a room…* → **SH59WH** → *opening the channel…*;
5. LEAVE, BACK, ENTER THE BUNKER → round 1, 500 points, M1911.

So the whole co-op front door is reachable in two clicks from a cold load, which
is the thing that was impossible before.

**THE POINTER LOCK COULD NOT BE CONFIRMED THIS WAY, and the reason is the harness,
not the change.** The driven tab reports `visibilityState: "hidden"`, and Chrome
refuses pointer lock to a hidden document outright — probed directly from a click
handler in that tab, `requestPointerLock()` rejects with `WrongDocumentError: The
root document of this element is not valid for pointer lock` while
`navigator.userActivation.isActive` reads `true`. The gesture is there; the tab is
not. The same refusal would have met the old shell-driven path.

What can be said without a browser: the capture is asked for from
`menu.gd::_on_start` → `press_primary()` → `start_game()` → `Player.set_capture`,
which is the identical call chain the shell's click used to reach — only the click
supplying the activation has changed, from the shell's button to the menu's. That
chain is also the one desktop has always used, and the one any web player who
reached the title screen through ABANDON RUN was already using. **Worth one
by-hand check in a visible tab.**

## What this does not fix

- **The stale-worker problem above.** A player who has loaded the site before still
  runs the previous build until every tab of the origin is closed. That is what
  makes this fix reach them late, and it is filed separately.
- **Anything about the shell being a copy of the title screen.** It still repeats
  the game's own key grid and hint text, which is right while 38 MB downloads and
  duplicative the instant the game appears. It is one more screen that has to be
  kept in step by hand, and the next thing to drift.
