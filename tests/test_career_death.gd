class_name TestCareerDeath
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_zero_hull_persists_through_hit(runner, catalog)
	_test_real_career_ends_once(runner, catalog)
	_test_sandbox_does_not_end_career(runner, catalog)
	_test_delete_slots_for_career(runner, catalog)
	_test_ended_career_refused_on_load(runner, catalog)


static func _writable_test_save_dir() -> String:
	var project_root := ProjectSettings.globalize_path("res://")
	var dir := project_root.path_join(".test_saves_career_death")
	if not dir.ends_with("/"):
		dir += "/"
	return dir


static func _session(catalog: Catalog, callsign: String) -> GameSession:
	var session := GameSession.new()
	if not session.start_new_game(catalog, callsign, "trader"):
		return null
	return session


static func _assembled(session: GameSession, catalog: Catalog) -> AssembledShip:
	var owned := session.get_current_owned_ship()
	if owned == null:
		return AssembledShip.new()
	return ShipAssembler.assemble_owned(catalog, owned)


static func _test_zero_hull_persists_through_hit(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(catalog, "DEATH-HULL")
	if session == null:
		runner.check(false, "career death: session starts for hull persistence")
		return
	var assembled := _assembled(session, catalog)
	session.combat.hull = session.combat.max_hull
	session.apply_combat_hit(catalog, assembled, "ballistic", {"kinetic": 99999.0})
	runner.check(is_equal_approx(session.hull, 0.0), "career death: hull stays at zero after killing hit")
	var rebuilt := session.build_combat_state(assembled)
	runner.check(is_equal_approx(rebuilt.hull_current, 0.0), "career death: rebuilt combat state keeps zero hull")
	runner.check(session.career.ended, "career death: killing hit ends the career")


static func _test_real_career_ends_once(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(catalog, "DEATH-END")
	if session == null:
		runner.check(false, "career death: session starts for career end")
		return
	var assembled := _assembled(session, catalog)
	session.apply_combat_hit(catalog, assembled, "ballistic", {"kinetic": 99999.0})
	runner.check(session.career.ended, "career death: career marked ended")
	runner.check_eq(session.last_log, "Ship destroyed.", "career death: log names destruction")
	session.apply_combat_hit(catalog, assembled, "ballistic", {"kinetic": 1.0})
	runner.check(session.career.ended, "career death: career stays ended after further hits")


static func _test_sandbox_does_not_end_career(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(catalog, "DEATH-SBOX")
	if session == null:
		runner.check(false, "career death: sandbox session starts")
		return
	session.sandbox = true
	var assembled := _assembled(session, catalog)
	session.apply_combat_hit(catalog, assembled, "ballistic", {"kinetic": 99999.0})
	runner.check(not session.career.ended, "career death: sandbox does not end career")
	runner.check_eq(session.last_log, "Hull breached. Systems offline.", "career death: sandbox keeps breach log")


static func _test_delete_slots_for_career(runner: TestRunner, catalog: Catalog) -> void:
	var original_dir := SaveStore.save_dir
	SaveStore.save_dir = _writable_test_save_dir()
	SaveStore.ensure_save_dir()

	var session_a := _session(catalog, "DEATH-A")
	var session_b := _session(catalog, "DEATH-B")
	if session_a == null or session_b == null:
		SaveStore.save_dir = original_dir
		runner.check(false, "career death: sessions start for slot deletion")
		return

	CareerStats._career_id_factory = Callable(TestCareerDeath, "_career_a_id")
	session_a.career.reset_for_new_career()
	CareerStats._career_id_factory = Callable(TestCareerDeath, "_career_b_id")
	session_b.career.reset_for_new_career()
	CareerStats.reset_factory()

	var payload_a := SaveStore.build_save_data(
		session_a.player_to_dict(),
		session_a.to_dict(),
		session_a.ships_to_array(),
		{},
		{}
	)
	var payload_b := SaveStore.build_save_data(
		session_b.player_to_dict(),
		session_b.to_dict(),
		session_b.ships_to_array(),
		{},
		{}
	)
	runner.check(SaveStore.write_slot(1, payload_a), "career death: write slot 1")
	runner.check(SaveStore.write_slot(2, payload_a), "career death: write slot 2 with same career")
	runner.check(SaveStore.write_slot(3, payload_b), "career death: write slot 3 with other career")

	SaveStore.delete_slots_for_career("career_death_a")

	runner.check(not SaveStore.slot_exists(1), "career death: slot 1 deleted for ended career")
	runner.check(not SaveStore.slot_exists(2), "career death: slot 2 deleted for ended career")
	runner.check(SaveStore.slot_exists(3), "career death: other career slot remains")

	SaveStore.save_dir = original_dir


static func _test_ended_career_refused_on_load(runner: TestRunner, catalog: Catalog) -> void:
	var temp_dir := _writable_test_save_dir()
	var original_lb := LeaderboardStore.store_dir
	LeaderboardStore.store_dir = temp_dir
	if not DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.make_dir_recursive_absolute(temp_dir)

	var session := _session(catalog, "DEATH-LD")
	if session == null:
		LeaderboardStore.store_dir = original_lb
		runner.check(false, "career death: session starts for load refusal")
		return
	session.career.career_id = "career_death_refused"
	LeaderboardStore.upsert_from_session(session, "2026-01-01T00:00:00", catalog, true)
	runner.check(
		LeaderboardStore.is_career_ended("career_death_refused"),
		"career death: leaderboard marks ended career"
	)
	runner.check(
		not LeaderboardStore.is_career_ended("career_death_other"),
		"career death: unrelated career id not ended"
	)

	LeaderboardStore.store_dir = original_lb
	if DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.remove_absolute(temp_dir.path_join(LeaderboardStore.FILE_NAME))


static func _career_a_id() -> String:
	return "career_death_a"


static func _career_b_id() -> String:
	return "career_death_b"
