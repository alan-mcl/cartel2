extends Area2D

const WeaponHit := preload("res://scripts/gameplay/weapon_hit.gd")
const ProjectGuidance := preload("res://scripts/gameplay/project_guidance.gd")
const WarheadBlast := preload("res://scripts/presentation/warhead_blast.gd")
const INTERCEPTABLE_GROUP := "interceptable_round"
const ROCKET_RADIUS := 10.0
const DEFAULT_SOLID_MASK := 2
const NPC_MASK := 16
const DEFAULT_WEAPON_MASK := DEFAULT_SOLID_MASK | NPC_MASK
const SPAWN_SKIN := 8.0
const SCENE_PATH := "res://scenes/world/rocket_projectile.tscn"

static var _packed_scene: PackedScene

var _velocity := Vector2.ZERO
var _muzzle_speed: float = 650.0
var _max_range: float = 1500.0
var _delivery_type := "ballistic"
var _packets: Dictionary = {}
var _traveled: float = 0.0
var _collision_mask: int = DEFAULT_WEAPON_MASK
var _exclude: Array = []
var _shooter: Node = null
var _homing := false
var _guidance_target_id := ""
var _guidance_turn_rate := 2.8
var _visual_variant := "rocket"
var _splash := false
var _exhaust_phase := 0.0


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
	shooter: Node = null,
	guidance: Dictionary = {},
	visual_variant: String = "rocket",
	splash: bool = false
) -> void:
	if _packed_scene == null:
		_packed_scene = load(SCENE_PATH) as PackedScene
	var scene := _packed_scene
	if scene == null:
		push_error("Missing rocket projectile scene.")
		return

	var rocket := scene.instantiate()
	if rocket == null:
		push_error("Failed to instantiate rocket projectile.")
		return

	parent.add_child(rocket)
	if rocket.has_method("configure"):
		rocket.configure(
			origin,
			direction,
			speed,
			max_range,
			delivery_type,
			packets,
			collision_mask,
			exclude,
			inherited_velocity,
			shooter,
			guidance,
			visual_variant,
			splash
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
	shooter: Node = null,
	guidance: Dictionary = {},
	visual_variant: String = "rocket",
	splash: bool = false
) -> void:
	_muzzle_speed = speed
	_velocity = direction.normalized() * speed + inherited_velocity
	_max_range = max_range
	_delivery_type = delivery_type
	_packets = packets.duplicate(true)
	_collision_mask = collision_mask
	_exclude = exclude
	_shooter = shooter
	_homing = bool(guidance.get("homing", false))
	_guidance_target_id = str(guidance.get("target_id", ""))
	_guidance_turn_rate = float(guidance.get("turn_rate", 2.8))
	_visual_variant = visual_variant if not visual_variant.is_empty() else "rocket"
	_splash = splash
	if _delivery_type == "guided" and not _homing:
		_visual_variant = "rocket"
	if _delivery_type == "guided":
		_visual_variant = "guided"
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
	if _delivery_type in ["ballistic", "guided"]:
		add_to_group(INTERCEPTABLE_GROUP)
	queue_redraw()


