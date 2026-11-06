class_name TestCharterResolution
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_on_time_pay(runner, catalog)
	_test_early_finish_first_half(runner, catalog)
	_test_early_finish_second_half(runner, catalog)
	_test_early_finish_requires_accepted_gst(runner, catalog)
	_test_passenger_early_finish_on_dock(runner, catalog)
	_test_late_fee(runner, catalog)
	_test_zero_reward_completion(runner, catalog)
	_test_missed_deadline(runner, catalog)
	_test_sandbox_skips_career(runner, catalog)
	_test_scan_satisfaction(runner, catalog)
	_test_books_keep_save_keys(runner)


static func _session(runner: TestRunner, catalog: Catalog, callsign: String) -> GameSession:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, callsign, "tester"), "charter resolution: session starts")
	session.player.reputation = 2
	return session


static func _charter(reward: int, deadline_gst: float, accepted_gst: float = -1.0) -> Dictionary:
	var out := {
		"reward": reward,
		"deadline_gst": deadline_gst,
	}
	if accepted_gst >= 0.0:
		out["accepted_gst"] = accepted_gst
	return out


static func _test_on_time_pay(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "RES-PAY")
	if session == null:
		return
	var before := session.credits
	var charter := _charter(100, session.gst_seconds + 100.0)
	CharterResolution.settle_on_dock(
		session,
		charter,
		25,
		"late",
		"Charter complete to Bela. +d100.",
		"unpaid"
	)
	runner.check_eq(session.credits, before + 100, "charter resolution: on-time dock pays the reward")
	runner.check_eq(session.player.reputation, 3, "charter resolution: on-time dock raises reputation")
	runner.check_eq(
		session.career.missions_completed_on_time,
		1,
		"charter resolution: on-time dock counts a completion"
	)
	runner.check_eq(session.career.mission_reward_total, 100, "charter resolution: on-time dock records the reward")
	runner.check_eq(
		session.last_log,
		"Charter complete to Bela. +d100. Reputation +1.",
		"charter resolution: on-time log names the reward and the reputation gain"
	)


static func _test_early_finish_first_half(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "RES-EARLY")
	if session == null:
		return
	var accepted := session.gst_seconds
	var deadline := accepted + 1000.0
	session.gst_seconds = accepted + 100.0
	var before := session.credits
	CharterResolution.settle_on_dock(
		session,
		_charter(100, deadline, accepted),
		25,
		"late",
		"Charter complete.",
		"unpaid"
	)
	runner.check_eq(session.credits, before + 125, "charter resolution: first-half dock pays reward plus 25%")
	runner.check_eq(session.career.mission_reward_total, 125, "charter resolution: early finish records total pay")
	runner.check(
		session.last_log.contains("Early bonus d25"),
		"charter resolution: early finish names the bonus"
	)


static func _test_early_finish_requires_accepted_gst(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "RES-NOACC")
	if session == null:
		return
	var deadline := session.gst_seconds + 1000.0
	session.gst_seconds = session.gst_seconds + 100.0
	var charter := _charter(100, deadline)
	runner.check_eq(
		CharterResolution.early_finish_bonus_amount(100, session, charter),
		0,
		"charter resolution: early bonus needs accepted_gst on charter"
	)


