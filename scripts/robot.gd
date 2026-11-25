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
## Turret: with turret.continuous the turret has no end stops and is commanded by angle
## (turret_goal_deg, robot-relative, CCW positive) or by aim_point (a world position to face).
var turret_continuous := true
var turret_goal_deg := 0.0
var aim_point = null   # Vector3 or null
var turret_servo := 0.5
var lever_front_servo := 0.0
var lever_back_servo := 0.0
## Where the parts actually are right now (degrees).
var turret_deg := 0.0
var lever_front_deg := 100.0
var lever_back_deg := 100.0
var has_cad_model := false

## Game-piece mechanisms, commanded like motors/servos.
var intake_front_power := 0.0   # -1..1, + = pull balls in and feed them up
var intake_back_power := 0.0
var shooter_power := 0.0        # 0..1
var gate_open := true           # the stopper at the neck; closed = pollen wait there even with the feeders running
## Dead-wheel pods: distance rolled, in metres.
var odo_forward := 0.0
var odo_strafe := 0.0
var _odo_left_off := -0.131
var _odo_fwd_off := -0.089
var hood_servo := 0.5           # 0..1 -> launch angle
var hood_deg := 45.0
var flywheel_fraction := 0.0    # actual flywheel speed, 0..1 of max
var flywheel_max_rpm := 3000.0
var shots_fired := 0
## Balls inside each feeder, the one nearest the shooter first:
## { p: progress 0 (just swallowed) .. 1 (waiting at the neck), kind: "pollen" / "nectar_red" / "nectar_blue" }.
var feeders: Array = [[], []]
## Why a ball is stuck at the shooter wheels right now ("" = nothing stuck).
var jam_reason := ""
## The last shot: { kind, speed (m/s), rpm_before, rpm_after }.
var last_shot: Dictionary = {}
## True = the motor controller holds the flywheel speed (setVelocity / RUN_USING_ENCODER): full voltage
## whenever the wheel is below the wanted speed. False = plain setPower, which recovers slowly.
var velocity_hold := true
var pollen  # scripts/pollen.gd, set by main

var _feeder_cap := 3
var _total_cap := 3
var _transit_s := 0.5
var _mouth_width := 0.216
var _exit_speed_max := 5.6
var _omega_max := 628.3         # flywheel free speed, rad/s
var _exit_per_omega := 0.04     # ball speed (m/s) per rad/s of flywheel
var _fly_r := 0.0508
var _top_r := 0.0381
var _wheel_gap := 0.0543
var _fly_inertia := 7.4e-4      # everything that spins, as felt at the flywheel shaft (kg m^2)
var _motor_torque := 0.288      # stall torque of all the shooter motors together (N m)
var _hold_gain := 20.0
var _wheel_grip := 0.8
var _feeder_push := 5.0
var _slip_factor := 2.0
var _spin_fraction := 0.6
var _jam_timer := 0.0
var _push_cache: Dictionary = {}
var _min_shoot := 0.2
var _shot_interval := 0.25
var _hood_min := 30.0
var _hood_max := 60.0
var _hood_speed := 90.0
var _exit_offset := Vector3(0.1, 0.5, 0.0)
var _shot_cooldown := 0.0
var _spit_cooldown := 0.0
var _zones: Array[Area3D] = []
var _aim_dots: Array[MeshInstance3D] = []
var _mouth_reach := 0.1

var _turret_range_deg := 64.3
var _turret_speed := 85.0
var _lever_stowed := 0.0
var _lever_deployed := 90.0
var _lever_speed := 240.0
var _lever_signs := [-1.0, 1.0]
var _lever_cad_deg := 0.0
var _lever_len := 0.1835
var _lever_pivots: Array = [Vector3(0, 0.156, -0.162), Vector3(0, 0.156, 0.162)]
var turret_home_deg := 90.0

