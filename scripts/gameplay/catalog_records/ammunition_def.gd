## Generated — do not edit. Run scripts/tools/generate_catalog_records.py.

class_name AmmunitionDef
extends RefCounted

var _present_keys: Dictionary = {}

var id: String = ""
var name: String = ""
var mass: float = 0
var cost: float = 0
var damage_packets: CatalogDamagePackets = CatalogDamagePackets.new()

static func from_dict(data: Dictionary) -> AmmunitionDef:
	var def := AmmunitionDef.new()
	for key in data.keys():
		def._present_keys[str(key)] = true
	def.id = str(data.get("id", ""))
	def.name = str(data.get("name", ""))
	def.mass = float(data.get("mass", 0))
	def.cost = float(data.get("cost", 0))
	def.damage_packets = CatalogDamagePackets.from_dict(data.get("damage_packets", {}))
	return def

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	out["id"] = id
	out["name"] = name
	out["mass"] = mass
	out["cost"] = cost
	out["damage_packets"] = damage_packets.to_dict()
	return out

static func allowed_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "mass", "cost", "damage_packets"])

static func required_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "mass", "cost", "damage_packets"])

func has_source_key(key: String) -> bool:
	return _present_keys.has(key)
