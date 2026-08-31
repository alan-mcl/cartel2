extends CanvasLayer

@onready var _speed: Label = $Root/Margin/VBox/StatsRow/SpeedLabel
@onready var _heading: Label = $Root/Margin/VBox/StatsRow/HeadingLabel
@onready var _boost: Label = $Root/Margin/VBox/StatsRow/BoostLabel
@onready var _location: Label = $Root/Margin/VBox/LocationLabel
@onready var _objective: Label = $Root/Margin/VBox/ObjectiveLabel
@onready var _target: Label = $Root/Margin/VBox/TargetLabel
@onready var _credits: Label = $Root/Margin/VBox/CreditsLabel
@onready var _log: Label = $Root/Margin/VBox/LogLabel
@onready var _boundary: Label = $Root/Margin/VBox/BoundaryLabel
@onready var _hint: Label = $Root/Margin/VBox/HintLabel

var _session: PrototypeSession
var _player: CharacterBody2D


func bind(session: PrototypeSession, player: CharacterBody2D) -> void:
	_session = session
	_player = player
	refresh()


func refresh() -> void:
	if _session == null:
		return

	_location.text = "Location: %s" % _session.location_name
	_objective.text = "Objective: %s" % _session.objective
	_credits.text = "Credits: d%d" % _session.credits
	_log.text = _session.last_log


func set_motion(speed: float, heading_deg: float, boosting: bool) -> void:
	_speed.text = "Speed: %.0f" % speed
	_heading.text = "Heading: %.0f°" % fposmod(heading_deg + 360.0, 360.0)
	_boost.text = "Boost: ON" if boosting else "Boost: --"


func set_target(target: Interactable) -> void:
	if target and target.can_interact():
		_target.text = "Target: %s" % target.get_title()
	else:
		_target.text = "Target: none"


func set_boundary_warning(active: bool) -> void:
	_boundary.visible = active
	if active:
		_boundary.text = "Warning: drifting toward dust ring edge"


func _ready() -> void:
	_boundary.visible = false
	if _hint:
		_hint.text = "W/↑ thrust · S/↓ reverse · A/D rotate · Shift boost · E interact · Esc pause"
