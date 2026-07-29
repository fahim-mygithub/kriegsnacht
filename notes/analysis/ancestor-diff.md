# Ancestor diff — `kriegsnacht.html` → Godot port

**Date:** 2026-07-27 (pass 2 — complete file coverage)
**Method:** full read of `kriegsnacht.html` (3,476 lines; CSS 1-230, DOM 232-360, script 362-3,474)
against every file in `scripts/` (~2,700 lines of GDScript). Every "port status" cell was
verified by search against the Godot tree, not inferred. The verification greps are in §7.

**What changed in this pass.** Pass 1 covered the systems half and explicitly excluded four
regions. All four are now read, and they contained the largest single deletion in the project
(the entire weapon-art pipeline), a three-line renderer trick that is the reason the port's
rooms look flat, an automatic performance governor that matters more here than anywhere else
given the GitHub-Pages constraint, and a dead-data trail proving **two weapons do not work**.
Pass 1 also asserted one feature that never existed; see §6.

---

## 0. The three things worth reading first

**(a) Two weapons in the port are silently broken, not merely unpolished.**
`weapons.gd` carries `proj`, `splash` and `splash_dmg` for the Ray Gun (620 splash) and China
Lake (1,150 splash). `player.gd:200-204` branches on `def.cone` or falls through to
`_hitscan` — **`def.proj` is read nowhere in the codebase.** So the Ray Gun is a 180-damage
single-target hitscan and the China Lake is a 120-damage, 62-rpm hitscan: the two most
expensive box pulls are the two worst guns in the game. The ancestor had a full projectile
integrator with gravity, an arming radius and a radial-falloff explosion that also hurts the
player (2552-2620). This is dead data pointing at a deleted subsystem, and it is invisible in
play because nothing errors.

**(b) The Pack-a-Punch machine does not exist as an object.** `main.gd:340-343` registers a
`"pap"` interactable at `MapData.PAPSPOT` and never calls `_prop_sprite` for it — unlike the
generator (`:339`), the perks (`:333`) and the box (`:346`). `assets/props/` contains no
`pap_off.png` / `pap_on.png`. The 5,000-point endgame purchase is an invisible trigger volume
in the middle of the Generator Hall floor. The art exists in the ancestor at 1986-2012 and can
be replayed the same way the other props were.

**(c) The rooms look flat for one reason and it is three lines.** Ancestor line 1799:
`if(side===1) lit = (lit*186)>>8` — north/south wall faces render at **0.727×** the brightness
of east/west faces. That single multiplier is what gives a texture-mapped box interior corner
definition, and it is the standard raycaster stand-in for directional light. `WorldBuilder._quad`
writes one vertex-colour `shade` per tile regardless of face normal, so every corner in the port
meets at identical luminance. Under `gl_compatibility` with no shadows and no SSAO, this is the
cheapest possible restoration of depth read in the entire project.

---

## 1. Master table — restorations ordered by value ÷ cost

Cost: **S** ≤ 1 day · **M** 1-3 days · **L** 1-2 weeks. Value: ★★★ changes how the game reads
or plays · ★★ noticeably better · ★ polish. Recipes for every **deleted** row are in §2.

### Tier A — cheap and high-value. Do these first.

| # | Behaviour | html | Port status | Cost | Value |
|---|---|---|---|---|---|
| A1 | Wall face directional shading (N/S faces ×0.727) | 1799 | deleted | **S** | ★★★ |
| A2 | Hitmarker on **every** damage event, blood-red on kill | 3086-3092, called 2238 + 2243 | deleted | **S** | ★★★ |
| A3 | Hit flinch — white tint on the zombie for 0.09 s | 2077, 2223, 2251 | deleted | **S** | ★★★ |
| A4 | Hold-F barricade rebuild, 0.34 s/board, +10 pts | 2978-2989 | deleted (`PTS_REBUILD` dead) | **S** | ★★★ |
| A5 | Per-zombie attack timer — N zombies deal N× DPS | 2213, 2323-2332 | **replaced** by one global cooldown | **S** | ★★★ |
| A6 | Prompt states: affordable / can't-afford / owned / free / hold, + `deny` + 260 ms red flash | 2694-2748, 3052-3067, 3081-3084 | deleted — port returns a bare String | **S** | ★★★ |
| A7 | Unavailable interactables skipped **in the scan**, not blanked in the prompt | 2682-2683 | deleted — dead objects win nearest-pick and eat F | **S** | ★★★ |
| A8 | Downed HUD: "YOU ARE DOWN / bleeding out — N" + camera drops 17% of screen height | 253, 1748, 2925, 3376 | deleted — `downed_changed` is emitted and **never connected** | **S** | ★★★ |
| A9 | Recoil spring + view bob + gun sway + screen shake | 2952-2961, 3116-3119, 1746-1752, 3366 | deleted (`_recoil` written, never read) | **S** | ★★★ |
| A10 | Render-quality selector (3 steps) **+ automatic drop below 38 fps** | 217-221, 293-297, 329-333, 1685-1741, 3331-3338, 3379-3388 | deleted | **S** | ★★★ |
| A11 | Per-zombie idle groans (3.5-9 s), hound barks, distance-culled at 20 m, pitched by palette | 494-500, 2214, 2260-2266 | deleted | **S** | ★★★ |
| A12 | Round title card: big numeral + per-round subtitle, 2.1 s fade | 2867, 3093-3101 | deleted | **S** | ★★ |
| A13 | Points readout: thousands separator, 110 ms scale bump, red on spend, floating `+N` delta | 3000-3013 | deleted (`str(p)`) | **S** | ★★ |
| A14 | Ammo readout: `--` while reloading, `low` ≤25%, `empty` blink, `✦` PaP suffix, `[Q] alt-weapon` line | 3026-3037 | deleted | **S** | ★★ |
| A15 | Round tally pips, 10 max, 10th turns sodium past round 10 | 3015-3025 | deleted | **S** | ★ |
| A16 | Low-HP pulse `0.4 + sin(t*7)*0.22` under 34% health | 39, 3377 | deleted | **S** | ★★ |
| A17 | Damage wash masked by the **inverse** vignette — edges only, centre always clear | 1972-1975 | deleted; port's is a flat full-screen tint | **S** | ★★ |
| A18 | Toast colour classes: sodium / `rad` green / `bad` red | 109-115, call sites 2367/2376/2428/2779/2787 | deleted — one colour | **S** | ★ |
| A19 | Spread ×1.5 while moving, ×1.4 while downed | 2530-2531 | deleted | **S** | ★★ |
| A20 | Metal walls brighten (+26 lit) when the power comes on | 1801 | deleted | **S** | ★ |
| A21 | Night-sky ceilings use a separate dimmer curve capped at 150 so the torch cannot light the sky | 1701, 1868 | deleted — the Alley reads as an indoor room | **S** | ★★ |
| A22 | Perk blurbs shown in the buy prompt ("you can take much more") | 1266-1269, 2718 | deleted — `PERKDEF.blurb` exists in `weapons.gd` and is never read | **S** | ★ |
| A23 | Round ≥14 regular-zombie speed nudge ×1.06 | 2334 | deleted | **S** | ★ |
| A24 | Wall-buy refuses the sale (and says so) when reserve is full | 2706 | deleted — port charges you and refills every gun | **S** | ★★ |

