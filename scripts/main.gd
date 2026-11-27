extends Node3D
## Builds the whole simulator scene and wires the pieces together.

const RobotScript := preload("res://scripts/robot.gd")
const FieldScript := preload("res://scripts/field.gd")
const TeleopScript := preload("res://scripts/builtin_teleop.gd")
const TimerScript := preload("res://scripts/match_timer.gd")
const HudScript := preload("res://scripts/hud.gd")
const PollenScript := preload("res://scripts/pollen.gd")
const BridgeScript := preload("res://scripts/java_bridge.gd")
const RunnerScript := preload("res://scripts/java_runner.gd")
const TagCameraScript := preload("res://scripts/tag_camera.gd")

var field
var robot
var teleop
var match_timer
var hud
var pollen
var bridge
var java_runner
var tag_camera
var _menu: Array = []   # OpModes offered in the Java menu; empty = menu closed
var _menu_open := false
## From the command line:  --opmode="Name"  launches that Java OpMode at startup, and  --start  presses
## start for it as soon as it reaches INIT. Put them after  --  so Godot passes them on.
var _auto_opmode := ""
var _auto_start := false
var _java_was_connected := false
var _alliance := "red"
## Set by tests that drive the robot themselves, so the built-in TeleOp stays off.
var _external_control := false

var _cams: Array[Camera3D] = []
var _cam_names := ["Driver station", "Top-down", "Chase"]
var _cam_index := 0

func _ready() -> void:
	_alliance = "blue" if str(Config.value("driver.alliance", "red")) == "blue" else "red"
	_build_world()
	field = FieldScript.new()
	add_child(field)
	pollen = PollenScript.new()
	pollen.name = "Pollen"
	add_child(pollen)
	field.reset_elements(pollen)
	robot = RobotScript.new()
	robot.name = "Robot"
	robot.pollen = pollen
	add_child(robot)
	robot.preload_pollen()
	match_timer = TimerScript.new()
	match_timer.name = "MatchTimer"
	add_child(match_timer)
	teleop = TeleopScript.new()
	teleop.name = "BuiltinTeleop"
	teleop.robot = robot
	add_child(teleop)
	teleop.reset_field_heading()
	tag_camera = TagCameraScript.new()
	tag_camera.name = "TagCamera"
	tag_camera.robot = robot
	tag_camera.field = field
	add_child(tag_camera)
	bridge = BridgeScript.new()
	bridge.name = "JavaBridge"
	bridge.robot = robot
	bridge.tag_camera = tag_camera
	add_child(bridge)
	java_runner = RunnerScript.new()
	java_runner.name = "JavaRunner"
	add_child(java_runner)
	hud = HudScript.new()
	add_child(hud)
	_build_cameras()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--opmode="):
			_auto_opmode = arg.trim_prefix("--opmode=")
		elif arg == "--start":
			_auto_start = true
	if _auto_opmode != "":
		java_runner.launch.call_deferred(_auto_opmode)

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	add_child(sun)

func _build_cameras() -> void:
	var half: float = field.size / 2.0
	# Standing behind our alliance wall (red = left, blue = right), looking across the field.
	var side := 1.0 if str(Config.value("driver.alliance", "red")) == "blue" else -1.0
	var driver := Camera3D.new()
	driver.fov = 50.0
	add_child(driver)
	driver.look_at_from_position(Vector3(side * (half + 1.9), 1.7, 0), Vector3(-side * 0.35, 0, 0))
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = field.size * 1.12
	top.position = Vector3(0, 6, 0)
	top.rotation_degrees = Vector3(-90, 0, 0)
	add_child(top)
	var chase := Camera3D.new()
	chase.fov = 65.0
	add_child(chase)
	_cams = [driver, top, chase]
	_cams[_cam_index].make_current()

## "Up on the screen" for the camera in use, flattened onto the floor.
func _view_forward() -> Vector3:
	var cam := _cams[_cam_index]
	var f := -cam.global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.2:  # looking straight down: use the top of the picture instead
		f = cam.global_transform.basis.y
		f.y = 0.0
	return f.normalized()

