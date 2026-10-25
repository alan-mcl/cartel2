class_name TestAssembler
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()

	for ship_id in ["flare_on_ss", "pegasus_p101"]:
		var assembled := ShipAssembler.assemble(catalog, ship_id)
		runner.check(not assembled.id.is_empty(), "%s assembles" % ship_id)
		runner.check(assembled.stats.max_speed > 0.0, "%s max_speed > 0" % ship_id)
		runner.check(assembled.stats.forward_thrust > 0.0, "%s forward_thrust > 0" % ship_id)

	_test_cargo_capabilities(runner, catalog)
	_test_chassis_def_keeps_dictionary(runner, catalog)
	_test_stock_list_meta(runner, catalog)
	_test_full_load_limits_fitting_and_launch(runner, catalog)
	_test_templates_fit_a_full_load(runner, catalog)
	_test_seed_skips_unfired_rounds(runner, catalog)
	_test_rearm_charges_the_repair_index(runner, catalog)


static func _test_cargo_capabilities(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "cargo_cap_test",
			"template_id": "flare_on_ss",
			"chassis_id": "flare_on_chassis",
		}
	)
	owned.set_module("other_1", "cargo_bay_10")
	var plain := ShipAssembler.assemble_owned(catalog, owned)
	runner.check(not plain.has_capability("refrigerated"), "assembler: plain cargo bay lacks refrigerated")
	owned.set_module("other_1", "ok_coolstore_10")
	var cold := ShipAssembler.assemble_owned(catalog, owned)
	runner.check(cold.has_capability("refrigerated"), "assembler: refrigerated bay grants flag")
	owned.set_module("other_1", "cargo_bay_10")
	owned.set_module("other_2", "gi_pharma_cold_10")
	var mixed := ShipAssembler.assemble_owned(catalog, owned)
	runner.check(mixed.has_capability("biohazard"), "assembler: mixed bays OR biohazard")
	runner.check(mixed.has_capability("refrigerated"), "assembler: mixed bays OR refrigerated")