### Tier B — worth a day or three each.

| # | Behaviour | html | Port status | Cost | Value |
|---|---|---|---|---|---|
| B1 | **Positional audio**: `spatial(d) = clamp(1-d/22,0,1)²` + camera-space `panOf()` | 452-456, 2434-2441 | deleted — 12 non-positional `AudioStreamPlayer`s on Master | **M** | ★★★ |
| B2 | **Particle system** + 4 tuned presets + ~10 call sites | 2117-2143, 2130-2133 | deleted — no particle node of any class exists | **M** | ★★★ |
| B3 | **Muzzle flash**: radial gradient + spinning 8-point star + hot core, per-weapon anchor and colour | 2020-2022, 3144-3170 | deleted | **M** | ★★★ |
| B4 | **Chalk wall-buy plaques** — gun silhouette + name + cost, drawn on the wall | 1244-1262, 2105-2106 | deleted — wall buys are invisible until you stand on them | **M** | ★★★ |
| B5 | **Projectiles**: Ray Gun bolt + China Lake grenade, gravity, splash with falloff, self-damage | 2552-2564, 2576-2620, 3419-3428 | deleted — `proj`/`splash`/`splash_dmg` are dead data | **M** | ★★★ |
| B6 | 13 deleted synth voices + 5 degraded (full table in §3) | 399-558 | deleted / degraded | **M** | ★★★ |
| B7 | Pack-a-Punch machine art, off + on states | 1986-2012 | deleted — see §0(b) | **S** | ★★ |
| B8 | Barricade **teardown** loop: zombie works boards at `rnd(1.5,0.9)` s (hound 0.42 s), enters only at 0 | 2268-2282 | deleted — board removed as a side-effect of spawning, zombie teleported inside | **M** | ★★★ |
| B9 | Distance-weighted spawn-window pick, best-of over all live windows | 2196-2201 | replaced with a uniform `randi() % size` | **S** | ★★★ |
| B10 | Ambient tension drone rising with the round | 541-555, 2868 | deleted | **S** | ★★ |
| B11 | Scanline overlay + static CSS vignette on top of the per-pixel one | 32-38 | deleted | **S** | ★ |
| B12 | Screen flash on shot / nuke / explosion / power-on (`G.flash`, a world-space light add) | 2421, 2524, 2577, 2786, 3365 | deleted — port's `_flash` is a damage vignette only | **S** | ★★ |

### Tier C — the expensive ones, still worth costing.

| # | Behaviour | html | Port status | Cost | Value |
|---|---|---|---|---|---|
| C1 | **Viewmodel**: `GUNART` 13-entry part list → `drawParts` → 200×120 canvas, tilt, gloved hands, PaP tint, reload dip, knife arc, swap raise | 1128-1241, 3106-3172 | deleted — **the port has no first-person weapon at all** | **L** | ★★★ |
| C2 | Real shell: title + pause screens with focusable buttons, keybind grid, "Abandon run", onboarding hint | 258-339, 3177-3204, 3327-3337 | one text blob, zero focusable controls, no mouse UI | **M** | ★★ |
| C3 | Game-over screen: accuracy, time survived, epitaph tier, rotating tip | 342-356, 3205-3228 | round/kills/headshots/points only | **S** | ★★ |
| C4 | Drifting title-screen camera behind the menu | 3397-3410 | deleted | **S** | ★ |
| C5 | `prefers-reduced-motion` (CSS half only — see §6) | 223-226 | deleted | **S** | ★★ |

---

## 2. Recipes for every deleted item

The constants are the value here. Grouped to match the tables above.

### A1 — wall face shading
`lit = (lit*186)>>8` on `side===1` only. **186/256 = 0.7266.** In `WorldBuilder._emit_wall_faces`,
multiply the vertex-colour `shade` by `0.727` for the two ±Z faces and leave ±X at `1.0`.
Note the ancestor also applies the per-tile `tileShade` jitter *first* (`lit = (lit*tileShade[ti])>>8`,
1798) — the port already ports that (`map_data.gd:141-142`), so the two multiply cleanly.

### A2 — hitmarker
26×26 px, rotated 45°, four 2×8 bars at the cardinal edges, colour `#EDE7D6`. Animates
`scale(.55) → 1` over **0.22 s ease-out**; the element is cleared and reflowed on every hit so
rapid fire re-triggers it. Kill variant swaps the bars to `--blood-lit #C4222A`. Auto-clears at
230 ms. Critically it fires on **non-kill hits too** (2243) — that is the whole point.

### A3 — hit flinch
`z.hitT = 0.09` on damage (2223), decayed `z.hitT -= dt` (2251). While positive the sprite is
tinted toward `(255, 235, 220)` at alpha `min(210, hitT*640)` — so it starts at ~58/255 alpha
and falls to zero over 90 ms. Insta-Kill adds a permanent `+40` alpha toward `(255, 90, 70)` on
every live zombie (2078), which is how you can see the power-up is active.

