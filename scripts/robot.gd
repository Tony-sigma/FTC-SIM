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

var _visual: Node3D
var _shape: CollisionShape3D

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
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
	_build_body()

func reset_pose() -> void:
	set_pose_ftc(Config.num("robot.start_x_in", 0.0), Config.num("robot.start_y_in", -48.0),
		Config.num("robot.start_heading_deg", 90.0))
	for i in 4:
		wheel_powers[i] = 0.0
		wheel_angles[i] = 0.0

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

func _physics_process(dt: float) -> void:
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

func _build_body() -> void:
	if _visual:
		_visual.queue_free()
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
	var wheel_w := 0.038
	var body_w := maxf(half_track * 2.0 - wheel_w - 0.01, 0.1)
	_box(Vector3(body_w, height - 0.03, length - 0.02), Vector3(0, 0.03 + (height - 0.03) / 2.0, 0), Color(0.16, 0.17, 0.2))
	# Translucent shell = the full footprint that collides.
	_box(Vector3(width, height - clearance, length), _shape.position, Color(0.3, 0.75, 1.0, 0.18))
	# Bright front bar + arrow on top so the driver can tell which way it faces.
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
