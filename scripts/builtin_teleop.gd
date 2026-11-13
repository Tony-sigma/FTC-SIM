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

func _ready() -> void:
	apply_config()
	field_centric = bool(Config.value("driver.field_centric_default", false))

func apply_config() -> void:
	_deadzone = Config.num("driver.stick_deadzone", 0.05)
	_slow_scale = Config.num("driver.slow_mode_scale", 0.4)
	_turn_scale = Config.num("driver.turn_scale", 1.0)
	_turret_rate = Config.num("driver.turret_nudge_per_s", 0.6)

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
	var t := _key_axis(KEY_Q, KEY_E) + _key_axis(KEY_LEFT, KEY_RIGHT)
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
		robot.turret_servo = clampf(robot.turret_servo + read_turret() * _turret_rate * dt, 0.0, 1.0)
	var in_ := read_sticks()
	robot.wheel_powers = compute_powers(in_[0], in_[1], in_[2])
