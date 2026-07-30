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
    # Bounded, because the failure this gate is most likely to meet is not a failed
    # assertion. A parse error in ANY script reachable from the main scene makes
    # main.gd fail to compile, and Godot then spends minutes dying while printing a
    # single "could not preload" line and no assertion output at all. Measured:
    # 414 s to exit against a healthy run's 5 s.
    #
    # It does exit non-zero, so the gate was never actually unsafe — but unbounded
    # it is indistinguishable from a hang, and the reflex is to kill it and guess.
    # Sixty seconds is twelve times a healthy run and a fraction of a broken one.
    $verifyTimeoutSec = 60
    # `--path .` with an explicit -WorkingDirectory, NOT `--path $root`.
    # Start-Process joins -ArgumentList with spaces and does not quote, and this
    # project's own path contains one ("Cod Zombies Rouglike"), so passing $root
    # here splits it into two arguments and Godot exits 1 on a path that does not
    # exist — which reads exactly like a failed assertion run.
    $v = Start-Process -FilePath $Godot `
      -ArgumentList @("--headless", "--path", ".", "--verify") `
      -WorkingDirectory $root -NoNewWindow -PassThru
    if (-not $v.WaitForExit($verifyTimeoutSec * 1000)) {
      $v.Kill(); $v.WaitForExit()
      throw @"
verification did not finish in ${verifyTimeoutSec}s (a healthy run takes about 5).
That is almost always a PARSE ERROR in a script reachable from the main scene
rather than a slow test. Find it with:

  & `$Godot --headless --path . --check-only --script scripts/<file>.gd

Ignore "Identifier not found: Game / Sfx / Rng / Settings" from that command --
it does not register autoloads. Only parse-stage errors are real, and note it
stops at the FIRST error, so everything below that line is unchecked.
"@
    }
    if ($v.ExitCode -ne 0) { throw "verification failed (exit $($v.ExitCode)) - not building" }
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
