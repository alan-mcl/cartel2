extends SceneTree

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")

const ACTOR_COUNT := 100
const SIM_SLOT_COUNT := 20
const ITERATIONS := 600
const DELTA := 1.0 / 60.0


func _init() -> void:
	var catalog := Catalog.load_default()
	var traffic_config := catalog.get_traffic_config()
	var visual_radius := float(traffic_config.get("visual_contact_radius", 250.0))
	var player_pos := Vector2.ZERO

	var actors: Array = []
	for i in range(ACTOR_COUNT):
		var angle := float(i) / float(ACTOR_COUNT) * TAU
		var radius := 500.0 + float(i % 50) * 120.0
		var pos := Vector2.from_angle(angle) * radius
		var actor = TrafficActorScript.create(
			catalog,
			traffic_config,
			"transit",
			"pegasus_p101",
			pos,
			angle,
			"proxima"
		)
		actor.owned_ship.transponder_enabled = i % 3 != 0
		actor.has_sim_slot = i < SIM_SLOT_COUNT
		actors.append(actor)

	var player_assembled := ShipAssembler.assemble(catalog, "pegasus_p101")
	var player_operating := ShipOperatingState.new()
	player_operating.active_systems = {
		"engine": false,
		"sensors": true,
		"weapons": false,
		"transponder": true,
	}
	var player_effectiveness := SensorSystem.sensor_effectiveness(player_assembled, player_operating)
	var player_profile := SensorSystem.tick_observer_profile(player_assembled, player_effectiveness)
	var player_signature := SensorSystem.live_signature(player_assembled, player_operating)

	var inputs := {
		"thrust": true,
		"reverse": false,
		"rotate_left": false,
		"rotate_right": false,
		"boost": false,
		"in_flight": true,
		"fire": false,
	}

	print("=== Traffic benchmark (%d actors, %d sim slots, %d iters) ===" % [
		ACTOR_COUNT, SIM_SLOT_COUNT, ITERATIONS
	])

	_bench("live_signature (sim actors)", ITERATIONS, func() -> void:
		for i in range(SIM_SLOT_COUNT):
			var actor = actors[i]
			SensorSystem.live_signature(actor.assembled_ship, actor.operating_state)
	)

	_bench("detection refresh (lazy path)", ITERATIONS, func() -> void:
		for actor_variant in actors:
			var actor = actor_variant
			actor.refresh_player_detection(
				player_pos,
				player_profile,
				player_signature,
				true,
				traffic_config,
				true
			)
	)

	_bench("is_detected (broadcasting, no sig needed)", ITERATIONS, func() -> void:
		for actor_variant in actors:
			var actor = actor_variant
			var distance: float = actor.position.distance_to(player_pos)
			SensorSystem.is_detected(
				distance,
				SensorSystem.empty_signature(),
				true,
				player_profile,
				visual_radius
			)
	)

	_bench("ShipOperations.tick (sim actors)", ITERATIONS, func() -> void:
		for i in range(SIM_SLOT_COUNT):
			var actor = actors[i]
			ShipOperations.tick(
				catalog,
				actor.assembled_ship,
				actor.owned_ship,
				DELTA,
				inputs,
				1,
				actor.combat_state
			)
	)

	_bench("mass + derive_stats (sim actors)", ITERATIONS, func() -> void:
		for i in range(SIM_SLOT_COUNT):
			var actor = actors[i]
			var loaded_mass := ShipAssembler.calculate_loaded_mass(
				catalog, actor.owned_ship, actor.assembled_ship
			)
			actor.assembled_ship.stats = ShipAssembler.derive_stats(actor.assembled_ship, loaded_mass)
	)

	_bench("modules_in_category transponder", ITERATIONS, func() -> void:
		for actor_variant in actors:
			var actor = actor_variant
			actor.assembled_ship.modules_in_category("transponder")
	)

	_bench("actor.tick kinematic", ITERATIONS, func() -> void:
		for i in range(SIM_SLOT_COUNT, ACTOR_COUNT):
			var actor = actors[i]
			actor.has_sim_slot = false
			actor.tick(
				catalog,
				traffic_config,
				DELTA,
				player_pos,
				[],
				6750.0,
				null,
				Vector2.ZERO,
				0.0,
				false
			)
	)

	_bench("actor.tick full sim", ITERATIONS, func() -> void:
		for i in range(SIM_SLOT_COUNT):
			var actor = actors[i]
			actor.has_sim_slot = true
			actor.tick(
				catalog,
				traffic_config,
				DELTA,
				player_pos,
				[],
				6750.0,
				null,
				Vector2.ZERO,
				0.0,
				false
			)
	)

	print("=== done ===")
	quit(0)


static func _bench(label: String, iterations: int, fn: Callable) -> void:
	var start_usec := Time.get_ticks_usec()
	for _i in range(iterations):
		fn.call()
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	var per_frame_usec := float(elapsed_usec) / float(iterations)
	print("%s: %.1f us/frame (total %.1f ms)" % [label, per_frame_usec, elapsed_usec / 1000.0])
