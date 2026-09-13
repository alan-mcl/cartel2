class_name SensorSystem
extends RefCounted

enum DetectStage { UNDETECTED, VISUAL, BEACON, NEEDS_SIGNATURE }

const CHANNELS := ["thermal", "gravitational", "electromagnetic", "computational"]
const SIGNATURE_BUCKETS := [
	"passive",
	"propulsion",
	"weapon",
	"sensor",
	"transponder",
	"power",
	"in_flight",
]
const DETECT_THRESHOLD := 8.0
const CLOSE_WEIGHT := 1.25
const FAR_WEIGHT := 0.75
const HULL_GRAV_PER_TONNE := 0.08
const SIGNATURE_GLOW_SEC := 1.5
const POWER_IDLE_SIGNATURE_FLOOR := 0.15

const PASSIVE_SIGNATURE_CATEGORIES := ["armour", "life_support"]
const IN_FLIGHT_SIGNATURE_CATEGORIES := ["shield", "point_defence", "ecm"]


static func empty_signature() -> Dictionary:
	return {
		"thermal": 0.0,
		"gravitational": 0.0,
		"electromagnetic": 0.0,
		"computational": 0.0,
	}


static func module_signature(module_def: ModuleDef) -> Dictionary:
	if module_def == null:
		return empty_signature()

	var raw := module_def.signature.to_dict()
	var result := empty_signature()
	for channel in CHANNELS:
		result[channel] = maxf(0.0, float(raw.get(channel, 0.0)))
	return result


static func _signature_bucket_for_category(category: String) -> String:
	if category in PASSIVE_SIGNATURE_CATEGORIES:
		return "passive"
	match category:
		"propulsion":
			return "propulsion"
		"weapon":
			return "weapon"
		"sensor":
			return "sensor"
		"transponder":
			return "transponder"
		"power":
			return "power"
		_:
			return "in_flight"


static func _empty_channel_array() -> PackedFloat32Array:
	return PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


static func _add_module_to_basis(basis: Dictionary, module_def: ModuleDef) -> void:
	if module_def == null:
		return
	var category := module_def.category
	if category == "sensor" and not module_def.has_active:
		return
	var bucket := _signature_bucket_for_category(category)
	var channels: PackedFloat32Array = basis.get(bucket, _empty_channel_array())
	var module_sig := module_signature(module_def)
	channels[0] += float(module_sig.get("thermal", 0.0))
	channels[1] += float(module_sig.get("gravitational", 0.0))
	channels[2] += float(module_sig.get("electromagnetic", 0.0))
	channels[3] += float(module_sig.get("computational", 0.0))
	basis[bucket] = channels


static func compute_signature_basis(assembled: AssembledShip) -> Dictionary:
	var basis := {
		"passive": _empty_channel_array(),
		"propulsion": _empty_channel_array(),
		"weapon": _empty_channel_array(),
		"sensor": _empty_channel_array(),
		"transponder": _empty_channel_array(),
		"power": _empty_channel_array(),
		"in_flight": _empty_channel_array(),
		"hull_grav_mass": 0.0,
	}
	if assembled == null:
		return basis

	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", null)
		if module_def == null or not module_def is ModuleDef:
			continue
		_add_module_to_basis(basis, module_def)

	var hull_mass := float(assembled.envelope.get("dry_mass", 0.0))
	if hull_mass <= 0.0:
		hull_mass = float(assembled.chassis.get("mass", 0.0))
	basis["hull_grav_mass"] = hull_mass
	return basis


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
		var module_def: Variant = entry.get("data", null)
		if module_def == null or not module_def is ModuleDef:
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


static func live_signature(
	assembled: AssembledShip,
	operating_state: ShipOperatingState = null,
	loaded_mass: float = -1.0
) -> Dictionary:
	if assembled == null:
		return empty_signature()
	if operating_state == null:
		return ship_signature(assembled, loaded_mass)

	assembled.ensure_signature_basis()
	if assembled.signature_basis.is_empty():
		return _live_signature_from_modules(assembled, operating_state, loaded_mass)
	return _live_signature_from_basis(assembled, operating_state, loaded_mass)


