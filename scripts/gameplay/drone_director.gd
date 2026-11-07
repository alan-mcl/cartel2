class_name DroneDirector
extends RefCounted

const TASK_ATTACK := "attack"
const TASK_DEFENCE := "defence"
const TASK_SENSOR := "sensor"
const TASK_RETRIEVAL := "retrieval"
const TASK_HOLD := "hold"

const CAP_ATTACK := "attack"
const CAP_DEFENCE := "defence"
const CAP_SENSOR := "sensor"
const CAP_RETRIEVAL := "retrieval"

## Minimum observer radius when classifying nearby threat actors (hulls without a sensor module).
const HOSTILE_THREAT_SENSOR_FLOOR := 8000.0


static func pick_task(module_def: ModuleDef, context: Dictionary) -> String:
	if module_def == null:
		return TASK_HOLD
	var caps := _drone_capabilities(module_def)
	if caps.is_empty():
		return TASK_HOLD

	var locked: Dictionary = context.get("locked_contact", {})
	var hostile_present := bool(context.get("hostile_present", false))
	var hostile_ids: Array = context.get("hostile_ship_ids", [])

	if not locked.is_empty():
		if _is_ship_lock(locked):
			if is_hostile_ship(locked, hostile_ids):
				return _first_cap(caps, [CAP_ATTACK, CAP_DEFENCE, CAP_SENSOR])
			if _has_attack_and_defence(module_def) and hostile_present:
				return _first_cap(caps, [CAP_ATTACK, CAP_DEFENCE, CAP_SENSOR])
			return _first_cap(caps, [CAP_RETRIEVAL, CAP_SENSOR, CAP_DEFENCE])
		if hostile_present:
			return _first_cap(caps, [CAP_ATTACK, CAP_RETRIEVAL, CAP_SENSOR, CAP_DEFENCE])
		return _first_cap(caps, [CAP_RETRIEVAL, CAP_SENSOR, CAP_DEFENCE, CAP_ATTACK])

	if hostile_present:
		return _first_cap(caps, [CAP_ATTACK, CAP_DEFENCE, CAP_SENSOR])
	return _first_cap(caps, [CAP_SENSOR, TASK_HOLD])


static func _first_cap(caps: PackedStringArray, order: Array) -> String:
	for entry in order:
		var cap := str(entry)
		if cap == TASK_HOLD:
			return TASK_HOLD
		if caps.has(cap):
			return cap
	return TASK_HOLD


static func _drone_capabilities(module_def: ModuleDef) -> PackedStringArray:
	var out: PackedStringArray = []
	for cap_variant in module_def.capabilities:
		var cap := str(cap_variant)
		if cap in [CAP_ATTACK, CAP_DEFENCE, CAP_SENSOR, CAP_RETRIEVAL]:
			out.append(cap)
	return out


static func _has_attack_and_defence(module_def: ModuleDef) -> bool:
	var caps := _drone_capabilities(module_def)
	return caps.has(CAP_ATTACK) and caps.has(CAP_DEFENCE)


static func _is_ship_lock(contact: Dictionary) -> bool:
	return str(contact.get("contact_kind", "")) == "traffic_npc"


static func is_hostile_ship(contact: Dictionary, hostile_ids: Array) -> bool:
	var id := str(contact.get("id", ""))
	if id.is_empty():
		return false
	for hostile_id in hostile_ids:
		if str(hostile_id) == id:
			return true
	return false


static func hostile_detection_range(context: Dictionary) -> float:
	var sensor_range := float(context.get("sensor_range", 0.0))
	return maxf(sensor_range, HOSTILE_THREAT_SENSOR_FLOOR)


static func hostile_present_in_sensor_range(context: Dictionary) -> bool:
	var detection_range := hostile_detection_range(context)
	var observer: Vector2 = context.get("observer_pos", Vector2.ZERO)
	var hostile_ids: Array = context.get("hostile_ship_ids", [])
	var contacts: Array = context.get("contacts", [])
	for contact_variant in contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if not _is_ship_lock(contact):
			continue
		if not is_hostile_ship(contact, hostile_ids):
			continue
		var pos: Vector2 = contact.get("position", Vector2.ZERO)
		if observer.distance_to(pos) <= detection_range:
			return true
	for pos_variant in context.get("hostile_positions", []):
		var threat_pos := _read_world_position(pos_variant)
		if threat_pos.is_finite() and observer.distance_to(threat_pos) <= detection_range:
			return true
	return false


static func _read_world_position(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if typeof(value) != TYPE_DICTIONARY:
		return Vector2(NAN, NAN)
	var p: Dictionary = value
	return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
