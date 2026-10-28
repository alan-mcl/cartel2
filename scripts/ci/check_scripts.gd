extends SceneTree

## Load every gameplay, presentation, UI, dev, and test script in one process (CI parse sweep).

const SCAN_DIRS: Array[String] = [
	"res://scripts/gameplay",
	"res://scripts/presentation",
	"res://scripts/ui",
	"res://scripts/dev",
	"res://tests",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var paths := _collect_script_paths()
	paths.sort()
	var failures: Array[String] = []
	for path in paths:
		if not _load_script(path):
			failures.append(path)
	if failures.is_empty():
		print("OK: %d scripts loaded." % paths.size())
		quit(0)
		return
	for path in failures:
		push_error("Failed to load script: %s" % path)
	quit(1)


func _collect_script_paths() -> Array[String]:
	var out: Array[String] = []
	for dir_path in SCAN_DIRS:
		_collect_in_dir(dir_path, out)
	return out


func _collect_in_dir(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Cannot open directory: %s" % dir_path)
		return
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect_in_dir(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
	dir.list_dir_end()


func _load_script(path: String) -> bool:
	var resource: Variant = load(path)
	return resource != null