static func _live_signature_from_basis(
	assembled: AssembledShip,
	operating_state: ShipOperatingState,
	loaded_mass: float
) -> Dictionary:
	var basis: Dictionary = assembled.signature_basis
	var in_flight := bool(operating_state.active_systems.get("sensors", false))
	var active_sensors := bool(operating_state.active_systems.get("active_sensors", false))
	var propulsion_glow := float(operating_state.signature_glow_propulsion)
	var weapon_glow := float(operating_state.signature_glow_weapon)
	var power_scale := _live_power_signature_scale(operating_state)

	var propulsion_factor := (
		1.0 if bool(operating_state.active_systems.get("engine", false)) else propulsion_glow
	)
	var weapon_factor := (
		1.0 if bool(operating_state.active_systems.get("weapons", false)) else weapon_glow
	)
	var sensor_factor := 1.0 if active_sensors else 0.0
	var transponder_factor := 1.0 if bool(operating_state.active_systems.get("transponder", false)) else 0.0
	var in_flight_factor := 1.0 if in_flight else 0.0

	var passive: PackedFloat32Array = basis.get("passive", _empty_channel_array())
	var propulsion: PackedFloat32Array = basis.get("propulsion", _empty_channel_array())
	var weapon: PackedFloat32Array = basis.get("weapon", _empty_channel_array())
	var sensor: PackedFloat32Array = basis.get("sensor", _empty_channel_array())
	var transponder: PackedFloat32Array = basis.get("transponder", _empty_channel_array())
	var power: PackedFloat32Array = basis.get("power", _empty_channel_array())
	var in_flight_sig: PackedFloat32Array = basis.get("in_flight", _empty_channel_array())

	var thermal := (
		passive[0]
		+ propulsion[0] * propulsion_factor
		+ weapon[0] * weapon_factor
		+ sensor[0] * sensor_factor
		+ transponder[0] * transponder_factor
		+ power[0] * power_scale
		+ in_flight_sig[0] * in_flight_factor
	)
	var gravitational := (
		passive[1]
		+ propulsion[1] * propulsion_factor
		+ weapon[1] * weapon_factor
		+ sensor[1] * sensor_factor
		+ transponder[1] * transponder_factor
		+ power[1] * power_scale
		+ in_flight_sig[1] * in_flight_factor
	)
	var electromagnetic := (
		passive[2]
		+ propulsion[2] * propulsion_factor
		+ weapon[2] * weapon_factor
		+ sensor[2] * sensor_factor
		+ transponder[2] * transponder_factor
		+ power[2] * power_scale
		+ in_flight_sig[2] * in_flight_factor
	)
	var computational := (
		passive[3]
		+ propulsion[3] * propulsion_factor
		+ weapon[3] * weapon_factor
		+ sensor[3] * sensor_factor
		+ transponder[3] * transponder_factor
		+ power[3] * power_scale
		+ in_flight_sig[3] * in_flight_factor
	)

	var hull_mass := loaded_mass
	if hull_mass < 0.0:
		hull_mass = float(basis.get("hull_grav_mass", 0.0))
		if hull_mass <= 0.0:
			hull_mass = float(assembled.envelope.get("dry_mass", 0.0))
			if hull_mass <= 0.0:
				hull_mass = float(assembled.chassis.get("mass", 0.0))
	gravitational += hull_mass * HULL_GRAV_PER_TONNE

	var compute_ratio := 0.0
	if operating_state.compute_capacity > 0.0:
		compute_ratio = clampf(
			operating_state.compute_demand / operating_state.compute_capacity,
			0.0,
			1.0
		)
	computational *= compute_ratio

	return {
		"thermal": thermal,
		"gravitational": gravitational,
		"electromagnetic": electromagnetic,
		"computational": computational,
	}


