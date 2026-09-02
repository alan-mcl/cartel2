extends Node2D

var session := PrototypeSession.new()
var catalog := Catalog.load_default()
var player_ship: AssembledShip
var play_bounds: float = 3500.0

var _world_loader := WorldLoader.new()
var _translate_gate_title: String = ""
var _current_slot: int = -1
var _game_active: bool = false
var _save_overlay_source: String = ""

const UNSPACE_TINT := Color(0.78, 0.58, 1.0, 1.0)

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

	session.changed.connect(_on_session_changed)
	_player.interaction_target_changed.connect(_on_interaction_target_changed)
	_player.motion_changed.connect(_on_motion_changed)

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


func _physics_process(_delta: float) -> void:
	if not _game_active or session.docked or _jump.visible:
		return

	var distance := _player.global_position.length()
	_hud.set_boundary_warning(distance > play_bounds, session.in_unspace)


func _unhandled_input(event: InputEvent) -> void:
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


func try_interact(target: Interactable) -> void:
	if not _game_active or target == null or target.definition == null:
		return

	match target.definition.kind:
		InteractableDef.Kind.DOCK:
			_dock_at(target.definition.dock_location_id)
		InteractableDef.Kind.TRANSLATE:
			if not session.in_unspace:
				_open_jump_overlay(target.definition.title)
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
	session = PrototypeSession.new()
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
	if player_ship.name.is_empty():
		push_error("Failed to assemble current player ship.")
		return

	_player.configure(player_ship)
	_hud.set_assembled_ship(player_ship)
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


func _begin_new_game(player_name: String, callsign: String) -> void:
	session = PrototypeSession.new()
	session.changed.connect(_on_session_changed)

	if not session.start_new_game(catalog, player_name, callsign):
		push_error("Failed to start new game.")
		return

	_current_slot = -1
	_main_menu.close()
	_new_game.close()
	_ui_root.session = session
	_start_game_from_session()


func _load_slot(slot_index: int) -> void:
	var data := SaveStore.read_slot(slot_index)
	if data.is_empty():
		push_error("Failed to read save slot %d." % slot_index)
		return

	var new_session := PrototypeSession.new()
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
		session.player_name,
		session.callsign,
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
			_player.global_position = session.get_spawn_position(catalog)
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
	for child in _world.get_children():
		child.queue_free()


func _load_current_space(place_player: bool = true) -> void:
	if session.in_unspace:
		_load_unspace(place_player)
	else:
		_load_current_sector(place_player)


func _load_current_sector(place_player: bool = true) -> void:
	play_bounds = _world_loader.load_sector(_world, catalog, session, session.sector_id)
	_starfield.reset_tint()
	_finalize_world_load(place_player)


func _load_unspace(place_player: bool = true) -> void:
	play_bounds = _world_loader.load_unspace(_world, catalog, session, session.unspace_world_id)
	if _starfield.has_method("set_tint"):
		_starfield.set_tint(UNSPACE_TINT)
	_finalize_world_load(place_player)


func _finalize_world_load(place_player: bool = true) -> void:
	if _player.has_method("register_world_interactables"):
		_player.register_world_interactables()
	if place_player:
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

	if not session.enter_unspace(catalog, target_sector_id, n, player_ship):
		return

	_load_unspace(true)
	_jump.close()
	get_tree().paused = false
	_on_session_changed()
	_on_interaction_target_changed(_player.get_current_target())


func _arrive_from_unspace() -> void:
	if not session.in_unspace:
		return

	if not session.arrive_from_unspace(catalog):
		return

	_load_current_sector(true)
	_on_session_changed()
	_on_interaction_target_changed(_player.get_current_target())


func _on_jump_cancelled() -> void:
	get_tree().paused = false
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


func _on_ui_undock_requested(ship_id: String) -> void:
	if ship_id.is_empty() or not session.docked:
		return

	if not session.undock(catalog, ship_id):
		return

	player_ship = _assemble_current_ship()
	_player.configure(player_ship)
	_player.freeze_motion()
	_hud.set_assembled_ship(player_ship)

	get_tree().paused = false
	_ui_root.close_ui()
	_hud.visible = true
	_pause.close()
	_on_session_changed()
	_on_interaction_target_changed(_player.get_current_target())


func _on_ui_ship_changed(ship_id: String) -> void:
	if ship_id != session.current_ship_id:
		return
	player_ship = _assemble_current_ship()
	_player.configure(player_ship)
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
	_new_game.open()


func _on_main_menu_load() -> void:
	_save_overlay_source = "menu"
	_save_overlay.open(_save_overlay.Mode.LOAD)


func _on_main_menu_exit() -> void:
	get_tree().quit()


func _on_new_game_confirmed(player_name: String, callsign: String) -> void:
	_begin_new_game(player_name, callsign)


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


func _on_interaction_target_changed(target: Interactable) -> void:
	_hud.set_target(target)


func _on_motion_changed(speed: float, heading_deg: float, boosting: bool) -> void:
	_hud.set_motion(speed, heading_deg, boosting)
