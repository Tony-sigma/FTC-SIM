extends CharacterBody3D
## Simulated robot: kinematic mecanum drive.
##
## Whoever controls the robot (built-in TeleOp now, the Java sim SDK later) only sets
## `wheel_powers` (-1..1, + = wheel drives the robot forward), exactly like motor.setPower().
##
## Frames: the robot's forward is its local -Z, left is local -X (Godot convention).
## FTC field coordinates: x = Godot x, y = -Godot z, heading counter-clockwise from +x.

enum { FL, FR, BL, BR }

var wheel_powers: Array = [0.0, 0.0, 0.0, 0.0]
var enabled := true

## Actual chassis velocity in the robot frame (m/s forward, m/s left, rad/s CCW).
var v_forward := 0.0
var v_left := 0.0
var omega := 0.0
## Accumulated wheel rotation (radians), for encoders.
var wheel_angles: Array[float] = [0.0, 0.0, 0.0, 0.0]

var length := 0.4572
var width := 0.4572
var height := 0.35
var wheel_radius := 0.052
var max_wheel_speed := 1.4   # m/s at the wheel rim under load
var half_track := 0.2
var half_wheelbase := 0.165
var strafe_eff := 0.85
var max_accel := 3.5
var max_ang_accel := 15.0
var ticks_per_wheel_rev := 537.7

## Mechanisms are commanded like servos: position 0..1. The parts follow at a limited speed.
var turret_servo := 0.5
var lever_front_servo := 0.0
var lever_back_servo := 0.0
## Where the parts actually are right now (degrees).
var turret_deg := 0.0
var lever_front_deg := 0.0
var lever_back_deg := 0.0
var has_cad_model := false

## Game-piece mechanisms, commanded like motors/servos.
var intake_front_power := 0.0   # -1..1, + = pull balls in and feed them up
var intake_back_power := 0.0
var shooter_power := 0.0        # 0..1
var hood_servo := 0.5           # 0..1 -> launch angle
var hood_deg := 45.0
var flywheel_fraction := 0.0    # actual flywheel speed, 0..1 of max
var flywheel_max_rpm := 3000.0
var shots_fired := 0
## Balls inside each feeder: progress 0 (just swallowed) .. 1 (waiting at the neck).
var feeders: Array = [[], []]
var pollen  # scripts/pollen.gd, set by main

var _feeder_cap := 3
var _total_cap := 3
var _transit_s := 0.5
var _mouth_width := 0.216
var _exit_speed_max := 5.6
var _spin_tau := 0.6
var _shot_drop := 0.25
var _min_shoot := 0.2
var _shot_interval := 0.25
var _hood_min := 30.0
var _hood_max := 60.0
var _hood_speed := 90.0
var _exit_offset := Vector3(0.1, 0.5, 0.0)
var _shot_cooldown := 0.0
var _spit_cooldown := 0.0
var _zones: Array[Area3D] = []

var _turret_range_deg := 64.3
var _turret_speed := 85.0
var _lever_stowed := 0.0
var _lever_deployed := 90.0
var _lever_speed := 240.0
var _lever_signs := [-1.0, 1.0]

var _visual: Node3D
var _shape: CollisionShape3D
var _shell: MeshInstance3D
var _turret_node: Node3D
var _lever_nodes: Array[Node3D] = []

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 1
	collision_mask = 1 | 8  # walls and hive keep-out; pollen (layer 2) never blocks the robot, the robot pushes it
	apply_config()
	reset_pose()