### A4 — barricade rebuild
```
if(keys['f'] && curInteract && curInteract.type==='window'){
  repairT += dt;
  if(repairT > 0.34){ repairT = 0; if(w.boards<6){ w.boards++; addPoints(10); Audio2.repair(); } }
} else repairT = 0;
```
**0.34 s per board**, 10 points each, 6 boards → 2.04 s and 60 points for a full window. The `F`
keydown handler explicitly excludes windows (`if(k==='f'){ if(curInteract && curInteract.type!=='window') doInteract(); }`,
3291) so tap-F never fires on a window — hold is the only verb. The prompt shows
`"Rebuild barricade"` plus `"(6 - boards) boards missing"` (3061-3064), and `findInteract`
suppresses the window entirely at 6 boards (2682). Windows are also the one interactable exempt
from the facing test (2687), so you can rebuild while looking away from the wall.
`repair()` sound: square 320→520 Hz over 0.09 s + bandpass-1800 noise 0.1 s.

### A5 — per-zombie attack timer
`atkT: rnd(0.6)` at spawn (2213) — randomised so a wave never lands a synchronised bite.
Cadence on connect: **1.05 s** normal, **0.85 s** hound, **1.1 s** against a downed player.
Damage **34** normal / **36** hound / **24** while downed. Reach 1.15 m, **1.05 m for crawlers**;
the downed branch uses `reachDist*0.92`. Each zombie owns its own timer, so a pile of five deals
five bites. The port's `player.gd:301-303` single 0.35 s global cooldown caps the entire horde at
one zombie's DPS.

### A6 / A7 — interaction states
`interactInfo(it)` returns `{label, cost, ok, none, free, sub, hold}`:
- `ok:false, none:false` → prompt renders in **blood-lit red**, key chip border red; pressing F
  plays `deny()` (square 150→80 Hz, 0.2 s) and `flashPrompt()` (force red for 260 ms).
- `none:true` → text with **no F chip**: `"Juggernog — owned"`, `"Pack-a-Punch — no power"`,
  `"Olympia — ammo full"`, `"Bowie Knife — owned"`, `"Power is on"`.
- `free:true` → no cost badge (generator, box take-out, window rebuild).
- `sub` → the perk blurb.
- `hold:true` → marks the window as a hold interaction.

Cost is rendered separately in sodium with `toLocaleString`. `findInteract` (2675-2691)
`continue`s past windows at 6 boards and doors already open — it removes them from the candidate
set rather than selecting them and then showing nothing, which is the port's bug.

### A8 — downed state
`P.downT = 7`, HUD text `'bleeding out — ' + Math.ceil(P.downT)` refreshed every frame (2925).
The camera drops: `horizon += (P.downed ? H*0.17 : 0)` (1748) — 17% of screen height, i.e. you
are on the floor. Movement speed **1.15 m/s** (2940), spread ×1.4, and zombies switch to the
24-damage 1.1 s cadence. Quick Revive is consumed on the way down and the weapon forcibly
switches to slot 0 (2364). Toast `'QUICK REVIVE — hold on'` in `bad` red; `'BACK ON YOUR FEET'`
in `rad` green on recovery. Port: `downed_changed` is emitted three times in `player.gd` and
`hud.gd:bind()` connects six other signals but not this one.

### A9 — camera feel
```
// recoil, a critically-damped spring
P.viewKickV += -P.viewKick*46*dt - P.viewKickV*11*dt;
P.viewKick  += P.viewKickV*dt;
```
Impulse on fire: `viewKickV += d.kick * (dtap ? 0.94 : 1)` — kick ranges 0.9 (PM63) to 4.2
(Thundergun). Read by the horizon (`- viewKick*H*0.012`, 1748), the viewmodel Y
(`+ viewKick*cssH*0.03`) and viewmodel rotation (`+ viewKick*0.05`).
**This is the fix for the port's aim bug**: `player.gd:197` adds `def.kick*0.0035` straight into
`_cam.rotation.x` with nothing to pull it back, so a 100-round RPK mag walks the camera up
permanently.

Bob: `bobPhase += dt * (sprinting ? 13 : 9.4)` while moving, `dt * 2.2` while idle.
`P.bob = moving ? sin(bobPhase)*(sprinting ? 2.4 : 1.5) : sin(bobPhase)*0.35`. Fed to the horizon
at `bob*H*0.006`. Viewmodel sway is `sin(bobPhase)*cssW*0.005` horizontally and
`abs(cos(bobPhase))*cssH*0.012` vertically — note the **X and Y use different functions**, which
is what makes it read as a figure-eight rather than a wobble.

Shake: `G.shake` decays at `2.2/s`. Sources — `hurt` 0.35, nuke 0.5, explosion 0.55, per-shot
`min(0.4, kick*0.055)`. Applied as `(random-0.5)*shake*7` px on Y **and, on X, as a perturbation
of the camera plane** (`planeX += shakeX*0.0009`, 1752) rather than a translation — so it reads
as a roll/lens wobble, not a pan. In Godot this maps to a dedicated `Node3D` pivot between the
body and the camera writing `rotation.z` and `rotation.x`, leaving `_cam.rotation.x` free for
mouse pitch.

### A10 — render quality
`QUAL = [320, 480, 700]` base widths. `RW = round(clamp(cssW/3, base*0.8, base*1.75))`,
`RH = RW/aspect`, then a hard total-pixel cap: `if(RH*RW > 400000)` re-derive from
`sqrt(400000/aspect)`. Three `.qbtn`s appear on **both** the title and pause screens and stay in
sync. `resize()` is debounced 120 ms.

The automatic governor (3379-3388):
```
frames++; fpsT += dt;
if(fpsT > 1.4){ if(frames/fpsT < 38 && quality > 0){ quality--; resize(); } frames=0; fpsT=0; }
```
Godot equivalent: `get_viewport().scaling_3d_scale` at 0.5 / 0.75 / 1.0 with
`scaling_3d_mode = SCALING_3D_MODE_BILINEAR`, driven by a 1.4 s rolling average of
`Performance.get_monitor(TIME_FPS)`. Given the hard constraint (single-threaded WebGL2, GitHub
Pages, unknown consumer hardware, no telemetry), this is the only mechanism in the ancestor that
made the build survive a bad machine, and it is one of the cheapest items on this list.

