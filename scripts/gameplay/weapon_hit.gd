class_name WeaponHit
extends RefCounted


static func apply(
	collider: Object,
	delivery_type: String,
	packets: Dictionary,
	shooter: Variant = null,
	shot_velocity: Vector2 = Vector2.ZERO,
	attribution_session: GameSession = null,
	attribution_catalog: Catalog = null
) -> void:
	if collider == null:
		return
	shooter = _valid_shooter(shooter)
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

	var session := attribution_session if attribution_session != null else _shooter_session(shooter)
	if (
		session != null
		and not session.player.sandbox
		and bool(result.get("destroyed", false))
	):
		session.career.record_kill()

	if session != null and bool(result.get("destroyed", false)):
		_maybe_record_bounty_target_destroyed(session, collider)

	var catalog := attribution_catalog if attribution_catalog != null else _shooter_catalog(shooter)
	if session == null or catalog == null:
		return
	Sanctions.record_player_weapon_hit(session, catalog, shooter, collider, result)


static func capture_attribution(shooter: Variant) -> Dictionary:
	shooter = _valid_shooter(shooter)
	if shooter == null:
		return {}
	return {
		"session": _shooter_session(shooter),
		"catalog": _shooter_catalog(shooter),
	}


static func _valid_shooter(shooter: Variant) -> Variant:
	if shooter == null:
		return null
	if shooter is Object and not is_instance_valid(shooter):
		return null
	return shooter


static func _maybe_record_bounty_target_destroyed(session: GameSession, collider: Object) -> void:
	if session == null or collider == null:
		return
	if not VolatileTranslation.is_volatile_sector_id(session.sector_id):
		return
	var record := VolatileTranslation.find_by_sector_id(session, session.sector_id)
	if record.is_empty():
		return
	var setup: Variant = record.get("setup", {})
	if typeof(setup) != TYPE_DICTIONARY:
		return
	var bounty_target: Variant = setup.get("bounty_target", {})
	if typeof(bounty_target) != TYPE_DICTIONARY:
		return
	var target_id := str(bounty_target.get("id", ""))
	if target_id.is_empty():
		return
	var actor = Sanctions._collider_actor(collider)
	if actor == null:
		return
	if str(actor.get("id")) != target_id:
		return
	session.player.record_target_scan(
		target_id,
		"bounty_target",
		session.sector_id,
		float(session.gst_seconds)
	)
	session.changed.emit()


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


static func _shooter_session(shooter: Variant) -> GameSession:
	shooter = _valid_shooter(shooter)
	if shooter == null or not shooter is Node:
		return null
	var value = shooter.get("session")
	if value is GameSession:
		return value
	return null


static func _shooter_catalog(shooter: Variant) -> Catalog:
	shooter = _valid_shooter(shooter)
	if shooter == null or not shooter is Node:
		return null
	var value = shooter.get("catalog")
	if value is Catalog:
		return value
	return null
