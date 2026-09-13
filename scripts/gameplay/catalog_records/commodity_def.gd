## Generated — do not edit. Run scripts/tools/generate_catalog_records.py.

class_name CommodityDef
extends RefCounted

var _present_keys: Dictionary = {}

var id: String = ""
var name: String = ""
var mass: float = 0
var base_price: float = 0
var description: String = ""

static func from_dict(data: Dictionary) -> CommodityDef:
	var def := CommodityDef.new()
	for key in data.keys():
		def._present_keys[str(key)] = true
	def.id = str(data.get("id", ""))
	def.name = str(data.get("name", ""))
	def.mass = float(data.get("mass", 0))
	def.base_price = float(data.get("base_price", 0))
	def.description = str(data.get("description", ""))
	return def

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	out["id"] = id
	out["name"] = name
	out["mass"] = mass
	out["base_price"] = base_price
	out["description"] = description
	return out

static func allowed_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "mass", "base_price", "description"])

static func required_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "mass", "base_price", "description"])

func has_source_key(key: String) -> bool:
	return _present_keys.has(key)
