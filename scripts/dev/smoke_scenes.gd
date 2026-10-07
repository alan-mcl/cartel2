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
	if _failures > 0:
		push_error("Scene smoke suite failed with %d assertion(s)." % _failures)
		quit(1)
		return
	print("=== scene smoke suite passed ===")
	quit(0)


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
	stack.queue_free()
	await process_frame


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
	world_root.queue_free()
	await process_frame


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
	sandbox.queue_free()
	await process_frame


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
	tester.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("SMOKE PASS: %s" % label)
		return
	_failures += 1
	push_error("SMOKE FAIL: %s" % label)