func apply_config() -> void:
	length = Config.inches("robot.length_in", 18.0)
	width = Config.inches("robot.width_in", 18.0)
	height = Config.inches("robot.height_in", 14.0)
	wheel_radius = Config.num("drivetrain.wheel_diameter_mm", 104.0) / 2000.0
	var gear := Config.num("drivetrain.external_gear_ratio", 1.0)
	var wheel_rpm := Config.num("drivetrain.motor_rpm", 312.0) / gear
	max_wheel_speed = wheel_rpm / 60.0 * TAU * wheel_radius * Config.num("drivetrain.loaded_speed_fraction", 0.85)
	half_track = Config.inches("drivetrain.track_width_in", 16.0) / 2.0
	half_wheelbase = Config.inches("drivetrain.wheelbase_in", 13.0) / 2.0
	strafe_eff = Config.num("drivetrain.strafe_efficiency", 0.85)
	max_accel = Config.inches("drivetrain.max_accel_in_per_s2", 140.0)
	max_ang_accel = deg_to_rad(Config.num("drivetrain.max_angular_accel_deg_per_s2", 900.0))
	ticks_per_wheel_rev = Config.num("drivetrain.ticks_per_rev", 537.7) * gear
	var ratio := Config.num("turret.servo_gear_teeth", 15.0) / Config.num("turret.turret_gear_teeth", 70.0)
	_turret_range_deg = Config.num("turret.servo_range_deg", 300.0) * ratio
	_turret_speed = Config.num("turret.servo_speed_deg_per_s", 400.0) * ratio
	_lever_stowed = Config.num("levers.stowed_deg", 0.0)
	_lever_deployed = Config.num("levers.deployed_deg", 90.0)
	_lever_speed = Config.num("levers.speed_deg_per_s", 240.0)
	_lever_signs = [Config.num("levers.front_deploy_sign", -1.0), Config.num("levers.back_deploy_sign", 1.0)]
	_feeder_cap = int(Config.num("intakes.feeder_capacity", 3))
	_total_cap = int(Config.num("intakes.total_capacity", 3))
	_transit_s = Config.num("intakes.feeder_transit_s", 0.5)
	_mouth_width = Config.inches("intakes.mouth_width_in", 8.5)
	flywheel_max_rpm = Config.num("shooter.flywheel_max_rpm", 3000.0)
	_exit_speed_max = flywheel_max_rpm / 60.0 * PI * Config.inches("shooter.flywheel_diameter_in", 4.0) * Config.num("shooter.exit_speed_fraction", 0.35)
	_spin_tau = Config.num("shooter.spin_up_time_s", 0.6)
	_shot_drop = Config.num("shooter.speed_drop_per_shot", 0.25)
	_min_shoot = Config.num("shooter.min_speed_fraction_to_shoot", 0.2)
	_shot_interval = Config.num("shooter.shot_interval_s", 0.25)
	_hood_min = Config.num("shooter.hood_min_deg", 30.0)
	_hood_max = Config.num("shooter.hood_max_deg", 60.0)
	_hood_speed = Config.num("shooter.hood_speed_deg_per_s", 90.0)
	_exit_offset = _vec("shooter.exit_offset_m", Vector3(0.1, 0.5, 0.0))
	_build_body()
	_build_intake_zones()

func reset_pose() -> void:
	set_pose_ftc(Config.num("robot.start_x_in", -58.0), Config.num("robot.start_y_in", -48.0),
		Config.num("robot.start_heading_deg", 0.0))
	for i in 4:
		wheel_powers[i] = 0.0
		wheel_angles[i] = 0.0
	turret_servo = 0.5
	lever_front_servo = 0.0
	lever_back_servo = 0.0
	intake_front_power = 0.0
	intake_back_power = 0.0
	shooter_power = 0.0
	hood_servo = 0.5
	flywheel_fraction = 0.0
	shots_fired = 0
	feeders = [[], []]

func set_pose_ftc(x_in: float, y_in: float, heading_deg: float) -> void:
	position = Vector3(x_in * Config.IN, 0.0, -y_in * Config.IN)
	rotation = Vector3(0.0, deg_to_rad(heading_deg - 90.0), 0.0)
	v_forward = 0.0
	v_left = 0.0
	omega = 0.0
	velocity = Vector3.ZERO

