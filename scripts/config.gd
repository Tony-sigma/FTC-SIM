extends Node
## Autoload "Config": loads robot_config.json, the one shared file of robot/field numbers.

const IN := 0.0254  # metres per inch
const FILE_NAME := "robot_config.json"

var data: Dictionary = {}
var loaded_from := ""

func _ready() -> void:
	load_config()

## The folder the game's loose files live in: the project folder when run from the Godot editor, and
## the folder holding the game when it is a built executable (on a Mac, the folder the .app sits in).
func app_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").trim_suffix("/")
	var dir := OS.get_executable_path().get_base_dir()
	var marker := dir.find(".app/Contents/MacOS")
	if marker >= 0:
		dir = dir.substr(0, marker).get_base_dir()
	return dir

func load_config() -> bool:
	# A robot_config.json next to the game wins, so the numbers can be edited without rebuilding it.
	var candidates := [app_dir().path_join(FILE_NAME), "res://" + FILE_NAME]
	for path in candidates:
		if not FileAccess.file_exists(path):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			data = parsed
			loaded_from = path
			return true
		push_error("Config: %s is not valid JSON, ignoring it" % path)
	push_error("Config: no usable %s found, using built-in defaults" % FILE_NAME)
	return false

## Look up "section.key"; returns `default` if missing.
func value(path: String, default = null):
	var node = data
	for part in path.split("."):
		if node is Dictionary and node.has(part):
			node = node[part]
		else:
			push_warning("Config: '%s' missing, using default %s" % [path, str(default)])
			return default
	return node

func num(path: String, default: float) -> float:
	var v = value(path, default)
	return float(v) if (v is float or v is int) else default

## A length stored in inches, returned in metres.
func inches(path: String, default_in: float) -> float:
	return num(path, default_in) * IN
