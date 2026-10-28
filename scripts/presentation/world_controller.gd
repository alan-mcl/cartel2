class_name WorldController
extends RefCounted

const UNSPACE_TINT := Color(0.1, 0.08, 0.14, 1.0)

var _world_loader := WorldLoader.new()
var _world: Node2D
var _starfield: Node2D
var _player: CharacterBody2D
var _pause: CanvasLayer
var _jump: CanvasLayer
var _hyperdrive: CanvasLayer
var _hud: CanvasLayer
var _ui_root: CanvasLayer
var _main: Node2D
var _catalog: Catalog
var _simulation: Simulation
var _flight: FlightLoopController
var _tree: SceneTree
var _on_session_changed: Callable
var _on_interaction_target_changed: Callable


func bind(
	main: Node2D,
	world: Node2D,
	starfield: Node2D,
	player: CharacterBody2D,
	pause: CanvasLayer,
	jump: CanvasLayer,
	hyperdrive: CanvasLayer,
	hud: CanvasLayer,
	ui_root: CanvasLayer,
	catalog: Catalog,
	simulation: Simulation,
	flight: FlightLoopController,
	tree: SceneTree,
	on_session_changed: Callable,
	on_interaction_target_changed: Callable
) -> void:
	_main = main
	_world = world
	_starfield = starfield
	_player = player
	_pause = pause
	_jump = jump
	_hyperdrive = hyperdrive
	_hud = hud
	_ui_root = ui_root
	_catalog = catalog
	_simulation = simulation
	_flight = flight
	_tree = tree
	_on_session_changed = on_session_changed
	_on_interaction_target_changed = on_interaction_target_changed


func get_loader() -> WorldLoader:
	return _world_loader


func clear_world() -> void:
	_flight.clear_traffic()
	_world_loader.clear_world(_world)


func load_current_space(place_player: bool = true) -> void:
	if _main.session.in_unspace:
		load_unspace(place_player)
	else:
		load_current_sector(place_player)


func load_current_sector(place_player: bool = true, spawn_near: String = "") -> void:
	_set_play_bounds(
		_world_loader.load_sector(_world, _catalog, _main.session, _main.session.sector_id)
	)
	if _starfield.has_method("set_unspace_mode"):
		_starfield.set_unspace_mode(false)
	else:
		_starfield.reset_tint()
	_finalize_world_load(place_player, spawn_near)


func load_unspace(place_player: bool = true) -> void:
	_set_play_bounds(
		_world_loader.load_unspace(_world, _catalog, _main.session, _main.session.unspace_world_id)
	)
	if _starfield.has_method("set_unspace_mode"):
		_starfield.set_unspace_mode(true)
	elif _starfield.has_method("set_tint"):
		_starfield.set_tint(UNSPACE_TINT)
	_finalize_world_load(place_player)


func apply_salvage_visuals() -> void:
	_world_loader.apply_salvage_visuals(_main.session)


func capture_flight_state() -> Dictionary:
	return {
		"x": _player.global_position.x,
		"y": _player.global_position.y,
		"vx": _player.motion.velocity.x,
		"vy": _player.motion.velocity.y,
		"facing": _player.motion.facing,
	}


func apply_flight_state(flight: Dictionary) -> void:
	if typeof(flight) != TYPE_DICTIONARY or flight.is_empty():
		if not _main.session.docked:
			if _main.session.in_unspace:
				_player.global_position = _main.session.get_spawn_position(_catalog)
			else:
				_player.global_position = _world_loader.get_habitat_launch_position()
		_player.freeze_motion()
		return

	_player.global_position = Vector2(
		float(flight.get("x", 0.0)),
		float(flight.get("y", 0.0))
	)
	_player.motion.velocity = Vector2(
		float(flight.get("vx", 0.0)),
		float(flight.get("vy", 0.0))
	)
	_player.motion.facing = float(flight.get("facing", -PI / 2.0))
	_player.velocity = _player.motion.velocity

	if _main.session.docked:
		_player.freeze_motion()


func try_interact(target: Interactable) -> void:
	if not _main.game_active or target == null or target.definition == null:
		return

	match target.definition.kind:
		InteractableDef.Kind.DOCK:
			dock_at(target.definition.dock_location_id)
		InteractableDef.Kind.TRANSLATE:
			if not _main.session.in_unspace:
				open_jump_overlay(target.get_title())
		InteractableDef.Kind.ARRIVE:
			arrive_from_unspace()
		_:
			var result := target.interact(_main.session)
			if result.is_empty():
				return
			_on_session_changed.call()
			_on_interaction_target_changed.call(_player.get_current_target())
			_world_loader.apply_salvage_visuals(_main.session)


