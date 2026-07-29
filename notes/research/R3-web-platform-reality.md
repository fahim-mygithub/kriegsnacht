# R3 — Web export persistence, input and platform reality

**Date:** 2026-07-27 · **Engine target:** Godot 4.7 · **Deploy:** GitHub Pages, `docs/`, `thread_support=false`, `gl_compatibility` effective
**Live build measured:** https://fahim-mygithub.github.io/kriegsnacht/ (headers fetched 2026-07-27 06:02 UTC)

Evidence tiers: **T1** official docs / engine source · **T2** maintainer statements, merged PRs, tracked issues · **T3** reputable secondary or reference implementation · **T4** community anecdote.

---

## Bottom line

1. **`user://` works and needs no flush call from GDScript — but only if you actually close the file.** Godot installs a `FileAccess` close hook that flags an IndexedDB sync, and `OS_Web::main_loop_iterate()` fires `FS.syncfs(false, …)` on the *next frame*. A `FileAccess` held in a member variable never closes, so it never syncs. There is a real lost-write window (≥1 frame + an async IDB transaction), and it widens without bound when the tab is backgrounded, because the browser stops running `main_loop_iterate()` entirely. **T1**
2. **The pause key is broken, and the certain half of the break is provable from spec.** WHATWG HTML explicitly excludes `Esc` from "activation triggering input event", and `requestPointerLock()` requires transient activation. So `hud.gd:188-194`'s "Esc to resume → `Player.set_capture(true)`" **can never re-capture the mouse in any browser, ever.** Separately (very likely, but measure it) the first Escape while locked is swallowed by the user agent, so pausing takes two presses. **Fix: drive pause off pointer-lock loss, not off a key.** **T1 + T3**
3. **`vram_texture_compression/for_mobile=false` currently breaks nothing in this project.** All 56 PNGs import at `compress/mode=0` (Lossless) with `metadata.vram_texture=false` — no VRAM variants exist, so no feature tag selects anything. The gap analysis's T0.2(c) claim is a latent bug, not a live one. It goes live the moment `detect_3d/compress_to=1` (set on every sprite) fires. **Set `detect_3d/compress_to=0` rather than enabling `for_mobile`** — block compression on 64 px nearest-filtered pixel art is worse than useless.
4. **The download is already 10.2 MB, not 39.5 MB, and GitHub Pages is already doing the work.** Measured today: `index.wasm` 39,509,339 → **10,246,865 B gzip** (74 % saved). Brotli is *not* offered. Total wire ≈ 10.6 MB. But `Cache-Control: max-age=600` means a returning visitor re-downloads all of it after ten minutes.
5. **Your stated hard constraint is wrong: threads *can* be enabled on GitHub Pages.** Godot's PWA export option ships a service worker that rewrites every response with `Cross-Origin-Embedder-Policy: require-corp` and `Cross-Origin-Opener-Policy: same-origin`, and the stock HTML template auto-installs it and calls `window.location.reload()` when isolation is missing. Cost: one extra page load on first visit. This is first-party engine machinery, documented and in-tree. **T1** — see Finding P1.
6. **Bonus, cross-cutting, and it invalidates part of the audio backlog:** with threads off, Godot 4.3+ web exports play audio as *samples*, not streams, and **"audio effects aren't yet implemented for samples."** The T2.x plan's `AudioEffectHardLimiter` / `AudioEffectCompressor` bus layout will silently do nothing in the shipped build. **T1**

---

## Findings

### A. Persistence

**A1 — `user://` on web is IDBFS over IndexedDB, mounted at boot with a blocking read-sync.** `GodotFS.init()` mounts `IDBFS` at each persistent path and resolves only after `FS.syncfs(true, …)` completes, so reads are correct from frame 0.
· T1 · https://raw.githubusercontent.com/godotengine/godot/4.7/platform/web/js/libs/library_godot_os.js (`$GodotFS.init`, `$GodotFS.sync`, `godot_js_os_fs_is_persistent`) · corroboration: 2 (docs + source)

**A2 — No explicit flush is required from GDScript. The engine hooks `FileAccess` close.** Verbatim, `platform/web/os_web.cpp` @ 4.7:

```cpp
// initialize() :317
FileAccessUnix::close_notification_func = file_access_close_callback;
DirAccessUnix::remove_notification_func = dir_access_remove_callback;

// :227
void OS_Web::file_access_close_callback(const String &p_file, int p_flags) {
    OS_Web *os = OS_Web::get_singleton();
    if (!(os->is_userfs_persistent() && (p_flags & FileAccess::WRITE))) {
        return; // FS persistence is not working or we are not writing.
    }
    bool is_file_persistent = p_file.begins_with("/userfs");
    ...
    if (is_file_persistent) { os->idb_needs_sync = true; }
}

// :78
bool OS_Web::main_loop_iterate() {
    if (is_userfs_persistent() && idb_needs_sync && !idb_is_syncing) {
        idb_is_syncing = true;
        idb_needs_sync = false;
        godot_js_os_fs_sync(&fs_sync_callback);
    }
    ...
}
```

