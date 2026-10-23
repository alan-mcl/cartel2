class_name FlightLoopController
extends RefCounted

const TrafficDirectorScript := preload("res://scripts/gameplay/traffic_director.gd")
const TrafficViewScript := preload("res://scripts/presentation/traffic_view.gd")
const TransponderBroadcastScript := preload("res://scripts/gameplay/transponder_broadcast.gd")
const TrafficSpawnScript := preload("res://scripts/gameplay/traffic_spawn.gd")

var _traffic_director = null
var _traffic_view = null
var _world_loader: WorldLoader
var _catalog: Catalog
var _main: Node2D
var _player: CharacterBody2D
var _hud: CanvasLayer
var _camera: Camera2D
var _jump: CanvasLayer
var _ui_root: CanvasLayer
var _tree: SceneTree


func bind(
	main: Node2D,
	world_loader: WorldLoader,
	catalog: Catalog,
	player: CharacterBody2D,
	hud: CanvasLayer,
	camera: Camera2D,
	jump: CanvasLayer,
	ui_root: CanvasLayer,
	tree: SceneTree
) -> void:
	_main = main
	_world_loader = world_loader
	_catalog = catalog
	_player = player
	_hud = hud
	_camera = camera
	_jump = jump
	_ui_root = ui_root
	_tree = tree


func refresh_session_refs() -> void:
	pass


func clear_traffic() -> void:
	if _traffic_view != null:
		_traffic_view.clear()
	if _traffic_director != null:
		_traffic_director.clear()


func setup_traffic(world: Node2D) -> void:
	if VolatileTranslation.is_volatile_sector_id(_main.session.sector_id):
		_setup_volatile_site_traffic(world)
		return
	_ensure_traffic_director()
	if _traffic_director == null:
		return
	_traffic_director.setup(
		_catalog,
		_main.session.sector_id,
		_world_loader.get_traffic_envelope_radius(),
		_player.global_position,
		_world_loader
	)
	if _traffic_view != null:
		_traffic_view.setup(world)
		_traffic_view.sync(_traffic_director.actors, _catalog)


func physics_tick(delta: float, physics_frame: int) -> void:
	if not _main.game_active:
		return
	if _main.session.docked or _jump.visible or _tree.paused:
		if _main.session.docked:
			if _player.has_method("clear_target_lock"):
				_player.clear_target_lock()
			if _player.has_method("reset_autopilot"):
				_player.reset_autopilot()
		_hud.set_star_lens_flare({}, _player.global_position, _player.motion.facing, _camera)
		return

	if VolatileTranslation.is_volatile_sector_id(_main.session.sector_id):
		VolatileTranslation.announce_gate_collapsed_if_needed(_main.session)
		_world_loader.refresh_volatile_return_gate(_main.session)
		_tick_volatile_site_traffic(delta, physics_frame)

	# Display-rate cadence: HUD nav/signature and traffic tick every physics frame.
	if (
		not _main.session.in_unspace
		and not VolatileTranslation.is_volatile_sector_id(_main.session.sector_id)
	):
		_ensure_traffic_director()
		if _traffic_director != null:
			var player_broadcasting: bool = (
				_player.operating_state.transponder_broadcasting
				if _player.assembled_ship != null
				else false
			)
			_traffic_director.tick(
				delta,
				_player.global_position,
				_world_loader,
				physics_frame,
				_player.motion.velocity,
				_player.motion.facing,
				_player.motion.is_thrusting(),
				_player.assembled_ship,
				_player.operating_state,
				player_broadcasting,
				_main.session.world
			)
			if _traffic_view != null:
				_traffic_view.sync(_traffic_director.actors, _catalog)

	var contacts := _collect_nav_contacts()
	var nav_radius: float = _main.play_bounds
	if not _main.session.in_unspace:
		nav_radius = _world_loader.get_content_radius()
		if nav_radius <= 0.0:
			nav_radius = _main.play_bounds
	var star_display: Dictionary = {}
	if not _main.session.in_unspace:
		star_display = _world_loader.get_local_star_display()
	present_flight_frame(contacts, nav_radius, star_display)


func install_scripted_roster(roster: Array, sector_id: String, envelope: float) -> void:
	_ensure_traffic_director()
	if _traffic_director == null:
		return
	_traffic_director.setup_scripted_volatile_roster(
		_catalog,
		sector_id,
		envelope,
		_player.global_position,
		roster
	)