func _process(_dt: float) -> void:
	teleop.view_forward = _view_forward()
	var chase := _cams[2]
	var back: Vector3 = robot.global_transform.basis.z
	chase.global_position = chase.global_position.lerp(robot.global_position + back * 1.3 + Vector3(0, 1.0, 0), 0.15)
	chase.look_at(robot.global_position + Vector3(0, 0.2, 0))

	var S = match_timer.State
	var st = match_timer.state
	var banner := ""
	if st == S.AUTO:
		banner = "" if bridge.connected else "Robot idle – press R, then J to run a Java autonomous"
	elif st == S.TRANSITION:
		banner = "Pick up your gamepads"
	elif st == S.ENDED:
		banner = "Press R / Back to reset"
	var clock_color := Color.WHITE
	if st == S.AUTO:
		clock_color = Color(0.5, 0.8, 1.0)
	elif st == S.TELEOP and match_timer.time_left <= 20.0:
		clock_color = Color(1.0, 0.75, 0.2)
	elif st == S.ENDED:
		clock_color = Color(1.0, 0.35, 0.3)
	var pts: Dictionary = field.points()
	hud.update_hud({
		"show_clock": st != S.IDLE,
		"time_left": match_timer.time_left,
		"clock_color": clock_color,
		"state_name": match_timer.state_name(),
		"banner": banner,
		"field_centric": teleop.field_centric,
		"java_driving": bridge.connected,
		"slow": teleop.slow,
		"pose": robot.get_pose_ftc(),
		"speed_in": robot.get_speed() / Config.IN,
		"max_speed_in": robot.max_forward_speed() / Config.IN,
		"camera": _cam_names[_cam_index],
		"gamepad": teleop.gamepad_name(),
		"java": _java_status(),
		"camera_sees": tag_camera.summary(),
		"held_front": robot.held_count(0),
		"held_back": robot.held_count(1),
		"flywheel_rpm": robot.flywheel_rpm(),
		"flywheel_on": teleop.flywheel_on,
		"hood_deg": robot.hood_deg,
		"score": "red %d  (tips %d)     blue %d  (tips %d)" % [pts["red"], field.tips["red"], pts["blue"], field.tips["blue"]],
		"hive": "red %d balls, %.1f g   blue %d balls, %.1f g   (tips at %.0f g)" % [field.cell_count("red", true), field.cell_weight_g("red", true), field.cell_count("blue", true), field.cell_weight_g("blue", true), Config.num("field.hive_tip_weight_g", 100.0)],
		"nectar": "red %d  blue %d waiting off the field" % [field.nectar_reserve["red"], field.nectar_reserve["blue"]],
		"held_nectar": robot.held_of("nectar"),
		"next_kind": robot.next_kind() if robot.held_total() > 0 else "",
		"jam": robot.jam_reason,
		"last_shot": robot.last_shot,
		"turret_deg": robot.turret_from_home_deg(),
		"turret_half_range": robot.turret_range_deg() / 2.0,
		"turret_continuous": robot.turret_continuous,
		"auto_aim": teleop.auto_aim and not bridge.connected,
		"auto_shot": "" if bridge.connected else teleop.auto_shot_status,
		"alliance": _alliance,
		"full": robot.is_full(),
		"lever_fight": "   %s LEVER: ITS TWO SERVOS FIGHT EACH OTHER (reverse one in the code)" % ("FRONT" if robot.lever_fight[0] else "BACK") if (robot.lever_fight[0] or robot.lever_fight[1]) else "",
		"lever_front_deg": robot.lever_front_deg,
		"lever_back_deg": robot.lever_back_deg,
		"size_in": Vector3(Config.num("robot.length_in", 18.0), Config.num("robot.width_in", 18.0), Config.num("robot.height_in", 18.0)),
		"size_limit_in": Config.num("robot.size_limit_in", 18.0),
	})

func _physics_process(_dt: float) -> void:
	# While a Java OpMode is connected it drives the robot; the built-in TeleOp steps aside.
	if _auto_start and bridge.connected and bridge.phase == "init" and bridge.opmode != "":
		_auto_start = false
		_start_pressed()
	if _java_was_connected and not bridge.connected:
		# The OpMode ended (finished, crashed or was stopped): back to free practice.
		match_timer.reset()
	_java_was_connected = bridge.connected
	if bridge.connected:
		teleop.active = false
		robot.enabled = match_timer.state != match_timer.State.ENDED
		if match_timer.state == match_timer.State.ENDED:
			bridge.request_stop()
	else:
		if not teleop.active and not _external_control:
			teleop.active = true
		robot.enabled = match_timer.driver_enabled()
	if teleop.active:  # when something else drives the robot (tests, later the Java bridge) it sets the aim itself
		robot.aim_point = (field.aim_point(_alliance) + teleop.aim_lead) if teleop.auto_aim else null
		teleop.shot_target = field.mouth_point(_alliance)
		teleop.shot_outward = field.mouth_outward(_alliance)
	field.update_flowers(robot, pollen, _dt)
	field.update_hives(_dt)
	# With a minute to go the humans may put all their remaining nectar on the field.
	if match_timer.state == match_timer.State.TELEOP and match_timer.time_left <= 60.0:
		for a in ["red", "blue"]:
			field.enter_nectar(a, 99)

