extends Node

## Self-contained frame-rate benchmark.
##
## Only runs in a build exported with the `perfprobe` custom feature, so it can
## never activate in the shipped web build. It exists because the browser
## automation tab reports visibilityState=hidden, which throttles
## requestAnimationFrame — any FPS sampled from JS there would be fiction.
## Measuring inside the engine and POSTing the result sidesteps that entirely.

const STAGES := [0, 6, 12, 18, 24]   # live zombies per stage
const SETTLE := 1.5                   # seconds to let a stage stabilise
const MEASURE := 5.0                  # seconds of frame sampling per stage
const ENDPOINT := "http://127.0.0.1:8970/result"

var _main: Node3D
var _stage := -1
var _t := 0.0
var _measuring := false
var _deltas: Array[float] = []
var _mon := {}
var _mon_n := 0
var _results := []
var _boot_ms := 0
var _rng := RandomNumberGenerator.new()
var _http: HTTPRequest


## Registered as an autoload only by the perf export, so nothing in the shipped
## game references this file at all. Waits for Main to exist, then drives it.
func _ready() -> void:
	_await_main.call_deferred()


func _await_main() -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("start_game"):
		await get_tree().process_frame
		_await_main.call_deferred()
		return
	begin(scene)


func begin(main: Node3D) -> void:
	_main = main
	_boot_ms = Time.get_ticks_msec()
	_rng.seed = 12345
	_http = HTTPRequest.new()
	add_child(_http)
	# Beacon immediately so a silent failure is distinguishable from a
	# probe that never started.
	_post({"event": "started", "boot_ms": _boot_ms,
		"adapter": RenderingServer.get_video_adapter_name()})
	_main.start_game()
	# Freeze the round loop so only the stage's own zombies are alive.
	_main._to_spawn = 0
	_main._intermission = true
	_main._round_timer = 99999.0
	_next_stage()


func _next_stage() -> void:
	_stage += 1
	if _stage >= STAGES.size():
		_finish()
		return
	_clear()
	_spawn(STAGES[_stage])
	_t = 0.0
	_measuring = false
	_deltas.clear()
	_mon.clear()
	_mon_n = 0


func _clear() -> void:
	for z in get_tree().get_nodes_in_group("zombies"):
		z.free()
	_main._alive.clear()


func _spawn(n: int) -> void:
	# _main is a plain Node3D here, so its members come back untyped —
	# annotate explicitly or inference fails at compile time.
	var p: Vector3 = _main.player.global_position
	var here := Vector2(p.x, p.z)
	var placed := 0
	var tries := 0
	while placed < n and tries < 4000:
		tries += 1
		var x := _rng.randi_range(3, 14)
		var y := _rng.randi_range(3, 13)
		if _main.map.is_blocked(x, y):
			continue
		var pos := Vector2(x + 0.5, y + 0.5)
		if pos.distance_to(here) < 3.0:
			continue
		var z := Zombie.create("zombie", placed % 3, 10, false)
		z.flow = _main.flow
		z.target = _main.player
		z.add_to_group("zombies")
		_main.add_child(z)
		z.global_position = Vector3(pos.x, 0.0, pos.y)
		_main._alive.append(z)
		placed += 1


func _process(dt: float) -> void:
	if _main == null or _stage >= STAGES.size():
		return
	# Keep the subject alive; dying mid-run would end the measurement.
	_main.player.hp = 1e9

	_t += dt
	if not _measuring:
		if _t >= SETTLE:
			_measuring = true
			_t = 0.0
		return

	_deltas.append(dt * 1000.0)
	_accum()
	if _t >= MEASURE:
		_record()
		_next_stage()


const MONITORS := {
	"draw_calls": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
	"primitives": Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
	"video_mem_mb": Performance.RENDER_VIDEO_MEM_USED,
	"static_mem_mb": Performance.MEMORY_STATIC,
	"process_ms": Performance.TIME_PROCESS,
	"physics_ms": Performance.TIME_PHYSICS_PROCESS,
	"nodes": Performance.OBJECT_NODE_COUNT,
}


func _accum() -> void:
	_mon_n += 1
	for key in MONITORS:
		_mon[key] = _mon.get(key, 0.0) + Performance.get_monitor(MONITORS[key])


## One HTTPRequest per message — a single node can only carry one in flight.
func _post(obj: Dictionary) -> void:
	var body := JSON.stringify(obj)
	print("PERF: ", body)
	var r := HTTPRequest.new()
	add_child(r)
	r.request(ENDPOINT, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)


func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	var i := clampi(int(sorted.size() * p), 0, sorted.size() - 1)
	return snappedf(sorted[i], 0.01)


func _record() -> void:
	var d := _deltas.duplicate()
	d.sort()
	var sum := 0.0
	for v in d:
		sum += v
	var mean: float = sum / maxf(1.0, d.size())
	var row := {
		"zombies": STAGES[_stage],
		"frames": d.size(),
		"avg_fps": snappedf(1000.0 / maxf(0.001, mean), 0.1),
		"mean_ms": snappedf(mean, 0.01),
		"median_ms": _pct(d, 0.50),
		"p95_ms": _pct(d, 0.95),
		"p99_ms": _pct(d, 0.99),
		"worst_ms": snappedf(d[d.size() - 1], 0.01),
	}
	for k in _mon:
		var avg: float = _mon[k] / maxf(1.0, _mon_n)
		if k.ends_with("_mb"):
			row[k] = snappedf(avg / 1048576.0, 0.1)
		elif k.ends_with("_ms"):
			row[k] = snappedf(avg * 1000.0, 0.02)
		else:
			row[k] = int(avg)
	_results.append(row)
	_post({"event": "stage", "data": row})


func _finish() -> void:
	_clear()
	var vp := get_viewport().get_visible_rect().size
	var payload := {
		"env": {
			"platform": OS.get_name(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"api": RenderingServer.get_video_adapter_api_version(),
			"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
			"threads": OS.get_processor_count(),
			"viewport": "%dx%d" % [vp.x, vp.y],
			"boot_to_first_frame_ms": _boot_ms,
			"max_fps_setting": Engine.max_fps,
		},
		"stages": _results,
	}
	payload["event"] = "final"
	_post(payload)
	_main = null
