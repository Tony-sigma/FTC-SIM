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
	main._external_control = true
	robot.aim_point = null
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
	check("turret starts at home (straight ahead), levers stowed", absf(robot.turret_from_home_deg()) < 0.01 and robot.lever_front_deg < 0.01)
	var shooter_fwd: Vector3 = (robot.global_transform.basis * Basis(Vector3.UP, deg_to_rad(robot.turret_deg))).x
	check("at home the shooter points to the robot's front", shooter_fwd.distance_to(-robot.global_transform.basis.z) < 0.01, str(shooter_fwd))
	robot.turret_goal_deg = -30.0
	robot.lever_front_servo = 1.0
	await steps(12)
	check("mechanisms do not snap instantly", robot.turret_deg < 89.0 and robot.turret_deg > 70.0 and robot.lever_front_deg > 5.0 and robot.lever_front_deg < 60.0,
		"turret %.1f, lever %.1f after 0.1 s" % [robot.turret_deg, robot.lever_front_deg])
	await steps(360)
	check("turret turns far past the old servo limit", absf(robot.turret_deg + 30.0) < 0.01, "%.2f deg" % robot.turret_deg)
	robot.turret_goal_deg = 170.0
	await steps(60)
	check("turret takes the short way round (through 180)", robot.turret_deg < -40.0, "%.1f deg" % robot.turret_deg)
	check("front lever deploys to 90, back stays stowed", absf(robot.lever_front_deg - 90.0) < 0.01 and robot.lever_back_deg < 0.01)
	# Auto-aim: the shooter side of the turret faces the tag under the raised cell, wherever the robot is.
	for pose in [Vector3(-50, -50, 90), Vector3(40, 50, -30), Vector3(-45, 45, 200)]:
		robot.set_pose_ftc(pose.x, pose.y, pose.z)
		var tag: Vector3 = main.field.aim_point("red")
		robot.aim_point = tag
		await steps(600)
		var to_tag: Vector3 = tag - robot.global_position
		to_tag.y = 0.0
		var shooter_dir: Vector3 = (robot.global_transform.basis * Basis(Vector3.UP, deg_to_rad(robot.turret_deg))).x
		var err: float = rad_to_deg(shooter_dir.angle_to(to_tag))
		check("auto-aim faces the red hive tag from %s" % str(pose), err < 1.0, "error %.2f deg" % err)
	robot.aim_point = null
	robot.reset_pose()
	await steps(240)

	# Pollen: intake swallows a ball, the shooter launches it.
	var pollen = main.pollen
	pollen.clear()
	robot.set_pose_ftc(-50, -50, 90)
	await steps(5)
	var ball = pollen.spawn_ball(robot.global_position + Vector3(0, pollen.radius, -(robot.length / 2.0 + 0.5)))
	var ball_z0: float = ball.global_position.z
	robot.wheel_powers = [0.3, 0.3, 0.3, 0.3]
	await steps(180)
	check("intake off: ball is pushed, not swallowed", robot.held_total() == 0 and pollen.ball_count() == 1 and ball.global_position.z < ball_z0 - 0.05)
	robot.intake_front_power = 1.0
	robot.wheel_powers = [1.0, 1.0, 1.0, 1.0]
	await steps(120)
	check("intake on at full speed: ball is swallowed into the front feeder", robot.held_count(0) == 1 and pollen.ball_count() == 0)
	robot.wheel_powers = [0.0, 0.0, 0.0, 0.0]
	await steps(120)
	check("ball waits at the neck while the flywheel is off", robot.held_count(0) == 1 and robot.shots_fired == 0)
	robot.intake_front_power = 0.0
	robot.set_pose_ftc(-50, -50, 90)  # a lane where the shot does not hit the hive frame
	robot.shooter_power = 0.22
	await steps(240)
	check("flywheel alone does not fire", robot.shots_fired == 0 and absf(robot.flywheel_fraction - 0.22) < 0.01)
	var start: Vector3 = robot.global_position
	robot.intake_front_power = 1.0
	await steps(30)
	check("flywheel + feeder: ball is launched", robot.held_total() == 0 and robot.shots_fired == 1 and pollen.ball_count() == 1)
	robot.intake_front_power = 0.0
	robot.shooter_power = 0.0
	var shot = get_nodes_in_group("pollen")[0]
	await steps(360)
	var flew: Vector3 = shot.global_position - start
	check("shot flies out of the robot's front and lands on the floor", flew.z < -0.8 and absf(flew.x) < 0.5 and shot.global_position.y < 0.1, "landed %.2f m ahead" % -flew.z)
	# Capacity limit.
	pollen.clear()
	robot.reset_pose()
	robot.set_pose_ftc(-50, -50, 90)
	robot.intake_front_power = 1.0
	for i in 6:
		pollen.spawn_ball(robot.global_position + Vector3((i - 2.5) * 0.03, pollen.radius + i * 0.09, -(robot.length / 2.0 + 0.06)))
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
	# Automatic hood: from several places on the field, a shot lands in the raised red cell.
	for pose in [Vector3(-58, -48, 0), Vector3(-40, -55, 120), Vector3(30, -60, -90), Vector3(0, -60, 180)]:
		pollen.clear()
		main.field.reset_elements(pollen)
		pollen.clear()
		robot.reset_pose()
		robot.set_pose_ftc(pose.x, pose.y, pose.z)
		robot.aim_point = main.field.aim_point("red")
		teleop.shot_outward = main.field.mouth_outward("red")
		robot.feeders = [[1.0], []]
		await steps(480)  # let the turret come round first: the exit point moves with it
		var plan: Dictionary = teleop.compute_shot(main.field.mouth_point("red"))
		robot.hood_servo = plan["hood_servo"]
		robot.shooter_power = plan["power"]
		await steps(300)
		robot.intake_front_power = 1.0
		await steps(360)
		robot.intake_front_power = 0.0
		check("auto hood scores from %s" % str(pose), plan["ok"] and robot.shots_fired == 1 and main.field.cell_count("red", true) == 1,
			"%s, hood %.1f deg, power %.2f, in cell %d" % [plan["reason"], robot.hood_deg, plan["power"], main.field.cell_count("red", true)])
	robot.set_pose_ftc(-55, 10, 45)
	await steps(5)
	var behind: Dictionary = teleop.compute_shot(main.field.mouth_point("red"))
	robot.set_pose_ftc(-13, -30, 0)
	robot.aim_point = main.field.aim_point("red")
	await steps(480)
	var near: Dictionary = teleop.compute_shot(main.field.mouth_point("red"))
	check("right under the hive the shot is reported as too close", not near["ok"] and str(near["reason"]).begins_with("TOO CLOSE"), str(near["reason"]))
	robot.set_pose_ftc(-55, 10, 45)
	await steps(5)
	behind = teleop.compute_shot(main.field.mouth_point("red"))
	check("from behind the cell's mouth the shot is reported as impossible", not behind["ok"] and behind["reason"] == "WRONG SIDE OF HIVE", str(behind["reason"]))
	robot.aim_point = null
	robot.shooter_power = 0.0
	# Limelight: sees the tag it is pointed at, with tx near zero; sees nothing when turned away.
	robot.reset_pose()
	robot.set_pose_ftc(-58, -48, 0)
	var our_tag: Vector3 = main.field.aim_point("red")
	robot.aim_point = our_tag
	await steps(480)
	var seen: Array = main.limelight.tags
	var centred := false
	for t in seen:
		if absf(t["tx"]) < 0.5:
			centred = true
	check("Limelight sees the tag the turret points at, centred", centred, main.limelight.summary())
	check("Limelight gives the robot's field position", main.limelight.botpose.size() == 3 and absf(main.limelight.botpose[0] - (-58 * IN)) < 0.01, str(main.limelight.botpose))
	robot.aim_point = null
	robot.turret_goal_deg = wrapf(robot.turret_deg + 180.0, -180.0, 180.0)
	await steps(480)
	check("Limelight sees nothing when the turret faces away", main.limelight.tags.is_empty() and main.limelight.botpose.is_empty(), main.limelight.summary())
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

	# Player's-view driving: W goes away from the player whatever way the robot faces.
	teleop.field_centric = true
	for case in [[Vector3(1, 0, 0), 180.0, "driver camera, robot facing the driver"], [Vector3(1, 0, 0), 90.0, "driver camera, robot facing sideways"],
			[Vector3(0, 0, -1), 0.0, "top-down camera, robot facing right"]]:
		robot.reset_pose()
		robot.set_pose_ftc(-50, -50, case[1])
		# Use the real cameras: main works out "away from the player" from the one in use.
		while main._cam_index != (1 if case[0].z < -0.5 else 0):
			main._next_camera()
		await steps(4)
		check("camera gives the expected view direction", teleop.view_forward.distance_to(case[0]) < 0.01, str(teleop.view_forward))
		robot.wheel_powers = teleop.compute_powers(1, 0, 0)
		await steps(90)
		var moved: Vector3 = robot.global_position - Vector3(-50 * IN, 0, 50 * IN)
		var along: float = moved.dot(case[0])
		var across: float = (moved - case[0] * along).length()
		check("W drives away from the player: %s" % case[2], along > 0.5 and across < 0.02 and absf(robot.get_pose_ftc().z - wrapf(case[1], -180.0, 180.0)) < 0.5, "%.2f m forward, %.3f m sideways" % [along, across])
	while main._cam_index != 0:
		main._next_camera()
	robot.reset_pose()
	robot.set_pose_ftc(-50, 20, 90)
	await steps(4)
	robot.wheel_powers = teleop.compute_powers(0, 1, 0)
	await steps(90)
	check("D strafes to the player's right", (robot.global_position - Vector3(-50 * IN, 0, -20 * IN)).dot(Vector3(0, 0, 1)) > 0.4)
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
