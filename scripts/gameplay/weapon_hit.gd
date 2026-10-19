class_name WeaponHit
extends RefCounted


static func apply(
	collider: Object,
	delivery_type: String,
	packets: Dictionary,
	shooter: Variant = null,
	shot_velocity: Vector2 = Vector2.ZERO
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

	if bool(result.get("intercepted", false)):
		return

	var delta := ShipCombat.impact_delta_v(packets, _target_mass(collider), shot_velocity)
	if delta.length_squared() > 0.01 and collider.has_method("apply_weapon_impulse"):
		collider.call("apply_weapon_impulse", delta)

	var session := _shooter_session(shooter)
	if (
		session != null
		and not session.player.sandbox
		and bool(result.get("destroyed", false))
	):
		session.career.record_kill()

	var catalog := _shooter_catalog(shooter)
	if session == null or catalog == null:
		return
	Sanctions.record_player_weapon_hit(session, catalog, shooter, collider, result)


static func _target_mass(collider: Object) -> float:
	if collider == null:
		return 10.0
	var catalog: Variant = collider.get("catalog")
	var owned: Variant = collider.get("owned_ship")
	var assembled: Variant = collider.get("assembled_ship")
	var actor: Variant = collider.get("actor")
	if actor != null:
		owned = actor.get("owned_ship")
		assembled = actor.get("assembled_ship")
	if catalog is Catalog and owned is OwnedShip and assembled is AssembledShip:
		return ShipAssembler.calculate_loaded_mass(catalog, owned, assembled)
	if assembled is AssembledShip:
		return maxf(float(assembled.envelope.get("dry_mass", 10.0)), 0.1)
	return 10.0


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
