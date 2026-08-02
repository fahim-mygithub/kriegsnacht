<#
.SYNOPSIS
  The controls for tools/coop.ps1. Breaks one wire path at a time and proves the
  named check fails.

.DESCRIPTION
  CLAUDE.md: "Every assertion ships with a control. Break the thing the assertion
  is named for, run the suite, confirm THAT SPECIFIC CHECK fails, restore. If it
  does not fail, it is decoration." This is that, for the co-op gate — and it is
  a script rather than a discipline because the co-op gate's assertions are the
  ones most likely to rot: they are the only ones in the repo that can be
  satisfied by two processes agreeing on nothing.

  It matters more here than anywhere else in the project. The whole reason the
  co-op gate exists is that `--verify` stayed green while seven constants across
  session_runtime.gd, replication.gd and remote_player.gd were sabotaged. A gate
  built to catch that which cannot itself be shown to catch it is worth nothing.

  RESTORE IS IN A `finally` AND IT IS LOAD-BEARING. A sabotage left in a file
  reachable from the main scene does not fail — it HANGS Godot, for ~414 s, for
  everyone, and that has happened on this project for seven minutes. Every
  sabotage is applied to a byte-for-byte backup that is restored whatever happens,
  including Ctrl-C.

  EACH CONTROL COSTS A FULL GATE RUN (~70 s and ~4000 Supabase events). The whole
  sweep is around ten minutes. Run it when the gate's assertions change, not
  routinely.

.PARAMETER Only
  Run just these controls by name.

.PARAMETER DryRun
  Resolve every anchor and print where it lands, without sabotaging anything or
  running the gate. A control whose anchor has drifted is a control that silently
  stops controlling, and finding that out costs a ten-minute sweep otherwise.

.EXAMPLE
  pwsh tools/coop-controls.ps1 -DryRun
  pwsh tools/coop-controls.ps1
  pwsh tools/coop-controls.ps1 -Only me-inert,kill-inert
