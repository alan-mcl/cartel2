class_name Simulation
extends RefCounted

## Central gameplay tick owner: GST advance plus registered subsystems.

var _clock := SimClock.new()
var _subsystems: Dictionary = {}


func _init() -> void:
	register(EconomySubsystem.new())
	register(MissionSubsystem.new())


func register(subsystem: SimSubsystem) -> bool:
	if subsystem == null:
		push_error("Simulation.register: subsystem is null.")
		return false
	var subsystem_id := str(subsystem.id).strip_edges()
	if subsystem_id.is_empty():
		push_error("Simulation.register: subsystem id is empty.")
		return false
	if _subsystems.has(subsystem_id):
		push_error("Simulation.register: duplicate subsystem id '%s'." % subsystem_id)
		return false
	_subsystems[subsystem_id] = subsystem
	return true


func has_subsystem(subsystem_id: String) -> bool:
	return _subsystems.has(subsystem_id)


func get_subsystem(subsystem_id: String) -> SimSubsystem:
	return _subsystems.get(subsystem_id, null)


func step(session: GameSession, catalog: Catalog, delta: float, frozen: bool) -> void:
	if frozen or session == null or delta <= 0.0:
		return

	var advance_result := _clock.advance(session, catalog, delta, false)
	if not bool(advance_result.get("advanced", false)):
		return

	session.advance_orbital_phase(catalog, delta)

	for subsystem_variant in _subsystems.values():
		var subsystem: SimSubsystem = subsystem_variant
		subsystem.on_tick(session, catalog, delta)

	if bool(advance_result.get("hour_crossed", false)):
		var hour: int = int(advance_result.get("current_hour", 0))
		for subsystem_variant in _subsystems.values():
			var subsystem: SimSubsystem = subsystem_variant
			subsystem.on_hour(session, catalog, hour)

	if bool(advance_result.get("day_crossed", false)):
		var day: int = int(advance_result.get("current_day", 0))
		for subsystem_variant in _subsystems.values():
			var subsystem: SimSubsystem = subsystem_variant
			subsystem.on_day(session, catalog, day)


func apply_mapping_lump(
	session: GameSession,
	mapping: Dictionary,
	field: String,
	catalog: Catalog = null
) -> float:
	if session == null or mapping.is_empty():
		return 0.0

	var base_seconds := float(mapping.get(field, 0.0))
	if base_seconds <= 0.0:
		return 0.0

	var jitter := clampf(float(mapping.get("time_jitter", 0.0)), 0.0, 0.5)
	var applied := base_seconds
	if jitter > 0.0:
		applied *= 1.0 + randf_range(-jitter, jitter)

	var previous_day := CommodityEconomy.gst_day(session.gst_seconds)
	var previous_hour := SimClock.gst_hour(session.gst_seconds)
	session.advance_gst(applied)
	var current_day := CommodityEconomy.gst_day(session.gst_seconds)
	var current_hour := SimClock.gst_hour(session.gst_seconds)

	if catalog == null:
		return applied

	for subsystem_variant in _subsystems.values():
		var subsystem: SimSubsystem = subsystem_variant
		if current_hour != previous_hour:
			subsystem.on_hour(session, catalog, current_hour)
		if current_day != previous_day:
			subsystem.on_day(session, catalog, current_day)

	return applied


func reset_unspace_pulse() -> void:
	_clock.reset_unspace_pulse()


func dispatch_event(session: GameSession, catalog: Catalog, evt: Dictionary) -> void:
	if evt.is_empty() or not evt.has("type"):
		return
	for subsystem_variant in _subsystems.values():
		var subsystem: SimSubsystem = subsystem_variant
		subsystem.on_event(session, catalog, evt)


func collect_save() -> Dictionary:
	var blob := {}
	for subsystem_id in _subsystems.keys():
		var subsystem: SimSubsystem = _subsystems[subsystem_id]
		blob[subsystem_id] = {
			"version": subsystem.save_version,
			"data": subsystem.to_dict(),
		}
	return blob


func apply_save(blob: Dictionary) -> void:
	if typeof(blob) != TYPE_DICTIONARY:
		blob = {}

	for subsystem_id in _subsystems.keys():
		var subsystem: SimSubsystem = _subsystems[subsystem_id]
		var section: Variant = blob.get(subsystem_id, null)
		if typeof(section) != TYPE_DICTIONARY:
			subsystem.from_dict({})
			continue

		var section_dict: Dictionary = section
		var data: Variant = section_dict.get("data", {})
		if typeof(data) != TYPE_DICTIONARY:
			data = {}

		var stored_version := int(section_dict.get("version", subsystem.save_version))
		var payload: Dictionary = data
		if stored_version != subsystem.save_version:
			payload = subsystem.migrate(payload, stored_version)
		subsystem.from_dict(payload)


func reset_save() -> void:
	apply_save({})
