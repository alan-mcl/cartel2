## Generated - do not edit. Run scripts/tools/generate_catalog_records.py.

class_name FuelDef
extends RefCounted

var _present_keys: Dictionary = {}

var id: String = ""
var name: String = ""
var price_min: float = 0
var price_max: float = 0
var tank_scale: float = 1

static func from_dict(data: Dictionary) -> FuelDef:
	var def := FuelDef.new()
	for key in data.keys():
		def._present_keys[str(key)] = true
	def.id = str(data.get("id", ""))
	def.name = str(data.get("name", ""))
	def.price_min = float(data.get("price_min", 0))
	def.price_max = float(data.get("price_max", 0))
	def.tank_scale = float(data.get("tank_scale", 1))
	return def

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	out["id"] = id
	out["name"] = name
	out["price_min"] = price_min
	out["price_max"] = price_max
	if _present_keys.has("tank_scale") or tank_scale != 1:
		out["tank_scale"] = tank_scale
	return out

static func allowed_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "price_min", "price_max", "tank_scale"])

static func required_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "price_min", "price_max"])

func has_source_key(key: String) -> bool:
	return _present_keys.has(key)
