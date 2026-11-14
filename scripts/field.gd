extends Node3D
## The BIOBUZZ field: tile floor, walls, and the game elements from data/field_layout.json
## (zones, flowers, hive frame, hive cells) plus the starting pollen from data/game_elements.json.
## The data files give the floor plan; heights and behaviour marked GUESS come from robot_config.json.

var size := 3.5875
var wall_height := 0.3048
var layout: Dictionary = {}
var elements: Dictionary = {}
## Each flower: { pos: Vector3, inward: Vector3, capacity: int, count: int, timer: float, label: Label3D }
var flowers: Array = []
## Each hive: { alliance, body, up_side ("top"/"bottom"), start_side, angle, areas: {top, bottom} }
var hives: Array = []
## Pollen scored per alliance (counted when that alliance's hive tips).
var score := {"red": 0, "blue": 0}
var tips := {"red": 0, "blue": 0}

var _tip_n := 8
var _tip_angle := 0.52
var _tip_time := 0.8

var _k := 1.0            # metres per data inch (data is on a nominal 144 in field)
var _flower_radius := 0.084
var _release_interval := 0.35
var _lever_reach := 0.06

func _ready() -> void:
	size = Config.inches("field.size_in", 141.24)
	wall_height = Config.inches("field.wall_height_in", 12.0)
	_k = size / 144.0
	layout = _load_json("res://data/field_layout.json")
	elements = _load_json("res://data/game_elements.json")
	_build_floor_and_walls()
	if not layout.is_empty():
		_build_zones()
		_build_flowers()
		_build_hives()

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Field: %s not found" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

## Data coordinates (inches, origin top-left, audience at the bottom) -> simulator world.
func to_world(x_in: float, y_in: float, height := 0.0) -> Vector3:
	return Vector3((x_in - 72.0) * _k, height, (y_in - 72.0) * _k)

func _build_floor_and_walls() -> void:
	var tile := Config.inches("field.tile_in", 23.54)
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
	var n := int(round(size / tile))
	for i in range(1, n):
		var o := -size / 2.0 + i * size / n
		_mesh(Vector3(0.006, 0.002, size), Vector3(o, 0.001, 0), Color(0.17, 0.18, 0.2))
		_mesh(Vector3(size, 0.002, 0.006), Vector3(0, 0.001, o), Color(0.17, 0.18, 0.2))
	var t := 0.025
	var h := size / 2.0 + t / 2.0
	_wall(Vector3(size + 2 * t, wall_height, t), Vector3(0, wall_height / 2.0, -h), Color(0.8, 0.9, 1.0, 0.22))
	_wall(Vector3(size + 2 * t, wall_height, t), Vector3(0, wall_height / 2.0, h), Color(0.8, 0.9, 1.0, 0.22))
	# Alliance walls: red on the left (-x), blue on the right (+x).
	_wall(Vector3(t, wall_height, size), Vector3(-h, wall_height / 2.0, 0), Color(1.0, 0.45, 0.45, 0.3))
	_wall(Vector3(t, wall_height, size), Vector3(h, wall_height / 2.0, 0), Color(0.45, 0.55, 1.0, 0.3))

func _build_zones() -> void:
	for z in layout.get("zones", []):
		var r: Array = z["rect"]
		var c := Color(str(z.get("color", "#ffffff")))
		var centre := to_world(r[0] + r[2] / 2.0, r[1] + r[3] / 2.0, 0.002)
		var w: float = r[2] * _k
		var d: float = r[3] * _k
		if z.get("filled", false):
			_mesh(Vector3(w, 0.003, d), centre, c)
		else:
			var tape := 0.025
			_mesh(Vector3(w, 0.003, tape), centre + Vector3(0, 0, -d / 2), c)
			_mesh(Vector3(w, 0.003, tape), centre + Vector3(0, 0, d / 2), c)
			_mesh(Vector3(tape, 0.003, d), centre + Vector3(-w / 2, 0, 0), c)
			_mesh(Vector3(tape, 0.003, d), centre + Vector3(w / 2, 0, 0), c)

