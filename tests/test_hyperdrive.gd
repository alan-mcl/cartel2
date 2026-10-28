class_name TestHyperdrive
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_sku_ladder(runner, catalog)
	_test_no_module(runner, catalog)
	_test_unspace_and_volatile_blocked(runner, catalog)
	_test_proxima_distance(runner, catalog)
	_test_dragon_post_thrust_budget(runner, catalog)
	_test_dragon_gold_thrust_budget(runner, catalog)
	_test_solution_calculation(runner, catalog)
	_test_off_network_compute_rules(runner, catalog)
	_test_calc_duration_minutes(runner, catalog)
	_test_library_enter_unspace_off_network(runner, catalog)
	_test_calc_aborts_on_sector_change(runner, catalog)


static func _owned_for_template(catalog: Catalog, ship_id: String) -> OwnedShip:
	var owned := OwnedShip.from_template(
		catalog,
		{"template_id": ship_id, "id": "test_%s" % ship_id, "name": ship_id}
	)
	ShipAssembler.seed_ammunition(catalog, owned)
	return owned


static func _spool_ok(
	catalog: Catalog,
	session: GameSession,
	assembled: AssembledShip,
	owned: OwnedShip,
	position: Vector2,
	thrusting: bool
) -> bool:
	var result := Hyperdrive.spool_block(
		catalog, session, assembled, owned, position, thrusting, false
	)
	return bool(result.get("ok", false))


static func _session_in_sector(sector_id: String) -> GameSession:
	var session := GameSession.new()
	session.sector_id = sector_id
	session.docked = false
	session.in_unspace = false
	return session


static func _test_sku_ladder(runner: TestRunner, catalog: Catalog) -> void:
	var span := catalog.get_module_def("te_span_hyperdrive")
	var alpha := catalog.get_module_def("hyperdrive_alpha")
	var needle := catalog.get_module_def("ora_needle_hyperdrive")
	var vertex := catalog.get_module_def("prv_vertex_hyperdrive")
	runner.check(span.cost < alpha.cost, "hyperdrive: Span costs less than Alpha")
	runner.check(needle.cost > vertex.cost, "hyperdrive: Needle costs more than Vertex")
	var brands: Dictionary = {}
	for module_id in [
		"te_span_hyperdrive",
		"hyperdrive_alpha",
		"hw_aperture_hyperdrive",
		"prv_vertex_hyperdrive",
		"ora_needle_hyperdrive",
	]:
		var module_def := catalog.get_module_def(module_id)
		runner.check(module_def != null, "hyperdrive: %s exists" % module_id)
		if module_def == null:
			continue
		runner.check(not module_def.brand.is_empty(), "hyperdrive: %s has brand" % module_id)
		brands[module_def.brand] = true
	runner.check_eq(brands.size(), 5, "hyperdrive: five distinct brands")


