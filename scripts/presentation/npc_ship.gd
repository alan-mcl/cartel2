extends CharacterBody2D

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
const ShipBreakup := preload("res://scripts/presentation/ship_breakup.gd")
const THRUST_SPRITE := "res://assets/ships/fx/thrust.svg"
const NPC_LAYER := 16
const SOLID_MASK := 2
const WEAPON_MASK := SOLID_MASK | NPC_LAYER | 1

var actor
var catalog: Catalog

@onready var _thrust_flame: Sprite2D = $Visual/ThrustFlame
@onready var _engine_exhaust: EngineExhaust = $Visual/EngineExhaust
@onready var _hull: Sprite2D = $Visual/Hull
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _visual_root: Node2D = $Visual

var _defence_visual: CombatDefenceVisual


func bind_actor(traffic_actor, game_catalog: Catalog) -> void:
	actor = traffic_actor
	catalog = game_catalog
	_apply_hull_visual()
	apply_hull_damage_visual(1.0)


func sync_from_actor(traffic_actor) -> void:
	if traffic_actor == null:
		return
	velocity = traffic_actor.motion.velocity
	rotation = traffic_actor.motion.facing + PI / 2.0
	# A newly added CharacterBody2D is not attached to a physics space until the
	# engine has completed its next physics registration pass.  Presentation can
	# still render the authoritative simulation position during that small window.
	# This also keeps headless presentation smoke/benchmark runs honest instead of
	# emitting PhysicsServer errors for a body that cannot collide yet.
	if PhysicsServer2D.body_get_space(get_rid()).is_valid():
		move_and_slide()
	else:
		global_position = traffic_actor.position
	traffic_actor.sync_position(global_position)
	_update_thrust_visual(traffic_actor.motion.is_thrusting())
	if _defence_visual != null and actor != null and actor.assembled_ship != null and actor.combat_state != null:
		_defence_visual.bind_ship(actor.assembled_ship, actor.combat_state)


func take_weapon_hit(damage: float) -> void:
	take_combat_hit("ballistic", {"kinetic": damage})


func take_combat_hit(delivery_type: String, packets: Dictionary) -> Dictionary:
	if actor == null or catalog == null:
		return {}
	var result: Dictionary = actor.take_combat_hit(delivery_type, packets, catalog.get_traffic_config())
	if _defence_visual != null:
		_defence_visual.play_hit_layers(result.get("defence_layers", {}))
	return result


func apply_weapon_impulse(delta_v: Vector2) -> void:
	if actor != null:
		actor.motion.velocity += delta_v


func apply_hull_damage_visual(health_ratio: float) -> void:
	if _hull == null:
		return
	ShipVisual.apply_damage_tint(_hull, health_ratio, _hull_base_modulate())


func play_destroyed() -> void:
	var ship_velocity := Vector2.ZERO
	if actor != null:
		ship_velocity = actor.motion.velocity
	var tint := _hull.modulate if _hull != null else Color.WHITE
	var world := _get_world_root()
	if world != null:
		ShipBreakup.spawn(world, global_position, ship_velocity, tint)
	queue_free()


func query_weapon_guidance(target_id: String) -> Dictionary:
	if actor == null:
		return {"active": false}
	if actor.locked_target_id != target_id or target_id.is_empty():
		return {"active": false}
	if target_id == TargetLock.PLAYER_TARGET_ID:
		return {"active": true, "position": actor.last_known_player_pos}
	return {"active": false}


func spawn_weapon_orders(orders: Array) -> void:
	var world := _get_world_root()
	if world == null or actor == null:
		return
	ShipVisual.spawn_weapon_orders(
		world,
		orders,
		global_position,
		actor.motion.facing,
		actor.motion.velocity,
		WEAPON_MASK,
		[self],
		self,
		actor.assembled_ship.chassis
	)


func _ready() -> void:
	collision_layer = NPC_LAYER
	collision_mask = SOLID_MASK
	add_to_group("npc_ship")
	_defence_visual = CombatDefenceVisual.new()
	_defence_visual.z_index = 2
	_defence_visual.bind_owner(self)
	if _visual_root != null:
		_visual_root.add_child(_defence_visual)

	var thrust_texture := load(THRUST_SPRITE) as Texture2D
	if _thrust_flame and thrust_texture:
		_thrust_flame.texture = thrust_texture


func _apply_hull_visual() -> void:
	if _hull == null or actor == null or actor.assembled_ship.chassis.is_empty():
		return

	var sprite_path := str(actor.assembled_ship.chassis.get("sprite", ""))
	if not sprite_path.is_empty():
		ShipVisual.apply_hull(_hull, _thrust_flame, _collision_shape, sprite_path)
		ShipVisual.sync_engine_exhaust(
			_engine_exhaust,
			_thrust_flame,
			actor.assembled_ship,
			sprite_path
		)

	var brightness: float = 1.0 + actor.hull_color_shift
	_hull.modulate = Color(brightness, brightness, brightness, 1.0)


func _hull_base_modulate() -> Color:
	if actor == null:
		return Color.WHITE
	var brightness: float = 1.0 + actor.hull_color_shift
	return Color(brightness, brightness, brightness, 1.0)


func _get_world_root() -> Node2D:
	var main := get_parent()
	while main != null:
		if main.name == "Traffic":
			return main.get_parent() as Node2D
		main = main.get_parent()
	return null


func _update_thrust_visual(active: bool) -> void:
	if _thrust_flame:
		_thrust_flame.visible = false
	if _engine_exhaust:
		_engine_exhaust.set_thrusting(active, 1.0 if active else 0.0)
