class_name TargetLock
extends RefCounted

const CAPABILITY_ID := "basic_target_lock"
const PLAYER_TARGET_ID := "player"

const PEGASUS_MASS := 8.5
const PEGASUS_LONGEST_AXIS := 70.0
const FAR_LOD_HULL_SCALE := 0.65
const MIN_HULL_RADIUS := 10.0


static func has_capability(assembled: AssembledShip) -> bool:
	return assembled != null and assembled.has_capability(CAPABILITY_ID)


static func lockable_contacts(contacts: Array, observer_pos: Vector2) -> Array:
	var candidates: Array = []
	for contact_variant in contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if str(contact.get("contact_kind", "")) != "traffic_npc":
			continue
		var id := str(contact.get("id", ""))
		if id.is_empty():
			continue
		var pos: Vector2 = contact.get("position", Vector2.ZERO)
		var dist_sq := observer_pos.distance_squared_to(pos)
		candidates.append({"id": id, "distance_sq": dist_sq, "contact": contact})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: float = float(a.get("distance_sq", 0.0))
		var db: float = float(b.get("distance_sq", 0.0))
		if da != db:
			return da < db
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return candidates


static func candidate_ids(contacts: Array, observer_pos: Vector2) -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in lockable_contacts(contacts, observer_pos):
		ids.append(str(entry.get("id", "")))
	return ids


static func contact_for_id(contacts: Array, target_id: String) -> Dictionary:
	if target_id.is_empty():
		return {}
	for contact_variant in contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if str(contact.get("id", "")) == target_id:
			return contact
	return {}


static func acquire_nearest(
	assembled: AssembledShip,
	contacts: Array,
	observer_pos: Vector2
) -> String:
	if not has_capability(assembled):
		return ""
	var ids := candidate_ids(contacts, observer_pos)
	if ids.is_empty():
		return ""
	return ids[0]


static func clear() -> String:
	return ""


static func cycle_next(
	current_id: String,
	assembled: AssembledShip,
	contacts: Array,
	observer_pos: Vector2
) -> String:
	if current_id.is_empty() or not has_capability(assembled):
		return current_id
	var ids := candidate_ids(contacts, observer_pos)
	if ids.is_empty():
		return ""
	if ids.size() == 1:
		return ids[0]
	var index := ids.find(current_id)
	if index < 0:
		return ids[0]
	return ids[(index + 1) % ids.size()]


static func retain(
	current_id: String,
	assembled: AssembledShip,
	contacts: Array,
	observer_pos: Vector2
) -> String:
	if current_id.is_empty():
		return ""
	if not has_capability(assembled):
		return ""
	var ids := candidate_ids(contacts, observer_pos)
	if ids.is_empty() or not ids.has(current_id):
		return ""
	return current_id


static func toggle(
	current_id: String,
	assembled: AssembledShip,
	contacts: Array,
	observer_pos: Vector2
) -> String:
	if not has_capability(assembled):
		return ""
	if not current_id.is_empty():
		return clear()
	return acquire_nearest(assembled, contacts, observer_pos)


static func hull_radius_world(assembled: AssembledShip, far_lod: bool) -> float:
	if assembled == null or assembled.chassis.is_empty():
		return 18.0
	var mass := float(assembled.chassis.get("mass", PEGASUS_MASS))
	var longest := _round_to_even(PEGASUS_LONGEST_AXIS * mass / PEGASUS_MASS)
	var half := longest * 0.5
	var scale := FAR_LOD_HULL_SCALE if far_lod else 1.0
	return maxf(half * scale, MIN_HULL_RADIUS)


static func lock_contact_fields(actor) -> Dictionary:
	if actor == null or actor.assembled_ship == null:
		return {
			"lock_hull_radius": 18.0,
			"heading_rad": 0.0,
			"sprite_path": "",
			"lock_hull_display_scale": 1.0,
		}
	var far_lod := not bool(actor.has_sim_slot)
	return {
		"lock_hull_radius": hull_radius_world(actor.assembled_ship, far_lod),
		"heading_rad": float(actor.motion.facing),
		"sprite_path": str(actor.assembled_ship.chassis.get("sprite", "")),
		"lock_hull_display_scale": FAR_LOD_HULL_SCALE if far_lod else 1.0,
	}


static func _round_to_even(value: float) -> float:
	var rounded := int(round(value))
	if rounded % 2 != 0:
		rounded += 1
	return float(rounded)


static func refresh_npc_lock(
	actor,
	has_player_contact: bool
) -> void:
	if actor == null:
		return
	if (
		has_player_contact
		and actor.assembled_ship != null
		and actor.assembled_ship.has_capability(CAPABILITY_ID)
	):
		actor.locked_target_id = PLAYER_TARGET_ID
	else:
		actor.locked_target_id = ""
