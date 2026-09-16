class_name MenuController
extends RefCounted

const TransponderBroadcastScript := preload("res://scripts/gameplay/transponder_broadcast.gd")

var _main_menu: CanvasLayer
var _new_game: CanvasLayer
var _save_overlay: CanvasLayer
var _pause: CanvasLayer
var _jump: CanvasLayer
var _hud: CanvasLayer
var _ui_root: CanvasLayer
var _player: CharacterBody2D
var _camera: Camera2D
var _catalog: Catalog
var _simulation: Simulation
var _world: WorldController
var _tree: SceneTree
var _main: Node2D
var _current_slot: int = -1
var _save_overlay_source: String = ""
var _on_session_changed: Callable
var _ui_callbacks: Dictionary = {}


func bind(
	main: Node2D,
	main_menu: CanvasLayer,
	new_game: CanvasLayer,
	save_overlay: CanvasLayer,
	pause: CanvasLayer,
	jump: CanvasLayer,
	hud: CanvasLayer,
	ui_root: CanvasLayer,
	player: CharacterBody2D,
	camera: Camera2D,
	catalog: Catalog,
	simulation: Simulation,
	world: WorldController,
	tree: SceneTree,
	on_session_changed: Callable,
	ui_callbacks: Dictionary
) -> void:
	_main = main
	_main_menu = main_menu
	_new_game = new_game
	_save_overlay = save_overlay
	_pause = pause
	_jump = jump
	_hud = hud
	_ui_root = ui_root
	_player = player
	_camera = camera
	_catalog = catalog
	_simulation = simulation
	_world = world
	_tree = tree
	_on_session_changed = on_session_changed
	_ui_callbacks = ui_callbacks


func is_gst_frozen() -> bool:
	if not _main.game_active:
		return true
	if _main_menu.visible or _new_game.visible:
		return true
	if _save_overlay.visible or _jump.visible:
		return true
	if _pause.visible and _tree.paused:
		return true
	return false


func can_toggle_pause() -> bool:
	if not _main.game_active:
		return false
	if _main_menu.visible or _new_game.visible or _save_overlay.visible:
		return false
	if _main.session.docked or _jump.visible or _ui_root.visible:
		return false
	return true


func toggle_pause() -> void:
	if _tree.paused:
		_tree.paused = false
		_pause.close()
	else:
		_tree.paused = true
		_pause.open()


func show_main_menu() -> void:
	_main.game_active = false
	_current_slot = -1
	_tree.paused = false
	_pause.close()
	_ui_root.close_ui()
	_jump.close()
	_new_game.close()
	_save_overlay.close()
	_hud.visible = false
	_player.freeze_motion()
	_world.clear_world()

	var session: GameSession = _main.session
	if session != null:
		unbind_session_events(session)
		if session.changed.is_connected(_on_session_changed):
			session.changed.disconnect(_on_session_changed)

	_main.session = GameSession.new()
	_main.session.changed.connect(_on_session_changed)
	bind_session_events(_main.session)
	_ui_root.configure(
		_catalog,
		_main.session,
		_ui_callbacks.get("ship_changed"),
		_ui_callbacks.get("undock_requested"),
		_ui_callbacks.get("save_requested"),
		_ui_callbacks.get("quit_to_menu")
	)
	_jump.bind(_catalog, _main.session)
	_hud.bind(_main.session, _player, AssembledShip.new())
	_refresh_session_bindings()
	_simulation.reset_save()
	_main_menu.open()


func start_game_from_session() -> void:
	_main.player_ship = _world.assemble_current_ship()
	if _main.player_ship.name.is_empty() and not _main.session.docked:
		push_error("Failed to assemble current player ship.")
		return

	_player.configure(
		_main.player_ship,
		_main.session.get_current_owned_ship(),
		_catalog,
		_main.session
	)
	_refresh_session_bindings()
	_hud.bind(_main.session, _player, _main.player_ship)
	_hud.visible = true
	_main.game_active = true

	_world.load_current_space(false)
	_world.apply_salvage_visuals()
	_on_session_changed.call()

	if _main.session.docked:
		_tree.paused = true
		_pause.close()
		_hud.visible = false
		_ui_root.session = _main.session
		_ui_root.open_habitat()
	else:
		_tree.paused = false
		_ui_root.close_ui()

	if _main.session.in_unspace:
		_simulation.reset_unspace_pulse()


func begin_new_game(callsign: String, background_id: String, portrait_path: String) -> void:
	var session: GameSession = _main.session
	if session != null:
		unbind_session_events(session)
		if session.changed.is_connected(_on_session_changed):
			session.changed.disconnect(_on_session_changed)

	_main.session = GameSession.new()
	_main.session.changed.connect(_on_session_changed)
	bind_session_events(_main.session)

	if not _main.session.start_new_game(_catalog, callsign, background_id, portrait_path):
		push_error("Failed to start new game.")
		return

	_simulation.reset_save()
	_current_slot = -1
	_main_menu.close()
	_new_game.close()
	_ui_root.session = _main.session
	_jump.bind(_catalog, _main.session)
	_hud.bind(_main.session, _player, AssembledShip.new())
	_refresh_session_bindings()
	start_game_from_session()


