<#
.SYNOPSIS
  Make a fresh clone or a new git worktree actually runnable.

.DESCRIPTION
  WHY THIS EXISTS. Neither a clone nor a worktree of this repository works out of
  the box, and both fail the same way: they hang rather than error.

  `project.godot` is TRACKED and declares three autoloads plus an editor plugin
  pointing into `res://addons/godot_mcp/`. That directory is GITIGNORED, because
  Godot MCP Pro is a paid product and is not redistributable. So every clone and
  every worktree references four files it does not contain. Godot reports three
  `Failed to instantiate an autoload` errors, which cascade: `.godot/` is
  gitignored too, so the global script class cache does not exist, so every
  `class_name` in the project -- MapData, WorldBuilder, Player, FlowField,
  Zombie -- is an unknown identifier, which is a parse error in main.gd, which by
  CLAUDE.md rule 3 hangs for ~414 s instead of exiting.

  MEASURED on a clean clone before this script existed: five minutes, no output,
  killed. After: import 9 s, verify 8 s, 819 passed / 0 failed.

  WHY A COPY AND NOT A JUNCTION, which is the expensive half of this comment.
  The first version of this script junctioned addons/godot_mcp into each worktree.
  It worked, and then `git worktree remove --force` FOLLOWED THE JUNCTION AND
  DELETED THE TARGET: 79 files of a licensed, non-redistributable product erased
  from the reference checkout, which is not in git and therefore not recoverable
  from it. Recovery needed an unrelated copy of the v1.15.1 distribution that
  happened to still be on the disk. A junction saves 79 files of duplication and
  risks the install; the copy is ~1 MB per worktree and risks nothing. If you
  reintroduce a link here, `git worktree remove` becomes a destructive command.

  WHY THE SERVER IS NOT COPIED OR LINKED AT ALL. `.mcp.json` is generated with an
  ABSOLUTE path to the reference install, so the worktree needs no server of its
  own and there is nothing there for a remove to follow.

  WHY `.godot/` IS NOT SHARED. It is per-directory import state, not a cache you
  can point elsewhere. Each tree imports its own, which is the 9 s.

.PARAMETER Reference
  A checkout that already HAS addons/godot_mcp -- normally your main clone.
  Defaults to the main worktree from `git worktree list`, which is right for a
  worktree and wrong for a first clone: there is nothing to copy from yet, so
  install Godot MCP Pro by hand once and re-run.

.PARAMETER Godot
  Same default as tools/build.ps1, deliberately: one path to be wrong about.

.PARAMETER SkipVerify
  Skip the closing suite run. That run is the only thing that proves setup
  worked, so skipping it is an admission rather than a shortcut.

.EXAMPLE
  pwsh tools/setup-env.ps1
  pwsh tools/setup-env.ps1 -Reference "C:\Users\me\Desktop\kriegsnacht"
