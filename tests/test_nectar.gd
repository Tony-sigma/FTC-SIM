extends SceneTree
## Headless self-test:  godot --headless -s tests/test_nectar.gd
## NECTAR, the flowers, weight-based hive tips and the shooter's flywheel physics.
## Also prints the "can we shoot it?" report for pollen and nectar.

const IN := 0.0254
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
	var field = main.field
	var pollen = main.pollen
	teleop.active = false
	main._external_control = true
	robot.aim_point = null
	var cfg = root.get_node("Config")

	# --- Staging -------------------------------------------------------------------------------
	await steps(300)
	check("3 red nectar start in the raised red cell", field.cell_count("red", true) == 3 and absf(field.cell_weight_g("red", true) - 79.5) < 0.1,
		"%d balls, %.1f g" % [field.cell_count("red", true), field.cell_weight_g("red", true)])
	check("3 blue nectar start in the raised blue cell", field.cell_count("blue", true) == 3, "%d balls" % field.cell_count("blue", true))
	check("5 more nectar per alliance wait off the field, no tips yet", field.nectar_reserve["red"] == 5 and field.nectar_reserve["blue"] == 5 and field.tips["red"] == 0 and field.tips["blue"] == 0 and pollen.nectar_count() == 6)
	check("flowers hold 4 pollen each, gardens score 4 each", field.flowers.all(func(f): return f["stack"] == ["pollen", "pollen", "pollen", "pollen"]) and field.points()["red"] == 4 + 6 and field.points()["blue"] == 4 + 6, str(field.points()))

	# --- First tip: the staged nectar already weigh 79.5 g, so 2 pollen are enough -----------------
	var hive: Dictionary = field.hive_of("red")
	var up0: String = hive["up_side"]
	var drop: Vector3 = hive["areas"][up0].global_position
	pollen.spawn_ball(drop)
	await steps(150)
	check("3 nectar + 1 pollen (92 g): no tip", field.tips["red"] == 0 and hive["up_side"] == up0, "%.1f g" % field.cell_weight_g("red", true))
	pollen.spawn_ball(drop)
	await steps(120)
	check("3 nectar + 2 pollen (104.5 g): the hive tips", field.tips["red"] == 1 and hive["up_side"] != up0)
	await steps(600)
	check("everything rolls out of the lowered cell onto the field", field.cell_count("red", false) == 0, "%d left" % field.cell_count("red", false))
	check("the tip lets the humans put one more red nectar in the loading zone", field.nectar_reserve["red"] == 4 and pollen.nectar_count() == 7, "reserve %d, on field %d" % [field.nectar_reserve["red"], pollen.nectar_count()])
	var in_zone := false
	for b in get_nodes_in_group("nectar"):
		var p: Vector3 = b.global_position
		if p.x < -1.45 and p.z < -0.5 and p.z > -1.25 and p.y < 0.06:
			in_zone = true
	check("that nectar is lying in the red loading zone", in_zone)

	# --- The shooter with each kind of ball ---------------------------------------------------------
	print("\n  SHOOTER REPORT (gap between the wheel pairs %.1f mm, spinning mass %.5f kg m^2, grip %.2f, feeder push %.1f N)" % [robot._wheel_gap * 1000.0, robot._fly_inertia, robot._wheel_grip, robot._feeder_push])
	for kind in ["pollen", "nectar_red"]:
		var b: Dictionary = pollen.props(kind)
		var r22: Dictionary = robot.shot_physics(kind, 0.22)
		var min_frac: float = sqrt(2.0 * r22["stored_j"] / robot._fly_inertia) / robot._omega_max
		print("    %-7s %.1f mm, %.1f g: squashed %.1f mm (%.0f %% of its size), pushes back %.0f N, takes %.2f J to squash (%.2f J lost)" % [
			kind.get_slice("_", 0), b["radius"] * 2000.0, b["mass"] * 1000.0, robot.squeeze_m(kind) * 1000.0, robot.squeeze_m(kind) / (b["radius"] * 2.0) * 100.0,
			b["squeeze_force_n"], r22["stored_j"], r22["lost_j"]])
		print("            needs %.1f N of push to feed; jams below %.0f rpm; at 1320 rpm leaves at %.2f m/s and the flywheel dips to %.0f rpm (-%.0f %%)" % [
			r22["push_n"], min_frac * robot.flywheel_max_rpm, r22["speed"], r22["after"] * robot.flywheel_max_rpm, (1.0 - r22["after"] / 0.22) * 100.0])
	var np: Dictionary = robot.shot_physics("nectar_red", 0.22)
	var pp: Dictionary = robot.shot_physics("pollen", 0.22)
	check("the wheels can feed a nectar", np["push_n"] <= robot._feeder_push, "needs %.1f N" % np["push_n"])
	check("a nectar goes through at shooting speed, slower than a pollen", np["ok"] and pp["ok"] and np["speed"] < pp["speed"] and np["speed"] > 0.85 * pp["speed"], "%.2f vs %.2f m/s" % [np["speed"], pp["speed"]])
	check("a nectar slows the flywheel more than a pollen", np["after"] < pp["after"] and pp["after"] > 0.94 * 0.22 and np["after"] > 0.8 * 0.22, "pollen %.3f nectar %.3f of 0.220" % [pp["after"], np["after"]])
	check("at a crawl the flywheel cannot squeeze a nectar through", not robot.shot_physics("nectar_red", 0.08)["ok"] and robot.shot_physics("pollen", 0.08)["ok"])

	# --- Intake a nectar from the floor --------------------------------------------------------------
	pollen.clear()
	robot.reset_pose()
	robot.set_pose_ftc(-50, -50, 90)
	await steps(5)
	pollen.spawn_ball(robot.global_position + Vector3(0, 0.046, -(robot.length / 2.0 + 0.4)), Vector3.ZERO, null, Vector3.ZERO, "nectar_red")
	robot.intake_front_power = 1.0
	robot.wheel_powers = [0.6, 0.6, 0.6, 0.6]
	await steps(120)
	robot.wheel_powers = [0.0, 0.0, 0.0, 0.0]
	check("the intake swallows a nectar and knows what it holds", robot.held_of("nectar") == 1 and robot.next_kind() == "nectar_red" and pollen.nectar_count() == 0, "holding %d" % robot.held_total())
	robot.intake_front_power = -1.0
	await steps(60)
	robot.intake_front_power = 0.0
	check("reverse spits the nectar back out as a nectar", robot.held_total() == 0 and pollen.nectar_count() == 1)

	# --- Jam: flywheel too slow for a nectar ----------------------------------------------------------
	pollen.clear()
	robot.reset_pose()
	robot.set_pose_ftc(-50, -50, 90)
	robot.load_ball(0, "nectar_red")
	robot.shooter_power = 0.08
	await steps(240)
	robot.intake_front_power = 1.0
	await steps(90)
	check("flywheel at 480 rpm: the nectar jams instead of shooting", robot.shots_fired == 0 and robot.held_total() == 1 and robot.jam_reason.begins_with("NECTAR JAMMED"), robot.jam_reason)
	await steps(60)
	check("keep feeding a slow flywheel and it stays jammed", robot.shots_fired == 0 and robot.held_total() == 1)
	robot.intake_front_power = 0.0
	robot.shooter_power = 0.22
	await steps(120)
	robot.intake_front_power = 1.0
	await steps(60)
	check("stop feeding, spin the flywheel up, feed again: the same nectar goes", robot.shots_fired == 1 and robot.held_total() == 0 and robot.jam_reason == "" and pollen.nectar_count() == 1)
	robot.intake_front_power = 0.0

	# --- Flywheel dip and recovery ------------------------------------------------------------------------
	for case in [["pollen", true], ["nectar_red", true], ["nectar_red", false]]:
		pollen.clear()
		robot.reset_pose()
		robot.set_pose_ftc(-50, -50, 90)
		robot.velocity_hold = case[1]
		robot.shooter_power = 0.22
		await steps(600)
		robot.load_ball(0, case[0])
		robot.intake_front_power = 1.0
		var n := 0
		while robot.shots_fired == 0 and n < 60:
			await steps(1)
			n += 1
		var dip: float = robot.flywheel_fraction
		var frames := 0
		while robot.flywheel_fraction < 0.98 * 0.22 and frames < 600:
			await steps(1)
			frames += 1
		robot.intake_front_power = 0.0
		var label := "%s, %s" % [str(case[0]).get_slice("_", 0), "speed held (RUN_USING_ENCODER)" if case[1] else "plain power (RUN_WITHOUT_ENCODER)"]
		if case[1]:
			check("flywheel recovers quickly after a %s" % label, robot.shots_fired == 1 and frames <= 20, "dipped to %.0f rpm, back in %.2f s" % [dip * 6000.0, frames / 60.0])
		else:
			check("flywheel recovers slowly after a %s" % label, robot.shots_fired == 1 and frames > 30, "dipped to %.0f rpm, back in %.2f s" % [dip * 6000.0, frames / 60.0])
	robot.velocity_hold = true

	# --- A stream of four --------------------------------------------------------------------------------
	for case in [["pollen", true], ["nectar_red", true], ["nectar_red", false]]:
		pollen.clear()
		robot.reset_pose()
		robot.set_pose_ftc(-50, -50, 90)
		robot.velocity_hold = case[1]
		robot.shooter_power = 0.22
		await steps(600)
		for i in 4:
			robot.load_ball(i % 2, case[0], 1.0 - 0.25 * (i / 2))
		robot.intake_front_power = 1.0
		robot.intake_back_power = 1.0
		var speeds: Array = []
		var n := 0
		while speeds.size() < 4 and n < 600:
			await steps(1)
			n += 1
			if robot.shots_fired > speeds.size():
				speeds.append(robot.last_shot["speed"])
		robot.intake_front_power = 0.0
		robot.intake_back_power = 0.0
		var text := ", ".join(speeds.map(func(v): return "%.2f" % v)) + " m/s in %.2f s" % (n / 60.0)
		var name := "four %s in a row, %s" % [str(case[0]).get_slice("_", 0), "speed held" if case[1] else "plain power"]
		if speeds.size() < 4:
			check(name, false, "only %d fired: %s" % [speeds.size(), text])
		elif case[1]:
			check(name + ": every shot the same speed", speeds.min() > 0.97 * speeds.max(), text)
		else:
			check(name + ": each shot weaker than the last", speeds[3] < 0.9 * speeds[0], text)
	robot.velocity_hold = true

	# --- Shoot nectar into the hive with the automatic hood ----------------------------------------------
	for pose in [Vector3(-58, -48, 0), Vector3(-40, -55, 120), Vector3(34, -50, -90), Vector3(0, -60, 180)]:
		field.reset_elements(pollen)
		pollen.clear()
		robot.reset_pose()
		robot.set_pose_ftc(pose.x, pose.y, pose.z)
		robot.aim_point = field.aim_point("red")
		teleop.shot_outward = field.mouth_outward("red")
		robot.load_ball(0, "nectar_red")
		await steps(480)
		var plan: Dictionary = teleop.compute_shot(field.mouth_point("red"))
		robot.hood_servo = plan.get("hood_servo", robot.hood_servo)
		robot.shooter_power = plan["power"]
		await steps(300)
		robot.intake_front_power = 1.0
		await steps(360)
		robot.intake_front_power = 0.0
		var cell: Array = field.cell_balls("red", true)
		check("a NECTAR shot lands in the raised cell from %s" % str(pose), plan["ok"] and robot.shots_fired == 1 and cell.size() == 1 and pollen.kind_of(cell[0]) == "nectar_red",
			"%s, hood %.1f deg, flywheel %.0f rpm, %.1f m/s, in cell %d" % [plan["reason"], robot.hood_deg, plan["power"] * 6000.0, robot.last_shot.get("speed", 0.0), cell.size()])
	# Four nectar in an empty cell (106 g) tip it.
	field.reset_elements(pollen)
	pollen.clear()
	robot.reset_pose()
	robot.set_pose_ftc(-58, -48, 0)
	robot.aim_point = field.aim_point("red")
	teleop.shot_outward = field.mouth_outward("red")
	for i in 4:
		robot.load_ball(i % 2, "nectar_red", 1.0 - 0.25 * (i / 2))
	await steps(480)
	var plan4: Dictionary = teleop.compute_shot(field.mouth_point("red"))
	robot.hood_servo = plan4.get("hood_servo", robot.hood_servo)
	robot.shooter_power = plan4["power"]
	await steps(300)
	var tol: float = cfg.num("driver.shoot_speed_tolerance", 0.04)
	for i in 480:
		# Feed like the built-in TeleOp does: only while the flywheel is at the speed the shot needs.
		var ready: bool = absf(robot.flywheel_fraction - robot.shooter_power) <= tol * robot.shooter_power
		robot.gate_open = ready
		robot.intake_front_power = 1.0
		robot.intake_back_power = 1.0
		await steps(1)
	robot.intake_front_power = 0.0
	robot.intake_back_power = 0.0
	robot.gate_open = true
	check("a stream of 4 nectar into an empty cell tips the hive", robot.shots_fired == 4 and field.tips["red"] == 1, "fired %d, tips %d, %.1f g in the raised cell" % [robot.shots_fired, field.tips["red"], field.cell_weight_g("red", true)])
	robot.aim_point = null
	robot.shooter_power = 0.0

	# --- Flowers ------------------------------------------------------------------------------------------
	field.reset_elements(pollen)
	robot.reset_pose()
	await steps(5)
	var fl: Dictionary = field.flowers[2]   # on the red wall
	var top: Vector3 = fl["pos"] + Vector3(0, 0.75, 0)
	var loose: int = pollen.ball_count()
	pollen.spawn_ball(top, Vector3.ZERO, null, Vector3.ZERO, "nectar_red")
	await steps(90)
	check("a nectar dropped into the top of a flower joins the stack", fl["stack"] == ["pollen", "pollen", "pollen", "pollen", "nectar_red"], str(fl["stack"]))
	var heights: Array = field.flower_heights(fl["stack"])
	check("it sits on top of the four pollen", absf(heights[4] / IN - (4 * 2.8 + 1.8)) < 0.05 and absf(heights[0] / IN - 1.4) < 0.05, "centre %.1f in up" % (heights[4] / IN))
	check("red owns the flower: 2 per scoring ball + 5 for the bottom nectar", field.points()["red"] == 4 + 6 + 2 * 4 + 5, str(field.points()))
	robot.set_pose_ftc(fl["pos"].x / IN + (robot.length / 2.0 + 0.12) / IN, -fl["pos"].z / IN, 0)
	robot.lever_back_servo = 1.0
	await steps(360)
	check("the lever takes out the pollen but never the nectar", fl["stack"] == ["nectar_red"] and pollen.ball_count() == loose + 4, "%s, +%d pollen" % [str(fl["stack"]), pollen.ball_count() - loose])
	check("the nectar comes to rest on the middle ring", absf(field.flower_heights(fl["stack"])[0] / IN - 6.9) < 0.05)
	robot.lever_back_servo = 0.0
	pollen.spawn_ball(top, Vector3.ZERO, null, Vector3.ZERO, "nectar_blue")
	await steps(90)
	var pts: Dictionary = field.points()
	check("a blue nectar on top takes the flower: blue 2 per ball, red keeps the bottom bonus", fl["stack"] == ["nectar_red", "nectar_blue"] and pts["blue"] == 4 + 6 + 4 and pts["red"] >= 4 + 6 + 5, str(pts))
	for i in 6:
		pollen.spawn_ball(top, Vector3.ZERO, null, Vector3.ZERO, "pollen")
		await steps(60)
	check("a full flower takes no more", fl["stack"].size() <= 7 and field.flower_heights(fl["stack"])[-1] <= 21.5 * IN, "%d in the flower" % fl["stack"].size())

	# --- The last minute: all remaining nectar may come in --------------------------------------------------
	field.reset_elements(pollen)
	robot.reset_pose()
	main.match_timer.start_teleop_only()
	await steps(60)
	check("before the last minute the waiting nectar stay off the field", field.nectar_reserve["red"] == 5 and pollen.nectar_count() == 6)
	main.match_timer.time_left = 60.0
	await steps(240)
	check("with a minute to go all the waiting nectar come in", field.nectar_reserve["red"] == 0 and field.nectar_reserve["blue"] == 0 and pollen.nectar_count() == 16, "%d nectar on the field" % pollen.nectar_count())
	main.match_timer.reset()

	print("\n%s" % ("ALL TESTS PASSED" if fails == 0 else "%d TEST(S) FAILED" % fails))
	quit(1 if fails > 0 else 0)