Three consequences, all load-bearing:
- **The write must reach `close`.** `p_flags & FileAccess::WRITE` on the *close* notification is the only trigger. `store_string()` / `store_var()` alone flag nothing.
- **The sync lands one frame later at the earliest,** then `FS.syncfs(false, cb)` runs an async IndexedDB transaction on top of that. Nothing in the engine awaits it, and there is no GDScript-visible completion signal.
- **`JavaScriptBridge.force_fs_sync()` will not save you.** `OS_Web::force_fs_sync()` (:263) only sets `idb_needs_sync = true`; the actual sync still waits for the next `main_loop_iterate()`. The class reference is explicit that it is "only useful for modules or extensions that can't use `FileAccess`".
· T1 · https://raw.githubusercontent.com/godotengine/godot/4.7/platform/web/os_web.cpp · https://raw.githubusercontent.com/godotengine/godot/4.7/doc/classes/JavaScriptBridge.xml · corroboration: 2 independent (C++ source, class XML)

**A3 — A backgrounded tab stops the main loop, which stops the sync.** Godot docs, Limitations → Background processing: *"The project will be paused by the browser when the tab is no longer the active tab… `_process()` and `_physics_process()` will no longer run until the tab is made active again."* So the classic loss case is not "mid-write tab close", it is **write → user switches tab → user closes tab.** The sync never ran.
· T1 · https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html · corroboration: 2 (docs + the `main_loop_iterate` code path in A2)

**A4 — Persistence fails outright under: blocked cookies/IndexedDB, incognito/private browsing, and third-party-cookie-blocked iframes.** `OS.is_userfs_persistent()` reports it *"but can give false positives in some cases."* GitHub Pages is first-party, same-origin, HTTPS, not iframed — the best case. itch.io embedding would not be.
· T1 · https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html · https://raw.githubusercontent.com/godotengine/godot/4.7/doc/classes/OS.xml · corroboration: 3 (docs, class XML, forum reports)

**A5 — `thread_support=false` is irrelevant to persistence.** IDBFS and `FS.syncfs` are main-thread Emscripten APIs with no `SharedArrayBuffer` dependency. Nothing in `os_web.cpp`, `library_godot_os.js`, or the documented limitation list conditions persistence on threads. The gap analysis's suspicion ("with `thread_support=false`, likely needs an explicit persistence flush") is **not supported** — the flush behaviour is identical either way.
· T1 (negative finding from source inspection) · corroboration: 2 · *Confidence: high, but this is an absence-of-evidence argument; see Coverage gaps.*

**A6 — The alternative is `JavaScriptBridge.eval()` → `localStorage`, and it is genuinely better for small profile data.** `eval(code, use_global_execution_context)` executes a string as JS. `localStorage.setItem` is synchronous by spec — the value is committed before the call returns, so there is no lost-write window and no dependence on `main_loop_iterate()` ever running again. Trade-offs: ~5 MB origin quota, strings only (JSON-encode), same "clear site data" fate as IndexedDB, and no `res://`-style API. `JavaScriptBridge.download_buffer()` exists as a manual-export escape hatch.
· T1 · https://docs.godotengine.org/en/4.7/classes/class_javascriptbridge.html · https://raw.githubusercontent.com/godotengine/godot/4.7/doc/classes/JavaScriptBridge.xml · corroboration: 2

---

### B. The pause key

**B1 — The binding is confirmed present and confirmed routed through `_process`.** `project.godot` binds `pause` to `physical_keycode=4194305` (`KEY_ESCAPE`). `scripts/ui/hud.gd:188-194`:

```gdscript
if Input.is_action_just_pressed("pause"):
    if Game.state == Game.STATE_PLAY:
        Game.set_state(Game.STATE_PAUSE); Player.set_capture(false)
    elif Game.state == Game.STATE_PAUSE:
        Game.set_state(Game.STATE_PLAY);  Player.set_capture(true)
```
and the pause overlay reads *"Esc to resume."* (`hud.gd:262`).
· T1 (project source)

**B2 — DEFINITIVE, spec-hard: `Esc` can never produce the transient activation that `requestPointerLock()` requires.** WHATWG HTML, *activation triggering input event*, verbatim:

> any event whose `isTrusted` attribute is true and whose `type` is one of: `keydown`, **provided the key is neither the Esc key** nor a shortcut key reserved by the user agent; `mousedown`; `pointerdown`, provided the event's `pointerType` is `mouse`; `pointerup`, provided the event's `pointerType` is not `mouse`; `touchend`.

MDN, `Element.requestPointerLock()`, Security: *"**Transient activation** is required when calling `requestPointerLock()`."*

Therefore `Player.set_capture(true)` fired from an Escape press **cannot** re-lock the pointer. This is not browser-dependent and not a bug that will be fixed. **"Esc to resume" is a dead instruction.**
· T1 · https://html.spec.whatwg.org/multipage/interaction.html · https://developer.mozilla.org/en-US/docs/Web/API/Element/requestPointerLock · corroboration: 2 independent