### A11 — zombie vocals
`groanT: rnd(6,1)` at spawn, re-rolled to `rnd(9,3.5)` on fire, culled at `d < 20` m.
`groan(dist, pan, pitch)` where `pitch = pal/2` (so the three palettes are three voices):
- sawtooth at `58 + pitch*36` Hz sweeping to `×0.62` over 0.85 s, gain `0.075 × spatial(d)`, decay 0.8
- bandpass noise at `300 + pitch*260` Hz, Q 2.4, 0.8 s, gain `0.09 × spatial(d)`, decay 0.7

`bark(dist, pan)` for hounds: sawtooth 220→110 Hz over 0.16 s at `0.16×`, plus bandpass-900 Q 1.2
noise for 0.16 s at `0.14×`.

### A12 — round title card
`roundFlash(n, sub)` where
`sub = dogRound ? 'the hounds are loose' : (round === 1 ? 'the dead are coming' : '')`.
Numeral at `clamp(72px, 14vw, 190px)` in blood-lit over a radial blood-wash backdrop; subtitle in
mono at `0.5em` letter-spacing. Opacity is snapped to 1 with `transition:none`, reflowed, then
faded to 0 over **2.1 s ease-out**. Fires *with* `Audio2.roundStart()` and
`Audio2.setTension(min(1, round/16))`.

### A13 / A14 / A15 — HUD detail
- Points: `toLocaleString('en-US')`; `scale(1.13)` for 110 ms on any change; `.spend` turns it
  blood-red when the delta is negative; a separate `#gain` line shows `+250` / `-950` in
  `--rad #7FA83C` for 700 ms.
- Ammo: magazine shows `--` while reloading; `.low` (blood-red) at `mag <= def.mag*0.25 && mag > 0`;
  `.empty` blinks `0.55 s steps(2)` at zero; PaP names get a trailing `✦`; the alt-weapon line
  reads `[Q] MP40  17/256`.
- Tally: `min(round, 10)` bars, 4×9 px, `skewX(-14deg)`, blood-coloured with a 6 px glow; past
  round 10 the tenth bar switches to sodium.

### A16 / A17 — screen effects
Low HP: `#lowhp` opacity `= hp/maxHp < 0.34 ? (0.4 + sin(t*7)*0.22) : 0`, rendered as
`inset 0 0 140px 40px rgba(140,8,10,.8)` — an edge-only pulse at ~1.1 Hz.

Damage wash, per pixel, **after** the vignette multiply:
```
k = (dmg * (255 - v)) >> 8;          // v is the vignette value: bright centre, dark edges
r += ((150 - r) * k) >> 8;           // pull red toward 150
g -= (g * k) >> 9;  b -= (b * k) >> 9;   // crush green and blue at half the rate
```
Because `k` scales with `255 - v`, the wash is **strongest exactly where the vignette is
darkest** — the corners — and vanishes at the crosshair. `G.dmgFlash += 120` per hit, capped at
255, decaying at `260/s`. This is the "irregular, edges only, centre clear" behaviour T1.4
proposes to design; it already has a recipe.

Vignette LUT: `d = hypot((x-cx)*1.02, (y-cy)*1.18) / hypot(cx,cy)` — deliberately anisotropic,
18% tighter vertically — then `v = clamp(1.06 - clamp(d,0,1)^2.7 * 0.92, 0, 1)`.
Grain: a 4,096-entry table of `±6` integers, added to all three channels, scrolled by a fresh
random offset each frame so it never reads as a fixed pattern.

### A19-A24 — small mechanical restorations
- Spread: `spreadDeg = d.spread * (moving ? 1.5 : 1) * (downed ? 1.4 : 1)` where
  `moving = hypot(vx,vy) > 0.6`. Hitscan converts with `*0.0175*2`, projectiles with `*0.0175`.
- Power-on lighting: `if(G.power && wid===TX_METAL) lit = min(400, lit + 26)`.
- Night ceiling: `skyLUT[i] = min(150, (0.26 + 0.34/(1+d²*0.2))*256)` — a separate, flatter,
  hard-capped curve used only for `CE_NIGHT` tiles, plus `+9` blue instead of `+5`. The Alley's
  sky therefore never brightens when you walk toward it. Godot: give the `night` ceiling material
  `shading_mode = SHADING_MODE_UNSHADED`.
- Wall-buy full-reserve refusal returns `{ok:false, none:true}` and shows `"Olympia — ammo full"`.

### B1 — positional audio
```
spatial(dist) = clamp(1 - dist/22, 0, 1) ** 2      // quadratic rolloff, hard cut at 22 m
```
`panOf(x,y)` is a **camera-space** pan, not a world-X approximation: it projects into the view
basis with `invDet = 1/(planeX*dirY - dirX*planeY)`, takes `tX/tY`, clamps to ±1, and falls back
to `clamp(tX,-1,1)` behind the camera. Every world sound takes `(dist, pan)` and multiplies its
gain by `spatial(dist)`; several return early at `v <= 0.02`, which is the voice-cull.
In Godot: `AudioStreamPlayer3D` with `max_distance = 22`, `attenuation_model = ATTENUATION_INVERSE_SQUARE_DISTANCE`
gets you most of it for free; the explicit hard cut at 22 m is worth keeping as the cull rule.

### B2 — particles
Spawner (2117-2129): count `n`, hard cap **420 live**, random heading `rnd(TAU)`, speed
`rnd(opt.spd, 0.4)`, vertical `rnd(opt.up, -0.4)`, life `rnd(opt.life, 0.22)`, gravity default
**11 m/s²**. Integrator (2135-2143): floor bounce at `z < 0.04` with `vz *= -0.3` and horizontal
damping `×0.55`. Alpha is `life/max` so everything fades linearly.

| Preset | rgb | spd | up | life | size | grav | glow |
|---|---|---|---|---|---|---|---|
| `BLOOD` | 126,16,18 | 4.2 | 4.0 | 0.72 | 0.10 | 11 | — |
| `SPLINT` | 150,110,56 | 3.4 | 3.6 | 0.80 | 0.085 | 11 | — |
| `SPARK` | 255,196,96 | 5.6 | 3.2 | 0.35 | 0.06 | 13 | yes |
| `EMBER` | 255,120,30 | 2.0 | 2.2 | 0.90 | 0.07 | 3 | yes |

