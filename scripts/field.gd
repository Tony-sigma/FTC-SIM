extends Node3D
## The BIOBUZZ field: tile floor, walls, and the game elements from data/field_layout.json
## (zones, flowers, hive frame, hive cells) plus the starting pollen from data/game_elements.json.
## The data files give the floor plan; heights and behaviour marked GUESS come from robot_config.json.

var size := 3.5875
var wall_height := 0.3048
var layout: Dictionary = {}
var elements: Dictionary = {}
## Each flower: { pos: Vector3, inward: Vector3, body, start: int, stack: Array (ball kinds, bottom first),
## timer: float, label: Label3D, plug: CollisionShape3D, visuals: Array }
var flowers: Array = []
## Each hive: { alliance, body, up_side ("top"/"bottom"), start_side, angle, areas: {top, bottom} }
var hives: Array = []
## Hive tips per alliance (20 points each).
var tips := {"red": 0, "blue": 0}
## NECTAR still waiting off the field with each alliance's humans.
var nectar_reserve := {"red": 0, "blue": 0}

var _tip_weight_g := 100.0
var _tip_angle := 0.52
var _tip_time := 0.8
var _pollen                   # scripts/pollen.gd, remembered from reset_elements
var _nectar_queue: Array = []  # [{ alliance, wait }] nectar the humans are about to put in
var _nectar_entered := 0
## Flower heights (metres above the tiles), from the CAD: the pollen stand on the tile inside the floor
## ring; nectar is too big for the middle ring and rests on it; the scoring volume is between the
## middle ring and the top ring.
var _fl_nectar_rest := 0.13
var _fl_score_min := 0.1245
var _fl_score_max := 0.551
var _fl_top_ring := 0.546

var _k := 1.0            # metres per data inch (data is on a nominal 144 in field)
var _flower_radius := 0.084
var _release_interval := 0.35
var _lever_reach := 0.06

func _ready() -> void:
	size = Config.inches("field.size_in", 141.24)
	wall_height = Config.inches("field.wall_height_in", 12.0)
	_k = size / 144.0
	_tip_weight_g = Config.num("field.hive_tip_weight_g", 100.0)
	_tip_angle = deg_to_rad(Config.num("field.hive_tip_angle_deg", 30.0))
	_tip_time = Config.num("field.hive_tip_time_s", 0.8)
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
	_flower_radius = Config.inches("field.flower_radius_in", 2.4)
	_release_interval = Config.num("field.flower_release_interval_s", 0.35)
	_lever_reach = Config.inches("field.flower_lever_reach_in", 2.5)
	_fl_nectar_rest = Config.inches("field.flower_nectar_rest_in", 5.1)
	_fl_score_min = Config.inches("field.flower_scoring_bottom_in", 4.9)
	_fl_score_max = Config.inches("field.flower_scoring_top_in", 21.7)
	_fl_top_ring = Config.inches("field.flower_top_ring_in", 21.5)
	var from_wall := Config.inches("field.flower_axis_from_wall_in", 3.75)
	var has_model := ResourceLoader.exists("res://models/field/flower.glb")
	var inward_of := {"top": Vector3(0, 0, 1), "bottom": Vector3(0, 0, -1), "left": Vector3(1, 0, 0), "right": Vector3(-1, 0, 0)}
	for f in layout.get("flowers", []):
		var inward: Vector3 = inward_of.get(str(f.get("wall", "top")), Vector3(0, 0, 1))
		# The flower hangs on the wall; its tube stands a few inches inside it.
		var pos := to_world(f["x"], f["y"]) + inward * from_wall
		var body := StaticBody3D.new()
		body.position = pos
		# The CAD's -z side is the wall side: turn the model so its +z points into the field.
		body.rotation.y = atan2(inward.x, inward.z)
		add_child(body)
		if has_model:
			_add_model_with_collision(body, load("res://models/field/flower.glb"))
		else:
			_add_box(body, Vector3(0.03, _fl_top_ring, 0.03), Vector3(0, _fl_top_ring / 2.0, -0.05), Color(0.3, 0.8, 0.4))
		# Stands in for the balls inside: a loose ball dropped in from the top lands on this.
		var plug := CollisionShape3D.new()
		plug.shape = BoxShape3D.new()
		body.add_child(plug)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 64
		label.pixel_size = 0.0015
		label.outline_size = 12
		label.position = Vector3(0, _fl_top_ring + 0.14, 0)
		body.add_child(label)
		flowers.append({"pos": pos, "inward": inward, "body": body, "start": int(f.get("pollen", 4)), "stack": [], "timer": 0.0, "label": label, "plug": plug, "visuals": []})

