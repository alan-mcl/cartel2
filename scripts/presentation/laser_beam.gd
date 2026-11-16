class_name LaserBeam
extends Area2D

const WeaponHit := preload("res://scripts/gameplay/weapon_hit.gd")
const WeaponAttributionScript := preload("res://scripts/presentation/weapon_attribution.gd")
const FX_GROUP := "laser_beam_fx"
const SCENE_PATH := "res://scenes/world/laser_beam.tscn"
const DURATION := 0.12
const FADE_DELTA_CAP := 1.0 / 30.0
const BEAM_Z_INDEX := 50
const BEAM_COLOR := Color(0.37, 0.88, 1.0, 1.0)
const CYBER_COLOR := Color(0.78, 0.35, 1.0, 1.0)
const DEFAULT_SOLID_MASK := 2
const NPC_MASK := 16
const DEFAULT_WEAPON_MASK := DEFAULT_SOLID_MASK | NPC_MASK

static var _packed_scene: PackedScene

var _local_end := Vector2.ZERO
var _beam_color := BEAM_COLOR
var _beam_width := 3.0
var _lifetime := DURATION
var _fade := 1.0
var _skip_next_fade_tick := true


static func spawn(
	parent: Node2D,
	origin: Vector2,
	direction: Vector2,
	max_range: float,
	delivery_type: String,
	packets: Dictionary,
	collision_mask: int = DEFAULT_WEAPON_MASK,
	exclude: Array = [],
	shooter: Node = null,
	visual_variant: String = ""
) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var travel := direction.normalized()
	var start := origin + travel * 6.0
	var end := start + travel * maxf(max_range, 1.0)
	var hit := _raycast(parent, start, direction, max_range, collision_mask, exclude)
	if not hit.is_empty():
		end = hit.position
		WeaponHit.apply(
			hit.collider,
			delivery_type,
			packets,
			shooter,
			direction,
			WeaponAttributionScript.capture(shooter),
			hit.position
		)

	if _packed_scene == null:
		_packed_scene = load(SCENE_PATH) as PackedScene
	if _packed_scene == null:
		push_error("Missing laser beam scene.")
		return

	var beam: LaserBeam = _packed_scene.instantiate() as LaserBeam
	if beam == null:
		push_error("Failed to instantiate laser beam.")
		return

	parent.add_child(beam)
	beam.configure(start, end, delivery_type, visual_variant)


func configure(start: Vector2, end: Vector2, delivery_type: String, visual_variant: String) -> void:
	add_to_group(FX_GROUP)
	z_as_relative = false
	z_index = BEAM_Z_INDEX
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	_lifetime = DURATION
	_fade = 1.0
	_skip_next_fade_tick = true
	_beam_width = 4.0 if visual_variant == "laser" else 3.0
	if delivery_type == "cyber" or visual_variant == "cyber":
		_beam_color = CYBER_COLOR
	elif visual_variant == "laser":
		_beam_color = Color(0.45, 0.95, 1.0, 1.0)
	else:
		_beam_color = BEAM_COLOR

	global_position = start
	_local_end = to_local(end)
	set_process(true)
	call_deferred("queue_redraw")


func _ready() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	if _skip_next_fade_tick:
		_skip_next_fade_tick = false
		queue_redraw()
		return
	var fade_step := minf(delta, FADE_DELTA_CAP) / maxf(_lifetime, 0.001)
	_fade -= fade_step
	if _fade <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var a := clampf(_fade, 0.0, 1.0)
	var glow := Color(_beam_color.r, _beam_color.g, _beam_color.b, 0.4 * a)
	var core := Color(_beam_color.r, _beam_color.g, _beam_color.b, a)
	draw_circle(Vector2.ZERO, _beam_width + 2.0, glow)
	draw_circle(Vector2.ZERO, _beam_width, core)

	var seg_len := _local_end.length()
	if seg_len < 0.05:
		return

	draw_line(Vector2.ZERO, _local_end, core, _beam_width, true)

	var dir := _local_end / seg_len
	var half_w := _beam_width * 0.5
	var perp := Vector2(-dir.y, dir.x) * half_w
	var quad := PackedVector2Array([
		Vector2.ZERO + perp,
		Vector2.ZERO - perp,
		_local_end - perp,
		_local_end + perp,
	])
	draw_colored_polygon(quad, glow)
	draw_colored_polygon(quad, core)
	draw_circle(_local_end, _beam_width * 0.65, core)


static func _raycast(
	parent: Node2D,
	origin: Vector2,
	direction: Vector2,
	max_range: float,
	collision_mask: int,
	exclude: Array
) -> Dictionary:
	if not parent.is_inside_tree():
		return {}
	var world := parent.get_world_2d()
	if world == null:
		return {}
	var space_state := world.direct_space_state
	if space_state == null:
		return {}

	var query := PhysicsRayQueryParameters2D.create(
		origin,
		origin + direction.normalized() * maxf(max_range, 1.0)
	)
	query.collision_mask = collision_mask
	for body in exclude:
		if not is_instance_valid(body):
			continue
		if body is CollisionObject2D:
			query.exclude.append(body.get_rid())
	return space_state.intersect_ray(query)