Call sites: body hit **4** BLOOD at z 1.05 · headshot **7** at z 1.58 **plus 7 more** at 1.62 on
the kill · nuke **8** each · Thundergun **16** per victim plus a 24-particle
`(140,220,250)` discharge burst 0.9 m in front of the muzzle · board torn **6** SPLINT at the
window centre, z 1.2 · hound spawn **10** EMBER at z 0.7 · explosion **26** `(255,170,60)` glow +
**14** `(70,64,58)` smoke · Ray Gun trail 1 per frame while `particles.length < 380` · **wall
miss: 3** `(150,146,132)` dust at `spd 1.2, up 1.2, life .35, size .03, grav 4`, spawned 5 cm back
along the ray from the impact point.

### B3 — muzzle flash
Fires while `G.flash > 0.55` and not mid-knife. Anchor from the `MUZZLE` table, in the same
100×60 space the gun art is authored in:
```
m1911 [22,25]  olympia [6,25]  m14 [10,24]  mp40 [8,25]   pm63 [12,26]
ak74u [6,25]   stakeout [4,24] m16 [4,25]   rpk [2,25]    chinalake [6,24]
raygun [16,26] thundergun [14,26]  knife [10,30]
```
Radius `cssH * (0.05 + random()*0.035)`, **×2.2 for the Thundergun**. Colour by weapon:
Ray Gun `160,255,90`, Thundergun `150,235,255`, everything else `255,214,130`.
Composited `lighter` (additive) as a radial gradient with stops at `0 → .95a`, `.35 → .45a`,
`1 → 0`, over an 8-point star alternating radii `r*0.62` / `r*0.20` and spinning at
`(t*7) % TAU`, plus a solid `r*0.22` core in `rgba(255,248,225,.92)`.
`G.flash` itself is **1.35 per shot, 2.2 for the Thundergun, 2.4 on an explosion, 1.2 on
power-on**, decaying at `7/s`, and it additionally brightens the whole world through
`flashLUT[i] = 256/(1 + d²*0.028)` — a real one-frame muzzle light on walls, floor and sprites.

### B4 — chalk plaques
52×40 px. Plate `rgba(12,14,11,.74)`, 1 px `rgba(216,210,192,.38)` border. Gun art drawn through
`drawParts(g, GUNART[key], 0.46, '#E8E3D2')` — the `mono` argument overrides every part colour to
one bone tone, i.e. **the same part list produces both the coloured viewmodel and the chalk
silhouette**. Alpha 0.8, offset `(2,-2)`. Name in 6 px monospace uppercase at
`rgba(216,210,192,.7)`, cost in **bold 10 px sodium `#E0A62B`** below it.
Placed at height 0.72 m, floated `1.30` m off the floor, on all seven wall buys and the Bowie
(2105-2106). The same chalk texture is reused as the **weapon hovering out of the open Mystery
Box** during both the spin and the offer (2099-2103), which is how you can see what you are being
offered from across the room.

### B5 — projectiles
Spawn at `P + dir*0.35`, `z = 1.42`. Ray: `spd 23`, `vz 0`, `grav 0`. Grenade: `spd 16`,
`vz 1.1`, `grav 2.6`. Life 3 s. Detonates on `blocked(tile)`, `z < 0.12`, life expiry, or a
zombie within `z.r + 0.16`. Direct hit applies `pr.dmg` first, **then** the explosion.
```
explode(x,y,radius,dmg):
  flash 2.4, shake 0.55, Audio2.explode(dist,pan)
  26 glow particles + 14 smoke
  for each zombie within radius WITH line of sight:
      damage = dmg * (1 - d/radius*0.55)        // only 45% falloff at the rim
  if player within radius*0.75: hurtPlayer(round(24 * (1 - pd/(radius*0.75))))
```
Ray Gun: splash 1.7 m / 620 dmg. China Lake: 2.6 m / 1,150. Both ×2.2 when Pack-a-Punched.
Note the explosion is **LOS-gated** (`hasLOS`) — it does not go through walls, unlike the port's
`_cone_blast` and `_knife`.

### B7 — Pack-a-Punch art
52×64. Cabinet `#23251F`, top rail `#31342C`, screen recess `#15170F`. When lit, the screen is a
diagonal gradient `#2E6ED8 → #8A3FD8 → #2E6ED8` with a 35%-white top highlight, a `#0C0E09`
letterbox and `"PAP"` in bold 9 px `#8FD0FF`. Output slot `#191B15` with a `#8A3FD8` bar. Whole
cabinet gets a `#7A4FE0` glow overlay at alpha 0.22 and a floor shadow ellipse (17×3) at
`rgba(0,0,0,.32)`. Off state: screen `#2A2C24`, slot bar `#22241E`, no glow.

### B8 — barricade teardown
```
state 'window':
  boardT -= dt
  if(w.boards <= 0){ state='chase'; x=w.ix+0.5; y=w.iy+0.5; }     // vault in
  else if(boardT <= 0){
    boardT = (type==='hound') ? 0.42 : rnd(1.5, 0.9);
    w.boards--; Audio2.board(dist, pan); spawnParticles(w.x+.5, w.y+.5, 1.2, 6, SPLINT);
    atkAnim = 0.3;
  }
  anim += dt*3;    // idle-shuffle animation rate while occupied
  continue;        // no steering, no separation, no attack — it is busy
```
Initial `boardT: rnd(1.2, 0.3)`. A zombie parked at a window is fully shootable and completely
harmless; that asymmetry *is* the tempo of rounds 1-5. Spawn position `w.sx/w.sy` is
**33% of the way from the room-side tile centre toward the wall tile** (1602-1603) — the port
kept the formula (`map_data.gd:197-202`) but applies it at spawn and then immediately teleports
the zombie to chase.

### B9 — spawn window weighting
```
for each live window:
  d  = hypot(w.sx - P.x, w.sy - P.y)
  wt = (1 / (1 + d*0.14)) * rnd(1.6, 0.4)      // random 0.4..1.6 jitter per window per spawn
  keep the highest
```
Best-of over all live windows with a wide random multiplier — so it is *biased* toward you, not
deterministic. At 30 tiles the weight is 0.19× the weight at 0 tiles before jitter. The port's
`live[_rng.randi() % live.size()]` makes late-round pressure *fall* as you open the map.

