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
