class_name TestFreight
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_board_generates(runner, catalog)
	_test_food_description_and_budgets(runner, catalog)
	_test_plain_hold_blocks_food(runner, catalog)
	_test_coolstore_accepts_food(runner, catalog)
	_test_livestock_requires_lss_hold(runner, catalog)
	_test_livestock_lss_with_passengers(runner, catalog)
	_test_cognition_compute_cap(runner, catalog)
	_test_cancel_at_origin(runner, catalog)
	_test_dock_pays_and_clears(runner, catalog)
	_test_reputation_gate(runner, catalog)


static func _simulation() -> Simulation:
	return Simulation.new()


static func _missions(simulation: Simulation) -> MissionSubsystem:
	return simulation.get_subsystem("missions") as MissionSubsystem


static func _wire_events(session: GameSession, catalog: Catalog, simulation: Simulation) -> void:
	session.events.subscribe_all(func(evt: Dictionary) -> void:
		simulation.dispatch_event(session, catalog, evt)
	)


static func _session(runner: TestRunner, catalog: Catalog, callsign: String) -> GameSession:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, callsign, "tester"), "freight: session starts")
	return session


static func _cargo_slot(ship: OwnedShip) -> String:
	for entry in ship.modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		var module_id := str(entry.get("module_id", ""))
		if module_id.begins_with("cargo_bay") or module_id.contains("coolstore"):
			return slot
	return "other_1"


static func _food_offer(
	catalog: Catalog,
	origin_habitat_id: String,
	destination_habitat_id: String,
	offer_id: String
) -> Dictionary:
	var dest := catalog.get_habitat(destination_habitat_id)
	var friction := PassengerCharters.friction_between(
		catalog,
		str(catalog.get_habitat(origin_habitat_id).get("sector_id", "")),
		str(dest.get("sector_id", ""))
	)
	var cfg := FreightCharters.config(catalog)
	var quantity := 4
	var mass := 1.0
	var reward := FreightCharters.compute_reward(cfg, quantity, mass, 1.0, friction)
	return {
		"id": offer_id,
		"origin_habitat_id": origin_habitat_id,
		"destination_habitat_id": destination_habitat_id,
		"destination_name": str(dest.get("name", destination_habitat_id)),
		"destination_sector_id": str(dest.get("sector_id", "")),
		"friction": friction,
		"cargo_id": "freight_food",
		"commodity_id": "food_products",
		"quantity": quantity,
		"mass_per_unit": mass,
		"tonnes": float(quantity) * mass,
		"requires_capabilities": ["refrigerated"],
		"life_support_seats": 0,
		"compute_demand": 0.0,
		"power_demand": 0.0,
		"description": "%d pallets of preserved rations for %s." % [quantity, dest.get("name", "")],
		"hold_label": "refrigerated",
		"reward": reward,
	}


static func _inject_freight_offer(
	missions: MissionSubsystem,
	session: GameSession,
	catalog: Catalog,
	offer: Dictionary
) -> void:
	var habitat_id := str(offer.get("origin_habitat_id", ""))
	missions.freight_offers_by_habitat[habitat_id] = [offer]
	missions.generated_day = CommodityEconomy.gst_day(session.gst_seconds)


static func _test_board_generates(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "FRT-BOARD")
	missions.ensure_boards(session, catalog)
	var offers := missions.list_freight_offers("proxima_habitat")
	runner.check(offers.size() >= 1, "freight: board generates offers")


static func _test_food_description_and_budgets(runner: TestRunner, catalog: Catalog) -> void:
	var offers := FreightCharters.generate_offers(catalog, "proxima_habitat", 1, 8, 99)
	var found := false
	for offer_variant in offers:
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = offer_variant
		if str(offer.get("commodity_id", "")) != "food_products":
			continue
		found = true
		var desc := str(offer.get("description", ""))
		runner.check(
			not desc.contains("food_products") and not desc.contains("Freight lot"),
			"freight: food blurb is specific"
		)
		runner.check(int(offer.get("life_support_seats", -1)) == 0, "freight: food has no seat draw")
		runner.check(float(offer.get("compute_demand", -1.0)) == 0.0, "freight: food has no compute draw")
		runner.check(float(offer.get("power_demand", -1.0)) == 0.0, "freight: food has no power draw")
		break
	runner.check(found, "freight: generated board includes food lot")


