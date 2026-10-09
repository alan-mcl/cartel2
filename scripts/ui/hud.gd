extends CanvasLayer

const PLAYER_HOVER_RADIUS := 24.0
const WIRE_TAPE_TOP_UP_MAX_TRIES := 12
const WEAPON_CHIT_STACK_GAP := 10.0
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
@onready var _target_lock_overlay: Control = $Root/TargetLockOverlay
@onready var _interact_prompt: Control = $Root/InteractPromptOverlay
@onready var _star_lens_flare: Control = $Root/StarLensFlare
@onready var _player_hover_probe: Control = $Root/PlayerHoverProbe
@onready var _wire_message_bar: MessageBar = $Root/WireMessageBar
@onready var _message_bar: MessageBar = $Root/MessageBar
@onready var _weapon_chit_stack: WeaponHudStack = $Root/WeaponChitStack

var _session: GameSession
var _catalog: Catalog
var _simulation: Simulation
var _assembled_ship: AssembledShip
var _operating_state: ShipOperatingState
var _player_broadcast_text: String = ""
var _wire_rng := RandomNumberGenerator.new()
var _wire_tape_active := false
var _wire_started := false
var _player_ship: CharacterBody2D
var _weapon_select_handler: Callable = Callable()
var _weapon_selection_player: CharacterBody2D = null


func bind(
	session: GameSession,
	player_ship: CharacterBody2D,
	assembled_ship: AssembledShip,
	simulation: Simulation = null,
	catalog: Catalog = null
) -> void:
	_unbind_weapon_selection_listener()
	_session = session
	_player_ship = player_ship
	_simulation = simulation
	_catalog = catalog
	_bind_gst_clock()
	set_assembled_ship(assembled_ship)
	_refresh_identity()
	_sync_wire_tape_state()
	_bind_weapon_chits()
	_bind_weapon_selection_listener()
	call_deferred("_sync_process_enabled")


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
	_refresh_weapon_chits(true)
	if _operating_state != null:
		set_operating_state(_operating_state)


func set_weapon_select_handler(handler: Callable) -> void:
	_weapon_select_handler = handler


func _bind_weapon_chits() -> void:
	if _weapon_chit_stack == null:
		return
	if not _weapon_chit_stack.weapon_selected.is_connected(_on_weapon_chit_selected):
		_weapon_chit_stack.weapon_selected.connect(_on_weapon_chit_selected)


func _bind_weapon_selection_listener() -> void:
	if _player_ship == null:
		return
	if not _player_ship.weapon_selection_changed.is_connected(_on_player_weapon_selection_changed):
		_player_ship.weapon_selection_changed.connect(_on_player_weapon_selection_changed)
	_weapon_selection_player = _player_ship


func _unbind_weapon_selection_listener() -> void:
	if _weapon_selection_player == null:
		return
	if (
		is_instance_valid(_weapon_selection_player)
		and _weapon_selection_player.weapon_selection_changed.is_connected(
			_on_player_weapon_selection_changed
		)
	):
		_weapon_selection_player.weapon_selection_changed.disconnect(
			_on_player_weapon_selection_changed
		)
	_weapon_selection_player = null


func _on_player_weapon_selection_changed() -> void:
	_refresh_weapon_chits(false)


func _on_weapon_chit_selected(slot_id: String) -> void:
	if _weapon_select_handler.is_valid():
		_weapon_select_handler.call(slot_id)


func _process(_delta: float) -> void:
	_refresh_weapon_chits(false)
	if not _wire_tape_active or not visible:
		return
	_top_up_wire_tape()


func _refresh_weapon_chits(force_rebuild: bool) -> void:
	if _weapon_chit_stack == null or not _has_capability("basic_hud"):
		if _weapon_chit_stack != null:
			_weapon_chit_stack.visible = false
		return
	var weapons: ShipWeapons = null
	var owned: OwnedShip = null
	if _player_ship != null:
		var weapons_variant: Variant = _player_ship.get("weapons")
		if weapons_variant is ShipWeapons:
			weapons = weapons_variant
		var owned_variant: Variant = _player_ship.get("owned_ship")
		if owned_variant is OwnedShip:
			owned = owned_variant
	if _assembled_ship == null or weapons == null:
		_weapon_chit_stack.visible = false
		return
	_weapon_chit_stack.rebuild_if_needed(_assembled_ship, weapons, owned)
	_weapon_chit_stack.refresh_states(_assembled_ship, weapons, owned)


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
	_sync_process_enabled()
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
	call_deferred("_sync_status_panel_layout")


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
	player_broadcast: Dictionary = {},
	locked_contact: Dictionary = {}
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
	if _has_capability("basic_target_lock") and _target_lock_overlay != null:
		if _target_lock_overlay.has_method("set_lock_state"):
			_target_lock_overlay.set_lock_state(locked_contact, camera)

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
	var has_target_lock := _has_capability("basic_target_lock")

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
	if _target_lock_overlay != null:
		_target_lock_overlay.set_feature_visible(has_target_lock)
	call_deferred("_sync_status_panel_layout")


func _sync_status_panel_layout() -> void:
	if _status_panel == null or _weapon_chit_stack == null:
		return
	if not _status_panel.visible:
		return
	var vbox := _status_panel.get_node_or_null("VBox") as Control
	if vbox == null:
		return
	var style := _status_panel.get_theme_stylebox(&"panel")
	var margin_y := 0.0
	if style != null:
		margin_y = style.get_content_margin(SIDE_TOP) + style.get_content_margin(SIDE_BOTTOM)
	var panel_height := vbox.get_combined_minimum_size().y + margin_y
	_status_panel.offset_bottom = _status_panel.offset_top + panel_height
	_weapon_chit_stack.offset_left = _status_panel.offset_left
	_weapon_chit_stack.offset_right = _status_panel.offset_right
	_weapon_chit_stack.offset_top = _status_panel.offset_top + panel_height + WEAPON_CHIT_STACK_GAP


func _has_capability(id: String) -> bool:
	return _assembled_ship != null and _assembled_ship.has_capability(id)


func _sync_log() -> void:
	if not visible:
		return
	if _message_bar == null or _session == null or not _has_capability("basic_hud"):
		return
	_message_bar.play_line(_session.last_log)


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
		_sync_process_enabled()
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
	_sync_process_enabled()
	_top_up_wire_tape()


func _sync_process_enabled() -> void:
	var want_wire := _wire_tape_active and visible
	var want_weapon_chits := visible and _has_capability("basic_hud") and _weapon_chit_stack != null
	set_process(want_wire or want_weapon_chits)


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
	call_deferred("_sync_status_panel_layout")
	if _wire_message_bar != null:
		_wire_message_bar.set_tag("HEADLINES")


func _apply_hud_ticker_panels() -> void:
	for bar in [_message_bar, _wire_message_bar]:
		if bar == null:
			continue
		bar.theme_type_variation = &"HudTicker"
