extends FlightSandboxBase

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")

const SPAWN_RING_FRACTION := 0.9
const DEFAULT_OPPONENT_COUNT := 4
const MIN_OPPONENT_COUNT := 1
const MAX_OPPONENT_COUNT := 12

enum DrillState { SETUP, ACTIVE }

var _drill_state: DrillState = DrillState.SETUP
var _nav_radius: float = 15000.0
var _current_pilot_skill: int = -1
var _count_spin: SpinBox
var _drill_actors: Array = []


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
	for actor_variant in _drill_actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		if not actor.is_active():
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

	_build_opponent_roster(opponent_template_id, opponent_count, _nav_radius * SPAWN_RING_FRACTION, attitude_index)
	_flight.install_scripted_roster(_drill_actors, "proxima", _nav_radius, _world)

	_enter_run_ui(player_assembled)
	_drill_state = DrillState.ACTIVE


func _build_opponent_roster(
	template_id: String,
	count: int,
	separation: float,
	attitude_index: int
) -> void:
	_drill_actors.clear()
	var traffic_config := catalog.get_traffic_config()

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

		_drill_actors.append(actor)


func _physics_process(delta: float) -> void:
	if _drill_state != DrillState.ACTIVE:
		return

	_flight.physics_tick(delta, Engine.get_physics_frames())
	_apply_pilot_skill_to_engaged_opponents()


func _apply_pilot_skill_to_engaged_opponents() -> void:
	if _current_pilot_skill < 0:
		return
	for actor_variant in _drill_actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		if actor.ai_state == TrafficActorScript.STATE_ENGAGE:
			_apply_pilot_skill(actor, _current_pilot_skill)


func _end_drill() -> void:
	_clear_drill()
	_return_to_setup_ui()
	_drill_state = DrillState.SETUP


func _clear_drill() -> void:
	_flight.clear_traffic()
	_drill_actors.clear()
	_clear_projectiles([])