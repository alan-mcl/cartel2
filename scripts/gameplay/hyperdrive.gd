class_name Hyperdrive
extends RefCounted


static func fitted_module(assembled: AssembledShip) -> ModuleDef:
	if assembled == null:
		return null
	for entry_variant in assembled.installed_modules:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var module_def: ModuleDef = entry_variant.get("data", null)
		if module_def != null and module_def.category == "hyperdrive":
			return module_def
	return null


static func min_spool_distance(catalog: Catalog, sector_id: String) -> float:
	if catalog == null or sector_id.is_empty():
		return 0.0
	var layout: Dictionary = catalog.get_world(sector_id)
	var beacon: Variant = layout.get("translation_beacon", {})
	if typeof(beacon) == TYPE_DICTIONARY and beacon.has("radius"):
		return float(beacon.get("radius", 0.0))
	var gate: Variant = layout.get("jump_gate", {})
	if typeof(gate) == TYPE_DICTIONARY and gate.has("radius"):
		return float(gate.get("radius", 0.0))
	var planet: Dictionary = layout.get("planet", {})
	var diameter := float(planet.get("diameter", 2000.0))
	return diameter * 0.5 * 5.4


static func spool_block(
	catalog: Catalog,
	session: GameSession,
	assembled: AssembledShip,
	owned: OwnedShip,
	position: Vector2,
	thrusting: bool,
	boosting: bool = false
) -> Dictionary:
	var module_def := fitted_module(assembled)
	if module_def == null:
		return {"ok": false, "message": "No hyperdrive fitted.", "title": ""}

	if session == null:
		return {"ok": false, "message": "Hyperdrive unavailable.", "title": ""}
	if session.docked:
		return {"ok": false, "message": "Undock before spooling the hyperdrive.", "title": ""}
	if session.in_unspace:
		return {"ok": false, "message": "Hyperdrive spool is unavailable in Unspace.", "title": ""}
	if VolatileTranslation.is_volatile_sector_id(session.sector_id):
		return {
			"ok": false,
			"message": "Use the return gate from this survey site.",
			"title": "",
		}

	var min_dist := min_spool_distance(catalog, session.sector_id)
	if position.length() < min_dist:
		return {
			"ok": false,
			"message": "Move beyond the gravity well before spooling the hyperdrive.",
			"title": "",
		}

	var occupant_count := 1

	var inputs := {
		"thrust": thrusting,
		"boost": boosting,
		"in_flight": true,
		"fire": false,
		"active_weapon_slot": "",
		"hyperdrive_spool": true,
	}
	var state := ShipOperations.tick(
		catalog,
		assembled,
		owned,
		0.0,
		inputs,
		occupant_count
	)

	var hd_requested := float(state.power_requested_by_category.get("hyperdrive", 0.0))
	var hd_allocated := float(state.power_allocated_by_category.get("hyperdrive", 0.0))
	if hd_requested > 0.0 and hd_allocated + 0.001 < hd_requested:
		return {
			"ok": false,
			"message": "Insufficient power to spool the hyperdrive.",
			"title": "",
		}
	if state.compute_demand > state.compute_capacity + 0.001:
		return {
			"ok": false,
			"message": "Insufficient compute to spool the hyperdrive.",
			"title": "",
		}

	return {"ok": true, "message": "", "title": module_def.name}
