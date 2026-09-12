extends RefCounted
class_name TrafficView

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
const NPC_SHIP_SCENE_PATH := "res://scenes/npc_ship.tscn"
const THRUST_SPRITE := "res://assets/ships/fx/thrust.svg"
const ChassisSpriteScript := preload("res://scripts/presentation/chassis_sprite.gd")
const HullHitboxScript := preload("res://scripts/presentation/hull_hitbox.gd")

var _traffic_root: Node2D
var _nodes_by_id: Dictionary = {}
var _far_thrust_by_id: Dictionary = {}
var _near_lod_by_id: Dictionary = {}
var _destroy_fx_started: Dictionary = {}


func setup(world_root: Node2D) -> void:
	clear()
	_traffic_root = Node2D.new()
	_traffic_root.name = "Traffic"
	world_root.add_child(_traffic_root)


func clear() -> void:
	for node_variant in _nodes_by_id.values():
		if typeof(node_variant) != TYPE_OBJECT:
			continue
		var node: Node = node_variant
		if is_instance_valid(node):
			node.queue_free()
	_nodes_by_id.clear()
	_far_thrust_by_id.clear()
	_near_lod_by_id.clear()
	_destroy_fx_started.clear()
	if _traffic_root != null and is_instance_valid(_traffic_root):
		_traffic_root.queue_free()
	_traffic_root = null


func sync(actors: Array, catalog: Catalog) -> void:
	if _traffic_root == null or not is_instance_valid(_traffic_root):
		return

	var active_ids: Dictionary = {}

	for actor_variant in actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		active_ids[actor.id] = true

		if actor.ai_state == TrafficActorScript.STATE_DESTROYED:
			_start_destroy_fx(actor)
			continue

		var was_near: bool = bool(_near_lod_by_id.get(actor.id, false))
		var is_near: bool = bool(actor.near_lod)
		var node: Node2D = _nodes_by_id.get(actor.id)

		if is_near != was_near or node == null or not is_instance_valid(node):
			if node != null and is_instance_valid(node):
				actor.sync_position(node.global_position)
				node.queue_free()
				_nodes_by_id.erase(actor.id)
				_far_thrust_by_id.erase(actor.id)
			if is_near:
				_spawn_near_ship(actor, catalog)
			else:
				_spawn_far_sprite(actor)
			_near_lod_by_id[actor.id] = is_near
			node = _nodes_by_id.get(actor.id)

		if node == null or not is_instance_valid(node):
			continue

		_apply_detection_visibility(actor, node)

		if is_near:
			if node.has_method("sync_from_actor"):
				node.call("sync_from_actor", actor)
			if node.has_method("apply_hull_damage_visual"):
				node.call(
					"apply_hull_damage_visual",
					actor.hull_current / maxf(actor.hull_max, 1.0)
				)
			_spawn_actor_weapons(actor, node)
		else:
			_sync_far_node(actor, node)

	_prune_stale_nodes(active_ids)


func _start_destroy_fx(actor) -> void:
	if _destroy_fx_started.has(actor.id):
		return
	var node: Node2D = _nodes_by_id.get(actor.id)
	if node != null and is_instance_valid(node):
		if node.has_method("play_destroyed"):
			node.call("play_destroyed")
		else:
			node.queue_free()
	_nodes_by_id.erase(actor.id)
	_far_thrust_by_id.erase(actor.id)
	_near_lod_by_id.erase(actor.id)
	_destroy_fx_started[actor.id] = true


func _prune_stale_nodes(active_ids: Dictionary) -> void:
	var stale_ids: Array = []
	for actor_id in _nodes_by_id.keys():
		if not active_ids.has(actor_id):
			stale_ids.append(actor_id)

	for actor_id in stale_ids:
		var node: Node2D = _nodes_by_id.get(actor_id)
		if node != null and is_instance_valid(node):
			node.queue_free()
		_nodes_by_id.erase(actor_id)
		_far_thrust_by_id.erase(actor_id)
		_near_lod_by_id.erase(actor_id)
		_destroy_fx_started.erase(actor_id)


func _apply_detection_visibility(actor, node: Node2D) -> void:
	var visible := bool(actor.player_detected)
	if node.visible != visible:
		node.visible = visible


func _spawn_near_ship(actor, catalog: Catalog) -> void:
	var packed: PackedScene = load(NPC_SHIP_SCENE_PATH) as PackedScene
	if packed == null:
		return
	var ship: Node2D = packed.instantiate()
	_traffic_root.add_child(ship)
	ship.global_position = actor.position
	if ship.has_method("bind_actor"):
		ship.call("bind_actor", actor, catalog)
	_nodes_by_id[actor.id] = ship


func _spawn_far_sprite(actor) -> void:
	var root := Node2D.new()
	root.name = "TrafficRemote_%s" % actor.callsign
	_traffic_root.add_child(root)

	var hull := Sprite2D.new()
	hull.name = "Hull"
	var sprite_path := str(actor.assembled_ship.chassis.get("sprite", ""))
	if not sprite_path.is_empty():
		hull.texture = ChassisSpriteScript.get_texture(sprite_path)
	hull.scale = Vector2(0.65, 0.65)
	var brightness: float = 1.0 + actor.hull_color_shift
	hull.modulate = Color(brightness, brightness, brightness, 1.0)
	root.add_child(hull)

	var thrust_flame := Sprite2D.new()
	thrust_flame.name = "ThrustFlame"
	thrust_flame.visible = false
	thrust_flame.scale = Vector2(0.65, 0.65)
	var thrust_texture := load(THRUST_SPRITE) as Texture2D
	if thrust_texture != null:
		thrust_flame.texture = thrust_texture
	if not sprite_path.is_empty():
		HullHitboxScript.apply_hull_and_thrust(hull, thrust_flame, sprite_path)
	root.add_child(thrust_flame)

	root.global_position = actor.position
	root.rotation = actor.motion.facing + PI / 2.0
	_nodes_by_id[actor.id] = root
	_far_thrust_by_id[actor.id] = thrust_flame


func _sync_far_node(actor, node: Node2D) -> void:
	node.global_position = actor.position
	node.rotation = actor.motion.facing + PI / 2.0
	var thrust_flame: Sprite2D = _far_thrust_by_id.get(actor.id)
	if thrust_flame != null and is_instance_valid(thrust_flame):
		thrust_flame.visible = actor.motion.is_thrusting()


func _spawn_actor_weapons(actor, node: Node2D) -> void:
	if actor.pending_weapon_orders.is_empty():
		return
	if not node.has_method("spawn_weapon_orders"):
		return
	node.call("spawn_weapon_orders", actor.pending_weapon_orders)
