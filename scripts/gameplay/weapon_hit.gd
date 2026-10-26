class_name WeaponHit
extends RefCounted


static func apply(
	collider: Object,
	delivery_type: String,
	packets: Dictionary,
	shooter: Variant = null,
	shot_velocity: Vector2 = Vector2.ZERO,
	context: WeaponHitContext = null
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

	var session: GameSession = context.session if context != null else null
	if (
		session != null
		and not session.player.sandbox
		and bool(result.get("destroyed", false))
	):
		session.career.record_kill()

	if session != null and bool(result.get("destroyed", false)):
		_maybe_record_bounty_target_destroyed(session, collider)
	elif session != null:
		_maybe_record_bounty_target_disabled(session, collider)

	var catalog: Catalog = context.catalog if context != null else null
	if session == null or catalog == null:
		return
	var player_shot := context != null and context.player_shot
	Sanctions.record_player_weapon_hit(session, catalog, player_shot, collider, result)


static func _valid_shooter(shooter: Variant) -> Variant:
	if shooter == null:
		return null
	if shooter is Object and not is_instance_valid(shooter):
		return null
	return shooter


static func _maybe_record_bounty_target_destroyed(session: GameSession, collider: Object) -> void:
	if session == null or collider == null:
		return
	var actor = _bounty_actor_from_collider(collider)
	if actor == null:
		return
	var target_id := str(actor.get("id"))
	if target_id.is_empty():
		return
	var sector_id := _bounty_record_sector(session, target_id)
	if sector_id.is_empty():
		return
	session.player.record_target_scan(
		target_id,
		"bounty_target",
		sector_id,
		float(session.gst_seconds)
	)
	session.changed.emit()


static func _maybe_record_bounty_target_disabled(session: GameSession, collider: Object) -> void:
	if session == null or collider == null:
		return
	var actor = _bounty_actor_from_collider(collider)
	if actor == null:
		return
	var target_id := str(actor.get("id"))
	if target_id.is_empty():
		return
	if float(actor.get("hull_current")) <= 0.0:
		return
	var assembled: Variant = actor.get("assembled_ship")
	var combat_state: Variant = actor.get("combat_state")
	if assembled == null:
		return
	if combat_state == null:
		combat_state = ShipCombatState.from_assembled(assembled)
	if ShipCombat.get_effective_power_generation(assembled, combat_state) > 0.0:
		return
	if session.player.has_contact_record(target_id, "bounty_disabled"):
		return
	if session.player.has_contact_record(target_id, "bounty_target"):
		return
	var sector_id := _bounty_record_sector(session, target_id)
	if sector_id.is_empty():
		return
	session.player.record_target_scan(
		target_id,
		"bounty_disabled",
		sector_id,
		float(session.gst_seconds)
	)
	session.changed.emit()


static func _bounty_record_sector(session: GameSession, target_id: String) -> String:
	var contracted := session.player.bounty_contract_sector(target_id)
	if not contracted.is_empty():
		return contracted
	if not VolatileTranslation.is_volatile_sector_id(session.sector_id):
		return ""
	var record := VolatileTranslation.find_by_sector_id(session, session.sector_id)
	if record.is_empty():
		return ""
	var setup: Variant = record.get("setup", {})
	if typeof(setup) != TYPE_DICTIONARY:
		return ""
	var bounty_target: Variant = setup.get("bounty_target", {})
	if typeof(bounty_target) != TYPE_DICTIONARY:
		return ""
	if str(bounty_target.get("id", "")) != target_id:
		return ""
	return session.sector_id


static func _bounty_actor_from_collider(collider: Object) -> Variant:
	var actor = Sanctions._collider_actor(collider)
	if actor != null:
		return actor
	if collider == null:
		return null
	if collider.get("assembled_ship") != null and not str(collider.get("id")).is_empty():
		return collider
	return null


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