## Pose in FTC field coordinates: inches, inches, degrees (-180..180, CCW positive).
func get_pose_ftc() -> Vector3:
	return Vector3(position.x / Config.IN, -position.z / Config.IN,
		wrapf(rad_to_deg(rotation.y) + 90.0, -180.0, 180.0))

func get_speed() -> float:
	return Vector2(v_forward, v_left).length()

func get_wheel_ticks(i: int) -> float:
	return wheel_angles[i] / TAU * ticks_per_wheel_rev

func max_forward_speed() -> float:
	return max_wheel_speed

## Total turret travel in degrees (servo range through the gear reduction).
func turret_range_deg() -> float:
	return _turret_range_deg

func toggle_shell() -> void:
	if _shell:
		_shell.visible = not _shell.visible

func _update_mechanisms(dt: float) -> void:
	# Positive turret angle = counter-clockwise seen from above (same sense as heading).
	var turret_goal := (clampf(turret_servo, 0.0, 1.0) - 0.5) * _turret_range_deg
	turret_deg = move_toward(turret_deg, turret_goal, _turret_speed * dt)
	lever_front_deg = move_toward(lever_front_deg, lerpf(_lever_stowed, _lever_deployed, clampf(lever_front_servo, 0.0, 1.0)), _lever_speed * dt)
	lever_back_deg = move_toward(lever_back_deg, lerpf(_lever_stowed, _lever_deployed, clampf(lever_back_servo, 0.0, 1.0)), _lever_speed * dt)
	if _turret_node:
		_turret_node.rotation.y = deg_to_rad(turret_deg)
	if _lever_nodes.size() == 2:
		_lever_nodes[0].rotation.x = deg_to_rad(lever_front_deg) * _lever_signs[0]
		_lever_nodes[1].rotation.x = deg_to_rad(lever_back_deg) * _lever_signs[1]

## Load the robot with its starting pollen, split between the two feeders.
func preload_pollen() -> void:
	feeders = [[], []]
	var n := mini(int(Config.num("intakes.preload", 0)), _total_cap)
	for i in n:
		var f: Array = feeders[i % 2]
		if f.size() < _feeder_cap:
			f.append(1.0 - 0.25 * f.size())

## The outer edge of each deployed lever, as [end_a, end_b] in world space (for touching flowers).
func deployed_lever_bars() -> Array:
	var out: Array = []
	var degs := [lever_front_deg, lever_back_deg]
	for i in _lever_nodes.size():
		if degs[i] < 60.0:
			continue
		var t: Transform3D = _lever_nodes[i].global_transform
		out.append([t * Vector3(-width / 2.0, 0.19, 0), t * Vector3(width / 2.0, 0.19, 0)])
	return out

func held_count(feeder: int) -> int:
	return feeders[feeder].size()

func held_total() -> int:
	return feeders[0].size() + feeders[1].size()

func flywheel_rpm() -> float:
	return flywheel_fraction * flywheel_max_rpm

func _build_intake_zones() -> void:
	for z in _zones:
		z.queue_free()
	_zones.clear()
	# A slot just outside each end of the chassis; a ball touching it while the intake runs is swallowed.
	for sgn in [-1.0, 1.0]:
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(_mouth_width, 0.1, 0.06)
		cs.shape = box
		area.add_child(cs)
		area.position = Vector3(0, 0.05, sgn * (length / 2.0 + 0.012))
		add_child(area)
		_zones.append(area)

