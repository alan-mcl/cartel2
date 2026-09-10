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
	_validate_compute_cores(runner, catalog)
	_validate_life_support(runner, catalog)
	_validate_propulsion(runner, catalog)
	_validate_combat(runner, catalog)


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


static func _validate_compute_cores(runner: TestRunner, catalog: Catalog) -> void:
	var computer_modules: Array = catalog.list_modules("computer")
	runner.check_eq(computer_modules.size(), 41, "forty-one compute core SKUs")

	var retired := [
		"nav_combat_core_mk1",
		"nav_combat_core_mk2",
		"targeting_core_mk2",
	]
	var type_counts := {"silicon": 0, "photon": 0, "quantum": 0}
	for module_def in computer_modules:
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var module_id := str(module_def.get("id", ""))
		runner.check(
			not module_id in retired,
			"retired POC computer %s absent" % module_id
		)
		var core_type := str(module_def.get("core_type", ""))
		runner.check(not core_type.is_empty(), "%s has core_type" % module_id)
		runner.check(not str(module_def.get("brand", "")).is_empty(), "%s has brand" % module_id)
		runner.check(
			not module_def.has("compute_demand"),
			"%s has no compute_demand" % module_id
		)
		var capabilities: Variant = module_def.get("capabilities", [])
		runner.check(
			typeof(capabilities) == TYPE_ARRAY and capabilities.has("basic_hud"),
			"%s grants basic_hud" % module_id
		)
		if type_counts.has(core_type):
			type_counts[core_type] += 1

	runner.check_eq(type_counts["silicon"], 27, "twenty-seven silicon cores")
	runner.check_eq(type_counts["photon"], 9, "nine photon cores")
	runner.check_eq(type_counts["quantum"], 5, "five quantum cores")

	for ship_def in catalog.ships_by_id.values():
		if typeof(ship_def) != TYPE_DICTIONARY:
			continue
		var ship_id := str(ship_def.get("id", ""))
		var owned := OwnedShip.from_template(
			catalog,
			{
				"id": "%s_compute_test" % ship_id,
				"template_id": ship_id,
				"chassis_id": str(ship_def.get("chassis", "")),
			}
		)
		var engineering := ShipAssembly.get_engineering_block(catalog, owned)
		var capacities: Dictionary = engineering.get("capacities", {})
		var compute_capacity := float(capacities.get("compute_capacity", 0.0))
		var idle_compute_demand := float(engineering.get("idle_compute_demand", 0.0))
		runner.check(compute_capacity > 0.0, "%s template has a compute core" % ship_id)
		runner.check(
			compute_capacity >= idle_compute_demand,
			"%s core covers idle compute demand" % ship_id
		)


static func _validate_propulsion(runner: TestRunner, catalog: Catalog) -> void:
	var propulsion_modules: Array = catalog.list_modules("propulsion")
	runner.check_eq(propulsion_modules.size(), 48, "forty-eight propulsion SKUs")

	var retired := [
		"mark_1_fusion",
		"mark_3_fusion",
		"mark_2_antimatter",
		"gravitic_mk1",
	]
	var type_counts := {
		"chemical": 0,
		"hydro_thermal": 0,
		"electric_plasma": 0,
		"direct_fusion": 0,
		"antimatter": 0,
		"gravitic": 0,
	}
	for module_def in propulsion_modules:
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var module_id := str(module_def.get("id", ""))
		runner.check(
			not module_id in retired,
			"retired POC propulsion %s absent" % module_id
		)
		var engine_type := str(module_def.get("engine_type", ""))
		runner.check(not engine_type.is_empty(), "%s has engine_type" % module_id)
		runner.check(not str(module_def.get("brand", "")).is_empty(), "%s has brand" % module_id)
		runner.check(
			str(module_def.get("maker", "")) != "Bayes Inc",
			"%s is not Bayes Inc propulsion" % module_id
		)
		if type_counts.has(engine_type):
			type_counts[engine_type] += 1

	runner.check_eq(type_counts["chemical"], 12, "twelve chemical engines")
	runner.check_eq(type_counts["hydro_thermal"], 16, "sixteen hydro-thermal engines")
	runner.check_eq(type_counts["electric_plasma"], 8, "eight electric plasma engines")
	runner.check_eq(type_counts["direct_fusion"], 7, "seven direct fusion engines")
	runner.check_eq(type_counts["antimatter"], 4, "four antimatter engines")
	runner.check_eq(type_counts["gravitic"], 1, "one gravitic placeholder")

	for ship_def in catalog.ships_by_id.values():
		if typeof(ship_def) != TYPE_DICTIONARY:
			continue
		var ship_id := str(ship_def.get("id", ""))
		var owned := OwnedShip.from_template(
			catalog,
			{
				"id": "%s_propulsion_test" % ship_id,
				"template_id": ship_id,
				"chassis_id": str(ship_def.get("chassis", "")),
			}
		)
		var assembled := ShipAssembler.assemble_owned(catalog, owned)
		runner.check(
			not assembled.get_propulsion_module().is_empty(),
			"%s template has a main engine" % ship_id
		)