func _build_hives() -> void:
	# The A-frame the hives hang from. Its CAD is centred on the field; its long side lies along our x.
	if ResourceLoader.exists("res://models/field/hive_frame.glb"):
		var frame := StaticBody3D.new()
		frame.rotation.y = PI / 2.0
		add_child(frame)
		_add_model_with_collision(frame, load("res://models/field/hive_frame.glb"))
	else:
		for b in layout.get("frame_bars", []):
			var r: Array = b["rect"]
			var bar := StaticBody3D.new()
			bar.position = to_world(r[0] + r[2] / 2.0, r[1] + r[3] / 2.0, 0.02)
			add_child(bar)
			_add_box(bar, Vector3(r[2] * _k, 0.04, r[3] * _k), Vector3.ZERO, Color(0.75, 0.76, 0.8))
	var pivot_h := Config.inches("field.hive_pivot_height_in", 43.03)
	var off: float = float(layout.get("cell_offset_in", 15.44)) * _k
	for h in layout.get("hives", []):
		var alliance := str(h["alliance"])
		# The whole seesaw is one moving body, pivoting about its centre (the model's origin).
		var body := AnimatableBody3D.new()
		body.collision_layer = 4   # only pollen collide with the hive; robots drive underneath it
		body.collision_mask = 0
		body.position = to_world(h["x"], 72.0, pivot_h)
		add_child(body)
		var path := "res://models/field/%s_hive.glb" % alliance
		if ResourceLoader.exists(path):
			_add_model_with_collision(body, load(path))
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
		var hive := {"alliance": alliance, "body": body, "start_side": str(h.get("up_cell", "top")), "up_side": "", "angle": 0.0, "areas": areas}
		hives.append(hive)
		_set_hive(hive, hive["start_side"], true)

## Show a CAD model under `body` and give it mesh collision that matches what you see.
func _add_model_with_collision(body: PhysicsBody3D, scene: PackedScene) -> void:
	var inst: Node3D = scene.instantiate()
	body.add_child(inst)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var shape: ConcavePolygonShape3D = mi.mesh.create_trimesh_shape()
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		cs.global_transform = mi.global_transform

## Tilt so the given cell is the raised one. A negative angle about X lifts the +z ("bottom", audience) end.
func _target_angle(side: String) -> float:
	return -_tip_angle if side == "bottom" else _tip_angle

func _set_hive(hive: Dictionary, side: String, snap := false) -> void:
	hive["up_side"] = side
	if snap:
		hive["angle"] = _target_angle(side)
		hive["body"].rotation.x = hive["angle"]
		# Jumping straight to a new tilt would sweep the cell through anything placed in it, so the hive
		# is made untouchable for the few physics steps the jump takes.
		hive["body"].collision_layer = 0
		hive["settle"] = 3

## The balls in the given alliance's raised (up = true) or lowered cell right now.
func cell_balls(alliance: String, up: bool) -> Array:
	for h in hives:
		if h["alliance"] == alliance:
			var side: String = h["up_side"]
			if not up:
				side = "top" if side == "bottom" else "bottom"
			return h["areas"][side].get_overlapping_bodies().filter(func(b): return b.is_in_group("balls") and not b.is_queued_for_deletion())
	return []

func cell_count(alliance: String, up: bool) -> int:
	return cell_balls(alliance, up).size()

## Weight (grams) of everything in the raised or lowered cell.
func cell_weight_g(alliance: String, up: bool) -> float:
	var g := 0.0
	for b in cell_balls(alliance, up):
		g += b.mass * 1000.0
	return g