func _update_game_pieces(dt: float) -> void:
	var powers := [intake_front_power if enabled else 0.0, intake_back_power if enabled else 0.0]
	# Flywheel spins up/down toward the commanded power.
	var target := clampf(shooter_power, 0.0, 1.0) if enabled else 0.0
	flywheel_fraction += (target - flywheel_fraction) * (1.0 - exp(-dt / maxf(_spin_tau / 3.0, 0.001)))
	hood_deg = move_toward(hood_deg, lerpf(_hood_min, _hood_max, clampf(hood_servo, 0.0, 1.0)), _hood_speed * dt)
	_shot_cooldown = maxf(_shot_cooldown - dt, 0.0)
	_spit_cooldown = maxf(_spit_cooldown - dt, 0.0)

	for i in 2:
		var power: float = clampf(powers[i], -1.0, 1.0)
		var balls: Array = feeders[i]
		# Swallow balls touching the intake mouth.
		if power > 0.1 and pollen != null:
			for body in _zones[i].get_overlapping_bodies():
				if balls.size() >= _feeder_cap or held_total() >= _total_cap:
					break
				if body.is_in_group("pollen") and not body.is_queued_for_deletion():
					pollen.remove_ball(body)
					balls.append(0.0)
		# Carry balls up the feeder; they queue behind each other.
		if power > 0.1:
			for k in balls.size():
				balls[k] = minf(balls[k] + power * dt / _transit_s, 1.0 - 0.25 * k)
			# Ball at the neck + flywheel spinning = shot.
			if balls.size() > 0 and balls[0] >= 1.0 and flywheel_fraction >= _min_shoot and _shot_cooldown <= 0.0:
				balls.pop_front()
				_launch()
		elif power < -0.1 and balls.size() > 0 and _spit_cooldown <= 0.0:
			# Reverse: spit the newest ball back out of the intake.
			balls.pop_back()
			_spit_cooldown = 0.3
			if pollen != null:
				var sgn := -1.0 if i == 0 else 1.0
				var out := global_transform.basis.z * sgn
				pollen.spawn_ball(global_position + out * (length / 2.0 + 0.09) + Vector3(0, 0.05, 0), velocity + out * 1.0, self)

func _launch() -> void:
	_shot_cooldown = _shot_interval
	shots_fired += 1
	var speed := _exit_speed_max * flywheel_fraction
	flywheel_fraction *= 1.0 - _shot_drop
	if pollen == null:
		return
	# The shooter points along the turret's +X (the Limelight side), tilted up by the hood angle.
	var turret_basis := global_transform.basis * Basis(Vector3.UP, deg_to_rad(turret_deg))
	var a := deg_to_rad(hood_deg)
	var dir := (turret_basis.x * cos(a) + Vector3.UP * sin(a)).normalized()
	var pos := global_position + turret_basis * _exit_offset
	pollen.spawn_ball(pos, velocity + dir * speed, self)

func _physics_process(dt: float) -> void:
	_update_mechanisms(dt)
	_update_game_pieces(dt)
	var p: Array[float] = [0.0, 0.0, 0.0, 0.0]
	if enabled:
		for i in 4:
			p[i] = clampf(float(wheel_powers[i]), -1.0, 1.0)
	var k := half_track + half_wheelbase

	# Mecanum forward kinematics: wheel rim speeds -> where the chassis wants to go.
	var w: Array[float] = [p[FL] * max_wheel_speed, p[FR] * max_wheel_speed, p[BL] * max_wheel_speed, p[BR] * max_wheel_speed]
	var want_fwd := (w[FL] + w[FR] + w[BL] + w[BR]) / 4.0
	var want_left := (-w[FL] + w[FR] + w[BL] - w[BR]) / 4.0 * strafe_eff
	var want_omega := (-w[FL] + w[FR] - w[BL] + w[BR]) / (4.0 * k)

	# Acceleration limits (stands in for motor torque and wheel grip).
	var v := Vector2(v_forward, v_left).move_toward(Vector2(want_fwd, want_left), max_accel * dt)
	omega = move_toward(omega, want_omega, max_ang_accel * dt)

	rotate_y(omega * dt)
	var fwd := -global_transform.basis.z
	var left := -global_transform.basis.x
	velocity = fwd * v.x + left * v.y
	move_and_slide()
	position.y = 0.0

	# Read back what actually happened, so hitting a wall kills the speed.
	var real := get_real_velocity()
	v_forward = real.dot(fwd)
	v_left = real.dot(left)

	# Inverse kinematics on the real motion -> wheel rotation (encoders).
	var s := v_left / strafe_eff
	var rim: Array[float] = [v_forward - s - k * omega, v_forward + s + k * omega,
		v_forward + s - k * omega, v_forward - s + k * omega]
	for i in 4:
		wheel_angles[i] += rim[i] / wheel_radius * dt