static func _test_chassis_def_keeps_dictionary(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := ShipAssembler.assemble(catalog, "flare_on_ss")
	runner.check(assembled.chassis_def != null, "assembler: chassis def is stored")
	runner.check_eq(
		assembled.chassis_def.id,
		str(assembled.chassis.get("id", "")),
		"assembler: chassis dictionary matches the def"
	)
	runner.check(
		not str(assembled.chassis.get("sprite", "")).is_empty(),
		"assembler: chassis dictionary keeps the sprite"
	)
	assembled.chassis = {"maneuver": "low", "hits": 4, "sprite": "res://stub.svg", "id": "stub_id", "header": "STUB"}
	runner.check(assembled.chassis_def == null, "assembler: replacing the chassis dictionary drops the def")
	runner.check_eq(assembled.chassis_maneuver(), "low", "assembler: a chassis stub supplies maneuver")
	runner.check_eq(assembled.chassis_hits(), 4, "assembler: a chassis stub supplies hits")
	runner.check_eq(assembled.chassis_sprite(), "res://stub.svg", "assembler: a chassis stub supplies the sprite")
	assembled.chassis_def = ChassisDef.from_dict({
		"id": "typed",
		"name": "Typed",
		"maker": "Test",
		"description": "Typed chassis",
		"mass": 1.0,
		"hits": 9.0,
		"mass_limit": 2.0,
		"volume": 1.0,
		"maneuver": "high",
		"sprite": "res://typed.svg",
		"header": "TYPED",
		"mounts": {},
	})
	runner.check(assembled.has_chassis(), "assembler: a chassis def counts as present")
	runner.check_eq(assembled.chassis_sprite(), "res://typed.svg", "assembler: chassis sprite prefers the def")
	runner.check_eq(assembled.chassis_id(), "typed", "assembler: chassis id prefers the def")
	runner.check_eq(assembled.chassis_header(), "TYPED", "assembler: chassis header prefers the def")


static func _test_stock_list_meta(runner: TestRunner, catalog: Catalog) -> void:
	var prop: Dictionary = {}
	for mod in catalog.list_modules():
		if str((mod as Dictionary).get("category", "")) == "propulsion":
			prop = mod as Dictionary
			break
	if not prop.is_empty():
		var prop_meta := ModuleSpecText.format_stock_list_meta("propulsion", prop)
		runner.check(prop_meta.contains("thrust"), "propulsion stock meta mentions thrust")
	var lss: Dictionary = {}
	for mod in catalog.list_modules():
		if str((mod as Dictionary).get("category", "")) == "life_support":
			lss = mod as Dictionary
			break
	if not lss.is_empty():
		var lss_meta := ModuleSpecText.format_stock_list_meta("life_support", lss)
		runner.check(lss_meta.contains("crew"), "life_support stock meta mentions crew")
	runner.check(
		ModuleSpecText.format_stock_list_meta("unknown_category", {}).is_empty(),
		"unknown stock category yields empty meta"
	)
	var ammo_weapon: Dictionary = {}
	for mod in catalog.list_modules():
		var data := mod as Dictionary
		if str(data.get("category", "")) != "weapon":
			continue
		if str(data.get("ammunition_type", "")).is_empty():
			continue
		ammo_weapon = data
		break
	if not ammo_weapon.is_empty():
		var weapon_meta := ModuleSpecText.format_stock_list_meta("weapon", ammo_weapon)
		runner.check(
			not weapon_meta.contains(str(ammo_weapon.get("ammunition_type", ""))),
			"weapon stock meta omits ammunition type"
		)
		runner.check(weapon_meta.contains("·"), "weapon stock meta keeps type and delivery")
		var ammo_tooltip := ModuleSpecText.format_tooltip(ammo_weapon)
		runner.check(
			ammo_tooltip.contains("Ammunition type"),
			"weapon tooltip lists ammunition type"
		)
	var packet_weapon: Dictionary = {}
	for mod in catalog.list_modules():
		var data := mod as Dictionary
		if str(data.get("category", "")) != "weapon":
			continue
		var packets: Variant = data.get("damage_packets", {})
		if typeof(packets) != TYPE_DICTIONARY or packets.is_empty():
			continue
		packet_weapon = data
		break
	if not packet_weapon.is_empty():
		var packet_meta := ModuleSpecText.format_stock_list_meta("weapon", packet_weapon)
		var packets: Dictionary = packet_weapon.get("damage_packets", {})
		for packet_key in packets.keys():
			runner.check(
				not packet_meta.contains(str(packet_key).capitalize()),
				"weapon stock meta omits damage packets"
			)
			break
		var packet_tooltip := ModuleSpecText.format_tooltip(packet_weapon)
		runner.check(
			packet_tooltip.contains("Damage packets"),
			"weapon tooltip lists damage packets"
		)


static func _test_full_load_limits_fitting_and_launch(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "mass_fit",
			"template_id": "flare_on_ss",
			"chassis_id": "flare_on_chassis",
		}
	)
	var slot := ""
	for slot_variant in ShipAssembler.list_slots_for_chassis(catalog.get_chassis_def("flare_on_chassis")):
		var candidate := str(slot_variant)
		if candidate.begins_with("other_") and owned.get_module_id(candidate).is_empty():
			slot = candidate
			break
	runner.check(not slot.is_empty(), "assembler: flare has a free slot for the mass check")
	var before := owned.get_module_id(slot)
	var refused := ShipAssembler.validate_install(catalog, owned, slot, "cargo_bay_20")
	runner.check(not bool(refused.get("ok", false)), "assembler: a 20 t bay that fits dry is refused when full")
	runner.check(
		str(refused.get("reason", "")).contains("fully loaded"),
		"assembler: the refusal names the full load"
	)
	runner.check_eq(owned.get_module_id(slot), before, "assembler: a refused install changes nothing")

	var launched := OwnedShip.from_template(
		catalog,
		{
			"id": "mass_launch",
			"template_id": "flare_on_ss",
			"chassis_id": "flare_on_chassis",
		}
	)
	runner.check(
		ShipAssembly.undock_blockers(catalog, launched).is_empty(),
		"assembler: an empty flare can undock"
	)
	launched.add_cargo("minerals", 20)
	var blocked := ShipAssembly.undock_blockers(catalog, launched)
	var saw_mass := false
	for reason in blocked:
		if str(reason).contains("mass limit"):
			saw_mass = true
	runner.check(saw_mass, "assembler: cargo over the limit blocks undock")
	launched.remove_cargo("minerals", 20)
	runner.check(
		ShipAssembly.undock_blockers(catalog, launched).is_empty(),
		"assembler: offloading the cargo clears the mass block"
	)


