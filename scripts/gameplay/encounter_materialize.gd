class_name EncounterMaterialize
extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
const TrafficSpawnScript := preload("res://scripts/gameplay/traffic_spawn.gd")
const TargetLockScript := preload("res://scripts/gameplay/target_lock.gd")

const ENCOUNTER_ID_PREFIX := "encounter_"


static func spawn_actors_for_plan(
	subsystem: EncounterSubsystem,
	catalog: Catalog,
	traffic_config: Dictionary,
	sector_id: String,
	world_loader: WorldLoader,
	player_pos: Vector2
) -> Array:
	if subsystem == null or catalog == null:
		return []
	var plan := subsystem.get_active_plan()
	if plan.is_empty():
		return []
	var spawns: Variant = plan.get("spawns", [])
	if typeof(spawns) != TYPE_ARRAY or spawns.is_empty():
		return []

	var rng := RandomNumberGenerator.new()
	rng.seed = int(plan.get("seed", 1))
	var anchors := world_loader.get_traffic_anchors() if world_loader != null else []
	var slot_to_actor_id: Dictionary = {}
	var roster: Array = []

	for entry_variant in spawns:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var slot := str(entry.get("slot", "")).strip_edges()
		if slot.is_empty():
			continue
		var actor_id := str(entry.get("id", "")).strip_edges()
		if actor_id.is_empty():
			actor_id = "%s%s" % [ENCOUNTER_ID_PREFIX, slot]
			entry["id"] = actor_id
		slot_to_actor_id[slot] = actor_id

		var loadout: Variant = entry.get("celebrity_loadout", {})
		var template_id := str(entry.get("template_id", ""))
		var has_loadout: bool = typeof(loadout) == TYPE_DICTIONARY and not loadout.is_empty()
		if not has_loadout:
			if template_id.is_empty() or catalog.get_ship_def(template_id) == null:
				continue

		var spawn_pos := _resolve_spawn_position(entry, rng, player_pos, anchors, world_loader)
		entry["position"] = {"x": spawn_pos.x, "y": spawn_pos.y}
		if not entry.has("heading_rad"):
			entry["heading_rad"] = rng.randf() * TAU

		var spawn_facing := float(entry.get("heading_rad", 0.0))
		var actor = null
		if has_loadout:
			actor = TrafficSpawnScript.create_from_celebrity_loadout(
				catalog,
				traffic_config,
				loadout,
				spawn_pos,
				spawn_facing,
				sector_id
			)
		else:
			actor = TrafficSpawnScript.create(
				catalog,
				traffic_config,
				"loiter",
				template_id,
				spawn_pos,
				spawn_facing,
				sector_id
			)
		if actor == null:
			continue
		actor.id = actor_id
		actor.encounter_pinned = true
		_apply_attitude(actor, entry, slot_to_actor_id, traffic_config)
		_apply_transponder_and_callsign(actor, entry, plan)
		roster.append(actor)

	subsystem.write_back_active_plan(plan)
	return roster


static func _resolve_spawn_position(
	entry: Dictionary,
	rng: RandomNumberGenerator,
	player_pos: Vector2,
	anchors: Array,
	world_loader: WorldLoader
) -> Vector2:
	var pos_dict: Variant = entry.get("position", {})
	if typeof(pos_dict) == TYPE_DICTIONARY and pos_dict.has("x") and pos_dict.has("y"):
		return Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0)))

	var offset := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1400.0, 3200.0)
	if anchors.size() > 0:
		var anchor_id := TrafficActorScript.pick_weighted_gate_orbital(anchors, {})
		for anchor_variant in anchors:
			if typeof(anchor_variant) != TYPE_DICTIONARY:
				continue
			var anchor: Dictionary = anchor_variant
			if str(anchor.get("id", "")) == anchor_id:
				return anchor.get("position", Vector2.ZERO) + offset
	if world_loader != null:
		var envelope := world_loader.get_traffic_envelope_radius()
		offset = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(envelope * 0.15, envelope * 0.35)
	return player_pos + offset


static func _apply_attitude(
	actor,
	entry: Dictionary,
	slot_to_actor_id: Dictionary,
	traffic_config: Dictionary
) -> void:
	var attitude := str(entry.get("attitude", "passive"))
	actor.encounter_engagement = ""
	match attitude:
		"hostile_player":
			actor.encounter_engagement = "player"
			actor.ai_state = TrafficActorScript.STATE_ENGAGE
			actor.combat_attitude = TrafficActorScript.CombatAttitude.FIGHT_TO_DEATH
			actor.locked_target_id = TargetLockScript.PLAYER_TARGET_ID
			actor.engage_timer = 9999.0
			actor.begin_combat_pilot()
		"hostile_peer":
			actor.encounter_engagement = "peer"
			var peer_slot := str(entry.get("peer", "")).strip_edges()
			var peer_id := str(slot_to_actor_id.get(peer_slot, ""))
			actor.encounter_peer_slot = peer_slot
			actor.ai_state = TrafficActorScript.STATE_ENGAGE
			actor.combat_attitude = TrafficActorScript.CombatAttitude.FIGHT_TO_DEATH
			actor.engage_timer = 9999.0
			if not peer_id.is_empty():
				actor.locked_target_id = peer_id
			actor.begin_combat_pilot()
		_:
			actor.role = "loiter"
			actor.loiter_center = actor.position


static func _apply_transponder_and_callsign(actor, entry: Dictionary, plan: Dictionary) -> void:
	if actor.owned_ship == null:
		return
	var transponder := bool(entry.get("transponder", false))
	actor.owned_ship.transponder_enabled = transponder
	var callsign := str(entry.get("callsign", "")).strip_edges()
	if callsign.is_empty():
		callsign = str(plan.get("bindings", {}).get("celebrity", "")).strip_edges()
	if not callsign.is_empty():
		actor.callsign = callsign
	var ship_name := str(entry.get("ship_name", "")).strip_edges()
	if ship_name.is_empty():
		ship_name = str(entry.get("celebrity_loadout", {}).get("ship_name", "")).strip_edges()
	if not ship_name.is_empty():
		actor.owned_ship.name = ship_name
	elif not callsign.is_empty():
		actor.owned_ship.name = callsign
