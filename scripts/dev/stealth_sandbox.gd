extends FlightSandboxBase

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")

const SPAWN_RING_FRACTION := 0.9
const DEFAULT_OPPONENT_COUNT := 4
const MIN_OPPONENT_COUNT := 1
const MAX_OPPONENT_COUNT := 12

enum DrillState { SETUP, ACTIVE }

var _drill_state: DrillState = DrillState.SETUP
var _opponents: Array = []
var _nav_radius: float = 15000.0
var _current_pilot_skill: int = -1
var _count_spin: SpinBox


func _sandbox_callsign() -> String:
	return "STLX"


func _sandbox_ready_log() -> String:
	return "Stealth sandbox ready."


func _on_sandbox_ready() -> void:
	_count_spin = get_node_or_null(
		"SetupLayer/Root/Panel/Margin/VBox/Footer/CountSpin"
	) as SpinBox
	if _count_spin != null:
		_count_spin.min_value = MIN_OPPONENT_COUNT
		_count_spin.max_value = MAX_OPPONENT_COUNT
		_count_spin.value = DEFAULT_OPPONENT_COUNT
		_count_spin.step = 1


func _is_run_active() -> bool:
	return _drill_state == DrillState.ACTIVE


func _nav_radius_for_hud() -> float:
	return _nav_radius


func _collect_nav_contacts() -> Array:
	var contacts: Array = []
	for entry_variant in _opponents:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var actor = entry.get("actor")
		if actor == null or not actor.is_active():
			continue
		var contact: Dictionary = actor.get_cached_player_contact()
		if not contact.is_empty():
			contacts.append(contact)
	return contacts


func _end_run() -> void:
	_end_drill()


func _on_begin_pressed() -> void:
	var player_template_id := _template_id_at(_player_option)
	var opponent_template_id := _template_id_at(_opponent_option)
	if player_template_id.is_empty() or opponent_template_id.is_empty():
		_status_label.text = "Select player and opponent hulls."
		return

	var count := DEFAULT_OPPONENT_COUNT
	if _count_spin != null:
		count = int(_count_spin.value)

	_begin_drill(
		player_template_id,
		opponent_template_id,
		count,
		_attitude_option.selected,
		_selected_pilot_skill()
	)


func _sensor_range(assembled: AssembledShip) -> float:
	if assembled == null or assembled.sensor_profile.is_empty():
		return float(
			SensorSystem.compute_static_sensor_profile(assembled).get("range", 500.0)
		)
	return float(assembled.sensor_profile.get("range", 500.0))


func _begin_drill(
	player_template_id: String,
	opponent_template_id: String,
	opponent_count: int,
	attitude_index: int,
	pilot_skill: int = -1
) -> void:
	_clear_drill()

	var player_owned := _owned_ship_from_template(player_template_id, "sandbox_player")
	player_owned.transponder_enabled = false
	var player_assembled := _configure_player_for_run(player_owned)

	_nav_radius = _sensor_range(player_assembled)
	_current_pilot_skill = pilot_skill

	_spawn_opponents(
		opponent_template_id,
		opponent_count,
		_nav_radius * SPAWN_RING_FRACTION,
		attitude_index
	)

	_enter_run_ui(player_assembled)
	_drill_state = DrillState.ACTIVE


func _spawn_opponents(
	template_id: String,
	count: int,
	separation: float,
	attitude_index: int
) -> void:
	var traffic_config := catalog.get_traffic_config()
	_traffic_root = _ensure_traffic_root()

	for i in range(count):
		var angle := TAU * float(i) / float(count) + randf_range(-0.08, 0.08)
		var radius := separation + randf_range(-400.0, 400.0)
		var spawn_pos := Vector2.from_angle(angle) * radius
		var spawn_facing := (Vector2.ZERO - spawn_pos).angle()

		var actor = TrafficActorScript.create(
			catalog,
			traffic_config,
			"stealth_sandbox",
			template_id,
			spawn_pos,
			spawn_facing,
			"proxima"
		)
		actor.id = "stealth_%d" % i
		actor.has_sim_slot = true
		actor.near_lod = true
		actor.motion.velocity = Vector2.ZERO
		actor.freeze_traffic_route()
		actor.ai_state = TrafficActorScript.AiState.TRAFFIC
		actor.owned_ship.transponder_enabled = false
		actor.operating_state.transponder_broadcasting = false

		if attitude_index == 0:
			actor.combat_attitude = TrafficActorScript.CombatAttitude.FIGHT_TO_DEATH
		else:
			actor.combat_attitude = TrafficActorScript.CombatAttitude.STANDARD

		var node: Node2D = _spawn_bound_npc(actor, spawn_pos)
		node.visible = false

		_opponents.append({
			"actor": actor,
			"node": node,
			"destroyed_pending": false,
		})