func try_hyperdrive_spool() -> void:
	if (
		_main.session.docked
		or _main.session.in_unspace
		or _jump.visible
		or (_hyperdrive != null and _hyperdrive.visible)
	):
		return
	var thrusting := false
	var boosting := false
	var motion = _player.get("motion")
	if motion != null:
		if motion.has_method("is_thrusting"):
			thrusting = motion.is_thrusting()
		if motion.has_method("is_boosting"):
			boosting = motion.is_boosting()
	var owned: OwnedShip = _main.session.get_current_owned_ship()
	if owned == null:
		return
	var result := Hyperdrive.spool_block(
		_catalog,
		_main.session,
		_main.player_ship,
		owned,
		_player.global_position,
		thrusting,
		boosting
	)
	if not bool(result.get("ok", false)):
		var message := str(result.get("message", ""))
		if not message.is_empty():
			_main.session.last_log = message
			_on_session_changed.call()
		return
	open_hyperdrive_overlay(str(result.get("title", "Hyperdrive")))


func open_hyperdrive_overlay(module_title: String) -> void:
	if _main.session.docked or _main.session.in_unspace:
		return
	var module_def := Hyperdrive.fitted_module(_main.player_ship)
	if module_def == null:
		return
	_tree.paused = true
	_pause.close()
	if _hyperdrive.has_method("set_assembled_ship"):
		_hyperdrive.set_assembled_ship(_main.player_ship)
	if _hyperdrive.has_method("bind"):
		_hyperdrive.bind(_catalog, _main.session, _main.player_ship, module_def)
	_hyperdrive.open(module_title)
	_on_interaction_target_changed.call(_player.get_current_target())


func on_hyperdrive_calculation_requested(target_sector_id: String, n: int) -> void:
	if target_sector_id.is_empty():
		return
	var module_def := Hyperdrive.fitted_module(_main.player_ship)
	var result := HyperdriveSolution.start_calculation(
		_main.session,
		_catalog,
		_main.player_ship,
		target_sector_id,
		n,
		module_def
	)
	_tree.paused = false
	if bool(result.get("ok", false)):
		_main.session.last_log = str(result.get("message", ""))
	else:
		_main.session.last_log = str(result.get("message", "Calculation refused."))
	_on_session_changed.call()


func on_hyperdrive_jump_requested(target_sector_id: String, n: int, solution: int) -> void:
	_tree.paused = false
	on_jump_requested(target_sector_id, n, solution)


func on_hyperdrive_cancelled() -> void:
	_tree.paused = false
	_on_interaction_target_changed.call(_player.get_current_target())


func open_jump_overlay(gate_title: String) -> void:
	if _main.session.docked or _main.session.in_unspace:
		return

	_tree.paused = true
	_pause.close()
	if _jump.has_method("set_assembled_ship"):
		_jump.set_assembled_ship(_main.player_ship)
	_jump.open(gate_title)
	_on_interaction_target_changed.call(_player.get_current_target())


func on_jump_requested(target_sector_id: String, n: int, solution: int) -> void:
	if target_sector_id.is_empty():
		return

	var origin_id: String = _main.session.sector_id
	var mapping := _catalog.get_translation(origin_id, solution)
	if mapping.is_empty():
		mapping = VolatileTranslation.resolve_mapping(
			_main.session,
			_catalog,
			origin_id,
			target_sector_id,
			n,
			solution
		)
	if mapping.is_empty():
		return

	var offer_accuracy := TranslationNav.compute_accuracy(
		float(TranslationNav.nav_stats_from_ship(_main.player_ship, _catalog).get("nav_rating", 0.0)),
		n,
		float(mapping.get("ease", 0.5))
	)
	var combat_state: ShipCombatState = _main.session.build_combat_state(_main.player_ship)
	_main.session.translation_stability = TranslationNav.roll_stability(
		offer_accuracy,
		n,
		_player.operating_state,
		_main.player_ship,
		combat_state
	)

	if not _main.session.enter_unspace(_catalog, target_sector_id, n, _main.player_ship, solution):
		_main.session.translation_stability = -1.0
		return

	var applied := _simulation.apply_mapping_lump(_main.session, mapping, "entry_seconds", _catalog)
	if applied > 0.0:
		_main.session.last_log = (
			"Translation complete. Entry lag %s. %s-space stability %d%%."
			% [
				GalacticCalendar.format_duration(applied),
				n,
				int(round(_main.session.translation_stability)),
			]
		)
	_simulation.reset_unspace_pulse()

	load_unspace(true)
	_jump.close()
	_tree.paused = false
	_on_session_changed.call()
	_on_interaction_target_changed.call(_player.get_current_target())


