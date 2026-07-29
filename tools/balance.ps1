<#
.SYNOPSIS
  Run the headless balance sim, keep the CSV, and print the comparison.

.DESCRIPTION
  `scripts/dev/balance_sim.gd` answers one question and only one: **did this
  change make a round harder or easier than the same model without it, and by
  how much.** This script is the way it is normally asked, and it exists so the
  CSV lands somewhere durable and the table is readable without a spreadsheet.

  The CSV is the artefact; the table is a convenience. Everything written goes to
  `notes/balance/sim-<stamp>-{rounds,summary,cadence}.csv`, and the whole point
  of keeping it is that the NEXT change can be diffed against it.

  **What the sim can and cannot answer** is in `notes/balance/README.md` and is
  not repeated here, except for the one line that matters at the point of use:
  *the levels are not survivability figures — read the ratios between builds.*
  Both builds are driven from one seed, so the horde is bit-identical between
  them and the difference is caused by the thing that changed.

  **Two things this script does that are not obvious.**

  1. It parses the CSV **by column name**, via `Import-Csv`, and never by
     position and never with a regex anchored on field order. That is not
     fastidiousness — `tools/perf_native.ps1` shipped a grep anchored on
     `PERF: {"event":...` when Godot serialises a Dictionary in INSERTION order,
     so the line really began `{"data":...`, the pattern matched nothing, and the
     harness reported "NO STAGE ROWS. Nothing was measured" while the probe was
     working perfectly. An hour went into diagnosing a working measurement. The
     GDScript side emits every row through one declared field list for the same
     reason; this side reads them back by name so neither end can drift.

  2. It greps `scripts/main.gd` for the `--sim` flag before running. A parse
     error in any script reachable from the main scene makes Godot HANG rather
     than exit, so an unwired flag and a broken script look identical from out
     here — both are a timeout. Checking first turns one of those two into a
     sentence.

.PARAMETER Guns
  Comma-separated weapon keys from scripts/data/weapons.gd. The Thundergun is
  refused by the sim rather than reported: its listed damage is 0 and its kill is
  a cone, which a model with no positions cannot represent.

.PARAMETER Cadence
  `fixed` is the shipping fire-rate code. `legacy` is a model of what the M2 fix
  replaced — an absolute cooldown clamped at zero on a 60 Hz tick, which
  quantised every rate UP to a multiple of 1/60 s. Running both is how the
  question "how much did M2's fire-rate fix change the round curve" is asked.

.EXAMPLE
  pwsh tools/balance.ps1
  pwsh tools/balance.ps1 -Rounds 30 -Guns mp40,ak74u
  pwsh tools/balance.ps1 -Guns mp40 -Cadence fixed -Perks dtap
#>
param(
  [int]$Rounds = 20,
  [string]$Guns = "mp40,ak74u,m16,rpk,pm63,m1911",
  [string]$Cadence = "fixed,legacy",
  [int]$Seed = 20260729,

  # Model knobs. Defaults live in balance_sim.gd; these only exist so a sweep can
  # be driven from here without editing GDScript.
  [double]$Accuracy = -1,
  [double]$Headshot = -1,
  [string]$Perks = "",
  [switch]$Pap,

  [string]$Out = "",

  # Names the output files. Defaults to a timestamp; pass one when the run is
  # going to be referenced from prose, because "sim-20260729-142609" tells a
  # reader nothing and "sim-m2cadence" tells them what the run was for.
  [string]$Stamp = "",

  [string]$Godot = "$env:USERPROFILE\Godot\Godot_v4.7-stable_win64_console.exe",
  [int]$TimeoutSec = 600
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$outDir = if ($Out) { $Out } else { Join-Path $root "notes/balance" }

if (-not (Test-Path $Godot)) { throw "Godot not found at $Godot. Pass -Godot <path>." }
if (-not (Test-Path (Join-Path $root "scripts/dev/balance_sim.gd"))) {
  throw "scripts/dev/balance_sim.gd not found - nothing to run"
}
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }

# notes/balance/.gdignore is load-bearing and must not be tidied away. Godot's
# importer treats EVERY .csv under res:// as a translation file: the first run
# without it generated a .import plus one binary .translation per column — 46
# files from three CSVs — and would have carried them into the export. .gdignore
# takes the directory out of the resource filesystem entirely. FileAccess still
# reads and writes res://notes/balance/ at runtime, because res:// is resolved
# against the project directory rather than against the import database.
if (-not (Test-Path (Join-Path $outDir ".gdignore"))) {
  New-Item -ItemType File -Path (Join-Path $outDir ".gdignore") | Out-Null
  Write-Host "   + .gdignore (stops Godot importing these CSVs as translations)"
}

