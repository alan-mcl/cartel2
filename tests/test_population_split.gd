class_name TestPopulationSplit
extends RefCounted

const ALLOWED_OUTLYING_SURFACE: Array = [
	"new_ceres",
	"junkers_world",
	"byrsa",
	"acb2",
	"aurelia",
	"scoria",
	"caldera",
	"denarius_ii",
	"typhon_xvi",
	"ursa_xvi",
	"titania_ixx",
	"nightjar",
	"janus",
]

const SPLIT_TOLERANCE := 0.001


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var orbital_by_sector: Dictionary = {}
	for habitat_variant in catalog.list_habitat_dicts():
		if typeof(habitat_variant) != TYPE_DICTIONARY:
			continue
		var habitat: Dictionary = habitat_variant
		var sector_id := str(habitat.get("sector_id", ""))
		if sector_id.is_empty():
			continue
		var pop := float(habitat.get("population_billions", 0.0))
		orbital_by_sector[sector_id] = float(orbital_by_sector.get(sector_id, 0.0)) + pop

	var catalog_total := 0.0
	for sector_variant in catalog.list_sectors():
		if typeof(sector_variant) != TYPE_DICTIONARY:
			continue
		var sector: Dictionary = sector_variant
		var sector_id := str(sector.get("id", ""))
		var total := float(sector.get("population_billions", 0.0))
		catalog_total += total
		var surface := float(sector.get("surface_population_billions", 0.0))
		var orbital := float(orbital_by_sector.get(sector_id, 0.0))
		runner.check(
			absf(total - surface - orbital) <= SPLIT_TOLERANCE,
			"%s population split sums" % sector_id
		)

		var classification := str(sector.get("classification", "")).strip_edges()
		if not classification.is_empty() and total > 0.0:
			runner.check(surface > orbital, "%s e-world surface majority" % sector_id)
		if classification.is_empty():
			if surface > 0.0:
				runner.check(
					ALLOWED_OUTLYING_SURFACE.has(sector_id),
					"%s allowed outlying surface" % sector_id
				)
			if ALLOWED_OUTLYING_SURFACE.has(sector_id):
				var malls: Variant = sector.get("city_malls", [])
				runner.check(
					typeof(malls) == TYPE_ARRAY and (malls as Array).size() == 1,
					"%s single surface camp marker" % sector_id
				)

	runner.check(catalog_total >= 352.0, "catalog population total floor")

	var proxima := catalog.get_sector("proxima")
	runner.check_eq(
		float(proxima.get("surface_population_billions", 0.0)),
		57.6,
		"proxima surface population"
	)
	var proxima_hab := catalog.get_habitat("proxima_habitat")
	runner.check(
		absf(float(proxima_hab.get("population_billions", 0.0)) - 1.8) < SPLIT_TOLERANCE,
		"proxima habitat orbital share"
	)

	var detail := LibraryIndex.detail_text(catalog, LibraryIndex.SHELF_WORLDS, "proxima")
	runner.check("Surface" in detail, "library world detail includes Surface")
	runner.check("Orbital (Proxima Habitat)" in detail, "library lists habitat orbital population")
