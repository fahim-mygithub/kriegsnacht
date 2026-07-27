extends Node

## The browser build synthesised every sound through the Web Audio API from
## oscillators plus one shared noise buffer — no samples anywhere. Godot has no
## direct Web Audio equivalent, so the same synthesis is done once at startup
## and baked into AudioStreamWAV buffers, which are then played as normal.

const RATE := 22050
const POOL := 12

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x5EED
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)


func _bake(samples: PackedFloat32Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
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


func _stream(id: String) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	var s: AudioStreamWAV
	match id:
		"hit": s = _noise_hit(0.09, 46.0, 0.0, 0.5)
		"headshot": s = _noise_hit(0.16, 26.0, 190.0, 0.7)
		"death": s = _noise_hit(0.42, 8.0, 90.0, 0.45)
		"melee": s = _noise_hit(0.12, 30.0, 140.0, 0.55)
		"board": s = _noise_hit(0.14, 24.0, 220.0, 0.5)
		"buy": s = _tone(660.0, 0.20, 12.0, 0.35, 2.0)
		"deny": s = _tone(180.0, 0.22, 14.0, 0.35, 0.6)
		"reload_in": s = _noise_hit(0.07, 55.0, 320.0, 0.4)
		"reload_out": s = _noise_hit(0.06, 60.0, 240.0, 0.35)
		"round": s = _tone(120.0, 1.30, 2.4, 0.42, 1.6)
		"powerup": s = _tone(880.0, 0.50, 5.0, 0.34, 1.8)
		"hurt": s = _noise_hit(0.22, 16.0, 70.0, 0.5)
		"box": s = _tone(300.0, 0.30, 8.0, 0.3, 2.4)
		"empty": s = _noise_hit(0.05, 70.0, 900.0, 0.25)
		_: s = _noise_hit(0.08, 40.0, 0.0, 0.3)
	_cache[id] = s
	return s


func play(id: String, volume_db := 0.0, pitch := 1.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = _stream(id)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Weapon shots are cached per weapon key so each gun keeps its own voice.
func play_shot(key: String, freq: float, thump: float, body: float) -> void:
	var id := "shot_" + key
	if not _cache.has(id):
		_cache[id] = _gunshot(freq, thump, body)
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = _cache[id]
	p.volume_db = -4.0
	p.pitch_scale = _rng.randf_range(0.96, 1.04)
	p.play()
