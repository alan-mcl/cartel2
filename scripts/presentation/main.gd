extends Node2D

const TrafficDirectorScript := preload("res://scripts/gameplay/traffic_director.gd")
const TransponderBroadcastScript := preload("res://scripts/gameplay/transponder_broadcast.gd")

var session := GameSession.new()
var catalog := Catalog.load_default()
var player_ship: AssembledShip
var play_bounds: float = 3500.0

var _game_clock := GameClock.new()
var _world_loader := WorldLoader.new()
var _traffic_director = null
var _translate_gate_title: String = ""
var _current_slot: int = -1
var _game_active: bool = false
var _save_overlay_source: String = ""

const UNSPACE_TINT := Color(0.1, 0.08, 0.14, 1.0)

@onready var _world: Node2D = $World
@onready var _player: CharacterBody2D = $PlayerShip
@onready var _hud: CanvasLayer = $HUD
@onready var _pause: CanvasLayer = $PauseOverlay
@onready var _jump: CanvasLayer = $JumpOverlay
@onready var _ui_root: CanvasLayer = $UiRoot
@onready var _main_menu: CanvasLayer = $MainMenu
@onready var _new_game: CanvasLayer = $NewGameOverlay
@onready var _save_overlay: CanvasLayer = $SaveOverlay
@onready var _starfield: Node2D = $Starfield
@onready var _camera: Camera2D = $PlayerShip/FollowCamera


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE

	session.changed.connect(_on_session_changed)
	_player.interaction_target_changed.connect(_on_interaction_target_changed)
	_player.motion_changed.connect(_on_motion_changed)
	_player.operating_state_changed.connect(_on_operating_state_changed)

	if _starfield.has_method("bind_camera"):
		_starfield.bind_camera(_camera)

	_hud.bind(session, _player, AssembledShip.new())

	_ui_root.configure(
		catalog,
		session,
		_on_ui_ship_changed,
		_on_ui_undock_requested,
		_on_ui_save_requested,
		_on_quit_to_menu_requested
	)

	_jump.bind(catalog, session)
	_jump.jump_requested.connect(_on_jump_requested)
	_jump.cancelled.connect(_on_jump_cancelled)

	_pause.resume_requested.connect(_on_pause_resume_requested)
	_pause.save_requested.connect(_on_pause_save_requested)
	_pause.load_requested.connect(_on_pause_load_requested)
	_pause.quit_to_menu_requested.connect(_on_quit_to_menu_requested)

	_main_menu.new_game_requested.connect(_on_main_menu_new_game)
	_main_menu.load_requested.connect(_on_main_menu_load)
	_main_menu.exit_requested.connect(_on_main_menu_exit)

	_new_game.confirmed.connect(_on_new_game_confirmed)
	_new_game.cancelled.connect(_on_new_game_cancelled)

	_save_overlay.slot_chosen.connect(_on_save_slot_chosen)
	_save_overlay.cancelled.connect(_on_save_overlay_cancelled)

	_player.freeze_motion()
	_pause.visible = false
	_jump.visible = false
	_hud.visible = false
	_new_game.close()
	_save_overlay.close()

	_show_main_menu()


func _process(delta: float) -> void:
	if _game_clock == null:
		return
	_game_clock.tick(session, catalog, delta, _is_gst_frozen())


func _is_gst_frozen() -> bool:
	if not _game_active:
		return true
	if _main_menu.visible or _new_game.visible:
		return true
	if _save_overlay.visible or _jump.visible:
		return true
	if _pause.visible and get_tree().paused:
		return true
	return false


func _ensure_traffic_director() -> void:
	if _traffic_director != null:
		return
	_traffic_director = TrafficDirectorScript.new()