var _visual: Node3D
var _shape: CollisionShape3D
var _shell: MeshInstance3D
var _turret_node: Node3D
var _lever_nodes: Array[Node3D] = []
var _hood_node: Node3D
var _flywheel_node: Node3D
var _top_wheel_node: Node3D
var _cad_line_deg := 22.7
var _top_ratio := 2.25
var _spin_per_speed := 0.0
const Ballistics := preload("res://scripts/ballistics.gd")

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 1
	collision_mask = 1  # walls, flowers, hive frame; pollen (layer 2) never blocks the robot, the robot pushes it
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
	turret_continuous = bool(Config.value("turret.continuous", true))
	_turret_range_deg = Config.num("turret.servo_range_deg", 300.0) * ratio
	_turret_speed = Config.num("turret.servo_speed_deg_per_s", 400.0) * ratio
	_lever_stowed = Config.num("levers.stowed_deg", 0.0)
	_lever_deployed = Config.num("levers.deployed_deg", 90.0)
	lever_front_deg = _lever_stowed
	lever_back_deg = _lever_stowed
	_lever_speed = Config.num("levers.speed_deg_per_s", 240.0)
	_lever_signs = [Config.num("levers.front_deploy_sign", -1.0), Config.num("levers.back_deploy_sign", 1.0)]
	_lever_cad_deg = Config.num("levers.cad_pose_deg", 0.0)
	_lever_len = Config.num("levers.length_m", 0.1835)
	_lever_pivots = [_vec("levers.front_pivot_m", Vector3(0, 0.156, -0.162)), _vec("levers.back_pivot_m", Vector3(0, 0.156, 0.162))]
	turret_home_deg = Config.num("turret.home_deg", 90.0)
	_odo_left_off = Config.inches("odometry.forward_pod_left_offset_in", -5.159)
	_odo_fwd_off = Config.inches("odometry.strafe_pod_forward_offset_in", -3.497)
	_feeder_cap = int(Config.num("intakes.feeder_capacity", 3))
	_total_cap = int(Config.num("intakes.total_capacity", 3))
	_transit_s = Config.num("intakes.feeder_transit_s", 0.5)
	_mouth_width = Config.inches("intakes.mouth_width_in", 12.0)
	_mouth_reach = Config.inches("intakes.mouth_reach_in", 4.0)
	flywheel_max_rpm = Config.num("shooter.flywheel_max_rpm", 3000.0)
	_fly_r = Config.inches("shooter.flywheel_diameter_in", 4.0) / 2.0
	_top_r = Config.inches("shooter.top_wheel_diameter_in", 3.0) / 2.0
	_top_ratio = Config.num("shooter.top_wheel_speed_ratio", 2.25)
	_omega_max = flywheel_max_rpm / 60.0 * TAU
	_exit_per_omega = _fly_r * Config.num("shooter.exit_speed_fraction", 0.35)
	_exit_speed_max = _omega_max * _exit_per_omega
	_wheel_gap = Config.num("shooter.wheel_gap_mm", 54.3) / 1000.0
	# What has to be kept spinning: the flywheel weights and the bottom wheels on the motor shaft, plus the
	# top wheels, which turn faster and so count for (ratio squared) times their own inertia.
	var disc_r := Config.num("shooter.flywheel_weight_diameter_mm", 71.0) / 2000.0
	_fly_inertia = Config.num("shooter.flywheel_weight_count", 2.0) * 0.5 * Config.num("shooter.flywheel_weight_kg", 0.125) * disc_r * disc_r \
		+ Config.num("shooter.wheel_count", 2.0) * 0.5 * Config.num("shooter.wheel_mass_kg", 0.085) * _fly_r * _fly_r \
		+ Config.num("shooter.top_wheel_count", 2.0) * 0.5 * Config.num("shooter.top_wheel_mass_kg", 0.05) * _top_r * _top_r * _top_ratio * _top_ratio
	_motor_torque = Config.num("shooter.motor_count", 2.0) * Config.num("shooter.motor_stall_torque_nm", 0.144)
	velocity_hold = bool(Config.value("shooter.velocity_control", true))
	_hold_gain = Config.num("shooter.velocity_gain", 20.0)
	_wheel_grip = Config.num("shooter.wheel_grip", 0.8)
	_feeder_push = Config.num("intakes.feeder_push_n", 5.0)
	_slip_factor = Config.num("shooter.slip_energy_factor", 2.0)
	_push_cache = {}
	_min_shoot = Config.num("shooter.min_speed_fraction_to_shoot", 0.2)
	_shot_interval = Config.num("shooter.shot_interval_s", 0.25)
	_hood_min = Config.num("shooter.hood_min_deg", 30.0)
	_hood_max = Config.num("shooter.hood_max_deg", 60.0)
	_hood_speed = Config.num("shooter.hood_speed_deg_per_s", 90.0)
	_exit_offset = _vec("shooter.exit_offset_m", Vector3(0.1, 0.5, 0.0))
	_cad_line_deg = Config.num("shooter.cad_wheel_line_deg", 22.7)
	# Spin the ball leaves with. Rolling between two surfaces moving at different speeds gives
	# spin = (difference in surface speed) / (ball diameter); this is that difference per m/s of exit speed.
	var surf_ratio := _top_ratio * _top_r / _fly_r
	var fly_surface_per_exit := 1.0 / maxf(Config.num("shooter.exit_speed_fraction", 0.8), 0.01)
	_spin_per_speed = (surf_ratio - 1.0) * fly_surface_per_exit
	_build_body()
	_build_intake_zones()

