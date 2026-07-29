extends Node

## The browser build synthesised every sound through the Web Audio API from
## oscillators plus one shared noise buffer — no samples anywhere. Godot has no
## direct Web Audio equivalent, so the same synthesis is done once at startup
## and baked into AudioStreamWAV buffers, which are then played as normal.
##
## Everything here is designed for Godot's **Sample** playback mode, which is what
## the web export uses. In that mode no AudioEffect executes at all — no reverb,
## no compressor, no attenuation filter, no Doppler, no Area3D bus override. They
## work in the editor and vanish in the browser, so none of them is used. Buses
## exist purely as volume groups.
##
## The other web constraint is main-thread pressure rather than mixing: every live
## voice owns an AudioWorkletNode that posts a message every 128-sample quantum
## (~344/s per voice) onto the single thread that also runs the game and the
## renderer. Hence a hard voice cap and a mandatory max_distance on every 3D
## player — max_distance defaults to 0.0, which means "never cull".

const RATE := 22050
const POOL := 12          # non-positional voices (UI, toasts, purchases)
const POOL_3D := 14       # positional voices — see the message-pressure note above

## Every 3D player gets one of these. Without it the voice stays in the graph at
## any distance and keeps posting messages forever.
const MAX_DIST := 26.0
const MAX_DIST_VOICE := 20.0   # zombie vocalisations cull tighter

# --- the round ceremony -------------------------------------------------------

## The beat of nothing between the round changing and the toll announcing it.
## The ancestor fires the sting, the flash and the spawn timer in the same frame
## (html:2865-2868), so the most recognisable cue in the game lands on top of
## whatever the last zombie was still doing. Cutting the bed and holding this
## long is what makes it land; the four layers below are only half of the fix.
## Read by the HUD too — the title card holds at full opacity for exactly this
## long before it starts fading, so the numeral and the toll arrive together.
const ROUND_SILENCE := 1.2

## The four layers peak at 0.452 — well under the 0.86 their gains sum to, because
## they are not in phase and the noise layer comes out of a low-pass. So the cue
## has headroom the single tone it replaces did not: that was 0.42 played at -6.0,
## and matching it here would make the biggest moment in the game quieter than the
## bug it fixes. -3.0 puts the sting about 6 dB under a gunshot, which is roughly
## where the ancestor's own roundStart sits against its shot().
const ROUND_DB := -3.0

## Web Audio's `exponentialRampToValueAtTime(0.0001, t + decay)` (html:445) is the
## envelope behind every `decay:` in the ancestor's synth. It is a fixed 80 dB
## fall, not a fixed rate, so the per-sample constant depends on the layer's own
## peak. The combat one-shots use the port's rate-based `exp(-t*k)` instead, which
## is fine for a 90 ms hit; a ceremony cue is the one place the ancestor's actual
## envelope shape is the whole point, because it is what makes the sting a *hit*
## with a tail rather than a swell.
const RAMP_FLOOR := 0.0001

## A layer is cut when its envelope reaches this — about -54 dBFS, silent under
## anything else in the mix — rather than when the ancestor's ramp reaches its own
## 0.0001. That is the difference between a two-second buffer and a 1.2 s one, and
## every sample in between costs real boot milliseconds for nothing audible.
## Quiet layers are cut sooner than loud ones, which is the point: the three
## power-on harmonics at gain .06 die 0.4 s before the saw underneath them does.
const CUT_LEVEL := 0.002

## Each layer is faded out over its last few milliseconds so the cut cannot click.
const FADE := 0.02

## Naive sawtooth from a phase in [0, TAU): the ancestor's OscillatorNode is
## band-limited and ours is not, which is already true of `_voice()`.
const SAW_K := 1.0 / PI

# --- the ambient bed ----------------------------------------------------------

## Three baked tiers rather than three layers faded against each other: there are
## no AudioEffects on this platform and no runtime mixing budget (SYNTHESIS §1.2
## deletes T1.6's AudioStreamSynchronized design outright), so the crossfade the
## ancestor gets for free from `setTension()` becomes a choice between three
## finished loops. Rounds 1-5, 6-15, 16+ — the gap analysis's density bands.
const AMB_BANDS := [5, 15]

