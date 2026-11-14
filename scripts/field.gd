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
## Each cell: { name, alliance, up, area: Area3D, body, outer: CollisionShape3D, outer_mesh, sign, state, t }
var cells: Array = []
## Pollen scored per alliance (counted when that alliance's hive tips).
var score := {"red": 0, "blue": 0}
var tips := {"red": 0, "blue": 0}

var _tip_n := 8
var _tip_angle := 0.52
var _tip_time := 0.8
var _tip_reset := 3.0

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
	var wall_h := Config.inches("field.cell_wall_height_in", 5.0)      # GUESS
	var up_h := Config.inches("field.up_cell_floor_height_in", 12.0)   # GUESS
	_tip_n = int(Config.num("field.hive_tip_pollen", 8))
	_tip_angle = deg_to_rad(Config.num("field.hive_tip_angle_deg", 30.0))
	_tip_time = Config.num("field.hive_tip_time_s", 0.8)
	_tip_reset = Config.num("field.hive_reset_after_s", 3.0)
	for b in layout.get("frame_bars", []):
		var r: Array = b["rect"]
		var body := StaticBody3D.new()
		body.position = to_world(r[0] + r[2] / 2.0, r[1] + r[3] / 2.0, bar_h / 2.0)
		add_child(body)
		var sz := Vector3(r[2] * _k, bar_h, r[3] * _k)
		_add_box(body, sz, Vector3.ZERO, Color(0.75, 0.76, 0.8))
	var cs_in: Array = layout.get("cell_size_in", [20, 12.04])
	var off: float = float(layout.get("cell_offset_in", 15.44))
	for h in layout.get("hives", []):
		var col := Color(str(h.get("color", "#ffffff")))
		for side in ["top", "bottom"]:
			var is_up: bool = str(h.get("up_cell", "top")) == side
			var y: float = 72.0 + (-off if side == "top" else off)
			var base := to_world(h["x"], y, up_h if is_up else 0.0)
			var w: float = cs_in[0] * _k
			var d: float = cs_in[1] * _k
			var t := 0.01
			# The raised cell can tip, so it is a body that is allowed to move.
			var body: PhysicsBody3D = AnimatableBody3D.new() if is_up else StaticBody3D.new()
			body.position = base
			add_child(body)
			var c := Color(col.r, col.g, col.b, 0.5)
			# The cell's mouth faces away from the field centre: top cell -> back wall, bottom cell -> audience.
			var out_sign := -1.0 if side == "top" else 1.0
			_add_box(body, Vector3(w, t, d), Vector3(0, t / 2, 0), c)
			_add_box(body, Vector3(w, wall_h, t), Vector3(0, wall_h / 2, -out_sign * d / 2), c)
			_add_box(body, Vector3(w, wall_h, t), Vector3(0, wall_h / 2, out_sign * d / 2), c)
			var outer: CollisionShape3D = body.get_child(body.get_child_count() - 2)
			var outer_mesh: MeshInstance3D = body.get_child(body.get_child_count() - 1)
			_add_box(body, Vector3(t, wall_h, d), Vector3(-w / 2, wall_h / 2, 0), c)
			_add_box(body, Vector3(t, wall_h, d), Vector3(w / 2, wall_h / 2, 0), c)
			if is_up:
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						_mesh(Vector3(0.03, up_h, 0.03), base + Vector3(sx * (w / 2 - 0.015), -up_h / 2, sz * (d / 2 - 0.015)), Color(0.75, 0.76, 0.8))
			var area := Area3D.new()
			area.collision_layer = 0
			area.collision_mask = 2
			var acs := CollisionShape3D.new()
			var abox := BoxShape3D.new()
			abox.size = Vector3(w - 2 * t, wall_h * 0.8, d - 2 * t)
			acs.shape = abox
			area.add_child(acs)
			area.position = base + Vector3(0, wall_h * 0.4 + t, 0)
			add_child(area)
			cells.append({"name": "%s %s" % [h["alliance"], "up" if is_up else "low"], "alliance": str(h["alliance"]), "up": is_up, "area": area,
				"body": body, "outer": outer, "outer_mesh": outer_mesh, "sign": out_sign, "state": "idle", "t": 0.0})

## How many balls are resting in the given alliance's cell.
func cell_count(alliance: String, up: bool) -> int:
	for c in cells:
		if c["alliance"] == alliance and c["up"] == up:
			return c["area"].get_overlapping_bodies().size()
	return 0

## The hive rule: when the raised cell holds enough pollen it tips. The pollen inside at that moment
## are scored; then they spill out of the cell's mouth and the cell comes back up.
func update_hives(dt: float) -> void:
	for c in cells:
		if not c["up"]:
			continue
		match c["state"]:
			"idle":
				var n: int = c["area"].get_overlapping_bodies().size()
				if n >= _tip_n:
					score[c["alliance"]] += n
					tips[c["alliance"]] += 1
					c["state"] = "tipped"
					c["t"] = 0.0
					c["outer"].disabled = true
					c["outer_mesh"].visible = false
			"tipped":
				c["t"] += dt
				c["body"].rotation.x = c["sign"] * _tip_angle * clampf(c["t"] / _tip_time, 0.0, 1.0)
				if c["t"] >= _tip_reset:
					c["state"] = "returning"
					c["t"] = 0.0
			"returning":
				c["t"] += dt
				c["body"].rotation.x = c["sign"] * _tip_angle * (1.0 - clampf(c["t"] / 0.5, 0.0, 1.0))
				if c["t"] >= 0.5:
					_reset_cell(c)

func _reset_cell(c: Dictionary) -> void:
	c["state"] = "idle"
	c["t"] = 0.0
	c["body"].rotation.x = 0.0
	c["outer"].disabled = false
	c["outer_mesh"].visible = true

## Put every game piece back where a match starts.
func reset_elements(pollen) -> void:
	pollen.clear()
	score = {"red": 0, "blue": 0}
	tips = {"red": 0, "blue": 0}
	for c in cells:
		if c["up"]:
			_reset_cell(c)
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
