extends Area2D

const WeaponHit := preload("res://scripts/gameplay/weapon_hit.gd")
const ROUND_RADIUS := 5.0
const ROUND_COLOR := Color(1.0, 0.7, 0.27, 1.0)
const ROUND_OUTLINE := Color(1.0, 0.55, 0.2, 1.0)
const PLASMA_COLOR := Color(0.95, 0.35, 1.0, 1.0)
const PLASMA_OUTLINE := Color(0.75, 0.2, 0.95, 1.0)
const DEFAULT_SOLID_MASK := 2
const NPC_MASK := 16
const DEFAULT_WEAPON_MASK := DEFAULT_SOLID_MASK | NPC_MASK
const SPAWN_SKIN := 6.0

var _velocity := Vector2.ZERO
var _muzzle_speed: float = 1000.0
var _max_range: float = 1200.0
var _delivery_type := "ballistic"
var _packets: Dictionary = {}
var _traveled: float = 0.0
var _collision_mask: int = DEFAULT_WEAPON_MASK
var _exclude: Array = []
var _shooter: Node = null
var _plasma := false


static func spawn(
	parent: Node2D,
	origin: Vector2,
	direction: Vector2,
	speed: float,
	max_range: float,
	delivery_type: String,
	packets: Dictionary,
	collision_mask: int = DEFAULT_WEAPON_MASK,
	exclude: Array = [],
	inherited_velocity: Vector2 = Vector2.ZERO,
	shooter: Node = null
) -> void:
	var scene := load("res://scenes/world/mass_driver_round.tscn") as PackedScene
	if scene == null:
		push_error("Missing mass driver round scene.")
		return

	var round := scene.instantiate()
	if round == null:
		push_error("Failed to instantiate mass driver round.")
		return

	parent.add_child(round)
	if round.has_method("configure"):
		round.configure(
			origin,
			direction,
			speed,
			max_range,
			delivery_type,
			packets,
			collision_mask,
			exclude,
			inherited_velocity,
			shooter
		)


func configure(
	origin: Vector2,
	direction: Vector2,
	speed: float,
	max_range: float,
	delivery_type: String,
	packets: Dictionary,
	collision_mask: int = DEFAULT_WEAPON_MASK,
	exclude: Array = [],
	inherited_velocity: Vector2 = Vector2.ZERO,
	shooter: Node = null
) -> void:
	_muzzle_speed = speed
	_velocity = direction.normalized() * speed + inherited_velocity
	_max_range = max_range
	_delivery_type = delivery_type
	_packets = packets.duplicate(true)
	_collision_mask = collision_mask
	_exclude = exclude
	_shooter = shooter
	_plasma = delivery_type == "plasma"
	var travel_dir := _velocity.normalized() if _velocity.length_squared() > 1.0 else direction.normalized()
	global_position = origin + travel_dir * SPAWN_SKIN
	if _velocity.length_squared() > 1.0:
		rotation = _velocity.angle() + PI / 2.0
	else:
		rotation = direction.angle() + PI / 2.0
	queue_redraw()


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	queue_redraw()


func _draw() -> void:
	var fill := PLASMA_COLOR if _plasma else ROUND_COLOR
	var outline := PLASMA_OUTLINE if _plasma else ROUND_OUTLINE
	draw_circle(Vector2.ZERO, ROUND_RADIUS, fill)
	draw_arc(Vector2.ZERO, ROUND_RADIUS, 0.0, TAU, 24, outline, 1.5)


func _physics_process(delta: float) -> void:
	var range_step := _muzzle_speed * delta
	var next_traveled := _traveled + range_step
	if next_traveled >= _max_range:
		queue_free()
		return

	var from := global_position
	var to := from + _velocity * delta
	var hit := _sweep(from, to)
	if not hit.is_empty():
		global_position = hit.position
		_apply_hit(hit.collider)
		queue_free()
		return

	global_position = to
	_traveled = next_traveled


func _apply_hit(collider: Object) -> void:
	WeaponHit.apply(collider, _delivery_type, _packets, _shooter)


func _sweep(from: Vector2, to: Vector2) -> Dictionary:
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return {}

	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = _collision_mask
	for body in _exclude:
		if not is_instance_valid(body):
			continue
		if body is CollisionObject2D:
			query.exclude.append(body.get_rid())
	return space_state.intersect_ray(query)


func _on_body_entered(body: Node) -> void:
	_apply_hit(body)
	queue_free()
