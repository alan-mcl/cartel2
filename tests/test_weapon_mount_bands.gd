class_name TestWeaponMountBands
extends RefCounted

const MOUNT_BANDS := {
	"light_weapon": {"min": 10.0, "max": 14.0},
	"medium_weapon": {"min": 15.0, "max": 20.0},
	"heavy_weapon": {"min": 22.0, "max": 30.0},
}


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var ctx := BalanceMetrics.build_context(catalog, {})
	var weapons: Dictionary = ctx["weapons"]
	var min_hull := _min_unarmoured_template_hull(catalog)
	runner.check(min_hull > 0.0, "weapon bands: min unarmoured hull hits")
	for def in catalog.list_modules("weapon"):
		if def.weapon_type == "cyber":
			continue
		var stats: Dictionary = weapons.get(def.id, {})
		var hull_dps := float(stats.get("hull_dps", 0.0))
		if hull_dps <= 0.0:
			continue
		var mount := str(stats.get("mount", ""))
		var band: Dictionary = MOUNT_BANDS.get(mount, {})
		runner.check(
			hull_dps >= float(band.get("min", 0.0)) - 0.05
			and hull_dps <= float(band.get("max", 999.0)) + 0.05,
			"weapon mount band %s (%.2f hull DPS)" % [def.id, hull_dps]
		)
		var volley: Array = stats.get("volley", [])
		var one_pull := _volley_hull_hits(volley)
		runner.check(
			one_pull <= min_hull + 0.05,
			"weapon alpha cap %s (%.2f hull per pull, min template %.0f)" % [def.id, one_pull, min_hull]
		)


static func _volley_hull_hits(volley: Array) -> float:
	var bare := AssembledShip.new()
	var state := ShipCombatState.from_assembled(bare)
	var total := 0.0
	for packets_variant in volley:
		var packets: Dictionary = packets_variant
		var result := ShipCombat.resolve_hit(bare, state, "beam", packets)
		total += float(result.get("hull_damage", 0.0))
	return total


static func _min_unarmoured_template_hull(catalog: Catalog) -> float:
	var min_hull := INF
	for template_variant in catalog.list_ships():
		var template: Dictionary = template_variant
		var template_id := str(template.get("id", ""))
		var ship_def := catalog.get_ship_def(template_id)
		if ship_def == null:
			continue
		var owned := OwnedShip.from_template(
			catalog,
			{"id": "hull_probe_%s" % template_id, "template_id": template_id, "chassis_id": ship_def.chassis}
		)
		var assembled := ShipAssembler.assemble_owned(catalog, owned)
		if not assembled.modules_in_category("armour").is_empty():
			continue
		min_hull = minf(min_hull, float(assembled.capacities.get("hull_hits", 0.0)))
	return min_hull if min_hull < INF else 0.0
