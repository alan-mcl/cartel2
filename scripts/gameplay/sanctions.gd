class_name Sanctions
extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")


static func total_fine(sanctions: Array) -> int:
	var total := 0
	for entry_variant in sanctions:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		total += int(entry_variant.get("fine", 0))
	return total


static func has_infraction_for_target(
	sanctions: Array,
	infraction_id: String,
	target_id: String
) -> bool:
	for entry_variant in sanctions:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("infraction_id", "")) != infraction_id:
			continue
		if str(entry.get("target_id", "")) == target_id:
			return true
	return false


static func add_from_infraction(
	player: PlayerState,
	catalog: Catalog,
	infraction_id: String,
	target_id: String = ""
) -> bool:
	var def := catalog.get_sanction_infraction(infraction_id)
	if def.is_empty():
		return false
	if has_infraction_for_target(player.sanctions, infraction_id, target_id):
		return false
	var fine := int(def.get("fine", 0))
	if fine < 0:
		return false
	player.sanctions.append({
		"id": _next_sanction_id(player.sanctions),
		"infraction_id": infraction_id,
		"fine": fine,
		"target_id": target_id,
	})
	return true


static func infraction_label(catalog: Catalog, infraction_id: String) -> String:
	var def := catalog.get_sanction_infraction(infraction_id)
	if def.is_empty():
		return infraction_id
	return str(def.get("name", infraction_id))


static func record_player_weapon_hit(
	session: Variant,
	catalog: Catalog,
	shooter: Variant,
	collider: Variant,
	result: Dictionary
) -> void:
	if session == null or catalog == null or session.sandbox:
		return
	if session.in_unspace:
		return
	if not _is_player_shooter(shooter):
		return
	if bool(result.get("intercepted", false)):
		return
	var target_id := _sanction_target_id(collider)
	if target_id.is_empty():
		return

	var added_fire := add_from_infraction(session.player, catalog, "unlawful_fire", target_id)
	var added_destroy := false
	if _target_destroyed(collider):
		added_destroy = add_from_infraction(
			session.player,
			catalog,
			"ship_destroyed",
			target_id
		)

	if not added_fire and not added_destroy:
		return

	var parts: PackedStringArray = PackedStringArray()
	if added_fire:
		var fire_def := catalog.get_sanction_infraction("unlawful_fire")
		parts.append(
			"%s (d%d)" % [infraction_label(catalog, "unlawful_fire"), int(fire_def.get("fine", 0))]
		)
	if added_destroy:
		var destroy_def := catalog.get_sanction_infraction("ship_destroyed")
		parts.append(
			"%s (d%d)" % [
				infraction_label(catalog, "ship_destroyed"),
				int(destroy_def.get("fine", 0)),
			]
		)
	session.last_log = "Sanction recorded: %s." % ", ".join(parts)
	session.changed.emit()


static func _is_player_shooter(shooter: Variant) -> bool:
	if shooter == null:
		return false
	return _shooter_session(shooter) != null


static func _sanction_target_id(collider: Variant) -> String:
	if collider == null:
		return ""
	var actor = _collider_actor(collider)
	if actor == null:
		return ""
	return str(actor.get("id"))


static func _target_destroyed(collider: Variant) -> bool:
	if collider == null:
		return false
	var actor = _collider_actor(collider)
	if actor == null:
		return false
	var ai_state = actor.get("ai_state")
	if ai_state != null:
		return int(ai_state) == TrafficActorScript.AiState.DESTROYED
	return float(actor.get("hull_current")) <= 0.0


static func _collider_actor(collider: Variant) -> Variant:
	if collider == null:
		return null
	if collider is Object:
		return collider.get("actor")
	return null


static func _shooter_session(shooter: Variant) -> Variant:
	if shooter == null:
		return null
	if shooter is Object:
		var value = shooter.get("session")
		if value != null and value.get("player") != null:
			return value
	return null


static func _shooter_catalog(shooter: Variant) -> Catalog:
	if shooter == null:
		return null
	if shooter is Object:
		var value = shooter.get("catalog")
		if value is Catalog:
			return value
	return null


static func _next_sanction_id(sanctions: Array) -> String:
	return "san_%d" % (sanctions.size() + 1)
