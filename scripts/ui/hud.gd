extends CanvasLayer

const PANEL_BG_ALPHA := 0.25

@onready var _status_panel: PanelContainer = $Root/StatusPanel
@onready var _speed: Label = $Root/StatusPanel/VBox/StatsRow/SpeedLabel
@onready var _heading: Label = $Root/StatusPanel/VBox/StatsRow/HeadingLabel
@onready var _fuel: Label = $Root/StatusPanel/VBox/SystemsRow/FuelLabel
@onready var _power: Label = $Root/StatusPanel/VBox/SystemsRow/PowerLabel
@onready var _gst_clock: Label = $Root/StatusPanel/VBox/GstClockLabel
@onready var _local_sensor_map: Control = $Root/LocalSensorMap
@onready var _waypoint_arrows: Control = $Root/WaypointArrows

var _session: GameSession
var _assembled_ship: AssembledShip
var _operating_state: ShipOperatingState


func bind(session: GameSession, _player: CharacterBody2D, assembled_ship: AssembledShip) -> void:
	_session = session
	_bind_gst_clock()
	set_assembled_ship(assembled_ship)


func _bind_gst_clock() -> void:
	var clock := _get_gst_clock()
	if clock != null and clock.has_method("bind"):
		clock.bind(_session)


func _get_gst_clock() -> Label:
	if _gst_clock != null:
		return _gst_clock
	return get_node_or_null("Root/StatusPanel/VBox/GstClockLabel") as Label


func set_assembled_ship(assembled_ship: AssembledShip) -> void:
	_assembled_ship = assembled_ship
	_refresh_capabilities()
	if _operating_state != null:
		set_operating_state(_operating_state)


func refresh() -> void:
	_refresh_capabilities()


func set_motion(speed: float, heading_deg: float, _boosting: bool) -> void:
	if not _has_capability("basic_hud"):
		return
	_speed.text = "Speed: %.0f" % speed
	_heading.text = "Heading: %.0f°" % fposmod(heading_deg + 360.0, 360.0)


func set_operating_state(state: ShipOperatingState) -> void:
	_operating_state = state
	if not _has_capability("basic_hud") or state == null:
		return
	_fuel.text = "Fuel: %.0f / %.0f" % [state.fuel_current, state.fuel_capacity]
	_power.text = "Power: %.0f / %.0f MW" % [state.power_allocated, state.power_available]


func set_nav_state(
	nav_radius: float,
	ship_pos: Vector2,
	ship_heading_deg: float,
	contacts: Array,
	camera: Camera2D
) -> void:
	if _has_capability("local_sensor") and _local_sensor_map != null:
		_local_sensor_map.set_nav_state(nav_radius, ship_pos, ship_heading_deg, contacts)
	if _has_capability("local_system_waypoints") and _waypoint_arrows != null:
		_waypoint_arrows.set_nav_state(ship_pos, contacts, camera)


func _refresh_capabilities() -> void:
	var has_basic := _has_capability("basic_hud")
	var has_sensor := _has_capability("local_sensor")
	var has_waypoints := _has_capability("local_system_waypoints")

	if _status_panel != null:
		_status_panel.visible = has_basic
	if _local_sensor_map != null:
		_local_sensor_map.set_feature_visible(has_sensor)
	if _waypoint_arrows != null:
		_waypoint_arrows.set_feature_visible(has_waypoints)


func _has_capability(id: String) -> bool:
	return _assembled_ship != null and _assembled_ship.has_capability(id)


func _ready() -> void:
	_apply_translucent_panel(_status_panel)
	if _session != null:
		_bind_gst_clock()
	_refresh_capabilities()


func _apply_translucent_panel(panel: PanelContainer) -> void:
	if panel == null:
		return

	var style := StyleBoxFlat.new()
	var bg: Color = panel.get_theme_color("surface", "Cartel")
	bg.a = PANEL_BG_ALPHA
	style.bg_color = bg

	var border: Color = panel.get_theme_color("border", "Cartel")
	border.a = PANEL_BG_ALPHA
	style.border_color = border
	style.set_border_width_all(1)

	panel.add_theme_stylebox_override("panel", style)
