extends CanvasLayer

const PLAYER_HOVER_RADIUS := 24.0
const WIRE_TAPE_TOP_UP_MAX_TRIES := 12
const TransponderBroadcastScript := preload("res://scripts/gameplay/transponder_broadcast.gd")

@onready var _status_panel: PanelContainer = $Root/StatusPanel
@onready var _flight_strip: PanelContainer = $Root/FlightStrip
@onready var _signature_panel: PanelContainer = $Root/SignaturePanel
@onready var _field_panel: PanelContainer = $Root/FieldPanel
@onready var _field_gravity_label: Label = $Root/FieldPanel/VBox/GravityLabel
@onready var _field_magnetic_label: Label = $Root/FieldPanel/VBox/MagneticLabel
@onready var _field_radiant_label: Label = $Root/FieldPanel/VBox/RadiantLabel
@onready var _field_particles_label: Label = $Root/FieldPanel/VBox/ParticlesLabel
@onready var _thermal_label: Label = $Root/SignaturePanel/VBox/ThermalLabel
@onready var _grav_label: Label = $Root/SignaturePanel/VBox/GravLabel
@onready var _em_label: Label = $Root/SignaturePanel/VBox/EmLabel
@onready var _compute_signature_label: Label = $Root/SignaturePanel/VBox/ComputeLabel
@onready var _transponder_label: Label = $Root/SignaturePanel/VBox/TransponderLabel
@onready var _active_sensors_label: Label = $Root/SignaturePanel/VBox/ActiveSensorsLabel
@onready var _power: Label = $Root/StatusPanel/VBox/PowerLabel
@onready var _fuel: Label = $Root/StatusPanel/VBox/FuelLabel
@onready var _compute: Label = $Root/StatusPanel/VBox/ComputeLabel
@onready var _life_support: Label = $Root/StatusPanel/VBox/LifeSupportLabel
@onready var _hull: Label = $Root/StatusPanel/VBox/HullLabel
@onready var _identity: Label = $Root/FlightStrip/HBox/IdentityLabel
@onready var _speed: Label = $Root/FlightStrip/HBox/SpeedLabel
@onready var _heading: Label = $Root/FlightStrip/HBox/HeadingLabel
@onready var _gst_clock: Label = $Root/FlightStrip/HBox/GstClockLabel
@onready var _stability_label: Label = $Root/FieldPanel/VBox/StabilityLabel
@onready var _local_sensor_map: Control = $Root/LocalSensorMap
@onready var _waypoint_arrows: Control = $Root/WaypointArrows
@onready var _beacon_labels: Control = $Root/BeaconLabelOverlay
@onready var _interact_prompt: Control = $Root/InteractPromptOverlay
@onready var _star_lens_flare: Control = $Root/StarLensFlare
@onready var _player_hover_probe: Control = $Root/PlayerHoverProbe
@onready var _wire_message_bar: MessageBar = $Root/WireMessageBar
@onready var _message_bar: MessageBar = $Root/MessageBar

var _session: GameSession
var _catalog: Catalog
var _simulation: Simulation
var _assembled_ship: AssembledShip
var _operating_state: ShipOperatingState
var _player_broadcast_text: String = ""
var _wire_rng := RandomNumberGenerator.new()
var _wire_tape_active := false
var _wire_started := false


func bind(
	session: GameSession,
	_player: CharacterBody2D,
	assembled_ship: AssembledShip,
	simulation: Simulation = null,
	catalog: Catalog = null
) -> void:
	_session = session
	_simulation = simulation
	_catalog = catalog
	_bind_gst_clock()
	set_assembled_ship(assembled_ship)
	_refresh_identity()
	_sync_wire_tape_state()


func _bind_gst_clock() -> void:
	var clock := _get_gst_clock()
	if clock != null and clock.has_method("bind"):
		clock.bind(_session)


func _get_gst_clock() -> Label:
	if _gst_clock != null:
		return _gst_clock
	return get_node_or_null("Root/FlightStrip/HBox/GstClockLabel") as Label


func set_assembled_ship(assembled_ship: AssembledShip) -> void:
	_assembled_ship = assembled_ship
	_refresh_capabilities()
	_refresh_identity()
	if _operating_state != null:
		set_operating_state(_operating_state)


func refresh() -> void:
	_refresh_capabilities()
	_refresh_identity()
	_sync_log()
	_sync_wire_tape_state()


func clear_message_log() -> void:
	if _message_bar != null:
		_message_bar.clear_queued_lines()
	if _wire_message_bar != null:
		_wire_message_bar.clear_queued_lines()
	_wire_tape_active = false
	_wire_started = false
	set_process(false)
	var messages := _messages_subsystem()
	if messages != null:
		messages.clear_channel(MessageChannels.HEADLINES)


func set_interaction_target(target: Interactable) -> void:
	if _interact_prompt != null and _interact_prompt.has_method("set_target"):
		_interact_prompt.set_target(target)


func set_motion(speed: float, heading_deg: float, _boosting: bool) -> void:
	if not _has_capability("basic_hud"):
		return
	_speed.text = "Speed: %.0f" % speed
	_heading.text = "Heading: %.0f°" % fposmod(heading_deg + 360.0, 360.0)


