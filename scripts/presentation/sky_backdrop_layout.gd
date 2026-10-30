class_name SkyBackdropLayout
extends RefCounted

const STAR_MIN_RADIUS := 7000.0
const STAR_MAX_RADIUS := 12000.0
const INNER_CLEARANCE_RADIUS := 6200.0
const COMPANION_MIN_DISC_RADIUS := 8.0

const RING_OUTER_SCALE := {
	"none": 1.0,
	"small": 1.4,
	"broad": 2.2,
}

const APPEARANCE_MIX := {
	"banded": 0.0,
	"silver": 0.35,
	"turbulent": 0.85,
}


static func disc_radius_from_angular(angular_diameter_deg: float, distance: float) -> float:
	var half_rad := deg_to_rad(angular_diameter_deg * 0.5)
	return distance * tan(half_rad)


static func ring_outer_scale(rings: String) -> float:
	return float(RING_OUTER_SCALE.get(rings, 1.0))


static func min_distance_for_parent(angular_diameter_deg: float, rings: String) -> float:
	var half_rad := deg_to_rad(angular_diameter_deg * 0.5)
	var ring_scale := ring_outer_scale(rings)
	for attempt in range(64):
		var t := float(attempt) / 63.0
		var distance := lerpf(STAR_MIN_RADIUS, STAR_MAX_RADIUS, t)
		var disc_r := disc_radius_from_angular(angular_diameter_deg, distance)
		var outer := disc_r * ring_scale
		if distance - outer >= INNER_CLEARANCE_RADIUS:
			return distance
	return STAR_MAX_RADIUS


static func companion_disc_radius(
	primary_disc_radius: float,
	catalog_primary_luminosity: float,
	catalog_companion_luminosity: float
) -> float:
	var primary_lum := maxf(catalog_primary_luminosity, 1e-6)
	var companion_lum := maxf(catalog_companion_luminosity, 1e-6)
	var scaled := primary_disc_radius * sqrt(companion_lum / primary_lum)
	return maxf(scaled, COMPANION_MIN_DISC_RADIUS)


static func companion_world_position(
	primary_pos: Vector2,
	separation_deg: float
) -> Vector2:
	if primary_pos.length_squared() < 1.0:
		return Vector2.ZERO
	var base_angle := primary_pos.angle()
	var distance := primary_pos.length()
	var angle := base_angle + deg_to_rad(separation_deg)
	return Vector2.from_angle(angle) * distance


static func pick_parent_angle(primary_pos: Vector2, rng: RandomNumberGenerator) -> float:
	if primary_pos.length_squared() < 1.0:
		return rng.randf() * TAU
	var away := primary_pos.angle() + PI + rng.randf_range(-0.6, 0.6)
	return away


static func appearance_mix(appearance: String) -> float:
	return float(APPEARANCE_MIX.get(appearance, 0.0))


static func ring_mode(rings: String) -> float:
	match rings:
		"small":
			return 0.25
		"broad":
			return 1.0
		_:
			return 0.0
