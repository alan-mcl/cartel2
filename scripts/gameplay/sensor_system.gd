class_name SensorSystem
extends RefCounted

const CHANNELS := ["thermal", "gravitational", "electromagnetic", "computational"]
const SIGNATURE_SCALE := 100.0
const MAX_CHANNEL_RANGE_MULT := 1.5
const HULL_GRAV_PER_TONNE := 0.08


static func empty_signature() -> Dictionary:
	return {
		"thermal": 0.0,
		"gravitational": 0.0,
		"electromagnetic": 0.0,
		"computational": 0.0,
	}


static func module_signature(module_def: Dictionary) -> Dictionary:
	if typeof(module_def) != TYPE_DICTIONARY or module_def.is_empty():
		return empty_signature()

	var raw: Variant = module_def.get("signature", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return empty_signature()

	var result := empty_signature()
	for channel in CHANNELS:
		result[channel] = maxf(0.0, float(raw.get(channel, 0.0)))
	return result


static func ship_signature(assembled: AssembledShip, loaded_mass: float = -1.0) -> Dictionary:
	if assembled != null and not assembled.signature.is_empty():
		return assembled.signature
	return compute_ship_signature(assembled, loaded_mass)


static func compute_ship_signature(assembled: AssembledShip, loaded_mass: float = -1.0) -> Dictionary:
	var result := empty_signature()
	if assembled == null:
		return result

	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", {})
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var module_sig := module_signature(module_def)
		for channel in CHANNELS:
			result[channel] = float(result[channel]) + float(module_sig[channel])

	var hull_mass := loaded_mass
	if hull_mass < 0.0:
		hull_mass = float(assembled.envelope.get("dry_mass", 0.0))
		if hull_mass <= 0.0:
			hull_mass = float(assembled.chassis.get("mass", 0.0))

	result["gravitational"] = float(result["gravitational"]) + hull_mass * HULL_GRAV_PER_TONNE
	return result


static func compute_static_sensor_profile(assembled: AssembledShip) -> Dictionary:
	var profile := {
		"has_local_sensor": false,
		"range": 0.0,
		"sensitivity": empty_signature(),
		"effectiveness": 1.0,
	}

	if assembled == null:
		return profile

	profile["has_local_sensor"] = assembled.has_capability("local_sensor")
	if not profile["has_local_sensor"]:
		return profile

	var range_max := 0.0
	var sensitivity := empty_signature()

	for entry in assembled.modules_in_category("sensor"):
		var module_def: Variant = entry.get("data", {})
		if typeof(module_def) != TYPE_DICTIONARY:
			continue

		var module_range := float(module_def.get("sensor_range", 6500.0))
		range_max = maxf(range_max, module_range)

		var module_sensitivity: Variant = module_def.get("sensor_sensitivity", {})
		if typeof(module_sensitivity) != TYPE_DICTIONARY:
			continue
		for channel in CHANNELS:
			var value := float(module_sensitivity.get(channel, 0.0))
			sensitivity[channel] = maxf(float(sensitivity[channel]), value)

	profile["range"] = range_max
	profile["sensitivity"] = sensitivity
	profile["max_detect_range"] = range_max * MAX_CHANNEL_RANGE_MULT
	return profile


static func sensor_effectiveness(
	assembled: AssembledShip,
	operating_state: ShipOperatingState = null
) -> float:
	return _sensor_effectiveness(assembled, operating_state)


static func tick_observer_profile(
	assembled: AssembledShip,
	effectiveness: float = 1.0
) -> Dictionary:
	if assembled == null or assembled.sensor_profile.is_empty():
		var fallback := compute_static_sensor_profile(assembled)
		fallback["effectiveness"] = effectiveness
		return fallback

	var static_profile: Dictionary = assembled.sensor_profile
	return {
		"has_local_sensor": bool(static_profile.get("has_local_sensor", false)),
		"range": float(static_profile.get("range", 0.0)),
		"max_detect_range": float(static_profile.get("max_detect_range", 0.0)),
		"sensitivity": static_profile.get("sensitivity", empty_signature()),
		"effectiveness": effectiveness,
	}


static func sensor_profile(assembled: AssembledShip, operating_state: ShipOperatingState = null) -> Dictionary:
	return tick_observer_profile(assembled, _sensor_effectiveness(assembled, operating_state))


static func is_detected(
	distance: float,
	target_signature: Dictionary,
	target_broadcasting: bool,
	observer_profile: Dictionary,
	visual_radius: float
) -> bool:
	if distance < 0.0:
		return false

	var effectiveness := float(observer_profile.get("effectiveness", 1.0))
	if distance <= visual_radius:
		return true

	var has_local_sensor := bool(observer_profile.get("has_local_sensor", false))
	var sensor_range := float(observer_profile.get("range", 0.0))
	if not has_local_sensor or sensor_range <= 0.0:
		return false

	var max_detect_range := float(observer_profile.get("max_detect_range", sensor_range * MAX_CHANNEL_RANGE_MULT))
	var outer_limit := maxf(visual_radius, max_detect_range) * effectiveness
	if distance > outer_limit:
		return false

	if target_broadcasting and distance <= sensor_range * effectiveness:
		return true

	var sensitivity: Dictionary = observer_profile.get("sensitivity", empty_signature())
	for channel in CHANNELS:
		var sig_strength := float(target_signature.get(channel, 0.0))
		var channel_sensitivity := float(sensitivity.get(channel, 0.0))
		if sig_strength <= 0.0 or channel_sensitivity <= 0.0:
			continue

		var channel_mult := clampf(
			sig_strength * channel_sensitivity / SIGNATURE_SCALE,
			0.0,
			MAX_CHANNEL_RANGE_MULT
		)
		var channel_range := sensor_range * channel_mult * effectiveness
		if distance <= channel_range:
			return true

	return false


static func evaluate(
	distance: float,
	target_signature: Dictionary,
	target_broadcasting: bool,
	observer_profile: Dictionary,
	visual_radius: float
) -> Dictionary:
	var result := {
		"detected": false,
		"via_visual": false,
		"via_beacon": false,
		"channels": PackedStringArray(),
	}

	if distance < 0.0:
		return result

	if is_detected(distance, target_signature, target_broadcasting, observer_profile, visual_radius):
		result["detected"] = true
		if distance <= visual_radius:
			result["via_visual"] = true
			result["channels"].append("visual")
			return result

		var has_local_sensor := bool(observer_profile.get("has_local_sensor", false))
		var sensor_range := float(observer_profile.get("range", 0.0))
		var effectiveness := float(observer_profile.get("effectiveness", 1.0))

		if (
			target_broadcasting
			and has_local_sensor
			and sensor_range > 0.0
			and distance <= sensor_range * effectiveness
		):
			result["via_beacon"] = true
			result["channels"].append("beacon")
			return result

		var sensitivity: Dictionary = observer_profile.get("sensitivity", empty_signature())
		for channel in CHANNELS:
			var sig_strength := float(target_signature.get(channel, 0.0))
			var channel_sensitivity := float(sensitivity.get(channel, 0.0))
			if sig_strength <= 0.0 or channel_sensitivity <= 0.0:
				continue

			var channel_mult := clampf(
				sig_strength * channel_sensitivity / SIGNATURE_SCALE,
				0.0,
				MAX_CHANNEL_RANGE_MULT
			)
			var channel_range := sensor_range * channel_mult * effectiveness
			if distance <= channel_range:
				result["channels"].append(channel)

	return result


static func format_signature_lines(signature: Dictionary, transponder_label: String = "") -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Thermal: %.1f" % float(signature.get("thermal", 0.0)))
	lines.append("Gravitational: %.1f" % float(signature.get("gravitational", 0.0)))
	lines.append("EM: %.1f" % float(signature.get("electromagnetic", 0.0)))
	lines.append("Computational: %.1f" % float(signature.get("computational", 0.0)))
	if not transponder_label.is_empty():
		lines.append("Transponder: %s" % transponder_label)
	return lines


static func channel_summary(channels: PackedStringArray) -> String:
	if channels.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for entry in channels:
		var channel := str(entry)
		if channel == "beacon":
			parts.append("beacon")
		elif channel == "visual":
			parts.append("visual")
		else:
			parts.append("%s sig" % channel)
	return ", ".join(parts)


static func _sensor_effectiveness(assembled: AssembledShip, operating_state: ShipOperatingState) -> float:
	if operating_state == null:
		return 1.0

	var effectiveness := 1.0
	var sensor_requested := float(operating_state.power_requested_by_category.get("sensor", 0.0))
	var sensor_allocated := float(operating_state.power_allocated_by_category.get("sensor", 0.0))
	if sensor_requested > 0.0:
		effectiveness *= clampf(sensor_allocated / sensor_requested, 0.35, 1.0)

	if operating_state.compute_demand > operating_state.compute_capacity and operating_state.compute_capacity > 0.0:
		var overload := operating_state.compute_demand / operating_state.compute_capacity
		effectiveness *= clampf(1.0 / overload, 0.35, 1.0)

	return effectiveness
