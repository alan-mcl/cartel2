class_name TestCargoRequirements
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_plain_hold_rejects_refrigerated_cargo(runner, catalog)
	_test_cold_hold_accepts_food(runner, catalog)
	_test_unrestricted_commodity_needs_no_hold(runner, catalog)
	_test_aboard_cargo_blocks_bay_change(runner, catalog)
	_test_requirement_labels(runner, catalog)


static func _owned(catalog: Catalog) -> OwnedShip:
	return OwnedShip.from_template(
		catalog,
		{
			"id": "cargo_req_test",
			"template_id": "flare_on_ss",
			"chassis_id": "flare_on_chassis",
		}
	)


static func _test_plain_hold_rejects_refrigerated_cargo(runner: TestRunner, catalog: Catalog) -> void:
	var owned := _owned(catalog)
	owned.set_module("other_1", "cargo_bay_10")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var food := catalog.get_commodity("food_products")
	runner.check(
		not CargoRequirements.assembled_meets_commodity(assembled, food),
		"cargo requirements: plain hold cannot carry food"
	)
	runner.check_eq(
		CargoRequirements.cannot_carry_reason(catalog, assembled, food),
		"Need a refrigerated hold to carry Food Products.",
		"cargo requirements: food rejection names the hold and the cargo"
	)
	runner.check_eq(
		CargoRequirements.commodity_requirement_phrase(food),
		"refrigerated",
		"cargo requirements: food phrase is the refrigerated label"
	)


static func _test_cold_hold_accepts_food(runner: TestRunner, catalog: Catalog) -> void:
	var owned := _owned(catalog)
	owned.set_module("other_1", "ok_coolstore_10")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var food := catalog.get_commodity("food_products")
	runner.check(
		CargoRequirements.assembled_meets_commodity(assembled, food),
		"cargo requirements: refrigerated hold can carry food"
	)
	runner.check_eq(
		CargoRequirements.cannot_carry_reason(catalog, assembled, food),
		"",
		"cargo requirements: accepted food has no rejection reason"
	)


static func _test_unrestricted_commodity_needs_no_hold(runner: TestRunner, catalog: Catalog) -> void:
	var owned := _owned(catalog)
	owned.set_module("other_1", "cargo_bay_10")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var goods := catalog.get_commodity("consumer_goods")
	runner.check(
		CargoRequirements.assembled_meets_commodity(assembled, goods),
		"cargo requirements: unrestricted goods need no special hold"
	)
	runner.check_eq(
		CargoRequirements.commodity_requirement_phrase(goods),
		"",
		"cargo requirements: unrestricted goods have an empty phrase"
	)
	runner.check_eq(
		CargoRequirements.required_capabilities({"requires_capabilities": "refrigerated"}),
		[],
		"cargo requirements: a non-array capability field is ignored"
	)


static func _test_aboard_cargo_blocks_bay_change(runner: TestRunner, catalog: Catalog) -> void:
	runner.check_eq(
		CargoRequirements.cargo_aboard_violation_reason(catalog, null),
		"",
		"cargo requirements: a missing ship has no aboard violation"
	)
	var owned := _owned(catalog)
	owned.set_module("other_1", "cargo_bay_10")
	owned.add_cargo("not_a_commodity", 3)
	runner.check_eq(
		CargoRequirements.cargo_aboard_violation_reason(catalog, owned),
		"",
		"cargo requirements: an unknown commodity id does not block a bay change"
	)
	owned.add_cargo("food_products", 2)
	runner.check_eq(
		CargoRequirements.cargo_aboard_violation_reason(catalog, owned),
		"Cannot change cargo bays: Food Products is still aboard.",
		"cargo requirements: food aboard blocks a bay change on a plain hold"
	)
	owned.cargo["food_products"] = 0
	runner.check_eq(
		CargoRequirements.cargo_aboard_violation_reason(catalog, owned),
		"",
		"cargo requirements: a zero count does not block a bay change"
	)


static func _test_requirement_labels(runner: TestRunner, catalog: Catalog) -> void:
	var owned := _owned(catalog)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var specimen := {
		"id": "specimen",
		"name": "Specimen",
		"requires_capabilities": ["", "biohazard", "secure_cargo"],
	}
	runner.check_eq(
		CargoRequirements.commodity_requirement_phrase(specimen),
		"biohazard, secure / bonded",
		"cargo requirements: empty capability ids are dropped and known labels are joined"
	)
	runner.check_eq(
		CargoRequirements.cannot_carry_reason(catalog, assembled, specimen),
		"Need a biohazard hold to carry Specimen.",
		"cargo requirements: the first missing capability is the rejection reason"
	)
	var unknown := {
		"id": "odd_cargo",
		"name": "Odd Cargo",
		"requires_capabilities": ["not_a_real_cap"],
	}
	runner.check_eq(
		CargoRequirements.requirement_label("not_a_real_cap"),
		"not_a_real_cap",
		"cargo requirements: an unknown capability label is the id"
	)
	runner.check(
		not CargoRequirements.assembled_meets_commodity(assembled, unknown),
		"cargo requirements: an unknown capability is not met by a stock hull"
	)
