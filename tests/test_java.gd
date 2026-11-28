extends SceneTree
## End-to-end test of real Java OpModes:  godot --headless -s tests/test_java.gd
## Compiles java/teamcode, runs the sample autonomous and TeleOp against the sim, checks the robot obeys.

var fails := 0

func check(name: String, ok: bool, detail := "") -> void:
	print(("  PASS  " if ok else "  FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not ok:
		fails += 1

func steps(n: int) -> void:
	for i in n:
		await physics_frame

func key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func wait_for(cond: Callable, seconds: float) -> bool:
	var t := 0.0
	while t < seconds:
		if cond.call():
			return true
		await steps(12)
		t += 0.1
	return cond.call()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.get_node("Config").realism_scale = 0.0   # exact, repeatable physics
	root.add_child(main)
	await steps(5)
	var robot = main.robot
	var bridge = main.bridge
	var runner = main.java_runner

	var found: Array = runner.scan_opmodes()
	var names: Array = found.map(func(o): return o["name"])
	check("finds the sample OpModes in the TeamCode folder", names.has("Biobuzz TeleOp") and names.has("Drive And Turn"), str(names))

	# ---- autonomous: 24 in forward by encoders, then 90 degrees left by IMU ----
	runner.launch("Drive And Turn")
	var ok: bool = await wait_for(func(): return bridge.connected and bridge.phase == "init" and bridge.opmode != "", 60.0)
	check("autonomous compiles, connects and waits in INIT", ok, runner.log_tail)
	var p0: Vector3 = robot.get_pose_ftc()
	await steps(60)
	check("robot stays still before start", robot.get_pose_ftc().distance_to(p0) < 0.01 and bridge.telemetry.contains("Ready"), bridge.telemetry.strip_edges())
	main._start_pressed()
	ok = await wait_for(func(): return not bridge.connected, 25.0)
	var p1: Vector3 = robot.get_pose_ftc()
	check("autonomous finishes by itself", ok and bridge.phase == "done", "phase " + bridge.phase)
	check("drove 24 in forward", absf((p1.x - p0.x) - 24.0) < 1.5 and absf(p1.y - p0.y) < 1.0, "moved %.1f, %.1f in" % [p1.x - p0.x, p1.y - p0.y])
	check("turned 90 degrees left", absf(wrapf(p1.z - p0.z - 90.0, -180.0, 180.0)) < 3.0, "turned %.1f deg" % wrapf(p1.z - p0.z, -180.0, 180.0))
	await steps(60)
	check("motors are off after the OpMode ends", robot.get_speed() < 0.01 and absf(robot.omega) < 0.01)

	# ---- TeleOp driven by (simulated) key presses ----
	main.reset_all()
	await steps(10)
	p0 = robot.get_pose_ftc()
	runner.launch("Biobuzz TeleOp")
	ok = await wait_for(func(): return bridge.connected and bridge.phase == "init", 60.0)
	check("TeleOp compiles, connects and waits in INIT", ok, runner.log_tail)
	main._start_pressed()
	ok = await wait_for(func(): return bridge.phase == "run", 5.0)
	check("TeleOp runs after start, built-in TeleOp is off", ok and not main.teleop.active)
	await steps(120)
	check("the OpMode's own speed control holds the flywheel at 1400 rpm", absf(robot.flywheel_rpm() - 1400.0) < 40.0, "%.0f rpm" % robot.flywheel_rpm())
	key(KEY_W, true)
	await steps(120)
	key(KEY_W, false)
	await steps(60)
	p1 = robot.get_pose_ftc()
	check("left stick forward drives forward (left motors reversed in code)", p1.x - p0.x > 20.0 and absf(p1.y - p0.y) < 1.0 and absf(p1.z - p0.z) < 1.0, "moved %.1f, %.1f in, turned %.1f" % [p1.x - p0.x, p1.y - p0.y, p1.z - p0.z])
	key(KEY_D, true)
	await steps(90)
	key(KEY_D, false)
	await steps(60)
	var p2: Vector3 = robot.get_pose_ftc()
	check("left stick right strafes right", p2.y - p1.y < -10.0 and absf(p2.x - p1.x) < 1.0, "moved %.1f, %.1f in" % [p2.x - p1.x, p2.y - p1.y])
	key(KEY_E, true)
	await steps(40)
	key(KEY_E, false)
	await steps(60)
	var turned: Vector3 = robot.get_pose_ftc()
	key(KEY_A, true)
	await steps(60)
	key(KEY_A, false)
	await steps(60)
	var after_turn: Vector3 = robot.get_pose_ftc()
	check("field-centric: after turning the robot, stick left still goes to the driver's left", after_turn.y - turned.y > 8.0 and absf(after_turn.x - turned.x) < 3.0, "robot facing %.0f deg, moved %.1f, %.1f in" % [turned.z, after_turn.x - turned.x, after_turn.y - turned.y])
	check("telemetry reaches the simulator", bridge.telemetry.contains("Heading") and bridge.telemetry.contains("Front left encoder"), bridge.telemetry.strip_edges().replace("\n", " | "))
	# Out in the open, with no loose balls nearby: the next part is about the balls already on board,
	# and a shot that bounces back off a wall would be swallowed and fired again.
	main.pollen.clear()
	robot.set_pose_ftc(-45, -45, 0)
	await steps(5)
	var held: int = robot.held_total()
	key(KEY_SHIFT, true)
	await steps(90)
	key(KEY_SHIFT, false)
	check("intake trigger runs the feeders without shooting (gate shut)", robot.shots_fired == 0 and robot.held_total() == held)
	key(KEY_SPACE, true)
	await steps(240)
	key(KEY_SPACE, false)
	check("shoot trigger opens the gate and fires", robot.shots_fired == held and robot.held_total() == 0, "%d shots" % robot.shots_fired)
	key(KEY_1, true)
	key(KEY_LEFT, true)
	await steps(120)
	key(KEY_1, false)
	key(KEY_LEFT, false)
	check("A button deploys a lever, D-pad turns the turret", robot.lever_front_deg > 130.0 and robot.turret_from_home_deg() > 5.0, "lever %.0f, turret %.1f" % [robot.lever_front_deg, robot.turret_from_home_deg()])
	check("the turret stops at the end of the real servo's travel (300 deg through 15:70 = 64 deg in all)", absf(robot.turret_from_home_deg() - robot.turret_range_deg() / 2.0) < 0.5, "turret %.1f" % robot.turret_from_home_deg())
	key(KEY_1, true)
	await steps(10)
	key(KEY_1, false)
	# Camera: the OpMode's own auto-aim finds our hive's tag and centres the turret on it. The robot has
	# to face the hive roughly, as on the real field: the turret only covers 32 degrees each way.
	robot.set_pose_ftc(34, -50, 145)
	main.pollen.clear()
	for i in 2:
		robot.load_ball(i, "pollen")
	key(KEY_T, true)
	await steps(20)
	key(KEY_T, false)
	var cam = main.tag_camera
	var locked := func():
		for t in cam.tags:
			if str(t["name"]).begins_with("RED") and absf(t["roll"]) < 90.0 and absf(t["tx"]) < 1.5:
				return true
		return false
	ok = await wait_for(locked, 20.0)
	check("Java auto-aim centres the turret on our hive's raised cell", ok, cam.summary())
	check("the cell it locked onto is the raised one", main.field.hive_of("red")["up_side"] == "bottom" and cam.tags.size() > 0 and str(cam.tags[0]["name"]) == "RED AUDIENCE", cam.summary())
	check("camera data shows up in telemetry", bridge.telemetry.contains("Auto-aim : ON") and bridge.telemetry.contains("Camera : RED AUDIENCE"), bridge.telemetry.strip_edges().replace("\n", " | "))
	# With auto-aim on, the OpMode takes the hood and flywheel speed from its shot table.
	await steps(120)
	var fired0: int = robot.shots_fired
	key(KEY_SPACE, true)
	await steps(180)
	key(KEY_SPACE, false)
	await steps(240)
	check("Java auto shot: hood and flywheel from the table put both pollen in the raised cell", robot.shots_fired == fired0 + 2 and main.field.cell_count("red", true) == 2,
		"fired %d, in cell %d, hood %.1f deg, %.0f rpm | %s" % [robot.shots_fired - fired0, main.field.cell_count("red", true), robot.hood_deg, robot.flywheel_rpm(), bridge.telemetry.strip_edges().replace("\n", " | ")])
	main.reset_all()
	ok = await wait_for(func(): return not bridge.connected and not runner.is_running(), 5.0)
	check("reset stops the OpMode and hands back to the built-in TeleOp", ok)
	await steps(5)
	check("built-in TeleOp is active again", main.teleop.active)

	# ---- Chassis + Levers: the small OpMode with only the drive and the two lever servos ----
	main.reset_all()
	await steps(10)
	runner.launch("Chassis + Levers")
	ok = await wait_for(func(): return bridge.connected and bridge.phase == "init", 60.0)
	check("Chassis + Levers compiles, connects and waits in INIT", ok, runner.log_tail)
	main._start_pressed()
	ok = await wait_for(func(): return bridge.phase == "run", 5.0)
	await steps(30)
	p0 = robot.get_pose_ftc()
	check("it leaves the shooter, intakes and levers alone at start", ok and robot.shooter_power == 0.0 and robot.intake_front_power == 0.0 and robot.lever_front_deg < 20.0 and robot.lever_back_deg < 20.0)
	key(KEY_W, true)
	await steps(60)
	key(KEY_W, false)
	await steps(60)
	p1 = robot.get_pose_ftc()
	check("chassis: forward drives forward", p1.x - p0.x > 15.0 and absf(p1.y - p0.y) < 1.0, "moved %.1f, %.1f in" % [p1.x - p0.x, p1.y - p0.y])
	key(KEY_E, true)
	await steps(40)
	key(KEY_E, false)
	await steps(60)
	p2 = robot.get_pose_ftc()
	check("chassis: right stick turns right", wrapf(p2.z - p1.z, -180.0, 180.0) < -20.0, "turned %.1f" % wrapf(p2.z - p1.z, -180.0, 180.0))
	key(KEY_W, true)
	await steps(60)
	key(KEY_W, false)
	await steps(60)
	var p3: Vector3 = robot.get_pose_ftc()
	check("field-centric: forward still goes away from the driver after the robot has turned", p3.x - p2.x > 15.0 and absf(p3.y - p2.y) < 3.0, "robot facing %.0f deg, moved %.1f, %.1f in" % [p3.z, p3.x - p2.x, p3.y - p2.y])
	key(KEY_D, true)
	await steps(60)
	key(KEY_D, false)
	await steps(60)
	var p4: Vector3 = robot.get_pose_ftc()
	check("field-centric: right still goes to the driver's right", p4.y - p3.y < -8.0 and absf(p4.x - p3.x) < 3.0, "moved %.1f, %.1f in" % [p4.x - p3.x, p4.y - p3.y])
	# Odometry (goBILDA Pinpoint): position counted from where the robot stood at INIT, X forward, Y left.
	var odo := RegEx.new()
	odo.compile("Position : x (-?[0-9.]+) in  y (-?[0-9.]+) in  facing (-?[0-9.]+) deg")
	var seen := odo.search(bridge.telemetry)
	check("odometry shows how far the robot has gone since INIT", seen != null and absf(float(seen.get_string(1)) - (p4.x - p0.x)) < 0.5 and absf(float(seen.get_string(2)) - (p4.y - p0.y)) < 0.5 and absf(float(seen.get_string(3)) - p4.z) < 1.0,
		"%s | robot really moved %.1f, %.1f in and faces %.1f" % [seen.get_string(0) if seen != null else bridge.telemetry.strip_edges().replace("\n", " | "), p4.x - p0.x, p4.y - p0.y, p4.z])
	key(KEY_1, true)
	await steps(10)
	key(KEY_1, false)
	await steps(90)
	check("A puts the front lever out, the back lever stays in", robot.lever_front_deg > 130.0 and robot.lever_back_deg < 20.0, "front %.0f back %.0f" % [robot.lever_front_deg, robot.lever_back_deg])
	key(KEY_2, true)
	key(KEY_1, true)
	await steps(10)
	key(KEY_2, false)
	key(KEY_1, false)
	await steps(90)
	check("B puts the back lever out, A again folds the front one in", robot.lever_back_deg > 130.0 and robot.lever_front_deg < 20.0, "front %.0f back %.0f" % [robot.lever_front_deg, robot.lever_back_deg])
	main.reset_all()
	await wait_for(func(): return not bridge.connected and not runner.is_running(), 5.0)

	# ---- Camera + Shooter: turret, hood, flywheel, feeders and camera, no driving ----
	main.reset_all()
	await steps(10)
	runner.launch("Camera + Shooter")
	ok = await wait_for(func(): return bridge.connected and bridge.phase == "init", 60.0)
	check("Camera + Shooter compiles, connects and waits in INIT", ok, runner.log_tail)
	main._start_pressed()
	ok = await wait_for(func(): return bridge.phase == "run", 5.0)
	main.pollen.clear()
	robot.set_pose_ftc(34, -50, 145)   # facing the red hive, as if the robot had been carried there
	await steps(30)
	var held0: int = robot.held_total()
	key(KEY_SPACE, true)
	await steps(90)
	key(KEY_SPACE, false)
	check("the flywheel is off until X is pressed, and nothing is fired", ok and robot.shooter_power == 0.0 and robot.shots_fired == 0 and robot.held_total() == held0 and bridge.telemetry.contains("flywheel is off (X)"), bridge.telemetry.strip_edges().replace("\n", " | "))
	for k in [KEY_3, KEY_4, KEY_4]:   # X = on, Y twice = +500 rpm
		key(k, true)
		await steps(10)
		key(k, false)
		await steps(10)
	await steps(300)   # the OpMode assumes the real robot's 5000 rpm top speed; the sim's is 6000, so it settles more slowly
	check("X turns the flywheel on, Y raises the speed by 250 rpm a press", absf(robot.flywheel_rpm() - 1900.0) < 50.0, "%.0f rpm" % robot.flywheel_rpm())
	key(KEY_T, true)
	await steps(20)
	key(KEY_T, false)
	var cam2 = main.tag_camera
	ok = await wait_for(func():
		for t in cam2.tags:
			if str(t["name"]).begins_with("RED") and absf(t["roll"]) < 90.0 and absf(t["tx"]) < 1.5:
				return true
		return false, 20.0)
	check("auto-aim turns the turret onto our raised cell", ok, cam2.summary())
	await steps(120)
	check("it shows the row to copy into the shot table", bridge.telemetry.contains("Table row : {") and bridge.telemetry.contains("from the table"), bridge.telemetry.strip_edges().replace("\n", " | "))
	var shots0: int = robot.shots_fired
	var loaded: int = robot.held_total()
	key(KEY_SPACE, true)
	await steps(240)
	key(KEY_SPACE, false)
	await steps(240)
	check("shoot puts the loaded pollen in the raised cell, and the wheels never move", robot.shots_fired - shots0 == loaded and main.field.cell_count("red", true) >= loaded - 1 and robot.wheel_powers == [0.0, 0.0, 0.0, 0.0],
		"fired %d of %d, in cell %d" % [robot.shots_fired - shots0, loaded, main.field.cell_count("red", true)])
	main.reset_all()
	await wait_for(func(): return not bridge.connected and not runner.is_running(), 5.0)

	print("\n%s" % ("ALL TESTS PASSED" if fails == 0 else "%d TEST(S) FAILED" % fails))
	runner.stop()
	quit(1 if fails > 0 else 0)