static func _test_plain_hold_blocks_food(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "FRT-PLAIN")
	var ship := session.get_cargo_ship()
	if ship == null:
		runner.check(false, "freight: plain hold test needs cargo ship")
		return
	var offer := _food_offer(catalog, "proxima_habitat", "irasia_habitat", "freight_plain_block")
	_inject_freight_offer(missions, session, catalog, offer)
	var check := missions.evaluate_freight_offer(session, catalog, offer.id, ship.id)
	runner.check(not bool(check.get("ok", false)), "freight: plain Tukey hold blocks food")


static func _test_coolstore_accepts_food(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "FRT-COLD")
	var ship := session.get_cargo_ship()
	if ship == null:
		return
	ship.set_module(_cargo_slot(ship), "ok_coolstore_10")
	var offer := _food_offer(catalog, "proxima_habitat", "irasia_habitat", "freight_cold_ok")
	offer["quantity"] = 2
	offer["tonnes"] = 2.0
	var cfg := FreightCharters.config(catalog)
	offer["reward"] = FreightCharters.compute_reward(cfg, 2, 1.0, 1.0, int(offer.get("friction", 0)))
	_inject_freight_offer(missions, session, catalog, offer)
	var check := missions.evaluate_freight_offer(session, catalog, offer.id, ship.id)
	runner.check(bool(check.get("ok", false)), "freight: coolstore accepts food when tonnes fit")


static func _test_livestock_requires_lss_hold(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "FRT-LIVE")
	var ship := session.get_cargo_ship()
	if ship == null:
		return
	ship.set_module(_cargo_slot(ship), "ok_coolstore_10")
	var offer := _livestock_offer(catalog, "proxima_habitat", "irasia_habitat", "freight_live_hold")
	_inject_freight_offer(missions, session, catalog, offer)
	var check := missions.evaluate_freight_offer(session, catalog, offer.id, ship.id)
	runner.check(not bool(check.get("ok", false)), "freight: refrigerated hold cannot take livestock")


static func _livestock_offer(
	catalog: Catalog,
	origin_habitat_id: String,
	destination_habitat_id: String,
	offer_id: String
) -> Dictionary:
	var dest := catalog.get_habitat(destination_habitat_id)
	var friction := PassengerCharters.friction_between(
		catalog,
		str(catalog.get_habitat(origin_habitat_id).get("sector_id", "")),
		str(dest.get("sector_id", ""))
	)
	var cfg := FreightCharters.config(catalog)
	var quantity := 2
	var mass := 0.8
	var reward := FreightCharters.compute_reward(cfg, quantity, mass, 1.6, friction)
	return {
		"id": offer_id,
		"origin_habitat_id": origin_habitat_id,
		"destination_habitat_id": destination_habitat_id,
		"destination_name": str(dest.get("name", destination_habitat_id)),
		"friction": friction,
		"cargo_id": "livestock",
		"quantity": quantity,
		"mass_per_unit": mass,
		"tonnes": float(quantity) * mass,
		"requires_capabilities": ["life_support_integrated"],
		"life_support_seats": quantity,
		"compute_demand": 0.0,
		"power_demand": 0.0,
		"description": "%d stud horses for %s." % [quantity, dest.get("name", "")],
		"hold_label": "live cargo",
		"reward": reward,
	}


static func _test_livestock_lss_with_passengers(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "FRT-LSS")
	var ship := session.get_cargo_ship()
	if ship == null:
		return
	ship.set_module(_cargo_slot(ship), "carthage_live_4")
	var passenger := {
		"id": "pass_test",
		"origin_habitat_id": "proxima_habitat",
		"destination_habitat_id": "irasia_habitat",
		"quantity": 3,
		"life_support": "spartan",
		"reward": 100,
	}
	var passenger_charter := passenger.duplicate(true)
	passenger_charter["charter_id"] = "charter_test"
	passenger_charter["ship_id"] = ship.id
	missions.accepted.append(passenger_charter)
	var offer := _livestock_offer(catalog, "proxima_habitat", "irasia_habitat", "freight_lss_mix")
	offer["quantity"] = 2
	offer["life_support_seats"] = 2
	_inject_freight_offer(missions, session, catalog, offer)
	var check := missions.evaluate_freight_offer(session, catalog, offer.id, ship.id)
	runner.check(not bool(check.get("ok", false)), "freight: passengers plus livestock exceed LSS")