## Every AprilTag cluster on the field right now. Each hive cell has four tags on its underside:
## [{ key, name, tags: [{ id, pos, normal }], aim: Vector3, up: Vector3 }]. `aim` is the centre of the
## cell's opening (where the SDK says the cluster "is"); `up` is the sticker's top edge direction.
func april_tag_clusters() -> Array:
	var defs = Config.value("field.april_tag_clusters", {})
	var offsets = Config.value("field.april_tag_offsets_in", [-6.0, -2.26, 3.24, 6.99])
	var out: Array = []
	if not defs is Dictionary:
		return out
	for h in hives:
		var t: Transform3D = h["body"].global_transform
		for side in ["bottom", "top"]:
			var key := "%s_%s" % [h["alliance"], "audience" if side == "bottom" else "scoring"]
			if not defs.has(key):
				continue
			var z_sign := 1.0 if side == "bottom" else -1.0
			var tags: Array = []
			var ids: Array = defs[key].get("ids", [])
			for i in ids.size():
				var off: float = float(offsets[i]) if i < offsets.size() else 0.0
				tags.append({"id": int(ids[i]), "pos": t * Vector3(off * Config.IN, -1.5 * Config.IN, 14.0 * Config.IN * z_sign), "normal": t.basis * Vector3.DOWN})
			out.append({"key": key, "name": str(defs[key].get("name", key)), "tags": tags,
				"aim": t * Vector3(0, 6.5 * Config.IN, 19.0 * Config.IN * z_sign), "up": t.basis * Vector3(0, 0, z_sign)})
	return out

## World position of the AprilTag under the raised (active) cell of an alliance's hive.
func aim_point(alliance: String):
	var h := hive_of(alliance)
	if h.is_empty():
		return null
	var z := 14.0 * Config.IN * (1.0 if h["up_side"] == "bottom" else -1.0)
	return h["body"].global_transform * Vector3(0, -1.5 * Config.IN, z)

## World position of the middle of the raised cell's mouth: where a shot has to go in.
func mouth_point(alliance: String):
	var h := hive_of(alliance)
	if h.is_empty():
		return null
	var z := 19.0 * Config.IN * (1.0 if h["up_side"] == "bottom" else -1.0)
	return h["body"].global_transform * Vector3(0, 6.5 * Config.IN, z)

## Horizontal direction the raised cell's mouth faces (away from the field centre).
func mouth_outward(alliance: String) -> Vector3:
	var h := hive_of(alliance)
	if h.is_empty():
		return Vector3.ZERO
	return Vector3(0, 0, 1.0 if h["up_side"] == "bottom" else -1.0)

func hive_of(alliance: String) -> Dictionary:
	for h in hives:
		if h["alliance"] == alliance:
			return h
	return {}

## The hive rule: the seesaw tips when the weight in the raised cell reaches the threshold (pollen and
## nectar both count; a nectar weighs about as much as two pollen). A tip is worth 20 points; what was
## inside rolls out of the lowered cell, the other cell becomes the raised one, and the alliance's
## humans may put one more nectar on the field.
func update_hives(dt: float) -> void:
	for h in hives:
		if int(h.get("settle", 0)) > 0:
			h["settle"] -= 1
			if h["settle"] == 0:
				h["body"].collision_layer = 4
			continue
		var goal := _target_angle(h["up_side"])
		if not is_equal_approx(h["angle"], goal):
			h["angle"] = move_toward(h["angle"], goal, 2.0 * _tip_angle / maxf(_tip_time, 0.05) * dt)
			h["body"].rotation.x = h["angle"]
			continue
		if cell_weight_g(h["alliance"], true) >= _tip_weight_g - 0.05:
			tips[h["alliance"]] += 1
			_set_hive(h, "top" if h["up_side"] == "bottom" else "bottom")
			enter_nectar(h["alliance"], 1, 1.5)
	# Nectar on its way in: the human drops it onto the tiles of the alliance's loading zone.
	for q in _nectar_queue:
		q["wait"] -= dt
	while not _nectar_queue.is_empty() and _nectar_queue[0]["wait"] <= 0.0:
		var q: Dictionary = _nectar_queue.pop_front()
		_drop_nectar(q["alliance"])