func reset_pose() -> void:
	set_pose_ftc(Config.num("robot.start_x_in", -58.0), Config.num("robot.start_y_in", -48.0),
		Config.num("robot.start_heading_deg", 0.0))
	for i in 4:
		wheel_powers[i] = 0.0
		wheel_angles[i] = 0.0
	turret_servo = 0.5
	turret_goal_deg = turret_home_deg
	turret_deg = turret_home_deg
	lever_front_servo = 0.0
	lever_back_servo = 0.0
	intake_front_power = 0.0
	intake_back_power = 0.0
	shooter_power = 0.0
	gate_open = true
	odo_forward = 0.0
	odo_strafe = 0.0
	hood_servo = 0.5
	flywheel_fraction = 0.0
	shots_fired = 0
	feeders = [[], []]
	jam_reason = ""
	last_shot = {}
	_jam_timer = 0.0

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
	if turret_continuous:
		var goal := turret_goal_deg
		if aim_point != null:
			# The shooter looks along the turret's +X; find the turret angle that points +X at the target.
			var v: Vector3 = global_transform.basis.inverse() * (aim_point - global_position)
			goal = rad_to_deg(atan2(-v.z, v.x))
			turret_goal_deg = goal
		# Take the short way round.
		var diff := wrapf(goal - turret_deg, -180.0, 180.0)
		turret_deg = wrapf(turret_deg + clampf(diff, -_turret_speed * dt, _turret_speed * dt), -180.0, 180.0)
	else:
		var turret_goal := turret_home_deg + (clampf(turret_servo, 0.0, 1.0) - 0.5) * _turret_range_deg
		turret_deg = move_toward(turret_deg, turret_goal, _turret_speed * dt)
	lever_front_deg = move_toward(lever_front_deg, lerpf(_lever_stowed, _lever_deployed, clampf(lever_front_servo, 0.0, 1.0)), _lever_speed * dt)
	lever_back_deg = move_toward(lever_back_deg, lerpf(_lever_stowed, _lever_deployed, clampf(lever_back_servo, 0.0, 1.0)), _lever_speed * dt)
	if _turret_node:
		_turret_node.rotation.y = deg_to_rad(turret_deg)
	if _hood_node:
		# The shot leaves at right angles to the line between the two wheel centres, so a shot angle of
		# hood_deg means that line is at (90 - hood_deg); the CAD has it at cad_wheel_line_deg.
		_hood_node.rotation.z = -deg_to_rad((90.0 - hood_deg) - _cad_line_deg)
	if _flywheel_node and _top_wheel_node:
		# Slowed down a lot so you can see them turn: the real wheels do thousands of rpm.
		var turn := flywheel_fraction * 60.0 * dt
		_flywheel_node.rotation.z -= turn
		_top_wheel_node.rotation.z += turn * _top_ratio
	if _lever_nodes.size() == 2:
		# The models are exported folded out by cad_pose_deg, so turn them back by that much.
		_lever_nodes[0].rotation.x = deg_to_rad(lever_front_deg - _lever_cad_deg) * _lever_signs[0]
		_lever_nodes[1].rotation.x = deg_to_rad(lever_back_deg - _lever_cad_deg) * _lever_signs[1]

## Load the robot with its starting pollen, split between the two feeders.
func preload_pollen() -> void:
	feeders = [[], []]
	var n := mini(int(Config.num("intakes.preload", 0)), _total_cap)
	for i in n:
		var f: Array = feeders[i % 2]
		if f.size() < _feeder_cap:
			f.append({"p": 1.0 - 0.25 * f.size(), "kind": "pollen"})

## Put a ball straight into a feeder (tests, practice set-ups). Returns false when there is no room.
func load_ball(feeder: int, kind := "pollen", progress := 1.0) -> bool:
	if feeders[feeder].size() >= _feeder_cap or held_total() >= _total_cap:
		return false
	feeders[feeder].append({"p": progress, "kind": kind})
	return true

