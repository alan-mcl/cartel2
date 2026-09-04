extends Line2D

const WeaponHit := preload("res://scripts/gameplay/weapon_hit.gd")
const DURATION := 0.1
const BEAM_COLOR := Color(0.37, 0.88, 1.0, 0.95)
const SOLID_MASK := 2


static func spawn(parent: Node2D, origin: Vector2, direction: Vector2, max_range: float, damage: float) -> void:
	var end := origin + direction.normalized() * max_range
	var hit := _raycast(parent, origin, direction, max_range)
	if not hit.is_empty():
		end = hit.position
		WeaponHit.apply(hit.collider, damage)

	var beam := Line2D.new()
	beam.width = 2.5
	beam.default_color = BEAM_COLOR
	beam.points = PackedVector2Array([origin, end])
	parent.add_child(beam)

	var timer := beam.get_tree().create_timer(DURATION)
	timer.timeout.connect(beam.queue_free)


static func _raycast(parent: Node2D, origin: Vector2, direction: Vector2, max_range: float) -> Dictionary:
	var space_state := parent.get_world_2d().direct_space_state
	if space_state == null:
		return {}

	var query := PhysicsRayQueryParameters2D.create(
		origin,
		origin + direction.normalized() * max_range
	)
	query.collision_mask = SOLID_MASK
	return space_state.intersect_ray(query)
