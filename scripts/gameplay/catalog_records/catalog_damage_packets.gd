## Generated — do not edit. Run scripts/tools/generate_catalog_records.py.

class_name CatalogDamagePackets
extends RefCounted

var kinetic: float = 0.0
var energy: float = 0.0
var concussive: float = 0.0
var cyber: float = 0.0

static func from_dict(data: Dictionary) -> CatalogDamagePackets:
	var def := CatalogDamagePackets.new()
	def.kinetic = float(data.get("kinetic", 0.0))
	def.energy = float(data.get("energy", 0.0))
	def.concussive = float(data.get("concussive", 0.0))
	def.cyber = float(data.get("cyber", 0.0))
	return def

static func is_empty(value: CatalogDamagePackets) -> bool:
	return value.kinetic == 0.0 and value.energy == 0.0 and value.concussive == 0.0 and value.cyber == 0.0

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	out["kinetic"] = kinetic
	out["energy"] = energy
	out["concussive"] = concussive
	out["cyber"] = cyber
	return out