### B10 / B12 — ambience and flash
Drone: sawtooth **41 Hz** → lowpass 180 Hz → gain ramped to 0.05 with `setTargetAtTime(τ=2 s)`.
Wind layer: the shared noise buffer → bandpass **340 Hz Q 0.6** → gain **0.014**, looped forever.
`setTension(t)` sets `droneGain = 0.04 + t*0.09` with `τ = 0.4 s`; `t = min(1, round/16)`, and it
is reset to 0 on game over and on "Abandon run".

### C1 — viewmodel
Authoring space is **100×60, muzzle at the left, stock at the right**. `drawParts` understands
four primitives: `['r',x,y,w,h,col]`, `['p',[x,y,...],col]`, `['c',cx,cy,r,col]`,
`['rr',x,y,w,h,angle,col]`. Thirteen part lists (12 guns + knife) at 1151-1207; the RPK is 9
parts, the Thundergun 11, the M1911 7 — this is a *compact* format, roughly 60 lines of data
total, and it is the single most portable art asset in the ancestor.

`makeViewmodel(key, tint)`: 200×120 canvas · `translate(6,26)` · rotate **-0.09 rad** about
(96,30) so it does not read as a flat cutout · `drawParts(..., 1.9)`. PaP variant overlays
`rgba(96,64,200,.42)` with `globalCompositeOperation='source-atop'`.
Gloved hands: a per-weapon `grips` table (13 entries, e.g. `m1911:[52,30]`, `thundergun:[54,34]`),
a 30×26 rounded rect (r 5) in `#2E2B26` with a 26×10 (r 4) `#3A362F` highlight at `+2/+4`; a
support hand 58 px further up the barrel for everything except `m1911`, `knife`, `raygun`.

Screen placement (3113-3136): `scale = min(cssH*0.46, cssW*0.30)/120`, anchored at
`x = cssW*0.56`, `y = cssH - h*0.74`, drawn from `(-w*0.38, -h)` after translating to `(x, y+h)` —
so it rotates about its own bottom-left, which is what makes recoil rock the muzzle up rather
than slide the gun.
- **Reload**: `s = sin(progress*π)` → `y += s*cssH*0.30`, `rot += s*0.5`, `x += s*cssW*0.03`. A
  dip-and-tilt, peaking at the halfway point.
- **Knife**: `s = sin((1 - meleeT/mt)*π)` → `x -= s*cssW*0.24`, `y -= s*cssH*0.06`, `rot -= s*0.85`.
  Swipe left and up. Duration 0.55 s, **0.42 s with the Bowie**; the hit test fires at
  0.22 s / 0.16 s in.
- **Swap**: `y += (swapT/0.45) * cssH*0.42` — the gun drops off the bottom of the screen and
  rises back over 0.45 s (0.42 s on a Q swap).
- Base rotation `-0.04 + viewKick*0.05`.

### C3 — game over
Accuracy `shotsHit/shotsFired` (both counters exist in the ancestor; note `shotsHit` is
incremented **once per Thundergun blast**, not per victim, 2546). Time as `m:ss`.
Epitaph tiers: **round ≥15 "Legend" · ≥10 "Veteran" · ≥5 "Overrun" · else "Devoured"**, over the
subtitle "you did not survive the night". Six rotating tips (3216-3223) — one of which is
*"Rebuilding barricades pays 10 points a board"*, which the port does not implement.

---

## 3. Audio — `Audio2` (399-558) vs `scripts/autoload/sfx.gd`

The ancestor's audio module is a complete, tuned synthesis spec: 27 named voices with exact
frequencies, durations, gains, decay constants and filter types. The port implements 14, all
non-positional, several materially degraded. `play()` takes `(id, volume_db, pitch)` — there is
no distance or pan parameter anywhere in its signature.

| Voice | html | Recipe | Port status | Cost |
|---|---|---|---|---|
| `startDrone` | 541-554 | 41 Hz saw → lowpass 180; + wind noise → bandpass 340 Q .6 @ .014 | **deleted** | S |
| `setTension` | 555 | gain `.04 + t*.09`, τ 0.4 s; `t = round/16` (2868) | **deleted** | S |
| `groan(d,pan,pitch)` | 494-497 | saw `58+pitch*36` →×.62 / .85 s; + bandpass `300+pitch*260` Q 2.4 | **deleted** | S |
| `bark(d,pan)` | 498-500 | saw 220→110 / .16 s; + bandpass 900 Q 1.2 | **deleted** | S |
| `board(d,pan)` | 501-503 | bandpass 1500 Q .8 / .2 s; + square 240→90 | **baked, never played** (`sfx.gd:99`) | S |
| `repair` | 504-505 | square 320→520 / .09 s; + bandpass 1800 | **deleted** | S |
| `powerOn` | 513-518 | saw 40→120 over 2.2 s; + lowpass-900 noise 1.6 s; + 3 harmonics at 220/440/660 delayed .5/.6/.7 s | **deleted** — port plays the generic `buy` blip | S |
| `boxOpen` | 527-532 | 12-note music box, triangle, semitones `0 3 7 10 12 10 7 3 0 7 12 15` from 392 Hz, 0.19 s apart | one 0.3 s tone (`sfx.gd:107`) | S |
| `boxTake` | 533 | arpeggio 0/4/7/12 from 330 Hz, 0.07 s apart | **deleted** | S |
| `teddy` | 534 | descending 12/10/7/3/0/−5 from 520 Hz, 0.16 s apart | **deleted** | S |
| `roundStart` | 519-526 | **4 layers**: 320 Hz **and 322 Hz** saws both →~51 Hz over 1.5 s (the 2 Hz beat *is* the lurch), + lowpass-700 noise 1.7 s, + 70→32 Hz sine 1.9 s delayed 0.1 s | one `_tone(120, 1.3, 2.4, .42, 1.6)` (`sfx.gd:104`) | S |
| `down` | 536-538 | saw 160→36 over 2.4 s; + lowpass-340 noise 2 s | **deleted** | S |
| `revive` | 539 | 0/5/9/12/17 from 262 Hz, 0.11 s apart | **deleted** | S |
| `explode` | 490-492 | lowpass-520 noise .7 s; + sine 70→28 | **deleted** | S |
| `setMuffled` | 463-467 | menu open → master lowpass 20 kHz→**420 Hz**, gain .85→.45, τ .05 | **deleted** | S |
| `shot(profile)` | 469-477 | 4 layers, gain scaled by **`body`** so the Thundergun (body 2.0) is genuinely louder than the M1911 (0.7); optional `tail` = lowpass-600 noise, .42 s decay | present, one baked buffer, **flat −4 dB, no tail** (`sfx.gd:124-133`) | S |
| `hit`/`headshot`/`gib` | 483-489 | all `(dist,pan)`-scaled | present, **non-positional** | M |
| `dryFire` | 478 | square 2600 Hz .04 s + square 900 Hz .05 s delayed .02 | present, degraded | S |
| `reloadClick(d)` | 479-480 | square 1700→1100 + highpass-2600 noise; called **twice** — at 0 and at `reload*0.55` | present as two distinct one-shots | S |
| `knife`/`hurt`/`buy`/`deny`/`pickup` | 481, 507-511 | — | present, degraded | S |

