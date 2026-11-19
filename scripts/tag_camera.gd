extends Node
## Simulated AprilTag camera on the turret (the main Arducam). No image processing: for every AprilTag on
## the field it works out whether the camera could see it (field of view, range, the tag facing the
## camera) and, if so, where it is in the camera's own frame: x right, y straight out of the lens, z up.
## tx / ty are the angles to the tag (positive = right / above).

var robot
var field
## Latest cluster detections: [{ name, key, percent, tx, ty, ta, dist_m, cam_xyz, roll }], best first.
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
	var a = Config.value("camera.position_m", null)
	if a is Array and a.size() == 3:
		_pos = Vector3(a[0], a[1], a[2])
	_pitch = deg_to_rad(Config.num("camera.mount_pitch_deg", 25.0))
	_hfov = Config.num("camera.fov_horizontal_deg", 82.0)
	_vfov = Config.num("camera.fov_vertical_deg", 56.2)
	_range = Config.inches("camera.max_range_in", 144.0)
	_max_view = Config.num("camera.max_view_angle_deg", 75.0)
	_tag_size = Config.inches("camera.tag_size_in", 4.0)
	_angle_noise = Config.num("camera.angle_noise_deg", 0.0)
	_pose_noise = Config.inches("camera.pose_noise_in", 0.0)

## Where the camera is and which way it looks, in world space: [position, forward, right, up].
func camera_frame() -> Array:
	var turret: Basis = robot.global_transform.basis * Basis(Vector3.UP, deg_to_rad(robot.turret_deg))
	var fwd := turret * Vector3(cos(_pitch), sin(_pitch), 0.0)
	var up := turret * Vector3(-sin(_pitch), cos(_pitch), 0.0)
	return [robot.global_position + turret * _pos, fwd, turret * Vector3(0, 0, 1), up]

func _physics_process(_dt: float) -> void:
	var cam := camera_frame()
	var found: Array = []
	for cluster in field.april_tag_clusters():
		# A cluster is detected when at least one of its four tags can be read.
		var seen := 0
		var best_area := 0.0
		for tag in cluster["tags"]:
			var v: Vector3 = tag["pos"] - cam[0]
			var dist := v.length()
			var f: float = v.dot(cam[1])
			if dist > _range or f <= 0.01:
				continue
			if absf(rad_to_deg(atan2(v.dot(cam[2]), f))) > _hfov / 2.0 or absf(rad_to_deg(atan2(v.dot(cam[3]), f))) > _vfov / 2.0:
				continue
			var facing: float = tag["normal"].dot(-v / dist)
			if facing < cos(deg_to_rad(_max_view)):
				continue
			seen += 1
			var image_area := 4.0 * tan(deg_to_rad(_hfov / 2.0)) * tan(deg_to_rad(_vfov / 2.0)) * dist * dist
			best_area = maxf(best_area, 100.0 * _tag_size * _tag_size * facing / image_area)
		if seen == 0:
			continue
		# The pose the SDK reports for a cluster is the centre of the cell's opening, not the sticker.
		var a: Vector3 = cluster["aim"] - cam[0]
		var af: float = a.dot(cam[1])
		var up: Vector3 = cluster["up"]
		found.append({"name": cluster["name"], "key": cluster["key"], "percent": 100.0 * seen / cluster["tags"].size(),
			"tx": rad_to_deg(atan2(a.dot(cam[2]), af)) + _rng.randfn(0.0, _angle_noise),
			"ty": rad_to_deg(atan2(a.dot(cam[3]), af)) + _rng.randfn(0.0, _angle_noise),
			"ta": best_area, "dist_m": a.length(), "cam_xyz": Vector3(a.dot(cam[2]), af, a.dot(cam[3])),
			# Roll: how the sticker is turned in the picture. Near 0 = right way up (a raised, scorable
			# cell seen from in front of its opening); near 180 = upside down (the lowered cell).
			"roll": rad_to_deg(atan2(up.dot(cam[2]), up.dot(cam[3])))})
	found.sort_custom(func(x, y): return x["ta"] > y["ta"])
	tags = found
	if found.is_empty():
		botpose = []
	else:
		var p: Vector3 = robot.get_pose_ftc()
		botpose = [p.x * Config.IN + _rng.randfn(0.0, _pose_noise), p.y * Config.IN + _rng.randfn(0.0, _pose_noise), p.z]

func summary() -> String:
	if tags.is_empty():
		return "no tags in view"
	var parts: Array = []
	for t in tags:
		parts.append("%s %d%%  bearing %+.0f  roll %+.0f" % [t["name"], int(t["percent"]), -t["tx"], t["roll"]])
	return "  |  ".join(parts)