# See note 2 in the description. An unwired flag and a parse error are both a
# timeout from out here, and only one of them is worth twenty minutes.
$mainGd = Join-Path $root "scripts/main.gd"
if (-not (Select-String -Path $mainGd -Pattern '"--sim"' -Quiet)) {
  Write-Host "!! scripts/main.gd does not read --sim yet, so this run will start the"
  Write-Host "!! game normally and then sit there until the timeout. The wiring is two"
  Write-Host "!! blocks; see the PACKAGE E report or the head of scripts/dev/balance_sim.gd."
}

# $runStamp, not $stamp: `$stamp` and the [string]$Stamp parameter are the same
# variable, for the same case-insensitivity reason as the $gunList note below.
# It is harmless here because both are strings, and it is renamed anyway — a
# reader should not have to work out which of the two collisions is the benign
# one.
$runStamp = if ($Stamp) { $Stamp } else { Get-Date -Format "yyyyMMdd-HHmmss" }
$argv = [System.Collections.Generic.List[string]]::new()
$argv.Add("--headless")
# Quoted, and this is not decoration: Start-Process re-splits ArgumentList on
# spaces and this project lives under "Cod Zombies Rouglike". Unquoted, Godot gets
# a truncated path and answers "Invalid project path specified" on STDOUT rather
# than stderr, so the run looks like a silent no-op and this script reports
# "nothing was simulated". tools/perf_native.ps1 quotes $root for the same reason.
$argv.Add("--path"); $argv.Add("`"$root`"")
$argv.Add("--sim")
$argv.Add("--sim-rounds"); $argv.Add("$Rounds")
$argv.Add("--sim-gun"); $argv.Add($Guns)
$argv.Add("--sim-cadence"); $argv.Add($Cadence)
$argv.Add("--sim-seed"); $argv.Add("$Seed")
$argv.Add("--sim-out"); $argv.Add("`"$outDir`"")
$argv.Add("--sim-stamp"); $argv.Add($runStamp)
if ($Accuracy -ge 0) { $argv.Add("--sim-accuracy"); $argv.Add("$Accuracy") }
if ($Headshot -ge 0) { $argv.Add("--sim-headshot"); $argv.Add("$Headshot") }
if ($Perks) { $argv.Add("--sim-perks"); $argv.Add($Perks) }
if ($Pap) { $argv.Add("--sim-pap") }

Write-Host "== sim: $Guns x $Cadence, $Rounds rounds, seed $Seed =="

# Start-Process rather than the call operator, because the run has to be bounded:
# a parse error anywhere reachable from the main scene makes Godot HANG, and `&`
# has no timeout. That is the same trade tools/perf_native.ps1 makes, and it
# carries the same quoting tax — see the note above.
$stdout = Join-Path $env:TEMP "balance_$runStamp.out"
$stderr = Join-Path $env:TEMP "balance_$runStamp.err"
$p = Start-Process -FilePath $Godot -ArgumentList $argv.ToArray() `
  -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
if (-not $p.WaitForExit($TimeoutSec * 1000)) {
  $p.Kill()
  Write-Host "!! timed out after ${TimeoutSec}s."
  Write-Host "!! A parse error in any script reachable from the main scene makes Godot"
  Write-Host "!! HANG rather than exit, so a timeout is a parse error until the stderr"
  Write-Host "!! below proves otherwise. Parse-gate the files you touched:"
  Write-Host "!!   & `"$Godot`" --headless --path . --check-only --script scripts/dev/balance_sim.gd"
}

Get-Content $stdout -ErrorAction SilentlyContinue | Where-Object {
  $_ -match '^(balance sim|model:|READ THE|delivered RPM|  |wrote |!!|===)'
}
# Both streams. Godot prints "Invalid project path specified" — the failure a
# mis-quoted argument produces — to STDOUT, so a sweep that only reads stderr sees
# a clean run that did nothing.
$errs = @(@(Get-Content $stderr -ErrorAction SilentlyContinue) +
          @(Get-Content $stdout -ErrorAction SilentlyContinue)) |
  Where-Object { $_ -match 'ERROR|SCRIPT ERROR|Parse Error|Compile Error|Invalid project path' }
if ($errs) { Write-Host "`nengine errors:"; $errs | Select-Object -First 12 }

$roundsCsv = Join-Path $outDir "sim-$runStamp-rounds.csv"
$summaryCsv = Join-Path $outDir "sim-$runStamp-summary.csv"
if (-not (Test-Path $roundsCsv)) {
  Write-Host "`n!! no CSV at $roundsCsv - nothing was simulated."
  exit 1
}

# --- the table ---------------------------------------------------------------