static func _test_no_module(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := ShipAssembler.assemble(catalog, "dragon_bronze")
	var owned := _owned_for_template(catalog, "dragon_bronze")
	var session := _session_in_sector("proxima")
	var gate: float = FieldConditions._world_radii(catalog, "proxima").gate_radius
	runner.check(
		not _spool_ok(catalog, session, assembled, owned, Vector2(gate + 100.0, 0.0), false),
		"hyperdrive: bronze without coil refused"
	)


static func _test_unspace_and_volatile_blocked(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := ShipAssembler.assemble(catalog, "dragon_post")
	var owned := _owned_for_template(catalog, "dragon_post")
	var session := _session_in_sector("proxima")
	session.in_unspace = true
	runner.check(
		not _spool_ok(catalog, session, assembled, owned, Vector2(6000.0, 0.0), false),
		"hyperdrive: refused in unspace"
	)
	session.in_unspace = false
	session.sector_id = VolatileTranslation.sector_id_for("vt_test")
	runner.check(
		not _spool_ok(catalog, session, assembled, owned, Vector2(6000.0, 0.0), false),
		"hyperdrive: refused on volatile site"
	)


static func _test_proxima_distance(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := ShipAssembler.assemble(catalog, "dragon_post")
	var owned := _owned_for_template(catalog, "dragon_post")
	var session := _session_in_sector("proxima")
	var gate: float = FieldConditions._world_radii(catalog, "proxima").gate_radius
	runner.check(
		not _spool_ok(catalog, session, assembled, owned, Vector2(gate - 200.0, 0.0), false),
		"hyperdrive: inside gate radius refused"
	)
	runner.check(
		_spool_ok(catalog, session, assembled, owned, Vector2(gate + 200.0, 0.0), false),
		"hyperdrive: Dragon Post coasts outside gate"
	)


static func _test_dragon_post_thrust_budget(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := ShipAssembler.assemble(catalog, "dragon_post")
	var owned := _owned_for_template(catalog, "dragon_post")
	var session := _session_in_sector("proxima")
	var gate: float = FieldConditions._world_radii(catalog, "proxima").gate_radius
	var pos := Vector2(gate + 200.0, 0.0)
	runner.check(
		not _spool_ok(catalog, session, assembled, owned, pos, true),
		"hyperdrive: Dragon Post under thrust refused"
	)


static func _assembled_with_nav(catalog: Catalog, nav_module_id: String) -> AssembledShip:
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "test_hd_nav",
			"template_id": "flare_on_ss",
			"chassis_id": "flare_on_chassis",
		}
	)
	for entry_variant in owned.modules:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var slot := str(entry.get("slot", ""))
		var existing_id := str(entry.get("module_id", ""))
		var module_def := catalog.get_module_def(existing_id)
		if module_def != null and str(module_def.category) == "navigation":
			owned.set_module(slot, nav_module_id)
			return ShipAssembler.assemble_owned(catalog, owned)
	owned.set_module("system_5", nav_module_id)
	return ShipAssembler.assemble_owned(catalog, owned)


static func _test_solution_calculation(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "HD-1", "tester"), "hyperdrive calc new game")
	session.docked = false
	var assembled := _assembled_with_nav(catalog, "sne_astrolabe")
	var module := catalog.get_module_def("hyperdrive_alpha")
	runner.check(module != null, "hyperdrive_alpha for calc test")
	var deep := HyperdriveSolution.calculation_seconds(12, 9, 55.0, 42.0)
	var shallow := HyperdriveSolution.calculation_seconds(12, 4, 55.0, 42.0)
	runner.check(deep > shallow, "deeper N costs more GST to calculate")
	var start := HyperdriveSolution.start_calculation(
		session, catalog, assembled, "tokirev", 5, module
	)
	runner.check(bool(start.get("ok", false)), "start calculation proxima→tokirev 5-space")
	runner.check(HyperdriveSolution.is_active(session), "calc active after start")
	HyperdriveSolution.force_complete_for_tests(session, catalog, true)
	runner.check(not HyperdriveSolution.is_active(session), "calc completes")
	runner.check_eq(session.player.translation_library.size(), 1, "success appends library row")
	var entry: Dictionary = session.player.translation_library[0]
	runner.check_eq(str(entry.get("target", "")), "tokirev", "stored target")
	runner.check_eq(int(entry.get("n", 0)), 5, "stored depth")
	start = HyperdriveSolution.start_calculation(session, catalog, assembled, "fennet", 5, module)
	runner.check(bool(start.get("ok", false)), "start second calc")
	HyperdriveSolution.force_complete_for_tests(session, catalog, false)
	runner.check_eq(session.player.translation_library.size(), 1, "failed calc stores nothing")
	HyperdriveSolution.cancel(session, "test cancel")
	runner.check(not HyperdriveSolution.is_active(session), "cancel clears calc")


static func _test_calc_duration_minutes(runner: TestRunner, catalog: Catalog) -> void:
	var seconds := HyperdriveSolution.calculation_seconds(40, 6, 70.0, 50.0)
	runner.check(
		seconds >= HyperdriveSolution.MIN_CALC_SECONDS,
		"hyperdrive calc: at least min duration"
	)
	runner.check(
		seconds <= HyperdriveSolution.MAX_CALC_SECONDS,
		"hyperdrive calc: at most max duration (3 min)"
	)
	runner.check_eq(HyperdriveSolution.MIN_CALC_SECONDS, 15.0, "hyperdrive calc: min is 15s")
	runner.check_eq(HyperdriveSolution.MAX_CALC_SECONDS, 180.0, "hyperdrive calc: max is 3 min")


static func _test_off_network_compute_rules(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "HD-2", "tester"), "off-network calc new game")
	session.docked = false
	session.sector_id = "tycho"
	var assembled := _assembled_with_nav(catalog, "sne_astrolabe")
	var module := catalog.get_module_def("hyperdrive_alpha")
	var tree := HyperdriveSolution.build_compute_spanning_tree(catalog, "tycho")
	var has_acb1 := false
	for row_variant in tree:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		if str((row_variant as Dictionary).get("target", "")) == "acb1":
			has_acb1 = true
	runner.check(has_acb1, "hyperdrive tree: tycho includes acb1")
	runner.check(
		not HyperdriveSolution.is_direct_public_edge(catalog, "tycho", "acb1"),
		"hyperdrive: tycho→acb1 is off-network"
	)
	var n5 := HyperdriveSolution.start_calculation(
		session, catalog, assembled, "acb1", 5, module
	)
	runner.check(not bool(n5.get("ok", false)), "hyperdrive: tycho→acb1 5-space refused")
	var n6 := HyperdriveSolution.start_calculation(
		session, catalog, assembled, "acb1", 6, module
	)
	runner.check(bool(n6.get("ok", false)), "hyperdrive: tycho→acb1 6-space allowed")
	HyperdriveSolution.cancel(session, "test cleanup")


