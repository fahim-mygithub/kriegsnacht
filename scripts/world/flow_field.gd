class_name FlowField
extends RefCounted

## BFS flow field over the tile grid, kept from the browser build.
##
## Godot ships NavigationServer3D, but a flow field is still the better fit
## here: up to 24 agents all converge on one target, so a single breadth-first
## sweep solves every agent's path at once and costs less than 24 individual
## NavigationAgent3D queries. It is only re-solved when the player changes tile.

var map: MapData
var dist := PackedInt32Array()
var _origin := Vector2i(-999, -999)


func _init(m: MapData) -> void:
	map = m
	dist.resize(MapData.MAPW * MapData.MAPH)


## Re-solve only when the target moved to a new tile.
func update(target: Vector2) -> void:
	var tt := Vector2i(int(target.x), int(target.y))
	if tt == _origin:
		return
	_origin = tt
	solve(tt)


func solve(target: Vector2i) -> void:
	dist.fill(-1)
	if map.is_blocked(target.x, target.y):
		return
	var start := MapData.ix(target.x, target.y)
	dist[start] = 0
	var q: Array[int] = [start]
	var head := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		var x := i % MapData.MAPW
		var y := i / MapData.MAPW
		var nd: int = dist[i] + 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + d.x
			var ny := y + d.y
			if map.is_blocked(nx, ny):
				continue
			var ni := MapData.ix(nx, ny)
			if dist[ni] >= 0:
				continue
			dist[ni] = nd
			q.append(ni)


## Downhill step from a world position, as a unit direction on the XZ plane.
func direction_at(pos: Vector2) -> Vector2:
	var x := int(pos.x)
	var y := int(pos.y)
	if map.is_blocked(x, y):
		return Vector2.ZERO
	var here: int = dist[MapData.ix(x, y)]
	if here <= 0:
		return Vector2.ZERO
	var best := here
	var best_dir := Vector2.ZERO
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var nx := x + d.x
		var ny := y + d.y
		if map.is_blocked(nx, ny):
			continue
		# Do not cut a diagonal through a corner.
		if d.x != 0 and d.y != 0:
			if map.is_blocked(x + d.x, y) or map.is_blocked(x, y + d.y):
				continue
		var nd: int = dist[MapData.ix(nx, ny)]
		if nd < 0:
			continue
		if nd < best:
			best = nd
			best_dir = Vector2(d.x, d.y)
	return best_dir.normalized()


func reachable(pos: Vector2) -> bool:
	var x := int(pos.x)
	var y := int(pos.y)
	if x < 0 or y < 0 or x >= MapData.MAPW or y >= MapData.MAPH:
		return false
	return dist[MapData.ix(x, y)] >= 0
