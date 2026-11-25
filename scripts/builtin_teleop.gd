extends Node
## Built-in driver-practice TeleOp: reads the gamepad (or keyboard) and sets wheel powers.
## Works with no Java running. Same stick layout most FTC mecanum TeleOps use:
##   left stick = drive/strafe, right stick X = turn, left bumper = slow mode.

var robot  # scripts/robot.gd
var active := true
var field_centric := false
## Player's-view driving: which way "up on the screen" points on the field (flat, world space).
## Main sets it from the camera in use, so W always drives away from you whatever way the robot faces.
var view_forward := Vector3(1, 0, 0)
var heading_offset := 0.0
var slow := false

var _deadzone := 0.05
var _slow_scale := 0.4
var _turn_scale := 1.0
var _turret_rate := 0.6
var _hood_rate := 0.8
var flywheel_on := false
var auto_aim := true
## Where shots should land (the raised cell's mouth); set by main. Used for the automatic hood.
var shot_target = null
## Which way that mouth faces; a shot can only go in from in front of it.
var shot_outward := Vector3.ZERO
var _mouth_half_angle := 75.0
## What the automatic hood decided: "" = not in use, otherwise a short status for the HUD.
var auto_shot_status := ""
var _auto_power := 1.0
var _manual_power := 0.22
const Ballistics := preload("res://scripts/ballistics.gd")
var _plan := {}
var _plan_age := 1.0
var _plan_kind := ""
var _min_descent := 30.0
var _speed_tol := 0.04
var _turret_manual_rate := 90.0
## Shooting on the move. A ball keeps the robot's own speed when it leaves, so a shot aimed straight at
## the hive from a moving robot drifts off by (robot speed x flight time). With `lead_shots` on, the
## turret aims where the hive "will be" as seen from the robot: `aim_lead` is how far the aim is moved.
var lead_shots := true
var aim_lead := Vector3.ZERO
var _aim_tol := 3.0

func _ready() -> void:
	apply_config()
	field_centric = bool(Config.value("driver.field_centric_default", false))
	auto_aim = bool(Config.value("driver.auto_aim_default", true))

func apply_config() -> void:
	_deadzone = Config.num("driver.stick_deadzone", 0.05)
	_slow_scale = Config.num("driver.slow_mode_scale", 0.4)
	_turn_scale = Config.num("driver.turn_scale", 1.0)
	_turret_rate = Config.num("driver.turret_nudge_per_s", 0.6)
	_hood_rate = Config.num("driver.hood_nudge_per_s", 0.8)
	_manual_power = Config.num("driver.manual_shooter_power", 0.22)
	_speed_tol = Config.num("driver.shoot_speed_tolerance", 0.04)
	_min_descent = Config.num("driver.auto_min_descent_deg", 30.0)
	_turret_manual_rate = Config.num("driver.turret_manual_deg_per_s", 90.0)
	lead_shots = bool(Config.value("driver.lead_moving_shots", true))
	_aim_tol = Config.num("driver.shoot_aim_tolerance_deg", 3.0)

func gamepad_id() -> int:
	var pads := Input.get_connected_joypads()
	return pads[0] if pads.size() > 0 else -1

func gamepad_name() -> String:
	var id := gamepad_id()
	return Input.get_joy_name(id) if id >= 0 else ""

## Kept for older callers; player's-view driving follows the camera and needs no reset.
func reset_field_heading() -> void:
	heading_offset = robot.rotation.y

func _dz(v: float) -> float:
	if absf(v) < _deadzone:
		return 0.0
	return signf(v) * (absf(v) - _deadzone) / (1.0 - _deadzone)

func _key_axis(neg: Key, pos: Key) -> float:
	return (1.0 if Input.is_physical_key_pressed(pos) else 0.0) - (1.0 if Input.is_physical_key_pressed(neg) else 0.0)