func load_slot(slot_index: int) -> void:
	var data := SaveStore.read_slot(slot_index)
	if data.is_empty():
		push_error("Failed to read save slot %d." % slot_index)
		return

	var new_session := GameSession.new()
	if not new_session.from_save(_catalog, data):
		push_error("Failed to load save slot %d." % slot_index)
		return

	_simulation.apply_save(data.get("subsystems", {}))

	var session: GameSession = _main.session
	if session != null:
		unbind_session_events(session)
		if session.changed.is_connected(_on_session_changed):
			session.changed.disconnect(_on_session_changed)

	_main.session = new_session
	_main.session.changed.connect(_on_session_changed)
	bind_session_events(_main.session)
	_ui_root.configure(
		_catalog,
		_main.session,
		_ui_callbacks.get("ship_changed"),
		_ui_callbacks.get("undock_requested"),
		_ui_callbacks.get("save_requested"),
		_ui_callbacks.get("quit_to_menu")
	)
	_jump.bind(_catalog, _main.session)
	_hud.bind(_main.session, _player, AssembledShip.new())
	_refresh_session_bindings()

	_current_slot = slot_index
	_main_menu.close()
	_new_game.close()
	_save_overlay.close()
	_pause.close()
	start_game_from_session()

	var flight: Dictionary = data.get("flight", {})
	_world.apply_flight_state(flight)


func save_to_slot(slot_index: int) -> bool:
	if not _main.game_active:
		return false

	var flight := _world.capture_flight_state()
	var save_data := SaveStore.build_save_data(
		_main.session.player_to_dict(),
		_main.session.to_dict(),
		_main.session.ships_to_array(),
		flight,
		_simulation.collect_save()
	)
	if not SaveStore.write_slot(slot_index, save_data):
		return false

	_current_slot = slot_index
	_main.session.last_log = "Game saved to slot %d." % slot_index
	_main.session.changed.emit()
	return true


func on_pause_resume_requested() -> void:
	_tree.paused = false
	_pause.close()


func on_pause_save_requested() -> void:
	_save_overlay_source = "pause"
	_pause.close()
	_tree.paused = true
	_save_overlay.open(_save_overlay.Mode.SAVE)


func on_pause_load_requested() -> void:
	_save_overlay_source = "pause"
	_pause.close()
	_tree.paused = true
	_save_overlay.open(_save_overlay.Mode.LOAD)


func on_main_menu_new_game() -> void:
	var default_callsign := TransponderBroadcastScript.generate_independent_callsign(
		_catalog.get_traffic_config()
	)
	_new_game.bind(_catalog)
	_new_game.open(default_callsign)


func on_main_menu_load() -> void:
	_save_overlay_source = "menu"
	_save_overlay.open(_save_overlay.Mode.LOAD)


func on_main_menu_exit() -> void:
	_tree.quit()


func on_new_game_confirmed(callsign: String, background_id: String, portrait_path: String) -> void:
	begin_new_game(callsign, background_id, portrait_path)


func on_new_game_cancelled() -> void:
	_new_game.close()


func on_save_slot_chosen(slot_index: int) -> void:
	if _save_overlay.is_save_mode():
		if save_to_slot(slot_index):
			_save_overlay.close()
			if _save_overlay_source == "pause":
				_pause.open()
			_on_session_changed.call()
	else:
		load_slot(slot_index)


func on_save_overlay_cancelled() -> void:
	_save_overlay.close()
	if _save_overlay_source == "pause" and _main.game_active and not _main.session.docked:
		_pause.open()
	elif _save_overlay_source == "menu" and not _main.game_active:
		_main_menu.open()


func on_quit_to_menu_requested() -> void:
	_tree.paused = false
	show_main_menu()


func on_ui_save_requested() -> void:
	_save_overlay_source = "habitat"
	_tree.paused = true
	_save_overlay.open(_save_overlay.Mode.SAVE)


func _refresh_session_bindings() -> void:
	if _camera != null and _camera.has_method("bind_session"):
		_camera.bind_session(_main.session)


func bind_session_events(game_session: GameSession) -> void:
	if game_session == null:
		return
	game_session.events.subscribe_all(_forward_session_event)


func unbind_session_events(game_session: GameSession) -> void:
	if game_session == null:
		return
	game_session.events.unsubscribe_all(_forward_session_event)


func _forward_session_event(evt: Dictionary) -> void:
	if _simulation == null:
		return
	_simulation.dispatch_event(_main.session, _catalog, evt)
