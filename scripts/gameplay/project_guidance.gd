class_name ProjectGuidance
extends RefCounted

## Steers a projectile velocity toward a world-space target without exceeding turn_rate_rad per second.

static func steer_velocity(
	velocity: Vector2,
	current_position: Vector2,
	target_position: Vector2,
	turn_rate_rad: float,
	delta: float
) -> Vector2:
	var speed := velocity.length()
	if speed < 1.0 or delta <= 0.0 or turn_rate_rad <= 0.0:
		return velocity

	var to_target := target_position - current_position
	if to_target.length_squared() < 1.0:
		return velocity

	var current_dir := velocity / speed
	var desired_dir := to_target.normalized()
	var angle_delta := current_dir.angle_to(desired_dir)
	var max_turn := turn_rate_rad * delta
	angle_delta = clampf(angle_delta, -max_turn, max_turn)
	return current_dir.rotated(angle_delta) * speed