static func _test_cognition_compute_cap(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "FRT-CU")
	var ship := session.get_owned_ship("flare_on_ss_1")
	if ship == null:
		runner.check(false, "freight: cognition test needs flare template")
		return
	session.fleet.current_ship_id = ship.id
	for entry in ship.modules.duplicate(true):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		if slot.begins_with("system") and slot != "system_4":
			ship.set_module(slot, "")
	ship.set_module("other_2", "chettiar_compute_vault_10")
	var dest := catalog.get_habitat("irasia_habitat")
	var friction := 15
	var cfg := FreightCharters.config(catalog)
	var quantity := 3
	var mass := 0.25
	var offer := {
		"id": "freight_cog",
		"origin_habitat_id": "proxima_habitat",
		"destination_habitat_id": "irasia_habitat",
		"destination_name": str(dest.get("name", "")),
		"friction": friction,
		"cargo_id": "cognition_crate",
		"quantity": quantity,
		"mass_per_unit": mass,
		"tonnes": float(quantity) * mass,
		"requires_capabilities": ["compute_integrated"],
		"life_support_seats": 0,
		"compute_demand": float(quantity) * 2.5,
		"power_demand": 0.0,
		"description": "Cognition crates for Irasia.",
		"hold_label": "compute-integrated",
		"reward": FreightCharters.compute_reward(cfg, quantity, mass, 1.8, friction),
	}
	_inject_freight_offer(missions, session, catalog, offer)
	var check := missions.evaluate_freight_offer(session, catalog, offer.id, ship.id)
	runner.check(not bool(check.get("ok", false)), "freight: cognition lot exceeds spare compute")


static func _test_cancel_at_origin(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "FRT-CANCEL")
	var ship := session.get_cargo_ship()
	if ship == null:
		return
	ship.set_module(_cargo_slot(ship), "ok_coolstore_10")
	var offer := _food_offer(catalog, "proxima_habitat", "irasia_habitat", "freight_cancel")
	offer["quantity"] = 1
	offer["tonnes"] = 1.0
	_inject_freight_offer(missions, session, catalog, offer)
	runner.check(
		missions.accept_freight_offer(session, catalog, offer.id, ship.id),
		"freight: accept for cancel test"
	)
	var credits_before := session.credits
	var charter_id := str(missions.list_freight_accepted()[0].get("charter_id", ""))
	runner.check(
		missions.cancel_freight_charter(session, catalog, charter_id),
		"freight: cancel at origin"
	)
	runner.check(missions.list_freight_accepted().is_empty(), "freight: cancel clears contract")
	runner.check(session.credits < credits_before, "freight: cancel charges penalty")


static func _test_dock_pays_and_clears(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "FRT-DOCK")
	_wire_events(session, catalog, simulation)
	var ship := session.get_cargo_ship()
	if ship == null:
		return
	ship.set_module(_cargo_slot(ship), "ok_coolstore_10")
	var offer := _food_offer(catalog, "proxima_habitat", "bela_orbital_habitat", "freight_dock")
	offer["quantity"] = 1
	offer["tonnes"] = 1.0
	var cfg := FreightCharters.config(catalog)
	offer["reward"] = FreightCharters.compute_reward(
		cfg,
		1,
		1.0,
		1.0,
		int(offer.get("friction", 0))
	)
	_inject_freight_offer(missions, session, catalog, offer)
	runner.check(
		missions.accept_freight_offer(session, catalog, offer.id, ship.id),
		"freight: accept for delivery"
	)
	var reward := int(offer.get("reward", 0))
	var credits_before := session.credits
	runner.check(session.undock(catalog, ship.id, missions), "freight: undock for delivery")
	runner.check(session.enter_sector(catalog, "bela", false), "freight: travel to bela")
	runner.check(session.dock(catalog, "bela_orbital_habitat"), "freight: dock at destination")
	runner.check(missions.list_freight_accepted().is_empty(), "freight: dock clears contract")
	runner.check(session.credits >= credits_before + reward, "freight: dock pays reward")


static func _test_reputation_gate(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "FRT-REP")
	var ship := session.get_cargo_ship()
	if ship == null:
		runner.check(false, "freight: cargo ship for reputation gate")
		return
	const MIN_REP := 50
	var offer := {
		"quantity": 0,
		"tonnes": 0.0,
		"requires_capabilities": [],
		"life_support_seats": 0,
		"compute_demand": 0.0,
		"power_demand": 0.0,
		"min_reputation": MIN_REP,
	}
	var check := FreightCharters.evaluate_offer_for_ship(session, catalog, offer, ship.id, {})
	runner.check(not bool(check.get("ok", false)), "freight: reputation gate blocks default pilot")
	session.player.reputation = MIN_REP
	check = FreightCharters.evaluate_offer_for_ship(session, catalog, offer, ship.id, {})
	runner.check(bool(check.get("ok", false)), "freight: reputation gate passes at minimum")