# --- placeholder visuals + collision (replaced by the CAD model in Phase 2) ---

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	_visual.add_child(mi)
	return mi

func _vec(path: String, default: Vector3) -> Vector3:
	var a = Config.value(path, null)
	if a is Array and a.size() == 3:
		return Vector3(a[0], a[1], a[2])
	return default

func _add_model(file: String, parent: Node3D, pivot: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.position = pivot
	parent.add_child(holder)
	var scene = load("res://models/%s.glb" % file)
	if scene is PackedScene:
		holder.add_child(scene.instantiate())
	return holder

func _build_body() -> void:
	if _visual:
		_visual.queue_free()
	_lever_nodes.clear()
	_turret_node = null
	if _shape == null:
		_shape = CollisionShape3D.new()
		add_child(_shape)
	var clearance := 0.01
	var box := BoxShape3D.new()
	box.size = Vector3(width, height - clearance, length)
	_shape.shape = box
	_shape.position = Vector3(0, clearance + box.size.y / 2.0, 0)

	_visual = Node3D.new()
	add_child(_visual)
	# Translucent shell = the box that actually collides (toggle with V).
	_shell = _box(Vector3(width, height - clearance, length), _shape.position, Color(0.3, 0.75, 1.0, 0.18))

	has_cad_model = ResourceLoader.exists("res://models/chassis.glb")
	if has_cad_model:
		# Real CAD, pre-processed by tools/process_cad.mjs. Each moving piece's origin is its pivot.
		_shell.visible = false
		_add_model("chassis", _visual, Vector3.ZERO)
		_turret_node = _add_model("turret", _visual, _vec("turret.pivot_m", Vector3.ZERO))
		_lever_nodes.append(_add_model("lever_front", _visual, _vec("levers.front_pivot_m", Vector3(0, 0.156, -0.162))))
		_lever_nodes.append(_add_model("lever_back", _visual, _vec("levers.back_pivot_m", Vector3(0, 0.156, 0.162))))
		# Small arrow on the floor in front of the robot marks which end is "front".
		_box(Vector3(0.05, 0.004, 0.09), Vector3(0, 0.004, -length / 2.0 - 0.07), Color(1.0, 0.85, 0.1))
		return

	# No CAD available: simple placeholder box robot.
	var wheel_w := 0.038
	var body_w := maxf(half_track * 2.0 - wheel_w - 0.01, 0.1)
	_box(Vector3(body_w, height - 0.03, length - 0.02), Vector3(0, 0.03 + (height - 0.03) / 2.0, 0), Color(0.16, 0.17, 0.2))
	_box(Vector3(width, 0.03, 0.03), Vector3(0, height - 0.015, -length / 2.0 + 0.015), Color(1.0, 0.85, 0.1))
	_box(Vector3(0.04, 0.012, length * 0.55), Vector3(0, height + 0.006, -length * 0.1), Color(1.0, 0.85, 0.1))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var cyl := CylinderMesh.new()
			cyl.top_radius = wheel_radius
			cyl.bottom_radius = wheel_radius
			cyl.height = wheel_w
			var mi := MeshInstance3D.new()
			mi.mesh = cyl
			mi.rotation.z = PI / 2.0
			mi.position = Vector3(sx * half_track, wheel_radius, sz * half_wheelbase)
			mi.material_override = _mat(Color(0.85, 0.5, 0.1))
			_visual.add_child(mi)
