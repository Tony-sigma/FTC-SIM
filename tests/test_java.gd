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
	check("flywheel spins up from the OpMode's setPower", absf(robot.flywheel_fraction - 0.22) < 0.02, "%.2f" % robot.flywheel_fraction)
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
	check("telemetry reaches the simulator", bridge.telemetry.contains("Heading") and bridge.telemetry.contains("Front left encoder"), bridge.telemetry.strip_edges().replace("\n", " | "))
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
	check("A button deploys a lever, D-pad turns the turret", robot.lever_front_deg > 80.0 and robot.turret_deg > 5.0, "lever %.0f, turret %.1f" % [robot.lever_front_deg, robot.turret_deg])
	# Limelight: the OpMode's own auto-aim finds our hive's tag and centres the turret on it.
	key(KEY_T, true)
	await steps(20)
	key(KEY_T, false)
	var ll = main.limelight
	var locked := func():
		for t in ll.tags:
			if (t["id"] == 1 or t["id"] == 2) and absf(t["tx"]) < 1.5:
				return true
		return false
	ok = await wait_for(locked, 20.0)
	check("Java auto-aim centres the turret on our hive's AprilTag", ok, ll.summary())
	check("Limelight data shows up in telemetry", bridge.telemetry.contains("Auto-aim : ON") and bridge.telemetry.contains("Limelight : tag"), bridge.telemetry.strip_edges().replace("\n", " | "))
	main.reset_all()
	ok = await wait_for(func(): return not bridge.connected and not runner.is_running(), 5.0)
	check("reset stops the OpMode and hands back to the built-in TeleOp", ok)
	await steps(5)
	check("built-in TeleOp is active again", main.teleop.active)

	print("\n%s" % ("ALL TESTS PASSED" if fails == 0 else "%d TEST(S) FAILED" % fails))
	runner.stop()
	quit(1 if fails > 0 else 0)
