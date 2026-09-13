## Generated — do not edit. Run scripts/tools/generate_catalog_records.py.

class_name UnspaceDef
extends RefCounted

var _present_keys: Dictionary = {}

var id: String = ""
var n: int = 0
var name: String = ""
var orbit_name: String = ""
var play_bounds: float = 0
var objective: String = ""
var spawn: Dictionary = {}
var gst: Dictionary = {}
var field: Dictionary = {}

static func from_dict(data: Dictionary) -> UnspaceDef:
	var def := UnspaceDef.new()
	for key in data.keys():
		def._present_keys[str(key)] = true
	def.id = str(data.get("id", ""))
	def.n = int(data.get("n", 0))
	def.name = str(data.get("name", ""))
	def.orbit_name = str(data.get("orbit_name", ""))
	def.play_bounds = float(data.get("play_bounds", 0))
	def.objective = str(data.get("objective", ""))
	var raw_spawn: Variant = data.get("spawn", {})
	if typeof(raw_spawn) == TYPE_DICTIONARY:
		def.spawn = raw_spawn.duplicate()
	var raw_gst: Variant = data.get("gst", {})
	if typeof(raw_gst) == TYPE_DICTIONARY:
		def.gst = raw_gst.duplicate()
	var raw_field: Variant = data.get("field", {})
	if typeof(raw_field) == TYPE_DICTIONARY:
		def.field = raw_field.duplicate()
	return def

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	out["id"] = id
	out["n"] = n
	out["name"] = name
	if _present_keys.has("orbit_name") or orbit_name != "":
		out["orbit_name"] = orbit_name
	out["play_bounds"] = play_bounds
	if _present_keys.has("objective") or objective != "":
		out["objective"] = objective
	out["spawn"] = spawn.duplicate()
	out["gst"] = gst.duplicate()
	out["field"] = field.duplicate()
	return out

static func allowed_keys() -> PackedStringArray:
	return PackedStringArray(["id", "n", "name", "orbit_name", "play_bounds", "objective", "spawn", "gst", "field"])

static func required_keys() -> PackedStringArray:
	return PackedStringArray(["id", "n", "name", "play_bounds", "spawn", "gst", "field"])

func has_source_key(key: String) -> bool:
	return _present_keys.has(key)
