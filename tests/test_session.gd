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

	_test_habitat_tram_hop(runner, catalog)

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

	var old_money := GameSession.new()
	runner.check(
		old_money.start_new_game(catalog, "OLD-1", "old_money"),
		"start_new_game old_money succeeds"
	)
	runner.check_eq(old_money.habitat_id, "proxima_habitat", "old_money starts at proxima")
	runner.check(old_money.docked, "old_money begins docked")
	runner.check_eq(old_money.credits, 1500, "old_money credits")
	runner.check_eq(old_money.player.reputation, 8, "old_money reputation")
	runner.check_eq(old_money.owned_ships.size(), 1, "old_money has one ship")
	runner.check_eq(old_money.owned_ships[0].chassis_id, "silhouette_chassis", "old_money ship chassis")
	runner.check(
		ShipAssembly.undock_blockers(catalog, old_money.owned_ships[0]).is_empty(),
		"old_money ship can launch"
	)

	var influencer := GameSession.new()
	runner.check(
		influencer.start_new_game(catalog, "INF-1", "influencer"),
		"start_new_game influencer succeeds"
	)
	runner.check_eq(influencer.habitat_id, "fortuna_habitat", "influencer starts at fortuna")
	runner.check(influencer.docked, "influencer begins docked")
	runner.check_eq(influencer.credits, 4000, "influencer credits")
	runner.check_eq(influencer.player.reputation, 25, "influencer reputation")
	runner.check_eq(influencer.owned_ships.size(), 1, "influencer has one ship")
	runner.check_eq(influencer.owned_ships[0].chassis_id, "krypton_chassis", "influencer ship chassis")
	runner.check(
		ShipAssembly.undock_blockers(catalog, influencer.owned_ships[0]).is_empty(),
		"influencer ship can launch"
	)

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
	runner.check(broke.start_new_game(catalog, "POOR-1", "entrepreneur"), "poor buyer session starts")
	broke.credits = 750
	runner.check(broke.visit(catalog, "concord_scouts"), "poor buyer visits Concord Scouts")
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
	runner.check(beacon_only.visit(catalog, "proxima_shipyard"), "beacon-only visits shipyard")
	runner.check(
		not beacon_only.visit(catalog, "tycho_exchange"),
		"cannot visit exchange on another habitat"
	)
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
	no_fuel.fuels.clear()
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

	var rename_session := GameSession.new()
	runner.check(
		rename_session.start_new_game(catalog, "REN-1", "tester"),
		"rename session starts docked"
	)
	var rename_ship := rename_session.owned_ships[0]
	runner.check(
		rename_session.rename_ship(rename_ship.id, "  New Name  "),
		"rename docked ship succeeds"
	)
	runner.check_eq(rename_ship.name, "New Name", "rename strips whitespace")
	runner.check(
		not rename_session.rename_ship(rename_ship.id, "   "),
		"empty rename rejected"
	)
	rename_ship.location = "aboard"
	runner.check(
		not rename_session.rename_ship(rename_ship.id, "Away Ship"),
		"rename rejected when ship not at habitat"
	)

	runner.check(
		session.enter_unspace(catalog, "bela", 4, assembled, 42),
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


static func _test_habitat_tram_hop(runner: TestRunner, catalog: Catalog) -> void:
	var tram_session := GameSession.new()
	runner.check(
		tram_session.start_new_game(catalog, "TRAM-1", "tester"),
		"tram: session starts docked"
	)
	var gst_before := tram_session.gst_seconds
	runner.check_eq(
		tram_session.building_id,
		"proxima_habitat_terminal",
		"tram: starts at default building"
	)

	runner.check(
		tram_session.visit(catalog, "skyedge_space_ships"),
		"tram: visit another building"
	)
	runner.check_eq(
		tram_session.gst_seconds,
		gst_before + 15.0 * float(GalacticCalendar.SECONDS_PER_MINUTE),
		"tram: visit advances GST fifteen minutes"
	)
	runner.check_eq(
		tram_session.last_log,
		"Took a tram over to Skyedge Space Ships.",
		"tram: visit sets log message"
	)

	var gst_after_hop := tram_session.gst_seconds
	runner.check(
		tram_session.visit(catalog, "skyedge_space_ships"),
		"tram: repeat visit to same building succeeds"
	)
	runner.check_eq(
		tram_session.gst_seconds,
		gst_after_hop,
		"tram: same building does not advance GST"
	)


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
		var module_data: ModuleDef = entry.get("data", null)
		if module_data == null:
			continue
		if module_data.category == category:
			ship.remove_module(str(entry.get("slot", "")))
