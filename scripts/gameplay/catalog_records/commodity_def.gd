## Generated — do not edit. Run scripts/tools/generate_catalog_records.py.

class_name CommodityDef
extends RefCounted

var _present_keys: Dictionary = {}

var id: String = ""
var name: String = ""
var mass: float = 0
var base_price: float = 0
var description: String = ""
var requires_capabilities: Array = []

static func from_dict(data: Dictionary) -> CommodityDef:
	var def := CommodityDef.new()
	for key in data.keys():
		def._present_keys[str(key)] = true
	def.id = str(data.get("id", ""))
	def.name = str(data.get("name", ""))
	def.mass = float(data.get("mass", 0))
	def.base_price = float(data.get("base_price", 0))
	def.description = str(data.get("description", ""))
	def.requires_capabilities = []
	var raw_requires_capabilities: Variant = data.get("requires_capabilities", [])
	if typeof(raw_requires_capabilities) == TYPE_ARRAY:
		for item in raw_requires_capabilities:
			def.requires_capabilities.append(str(item))
	return def

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	out["id"] = id
	out["name"] = name
	out["mass"] = mass
	out["base_price"] = base_price
	out["description"] = description
	if _present_keys.has("requires_capabilities") or not requires_capabilities.is_empty():
		out["requires_capabilities"] = requires_capabilities.duplicate()
	return out

static func allowed_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "mass", "base_price", "description", "requires_capabilities"])

static func required_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "mass", "base_price", "description"])

func has_source_key(key: String) -> bool:
	return _present_keys.has(key)
