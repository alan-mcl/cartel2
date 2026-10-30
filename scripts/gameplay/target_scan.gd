class_name TargetScan
extends RefCounted

## Read-only active-scan report for the current target lock.


static func build(
	session: GameSession,
	catalog: Catalog,
	contact: Dictionary,
	observer_pos: Vector2,
	beacon_destination: String = ""
) -> Dictionary:
	if contact.is_empty() or catalog == null or session == null:
		return _empty_snapshot()

	var target_pos: Vector2 = contact.get("position", Vector2.ZERO)
	var velocity: Vector2 = contact.get("velocity", Vector2.ZERO)
	var kind := str(contact.get("contact_kind", ""))
	var title := _title_for_contact(contact)
	var range_text := (
		_format_star_range_au(session, catalog, contact)
		if kind == "star"
		else _format_distance(observer_pos.distance_to(target_pos))
	)
	var rows: Array = [
		_row("Kind", _kind_display(kind, contact)),
		_row("Range", range_text),
		_row("Speed", _format_speed(velocity.length())),
		_row("Heading", _format_heading(velocity)),
	]
	rows.append_array(_detail_rows(session, catalog, contact, kind, beacon_destination))
	return {"title": title, "rows": rows}


static func _empty_snapshot() -> Dictionary:
	return {"title": "Target", "rows": []}


static func _title_for_contact(contact: Dictionary) -> String:
	var kind := str(contact.get("contact_kind", ""))
	if kind == "star":
		var star_name := str(contact.get("star_name", contact.get("name", ""))).strip_edges()
		if not star_name.is_empty():
			return star_name
	if kind == "traffic_npc":
		var ship_name := str(contact.get("ship_name", "")).strip_edges()
		if not ship_name.is_empty():
			return ship_name
	var name := str(contact.get("name", "")).strip_edges()
	if not name.is_empty():
		return name.get_slice("\n", 0)
	match kind:
		"orbital":
			return "Unnamed orbital"
		"debris":
			return "Debris"
		_:
			return "Target"


static func _detail_rows(
	session: GameSession,
	catalog: Catalog,
	contact: Dictionary,
	kind: String,
	beacon_destination: String
) -> Array:
	match kind:
		"traffic_npc":
			return _ship_detail_rows(contact)
		"landmark":
			return _landmark_detail_rows(session, catalog, contact, beacon_destination)
		"star":
			return _star_detail_rows(catalog, contact)
		"orbital":
			return _orbital_detail_rows(contact)
		"debris":
			return _debris_detail_rows(contact)
		"ascidian", _:
			return []


static func _ship_detail_rows(contact: Dictionary) -> Array:
	var rows: Array = []
	var chassis_name := str(contact.get("chassis_name", "")).strip_edges()
	if not chassis_name.is_empty():
		rows.append(_row("Chassis", chassis_name))
	var mass := float(contact.get("ship_mass", 0.0))
	if mass > 0.0:
		rows.append(_row("Mass", "%.1f t" % mass))

	var signature: Variant = contact.get("live_signature", {})
	if typeof(signature) == TYPE_DICTIONARY:
		var sig: Dictionary = signature
		rows.append(_row("Thermal", "%.1f" % float(sig.get("thermal", 0.0))))
		rows.append(_row("Gravitational", "%.1f" % float(sig.get("gravitational", 0.0))))
		rows.append(_row("EM", "%.1f" % float(sig.get("electromagnetic", 0.0))))
		rows.append(_row("Computational", "%.1f" % float(sig.get("computational", 0.0))))

	var callsign := str(contact.get("callsign", "")).strip_edges()
	if not callsign.is_empty():
		rows.append(_row("Callsign", callsign))
	var affiliation := str(contact.get("affiliation", "")).strip_edges()
	if not affiliation.is_empty():
		rows.append(_row("Affiliation", affiliation))
	if bool(contact.get("broadcasting", false)):
		var registration := str(contact.get("registration", "")).strip_edges()
		if not registration.is_empty():
			rows.append(_row("Registration", registration))
	return rows


static func _landmark_detail_rows(
	session: GameSession,
	catalog: Catalog,
	contact: Dictionary,
	beacon_destination: String
) -> Array:
	var rows: Array = []
	var role := str(contact.get("landmark_role", ""))
	if role == "planet":
		var diameter := float(contact.get("planet_diameter_m", 0.0))
		if diameter > 0.0:
			rows.append(_row("Diameter", "%.0f m" % diameter))
		rows.append_array(_planet_setting_rows(session, catalog))
		return rows

	var interactable_id := str(contact.get("interactable_id", ""))
	if not interactable_id.is_empty():
		var data := catalog.get_interactable(interactable_id)
		if not data.is_empty():
			var def := InteractableDef.from_dict(data)
			if not def.title.is_empty():
				rows.append(_row("Facility", def.title))
			if not def.inspect_text.is_empty():
				rows.append(_row("Scan", def.inspect_text))

	if bool(contact.get("translation_beacon", false)) and not beacon_destination.is_empty():
		var dest_label := TranslationNav.destination_display_label(catalog, beacon_destination)
		if not dest_label.is_empty():
			rows.append(_row("Tuned destination", dest_label))
	return rows


