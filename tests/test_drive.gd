extends SceneTree
## Headless self-test:  godot --headless -s tests/test_drive.gd
## Drives the simulated robot with known wheel powers and checks the physics.

var fails := 0

func check(name: String, ok: bool, detail := "") -> void:
	print(("  PASS  " if ok else "  FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not ok:
		fails += 1

func steps(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await steps(2)
	var robot = main.robot
	var teleop = main.teleop
	var timer = main.match_timer
	teleop.active = false  # the test sets wheel powers itself
	var IN := 0.0254

	var p0: Vector3 = robot.get_pose_ftc()
	check("starts at configured pose", p0.distance_to(Vector3(0, -48, 90)) < 0.01, str(p0))

	# Forward at full power for 1 s.
	robot.wheel_powers = [1.0, 1.0, 1.0, 1.0]
	await steps(120)
	var p: Vector3 = robot.get_pose_ftc()
	var expect_v: float = 312.0 / 60.0 * PI * 0.104 * 0.85
	check("forward reaches max speed", absf(robot.get_speed() - expect_v) < 0.01, "%.3f m/s vs %.3f" % [robot.get_speed(), expect_v])
	check("forward moves +y only", p.y > p0.y + 30 and absf(p.x) < 0.01 and absf(p.z - 90) < 0.01, str(p))
	check("encoders count up", robot.get_wheel_ticks(0) > 1000, "%.0f ticks" % robot.get_wheel_ticks(0))
	var dist_m: float = (p.y - p0.y) * IN
	var ticks_dist: float = robot.get_wheel_ticks(0) / 537.7 * PI * 0.104
	check("encoder distance matches travel", absf(dist_m - ticks_dist) < 0.005, "%.3f vs %.3f m" % [dist_m, ticks_dist])

	# Strafe right.
	robot.reset_pose()
	robot.wheel_powers = teleop.mix(0, 1, 0)
	await steps(120)
	p = robot.get_pose_ftc()
	check("strafe right moves +x only", p.x > 20 and absf(p.y + 48) < 0.01 and absf(p.z - 90) < 0.01, str(p))
	check("strafe is slower than forward", robot.get_speed() < expect_v * 0.9)

	# Turn right (clockwise) in place.
	robot.reset_pose()
	robot.wheel_powers = teleop.mix(0, 0, 1)
	await steps(60)
	p = robot.get_pose_ftc()
	check("turn right is clockwise, in place", p.z < 60 and Vector2(p.x, p.y + 48).length() < 0.01, str(p))

	# Walls stop the robot.
	robot.reset_pose()
	robot.wheel_powers = [1.0, 1.0, 1.0, 1.0]
	await steps(600)
	p = robot.get_pose_ftc()
	var limit: float = 141.24 / 2 - 9
	check("wall stops the robot", absf(p.y - limit) < 0.3 and robot.get_speed() < 0.02, "y=%.2f in, limit %.2f" % [p.y, limit])

	# Field-centric: robot facing left, stick forward must still drive away from the driver.
	robot.reset_pose()
	teleop.reset_field_heading()
	robot.set_pose_ftc(0, 0, 180)
	teleop.field_centric = true
	robot.wheel_powers = teleop.compute_powers(1, 0, 0)
	await steps(120)
	p = robot.get_pose_ftc()
	check("field-centric forward = away from driver", p.y > 20 and absf(p.x) < 0.5, str(p))
	teleop.field_centric = false

	# Match clock.
	robot.reset_pose()
	timer.auto_s = 0.5
	timer.transition_s = 0.25
	timer.teleop_s = 0.5
	timer.start_full_match()
	robot.wheel_powers = [1.0, 1.0, 1.0, 1.0]
	await steps(30)
	check("robot disabled in auto (no auto code)", timer.state == timer.State.AUTO and robot.get_speed() == 0.0)
	await steps(45)
	check("transition follows auto", timer.state == timer.State.TRANSITION)
	await steps(45)
	check("teleop enables the driver", timer.state == timer.State.TELEOP and robot.get_speed() > 0.1)
	await steps(120)
	check("match ends and robot stops", timer.state == timer.State.ENDED and robot.get_speed() < 0.01)

	print("\n%s" % ("ALL TESTS PASSED" if fails == 0 else "%d TEST(S) FAILED" % fails))
	quit(1 if fails > 0 else 0)
