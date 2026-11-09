class_name TestLibrary
extends RefCounted

const E_WORLD_SECTOR_COUNT := 11


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_validate_e_world_libraries(runner, catalog)
	_validate_corporation_descriptions(runner, catalog)
	_validate_library_index(runner, catalog)
	_validate_library_charter_counts(runner, catalog)


static func _validate_e_world_libraries(runner: TestRunner, catalog: Catalog) -> void:
	var libraries_per_sector: Dictionary = {}
	var library_building_ids: Array[String] = []
	for habitat_variant in catalog.list_habitat_dicts():
		if typeof(habitat_variant) != TYPE_DICTIONARY:
			continue
		var habitat: Dictionary = habitat_variant
		var sector_id := str(habitat.get("sector_id", ""))
		for building_id_variant in habitat.get("buildings", []):
			var building_id := str(building_id_variant)
			var building := catalog.get_building(building_id)
			if catalog.get_building_type(building) != "library":
				continue
			libraries_per_sector[sector_id] = int(libraries_per_sector.get(sector_id, 0)) + 1
			library_building_ids.append(building_id)

	runner.check(
		library_building_ids.size() >= E_WORLD_SECTOR_COUNT,
		"at least eleven library buildings exist"
	)
	var names: Dictionary = {}
	for building_id in library_building_ids:
		var building := catalog.get_building(building_id)
		var name := str(building.get("name", ""))
		runner.check(not names.has(name), "library name unique: %s" % name)
		names[name] = true

	for sector_variant in catalog.list_sectors():
		if typeof(sector_variant) != TYPE_DICTIONARY:
			continue
		var sector: Dictionary = sector_variant
		var sector_id := str(sector.get("id", ""))
		var classification := str(sector.get("classification", ""))
		var count := int(libraries_per_sector.get(sector_id, 0))
		if classification.begins_with("E"):
			runner.check_eq(count, 1, "E-world sector %s has one library" % sector_id)
		else:
			runner.check_eq(count, 0, "non-E sector %s has no library" % sector_id)


static func _validate_corporation_descriptions(runner: TestRunner, catalog: Catalog) -> void:
	for corp_variant in catalog.list_corporations():
		if typeof(corp_variant) != TYPE_DICTIONARY:
			continue
		var corp: Dictionary = corp_variant
		var corp_id := str(corp.get("id", ""))
		var description := str(corp.get("description", "")).strip_edges()
		runner.check(not description.is_empty(), "corporation %s has description" % corp_id)


static func _validate_library_index(runner: TestRunner, catalog: Catalog) -> void:
	for shelf_id in LibraryIndex.list_shelf_ids():
		var rows: Array = LibraryIndex.list_rows(catalog, shelf_id)
		runner.check(rows.size() >= 1, "library shelf %s has entries" % shelf_id)

	var star_rows: Array = LibraryIndex.list_rows(catalog, LibraryIndex.SHELF_STARS)
	runner.check(star_rows.size() >= 5, "stars shelf has several entries")
	var first_star_id := str((star_rows[0] as Dictionary).get("id", ""))
	var star_detail := LibraryIndex.detail_text(catalog, LibraryIndex.SHELF_STARS, first_star_id)
	runner.check("Spectral class:" in star_detail, "star detail includes spectral class")

	var world_detail := LibraryIndex.detail_text(catalog, LibraryIndex.SHELF_WORLDS, "proxima")
	runner.check("Classification: E1" in world_detail, "Proxima world detail includes classification")

	var corp_rows: Array = LibraryIndex.list_rows(catalog, LibraryIndex.SHELF_CORPORATIONS)
	runner.check(corp_rows.size() >= 10, "corporation shelf has several entries")
	var creus_detail := LibraryIndex.detail_text(catalog, LibraryIndex.SHELF_CORPORATIONS, "creus")
	runner.check(
		"auction houses" in creus_detail.to_lower(),
		"creus description mentions auction houses"
	)

	var module_rows: Array = LibraryIndex.list_rows(catalog, LibraryIndex.SHELF_MODULES)
	runner.check(module_rows.size() >= 20, "module shelf has many entries")
	var module_id := str((module_rows[0] as Dictionary).get("id", ""))
	var module_detail := LibraryIndex.detail_text(catalog, LibraryIndex.SHELF_MODULES, module_id)
	runner.check(not module_detail.is_empty(), "module detail is non-empty")


static func _validate_library_charter_counts(runner: TestRunner, catalog: Catalog) -> void:
	var counts := DeskCharterBoards.counts_for_building(
		catalog,
		"proxima_habitat",
		"the_alexandria_center",
		"library",
		1,
		42
	)
	runner.check_eq(int(counts.get("passenger", -1)), 0, "library has no passenger charters")
	runner.check_eq(int(counts.get("freight", -1)), 0, "library has no freight charters")
	runner.check_eq(int(counts.get("scan", -1)), 0, "library has no scan charters")
