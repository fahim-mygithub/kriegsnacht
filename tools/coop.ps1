<#
.SYNOPSIS
  The two-process co-op gate.

.DESCRIPTION
  Launches two real game clients against the live Supabase project, has them meet
  in one room, play a run together, and then asserts on what each of them saw.

  WHY THIS IS NOT AN ASSERTION IN `--verify`. session_runtime.gd, replication.gd
  and remote_player.gd are the three files that carry a co-op run, and none of
  them can be true or false inside one process: what they do is move state across
  a wire into a second copy of the game. A single-process test can only stand a
  fake channel between the two halves and assert that the codec round trips
  through it — a copy of the thing under test, which is exactly the failure
  CLAUDE.md names ("a test that does not call what the game calls"). The suite's
  blindness here is measured, not suspected: an adversarial pass sabotaged seven
  constants across all three files and `--verify` still printed 676 passed.

  HEADLESS IS CORRECT HERE. The `--shot`/`--frames` prohibition is about awaiting
  `RenderingServer.frame_post_draw` with no rendering device; nothing in the co-op
  probe waits on a frame, and the net layer was proven headless against this same
  service already (notes/net/2026-07-31-realtime-probe.md).

  IT SPENDS REAL EVENTS. Two clients for the probe's 45 s budget is roughly 60
  events/second against a free tier that allows two million a month — about
  1/10000th of the quota per run. Run it on a change to the net package; do not
  put it in a loop.

  WHAT IT ASSERTS, and each line is a distinct wire path in a distinct direction:
    both processes reported          the room, the code and the join all worked
    seeds agree                      both machines built the same world
    each saw exactly one peer        presence resolved on both ends
    each peer was POSED              a `me` crossed and was applied (not just a
                                     roster entry — the avatar is built hidden and
                                     only a delivered pose reveals it)
    each peer MOVED                  successive `me`s were interpolated
    client built puppets             the host's `snap`/`spawn` reached it
    host applied claims              the client's `dmg` reached the host
    client's puppets died            the host's `kill` came back
    rounds agree                     the two simulations did not diverge
  The last four are the ones nothing in the repo could check before this existed.

.PARAMETER Godot
  The binary. Same default as tools/frames.ps1.

.PARAMETER TimeoutSec
  Outer bound per process. The probe's own budget is 45 s and its join deadline
  is 75 s, so this only fires when a process is wedged rather than slow.

.PARAMETER KeepLogs
  Leave the two stdout captures on disk instead of deleting them on success.

.EXAMPLE
  pwsh tools/coop.ps1
  pwsh tools/coop.ps1 -KeepLogs