static func _live_signature_from_modules(
	assembled: AssembledShip,
	operating_state: ShipOperatingState,
	loaded_mass: float
) -> Dictionary:
	var result := empty_signature()
	var in_flight := bool(operating_state.active_systems.get("sensors", false))
	var active_sensors := bool(operating_state.active_systems.get("active_sensors", false))
	var propulsion_glow := float(operating_state.signature_glow_propulsion)
	var weapon_glow := float(operating_state.signature_glow_weapon)
	var power_scale := _live_power_signature_scale(operating_state)

	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_data: Variant = entry.get("data", null)
		if module_data == null or not module_data is ModuleDef:
			continue
		var module_def: ModuleDef = module_data

		var category := module_def.category
		var factor := _live_module_signature_factor(
			category,
			module_def,
			operating_state,
			in_flight,
			active_sensors,
			propulsion_glow,
			weapon_glow,
			power_scale
		)
		if factor <= 0.0:
			continue

		var module_sig := module_signature(module_def)
		for channel in CHANNELS:
			result[channel] = float(result[channel]) + float(module_sig[channel]) * factor

	var hull_mass := loaded_mass
	if hull_mass < 0.0:
		hull_mass = float(assembled.envelope.get("dry_mass", 0.0))
		if hull_mass <= 0.0:
			hull_mass = float(assembled.chassis.get("mass", 0.0))
	result["gravitational"] = float(result["gravitational"]) + hull_mass * HULL_GRAV_PER_TONNE

	var compute_ratio := 0.0
	if operating_state.compute_capacity > 0.0:
		compute_ratio = clampf(
			operating_state.compute_demand / operating_state.compute_capacity,
			0.0,
			1.0
		)
	result["computational"] = float(result["computational"]) * compute_ratio
	return result


static func tick_signature_glow(operating_state: ShipOperatingState, delta: float) -> void:
	if operating_state == null:
		return

	var engine_active := bool(operating_state.active_systems.get("engine", false))
	var weapons_active := bool(operating_state.active_systems.get("weapons", false))

	if engine_active:
		operating_state.signature_glow_propulsion = 1.0
	elif operating_state.signature_glow_propulsion > 0.0:
		operating_state.signature_glow_propulsion = maxf(
			0.0,
			operating_state.signature_glow_propulsion - delta / SIGNATURE_GLOW_SEC
		)

	if weapons_active:
		operating_state.signature_glow_weapon = 1.0
	elif operating_state.signature_glow_weapon > 0.0:
		operating_state.signature_glow_weapon = maxf(
			0.0,
			operating_state.signature_glow_weapon - delta / SIGNATURE_GLOW_SEC
		)


static func _module_sensitivity_for_toggle(
	module_def: ModuleDef,
	active_sensors_enabled: bool
) -> Dictionary:
	var result := empty_signature()
	if module_def == null:
		return result

	var full_sensitivity := module_def.sensor_sensitivity.to_dict()
	if active_sensors_enabled or not module_def.has_active:
		for channel in CHANNELS:
			result[channel] = maxf(0.0, float(full_sensitivity.get(channel, 0.0)))
		return result

	var quiet_sensitivity := module_def.sensor_sensitivity_passive.to_dict()
	for channel in CHANNELS:
		result[channel] = maxf(0.0, float(quiet_sensitivity.get(channel, 0.0)))
	return result