## Two seconds at 22050 is 44100 samples, in which the 41 Hz drone completes
## exactly 82 cycles and the 466 Hz whine exactly 932 — so both oscillators are
## phase-continuous across the loop point and the seam carries no waveform step.
const AMB_SECONDS := 2.0

## Sources are the ancestor's own (html:541-554): a sawtooth at 41 Hz through a
## 180 Hz lowpass, and white noise through a 340 Hz bandpass at Q 0.6 for the room
## tone. 466 Hz is a tritone three octaves above the drone and is *not* in the
## ancestor — it is what makes tier three read as worse rather than merely louder,
## which a gain change on its own cannot do.
const AMB_DRONE := 41.0
const AMB_WIND := 340.0
const AMB_WHINE := 466.0

## [drone, wind, whine] per tier. The drone column is the ancestor's own tension
## curve, `.04 + t*.09` (html:555) with `t = min(1, round/16)` (html:2868),
## evaluated at the middle of each band — rounds 3, 10 and 16+. The wind column is
## flat because the ancestor's is: `startDrone` sets it once at .014 (html:552)
## and `setTension` never touches it. The whine column is invented.
const AMB_GAIN := [
	[0.0569, 0.014, 0.000],
	[0.0963, 0.014, 0.004],
	[0.1300, 0.014, 0.011],
]

## The bed is baked this much hot and played back that much down, which is the
## same level with two and a half more bits of resolution under it — a tier baked
## at the ancestor's raw gains peaks around 0.16 and throws away three bits.
## Scaled, the three tiers peak at 0.33 / 0.57 / 0.78, so the loudest still has
## headroom. -14.0 dB is 5.0 to within a fiftieth of a decibel, which means the
## level that actually reaches the bus is the ancestor's own.
const AMB_SCALE := 5.0
const AMB_DB := -14.0

## The loop is shaped as one slow gust that dies at both ends. That is not a
## flourish: on this platform a looping sample is restarted from the `ended` event
## on the main thread rather than scheduled gaplessly (read out of the shipped
## engine glue, docs/index.js — `case "forward": self.restart()`), so a seam that
## is not already silent is an audible click on every pass. Dying at both ends
## puts the gap in the quiet part on every platform, and the periodicity then
## reads as the building breathing instead of as a loop.
const AMB_FLOOR := 0.55
const AMB_EDGE := 0.03

var _players: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next := 0
var _cache := {}
var _rng := RandomNumberGenerator.new()
var _bake_ms := 0

## The bed gets its own non-positional player and never touches either pool. The
## 3D pool is 14 voices, and notes/perf/README.md records that 14 is an estimate
## nothing has ever measured — a voice that is live for the whole run must not be
## spending one of them.
var _amb: AudioStreamPlayer
var _amb_streams: Array[AudioStreamWAV] = []
var _amb_tier := -1

## "The bed should be sounding right now", which is not the same as `_amb.playing`
## and is what the loop watchdog below tests. Without it, a `stop()` that emits
## `finished` on the way out would restart the bed inside the silence beat.
var _amb_on := false

## Bumped by every ceremony and by every state change that ends one, so a beat
## still in flight when the run restarts cannot land its toll on the menu.
var _ceremony := 0

## Ids that get several baked variants so a repeated sound is not literally the
## same samples every time. The old code cached exactly one buffer per id for the
## life of the process, so every hit in every run sounded identical.
const VARIANTS := {"hit": 3, "headshot": 3, "melee": 3, "board": 3, "death": 3}


func _ready() -> void:
	_rng.seed = 0x5EED
	_setup_buses()

	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)

	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = &"SFX"
		p3.max_distance = MAX_DIST
		p3.unit_size = 4.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		# Doppler does nothing under Sample playback; leaving it on would only
		# cost tracking work for an effect that never reaches the output.
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p3.max_polyphony = 1
		add_child(p3)
		_players_3d.append(p3)

	_amb = AudioStreamPlayer.new()
	_amb.name = "Ambience"
	_amb.bus = &"SFX"
	_amb.volume_db = AMB_DB
	add_child(_amb)
	_amb.finished.connect(_amb_finished)

	_prebake()

	# The bed belongs to play: it must not run under the title card, the death
	# screen or the pause overlay, and the tier must not survive into a new run.
	Game.state_changed.connect(_on_state)