**B3 — Compounding: after a *user-initiated* unlock, re-locking needs a fresh engagement gesture even if activation is available.** MDN, verbatim: *"If calling `requestPointerLock()` immediately after releasing the pointer lock via the default unlock gesture (instead of through an `exitPointerLock()` call), the call will fail, even if a transient activation is available."* Pointer Lock 2.0 rationale: *"This ensures a user can leave a document that constantly attempts to lock the pointer."*
· T1 · https://developer.mozilla.org/en-US/docs/Web/API/Element/requestPointerLock · https://www.w3.org/TR/pointerlock-2/ · corroboration: 2

**B4 — Godot's own docs say capture must originate inside a live input event, which `_process` is not.** Verbatim: *"Browsers do not allow arbitrarily entering full screen. The same goes for capturing the cursor. Instead, these actions have to occur as a response to a JavaScript input event. In Godot, this means entering full screen from within a pressed input event callback such as `_input` or `_unhandled_input`. **Querying the `Input` singleton is not sufficient, the relevant input event must currently be active.**"* `hud.gd` does exactly the prohibited thing — polls `Input.is_action_just_pressed` inside `_process` and then calls `set_mouse_mode`.
· T1 · https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html

**B5 — PROBABLE, not spec-guaranteed: the first Escape keydown while pointer-locked is swallowed by the user agent.** Pointer Lock 2.0 mandates only that *"A default unlock gesture must always be available… The ESC key is the recommended default unlock gesture"* — it is **silent** on event delivery. Three independent supporting sources, none authoritative:
- Chromium mouse-lock design doc: *"ESC to exit mouse lock & full screen / ESC to stop loading / ESC again is handled by the page"* — i.e. the page gets the *third* press, not the first. **T3**, and old.
- Godot proposal #11415 (author's empirical report): *"pressing Esc to open menu in addition to freeing the mouse cursor **instead of having to press esc twice**."* **T4** — but it is a direct observation of exactly this scenario.
- MDN guidance to key off `pointerlockchange` rather than keyboard events. **T1**, indirect.

**Net effect on the shipped build:** press 1 frees the cursor and does nothing to the game (still `STATE_PLAY`, still running, mouselook now dead because `player.gd:93` gates on `MOUSE_MODE_CAPTURED`). Press 2 opens the pause menu. Press 3 closes it but cannot re-lock (B2). The player recovers only by clicking, which `player.gd:104-107` handles — the click both fires the weapon and re-captures.
· corroboration: 3 sources, 0 authoritative → **flagged for measurement**

