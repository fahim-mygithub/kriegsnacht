class_name WorldBuilder
extends Node3D

## Turns the 42x34 grid into real 3D geometry.
##
## This is the part of the browser build that does NOT port: the software
## raycaster is gone entirely. What survives is the data it was reading — the
## same grid, the same per-tile texture assignment, the same metre scale.
##
## One surface is built per texture so the whole level is a handful of draw
## calls. Per-tile brightness jitter is baked into vertex colours, reproducing
## the `tileShade` table that stopped a 64px texture reading as wallpaper.

const TEX_DIR := "res://assets/textures/"

var map: MapData
var _materials := {}
var _door_nodes := {}
var _window_nodes := {}


func build(m: MapData) -> void:
	map = m
	_build_static()
	_build_doors()
	_build_windows()


func _material(tex_name: String) -> StandardMaterial3D:
	if _materials.has(tex_name):
		return _materials[tex_name]
	var mat := StandardMaterial3D.new()
	var path := TEX_DIR + tex_name + ".png"
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path)
		mat.albedo_texture = t
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.texture_repeat = true
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Faces are single-sided by construction; disabling culling keeps a wrong
	# winding from ever producing an invisible wall.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[tex_name] = mat
	return mat


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, shade: float) -> void:
	var col := Color(shade, shade, shade)
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var v := [a, b, c, d]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for k in tri:
			st.set_normal(n)
			st.set_color(col)
			st.set_uv(uv[k])
			st.add_vertex(v[k])


func _build_static() -> void:
	var wall_st := {}
	var floor_st := {}
	var ceil_st := {}
	var collide := PackedVector3Array()

	var H := MapData.WALL_H

	for y in MapData.MAPH:
		for x in MapData.MAPW:
			var i := MapData.ix(x, y)
			var shade: float = map.tile_shade[i]

			if map.solid[i] == 1:
				# Door and window tiles get their own removable/updatable nodes.
				if map.door_at[i] >= 0 or map.win_at[i] >= 0:
					continue
				var tname: String = MapData.WALL_TEX[map.wtex[i]]
				if not wall_st.has(tname):
					wall_st[tname] = _new_st()
				var st: SurfaceTool = wall_st[tname]
				_emit_wall_faces(st, x, y, shade, collide, H)
			else:
				var fname: String = MapData.FLOOR_TEX[map.ftex[i]]
				if not floor_st.has(fname):
					floor_st[fname] = _new_st()
				_quad(floor_st[fname],
					Vector3(x, 0, y), Vector3(x + 1, 0, y),
					Vector3(x + 1, 0, y + 1), Vector3(x, 0, y + 1),
					Vector3.UP, shade)
				collide.append_array([
					Vector3(x, 0, y), Vector3(x + 1, 0, y), Vector3(x + 1, 0, y + 1),
					Vector3(x, 0, y), Vector3(x + 1, 0, y + 1), Vector3(x, 0, y + 1)])

				var cname: String = MapData.CEIL_TEX[map.ctex[i]]
				if not ceil_st.has(cname):
					ceil_st[cname] = _new_st()
				_quad(ceil_st[cname],
					Vector3(x, H, y + 1), Vector3(x + 1, H, y + 1),
					Vector3(x + 1, H, y), Vector3(x, H, y),
					Vector3.DOWN, shade)

	_commit(wall_st, "Walls")
	_commit(floor_st, "Floors")
	_commit(ceil_st, "Ceilings")

	var body := StaticBody3D.new()
	body.name = "WorldCollision"
	body.collision_layer = 1
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(collide)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Emit only the faces of a solid tile that actually border open space.
func _emit_wall_faces(st: SurfaceTool, x: int, y: int, shade: float,
		collide: PackedVector3Array, H: float) -> void:
	var dirs := [
		{"d": Vector2i(1, 0), "n": Vector3(1, 0, 0)},
		{"d": Vector2i(-1, 0), "n": Vector3(-1, 0, 0)},
		{"d": Vector2i(0, 1), "n": Vector3(0, 0, 1)},
		{"d": Vector2i(0, -1), "n": Vector3(0, 0, -1)},
	]
	for e in dirs:
		var nx: int = x + e.d.x
		var ny: int = y + e.d.y
		if nx < 0 or ny < 0 or nx >= MapData.MAPW or ny >= MapData.MAPH:
			continue
		if map.solid[MapData.ix(nx, ny)] == 1:
			continue
		var a: Vector3
		var b: Vector3
		if e.d == Vector2i(1, 0):
			a = Vector3(x + 1, 0, y); b = Vector3(x + 1, 0, y + 1)
		elif e.d == Vector2i(-1, 0):
			a = Vector3(x, 0, y + 1); b = Vector3(x, 0, y)
		elif e.d == Vector2i(0, 1):
			a = Vector3(x + 1, 0, y + 1); b = Vector3(x, 0, y + 1)
		else:
			a = Vector3(x, 0, y); b = Vector3(x + 1, 0, y)
		var c := b + Vector3(0, H, 0)
		var d := a + Vector3(0, H, 0)
		_quad(st, a, b, c, d, e.n, shade)
		collide.append_array([a, b, c, a, c, d])


