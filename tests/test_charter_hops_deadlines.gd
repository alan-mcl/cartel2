class_name TestCharterHopsDeadlines
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_two_hop_destination_exists(runner, catalog)
	_test_two_hop_pay_uses_path_friction(runner, catalog)
	_test_multihop_passenger_requires_habitat_ls(runner, catalog)
	_test_on_time_destination_pays(runner, catalog)
	_test_late_destination_charges_cancel_fee(runner, catalog)
	_test_penalty_can_overdraw(runner, catalog)
	_test_spend_blocked_when_overdrawn(runner, catalog)
	_test_late_passenger_elsewhere_clears(runner, catalog)
	_test_late_freight_elsewhere_keeps_contract(runner, catalog)
	_test_legacy_charter_without_deadline_pays(runner, catalog)
	_test_deadline_covers_jump_gate_lag(runner, catalog)
	_test_charter_tooltip_layout(runner, catalog)


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
	runner.check(session.start_new_game(catalog, callsign, "tester"), "charter hops: session starts")
	return session


static func _best_docked_ship(session: GameSession, catalog: Catalog, habitat_id: String) -> OwnedShip:
	var best: OwnedShip = null
	var best_cap := -1.0
	for ship in session.ships_at(habitat_id):
		var assembled := ShipAssembler.assemble_owned(catalog, ship)
		var cap := float(assembled.capacities.get("life_support_capacity", 0.0))
		if cap > best_cap:
			best_cap = cap
			best = ship
	return best


static func _two_hop_dest(catalog: Catalog, origin_habitat_id: String) -> Dictionary:
	var cfg := PassengerCharters.config(catalog)
	var max_hops := PassengerCharters.max_hops_from_config(cfg)
	for entry_variant in PassengerCharters.multi_hop_destinations(
		catalog, origin_habitat_id, max_hops
	):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if int(entry.get("hops", 0)) == 2:
			return entry
	return {}


static func _passenger_offer(
	catalog: Catalog,
	origin_habitat_id: String,
	dest: Dictionary,
	offer_id: String,
	hops: int = 1
) -> Dictionary:
	var cfg := PassengerCharters.config(catalog)
	var friction := int(dest.get("friction", 0))
	var reward := PassengerCharters.compute_reward(cfg, 2, 1.0, friction)
	var path_sectors: Array = dest.get("path_sectors", [])
	if path_sectors.is_empty():
		path_sectors = [
			str(catalog.get_habitat(origin_habitat_id).get("sector_id", "")),
			str(dest.get("sector_id", "")),
		]
	var deadline_hours := PassengerCharters.offer_deadline_hours(catalog, cfg, path_sectors)
	return {
		"id": offer_id,
		"board": PassengerCharters.BOARD_TERMINAL,
		"origin_habitat_id": origin_habitat_id,
		"destination_habitat_id": str(dest.get("habitat_id", "")),
		"destination_name": str(dest.get("habitat_name", "")),
		"friction": friction,
		"hops": hops,
		"via_label": str(dest.get("via_label", "")),
		"deadline_hours": deadline_hours,
		"role_id": "steerage",
		"role_title": "Steerage passengers",
		"affiliation": "civilian",
		"life_support": "spartan",
		"quantity": 2,
		"pay_multiplier": 1.0,
		"requires_player_affiliation": false,
		"corporation_id": "",
		"corporation_name": "",
		"description": "Test charter.",
		"reward": reward,
	}


static func _inject_passenger_offer(
	missions: MissionSubsystem,
	session: GameSession,
	offer: Dictionary
) -> void:
	var habitat_id := str(offer.get("origin_habitat_id", ""))
	missions.offers_by_habitat[habitat_id] = {
		PassengerCharters.BOARD_TERMINAL: [offer],
	}
	missions.generated_day = CommodityEconomy.gst_day(session.gst_seconds)


static func _test_two_hop_destination_exists(runner: TestRunner, catalog: Catalog) -> void:
	var dest := _two_hop_dest(catalog, "proxima_habitat")
	runner.check(not dest.is_empty(), "charter hops: proxima has a two-hop destination")
	runner.check(int(dest.get("friction", 0)) > 0, "charter hops: two-hop path has friction")


