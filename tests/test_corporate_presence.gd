class_name TestCorporatePresence
extends RefCounted

const TrafficSpawnScript := preload("res://scripts/gameplay/traffic_spawn.gd")


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_deepspace_identity(runner, catalog)
	_test_sector_shares(runner, catalog)
	_test_weighted_pick(runner, catalog)
	_test_traffic_spawn_corporate(runner, catalog)


static func _test_deepspace_identity(runner: TestRunner, catalog: Catalog) -> void:
	var corp := catalog.get_corporation("deepspace")
	runner.check(not corp.is_empty(), "deepspace corporation exists")
	runner.check_eq(str(corp.get("name", "")), "DeepSpace Cooperative", "deepspace name")
	runner.check_eq(str(corp.get("callsign_prefix", "")), "DSC", "deepspace ticker")


static func _test_sector_shares(runner: TestRunner, catalog: Catalog) -> void:
	var presence := catalog.get_corporate_presence()
	runner.check(presence.size() >= catalog.list_sectors().size(), "presence covers sectors")
	for sector in catalog.list_sectors():
		var sector_id := str(sector.get("id", ""))
		var block: Variant = presence.get(sector_id, {})
		runner.check(typeof(block) == TYPE_DICTIONARY, "presence block for %s" % sector_id)
		if typeof(block) != TYPE_DICTIONARY:
			continue
		var deepspace_share := float(block.get("deepspace", 0.0))
		runner.check(deepspace_share > 0.0, "deepspace share on %s" % sector_id)
		var total := 0.0
		for percent_variant in block.values():
			total += float(percent_variant)
		runner.check(abs(total - 100.0) < 0.02, "presence sum 100 on %s" % sector_id)


static func _test_weighted_pick(runner: TestRunner, catalog: Catalog) -> void:
	var shares := CorporatePresence.shares(catalog, "fortuna")
	runner.check(not shares.is_empty(), "fortuna shares loaded")
	var first := CorporatePresence.pick_corporation(catalog, "fortuna", 0.0)
	runner.check(str(first.get("kind", "")) == "corporate", "pick returns corporate kind")
	runner.check(not str(first.get("name", "")).is_empty(), "pick returns corporate name")
	var last := CorporatePresence.pick_corporation(catalog, "fortuna", 0.999)
	runner.check(str(last.get("kind", "")) == "corporate", "high roll still corporate")
	runner.check(not str(last.get("id", "")).is_empty(), "high roll returns corp id")


static func _test_traffic_spawn_corporate(runner: TestRunner, catalog: Catalog) -> void:
	var traffic_config := catalog.get_traffic_config().duplicate(true)
	traffic_config["independent_weight"] = 0.0
	var record := TrafficSpawnScript._pick_affiliation_record(
		catalog,
		traffic_config,
		"fennet"
	)
	runner.check(str(record.get("kind", "")) == "corporate", "spawn pick corporate when no independents")
	var corp_names: Dictionary = {}
	for corp in catalog.list_corporations():
		corp_names[str(corp.get("name", ""))] = true
	runner.check(corp_names.has(str(record.get("name", ""))), "spawn affiliation is catalog corp")
