## Generated — do not edit. Run scripts/tools/generate_catalog_records.py.

class_name CatalogSignature
extends RefCounted

var thermal: float = 0.0
var gravitational: float = 0.0
var electromagnetic: float = 0.0
var computational: float = 0.0

static func from_dict(data: Dictionary) -> CatalogSignature:
	var def := CatalogSignature.new()
	def.thermal = float(data.get("thermal", 0.0))
	def.gravitational = float(data.get("gravitational", 0.0))
	def.electromagnetic = float(data.get("electromagnetic", 0.0))
	def.computational = float(data.get("computational", 0.0))
	return def

static func is_empty(value: CatalogSignature) -> bool:
	return value.thermal == 0.0 and value.gravitational == 0.0 and value.electromagnetic == 0.0 and value.computational == 0.0

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	out["thermal"] = thermal
	out["gravitational"] = gravitational
	out["electromagnetic"] = electromagnetic
	out["computational"] = computational
	return out
