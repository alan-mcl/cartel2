class_name TestCatalog
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()

	runner.check(not catalog.get_sector("proxima").is_empty(), "proxima sector exists")
	runner.check(not catalog.get_sector("bela").is_empty(), "bela sector exists")

	var module_def := catalog.get_module_def("light_laser")
	runner.check(module_def is ModuleDef, "get_module_def(light_laser) is ModuleDef")
	var weapon_defs: Array = catalog.list_module_defs("weapon")
	runner.check(not weapon_defs.is_empty(), "list_module_defs(weapon) non-empty")
	runner.check(weapon_defs[0] is ModuleDef, "list_module_defs returns ModuleDef")
	runner.check_eq(module_def.category, "weapon", "light_laser category")
	runner.check_eq(module_def.mount, "light_weapon", "light_laser mount")

	var module_dict := catalog.get_module("light_laser")
	runner.check(typeof(module_dict) == TYPE_DICTIONARY, "get_module still returns Dictionary")
	runner.check(module_dict.has("id"), "module dict has id")
	runner.check(module_dict.has("range"), "module dict has range")
	runner.check(module_dict.has("signature"), "module dict has signature")

	var ship_def := catalog.get_ship_def("flare_on_ss")
	runner.check(not ship_def.chassis.is_empty(), "flare_on_ss chassis id")

	var chassis_def := catalog.get_chassis_def("pegasus_chassis")
	var ammo_def := catalog.get_ammunition_def("mass_driver_round")
	var commodity_def := catalog.get_commodity_def("food_products")
	runner.check(commodity_def is CommodityDef, "get_commodity_def returns CommodityDef")
	var commodity_dict := catalog.get_commodity("food_products")
	runner.check(typeof(commodity_dict) == TYPE_DICTIONARY, "get_commodity still returns Dictionary")
	var economy_def := catalog.get_economy_def("proxima")
	runner.check(economy_def is EconomyDef, "get_economy_def returns EconomyDef")
	runner.check(not economy_def.produce.is_empty(), "proxima economy has produce")
	var economy_dict := catalog.get_economy("proxima")
	runner.check(typeof(economy_dict) == TYPE_DICTIONARY, "get_economy still returns Dictionary")
	runner.check(chassis_def.to_dict()["id"] == "pegasus_chassis", "chassis to_dict round-trip id")
	runner.check(
		ammo_def.to_dict()["damage_packets"]["kinetic"] > 0.0,
		"ammunition to_dict round-trip damage_packets"
	)

	var unspace_def := catalog.get_unspace_def("n4_default")
	runner.check(unspace_def is UnspaceDef, "get_unspace_def(n4_default) is UnspaceDef")
	runner.check_eq(unspace_def.n, 4, "n4_default depth n")
	var unspace := catalog.get_unspace_for_n(4)
	runner.check_eq(str(unspace.get("id", "")), "n4_default", "get_unspace_for_n(4)")
	var unspace_dict := catalog.get_unspace("n4_default")
	runner.check(typeof(unspace_dict) == TYPE_DICTIONARY, "get_unspace still returns Dictionary")
	runner.check(not unspace_dict.get("field", {}).is_empty(), "unspace dict includes field")

	var exit_def := InteractableDef.from_dict(catalog.get_interactable("unspace_exit"))
	runner.check(exit_def.kind == InteractableDef.Kind.ARRIVE, "unspace_exit parses as ARRIVE")

	var tycho_world := catalog.get_world("tycho")
	var debris_count := 0
	var entities: Variant = tycho_world.get("entities", [])
	if typeof(entities) == TYPE_ARRAY:
		for entity_variant in entities:
			if typeof(entity_variant) != TYPE_DICTIONARY:
				continue
			if str(entity_variant.get("kind", "")) == "debris":
				debris_count += 1
	runner.check(debris_count >= 1, "catalog has at least one debris world entity (tycho)")

	var mapping := catalog.get_mapping("proxima", "bela", 4)
	runner.check(not mapping.is_empty(), "proxima→bela n=4 mapping exists")
	runner.check(int(mapping.get("solution", 0)) == 42, "proxima→bela solution is 42")

	_test_centauri_a_beltworks_public_route(runner, catalog)
	_test_neighbourhood_beacon_sectors(runner, catalog)

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
	_validate_habitat_buildings(runner, catalog)