func _physics_process(delta: float) -> void:
	if _drill_state != DrillState.ACTIVE:
		return

	var traffic_config := catalog.get_traffic_config()
	var anchors: Array = []
	var observer_profile := SensorSystem.tick_observer_profile(
		_player.assembled_ship,
		SensorSystem.sensor_effectiveness(_player.assembled_ship, _player.operating_state),
		bool(_player.operating_state.active_systems.get("active_sensors", true))
	)
	var player_signature := SensorSystem.live_signature(
		_player.assembled_ship,
		_player.operating_state
	)
	var player_broadcasting: bool = _player.operating_state.transponder_broadcasting
	var player_reads_beacons: bool = _player.assembled_ship.has_capability("sensor_read_beacons")

	for entry_variant in _opponents:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var actor = entry.get("actor")
		var node: Node2D = entry.get("node")
		if actor == null:
			continue

		if actor.ai_state == TrafficActorScript.STATE_DESTROYED:
			if not bool(entry.get("destroyed_pending", false)):
				entry["destroyed_pending"] = true
				_play_destroyed_or_free(node)
				entry["node"] = null
			continue

		actor.refresh_player_detection(
			_player.global_position,
			observer_profile,
			player_signature,
			player_broadcasting,
			traffic_config,
			player_reads_beacons
		)
		_try_npc_acquire(actor, traffic_config, player_signature, player_broadcasting)
		_apply_detection_visibility(actor, node)

		actor.tick(
			catalog,
			traffic_config,
			delta,
			_player.global_position,
			anchors,
			0.0,
			null,
			_player.motion.velocity,
			_player.motion.facing,
			_player.motion.is_thrusting()
		)

		_sync_npc_node(node, actor)

	_update_hud_nav()


func _try_npc_acquire(
	actor,
	traffic_config: Dictionary,
	player_signature: Dictionary,
	player_broadcasting: bool
) -> void:
	if actor.ai_state != TrafficActorScript.AiState.TRAFFIC:
		return

	var visual_radius := float(traffic_config.get("visual_contact_radius", 250.0))
	var distance: float = actor.position.distance_to(_player.global_position)
	var npc_effectiveness := SensorSystem.sensor_effectiveness(actor.assembled_ship, actor.operating_state)
	var npc_profile := SensorSystem.tick_observer_profile(actor.assembled_ship, npc_effectiveness)
	if not SensorSystem.is_detected(
		distance,
		player_signature,
		player_broadcasting,
		npc_profile,
		visual_radius
	):
		return

	actor.has_player_contact = true
	actor.last_known_player_pos = _player.global_position

	if (
		actor.combat_attitude == TrafficActorScript.CombatAttitude.FIGHT_TO_DEATH
		or actor.should_engage(traffic_config)
	):
		actor.ai_state = TrafficActorScript.STATE_ENGAGE
		if actor.combat_attitude == TrafficActorScript.CombatAttitude.FIGHT_TO_DEATH:
			actor.engage_timer = 9999.0
		else:
			actor.engage_timer = float(traffic_config.get("engage_timeout_seconds", 45.0))
		actor.begin_combat_pilot()
		_apply_pilot_skill(actor, _current_pilot_skill)
	else:
		actor.begin_flee(traffic_config)


func _apply_detection_visibility(actor, node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var visible := bool(actor.player_detected)
	if node.visible != visible:
		node.visible = visible


func _end_drill() -> void:
	_clear_drill()
	_return_to_setup_ui()
	_drill_state = DrillState.SETUP


func _clear_drill() -> void:
	_clear_opponents()
	_clear_projectiles([])


func _clear_opponents() -> void:
	for entry_variant in _opponents:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var node: Node2D = entry.get("node")
		if node != null and is_instance_valid(node):
			node.queue_free()
	_opponents.clear()
	_clear_traffic_root()
