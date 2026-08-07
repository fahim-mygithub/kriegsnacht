# Working on Kriegsnacht with someone else

`CLAUDE.md` is the law: the constraints, the testing standard, the CLI footguns.
Read it before your first change and do not skim §"Hard constraints". This file is
the smaller thing — how to get a clone running, and how two people share one repo
without stepping on each other.

---

## First run, and why it is not just "clone and go"

**A fresh clone does not work.** This is measured, not cautionary: a clone of this
repo, run straight from `--verify`, produced no result at all in five minutes and
had to be killed. Two separate causes, and you will hit both.

### 1. `addons/godot_mcp/` is missing, and `project.godot` insists on it

`project.godot` is tracked and declares three autoloads plus an editor plugin
pointing into `res://addons/godot_mcp/`:

```
MCPScreenshot="*res://addons/godot_mcp/mcp_screenshot_service.gd"
MCPInputService="*res://addons/godot_mcp/mcp_input_service.gd"
MCPGameInspector="*res://addons/godot_mcp/mcp_game_inspector_service.gd"
```

`addons/` is gitignored — Godot MCP Pro is a paid product and is not
redistributable — so those four lines reference files no clone contains. What you
see is:

```
ERROR: Failed to instantiate an autoload, can't load from path:
       res://addons/godot_mcp/mcp_screenshot_service.gd.
```

**Fix: install your own Godot MCP Pro copy** into `addons/godot_mcp/` (and put the
server anywhere; `.mcp.json.example` assumes `./godot-mcp-pro-v1.15.1/`). Both
paths are gitignored, so your copy never enters the repo and never appears in a
diff.

If you ever need to run *without* it, delete the four lines — but do not commit
that. `.github/workflows/verify.yml` does exactly this on the runner, which has no
licence, and `tools/build.ps1` does it locally before an export and restores
`project.godot` afterwards even if the export fails.

### 2. `.godot/` does not exist, so no `class_name` resolves

`.godot/` is gitignored, and it holds the global script class cache. Without it
every `class_name` in the project — `MapData`, `WorldBuilder`, `Player`,
`FlowField`, `Zombie` — is an unknown identifier, which is a parse error in
`main.gd`, which by CLAUDE.md rule 3 **hangs Godot for ~414 s** instead of failing.
That is the five minutes.

```
SCRIPT ERROR: Parse Error: Could not find type "MapData" in the current scope.
ERROR: Failed to load script "res://scripts/main.gd" with error "Parse error".
```

**Fix: run the import pass once.**

### The recipe, verified end to end

```powershell
git clone https://github.com/fahim-mygithub/kriegsnacht.git
cd kriegsnacht

# 1. drop your Godot MCP Pro copy into addons/godot_mcp/   (see above)
# 2. build the class cache -- once, and after any new class_name
& "$env:USERPROFILE\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --import

# 3. the suite
& "$env:USERPROFILE\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --verify
```

MEASURED on a clean clone: import **9 s**, verify **8 s**, `=== 819 passed, 0 failed ===`.
If you get that line, you are set up correctly. Anything else, stop and read the
error rather than re-running.

---

## Prerequisites

| Thing | Version | Notes |
|---|---|---|
| Godot | **4.7-stable** | `tools/build.ps1` defaults to `%USERPROFILE%\Godot\Godot_v4.7-stable_win64_console.exe`. Elsewhere, pass `-Godot <path>`. CI pins the same version. |
| PowerShell | **7+** (`pwsh`) | Every gate in `tools/` is PowerShell. Not Windows PowerShell 5. |
| Node | any recent | Only for the Godot MCP Pro server and `tools/gen/`. |
| Godot MCP Pro | your own licence | Paid, gitignored, required to open the project. See above. |

Do not open the project in the Godot **editor** to make a change. An editor pass
rewrites `project.godot`, strips every comment (32 → 7, once) and silently drops
the explicit `rendering_method.web` pin. Edit the file as text.

---

## MCP setup

```powershell
Copy-Item .mcp.json.example .mcp.json
```

`.mcp.json` is gitignored on purpose — it points at a paid product wherever *you*
installed it. If your server lives outside the project, replace the relative path
with an absolute one.

`.claude/settings.json` is committed and shared: it pre-approves the read-only git
and `gh` calls and the gate scripts, so neither of us spends the day clicking
"allow". Personal overrides go in `.claude/settings.local.json`, which is
gitignored — put machine-specific paths and your own permission tweaks there, not
in the shared file.

---

## How work lands

Both of us have push access. Nothing goes straight to `main`.

```
git switch -c <short-topic-name>
# ... work, with gates green ...
git push -u origin <short-topic-name>
gh pr create
```

CI runs `--verify` on every PR and blocks the merge if it fails. It is ~20 s
end to end.

**CI cannot run the frame gate.** A GitHub runner has no rendering device, and the
capture half of `tools/frames.ps1` awaits `RenderingServer.frame_post_draw`, which
under `--headless` never returns — it would hang, not fail. So if your change can
reach a pixel, run `pwsh tools/frames.ps1` locally and say so in the PR. CLAUDE.md
is blunt about the cost of skipping this: two milestones shipped a near-black frame
that every assertion passed.

### `docs/` — the one that will bite first

`docs/` is the committed web build GitHub Pages serves. It contains `index.wasm`
and `index.pck`: **binary, unmergeable**. If we both run `tools/build.ps1` on
branches, every merge is a hand-resolved binary conflict.

**Rule: feature branches never commit `docs/`.** Rebuild it on `main` only, and
only when actually publishing. If `git status` shows `docs/` dirty on a branch,
that is a mistake — `git restore docs/` before you commit.

### `ASSERTION_FLOOR` and `verify.gd`

`verify.gd:417` holds `ASSERTION_FLOOR`, currently **818** against 819 real
assertions. Two branches both raising it will conflict. Raise it **additively** by
what your branch adds; reconcile to the true total when the branches meet. Same for
`verify.gd`'s registration lines — if you need one changed and it is not your
branch's file, report the exact hunk instead of editing across.

### Line endings

`.gitattributes` normalises everything to LF. It was added before the second clone
existed, because without it each checkout's byte content depended on the cloner's
`core.autocrlf` — and one machine had already split its own working copy into 186
LF and 180 CRLF files, `.gd` sources included. If you cloned before it landed:

```powershell
git add --renormalize .
```

Expect no diff. The index was already LF throughout; the file only makes checkout
deterministic.