static func _test_passenger_early_finish_on_dock(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := Simulation.new()
	var missions := simulation.get_subsystem("missions") as MissionSubsystem
	var session := _session(runner, catalog, "RES-PAXEARLY")
	if session == null:
		return
	session.events.subscribe_all(func(evt: Dictionary) -> void:
		simulation.dispatch_event(session, catalog, evt)
	)
	var ship := _best_docked_ship(session, catalog, "proxima_habitat")
	if ship == null:
		runner.check(false, "charter resolution: passenger early bonus needs ship")
		return
	var dest_habitat := catalog.get_habitat("bela_orbital_habitat")
	var cfg := PassengerCharters.config(catalog)
	var friction := 45
	var reward := PassengerCharters.compute_reward(cfg, 2, 1.0, friction)
	var offer := {
		"id": "early_bonus_pax",
		"board": PassengerCharters.BOARD_TERMINAL,
		"origin_habitat_id": "proxima_habitat",
		"destination_habitat_id": "bela_orbital_habitat",
		"destination_name": str(dest_habitat.get("name", "Bela")),
		"friction": friction,
		"hops": 1,
		"via_label": "",
		"deadline_hours": 48,
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
	missions.passengers.offers["proxima_habitat"] = {
		PassengerCharters.BOARD_TERMINAL: [offer],
	}
	missions.mark_habitat_boards_materialised("proxima_habitat")
	missions.generated_day = CommodityEconomy.gst_day(session.gst_seconds)
	var accepted_ok := missions.accept_offer(session, catalog, offer.id, ship.id)
	if not accepted_ok:
		runner.check(false, "charter resolution: accept passenger for early bonus (%s)" % session.last_log)
		return
	var accepted: Array = missions.list_accepted()
	runner.check(accepted.size() == 1, "charter resolution: one accepted passenger charter")
	if accepted.is_empty():
		return
	var charter: Dictionary = accepted[0]
	runner.check(charter.has("accepted_gst"), "charter resolution: passenger charter stores accepted_gst")
	runner.check(charter.has("deadline_gst"), "charter resolution: passenger charter stores deadline_gst")
	var bonus := int(round(float(reward) * CharterResolution.EARLY_FINISH_BONUS_FRACTION))
	var credits_before := session.credits
	runner.check(session.undock(catalog, ship.id, missions), "charter resolution: undock for early bonus")
	runner.check(session.enter_sector(catalog, "bela", false), "charter resolution: travel for early bonus")
	runner.check(session.dock(catalog, "bela_orbital_habitat"), "charter resolution: dock for early bonus")
	runner.check_eq(
		session.credits,
		credits_before + reward + bonus,
		"charter resolution: passenger early dock pays reward plus bonus"
	)
	runner.check(
		session.last_log.contains("Early bonus d%d" % bonus),
		"charter resolution: passenger early dock log names bonus"
	)


static func _test_early_finish_second_half(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "RES-LATEWIN")
	if session == null:
		return
	var accepted := session.gst_seconds
	var deadline := accepted + 1000.0
	session.gst_seconds = accepted + 800.0
	var before := session.credits
	CharterResolution.settle_on_dock(
		session,
		_charter(100, deadline, accepted),
		25,
		"late",
		"Charter complete.",
		"unpaid"
	)
	runner.check_eq(session.credits, before + 100, "charter resolution: second-half dock pays posted reward only")
	runner.check(
		not session.last_log.contains("Early bonus"),
		"charter resolution: second-half dock omits early bonus"
	)


static func _test_late_fee(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "RES-LATE")
	if session == null:
		return
	var before := session.credits
	var charter := _charter(100, session.gst_seconds - 1.0)
	CharterResolution.settle_on_dock(
		session,
		charter,
		40,
		"Charter late to Bela. Fee d40.",
		"paid",
		"unpaid"
	)
	runner.check_eq(session.credits, before - 40, "charter resolution: a late dock charges the fee")
	runner.check_eq(session.player.reputation, 1, "charter resolution: a late dock lowers reputation")
	runner.check_eq(session.career.missions_late, 1, "charter resolution: a late dock counts as late")
	runner.check_eq(session.career.mission_penalty_total, 40, "charter resolution: a late dock records the fee")
	runner.check_eq(session.career.missions_completed_on_time, 0, "charter resolution: a late dock is not on time")
	runner.check(
		not CharterResolution.is_late(session, {"reward": 10}),
		"charter resolution: a charter without a deadline is not late"
	)


static func _test_zero_reward_completion(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "RES-ZERO")
	if session == null:
		return
	var before := session.credits
	CharterResolution.settle_on_dock(
		session,
		_charter(0, session.gst_seconds + 100.0),
		10,
		"late",
		"paid",
		"Scan charter complete."
	)
	runner.check_eq(session.credits, before, "charter resolution: a zero reward does not move credits")
	runner.check_eq(
		session.career.missions_completed_on_time,
		1,
		"charter resolution: a zero reward still counts as on time"
	)
	runner.check_eq(session.career.mission_reward_total, 0, "charter resolution: a zero reward is not recorded as pay")
	runner.check_eq(
		session.last_log,
		"Scan charter complete. Reputation +1.",
		"charter resolution: a zero reward log omits a fee"
	)


static func _test_missed_deadline(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "RES-MISS")
	if session == null:
		return
	var before := session.credits
	CharterResolution.fail_missed_deadline(session, 30, "Passengers left charter after deadline. Fee d30.")
	runner.check_eq(session.credits, before - 30, "charter resolution: a missed deadline charges the fee")
	runner.check_eq(session.player.reputation, 1, "charter resolution: a missed deadline lowers reputation")
	runner.check_eq(
		session.career.missions_missed_deadline,
		1,
		"charter resolution: a missed deadline is counted"
	)
	runner.check_eq(
		session.career.mission_penalty_total,
		30,
		"charter resolution: a missed deadline records the fee"
	)
	runner.check_eq(
		session.last_log,
		"Passengers left charter after deadline. Fee d30. Reputation -1.",
		"charter resolution: a missed deadline log names the fee"
	)


static func _test_sandbox_skips_career(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "RES-BOX")
	if session == null:
		return
	session.player.sandbox = true
	var before := session.credits
	CharterResolution.settle_on_dock(
		session,
		_charter(80, session.gst_seconds + 50.0),
		10,
		"late",
		"paid",
		"unpaid"
	)
	runner.check_eq(session.credits, before + 80, "charter resolution: a sandbox dock still pays")
	runner.check_eq(
		session.career.missions_completed_on_time,
		0,
		"charter resolution: a sandbox dock does not count a career completion"
	)


static func _test_scan_satisfaction(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "RES-SCAN")
	if session == null:
		return
	var charter := {
		"scan_contact_id": "planet",
		"target_kind": "planet",
		"destination_sector_id": "bela",
		"accepted_gst": session.gst_seconds,
	}
	runner.check(
		not ScanCharters.charter_satisfied(session, charter),
		"charter resolution: an unscanned planet does not satisfy the contract"
	)
	session.player.record_target_scan("planet", "planet", "bela", session.gst_seconds)
	runner.check(
		ScanCharters.charter_satisfied(session, charter),
		"charter resolution: a post-accept planet scan satisfies the contract"
	)
	runner.check(
		not ScanCharters.charter_satisfied(null, charter),
		"charter resolution: a missing session does not satisfy a scan"
	)


static func _test_books_keep_save_keys(runner: TestRunner) -> void:
	var missions := MissionSubsystem.new()
	missions.passengers.offers["proxima_habitat"] = {"terminal": [{"id": "p1"}]}
	missions.passengers.accepted.append({"charter_id": "charter_1", "reward": 10})
	missions.passengers.next_id = 2
	missions.freight.offers["proxima_habitat"] = {
		DeskCharterBoards.FREIGHT_BOARD_TERMINAL: [{"id": "f1"}],
	}
	missions.freight.next_id = 3
	missions.scans.next_id = 4
	missions.bounties.next_id = 5
	var data := missions.to_dict()
	runner.check_eq(int(data["next_charter_id"]), 2, "charter book: passenger id counter keeps its save key")
	runner.check_eq(int(data["next_freight_charter_id"]), 3, "charter book: freight id counter keeps its save key")
	runner.check_eq(int(data["next_scan_charter_id"]), 4, "charter book: scan id counter keeps its save key")
	runner.check_eq(int(data["next_bounty_charter_id"]), 5, "charter book: bounty id counter keeps its save key")
	runner.check(data.has("offers_by_habitat"), "charter book: passenger offers keep their save key")
	runner.check(data.has("freight_offers_by_habitat"), "charter book: freight offers keep their save key")
	var freight_rows: Variant = data["freight_offers_by_habitat"]["proxima_habitat"]
	runner.check(typeof(freight_rows) == TYPE_DICTIONARY, "charter book: freight offers keyed by desk")
	var loaded := MissionSubsystem.new()
	loaded.from_dict(data)
	runner.check_eq(loaded.passengers.next_id, 2, "charter book: passenger id counter round-trips")
	runner.check_eq(
		str(loaded.passengers.find_accepted("charter_1").get("charter_id", "")),
		"charter_1",
		"charter book: an accepted passenger round-trips"
	)
	runner.check_eq(str(loaded.passengers.find_offer("p1").get("id", "")), "p1", "charter book: a passenger offer round-trips")
	loaded.passengers.remove_offer("p1")
	runner.check(loaded.passengers.find_offer("p1").is_empty(), "charter book: removing a passenger offer drops it")
	runner.check_eq(str(loaded.freight.find_offer("f1").get("id", "")), "f1", "charter book: a freight offer round-trips")
	runner.check_eq(loaded.freight.allocate_id(), "freight_3", "charter book: freight ids keep the freight_ prefix")
	runner.check_eq(loaded.passengers.allocate_id(), "charter_2", "charter book: passenger ids keep the charter_ prefix")
	runner.check_eq(loaded.scans.allocate_id(), "scan_4", "charter book: scan ids keep the scan_ prefix")
	runner.check_eq(loaded.bounties.allocate_id(), "bounty_5", "charter book: bounty ids keep the bounty_ prefix")


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
