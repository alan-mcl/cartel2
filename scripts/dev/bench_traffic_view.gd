extends SceneTree

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
const TrafficViewScript := preload("res://scripts/presentation/traffic_view.gd")
const LaserBeamScript := preload("res://scripts/presentation/laser_beam.gd")
const MassDriverRoundScript := preload("res://scripts/presentation/mass_driver_round.gd")
const RocketProjectileScript := preload("res://scripts/presentation/rocket_projectile.gd")

const ACTOR_COUNT := 100
const NEAR_COUNT := 20
const ITERATIONS := 120
const CROSSINGS_PER_FRAME := 4


func _initialize() -> void:
	var catalog := Catalog.load_default()
	var traffic_config := catalog.get_traffic_config()
	var actors := _make_actors(catalog, traffic_config)

	var world_root := Node2D.new()
	world_root.name = "World"
	root.add_child(world_root)

	var view := TrafficViewScript.new()
	view.setup(world_root)

	# Warm: build all near nodes once, then far, so crossing bench measures flip churn.
	for i in range(NEAR_COUNT):
		actors[i].near_lod = true
		actors[i].has_sim_slot = true
	for i in range(NEAR_COUNT, ACTOR_COUNT):
		actors[i].near_lod = false
		actors[i].has_sim_slot = false
	view.sync(actors, catalog)

	print(
		"=== TrafficView benchmark (%d actors, %d near, %d iters) ==="
		% [ACTOR_COUNT, NEAR_COUNT, ITERATIONS]
	)

	_bench_sync_stable(view, actors, catalog)
	_bench_sync_crossings(view, actors, catalog)
	_bench_near_spawn_load_vs_cached(world_root, catalog, actors[0])
	_bench_projectiles(world_root)

	quit()


func _make_actors(catalog: Catalog, traffic_config: Dictionary) -> Array:
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
		actor.id = "bench_%d" % i
		actors.append(actor)
	return actors


func _bench_sync_stable(view: TrafficView, actors: Array, catalog: Catalog) -> void:
	for i in range(ACTOR_COUNT):
		actors[i].near_lod = i < NEAR_COUNT
		actors[i].has_sim_slot = i < NEAR_COUNT
	view.sync(actors, catalog)

	var start_usec := Time.get_ticks_usec()
	for _i in range(ITERATIONS):
		view.sync(actors, catalog)
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	var per_frame_usec := float(elapsed_usec) / float(ITERATIONS)
	print(
		"sync stable LOD: %.1f us/frame (total %.1f ms)"
		% [per_frame_usec, elapsed_usec / 1000.0]
	)


func _bench_sync_crossings(view: TrafficView, actors: Array, catalog: Catalog) -> void:
	for i in range(ACTOR_COUNT):
		actors[i].near_lod = i < NEAR_COUNT
		actors[i].has_sim_slot = i < NEAR_COUNT
	view.sync(actors, catalog)

	var flip_index := 0
	var start_usec := Time.get_ticks_usec()
	for _i in range(ITERATIONS):
		for _c in range(CROSSINGS_PER_FRAME):
			var actor = actors[flip_index % ACTOR_COUNT]
			flip_index += 1
			actor.near_lod = not bool(actor.near_lod)
			actor.has_sim_slot = actor.near_lod
		view.sync(actors, catalog)
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	var per_frame_usec := float(elapsed_usec) / float(ITERATIONS)
	var crossings := ITERATIONS * CROSSINGS_PER_FRAME
	print(
		"sync forced crossings (%d flips/frame): %.1f us/frame (total %.1f ms, %d crossings)"
		% [CROSSINGS_PER_FRAME, per_frame_usec, elapsed_usec / 1000.0, crossings]
	)


func _bench_near_spawn_load_vs_cached(world_root: Node2D, catalog: Catalog, actor) -> void:
	const NPC_PATH := "res://scenes/npc_ship.tscn"
	const SPAWNS := 40

	var start_load := Time.get_ticks_usec()
	for _i in range(SPAWNS):
		var packed: PackedScene = load(NPC_PATH) as PackedScene
		if packed == null:
			continue
		var ship: Node2D = packed.instantiate()
		world_root.add_child(ship)
		if ship.has_method("bind_actor"):
			ship.call("bind_actor", actor, catalog)
		ship.queue_free()
	var load_usec := Time.get_ticks_usec() - start_load

	var cached: PackedScene = load(NPC_PATH) as PackedScene
	var start_cached := Time.get_ticks_usec()
	for _i in range(SPAWNS):
		if cached == null:
			break
		var ship: Node2D = cached.instantiate()
		world_root.add_child(ship)
		if ship.has_method("bind_actor"):
			ship.call("bind_actor", actor, catalog)
		ship.queue_free()
	var cached_usec := Time.get_ticks_usec() - start_cached

	print(
		"near spawn load() each time: %.1f us/spawn (%d spawns)"
		% [float(load_usec) / float(SPAWNS), SPAWNS]
	)
	print(
		"near spawn cached PackedScene: %.1f us/spawn (%d spawns)"
		% [float(cached_usec) / float(SPAWNS), SPAWNS]
	)


func _bench_projectiles(world_root: Node2D) -> void:
	const SHOTS := 200
	var origin := Vector2.ZERO
	var direction := Vector2.RIGHT
	var packets := {"kinetic": 1.0}
	var mask := 2 | 16 | 1

	var start_laser := Time.get_ticks_usec()
	for _i in range(SHOTS):
		LaserBeamScript.spawn(world_root, origin, direction, 500.0, "beam", packets, mask, [], null)
		for child in world_root.get_children():
			if child is Line2D:
				child.queue_free()
	var laser_usec := Time.get_ticks_usec() - start_laser

	var start_round := Time.get_ticks_usec()
	for _i in range(SHOTS):
		MassDriverRoundScript.spawn(
			world_root,
			origin,
			direction,
			1000.0,
			1200.0,
			"ballistic",
			packets,
			mask,
			[],
			Vector2.ZERO,
			null
		)
		for child in world_root.get_children():
			if child.has_method("configure"):
				child.queue_free()
	var round_usec := Time.get_ticks_usec() - start_round

	var start_rocket := Time.get_ticks_usec()
	for _i in range(SHOTS):
		RocketProjectileScript.spawn(
			world_root,
			origin,
			direction,
			650.0,
			1500.0,
			"guided",
			packets,
			mask,
			[],
			Vector2.ZERO,
			null
		)
		for child in world_root.get_children():
			if child.has_method("configure"):
				child.queue_free()
	var rocket_usec := Time.get_ticks_usec() - start_rocket

	print("projectile spawn+free laser: %.1f us/shot" % (float(laser_usec) / float(SHOTS)))
	print("projectile spawn+free mass driver: %.1f us/shot" % (float(round_usec) / float(SHOTS)))
	print("projectile spawn+free rocket: %.1f us/shot" % (float(rocket_usec) / float(SHOTS)))
