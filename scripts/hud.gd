extends CanvasLayer
## On-screen display: match clock, drive mode, robot pose, controls help.

var _timer_label: Label
var _state_label: Label
var _info_label: Label
var _help_label: Label
var _banner: Label
var _java_label: Label
var _menu_label: Label
var _menu_shade: ColorRect

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 10
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_timer_label = _label(top, 72, HORIZONTAL_ALIGNMENT_CENTER)
	_state_label = _label(top, 26, HORIZONTAL_ALIGNMENT_CENTER)
	_banner = _label(top, 22, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.modulate = Color(1.0, 0.8, 0.3)

	_info_label = _label(root, 20, HORIZONTAL_ALIGNMENT_LEFT)
	_info_label.position = Vector2(16, 14)

	# Java OpMode status + telemetry, top right.
	_java_label = _label(root, 18, HORIZONTAL_ALIGNMENT_LEFT)
	_java_label.anchor_left = 1.0
	_java_label.anchor_right = 1.0
	_java_label.offset_left = -560
	_java_label.offset_right = -16
	_java_label.offset_top = 14
	_java_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_java_label.modulate = Color(0.75, 1.0, 0.8)
	_menu_shade = ColorRect.new()
	_menu_shade.color = Color(0, 0, 0, 0.78)
	_menu_shade.anchor_right = 1.0
	_menu_shade.anchor_bottom = 1.0
	_menu_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_shade.visible = false
	root.add_child(_menu_shade)
	_menu_label = _label(_menu_shade, 28, HORIZONTAL_ALIGNMENT_CENTER)
	_menu_label.anchor_right = 1.0
	_menu_label.anchor_bottom = 1.0
	_menu_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_help_label = _label(root, 16, HORIZONTAL_ALIGNMENT_LEFT)
	_help_label.anchor_top = 1.0
	_help_label.anchor_bottom = 1.0
	_help_label.anchor_right = 1.0
	_help_label.offset_left = 16
	_help_label.offset_top = -150
	_help_label.offset_right = -16
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_label.offset_bottom = -12
	_help_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_help_label.modulate = Color(1, 1, 1, 0.8)
	_help_label.text = "\n".join([
		"GAMEPAD: left stick drive/strafe · right stick turn · LT intake · RT shoot · RB (hold) spit out · LB slow · RS click auto-aim · D-pad turret/hood by hand · A/B levers · Y field-centric · X reset field heading · Start match · Back reset",
		"KEYS: WASD drive · Q/E turn · Shift intake · Space shoot · B (hold) spit out · Ctrl slow · T auto-aim · Z/X turret, ↑/↓ hood by hand · 1/2 levers · F field-centric · H reset field heading · Enter match · M full match · R reset · C camera · J run Java OpMode · F1 hide help",
	])

func _label(parent: Node, font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func show_menu(text: String) -> void:
	_menu_label.text = text
	_menu_shade.visible = text != ""

func toggle_help() -> void:
	_help_label.visible = not _help_label.visible

func update_hud(d: Dictionary) -> void:
	if d.show_clock:
		var t := int(ceil(maxf(d.time_left, 0.0)))
		_timer_label.text = "%d:%02d" % [t / 60, t % 60]
	else:
		_timer_label.text = "-:--"
	_timer_label.modulate = d.clock_color
	_state_label.text = d.state_name
	_banner.text = d.banner
	_java_label.text = d.java
	var pose: Vector3 = d.pose
	_info_label.text = "\n".join([
		"Drive: %s" % ("Java OpMode" if d.java_driving else ("%s%s" % ["FIELD-centric" if d.field_centric else "ROBOT-centric", "  (SLOW)" if d.slow else ""])),
		"Pose:  x %6.1f in   y %6.1f in   heading %6.1f°" % [pose.x, pose.y, pose.z],
		"Speed: %4.1f in/s  (max %.1f)" % [d.speed_in, d.max_speed_in],
		"Pollen held: front %d  back %d%s" % [d.held_front, d.held_back, "   FULL" if d.full else ""],
		"Hive cells: %s" % d.hive,
		"Scored: %s" % d.score,
		"Shooter: %4.0f rpm   hood %2.0f°%s" % [d.flywheel_rpm, d.hood_deg,
			("  (%s)" % d.auto_shot) if d.auto_shot != "" else ""],
		"Turret: %+6.1f°  %s   %s" % [d.turret_deg, "360°" if d.turret_continuous else "limit ±%.1f°" % d.turret_half_range,
			("AUTO-AIM at %s hive tag" % d.alliance) if d.auto_aim else "manual"],
		"Levers: front %2.0f°   back %2.0f°" % [d.lever_front_deg, d.lever_back_deg],
		"Size:  %.1f x %.1f x %.1f in  %s" % [d.size_in.x, d.size_in.y, d.size_in.z,
			"OK" if maxf(d.size_in.x, maxf(d.size_in.y, d.size_in.z)) <= d.size_limit_in else "OVER %.0f in LIMIT" % d.size_limit_in],
		"Camera: %s" % d.camera,
		"Gamepad: %s" % (d.gamepad if d.gamepad != "" else "none – using keyboard"),
	])
