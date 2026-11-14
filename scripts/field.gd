extends Node3D
## The field: tile floor + perimeter walls. Game elements are placeholders until the
## BIOBUZZ manual / field drawings are available.

var size := 3.5875
var wall_height := 0.3048
var goal_area: Area3D

func _ready() -> void:
	size = Config.inches("field.size_in", 141.24)
	wall_height = Config.inches("field.wall_height_in", 12.0)
	var tile := Config.inches("field.tile_in", 23.54)

	# Floor (static, so pollen balls can roll on it later).
	var floor_body := StaticBody3D.new()
	add_child(floor_body)
	var fs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(size + 2.0, 0.1, size + 2.0)
	fs.shape = fbox
	fs.position.y = -0.05
	floor_body.add_child(fs)
	_mesh(Vector3(size, 0.02, size), Vector3(0, -0.01, 0), Color(0.36, 0.37, 0.4))
	_mesh(Vector3(size + 6.0, 0.02, size + 6.0), Vector3(0, -0.03, 0), Color(0.2, 0.21, 0.23))

	# Tile seams.
	var n := int(round(size / tile))
	for i in range(1, n):
		var o := -size / 2.0 + i * size / n
		_mesh(Vector3(0.006, 0.002, size), Vector3(o, 0.001, 0), Color(0.17, 0.18, 0.2))
		_mesh(Vector3(size, 0.002, 0.006), Vector3(0, 0.001, o), Color(0.17, 0.18, 0.2))

	# Walls: clear panels with a dark top rail.
	var t := 0.025
	var h := size / 2.0 + t / 2.0
	_wall(Vector3(size + 2 * t, wall_height, t), Vector3(0, wall_height / 2.0, -h))
	_wall(Vector3(size + 2 * t, wall_height, t), Vector3(0, wall_height / 2.0, h))
	_wall(Vector3(t, wall_height, size), Vector3(-h, wall_height / 2.0, 0))
	_wall(Vector3(t, wall_height, size), Vector3(h, wall_height / 2.0, 0))
	_build_placeholder_goal()

## Invented stand-in for a scoring goal: an open-top bin. Replace once the field CAD arrives.
func _build_placeholder_goal() -> void:
	var g = Config.value("field.placeholder_goal", null)
	if not g is Dictionary:
		return
	var sz: float = float(g.get("size_in", 22.0)) * Config.IN
	var h: float = float(g.get("height_in", 16.0)) * Config.IN
	var c := Vector3(float(g.get("x_in", 0.0)) * Config.IN, 0, -float(g.get("y_in", 0.0)) * Config.IN)
	var t := 0.012
	var body := StaticBody3D.new()
	body.position = c
	add_child(body)
	for side in [[Vector3(sz, h, t), Vector3(0, h / 2, -sz / 2)], [Vector3(sz, h, t), Vector3(0, h / 2, sz / 2)],
			[Vector3(t, h, sz), Vector3(-sz / 2, h / 2, 0)], [Vector3(t, h, sz), Vector3(sz / 2, h / 2, 0)]]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = side[0]
		cs.shape = box
		cs.position = side[1]
		body.add_child(cs)
		_mesh(side[0], side[1], Color(0.3, 0.9, 0.45, 0.45), body)
	goal_area = Area3D.new()
	goal_area.collision_layer = 0
	goal_area.collision_mask = 2
	var acs := CollisionShape3D.new()
	var abox := BoxShape3D.new()
	abox.size = Vector3(sz - 2 * t, h * 0.6, sz - 2 * t)
	acs.shape = abox
	goal_area.position = c + Vector3(0, h * 0.3, 0)
	goal_area.add_child(acs)
	add_child(goal_area)

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _mesh(sz: Vector3, pos: Vector3, color: Color, parent: Node = self) -> void:
	var mesh := BoxMesh.new()
	mesh.size = sz
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	parent.add_child(mi)

func _wall(sz: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Collide taller than the wall looks, so nothing gets pushed over it.
	box.size = Vector3(sz.x, sz.y + 1.0, sz.z)
	cs.shape = box
	cs.position.y = 0.5
	body.add_child(cs)
	_mesh(sz, Vector3.ZERO, Color(0.8, 0.9, 1.0, 0.22), body)
	var rail := Vector3(sz.x + 0.01, 0.03, sz.z + 0.01)
	_mesh(rail, Vector3(0, sz.y / 2.0, 0), Color(0.1, 0.1, 0.12), body)
