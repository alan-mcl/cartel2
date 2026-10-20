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
	_test_stock_list_meta(runner, catalog)


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