## How many of the held balls are of this kind ("nectar" counts both colours).
func held_of(kind: String) -> int:
	var n := 0
	for f in feeders:
		for b in f:
			if str(b["kind"]).begins_with(kind):
				n += 1
	return n

## The ball that will be shot next: the one furthest up either feeder ("pollen" when the robot is empty).
func next_kind() -> String:
	var best := -1.0
	var kind := "pollen"
	for f in feeders:
		if f.size() > 0 and float(f[0]["p"]) > best:
			best = f[0]["p"]
			kind = f[0]["kind"]
	return kind

## The outer edge of each deployed lever, as [end_a, end_b] in world space (for touching flowers).
func deployed_lever_bars() -> Array:
	var out: Array = []
	var degs := [lever_front_deg, lever_back_deg]
	for i in 2:
		if degs[i] < _lever_deployed - 8.0:   # only a lever that is (nearly) fully out works a flower
			continue
		var a := deg_to_rad(degs[i])
		var p: Vector3 = _lever_pivots[i]
		# Upright at 0 deg, swinging outward (front lever towards -z, back lever towards +z).
		var tip := Vector3(0, p.y + _lever_len * cos(a), p.z + signf(p.z) * _lever_len * sin(a))
		out.append([global_transform * (tip + Vector3(-width / 2.0, 0, 0)), global_transform * (tip + Vector3(width / 2.0, 0, 0))])
	return out

## Turret angle as the driver thinks of it: 0 = the shooter's home direction (straight ahead).
func turret_from_home_deg() -> float:
	return wrapf(turret_deg - turret_home_deg, -180.0, 180.0)

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
		# Reaches a little way out in front of the chassis, so a ball is caught even at full speed.
		box.size = Vector3(_mouth_width, 0.12, _mouth_reach + 0.04)
		cs.shape = box
		area.add_child(cs)
		area.position = Vector3(0, 0.06, sgn * (length / 2.0 + _mouth_reach / 2.0 - 0.02))
		add_child(area)
		_zones.append(area)

func _update_game_pieces(dt: float) -> void:
	var powers := [intake_front_power if enabled else 0.0, intake_back_power if enabled else 0.0]
	# Flywheel: a DC motor's torque falls off as it speeds up (stall torque at rest, nothing at free
	# speed), and it has the whole spinning mass to turn. With velocity hold the controller pushes at
	# full voltage until the wanted speed is reached; with plain power it only ever gets `target` volts.
	var target := clampf(shooter_power, 0.0, 1.0) if enabled else 0.0
	var volts := target
	if velocity_hold and target > 0.0:
		volts = clampf(target + _hold_gain * (target - flywheel_fraction), 0.0, 1.0)
	if _jam_timer > 0.0:
		_jam_timer = maxf(_jam_timer - dt, 0.0)   # a ball is wedged against the wheels
		flywheel_fraction = 0.0
	else:
		flywheel_fraction = maxf(flywheel_fraction + _motor_torque * (volts - flywheel_fraction) / (_fly_inertia * _omega_max) * dt, 0.0)
		if jam_reason != "" and held_total() == 0:
			jam_reason = ""
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
				if body.is_in_group("balls") and not body.is_queued_for_deletion():
					balls.append({"p": 0.0, "kind": pollen.kind_of(body)})
					pollen.remove_ball(body)
		# Carry balls up the feeder; they queue behind each other.
		if power > 0.1:
			for k in balls.size():
				balls[k]["p"] = minf(balls[k]["p"] + power * dt / _transit_s, 1.0 - 0.25 * k)
			# Ball at the neck + flywheel spinning = it meets the wheels.
			if gate_open and balls.size() > 0 and balls[0]["p"] >= 1.0 and flywheel_fraction >= _min_shoot and _shot_cooldown <= 0.0 and _jam_timer <= 0.0:
				var kind: String = balls[0]["kind"]
				var res := shot_physics(kind, flywheel_fraction)
				if res["ok"]:
					balls.pop_front()
					jam_reason = ""
					_launch(kind, res)
				else:
					# The wheels cannot get it through: it stalls them and is pushed back down a little.
					jam_reason = res["reason"]
					_jam_timer = 0.4
					_shot_cooldown = 0.4
					balls[0]["p"] = 0.8
		elif power < -0.1 and balls.size() > 0 and _spit_cooldown <= 0.0:
			# Reverse: spit the newest ball back out of the intake.
			var spat: Dictionary = balls.pop_back()
			_spit_cooldown = 0.3
			if pollen != null:
				var sgn := -1.0 if i == 0 else 1.0
				var out := global_transform.basis.z * sgn
				var r: float = pollen.props(spat["kind"])["radius"]
				pollen.spawn_ball(global_position + out * (length / 2.0 + r + 0.055) + Vector3(0, r + 0.014, 0), velocity + out * 1.0, self, Vector3.ZERO, spat["kind"])

