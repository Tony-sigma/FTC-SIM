extends Node3D
## The game's balls: POLLEN (yellow) and NECTAR (red / blue, bigger and heavier). Real physics
## (RigidBody3D) for rolling, bouncing and flying. Every ball is in the group "balls"; pollen are also in
## "pollen" and nectar in "nectar". Each ball carries its kind: "pollen", "nectar_red" or "nectar_blue".

const Ballistics := preload("res://scripts/ballistics.gd")
const KINDS := ["pollen", "nectar_red", "nectar_blue"]

## Pollen numbers, kept as plain variables for code that only cares about pollen.
var radius := 0.0381
var mass_kg := 0.075
## Air: k_drag = 0.5 * rho * area * Cd / mass, k_area = 0.5 * rho * area / mass.
var k_drag := 0.0
var k_area := 0.0
var lift_max := 0.35

## Everything about each kind of ball: { radius, mass, k_drag, k_area, lift_max, ang_damp, color,
## squeeze_force_n, squeeze_loss, mesh, shape, material, physics }.
var kinds: Dictionary = {}

func _ready() -> void:
	apply_config()

func apply_config() -> void:
	var data: Dictionary = {}
	if FileAccess.file_exists("res://data/game_elements.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_elements.json"))
		if parsed is Dictionary:
			data = parsed.get("types", {})
	var rho := Config.num("pollen.air_density_kg_m3", 1.2)
	kinds = {}
	for kind in KINDS:
		var section := "pollen" if kind == "pollen" else "nectar"
		var k := {}
		k["radius"] = Config.inches(section + ".diameter_in", 2.8 if kind == "pollen" else 3.6) / 2.0
		k["mass"] = Config.num(section + ".mass_g", 12.5 if kind == "pollen" else 26.5) / 1000.0
		var bounce := 0.45
		var friction := 0.6
		k["ang_damp"] = 0.6
		k["color"] = {"pollen": Color(1.0, 0.8, 0.1), "nectar_red": Color(0.88, 0.19, 0.19), "nectar_blue": Color(0.23, 0.36, 0.86)}[kind]
		# Prefer the real numbers from the field data when present.
		if data.has(kind):
			var t: Dictionary = data[kind]
			k["radius"] = float(t.get("size_in", k["radius"] * 2.0 / Config.IN)) * Config.IN / 2.0
			k["mass"] = float(t.get("weight_g", k["mass"] * 1000.0)) / 1000.0
			bounce = float(t.get("bounce", 0.25)) * 2.0  # the data adds the bounce of both bodies
			friction = float(t.get("friction", 0.3))
			k["ang_damp"] = float(t.get("angular_damp", 3.0))
			if t.has("color"):
				k["color"] = Color(str(t["color"]))
		var area: float = PI * k["radius"] * k["radius"]
		k["k_area"] = 0.5 * rho * area / k["mass"]
		k["k_drag"] = k["k_area"] * Config.num(section + ".drag_coefficient", 0.5)
		k["lift_max"] = Config.num(section + ".lift_coefficient_max", 0.35)
		k["spin_efficiency"] = Config.num(section + ".spin_efficiency", 0.6)
		# How hard the ball pushes back when the shooter wheels squash it, and how much of that work is lost.
		k["squeeze_force_n"] = Config.num(section + ".squeeze_force_n", 45.0 if kind == "pollen" else 100.0)
		k["squeeze_loss"] = Config.num(section + ".squeeze_loss_fraction", 0.3)
		var mesh := SphereMesh.new()
		mesh.radius = k["radius"]
		mesh.height = k["radius"] * 2.0
		mesh.radial_segments = 20
		mesh.rings = 10
		k["mesh"] = mesh
		var shape := SphereShape3D.new()
		shape.radius = k["radius"]
		k["shape"] = shape
		var material := StandardMaterial3D.new()
		material.albedo_color = k["color"]
		material.roughness = 0.6
		k["material"] = material
		var physics := PhysicsMaterial.new()
		physics.bounce = bounce
		physics.friction = friction
		k["physics"] = physics
		kinds[kind] = k
	var p: Dictionary = kinds["pollen"]
	radius = p["radius"]
	mass_kg = p["mass"]
	k_drag = p["k_drag"]
	k_area = p["k_area"]
	lift_max = p["lift_max"]

