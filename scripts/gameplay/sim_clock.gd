class_name SimClock
extends RefCounted

## Advances [GameSession.gst_seconds] in real time or via unspace pulses.
## Does not notify subsystems — [Simulation] owns boundary dispatch.

var _pulse_timer: float = 0.0
var _pulse_interval: float = 1.0


static func gst_hour(gst_seconds: float) -> int:
	return int(floor(gst_seconds / float(GalacticCalendar.SECONDS_PER_HOUR)))


func reset_unspace_pulse() -> void:
	_pulse_timer = 0.0
	_pulse_interval = 0.0


func advance(
	session: GameSession,
	catalog: Catalog,
	delta: float,
	frozen: bool
) -> Dictionary:
	var result := {
		"advanced": false,
		"hour_crossed": false,
		"day_crossed": false,
		"previous_hour": 0,
		"previous_day": 0,
		"current_hour": 0,
		"current_day": 0,
	}
	if frozen or session == null or delta <= 0.0:
		return result

	result["previous_day"] = CommodityEconomy.gst_day(session.gst_seconds)
	result["previous_hour"] = gst_hour(session.gst_seconds)

	if session.in_unspace:
		_tick_unspace(session, catalog, delta)
	else:
		session.gst_seconds += delta

	result["current_day"] = CommodityEconomy.gst_day(session.gst_seconds)
	result["current_hour"] = gst_hour(session.gst_seconds)
	result["advanced"] = true
	result["day_crossed"] = result["current_day"] != result["previous_day"]
	result["hour_crossed"] = result["current_hour"] != result["previous_hour"]
	return result


func _tick_unspace(session: GameSession, catalog: Catalog, delta: float) -> void:
	var config := _get_unspace_gst_config(catalog, session.unspace_world_id)

	_pulse_timer -= delta
	var safety := 0
	while _pulse_timer <= 0.0 and safety < 32:
		safety += 1
		if _pulse_interval <= 0.0:
			_schedule_next_pulse(config)

		var stretch := gst_stretch_factor(config, randf())
		var gst_chunk := _pulse_interval * stretch
		session.gst_seconds += gst_chunk

		if randf() < gst_slip_chance(config):
			var slip_min := float(config.get("slip_min", 2.0))
			var slip_max := float(config.get("slip_max", 18.0))
			session.gst_seconds += randf_range(slip_min, slip_max)

		_schedule_next_pulse(config)


func _schedule_next_pulse(config: Dictionary) -> void:
	_pulse_interval = gst_pulse_interval(config, randf())
	_pulse_timer += _pulse_interval


static func gst_stretch_factor(config: Dictionary, rand_unit: float) -> float:
	var stretch_min := float(config.get("stretch_min", 0.35))
	var stretch_max := float(config.get("stretch_max", 2.8))
	return lerpf(stretch_min, stretch_max, rand_unit)


static func gst_slip_chance(config: Dictionary) -> float:
	return clampf(float(config.get("slip_chance", 0.12)), 0.0, 0.75)


static func gst_pulse_interval(config: Dictionary, rand_unit: float) -> float:
	var pulse_min := float(config.get("pulse_min", 0.35))
	var pulse_max := float(config.get("pulse_max", 2.4))
	return lerpf(pulse_min, pulse_max, rand_unit)


func _get_unspace_gst_config(catalog: Catalog, unspace_world_id: String) -> Dictionary:
	if catalog == null or unspace_world_id.is_empty():
		return {}

	var unspace := catalog.get_unspace(unspace_world_id)
	var gst: Variant = unspace.get("gst", {})
	if typeof(gst) != TYPE_DICTIONARY:
		return {}
	return gst