func arrive_from_unspace() -> void:
	if not _main.session.in_unspace:
		return

	var origin_id: String = _main.session.sector_id
	var dest_id: String = _main.session.pending_destination_id
	var solution: int = _main.session.unspace_solution
	var unspace_n: int = _main.session.unspace_n
	# Snapshot before arrival. Outbound marks the grant consumed on entry, and a
	# successful return deletes the record inside arrive_from_unspace.
	var mapping := _exit_mapping(origin_id, dest_id, unspace_n, solution)

	if not _main.session.arrive_from_unspace(_catalog):
		return

	var applied := _simulation.apply_mapping_lump(_main.session, mapping, "exit_seconds", _catalog)
	var sector_name := dest_id
	if VolatileTranslation.is_volatile_sector_id(dest_id):
		var volatile_record := VolatileTranslation.find_by_sector_id(_main.session, dest_id)
		sector_name = str(volatile_record.get("label", dest_id))
	else:
		var sector := _catalog.get_sector_def(dest_id)
		if sector != null and sector.has_source_key("name"):
			sector_name = sector.name
		else:
			sector_name = dest_id
	_main.session.last_log = (
		"Translation complete. Exit lag %s. Welcome to %s."
		% [GalacticCalendar.format_duration(applied), sector_name]
	)

	load_current_sector(true, "jump_gate")
	_on_session_changed.call()
	_on_interaction_target_changed.call(_player.get_current_target())


func _exit_mapping(origin_id: String, dest_id: String, unspace_n: int, solution: int) -> Dictionary:
	var mapping := _catalog.get_translation(origin_id, solution)
	if mapping.is_empty():
		mapping = VolatileTranslation.transit_mapping(
			_main.session,
			origin_id,
			dest_id,
			unspace_n,
			solution
		)
	if mapping.is_empty() and not VolatileTranslation.is_volatile_sector_id(origin_id):
		mapping = _catalog.get_public_translation(origin_id, dest_id, unspace_n if unspace_n > 0 else 4)
	return mapping


func on_jump_cancelled() -> void:
	_tree.paused = false
	_on_interaction_target_changed.call(_player.get_current_target())


func dock_at(location_id: String) -> void:
	if location_id.is_empty() or _main.session.docked:
		return

	if not _main.session.dock(_catalog, location_id):
		return

	_player.freeze_motion()
	_tree.paused = true
	_pause.close()
	_hud.visible = false
	_ui_root.session = _main.session
	_ui_root.sync_context_callbacks()
	_ui_root.open_habitat()
	AudioService.play_music("habitat")
	AudioService.play_ambience("habitat")
	AudioService.set_ship_thrust(0.0, false, _player.global_position)
	_on_session_changed.call()
	_on_interaction_target_changed.call(_player.get_current_target())


func on_ui_undock_requested(ship_id: String) -> void:
	if ship_id.is_empty() or not _main.session.docked:
		return

	var dock_location_id: String = _main.session.habitat_id
	var missions := _simulation.get_subsystem("missions") as MissionSubsystem
	if not _main.session.undock(_catalog, ship_id, missions):
		return

	_main.player_ship = assemble_current_ship()
	_player.configure(
		_main.player_ship,
		_main.session.get_current_owned_ship(),
		_catalog,
		_main.session
	)
	_hud.bind(_main.session, _player, _main.player_ship, _simulation, _catalog)
	_hud.set_weapon_select_handler(Callable(_player, "select_weapon_slot"))
	var launch_pos := _world_loader.get_dock_launch_position(dock_location_id)
	var dock_pos := _world_loader.get_dock_world_position(dock_location_id)
	var outward := (launch_pos - dock_pos).normalized()
	if outward.length_squared() < 0.001:
		outward = Vector2.UP

	_tree.paused = false
	_ui_root.close_ui()
	_hud.visible = true
	_hud.clear_message_log()
	_pause.close()
	_on_session_changed.call()

	_player.global_position = launch_pos
	_player.apply_launch_velocity(_world_loader.get_undock_exit_velocity(dock_location_id), outward.angle())
	AudioService.play_music("exploration")
	AudioService.play_ambience("space")
	_on_interaction_target_changed.call(_player.get_current_target())


func on_ui_ship_changed(ship_id: String) -> void:
	if ship_id != _main.session.current_ship_id:
		return
	_main.player_ship = assemble_current_ship()
	_player.configure(
		_main.player_ship,
		_main.session.get_current_owned_ship(),
		_catalog,
		_main.session
	)
	_hud.set_assembled_ship(_main.player_ship)
	if _jump.has_method("set_assembled_ship"):
		_jump.set_assembled_ship(_main.player_ship)


func assemble_current_ship() -> AssembledShip:
	var owned: OwnedShip = _main.session.get_current_owned_ship()
	if owned == null:
		return AssembledShip.new()
	return ShipAssembler.assemble_owned(_catalog, owned)


func _finalize_world_load(place_player: bool = true, spawn_near: String = "") -> void:
	if _player.has_method("register_world_interactables"):
		_player.register_world_interactables()

	_flight.clear_traffic()
	if not _main.session.in_unspace:
		_flight.setup_traffic(_world)

	if place_player:
		match spawn_near:
			"habitat":
				_player.global_position = _world_loader.get_habitat_launch_position()
			"jump_gate":
				_player.global_position = _world_loader.get_jump_gate_approach_position()
			_:
				_player.global_position = _main.session.get_spawn_position(_catalog)
		_player.freeze_motion()


func _set_play_bounds(value: float) -> void:
	_main.play_bounds = value
