class_name TestTraffic
extends RefCounted

const TrafficDirectorScript := preload("res://scripts/gameplay/traffic_director.gd")
const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
const TrafficSpawnScript := preload("res://scripts/gameplay/traffic_spawn.gd")


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_setup_fleet_size(runner, catalog)
	_test_sim_slot_cap(runner, catalog)
	_test_near_lod_tracks_sim_slot(runner, catalog)
	_test_detection_stagger(runner, catalog)
	_test_detection_stagger_phase(runner)
	_test_clear_drops_fleet(runner, catalog)
	_test_ambient_ship_spawn_anonymous(runner, catalog)


static func _test_setup_fleet_size(runner: TestRunner, catalog: Catalog) -> void:
	var director := TrafficDirectorScript.new()
	var world_loader := WorldLoader.new()
	var traffic_config := catalog.get_traffic_config()
	var sector := catalog.get_sector("proxima")

	director.setup(
		catalog,
		"proxima",
		world_loader.get_traffic_envelope_radius(),
		Vector2.ZERO,
		world_loader
	)

	var near_min := int(traffic_config.get("near_count_min", 9))
	var near_max := int(traffic_config.get("near_count_max", 16))
	var far_min := int(traffic_config.get("far_count_min", 3))
	var far_max := int(traffic_config.get("far_count_max", 84))

	runner.check(director.actors.size() >= near_min + far_min, "proxima fleet meets near+far floor")
	runner.check(
		director.actors.size() <= near_max + far_max,
		"proxima fleet respects near+far ceiling"
	)
	runner.check(
		float(sector.get("population_billions", 0.0)) >= float(traffic_config.get("population_max_billions", 60.0)) * 0.5,
		"proxima population high enough for meaningful fleet test"
	)


static func _test_sim_slot_cap(runner: TestRunner, catalog: Catalog) -> void:
	var director := TrafficDirectorScript.new()
	var world_loader := WorldLoader.new()
	var traffic_config := catalog.get_traffic_config()
	var sim_max := int(traffic_config.get("sim_slot_max", 20))

	director.setup(
		catalog,
		"proxima",
		world_loader.get_traffic_envelope_radius(),
		Vector2.ZERO,
		world_loader
	)

	var slotted := 0
	for actor_variant in director.actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		if actor.has_sim_slot:
			slotted += 1

	runner.check(slotted <= sim_max, "at most sim_slot_max actors hold sim slots")
	runner.check(slotted > 0, "proxima fleet assigns at least one sim slot near origin")


static func _test_near_lod_tracks_sim_slot(runner: TestRunner, catalog: Catalog) -> void:
	var director := TrafficDirectorScript.new()
	var world_loader := WorldLoader.new()

	director.setup(
		catalog,
		"proxima",
		world_loader.get_traffic_envelope_radius(),
		Vector2(100.0, 50.0),
		world_loader
	)

	director.tick(
		1.0 / 60.0,
		Vector2(100.0, 50.0),
		world_loader,
		42,
		Vector2.ZERO,
		0.0,
		false
	)

	for actor_variant in director.actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		runner.check(
			actor.near_lod == actor.has_sim_slot,
			"near_lod tracks has_sim_slot for %s" % actor.id
		)


static func _test_detection_stagger(runner: TestRunner, catalog: Catalog) -> void:
	var traffic_config := catalog.get_traffic_config()
	var visual_radius := float(traffic_config.get("visual_contact_radius", 250.0))
	var observer_pos := Vector2.ZERO
	var frame := 17
	var refresh_count := 0
	var eligible := 0

	for i in range(32):
		var actor = TrafficActorScript.create(
			catalog,
			traffic_config,
			"transit",
			TrafficActorScript.pick_template_for_role(traffic_config, "transit"),
			Vector2(5000.0 + float(i) * 120.0, float(i) * 80.0),
			0.0,
			"proxima"
		)
		actor.has_sim_slot = false
		actor.ai_state = TrafficActorScript.AiState.TRAFFIC
		eligible += 1
		if actor.should_refresh_detection(frame, observer_pos, visual_radius):
			refresh_count += 1

	runner.check(eligible >= 32, "stagger probe builds eligible actors")
	runner.check(refresh_count > 0, "stagger probe refreshes some actors")
	runner.check(
		refresh_count < eligible,
		"detection stagger skips some far actors on a single frame"
	)


