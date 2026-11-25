extends SceneTree
## Headless self-test:  godot --headless -s tests/test_moving_shot.gd
## Shooting on the move: the robot drives past (or spins in front of) the red hive while the built-in
## auto-aim, automatic hood and gate logic fire four pollen. Prints how many land in the raised cell.

const IN := 0.0254
var fails := 0
var main
var robot
var teleop
var field
var pollen

func check(name: String, ok: bool, detail := "") -> void:
	print(("  PASS  " if ok else "  FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not ok:
		fails += 1

func steps(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	_run.call_deferred()

## One pass. `wheels` = the four wheel powers while shooting. Returns what happened.
## `fire_at_x_in`: fire one ball each time the robot passes one of these x positions (empty = fire freely).
func run_pass(start: Vector3, wheels: Array, lead: bool, turret_deg_per_s: float, fire_at_x_in: Array) -> Dictionary:
	field.reset_elements(pollen)
	pollen.clear()
	robot.reset_pose()
	robot.set_pose_ftc(start.x, start.y, start.z)
	robot._turret_speed = turret_deg_per_s
	teleop.lead_shots = lead
	teleop.auto_aim = true
	teleop._plan = {}
	for i in 4:
		robot.load_ball(i % 2, "pollen", 1.0 - 0.25 * (i / 2))
	var max_err := 0.0
	var speed_sum := 0.0
	var speed_n := 0
	var held := 0.0
	var spin := 0.0
	var dt := 1.0 / 60.0
	# Stand still first so the turret, hood and flywheel are ready, then go.
	for i in 900:
		var x_in: float = robot.global_position.x / IN
		var moving: bool = i >= 300
		robot.wheel_powers = wheels if moving else [0.0, 0.0, 0.0, 0.0]
		robot.aim_point = field.aim_point("red") + teleop.aim_lead
		teleop.shot_target = field.mouth_point("red")
		teleop.shot_outward = field.mouth_outward("red")
		var window: bool = moving and robot.held_total() > 0 and (fire_at_x_in.is_empty() or (robot.shots_fired < fire_at_x_in.size() and x_in >= fire_at_x_in[robot.shots_fired]))
		teleop.run_mechanisms(dt, 0.0, 0.0, 0.0, window, false)
		if window:
			max_err = maxf(max_err, teleop.turret_error_deg())
			speed_sum += robot.get_speed()
			spin = maxf(spin, absf(rad_to_deg(robot.omega)))
			speed_n += 1
			if not robot.gate_open:
				held += dt
		await physics_frame
	robot.wheel_powers = [0.0, 0.0, 0.0, 0.0]
	teleop.run_mechanisms(dt, 0.0, 0.0, 0.0, false, false)
	await steps(150)
	return {"fired": robot.shots_fired, "in": field.cell_count("red", true), "err": max_err, "speed": speed_sum / maxi(speed_n, 1), "held": held, "omega": spin}

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await steps(2)
	robot = main.robot
	teleop = main.teleop
	field = main.field
	pollen = main.pollen
	teleop.active = false
	main._external_control = true
	var cfg = root.get_node("Config")
	var turret_cfg: float = cfg.num("turret.servo_speed_deg_per_s", 400.0) * cfg.num("turret.servo_gear_teeth", 15.0) / cfg.num("turret.turret_gear_teeth", 70.0)

	print("\n  DRIVING PAST the hive (33 in to the side of it), firing one pollen at 4 points along the way")
	print("    drive   lead   turret     robot speed   fired  in cell   worst turret lag   fire held back")
	var results := {}
	for turret in [turret_cfg, 51.0]:
		for lead in [false, true]:
			for p in [0.25, 0.5, 1.0]:
				var r: Dictionary = await run_pass(Vector3(-61, -52, 0), [p, p, p, p], lead, turret, [-52.0, -42.0, -32.0, -22.0])
				results["%s %s %.2f" % [turret, lead, p]] = r
				print("    %3.0f %%   %-5s  %3.0f deg/s   %4.1f in/s    %d      %d         %4.1f deg           %.2f s" % [p * 100.0, "yes" if lead else "no", turret, r["speed"] / IN, r["fired"], r["in"], r["err"], r["held"]])

	print("\n  SPINNING on the spot in front of the hive, firing 4 pollen")
	print("    turn power   turret     robot spin   fired  in cell   worst turret lag")
	var spins := {}
	for turret in [turret_cfg, 51.0]:
		for p in [0.1, 0.2, 0.4]:
			var r: Dictionary = await run_pass(Vector3(-12, -58, 90), [-p, p, -p, p], true, turret, [])
			spins["%s %.1f" % [turret, p]] = r
			print("    %3.0f %%        %3.0f deg/s   %4.0f deg/s    %d      %d         %4.1f deg" % [p * 100.0, turret, r["omega"], r["fired"], r["in"], r["err"]])
	robot._turret_speed = turret_cfg

	var k := "%s " % turret_cfg
	check("standing-start check: slow drive-by with lead scores all 4", results[k + "true 0.25"]["in"] == 4, str(results[k + "true 0.25"]))
	check("at full speed, aiming straight at the hive misses", results[k + "false 1.00"]["in"] <= 1, "%d in" % results[k + "false 1.00"]["in"])
	check("at full speed, leading the shot scores", results[k + "true 1.00"]["in"] >= 3, "%d in" % results[k + "true 1.00"]["in"])
	check("at half speed, leading the shot scores all 4", results[k + "true 0.50"]["in"] == 4, "%d in" % results[k + "true 0.50"]["in"])

	print("\n%s" % ("ALL TESTS PASSED" if fails == 0 else "%d TEST(S) FAILED" % fails))
	quit(1 if fails > 0 else 0)