static func _test_two_hop_pay_uses_path_friction(runner: TestRunner, catalog: Catalog) -> void:
	var dest := _two_hop_dest(catalog, "proxima_habitat")
	if dest.is_empty():
		return
	var cfg := PassengerCharters.config(catalog)
	var neighbor := PassengerCharters.neighbor_destinations(catalog, "proxima_habitat")
	if neighbor.is_empty():
		return
	var one_hop_friction := int(neighbor[0].get("friction", 0))
	var two_hop_friction := int(dest.get("friction", 0))
	var one_pay := PassengerCharters.compute_reward(cfg, 2, 1.0, one_hop_friction)
	var two_pay := PassengerCharters.compute_reward(cfg, 2, 1.0, two_hop_friction)
	runner.check(two_pay > one_pay, "charter hops: two-hop pay exceeds typical one-hop pay")


static func _test_multihop_passenger_requires_habitat_ls(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "CH-HAB")
	var ship := session.get_owned_ship("flare_on_ss_1")
	if ship == null:
		runner.check(false, "charter hops: flare needed for habitat LS test")
		return
	session.fleet.current_ship_id = ship.id
	var dest := _two_hop_dest(catalog, "proxima_habitat")
	if dest.is_empty():
		return
	var offer := _passenger_offer(catalog, "proxima_habitat", dest, "hab_ls_test", 2)
	_inject_passenger_offer(missions, session, offer)
	var check := missions.evaluate_offer(session, catalog, offer.id, ship.id)
	runner.check(not bool(check.get("ok", false)), "charter hops: multi-hop blocks without habitat LS")
	ship.set_module("system_2", "gi_ls_4")
	check = missions.evaluate_offer(session, catalog, offer.id, ship.id)
	runner.check(bool(check.get("ok", false)), "charter hops: habitat LS allows multi-hop accept eval")


static func _test_on_time_destination_pays(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "CH-ONTIME")
	_wire_events(session, catalog, simulation)
	var ship := _best_docked_ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var dest := catalog.get_habitat("bela_orbital_habitat")
	var offer := _passenger_offer(
		catalog,
		"proxima_habitat",
		{
			"habitat_id": "bela_orbital_habitat",
			"habitat_name": str(dest.get("name", "Bela")),
			"friction": 45,
		},
		"on_time"
	)
	_inject_passenger_offer(missions, session, offer)
	runner.check(missions.accept_offer(session, catalog, offer.id, ship.id), "charter hops: accept on-time test")
	var reward := int(offer.get("reward", 0))
	var credits_before := session.credits
	runner.check(session.undock(catalog, ship.id, missions), "charter hops: undock on-time")
	runner.check(session.enter_sector(catalog, "bela", false), "charter hops: travel bela")
	runner.check(session.dock(catalog, "bela_orbital_habitat"), "charter hops: dock on time")
	runner.check(missions.list_accepted().is_empty(), "charter hops: on-time clears charter")
	runner.check(session.credits >= credits_before + reward, "charter hops: on-time pays reward")


static func _test_late_destination_charges_cancel_fee(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "CH-LATE")
	_wire_events(session, catalog, simulation)
	var ship := _best_docked_ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var dest := catalog.get_habitat("bela_orbital_habitat")
	var offer := _passenger_offer(
		catalog,
		"proxima_habitat",
		{
			"habitat_id": "bela_orbital_habitat",
			"habitat_name": str(dest.get("name", "Bela")),
			"friction": 45,
		},
		"late_dest",
		1
	)
	offer["deadline_hours"] = 1
	_inject_passenger_offer(missions, session, offer)
	runner.check(missions.accept_offer(session, catalog, offer.id, ship.id), "charter hops: accept late dest test")
	var reward := int(offer.get("reward", 0))
	var penalty := PassengerCharters.cancel_penalty(PassengerCharters.config(catalog), reward)
	session.credits = penalty + 5
	var credits_before := session.credits
	session.advance_gst(float(GalacticCalendar.SECONDS_PER_HOUR * 2))
	runner.check(session.undock(catalog, ship.id, missions), "charter hops: undock late")
	runner.check(session.enter_sector(catalog, "bela", false), "charter hops: travel bela late")
	runner.check(session.dock(catalog, "bela_orbital_habitat"), "charter hops: dock late at destination")
	runner.check(missions.list_accepted().is_empty(), "charter hops: late destination clears")
	runner.check(
		session.credits <= credits_before - penalty + 1,
		"charter hops: late destination charges cancel fee not reward"
	)


