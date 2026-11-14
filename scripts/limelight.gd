extends Node
## Simulated Limelight on the turret. No image processing: for every AprilTag on the field it works out
## whether the camera could see it (field of view, range, the tag facing the camera) and, if so, the
## angles a real Limelight would report: tx (positive = tag is to the right) and ty (positive = above).

var robot
var field
## Latest detections: [{ id, tx, ty, ta, dist_m }], best (largest) first.
var tags: Array = []
## Robot pose from the tags, in FTC field coordinates: [x_m, y_m, heading_deg]; empty if no tag is in view.
var botpose: Array = []

var _pos := Vector3(0.164, 0.362, 0.0)
var _pitch := 0.436
var _hfov := 82.0
var _vfov := 56.2
var _range := 3.66
var _max_view := 75.0
var _tag_size := 0.1
var _angle_noise := 0.0
var _pose_noise := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	apply_config()

func apply_config() -> void:
	var a = Config.value("limelight.position_m", null)
	if a is Array and a.size() == 3:
		_pos = Vector3(a[0], a[1], a[2])
	_pitch = deg_to_rad(Config.num("limelight.mount_pitch_deg", 25.0))
	_hfov = Config.num("limelight.fov_horizontal_deg", 82.0)
	_vfov = Config.num("limelight.fov_vertical_deg", 56.2)
	_range = Config.inches("limelight.max_range_in", 144.0)
	_max_view = Config.num("limelight.max_view_angle_deg", 75.0)
	_tag_size = Config.inches("limelight.tag_size_in", 4.0)
	_angle_noise = Config.num("limelight.angle_noise_deg", 0.0)
	_pose_noise = Config.inches("limelight.pose_noise_in", 0.0)

## Where the camera is and which way it looks, in world space: [position, forward, right, up].
func camera_frame() -> Array:
	var turret: Basis = robot.global_transform.basis * Basis(Vector3.UP, deg_to_rad(robot.turret_deg))
	var fwd := turret * Vector3(cos(_pitch), sin(_pitch), 0.0)
	var up := turret * Vector3(-sin(_pitch), cos(_pitch), 0.0)
	return [robot.global_position + turret * _pos, fwd, turret * Vector3(0, 0, 1), up]

func _physics_process(_dt: float) -> void:
	var cam := camera_frame()
	var found: Array = []
	for tag in field.april_tags():
		var v: Vector3 = tag["pos"] - cam[0]
		var dist := v.length()
		var f: float = v.dot(cam[1])
		if dist > _range or f <= 0.01:
			continue
		var tx := rad_to_deg(atan2(v.dot(cam[2]), f))
		var ty := rad_to_deg(atan2(v.dot(cam[3]), f))
		if absf(tx) > _hfov / 2.0 or absf(ty) > _vfov / 2.0:
			continue
		# The tag has to face the camera enough to be read.
		var facing: float = tag["normal"].dot(-v / dist)
		if facing < cos(deg_to_rad(_max_view)):
			continue
		var image_area := 4.0 * tan(deg_to_rad(_hfov / 2.0)) * tan(deg_to_rad(_vfov / 2.0)) * dist * dist
		found.append({"id": tag["id"], "tx": tx + _rng.randfn(0.0, _angle_noise), "ty": ty + _rng.randfn(0.0, _angle_noise),
			"ta": 100.0 * _tag_size * _tag_size * facing / image_area, "dist_m": dist})
	found.sort_custom(func(a, b): return a["ta"] > b["ta"])
	tags = found
	if found.is_empty():
		botpose = []
	else:
		var p: Vector3 = robot.get_pose_ftc()
		botpose = [p.x * Config.IN + _rng.randfn(0.0, _pose_noise), p.y * Config.IN + _rng.randfn(0.0, _pose_noise), p.z]

func summary() -> String:
	if tags.is_empty():
		return "no tag in view"
	var parts: Array = []
	for t in tags:
		parts.append("tag %d  tx %+.1f  ty %+.1f" % [t["id"], t["tx"], t["ty"]])
	return "   |   ".join(parts)
