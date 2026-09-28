## Generated — do not edit. Run scripts/tools/generate_catalog_records.py.

class_name CatalogNeighborhood
extends RefCounted

var magnetic_surface: float = 1.0
var magnetic_fluctuation: float = 0.0
var radiant: float = 1.0
var radiant_fluctuation: float = 0.0
var charged_particle: float = 1.0
var charged_particle_fluctuation: float = 0.0

static func from_dict(data: Dictionary) -> CatalogNeighborhood:
	var def := CatalogNeighborhood.new()
	def.magnetic_surface = float(data.get("magnetic_surface", 1.0))
	def.magnetic_fluctuation = float(data.get("magnetic_fluctuation", 0.0))
	def.radiant = float(data.get("radiant", 1.0))
	def.radiant_fluctuation = float(data.get("radiant_fluctuation", 0.0))
	def.charged_particle = float(data.get("charged_particle", 1.0))
	def.charged_particle_fluctuation = float(data.get("charged_particle_fluctuation", 0.0))
	return def

static func is_empty(value: CatalogNeighborhood) -> bool:
	return value.magnetic_surface == 1.0 and value.magnetic_fluctuation == 0.0 and value.radiant == 1.0 and value.radiant_fluctuation == 0.0 and value.charged_particle == 1.0 and value.charged_particle_fluctuation == 0.0

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	out["magnetic_surface"] = magnetic_surface
	out["magnetic_fluctuation"] = magnetic_fluctuation
	out["radiant"] = radiant
	out["radiant_fluctuation"] = radiant_fluctuation
	out["charged_particle"] = charged_particle
	out["charged_particle_fluctuation"] = charged_particle_fluctuation
	return out