## The alliance's humans put up to `n` of their waiting nectar onto the field, after `delay` seconds.
func enter_nectar(alliance: String, n: int, delay := 0.0) -> int:
	var k := mini(n, int(nectar_reserve.get(alliance, 0)))
	for i in k:
		nectar_reserve[alliance] -= 1
		_nectar_queue.append({"alliance": alliance, "wait": delay + 0.25 * i})
	_nectar_queue.sort_custom(func(a, b): return a["wait"] < b["wait"])
	return k

func _drop_nectar(alliance: String) -> void:
	if _pollen == null:
		return
	for z in layout.get("zones", []):
		if str(z.get("kind", "")) == "loading" and str(z.get("alliance", "")) == alliance:
			var r: Array = z["rect"]
			# Spread them over the zone so they do not land on each other.
			var i := _nectar_entered % 6
			_nectar_entered += 1
			var x: float = r[0] + r[2] * 0.5
			var y: float = r[1] + r[3] * (0.15 + 0.14 * i)
			_pollen.spawn_ball(to_world(x, y, 0.25), Vector3.ZERO, null, Vector3.ZERO, "nectar_" + alliance)
			return

## Put every game piece back where a match starts.
func reset_elements(pollen) -> void:
	_pollen = pollen
	pollen.clear()
	tips = {"red": 0, "blue": 0}
	_nectar_queue.clear()
	_nectar_entered = 0
	var reserve := int(layout.get("alliance_nectar", 5))
	nectar_reserve = {"red": reserve, "blue": reserve}
	for h in hives:
		_set_hive(h, h["start_side"], true)
		# Three nectar of the hive's colour start in its raised cell, against the back wall, in a line
		# from the side nearest that alliance (red is on the -x side of the field).
		var side_x := -1.0 if h["alliance"] == "red" else 1.0
		var z_sign := 1.0 if h["up_side"] == "bottom" else -1.0
		for i in int(Config.num("field.nectar_in_raised_cell", 3)):
			var local := Vector3(side_x * (8.2 - 3.75 * i), 2.6, z_sign * 11.8) * Config.IN
			# (The hive's node still reports its old tilt until the next physics step, so use the new one.)
			var tilted := Transform3D(Basis(Vector3.RIGHT, h["angle"]), h["body"].position)
			pollen.spawn_ball(tilted * local, Vector3.ZERO, null, Vector3.ZERO, "nectar_" + h["alliance"])
	for f in flowers:
		f["stack"] = []
		for i in f["start"]:
			f["stack"].append("pollen")
		f["timer"] = 0.0
		_refresh_flower(f)
	for e in elements.get("elements", []):
		var kind := str(e.get("type", ""))
		if pollen.kinds.has(kind):
			pollen.spawn_ball(to_world(e["x"], e["y"], pollen.props(kind)["radius"] + 0.002), Vector3.ZERO, null, Vector3.ZERO, kind)

## Where each ball in a flower sits: centre heights above the tiles, bottom first. Pollen stand on the
## tile and stack up through the rings; a nectar cannot pass the middle ring, so it rests on it (or on
## the pollen under it), and whatever is dropped in afterwards sits on top.
func flower_heights(stack: Array) -> Array:
	var out: Array = []
	var top := 0.0
	for kind in stack:
		var r: float = _pollen.props(kind)["radius"] if _pollen != null else 0.0356
		var bottom := top
		if str(kind).begins_with("nectar"):
			bottom = maxf(top, _fl_nectar_rest)
		out.append(bottom + r)
		top = bottom + 2.0 * r
	return out

func _refresh_flower(f: Dictionary) -> void:
	for v in f["visuals"]:
		v.queue_free()
	f["visuals"] = []
	var heights := flower_heights(f["stack"])
	var top := 0.0
	for i in f["stack"].size():
		var kind: String = f["stack"][i]
		if _pollen != null:
			var mi: MeshInstance3D = _pollen.make_visual(kind)
			mi.position = Vector3(0, heights[i], 0)
			f["body"].add_child(mi)
			f["visuals"].append(mi)
			top = heights[i] + _pollen.props(kind)["radius"]
	var box: BoxShape3D = f["plug"].shape
	box.size = Vector3(0.07, maxf(top, 0.02), 0.07)
	f["plug"].position = Vector3(0, box.size.y / 2.0, 0)
	var pollen_n: int = f["stack"].count("pollen")
	var nectar_n: int = f["stack"].size() - pollen_n
	f["label"].text = str(pollen_n) if nectar_n == 0 else "%d + %dN" % [pollen_n, nectar_n]

