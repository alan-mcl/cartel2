extends Area2D

const WeaponHit := preload("res://scripts/gameplay/weapon_hit.gd")
const ROCKET_RADIUS := 7.0
const ROCKET_COLOR := Color(0.95, 0.45, 0.25, 1.0)
const ROCKET_OUTLINE := Color(0.85, 0.3, 0.15, 1.0)
const DEFAULT_SOLID_MASK := 2
const NPC_MASK := 16
const DEFAULT_WEAPON_MASK := DEFAULT_SOLID_MASK | NPC_MASK

var _direction := Vector2.RIGHT
var _speed: float = 650.0
var _max_range: float = 1500.0
var _delivery_type := "ballistic"
var _packets: Dictionary = {}
var _traveled: float = 0.0
var _collision_mask: int = DEFAULT_WEAPON_MASK
var _exclude: Array = []


static func spawn(
	parent: Node2D,
	origin: Vector2,
	direction: Vector2,
	speed: float,
	max_range: float,
	delivery_type: String,
	packets: Dictionary,
	collision_mask: int = DEFAULT_WEAPON_MASK,
	exclude: Array = []
) -> void:
	var scene := load("res://scenes/world/rocket_projectile.tscn") as PackedScene
	if scene == null:
		push_error("Missing rocket projectile scene.")
		return

	var rocket := scene.instantiate()
	if rocket == null:
		push_error("Failed to instantiate rocket projectile.")
		return

	parent.add_child(rocket)
	if rocket.has_method("configure"):
		rocket.configure(origin, direction, speed, max_range, delivery_type, packets, collision_mask, exclude)


func configure(
	origin: Vector2,
	direction: Vector2,
	speed: float,
	max_range: float,
	delivery_type: String,
	packets: Dictionary,
	collision_mask: int = DEFAULT_WEAPON_MASK,
	exclude: Array = []
) -> void:
	global_position = origin
	_direction = direction.normalized()
	_speed = speed
	_max_range = max_range
	_delivery_type = delivery_type
	_packets = packets.duplicate(true)
	_collision_mask = collision_mask
	_exclude = exclude
	rotation = _direction.angle() + PI / 2.0
	queue_redraw()


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, ROCKET_RADIUS, ROCKET_COLOR)
	draw_arc(Vector2.ZERO, ROCKET_RADIUS, 0.0, TAU, 24, ROCKET_OUTLINE, 2.0)


func _physics_process(delta: float) -> void:
	var step := _speed * delta
	var next_traveled := _traveled + step
	if next_traveled >= _max_range:
		queue_free()
		return

	var from := global_position
	var to := from + _direction * step
	var hit := _sweep(from, to)
	if not hit.is_empty():
		global_position = hit.position
		WeaponHit.apply(hit.collider, _delivery_type, _packets)
		queue_free()
		return

	global_position = to
	_traveled = next_traveled


func _sweep(from: Vector2, to: Vector2) -> Dictionary:
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return {}

	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = _collision_mask
	for body in _exclude:
		if body is CollisionObject2D:
			query.exclude.append(body.get_rid())
	return space_state.intersect_ray(query)


func _on_body_entered(body: Node) -> void:
	WeaponHit.apply(body, _delivery_type, _packets)
	queue_free()