#>
param(
  [string]$Reference,
  [string]$Godot = "$env:USERPROFILE\Godot\Godot_v4.7-stable_win64_console.exe",
  [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $root
Write-Host "== target: $root =="

if (-not $Reference) {
  $first = (& git worktree list) | Select-Object -First 1
  if ($first -match '^(.*?)\s+[0-9a-f]{7,}\s') { $Reference = $Matches[1].Trim() }
}
if (-not $Reference) { throw "No -Reference given and ``git worktree list`` told us nothing." }
$Reference = (Resolve-Path $Reference).Path

$srcAddon = Join-Path $Reference "addons/godot_mcp"
if (-not (Test-Path $srcAddon)) {
  throw @"
Reference checkout has no addons/godot_mcp:
  $srcAddon

This is the paid Godot MCP Pro plugin and nothing can install it for you.
Put your licensed copy there first, then re-run. See CONTRIBUTING.md.
"@
}

# --- addons/godot_mcp ---------------------------------------------------------
$dstAddon = Join-Path $root "addons/godot_mcp"
if ($srcAddon -eq $dstAddon) {
  Write-Host "addons/godot_mcp: this IS the reference checkout, left alone"
} elseif (Test-Path $dstAddon) {
  Write-Host "addons/godot_mcp: already present, left alone"
} else {
  New-Item -ItemType Directory -Force -Path $dstAddon | Out-Null
  Copy-Item -Path (Join-Path $srcAddon "*") -Destination $dstAddon -Recurse -Force
  $n = (Get-ChildItem $dstAddon -Recurse -File -Force | Measure-Object).Count
  Write-Host "addons/godot_mcp: copied $n files from $srcAddon"
}

# Guard the invariant the hard way, because the failure mode is silent until a
# `git worktree remove` eats the licensed install.
$link = Get-Item $dstAddon -Force -ErrorAction SilentlyContinue
if ($link -and ($link.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
  throw "addons/godot_mcp is a link, not a directory. `git worktree remove` would delete its target. Replace it with a real copy."
}

# --- .mcp.json ----------------------------------------------------------------
# Absolute path to the reference server: nothing to copy, nothing to follow.
$srcServer = Get-ChildItem -Path $Reference -Directory -Filter "godot-mcp-pro-v*" -ErrorAction SilentlyContinue | Select-Object -First 1
$mcp = Join-Path $root ".mcp.json"
if (Test-Path $mcp) {
  Write-Host ".mcp.json: already present, left alone"
} elseif ($srcServer) {
  $entry = (Join-Path $srcServer.FullName "server/build/index.js") -replace '\\', '/'
  @{ mcpServers = @{ "godot-mcp-pro" = @{ command = "node"; args = @($entry) } } } |
    ConvertTo-Json -Depth 5 | Set-Content -Path $mcp -Encoding UTF8
  Write-Host ".mcp.json: written, server -> $entry"
} else {
  Write-Warning "No godot-mcp-pro-v* directory in the reference; .mcp.json not written and MCP tools will not connect."
}

# --- the vendor's own tool documentation --------------------------------------
# addons/godot_mcp/skills.md documents every MCP tool and the vendor tells you to
# copy it into the project. NOT committed: this repo is public and that file
# ships with a paid product, so each machine generates it from its own licensed
# install. .gitignore excludes the destination.
$srcSkill = Join-Path $dstAddon "skills.md"
$dstSkillDir = Join-Path $root ".claude/skills/godot-mcp-pro"
$dstSkill = Join-Path $dstSkillDir "SKILL.md"
if ((Test-Path $srcSkill) -and -not (Test-Path $dstSkill)) {
  New-Item -ItemType Directory -Force -Path $dstSkillDir | Out-Null
  # Claude Code needs frontmatter to index a skill; the vendor file has none.
  $fm = @"
---
name: godot-mcp-pro
description: Use when driving the Godot editor through the godot-mcp-pro MCP tools - creating or editing scenes and nodes, attaching scripts, inspecting a running game, simulating input, or capturing editor and game screenshots. Covers the full tool set and the editor-vs-runtime split that decides which of them can work at all.
---

<!-- Copied from addons/godot_mcp/skills.md by tools/setup-env.ps1. Vendor
     documentation for a paid product: NOT committed, regenerated per machine
     from that machine's own licensed install. Edit the source, not this. -->

"@
  Set-Content -Path $dstSkill -Value ($fm + (Get-Content $srcSkill -Raw)) -Encoding UTF8
  Write-Host ".claude/skills/godot-mcp-pro/SKILL.md: written from your licensed copy"
}

# --- the import pass ----------------------------------------------------------
# Not a warm-up. Without it no class_name resolves and the suite cannot run.
if (-not (Test-Path $Godot)) { throw "Godot not found at $Godot. Pass -Godot <path>." }
Write-Host "== importing (builds .godot/ class cache) =="
& $Godot --headless --path $root --import
if ($LASTEXITCODE -ne 0) { throw "Import failed with $LASTEXITCODE." }

# --- proof --------------------------------------------------------------------
if ($SkipVerify) {
  Write-Warning "Suite skipped. Nothing has demonstrated that this tree works."
  return
}
Write-Host "== assertion suite =="
& $Godot --headless --path $root --verify
if ($LASTEXITCODE -ne 0) { throw "Suite failed with $LASTEXITCODE. Setup is NOT good." }
Write-Host ""
Write-Host "Ready. ONE Godot editor at a time across all worktrees -- see CONTRIBUTING.md." -ForegroundColor Green
