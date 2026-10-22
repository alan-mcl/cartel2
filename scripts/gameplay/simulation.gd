class_name Simulation
extends RefCounted

## Central gameplay tick owner: GST advance plus registered subsystems.

var _clock := SimClock.new()
var _subsystems: Dictionary = {}
var _event_session: GameSession
var _event_catalog: Catalog
var _event_listener: Callable = Callable()


func _init() -> void:
	register(EconomySubsystem.new())
	register(MissionSubsystem.new())
	register(MessageSubsystem.new())


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

	if not session.player.sandbox:
		session.career.record_played_seconds(delta)
		if not session.docked:
			var gst_delta := float(advance_result.get("gst_delta", 0.0))
			session.career.record_flight_gst(gst_delta, session.in_unspace)

	session.advance_orbital_phase(catalog, delta)
	VolatileTranslation.sweep(session)

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

	VolatileTranslation.sweep(session)

	for subsystem_variant in _subsystems.values():
		var subsystem: SimSubsystem = subsystem_variant
		if current_hour != previous_hour:
			subsystem.on_hour(session, catalog, current_hour)
		if current_day != previous_day:
			subsystem.on_day(session, catalog, current_day)

	return applied


func reset_unspace_pulse() -> void:
	_clock.reset_unspace_pulse()


## Subscribe this simulation to a session bus. Replaces any previous attachment.
func attach_events(session: GameSession, catalog: Catalog) -> void:
	detach_events()
	if session == null or catalog == null:
		return
	_event_session = session
	_event_catalog = catalog
	_event_listener = _on_session_event
	session.events.subscribe_all(_event_listener)


## Drop the session bus subscription. A different session is left untouched.
func detach_events(session: GameSession = null) -> void:
	if _event_session == null:
		return
	if session != null and session != _event_session:
		return
	if _event_listener.is_valid():
		_event_session.events.unsubscribe_all(_event_listener)
	_event_session = null
	_event_catalog = null
	_event_listener = Callable()


func _on_session_event(evt: Dictionary) -> void:
	if _event_session == null or _event_catalog == null:
		return
	dispatch_event(_event_session, _event_catalog, evt)


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
