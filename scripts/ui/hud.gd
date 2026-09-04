extends CanvasLayer

@onready var _pilot: Label = $Root/Margin/StatusPanel/VBox/PilotLabel
@onready var _ship: Label = $Root/Margin/StatusPanel/VBox/ShipLabel
@onready var _speed: Label = $Root/Margin/StatusPanel/VBox/StatsRow/SpeedLabel
@onready var _heading: Label = $Root/Margin/StatusPanel/VBox/StatsRow/HeadingLabel
@onready var _boost: Label = $Root/Margin/StatusPanel/VBox/StatsRow/BoostLabel
@onready var _systems_row: HBoxContainer = $Root/Margin/StatusPanel/VBox/SystemsRow
@onready var _fuel: Label = $Root/Margin/StatusPanel/VBox/SystemsRow/FuelLabel
@onready var _power: Label = $Root/Margin/StatusPanel/VBox/SystemsRow/PowerLabel
@onready var _heat: Label = $Root/Margin/StatusPanel/VBox/SystemsRow/HeatLabel
@onready var _location: Label = $Root/Margin/StatusPanel/VBox/LocationLabel
@onready var _objective: Label = $Root/Margin/StatusPanel/VBox/ObjectiveLabel
@onready var _target: Label = $Root/Margin/StatusPanel/VBox/TargetLabel
@onready var _credits: Label = $Root/Margin/StatusPanel/VBox/CreditsLabel
@onready var _log: Label = $Root/Margin/StatusPanel/VBox/LogLabel
@onready var _boundary: Label = $Root/Margin/StatusPanel/VBox/BoundaryLabel
@onready var _hull: Label = $Root/Margin/StatusPanel/VBox/HullLabel
@onready var _hint: Label = $Root/Margin/StatusPanel/VBox/HintLabel

var _session: PrototypeSession
var _player: CharacterBody2D
var _assembled_ship: AssembledShip
var _operating_state: ShipOperatingState


func bind(session: PrototypeSession, player: CharacterBody2D, assembled_ship: AssembledShip) -> void:
	_session = session
	_player = player
	set_assembled_ship(assembled_ship)


func set_assembled_ship(assembled_ship: AssembledShip) -> void:
	_assembled_ship = assembled_ship
	refresh()


func refresh() -> void:
	if _session == null:
		return

	if not _session.player_name.is_empty() or not _session.callsign.is_empty():
		_pilot.text = 'Pilot: %s "%s"' % [_session.player_name, _session.callsign]
	else:
		_pilot.text = ""

	if _assembled_ship != null:
		_ship.text = "Ship: %s" % _assembled_ship.get_summary()

	_location.text = "Location: %s" % _session.location_name
	_objective.text = "Objective: %s" % _session.objective
	_credits.text = "Credits: d%d" % _session.credits
	_log.text = _session.last_log

	if _hull != null:
		if _session.in_unspace and _session.max_hull > 0.0:
			_hull.visible = true
			_hull.text = "Hull: %d / %d" % [int(_session.hull), int(_session.max_hull)]
		else:
			_hull.visible = false

	if _operating_state != null:
		set_operating_state(_operating_state)


func set_motion(speed: float, heading_deg: float, boosting: bool) -> void:
	_speed.text = "Speed: %.0f" % speed
	_heading.text = "Heading: %.0f°" % fposmod(heading_deg + 360.0, 360.0)
	_boost.text = "Boost: ON" if boosting else "Boost: --"


func set_operating_state(state: ShipOperatingState) -> void:
	_operating_state = state
	if state == null:
		return
	_fuel.text = "Fuel: %.0f / %.0f" % [state.fuel_current, state.fuel_capacity]
	_power.text = "Power: %.0f / %.0f MW" % [state.power_allocated, state.power_available]
	_heat.text = "Heat: %.0f / %.0f" % [state.heat, state.heat_capacity]


func set_target(target: Interactable) -> void:
	if _session != null and _session.docked:
		_target.text = "Target: Docked"
		return

	if target and target.can_interact():
		_target.text = "Target: %s" % target.get_title()
	else:
		_target.text = "Target: none"


func set_boundary_warning(active: bool, in_unspace: bool = false) -> void:
	_boundary.visible = active
	if active:
		if in_unspace:
			_boundary.text = "Warning: drifting toward 4-space boundary"
		else:
			_boundary.text = "Warning: drifting toward dust ring edge"


func _ready() -> void:
	_boundary.visible = false
	if _hint:
		_hint.text = "W/↑ thrust · S/↓ reverse · A/D rotate · Shift boost · E interact · Esc pause"
