class_name UnspaceContainmentFold
extends RefCounted

## Player-pivot rim folds: spin the topo about the ship when near the mesh edge or far from the portal.

const RIM_GUARD_FRACTION := 1.25
const PORTAL_TRIGGER_FRACTION := 1.15
const VELOCITY_FLOOR := 8.0
const INWARD_MIN_ANGLE_DEG := 70.0


static func rim_guard_distance(play_bounds: float) -> float:
	return maxf(play_bounds, 0.0) * RIM_GUARD_FRACTION


static func portal_trigger_distance(play_bounds: float) -> float:
	return maxf(play_bounds, 0.0) * PORTAL_TRIGGER_FRACTION


static func should_trigger_containment(
	ship_pos: Vector2,
	portal_pos: Vector2,
	mesh_center: Vector2,
	play_bounds: float,
	fold_animating: bool,
	containment_cooldown: float = 0.0
) -> bool:
	if fold_animating or play_bounds <= 0.0 or containment_cooldown > 0.0:
		return false
	if ship_pos.distance_to(mesh_center) > rim_guard_distance(play_bounds):
		return true
	if portal_pos.is_finite() and ship_pos.distance_to(portal_pos) > portal_trigger_distance(play_bounds):
		return true
	return false


static func rotate_about_pivot(point: Vector2, pivot: Vector2, angle_rad: float) -> Vector2:
	if absf(angle_rad) < 0.0001:
		return point
	var offset := point - pivot
	var c := cos(angle_rad)
	var s := sin(angle_rad)
	return pivot + Vector2(offset.x * c - offset.y * s, offset.x * s + offset.y * c)


static func rotate_vector(vec: Vector2, angle_rad: float) -> Vector2:
	if absf(angle_rad) < 0.0001:
		return vec
	var c := cos(angle_rad)
	var s := sin(angle_rad)
	return Vector2(vec.x * c - vec.y * s, vec.x * s + vec.y * c)


static func pick_rim_fold_angle(
	n: int,
	ship_pos: Vector2,
	mesh_center: Vector2,
	velocity: Vector2,
	seed: int = 0
) -> Dictionary:
	var out := {
		"delta_rad": 0.0,
		"k": 0,
	}
	if n < 2:
		return out

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	if velocity.length() < VELOCITY_FLOOR:
		var k_rand := rng.randi_range(1, n - 1)
		out["k"] = k_rand
		out["delta_rad"] = float(k_rand) * TAU / float(n)
		return out

	var outward := ship_pos - mesh_center
	if outward.length_squared() < 1.0:
		outward = velocity.normalized()

	var cos_limit := cos(deg_to_rad(INWARD_MIN_ANGLE_DEG))
	var qualified: Array = []
	var best_k := -1
	var best_dot := INF

	for k in range(1, n):
		var delta_rad := float(k) * TAU / float(n)
		var new_outward := rotate_vector(outward, delta_rad)
		if new_outward.length_squared() < 0.001:
			continue
		var dir_out := new_outward.normalized()
		var dir_vel := velocity.normalized()
		var dot := dir_vel.dot(dir_out)
		if dot <= cos_limit:
			qualified.append(k)
		if dot < best_dot:
			best_dot = dot
			best_k = k

	var chosen_k := best_k
	if qualified.size() > 0:
		chosen_k = int(qualified[rng.randi_range(0, qualified.size() - 1)])
	elif chosen_k < 0:
		return out

	out["k"] = chosen_k
	out["delta_rad"] = float(chosen_k) * TAU / float(n)
	return out


static func distance_to_mesh_center_unchanged_by_player_spin(
	ship_pos: Vector2,
	mesh_center: Vector2,
	angle_rad: float
) -> bool:
	var pivot := ship_pos
	var new_center := rotate_about_pivot(mesh_center, pivot, angle_rad)
	return is_equal_approx(ship_pos.distance_to(mesh_center), ship_pos.distance_to(new_center))