## Where a ball leaves the shooter, how fast, and with what spin: [position, velocity, spin] in world space.
## The shooter points along the turret's +X (the camera side), tilted up by the hood angle. The faster top
## wheel gives the ball topspin about the turret's sideways axis.
## `power_fraction` is the flywheel's speed (as a fraction of full speed) when the ball reaches it; the
## ball's own weight and squeeze slow the wheels a little on the way through (see shot_physics).
func shot_state_for(power_fraction: float, hood_angle_deg: float, kind := "") -> Array:
	var turret_basis := global_transform.basis * Basis(Vector3.UP, deg_to_rad(turret_deg))
	var a := deg_to_rad(hood_angle_deg)
	var dir := (turret_basis.x * cos(a) + Vector3.UP * sin(a)).normalized()
	if kind == "":
		kind = next_kind()
	var res := shot_physics(kind, power_fraction)
	var speed: float = res["speed"]
	return [global_position + turret_basis * _exit_offset, velocity + dir * speed, -turret_basis.z * (speed * _spin_rate(kind))]

func shot_state() -> Array:
	return shot_state_for(flywheel_fraction, hood_deg)

## Spin (rad/s) a ball of this kind leaves with, per m/s of exit speed.
func _spin_rate(kind: String) -> float:
	var b := _ball(kind)
	return _spin_per_speed / (2.0 * float(b["radius"])) * float(b["spin_efficiency"])

func _ball(kind: String) -> Dictionary:
	if pollen != null:
		return pollen.props(kind)
	return {"radius": 0.0356, "mass": 0.0125, "squeeze_force_n": 45.0, "squeeze_loss": 0.3, "spin_efficiency": 0.6}

## How far the two shooter wheels squash a ball of this kind (metres), from the gap between them.
func squeeze_m(kind: String) -> float:
	return maxf(2.0 * float(_ball(kind)["radius"]) - _wheel_gap, 0.0)

## The push from behind a ball needs before the wheels pull it in by themselves. As the ball arrives the
## wheels touch it at a slant: they push it back (the slanted squeeze) and drag it in (grip). A big ball
## meets them at a steeper slant, so it needs more grip, or a shove from the feeder.
func push_needed_n(kind: String) -> float:
	if _push_cache.has(kind):
		return _push_cache[kind]
	_push_cache[kind] = _push_needed_n(kind)
	return _push_cache[kind]

func _push_needed_n(kind: String) -> float:
	var b := _ball(kind)
	var r: float = b["radius"]
	var side := squeeze_m(kind) / 2.0
	if side <= 0.0:
		return 0.0
	var stiffness: float = float(b["squeeze_force_n"]) / side
	var worst := 0.0
	var steps := 240
	for i in steps:
		var x := -(_fly_r + r) * (1.0 - float(i) / steps)   # distance still to go to the narrowest point
		var total := 0.0
		for wheel_r in [_fly_r, _top_r]:
			var y: float = wheel_r + _wheel_gap / 2.0
			var depth := maxf(wheel_r + r - sqrt(x * x + y * y), 0.0)
			var slant := atan2(-x, y)
			total += stiffness * depth * (_wheel_grip * cos(slant) - sin(slant))
		worst = minf(worst, total)
	return maxf(-worst, 0.0)