# Signed percentage change, with the two zero cases named rather than collapsed.
# A band where NEITHER build let anything reach the player is a real and important
# outcome — it is what rounds 1-5 look like — and printing it as "-100%" would be a
# divide by zero dressed up as the largest effect in the table.
function Get-Pct($a, $b) {
  $aa = [double]$a
  $bb = [double]$b
  if ($aa -eq 0 -and $bb -eq 0) { return "both 0" }
  if ($bb -eq 0) { return ("0 -> {0:0.#}" -f $aa) }
  return ("{0:+0.0;-0.0;0.0}%" -f ((($aa / $bb) - 1) * 100))
}

# Import-Csv keys off the header row, so every lookup below is by column NAME.
# Adding, removing or reordering a column in ROUND_FIELDS cannot silently shift
# what this reads.

# `$gunList`, NOT `$guns`. PowerShell variable names are case-insensitive, so
# `$guns` IS the `[string]$Guns` parameter — and because that parameter carries a
# type constraint, assigning an array to it silently coerces the array back to one
# space-joined string. Every `Where-Object { $_.gun -eq $g }` below then compares
# against "mp40 ak74u" and matches nothing, so both tables print their headers and
# no rows. It fails as an empty table, which reads exactly like "the sim produced
# nothing" — and tools/build.ps1 already carries a comment about the identical
# trap with `$out` vs `$Out`. Second time in this repo.
$rows = @(Import-Csv $roundsCsv)
$summary = @(Import-Csv $summaryCsv)
$cadenceList = @($rows | ForEach-Object { $_.cadence } | Select-Object -Unique)
$gunList = @($rows | ForEach-Object { $_.gun } | Select-Object -Unique)

Write-Host "`n== per round =="
Write-Host ("{0,-9} {1,-7} {2,4} {3,4} {4,6} {5,9} {6,8} {7,8} {8,8} {9,7}" -f `
  "gun", "cadence", "rnd", "n", "hp", "clear_s", "contact", "taken", "hp/s", "cfrac")
foreach ($g in $gunList) {
  foreach ($c in $cadenceList) {
    foreach ($r in ($rows | Where-Object { $_.gun -eq $g -and $_.cadence -eq $c })) {
      Write-Host ("{0,-9} {1,-7} {2,4} {3,4} {4,6} {5,9} {6,8} {7,8} {8,8} {9,7}" -f `
        $r.gun, $r.cadence, $r.round, $r.count, $r.hp_each, $r.time_to_clear_s,
        $r.contact_zsec, $r.damage_taken, $r.hp_per_s, $r.contact_frac)
    }
  }
}

Write-Host "`n== per five-round band =="
Write-Host ("{0,-9} {1,-7} {2,-6} {3,9} {4,10} {5,10} {6,8}" -f `
  "gun", "cadence", "band", "clear_s", "contact", "taken", "points")
# `band` is a string, so a plain Sort-Object on it is lexicographic: "11-15" lands
# before "6-10" and the table reads out of order for any run past twenty rounds.
# Sorted on the band's opening round number instead, with "all" forced last.
$bandOrder = { if ($_.band -eq "all") { [int]::MaxValue } else { [int](($_.band -split "-")[0]) } }
foreach ($s in ($summary | Sort-Object gun, cadence, $bandOrder)) {
  Write-Host ("{0,-9} {1,-7} {2,-6} {3,9} {4,10} {5,10} {6,8}" -f `
    $s.gun, $s.cadence, $s.band, $s.clear_s, $s.contact_zsec, $s.damage_taken, $s.points)
}

# The comparison this whole harness exists for. Only meaningful when both halves
# of a pair were run, so it says nothing rather than half of something.
if ($cadenceList -contains "fixed" -and $cadenceList -contains "legacy") {
  Write-Host "`n== fixed against legacy (negative = the M2 fire-rate fix made it easier) =="
  Write-Host ("{0,-9} {1,-6} {2,10} {3,10} {4,10}" -f `
    "gun", "band", "clear_s", "contact", "taken")
  $bands = @($summary | ForEach-Object { $_.band } | Select-Object -Unique)
  foreach ($g in $gunList) {
    foreach ($b in $bands) {
      $f = $summary | Where-Object { $_.gun -eq $g -and $_.band -eq $b -and $_.cadence -eq "fixed" }
      $l = $summary | Where-Object { $_.gun -eq $g -and $_.band -eq $b -and $_.cadence -eq "legacy" }
      if (-not $f -or -not $l) { continue }
      Write-Host ("{0,-9} {1,-6} {2,10} {3,10} {4,10}" -f $g, $b,
        (Get-Pct $f.clear_s $l.clear_s),
        (Get-Pct $f.contact_zsec $l.contact_zsec),
        (Get-Pct $f.damage_taken $l.damage_taken))
    }
  }
}

Write-Host "`nCSV: $roundsCsv"
Write-Host "     $summaryCsv"
Write-Host "     $(Join-Path $outDir "sim-$runStamp-cadence.csv")"
Write-Host "The CSV is the artefact. Commit it, and diff the next run against it."
