<#
.SYNOPSIS
  The rendered-frame regression gate.

.DESCRIPTION
  Renders every scenario in scripts/dev/shot_setup.gd, measures the frame, and
  compares the measurements against the committed golden values in
  notes/perf/frames/golden.json. Exits non-zero on drift.

  WHY THIS IS A SCRIPT AND NOT A GODOT FLAG. Every scenario runs in its OWN
  process. There is no supported way to reset the scene between scenarios inside
  one run: `reload_current_scene()` needs a driver that survives the reload,
  which means an autoload, which means editing project.godot — and a run where
  scenario N inherits scenario N-1's opened doors, thrown generator and downed
  player is exactly the non-determinism this gate exists to detect. A fresh
  process per scenario costs about three seconds each and guarantees isolation.

  THE CAPTURE IS WINDOWED AND THE GATE IS HEADLESS, and neither may be swapped.
  `--frames` awaits `RenderingServer.frame_post_draw`, which under `--headless`
  never returns because there is no rendering device: the process hangs forever
  rather than failing. `--frames-report` renders nothing, reads JSON, and is
  headless. If this machine cannot open a window, this script FAILS — it does
  not skip. A silently skipped visual gate is how two black frames shipped.

.PARAMETER Bless
  Adopt this run's measurements as the new golden values and copy its PNGs to
  notes/perf/frames/ref/. Preserves the tolerance block and the relation rules,
  which are hand-set from a measured spread and must not be regenerated.

.PARAMETER Only
  Capture just these scenarios. The report still evaluates all of them, and the
  ones this run did not capture are reported as failures — deliberately, and see
  Clear-Current below for what it took to make that true.

.PARAMETER Spread
  Capture each scenario N times and print the run-to-run variation instead of
  gating. This is how the tolerance block was set; re-run it after any change to
  the machine, the driver or the resolution.

.EXAMPLE
  pwsh tools/frames.ps1
  pwsh tools/frames.ps1 -Bless
  pwsh tools/frames.ps1 -Spread 5 -Only spawn,horde