#>
param(
  [string[]]$Only = @(),
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

# Each control: the file, an exact substring to replace, its replacement, and the
# check that MUST go from pass to fail. `Expect` is matched as a substring of the
# gate's own check name, so renaming a check breaks the control loudly instead of
# leaving it matching nothing.
#
# The sabotages are all of one shape — turn a guard into `if true:` so the function
# returns before doing its work. That keeps them syntactically valid (a parse error
# here would hang Godot rather than fail the gate) and keeps the diff one token.
$controls = @(
  @{
    Name = "seed-ignored"
    File = "scripts/net/session.gd"
    From = '			var s := int(payload.get("seed", 0))'
    To   = '			var s := 12345'
    Expect = "agree on the seed"
    Why  = "the client builds its world from its own number instead of the host's"
  },
  @{
    Name = "me-inert"
    File = "scripts/net/session_runtime.gd"
    From = '	if not bool(m.get("ok", false)):'
    To   = '	if true:'
    Expect = "posed from a delivered 'me'"
    Why  = "no body message is ever applied, so the avatar is never revealed"
  },
  @{
    Name = "me-frozen"
    File = "scripts/net/session_runtime.gd"
    From = "	samples.append({`n		`"t`": _now(), `"x`": float(m.get(`"x`", 0.0)), `"y`": 0.0,"
    To   = "	if samples.size() > 0:`n		return`n	samples.append({`n		`"t`": _now(), `"x`": float(m.get(`"x`", 0.0)), `"y`": 0.0,"
    Expect = "moved on the"
    Why  = "the first pose lands and no later one does: posed, but frozen"
  },
  @{
    Name = "snap-inert"
    File = "scripts/net/session_runtime.gd"
    From = '			_send_snapshot()'
    To   = '			pass'
    Expect = "horde reached the client"
    Why  = "the host never describes its horde, so the client builds no puppets"
  },
  @{
    Name = "claim-inert"
    File = "scripts/net/session_runtime.gd"
    From = '	if _host or _chan == null or not is_instance_valid(_chan):'
    To   = '	if true:'
    Expect = "damage claims reached the host"
    Why  = "the client resolves its shots locally and tells nobody"
  },
  @{
    Name = "kill-inert"
    File = "scripts/net/session_runtime.gd"
    From = '	if not bool(k.get("ok", false)):'
    To   = '	if true:'
    Expect = "kills came back"
    Why  = "the host confirms the death and the client ignores the confirmation"
  },
  @{
    Name = "round-inert"
    File = "scripts/net/session_runtime.gd"
    From = '	if n <= 0 or n == Game.round_no:'
    To   = '	if true:'
    Expect = "learned the host's forced round"
    Why  = "the round on the wire is discarded instead of applied"
  }
)

if ($Only.Count -gt 0) {
  $controls = $controls | Where-Object { $Only -contains $_.Name }
  if (-not $controls) { Write-Error "no control matched -Only"; exit 2 }
}

$results = @()

foreach ($c in $controls) {
  $path = Join-Path $root $c.File
  $original = [IO.File]::ReadAllText($path)

  if (-not $original.Contains($c.From)) {
    Write-Host ("[{0}] ANCHOR MISSING in {1}" -f $c.Name, $c.File) -ForegroundColor Red
    Write-Host "      The control cannot sabotage what it cannot find; the code moved."
    $results += @{ Name = $c.Name; Verdict = "anchor-missing"; Detail = "" }
    continue
  }
  # Exactly one site, or the sabotage is not the one described.
  $hits = ([regex]::Matches($original, [regex]::Escape($c.From))).Count
  if ($hits -ne 1) {
    Write-Host ("[{0}] ANCHOR MATCHED {1} TIMES in {2}" -f $c.Name, $hits, $c.File) -ForegroundColor Red
    $results += @{ Name = $c.Name; Verdict = "anchor-ambiguous"; Detail = "$hits sites" }
    continue
  }

  if ($DryRun) {
    # The 1-based line the anchor starts on, so a drifted anchor can be compared
    # against the file by eye.
    $before = $original.Substring(0, $original.IndexOf($c.From))
    $line = ($before -split "`n").Count
    Write-Host ("  ok  {0}  {1}:{2}" -f $c.Name.PadRight(16), $c.File, $line) -ForegroundColor Green
    $results += @{ Name = $c.Name; Verdict = "anchor-ok"; Detail = "$($c.File):$line" }
    continue
  }

  Write-Host ""
  Write-Host ("=== {0} — {1}" -f $c.Name, $c.Why) -ForegroundColor Cyan

  try {
    [IO.File]::WriteAllText($path, $original.Replace($c.From, $c.To))

    $out = & pwsh (Join-Path $PSScriptRoot "coop.ps1") 2>&1 | Out-String
    $failed = [regex]::Matches($out, '\[FAIL\]\s+(.+?)\s{2,}') | ForEach-Object { $_.Groups[1].Value.Trim() }
    $named  = $failed | Where-Object { $_ -like "*$($c.Expect)*" }

    if ($named) {
      Write-Host ("    the named check failed: {0}" -f ($named -join "; ")) -ForegroundColor Green
      $others = $failed | Where-Object { $_ -notlike "*$($c.Expect)*" }
      if ($others) {
        # Not a problem, and worth printing rather than hiding: cutting one wire
        # path legitimately starves the ones downstream of it. What would be a
        # problem is the named check surviving.
        Write-Host ("    also failed downstream: {0}" -f ($others -join "; ")) -ForegroundColor DarkGray
      }
      $results += @{ Name = $c.Name; Verdict = "discriminates"; Detail = "$($failed.Count) check(s) failed" }
    }
    elseif ($out -notmatch "co-op gate: (all checks passed|\d+ failure)") {
      # The gate threw instead of scoring — a process died or timed out. That is
      # NOT a pass: it proves the sabotage broke something, not that this check is
      # the one that saw it.
      #
      # Matched on the two SCORED outcomes rather than on the `co-op gate:` prefix.
      # The prefix alone also matched the opening banner, so every control looked
      # aborted whether it was or not.
      $reason = ([regex]::Matches($out, "co-op gate: (.+)") | Select-Object -Last 1)
      $detail = if ($reason) { $reason.Groups[1].Value.Trim() } else { "no outcome line" }
      Write-Host ("    the gate aborted rather than scoring: {0}" -f $detail) -ForegroundColor Yellow
      $results += @{ Name = $c.Name; Verdict = "aborted"; Detail = $detail }
    }
    else {
      Write-Host "    THE NAMED CHECK STILL PASSED — it is decoration." -ForegroundColor Red
      $results += @{ Name = $c.Name; Verdict = "DECORATION"; Detail = "" }
    }
  }
  finally {
    # Whatever happened, including Ctrl-C. See the note at the top.
    [IO.File]::WriteAllText($path, $original)
  }
}

Write-Host ""
Write-Host "=== controls ==="
foreach ($r in $results) {
  $colour = switch ($r.Verdict) {
    "discriminates" { "Green" }
    "DECORATION"    { "Red" }
    default         { "Yellow" }
  }
  Write-Host ("  {0}  {1}  {2}" -f $r.Name.PadRight(16), $r.Verdict.PadRight(17), $r.Detail) -ForegroundColor $colour
}

# A file left sabotaged is the failure mode that costs everyone else twenty minutes,
# so the restore is verified rather than assumed.
$dirty = @()
foreach ($c in $controls) {
  $text = [IO.File]::ReadAllText((Join-Path $root $c.File))
  if ($text.Contains($c.To) -and -not $text.Contains($c.From)) { $dirty += $c.File }
}
if ($dirty.Count -gt 0) {
  Write-Host ""
  Write-Host "RESTORE FAILED — these files are still sabotaged: $($dirty -join ', ')" -ForegroundColor Red
  exit 2
}

$want = if ($DryRun) { "anchor-ok" } else { "discriminates" }
$bad = @($results | Where-Object { $_.Verdict -ne $want })
if ($bad.Count -gt 0) { exit 1 }
exit 0