#>
param(
  [string]$Godot = "$env:USERPROFILE\Godot\Godot_v4.7-stable_win64_console.exe",
  [int]$TimeoutSec = 150,
  [switch]$KeepLogs
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path ([IO.Path]::GetTempPath()) "kriegsnacht-coop"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$hostLog = Join-Path $logDir "host.log"
$joinLog = Join-Path $logDir "join.log"
foreach ($f in @($hostLog, $joinLog)) { if (Test-Path $f) { Remove-Item $f -Force } }

if (-not (Test-Path $Godot)) { Write-Error "Godot not found at $Godot"; exit 2 }

# Both processes are killed in the finally block below whatever happens. A killed
# shell leaves Godot running (CLAUDE.md: "timeout kills the shell, not Godot"), and
# an orphan holding a Realtime channel keeps burning the room's event budget — two
# such orphans were once found at 6696 s and 3591 s of CPU.
$procs = @()

function Stop-All {
  foreach ($p in $procs) {
    if ($null -ne $p -and -not $p.HasExited) {
      try { $p.Kill($true) } catch { }
    }
  }
}

function Start-Client([string[]]$ClientArgs, [string]$Log) {
  # The project path is quoted by hand. Start-Process joins an -ArgumentList array
  # with plain spaces and quotes nothing, so a repo under "...\Pojects\Cod Zombies
  # Rouglike" reached Godot as `--path C:\...\Pojects\Cod` and it aborted with
  # "Invalid project path". Found by running this; the failure is silent-looking
  # because the child dies before it prints a single COOP line.
  $all = @("--headless", "--path", "`"$root`"", "--coop") + $ClientArgs
  return Start-Process -FilePath $Godot -ArgumentList $all -PassThru `
    -RedirectStandardOutput $Log -RedirectStandardError "$Log.err" -WindowStyle Hidden
}

# Reads the COOP lines out of a log that is still being written. Opened
# shared-read because the child process holds the handle for writing.
function Get-CoopLines([string]$Log) {
  if (-not (Test-Path $Log)) { return @() }
  try {
    $fs = [IO.File]::Open($Log, 'Open', 'Read', 'ReadWrite')
    $sr = New-Object IO.StreamReader($fs)
    $text = $sr.ReadToEnd()
    $sr.Close(); $fs.Close()
  } catch { return @() }
  return $text -split "`r?`n" | Where-Object { $_ -like "COOP *" }
}

function Wait-ForLine([string]$Log, [string]$Prefix, [int]$Seconds, $Proc) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    foreach ($line in (Get-CoopLines $Log)) {
      if ($line -like "COOP $Prefix*") { return $line }
      # An ERROR from either end is terminal: waiting out the rest of the timeout
      # after the process has already said why it failed just wastes the operator's
      # time and buries the reason under a generic timeout message.
      if ($line -like "COOP ERROR*") { throw "peer reported: $line" }
    }
    if ($null -ne $Proc -and $Proc.HasExited) { throw "the process exited before '$Prefix' (code $($Proc.ExitCode))" }
    Start-Sleep -Milliseconds 250
  }
  throw "timed out after ${Seconds}s waiting for '$Prefix' in $Log"
}

$failures = @()
function Check([string]$Name, [bool]$Ok, [string]$Detail) {
  $mark = if ($Ok) { "ok  " } else { "FAIL" }
  Write-Host ("  [{0}] {1}{2}" -f $mark, $Name.PadRight(46), $Detail)
  if (-not $Ok) { $script:failures += $Name }
}

