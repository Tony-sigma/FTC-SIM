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
	# A clear lane on the red side for the driving checks.
	var cfg = root.get_node("Config")
	cfg.data["robot"]["start_x_in"] = -50.0
	cfg.data["robot"]["start_y_in"] = -50.0
	cfg.data["robot"]["start_heading_deg"] = 90.0
	check("robot starts preloaded", robot.held_total() == 4, "holding %d" % robot.held_total())
	check("field has 4 flowers and 2 hives", main.field.flowers.size() == 4 and main.field.hives.size() == 2)
	check("starting pollen is on the field", main.pollen.ball_count() == 20, "%d balls" % main.pollen.ball_count())
	robot.reset_pose()
	await steps(2)
	var IN := 0.0254

	var p0: Vector3 = robot.get_pose_ftc()
	check("starts at configured pose", p0.distance_to(Vector3(-50, -50, 90)) < 0.01, str(p0))

	# Forward at full power for 1 s.
	robot.wheel_powers = [1.0, 1.0, 1.0, 1.0]
	await steps(120)
	var p: Vector3 = robot.get_pose_ftc()
	var expect_v: float = 312.0 / 60.0 * PI * 0.104 * 0.85
	check("forward reaches max speed", absf(robot.get_speed() - expect_v) < 0.01, "%.3f m/s vs %.3f" % [robot.get_speed(), expect_v])
	check("forward moves +y only", p.y > p0.y + 30 and absf(p.x + 50) < 0.01 and absf(p.z - 90) < 0.01, str(p))
	check("encoders count up", robot.get_wheel_ticks(0) > 1000, "%.0f ticks" % robot.get_wheel_ticks(0))
	var dist_m: float = (p.y - p0.y) * IN
	var ticks_dist: float = robot.get_wheel_ticks(0) / 537.7 * PI * 0.104
	check("encoder distance matches travel", absf(dist_m - ticks_dist) < 0.005, "%.3f vs %.3f m" % [dist_m, ticks_dist])

	# Strafe right.
	robot.reset_pose()
	robot.wheel_powers = teleop.mix(0, 1, 0)
	await steps(120)
	p = robot.get_pose_ftc()
	check("strafe right moves +x only", p.x > -30 and absf(p.y + 50) < 0.01 and absf(p.z - 90) < 0.01, str(p))
	check("strafe is slower than forward", robot.get_speed() < expect_v * 0.9)

	# Turn right (clockwise) in place.
	robot.reset_pose()
	robot.wheel_powers = teleop.mix(0, 0, 1)
	await steps(60)
	p = robot.get_pose_ftc()
	check("turn right is clockwise, in place", p.z < 60 and Vector2(p.x + 50, p.y + 50).length() < 0.01, str(p))

	# Walls stop the robot.
	robot.reset_pose()
	robot.wheel_powers = [1.0, 1.0, 1.0, 1.0]
	await steps(600)
	p = robot.get_pose_ftc()
	var limit: float = (main.field.size / 2.0 - robot.length / 2.0) / IN
	check("wall stops the robot", absf(p.y - limit) < 0.3 and robot.get_speed() < 0.05, "y=%.2f in, limit %.2f, speed %.3f" % [p.y, limit, robot.get_speed()])

	# Mechanisms follow servo commands at a limited speed.
	robot.reset_pose()
	robot.wheel_powers = [0.0, 0.0, 0.0, 0.0]
	await steps(5)
	check("CAD model loaded", robot.has_cad_model)
	check("turret starts centred, levers stowed", absf(robot.turret_deg) < 0.01 and robot.lever_front_deg < 0.01)
	robot.turret_servo = 1.0
	robot.lever_front_servo = 1.0
	await steps(12)
	check("mechanisms do not snap instantly", robot.turret_deg > 1.0 and robot.turret_deg < 20.0 and robot.lever_front_deg > 5.0 and robot.lever_front_deg < 60.0,
		"turret %.1f, lever %.1f after 0.1 s" % [robot.turret_deg, robot.lever_front_deg])
	await steps(240)
	var half: float = 300.0 * 15.0 / 70.0 / 2.0
	check("turret stops at its servo limit", absf(robot.turret_deg - half) < 0.01, "%.2f deg (limit %.2f)" % [robot.turret_deg, half])
	check("front lever deploys to 90, back stays stowed", absf(robot.lever_front_deg - 90.0) < 0.01 and robot.lever_back_deg < 0.01)
	robot.reset_pose()
	await steps(240)

	# Pollen: intake swallows a ball, the shooter launches it.
	var pollen = main.pollen
	pollen.clear()
	robot.set_pose_ftc(-50, -50, 90)
	await steps(5)
	var ball = pollen.spawn_ball(robot.global_position + Vector3(0, pollen.radius, -(robot.length / 2.0 + 0.3)))
	var ball_z0: float = ball.global_position.z
	robot.wheel_powers = [0.3, 0.3, 0.3, 0.3]
	await steps(180)
	check("intake off: ball is pushed, not swallowed", robot.held_total() == 0 and pollen.ball_count() == 1 and ball.global_position.z < ball_z0 - 0.05)
	robot.intake_front_power = 1.0
	await steps(120)
	check("intake on: ball is swallowed into the front feeder", robot.held_count(0) == 1 and pollen.ball_count() == 0)
	robot.wheel_powers = [0.0, 0.0, 0.0, 0.0]
	await steps(120)
	check("ball waits at the neck while the flywheel is off", robot.held_count(0) == 1 and robot.shots_fired == 0)
	robot.intake_front_power = 0.0
	robot.shooter_power = 1.0
	await steps(240)
	check("flywheel alone does not fire", robot.shots_fired == 0 and robot.flywheel_fraction > 0.95)
	var start: Vector3 = robot.global_position
	robot.intake_front_power = 1.0
	await steps(30)
	check("flywheel + feeder: ball is launched", robot.held_total() == 0 and robot.shots_fired == 1 and pollen.ball_count() == 1)
	robot.intake_front_power = 0.0
	robot.shooter_power = 0.0
	var shot = get_nodes_in_group("pollen")[0]
	await steps(360)
	var flew: Vector3 = shot.global_position - start
	check("shot flies out the robot's right side and lands on the floor", flew.x > 1.5 and absf(flew.z) < 0.5 and shot.global_position.y < 0.1, "landed %.2f m to the right" % flew.x)
	# Capacity limit.
	pollen.clear()
	robot.reset_pose()
	robot.set_pose_ftc(-50, -50, 90)
	robot.intake_front_power = 1.0
	for i in 6:
		pollen.spawn_ball(robot.global_position + Vector3((i - 2.5) * 0.03, pollen.radius + i * 0.09, -(robot.length / 2.0 + 0.045)))
		await steps(40)
	check("one feeder holds no more than its capacity", robot.held_total() == 2, "holding %d" % robot.held_total())
	robot.intake_front_power = -1.0
	await steps(200)
	check("reverse spits the balls back out", robot.held_total() == 0 and pollen.ball_count() == 6, "%d on field" % pollen.ball_count())
	robot.intake_front_power = 0.0
	# Hive rule: 7 pollen do nothing, the 8th tips the seesaw and all 8 score.
	pollen.clear()
	var hive: Dictionary = main.field.hive_of("red")
	var up0: String = hive["up_side"]
	var drop: Vector3 = hive["areas"][up0].global_position
	for i in 7:
		pollen.spawn_ball(drop + Vector3((i % 4 - 1.5) * 0.08, 0.0, 0.0))
		await steps(50)
	await steps(120)
	check("7 pollen in the raised cell: no tip, nothing scored", main.field.score["red"] == 0 and hive["up_side"] == up0 and main.field.cell_count("red", true) == 7, "%d in cell" % main.field.cell_count("red", true))
	pollen.spawn_ball(drop)
	await steps(90)
	check("8th pollen tips the hive and 8 are scored", main.field.score["red"] == 8 and main.field.tips["red"] == 1 and hive["up_side"] != up0, "score %d" % main.field.score["red"])
	await steps(600)
	check("pollen roll out of the lowered cell", main.field.cell_count("red", false) == 0 and pollen.ball_count() == 8, "%d left in cell" % main.field.cell_count("red", false))
	check("blue score is untouched", main.field.score["blue"] == 0)
	# A deployed lever against a flower releases its pollen.
	main.field.reset_elements(pollen)
	var before: int = pollen.ball_count()
	var fl = main.field.flowers[2]  # the flower on the left (red) wall
	robot.set_pose_ftc(fl["pos"].x / IN + (robot.length / 2.0 + 0.17) / IN, -fl["pos"].z / IN, 0)
	await steps(120)
	check("flower keeps its pollen while the lever is stowed", fl["count"] == 4 and pollen.ball_count() == before)
	robot.lever_back_servo = 1.0
	await steps(360)
	check("deployed lever empties the flower", fl["count"] == 0 and pollen.ball_count() == before + 4, "flower %d, +%d balls" % [fl["count"], pollen.ball_count() - before])
	pollen.clear()
	robot.reset_pose()
	await steps(5)

	# Field-centric: robot facing left, stick forward must still drive away from the driver.
	robot.reset_pose()
	teleop.reset_field_heading()
	robot.set_pose_ftc(-50, -50, 180)
	teleop.field_centric = true
	robot.wheel_powers = teleop.compute_powers(1, 0, 0)
	await steps(120)
	p = robot.get_pose_ftc()
	check("field-centric forward = away from driver", p.y > -30 and absf(p.x + 50) < 0.5, str(p))
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
