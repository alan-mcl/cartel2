## Generated — do not edit. Run scripts/tools/generate_catalog_records.py.

class_name ShipDef
extends RefCounted

var _present_keys: Dictionary = {}

var id: String = ""
var name: String = ""
var maker: String = ""
var chassis: String = ""
var modules: Array = []

static func from_dict(data: Dictionary) -> ShipDef:
	var def := ShipDef.new()
	for key in data.keys():
		def._present_keys[str(key)] = true
	def.id = str(data.get("id", ""))
	def.name = str(data.get("name", ""))
	def.maker = str(data.get("maker", ""))
	def.chassis = str(data.get("chassis", ""))
	def.modules = []
	var raw_modules: Variant = data.get("modules", [])
	if typeof(raw_modules) == TYPE_ARRAY:
		for item in raw_modules:
			def.modules.append(str(item))
	return def

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	out["id"] = id
	out["name"] = name
	out["maker"] = maker
	out["chassis"] = chassis
	out["modules"] = modules.duplicate()
	return out

static func allowed_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "maker", "chassis", "modules"])

static func required_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "maker", "chassis", "modules"])