func present_flight_frame(contacts: Array, nav_radius: float, star_display: Dictionary = {}) -> void:
	if _player.has_method("retain_target_lock"):
		_player.retain_target_lock(contacts)
	var locked_contact := TargetLock.contact_for_id(contacts, _player.locked_target_id)
	if _player.has_method("set_guidance_lock_contact"):
		_player.set_guidance_lock_contact(locked_contact)
	if _player.has_method("set_autopilot_target"):
		_player.set_autopilot_target(locked_contact)

	var owned: OwnedShip = _main.session.get_current_owned_ship()
	var player_broadcast: Dictionary = TransponderBroadcastScript.player_broadcast(
		owned.registration if owned != null else "",
		_main.session.callsign,
		owned.name if owned != null else ""
	)
	_hud.set_nav_state(
		nav_radius,
		_player.global_position,
		rad_to_deg(_player.motion.facing),
		contacts,
		_camera,
		player_broadcast,
		locked_contact
	)
	_hud.set_star_lens_flare(
		star_display,
		_player.global_position,
		_player.motion.facing,
		_camera
	)
	var player_signature := SensorSystem.live_signature(
		_player.assembled_ship,
		_player.operating_state
	)
	var transponder_label := "on" if _player.operating_state.transponder_broadcasting else "off"
	var active_sensors_label := active_sensors_hud_label(
		_player.assembled_ship,
		_player.operating_state
	)
	_hud.set_signature_state(player_signature, transponder_label, active_sensors_label)
	if _catalog != null:
		var field_sample := FieldConditions.sample(
			_catalog,
			_main.session.world,
			_player.global_position
		)
		_hud.set_field_state(field_sample)
	_hud.set_translation_stability(
		_main.session.translation_stability,
		_main.session.in_unspace
	)


func can_toggle_active_sensors() -> bool:
	if not _main.game_active or _main.session.docked or _jump.visible or _ui_root.visible:
		return false
	if _tree.paused:
		return false
	if _player.assembled_ship == null:
		return false
	return _player.assembled_ship.has_active_sensor_package()


func toggle_active_sensors() -> void:
	var owned: OwnedShip = _main.session.get_current_owned_ship()
	if owned == null:
		return
	owned.active_sensors_enabled = not owned.active_sensors_enabled
	_main.session.changed.emit()


func can_use_target_lock() -> bool:
	if not _main.game_active or _main.session.docked or _jump.visible or _ui_root.visible:
		return false
	if _tree.paused:
		return false
	if _player.assembled_ship == null:
		return false
	return TargetLock.has_capability(_player.assembled_ship)


func toggle_target_lock() -> void:
	if not can_use_target_lock():
		return
	var contacts := _collect_nav_contacts()
	if _player.has_method("toggle_target_lock"):
		_player.toggle_target_lock(contacts)


func cycle_target_lock() -> void:
	if not can_use_target_lock():
		return
	if _player.locked_target_id.is_empty():
		return
	var contacts := _collect_nav_contacts()
	if _player.has_method("cycle_target_lock"):
		_player.cycle_target_lock(contacts)


func request_target_scan() -> void:
	if not can_use_target_lock():
		return
	if _player.locked_target_id.is_empty():
		_main.session.last_log = "No target lock held."
		return
	var contacts := _collect_nav_contacts()
	var locked_contact := TargetLock.contact_for_id(contacts, _player.locked_target_id)
	if locked_contact.is_empty():
		_main.session.last_log = "No target lock held."
		return
	var beacon_destination := ""
	if not _main.session.in_unspace:
		beacon_destination = _world_loader.get_translation_beacon_destination(_catalog)
	_main.session.player.record_target_scan(
		str(locked_contact.get("id", "")),
		str(locked_contact.get("contact_kind", "")),
		_main.session.sector_id,
		_main.session.gst_seconds
	)
	_hud.open_target_scan(locked_contact, _player.global_position, beacon_destination)


func can_use_autopilot_hotkey(index: int) -> bool:
	if not _main.game_active or _main.session.docked or _jump.visible or _ui_root.visible:
		return false
	if _tree.paused:
		return false
	if _player.assembled_ship == null:
		return false
	if index == 1:
		return true
	return Autopilot.has_capability(_player.assembled_ship)


func request_autopilot_hotkey(index: int) -> void:
	if not can_use_autopilot_hotkey(index):
		return
	if _player.has_method("request_autopilot_hotkey"):
		_player.request_autopilot_hotkey(index)


func _collect_nav_contacts() -> Array:
	var landmark_contacts := _world_loader.get_nav_contacts(_catalog, _main.session.in_unspace)
	var contacts: Array = []
	contacts.append_array(landmark_contacts)
	if _main.session.in_unspace and not _main.player_ship.has_capability("4_space_topology"):
		contacts = _filter_topology_contacts(contacts)
	if not _main.session.in_unspace:
		_ensure_traffic_director()
		if _traffic_director != null:
			contacts.append_array(_traffic_director.get_traffic_contacts())
	return contacts