**B6 — Godot 4.7 reports mouse state truthfully, so polling works as a detector.** `DisplayServerWeb::mouse_get_mode()` queries the browser live (`godot_js_display_cursor_is_hidden()` / `_is_locked()`), it does not return a cached field. The 4.4-era desync (issues #102209, #102445 — "can't recapture after Escape") was fixed by PR #102719. So `Input.mouse_mode` in `_process` is a reliable *"did the user just escape out?"* signal in 4.7. Godot exposes **no signal or notification** for pointer-lock loss; you must poll, or add your own `pointerlockchange` listener via `JavaScriptBridge`.
· T1 (source) + T2 (issues/PR) · https://raw.githubusercontent.com/godotengine/godot/4.7/platform/web/display_server_web.cpp :595-604 · https://github.com/godotengine/godot/issues/102209 · corroboration: 3

**B7 — No engine-level fix is coming.** godot-proposals #11415, "Add Keyboard lock to web export", is **closed as not planned / archived**. The `navigator.keyboard.lock(['Escape'])` API is Chrome 68+ / Edge 79+ only, requires fullscreen, and has required explicit user permission since Chrome 130. Firefox and Safari implement a *different* Fullscreen Keyboard Lock (a `requestFullscreen` option); Safari additionally requires the site to `preventDefault()` the Escape key, Firefox does not. Under Firefox's version, a single Escape does not exit pointer lock — it is tied to a long-press. This is four incompatible behaviours across three engines. **Not worth a solo developer's time.**
· T2 + T1 · https://github.com/godotengine/godot-proposals/issues/11415 · https://developer.chrome.com/blog/better-full-screen-mode · https://bugzilla.mozilla.org/show_bug.cgi?id=2032302 · corroboration: 3

**B8 — The convention for browser FPS games.** Converging on: (a) **pointer-lock loss *is* the pause event** — do not wait for a key; (b) **resume is a click on the canvas**, because a click is the only gesture that reliably re-locks; (c) a **secondary pause key that is not Escape** (`P`, `Tab`, or backquote) for players who want to pause without losing the lock; (d) copy that says *"Click to resume"*, never *"Esc to resume"*. Note the project already carries a scar from this: `toggle_capture` is bound to `L` (`project.godot`), which is exactly the workaround a developer adds after hitting this once.
· T3 (synthesis of MDN's `pointerlockchange` guidance + the Godot issue corpus) · corroboration: 2 · *This is a convention claim, not a measurable fact.*

---

### C. Mobile, textures and gamepad

**C1 — What the flags actually do.** `platform/web/export/export_plugin.cpp` @ 4.7 :348-356:
```cpp
if (p_preset->get("vram_texture_compression/for_desktop")) {
    r_features->push_back("s3tc"); r_features->push_back("bptc");
}
if (p_preset->get("vram_texture_compression/for_mobile")) {
    r_features->push_back("etc2"); r_features->push_back("astc");
}
```
These are *export feature tags* that select which pre-baked variant of a VRAM-compressed texture gets packed. `for_mobile` defaults to `false` (:377).
· T1 · https://raw.githubusercontent.com/godotengine/godot/4.7/platform/web/export/export_plugin.cpp

**C2 — In this project the flag is currently inert.** Every `.import` under `assets/` carries `compress/mode=0` (Lossless) and `metadata={"vram_texture": false}`. No S3TC/BPTC/ETC2/ASTC variant is generated for any of the 56 textures, so no feature tag selects anything and mobile WebGL2 receives ordinary uncompressed textures. **The gap analysis line "desktop-only S3TC/BPTC, which mobile WebGL2 does not provide" is describing a bug that does not currently exist.**
· T1 (measured from the repository's own `.import` files)

**C3 — But it is armed.** Every sprite import also carries `detect_3d/compress_to=1` (= VRAM Compressed). These sprites *are* used in 3D. If the editor's 3D-usage detector ever fires on them, it silently reimports as VRAM Compressed, and from that moment `for_mobile=false` ships desktop-only formats.
· T1 (repository `.import` files + Godot import semantics)

**C4 — Even then it degrades rather than breaks.** PR #101178 (merged 2025-01-08, milestone 4.4) extended web export to S3TC/ETC2/BPTC/ASTC and confirmed that GLES3 and RenderingDevice texture storage already **decompress unsupported formats at runtime**. Cost is a CPU decompress at load and uncompressed VRAM, not black textures. Reviewed and approved by maintainers (Fire, clayjohn).
· T2 · https://github.com/godotengine/godot/pull/101178 · corroboration: 2

**C5 — Turning `for_mobile` on has a hidden prerequisite with a silent failure.** `EditorExportPlatformWeb::has_valid_project_configuration()` (:471-475) sets `valid = false` when `for_mobile` is on and `ResourceImporterTextureSettings::should_import_etc2_astc()` is false — i.e. the project setting `rendering/textures/vram_compression/import_etc2_astc` must also be enabled. It sets `valid = false` **without setting `err`**, so the export button greys out with an empty explanation.
· T1 · export_plugin.cpp :464-481

**C6 — Gamepad: works for the mainstream case, unreliable in general.** Godot's web platform uses the browser Gamepad API. Docs: *"Gamepads will not be detected until one of their buttons is pressed."* Secure context (HTTPS) is required — GitHub Pages qualifies. The Gamepad API deliberately withholds vendor/product identification for privacy, so Godot cannot apply its SDL mapping database; the browser's own remapping is dependable only for official Xbox/PlayStation pads (and mostly on Windows). Known divergences: PlayStation D-pad works in Chromium but not Firefox (#50553); Xbox analog triggers do not register on web export (#81758); Xbox mapping wrong in Firefox (#39253).
· T1 + T2 · https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html · https://github.com/godotengine/godot/issues/50553 · https://github.com/godotengine/godot/issues/81758 · corroboration: 3

**C7 — Touch: the engine support is there; the design is the hard part.** `DisplayServerWeb` emits `InputEventScreenTouch` and `InputEventScreenDrag` from DOM touch events (`display_server_web.cpp` :730-780), and `is_touchscreen_available()` reports capability. Two hard platform limits: `MOUSE_MODE_CONFINED` / `CONFINED_HIDDEN` raise `ERR_FAIL_COND_MSG` — *"not supported for the Web platform"* (:560) — and **Pointer Lock does not exist on mobile browsers at all**, so mouselook must become drag-look. Minimum viable scheme for this game's seven actions: left-half virtual analog stick (move), right-half drag-to-look with auto-fire-on-hold, and a small button cluster for reload / interact / knife / swap. Sprint = stick-deflection threshold. Permissively licensed prior art: MarcoFazioRandom's Virtual-Joystick-Godot (MIT).
· T1 (source) + T3 (addon) · https://raw.githubusercontent.com/godotengine/godot/4.7/platform/web/display_server_web.cpp · https://github.com/MarcoFazioRandom/Virtual-Joystick-Godot · corroboration: 2

**C8 — Textures are not the mobile blocker.** The real barriers are: a 39.5 MB wasm that must be compiled on the main thread on phone silicon; `gl_compatibility` with eight `OmniLight3D`s; no pointer lock; and iOS Safari's wasm memory ceiling. Total asset weight is 664 KB across 56 files — texture format is noise next to the module.
· T1 (measured on disk) + T1 (docs: *"CPU and GPU performance at a premium"*)

---

### D. Loading shell and delivery

**D1 — The shipped page is the stock shell.** `docs/index.html` (5,441 B) contains `$GODOT_CONFIG`-substituted output and a bare `<progress>`; `html/custom_html_shell=""` in both presets.
· T1 (project files)

**D2 — Measured wire cost, live, 2026-07-27.** GitHub Pages **does** gzip `application/wasm`:

| File | On disk | Over the wire (gzip) | Saving |
|---|---:|---:|---:|
| `index.wasm` | 39,509,339 | **10,246,865** | 74.1 % |
| `index.pck` | 291,940 | 261,528 | 10.4 % |
| `index.js` | 279,815 | 69,439 | 75.2 % |
| `index.html` | 5,441 | ~2 K | — |
| **total** | **≈40.1 MB** | **≈10.6 MB** | **73.6 %** |

Brotli is **not** available: a request with `Accept-Encoding: br` alone returns identity/39,509,339 B. Real browsers advertise `gzip` too, so they get 10.2 MB. Also measured: `Cache-Control: max-age=600`, `Vary: Accept-Encoding`, `Content-Type: application/wasm` (correct, so streaming compilation works), served via Fastly.
· T1 (first-party measurement, `curl -sI --compressed`) · reproducible, see §Measurement M4

**D3 — Progress percentage is reliable here, contrary to the docs caveat.** The docs warn *"in some cases `total` can be `0`. This means that it cannot be calculated."* That caveat does not bite for Godot 4.7, because the loader seeds the total from export-baked file sizes, not `Content-Length`. From the project's own shipped `docs/index.js`:

```js
function loadFetch(file, tracker, fileSize, raw) {
    tracker[file] = { total: fileSize || 0, loaded: 0, done: false };
    return fetch(file).then(...)
}
```
and `docs/index.html`'s config carries `"fileSizes":{"index.pck":291940,"index.wasm":39509339}`. `loaded` is accumulated from the decoded `ReadableStream` chunks, so it counts up to the *uncompressed* total consistently even under gzip. **A real percentage bar will work on GitHub Pages.**
· T1 (shipped loader source, read directly)

**D4 — Custom shell API.** Placeholders: `$GODOT_URL` (required), `$GODOT_CONFIG` (required), `$GODOT_PROJECT_NAME`, `$GODOT_HEAD_INCLUDE`, `$GODOT_SPLASH`, `$GODOT_SPLASH_COLOR`, `$GODOT_SPLASH_CLASSES`. API: `new Engine($GODOT_CONFIG)` then `engine.startGame({ onProgress(current,total), onPrint, onPrintError, canvasResizePolicy, unloadAfterInit })`.
· T1 · https://docs.godotengine.org/en/4.7/tutorials/platform/web/customizing_html5_shell.html

**D5 — Cost estimate: half a day, low risk.** Start from `misc/dist/html/full-size.html` in the Godot repo (the template the current page was generated from), copy to `web/shell.html`, point `html/custom_html_shell` at it. Do **not** hand-edit `docs/index.html` — it is regenerated on every export. Keep it single-file (no CDN) so it stays as portable as the rest of the build.
· T1 + T3

**D6 — Audio autoplay forces a click gate anyway, and that click is the one you need.** Docs: browsers restrict autoplay; *"the easiest way around this limitation is to request the player to click, tap or press a key/button to enable audio."* A "CLICK TO PLAY" gate in the shell resolves three things at once: the AudioContext unlock, the transient activation for the initial `requestPointerLock()`, and the place to put the keybind table and the "desktop, mouse + keyboard" notice that T2.7 wants.
· T1 · https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html

---

### P. The platform constraint that turns out to be false

**P1 — Threads are achievable on GitHub Pages via Godot's own PWA service worker.** godot-docs, Exporting for the Web → PWA, verbatim:

> Ensure cross-origin isolation headers are always present, even if the web server hasn't been configured to send them. **This allows exports with threads enabled to work when hosted on any website, even if there is no way for you to control the headers it sends.**
> - This behavior can be disabled by unchecking **Enable Cross Origin Isolation Headers** in the Progressive Web App section.

The mechanism, from `misc/dist/html/service-worker.js` @ 4.7:

```js
function ensureCrossOriginIsolationHeaders(response) {
	if (response.headers.get('Cross-Origin-Embedder-Policy') === 'require-corp'
		&& response.headers.get('Cross-Origin-Opener-Policy') === 'same-origin') { return response; }
	const crossOriginIsolatedHeaders = new Headers(response.headers);
	crossOriginIsolatedHeaders.set('Cross-Origin-Embedder-Policy', 'require-corp');
	crossOriginIsolatedHeaders.set('Cross-Origin-Opener-Policy', 'same-origin');
	return new Response(response.body, { status: response.status, statusText: response.statusText, headers: crossOriginIsolatedHeaders });
}
```

And the bootstrap, already present verbatim in the project's own `docs/index.html` :169-192 — dormant only because `GODOT_CONFIG['serviceWorker']` is unset while PWA is disabled:

```js
if (missing.length !== 0) {
    if (GODOT_CONFIG['serviceWorker'] && GODOT_CONFIG['ensureCrossOriginIsolationHeaders'] && 'serviceWorker' in navigator) {
        ….then(() => engine.installServiceWorker()), … ]).then(() => {
            // Reload if there was no error.
            window.location.reload();
```

So: first visit is not isolated → engine reports SharedArrayBuffer missing → SW installs → page reloads → second load is cross-origin isolated → threads work. **Honest caveats:** costs one extra navigation on first visit; `COEP: require-corp` means every cross-origin subresource must send CORP/CORS headers (fine for a self-contained build, fatal for third-party embeds, ads, or CDN fonts); browsers can evict SW caches; and the threaded wasm template is larger. **Not a recommendation to flip today** — but "threads cannot be turned on, full stop" is not accurate, and the note in `README.md` should be corrected to "cannot be turned on *without a service worker shim*".
· T1 (docs) + T1 (engine source) + T1 (the project's own shipped HTML) · corroboration: 3 independent

**P2 — Threads-off has a documented audio consequence the backlog has not accounted for.** Docs, verbatim:

> Since Godot 4.3, by default Web exports will use samples instead of streams to play audio. This is due to the way browsers prefer to play audio and the lack of processing power available when exporting Web games with the **Use Threads** export option off.
> **Please note that audio effects aren't yet implemented for samples.**

The T2.x audio plan (`default_bus_layout.tres` with `AudioEffectHardLimiter` on Master and sidechained `AudioEffectCompressor` on Music/Ambience) will therefore have **no audible effect in the shipped web build**. `AudioStreamPolyphonic` and `AudioStreamRandomizer` are unaffected; the bus *effects* are the casualty. Enabling thread support (P1) restores Stream playback and effects — which is a much stronger argument for P1 than raw performance.
· T1 · https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html · corroboration: 2 (docs prose + the `AudioDriverWeb`/sample-playback path in `os_web.cpp` initialize)

---

## Recommendations for this project

**R1 — Save pattern (adopt verbatim).** Small profile blob → `localStorage` via `JavaScriptBridge`, with `user://` as the desktop path and a read-side fallback. Rationale against constraints: the payload is a handful of ints (best round, best points, kills, sensitivity, quality tier); `localStorage.setItem` is synchronous so it survives A3's backgrounded-tab hole; and it costs zero build weight.

```gdscript
# scripts/autoload/save.gd  — sketch, not tested
const KEY := "kriegsnacht.profile.v1"
const PATH := "user://profile.json"

func save_profile(d: Dictionary) -> void:
    var json := JSON.stringify(d)
    if OS.has_feature("web"):
        JavaScriptBridge.eval("try{localStorage.setItem(%s,%s)}catch(e){}"
            % [JSON.stringify(KEY), JSON.stringify(json)], true)
        return
    var f := FileAccess.open(PATH, FileAccess.WRITE)
    if f == null: return
    f.store_string(json)
    f.close()            # REQUIRED on web — this is what arms the IDB sync (A2)

func load_profile() -> Dictionary:
    var json := ""
    if OS.has_feature("web"):
        var v = JavaScriptBridge.eval("localStorage.getItem(%s)" % JSON.stringify(KEY), true)
        json = str(v) if v != null else ""
    elif FileAccess.file_exists(PATH):
        json = FileAccess.get_file_as_string(PATH)
    var parsed = JSON.parse_string(json) if json != "" else null
    return parsed if parsed is Dictionary else {}
```
Rules that follow from A2/A3 regardless of backing store: **never hold a `FileAccess` in a member variable**; write on meaningful boundaries (end of round, settings change, death) rather than per-frame; and if you *do* use `user://`, gate on `OS.is_userfs_persistent()` and warn the player once when it is false (incognito). Do not bother implementing a `beforeunload` flush — a backgrounded tab cannot run the sync anyway (A3), so the only real mitigation is writing earlier.

**R2 — Fix the pause key by inverting the trigger. This is the highest-value item in the brief.** Do not try to make Escape work. Make *losing the pointer lock* the pause event, which is correct on every browser and also correct when the player alt-tabs, and put resume on a click.

```gdscript
# hud.gd _process — replaces the current pause block
if Game.state == Game.STATE_PLAY and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
    Game.set_state(Game.STATE_PAUSE)          # user pressed Esc, alt-tabbed, or clicked away
if Input.is_action_just_pressed("pause") and Game.state == Game.STATE_PLAY:
    Game.set_state(Game.STATE_PAUSE)
    Player.set_capture(false)                  # exitPointerLock() — programmatic, so re-lock is cheap
```
and resume from a real input event, never from `_process` (B4):
```gdscript
# player.gd _unhandled_input
if Game.state == Game.STATE_PAUSE and event.is_action_pressed("fire"):
    Game.set_state(Game.STATE_PLAY)
    set_capture(true)                          # inside a live input event → transient activation is present
    get_viewport().set_input_as_handled()      # don't also fire the weapon on the resume click
```
Additional changes, all cheap:
- **Rebind `pause` to a non-Escape key** and keep Escape bound as a *secondary* event. `P` or backquote. Escape then still works after the first press has freed the cursor, and the primary key works while locked.
- **Change the overlay copy** from `"Esc to resume."` to `"Click to resume."` (`hud.gd:262`). It is currently instructing the player to do the one thing that provably cannot work (B2).
- Keep `toggle_capture` on `L` — it is harmless and it is your manual override.
- The gap analysis's separate recommendation to move to real `get_tree().paused` composes with this cleanly; the trigger fix is independent and should not wait for it.
- **Do not** pursue `navigator.keyboard.lock()` (B7).

**R3 — Textures: disarm rather than enable.** Set `detect_3d/compress_to=0` (Disabled) on all 56 sprite imports so the editor can never silently convert 64 px nearest-filtered pixel art to block-compressed garbage. Leave `for_mobile=false`. This is strictly better than enabling `for_mobile` (which would also require the `import_etc2_astc` project setting per C5, and would double the packed size of any VRAM texture for a platform you are not targeting). Then update the gap analysis's T0.2(c) text — it currently asserts a live bug that does not exist (C2).

**R4 — Mobile: confirm desktop-only, and say so on the shell.** The gap analysis's recommendation stands, but for different reasons than it gives (C8, not C2). Do not spend the touch-scheme budget. Put the "desktop, mouse + keyboard" line in the loading shell (R5) where a phone visitor sees it before downloading 10 MB — ideally gate the download behind a `matchMedia('(pointer: coarse)')` check that shows the notice instead.

**R5 — Loading shell: build it, and make it earn three things at once.** Half a day (D5). Copy `misc/dist/html/full-size.html` → `web/shell.html`, set `html/custom_html_shell`. Content: project wordmark, a real percentage bar (D3 — it works), the keybind table the ancestor shipped, the one-paragraph points-economy hint, the fan-project disclaimer, the desktop-only notice, and a **CLICK TO PLAY** button that starts the engine (D6). Keep the fan-project / non-affiliation notice visible on this page, since it is the first thing a stranger sees at a public URL under your own name.

**R6 — Enable the PWA option, for caching, before you think about threads.** `progressive_web_app/enabled=true` alone fixes the measured `max-age=600` re-download (D2) by caching all 10.6 MB in a service worker, and gives you an offline page. Leave `ensure_cross_origin_isolation_headers=true` (the default) — with `thread_support=false` it is inert, and it means the isolation shim is already deployed if you later want to test threads. Then **re-run the R2 fix against the PWA build**, because a stale service worker is the classic "my fix didn't deploy" trap the docs warn about.

**R7 — Correct `README.md` and the gap analysis on the threads claim.** The current wording ("GitHub Pages cannot set custom headers. The single-threaded template boots without them.") is true but incomplete, and it is being carried forward as an unquestioned constraint into every downstream decision — including, per P2, an audio plan that cannot work. Rewrite as: *single-threaded by choice, because the threaded build requires a service-worker COOP/COEP shim that costs an extra first-load navigation and forbids third-party subresources.* Then treat "enable threads" as a live option with a known price, especially if audio bus effects matter.

**R8 — Gamepad: ship it as a bonus, never as the only path.** Wire the existing actions to joypad events, accept that non-Xbox/PS pads will be wrong on some browsers (C6), and put the rebind UI that T2.7 already plans in front of it. Do not put anything essential behind a trigger axis (#81758).

---

## Coverage gaps

- **Whether the first Escape keydown reaches the page while pointer-locked is not settled by any authoritative source.** Pointer Lock 2.0 is explicitly silent (fetched and checked). The supporting evidence is a Chromium design document of unknown vintage and one proposal author's anecdote (B5). I did not reach Chromium's `WebViewImpl` / `PointerLockController` source, a WebKit source, or a Gecko source to confirm suppression at the implementation level. **This does not affect R2**, which is correct either way — but the claim "the pause key is dead" should be stated as "the pause key is double-press and cannot resume", which *is* proven.
- **Behaviour was not verified on Safari or Firefox for anything in section B.** All the pointer-lock reasoning is spec-derived plus Chromium-flavoured. Safari in particular has documented WebGL2 problems on this platform per Godot's own docs, and its Fullscreen Keyboard Lock semantics differ (B7).
- **A5 (threads irrelevant to persistence) is an absence-of-evidence finding.** I read the source and the limitation list and found no thread coupling. I did not find a maintainer stating it affirmatively, and I did not find a bug report either confirming or denying thread-related persistence failure. Treat as high-confidence, not certain.
- **iOS Safari's wasm module size / memory ceiling was not researched.** Relevant to C8 if mobile is ever revisited; the 39.5 MB uncompressed module is the risk, not the textures.
- **I did not verify that `progressive_web_app/enabled=true` + `thread_support=true` actually achieves cross-origin isolation on *GitHub Pages specifically*.** The docs claim it works "on any website" and the mechanism is sound, but GitHub Pages' Fastly layer, its `Vary` handling, and SW scope under a project-page subpath (`/kriegsnacht/`) are untested here. **This must be measured before acting on P1** — see M3.
- **`localStorage` quota under the specific GitHub Pages origin was not measured.** ~5 MB is the widely-cited figure; the profile blob will be under 1 KB, so this is not a practical risk.
- **No fetched page contained text addressed to me**, so there is nothing to quote under the untrusted-content rule.

---

## What must be measured, not researched

**M1 — Does the first Escape reach the game? (30 minutes, resolves B5.)**
Deploy a build with this in an autoload, then open the *live GitHub Pages URL* (not the editor — web behaviour does not reproduce in the editor):
```gdscript
func _input(e):
    if e is InputEventKey and e.keycode == KEY_ESCAPE:
        print("ESC %s locked=%s t=%d" % [
            "down" if e.pressed else "up",
            Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
            Time.get_ticks_msec()])
```
Procedure: click to capture → press Escape once → observe. **Expected if B5 holds:** no print on press 1, cursor appears; print on press 2 with `locked=false`. Repeat in Chrome, Firefox and Safari; repeat in fullscreen and windowed. Record which browsers deliver press 1.

**M2 — Does the save survive a hostile close? (20 minutes, resolves A2/A3 in practice.)**
1. Write the profile, then **immediately** (same frame) `JavaScriptBridge.eval("window.close()")` or kill the tab from the OS. Reload. Is the value there?
2. Write the profile, switch to another tab for 5 s, then close the tab from the tab strip without returning. Reload. Is the value there? **A3 predicts this one loses the write for `user://` and keeps it for `localStorage`.**
3. Repeat both in a private/incognito window and log `OS.is_userfs_persistent()` to see whether it false-positives (A4).
Run each variant three times; a single pass proves nothing about a race.

**M3 — Does the PWA COOP/COEP shim actually isolate on GitHub Pages? (1 hour, gates P1/R6.)**
Export a throwaway branch with `progressive_web_app/enabled=true` and `thread_support=true`, deploy to a `gh-pages` subpath, then on the live URL:
```js
// DevTools console, first load and after the auto-reload
crossOriginIsolated                    // false, then true
typeof SharedArrayBuffer               // "undefined", then "function"
navigator.serviceWorker.getRegistrations()
```
Check the Network tab that `index.wasm` shows the injected `Cross-Origin-Embedder-Policy: require-corp` on the second load. Confirm the scope covers `/kriegsnacht/`. Confirm it survives a hard reload and a new incognito session. Also confirm the *single-threaded* PWA build (R6) still boots — a broken SW is worse than no SW.

**M4 — Wire size and cache behaviour after any export change. (2 minutes, repeatable.)**
```bash
for f in index.wasm index.pck index.js index.html; do
  echo "--- $f"
  curl -sI --compressed "https://fahim-mygithub.github.io/kriegsnacht/$f" \
    | grep -iE 'content-(length|encoding|type)|cache-control'
done
```
Baseline recorded 2026-07-27 in D2. Re-run after enabling PWA to confirm the SW is caching rather than the 600 s `max-age` re-fetching.

**M5 — Whether `detect_3d` has already fired. (1 minute, before R3.)**
```bash
grep -l 'vram_texture": true\|compress/mode=2' assets/**/*.import
```
Empty output today (verified). Re-check after any editor session that opens a 3D scene using these sprites — that is the moment C3 arms.

**M6 — Shader compilation stalls, which is the real single-threaded cost and is not in this brief.**
Nothing in this document measures it. Whoever picks up the rendering workstream should profile first-fire / first-particle / first-light-change frames on the live build, because with threads off every shader compiles on the main thread mid-gameplay.

---

## Source index

| Source | Tier | Used for |
|---|---|---|
| `platform/web/os_web.cpp` @ 4.7 | 1 | A2, A3, A5 |
| `platform/web/js/libs/library_godot_os.js` @ 4.7 | 1 | A1, A2 |
| `platform/web/js/libs/library_godot_display.js` @ 4.7 | 1 | B6 |
| `platform/web/display_server_web.cpp` @ 4.7 | 1 | B6, C7 |
| `platform/web/export/export_plugin.cpp` @ 4.7 | 1 | C1, C5 |
| `misc/dist/html/service-worker.js`, `full-size.html` @ 4.7 | 1 | P1, D5 |
| `doc/classes/JavaScriptBridge.xml`, `OS.xml` @ 4.7 | 1 | A2, A4, A6 |
| https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html | 1 | A3, A4, B4, C6, C8, D6, P1, P2 |
| https://docs.godotengine.org/en/4.7/tutorials/platform/web/customizing_html5_shell.html | 1 | D4 |
| https://html.spec.whatwg.org/multipage/interaction.html | 1 | B2 |
| https://developer.mozilla.org/en-US/docs/Web/API/Element/requestPointerLock | 1 | B2, B3 |
| https://developer.mozilla.org/en-US/docs/Web/API/Pointer_Lock_API | 1 | B6 |
| https://www.w3.org/TR/pointerlock-2/ | 1 | B3, B5 |
| This repository's `docs/index.html`, `docs/index.js`, `*.import`, `export_presets.cfg`, `project.godot` | 1 | B1, C2, C3, D1, D3, P1 |
| Live `curl -sI` against fahim-mygithub.github.io, 2026-07-27 | 1 | D2 |
| https://github.com/godotengine/godot/pull/101178 | 2 | C4 |
| https://github.com/godotengine/godot/issues/102209, /102445 | 2 | B6 |
| https://github.com/godotengine/godot-proposals/issues/11415 | 2 / 4 | B5, B7 |
| https://github.com/godotengine/godot/issues/50553, /81758, /39253 | 2 | C6 |
| https://developer.chrome.com/blog/better-full-screen-mode | 2 | B7 |
| https://bugzilla.mozilla.org/show_bug.cgi?id=2032302 | 2 | B7 |
| https://www.chromium.org/developers/design-documents/mouse-lock/ | 3 | B5 |
| https://github.com/MarcoFazioRandom/Virtual-Joystick-Godot | 3 | C7 |