## Buses are volume groups only — no effects, because none would execute on web.
func _setup_buses() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "SFX")
		AudioServer.set_bus_send(i, "Master")


## Synthesis runs in a per-sample GDScript loop on the only thread there is, so
## doing it lazily meant the first shot of a new weapon baked mid-fight. Bake the
## combat set up front and record the cost, since nothing had ever measured it.
func _prebake() -> void:
	var t0 := Time.get_ticks_usec()
	for id in ["hit", "headshot", "death", "melee", "board", "hurt", "empty",
			"buy", "deny", "reload_in", "reload_out", "round", "hound_round",
			"power_on", "powerup", "box"]:
		_stream(id)
	for pal in 3:
		_stream("groan%d" % pal)
	_stream("bark")
	# The bed is three buffers off one set of stems, so it is built as a set
	# rather than reached through _build() three times.
	_bake_ambience()
	_bake_ms = int((Time.get_ticks_usec() - t0) / 1000)


func bake_ms() -> int:
	return _bake_ms


## Two 16-bit samples to an int32 word, then one memcpy out through
## `to_byte_array()`. The obvious spelling — `clampf()` and `encode_s16()` per
## sample — is two Variant method calls for every sample in the project, and the
## round ceremony below roughly triples the number of samples that pass through
## here. Same arithmetic, same truncation, calls hoisted out of the loop; it is
## worth about a third of the bake budget `--verify` prints.
##
## `int()` truncates toward zero, which is what the clampf/encode_s16 spelling
## did. Rounding instead would move every sample in the game by half an LSB.
func _bake(samples: PackedFloat32Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var n := samples.size()
	var pairs := n >> 1
	var words := PackedInt32Array()
	words.resize((n + 1) >> 1)
	for i in pairs:
		var j := i << 1
		var a := samples[j]
		if a > 1.0:
			a = 1.0
		elif a < -1.0:
			a = -1.0
		var b := samples[j + 1]
		if b > 1.0:
			b = 1.0
		elif b < -1.0:
			b = -1.0
		words[i] = (int(a * 32767.0) & 0xFFFF) | (int(b * 32767.0) << 16)
	if (n & 1) == 1:
		var tail := samples[n - 1]
		if tail > 1.0:
			tail = 1.0
		elif tail < -1.0:
			tail = -1.0
		words[pairs] = int(tail * 32767.0) & 0xFFFF
	var bytes := words.to_byte_array()
	# An odd sample count leaves one padding sample in the last word.
	if (n & 1) == 1:
		bytes.resize(n * 2)
	w.data = bytes
	return w


## Gunshot: a short pitched "crack" over a noise body, both decaying fast.
## freq/thump/body come straight out of the weapon table.
func _gunshot(freq: float, thump: float, body: float) -> AudioStreamWAV:
	var dur := 0.10 + 0.09 * body
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	var thump_phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 34.0 / body)
		var crack := sin(phase) * 0.30
		var low := sin(thump_phase) * 0.42 * exp(-t * 22.0)
		var noise := _rng.randf_range(-1.0, 1.0) * 0.55 * exp(-t * 26.0 / body)
		buf[i] = (crack + low + noise) * env
		# both oscillators sweep down over the shot
		phase += TAU * (freq * exp(-t * 12.0)) / RATE
		thump_phase += TAU * (thump * exp(-t * 6.0)) / RATE
	return _bake(buf)


func _noise_hit(dur: float, decay: float, tone: float, amp: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * decay)
		var s := _rng.randf_range(-1.0, 1.0) * 0.7
		if tone > 0.0:
			s += sin(phase) * 0.5
			phase += TAU * tone / RATE
		buf[i] = s * env * amp
	return _bake(buf)


func _tone(freq: float, dur: float, decay: float, amp: float, sweep := 1.0) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		buf[i] = sin(phase) * exp(-t * decay) * amp
		phase += TAU * (freq * pow(sweep, t)) / RATE
	return _bake(buf)


