extends Node
## Built-in driver-practice TeleOp: reads the gamepad (or keyboard) and sets wheel powers.
## Works with no Java running. Same stick layout most FTC mecanum TeleOps use:
##   left stick = drive/strafe, right stick X = turn, left bumper = slow mode.

var robot  # scripts/robot.gd
var active := true
var field_centric := false
## The robot yaw (Godot rotation.y) that counts as "pointing away from the driver".
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
var _turret_manual_rate := 90.0

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
	_turret_manual_rate = Config.num("driver.turret_manual_deg_per_s", 90.0)

func gamepad_id() -> int:
	var pads := Input.get_connected_joypads()
	return pads[0] if pads.size() > 0 else -1

func gamepad_name() -> String:
	var id := gamepad_id()
	return Input.get_joy_name(id) if id >= 0 else ""

## Make the robot's current facing the new "forward" for field-centric (like an IMU yaw reset).
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
	slow = Input.is_physical_key_pressed(KEY_SHIFT)
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
		var yaw: float = robot.rotation.y - heading_offset
		var rf := f * cos(yaw) - s * sin(yaw)
		var rs := f * sin(yaw) + s * cos(yaw)
		f = rf
		s = rs
	var scale := _slow_scale if slow else 1.0
	return mix(f * scale, s * scale, t * _turn_scale * scale)

## -1 = turret right, +1 = turret left (D-pad left/right, or Z / X keys).
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

func toggle_flywheel() -> void:
	if active and robot.enabled:
		flywheel_on = not flywheel_on

## Pick the hood angle (and, when the hood alone cannot do it, the flywheel speed) that lands a
## shot on `target`. Prefers the steepest arc, so the ball drops into the cell instead of flying in
## flat and bouncing back out.
## Returns { ok, hood_servo, power }.
func compute_shot(target: Vector3) -> Dictionary:
	var start: Vector3 = robot.shot_state()[0]
	var flat := Vector2(target.x - start.x, target.z - start.z)
	var d := flat.length()
	var h := target.y - start.y
	var lim: Vector2 = robot.hood_limits_deg()
	var v_max: float = robot.max_exit_speed()
	var fallback := {"ok": false, "reason": "OUT OF RANGE", "hood_servo": inverse_lerp(lim.x, lim.y, clampf(45.0, lim.x, lim.y)), "power": 1.0}
	if shot_outward != Vector3.ZERO and d > 0.01:
		var from_mouth := Vector3(-flat.x, 0, -flat.y).normalized()
		if rad_to_deg(from_mouth.angle_to(shot_outward)) > _mouth_half_angle:
			fallback["reason"] = "WRONG SIDE OF HIVE"
			return fallback
	var g := 9.8
	# No shot at all is possible either because the mouth is too high above us (too close) or too far off.
	if rad_to_deg(atan2(h, d)) > 40.0:
		fallback["reason"] = "TOO CLOSE - back away from the hive"
		fallback["hood_servo"] = 1.0
	else:
		fallback["reason"] = "TOO FAR - drive closer"
	var deg := lim.y
	var close_call := {}
	while deg >= lim.x - 0.001:
		var a := deg_to_rad(deg)
		var denom := 2.0 * cos(a) * cos(a) * (d * tan(a) - h)
		if denom > 0.0:
			var v := sqrt(g * d * d / denom)
			if v <= v_max:
				var plan := {"ok": true, "reason": "auto", "hood_servo": inverse_lerp(lim.x, lim.y, deg), "power": v / v_max}
				# The ball must already be coming down when it reaches the mouth, or it bounces back out.
				if v * sin(a) - g * d / (v * cos(a)) < 0.0:
					return plan
				if close_call.is_empty():
					plan["ok"] = false
					plan["reason"] = "TOO CLOSE - back away from the hive"
					close_call = plan
		deg -= 0.5
	if not close_call.is_empty():
		return close_call
	# Out of reach: do the best we can (full power, 45 degrees or the nearest the hood allows).
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
		# Turret: moving it by hand switches auto-aim off; the auto-aim button switches it back on.
		var turret_in := read_turret()
		if turret_in != 0.0:
			auto_aim = false
		robot.turret_servo = clampf(robot.turret_servo + turret_in * _turret_rate * dt, 0.0, 1.0)
		robot.turret_goal_deg = wrapf(robot.turret_goal_deg + turret_in * _turret_manual_rate * dt, -180.0, 180.0)
		# Hood: set automatically while auto-aim is on, otherwise D-pad up/down or arrow keys.
		_auto_power = 1.0
		auto_shot_status = ""
		if auto_aim and shot_target != null:
			var shot := compute_shot(shot_target)
			robot.hood_servo = shot["hood_servo"]
			_auto_power = shot["power"]
			auto_shot_status = shot["reason"]
		else:
			var hood := _key_axis(KEY_DOWN, KEY_UP) + _pad_btn(JOY_BUTTON_DPAD_UP) - _pad_btn(JOY_BUTTON_DPAD_DOWN)
			robot.hood_servo = clampf(robot.hood_servo + hood * _hood_rate * dt, 0.0, 1.0)
		# Intakes: right trigger = front (A side), left trigger = back. Hold Ctrl / left-stick click to reverse.
		var rev := -1.0 if (Input.is_physical_key_pressed(KEY_CTRL) or _pad_btn(JOY_BUTTON_LEFT_STICK) > 0.0) else 1.0
		var front := maxf(_pad_axis(JOY_AXIS_TRIGGER_RIGHT), 1.0 if Input.is_physical_key_pressed(KEY_I) else 0.0)
		var back := maxf(_pad_axis(JOY_AXIS_TRIGGER_LEFT), 1.0 if Input.is_physical_key_pressed(KEY_K) else 0.0)
		robot.shooter_power = _auto_power if flywheel_on else 0.0
		# With the automatic hood, hold the feeders until the flywheel is at the speed the shot needs.
		if flywheel_on and auto_shot_status != "" and rev > 0.0 and absf(robot.flywheel_fraction - robot.shooter_power) > 0.015 and robot.held_total() > 0:
			front = 0.0
			back = 0.0
		robot.intake_front_power = front * rev
		robot.intake_back_power = back * rev
	else:
		flywheel_on = false
	var in_ := read_sticks()
	robot.wheel_powers = compute_powers(in_[0], in_[1], in_[2])