## The numbers for one kind of ball (pollen when the kind is unknown).
func props(kind: String) -> Dictionary:
	return kinds.get(kind, kinds["pollen"])

static func kind_of(body: Node) -> String:
	return str(body.get_meta("kind", "pollen"))

## "red" / "blue" for nectar, "" for pollen.
static func alliance_of(kind: String) -> String:
	return kind.trim_prefix("nectar_") if kind.begins_with("nectar_") else ""

## A ball you can see but that is not part of the physics (inside a flower, for example).
func make_visual(kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = props(kind)["mesh"]
	mi.material_override = props(kind)["material"]
	return mi

## Loose pollen on the field.
func ball_count() -> int:
	return get_tree().get_nodes_in_group("pollen").size()

func nectar_count() -> int:
	return get_tree().get_nodes_in_group("nectar").size()

func spawn_ball(pos: Vector3, vel := Vector3.ZERO, ignore: PhysicsBody3D = null, spin := Vector3.ZERO, kind := "pollen") -> RigidBody3D:
	var k := props(kind)
	var b := RigidBody3D.new()
	b.mass = k["mass"]
	b.physics_material_override = k["physics"]
	b.collision_layer = 2
	b.collision_mask = 7  # floor/walls/robot, other balls, hives
	b.continuous_cd = true
	b.linear_damp = 0.05
	b.angular_damp = k["ang_damp"]
	var cs := CollisionShape3D.new()
	cs.shape = k["shape"]
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = k["mesh"]
	mi.material_override = k["material"]
	b.add_child(mi)
	b.set_meta("kind", kind)
	b.add_to_group("balls")
	b.add_to_group("pollen" if kind == "pollen" else "nectar")
	add_child(b)
	b.global_position = pos
	b.linear_velocity = vel
	if spin != Vector3.ZERO:
		# A launched ball keeps its spin until it first touches something.
		b.angular_velocity = spin
		b.angular_damp = 0.0
		b.contact_monitor = true
		b.max_contacts_reported = 1
		b.set_meta("spin", spin)
	if ignore != null:
		# A ball leaving the robot must not hit the robot's own collision box on the way out.
		b.add_collision_exception_with(ignore)
		var bid := b.get_instance_id()
		var iid := ignore.get_instance_id()
		get_tree().create_timer(0.35, false, true).timeout.connect(func():
			var bb = instance_from_id(bid)
			var ii = instance_from_id(iid)
			if bb != null and ii != null:
				bb.remove_collision_exception_with(ii))
	return b

## Air drag on every flying ball, plus the Magnus force on the ones still spinning from the shooter.
func _physics_process(_dt: float) -> void:
	for b in get_tree().get_nodes_in_group("balls"):
		var body := b as RigidBody3D
		if body == null or body.sleeping:
			continue
		var k := props(kind_of(body))
		if body.global_position.y < k["radius"] + 0.01:
			continue
		var spin := Vector3.ZERO
		if body.has_meta("spin"):
			if body.get_contact_count() > 0:
				body.remove_meta("spin")
				body.angular_damp = k["ang_damp"]
			else:
				spin = body.get_meta("spin")
		body.apply_central_force(Ballistics.air_accel(body.linear_velocity, spin, k["radius"], k["k_drag"], k["k_area"], k["lift_max"]) * body.mass)

func remove_ball(b: Node) -> void:
	for g in ["balls", "pollen", "nectar"]:
		if b.is_in_group(g):
			b.remove_from_group(g)
	b.queue_free()

func clear() -> void:
	for b in get_tree().get_nodes_in_group("balls"):
		remove_ball(b)
