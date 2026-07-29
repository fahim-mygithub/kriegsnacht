<#
.SYNOPSIS
  Drive scripts/perf_probe.gd natively, in whichever of the two ways the mode
  being measured actually needs.

.DESCRIPTION
  There are three kinds of measurement in this project and only two of them can
  be answered without a browser. This script exists to make the difference
  impossible to get wrong by accident, because getting it wrong does not fail —
  it produces a plausible number.

  **Headless.** The question is about the CPU: the physics server, or a sweep
  over an integer grid. Removing the renderer makes `physics_ms` and the probe's
  own timings the signal instead of a term inside a frame time.
    M-PHYS   pwsh tools/perf_native.ps1 -Mode phys
    M-FLOW   pwsh tools/perf_native.ps1 -Mode flow
    M-SEP    pwsh tools/perf_native.ps1 -Mode sep

  **Windowed.** The question needs a frame to have been drawn — a shadow map, a
  post pass, a particle draw, a shader that has to build. `-Windowed` is selected
  automatically for these; do not force `-Headless` on them, because under
  `--headless` `draw_calls` is 0, `video_mem` is 0, nothing rasterises, and every
  row comes back looking healthy.
    M-WARM              -Mode warm        (runs the A/B pair; see below)
    M-SHADOW/M-SHADOW2  -Mode shadow
    M-SSAO              -Mode ssao
    M-PARTICLES         -Mode particles
    M-BILLBOARD         -Mode billboard
    M-VMFOV             -Mode vmfov       (writes PNGs)
    M-MMCOLOR           -Mode mmcolor     (writes PNGs)
    M-SHADOWCAST        -Mode shadowcast  (writes PNGs)

  **Web only.** M-BASE and M-AUDIO are about WebGL2 fill rate and about
  `postMessage` pressure on the one thread that also runs the renderer. Neither
  is answerable here at all and this script refuses to pretend: it needs
  `tools/build.ps1 -Perf`, `tools/perf_collector.py`, and a browser tab that is
  genuinely visible and focused. A background tab reports *nothing* rather than
  reporting *slow*, so a run from an automated tab is not a pessimistic
  measurement, it is an absent one.

  **What a windowed native run is and is not.** It runs `gl_compatibility` — the
  shipping renderer — but through a desktop OpenGL driver rather than through
  WebGL2, on whatever GPU this machine has. So it answers the *structural*
  questions honestly (does the draw-call count stay flat, does the object count
  jump, does that shader build at all, which sign is upright) and it does not
  answer the *budget* questions (is this under 1.0 ms on an integrated laptop).
  Take the structure from here and the milliseconds from the browser.

  **Three things this script does that are not obvious and are not optional.**

  1. It deletes `user://shader_cache` before a `warm` run. Godot compiles
     `_load_from_cache`/`_save_to_cache` out under `#ifdef WEB_ENABLED`, so on
     desktop the *second* run of anything starts warm and M-WARM measures
     nothing at all. Deleting it is necessary and still not sufficient — the
     graphics driver keeps its own program cache and we cannot reach it, which
     is why the native number is a floor and the browser is the answer.

  2. It never passes `--shot`. `main.gd`'s `--shot` handler quits after 60
     frames and steers the player's yaw itself; the probe's capture modes settle
     for longer than that and own the camera. Two writers, one node — the probe
     writes its own PNGs through `--perf-shots`.

  3. It refuses to start if `project.godot.perfbak` already exists. That file is
     only there if a previous run was killed before its finally block, which
     means `project.godot` on disk is the *injected* copy and the backup is the
     only clean one left. Overwriting it would destroy the clean copy and then
     "restore" the injected one — shipping an autoload that points every
     visitor's browser at a localhost socket. This is the only failure of this
     script that outlives the script, so it is a hard stop rather than a warning.

  The probe is registered as an autoload for the duration of the run and removed
  afterwards, in a finally block, exactly as tools/build.ps1 does it.

.EXAMPLE
  python tools/perf_collector.py build/perf     # in another shell, for the POSTs
  pwsh tools/perf_native.ps1 -Mode phys
  pwsh tools/perf_native.ps1 -Mode shadow
  pwsh tools/perf_native.ps1 -Mode vmfov
