class_name AudioLibrary
extends RefCounted

const LIBRARY_PATH := "res://data/audio/library.json"

var _music: Dictionary = {}
var _ambience: Dictionary = {}
var _sfx: Dictionary = {}


static func load_default() -> AudioLibrary:
	var lib := AudioLibrary.new()
	lib._load_from_file(LIBRARY_PATH)
	return lib


func _load_from_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("AudioLibrary: missing %s" % path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("AudioLibrary: invalid JSON in %s" % path)
		return
	_music = _coerce_track_map(parsed.get("music", {}))
	_ambience = _coerce_track_map(parsed.get("ambience", {}))
	_sfx = _coerce_sfx_map(parsed.get("sfx", {}))


func _coerce_track_map(raw: Variant) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for context in raw.keys():
		var tracks: Variant = raw[context]
		if typeof(tracks) != TYPE_ARRAY:
			continue
		var paths: Array[String] = []
		for entry in tracks:
			if typeof(entry) == TYPE_STRING and not String(entry).is_empty():
				paths.append(String(entry))
		if not paths.is_empty():
			out[String(context)] = paths
	return out


func _coerce_sfx_map(raw: Variant) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for sound_id in raw.keys():
		var entry: Variant = raw[sound_id]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var paths: Array[String] = []
		for path_entry in entry.get("paths", []):
			if typeof(path_entry) == TYPE_STRING and not String(path_entry).is_empty():
				paths.append(String(path_entry))
		if paths.is_empty():
			continue
		out[String(sound_id)] = {
			"bus": String(entry.get("bus", "SFX")),
			"paths": paths,
			"loop": bool(entry.get("loop", false)),
			"min_interval_sec": maxf(0.0, float(entry.get("min_interval_sec", 0.0))),
			"max_overlap": maxi(1, int(entry.get("max_overlap", 8))),
		}
	return out


func has_music_context(context: String) -> bool:
	return _music.has(context)


func has_ambience_context(context: String) -> bool:
	return _ambience.has(context)


func has_sfx(sound_id: String) -> bool:
	return _sfx.has(sound_id)


func music_track_for_context(context: String, _track_index: int = 0) -> String:
	if not _music.has(context):
		return ""
	var tracks: Array = _music[context]
	if tracks.is_empty():
		return ""
	return String(tracks[0])


func ambience_track_for_context(context: String, _track_index: int = 0) -> String:
	if not _ambience.has(context):
		return ""
	var tracks: Array = _ambience[context]
	if tracks.is_empty():
		return ""
	return String(tracks[0])


func sfx_entry(sound_id: String) -> Dictionary:
	if not _sfx.has(sound_id):
		return {}
	return (_sfx[sound_id] as Dictionary).duplicate(true)


func sfx_variant_path(sound_id: String, rng: RandomNumberGenerator) -> String:
	var entry := sfx_entry(sound_id)
	var paths: Array = entry.get("paths", [])
	if paths.is_empty():
		return ""
	return String(paths[rng.randi_range(0, paths.size() - 1)])


func sfx_variant_count(sound_id: String) -> int:
	return sfx_entry(sound_id).get("paths", []).size()