func _build_flowers() -> void:
	_flower_radius = float(layout.get("flower_radius_in", 3.3)) * Config.IN
	_release_interval = Config.num("field.flower_release_interval_s", 0.35)
	_lever_reach = Config.inches("field.flower_lever_reach_in", 2.5)
	var height := Config.inches("field.flower_height_in", 17.5)  # GUESS
	var inward_of := {"top": Vector3(0, 0, 1), "bottom": Vector3(0, 0, -1), "left": Vector3(1, 0, 0), "right": Vector3(-1, 0, 0)}
	for f in layout.get("flowers", []):
		var inward: Vector3 = inward_of.get(str(f.get("wall", "top")), Vector3(0, 0, 1))
		# Stand the flower just inside the wall.
		var pos := to_world(f["x"], f["y"]) + inward * _flower_radius
		var body := StaticBody3D.new()
		body.position = pos + Vector3(0, height / 2.0, 0)
		add_child(body)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = _flower_radius
		cyl.height = height
		cs.shape = cyl
		body.add_child(cs)
		var mesh := CylinderMesh.new()
		mesh.top_radius = _flower_radius
		mesh.bottom_radius = _flower_radius
		mesh.height = height
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mat(Color(0.95, 0.55, 0.85, 0.55))
		body.add_child(mi)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 64
		label.pixel_size = 0.0015
		label.outline_size = 12
		label.position = Vector3(0, height / 2.0 + 0.08, 0)
		body.add_child(label)
		flowers.append({"pos": pos, "inward": inward, "capacity": int(f.get("pollen", 4)), "count": 0, "timer": 0.0, "label": label})

func _build_hives() -> void:
	var bar_h := Config.inches("field.frame_bar_height_in", 1.5)       # GUESS
	_tip_n = int(Config.num("field.hive_tip_pollen", 8))
	_tip_angle = deg_to_rad(Config.num("field.hive_tip_angle_deg", 30.0))
	_tip_time = Config.num("field.hive_tip_time_s", 0.8)
	for b in layout.get("frame_bars", []):
		var r: Array = b["rect"]
		var body := StaticBody3D.new()
		body.position = to_world(r[0] + r[2] / 2.0, r[1] + r[3] / 2.0, bar_h / 2.0)
		add_child(body)
		var sz := Vector3(r[2] * _k, bar_h, r[3] * _k)
		_add_box(body, sz, Vector3.ZERO, Color(0.75, 0.76, 0.8))
	var pivot_h := Config.inches("field.hive_pivot_height_in", 15.0)   # GUESS
	var off: float = float(layout.get("cell_offset_in", 15.44)) * _k
	var model = load("res://models/field/red_hive.glb") if ResourceLoader.exists("res://models/field/red_hive.glb") else null
	for h in layout.get("hives", []):
		var alliance := str(h["alliance"])
		# The whole seesaw is one moving body, pivoting about its centre (the model's origin).
		var body := AnimatableBody3D.new()
		body.collision_layer = 4   # pollen collide with it; the robot is kept out by the box below
		body.collision_mask = 0
		body.position = to_world(h["x"], 72.0, pivot_h)
		add_child(body)
		if model is PackedScene:
			var inst: Node3D = model.instantiate()
			body.add_child(inst)
			for mi in inst.find_children("*", "MeshInstance3D", true, false):
				var shape: ConcavePolygonShape3D = mi.mesh.create_trimesh_shape()
				shape.backface_collision = true
				var cs := CollisionShape3D.new()
				cs.shape = shape
				body.add_child(cs)
				cs.global_transform = mi.global_transform
				if alliance == "blue":
					_recolor_blue(mi)
		var areas := {}
		for side in ["top", "bottom"]:
			var area := Area3D.new()
			area.collision_layer = 0
			area.collision_mask = 2
			var acs := CollisionShape3D.new()
			var abox := BoxShape3D.new()
			abox.size = Vector3(18.0, 11.0, 9.5) * Config.IN
			acs.shape = abox
			area.add_child(acs)
			area.position = Vector3(0, 5.6 * Config.IN, (-off if side == "top" else off))
			body.add_child(area)
			areas[side] = area
		# Robots cannot drive through the hive.
		var keep_out := StaticBody3D.new()
		keep_out.collision_layer = 8
		keep_out.collision_mask = 0
		var kcs := CollisionShape3D.new()
		var kbox := BoxShape3D.new()
		kbox.size = Vector3(21.0 * Config.IN, 1.0, 43.0 * Config.IN)
		kcs.shape = kbox
		keep_out.add_child(kcs)
		keep_out.position = to_world(h["x"], 72.0, 0.5)
		add_child(keep_out)
		var hive := {"alliance": alliance, "body": body, "start_side": str(h.get("up_cell", "top")), "up_side": "", "angle": 0.0, "areas": areas}
		hives.append(hive)
		_set_hive(hive, hive["start_side"], true)

