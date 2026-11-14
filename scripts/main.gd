extends Node3D
## Builds the whole simulator scene and wires the pieces together.

const RobotScript := preload("res://scripts/robot.gd")
const FieldScript := preload("res://scripts/field.gd")
const TeleopScript := preload("res://scripts/builtin_teleop.gd")
const TimerScript := preload("res://scripts/match_timer.gd")
const HudScript := preload("res://scripts/hud.gd")
const PollenScript := preload("res://scripts/pollen.gd")

var field
var robot
var teleop
var match_timer
var hud
var pollen
var _alliance := "red"

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
	hud = HudScript.new()
	add_child(hud)
	_build_cameras()

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

func _process(_dt: float) -> void:
	var chase := _cams[2]
	var back: Vector3 = robot.global_transform.basis.z
	chase.global_position = chase.global_position.lerp(robot.global_position + back * 1.3 + Vector3(0, 1.0, 0), 0.15)
	chase.look_at(robot.global_position + Vector3(0, 0.2, 0))

	var S = match_timer.State
	var st = match_timer.state
	var banner := ""
	if st == S.AUTO:
		banner = "Robot idle – no autonomous code yet (Phase 5)"
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
	hud.update_hud({
		"show_clock": st != S.IDLE,
		"time_left": match_timer.time_left,
		"clock_color": clock_color,
		"state_name": match_timer.state_name(),
		"banner": banner,
		"field_centric": teleop.field_centric,
		"slow": teleop.slow,
		"pose": robot.get_pose_ftc(),
		"speed_in": robot.get_speed() / Config.IN,
		"max_speed_in": robot.max_forward_speed() / Config.IN,
		"camera": _cam_names[_cam_index],
		"gamepad": teleop.gamepad_name(),
		"held_front": robot.held_count(0),
		"held_back": robot.held_count(1),
		"flywheel_rpm": robot.flywheel_rpm(),
		"flywheel_on": teleop.flywheel_on,
		"hood_deg": robot.hood_deg,
		"score": "red %d  (tips %d)     blue %d  (tips %d)" % [field.score["red"], field.tips["red"], field.score["blue"], field.tips["blue"]],
		"hive": "red up %d low %d   blue up %d low %d" % [field.cell_count("red", true), field.cell_count("red", false), field.cell_count("blue", true), field.cell_count("blue", false)],
		"turret_deg": robot.turret_deg,
		"turret_half_range": robot.turret_range_deg() / 2.0,
		"turret_continuous": robot.turret_continuous,
		"auto_aim": teleop.auto_aim,
		"auto_shot": teleop.auto_shot_status,
		"alliance": _alliance,
		"full": robot.is_full(),
		"lever_front_deg": robot.lever_front_deg,
		"lever_back_deg": robot.lever_back_deg,
		"size_in": Vector3(Config.num("robot.length_in", 18.0), Config.num("robot.width_in", 18.0), Config.num("robot.height_in", 18.0)),
		"size_limit_in": Config.num("robot.size_limit_in", 18.0),
	})

func _physics_process(_dt: float) -> void:
	robot.enabled = match_timer.driver_enabled()
	if teleop.active:  # when something else drives the robot (tests, later the Java bridge) it sets the aim itself
		robot.aim_point = field.aim_point(_alliance) if teleop.auto_aim else null
		teleop.shot_target = field.mouth_point(_alliance)
		teleop.shot_outward = field.mouth_outward(_alliance)
	field.update_flowers(robot, pollen, _dt)
	field.update_hives(_dt)

func reset_all() -> void:
	match_timer.reset()
	robot.reset_pose()
	teleop.reset_field_heading()
	teleop.flywheel_on = false
	field.reset_elements(pollen)
	robot.preload_pollen()

func reload_config() -> void:
	Config.load_config()
	pollen.apply_config()
	robot.apply_config()
	teleop.apply_config()
	match_timer.apply_config()
	reset_all()

func _next_camera() -> void:
	_cam_index = (_cam_index + 1) % _cams.size()
	_cams[_cam_index].make_current()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F: teleop.field_centric = not teleop.field_centric
			KEY_H: teleop.reset_field_heading()
			KEY_ENTER, KEY_KP_ENTER: match_timer.start_teleop_only()
			KEY_M: match_timer.start_full_match()
			KEY_R: reset_all()
			KEY_C: _next_camera()
			KEY_F5: reload_config()
			KEY_F1: hud.toggle_help()
			KEY_1: teleop.toggle_lever(true)
			KEY_2: teleop.toggle_lever(false)
			KEY_V: robot.toggle_shell()
			KEY_G: teleop.toggle_flywheel()
			KEY_T: teleop.auto_aim = not teleop.auto_aim
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_Y: teleop.field_centric = not teleop.field_centric
			JOY_BUTTON_X: teleop.reset_field_heading()
			JOY_BUTTON_START: match_timer.start_teleop_only()
			JOY_BUTTON_BACK: reset_all()
			JOY_BUTTON_RIGHT_SHOULDER: teleop.toggle_flywheel()
			JOY_BUTTON_RIGHT_STICK: teleop.auto_aim = not teleop.auto_aim
			JOY_BUTTON_A: teleop.toggle_lever(true)
			JOY_BUTTON_B: teleop.toggle_lever(false)
