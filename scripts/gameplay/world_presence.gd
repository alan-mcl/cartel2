class_name WorldPresence
extends RefCounted

var sector_id: String = "proxima"
var location_name: String = "Proxima near orbit"
var docked: bool = false
var habitat_id: String = ""
var building_id: String = ""
var in_unspace: bool = false
var unspace_n: int = 0
var unspace_world_id: String = ""
var unspace_solution: int = 0
var translation_stability: float = -1.0
var pending_destination_id: String = ""
var gst_seconds: float = 0.0
## Per-save RNG salt for daily procedural content (e.g. passenger charter boards).
var run_seed: int = 0
var orbital_phase_by_sector: Dictionary = {}
var market_quotes: Dictionary = {}
var market_quotes_day: int = -1
var route_friction_delta: Dictionary = {}


func advance_gst(seconds: float) -> void:
	if seconds <= 0.0:
		return
	gst_seconds += seconds


func get_orbital_phase(sector_key: String) -> float:
	return float(orbital_phase_by_sector.get(sector_key, 0.0))


func set_orbital_phase(sector_key: String, phase: float) -> void:
	orbital_phase_by_sector[sector_key] = phase


func advance_orbital_phase(sector_key: String, period_seconds: float, delta: float) -> void:
	if period_seconds <= 0.0 or delta <= 0.0:
		return
	var phase := get_orbital_phase(sector_key)
	phase = fposmod(phase + TAU / period_seconds * delta, TAU)
	set_orbital_phase(sector_key, phase)


func get_unspace_spawn(catalog: Catalog) -> Vector2:
	var unspace := catalog.get_unspace(unspace_world_id)
	if unspace.is_empty():
		return Vector2.ZERO

	var spawn: Dictionary = unspace.get("spawn", {})
	return Vector2(float(spawn.get("x", 0.0)), float(spawn.get("y", 0.0)))


func get_sector_spawn(_catalog: Catalog) -> Vector2:
	return Vector2.ZERO


func get_spawn_position(catalog: Catalog) -> Vector2:
	if in_unspace:
		return get_unspace_spawn(catalog)
	return get_sector_spawn(catalog)


func get_market_sector_id(catalog: Catalog) -> String:
	if not habitat_id.is_empty():
		var habitat_sector := catalog.get_habitat_sector_id(habitat_id)
		if not habitat_sector.is_empty():
			return habitat_sector
	return sector_id


func get_market_quote_day_label() -> String:
	return GalacticCalendar.format_date_only(gst_seconds)


func get_gst_timestamp() -> String:
	return GalacticCalendar.format_timestamp(gst_seconds)


func to_session_dict() -> Dictionary:
	return {
		"sector_id": sector_id,
		"location_name": location_name,
		"docked": docked,
		"habitat_id": habitat_id,
		"building_id": building_id,
		"in_unspace": in_unspace,
		"unspace_n": unspace_n,
		"unspace_world_id": unspace_world_id,
		"unspace_solution": unspace_solution,
		"translation_stability": translation_stability,
		"pending_destination_id": pending_destination_id,
		"orbital_phase_by_sector": orbital_phase_by_sector.duplicate(),
		"gst_seconds": gst_seconds,
		"run_seed": run_seed,
		"route_friction_delta": route_friction_delta.duplicate(),
	}


func load_session_dict(data: Dictionary, default_gst_seconds: float) -> void:
	sector_id = str(data.get("sector_id", "proxima"))
	location_name = str(data.get("location_name", ""))
	docked = bool(data.get("docked", false))
	habitat_id = str(data.get("habitat_id", ""))
	building_id = str(data.get("building_id", ""))
	in_unspace = bool(data.get("in_unspace", false))
	unspace_n = int(data.get("unspace_n", 0))
	unspace_world_id = str(data.get("unspace_world_id", ""))
	unspace_solution = int(data.get("unspace_solution", 0))
	translation_stability = float(data.get("translation_stability", -1.0))
	pending_destination_id = str(data.get("pending_destination_id", ""))
	orbital_phase_by_sector = _float_dict_from_variant(data.get("orbital_phase_by_sector", {}))
	if data.has("gst_seconds"):
		gst_seconds = float(data.get("gst_seconds", 0.0))
	else:
		gst_seconds = default_gst_seconds
	run_seed = int(data.get("run_seed", 0))
	route_friction_delta = _float_dict_from_variant(data.get("route_friction_delta", {}))
	market_quotes.clear()
	market_quotes_day = -1


static func _float_dict_from_variant(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for key in value.keys():
		result[str(key)] = float(value[key])
	return result
