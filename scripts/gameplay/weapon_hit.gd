class_name WeaponHit
extends RefCounted


static func apply(
	collider: Object,
	delivery_type: String,
	packets: Dictionary,
	shooter: Variant = null
) -> void:
	if collider == null:
		return
	if shooter != null and collider == shooter:
		return
	var result: Dictionary = {}
	if collider.has_method("take_combat_hit"):
		result = collider.call("take_combat_hit", delivery_type, packets)
	elif collider.has_method("take_weapon_hit"):
		collider.call("take_weapon_hit", ShipCombat.sum_packets(packets))
	else:
		return

	var session := _shooter_session(shooter)
	var catalog := _shooter_catalog(shooter)
	if session == null or catalog == null:
		return
	Sanctions.record_player_weapon_hit(session, catalog, shooter, collider, result)


static func _shooter_session(shooter: Node) -> GameSession:
	if shooter == null:
		return null
	var value = shooter.get("session")
	if value is GameSession:
		return value
	return null


static func _shooter_catalog(shooter: Node) -> Catalog:
	if shooter == null:
		return null
	var value = shooter.get("catalog")
	if value is Catalog:
		return value
	return null