func set_operating_state(state: ShipOperatingState) -> void:
	_operating_state = state
	_sync_log()
	if not _has_capability("basic_hud") or state == null:
		return
	if not state.propulsion_requires_fuel:
		_fuel.text = "Fuel: —"
	elif state.propulsion_fuel_label.is_empty():
		_fuel.text = "Fuel: %.0f / %.0f" % [state.fuel_current, state.fuel_capacity]
	else:
		_fuel.text = "%s: %.0f / %.0f" % [
			state.propulsion_fuel_label,
			state.fuel_current,
			state.fuel_capacity,
		]
	_power.text = "Power: %.0f / %.0f MW" % [state.power_allocated, state.power_available]
	_compute.text = "Compute: %.0f / %.0f CU" % [state.compute_demand, state.compute_capacity]
	var ls_text := "Life support: %.0f / %.0f" % [
		state.life_support_demand,
		state.life_support_capacity,
	]
	if state.life_support_overloaded:
		ls_text += " overloaded"
	_life_support.text = ls_text
	_refresh_hull()


func set_signature_state(
	signature: Dictionary,
	transponder_label: String,
	active_sensors_label: String = ""
) -> void:
	if not _has_capability("basic_hud"):
		return
	if _thermal_label != null:
		_thermal_label.text = "Thermal: %.1f" % float(signature.get("thermal", 0.0))
	if _grav_label != null:
		_grav_label.text = "Gravitational: %.1f" % float(signature.get("gravitational", 0.0))
	if _em_label != null:
		_em_label.text = "EM: %.1f" % float(signature.get("electromagnetic", 0.0))
	if _compute_signature_label != null:
		_compute_signature_label.text = "Computational: %.1f" % float(signature.get("computational", 0.0))
	if _transponder_label != null:
		_transponder_label.text = "Transponder: %s" % transponder_label
	if _active_sensors_label != null:
		if active_sensors_label.is_empty():
			_active_sensors_label.visible = false
		else:
			_active_sensors_label.visible = true
			_active_sensors_label.text = "Active sensors: %s" % active_sensors_label


func set_translation_stability(stability: float, in_unspace: bool) -> void:
	if _stability_label == null:
		return
	var show := in_unspace and stability >= 0.0 and _has_capability("local_sensor")
	_stability_label.visible = show
	if show:
		_stability_label.text = "N-space stability: %d%%" % int(round(stability))


func set_field_state(sample: FieldConditions.FieldSample) -> void:
	if not _has_capability("local_sensor"):
		return
	if sample == null:
		return
	if _field_gravity_label != null:
		_field_gravity_label.text = "Gravity: %.2f G" % sample.gravity
	if _field_magnetic_label != null:
		_field_magnetic_label.text = "Magnetic: %.2f" % sample.magnetic
	if _field_radiant_label != null:
		_field_radiant_label.text = "Radiant: %.2f" % sample.radiant
	if _field_particles_label != null:
		_field_particles_label.text = "Particles: %.2f" % sample.charged_particle


func set_nav_state(
	nav_radius: float,
	ship_pos: Vector2,
	ship_heading_deg: float,
	contacts: Array,
	camera: Camera2D,
	player_broadcast: Dictionary = {}
) -> void:
	_player_broadcast_text = TransponderBroadcastScript.format_tooltip(player_broadcast)

	if _has_capability("local_sensor") and _local_sensor_map != null:
		if _local_sensor_map.has_method("set_player_broadcast"):
			_local_sensor_map.set_player_broadcast(_player_broadcast_text)
		_local_sensor_map.set_nav_state(nav_radius, ship_pos, ship_heading_deg, contacts)
	if _has_capability("local_system_waypoints") and _waypoint_arrows != null:
		_waypoint_arrows.set_nav_state(ship_pos, contacts, camera)
	if _has_capability("sensor_read_beacons") and _beacon_labels != null:
		_beacon_labels.set_overlay_state(contacts, camera)

	if _interact_prompt != null and _interact_prompt.has_method("set_camera"):
		_interact_prompt.set_camera(camera)

	_update_player_hover_probe(ship_pos, camera)


func set_star_lens_flare(
	star_info: Dictionary,
	ship_pos: Vector2,
	player_facing: float,
	camera: Camera2D
) -> void:
	if _star_lens_flare == null or not _star_lens_flare.has_method("update_flare"):
		return
	if star_info.is_empty():
		_star_lens_flare.update_flare(Vector2.ZERO, Color.WHITE, 0.0, ship_pos, player_facing, camera)
		return
	_star_lens_flare.update_flare(
		star_info.get("world_position", Vector2.ZERO),
		star_info.get("color", Color.WHITE),
		float(star_info.get("luminosity", 1.0)),
		ship_pos,
		player_facing,
		camera
	)


