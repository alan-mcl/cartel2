class_name TestSimulation
extends RefCounted

## [Simulation] registry and boundary dispatch.


class ProbeSubsystem extends SimSubsystem:
	var tick_count: int = 0
	var hour_count: int = 0
	var day_count: int = 0
	var last_hour: int = -1
	var last_day: int = -1
	var event_count: int = 0

	func _init() -> void:
		id = "probe"

	func on_tick(_session: GameSession, _catalog: Catalog, _delta: float) -> void:
		tick_count += 1

	func on_hour(_session: GameSession, _catalog: Catalog, hour: int) -> void:
		hour_count += 1
		last_hour = hour

	func on_day(_session: GameSession, _catalog: Catalog, day: int) -> void:
		day_count += 1
		last_day = day

	func on_event(_evt: Dictionary) -> void:
		event_count += 1

	func to_dict() -> Dictionary:
		return {"tick_count": tick_count}

	func from_dict(data: Dictionary) -> void:
		tick_count = int(data.get("tick_count", 0))


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_default_economy_registration(runner, catalog)
	_test_day_crossing_reposts_quotes(runner, catalog)
	_test_frozen_step(runner, catalog)
	_test_probe_hooks(runner, catalog)
	_test_duplicate_register_rejected(runner)
	_test_mapping_lump_day_hook(runner, catalog)
	_test_subsystem_save_hooks_noop(runner)


static func _new_session(runner: TestRunner, catalog: Catalog, callsign: String) -> GameSession:
	var session := GameSession.new()
	if not session.start_new_game(catalog, callsign, "trader"):
		runner.check(false, "simulation: session %s starts" % callsign)
		return null
	return session


static func _test_default_economy_registration(runner: TestRunner, _catalog: Catalog) -> void:
	var simulation := Simulation.new()
	runner.check(simulation.has_subsystem("economy"), "simulation: economy registered by default")
	runner.check(
		simulation.get_subsystem("economy") is EconomySubsystem,
		"simulation: economy subsystem type"
	)


static func _test_day_crossing_reposts_quotes(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "SIM-DAY")
	if session == null:
		return
	var simulation := Simulation.new()

	var day := CommodityEconomy.gst_day(session.gst_seconds)
	session.gst_seconds = float(day + 1) * float(GalacticCalendar.SECONDS_PER_DAY) - 0.5
	CommodityEconomy.ensure_quotes(session, catalog)
	var posted_day := session.market_quotes_day
	var before := JSON.stringify(session.market_quotes)

	simulation.step(session, catalog, 0.5, false)

	runner.check_eq(
		CommodityEconomy.gst_day(session.gst_seconds),
		posted_day + 1,
		"simulation: step crosses day boundary"
	)
	runner.check_eq(session.market_quotes_day, posted_day + 1, "simulation: day crossing reposts quotes")
	runner.check(
		JSON.stringify(session.market_quotes) != before,
		"simulation: reposted quotes differ from previous day"
	)


static func _test_frozen_step(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "SIM-FROZEN")
	if session == null:
		return
	var simulation := Simulation.new()
	var probe := ProbeSubsystem.new()
	runner.check(simulation.register(probe), "simulation: probe registers for frozen test")

	var before := session.gst_seconds
	simulation.step(session, catalog, 5.0, true)

	runner.check_eq(session.gst_seconds, before, "simulation: frozen step does not advance GST")
	runner.check_eq(probe.tick_count, 0, "simulation: frozen step does not call on_tick")


static func _test_probe_hooks(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "SIM-PROBE")
	if session == null:
		return
	var simulation := Simulation.new()
	var probe := ProbeSubsystem.new()
	runner.check(simulation.register(probe), "simulation: probe registers for hook test")

	simulation.step(session, catalog, 1.0, false)
	runner.check_eq(probe.tick_count, 1, "simulation: on_tick on first step")
	runner.check_eq(probe.hour_count, 0, "simulation: sub-hour step does not call on_hour")
	runner.check_eq(probe.day_count, 0, "simulation: sub-day step does not call on_day")

	simulation.step(session, catalog, float(GalacticCalendar.SECONDS_PER_HOUR), false)
	runner.check(probe.tick_count >= 2, "simulation: on_tick accumulates")
	runner.check_eq(probe.hour_count, 1, "simulation: hour boundary calls on_hour once")
	runner.check_eq(probe.day_count, 0, "simulation: hour-only step does not call on_day")

	var day := CommodityEconomy.gst_day(session.gst_seconds)
	session.gst_seconds = float(day + 1) * float(GalacticCalendar.SECONDS_PER_DAY) - 0.5
	CommodityEconomy.ensure_quotes(session, catalog)
	probe.tick_count = 0
	probe.hour_count = 0
	probe.day_count = 0

	simulation.step(session, catalog, 0.5, false)
	runner.check_eq(probe.tick_count, 1, "simulation: on_tick on day-crossing step")
	runner.check_eq(probe.hour_count, 1, "simulation: day crossing also crosses an hour")
	runner.check_eq(probe.day_count, 1, "simulation: day boundary calls on_day once")


static func _test_duplicate_register_rejected(runner: TestRunner) -> void:
	var simulation := Simulation.new()
	var first := ProbeSubsystem.new()
	first.id = "duplicate"
	var second := ProbeSubsystem.new()
	second.id = "duplicate"

	runner.check(simulation.register(first), "simulation: first duplicate id registers")
	runner.check(not simulation.register(second), "simulation: duplicate id rejected")


static func _test_mapping_lump_day_hook(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "SIM-LUMP")
	if session == null:
		return
	var simulation := Simulation.new()
	var probe := ProbeSubsystem.new()
	runner.check(simulation.register(probe), "simulation: probe registers for lump test")

	var day := CommodityEconomy.gst_day(session.gst_seconds)
	session.gst_seconds = float(day) * float(GalacticCalendar.SECONDS_PER_DAY) + 3600.0
	CommodityEconomy.ensure_quotes(session, catalog)
	probe.day_count = 0

	var applied := simulation.apply_mapping_lump(
		session,
		{"transit_seconds": float(GalacticCalendar.SECONDS_PER_DAY)},
		"transit_seconds",
		catalog
	)
	runner.check(
		applied >= float(GalacticCalendar.SECONDS_PER_DAY),
		"simulation: mapping lump applies at least one day"
	)
	runner.check_eq(probe.day_count, 1, "simulation: mapping lump crossing day calls on_day once")


static func _test_subsystem_save_hooks_noop(runner: TestRunner) -> void:
	var probe := ProbeSubsystem.new()
	probe.tick_count = 7
	probe.on_event({"type": "noop"})
	runner.check_eq(probe.event_count, 1, "simulation: on_event is callable")

	var data := probe.to_dict()
	probe.tick_count = 0
	probe.from_dict(data)
	runner.check_eq(probe.tick_count, 7, "simulation: probe round-trips to_dict/from_dict")

	var base := SimSubsystem.new()
	base.id = "base"
	runner.check(base.to_dict().is_empty(), "simulation: base to_dict is empty")
	base.from_dict({"ignored": true})
	runner.check(true, "simulation: base from_dict is a no-op")