static func _test_penalty_can_overdraw(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "CH-OVER")
	session.credits = 10
	session.assess_penalty_credits(50)
	runner.check(session.credits < 0, "charter hops: penalty overdraws credits")


static func _test_spend_blocked_when_overdrawn(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "CH-NOSPEND")
	session.credits = -5
	runner.check(not session.try_spend_credits(1), "charter hops: spend blocked when overdrawn")


static func _test_late_passenger_elsewhere_clears(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "CH-PAX-WALK")
	_wire_events(session, catalog, simulation)
	var ship := _best_docked_ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var offer := _passenger_offer(
		catalog,
		"proxima_habitat",
		{
			"habitat_id": "bela_orbital_habitat",
			"habitat_name": "Bela",
			"friction": 45,
		},
		"pax_walk",
		1
	)
	offer["deadline_hours"] = 1
	_inject_passenger_offer(missions, session, offer)
	runner.check(missions.accept_offer(session, catalog, offer.id, ship.id), "charter hops: accept walk-off test")
	session.advance_gst(float(GalacticCalendar.SECONDS_PER_HOUR * 2))
	runner.check(session.undock(catalog, ship.id, missions), "charter hops: launch walk-off")
	runner.check(session.enter_sector(catalog, "irasia", false), "charter hops: travel irasia")
	runner.check(session.dock(catalog, "irasia_habitat"), "charter hops: dock wrong habitat late")
	runner.check(missions.list_accepted().is_empty(), "charter hops: late passenger clears off-route")


static func _test_late_freight_elsewhere_keeps_contract(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "CH-FRT-KEEP")
	_wire_events(session, catalog, simulation)
	var ship := session.get_owned_ship("pegasus_p101_1")
	if ship == null:
		runner.check(false, "charter hops: pegasus needed for freight keep test")
		return
	session.fleet.current_ship_id = ship.id
	ship.set_module("other_3", "ok_coolstore_10")
	var offer := {
		"id": "freight_keep",
		"origin_habitat_id": "proxima_habitat",
		"destination_habitat_id": "bela_orbital_habitat",
		"destination_name": "Bela",
		"friction": 45,
		"hops": 1,
		"deadline_hours": 1,
		"commodity_id": "food_products",
		"quantity": 1,
		"mass_per_unit": 1.0,
		"tonnes": 1.0,
		"requires_capabilities": ["refrigerated"],
		"life_support_seats": 0,
		"compute_demand": 0.0,
		"power_demand": 0.0,
		"description": "Late freight test.",
		"hold_label": "refrigerated",
		"reward": 100,
	}
	missions.freight_offers_by_habitat["proxima_habitat"] = [offer]
	missions.generated_day = CommodityEconomy.gst_day(session.gst_seconds)
	runner.check(missions.accept_freight_offer(session, catalog, offer.id, ship.id), "charter hops: accept freight keep test")
	session.advance_gst(float(GalacticCalendar.SECONDS_PER_HOUR * 2))
	runner.check(session.undock(catalog, ship.id, missions), "charter hops: undock freight keep")
	runner.check(session.enter_sector(catalog, "irasia", false), "charter hops: irasia freight keep")
	runner.check(session.dock(catalog, "irasia_habitat"), "charter hops: dock irasia freight keep")
	runner.check(missions.list_freight_accepted().size() == 1, "charter hops: late freight stays active off-route")


static func _test_deadline_covers_jump_gate_lag(runner: TestRunner, catalog: Catalog) -> void:
	var cfg := PassengerCharters.config(catalog)
	var path := PackedStringArray(["proxima", "bela"])
	var hours := PassengerCharters.offer_deadline_hours(catalog, cfg, path)
	var translation := PassengerCharters.path_translation_seconds(catalog, path)
	runner.check(
		hours * GalacticCalendar.SECONDS_PER_HOUR >= translation,
		"charter hops: deadline hours cover entry+exit translation"
	)
	runner.check(hours >= 10, "charter hops: proxima-bela deadline is achievable")