static func _validate_habitat_buildings(runner: TestRunner, catalog: Catalog) -> void:
	var seen_buildings: Dictionary = {}
	var art_paths: Dictionary = {}
	var shipyard_count := 0

	for habitat in catalog.list_habitat_dicts():
		if typeof(habitat) != TYPE_DICTIONARY:
			continue
		var habitat_id := str(habitat.get("id", ""))
		var art := str(habitat.get("art", ""))
		runner.check(not art.is_empty(), "habitat %s has art" % habitat_id)
		runner.check(
			not art_paths.has(art),
			"habitat %s art path unique" % habitat_id
		)
		art_paths[art] = habitat_id

		shipyard_count = 0
		for building_id_variant in habitat.get("buildings", []):
			var building_id := str(building_id_variant)
			runner.check(
				not seen_buildings.has(building_id),
				"building %s on one habitat only" % building_id
			)
			seen_buildings[building_id] = habitat_id
			var building := catalog.get_building(building_id)
			runner.check(not building.is_empty(), "habitat building %s exists" % building_id)
			var building_art := catalog.get_building_art(building)
			runner.check(
				not art_paths.has(building_art),
				"building %s art path unique" % building_id
			)
			art_paths[building_art] = building_id
			if catalog.get_building_type(building) == "shipyard":
				shipyard_count += 1
		var no_shipyard_habitats: Array[String] = [
			"centauri_a_beltworks_habitat",
			"acb1_habitat",
			"acb2_habitat",
			"acb3_habitat",
			"terminus_habitat",
			"vulcan_research_habitat",
			"regulus_belt_habitat",
			"denarius_ii_habitat",
			"typhon_xvi_habitat",
		]
		if habitat_id in no_shipyard_habitats:
			runner.check_eq(shipyard_count, 0, "habitat %s has no shipyard" % habitat_id)
		else:
			runner.check_eq(shipyard_count, 1, "habitat %s has one shipyard" % habitat_id)


## Catalog sizes are content, not contract. Assert a floor so accidental bulk deletion is still
## caught, but do not assert equality — exact counts broke this suite on every SKU addition.
## Do not reintroduce `check_eq` on category sizes.
static func _check_min_count(
	runner: TestRunner,
	actual: int,
	minimum: int,
	label: String
) -> void:
	runner.check(actual >= minimum, "%s (expected >= %d, got %d)" % [label, minimum, actual])


## Every subtype a category declares must have at least one SKU, so a family cannot silently
## vanish from the catalog.
static func _check_subtypes_present(
	runner: TestRunner,
	type_counts: Dictionary,
	label: String
) -> void:
	for type_name in type_counts.keys():
		runner.check(
			int(type_counts[type_name]) > 0,
			"%s: %s represented (got %d)" % [label, str(type_name), int(type_counts[type_name])]
		)