#>
param(
  [string]$Godot = "$env:USERPROFILE\Godot\Godot_v4.7-stable_win64_console.exe",
  [switch]$Bless,
  [string[]]$Only = @(),
  [int]$Spread = 0,
  # A capture is ~3.3 s healthy. Sixty seconds is eighteen times that and a
  # fraction of the ~414 s a parse error in a script reachable from the main
  # scene takes to die — the same bound, for the same reason, as build.ps1's
  # --verify gate.
  [int]$TimeoutSec = 60
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$framesDir = Join-Path $root "notes/perf/frames"

if (-not (Test-Path $Godot)) {
  throw "Godot not found at $Godot. Pass -Godot <path>."
}

# Runs Godot with a hard timeout and returns the exit code. `timeout` and
# Ctrl-C kill the SHELL, not Godot: two orphans were once found at 6696 s and
# 3591 s of CPU, pinning two cores under every measurement taken that night.
# Start-Process -PassThru gives a handle that can actually be killed.
function Invoke-Godot {
  param([string[]]$GodotArgs, [string]$What)
  # `--path .` with an explicit -WorkingDirectory, NOT `--path $root`:
  # Start-Process joins -ArgumentList with spaces and does not quote, and this
  # project's path contains one ("Cod Zombies Rouglike").
  $p = Start-Process -FilePath $Godot -ArgumentList $GodotArgs `
    -WorkingDirectory $root -NoNewWindow -PassThru
  if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    $p.Kill(); $p.WaitForExit()
    throw "$What did not finish in ${TimeoutSec}s. A windowed capture that hangs is almost always either --headless slipped into the argument list (no rendering device, so frame_post_draw never returns) or a parse error in a script reachable from the main scene."
  }
  return $p.ExitCode
}

# MEASURED: a windowed capture occasionally dies right after the GL context comes
# up. Two failures in about thirty back-to-back `--frames horde` runs on
# 2026-07-30 (RTX 5090 / 591.86): exit -1, an EMPTY stderr, and nothing on stdout
# past the two engine banner lines — so it died before `_tick_shot` reached the
# shutter, and there is no Godot-side error to act on. Left unhandled it is a
# ~7% chance per capture of failing a release build for a reason that has nothing
# to do with the change under test, which is how a gate acquires the reputation
# that gets it passed over with -SkipFrames.
#
# The retry is bounded to NEGATIVE exit codes ONLY. `--frames` chooses 0 (fine),
# 1 (the scenario's probe subject was not in the scene), 2 (unknown scenario) and
# 3 (the scenario's arrival predicate never became true, or `dt` stopped
# advancing); a negative code is the OS reporting a process that stopped existing,
# never a verdict the game reached. So a real capture failure is never retried and
# never masked, and every retry says so out loud.
function Invoke-Capture {
  param([string[]]$GodotArgs, [string]$What, [int]$Retries = 2)
  for ($attempt = 0; ; $attempt++) {
    $rc = Invoke-Godot $GodotArgs $What
    if ($rc -ge 0 -or $attempt -ge $Retries) { return $rc }
    Write-Host ("   !! $What died with exit $rc before it rendered - retrying ({0}/{1})" -f ($attempt + 1), $Retries)
  }
}

# The scenario list comes from the registry itself. A runner with its own copy
# is a runner that silently stops covering a scenario the day one is added.
$listFile = Join-Path ([System.IO.Path]::GetTempPath()) "kn-frames-list.txt"
$lp = Start-Process -FilePath $Godot `
  -ArgumentList @("--headless", "--path", ".", "--frames-list") `
  -WorkingDirectory $root -NoNewWindow -PassThru -RedirectStandardOutput $listFile
if (-not $lp.WaitForExit($TimeoutSec * 1000)) { $lp.Kill(); throw "--frames-list hung" }
if ($lp.ExitCode -ne 0) { throw "--frames-list failed (exit $($lp.ExitCode))" }
$names = Get-Content $listFile | Where-Object { $_ -match '^[a-z0-9_]+$' }
Remove-Item -Force $listFile -ErrorAction SilentlyContinue
if (-not $names) { throw "--frames-list returned no scenarios" }

# @(...) IS LOAD-BEARING. Without it a single-element -Only collapses to a bare
# string, `$capture[0]` indexes a CHARACTER out of it, and the bless below wrote
# `"resolution": [0, 0]` into golden.json from a member lookup on "a". Caught by
# checks/frame.gd's golden-file audit on the very next --verify, which is the
# whole point of that audit existing.
# `pwsh tools/frames.ps1 -Only spawn,horde` -- the form the README and CLAUDE.md
# both document -- arrives as ONE string, because a native-command invocation
# stringifies its arguments and `-File` does not re-parse them into an array.
# Unsplit, $Only.Count is 1, the arity check below sees 2 captures against 1 name
# and throws "unknown scenario in -Only: spawn,horde (known: ...spawn...horde...)"
# with both names visibly present in its own error message.
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
$capture = @(if ($Only.Count -gt 0) { $names | Where-Object { $Only -contains $_ } } else { $names })
if ($Only.Count -gt 0 -and $capture.Count -ne $Only.Count) {
  throw "unknown scenario in -Only: $($Only -join ',') (known: $($names -join ','))"
}

# EVERY CAPTURE THE REPORT READS MUST BE FROM THIS RUN. Without this the gate is
# a check that passes by skipping, and it was: `pwsh tools/frames.ps1 -Only spawn`
# captured one scenario, the report loaded seven JSON files left behind by an
# earlier pass, and it printed
#
#     === 8 scenarios, 0 failure(s) ===
#     == frame gate passed ==
#
# for seven frames that were never rendered. The same hole swallows a capture
# that exits 0 without writing its row -- `frame_stats.record()` push_errors and
# returns when it cannot open the file -- and it makes the documented -Only
# behaviour ("the ones it did not capture are reported as failures") false.
#
# `report()` already treats an absent row as a failure rather than a skip, so
# emptying the directory is the whole fix: what is not captured this run cannot
# be read this run.
$currentDir = Join-Path $framesDir "current"
New-Item -ItemType Directory -Force $currentDir | Out-Null
Get-ChildItem -Path $currentDir -Include *.json, *.png -File -Recurse |
Remove-Item -Force -ErrorAction Stop

# --- the spread measurement --------------------------------------------------
# Not a gate. This is where the tolerance block in golden.json came from, and it
# is here rather than in a notebook so the number can be re-derived on any
# machine the gate is expected to run on.
if ($Spread -gt 0) {
  Write-Host "== run-to-run spread, $Spread captures per scenario =="
  $rows = @()
  foreach ($n in $capture) {
    $samples = @()
    for ($i = 0; $i -lt $Spread; $i++) {
      $rc = Invoke-Capture @("--path", ".", "--fixed-fps", "60", "--frames", $n) "capture '$n'"
      if ($rc -ne 0) { throw "capture '$n' failed (exit $rc)" }
      $j = Get-Content (Join-Path $framesDir "current/$n.json") -Raw | ConvertFrom-Json
      $samples += , $j
    }
    foreach ($k in @("mean", "median", "black", "blown")) {
      $vals = $samples | ForEach-Object { [double]$_.$k }
      $mn = ($vals | Measure-Object -Minimum).Minimum
      $mx = ($vals | Measure-Object -Maximum).Maximum
      $av = ($vals | Measure-Object -Average).Average
      $rel = if ($av -ne 0) { ($mx - $mn) / [math]::Abs($av) } else { 0 }
      $rows += [pscustomobject]@{
        scenario = $n; stat = $k; min = $mn; max = $mx
        span = $mx - $mn; rel = $rel
      }
    }
    # Every region cell and every probe, collapsed to the worst of them: the
    # tolerance has to cover the noisiest number in the file, not the average.
    $worstRegion = 0.0; $worstProbe = 0.0
    for ($c = 0; $c -lt $samples[0].regions.Count; $c++) {
      $vals = $samples | ForEach-Object { [double]$_.regions[$c] }
      $mn = ($vals | Measure-Object -Minimum).Minimum
      $mx = ($vals | Measure-Object -Maximum).Maximum
      $av = ($vals | Measure-Object -Average).Average
      if ($av -ne 0) { $worstRegion = [math]::Max($worstRegion, ($mx - $mn) / $av) }
    }
    foreach ($pk in $samples[0].probes.PSObject.Properties.Name) {
      $vals = $samples | ForEach-Object { [double]$_.probes.$pk }
      $mn = ($vals | Measure-Object -Minimum).Minimum
      $mx = ($vals | Measure-Object -Maximum).Maximum
      $av = ($vals | Measure-Object -Average).Average
      if ($av -ne 0) { $worstProbe = [math]::Max($worstProbe, ($mx - $mn) / [math]::Abs($av)) }
    }
    $rows += [pscustomobject]@{ scenario = $n; stat = "region(worst)"; min = 0; max = 0; span = 0; rel = $worstRegion }
    $rows += [pscustomobject]@{ scenario = $n; stat = "probe(worst)"; min = 0; max = 0; span = 0; rel = $worstProbe }
  }
  $rows | Format-Table -AutoSize @{n = "scenario"; e = { $_.scenario } }, `
  @{n = "stat"; e = { $_.stat } }, `
  @{n = "min"; e = { "{0:g6}" -f $_.min } }, `
  @{n = "max"; e = { "{0:g6}" -f $_.max } }, `
  @{n = "span"; e = { "{0:g4}" -f $_.span } }, `
  @{n = "rel"; e = { "{0:p4}" -f $_.rel } }
  $worst = ($rows | Measure-Object -Property rel -Maximum).Maximum
  Write-Host ("== worst relative spread across every statistic: {0:p6} ==" -f $worst)
  exit 0
}

# --- the capture pass --------------------------------------------------------
Write-Host "== capturing $($capture.Count) scenario(s), windowed =="
foreach ($n in $capture) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  # --fixed-fps 60 pins the frame delta, so a scenario's settle budget is an
  # exact number of seconds of game time rather than however fast this machine
  # happened to be. The seed is pinned inside shot_setup.apply().
  $rc = Invoke-Capture @("--path", ".", "--fixed-fps", "60", "--frames", $n) "capture '$n'"
  $sw.Stop()
  if ($rc -ne 0) {
    throw "capture '$n' failed (exit $rc). 1 = the scenario's probe subject was not in the scene; 2 = unknown scenario; 3 = the scenario never arrived in the state its name claims, so the shutter refused rather than photographing the wrong one. See the [shot]/[frames] error above."
  }
  Write-Host ("   {0,-12} {1,5:n1}s" -f $n, $sw.Elapsed.TotalSeconds)
}