#>
param(
  [ValidateSet("phys", "flow", "sep", "warm", "shadow", "ssao", "particles",
    "billboard", "vmfov", "mmcolor", "shadowcast", "base", "audio")]
  [string]$Mode = "phys",

  # Only meaningful for -Mode phys. "Jolt Physics", with the space. NOT
  # "JoltPhysics3D" — that is not one of the names the setting accepts (the hint
  # string is "DEFAULT,Jolt Physics,GodotPhysics3D,Dummy"), and an unrecognised
  # value falls back to GodotPhysics3D in silence. A matrix run using the wrong
  # name compares GodotPhysics3D against itself and reports a dead heat.
  [string[]]$Engines = @(),

  # Where the capture modes write their PNGs. Absolute, because Godot resolves a
  # path with no res:// or user:// prefix against the OS and this script's
  # working directory is not the project's.
  [string]$Shots = "",

  # Force the renderer on or off, for the one case the table below cannot know
  # about: re-running a headless-capable mode windowed to see it happen.
  [switch]$Windowed,
  [switch]$Headless,

  [string]$Godot = "$env:USERPROFILE\Godot\Godot_v4.7-stable_win64_console.exe",
  [int]$TimeoutSec = 400
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$proj = Join-Path $root "project.godot"
$backup = Join-Path $root "project.godot.perfbak"

if (-not (Test-Path $Godot)) { throw "Godot not found at $Godot" }

# A surviving backup means the previous run was killed before its finally block,
# so project.godot on disk is the INJECTED one and the backup is the only clean
# copy there is. Copying over it here would destroy the clean copy and then
# "restore" the injected one at the end of this run — committing an autoload that
# points every visitor's browser at a localhost socket. Refuse, and say what to
# do. This is the one failure mode of this script that outlives the script.
if (Test-Path $backup) {
  throw @"
$backup already exists, so a previous run was killed before it could restore.
project.godot on disk is probably the injected copy. Do NOT re-run until you have:
  Move-Item -Force "$backup" "$proj"
and confirmed that 'git diff project.godot' is clean.
"@
}

if (-not (Test-Path (Join-Path $root "scripts/perf_probe.gd"))) {
  throw "scripts/perf_probe.gd not found - nothing to register as an autoload"
}

# Which modes need a drawn frame. Getting this wrong is the failure this script
# exists to prevent, so it is a table rather than a habit.
$needsRenderer = @{
  phys = $false; flow = $false; sep = $false
  warm = $true; shadow = $true; ssao = $true; particles = $true
  billboard = $true; vmfov = $true; mmcolor = $true; shadowcast = $true
}

if ($Mode -eq "base" -or $Mode -eq "audio") {
  throw @"
$Mode is web-only by construction and this script will not fake it.
  M-BASE  is about WebGL2 fill rate on the shipping target.
  M-AUDIO is about postMessage pressure on the single thread that also runs the
          renderer (~344 messages/s per live voice).
Neither has a native equivalent, and the headless frame times here must not be
borrowed for them. Run instead:
  pwsh tools/build.ps1 -Perf
  python tools/perf_collector.py build/perf
  # then open http://127.0.0.1:8970/index.html?mode=$Mode in a VISIBLE, FOCUSED tab
"@
}

$render = $needsRenderer[$Mode]
if ($Windowed) { $render = $true }
if ($Headless) { $render = $false }

if ($Windowed -and $Headless) { throw "-Windowed and -Headless are mutually exclusive" }
if ($Headless -and $needsRenderer[$Mode]) {
  Write-Host "!! -Headless on ${Mode}: draw_calls will be 0 and nothing will rasterise."
  Write-Host "!! The rows will look healthy and mean nothing. Continuing because you asked."
}

# The engine sweep belongs to M-PHYS and to nothing else. Every other mode runs
# once, on whatever the project committed, so the row describes the shipping
# configuration rather than a variant of it.
if ($Engines.Count -eq 0) {
  if ($Mode -eq "phys") { $Engines = @("GodotPhysics3D", "Jolt Physics") }
  else { $Engines = @("") }   # "" means: leave 3d/physics_engine alone
}

$capture = @("vmfov", "mmcolor", "shadowcast", "billboard") -contains $Mode
if ($capture) {
  if (-not $Shots) { $Shots = Join-Path $root "notes/perf/shots" }
  if (-not (Test-Path $Shots)) { New-Item -ItemType Directory -Force $Shots | Out-Null }
  Write-Host "shots -> $Shots"
}

# M-WARM is a *difference*, so the one command runs both halves. `--no-warmup`
# is read by main.gd (mirroring quality_governor's `--no-post-fx`), not by the
# probe — the probe only records which way the flag was set, in env.
$warmPasses = @($false)
if ($Mode -eq "warm") {
  $warmPasses = @($false, $true)
  # The A/B is only an A/B if main.gd honours the flag. Until that wiring lands
  # the two passes below are byte-for-byte the same run: the probe records
  # env.warmup_disabled either way, so the JSON stays honest, but two identical
  # tables invite the conclusion "the warm-up pass does nothing" and that is the
  # wrong one. Grep for it rather than assume.
  $mainGd = Join-Path $root "scripts/main.gd"
  if (-not (Select-String -Path $mainGd -Pattern '_warmup_disabled' -Quiet)) {
    Write-Host "!! main.gd does not read --no-warmup yet, so BOTH passes below are the"
    Write-Host "!! SAME RUN and the difference between them is zero by construction."
    Write-Host "!! See the M-WARM section of notes/perf/README.md for the wiring."
  }
}

function Restore-Project {
  if (Test-Path $backup) { Move-Item -Force $backup $proj; Write-Host "restored project.godot" }
}

# The exported/project-run shader cache. Deleting it is what makes a second
# `warm` run mean the same thing as the first.
function Clear-ShaderCache {
  # Indexed defensively: `(Select-String ... | Select -First 1).Matches.Groups[1]`
  # is "Cannot index into a null array" the moment the pattern misses, and
  # $ErrorActionPreference is Stop, so a missing key would abort the run rather
  # than skip the cache clear.
  $hit = Select-String -Path $backup -Pattern '^config/name="(.*)"' | Select-Object -First 1
  $name = ""
  if ($hit) { $name = $hit.Matches[0].Groups[1].Value }
  if (-not $name) { Write-Host "!! could not read config/name; shader cache not cleared"; return }
  $dir = Join-Path $env:APPDATA "Godot\app_userdata\$name\shader_cache"
  if (Test-Path $dir) {
    Remove-Item -Recurse -Force $dir
    Write-Host "cleared $dir"
  } else {
    Write-Host "no shader cache at $dir (already cold)"
  }
  Write-Host "note: the graphics driver's own program cache is not ours to clear."
}

try {
  Copy-Item $proj $backup

  foreach ($engine in $Engines) {
    foreach ($noWarm in $warmPasses) {
      $tag = $Mode
      if ($engine) { $tag += " / $engine" }
      if ($Mode -eq "warm") { $tag += if ($noWarm) { " / warm-up OFF" } else { " / warm-up ON" } }
      Write-Host "`n=== $tag ==="

      $lines = Get-Content $backup
      $injected = [System.Collections.Generic.List[string]]::new()
      $addedProbe = $false
      $setEngine = $false
      foreach ($line in $lines) {
        # Strip the editor-only plugin, same as the export path.
        if ($line -match '^MCP(Screenshot|InputService|GameInspector)=') { continue }
        if ($line -match '^enabled=PackedStringArray\("res://addons/godot_mcp/plugin\.cfg"\)') { continue }
        if ($engine -and $line -match '^3d/physics_engine=') {
          $injected.Add("3d/physics_engine=`"$engine`"")
          $setEngine = $true
          continue
        }
        $injected.Add($line)
        if (-not $addedProbe -and $line -match '^Sfx=') {
          $injected.Add('PerfProbe="*res://scripts/perf_probe.gd"')
          $addedProbe = $true
        }
      }
      if (-not $addedProbe) { throw "could not anchor PerfProbe after the Sfx autoload" }
      if ($engine -and -not $setEngine) { throw "no 3d/physics_engine key to rewrite - it is supposed to be set explicitly" }
      Set-Content -Path $proj -Value $injected

      if ($Mode -eq "warm") { Clear-ShaderCache }

      # $root is quoted because Start-Process re-splits ArgumentList on spaces,
      # and this project lives under a path that has one. build.ps1 avoids it by
      # using the call operator instead.
      $argv = [System.Collections.Generic.List[string]]::new()
      if (-not $render) { $argv.Add("--headless") }
      $argv.Add("--path"); $argv.Add("`"$root`"")
      $argv.Add("--perf-mode"); $argv.Add($Mode)
      if ($capture) { $argv.Add("--perf-shots"); $argv.Add("`"$Shots`"") }
      if ($noWarm) { $argv.Add("--no-warmup") }

      $slug = ($tag -replace '[^A-Za-z0-9]', '_')
      $out = Join-Path $env:TEMP "perfnat_$slug.out"
      $err = Join-Path $env:TEMP "perfnat_$slug.err"
      if ($render) {
        Write-Host "   a window will open. Leave it alone and do not alt-tab into it."
      }
      $p = Start-Process -FilePath $Godot -ArgumentList $argv.ToArray() `
        -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
      if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        $p.Kill()
        Write-Host "!! timed out after ${TimeoutSec}s"
      }

      # Read once. Four separate Get-Content passes over the same file is four
      # chances for one of them to see a half-flushed tail after a Kill().
      $stdout = @(Get-Content $out -ErrorAction SilentlyContinue)

      # Anchored on the key alone, NOT on `PERF: {"event":...`. Godot serialises a
      # Dictionary in insertion order, and the probe builds these rows with "data"
      # first — so the line really reads `PERF: {"data":{...},"event":"stage",...}`
      # and a pattern expecting "event" straight after the brace matches nothing at
      # all. It fails as "NO STAGE ROWS. Nothing was measured", which reads exactly
      # like the parse-error case the block below warns about, so it cost a real
      # diagnosis: the probe was working perfectly and only the grep was wrong.
      $rows = $stdout | Select-String '"event":"stage"'
      $rows | ForEach-Object { ($_ -replace '.*"data":', '') -replace '\}\}$', '}' }
      $stdout | Select-String '"event":"warn"' | ForEach-Object { "  !! $_" }

      # A shader that fails to build under gl_compatibility does not throw and
      # does not return an error code — it prints and draws nothing. M-BILLBOARD
      # is decided as much by this as by the pixel count.
      $errors = Get-Content $err -ErrorAction SilentlyContinue |
        Where-Object { $_ -match 'ERROR|Invalid|Failed|shader|SHADER|Compilation' }
      if ($errors) { Write-Host "stderr:"; $errors | Select-Object -First 12 }

      # An empty run is the failure this whole harness is most likely to produce
      # and the least likely to be noticed, because "no rows" reads exactly like
      # "nothing interesting happened" when it is scrolling past.
      if (-not $rows) {
        Write-Host "!! NO STAGE ROWS. Nothing was measured."
        Write-Host "!! A parse error in any script reachable from the main scene makes"
        Write-Host "!! Godot HANG rather than exit, so a timeout here is a parse error"
        Write-Host "!! until the stderr above proves otherwise. The other usual cause is"
        Write-Host "!! the PerfProbe autoload not taking - check the [autoload] block of"
        Write-Host "!! project.godot while this run is still in flight."
      } elseif (-not ($stdout | Select-String '"event":"final"' -Quiet)) {
        Write-Host "!! No final payload: the run ended before writing its env block, so"
        Write-Host "!! the rows above carry no renderer, driver, physics server or render"
        Write-Host "!! scale. Unlabelled rows are not measurements - re-run."
      }
    }
  }
}
finally {
  Restore-Project
}

if ($capture) {
  Write-Host "`nPNGs:"
  Get-ChildItem $Shots -Filter "$Mode-*.png" | ForEach-Object { "  $($_.FullName)" }
  Write-Host "The numbers above are the verdict; the PNGs are how you check the verdict."
}
