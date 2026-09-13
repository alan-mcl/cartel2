class_name TestClock
extends RefCounted

## `GameClock` coverage.
##
## The clock is the only thing advancing GST, and GST rollover is what reposts markets. Phase 1
## rehosts this onto `SimClock`, so pin the observable behaviour first: real-time advance in
## normal space, stochastic-but-forward advance in unspace, freezing, and day-boundary refresh.

const EPSILON := 0.0001


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_normal_space_advance(runner, catalog)
	_test_frozen_and_degenerate_deltas(runner, catalog)
	_test_day_boundary_reposts_markets(runner, catalog)
	_test_unspace_advance(runner, catalog)
	_test_unspace_gst_from_catalog_only(runner, catalog)
	_test_mapping_lump(runner, catalog)


static func _new_session(runner: TestRunner, catalog: Catalog, callsign: String) -> GameSession:
	var session := GameSession.new()
	if not session.start_new_game(catalog, callsign, "trader"):
		runner.check(false, "clock: session %s starts" % callsign)
		return null
	return session


static func _test_normal_space_advance(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "CLK-1")
	if session == null:
		return
	var clock := GameClock.new()
	var before := session.gst_seconds

	clock.tick(session, catalog, 1.5, false)
	runner.check(
		absf(session.gst_seconds - (before + 1.5)) < EPSILON,
		"clock: normal space advances GST one second per second"
	)

	clock.tick(session, catalog, 2.5, false)
	runner.check(
		absf(session.gst_seconds - (before + 4.0)) < EPSILON,
		"clock: normal space advance accumulates"
	)


static func _test_frozen_and_degenerate_deltas(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "CLK-2")
	if session == null:
		return
	var clock := GameClock.new()
	var before := session.gst_seconds

	clock.tick(session, catalog, 5.0, true)
	runner.check_eq(session.gst_seconds, before, "clock: frozen tick does not advance GST")

	clock.tick(session, catalog, 0.0, false)
	runner.check_eq(session.gst_seconds, before, "clock: zero delta does not advance GST")

	clock.tick(session, catalog, -3.0, false)
	runner.check_eq(session.gst_seconds, before, "clock: negative delta does not advance GST")

	clock.tick(null, catalog, 1.0, false)
	runner.check(true, "clock: null session tick is a no-op rather than a crash")


static func _test_day_boundary_reposts_markets(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "CLK-3")
	if session == null:
		return
	var clock := GameClock.new()

	# Park GST just short of a day boundary with quotes already posted for the current day.
	var seconds_per_day := float(GalacticCalendar.SECONDS_PER_DAY)
	var current_day := CommodityEconomy.gst_day(session.gst_seconds)
	session.gst_seconds = float(current_day + 1) * seconds_per_day - 0.5
	CommodityEconomy.ensure_quotes(session, catalog)
	var posted_day := session.market_quotes_day
	runner.check_eq(
		posted_day,
		CommodityEconomy.gst_day(session.gst_seconds),
		"clock: quotes posted for the pre-boundary day"
	)

	clock.tick(session, catalog, 0.25, false)
	runner.check_eq(
		session.market_quotes_day,
		posted_day,
		"clock: tick within the day leaves quotes alone"
	)

	clock.tick(session, catalog, 0.5, false)
	runner.check_eq(
		CommodityEconomy.gst_day(session.gst_seconds),
		posted_day + 1,
		"clock: tick crosses the day boundary"
	)
	runner.check_eq(
		session.market_quotes_day,
		posted_day + 1,
		"clock: crossing a day boundary reposts markets"
	)


