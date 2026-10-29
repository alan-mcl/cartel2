extends SceneTree

## Lightweight rendered-boundary smoke suite. Run through scripts/ci/smoke_scenes.sh;
## the wrapper turns Godot engine/script errors into a failing command.

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var catalog := Catalog.load_default()
	await _smoke_embedded_shipyard(catalog)
	await _smoke_save_loaded_world(catalog)
	await _smoke_combat_motion()
	await _smoke_system_render_tester()
	await _smoke_mission_harness()
	await _smoke_audio_sandbox()
	await _finish()


func _finish() -> void:
	await _drain_root_children()
	ChassisSprite.clear_cache()
	AudioService.stop_music(true)
	AudioService.stop_ambience(true)
	AudioService.set_ship_thrust(0.0, false, Vector2.ZERO)
	AudioService.release_playback_streams()
	await _pump_frames(2)
	var audio_mgr := root.get_node_or_null("AudioManager")
	if audio_mgr != null:
		AudioService.unbind_manager(audio_mgr)
	if _failures > 0:
		push_error("Scene smoke suite failed with %d assertion(s)." % _failures)
		quit(1)
		return
	print("=== scene smoke suite passed ===")
	quit(0)


func _pump_frames(count: int) -> void:
	for _i in count:
		await process_frame
		await physics_frame


func _invoke_smoke_teardown(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.has_method("smoke_teardown"):
		node.smoke_teardown()
	elif node.has_method("smoke_shutdown"):
		node.smoke_shutdown()
	elif node.has_method("smoke_unload"):
		node.smoke_unload()


func _destroy_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_invoke_smoke_teardown(node)
	node.free()


func _free_and_drain(node: Node) -> void:
	_destroy_node(node)
	await _pump_frames(2)


func _drain_root_children() -> void:
	for child in root.get_children():
		if child.name == "AudioManager":
			continue
		if is_instance_valid(child):
			child.free()
	await _pump_frames(2)


func _smoke_embedded_shipyard(catalog: Catalog) -> void:
	var session := GameSession.new()
	_check(session.start_new_game(catalog, "SMOKE-UI", "trader"), "UI session starts")
	_check(session.visit(catalog, "proxima_shipyard"), "UI can select shipyard building")
	var stack := ScreenStack.new()
	root.add_child(stack)
	var screen := preload("res://scenes/ui/habitat_screen.tscn").instantiate()
	stack.push_screen(screen)
	var context := UiContext.new()
	context.catalog = catalog
	context.session = session
	context.stack = stack
	screen.bind(context)
	await process_frame
	_check(screen._building_item_list.item_count > 0, "habitat lists buildings")
	_check(screen._embedded_panel != null, "habitat embeds selected building panel")
	_check(
		screen._embedded_panel != null and screen._embedded_panel is Control,
		"embedded shipyard is a control"
	)
	await _free_and_drain(stack)


func _smoke_save_loaded_world(catalog: Catalog) -> void:
	var session := GameSession.new()
	_check(session.start_new_game(catalog, "SMOKE-WORLD", "trader"), "world session starts")
	var save_data := SaveStore.build_save_data(
		session.player_to_dict(), session.to_dict(), session.ships_to_array(), {}, {}
	)
	var loaded := GameSession.new()
	_check(loaded.from_save(catalog, save_data), "fresh save loads before rendering")
	var world_root := Node2D.new()
	root.add_child(world_root)
	var loader := WorldLoader.new()
	loader.load_sector(world_root, catalog, loaded, loaded.sector_id)
	await process_frame
	_check(world_root.get_child_count() > 0, "sector load creates rendered world nodes")
	loader.load_unspace(world_root, catalog, loaded, "n4_default")
	await process_frame
	_check(world_root.get_node_or_null("NspaceField") != null, "unspace load creates field")
	_check(not loader.get_nav_contacts(catalog, true).is_empty(), "unspace exposes exit nav contact")
	loader.clear_world(world_root)
	await _free_and_drain(world_root)


func _smoke_combat_motion() -> void:
	var sandbox := preload("res://scenes/dev/combat_sandbox.tscn").instantiate()
	root.add_child(sandbox)
	await process_frame
	sandbox._on_begin_pressed()
	var opponent = sandbox._opponent_actor
	_check(opponent != null, "combat sandbox spawns opponent")
	if opponent != null:
		var start: Vector2 = opponent.position
		# The pilot may spend its first physics ticks establishing a contact and
		# maneuver intent. Observe a full second of simulation rather than relying
		# on a single-frame motion impulse.
		for _frame in range(60):
			await physics_frame
		_check(
			opponent.position.distance_to(start) > 0.01,
			"combat sandbox opponent simulation advances"
		)
		_check(
			sandbox._opponent_node != null
			and sandbox._opponent_node.global_position.distance_to(opponent.position) < 1.0,
			"combat sandbox opponent visual follows simulation"
		)
	paused = false
	await _free_and_drain(sandbox)


func _smoke_mission_harness() -> void:
	var harness := preload("res://scenes/dev/mission_harness.tscn").instantiate()
	root.add_child(harness)
	await process_frame
	await process_frame
	var ok: bool = harness.smoke_begin_site_only("deep_space")
	_check(ok, "mission harness begins site-only run")
	await process_frame
	var main: Node2D = harness.get_node("Main")
	_check(
		VolatileTranslation.is_volatile_sector_id(main.session.sector_id),
		"mission harness session in volatile sector"
	)
	_check(not main.session.docked, "mission harness player undocked")
	var world: Node2D = main.get_node("World")
	_check(world.get_child_count() > 0, "mission harness loads volatile world")
	paused = false
	await _free_and_drain(harness)


func _smoke_audio_sandbox() -> void:
	var sandbox := preload("res://scenes/dev/audio_sandbox.tscn").instantiate()
	root.add_child(sandbox)
	await process_frame
	await _free_and_drain(sandbox)


func _smoke_system_render_tester() -> void:
	var tester := preload("res://scenes/dev/system_render_tester.tscn").instantiate()
	root.add_child(tester)
	await process_frame
	var world: Node2D = tester.get_node("World")
	var has_layout := (
		world.get_node_or_null("Planet") != null
		or world.get_node_or_null("OrbitalRing") != null
	)
	_check(has_layout, "system render tester loads sector layout")
	_check(tester.get_node_or_null("PlayerShip") == null, "system render tester has no player ship")
	var label_overlay: Node = tester.get_node_or_null("Overlay/Root/CityMallLabelOverlay")
	_check(label_overlay != null, "system render tester has city-mall labels")
	await _free_and_drain(tester)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("SMOKE PASS: %s" % label)
		return
	_failures += 1
	push_error("SMOKE FAIL: %s" % label)