func _java_status() -> String:
	if bridge.connected:
		var head := "JAVA  %s  [%s]" % [bridge.opmode, {"init": "INIT - press Enter / Start to run", "run": "RUNNING", "done": "finished", "error": "CRASHED"}.get(bridge.phase, bridge.phase)]
		return head + ("\n" + bridge.telemetry.strip_edges() if bridge.telemetry.strip_edges() != "" else "")
	if java_runner.running_name != "" and (java_runner.is_running() or java_runner.log_tail != ""):
		return "JAVA  %s  [%s]\n%s" % [java_runner.running_name, "starting..." if java_runner.is_running() else "stopped", java_runner.log_tail]
	return ""

func reset_all() -> void:
	bridge.request_stop()
	java_runner.stop()
	match_timer.reset()
	robot.reset_pose()
	teleop.reset_field_heading()
	teleop.flywheel_on = false
	field.reset_elements(pollen)
	robot.preload_pollen()

func reload_config() -> void:
	Config.load_config()
	bridge.apply_config()
	tag_camera.apply_config()
	pollen.apply_config()
	robot.apply_config()
	teleop.apply_config()
	match_timer.apply_config()
	reset_all()

func _next_camera() -> void:
	_cam_index = (_cam_index + 1) % _cams.size()
	_cams[_cam_index].make_current()

## Enter / Start: with a Java OpMode waiting in INIT this is the Driver Station's play button.
func _start_pressed() -> void:
	if bridge.connected and bridge.phase == "init":
		bridge.request_start()
		if bridge.flavor == "auto":
			match_timer.start_auto_only()
		else:
			match_timer.start_teleop_only()
	elif not bridge.connected:
		match_timer.start_teleop_only()

func _open_java_menu() -> void:
	_menu = java_runner.scan_opmodes()
	_menu_open = true
	var lines := ["RUN A JAVA OPMODE", "from " + java_runner.teamcode_dir(), ""]
	if _menu.is_empty():
		lines.append("No OpModes found (looking for @TeleOp / @Autonomous in .java files).")
	for i in mini(_menu.size(), 9):
		lines.append("%d   %s   (%s)" % [i + 1, _menu[i]["name"], "TeleOp" if _menu[i]["flavor"] == "teleop" else "Autonomous"])
	lines.append("")
	lines.append("Press a number to run it, Esc to close.")
	hud.show_menu("\n".join(lines))

func _close_java_menu() -> void:
	_menu_open = false
	hud.show_menu("")

func _unhandled_input(event: InputEvent) -> void:
	if _menu_open:
		if event is InputEventKey and event.pressed and not event.echo:
			var idx: int = event.physical_keycode - KEY_1
			if idx >= 0 and idx < mini(_menu.size(), 9):
				reset_all()
				java_runner.launch(_menu[idx]["name"])
			_close_java_menu()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if bridge.connected and event.physical_keycode in [KEY_1, KEY_2, KEY_F, KEY_H, KEY_T, KEY_M]:
			return  # these keys belong to the built-in TeleOp; the OpMode reads the gamepad itself
		match event.physical_keycode:
			KEY_J: _open_java_menu()
			KEY_F: teleop.field_centric = not teleop.field_centric
			KEY_ENTER, KEY_KP_ENTER: _start_pressed()
			KEY_M: match_timer.start_full_match()
			KEY_R: reset_all()
			KEY_C: _next_camera()
			KEY_F5: reload_config()
			KEY_F1: hud.toggle_help()
			KEY_1: teleop.toggle_lever(true)
			KEY_2: teleop.toggle_lever(false)
			KEY_V: robot.toggle_shell()
			KEY_T: teleop.auto_aim = not teleop.auto_aim
			KEY_N: field.enter_nectar(_alliance, 1)   # a human puts one of our waiting nectar in the loading zone
	elif event is InputEventJoypadButton and event.pressed:
		if bridge.connected and not event.button_index in [JOY_BUTTON_START, JOY_BUTTON_BACK]:
			return
		match event.button_index:
			JOY_BUTTON_Y: teleop.field_centric = not teleop.field_centric
			JOY_BUTTON_START: _start_pressed()
			JOY_BUTTON_BACK: reset_all()
			JOY_BUTTON_RIGHT_STICK: teleop.auto_aim = not teleop.auto_aim
			JOY_BUTTON_A: teleop.toggle_lever(true)
			JOY_BUTTON_B: teleop.toggle_lever(false)