static func _test_library_enter_unspace_off_network(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "HD-3", "tester"), "library jump new game")
	session.docked = false
	session.sector_id = "tycho"
	var assembled := _assembled_with_nav(catalog, "sne_astrolabe")
	var module := catalog.get_module_def("hyperdrive_alpha")
	var start := HyperdriveSolution.start_calculation(
		session, catalog, assembled, "acb1", 6, module
	)
	runner.check(bool(start.get("ok", false)), "library jump: start tycho→acb1")
	HyperdriveSolution.force_complete_for_tests(session, catalog, true)
	runner.check_eq(session.player.translation_library.size(), 1, "library jump: stored row")
	var entry: Dictionary = session.player.translation_library[0]
	var solution := int(entry.get("solution", 0))
	runner.check(
		session.enter_unspace(catalog, "acb1", 6, assembled, solution),
		"library jump: enter_unspace off-network"
	)
	runner.check_eq(session.pending_destination_id, "acb1", "library jump: pending acb1")
	session.in_unspace = false
	session.pending_destination_id = ""
	var resolved := session.resolve_translation_mapping(catalog, "acb1", 6, solution)
	runner.check(not resolved.is_empty(), "library jump: resolve_translation_mapping for UI jump")
	runner.check_eq(str(resolved.get("target", "")), "acb1", "library jump: resolved target")


static func _test_calc_aborts_on_sector_change(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "HD-4", "tester"), "sector change abort new game")
	session.docked = false
	session.sector_id = "tycho"
	var assembled := _assembled_with_nav(catalog, "sne_astrolabe")
	var module := catalog.get_module_def("hyperdrive_alpha")
	runner.check(
		bool(
			HyperdriveSolution.start_calculation(
				session, catalog, assembled, "acb1", 6, module
			).get("ok", false)
		),
		"sector change: calc started"
	)
	session.sector_id = "proxima"
	HyperdriveSolution.advance(session, catalog, 1.0)
	runner.check(not HyperdriveSolution.is_active(session), "sector change: calc aborted")


static func _test_dragon_gold_thrust_budget(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := ShipAssembler.assemble(catalog, "dragon_gold")
	var owned := _owned_for_template(catalog, "dragon_gold")
	var session := _session_in_sector("proxima")
	var gate: float = FieldConditions._world_radii(catalog, "proxima").gate_radius
	var pos := Vector2(gate + 200.0, 0.0)
	runner.check(
		_spool_ok(catalog, session, assembled, owned, pos, true),
		"hyperdrive: Dragon Gold under thrust allowed"
	)
