extends Node2D

var session := PrototypeSession.new()
var catalog := Catalog.load_default()
var player_ship: AssembledShip
var play_bounds: float = 3500.0

var _world_loader := WorldLoader.new()
var _translate_gate_title: String = ""

@onready var _world: Node2D = $World
@onready var _player: CharacterBody2D = $PlayerShip
@onready var _hud: CanvasLayer = $HUD
@onready var _pause: CanvasLayer = $PauseOverlay
@onready var _location: CanvasLayer = $LocationOverlay
@onready var _jump: CanvasLayer = $JumpOverlay
@onready var _starfield: Node2D = $Starfield
@onready var _camera: Camera2D = $PlayerShip/FollowCamera


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	session.load_player(catalog)
	player_ship = _assemble_current_ship()
	if player_ship.name.is_empty():
		push_error("Failed to assemble current player ship.")
		return

	_player.configure(player_ship)

	session.changed.connect(_on_session_changed)
	_player.interaction_target_changed.connect(_on_interaction_target_changed)
	_player.motion_changed.connect(_on_motion_changed)

	if _starfield.has_method("bind_camera"):
		_starfield.bind_camera(_camera)

	_hud.bind(session, _player, player_ship)
	_location.bind(catalog, session)
	_location.visit_requested.connect(_on_visit_requested)
	_location.undock_ship_selected.connect(_on_undock_ship_selected)
	_location.module_changed.connect(_on_module_changed)

	_jump.bind(catalog, session)
	_jump.jump_requested.connect(_on_jump_requested)
	_jump.cancelled.connect(_on_jump_cancelled)

	_pause.visible = false
	_location.visible = false
	_jump.visible = false

	_load_current_sector(false)
	_on_session_changed()


func _physics_process(_delta: float) -> void:
	if session.docked or _jump.visible:
		return

	var distance := _player.global_position.length()
	_hud.set_boundary_warning(distance > play_bounds)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not session.docked and not _jump.visible:
		_toggle_pause()


func try_interact(target: Interactable) -> void:
	if target == null or target.definition == null:
		return

	match target.definition.kind:
		InteractableDef.Kind.DOCK:
			_dock_at(target.definition.dock_location_id)
		InteractableDef.Kind.TRANSLATE:
			_open_jump_overlay(target.definition.title)
		_:
			var result := target.interact(session)
			if result.is_empty():
				return
			_on_session_changed()
			_on_interaction_target_changed(_player.get_current_target())
			_world_loader.apply_salvage_visuals(session)


func _load_current_sector(place_player: bool = true) -> void:
	play_bounds = _world_loader.load_sector(_world, catalog, session, session.sector_id)
	if _player.has_method("register_world_interactables"):
		_player.register_world_interactables()
	if place_player:
		_player.global_position = session.get_sector_spawn(catalog)
	_player.freeze_motion()


func _open_jump_overlay(gate_title: String) -> void:
	if session.docked:
		return

	_translate_gate_title = gate_title
	get_tree().paused = true
	_pause.visible = false
	_jump.open(gate_title)
	_on_interaction_target_changed(_player.get_current_target())


func _on_jump_requested(target_sector_id: String) -> void:
	if target_sector_id.is_empty():
		return

	if not session.enter_sector(catalog, target_sector_id):
		return

	_load_current_sector(true)
	_jump.close()
	get_tree().paused = false
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
	_pause.visible = false
	_location.open()
	_on_session_changed()
	_on_interaction_target_changed(_player.get_current_target())


func _on_visit_requested(building_id: String) -> void:
	if session.visit(catalog, building_id):
		_location.refresh()
		_on_session_changed()


func _on_undock_ship_selected(ship_id: String) -> void:
	if ship_id.is_empty() or not session.docked:
		return

	if not session.undock(catalog, ship_id):
		return

	player_ship = _assemble_current_ship()
	_player.configure(player_ship)
	_player.freeze_motion()
	_hud.set_assembled_ship(player_ship)

	get_tree().paused = false
	_location.close()
	_pause.visible = false
	_on_session_changed()
	_on_interaction_target_changed(_player.get_current_target())


func _on_module_changed(ship_id: String, slot: String, module_id: String) -> void:
	if not session.set_module(ship_id, slot, module_id):
		return

	if ship_id == session.current_ship_id:
		player_ship = _assemble_current_ship()
		_player.configure(player_ship)
		_hud.set_assembled_ship(player_ship)

	_location.refresh()
	_on_session_changed()


func _assemble_current_ship() -> AssembledShip:
	var owned := session.get_current_owned_ship()
	if owned == null:
		return AssembledShip.new()
	return ShipAssembler.assemble_owned(catalog, owned)


func _toggle_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_pause.visible = paused


func _on_session_changed() -> void:
	_hud.refresh()


func _on_interaction_target_changed(target: Interactable) -> void:
	_hud.set_target(target)


func _on_motion_changed(speed: float, heading_deg: float, boosting: bool) -> void:
	_hud.set_motion(speed, heading_deg, boosting)
