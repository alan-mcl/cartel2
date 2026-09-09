class_name TestSession
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var session := GameSession.new()

	runner.check(
		session.start_new_game(catalog, "TST-1", "tester"),
		"start_new_game tester succeeds"
	)
	runner.check_eq(session.sector_id, "proxima", "tester starts in proxima")
	runner.check(session.docked, "tester begins docked")

	var parked := session.ships_at("proxima_habitat")
	runner.check(parked.size() >= 2, "tester ships parked at proxima_habitat")

	var owned := session.get_current_owned_ship()
	runner.check(owned != null, "tester current owned ship is set")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	runner.check(assembled.stats.max_speed > 0.0, "assembled current ship has speed")

	var hotshot := GameSession.new()
	runner.check(
		hotshot.start_new_game(catalog, "HOT-1", "hotshot"),
		"start_new_game hotshot succeeds"
	)
	runner.check_eq(hotshot.sector_id, "bela", "hotshot starts in bela")
	runner.check_eq(hotshot.ships_at("bela_orbital_habitat").size(), 1, "hotshot has one ship")

	var entrepreneur := GameSession.new()
	runner.check(
		entrepreneur.start_new_game(catalog, "ENT-1", "entrepreneur"),
		"start_new_game entrepreneur succeeds"
	)
	runner.check(entrepreneur.docked, "entrepreneur begins docked")
	runner.check_eq(entrepreneur.owned_ships.size(), 0, "entrepreneur has no ships")
	runner.check_eq(entrepreneur.credits, 32000, "entrepreneur credits")

	runner.check(entrepreneur.visit(catalog, "skyedge_space_ships"), "entrepreneur visits Skyedge")
	runner.check(
		entrepreneur.buy_chassis(catalog, "flare_on_chassis"),
		"entrepreneur buys empty Flare-ON chassis"
	)
	runner.check_eq(entrepreneur.owned_ships.size(), 1, "entrepreneur owns one hull")
	runner.check(entrepreneur.owned_ships[0].modules.is_empty(), "purchased chassis is unfitted")
	runner.check_eq(entrepreneur.credits, 24000, "entrepreneur credits after chassis purchase")
	runner.check(
		not entrepreneur.undock(catalog, entrepreneur.owned_ships[0].id),
		"empty chassis cannot undock"
	)

	var buyer := GameSession.new()
	runner.check(buyer.start_new_game(catalog, "BUY-1", "entrepreneur"), "buyer session starts")
	runner.check(buyer.visit(catalog, "concord_scouts"), "buyer visits Concord Scouts")
	var used_price := ShipAssembly.used_ship_price(catalog, "flare_on_ss")
	runner.check(used_price > 0, "used ship price computed")
	runner.check(
		buyer.buy_used_ship(catalog, "flare_on_ss"),
		"buy used Flare-ON SS"
	)
	runner.check_eq(buyer.credits, 32000 - used_price, "buyer credits after used ship")
	runner.check_eq(buyer.owned_ships.size(), 1, "buyer owns purchased ship")
	runner.check(
		not buyer.buy_chassis(catalog, "flare_on_chassis"),
		"chassis purchase rejected at ship dealer"
	)

	var broke := GameSession.new()
	runner.check(broke.start_new_game(catalog, "POOR-1", "outlaw"), "outlaw session starts")
	runner.check(broke.visit(catalog, "concord_scouts"), "outlaw visits Concord Scouts")
	runner.check(
		not broke.buy_used_ship(catalog, "dragon_gold"),
		"unaffordable used ship rejected"
	)

	var beacon_only := GameSession.new()
	runner.check(
		beacon_only.start_new_game(catalog, "BEACON-1", "entrepreneur"),
		"beacon-only session starts"
	)
	runner.check(beacon_only.visit(catalog, "skyedge_space_ships"), "beacon-only visits Skyedge")
	runner.check(beacon_only.buy_chassis(catalog, "flare_on_chassis"), "beacon-only buys chassis")
	runner.check(beacon_only.visit(catalog, "habitat_workshop"), "beacon-only visits shipyard")
	runner.check(
		ShipAssembly.buy_part(beacon_only, catalog, "vessel_registration_beacon"),
		"beacon-only buys transponder"
	)
	var bare_hull := beacon_only.owned_ships[0]
	runner.check(
		ShipAssembly.install_module(
			beacon_only,
			catalog,
			bare_hull.id,
			"system_1",
			"vessel_registration_beacon"
		),
		"beacon-only installs transponder"
	)
	runner.check(
		not beacon_only.undock(catalog, bare_hull.id),
		"beacon-only hull cannot undock"
	)

	var gate_session := GameSession.new()
	runner.check(gate_session.start_new_game(catalog, "GATE-1", "tester"), "gate session starts")
	var gate_ship := gate_session.get_owned_ship("flare_on_ss_1")
	runner.check(gate_ship != null, "gate session has flare_on_ss_1")
	runner.check(
		ShipAssembly.undock_blockers(catalog, gate_ship).is_empty(),
		"fully fitted ship has no launch blockers"
	)

	var no_fuel := OwnedShip.from_dict(gate_ship.to_dict())
	no_fuel.fuel_current = 0.0
	runner.check(_blockers_include(catalog, no_fuel, "fuel"), "zero fuel blocks launch")

	var no_ls := OwnedShip.from_dict(gate_ship.to_dict())
	_remove_modules_in_category(catalog, no_ls, "life_support")
	runner.check(_blockers_include(catalog, no_ls, "life support"), "missing life support blocks launch")

	var no_power := OwnedShip.from_dict(gate_ship.to_dict())
	no_power.remove_module("power_1")
	runner.check(_blockers_include(catalog, no_power, "power"), "missing reactor blocks launch")

	var no_xpdr := OwnedShip.from_dict(gate_ship.to_dict())
	no_xpdr.remove_module("system_4")
	runner.check(_blockers_include(catalog, no_xpdr, "transponder"), "missing transponder blocks launch")

	var xpdr_off := OwnedShip.from_dict(gate_ship.to_dict())
	xpdr_off.transponder_enabled = false
	runner.check(
		_blockers_include(catalog, xpdr_off, "deactivated"),
		"disabled transponder blocks launch"
	)
	runner.check(gate_session.undock(catalog, gate_ship.id), "fully fitted tester ship undocks")

	runner.check(
		session.enter_unspace(catalog, "bela", 4, assembled),
		"enter_unspace proxima→bela"
	)
	runner.check(session.in_unspace, "session marks in_unspace")
	runner.check_eq(session.unspace_world_id, "n4_default", "unspace world id")
	runner.check_eq(session.pending_destination_id, "bela", "pending destination bela")

	runner.check(session.arrive_from_unspace(catalog), "arrive_from_unspace succeeds")
	runner.check(not session.in_unspace, "no longer in unspace after arrival")
	runner.check_eq(session.sector_id, "bela", "arrived in bela sector")

	var salvage_def := InteractableDef.new()
	salvage_def.id = "unit_test_salvage"
	salvage_def.kind = InteractableDef.Kind.SALVAGE
	salvage_def.salvage_reward = 50
	var credits_before := session.credits
	runner.check(session.salvage(salvage_def), "first salvage succeeds")
	runner.check_eq(session.credits, credits_before + 50, "salvage credits applied")
	runner.check(not session.salvage(salvage_def), "duplicate salvage rejected")
	runner.check(salvage_def.id in session.salvaged_ids, "salvage id recorded")


static func _blockers_include(catalog: Catalog, ship: OwnedShip, needle: String) -> bool:
	var lowered := needle.to_lower()
	for reason in ShipAssembly.undock_blockers(catalog, ship):
		if lowered in reason.to_lower():
			return true
	return false


static func _remove_modules_in_category(catalog: Catalog, ship: OwnedShip, category: String) -> void:
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_data: Variant = entry.get("data", {})
		if typeof(module_data) != TYPE_DICTIONARY:
			continue
		if str(module_data.get("category", "")) == category:
			ship.remove_module(str(entry.get("slot", "")))