func _physics_process(delta: float) -> void:
	if not _game_active or session.docked or _jump.visible or get_tree().paused:
		return

	if not session.in_unspace:
		_ensure_traffic_director()
		if _traffic_director != null:
			var player_broadcasting: bool = (
				_player.operating_state.transponder_broadcasting
				if _player.assembled_ship != null
				else false
			)
			_traffic_director.tick(
				delta,
				_player.global_position,
				_world_loader,
				_player.motion.velocity,
				_player.motion.facing,
				_player.motion.is_thrusting(),
				_player.assembled_ship,
				_player.operating_state,
				player_broadcasting
			)

	var contacts := _world_loader.get_nav_contacts(catalog, session.in_unspace)
	if session.in_unspace and not player_ship.has_capability("4_space_topology"):
		contacts = _filter_topology_contacts(contacts)
	if not session.in_unspace and _traffic_director != null:
		contacts.append_array(_traffic_director.get_traffic_contacts())

	var nav_radius := play_bounds
	if not session.in_unspace:
		nav_radius = _world_loader.get_content_radius()

	var owned := session.get_current_owned_ship()
	var player_broadcast: Dictionary = TransponderBroadcastScript.player_broadcast(
		owned.registration if owned != null else "",
		session.callsign,
		owned.name if owned != null else ""
	)
	_hud.set_nav_state(
		nav_radius,
		_player.global_position,
		rad_to_deg(_player.motion.facing),
		contacts,
		_camera,
		player_broadcast
	)
	var player_signature := SensorSystem.live_signature(
		_player.assembled_ship,
		_player.operating_state
	)
	var transponder_label := "off"
	if _player.operating_state.transponder_broadcasting:
		transponder_label = "on"
	var active_sensors_label := _active_sensors_hud_label(_player.assembled_ship, _player.operating_state)
	_hud.set_signature_state(player_signature, transponder_label, active_sensors_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_active_sensors"):
		if _can_toggle_active_sensors():
			_toggle_active_sensors()
			return
	if event.is_action_pressed("pause"):
		if _ui_root.visible and _ui_root.handle_back():
			return
		if _can_toggle_pause():
			_toggle_pause()


func _can_toggle_pause() -> bool:
	if not _game_active:
		return false
	if _main_menu.visible or _new_game.visible or _save_overlay.visible:
		return false
	if session.docked or _jump.visible or _ui_root.visible:
		return false
	return true


func _can_toggle_active_sensors() -> bool:
	if not _game_active or session.docked or _jump.visible or _ui_root.visible:
		return false
	if get_tree().paused:
		return false
	if _player.assembled_ship == null:
		return false
	return _player.assembled_ship.has_active_sensor_package()


func _toggle_active_sensors() -> void:
	var owned := session.get_current_owned_ship()
	if owned == null:
		return
	owned.active_sensors_enabled = not owned.active_sensors_enabled
	session.changed.emit()


func _active_sensors_hud_label(assembled: AssembledShip, state: ShipOperatingState) -> String:
	if assembled == null or not assembled.has_active_sensor_package():
		return ""
	if state == null:
		return "off"
	return "on" if bool(state.active_systems.get("active_sensors", false)) else "off"


func try_interact(target: Interactable) -> void:
	if not _game_active or target == null or target.definition == null:
		return

	match target.definition.kind:
		InteractableDef.Kind.DOCK:
			_dock_at(target.definition.dock_location_id)
		InteractableDef.Kind.TRANSLATE:
			if not session.in_unspace:
				_open_jump_overlay(target.get_title())
		InteractableDef.Kind.ARRIVE:
			_arrive_from_unspace()
		_:
			var result := target.interact(session)
			if result.is_empty():
				return
			_on_session_changed()
			_on_interaction_target_changed(_player.get_current_target())
			_world_loader.apply_salvage_visuals(session)


func _show_main_menu() -> void:
	_game_active = false
	_current_slot = -1
	get_tree().paused = false
	_pause.close()
	_ui_root.close_ui()
	_jump.close()
	_new_game.close()
	_save_overlay.close()
	_hud.visible = false
	_player.freeze_motion()
	_clear_world()

	if session != null and session.changed.is_connected(_on_session_changed):
		session.changed.disconnect(_on_session_changed)
	session = GameSession.new()
	session.changed.connect(_on_session_changed)
	_ui_root.configure(
		catalog,
		session,
		_on_ui_ship_changed,
		_on_ui_undock_requested,
		_on_ui_save_requested,
		_on_quit_to_menu_requested
	)
	_jump.bind(catalog, session)
	_hud.bind(session, _player, AssembledShip.new())

	_main_menu.open()


func _start_game_from_session() -> void:
	player_ship = _assemble_current_ship()
	if player_ship.name.is_empty() and not session.docked:
		push_error("Failed to assemble current player ship.")
		return

	_player.configure(player_ship, session.get_current_owned_ship(), catalog)
	_hud.bind(session, _player, player_ship)
	_hud.visible = true
	_game_active = true

	_load_current_space(false)
	_world_loader.apply_salvage_visuals(session)
	_on_session_changed()

	if session.docked:
		get_tree().paused = true
		_pause.close()
		_hud.visible = false
		_ui_root.session = session
		_ui_root.open_habitat()
	else:
		get_tree().paused = false
		_ui_root.close_ui()

	if session.in_unspace:
		_game_clock.reset_unspace_pulse()


func _begin_new_game(callsign: String, background_id: String, portrait_path: String) -> void:
	session = GameSession.new()
	session.changed.connect(_on_session_changed)

	if not session.start_new_game(catalog, callsign, background_id, portrait_path):
		push_error("Failed to start new game.")
		return

	_current_slot = -1
	_main_menu.close()
	_new_game.close()
	_ui_root.session = session
	_jump.bind(catalog, session)
	_hud.bind(session, _player, AssembledShip.new())
	_start_game_from_session()


func _load_slot(slot_index: int) -> void:
	var data := SaveStore.read_slot(slot_index)
	if data.is_empty():
		push_error("Failed to read save slot %d." % slot_index)
		return

	var new_session := GameSession.new()
	if not new_session.from_save(catalog, data):
		push_error("Failed to load save slot %d." % slot_index)
		return

	if session != null and session.changed.is_connected(_on_session_changed):
		session.changed.disconnect(_on_session_changed)

	session = new_session
	session.changed.connect(_on_session_changed)
	_ui_root.configure(
		catalog,
		session,
		_on_ui_ship_changed,
		_on_ui_undock_requested,
		_on_ui_save_requested,
		_on_quit_to_menu_requested
	)
	_jump.bind(catalog, session)
	_hud.bind(session, _player, AssembledShip.new())

	_current_slot = slot_index
	_main_menu.close()
	_new_game.close()
	_save_overlay.close()
	_pause.close()
	_start_game_from_session()

	var flight: Dictionary = data.get("flight", {})
	_apply_flight_state(flight)


func _save_to_slot(slot_index: int) -> bool:
	if not _game_active:
		return false

	var flight := _capture_flight_state()
	var save_data := SaveStore.build_save_data(
		session.player_to_dict(),
		session.to_dict(),
		session.ships_to_array(),
		flight
	)
	if not SaveStore.write_slot(slot_index, save_data):
		return false

	_current_slot = slot_index
	session.last_log = "Game saved to slot %d." % slot_index
	session.changed.emit()
	return true


func _capture_flight_state() -> Dictionary:
	return {
		"x": _player.global_position.x,
		"y": _player.global_position.y,
		"vx": _player.motion.velocity.x,
		"vy": _player.motion.velocity.y,
		"facing": _player.motion.facing,
	}


func _apply_flight_state(flight: Dictionary) -> void:
	if typeof(flight) != TYPE_DICTIONARY or flight.is_empty():
		if not session.docked:
			if session.in_unspace:
				_player.global_position = session.get_spawn_position(catalog)
			else:
				_player.global_position = _world_loader.get_habitat_launch_position()
		_player.freeze_motion()
		return

	_player.global_position = Vector2(
		float(flight.get("x", 0.0)),
		float(flight.get("y", 0.0))
	)
	_player.motion.velocity = Vector2(
		float(flight.get("vx", 0.0)),
		float(flight.get("vy", 0.0))
	)
	_player.motion.facing = float(flight.get("facing", -PI / 2.0))
	_player.velocity = _player.motion.velocity

	if session.docked:
		_player.freeze_motion()


func _clear_world() -> void:
	if _traffic_director != null:
		_traffic_director.clear()
	for child in _world.get_children():
		child.queue_free()


func _load_current_space(place_player: bool = true) -> void:
	if session.in_unspace:
		_load_unspace(place_player)
	else:
		_load_current_sector(place_player)


func _load_current_sector(place_player: bool = true, spawn_near: String = "") -> void:
	play_bounds = _world_loader.load_sector(_world, catalog, session, session.sector_id)
	if _starfield.has_method("set_unspace_mode"):
		_starfield.set_unspace_mode(false)
	else:
		_starfield.reset_tint()
	_finalize_world_load(place_player, spawn_near)


func _load_unspace(place_player: bool = true) -> void:
	play_bounds = _world_loader.load_unspace(_world, catalog, session, session.unspace_world_id)
	if _starfield.has_method("set_unspace_mode"):
		_starfield.set_unspace_mode(true)
	elif _starfield.has_method("set_tint"):
		_starfield.set_tint(UNSPACE_TINT)
	_finalize_world_load(place_player)


func _filter_topology_contacts(contacts: Array) -> Array:
	var filtered: Array = []
	for contact_variant in contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if str(contact.get("id", "")) == "exit_portal":
			continue
		filtered.append(contact)
	return filtered


func _finalize_world_load(place_player: bool = true, spawn_near: String = "") -> void:
	if _player.has_method("register_world_interactables"):
		_player.register_world_interactables()

	if _traffic_director != null:
		_traffic_director.clear()
	if not session.in_unspace:
		_ensure_traffic_director()
		if _traffic_director != null:
			_traffic_director.setup(
				catalog,
				_world,
				session.sector_id,
				_world_loader.get_traffic_envelope_radius(),
				_player.global_position,
				_world_loader
			)

	if place_player:
		match spawn_near:
			"habitat":
				_player.global_position = _world_loader.get_habitat_launch_position()
			"jump_gate":
				_player.global_position = _world_loader.get_jump_gate_approach_position()
			_:
				_player.global_position = session.get_spawn_position(catalog)
		_player.freeze_motion()


func _open_jump_overlay(gate_title: String) -> void:
	if session.docked or session.in_unspace:
		return

	_translate_gate_title = gate_title
	get_tree().paused = true
	_pause.close()
	_jump.open(gate_title)
	_on_interaction_target_changed(_player.get_current_target())


func _on_jump_requested(target_sector_id: String, n: int) -> void:
	if target_sector_id.is_empty():
		return

	var origin_id := session.sector_id
	if not session.enter_unspace(catalog, target_sector_id, n, player_ship):
		return

	var mapping := catalog.get_mapping(origin_id, target_sector_id, n)
	var applied := _game_clock.apply_mapping_lump(session, mapping, "entry_seconds", catalog)
	if applied > 0.0:
		session.last_log = (
			"Translated into %d-space. Entry lag: %s GST."
			% [n, GalacticCalendar.format_duration(applied)]
		)
	_game_clock.reset_unspace_pulse()

	_load_unspace(true)
	_jump.close()
	get_tree().paused = false
	_on_session_changed()
	_on_interaction_target_changed(_player.get_current_target())


func _arrive_from_unspace() -> void:
	if not session.in_unspace:
		return

	var origin_id := session.sector_id
	var dest_id := session.pending_destination_id
	var n := session.unspace_n

	if not session.arrive_from_unspace(catalog):
		return

	var mapping := catalog.get_mapping(origin_id, dest_id, n)
	var applied := _game_clock.apply_mapping_lump(session, mapping, "exit_seconds", catalog)
	if applied > 0.0:
		session.last_log = (
			"Emergence complete. Exit lag: %s GST."
			% GalacticCalendar.format_duration(applied)
		)

	_load_current_sector(true, "jump_gate")
	_on_session_changed()
	_on_interaction_target_changed(_player.get_current_target())


func _dock_at(location_id: String) -> void:
	if location_id.is_empty() or session.docked:
		return

	if not session.dock(catalog, location_id):
		return

	_player.freeze_motion()
	get_tree().paused = true
	_pause.close()
	_hud.visible = false
	_ui_root.session = session
	_ui_root.open_habitat()
	_on_session_changed()
	_on_interaction_target_changed(_player.get_current_target())


func _on_jump_cancelled() -> void:
	get_tree().paused = false
	_on_interaction_target_changed(_player.get_current_target())


func _on_ui_undock_requested(ship_id: String) -> void:
	if ship_id.is_empty() or not session.docked:
		return

	if not session.undock(catalog, ship_id):
		return

	player_ship = _assemble_current_ship()
	_player.configure(player_ship, session.get_current_owned_ship(), catalog)
	_hud.bind(session, _player, player_ship)

	var launch_pos := _world_loader.get_habitat_launch_position()
	var habitat_pos := _world_loader.get_habitat_world_position()
	var outward := (launch_pos - habitat_pos).normalized()
	if outward.length_squared() < 0.001:
		outward = Vector2.UP

	get_tree().paused = false
	_ui_root.close_ui()
	_hud.visible = true
	_pause.close()
	_on_session_changed()

	_player.global_position = launch_pos
	_player.apply_launch_velocity(_world_loader.get_undock_exit_velocity(), outward.angle())
	_on_interaction_target_changed(_player.get_current_target())


func _on_ui_ship_changed(ship_id: String) -> void:
	if ship_id != session.current_ship_id:
		return
	player_ship = _assemble_current_ship()
	_player.configure(player_ship, session.get_current_owned_ship(), catalog)
	_hud.set_assembled_ship(player_ship)


func _on_ui_save_requested() -> void:
	_save_overlay_source = "habitat"
	get_tree().paused = true
	_save_overlay.open(_save_overlay.Mode.SAVE)


func _assemble_current_ship() -> AssembledShip:
	var owned := session.get_current_owned_ship()
	if owned == null:
		return AssembledShip.new()
	return ShipAssembler.assemble_owned(catalog, owned)


func _toggle_pause() -> void:
	if get_tree().paused:
		get_tree().paused = false
		_pause.close()
	else:
		get_tree().paused = true
		_pause.open()


func _on_pause_resume_requested() -> void:
	get_tree().paused = false
	_pause.close()


func _on_pause_save_requested() -> void:
	_save_overlay_source = "pause"
	_pause.close()
	get_tree().paused = true
	_save_overlay.open(_save_overlay.Mode.SAVE)


func _on_pause_load_requested() -> void:
	_save_overlay_source = "pause"
	_pause.close()
	get_tree().paused = true
	_save_overlay.open(_save_overlay.Mode.LOAD)


func _on_main_menu_new_game() -> void:
	var default_callsign := TransponderBroadcastScript.generate_independent_callsign(
		catalog.get_traffic_config()
	)
	_new_game.bind(catalog)
	_new_game.open(default_callsign)


func _on_main_menu_load() -> void:
	_save_overlay_source = "menu"
	_save_overlay.open(_save_overlay.Mode.LOAD)


func _on_main_menu_exit() -> void:
	get_tree().quit()


func _on_new_game_confirmed(callsign: String, background_id: String, portrait_path: String) -> void:
	_begin_new_game(callsign, background_id, portrait_path)


func _on_new_game_cancelled() -> void:
	_new_game.close()


func _on_save_slot_chosen(slot_index: int) -> void:
	if _save_overlay.is_save_mode():
		if _save_to_slot(slot_index):
			_save_overlay.close()
			if _save_overlay_source == "pause":
				_pause.open()
			_on_session_changed()
	else:
		_load_slot(slot_index)


func _on_save_overlay_cancelled() -> void:
	_save_overlay.close()
	if _save_overlay_source == "pause" and _game_active and not session.docked:
		_pause.open()
	elif _save_overlay_source == "menu" and not _game_active:
		_main_menu.open()


func _on_quit_to_menu_requested() -> void:
	get_tree().paused = false
	_show_main_menu()


func _on_session_changed() -> void:
	_hud.refresh()


func _on_interaction_target_changed(_target: Interactable) -> void:
	pass


func _on_motion_changed(speed: float, heading_deg: float, boosting: bool) -> void:
	_hud.set_motion(speed, heading_deg, boosting)


func _on_operating_state_changed(state: ShipOperatingState) -> void:
	_hud.set_operating_state(state)
	if _player.assembled_ship != null:
		var signature := SensorSystem.live_signature(_player.assembled_ship, state)
		var transponder_label := "on" if state.transponder_broadcasting else "off"
		var active_sensors_label := _active_sensors_hud_label(_player.assembled_ship, state)
		_hud.set_signature_state(signature, transponder_label, active_sensors_label)