func _draw() -> void:
	var guided := _visual_variant == "guided"
	var body_col := Color(0.82, 0.84, 0.88, 1.0) if guided else Color(0.75, 0.72, 0.68, 1.0)
	var nose_col := Color(0.55, 0.95, 1.0, 1.0) if guided else Color(0.95, 0.55, 0.3, 1.0)
	var fin_col := Color(0.45, 0.48, 0.52, 1.0) if guided else Color(0.55, 0.35, 0.25, 1.0)
	var outline := Color(0.25, 0.28, 0.32, 1.0) if guided else Color(0.45, 0.22, 0.12, 1.0)

	# Nose at -Y (forward). Tail exhaust at +Y.
	var body := PackedVector2Array([
		Vector2(0.0, -ROCKET_RADIUS * 1.35),
		Vector2(ROCKET_RADIUS * 0.42, -ROCKET_RADIUS * 0.2),
		Vector2(ROCKET_RADIUS * 0.38, ROCKET_RADIUS * 0.85),
		Vector2(0.0, ROCKET_RADIUS * 0.55),
		Vector2(-ROCKET_RADIUS * 0.38, ROCKET_RADIUS * 0.85),
		Vector2(-ROCKET_RADIUS * 0.42, -ROCKET_RADIUS * 0.2),
	])
	draw_colored_polygon(body, body_col)
	draw_polyline(body + PackedVector2Array([body[0]]), outline, 1.5)

	var fin_w := ROCKET_RADIUS * 0.55
	var fin_h := ROCKET_RADIUS * 0.45
	for side in [-1.0, 1.0]:
		var fin := PackedVector2Array([
			Vector2(side * ROCKET_RADIUS * 0.35, ROCKET_RADIUS * 0.35),
			Vector2(side * (ROCKET_RADIUS * 0.35 + fin_w), ROCKET_RADIUS * 0.95),
			Vector2(side * ROCKET_RADIUS * 0.35, ROCKET_RADIUS * 0.75),
		])
		draw_colored_polygon(fin, fin_col)

	draw_circle(Vector2(0.0, -ROCKET_RADIUS * 1.05), ROCKET_RADIUS * 0.22, nose_col)

	var plume_len := ROCKET_RADIUS * (1.1 + 0.25 * sin(_exhaust_phase))
	var plume := PackedVector2Array([
		Vector2(0.0, ROCKET_RADIUS * 0.6),
		Vector2(ROCKET_RADIUS * 0.28, ROCKET_RADIUS * 0.6 + plume_len * 0.35),
		Vector2(0.0, ROCKET_RADIUS * 0.6 + plume_len),
		Vector2(-ROCKET_RADIUS * 0.28, ROCKET_RADIUS * 0.6 + plume_len * 0.35),
	])
	var plume_col := Color(1.0, 0.55, 0.2, 0.55) if not guided else Color(0.45, 0.75, 1.0, 0.5)
	draw_colored_polygon(plume, plume_col)


func _physics_process(delta: float) -> void:
	_exhaust_phase += delta * 18.0
	_apply_guidance(delta)
	var range_step := _velocity.length() * delta
	var next_traveled := _traveled + range_step
	if next_traveled >= _max_range:
		_despawn(true)
		return

	var from := global_position
	var to := from + _velocity * delta
	var hit := _sweep(from, to)
	if not hit.is_empty():
		global_position = hit.position
		_apply_hit(hit.collider)
		_despawn(false)
		return

	global_position = to
	_traveled = next_traveled
	if _velocity.length_squared() > 1.0:
		rotation = _velocity.angle() + PI / 2.0
	queue_redraw()


func _despawn(range_fizzle: bool) -> void:
	if _splash:
		var parent := get_parent()
		if parent != null:
			WarheadBlast.spawn(parent, global_position, range_fizzle)
	remove_from_group(INTERCEPTABLE_GROUP)
	queue_free()


func _apply_guidance(delta: float) -> void:
	if not _homing or _guidance_target_id.is_empty():
		return
	if _shooter == null or not is_instance_valid(_shooter):
		_homing = false
		return
	if not _shooter.has_method("query_weapon_guidance"):
		_homing = false
		return
	var query: Dictionary = _shooter.query_weapon_guidance(_guidance_target_id)
	if not bool(query.get("active", false)):
		_homing = false
		return
	var target_pos: Vector2 = query.get("position", Vector2.ZERO)
	_velocity = ProjectGuidance.steer_velocity(
		_velocity,
		global_position,
		target_pos,
		_guidance_turn_rate,
		delta
	)


func _apply_hit(collider: Object) -> void:
	WeaponHit.apply(collider, _delivery_type, _packets, _shooter, _velocity)


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
	_despawn(false)