## Which of a flower's balls count for points: at least partly between the middle ring and the top ring.
func flower_scoring(f: Dictionary) -> Array:
	var out: Array = []
	var heights := flower_heights(f["stack"])
	for i in f["stack"].size():
		var r: float = _pollen.props(f["stack"][i])["radius"] if _pollen != null else 0.0356
		if heights[i] + r > _fl_score_min and heights[i] - r < _fl_score_max:
			out.append(f["stack"][i])
	return out

## The flowers. A deployed lever held under a flower wedges out the bottom POLLEN, one at a time
## (never a nectar: that is too big for the opening, and against the rules). A loose ball that drops in
## through the top ring joins the stack.
func update_flowers(robot, pollen, dt: float) -> void:
	var bars: Array = robot.deployed_lever_bars()
	for f in flowers:
		f["timer"] = maxf(f["timer"] - dt, 0.0)
		var p: Vector3 = f["pos"]
		# From the top: a ball whose centre is inside the tube and below the top ring has gone in.
		for b in pollen.get_tree().get_nodes_in_group("balls"):
			if b.is_queued_for_deletion():
				continue
			var local: Vector3 = b.global_position - p
			if absf(local.x) < 0.03 and absf(local.z) < 0.03 and local.y < _fl_top_ring and local.y > 0.05:
				f["stack"].append(pollen.kind_of(b))
				pollen.remove_ball(b)
				_refresh_flower(f)
		if f["stack"].is_empty() or f["stack"][0] != "pollen" or f["timer"] > 0.0:
			continue
		for bar in bars:
			var a: Vector3 = bar[0]
			var b: Vector3 = bar[1]
			var a2 := Vector2(a.x, a.z)
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var tt := clampf((Vector2(p.x, p.z) - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			if (a2 + ab * tt).distance_to(Vector2(p.x, p.z)) <= _flower_radius + _lever_reach:
				f["stack"].pop_front()
				f["timer"] = _release_interval
				_refresh_flower(f)
				# It rolls out of the opening at the bottom, towards the robot's intake.
				var inward: Vector3 = f["inward"]
				pollen.spawn_ball(p + inward * (_flower_radius + pollen.radius + 0.004) + Vector3(0, pollen.radius + 0.002, 0), inward * 0.4, robot)
				break

## Points each alliance would have if the match ended now (manual section 10.5):
## 20 per hive tip, 2 per ball still in its raised cell, 2 per scoring ball in a flower it owns (the
## flower's owner is the alliance whose nectar is top-most in it), 5 for the bottom-most nectar in each
## flower, 1 per ball in its garden. LEAVE and PARK points are not counted.
func points() -> Dictionary:
	var out := {"red": 0, "blue": 0}
	for a in out.keys():
		out[a] += 20 * int(tips[a]) + 2 * cell_count(a, true)
	for f in flowers:
		var scoring := flower_scoring(f)
		var nectar := scoring.filter(func(k): return str(k).begins_with("nectar"))
		if nectar.is_empty():
			continue
		out[str(nectar[0]).trim_prefix("nectar_")] += 5
		out[str(nectar[-1]).trim_prefix("nectar_")] += 2 * scoring.size()
	if _pollen != null:
		for z in layout.get("zones", []):
			if str(z.get("kind", "")) != "garden":
				continue
			var r: Array = z["rect"]
			var lo := to_world(r[0], r[1])
			var hi := to_world(r[0] + r[2], r[1] + r[3])
			for b in _pollen.get_tree().get_nodes_in_group("balls"):
				var rad: float = _pollen.props(_pollen.kind_of(b))["radius"]
				var q: Vector3 = b.global_position
				if q.y < rad + 0.03 and q.x > lo.x - rad and q.x < hi.x + rad and q.z > lo.z - rad and q.z < hi.z + rad:
					out[str(z["alliance"])] += 1
	return out

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