**Net: 13 deleted outright, 1 baked but unwired, 5 materially degraded.**

---

## 4. Present and correct — no action

| Behaviour | html | Port |
|---|---|---|
| Map grid, rooms, openings, doors, windows, wall buys, perk spots, box spots | 1502-1569 | `map_data.gd` — 1:1 |
| Per-tile shade hash `((i*2654435761) ^ (i<<7)) >>> 0`, 212+h%44 | 1573-1576 | `map_data.gd:141-142`, baked to vertex colours |
| Reachability flood fill treating windows as passable edges | 1609-1624 | `map_data.gd:207-232` |
| BFS flow field + 8-way downhill step with corner-cut rejection | 2152-2165, 2293-2305 | `flow_field.gd` |
| Boid separation (radius² 0.42 ≈ 0.65 m, weight 0.62) | 2308-2319 | `zombie.gd:163-173` (0.62 / 2.4) |
| LOS beats flow field | 2288 | `zombie.gd:146` — **but ungated by distance; ancestor gated at `dist < 9`** |
| Zombie HP 150, +100 → r9, then ×1.1 | 2178-2182 | `game_state.gd:122-128` |
| Zombie speed `min(1.05 + r*0.155, 3.45)`, jitter `rnd(1.12,0.86)` | 2183, 2203 | `game_state.gd:131-134`, `zombie.gd:65` (0.86-1.14) |
| Zombie count `6 + (r-1)*3.2 + r^1.6*0.28`; dogs `min(30, 5+r*0.85)` | 2186-2190 | `game_state.gd:137-142` |
| Spawn interval `max(0.22, (dog?0.9:1.5) - r*0.045) * rnd(1.25,0.7)`, cap 24 alive | 2879-2881 | `game_state.gd:145-149` |
| Hound ×0.62 HP ×1.55 speed; crawler ×0.8 HP ×0.62 speed, 9% from round 6 | 2205-2211 | `zombie.gd:50-63`, `game_state.gd:153-156` |
| Full weapon table, PaP maths (dmg ×2.6, mag/res ×1.5, reload ×0.88), 12 PaP names | 1458-1491 | `weapons.gd` — 1:1 |
| Perk table, costs, colours, letters | 1265-1270 | `weapons.gd:42-47` |
| Perk effects: Jug 250 HP, Speed ×0.5 reload, DTap ×1.34 rpm ×1.15 dmg, Revive 7 s | 2519-2529, 2625, 2777 | `game_state.gd:29-34` |
| Box state machine: spin 2.9 s → offer 7 s → close 0.6 s; teddy `uses>3 && rnd < .16*(uses-3)` | 2818-2851 | `main.gd:554-583` |
| Power-up pool (7 entries, 2 ammo, 2 points), 26 s life, 1.5 m pickup, blink-out | 2385-2402 | `main.gd:231, 250-269` |
| Nuke 400 pts, Carpenter 200 pts + all windows to 6 | 2420, 2424-2426 | `main.gd:284-294` |
| Health regen: 3.4 s delay, 34% max HP/s | 2973-2976 | `player.gd:158-162` |
| Between-round 50%/window board regrowth | 2888 | `main.gd:171-174` |
| Interact facing test `dot < 0.35`, windows exempt | 2684-2688 | `main.gd` (facing test absent — see A7) |
| Drop counter: cap 4/round, `nextDropAt = 16 + rndi(14)` | 2379-2384 | `main.gd:216-220` — but initial value is **6**, ancestor's is 18 |
| Bowie: 3,000 pts, 1,000 dmg, faster swing | 2711, 2769-2771 | `player.gd:266-267` |
| Zombie/crawler/hound world heights 1.82 / 0.62 / 0.98 m | 2050 | `sprite_lib.gd:21` |
| Wall height 2.8 m, eye 1.55 m | 1683 | `map_data.gd:16-17` |
| All sprite art (3 zombie palettes, crawlers, hound, perks, box, generator, power-ups) | 973-1448 | replayed into `assets/` |
| 1 px dark rim on every sprite (`α ≤ 18` next to `α > 80` → `(6,6,5,205)`) | 955-971 | baked into the exported PNGs |

---

## 5. What the port did better — do not regress these

1. **Hit registration.** The ancestor's `traceShot` (2477-2505) is a 2D cylinder test: it takes
   the along-ray distance `t` and the perpendicular offset, and compares perp against `z.r`
   (0.30 m) — **with no height test whatsoever.** Pitch is ignored entirely, so you can kill a
   0.62 m crawler across the room while aiming at the ceiling. The port's `_hitscan` is a real
   `intersect_ray` against a real capsule with a pierce/exclude list. This is a larger
   improvement than the headshot one and it must not be traded away for "ancestor fidelity".
2. **Headshots.** `isHeadshot` (2465-2475) reconstructs the sprite's projected top edge and asks
   whether the screen centre falls in the top 30% band — a raycaster hack that is wrong whenever
   the player is pitched. `zombie.gd:188-195` does a real world-space height test.
   *(But: the ancestor's headshot multiplier is **×2** and the port's is ×1.5 — that half is a
   degradation, not an improvement.)*