## What happens when a ball of this kind meets the wheels turning at `fraction` of full speed.
## Returns { ok, reason, speed (ball exit speed, m/s), after (flywheel fraction just after), stored_j, lost_j,
## push_n }. The energy comes out of the spinning wheels:
##  - squashing the ball takes work; most comes back as it springs out, a share (squeeze_loss) is lost;
##  - the ball is dragged up to speed by rubbing: the wheels spend about twice the energy the ball gains.
## If the wheels do not hold enough energy to squash it through, or cannot grip it, it does not go.
func shot_physics(kind: String, fraction: float) -> Dictionary:
	var b := _ball(kind)
	var out := {"ok": false, "reason": "", "speed": 0.0, "after": fraction, "stored_j": 0.0, "lost_j": 0.0, "push_n": 0.0}
	var w0 := fraction * _omega_max
	var stored: float = 2.0 / 3.0 * float(b["squeeze_force_n"]) * squeeze_m(kind)
	var lost: float = stored * float(b["squeeze_loss"])
	out["stored_j"] = stored
	out["lost_j"] = lost
	out["push_n"] = push_needed_n(kind)
	var label := "NECTAR" if kind.begins_with("nectar") else "POLLEN"
	if out["push_n"] > _feeder_push:
		out["reason"] = "%s WON'T FEED - the wheels can't grip it" % label
		return out
	if 0.5 * _fly_inertia * w0 * w0 <= stored:
		out["reason"] = "%s JAMMED - flywheel too slow to squeeze it through" % label
		out["after"] = 0.0
		return out
	# Energy the ball carries away: moving + spinning (a hollow ball: I = 2/3 m r^2).
	var r: float = b["radius"]
	var spin_per_speed := _spin_rate(kind)
	var per_v2: float = 0.5 * float(b["mass"]) * (1.0 + 2.0 / 3.0 * r * r * spin_per_speed * spin_per_speed) * _slip_factor
	var w1_sq := (w0 * w0 - 2.0 * lost / _fly_inertia) / (1.0 + 2.0 * per_v2 * _exit_per_omega * _exit_per_omega / _fly_inertia)
	var w1 := sqrt(maxf(w1_sq, 0.0))
	out["ok"] = true
	out["speed"] = w1 * _exit_per_omega
	out["after"] = w1 / _omega_max
	return out

func max_exit_speed() -> float:
	return _exit_speed_max

func hood_limits_deg() -> Vector2:
	return Vector2(_hood_min, _hood_max)

func is_full() -> bool:
	return held_total() >= _total_cap

func _launch(kind: String, res: Dictionary) -> void:
	_shot_cooldown = _shot_interval
	shots_fired += 1
	var st := shot_state_for(flywheel_fraction, hood_deg, kind)
	last_shot = {"kind": kind, "speed": res["speed"], "rpm_before": flywheel_rpm(), "rpm_after": float(res["after"]) * flywheel_max_rpm}
	flywheel_fraction = res["after"]
	if pollen != null:
		pollen.spawn_ball(st[0], st[1], self, st[2], kind)

## Dotted arc showing where a shot would go with the current flywheel speed, hood and turret.
func _update_aim_dots() -> void:
	if _aim_dots.is_empty():
		var mesh := SphereMesh.new()
		mesh.radius = 0.03
		mesh.height = 0.06
		mesh.radial_segments = 8
		mesh.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 1.0, 0.4)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for i in 28:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.top_level = true
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_aim_dots.append(mi)
	var show := flywheel_fraction > 0.03
	var st := shot_state()
	var p: Vector3 = st[0]
	var v: Vector3 = st[1]
	var b: Dictionary = pollen.props(next_kind()) if pollen != null else {}
	var k_drag: float = b.get("k_drag", 0.0)
	var k_area: float = b.get("k_area", 0.0)
	var lift_max: float = b.get("lift_max", 0.0)
	var rad: float = b.get("radius", 0.036)
	var dt := 0.0125
	for i in _aim_dots.size():
		for sub in 4:
			var acc := Vector3(0, -Ballistics.G, 0) + Ballistics.air_accel(v, st[2], rad, k_drag, k_area, lift_max)
			p += v * dt + 0.5 * acc * dt * dt
			v += acc * dt
		_aim_dots[i].visible = show and p.y > 0.0
		_aim_dots[i].global_position = p

func _physics_process(dt: float) -> void:
	_update_mechanisms(dt)
	_update_game_pieces(dt)
	_update_aim_dots()
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
	# Dead wheels: a pod mounted off-centre also rolls when the robot turns.
	odo_forward += (v_forward - omega * _odo_left_off) * dt
	odo_strafe += (v_left + omega * _odo_fwd_off) * dt

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
	_hood_node = null
	_flywheel_node = null
	_top_wheel_node = null
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
		# The moving parts of the shooter ride on the turret: the flywheel and the hood turn about the
		# flywheel axle, and the top wheel sits on the hood.
		var fly_pos := _vec("shooter.flywheel_pos_m", Vector3(0.078, 0.351, 0))
		_flywheel_node = _add_model("flywheel", _turret_node, fly_pos)
		_hood_node = _add_model("hood", _turret_node, fly_pos)
		_top_wheel_node = _add_model("top_wheel", _hood_node, _vec("shooter.top_wheel_pos_m", Vector3(-0.054, 0.406, 0)) - fly_pos)
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