static func _validate_life_support(runner: TestRunner, catalog: Catalog) -> void:
	var life_support_modules: Array = catalog.list_modules("life_support")
	runner.check_eq(life_support_modules.size(), 41, "forty-one life support SKUs")

	var retired := ["life_support_mk1", "life_support_a3"]
	for module_def in life_support_modules:
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var module_id := str(module_def.get("id", ""))
		runner.check(
			not module_id in retired,
			"retired POC life support %s absent" % module_id
		)
		runner.check(not str(module_def.get("brand", "")).is_empty(), "%s has brand" % module_id)
		runner.check(
			module_def.has("compute_demand"),
			"%s has compute_demand" % module_id
		)
		var crew := float(module_def.get("life_support_capacity", 0.0))
		runner.check(crew >= 1.0 and crew <= 6.0, "%s crew is 1–6" % module_id)
		var capabilities: Variant = module_def.get("capabilities", [])
		var cap_list: Array = []
		if typeof(capabilities) == TYPE_ARRAY:
			cap_list = capabilities
		for cap in cap_list:
			var cap_id := str(cap)
			runner.check(
				cap_id == "ls_comfort" or cap_id == "ls_luxury" or cap_id == "ls_habitat",
				"%s has valid life support flag %s" % [module_id, cap_id]
			)
		var volume := float(module_def.get("volume", 0.0))
		var floor := _life_support_volume_floor(crew, cap_list)
		runner.check(
			volume + 0.0001 >= floor,
			"%s volume %.1f meets floor %.1f" % [module_id, volume, floor]
		)

	for ship_def in catalog.ships_by_id.values():
		if typeof(ship_def) != TYPE_DICTIONARY:
			continue
		var ship_id := str(ship_def.get("id", ""))
		var owned := OwnedShip.from_template(
			catalog,
			{
				"id": "%s_lss_test" % ship_id,
				"template_id": ship_id,
				"chassis_id": str(ship_def.get("chassis", "")),
			}
		)
		var engineering := ShipAssembly.get_engineering_block(catalog, owned)
		var capacities: Dictionary = engineering.get("capacities", {})
		var envelope: Dictionary = engineering.get("envelope", {})
		var lss_capacity := float(capacities.get("life_support_capacity", 0.0))
		var compute_capacity := float(capacities.get("compute_capacity", 0.0))
		var idle_compute_demand := float(engineering.get("idle_compute_demand", 0.0))
		var volume_used := float(envelope.get("volume_used", 0.0))
		var volume_limit := float(envelope.get("volume", 0.0))
		var dry_mass := float(envelope.get("dry_mass", 0.0))
		var mass_limit := float(envelope.get("mass_limit", 0.0))
		runner.check(lss_capacity >= 1.0, "%s template has life support" % ship_id)
		runner.check(
			compute_capacity >= idle_compute_demand,
			"%s life support fits idle compute budget" % ship_id
		)
		runner.check(
			volume_used <= volume_limit + 0.0001,
			"%s assembled volume %.2f ≤ %.1f" % [ship_id, volume_used, volume_limit]
		)
		runner.check(
			dry_mass <= mass_limit + 0.0001,
			"%s assembled mass %.2f ≤ %.1f" % [ship_id, dry_mass, mass_limit]
		)


static func _validate_combat(runner: TestRunner, catalog: Catalog) -> void:
	var weapons: Array = catalog.list_modules("weapon")
	runner.check_eq(weapons.size(), 31, "thirty-one weapon SKUs")

	var armour: Array = catalog.list_modules("armour")
	runner.check_eq(armour.size(), 16, "sixteen armour SKUs")

	var shields: Array = catalog.list_modules("shield")
	runner.check_eq(shields.size(), 13, "thirteen shield SKUs")

	for module_def in weapons:
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var module_id := str(module_def.get("id", ""))
		runner.check(not str(module_def.get("weapon_type", "")).is_empty(), "%s has weapon_type" % module_id)
		runner.check(not str(module_def.get("delivery_type", "")).is_empty(), "%s has delivery_type" % module_id)
		runner.check(not str(module_def.get("brand", "")).is_empty(), "%s has brand" % module_id)
		runner.check(
			str(module_def.get("maker", "")) != "Bayes Inc",
			"%s is not Bayes Inc weapon" % module_id
		)

	for module_def in armour:
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var module_id := str(module_def.get("id", ""))
		runner.check(module_def.has("protection"), "%s has protection profile" % module_id)
		runner.check(
			str(module_def.get("maker", "")) != "Bayes Inc",
			"%s is not Bayes Inc armour" % module_id
		)

	var assembled := ShipAssembler.assemble(catalog, "pegasus_p101")
	var state := ShipCombatState.from_assembled(assembled)
	var result := ShipCombat.resolve_hit(
		assembled,
		state,
		"ballistic",
		{"kinetic": 40.0}
	)
	runner.check(float(result.get("hull_damage", 0.0)) > 0.0, "pegasus takes kinetic hull damage")


static func _life_support_volume_floor(crew: float, capabilities: Array) -> float:
	var habitat := capabilities.has("ls_habitat")
	var band := "spartan"
	if capabilities.has("ls_luxury"):
		band = "luxury"
	elif capabilities.has("ls_comfort"):
		band = "comfort"
	var per_crew := 2.5
	if habitat:
		match band:
			"comfort":
				per_crew = 11.0
			"luxury":
				per_crew = 14.0
			_:
				per_crew = 8.0
	else:
		match band:
			"comfort":
				per_crew = 5.0
			"luxury":
				per_crew = 7.0
			_:
				per_crew = 2.5
	var floor := per_crew * crew
	if not habitat and crew <= 1.0:
		floor = maxf(floor, 4.0)
	return floor
