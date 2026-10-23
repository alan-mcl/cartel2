class_name BallisticHit
extends RefCounted

## Shared ray sweep and hit application for mass-driver rounds and rockets.
## A proximity mine uses `apply` only. Lasers and point-defence pellets stay on their own paths.


static func sweep(
	space_state: PhysicsDirectSpaceState2D,
	from: Vector2,
	to: Vector2,
	collision_mask: int,
	exclude: Array
) -> Dictionary:
	if space_state == null:
		return {}

	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = collision_mask
	var excluded: Array[RID] = []
	for body in exclude:
		if not is_instance_valid(body):
			continue
		if body is CollisionObject2D:
			var rid: RID = (body as CollisionObject2D).get_rid()
			if rid.is_valid():
				excluded.append(rid)
	query.exclude = excluded
	return space_state.intersect_ray(query)


static func apply(
	collider: Object,
	delivery_type: String,
	packets: Dictionary,
	shooter: Variant,
	shot_velocity: Vector2,
	context: WeaponHitContext = null
) -> void:
	var attributed: Variant = shooter
	if not is_instance_valid(shooter):
		attributed = null
	WeaponHit.apply(collider, delivery_type, packets, attributed, shot_velocity, context)
