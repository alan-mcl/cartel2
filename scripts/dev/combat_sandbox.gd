extends FlightSandboxBase

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")

const NPC_MIN_WEAPON_RANGE := 800.0
const ENGAGEMENT_MARGIN := 80.0
const NAV_RADIUS := 3000.0

enum BoutState { SETUP, FIGHTING }

var _bout_state: BoutState = BoutState.SETUP
var _opponent_actor = null
var _opponent_node: Node2D = null
var _destroyed_pending: bool = false


func _sandbox_callsign() -> String:
	return "SBX"


func _sandbox_ready_log() -> String:
	return "Combat sandbox ready."


func _is_run_active() -> bool:
	return _bout_state == BoutState.FIGHTING


func _nav_radius_for_hud() -> float:
	return NAV_RADIUS


func _collect_nav_contacts() -> Array:
	var contacts: Array = []
	if _opponent_actor != null and _opponent_actor.is_active():
		var contact: Dictionary = _opponent_actor.get_cached_player_contact()
		if not contact.is_empty():
			contacts.append(contact)
	return contacts


func _end_run() -> void:
	_end_bout()


func _on_begin_pressed() -> void:
	var player_template_id := _template_id_at(_player_option)
	var opponent_template_id := _template_id_at(_opponent_option)
	if player_template_id.is_empty() or opponent_template_id.is_empty():
		_status_label.text = "Select player and opponent hulls."
		return

	_begin_bout(
		player_template_id,
		opponent_template_id,
		_attitude_option.selected,
		_selected_pilot_skill()
	)


func _engagement_separation(player_assembled: AssembledShip, opponent_assembled: AssembledShip) -> float:
	return (
		maxf(
			maxf(
				ShipWeapons.max_module_range(player_assembled),
				ShipWeapons.max_module_range(opponent_assembled)
			),
			NPC_MIN_WEAPON_RANGE
		)
		+ ENGAGEMENT_MARGIN
	)


func _begin_bout(
	player_template_id: String,
	opponent_template_id: String,
	attitude_index: int,
	pilot_skill: int = -1
) -> void:
	_clear_bout()

	var player_owned := _owned_ship_from_template(player_template_id, "sandbox_player")
	var player_assembled := _configure_player_for_run(player_owned)

	var opponent_assembled := ShipAssembler.assemble_owned(
		catalog,
		_owned_ship_from_template(opponent_template_id, "sandbox_opponent")
	)
	var separation := _engagement_separation(player_assembled, opponent_assembled)

	_spawn_opponent(opponent_template_id, separation, attitude_index, pilot_skill)

	_enter_run_ui(player_assembled)
	_bout_state = BoutState.FIGHTING
	_destroyed_pending = false


func _spawn_opponent(
	template_id: String,
	separation: float,
	attitude_index: int,
	pilot_skill: int = -1
) -> void:
	var traffic_config := catalog.get_traffic_config()
	var spawn_pos := Vector2(separation, 0.0)
	var spawn_facing := PI

	_opponent_actor = TrafficActorScript.create(
		catalog,
		traffic_config,
		"combat_sandbox",
		template_id,
		spawn_pos,
		spawn_facing,
		"proxima"
	)
	_opponent_actor.has_sim_slot = true
	_opponent_actor.near_lod = true
	_opponent_actor.motion.velocity = Vector2.ZERO
	_opponent_actor.freeze_traffic_route()

	if attitude_index == 0:
		_opponent_actor.combat_attitude = TrafficActorScript.CombatAttitude.FIGHT_TO_DEATH
		_opponent_actor.ai_state = TrafficActorScript.STATE_ENGAGE
		_opponent_actor.engage_timer = 9999.0
		_opponent_actor.begin_combat_pilot()
		_apply_pilot_skill(_opponent_actor, pilot_skill)
	else:
		_opponent_actor.combat_attitude = TrafficActorScript.CombatAttitude.STANDARD
		_opponent_actor.ai_state = TrafficActorScript.AiState.TRAFFIC

	_opponent_node = _spawn_bound_npc(_opponent_actor, spawn_pos)


func _physics_process(delta: float) -> void:
	if _bout_state != BoutState.FIGHTING:
		return

	if _opponent_actor == null:
		_update_hud_nav()
		return

	if _opponent_actor.ai_state == TrafficActorScript.STATE_DESTROYED:
		if not _destroyed_pending:
			_destroyed_pending = true
			_play_destroyed_or_free(_opponent_node)
			_opponent_node = null
		_update_hud_nav()
		return

	var traffic_config := catalog.get_traffic_config()
	var anchors: Array = []
	var observer_profile := SensorSystem.sensor_profile(
		_player.assembled_ship,
		_player.operating_state
	)
	var player_signature := SensorSystem.live_signature(
		_player.assembled_ship,
		_player.operating_state
	)
	var player_broadcasting: bool = _player.operating_state.transponder_broadcasting
	_opponent_actor.refresh_player_detection(
		_player.global_position,
		observer_profile,
		player_signature,
		player_broadcasting,
		traffic_config,
		_player.assembled_ship.has_capability("sensor_read_beacons")
	)
	_opponent_actor.tick(
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

	_sync_npc_node(_opponent_node, _opponent_actor)
	_update_hud_nav()


func _end_bout() -> void:
	_clear_bout()
	_return_to_setup_ui()
	_bout_state = BoutState.SETUP


func _clear_bout() -> void:
	_clear_opponent()
	_clear_projectiles([_opponent_node] if _opponent_node != null else [])
	_destroyed_pending = false


func _clear_opponent() -> void:
	if _opponent_node != null and is_instance_valid(_opponent_node):
		_opponent_node.queue_free()
	_opponent_node = null
	_opponent_actor = null
	_clear_traffic_root()
