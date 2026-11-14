extends Node3D
## Pollen: the game's balls. Real physics (RigidBody3D) for rolling, bouncing and flying.

var radius := 0.0381
var mass_kg := 0.075
var scored := 0

var _mesh: SphereMesh
var _shape: SphereShape3D
var _material: StandardMaterial3D
var _physics: PhysicsMaterial
var _ang_damp := 0.6

func _ready() -> void:
	apply_config()

func apply_config() -> void:
	radius = Config.inches("pollen.diameter_in", 2.8) / 2.0
	mass_kg = Config.num("pollen.mass_g", 12.5) / 1000.0
	var bounce := 0.45
	var friction := 0.6
	var ang_damp := 0.6
	# Prefer the real numbers from the field data when present.
	if FileAccess.file_exists("res://data/game_elements.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_elements.json"))
		if parsed is Dictionary and parsed.get("types", {}).has("pollen"):
			var t: Dictionary = parsed["types"]["pollen"]
			radius = float(t.get("size_in", 2.8)) * Config.IN / 2.0
			mass_kg = float(t.get("weight_g", 12.5)) / 1000.0
			bounce = float(t.get("bounce", 0.25)) * 2.0  # the data adds the bounce of both bodies
			friction = float(t.get("friction", 0.3))
			ang_damp = float(t.get("angular_damp", 3.0))
	_ang_damp = ang_damp
	_mesh = SphereMesh.new()
	_mesh.radius = radius
	_mesh.height = radius * 2.0
	_mesh.radial_segments = 20
	_mesh.rings = 10
	_shape = SphereShape3D.new()
	_shape.radius = radius
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(1.0, 0.8, 0.1)
	_material.roughness = 0.6
	_physics = PhysicsMaterial.new()
	_physics.bounce = bounce
	_physics.friction = friction

func ball_count() -> int:
	return get_tree().get_nodes_in_group("pollen").size()

func spawn_ball(pos: Vector3, vel := Vector3.ZERO, ignore: PhysicsBody3D = null) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = mass_kg
	b.physics_material_override = _physics
	b.collision_layer = 2
	b.collision_mask = 7  # floor/walls/robot, other pollen, hives
	b.continuous_cd = true
	b.linear_damp = 0.05
	b.angular_damp = _ang_damp
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _material
	b.add_child(mi)
	b.add_to_group("pollen")
	add_child(b)
	b.global_position = pos
	b.linear_velocity = vel
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

func remove_ball(b: Node) -> void:
	b.remove_from_group("pollen")
	b.queue_free()

func clear() -> void:
	for b in get_tree().get_nodes_in_group("pollen"):
		remove_ball(b)
	scored = 0
