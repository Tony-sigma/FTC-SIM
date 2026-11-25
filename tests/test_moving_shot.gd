extends SceneTree
## Headless self-test:  godot --headless -s tests/test_moving_shot.gd
## Shooting on the move: the robot drives past the red hive (33 in to the side of it) while the built-in
## auto-aim, automatic hood and gate logic fire one pollen at each of four points along the way.
##
## Part 1 uses exact physics and checks that leading the shot works at all.
## Part 2 switches on the real-world imperfections from robot_config.json ("realism") and reports the
## share of shots that score. Options after "--":
##   --passes=5      passes per row in part 2 (4 shots each; default 2)
##   --turret=51     only this turret speed in part 2, in deg/s (default: 51 and the configured one)
##   --scale=2       multiply every imperfection by this (default 1)

const IN := 0.0254
var fails := 0
var main
var robot
var teleop
var field
var pollen
var cfg

func check(name: String, ok: bool, detail := "") -> void:
	print(("  PASS  " if ok else "  FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not ok:
		fails += 1

func steps(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	_run.call_deferred()

func option(name: String, default: float) -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return float(a.get_slice("=", 1))
	return default

## One pass at wheel power `p` (0 = stand still and fire all four from the start position).
func run_pass(start: Vector3, p: float, lead: bool, turret_deg_per_s: float) -> Dictionary:
	var fire_at: Array = [-52.0, -42.0, -32.0, -22.0]
	field.reset_elements(pollen)
	pollen.clear()
	robot.reset_pose()
	robot.set_pose_ftc(start.x, start.y, start.z)
	robot._turret_speed = turret_deg_per_s
	teleop.lead_shots = lead
	teleop.auto_aim = true
	teleop._plan = {}
	teleop.reset_sensor_errors()
	for i in 4:
		robot.load_ball(i % 2, "pollen", 1.0 - 0.25 * (i / 2))
	var max_err := 0.0
	var held := 0.0
	var dt := 1.0 / 60.0
	var done_at := -1
	# Stand still first so the turret, hood and flywheel are ready, then go.
	for i in 1500:
		var x_in: float = robot.global_position.x / IN
		var moving: bool = i >= 150
		var w := p if moving else 0.0
		robot.wheel_powers = [w, w, w, w]
		robot.aim_point = field.aim_point("red") + teleop.aim_lead
		teleop.shot_target = field.mouth_point("red")
		teleop.shot_outward = field.mouth_outward("red")
		# Only shots fired while still on the way past count: no waiting until the robot has stopped.
		var window: bool = moving and robot.held_total() > 0 and x_in <= -5.0 and (p == 0.0 or x_in >= fire_at[robot.shots_fired])
		teleop.run_mechanisms(dt, 0.0, 0.0, 0.0, window, false)
		if window:
			max_err = maxf(max_err, teleop.turret_error_deg())
			if not robot.gate_open:
				held += dt
		await physics_frame
		if done_at < 0 and moving and (robot.shots_fired == 4 or x_in > -5.0 or (p == 0.0 and i > 600)):
			done_at = i
		if done_at >= 0 and i > done_at + 130:
			break
	robot.wheel_powers = [0.0, 0.0, 0.0, 0.0]
	teleop.run_mechanisms(dt, 0.0, 0.0, 0.0, false, false)
	await steps(20)
	return {"fired": robot.shots_fired, "in": field.cell_count("red", true), "err": max_err, "held": held}

func _run() -> void:
	cfg = root.get_node("Config")
	cfg.realism_scale = 0.0   # exact, repeatable physics for part 1
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await steps(2)
	robot = main.robot
	teleop = main.teleop
	field = main.field
	pollen = main.pollen
	teleop.active = false
	main._external_control = true
	var turret_cfg: float = cfg.num("turret.servo_speed_deg_per_s", 400.0) * cfg.num("turret.servo_gear_teeth", 15.0) / cfg.num("turret.turret_gear_teeth", 70.0)
	var start := Vector3(-61, -52, 0)

	print("\n  PART 1 - perfect robot (exact physics), turret %.0f deg/s" % turret_cfg)
	print("    drive   lead   fired  in cell   worst turret lag")
	var exact := {}
	for lead in [false, true]:
		for p in [0.5, 1.0]:
			var r: Dictionary = await run_pass(start, p, lead, turret_cfg)
			exact["%s %.1f" % [lead, p]] = r
			print("    %3.0f %%   %-5s  %d      %d         %4.1f deg" % [p * 100.0, "yes" if lead else "no", r["fired"], r["in"], r["err"]])
	check("at full speed, aiming straight at the hive misses", exact["false 1.0"]["in"] <= 1, "%d in" % exact["false 1.0"]["in"])
	check("at full speed, leading the shot scores", exact["true 1.0"]["in"] >= 3, "%d in" % exact["true 1.0"]["in"])
	check("at half speed, leading the shot scores all 4", exact["true 0.5"]["in"] == 4, "%d in" % exact["true 0.5"]["in"])

	var passes := int(option("passes", 2.0))
	var only := option("turret", 0.0)
	var scale := option("scale", 1.0)
	cfg.realism_scale = scale
	cfg.rng.seed = 20261125
	print("\n  PART 2 - real-world imperfections x %.1f (shot scatter %.1f %% and %.1f deg, turret %.2f s late with %.1f deg of play," % [scale,
		cfg.real("shot_speed_scatter_percent", 0.0), cfg.real("shot_angle_scatter_deg", 0.0), cfg.real("turret_delay_s", 0.0), cfg.real("turret_backlash_deg", 0.0)])
	print("           speed reading %.2f s late, %.0f %% off, +-%.0f in/s noise, position %.1f in off), %d shots per row" % [
		cfg.real("speed_delay_s", 0.0), cfg.real("speed_scale_error_percent", 0.0), cfg.real("speed_noise_in_per_s", 0.0), cfg.real("pose_error_in", 0.0), passes * 4])
	print("    turret      drive         fired while moving   scored    worst turret lag")
	var standing_hits := 0
	for turret in ([only] if only > 0.0 else [51.0, turret_cfg]):
		for p in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var fired := 0
			var hits := 0
			var worst := 0.0
			for n in passes:
				var r: Dictionary = await run_pass(Vector3(-42, -52, 0) if p == 0.0 else start, p, true, turret)
				fired += r["fired"]
				hits += r["in"]
				worst = maxf(worst, r["err"])
			if p == 0.0:
				standing_hits = maxi(standing_hits, hits)
			print("    %3.0f deg/s   %-12s  %2d of %2d             %2d (%3.0f %%)   %4.1f deg" % [turret, "standing" if p == 0.0 else "%.0f %% speed" % (p * 100.0), fired, passes * 4, hits, 100.0 * hits / (passes * 4), worst])
	check("with imperfections, standing shots still mostly score", standing_hits >= passes * 4 * 0.6, "%d of %d" % [standing_hits, passes * 4])
	robot._turret_speed = turret_cfg

	print("\n%s" % ("ALL TESTS PASSED" if fails == 0 else "%d TEST(S) FAILED" % fails))
	quit(1 if fails > 0 else 0)
