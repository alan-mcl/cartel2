class_name AscidianTerrainSteer
extends RefCounted

## Headless-friendly terrain following from a height sampler (0..1).


static func compute_steer(
	position: Vector2,
	velocity: Vector2,
	sample_height: Callable,
	probe_distance: float = 220.0
) -> Vector2:
	if not sample_height.is_valid():
		return Vector2.ZERO
	var forward := velocity
	if forward.length_squared() < 1.0:
		forward = Vector2.RIGHT
	forward = forward.normalized()

	var ahead := position + forward * probe_distance
	var left := position + forward.rotated(PI * 0.5) * probe_distance * 0.65
	var right := position + forward.rotated(-PI * 0.5) * probe_distance * 0.65

	var h_ahead := float(sample_height.call(ahead))
	var h_left := float(sample_height.call(left))
	var h_right := float(sample_height.call(right))
	var h_here := float(sample_height.call(position))

	var steer := Vector2.ZERO
	if h_ahead > h_left + 0.015 and h_ahead > h_right + 0.015:
		var flank_dir := forward.rotated(PI * 0.5) if h_left < h_right else forward.rotated(-PI * 0.5)
		steer = flank_dir * 0.85
	else:
		var grad := Vector2(
			float(sample_height.call(position + Vector2(probe_distance * 0.35, 0.0)))
				- float(sample_height.call(position - Vector2(probe_distance * 0.35, 0.0))),
			float(sample_height.call(position + Vector2(0.0, probe_distance * 0.35)))
				- float(sample_height.call(position - Vector2(0.0, probe_distance * 0.35)))
		)
		if grad.length_squared() > 0.0001:
			steer = -grad.normalized() * 0.55

	if h_here > h_ahead:
		steer -= forward * 0.25

	return steer