3. **Mystery Box weighting.** `weightedBox()` (2845-2851) is rejection sampling with a 24-try cap
   that **falls back to `mp40`** — so the box has a small systematic MP40 bias and a hard floor.
   `Weapons.roll_box` (`weapons.gd:83-92`) is a correct cumulative-weight pick. Keep the port's.
4. **Strafing.** The ancestor hand-rolls the perpendicular (`fx = dirX*my - dirY*mx`, 2947-2948);
   `player.gd:145` derives it from `transform.basis.x`. The port's own comment records that the
   hand-rolled version inverted A/D. Keep it.
5. **Collision.** The ancestor moves by axis-separated tile point-tests
   (`blocked((nx + sign(tx)*R)|0, y|0)`, 2338-2339), which lets a body clip a corner whenever its
   radius straddles two tiles. The port uses real capsules and `move_and_slide()`.
6. **Mouse capture.** The ancestor needed a capture chip, a `pointerlockerror` path, a
   `releasing` flag to distinguish deliberate release from Esc, an edge-steering fallback and an
   idle-cursor timer (3230-3306, 3369-3374) — ~75 lines. `Input.set_mouse_mode()` replaces all of
   it. Do not port the fallback.
7. **Melee timing.** The ancestor resolves the swing in a wall-clock `setTimeout` (2643-2660),
   which is decoupled from the frame loop and from `Engine.time_scale`. The port resolves it
   synchronously.
8. **The flow field was kept**, not replaced with 24 `NavigationAgent3D` queries. Correct call.
9. **Real geometry** with one surface per texture instead of a software raycaster.
10. **PaP pierce.** `weapons.gd:68` gives Pack-a-Punched rounds `pierce = 2` as explicit data;
    the ancestor buried it in a call-site ternary (`d.pap ? 2 : 1`, 2572).

---

## 6. Ancestor bugs and dead code — do **not** port these

Flagged because a faithful transliteration would import them, and because one of them is
currently on the backlog as a feature to restore.

- **`G.decals` never existed as a feature.** It is declared at 1638 and cleared at 1659 and
  **nothing ever pushes to it** — there is no decal code in the file. The Tier-0 gap analysis
  lists "Bullet-hole decal array | 1638 | deleted" as an ancestor behaviour to restore. It was
  never implemented. If bullet holes are wanted, they are new design, not a restoration, and on
  `gl_compatibility` `Decal` is a no-op anyway.
- **`G.hitFlash`, `G.hitKill`, `G.killFeedT`** (1639) — declared in the state object, never read
  or written anywhere. Vestigial.
- **`reduceMotion`** (394) — the `matchMedia` result is captured into a `const` and **never
  used**. Only the CSS half of the reduced-motion path works (223-226: scanline hidden, animation
  durations collapsed). Restoring "the ancestor's reduced-motion handling" means restoring a CSS
  rule and writing the logic half from scratch.
- **`zombieDamage(z, dmg, head, srcX, srcY, silent)`** (2219) — `srcX` and `srcY` are accepted and
  never referenced. The directional-damage information the T1.4 screen-effect work wants was
  plumbed and then dropped on the floor.
- **Nuke dead branch** (2415-2416): `if(z.state==='window'){ z.state='chase'; } z.state='dying';`
  — the first assignment is unconditionally overwritten on the next line.
- **`G.dropsThisRound`** is read at 2380 before it exists in any reset path; it works only via the
  `(G.dropsThisRound||0)` guard at 2384 and the assignment in `startRound` (2862). Note that
  `resetGame` resets `dropCount`/`nextDropAt` but not `dropTick` — the port inherited exactly this
  omission (`main.gd:165` resets `drop_count`, not `drop_tick`).
- **Thundergun accuracy accounting** (2546): `G.shotsHit++` fires once per blast regardless of how
  many zombies were in the wedge, and `zombieDamage` also increments it per victim (2224) — so a
  Thundergun blast that hits 6 zombies counts 7 hits against 1 shot. End-of-run accuracy can
  exceed 100%.
- **Double reload sound**: `startReload` schedules `reloadClick` at `t=0` *and* at
  `reload*0.55` (2627-2628) — that is intentional and good, but note it is scheduled at reload
  *start* with an absolute delay, so a cancelled reload still plays the second click.

---

## 7. Verification searches (re-runnable)

All negative claims rest on these returning zero matches across `scripts/`:

```
viewmodel | VM | chalk | muzzle | shake | bob | sway            → 0
particle | Particles | splint | ember | spark                   → 0
AudioStreamPlayer3D | groan | bark | drone | tension | muffle    → 0
reduced_motion | scaling_3d | SubViewport                        → 0
```

Single-match (declared, unused) claims:
```
PTS_REBUILD   → game_state.gd:24 only
"board"       → sfx.gd:99 only (the bake; no play site)
proj / splash / splash_dmg  → weapons.gd:10,24,25 only (never read by player.gd)
shells        → weapons.gd:10,16,21 only
downed_changed→ emitted 3× in player.gd; hud.gd:bind() connects 6 signals, not this one
blurb         → weapons.gd:43-46 only
PAPSPOT       → map_data.gd:102, main.gd:341 — no _prop_sprite call, no pap_*.png in assets/props/
```

`assets/props/` contains 18 PNGs: box ×3, gen ×2, perk ×8, powerup ×5. **No PaP, no chalk, no
viewmodel, no projectile sprites** — the export pass that replayed the ancestor's canvas code
stopped at the props and never reached `makeViewmodel`, `makeChalk`, `makePaP`, `SPR.projRay` or
`SPR.projNade`. That is the mechanical explanation for the four largest visual deletions, and it
means restoring them is an **export-script** task before it is a gameplay task.

---

## 8. Coverage

Complete. Every line of `kriegsnacht.html` has been read in this pass or pass 1.
Non-portable by construction and inventoried only for the constants they carry:
the software raycaster (1744-1931), the floor/ceiling row casts (1818-1877), the per-pixel post
loop (1960-1977) — the useful residue of all three is captured in A1, A17 and A21.
