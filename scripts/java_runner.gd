extends Node
## Finds the OpModes in the TeamCode folder and starts one as a Java process (java/RunSim.java),
## which compiles the code and connects back to the simulator. Needs a JDK 11+ on this computer.

var pid := -1
var running_name := ""
var log_tail := ""

var _log_path := ""
var _poll := 0.0

func java_home() -> String:
	return ProjectSettings.globalize_path("res://java")

func teamcode_dir() -> String:
	var d := str(Config.value("java.teamcode_dir", ""))
	return d if d != "" else java_home().path_join("teamcode")

## OpModes found by reading the source files: [{ name, flavor, file }].
func scan_opmodes() -> Array:
	var out: Array = []
	_scan_dir(teamcode_dir(), out)
	out.sort_custom(func(a, b): return (a["flavor"] + a["name"]) > (b["flavor"] + b["name"]))
	return out

func _scan_dir(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan_dir(path.path_join(sub), out)
	var annotation := RegEx.create_from_string("@(TeleOp|Autonomous)\\b\\s*(\\(([^)]*)\\))?")
	var name_attr := RegEx.create_from_string("name\\s*=\\s*\"([^\"]*)\"")
	var class_name_re := RegEx.create_from_string("\\bclass\\s+(\\w+)")
	for file in dir.get_files():
		if not file.ends_with(".java"):
			continue
		var text := FileAccess.get_file_as_string(path.path_join(file))
		var m := annotation.search(text)
		if m == null or text.contains("@Disabled"):
			continue
		var cls := class_name_re.search(text)
		var name := cls.get_string(1) if cls != null else file.get_basename()
		var attr := name_attr.search(m.get_string(3))
		if attr != null and attr.get_string(1) != "":
			name = attr.get_string(1)
		out.append({"name": name, "flavor": "teleop" if m.get_string(1) == "TeleOp" else "auto", "file": file})

func is_running() -> bool:
	return pid > 0 and OS.is_process_running(pid)

func launch(opmode_name: String) -> void:
	stop()
	_log_path = OS.get_user_data_dir().path_join("java_run.log")
	if FileAccess.file_exists(_log_path):
		DirAccess.remove_absolute(_log_path)
	log_tail = "Starting Java..."
	running_name = opmode_name
	var args := [java_home().path_join("RunSim.java"), opmode_name, "--home", java_home(), "--teamcode", teamcode_dir(),
		"--port", str(int(Config.num("java.port", 7778))), "--log", _log_path]
	pid = OS.create_process(str(Config.value("java.command", "java")), args)
	if pid <= 0:
		log_tail = "Could not start Java. Install a JDK 11 or newer (https://adoptium.net) and make sure the\n'java' command works, or set java.command in robot_config.json to its full path."

func stop() -> void:
	if is_running():
		OS.kill(pid)
	pid = -1

func _process(dt: float) -> void:
	_poll -= dt
	if _poll > 0.0 or _log_path == "":
		return
	_poll = 0.3
	if FileAccess.file_exists(_log_path):
		var lines := FileAccess.get_file_as_string(_log_path).strip_edges().split("\n")
		log_tail = "\n".join(lines.slice(maxi(lines.size() - 14, 0)))

func _exit_tree() -> void:
	stop()
