class_name TestPresentation
extends RefCounted

## Node-level lifecycle coverage for pooled traffic presentation.  This is kept
## separate from gameplay traffic tests because it intentionally owns scene-tree
## nodes and verifies the presentation boundary.

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")


static func run(runner: TestRunner) -> void:
	_test_node_pool_reparents_and_clears(runner)
	_test_traffic_view_lifecycle(runner)
	_test_traffic_destroy_breakup(runner)
	_test_npc_play_destroyed_breakup(runner)
	_test_traffic_detection_fade(runner)


static func _test_node_pool_reparents_and_clears(runner: TestRunner) -> void:
	var host_a := Node2D.new()
	var host_b := Node2D.new()
	var pool := PresentationNodePool.new()
	pool.setup(preload("res://scenes/world/orbital.tscn"), 1)

	var first: Node = pool.acquire(host_a)
	runner.check(first != null, "presentation pool: creates node")
	if first == null:
		return
	runner.check_eq(first.get_parent(), host_a, "presentation pool: attaches created node")
	pool.release(first)
	runner.check(not first.visible, "presentation pool: hides released node")
	runner.check_eq(first.get_parent(), null, "presentation pool: detaches released node")

	var reused := pool.acquire(host_b)
	runner.check_eq(reused, first, "presentation pool: reuses released node")
	runner.check_eq(reused.get_parent(), host_b, "presentation pool: reparents reused node")
	pool.release(reused)
	pool.clear()
	runner.check(pool._available.is_empty(), "presentation pool: clear empties available nodes")


static func _test_traffic_view_lifecycle(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var world_root := Node2D.new()
	var view := TrafficView.new()
	view.setup(world_root)

	var first: Variant = _actor(catalog, "presentation_first")
	first.player_detected = true
	first.near_lod = false
	view.sync([first], catalog)
	var far_node: Node2D = view._nodes_by_id.get(first.id)
	runner.check(far_node != null, "traffic view: creates far LOD node")
	if far_node == null:
		view.clear()
		return
	runner.check(far_node.visible, "traffic view: detected far node is visible")

	first.player_detected = false
	view.sync([first], catalog)
	runner.check(not far_node.visible, "traffic view: detection hides existing node")

	first.player_detected = true
	first.near_lod = true
	view.sync([first], catalog)
	var near_node: Node2D = view._nodes_by_id.get(first.id)
	runner.check(near_node != null and near_node != far_node, "traffic view: near LOD replaces far node")

	first.near_lod = false
	view.sync([first], catalog)
	runner.check_eq(
		view._nodes_by_id.get(first.id),
		far_node,
		"traffic view: far LOD reuses pooled sprite root"
	)

	first.near_lod = true
	view.sync([first], catalog)
	near_node = view._nodes_by_id.get(first.id)
	view.sync([], catalog)
	var second: Variant = _actor(catalog, "presentation_second")
	second.player_detected = true
	second.near_lod = true
	view.sync([second], catalog)
	runner.check_eq(
		view._nodes_by_id.get(second.id),
		near_node,
		"traffic view: stale near node is reused and rebound"
	)

	second.ai_state = TrafficActorScript.STATE_DESTROYED
	view.sync([second], catalog)
	runner.check(
		not view._nodes_by_id.has(second.id),
		"traffic view: destroyed actor leaves active-node map"
	)
	view.clear()
	runner.check(view._nodes_by_id.is_empty(), "traffic view: clear drops active nodes")
	runner.check(view._far_sprite_pool.is_empty(), "traffic view: clear drops far pool")
	runner.check(view._near_pool._available.is_empty(), "traffic view: clear drops near pool")
	runner.check_eq(view._traffic_root, null, "traffic view: clear releases traffic root")


static func _test_traffic_destroy_breakup(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var world_root := Node2D.new()
	var view := TrafficView.new()
	view.setup(world_root)
	var actor: Variant = _actor(catalog, "presentation_destroy")
	actor.player_detected = true
	actor.near_lod = true
	view.sync([actor], catalog)
	runner.check(view._nodes_by_id.has(actor.id), "traffic destroy: near node active")
	actor.ai_state = TrafficActorScript.STATE_DESTROYED
	view.sync([actor], catalog)
	runner.check(
		not view._nodes_by_id.has(actor.id),
		"traffic destroy: actor leaves active map"
	)
	runner.check(
		_has_ship_breakup_child(world_root),
		"traffic destroy: spawns ShipBreakup on world"
	)
	runner.check(
		view._near_pool._available.size() >= 1,
		"traffic destroy: returns near hull to pool"
	)
	view.clear()


static func _test_npc_play_destroyed_breakup(runner: TestRunner) -> void:
	var world_root := Node2D.new()
	var traffic_root := Node2D.new()
	world_root.add_child(traffic_root)
	var packed := load("res://scenes/npc_ship.tscn") as PackedScene
	runner.check(packed != null, "npc destroy: npc scene loads")
	if packed == null:
		return
	var ship: Node2D = packed.instantiate()
	traffic_root.add_child(ship)
	runner.check(ship.has_method("play_destroyed"), "npc destroy: play_destroyed exists")
	ship.call("play_destroyed")
	runner.check(
		_has_ship_breakup_child(world_root),
		"npc destroy: play_destroyed spawns ShipBreakup on world"
	)


static func _has_ship_breakup_child(root: Node) -> bool:
	for child in root.get_children():
		if child is ShipBreakup:
			return true
	return false


static func _test_traffic_detection_fade(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var world_root := Node2D.new()
	var view := TrafficView.new()
	view.setup(world_root)
	var actor: Variant = _actor(catalog, "presentation_fade")
	actor.player_detected = false
	actor.near_lod = false
	view.sync([actor], catalog, 0.0)
	var node: Node2D = view._nodes_by_id.get(actor.id)
	runner.check(node != null, "traffic fade: spawns node")
	if node == null:
		view.clear()
		return
	runner.check(not node.visible, "traffic fade: undetected starts hidden")

	actor.player_detected = true
	view.sync([actor], catalog, 0.2)
	runner.check(node.visible, "traffic fade: fade-in becomes visible")
	runner.check(
		node.modulate.a > TrafficView.OPACITY_EPSILON and node.modulate.a < 1.0,
		"traffic fade: partial opacity while fading in"
	)
	view.sync([actor], catalog, 0.2)
	runner.check(
		absf(node.modulate.a - 1.0) < 0.01,
		"traffic fade: opacity reaches detected"
	)

	actor.player_detected = false
	view.sync([actor], catalog, 0.2)
	runner.check(
		absf(node.modulate.a - 0.5) < 0.01 and node.visible,
		"traffic fade: partial opacity while fading out"
	)
	view.sync([actor], catalog, 0.2)
	runner.check(not node.visible, "traffic fade: hidden after fade-out")
	runner.check(
		node.modulate.a <= TrafficView.OPACITY_EPSILON,
		"traffic fade: opacity reaches zero"
	)
	view.clear()


static func _actor(catalog: Catalog, actor_id: String):
	var actor = TrafficActorScript.create(
		catalog,
		catalog.get_traffic_config(),
		"transit",
		"pegasus_p101",
		Vector2(300.0, 0.0),
		PI,
		"proxima"
	)
	actor.id = actor_id
	return actor