static func _test_detection_stagger_phase(runner: TestRunner) -> void:
	var actor = TrafficActorScript.new()
	actor.id = "stagger-phase-probe"
	actor.position = Vector2(20000.0, 0.0)
	actor.has_sim_slot = false
	actor.ai_state = TrafficActorScript.AiState.TRAFFIC
	var observer := Vector2.ZERO
	var radius := 250.0
	var window := TrafficDetection.DETECTION_STAGGER_FRAMES
	var hits := 0
	var hit_frame := -1
	for frame in range(window):
		if TrafficDetection.should_refresh_detection(actor, frame, observer, radius):
			hits += 1
			hit_frame = frame
	runner.check_eq(hits, 1, "detection stagger: far traffic refreshes once per window")
	if hits != 1:
		return
	runner.check(
		TrafficDetection.should_refresh_detection(actor, hit_frame + window, observer, radius),
		"detection stagger: the same phase repeats on the next window"
	)
	runner.check(
		not TrafficDetection.should_refresh_detection(actor, hit_frame + 1, observer, radius),
		"detection stagger: the next frame in the window is skipped"
	)

	actor.has_sim_slot = true
	runner.check_eq(
		_refresh_count(actor, observer, radius, window),
		window,
		"detection stagger: a sim slot refreshes every frame"
	)
	actor.has_sim_slot = false
	actor.ai_state = TrafficActorScript.AiState.ENGAGE
	runner.check_eq(
		_refresh_count(actor, observer, radius, window),
		window,
		"detection stagger: an engaging actor refreshes every frame"
	)
	actor.ai_state = TrafficActorScript.AiState.FLEE
	runner.check_eq(
		_refresh_count(actor, observer, radius, window),
		window,
		"detection stagger: a fleeing actor refreshes every frame"
	)
	actor.ai_state = TrafficActorScript.AiState.TRAFFIC
	actor.position = Vector2(10.0, 0.0)
	runner.check_eq(
		_refresh_count(actor, observer, radius, window),
		window,
		"detection stagger: an actor inside visual range refreshes every frame"
	)


static func _refresh_count(actor, observer: Vector2, radius: float, window: int) -> int:
	var hits := 0
	for frame in range(window):
		if TrafficDetection.should_refresh_detection(actor, frame, observer, radius):
			hits += 1
	return hits


static func _test_clear_drops_fleet(runner: TestRunner, catalog: Catalog) -> void:
	var director := TrafficDirectorScript.new()
	var world_loader := WorldLoader.new()

	director.setup(
		catalog,
		"proxima",
		world_loader.get_traffic_envelope_radius(),
		Vector2.ZERO,
		world_loader
	)
	runner.check(director.actors.size() > 0, "clear test starts with fleet")

	director.clear()
	runner.check_eq(director.actors.size(), 0, "director clear drops actors")


static func _test_ambient_ship_spawn_anonymous(runner: TestRunner, catalog: Catalog) -> void:
	var traffic_config := catalog.get_traffic_config()
	var ship_record := {
		"id": "ambient_ship_test",
		"template_id": str(catalog.list_ships()[0].get("id", "")),
		"position": {"x": 1200.0, "y": 800.0},
		"heading_rad": 0.2,
		"anonymous": true,
	}
	var actor = TrafficSpawnScript.create_from_ambient_ship(
		catalog,
		traffic_config,
		ship_record,
		"proxima"
	)
	runner.check(actor != null, "traffic: ambient ship spawns")
	runner.check_eq(str(actor.callsign), "", "traffic: ambient ship has no callsign")
	runner.check_eq(str(actor.affiliation), "", "traffic: ambient ship has no affiliation")
	runner.check(not actor.owned_ship.transponder_enabled, "traffic: ambient ship transponder off")