try {
  # An em dash, not a colon, and deliberately. `co-op gate:` is the prefix of the
  # three OUTCOME lines (all checks passed / N failure(s) / the thrown message), and
  # coop-controls.ps1 reads those to classify a control run. With a colon here the
  # banner matched first and reported a perfectly good control as "aborted".
  Write-Host "co-op gate — two clients, one room, the live relay"

  $hostProc = Start-Client @("host") $hostLog
  $procs += $hostProc
  $codeLine = Wait-ForLine $hostLog "CODE" 60 $hostProc
  $code = ($codeLine -split "\s+")[2]
  Write-Host "  room $code"

  $joinProc = Start-Client @("join", $code) $joinLog
  $procs += $joinProc

  # The probe reports and then quits itself; this is only the wedge bound.
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    if ($hostProc.HasExited -and $joinProc.HasExited) { break }
    Start-Sleep -Milliseconds 500
  }

  $hostLines = Get-CoopLines $hostLog
  $joinLines = Get-CoopLines $joinLog

  function Get-Result($Lines, [string]$Who) {
    $line = $Lines | Where-Object { $_ -like "COOP RESULT *" } | Select-Object -First 1
    if (-not $line) {
      $err = $Lines | Where-Object { $_ -like "COOP ERROR*" } | Select-Object -First 1
      if ($err) { throw "$Who never finished - $err" }
      throw "$Who never reported a RESULT (see $logDir)"
    }
    return ($line.Substring("COOP RESULT ".Length) | ConvertFrom-Json)
  }

  $h = Get-Result $hostLines "host"
  $j = Get-Result $joinLines "client"

  Write-Host ""
  Write-Host "  host  : $($hostLines | Where-Object { $_ -like 'COOP RESULT *' })"
  Write-Host "  client: $($joinLines | Where-Object { $_ -like 'COOP RESULT *' })"
  Write-Host ""

  # --- the assertions ---------------------------------------------------------
  # Bounded at BOTH ends wherever a bound exists. CLAUDE.md: a check that only
  # asserts the refusal passes equally well against a subsystem that has stopped
  # working, so where a count must be non-zero it also has a ceiling that a
  # runaway would breach.

  # FIRST, because it invalidates everything below it. A client that died stops
  # driving `_session.tick` entirely (main.gd returns before it on any state but
  # STATE_PLAY), so its counters flatline and the failure presents as a network
  # fault. Two runs were mis-read as a replication bug before this check existed.
  Check "both clients were still in the run at the end" `
    ($h.playing -and $j.playing) "host=$($h.playing) client=$($j.playing)"

  Check "both clients agree on the seed" `
    ($h.seed -eq $j.seed -and $h.seed -ge 0) "host=$($h.seed) client=$($j.seed)"

  Check "each client sees exactly one peer" `
    ($h.avatars -eq 1 -and $j.avatars -eq 1) "host=$($h.avatars) client=$($j.avatars)"

  # The sharp one. An avatar is built hidden and revealed only once `_drive` has a
  # delivered pose to write into it, so this fails if presence works and `me` does
  # not — which a roster count cannot tell apart.
  Check "each peer was posed from a delivered 'me'" `
    ($h.avatars_posed -eq 1 -and $j.avatars_posed -eq 1) "host=$($h.avatars_posed) client=$($j.avatars_posed)"

  # Travel, not just presence. 2 m is well above interpolation jitter and well
  # below what a bot walking for 45 s covers, and the ceiling catches a peer being
  # teleported around by a decode bug rather than moved.
  Check "the host's avatar moved on the client" `
    ($j.peer_max_m -gt 2.0 -and $j.peer_path_m -lt 4000) "max=$($j.peer_max_m)m path=$($j.peer_path_m)m"
  Check "the client's avatar moved on the host" `
    ($h.peer_max_m -gt 2.0 -and $h.peer_path_m -lt 4000) "max=$($h.peer_max_m)m path=$($h.peer_path_m)m"

  # HOST -> CLIENT: the horde.
  Check "the host's horde reached the client as puppets" `
    ($j.puppets_spawned -ge 4) "spawned=$($j.puppets_spawned) peak=$($j.puppets_peak)"

  # CLIENT -> HOST: damage. This is the path that was dead in both directions
  # until three reported hunks landed, and nothing in the repo could see it.
  Check "the client's damage claims reached the host" `
    ($h.claims_applied -ge 1) "applied=$($h.claims_applied) client_shots=$($j.shots)"

  # HOST -> CLIENT: the confirmation coming back.
  Check "the host's kills came back and killed the copies" `
    ($j.puppet_deaths -ge 1) "deaths=$($j.puppet_deaths)"

  # AGREEMENT ALONE WOULD BE DECORATION. Both machines call `begin_run()` and both
  # would sit on round 1 for the whole budget, so "they agree" passes against a
  # client that never received a `world` message at all. The host forces round 3 at
  # t=30 s (coop_probe.gd::ROUND_AT), which makes the client's number reachable only
  # through `_apply_round` — so this now fails when the round path is cut, and the
  # control run below proves it does.
  Check "the client learned the host's forced round" `
    ($h.round -eq 3 -and $j.round -eq 3) "host=$($h.round) client=$($j.round) (forced 3)"

  # Not a pass/fail: the send budget shedding frames is a tuning signal, and
  # silently dropping it would hide the very thing SEND_BUDGET exists to bound.
  Write-Host ""
  Write-Host "  dropped sends: host=$($h.dropped_sends) client=$($j.dropped_sends)"
  if ($j.rescued) {
    Write-Host "  NOTE: the client was teleported into contact (see RESCUE_AT). The"
    Write-Host "        damage assertions still ran against the real wire, but the bot"
    Write-Host "        could not walk there on its own."
  }

  Write-Host ""
  if ($failures.Count -gt 0) {
    Write-Host "co-op gate: $($failures.Count) failure(s)" -ForegroundColor Red
    Write-Host "logs: $logDir"
    exit 1
  }
  Write-Host "co-op gate: all checks passed" -ForegroundColor Green
  if (-not $KeepLogs) { Remove-Item $logDir -Recurse -Force -ErrorAction SilentlyContinue }
  exit 0
}
catch {
  Write-Host ""
  Write-Host "co-op gate: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "logs: $logDir"
  exit 1
}
finally {
  Stop-All
}
