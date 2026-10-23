class_name TestCharterResolution
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_on_time_pay(runner, catalog)
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


static func _charter(reward: int, deadline_gst: float) -> Dictionary:
	return {
		"reward": reward,
		"deadline_gst": deadline_gst,
	}


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
	missions.freight.offers["proxima_habitat"] = [{"id": "f1"}]
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
	runner.check(typeof(freight_rows) == TYPE_ARRAY, "charter book: freight offers stay a flat list")
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