static func _planet_setting_rows(session: GameSession, catalog: Catalog) -> Array:
	var rows: Array = []
	if session == null or catalog == null:
		return rows
	var sector_id := str(session.world.sector_id)
	if sector_id.is_empty() or VolatileTranslation.is_volatile_sector_id(sector_id):
		return rows
	var sector := catalog.get_sector_def(sector_id)
	if sector == null:
		return rows

	var classification := sector.classification.strip_edges()
	if not classification.is_empty():
		rows.append(_row("Classification", classification))
	var gravity := sector.gravity
	if gravity > 0.0:
		rows.append(_row("Gravity", "%.2f G" % gravity))
	if sector.has_source_key("population_billions"):
		rows.append(_row("Population", _format_population_billions(sector.population_billions)))
	if sector.has_source_key("ocean_coverage"):
		rows.append(_row("Ocean coverage", "%.0f%%" % (sector.ocean_coverage * 100.0)))
	var climate := sector.climate.strip_edges()
	if not climate.is_empty():
		rows.append(_row("Climate", climate))
	var system := sector.star_system.strip_edges()
	if not system.is_empty():
		rows.append(_row("System", system))
	return rows


static func _star_detail_rows(catalog: Catalog, contact: Dictionary) -> Array:
	var rows: Array = []
	var temp_k := float(contact.get("star_temperature_k", 0.0))
	if temp_k > 0.0:
		rows.append(_row("Temperature", "%.0f K" % temp_k))
	var lum := float(contact.get("star_luminosity", 0.0))
	if lum > 0.0:
		rows.append(_row("Luminosity", "%.3f" % lum))

	var star_name := str(contact.get("star_name", contact.get("name", ""))).strip_edges()
	var facts := catalog.get_star(star_name)
	if facts.is_empty():
		return rows

	var spectral := str(facts.get("spectral_class", "")).strip_edges()
	if not spectral.is_empty():
		rows.append(_row("Spectral class", spectral))
	if facts.has("mass_solar"):
		rows.append(_row("Mass", "%.2f M☉" % float(facts.get("mass_solar", 0.0))))
	if facts.has("radius_solar"):
		rows.append(_row("Radius", "%.2f R☉" % float(facts.get("radius_solar", 0.0))))
	var description := str(facts.get("description", "")).strip_edges()
	if not description.is_empty():
		rows.append(_row("Description", description))
	return rows


static func _orbital_detail_rows(contact: Dictionary) -> Array:
	var sprite_path := str(contact.get("orbital_sprite", contact.get("sprite_path", "")))
	var structure := _orbital_structure_label(sprite_path)
	if structure.is_empty():
		return []
	return [_row("Structure", structure)]


static func _debris_detail_rows(contact: Dictionary) -> Array:
	var ratio := float(contact.get("debris_health_ratio", 1.0))
	return [_row("Integrity", "%.0f%%" % (ratio * 100.0))]


static func _format_population_billions(value: float) -> String:
	if value >= 10.0:
		return "%.0f billion" % value
	if value >= 1.0:
		return "%.1f billion" % value
	if value > 0.0:
		return "%.0f million" % (value * 1000.0)
	return "0"


static func _orbital_structure_label(sprite_path: String) -> String:
	if sprite_path.is_empty():
		return ""
	var stem := sprite_path.get_file().get_basename()
	return stem.replace("_", " ").capitalize()


static func _kind_display(kind: String, contact: Dictionary) -> String:
	if kind == "landmark":
		var role := str(contact.get("landmark_role", ""))
		match role:
			"planet":
				return "Planet"
			"habitat":
				return "Habitat"
			"translation_beacon":
				return "Translation beacon"
			"jump_gate":
				return "Jump gate"
			"parent_planet":
				var type_label := str(contact.get("parent_type_label", "")).strip_edges()
				if not type_label.is_empty():
					return type_label
				return "Parent planet"
			_:
				return "Landmark"
	match kind:
		"traffic_npc":
			return "Ship"
		"star":
			return "Star"
		"orbital":
			return "Orbital"
		"debris":
			return "Debris"
		"ascidian":
			return "Ascidian"
		_:
			return kind.capitalize() if not kind.is_empty() else "Unknown"


static func _row(label_text: String, value_text: String) -> Dictionary:
	return {"label": label_text, "value": value_text}


static func _format_star_range_au(session: GameSession, catalog: Catalog, contact: Dictionary) -> String:
	if session == null or catalog == null:
		return "—"
	var sector_id := str(session.world.sector_id)
	if VolatileTranslation.is_volatile_sector_id(sector_id):
		var record := VolatileTranslation.find_by_sector_id(session, sector_id)
		var seed_key := str(record.get("id", VolatileTranslation.record_id_from_sector(sector_id)))
		if seed_key.is_empty():
			seed_key = sector_id
		var rng := RandomNumberGenerator.new()
		rng.seed = absi(seed_key.hash())
		var au := 1.0 + rng.randf() * 19.0
		return "%.3f AU" % au
	var sector := catalog.get_sector_def(sector_id)
	var base_au := 0.0 if sector == null else sector.star_distance_au
	if base_au <= 0.0:
		base_au = 1.0
	var jitter := _star_range_jitter_au(sector_id)
	return "%.3f AU" % (base_au + jitter)


static func _star_range_jitter_au(sector_id: String) -> float:
	if sector_id.is_empty():
		return 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(sector_id.hash())
	return rng.randf_range(-0.005, 0.005)


static func _format_distance(metres: float) -> String:
	if metres >= 1000.0:
		return "%.1f km" % (metres / 1000.0)
	return "%.0f m" % metres


static func _format_speed(metres_per_sec: float) -> String:
	if metres_per_sec < 0.5:
		return "0 m/s"
	return "%.0f m/s" % metres_per_sec


static func _format_heading(velocity: Vector2) -> String:
	if velocity.length_squared() < 0.25:
		return "-"
	return "%.0f°" % wrapf(rad_to_deg(velocity.angle()), 0.0, 360.0)