## Returns [forward, strafe_right, turn_right], each -1..1.
func read_sticks() -> Array[float]:
	var f := _key_axis(KEY_S, KEY_W)
	var s := _key_axis(KEY_A, KEY_D)
	var t := _key_axis(KEY_Q, KEY_E)
	slow = Input.is_physical_key_pressed(KEY_CTRL)
	var id := gamepad_id()
	if id >= 0:
		f += _dz(-Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
		s += _dz(Input.get_joy_axis(id, JOY_AXIS_LEFT_X))
		t += _dz(Input.get_joy_axis(id, JOY_AXIS_RIGHT_X))
		slow = slow or Input.is_joy_button_pressed(id, JOY_BUTTON_LEFT_SHOULDER)
	return [clampf(f, -1, 1), clampf(s, -1, 1), clampf(t, -1, 1)]

## Standard mecanum mix. Returns [FL, FR, BL, BR] powers.
static func mix(f: float, s: float, t: float) -> Array[float]:
	var d := maxf(absf(f) + absf(s) + absf(t), 1.0)
	return [(f + s + t) / d, (f - s - t) / d, (f - s + t) / d, (f + s - t) / d]

func compute_powers(f: float, s: float, t: float) -> Array[float]:
	if field_centric:
		# The stick says where to go as the player sees it; turn that into the robot's own forward/right.
		var view_right := view_forward.cross(Vector3.UP)
		var want := view_forward * f + view_right * s
		var robot_fwd: Vector3 = -robot.global_transform.basis.z
		var robot_right: Vector3 = robot.global_transform.basis.x
		f = want.dot(robot_fwd)
		s = want.dot(robot_right)
	var scale := _slow_scale if slow else 1.0
	return mix(f * scale, s * scale, t * _turn_scale * scale)

func read_turret() -> float:
	var t := _key_axis(KEY_X, KEY_Z)
	var id := gamepad_id()
	if id >= 0:
		t += (1.0 if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_LEFT) else 0.0) - (1.0 if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_RIGHT) else 0.0)
	return clampf(t, -1.0, 1.0)

func _pad_btn(b: JoyButton) -> float:
	var id := gamepad_id()
	return 1.0 if id >= 0 and Input.is_joy_button_pressed(id, b) else 0.0

func _pad_axis(a: JoyAxis) -> float:
	var id := gamepad_id()
	return Input.get_joy_axis(id, a) if id >= 0 else 0.0

## Pick the hood angle and flywheel speed that land a shot on `target`. It flies each candidate shot
## through the same air model the real balls use (gravity, drag, spin), so the answer allows for the dip
## the topspin causes. Prefers the steepest arc, so the ball drops into the cell instead of flying in
## flat and bouncing back out. Returns { ok, reason, hood_servo, power }.
func compute_shot(target: Vector3) -> Dictionary:
	var start: Vector3 = robot.shot_state()[0]
	# On the move: work it out as the robot sees it. From a robot driving at v, the hive seems to come
	# towards it at -v, so aim at where it will seem to be when the ball gets there.
	var drift := Vector3(robot.velocity.x, 0, robot.velocity.z)
	var leading := lead_shots and drift.length() > 0.02
	aim_lead = Vector3.ZERO
	if leading:
		aim_lead = -drift * float(_plan.get("flight_s", 0.6))
		target += aim_lead
	var flat := Vector2(target.x - start.x, target.z - start.z)
	var d := flat.length()
	var h := target.y - start.y
	var lim: Vector2 = robot.hood_limits_deg()
	# No shot possible: say why, and leave the hood where it is (no "hood_servo" in the answer).
	var fallback := {"ok": false, "reason": "OUT OF RANGE", "power": _manual_power}
	if shot_outward != Vector3.ZERO and d > 0.01:
		var from_mouth := Vector3(-flat.x, 0, -flat.y).normalized()
		if rad_to_deg(from_mouth.angle_to(shot_outward)) > _mouth_half_angle:
			fallback["reason"] = "WRONG SIDE OF HIVE"
			return fallback
	if rad_to_deg(atan2(h, d)) > 40.0:
		fallback["reason"] = "TOO CLOSE - back away from the hive"
	else:
		fallback["reason"] = "TOO FAR - drive closer"
	# Aim for the ball that is next in line: a nectar is heavier, slows the wheels more and flies further.
	var kind: String = robot.next_kind()
	var ball: Dictionary = robot.pollen.props(kind) if robot.pollen != null else {}
	var rad: float = ball.get("radius", 0.036)
	var k_drag: float = ball.get("k_drag", 0.0)
	var k_area: float = ball.get("k_area", 0.0)
	var lift_max: float = ball.get("lift_max", 0.0)
	var height := func(power: float, deg: float) -> Array:
		var st: Array = robot.shot_state_for(power, deg, kind, not leading)
		return Ballistics.height_at(st[0], st[1], st[2], d, rad, k_drag, k_area, lift_max)
	# Try every hood angle. For each one, find the flywheel speed that reaches the cell, and note how
	# steeply the ball is coming down when it gets there.
	var best := {}        # least power among shots that arrive steeply enough
	var steepest := {}    # the steepest arrival of all, used when none is steep enough
	var steepest_descent := -INF
	var deg := lim.y
	while deg >= lim.x - 0.001:
		var top: Array = height.call(1.0, deg)
		if top[2] and top[0] >= target.y:
			# More power always carries the ball higher at the target's distance, so search the power in halves.
			var lo := 0.02
			var hi := 1.0
			for i in 12:
				var mid := (lo + hi) / 2.0
				var r: Array = height.call(mid, deg)
				if r[2] and r[0] >= target.y:
					hi = mid
				else:
					lo = mid
			var hit: Array = height.call(hi, deg)
			var descent := rad_to_deg(atan2(-hit[1], maxf(hit[3], 0.001)))
			var plan := {"ok": true, "reason": "auto", "hood_servo": inverse_lerp(lim.x, lim.y, deg), "power": hi, "descent_deg": descent, "flight_s": hit[4]}
			if descent >= _min_descent and (best.is_empty() or hi < best["power"]):
				best = plan
			if descent > steepest_descent:
				steepest_descent = descent
				steepest = plan
		deg -= 1.5
	if not best.is_empty():
		return best
	if not steepest.is_empty():
		# Reachable, but the ball arrives too flat (or still rising): it would bounce back out.
		if steepest_descent <= 0.0:
			steepest["ok"] = false
			steepest["reason"] = "TOO CLOSE - back away from the hive"
		return steepest
	return fallback