func on_motion_changed(speed: float, heading_deg: float, boosting: bool) -> void:
	_hud.set_motion(speed, heading_deg, boosting)


func on_operating_state_changed(state: ShipOperatingState) -> void:
	_hud.set_operating_state(state)
	if _player.assembled_ship != null:
		var signature := SensorSystem.live_signature(_player.assembled_ship, state)
		var transponder_label := "on" if state.transponder_broadcasting else "off"
		var active_sensors_label := active_sensors_hud_label(_player.assembled_ship, state)
		_hud.set_signature_state(signature, transponder_label, active_sensors_label)


func _setup_volatile_site_traffic(world: Node2D) -> void:
	_ensure_traffic_director()
	if _traffic_director == null:
		return
	var sector_id: String = _main.session.sector_id
	var record := VolatileTranslation.find_by_sector_id(_main.session, sector_id)
	if record.is_empty():
		clear_traffic()
		return
	var setup: Dictionary = record.get("setup", {})
	if typeof(setup) != TYPE_DICTIONARY:
		clear_traffic()
		return
	var traffic_config := _catalog.get_traffic_config()
	var roster: Array = []
	var ambient_ships: Variant = setup.get("ambient_ships", [])
	if typeof(ambient_ships) == TYPE_ARRAY:
		for ship_variant in ambient_ships:
			if typeof(ship_variant) != TYPE_DICTIONARY:
				continue
			var ship_record: Dictionary = ship_variant
			var actor = TrafficSpawnScript.create_from_ambient_ship(
				_catalog,
				traffic_config,
				ship_record,
				sector_id
			)
			if actor != null:
				roster.append(actor)
	var bounty_target: Variant = setup.get("bounty_target", {})
	if typeof(bounty_target) == TYPE_DICTIONARY and not bounty_target.is_empty():
		var target: Dictionary = bounty_target
		var target_id := str(target.get("id", ""))
		if (
			target_id.is_empty()
			or not _main.session.player.has_contact_record(target_id, "bounty_target")
		):
			var bounty_actor = TrafficSpawnScript.create_from_bounty_target(
				_catalog,
				traffic_config,
				target,
				sector_id
			)
			if bounty_actor != null:
				roster.append(bounty_actor)
			var escorts: Variant = setup.get("bounty_escorts", [])
			if typeof(escorts) == TYPE_ARRAY:
				for escort_variant in escorts:
					if typeof(escort_variant) != TYPE_DICTIONARY:
						continue
					var escort_actor = TrafficSpawnScript.create_from_bounty_target(
						_catalog,
						traffic_config,
						escort_variant,
						sector_id
					)
					if escort_actor != null:
						roster.append(escort_actor)
	if roster.is_empty():
		clear_traffic()
		return
	_traffic_director.setup_scripted_volatile_roster(
		_catalog,
		sector_id,
		_world_loader.get_traffic_envelope_radius(),
		_player.global_position,
		roster
	)
	if _traffic_view != null:
		_traffic_view.setup(world)
		_traffic_view.sync(_traffic_director.actors, _catalog)


func _tick_volatile_site_traffic(delta: float, physics_frame: int) -> void:
	if _traffic_director == null or _traffic_director.actors.is_empty():
		return
	var player_broadcasting: bool = (
		_player.operating_state.transponder_broadcasting
		if _player.assembled_ship != null
		else false
	)
	_traffic_director.tick(
		delta,
		_player.global_position,
		_world_loader,
		physics_frame,
		_player.motion.velocity,
		_player.motion.facing,
		_player.motion.is_thrusting(),
		_player.assembled_ship,
		_player.operating_state,
		player_broadcasting,
		_main.session.world
	)
	if _traffic_view != null:
		_traffic_view.sync(_traffic_director.actors, _catalog)


func _ensure_traffic_director() -> void:
	if _traffic_director != null:
		return
	_traffic_director = TrafficDirectorScript.new()
	_traffic_view = TrafficViewScript.new()


static func _filter_topology_contacts(contacts: Array) -> Array:
	var filtered: Array = []
	for contact_variant in contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if str(contact.get("id", "")) == "exit_portal":
			continue
		filtered.append(contact)
	return filtered


static func active_sensors_hud_label(assembled: AssembledShip, state: ShipOperatingState) -> String:
	if assembled == null or not assembled.has_active_sensor_package():
		return ""
	if state == null:
		return "off"
	return "on" if bool(state.active_systems.get("active_sensors", false)) else "off"