static func _validate_power_plants(runner: TestRunner, catalog: Catalog) -> void:
	var power_modules: Array = catalog.list_modules("power")
	_check_min_count(runner, power_modules.size(), 40, "power plant SKUs")

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

	_check_subtypes_present(runner, type_counts, "power plants")

	for ship_dict in catalog.list_ships():
		if typeof(ship_dict) != TYPE_DICTIONARY:
			continue
		var ship_id := str(ship_dict.get("id", ""))
		var owned := OwnedShip.from_template(
			catalog,
			{
				"id": "%s_test" % ship_id,
				"template_id": ship_id,
				"chassis_id": str(ship_dict.get("chassis", "")),
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
	_check_min_count(runner, computer_modules.size(), 35, "compute core SKUs")

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

	_check_subtypes_present(runner, type_counts, "compute cores")

	for ship_dict in catalog.list_ships():
		if typeof(ship_dict) != TYPE_DICTIONARY:
			continue
		var ship_id := str(ship_dict.get("id", ""))
		var owned := OwnedShip.from_template(
			catalog,
			{
				"id": "%s_compute_test" % ship_id,
				"template_id": ship_id,
				"chassis_id": str(ship_dict.get("chassis", "")),
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
	_check_min_count(runner, propulsion_modules.size(), 40, "propulsion SKUs")

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
		"integrated_sail": 0,
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
		if engine_type == "integrated_sail":
			runner.check_eq(
				float(module_def.get("fuel_consumption", -1.0)),
				0.0,
				"%s sail has zero fuel burn" % module_id
			)

	_check_subtypes_present(runner, type_counts, "engines")

	for ship_dict in catalog.list_ships():
		if typeof(ship_dict) != TYPE_DICTIONARY:
			continue
		var ship_id := str(ship_dict.get("id", ""))
		var owned := OwnedShip.from_template(
			catalog,
			{
				"id": "%s_propulsion_test" % ship_id,
				"template_id": ship_id,
				"chassis_id": str(ship_dict.get("chassis", "")),
			}
		)
		var assembled := ShipAssembler.assemble_owned(catalog, owned)
		runner.check(
			assembled.get_propulsion_module_def() != null,
			"%s template has a main engine" % ship_id
		)


static func _validate_life_support(runner: TestRunner, catalog: Catalog) -> void:
	var life_support_modules: Array = catalog.list_modules("life_support")
	_check_min_count(runner, life_support_modules.size(), 35, "life support SKUs")

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

	for ship_dict in catalog.list_ships():
		if typeof(ship_dict) != TYPE_DICTIONARY:
			continue
		var ship_id := str(ship_dict.get("id", ""))
		var owned := OwnedShip.from_template(
			catalog,
			{
				"id": "%s_lss_test" % ship_id,
				"template_id": ship_id,
				"chassis_id": str(ship_dict.get("chassis", "")),
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
	_check_min_count(runner, weapons.size(), 25, "weapon SKUs")

	var armour: Array = catalog.list_modules("armour")
	_check_min_count(runner, armour.size(), 12, "armour SKUs")

	var shields: Array = catalog.list_modules("shield")
	_check_min_count(runner, shields.size(), 10, "shield SKUs")

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


static func _test_centauri_a_beltworks_public_route(runner: TestRunner, catalog: Catalog) -> void:
	runner.check(not catalog.get_sector("centauri_a_beltworks").is_empty(), "centauri_a_beltworks sector exists")
	var belt_world := catalog.get_world("centauri_a_beltworks")
	runner.check(not belt_world.has("planet"), "beltworks world has no planet block")
	runner.check(belt_world.has("orbital_ring"), "beltworks world has orbital ring")

	var route_count := 0
	var partner := ""
	for route_variant in catalog.list_routes():
		if typeof(route_variant) != TYPE_DICTIONARY:
			continue
		var route: Dictionary = route_variant
		var a := str(route.get("a", ""))
		var b := str(route.get("b", ""))
		if a == "centauri_a_beltworks" or b == "centauri_a_beltworks":
			route_count += 1
			partner = b if a == "centauri_a_beltworks" else a

	runner.check_eq(route_count, 1, "beltworks has exactly one public route")
	runner.check_eq(partner, "proxima", "beltworks public route partner is proxima")

	var mapping := catalog.get_mapping("proxima", "centauri_a_beltworks", 4)
	runner.check(not mapping.is_empty(), "proxima→beltworks n=4 mapping exists")
	runner.check(
		catalog.get_mapping("centauri_a_beltworks", "proxima", 4).is_empty() == false,
		"beltworks→proxima n=4 mapping exists"
	)

	var beacon: Variant = belt_world.get("translation_beacon", {})
	runner.check(typeof(beacon) == TYPE_DICTIONARY and not beacon.is_empty(), "beltworks has translation_beacon")
	runner.check(not belt_world.has("jump_gate"), "beltworks has no jump_gate")
	runner.check_eq(str(beacon.get("destination", "")), "proxima", "beltworks beacon tuned to proxima")


static func _test_neighbourhood_beacon_sectors(runner: TestRunner, catalog: Catalog) -> void:
	var proxima_sites: Array[String] = ["acb1", "acb2", "acb3", "terminus"]
	for sector_id in proxima_sites:
		_test_beacon_outpost_route(runner, catalog, sector_id, "proxima")
	var tycho_sites: Array[String] = [
		"vulcan_research",
		"regulus_belt",
		"denarius_ii",
		"typhon_xvi",
	]
	for sector_id in tycho_sites:
		_test_beacon_outpost_route(runner, catalog, sector_id, "tycho")


static func _test_beacon_outpost_route(
	runner: TestRunner, catalog: Catalog, sector_id: String, hub_id: String
) -> void:
	runner.check(not catalog.get_sector(sector_id).is_empty(), "sector %s exists" % sector_id)
	var world := catalog.get_world(sector_id)
	runner.check(world.has("orbital_ring"), "%s world has orbital ring" % sector_id)

	var route_count := 0
	var partner := ""
	for route_variant in catalog.list_routes():
		if typeof(route_variant) != TYPE_DICTIONARY:
			continue
		var route: Dictionary = route_variant
		var a := str(route.get("a", ""))
		var b := str(route.get("b", ""))
		if a == sector_id or b == sector_id:
			route_count += 1
			partner = b if a == sector_id else a

	runner.check_eq(route_count, 1, "%s has exactly one public route" % sector_id)
	runner.check_eq(partner, hub_id, "%s public route partner is %s" % [sector_id, hub_id])
	runner.check(
		not catalog.get_mapping(hub_id, sector_id, 4).is_empty(),
		"%s→%s n=4 mapping exists" % [hub_id, sector_id]
	)
	runner.check(
		not catalog.get_mapping(sector_id, hub_id, 4).is_empty(),
		"%s→%s n=4 mapping exists" % [sector_id, hub_id]
	)

	var beacon: Variant = world.get("translation_beacon", {})
	runner.check(typeof(beacon) == TYPE_DICTIONARY and not beacon.is_empty(), "%s has translation_beacon" % sector_id)
	runner.check(not world.has("jump_gate"), "%s has no jump_gate" % sector_id)
	runner.check_eq(str(beacon.get("destination", "")), hub_id, "%s beacon tuned to hub" % sector_id)
