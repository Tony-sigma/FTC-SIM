extends Node3D
## Pollen: the game's balls. Real physics (RigidBody3D) for rolling, bouncing and flying.

var radius := 0.0381
var mass_kg := 0.075
var scored := 0

var _mesh: SphereMesh
var _shape: SphereShape3D
var _material: StandardMaterial3D
var _physics: PhysicsMaterial

func _ready() -> void:
	apply_config()

func apply_config() -> void:
	radius = Config.inches("pollen.diameter_in", 3.0) / 2.0
	mass_kg = Config.num("pollen.mass_g", 75.0) / 1000.0
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
	_physics.bounce = 0.45
	_physics.friction = 0.6

func ball_count() -> int:
	return get_tree().get_nodes_in_group("pollen").size()

func spawn_ball(pos: Vector3, vel := Vector3.ZERO, ignore: PhysicsBody3D = null) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = mass_kg
	b.physics_material_override = _physics
	b.collision_layer = 2
	b.collision_mask = 3
	b.continuous_cd = true
	b.linear_damp = 0.05
	b.angular_damp = 0.6
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

## Placeholder starting layout: rows of balls across the middle of the field.
func spawn_placeholder_layout(field_size: float) -> void:
	var n := int(Config.num("pollen.count", 24))
	var per_row := 6
	var gap := field_size / (per_row + 1)
	for i in n:
		var col := i % per_row
		var row := i / per_row
		var x := -field_size / 2.0 + gap * (col + 1)
		var z := -0.15 - row * 0.35
		spawn_ball(Vector3(x, radius + 0.002, z))

func on_goal_entered(body: Node) -> void:
	if body.is_in_group("pollen") and not body.has_meta("scored"):
		body.set_meta("scored", true)
		scored += 1
		var id := body.get_instance_id()
		get_tree().create_timer(1.5, false, true).timeout.connect(func():
			var bb = instance_from_id(id)
			if bb != null and not bb.is_queued_for_deletion():
				remove_ball(bb))
