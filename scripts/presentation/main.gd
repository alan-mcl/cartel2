extends Node2D

@export var play_bounds: float = 3500.0

var session := PrototypeSession.new()

@onready var _player: CharacterBody2D = $PlayerShip
@onready var _hud: CanvasLayer = $HUD
@onready var _pause: CanvasLayer = $PauseOverlay
@onready var _starfield: Node2D = $Starfield
@onready var _camera: Camera2D = $PlayerShip/FollowCamera
@onready var _hint: Label = $HUD/Root/Margin/VBox/HintLabel
@onready var _wreck: Interactable = $World/Wreck/Interactable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	session.changed.connect(_on_session_changed)
	_player.interaction_target_changed.connect(_on_interaction_target_changed)
	_player.motion_changed.connect(_on_motion_changed)

	if _starfield.has_method("bind_camera"):
		_starfield.bind_camera(_camera)

	_hud.bind(session, _player)
	_pause.visible = false
	_on_session_changed()

	if session.salvaged_wreck and _wreck:
		_wreck.mark_consumed()


func _physics_process(_delta: float) -> void:
	var distance := _player.global_position.length()
	if distance > play_bounds:
		_hud.set_boundary_warning(true)
	else:
		_hud.set_boundary_warning(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()


func try_interact(target: Interactable) -> void:
	if target == null:
		return

	var result := target.interact(session)
	if result.is_empty():
		return

	_on_session_changed()
	_on_interaction_target_changed(_player.get_current_target())

	if target.is_consumed and target == _wreck:
		$World/Wreck/Visual.modulate = Color(0.45, 0.45, 0.45, 0.6)


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