static func compute_static_sensor_profile(assembled: AssembledShip) -> Dictionary:
	var profile := {
		"has_local_sensor": false,
		"range": 0.0,
		"sensitivity": empty_signature(),
		"sensitivity_active": empty_signature(),
		"sensitivity_passive": empty_signature(),
		"effectiveness": 1.0,
	}

	if assembled == null:
		return profile

	profile["has_local_sensor"] = assembled.has_capability("local_sensor")
	if not profile["has_local_sensor"]:
		return profile

	var range_max := 0.0
	var sensitivity_active := empty_signature()
	var sensitivity_passive := empty_signature()

	for entry in assembled.modules_in_category("sensor"):
		var module_data: Variant = entry.get("data", null)
		if module_data == null or not module_data is ModuleDef:
			continue
		var module_def: ModuleDef = module_data

		var module_range: float = module_def.sensor_range if module_def.sensor_range > 0.0 else 6500.0
		range_max = maxf(range_max, module_range)

		var active_channels := _module_sensitivity_for_toggle(module_def, true)
		for channel in CHANNELS:
			sensitivity_active[channel] = maxf(
				float(sensitivity_active[channel]),
				float(active_channels[channel])
			)

		var passive_channels := _module_sensitivity_for_toggle(module_def, false)
		for channel in CHANNELS:
			sensitivity_passive[channel] = maxf(
				float(sensitivity_passive[channel]),
				float(passive_channels[channel])
			)

	profile["range"] = range_max
	profile["sensitivity"] = sensitivity_active
	profile["sensitivity_active"] = sensitivity_active
	profile["sensitivity_passive"] = sensitivity_passive
	profile["max_detect_range"] = range_max
	return profile


static func sensor_effectiveness(
	assembled: AssembledShip,
	operating_state: ShipOperatingState = null
) -> float:
	return _sensor_effectiveness(assembled, operating_state)


static func tick_observer_profile(
	assembled: AssembledShip,
	effectiveness: float = 1.0,
	active_sensors_enabled: bool = true
) -> Dictionary:
	if assembled == null or assembled.sensor_profile.is_empty():
		var fallback := compute_static_sensor_profile(assembled)
		fallback["effectiveness"] = effectiveness
		fallback["sensitivity"] = (
			fallback.get("sensitivity_active", empty_signature())
			if active_sensors_enabled
			else fallback.get("sensitivity_passive", empty_signature())
		)
		return fallback

	var static_profile: Dictionary = assembled.sensor_profile
	var sensitivity: Dictionary = (
		static_profile.get("sensitivity_active", static_profile.get("sensitivity", empty_signature()))
		if active_sensors_enabled
		else static_profile.get("sensitivity_passive", empty_signature())
	)
	return {
		"has_local_sensor": bool(static_profile.get("has_local_sensor", false)),
		"range": float(static_profile.get("range", 0.0)),
		"max_detect_range": float(static_profile.get("max_detect_range", 0.0)),
		"sensitivity": sensitivity,
		"effectiveness": effectiveness,
	}


static func sensor_profile(
	assembled: AssembledShip,
	operating_state: ShipOperatingState = null,
	active_sensors_enabled: bool = true
) -> Dictionary:
	var effectiveness := _sensor_effectiveness(assembled, operating_state)
	if operating_state != null:
		active_sensors_enabled = bool(operating_state.active_systems.get("active_sensors", active_sensors_enabled))
	return tick_observer_profile(assembled, effectiveness, active_sensors_enabled)


static func detection_stage(
	distance: float,
	target_broadcasting: bool,
	observer_profile: Dictionary,
	visual_radius: float
) -> DetectStage:
	if distance < 0.0:
		return DetectStage.UNDETECTED

	if distance <= visual_radius:
		return DetectStage.VISUAL

	var has_local_sensor := bool(observer_profile.get("has_local_sensor", false))
	var sensor_range := float(observer_profile.get("range", 0.0))
	if not has_local_sensor or sensor_range <= 0.0:
		return DetectStage.UNDETECTED

	var effectiveness := float(observer_profile.get("effectiveness", 1.0))
	var envelope := sensor_range * effectiveness
	if distance > envelope:
		return DetectStage.UNDETECTED

	if target_broadcasting:
		return DetectStage.BEACON

	return DetectStage.NEEDS_SIGNATURE


