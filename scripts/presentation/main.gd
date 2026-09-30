extends Node2D

var session := GameSession.new()
var catalog := Catalog.load_default()
var player_ship: AssembledShip
var play_bounds: float = 3500.0
var game_active: bool = false

var _simulation := Simulation.new()
var _flight := FlightLoopController.new()
var _world := WorldController.new()
var _menu := MenuController.new()

@onready var _world_node: Node2D = $World
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
	_world_node.process_mode = Node.PROCESS_MODE_PAUSABLE

	session.changed.connect(_on_session_changed)
	_player.interaction_target_changed.connect(_on_interaction_target_changed)
	_player.motion_changed.connect(_on_motion_changed)
	_player.operating_state_changed.connect(_on_operating_state_changed)

	if _starfield.has_method("bind_camera"):
		_starfield.bind_camera(_camera)

	_hud.bind(session, _player, AssembledShip.new())
	_bind_controllers()
	_bind_session_events(session)

	_jump.jump_requested.connect(_world.on_jump_requested)
	_jump.cancelled.connect(_world.on_jump_cancelled)

	_pause.resume_requested.connect(_menu.on_pause_resume_requested)
	_pause.save_requested.connect(_menu.on_pause_save_requested)
	_pause.load_requested.connect(_menu.on_pause_load_requested)
	_pause.quit_to_menu_requested.connect(_menu.on_quit_to_menu_requested)

	_main_menu.new_game_requested.connect(_menu.on_main_menu_new_game)
	_main_menu.load_requested.connect(_menu.on_main_menu_load)
	_main_menu.exit_requested.connect(_menu.on_main_menu_exit)

	_new_game.confirmed.connect(_menu.on_new_game_confirmed)
	_new_game.cancelled.connect(_menu.on_new_game_cancelled)

	_save_overlay.slot_chosen.connect(_menu.on_save_slot_chosen)
	_save_overlay.cancelled.connect(_menu.on_save_overlay_cancelled)

	_player.freeze_motion()
	_pause.visible = false
	_jump.visible = false
	_hud.visible = false
	_new_game.close()
	_save_overlay.close()

	_menu.show_main_menu()


func _bind_controllers() -> void:
	_flight.bind(
		self,
		_world.get_loader(),
		catalog,
		_player,
		_hud,
		_camera,
		_jump,
		_ui_root,
		get_tree()
	)
	_world.bind(
		self,
		_world_node,
		_starfield,
		_player,
		_pause,
		_jump,
		_hud,
		_ui_root,
		catalog,
		_simulation,
		_flight,
		get_tree(),
		_on_session_changed,
		_on_interaction_target_changed
	)
	_camera.bind_session(session)
	_menu.bind(
		self,
		_main_menu,
		_new_game,
		_save_overlay,
		_pause,
		_jump,
		_hud,
		_ui_root,
		_player,
		_camera,
		catalog,
		_simulation,
		_world,
		get_tree(),
		_on_session_changed,
		{
			"ship_changed": _world.on_ui_ship_changed,
			"undock_requested": _world.on_ui_undock_requested,
			"save_requested": _menu.on_ui_save_requested,
			"quit_to_menu": _menu.on_quit_to_menu_requested,
		}
	)
	_ui_root.configure(
		catalog,
		session,
		_simulation,
		_world.on_ui_ship_changed,
		_world.on_ui_undock_requested,
		_menu.on_ui_save_requested,
		_menu.on_quit_to_menu_requested
	)
	_jump.bind(catalog, session)


func _process(delta: float) -> void:
	if _simulation == null:
		return
	_simulation.step(session, catalog, delta, _menu.is_gst_frozen())


func _physics_process(delta: float) -> void:
	_flight.physics_tick(delta, Engine.get_physics_frames())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_active_sensors"):
		if _flight.can_toggle_active_sensors():
			_flight.toggle_active_sensors()
			return
	if event.is_action_pressed("pause"):
		if _ui_root.visible and _ui_root.handle_back():
			return
		if _menu.can_toggle_pause():
			_menu.toggle_pause()


func try_interact(target: Interactable) -> void:
	_world.try_interact(target)


func _bind_session_events(game_session: GameSession) -> void:
	_menu.bind_session_events(game_session)


func _on_session_changed() -> void:
	_hud.refresh()


func _on_interaction_target_changed(target: Interactable) -> void:
	_hud.set_interaction_target(target)


func _on_motion_changed(speed: float, heading_deg: float, boosting: bool) -> void:
	_flight.on_motion_changed(speed, heading_deg, boosting)


func _on_operating_state_changed(state: ShipOperatingState) -> void:
	_flight.on_operating_state_changed(state)
