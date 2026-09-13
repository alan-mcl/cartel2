## Generated — do not edit. Run scripts/tools/generate_catalog_records.py.

class_name SectorDef
extends RefCounted

var _present_keys: Dictionary = {}

var id: String = ""
var name: String = ""
var orbit_name: String = ""
var planet_name: String = ""
var star_system: String = ""
var classification: String = ""
var gravity: float = 1.0
var population_billions: float = 0.0
var ocean_coverage: float = 0.0
var climate: String = ""
var city_malls: Array = []
var play_bounds: float = 0
var objective: String = ""
var mappings: Array = []

static func from_dict(data: Dictionary) -> SectorDef:
	var def := SectorDef.new()
	for key in data.keys():
		def._present_keys[str(key)] = true
	def.id = str(data.get("id", ""))
	def.name = str(data.get("name", ""))
	def.orbit_name = str(data.get("orbit_name", ""))
	def.planet_name = str(data.get("planet_name", ""))
	def.star_system = str(data.get("star_system", ""))
	def.classification = str(data.get("classification", ""))
	def.gravity = float(data.get("gravity", 1.0))
	def.population_billions = float(data.get("population_billions", 0.0))
	def.ocean_coverage = float(data.get("ocean_coverage", 0.0))
	def.climate = str(data.get("climate", ""))
	def.city_malls = []
	var raw_city_malls: Variant = data.get("city_malls", [])
	if typeof(raw_city_malls) == TYPE_ARRAY:
		for item in raw_city_malls:
			def.city_malls.append(str(item))
	def.play_bounds = float(data.get("play_bounds", 0))
	def.objective = str(data.get("objective", ""))
	def.mappings = []
	var raw_mappings: Variant = data.get("mappings", [])
	if typeof(raw_mappings) == TYPE_ARRAY:
		def.mappings = raw_mappings.duplicate()
	return def

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	out["id"] = id
	out["name"] = name
	if _present_keys.has("orbit_name") or orbit_name != "":
		out["orbit_name"] = orbit_name
	if _present_keys.has("planet_name") or planet_name != "":
		out["planet_name"] = planet_name
	if _present_keys.has("star_system") or star_system != "":
		out["star_system"] = star_system
	if _present_keys.has("classification") or classification != "":
		out["classification"] = classification
	if _present_keys.has("gravity") or gravity != 1.0:
		out["gravity"] = gravity
	if _present_keys.has("population_billions") or population_billions != 0.0:
		out["population_billions"] = population_billions
	if _present_keys.has("ocean_coverage") or ocean_coverage != 0.0:
		out["ocean_coverage"] = ocean_coverage
	if _present_keys.has("climate") or climate != "":
		out["climate"] = climate
	if _present_keys.has("city_malls") or not city_malls.is_empty():
		out["city_malls"] = city_malls.duplicate()
	out["play_bounds"] = play_bounds
	if _present_keys.has("objective") or objective != "":
		out["objective"] = objective
	if _present_keys.has("mappings") or not mappings.is_empty():
		out["mappings"] = mappings.duplicate()
	return out

static func allowed_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "orbit_name", "planet_name", "star_system", "classification", "gravity", "population_billions", "ocean_coverage", "climate", "city_malls", "play_bounds", "objective", "mappings"])

static func required_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "play_bounds"])

func has_source_key(key: String) -> bool:
	return _present_keys.has(key)
