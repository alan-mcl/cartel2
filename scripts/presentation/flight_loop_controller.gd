class_name FlightLoopController
extends RefCounted

const TrafficDirectorScript := preload("res://scripts/gameplay/traffic_director.gd")
const TrafficViewScript := preload("res://scripts/presentation/traffic_view.gd")
const TransponderBroadcastScript := preload("res://scripts/gameplay/transponder_broadcast.gd")

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
		_hud.set_star_lens_flare({}, _player.global_position, _player.motion.facing, _camera)
		return

	# Display-rate cadence: HUD nav/signature and traffic tick every physics frame.
	if not _main.session.in_unspace:
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

	var landmark_contacts := _world_loader.get_nav_contacts(_catalog, _main.session.in_unspace)
	var contacts: Array = []
	contacts.append_array(landmark_contacts)
	if _main.session.in_unspace and not _main.player_ship.has_capability("4_space_topology"):
		contacts = _filter_topology_contacts(contacts)
	if not _main.session.in_unspace and _traffic_director != null:
		contacts.append_array(_traffic_director.get_traffic_contacts())

	var nav_radius: float = _main.play_bounds
	if not _main.session.in_unspace:
		nav_radius = _world_loader.get_content_radius()

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
		player_broadcast
	)
	if _main.session.in_unspace:
		_hud.set_star_lens_flare({}, _player.global_position, _player.motion.facing, _camera)
	else:
		_hud.set_star_lens_flare(
			_world_loader.get_local_star_display(),
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


func on_motion_changed(speed: float, heading_deg: float, boosting: bool) -> void:
	_hud.set_motion(speed, heading_deg, boosting)


func on_operating_state_changed(state: ShipOperatingState) -> void:
	_hud.set_operating_state(state)
	if _player.assembled_ship != null:
		var signature := SensorSystem.live_signature(_player.assembled_ship, state)
		var transponder_label := "on" if state.transponder_broadcasting else "off"
		var active_sensors_label := active_sensors_hud_label(_player.assembled_ship, state)
		_hud.set_signature_state(signature, transponder_label, active_sensors_label)


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
