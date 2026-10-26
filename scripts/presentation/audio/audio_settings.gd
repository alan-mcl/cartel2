class_name AudioSettings
extends RefCounted

const SETTINGS_VERSION := 1
const SETTINGS_DIR := "user://settings/"
const DEFAULT_FILE := "user://settings/settings.json"
const LEGACY_FILE := "user://settings.json"

static var settings_path: String = DEFAULT_FILE

const DEFAULT_VOLUMES := {
	"master": 0.80,
	"music": 0.70,
	"sfx": 0.85,
	"ambience": 0.55,
	"ui": 0.45,
}


static func default_volumes() -> Dictionary:
	return DEFAULT_VOLUMES.duplicate(true)


static func ensure_settings_dir() -> void:
	DirAccess.make_dir_recursive_absolute(SETTINGS_DIR)


static func read_volumes() -> Dictionary:
	var volumes := default_volumes()
	ensure_settings_dir()
	var path := _resolve_read_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return volumes
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("AudioSettings: could not read %s" % path)
		return volumes
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return volumes
	var audio: Variant = parsed.get("audio", {})
	if typeof(audio) != TYPE_DICTIONARY:
		return volumes
	for key in DEFAULT_VOLUMES.keys():
		if audio.has(key):
			volumes[key] = clampf(float(audio[key]), 0.0, 1.0)
	return volumes


static func _resolve_read_path() -> String:
	if FileAccess.file_exists(settings_path):
		return settings_path
	if FileAccess.file_exists(LEGACY_FILE):
		return LEGACY_FILE
	return settings_path


static func write_volumes(volumes: Dictionary) -> bool:
	ensure_settings_dir()
	var audio_section: Dictionary = {}
	for key in DEFAULT_VOLUMES.keys():
		audio_section[key] = clampf(float(volumes.get(key, DEFAULT_VOLUMES[key])), 0.0, 1.0)
	var payload := {
		"version": SETTINGS_VERSION,
		"audio": audio_section,
	}
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file == null:
		push_error(
			"AudioSettings: could not write %s (%s)"
			% [settings_path, error_string(FileAccess.get_open_error())]
		)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


static func linear_to_bus_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return linear_to_db(linear)


static func bus_db_to_linear(db: float) -> float:
	if db <= -79.0:
		return 0.0
	return db_to_linear(db)
