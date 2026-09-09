class_name TestCatalog
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()

	runner.check(not catalog.get_sector("proxima").is_empty(), "proxima sector exists")
	runner.check(not catalog.get_sector("bela").is_empty(), "bela sector exists")

	var unspace := catalog.get_unspace_for_n(4)
	runner.check_eq(str(unspace.get("id", "")), "n4_default", "get_unspace_for_n(4)")

	var exit_def := InteractableDef.from_dict(catalog.get_interactable("unspace_exit"))
	runner.check(exit_def.kind == InteractableDef.Kind.ARRIVE, "unspace_exit parses as ARRIVE")

	var mapping := catalog.get_mapping("proxima", "bela", 4)
	runner.check(not mapping.is_empty(), "proxima→bela n=4 mapping exists")
	runner.check(int(mapping.get("solution", 0)) == 42, "proxima→bela solution is 42")

	runner.check_eq(catalog.get_default_background_id(), "tester", "default background is tester")
	runner.check(not catalog.get_background("trader").is_empty(), "trader background exists")
	runner.check(not catalog.get_background("hotshot").is_empty(), "hotshot background exists")
	runner.check(not catalog.get_background("entrepreneur").is_empty(), "entrepreneur background exists")
	runner.check(not catalog.get_background("outlaw").is_empty(), "outlaw background exists")
	runner.check(not catalog.get_background("soldier").is_empty(), "soldier background exists")

	_validate_power_plants(runner, catalog)


static func _validate_power_plants(runner: TestRunner, catalog: Catalog) -> void:
	var power_modules: Array = catalog.list_modules("power")
	runner.check_eq(power_modules.size(), 48, "forty-eight power plant SKUs")

	var type_counts := {"fission": 0, "fusion": 0, "radioisotope": 0}
	for module_def in power_modules:
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var module_id := str(module_def.get("id", ""))
		runner.check(
			module_id != "fusion_plant_mk1" and module_id != "fusion_plant_mk2",
			"retired POC plant %s absent" % module_id
		)
		var plant_type := str(module_def.get("plant_type", ""))
		runner.check(not plant_type.is_empty(), "%s has plant_type" % module_id)
		runner.check(not str(module_def.get("brand", "")).is_empty(), "%s has brand" % module_id)
		if type_counts.has(plant_type):
			type_counts[plant_type] += 1
		if plant_type == "radioisotope":
			runner.check_eq(
				float(module_def.get("fuel_consumption", -1.0)),
				0.0,
				"%s radioisotope has zero fuel burn" % module_id
			)

	runner.check_eq(type_counts["fission"], 31, "thirty-one fission plants")
	runner.check_eq(type_counts["fusion"], 11, "eleven fusion plants")
	runner.check_eq(type_counts["radioisotope"], 6, "six radioisotope plants")

	for ship_def in catalog.ships_by_id.values():
		if typeof(ship_def) != TYPE_DICTIONARY:
			continue
		var ship_id := str(ship_def.get("id", ""))
		var owned := OwnedShip.from_template(
			catalog,
			{
				"id": "%s_test" % ship_id,
				"template_id": ship_id,
				"chassis_id": str(ship_def.get("chassis", "")),
			}
		)
		var engineering := ShipAssembly.get_engineering_block(catalog, owned)
		var generation := float(engineering.get("idle_power_available", 0.0))
		var idle_requested := float(engineering.get("idle_power_requested", 0.0))
		runner.check(generation > 0.0, "%s template has a power plant" % ship_id)
		runner.check(
			generation >= idle_requested,
			"%s plant covers idle power demand" % ship_id
		)