static func _test_legacy_charter_without_deadline_pays(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "CH-LEGACY")
	_wire_events(session, catalog, simulation)
	var ship := _best_docked_ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	missions.accepted.append({
		"charter_id": "legacy_1",
		"ship_id": ship.id,
		"origin_habitat_id": "proxima_habitat",
		"destination_habitat_id": "bela_orbital_habitat",
		"destination_name": "Bela",
		"quantity": 2,
		"reward": 200,
	})
	var credits_before := session.credits
	runner.check(session.undock(catalog, ship.id, missions), "charter hops: legacy undock")
	runner.check(session.enter_sector(catalog, "bela", false), "charter hops: legacy travel")
	runner.check(session.dock(catalog, "bela_orbital_habitat"), "charter hops: legacy dock")
	runner.check(missions.list_accepted().is_empty(), "charter hops: legacy clears")
	runner.check(session.credits >= credits_before + 200, "charter hops: legacy pays without deadline_gst")


static func _test_charter_tooltip_layout(runner: TestRunner, catalog: Catalog) -> void:
	var passenger := {
		"role_title": "Tourist party",
		"destination_name": "Bela",
		"via_label": " via Proxima Exchange",
		"hops": 2,
		"deadline_hours": 24,
		"life_support": "comfort",
		"quantity": 4,
		"reward": 500,
		"min_reputation": 15,
		"requires_player_affiliation": false,
		"description": "Four tourists for Bela.",
	}
	var passenger_tooltip := CharterTooltipText.format_passenger(passenger)
	runner.check(
		passenger_tooltip.contains("\n\n"),
		"charter tooltip: passenger sections separated by blank lines"
	)
	runner.check(
		passenger_tooltip.contains("Suggested route: 2 hops via Proxima Exchange"),
		"charter tooltip: passenger suggested route"
	)
	runner.check(
		passenger_tooltip.contains("Requirements"),
		"charter tooltip: passenger requirements heading"
	)
	runner.check(
		passenger_tooltip.contains("• Habitat life support"),
		"charter tooltip: passenger habitat life support bullet"
	)
	runner.check(
		passenger_tooltip.contains("• Comfort life support"),
		"charter tooltip: passenger comfort tier bullet"
	)
	runner.check(
		passenger_tooltip.contains("• 4 passenger seats"),
		"charter tooltip: passenger seat bullet"
	)
	runner.check(
		passenger_tooltip.contains("• Reputation 15"),
		"charter tooltip: passenger reputation bullet"
	)
	var req_index := passenger_tooltip.find("Requirements")
	var suggested_index := passenger_tooltip.find("Suggested route")
	runner.check(
		req_index > suggested_index and not passenger_tooltip.substr(req_index).contains("Suggested route"),
		"charter tooltip: hop count not listed under requirements"
	)
	runner.check(
		not passenger_tooltip.substr(req_index).contains("via Proxima"),
		"charter tooltip: via habitats not listed under requirements"
	)

	var freight := {
		"cargo_title": "Cold-chain vaccine shipment",
		"description": "2 vaccine cases for Bela.",
		"destination_name": "Bela",
		"hops": 1,
		"deadline_hours": 12,
		"tonnes": 1.5,
		"reward": 300,
		"requires_capabilities": ["refrigerated", "biohazard"],
		"life_support_seats": 0,
		"compute_demand": 0.0,
		"power_demand": 0.0,
		"min_reputation": 0,
	}
	var freight_tooltip := CharterTooltipText.format_freight(freight)
	runner.check(
		freight_tooltip.contains("Cold-chain vaccine shipment"),
		"charter tooltip: freight cargo title"
	)
	runner.check(
		freight_tooltip.contains("• refrigerated"),
		"charter tooltip: freight hold capability bullet"
	)
	runner.check(
		freight_tooltip.contains("• biohazard"),
		"charter tooltip: freight second hold capability bullet"
	)
	runner.check(
		freight_tooltip.contains("• 1.5 t cargo"),
		"charter tooltip: freight tonne bullet"
	)
	runner.check(
		not freight_tooltip.contains("Suggested route"),
		"charter tooltip: one-hop freight omits suggested route"
	)