static func is_detected(
	distance: float,
	target_signature: Dictionary,
	target_broadcasting: bool,
	observer_profile: Dictionary,
	visual_radius: float
) -> bool:
	var stage := detection_stage(
		distance,
		target_broadcasting,
		observer_profile,
		visual_radius
	)
	match stage:
		DetectStage.VISUAL, DetectStage.BEACON:
			return true
		DetectStage.UNDETECTED:
			return false
		DetectStage.NEEDS_SIGNATURE:
			return _signature_detected(distance, target_signature, observer_profile)
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

	var stage := detection_stage(
		distance,
		target_broadcasting,
		observer_profile,
		visual_radius
	)
	match stage:
		DetectStage.UNDETECTED:
			return result
		DetectStage.VISUAL:
			result["detected"] = true
			result["via_visual"] = true
			result["channels"].append("visual")
			return result
		DetectStage.BEACON:
			result["detected"] = true
			result["via_beacon"] = true
			result["channels"].append("beacon")
			return result
		DetectStage.NEEDS_SIGNATURE:
			if not _signature_detected(distance, target_signature, observer_profile):
				return result
			result["detected"] = true
			var sensor_range := float(observer_profile.get("range", 0.0))
			var effectiveness := float(observer_profile.get("effectiveness", 1.0))
			var range_weight := _range_weight(distance, sensor_range, effectiveness)
			var sensitivity: Dictionary = observer_profile.get("sensitivity", empty_signature())
			for channel in CHANNELS:
				var sig_strength := float(target_signature.get(channel, 0.0))
				var channel_sensitivity := float(sensitivity.get(channel, 0.0))
				if _channel_meets_threshold(sig_strength, channel_sensitivity, range_weight):
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


static func _signature_detected(
	distance: float,
	target_signature: Dictionary,
	observer_profile: Dictionary
) -> bool:
	var sensor_range := float(observer_profile.get("range", 0.0))
	var effectiveness := float(observer_profile.get("effectiveness", 1.0))
	var range_weight := _range_weight(distance, sensor_range, effectiveness)
	var sensitivity: Dictionary = observer_profile.get("sensitivity", empty_signature())
	for channel in CHANNELS:
		var sig_strength := float(target_signature.get(channel, 0.0))
		var channel_sensitivity := float(sensitivity.get(channel, 0.0))
		if _channel_meets_threshold(sig_strength, channel_sensitivity, range_weight):
			return true
	return false


static func _range_weight(distance: float, sensor_range: float, effectiveness: float) -> float:
	var envelope := maxf(sensor_range * effectiveness, 1.0)
	var t := clampf(distance / envelope, 0.0, 1.0)
	return lerpf(CLOSE_WEIGHT, FAR_WEIGHT, t)


static func _channel_meets_threshold(
	sig_strength: float,
	channel_sensitivity: float,
	range_weight: float
) -> bool:
	if sig_strength <= 0.0 or channel_sensitivity <= 0.0:
		return false
	return sig_strength * channel_sensitivity * range_weight >= DETECT_THRESHOLD


static func _live_power_signature_scale(operating_state: ShipOperatingState) -> float:
	if operating_state.power_available <= 0.0:
		return 0.0
	return clampf(
		operating_state.power_allocated / maxf(operating_state.power_available, 1.0),
		POWER_IDLE_SIGNATURE_FLOOR,
		1.0
	)


static func _live_module_signature_factor(
	category: String,
	module_def: ModuleDef,
	operating_state: ShipOperatingState,
	in_flight: bool,
	active_sensors: bool,
	propulsion_glow: float,
	weapon_glow: float,
	power_scale: float
) -> float:
	if category in PASSIVE_SIGNATURE_CATEGORIES:
		return 1.0

	match category:
		"propulsion":
			if bool(operating_state.active_systems.get("engine", false)):
				return 1.0
			return propulsion_glow
		"weapon":
			if bool(operating_state.active_systems.get("weapons", false)):
				return 1.0
			return weapon_glow
		"sensor":
			if module_def == null or not module_def.has_active:
				return 0.0
			return 1.0 if active_sensors else 0.0
		"transponder":
			return 1.0 if bool(operating_state.active_systems.get("transponder", false)) else 0.0
		"power":
			return power_scale
		_:
			if category in IN_FLIGHT_SIGNATURE_CATEGORIES:
				return 1.0 if in_flight else 0.0
			return 1.0 if in_flight else 0.0


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
