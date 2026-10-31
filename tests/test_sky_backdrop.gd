class_name TestSkyBackdrop
extends RefCounted

const LocalStarScript := preload("res://scripts/presentation/local_star.gd")


static func run(runner: TestRunner, tree: SceneTree = null) -> void:
	_test_angular_radius_math(runner)
	_test_parent_params(runner)
	_test_titania_angular_roll(runner, tree)
	_test_sector_spawns(runner, tree)


static func _test_angular_radius_math(runner: TestRunner) -> void:
	var distance := 8000.0
	var radius := SkyBackdropLayout.disc_radius_from_angular(14.0, distance)
	runner.check(radius > 900.0 and radius < 1100.0, "sky backdrop: 14 deg disc radius at 8k")
	var min_dist := SkyBackdropLayout.min_distance_for_parent(20.0, 2.2)
	runner.check(min_dist >= SkyBackdropLayout.STAR_MIN_RADIUS, "sky backdrop: parent min distance on annulus")
	runner.check(
		min_dist - SkyBackdropLayout.disc_radius_from_angular(20.0, min_dist) * 2.2
		>= SkyBackdropLayout.INNER_CLEARANCE_RADIUS - 1.0,
		"sky backdrop: broad parent clears play ring"
	)


static func _test_parent_params(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var world := catalog.get_world("titania")
	var parent_data: Dictionary = world.get("parent_body", {})
	var resolved := SkyParentBodyParams.resolve_from_parent(parent_data)
	runner.check(str(resolved.get("type_label", "")) == "Gas giant", "sky backdrop: type label")
	var appearance: Dictionary = resolved.get("appearance", {})
	runner.check(
		str(appearance.get("band_colour_1", "")) == "#857052",
		"sky backdrop: band colour from world"
	)
	var rings: Dictionary = resolved.get("rings", {})
	runner.check(
		absf(SkyParentBodyParams.ring_outer_scale(rings) - 1.0) < 0.001,
		"sky backdrop: none ring outer_scale 1"
	)
	var typhon_world := catalog.get_world("typhon_xvi")
	var typhon: Dictionary = typhon_world.get("parent_body", {})
	var typhon_resolved := SkyParentBodyParams.resolve_from_parent(typhon)
	var typhon_rings: Dictionary = typhon_resolved.get("rings", {})
	runner.check(
		absf(SkyParentBodyParams.ring_outer_scale(typhon_rings) - 2.2) < 0.01,
		"sky backdrop: broad legacy ring outer radius 2.2"
	)


static func _test_titania_angular_roll(runner: TestRunner, tree: SceneTree) -> void:
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		runner.check(false, "sky backdrop: SceneTree for titania roll")
		return
	var catalog := Catalog.load_default()
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "SKY-2", "tester"), "sky backdrop: session for titania roll")
	var host := Node2D.new()
	tree.root.add_child(host)
	for _attempt in range(12):
		for child in host.get_children():
			child.free()
		var loader := WorldLoader.new()
		loader.load_sector(host, catalog, session, "titania")
		var parent: Variant = loader.spawned_by_id.get("parent_body")
		runner.check(parent != null, "sky backdrop: titania parent on roll attempt")
		if parent != null and parent.has_method("get_angular_diameter_deg"):
			var angular := float(parent.call("get_angular_diameter_deg"))
			runner.check(angular >= 10.0 and angular <= 16.0, "sky backdrop: titania angular in 10-16")
	host.queue_free()


static func _test_sector_spawns(runner: TestRunner, tree: SceneTree) -> void:
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		runner.check(false, "sky backdrop: SceneTree available")
		return

	var catalog := Catalog.load_default()
	var host := Node2D.new()
	tree.root.add_child(host)
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "SKY-1", "tester"), "sky backdrop: session starts")

	_assert_world(runner, host, catalog, session, "titania", true, 0, 0)
	_assert_world(runner, host, catalog, session, "proxima", false, 2, 0)
	_assert_world(runner, host, catalog, session, "bela", false, 0, 0)
	_assert_world(runner, host, catalog, session, "pelagos", false, 1, 0)
	_assert_tycho_widow(runner, host, catalog, session)

	host.queue_free()


static func _assert_world(
	runner: TestRunner,
	host: Node2D,
	catalog: Catalog,
	session: GameSession,
	sector_id: String,
	expect_parent: bool,
	companion_count: int,
	_widow_index: int
) -> void:
	for child in host.get_children():
		child.free()
	var loader := WorldLoader.new()
	loader.load_sector(host, catalog, session, sector_id)
	runner.check(
		loader.spawned_by_id.has("parent_body") == expect_parent,
		"sky backdrop: %s parent_body spawn" % sector_id
	)
	runner.check(
		loader.get_companion_star_nav_entries().size() == companion_count,
		"sky backdrop: %s companion count" % sector_id
	)


static func _assert_tycho_widow(
	runner: TestRunner,
	host: Node2D,
	catalog: Catalog,
	session: GameSession
) -> void:
	for child in host.get_children():
		child.free()
	var loader := WorldLoader.new()
	loader.load_sector(host, catalog, session, "tycho")
	runner.check(loader.get_companion_star_nav_entries().size() == 2, "sky backdrop: tycho two companions")
	var widow_found := false
	for entry_variant in loader.get_companion_star_nav_entries():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("name", "")) == "The Widow":
			widow_found = true
			runner.check(bool(entry.get("presentation_only", false)), "sky backdrop: widow presentation-only")
			var render := {
				"temperature_k": entry.get("star_temperature_k", 0.0),
				"luminosity": entry.get("star_luminosity", 0.0),
				"disc_radius": 3.0,
			}
			var resolved := LocalStarScript.defaults_from_star_data(render)
			runner.check(
				absf(float(resolved.get("disc_radius", 0.0)) - 3.0) < 0.01,
				"sky backdrop: widow disc radius 3"
			)
	var world := catalog.get_world("tycho")
	var companions: Array = world.get("companion_stars", [])
	var widow_sep := -1.0
	for entry_variant in companions:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("name", "")) == "The Widow":
			widow_sep = float(entry.get("separation_deg", -1.0))
	runner.check(widow_found, "sky backdrop: tycho widow nav entry")
	runner.check(absf(widow_sep - 1.2) < 0.01, "sky backdrop: widow separation 1.2 deg")
