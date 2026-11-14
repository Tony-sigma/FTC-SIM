extends Node
## The simulator end of the link to real Java OpModes (java/sdk/org/ftcsim/SimLink.java).
## One line of JSON each way about 60 times a second: we send encoders, IMU and gamepads,
## the OpMode answers with motor powers and servo positions, by the hardware names in robot_config.json.

var robot  # scripts/robot.gd
var limelight  # scripts/limelight.gd
var connected := false
var opmode := ""
var flavor := ""     # "teleop" or "auto"
var phase := ""      # "init", "run", "done", "error"
var telemetry := ""
var match_time := 0.0

var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _buf := PackedByteArray()
var _tick := 0
var _start := false
var _stop := false
var _prev := {}
var _shooter := [0.0, 0.0]
var _shooter_ticks := 0.0

var _drive: Array = []
var _inverted: Array = []
var _intakes: Array = []
var _shooters: Array = []
var _odo: Array = []
var _levers: Array = []
var _turret := "turretServo"
var _hood := "hoodServo"
var _gate := "gateServo"

func _ready() -> void:
	apply_config()
	var port := int(Config.num("java.port", 7778))
	if _server.listen(port, "127.0.0.1") != OK:
		push_error("Java bridge: could not listen on port %d" % port)

func apply_config() -> void:
	_drive = Config.value("drivetrain.motor_names", ["frontLeft", "frontRight", "backLeft", "backRight"])
	_inverted = Config.value("drivetrain.motor_inverted", [true, false, true, false])
	_intakes = Config.value("intakes.motor_names", ["intakeA", "intakeB"])
	_shooters = Config.value("shooter.motor_names", ["shooterLeft", "shooterRight"])
	_odo = Config.value("odometry.names", ["odoX", "odoY"])
	_levers = Config.value("levers.servo_names", ["leverLeft", "leverRight"])
	_turret = str(Config.value("turret.servo_name", "turretServo"))
	_hood = str(Config.value("shooter.hood_servo_name", "hoodServo"))
	_gate = str(Config.value("shooter.gate_servo_name", "gateServo"))

## Like pressing the start (play) button on the Driver Station.
func request_start() -> void:
	_start = true

func request_stop() -> void:
	_stop = true

func _sign(i: int) -> float:
	return -1.0 if (i < _inverted.size() and bool(_inverted[i])) else 1.0

func _physics_process(dt: float) -> void:
	if _server.is_connection_available():
		if _peer != null:
			_peer.disconnect_from_host()
		_peer = _server.take_connection()
		_peer.set_no_delay(true)
		_on_connect()
	if _peer == null:
		return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_on_disconnect()
		return
	var n := _peer.get_available_bytes()
	if n > 0:
		var got := _peer.get_data(n)
		if got[0] == OK:
			_buf.append_array(got[1])
			var nl := _buf.find(10)
			while nl >= 0:
				var line := _buf.slice(0, nl).get_string_from_utf8()
				_buf = _buf.slice(nl + 1)
				var msg = JSON.parse_string(line)
				if msg is Dictionary:
					_apply(msg)
				nl = _buf.find(10)
	if phase == "run":
		match_time += dt
	_shooter_ticks += robot.flywheel_rpm() / 60.0 * 28.0 * dt
	_tick += 1
	if _tick % 2 == 0:
		_send(_state(dt * 2.0))

func _on_connect() -> void:
	connected = true
	opmode = ""
	flavor = ""
	phase = "init"
	telemetry = ""
	match_time = 0.0
	_start = false
	_stop = false
	_buf = PackedByteArray()
	_prev = {}
	_shooter = [0.0, 0.0]
	_zero_robot()
	var motors := {}
	var drive_max := Config.num("drivetrain.motor_rpm", 312.0) / 60.0 * Config.num("drivetrain.ticks_per_rev", 537.7)
	for name in _drive:
		motors[name] = drive_max
	for name in _intakes:
		motors[name] = Config.num("intakes.motor_rpm", 6000.0) / 60.0 * 28.0
	for name in _shooters:
		motors[name] = robot.flywheel_max_rpm / 60.0 * 28.0
	for name in _odo:
		motors[name] = 0.0
	var servos: Array = [_turret, _hood, _gate]
	servos.append_array(_levers)
	_send({"type": "hello", "motors": motors, "servos": servos, "limelight": str(Config.value("limelight.name", "limelight"))})

func _on_disconnect() -> void:
	_peer = null
	connected = false
	if phase != "error":
		phase = "done"
	_zero_robot()

func _zero_robot() -> void:
	robot.wheel_powers = [0.0, 0.0, 0.0, 0.0]
	robot.intake_front_power = 0.0
	robot.intake_back_power = 0.0
	robot.shooter_power = 0.0
	robot.gate_open = true   # no gate servo in the code = pollen feed straight through
	robot.aim_point = null

func _send(d: Dictionary) -> void:
	if _peer != null:
		_peer.put_data((JSON.stringify(d) + "\n").to_utf8_buffer())

