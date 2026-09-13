## Generated — do not edit. Run scripts/tools/generate_catalog_records.py.

class_name ChassisDef
extends RefCounted

var _present_keys: Dictionary = {}

var id: String = ""
var name: String = ""
var maker: String = ""
var cost: float = 0.0
var mass: float = 0
var hits: float = 0
var mass_limit: float = 0
var volume: float = 0
var maneuver: String = ""
var hull_color: String = ""
var sprite: String = ""
var mounts: Dictionary = {}

static func from_dict(data: Dictionary) -> ChassisDef:
	var def := ChassisDef.new()
	for key in data.keys():
		def._present_keys[str(key)] = true
	def.id = str(data.get("id", ""))
	def.name = str(data.get("name", ""))
	def.maker = str(data.get("maker", ""))
	def.cost = float(data.get("cost", 0.0))
	def.mass = float(data.get("mass", 0))
	def.hits = float(data.get("hits", 0))
	def.mass_limit = float(data.get("mass_limit", 0))
	def.volume = float(data.get("volume", 0))
	def.maneuver = str(data.get("maneuver", ""))
	def.hull_color = str(data.get("hull_color", ""))
	def.sprite = str(data.get("sprite", ""))
	var raw_mounts: Variant = data.get("mounts", {})
	if typeof(raw_mounts) == TYPE_DICTIONARY:
		def.mounts = raw_mounts.duplicate()
	return def

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	out["id"] = id
	out["name"] = name
	out["maker"] = maker
	if _present_keys.has("cost") or cost != 0.0:
		out["cost"] = cost
	out["mass"] = mass
	out["hits"] = hits
	out["mass_limit"] = mass_limit
	out["volume"] = volume
	out["maneuver"] = maneuver
	if _present_keys.has("hull_color") or hull_color != "":
		out["hull_color"] = hull_color
	if _present_keys.has("sprite") or sprite != "":
		out["sprite"] = sprite
	out["mounts"] = mounts.duplicate()
	return out

static func allowed_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "maker", "cost", "mass", "hits", "mass_limit", "volume", "maneuver", "hull_color", "sprite", "mounts"])

static func required_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "maker", "mass", "hits", "mass_limit", "volume", "maneuver", "mounts"])

func has_source_key(key: String) -> bool:
	return _present_keys.has(key)