static func _test_unspace_advance(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "CLK-4")
	if session == null:
		return

	# Drive the clock's unspace branch directly; `enter_unspace` needs an assembled ship and a
	# destination, neither of which the clock reads.
	session.in_unspace = true
	session.unspace_world_id = "n4_default"
	session.unspace_n = 4
	runner.check(
		not catalog.get_unspace("n4_default").is_empty(),
		"clock: n4_default unspace exists in catalog"
	)

	var clock := GameClock.new()
	clock.reset_unspace_pulse()
	var before := session.gst_seconds
	var delta := 0.1
	clock.tick(session, catalog, delta, false)

	# The pulse model stretches subjective time, so a tick advances GST by at least one
	# `stretch_min` chunk (0.35 s) rather than by `delta`.
	runner.check(
		session.gst_seconds > before + delta,
		"clock: unspace advances GST faster than wall clock"
	)

	# After a pulse fires, the next one is up to `pulse_max` (2.4 s) away, so tick past that to
	# guarantee another pulse rather than sampling inside the quiet window.
	var after_first := session.gst_seconds
	for _i in range(60):
		clock.tick(session, catalog, delta, false)
	runner.check(
		session.gst_seconds > after_first,
		"clock: repeated unspace ticks keep advancing GST"
	)

	session.in_unspace = true
	var frozen_before := session.gst_seconds
	clock.tick(session, catalog, delta, true)
	runner.check_eq(
		session.gst_seconds,
		frozen_before,
		"clock: frozen unspace tick does not advance GST"
	)


static func _test_unspace_gst_from_catalog_only(runner: TestRunner, catalog: Catalog) -> void:
	var config: Dictionary = catalog.get_unspace("n4_default").get("gst", {})
	runner.check(not config.is_empty(), "clock: n4_default gst block present")

	var stretch := SimClock.gst_stretch_factor(config, 0.42)
	var expected_stretch := lerpf(
		float(config.get("stretch_min", 0.35)),
		float(config.get("stretch_max", 2.8)),
		0.42
	)
	runner.check(
		absf(stretch - expected_stretch) < EPSILON,
		"clock: stretch factor uses gst block only"
	)
	runner.check_eq(
		SimClock.gst_slip_chance(config),
		clampf(float(config.get("slip_chance", 0.12)), 0.0, 0.75),
		"clock: slip chance uses gst block only"
	)
	var pulse := SimClock.gst_pulse_interval(config, 0.5)
	var expected_pulse := lerpf(
		float(config.get("pulse_min", 0.35)),
		float(config.get("pulse_max", 2.4)),
		0.5
	)
	runner.check(
		absf(pulse - expected_pulse) < EPSILON,
		"clock: pulse interval uses gst block only"
	)


static func _test_mapping_lump(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "CLK-5")
	if session == null:
		return
	var clock := GameClock.new()
	var before := session.gst_seconds

	runner.check_eq(
		clock.apply_mapping_lump(session, {}, "transit_seconds", catalog),
		0.0,
		"clock: empty mapping applies no lump"
	)
	runner.check_eq(session.gst_seconds, before, "clock: empty mapping leaves GST alone")

	runner.check_eq(
		clock.apply_mapping_lump(session, {"transit_seconds": 0.0}, "transit_seconds", catalog),
		0.0,
		"clock: zero lump applies nothing"
	)

	# No jitter configured, so the lump is applied exactly.
	var applied := clock.apply_mapping_lump(
		session, {"transit_seconds": 3600.0}, "transit_seconds", catalog
	)
	runner.check(absf(applied - 3600.0) < EPSILON, "clock: unjittered lump applies exactly")
	runner.check(
		absf(session.gst_seconds - (before + 3600.0)) < EPSILON,
		"clock: lump advances session GST"
	)

	# With jitter the lump stays inside the configured band.
	var jitter_before := session.gst_seconds
	var jittered := clock.apply_mapping_lump(
		session,
		{"transit_seconds": 1000.0, "time_jitter": 0.25},
		"transit_seconds",
		catalog
	)
	runner.check(
		jittered >= 750.0 and jittered <= 1250.0,
		"clock: jittered lump stays within its band"
	)
	runner.check(
		session.gst_seconds > jitter_before,
		"clock: jittered lump still advances GST"
	)