static func _test_templates_fit_a_full_load(runner: TestRunner, catalog: Catalog) -> void:
	var checked := 0
	for ship_variant in catalog.list_ships():
		if typeof(ship_variant) != TYPE_DICTIONARY:
			continue
		var ship_id := str(ship_variant.get("id", ""))
		var template := catalog.get_ship_def(ship_id)
		if template == null:
			continue
		var owned := OwnedShip.from_template(
			catalog,
			{
				"id": "full_%s" % ship_id,
				"template_id": ship_id,
				"chassis_id": template.chassis,
			}
		)
		var assembled := ShipAssembler.assemble_owned(catalog, owned)
		var full := ShipAssembler.projected_full_mass(catalog, owned, assembled)
		var limit := float(assembled.envelope.get("mass_limit", 0.0))
		runner.check(
			full <= limit,
			"assembler: %s full load %.2f t is within %.1f t" % [ship_id, full, limit]
		)
		checked += 1
	runner.check(checked >= 8, "assembler: full-load check covers the roster")


static func _test_seed_skips_unfired_rounds(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "seed_unfired",
			"template_id": "pegasus_p101",
			"chassis_id": "pegasus_chassis",
		}
	)
	var magazine_slot := ""
	for entry_variant in owned.modules:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		if str((entry_variant as Dictionary).get("module_id", "")) == "oc_river_md_light_magazine_200":
			magazine_slot = str((entry_variant as Dictionary).get("slot", ""))
			break
	runner.check(not magazine_slot.is_empty(), "assembler: the P101 fit has a light magazine to swap")
	owned.set_module(magazine_slot, "oc_river_md_magazine_200")
	owned.ammunition.clear()
	ShipAssembler.seed_ammunition(catalog, owned)
	runner.check_eq(
		owned.get_ammo_count("oc_river_md_round"),
		200,
		"assembler: seeding fills the light round a mass driver fires"
	)
	runner.check_eq(
		owned.get_ammo_count("oc_river_md_heavy_round"),
		0,
		"assembler: seeding skips heavy rounds no fitted weapon fires"
	)


static func _test_rearm_charges_the_repair_index(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "REARM-1", "trader"), "assembler: rearm session starts")
	var ship := session.get_current_owned_ship()
	if ship == null:
		runner.check(false, "assembler: trader has a ship to rearm")
		return
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	var caps: Dictionary = assembled.capacities.get("ammunition_capacity", {})
	var capacity := int(caps.get("oc_river_md_round", 0))
	runner.check(capacity > 10, "assembler: trader magazine holds light rounds")
	ship.ammunition = {"oc_river_md_round": 10.0}
	var index := ShipAssembly.repair_price_index(session, catalog)
	runner.check(index > 0.0, "assembler: rearm has a repair index")
	var missing := capacity - 10
	var unit := catalog.get_ammunition_def("oc_river_md_round").cost
	var expected := int(ceil(float(missing) * unit * index - 0.000001))
	var quote := ShipAssembly.rearm_quote(session, catalog, ship.id)
	runner.check(bool(quote.get("enabled", false)), "assembler: a short magazine can be rearmed")
	runner.check_eq(int(quote.get("cost", 0)), expected, "assembler: rearm bill is cost times the index")
	var credits_before := session.wallet.credits
	runner.check(ShipAssembly.rearm_ship(session, catalog, ship.id), "assembler: rearm fills the magazine")
	runner.check_eq(owned_ammo(ship), capacity, "assembler: rearm restores the listed capacity")
	runner.check_eq(session.wallet.credits, credits_before - expected, "assembler: rearm spends the bill")
	runner.check_eq(
		int(session.career.expenses_by_source.get("ammunition", 0)),
		expected,
		"assembler: rearm is an ammunition expense"
	)
	var full := ShipAssembly.rearm_quote(session, catalog, ship.id)
	runner.check(not bool(full.get("enabled", false)), "assembler: a full magazine is not rearmed again")

	ship.ammunition = {"oc_river_md_round": 10.0}
	session.wallet.credits = 0
	runner.check(not ShipAssembly.rearm_ship(session, catalog, ship.id), "assembler: rearm refuses an empty wallet")
	runner.check_eq(owned_ammo(ship), 10, "assembler: a refused rearm leaves the magazine")

	session.sandbox = true
	var sandbox_credits := session.wallet.credits
	var spent := int(session.career.expenses_by_source.get("ammunition", 0))
	runner.check(ShipAssembly.rearm_ship(session, catalog, ship.id), "assembler: sandbox rearm is free")
	runner.check_eq(session.wallet.credits, sandbox_credits, "assembler: sandbox rearm spends nothing")
	runner.check_eq(
		int(session.career.expenses_by_source.get("ammunition", 0)),
		spent,
		"assembler: sandbox rearm is not an expense"
	)
	runner.check_eq(owned_ammo(ship), capacity, "assembler: sandbox rearm still fills the magazine")


static func owned_ammo(ship: OwnedShip) -> int:
	return ship.get_ammo_count("oc_river_md_round")