func toggle_lever(front: bool) -> void:
	if not active or not robot.enabled:
		return
	if front:
		robot.lever_front_servo = 0.0 if robot.lever_front_servo > 0.5 else 1.0
	else:
		robot.lever_back_servo = 0.0 if robot.lever_back_servo > 0.5 else 1.0

func _physics_process(dt: float) -> void:
	if not active or robot == null:
		return
	if robot.enabled:
		var hood := _key_axis(KEY_DOWN, KEY_UP) + _pad_btn(JOY_BUTTON_DPAD_UP) - _pad_btn(JOY_BUTTON_DPAD_DOWN)
		var intake := maxf(_pad_axis(JOY_AXIS_TRIGGER_LEFT), 1.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 0.0)
		var shoot := maxf(_pad_axis(JOY_AXIS_TRIGGER_RIGHT), 1.0 if Input.is_physical_key_pressed(KEY_SPACE) else 0.0) > 0.3
		var reverse := Input.is_physical_key_pressed(KEY_B) or _pad_btn(JOY_BUTTON_RIGHT_SHOULDER) > 0.0
		run_mechanisms(dt, read_turret(), hood, intake, shoot, reverse)
	else:
		flywheel_on = false
	var in_ := read_sticks()
	robot.wheel_powers = compute_powers(in_[0], in_[1], in_[2])

## How far the turret still is from where it should point, in degrees.
func turret_error_deg() -> float:
	return absf(wrapf(robot.turret_goal_deg - robot.turret_deg, -180.0, 180.0))

## Everything except the wheels: turret, hood, flywheel, feeders and gate, from the driver's inputs.
func run_mechanisms(dt: float, turret_in: float, hood_in: float, intake: float, shoot: bool, reverse: bool) -> void:
	# Turret: moving it by hand switches auto-aim off; the auto-aim button switches it back on.
	if turret_in != 0.0:
		auto_aim = false
	robot.turret_servo = clampf(robot.turret_servo + turret_in * _turret_rate * dt, 0.0, 1.0)
	robot.turret_goal_deg = wrapf(robot.turret_goal_deg + turret_in * _turret_manual_rate * dt, -180.0, 180.0)
	# Hood: set automatically while auto-aim is on, otherwise D-pad up/down or arrow keys.
	_auto_power = _manual_power
	auto_shot_status = ""
	if auto_aim and shot_target != null:
		# Working out a shot flies a few dozen trial arcs, so do it ten times a second, not every tick
		# (twenty when the robot is moving and the answer changes quickly).
		_plan_age += dt
		var every := 0.05 if robot.velocity.length() > 0.1 else 0.1
		if _plan.is_empty() or _plan_age >= every or _plan_kind != robot.next_kind():
			_plan = compute_shot(shot_target)
			_plan_kind = robot.next_kind()
			_plan_age = 0.0
		var shot := _plan
		if shot.has("hood_servo"):
			robot.hood_servo = shot["hood_servo"]
		_auto_power = shot["power"]
		auto_shot_status = shot["reason"]
	else:
		aim_lead = Vector3.ZERO
		robot.hood_servo = clampf(robot.hood_servo + hood_in * _hood_rate * dt, 0.0, 1.0)
	# The flywheel runs all the time. Intake pulls balls in on both sides with the gate shut; shoot
	# opens the gate and feeds them to the flywheel.
	flywheel_on = true
	robot.shooter_power = _auto_power
	# With auto-aim, hold fire until the flywheel is at the speed the shot needs and the turret has
	# caught up with where it should point (it falls behind when the robot moves or turns fast).
	var ready := auto_shot_status == "" or (absf(robot.flywheel_fraction - robot.shooter_power) <= _speed_tol * maxf(robot.shooter_power, 0.05) and turret_error_deg() <= _aim_tol)
	if auto_shot_status == "auto" and turret_error_deg() > _aim_tol:
		auto_shot_status = "auto - TURRET CATCHING UP"
	robot.gate_open = shoot and ready
	var feed := -1.0 if reverse else maxf(intake, 1.0 if shoot else 0.0)
	robot.intake_front_power = feed
	robot.intake_back_power = feed
