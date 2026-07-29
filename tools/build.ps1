<#
.SYNOPSIS
  One-command reproducible web build.

.DESCRIPTION
  Exporting used to mean hand-editing project.godot to strip the Godot MCP
  plugin's three autoloads, running the export, then remembering to put them
  back. Miss the first step and MCPScreenshot / MCPInputService /
  MCPGameInspector ship to the browser and try to open localhost WebSockets for
  every visitor; miss the last and the editor stops working. The committed
  config therefore never matched what shipped.

  This script does the whole thing, restores the file even if the export fails,
  and gates on the headless assertion suite so a broken build cannot be
  published by accident.

.PARAMETER Preset
  Export preset name. "Web" ships to docs/; "WebPerf" adds the benchmark probe.

.PARAMETER SkipVerify
  Skip the assertion gate. For local iteration only — never for a release.

.PARAMETER Perf
  Build the benchmark harness instead of the game: selects the WebPerf preset,
  targets build/perf/, and registers scripts/perf_probe.gd as an autoload for
  the duration of the export. The probe is NOT referenced by any shipped code —
  registering it here is what keeps that true, because the shipped build never
  gets the autoload line.

.EXAMPLE
  pwsh tools/build.ps1
  pwsh tools/build.ps1 -Perf
  python tools/perf_collector.py build/perf
#>
param(
  [string]$Preset = "Web",
  [string]$Out = "docs/index.html",
  [string]$Godot = "$env:USERPROFILE\Godot\Godot_v4.7-stable_win64_console.exe",
  [switch]$SkipVerify,
  [switch]$Perf
)

if ($Perf) {
  if (-not $PSBoundParameters.ContainsKey('Preset')) { $Preset = "WebPerf" }
  if (-not $PSBoundParameters.ContainsKey('Out')) { $Out = "build/perf/index.html" }
}

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root

$proj = Join-Path $root "project.godot"
$backup = Join-Path $root "project.godot.buildbak"

if (-not (Test-Path $Godot)) {
  throw "Godot not found at $Godot. Pass -Godot <path>."
}

function Restore-Project {
  if (Test-Path $backup) {
    Move-Item -Force $backup $proj
    Write-Host "restored project.godot"
  }
}

try {
  if (-not $SkipVerify) {
    Write-Host "== verifying =="
    & $Godot --headless --path $root --verify
    if ($LASTEXITCODE -ne 0) { throw "verification failed (exit $LASTEXITCODE) - not building" }
  }

  Write-Host "== preparing project.godot =="
  Copy-Item $proj $backup
  $lines = Get-Content $proj
  # Drop the editor-only plugin: its autoloads would otherwise ship, and the
  # [editor_plugins] entry makes a fresh clone warn about a missing addon.
  $kept = $lines | Where-Object {
    $_ -notmatch '^MCPScreenshot=' -and
    $_ -notmatch '^MCPInputService=' -and
    $_ -notmatch '^MCPGameInspector=' -and
    $_ -notmatch '^enabled=PackedStringArray\("res://addons/godot_mcp/plugin\.cfg"\)'
  }
  if ($Perf) {
    # Append to the [autoload] block rather than the end of the file: an
    # autoload line under [rendering] is silently ignored, which reads as "the
    # probe never started" and is a miserable hour to diagnose.
    # Not $out: PowerShell variable names are case-insensitive, so $out and the
    # $Out export-path parameter are the same variable, and the accumulator
    # silently overwrote the export target.
    $injected = [System.Collections.Generic.List[string]]::new()
    $added = $false
    foreach ($line in $kept) {
      $injected.Add($line)
      if (-not $added -and $line -match '^Sfx=') {
        $injected.Add('PerfProbe="*res://scripts/perf_probe.gd"')
        $added = $true
      }
    }
    if (-not $added) { throw "could not find the Sfx autoload line to anchor PerfProbe after" }
    $kept = $injected
    Write-Host "   + PerfProbe autoload (perf build only)"
  }
  Set-Content -Path $proj -Value $kept

  $outDir = Split-Path -Parent (Join-Path $root $Out)
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }

  Write-Host "== exporting '$Preset' -> $Out =="
  & $Godot --headless --path $root --export-release $Preset $Out
  if ($LASTEXITCODE -ne 0) { throw "export failed (exit $LASTEXITCODE)" }
}
finally {
  Restore-Project
  Pop-Location
}

$wasm = Join-Path $root (Join-Path (Split-Path -Parent $Out) "index.wasm")
if (Test-Path $wasm) {
  $mb = [math]::Round((Get-Item $wasm).Length / 1MB, 1)
  Write-Host "== done. index.wasm $mb MB uncompressed =="
} else {
  Write-Host "== done =="
}