func _commit(dict: Dictionary, group_name: String) -> void:
	var root := Node3D.new()
	root.name = group_name
	add_child(root)
	for tname in dict:
		var st: SurfaceTool = dict[tname]
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.name = tname
		mi.mesh = mesh
		mi.material_override = _material(tname)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(mi)


## Doors are their own bodies so a purchase can simply delete them.
func _build_doors() -> void:
	var root := Node3D.new()
	root.name = "Doors"
	add_child(root)
	for di in MapData.DOORS.size():
		var holder := Node3D.new()
		holder.name = "Door%d" % di
		root.add_child(holder)
		var st := _new_st()
		var collide := PackedVector3Array()
		for t in MapData.DOORS[di].tiles:
			var i := MapData.ix(t[0], t[1])
			_emit_wall_faces(st, t[0], t[1], map.tile_shade[i], collide, MapData.WALL_H)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _material(MapData.WALL_TEX[MapData.DOORS[di].tex])
		holder.add_child(mi)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(collide)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		holder.add_child(body)
		_door_nodes[di] = holder


func open_door(di: int) -> void:
	map.open_door(di)
	if _door_nodes.has(di):
		_door_nodes[di].queue_free()
		_door_nodes.erase(di)
	# The tiles are now open floor — patch in the floor and ceiling quads.
	var st_f := {}
	var st_c := {}
	for t in MapData.DOORS[di].tiles:
		var i := MapData.ix(t[0], t[1])
		var shade: float = map.tile_shade[i]
		var fname: String = MapData.FLOOR_TEX[map.ftex[i]]
		var cname: String = MapData.CEIL_TEX[map.ctex[i]]
		if not st_f.has(fname): st_f[fname] = _new_st()
		if not st_c.has(cname): st_c[cname] = _new_st()
		_quad(st_f[fname], Vector3(t[0], 0, t[1]), Vector3(t[0] + 1, 0, t[1]),
			Vector3(t[0] + 1, 0, t[1] + 1), Vector3(t[0], 0, t[1] + 1), Vector3.UP, shade)
		_quad(st_c[cname], Vector3(t[0], MapData.WALL_H, t[1] + 1), Vector3(t[0] + 1, MapData.WALL_H, t[1] + 1),
			Vector3(t[0] + 1, MapData.WALL_H, t[1]), Vector3(t[0], MapData.WALL_H, t[1]), Vector3.DOWN, shade)
	_commit(st_f, "DoorFloor%d" % di)
	_commit(st_c, "DoorCeil%d" % di)


## Window barricades swap texture as their boards come off (7 variants, 0-6).
func _build_windows() -> void:
	var root := Node3D.new()
	root.name = "Windows"
	add_child(root)
	for wi in MapData.WINDOWS.size():
		var w: Dictionary = MapData.WINDOWS[wi]
		var i := MapData.ix(w.x, w.y)
		var st := _new_st()
		var collide := PackedVector3Array()
		_emit_wall_faces(st, w.x, w.y, map.tile_shade[i], collide, MapData.WALL_H)
		var mi := MeshInstance3D.new()
		mi.name = "Window%d" % wi
		mi.mesh = st.commit()
		mi.material_override = _material("window6")
		root.add_child(mi)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(collide)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
		_window_nodes[wi] = mi


func set_window_boards(wi: int, boards: int) -> void:
	map.window_boards[wi] = clampi(boards, 0, 6)
	if _window_nodes.has(wi):
		_window_nodes[wi].material_override = _material("window%d" % map.window_boards[wi])