## A sawtooth through a resonant band-pass, which is what gives the zombie voice
## its throat. Godot's AudioEffectFilter would be the obvious tool and does
## nothing on web, so the filter is baked into the sample loop instead: a
## two-pole state-variable band-pass, four multiply-adds per sample.
func _voice(f0: float, f1: float, dur: float, centre: float, q: float, amp: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	var low := 0.0
	var band := 0.0
	var f := 2.0 * sin(PI * clampf(centre / RATE, 0.0001, 0.24))
	var damp := 1.0 / maxf(q, 0.5)
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		# Sawtooth, sliding from f0 down to f1 across the whole utterance.
		var hz := lerpf(f0, f1, k)
		var saw: float = 2.0 * (phase / TAU - floor(phase / TAU + 0.5))
		phase += TAU * hz / RATE
		if phase > TAU:
			phase -= TAU
		var drive: float = saw + _rng.randf_range(-1.0, 1.0) * 0.12
		low += f * band
		var high: float = drive - low - damp * band
		band += f * high
		# Slow attack, long release — a groan should not click on.
		var env: float = minf(1.0, k * 6.0) * (1.0 - k) * (1.0 - k)
		buf[i] = band * env * amp
	return _bake(buf)


# --- ceremony layers ----------------------------------------------------------
#
# The one-shots above each own a whole buffer. A ceremony cue is several voices
# over one buffer, so these three add into a buffer somebody else sized and take
# the ancestor's tone()/noise() arguments in the ancestor's order. Each layer runs
# from its own `delay` for _span() samples and no longer.


## How many samples of a layer are worth synthesising, from its peak and the
## ancestor's decay time. See CUT_LEVEL.
func _span(amp: float, decay: float) -> int:
	if amp <= CUT_LEVEL:
		return 0
	return int(decay * RATE * log(amp / CUT_LEVEL) / log(amp / RAMP_FLOOR))


## Per-sample multiplier that walks an envelope from `amp` to RAMP_FLOOR across
## `decay` seconds. One multiply a sample instead of the exp() the rate-based
## one-shots above pay for — which matters, because these buffers are long.
func _decay_step(amp: float, decay: float) -> float:
	return pow(RAMP_FLOOR / amp, 1.0 / (decay * RATE))


## The same trick for the ancestor's `to:`, which is an exponential ramp on the
## oscillator frequency and therefore a constant ratio per sample on the phase
## increment. No pow() in the inner loop either.
func _glide_step(f0: float, f1: float, dur: float) -> float:
	return pow(f1 / f0, 1.0 / (dur * RATE))


## One or two sawtooths. The two-voice form is the round sting's pair
## (html:522-523), a couple of hertz apart so the beat between them makes the toll
## lurch rather than ring; `fb0 <= 0.0` runs a single voice, which is what the
## power-on whine wants.
func _mix_saw(buf: PackedFloat32Array, fa0: float, fa1: float, dur: float,
		amp: float, decay: float, delay := 0.0, fb0 := 0.0, fb1 := 0.0) -> void:
	var at := int(delay * RATE)
	var last := mini(buf.size(), at + _span(amp, decay))
	var fade := maxi(1, int(FADE * RATE))
	var two := fb0 > 0.0
	var env := amp
	var estep := _decay_step(amp, decay)
	var ia := TAU * fa0 / RATE
	var sa := _glide_step(fa0, fa1, dur)
	var ib := (TAU * fb0 / RATE) if two else 0.0
	var sb := _glide_step(fb0, fb1, dur) if two else 1.0
	var pa := 0.0
	var pb := 0.0
	for i in range(at, last):
		var g := env
		var left := last - i
		if left < fade:
			g *= float(left) / float(fade)
		var s := pa * SAW_K - 1.0
		pa += ia
		if pa >= TAU:
			pa -= TAU
		ia *= sa
		if two:
			s += pb * SAW_K - 1.0
			pb += ib
			if pb >= TAU:
				pb -= TAU
			ib *= sb
		buf[i] += s * g
		env *= estep


## A sine gliding f0 -> f1. Passing f1 == f0 is a steady tone, which is what the
## power-on harmonics are.
func _mix_sine(buf: PackedFloat32Array, f0: float, f1: float, dur: float,
		amp: float, decay: float, delay := 0.0) -> void:
	var at := int(delay * RATE)
	var last := mini(buf.size(), at + _span(amp, decay))
	var fade := maxi(1, int(FADE * RATE))
	var env := amp
	var estep := _decay_step(amp, decay)
	var inc := TAU * f0 / RATE
	var fstep := _glide_step(f0, f1, dur)
	var phase := 0.0
	for i in range(at, last):
		var g := env
		var left := last - i
		if left < fade:
			g *= float(left) / float(fade)
		buf[i] += sin(phase) * g
		phase += inc
		if phase >= TAU:
			phase -= TAU
		inc *= fstep
		env *= estep


## Filtered white noise, through the same two-pole state-variable filter `_voice`
## uses and for the same reason: no AudioEffect executes on this renderer, so the
## filter has to live in the sample loop. `band` picks the band-pass tap over the
## low-pass one. `attack` has no ancestor equivalent — the ancestor's noise() hits
## at full gain — and exists for the hound cue, where an instant attack on a dark
## noise bed reads as an explosion (html:490-492) and a slow one reads as weather.
func _mix_noise(buf: PackedFloat32Array, cutoff: float, q: float, band: bool,
		amp: float, decay: float, delay := 0.0, attack := 0.0) -> void:
	var at := int(delay * RATE)
	var last := mini(buf.size(), at + _span(amp, decay))
	var fade := maxi(1, int(FADE * RATE))
	var rise := maxi(1, int(attack * RATE))
	var env := amp
	var estep := _decay_step(amp, decay)
	var f := 2.0 * sin(PI * clampf(cutoff / RATE, 0.0001, 0.24))
	var damp := 1.0 / maxf(q, 0.5)
	var low := 0.0
	var bp := 0.0
	for i in range(at, last):
		var g := env
		var k := i - at
		if k < rise:
			g *= float(k) / float(rise)
		var left := last - i
		if left < fade:
			g *= float(left) / float(fade)
		var drive := _rng.randf_range(-1.0, 1.0)
		low += f * bp
		var high := drive - low - damp * bp
		bp += f * high
		buf[i] += (bp if band else low) * g
		env *= estep


# --- ceremony cues ------------------------------------------------------------


## The round sting: kriegsnacht.html:519-526, four layers, every one of them
## descending.
##
## The port shipped this as a single `_tone(120, 1.30, 2.4, 0.42, 1.6)`, and
## `freq * pow(sweep, t)` with a sweep above one makes the pitch *rise*. That
## sweep was the port's own: the ancestor's tone() takes a target frequency
## (`to:`, html:442), never a per-second ratio, and roundStart targets 52, 50 and
## 32 Hz from 320, 322 and 70. The thing being ported was always a falling toll.
##
## `roundStart(n)` ignores its argument, so there is no per-round variation here
## to restore — in the ancestor the escalation lives entirely in the drone, which
## is what the three ambience tiers below are.
func _round_sting() -> AudioStreamWAV:
	var sub_at := int(0.10 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(maxi(maxi(_span(0.20, 1.4), _span(0.16, 1.6)),
		sub_at + _span(0.30, 1.8)))
	# The detuned pair, two hertz apart (html:522-523).
	_mix_saw(buf, 320.0, 52.0, 1.5, 0.20, 1.4, 0.0, 322.0, 50.0)
	# The swell under them (html:524).
	_mix_noise(buf, 700.0, 1.0, false, 0.16, 1.6)
	# ...and the sub a tenth of a second late, so the low end arrives after the
	# attack rather than inside it (html:525).
	_mix_sine(buf, 70.0, 32.0, 1.9, 0.30, 1.8, 0.10)
	return _bake(buf)


## The hound-round variant. There is nothing to port: `roundStart(n)` ignores `n`
## and a dog round gets the identical cue in the ancestor, so this is built — but
## built out of the ancestor's own hound material and on the round sting's
## skeleton, so it still reads as a round beginning rather than some other event.
##
##  - the swell becomes thunder: the same low-passed noise dropped from 700 Hz to
##    240 and given a 0.22 s roll-in, which is the difference between a blast and
##    something a long way off;
##  - the detuned saws become two howls — the ancestor's bark is a sawtooth
##    220 -> 110 Hz over 0.16 s (html:499) — stretched eight times as long, pitched
##    up into a cry and started a fifth of a second after the thunder, so the
##    thunder announces and the pack answers;
##  - the sub is the round sting's, four hertz lower, so the two cues are not the
##    same note.
func _hound_sting() -> AudioStreamWAV:
	var sub_at := int(0.12 * RATE)
	var howl_at := int(0.20 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(maxi(maxi(_span(0.30, 1.9), howl_at + _span(0.15, 1.1)),
		sub_at + _span(0.30, 1.8)))
	_mix_noise(buf, 240.0, 0.9, false, 0.30, 1.9, 0.0, 0.22)
	_mix_saw(buf, 300.0, 150.0, 1.3, 0.15, 1.1, 0.20, 286.0, 138.0)
	_mix_sine(buf, 66.0, 30.0, 1.9, 0.30, 1.8, 0.12)
	return _bake(buf)


## The generator whine, html:513-518 — the one cue in the ancestor that rises. A
## sawtooth climbing 40 -> 120 Hz over 2.2 s is the flywheel finding its speed,
## the noise swell under it is the room waking up, and the three sine harmonics at
## a fifth of the saw's gain, entering a tenth of a second apart, are the relays.
func _power_on() -> AudioStreamWAV:
	var buf := PackedFloat32Array()
	buf.resize(maxi(_span(0.30, 2.0), int(0.7 * RATE) + _span(0.06, 1.3)))
	_mix_saw(buf, 40.0, 120.0, 2.2, 0.30, 2.0)
	_mix_noise(buf, 900.0, 1.0, false, 0.24, 1.5)
	for h in 3:
		var hz := 220.0 * float(h + 1)
		_mix_sine(buf, hz, hz, 1.4, 0.06, 1.3, 0.5 + float(h) * 0.1)
	return _bake(buf)


## The three ambience tiers, off one set of stems.
##
## The stems are where all the per-sample cost is — one noise generator and three
## filters — so they are synthesised once and each tier is a weighted sum of them.
## Three independent bakes would be three generators and nine filters for three
## mixes of the same material, and this runs inside the boot budget --verify
## prints alongside everything else in this file.
func _bake_ambience() -> void:
	var n := int(AMB_SECONDS * RATE)
	var drone := PackedFloat32Array()
	var wind := PackedFloat32Array()
	var whine := PackedFloat32Array()
	drone.resize(n)
	wind.resize(n)
	whine.resize(n)

	var dinc := TAU * AMB_DRONE / RATE
	var winc := TAU * AMB_WHINE / RATE
	var dphase := 0.0
	var wphase := 0.0

	# BiquadFilterNode's Q defaults to 1 and startDrone never sets it, so the
	# drone's low-pass takes 1 and only the wind's band-pass carries the .6 the
	# ancestor spells out (html:551).
	var f_lo := 2.0 * sin(PI * 180.0 / RATE)
	var d_lo := 1.0
	var lo_l := 0.0
	var lo_b := 0.0
	var f_wd := 2.0 * sin(PI * AMB_WIND / RATE)
	var d_wd := 1.0 / 0.6
	var wd_l := 0.0
	var wd_b := 0.0
	# The whine's band-pass sits on its own fundamental, which is what turns a
	# sawtooth into a thin resonant tone rather than a buzz. Q 1.4 is low enough
	# that the resonant gain cannot run away with the headroom AMB_SCALE assumes.
	var f_wh := 2.0 * sin(PI * AMB_WHINE / RATE)
	var d_wh := 1.0 / 1.4
	var wh_l := 0.0
	var wh_b := 0.0

	var edge := maxi(1, int(AMB_EDGE * RATE))
	for i in n:
		# One slow gust across the whole loop, folded into the stems so the tier
		# mixes below stay a straight weighted sum.
		var gust := AMB_FLOOR + (1.0 - AMB_FLOOR) * (0.5 - 0.5 * cos(TAU * float(i) / float(n)))
		var head := mini(i, n - 1 - i)
		if head < edge:
			gust *= float(head) / float(edge)

		var saw := dphase * SAW_K - 1.0
		lo_l += f_lo * lo_b
		var hi_lo := saw - lo_l - d_lo * lo_b
		lo_b += f_lo * hi_lo
		drone[i] = lo_l * gust

		var hiss := _rng.randf_range(-1.0, 1.0)
		wd_l += f_wd * wd_b
		var hi_wd := hiss - wd_l - d_wd * wd_b
		wd_b += f_wd * hi_wd
		wind[i] = wd_b * gust

		var saw2 := wphase * SAW_K - 1.0
		wh_l += f_wh * wh_b
		var hi_wh := saw2 - wh_l - d_wh * wh_b
		wh_b += f_wh * hi_wh
		whine[i] = wh_b * gust

		dphase += dinc
		if dphase >= TAU:
			dphase -= TAU
		wphase += winc
		if wphase >= TAU:
			wphase -= TAU

	_amb_streams.clear()
	var out := PackedFloat32Array()
	out.resize(n)
	for t in AMB_GAIN.size():
		# A const Array subscripts to Variant, so every gain is converted rather
		# than inferred — inference cannot see through the two levels of indexing.
		var g: Array = AMB_GAIN[t]
		var gd := float(g[0]) * AMB_SCALE
		var gw := float(g[1]) * AMB_SCALE
		var gh := float(g[2]) * AMB_SCALE
		for i in n:
			out[i] = drone[i] * gd + wind[i] * gw + whine[i] * gh
		var w := _bake(out)
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n - 1
		_amb_streams.append(w)


func _build(id: String) -> AudioStreamWAV:
	match id:
		"hit": return _noise_hit(0.09, 46.0, 0.0, 0.5)
		"headshot": return _noise_hit(0.16, 26.0, 190.0, 0.7)
		"death": return _noise_hit(0.42, 8.0, 90.0, 0.45)
		"melee": return _noise_hit(0.12, 30.0, 140.0, 0.55)
		"board": return _noise_hit(0.14, 24.0, 220.0, 0.5)
		"buy": return _tone(660.0, 0.20, 12.0, 0.35, 2.0)
		"deny": return _tone(180.0, 0.22, 14.0, 0.35, 0.6)
		"reload_in": return _noise_hit(0.07, 55.0, 320.0, 0.4)
		"reload_out": return _noise_hit(0.06, 60.0, 240.0, 0.35)
		# The ceremony cues. Each is several voices over one buffer rather than a
		# single _tone, which is what the ancestor's roundStart/powerOn are.
		"round": return _round_sting()
		"hound_round": return _hound_sting()
		"power_on": return _power_on()
		"powerup": return _tone(880.0, 0.50, 5.0, 0.34, 1.8)
		"hurt": return _noise_hit(0.22, 16.0, 70.0, 0.5)
		"box": return _tone(300.0, 0.30, 8.0, 0.3, 2.4)
		"empty": return _noise_hit(0.05, 70.0, 900.0, 0.25)
		"bark": return _voice(220.0, 110.0, 0.16, 900.0, 1.2, 0.6)
	# Palette-pitched groans: three palettes read as three different throats.
	if id.begins_with("groan"):
		var pal := float(id.substr(5).to_int()) * 0.5
		var base := 58.0 + pal * 36.0
		return _voice(base, base * 0.62, 0.85, 300.0 + pal * 260.0, 2.4, 0.5)
	return _noise_hit(0.08, 40.0, 0.0, 0.3)


## Returns one buffer for an id, picking among baked variants where they exist.
func _stream(id: String) -> AudioStreamWAV:
	var count: int = VARIANTS.get(id, 1)
	var pick := 0 if count == 1 else _rng.randi() % count
	var key := id if count == 1 else "%s#%d" % [id, pick]
	if _cache.has(key):
		return _cache[key]
	var s := _build(id)
	_cache[key] = s
	return s


func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	var p2 := _players[_next]
	_next = (_next + 1) % POOL
	return p2


## Oldest-wins stealing: a horde should drop its stalest voice, not refuse a new
## one. Idle players are preferred so a quiet moment never steals.
func _free_player_3d() -> AudioStreamPlayer3D:
	var oldest: AudioStreamPlayer3D = null
	var oldest_pos := -1.0
	for p in _players_3d:
		if not p.playing:
			return p
		var pos := p.get_playback_position()
		if pos > oldest_pos:
			oldest_pos = pos
			oldest = p
	return oldest


func play(id: String, volume_db := 0.0, pitch := 1.0) -> void:
	var p := _free_player()
	p.stream = _stream(id)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Positional one-shot. This is the call that makes the horde perceivable —
## everything used to arrive dead-centre at the same volume regardless of where
## it happened.
func play_at(id: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, max_dist := MAX_DIST) -> void:
	var p := _free_player_3d()
	if p == null:
		return
	p.stream = _stream(id)
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.play()


func play_shot(key: String, freq: float, thump: float, body: float) -> void:
	var id := "shot_" + key
	if not _cache.has(id):
		_cache[id] = _gunshot(freq, thump, body)
	var p := _free_player()
	p.stream = _cache[id]
	# Loudness now tracks the weapon's own body figure, so the Thundergun
	# (body 2.0) genuinely dwarfs the M1911 (0.7). Every shot used to be -4 dB.
	p.volume_db = -9.0 + 5.0 * body
	p.pitch_scale = 1.0
	p.play()


# --- the round ceremony -------------------------------------------------------


## The whole moment, in the order it has to happen: cut the bed, hold
## ROUND_SILENCE seconds of nothing, then drop the toll into it and bring the new
## tier up underneath. main.gd calls this instead of playing "round" directly, and
## emits `round_changed` first so the title card is already up during the beat.
func round_ceremony(round_no: int, dogs: bool) -> void:
	_ceremony += 1
	_amb_stop()
	# A timer callback rather than an `await`, so the caller is never handed a
	# coroutine it has to know about: the beat is entirely this file's business.
	get_tree().create_timer(ROUND_SILENCE).timeout.connect(
		_ceremony_land.bind(_ceremony, round_no, dogs))


## The far side of the beat.
func _ceremony_land(token: int, round_no: int, dogs: bool) -> void:
	# The latest ceremony wins. A restart, a death or a second round change inside
	# the beat has already bumped the counter, and this call is stale.
	if token != _ceremony:
		return
	_amb_tier = _tier_for(round_no)
	# Paused through the beat: the tier still advances, because the run did, but
	# nothing is dropped onto a menu. _on_state brings the bed back on resume.
	if Game.state != Game.STATE_PLAY:
		return
	play("hound_round" if dogs else "round", ROUND_DB)
	_amb_play()


## AMB_BANDS holds the upper round of every tier but the last, so the answer is
## always a valid index into the three baked streams.
func _tier_for(round_no: int) -> int:
	for i in AMB_BANDS.size():
		if round_no <= int(AMB_BANDS[i]):
			return i
	return AMB_BANDS.size()


func _amb_play() -> void:
	if _amb_tier < 0 or _amb_tier >= _amb_streams.size():
		return
	_amb_on = true
	_amb.stream = _amb_streams[_amb_tier]
	_amb.play()


func _amb_stop() -> void:
	# Cleared before the stop, not after: on a platform where stop() emits
	# `finished`, the watchdog below must already see that the bed is meant to be
	# down or it restarts it inside the silence beat.
	_amb_on = false
	_amb.stop()


## The bed is a LOOP_FORWARD sample, which the desktop mixer honours directly and
## which the web sample player implements by restarting the buffer from the
## `ended` event — so on both of the platforms this ships to, `finished` never
## arrives while the bed is running. This is the net for a third: a bed that stops
## after one pass is a worse failure than a bed with a seam.
func _amb_finished() -> void:
	if _amb_on:
		_amb.play()


## Title and game over end the run's escalation; pause only suspends it, so the
## tier survives a pause and the bed comes straight back on the resume click.
func _on_state(s: String) -> void:
	match s:
		"play":
			_amb_play()
		"pause":
			_amb_stop()
		_:
			# Also cancels a ceremony still inside its beat, so a restart cannot
			# land the previous run's toll over the title card.
			_ceremony += 1
			_amb_tier = -1
			_amb_stop()