# --- bless -------------------------------------------------------------------
if ($Bless) {
  $goldenPath = Join-Path $framesDir "golden.json"
  if (-not (Test-Path $goldenPath)) { throw "no golden.json to update - create the skeleton (tolerance + relations) first" }
  # -Depth matters: the default of 2 silently truncates the nested scenario rows
  # to the string "System.Object[]", which reloads as a string and then compares
  # unequal against every golden value forever.
  $g = Get-Content $goldenPath -Raw | ConvertFrom-Json -Depth 20
  foreach ($n in $capture) {
    $j = Get-Content (Join-Path $framesDir "current/$n.json") -Raw | ConvertFrom-Json -Depth 20
    $g.scenarios | Add-Member -NotePropertyName $n -NotePropertyValue $j -Force
    Copy-Item -Force (Join-Path $framesDir "current/$n.png") (Join-Path $framesDir "ref/$n.png")
  }
  $first = $capture[0]
  $w = [int]$g.scenarios.$first.w
  $h = [int]$g.scenarios.$first.h
  if ($w -le 0 -or $h -le 0) { throw "blessed row '$first' has no resolution ($w x $h) - refusing to write a golden file the gate cannot use" }
  $g.resolution = @($w, $h)
  $g.captured = (Get-Date -Format "yyyy-MM-dd")
  $g | ConvertTo-Json -Depth 20 | Set-Content -Path $goldenPath
  Write-Host "== blessed $($capture.Count) scenario(s) into notes/perf/frames/golden.json =="
}

# --- the gate ----------------------------------------------------------------
$rc = Invoke-Godot @("--headless", "--path", ".", "--frames-report") "--frames-report"
if ($rc -ne 0) {
  Write-Host "== FRAME GATE FAILED ($rc drift(s)) =="
  exit $rc
}
Write-Host "== frame gate passed =="
exit 0