func _recolor_blue(mi: MeshInstance3D) -> void:
	for i in mi.mesh.get_surface_count():
		var m = mi.mesh.surface_get_material(i)
		if m is StandardMaterial3D and m.albedo_color.r > 0.6 and m.albedo_color.g < 0.4:
			var m2: StandardMaterial3D = m.duplicate()
			m2.albedo_color = Color(0.2, 0.35, 0.9)
			mi.set_surface_override_material(i, m2)

## Tilt so the given cell is the raised one. A negative angle about X lifts the +z ("bottom", audience) end.
func _target_angle(side: String) -> float:
	return -_tip_angle if side == "bottom" else _tip_angle

func _set_hive(hive: Dictionary, side: String, snap := false) -> void:
	hive["up_side"] = side
	if snap:
		hive["angle"] = _target_angle(side)
		hive["body"].rotation.x = hive["angle"]

## How many balls are in the given alliance's raised (up = true) or lowered cell right now.
func cell_count(alliance: String, up: bool) -> int:
	for h in hives:
		if h["alliance"] == alliance:
			var side: String = h["up_side"]
			if not up:
				side = "top" if side == "bottom" else "bottom"
			return h["areas"][side].get_overlapping_bodies().size()
	return 0

func hive_of(alliance: String) -> Dictionary:
	for h in hives:
		if h["alliance"] == alliance:
			return h
	return {}

## The hive rule: when the raised cell holds enough pollen the seesaw tips. The pollen inside at that
## moment are scored; they then roll out of the lowered cell and the other cell becomes the raised one.
func update_hives(dt: float) -> void:
	for h in hives:
		var goal := _target_angle(h["up_side"])
		if not is_equal_approx(h["angle"], goal):
			h["angle"] = move_toward(h["angle"], goal, 2.0 * _tip_angle / maxf(_tip_time, 0.05) * dt)
			h["body"].rotation.x = h["angle"]
			continue
		var n: int = h["areas"][h["up_side"]].get_overlapping_bodies().size()
		if n >= _tip_n:
			score[h["alliance"]] += n
			tips[h["alliance"]] += 1
			_set_hive(h, "top" if h["up_side"] == "bottom" else "bottom")

## Put every game piece back where a match starts.
func reset_elements(pollen) -> void:
	pollen.clear()
	score = {"red": 0, "blue": 0}
	tips = {"red": 0, "blue": 0}
	for h in hives:
		_set_hive(h, h["start_side"], true)
	for f in flowers:
		f["count"] = f["capacity"]
		f["timer"] = 0.0
	for e in elements.get("elements", []):
		if str(e.get("type", "")) == "pollen":
			pollen.spawn_ball(to_world(e["x"], e["y"], pollen.radius + 0.002))
	_refresh_labels()

func _refresh_labels() -> void:
	for f in flowers:
		f["label"].text = str(f["count"])

## GUESS at the mechanic: a deployed lever held against a flower makes it drop its pollen, one at a time.
func update_flowers(robot, pollen, dt: float) -> void:
	var bars: Array = robot.deployed_lever_bars()
	for f in flowers:
		f["timer"] = maxf(f["timer"] - dt, 0.0)
		if f["count"] <= 0 or f["timer"] > 0.0:
			continue
		var p: Vector3 = f["pos"]
		for bar in bars:
			var a: Vector3 = bar[0]
			var b: Vector3 = bar[1]
			var a2 := Vector2(a.x, a.z)
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var tt := clampf((Vector2(p.x, p.z) - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			if (a2 + ab * tt).distance_to(Vector2(p.x, p.z)) <= _flower_radius + _lever_reach:
				f["count"] -= 1
				f["timer"] = _release_interval
				var inward: Vector3 = f["inward"]
				pollen.spawn_ball(p + inward * (_flower_radius + pollen.radius + 0.02) + Vector3(0, 0.25, 0), inward * 0.4)
				_refresh_labels()
				break

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

func _add_box(body: StaticBody3D, sz: Vector3, pos: Vector3, color: Color) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = sz
	cs.shape = box
	cs.position = pos
	body.add_child(cs)
	_mesh(sz, pos, color, body)

func _wall(sz: Vector3, pos: Vector3, color: Color) -> void:
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
	_mesh(sz, Vector3.ZERO, color, body)
	_mesh(Vector3(sz.x + 0.01, 0.03, sz.z + 0.01), Vector3(0, sz.y / 2.0, 0), Color(0.1, 0.1, 0.12), body)