func _update_player_hover_probe(ship_pos: Vector2, camera: Camera2D) -> void:
	if _player_hover_probe == null or camera == null:
		return

	var screen_pos := get_viewport().get_canvas_transform() * ship_pos
	_player_hover_probe.position = screen_pos - Vector2(PLAYER_HOVER_RADIUS, PLAYER_HOVER_RADIUS)
	_player_hover_probe.size = Vector2(PLAYER_HOVER_RADIUS * 2.0, PLAYER_HOVER_RADIUS * 2.0)
	_player_hover_probe.visible = not _player_broadcast_text.is_empty()

	var mouse_pos := _player_hover_probe.get_global_mouse_position()
	var hovering := _player_hover_probe.get_global_rect().has_point(mouse_pos)
	_player_hover_probe.tooltip_text = _player_broadcast_text if hovering else ""


func _refresh_identity() -> void:
	if _identity == null:
		return
	var callsign := ""
	var ship_name := ""
	if _session != null:
		callsign = _session.callsign.strip_edges()
	if _assembled_ship != null:
		ship_name = _assembled_ship.name.strip_edges()
	if callsign.is_empty():
		callsign = "—"
	if ship_name.is_empty():
		ship_name = "—"
	_identity.text = "%s aboard %s" % [callsign, ship_name]


func _refresh_hull() -> void:
	if _hull == null or _session == null:
		return
	var max_hull := _session.max_hull
	if max_hull <= 0.0:
		_hull.text = "Hull: —"
	else:
		_hull.text = "Hull: %.0f / %.0f" % [_session.hull, max_hull]


func _refresh_capabilities() -> void:
	var has_basic := _has_capability("basic_hud")
	var has_sensor := _has_capability("local_sensor")
	var has_waypoints := _has_capability("local_system_waypoints")
	var has_beacon_reader := _has_capability("sensor_read_beacons")

	if _status_panel != null:
		_status_panel.visible = has_basic
	if _flight_strip != null:
		_flight_strip.visible = has_basic
	if _signature_panel != null:
		_signature_panel.visible = has_basic
	if _message_bar != null:
		_message_bar.visible = has_basic
	if _wire_message_bar != null:
		_wire_message_bar.visible = has_basic and _wire_headlines_enabled()
	if _field_panel != null:
		_field_panel.visible = has_sensor
	if _local_sensor_map != null:
		_local_sensor_map.set_feature_visible(has_sensor)
	if _waypoint_arrows != null:
		_waypoint_arrows.set_feature_visible(has_waypoints)
	if _beacon_labels != null:
		_beacon_labels.set_feature_visible(has_beacon_reader)


func _has_capability(id: String) -> bool:
	return _assembled_ship != null and _assembled_ship.has_capability(id)


func _sync_log() -> void:
	if not visible:
		return
	if _message_bar == null or _session == null or not _has_capability("basic_hud"):
		return
	_message_bar.play_line(_session.last_log)


func _process(_delta: float) -> void:
	if not _wire_tape_active or not visible:
		return
	_top_up_wire_tape()


func _wire_headlines_enabled() -> bool:
	if _session == null or _catalog == null:
		return false
	if _session.world.in_unspace:
		return false
	return ExchangePriceTape.is_planetary_hub(_catalog, _session.sector_id)


func _messages_subsystem() -> MessageSubsystem:
	if _simulation == null:
		return null
	return _simulation.get_subsystem("messages") as MessageSubsystem


func _sync_wire_tape_state() -> void:
	var enabled := visible and _has_capability("basic_hud") and _wire_headlines_enabled()
	if _wire_message_bar != null:
		_wire_message_bar.visible = enabled
	if not enabled:
		_wire_tape_active = false
		_wire_started = false
		set_process(false)
		return
	var messages := _messages_subsystem()
	var headlines_sector_changed := false
	if messages != null:
		headlines_sector_changed = messages.note_headlines_sector(_session.sector_id)
	if headlines_sector_changed and _wire_message_bar != null:
		_wire_message_bar.clear_queued_lines()
	if not _wire_started:
		_wire_started = true
		_wire_tape_active = true
		_wire_rng.randomize()
		set_process(true)
	_top_up_wire_tape()


func _enqueue_wire_line() -> bool:
	var messages := _messages_subsystem()
	if messages == null or _session == null or _catalog == null or _wire_message_bar == null:
		return false
	var sample := messages.next_line(MessageChannels.HEADLINES, _session, _catalog, _wire_rng)
	var line := str(sample.get("text", "")).strip_edges()
	if line.is_empty():
		return false
	return _wire_message_bar.play_line(line, true, true)


func _top_up_wire_tape() -> void:
	if _wire_message_bar == null or not _wire_headlines_enabled():
		return
	var tries := 0
	while _wire_message_bar.wants_more_log_lines() and tries < WIRE_TAPE_TOP_UP_MAX_TRIES:
		if not _enqueue_wire_line():
			break
		tries += 1


func _ready() -> void:
	if _session != null:
		_bind_gst_clock()
	_apply_hud_ticker_panels()
	_refresh_capabilities()
	if _wire_message_bar != null:
		_wire_message_bar.set_tag("HEADLINES")


func _apply_hud_ticker_panels() -> void:
	for bar in [_message_bar, _wire_message_bar]:
		if bar == null:
			continue
		bar.theme_type_variation = &"HudTicker"