func _apply(msg: Dictionary) -> void:
	opmode = str(msg.get("opmode", opmode))
	flavor = str(msg.get("flavor", flavor))
	phase = str(msg.get("phase", phase))
	telemetry = str(msg.get("telemetry", telemetry))
	var motors: Dictionary = msg.get("motors", {})
	for name in motors:
		var p := clampf(float(motors[name]), -1.0, 1.0)
		var i := _drive.find(name)
		if i >= 0:
			robot.wheel_powers[i] = p * _sign(i)
		elif name == _intakes[0]:
			robot.intake_front_power = p
		elif _intakes.size() > 1 and name == _intakes[1]:
			robot.intake_back_power = p
		elif _shooters.has(name):
			_shooter[_shooters.find(name)] = absf(p)
			robot.shooter_power = (_shooter[0] + _shooter[1]) / 2.0 if _shooter[0] > 0.0 and _shooter[1] > 0.0 else maxf(_shooter[0], _shooter[1])
	var servos: Dictionary = msg.get("servos", {})
	for name in servos:
		var pos := clampf(float(servos[name]), 0.0, 1.0)
		if name == _turret:
			# 0.5 = straight ahead of the shooter's rest position; the full servo travel covers the turret's range.
			robot.turret_servo = pos
			robot.turret_goal_deg = (pos - 0.5) * 360.0
		elif name == _hood:
			robot.hood_servo = pos
		elif name == _gate:
			robot.gate_open = pos > 0.5
		elif name == _levers[0]:
			robot.lever_front_servo = pos
		elif _levers.size() > 1 and name == _levers[1]:
			robot.lever_back_servo = pos

func _encoder(name: String, ticks: float, dt: float) -> Array:
	var before: float = _prev.get(name, ticks)
	_prev[name] = ticks
	return [snappedf(ticks, 0.01), snappedf((ticks - before) / dt, 0.1)]

func _state(dt: float) -> Dictionary:
	var motors := {}
	for i in _drive.size():
		motors[_drive[i]] = _encoder(_drive[i], robot.get_wheel_ticks(i) * _sign(i), dt)
	for name in _intakes:
		motors[name] = [0, 0]
	for name in _shooters:
		motors[name] = _encoder(name, _shooter_ticks, dt)
	var odo_tpm := Config.num("odometry.ticks_per_rev", 2000.0) / (PI * Config.num("odometry.wheel_diameter_mm", 32.0) / 1000.0)
	if _odo.size() >= 2:
		motors[_odo[0]] = _encoder(_odo[0], robot.odo_forward * odo_tpm, dt)
		motors[_odo[1]] = _encoder(_odo[1], robot.odo_strafe * odo_tpm, dt)
	var ll: Array = []
	var ll_pose: Array = []
	if limelight != null:
		for t in limelight.tags:
			ll.append([t["id"], snappedf(t["tx"], 0.01), snappedf(t["ty"], 0.01), snappedf(t["ta"], 0.0001)])
		for v in limelight.botpose:
			ll_pose.append(snappedf(v, 0.0001))
	return {
		"ll": ll, "llpose": ll_pose,
		"type": "state", "t": snappedf(match_time, 0.001), "start": _start, "stop": _stop, "motors": motors,
		"imu": [snappedf(robot.get_pose_ftc().z, 0.001), snappedf(rad_to_deg(robot.omega), 0.01)],
		"gamepad1": _gamepad(0, true), "gamepad2": _gamepad(1, false),
	}

## Gamepad state in FTC terms. With `keys`, the keyboard fills in for a missing gamepad:
## WASD = left stick, Q/E = right stick X, Shift = left trigger, Space = right trigger, Ctrl = left bumper,
## B = right bumper, arrows = D-pad, 1 2 3 4 = A B X Y, T = right-stick click.
func _gamepad(index: int, keys: bool) -> Dictionary:
	var pads := Input.get_connected_joypads()
	var g := {"lx": 0.0, "ly": 0.0, "rx": 0.0, "ry": 0.0, "lt": 0.0, "rt": 0.0}
	var b: Array = []
	if index < pads.size():
		var id: int = pads[index]
		g["lx"] = _dz(Input.get_joy_axis(id, JOY_AXIS_LEFT_X))
		g["ly"] = _dz(Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
		g["rx"] = _dz(Input.get_joy_axis(id, JOY_AXIS_RIGHT_X))
		g["ry"] = _dz(Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y))
		g["lt"] = Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT)
		g["rt"] = Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT)
		var names := {JOY_BUTTON_A: "a", JOY_BUTTON_B: "b", JOY_BUTTON_X: "x", JOY_BUTTON_Y: "y",
			JOY_BUTTON_DPAD_UP: "dpad_up", JOY_BUTTON_DPAD_DOWN: "dpad_down", JOY_BUTTON_DPAD_LEFT: "dpad_left", JOY_BUTTON_DPAD_RIGHT: "dpad_right",
			JOY_BUTTON_LEFT_SHOULDER: "left_bumper", JOY_BUTTON_RIGHT_SHOULDER: "right_bumper",
			JOY_BUTTON_LEFT_STICK: "left_stick_button", JOY_BUTTON_RIGHT_STICK: "right_stick_button", JOY_BUTTON_GUIDE: "guide"}
		for btn in names:
			if Input.is_joy_button_pressed(id, btn):
				b.append(names[btn])
	if keys:
		g["lx"] = clampf(g["lx"] + _key(KEY_D) - _key(KEY_A), -1, 1)
		g["ly"] = clampf(g["ly"] + _key(KEY_S) - _key(KEY_W), -1, 1)
		g["rx"] = clampf(g["rx"] + _key(KEY_E) - _key(KEY_Q), -1, 1)
		g["lt"] = maxf(g["lt"], _key(KEY_SHIFT))
		g["rt"] = maxf(g["rt"], _key(KEY_SPACE))
		var keymap := {KEY_CTRL: "left_bumper", KEY_B: "right_bumper", KEY_UP: "dpad_up", KEY_DOWN: "dpad_down",
			KEY_LEFT: "dpad_left", KEY_RIGHT: "dpad_right", KEY_1: "a", KEY_2: "b", KEY_3: "x", KEY_4: "y", KEY_T: "right_stick_button"}
		for k in keymap:
			if Input.is_physical_key_pressed(k) and not b.has(keymap[k]):
				b.append(keymap[k])
	g["b"] = b
	return g

func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0

func _dz(v: float) -> float:
	return 0.0 if absf(v) < 0.05 else snappedf(v, 0.001)
