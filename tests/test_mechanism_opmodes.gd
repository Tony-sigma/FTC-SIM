extends SceneTree
## Runs each mechanism test OpMode (java/teamcode/Test*.java) in the sim and checks it does its job.
##   godot --headless -s tests/test_mechanism_opmodes.gd

var fails := 0
var main

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

func tap(k: Key) -> void:
	key(k, true)
	await steps(20)
	key(k, false)
	await steps(20)

func wait_for(cond: Callable, seconds: float) -> bool:
	var t := 0.0
	while t < seconds:
		if cond.call():
			return true
		await steps(12)
		t += 0.1
	return cond.call()

func start(opmode: String) -> bool:
	main.reset_all()
	await steps(10)
	main.java_runner.launch(opmode)
	var ok: bool = await wait_for(func(): return main.bridge.connected and main.bridge.phase == "init", 60.0)
	if not ok:
		print("    could not start: ", main.java_runner.log_tail)
		return false
	main._start_pressed()
	ok = await wait_for(func(): return main.bridge.phase == "run", 5.0)
	await steps(30)
	return ok

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.get_node("Config").realism_scale = 0.0   # exact, repeatable physics
	root.add_child(main)
	await steps(5)
	var robot = main.robot
	var bridge = main.bridge

	check("drive motor test starts", await start("Test: Drive Motors"))
	key(KEY_3, true)   # X on the gamepad
	await steps(40)
	check("holding X runs only frontLeft, forwards", absf(robot.wheel_powers[0] - 0.3) < 0.01 and robot.wheel_powers[1] == 0.0 and robot.wheel_powers[2] == 0.0 and robot.wheel_powers[3] == 0.0, str(robot.wheel_powers))
	key(KEY_CTRL, true)   # left bumper
	await steps(40)
	check("with the left bumper it runs backwards", absf(robot.wheel_powers[0] + 0.3) < 0.01, str(robot.wheel_powers))
	key(KEY_CTRL, false)
	key(KEY_3, false)
	key(KEY_2, true)   # B = backRight
	await steps(60)
	check("holding B runs only backRight, and its encoder shows", absf(robot.wheel_powers[3] - 0.3) < 0.01 and robot.wheel_powers[0] == 0.0 and bridge.telemetry.contains("backRight : RUNNING"), bridge.telemetry.strip_edges().replace("\n", " | "))
	key(KEY_2, false)

	check("any-servo test starts", await start("Test: Any Servo"))
	var hood0: float = robot.hood_servo
	var turret0: float = robot.turret_goal_deg
	await steps(60)
	check("nothing moves before a servo is armed", robot.hood_servo == hood0 and robot.turret_goal_deg == turret0)
	await tap(KEY_RIGHT)   # choose hoodServo
	await tap(KEY_1)       # A = arm
	key(KEY_UP, true)
	await steps(120)
	key(KEY_UP, false)
	await steps(20)
	check("hood servo follows the nudges, turret stays put", robot.hood_servo > 0.55 and robot.turret_goal_deg == turret0 and bridge.telemetry.contains(">> MOVING hoodServo"), "hood %.3f" % robot.hood_servo)
	await tap(KEY_RIGHT)   # gateServo (disarmed again)
	await tap(KEY_RIGHT)   # leverFrontLeft
	await tap(KEY_1)
	await tap(KEY_B)       # right bumper: +0.05
	check("lever servo jumps by 0.05 on the bumper", absf(robot.lever_front_servo - 0.55) < 0.001 and not robot.lever_fight[0], "%.3f" % robot.lever_front_servo)
	# The second servo of the same lever is mirrored. Driven the same way as the first (not reversed in
	# the code) it pushes against it: the sim reports the fight.
	await tap(KEY_RIGHT)   # leverFrontRight
	await tap(KEY_1)
	for i in 4:
		await tap(KEY_B)
	check("two lever servos told to go opposite ways are reported as fighting", robot.lever_fight[0] and not robot.lever_fight[1], "front lever at %.3f" % robot.lever_front_servo)

	check("intake + feeder test starts", await start("Test: Intake + Feeder"))
	key(KEY_SPACE, true)   # right trigger
	await steps(40)
	check("right trigger runs intakeA only", absf(robot.intake_front_power - 1.0) < 0.01 and robot.intake_back_power == 0.0)
	key(KEY_B, true)       # right bumper = reverse
	await steps(40)
	check("right bumper reverses it", absf(robot.intake_front_power + 1.0) < 0.01)
	key(KEY_B, false)
	key(KEY_SPACE, false)
	key(KEY_SHIFT, true)
	await steps(40)
	check("left trigger runs intakeB only", absf(robot.intake_back_power - 1.0) < 0.01 and robot.intake_front_power == 0.0)
	key(KEY_SHIFT, false)

	check("shooter test starts", await start("Test: Shooter"))
	await steps(60)
	check("flywheel is off until A is pressed", robot.shooter_power == 0.0)
	await tap(KEY_1)
	await tap(KEY_UP)
	await tap(KEY_UP)
	await steps(240)
	check("A turns it on, D-pad up raises the power in 0.02 steps", absf(robot.shooter_power - 0.14) < 0.001, "%.3f" % robot.shooter_power)
	check("the screen shows the real speed", bridge.telemetry.contains("rpm") and absf(robot.flywheel_rpm() - 0.14 * robot.flywheel_max_rpm) < 30.0, bridge.telemetry.strip_edges().replace("\n", " | "))
	await tap(KEY_2)
	check("B turns it off", robot.shooter_power == 0.0)

	check("sensor test starts", await start("Test: Sensors"))
	robot.set_pose_ftc(-40, -45, 30)   # as if someone turned the robot 30 degrees left by hand
	await steps(60)
	check("heading follows the robot being turned by hand", bridge.telemetry.contains("Heading : 30.0 deg"), bridge.telemetry.strip_edges().replace("\n", " | "))

	check("odometry test starts", await start("Test: Odometry"))
	var o0: Vector3 = robot.get_pose_ftc()
	check("odometry starts at zero and is ready", bridge.telemetry.contains("Status : READY") and bridge.telemetry.contains("X (forward) : 0.0 in") and bridge.telemetry.contains("Y (left) : 0.0 in"), bridge.telemetry.strip_edges().replace("\n", " | "))
	robot.set_pose_ftc(o0.x + 24.0, o0.y, o0.z)   # as if someone pushed the robot one tile forward (it faces +x)
	await steps(30)
	check("pushed one tile forward: X reads 24", bridge.telemetry.contains("X (forward) : 24.0 in") and bridge.telemetry.contains("Y (left) : 0.0 in"), bridge.telemetry.strip_edges().replace("\n", " | "))
	robot.set_pose_ftc(o0.x + 24.0, o0.y + 24.0, o0.z + 90.0)   # one tile to its left, then a quarter turn left
	await steps(30)
	check("pushed one tile left and turned left: Y reads 24, heading 90", bridge.telemetry.contains("X (forward) : 24.0 in") and bridge.telemetry.contains("Y (left) : 24.0 in") and bridge.telemetry.contains("Heading : 90.0 deg"), bridge.telemetry.strip_edges().replace("\n", " | "))

	check("camera test starts", await start("Test: Camera"))
	robot.aim_point = main.field.aim_point("red")
	await steps(480)
	check("camera test names the raised cell and says it can be scored in", bridge.telemetry.contains("RED AUDIENCE") and bridge.telemetry.contains("RAISED cell, can score") and bridge.telemetry.contains("% of its tags"), bridge.telemetry.strip_edges().replace("\n", " | "))

	check("turret test starts", await start("Test: Turret"))
	var home: float = robot.turret_goal_deg
	var hood_before: float = robot.hood_servo
	key(KEY_LEFT, true)
	await steps(60)
	key(KEY_LEFT, false)
	check("turret does not move before it is armed", robot.turret_goal_deg == home)
	await tap(KEY_1)   # A = arm
	key(KEY_LEFT, true)
	await steps(120)
	key(KEY_LEFT, false)
	await steps(20)
	check("after arming, D-pad left turns the turret left and only the turret", wrapf(robot.turret_goal_deg - robot.turret_home_deg, -180.0, 180.0) > 10.0 and robot.hood_servo == hood_before and bridge.telemetry.contains("deg from the middle"), "turned %.1f deg" % wrapf(robot.turret_goal_deg - robot.turret_home_deg, -180.0, 180.0))

	check("hood test starts", await start("Test: Hood"))
	await tap(KEY_1)
	await tap(KEY_B)   # right bumper: +0.05
	key(KEY_DOWN, true)
	await steps(60)
	key(KEY_DOWN, false)
	await steps(20)
	check("hood moves with the bumper and the D-pad, flywheel stays off", robot.hood_servo > 0.42 and robot.hood_servo < 0.5 and robot.shooter_power == 0.0, "%.3f" % robot.hood_servo)

	check("lever test starts", await start("Test: Levers"))
	await tap(KEY_2)   # B = back lever
	await tap(KEY_1)   # arm
	await tap(KEY_B)   # +0.05
	check("only the chosen (back) lever moves, its two servos together", absf(robot.lever_back_servo - 0.55) < 0.001 and robot.lever_front_servo == 0.0 and not robot.lever_fight[1], "front %.3f back %.3f" % [robot.lever_front_servo, robot.lever_back_servo])
	await tap(KEY_3)   # X = front lever
	await tap(KEY_1)
	key(KEY_UP, true)
	await steps(120)
	key(KEY_UP, false)
	await steps(20)
	check("then the front lever moves and the back one holds", robot.lever_front_servo > 0.6 and absf(robot.lever_back_servo - 0.55) < 0.001 and not robot.lever_fight[0], "front %.3f back %.3f" % [robot.lever_front_servo, robot.lever_back_servo])

	main.reset_all()
	await steps(30)
	print("\n%s" % ("ALL TESTS PASSED" if fails == 0 else "%d TEST(S) FAILED" % fails))
	main.java_runner.stop()
	quit(1 if fails > 0 else 0)
