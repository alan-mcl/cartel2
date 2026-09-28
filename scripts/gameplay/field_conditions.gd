class_name FieldConditions
extends RefCounted

const MAGNETIC_FLUCT_PERIOD := 47.0
const RADIANT_FLUCT_PERIOD := 113.0
const PARTICLE_FLUCT_PERIOD := 29.0
const UNSPACE_RADIANT := 0.06
## Nominal near-orbit G for rating gravitic thrust in unspace (absolute field stays much lower).
const UNSPACE_GRAVITIC_REFERENCE := 0.38
const GRAVITIC_SCALE_MAX := 1.5


class FieldSample:
	extends RefCounted

	var gravity: float = 0.0
	var magnetic: float = 0.0
	var radiant: float = 0.0
	var charged_particle: float = 0.0
	var reference_gravity: float = 0.0


static func sample(catalog: Catalog, world: WorldPresence, position: Vector2) -> FieldSample:
	var out := FieldSample.new()
	if catalog == null or world == null:
		return out

	var gst := world.gst_seconds
	if world.in_unspace:
		out.gravity = _unspace_gravity(gst)
		out.radiant = UNSPACE_RADIANT
		out.magnetic = _unspace_magnetic(gst)
		out.charged_particle = _unspace_charged_particle(gst)
		out.reference_gravity = UNSPACE_GRAVITIC_REFERENCE
		return out

	var sector := catalog.get_sector_def(world.sector_id)
	var radii := _world_radii(catalog, world.sector_id)
	var planet_radius: float = radii.planet_radius
	var ring_radius: float = radii.ring_radius
	var distance := maxf(position.length(), planet_radius)

	var surface_gravity := sector.gravity
	out.gravity = surface_gravity * pow(planet_radius / distance, 2.0)
	out.reference_gravity = surface_gravity * pow(planet_radius / ring_radius, 2.0)

	var nh := sector.neighborhood
	if nh.magnetic_surface <= 0.0:
		out.magnetic = 0.0
	else:
		var magnetic := nh.magnetic_surface * pow(planet_radius / distance, 3.0)
		if nh.magnetic_fluctuation > 0.0:
			magnetic *= 1.0 + nh.magnetic_fluctuation * sin(TAU * gst / MAGNETIC_FLUCT_PERIOD)
		out.magnetic = maxf(magnetic, 0.0)

	var radiant := nh.radiant
	if nh.radiant_fluctuation > 0.0:
		radiant *= 1.0 + nh.radiant_fluctuation * sin(TAU * gst / RADIANT_FLUCT_PERIOD)
	out.radiant = maxf(radiant, 0.0)

	var wind := nh.charged_particle
	if nh.charged_particle_fluctuation > 0.0:
		wind *= 1.0 + nh.charged_particle_fluctuation * sin(TAU * gst / PARTICLE_FLUCT_PERIOD)
	wind = maxf(wind, 0.0)

	var shield := 0.0
	if nh.charged_particle > 0.0:
		shield = out.magnetic / (out.magnetic + 0.25 * nh.charged_particle)
	out.charged_particle = wind * (1.0 - 0.85 * shield)
	return out


static func gravitic_thrust_scale(engine_type: String, sample: FieldSample) -> float:
	if engine_type != "gravitic":
		return 1.0
	if sample == null or sample.reference_gravity <= 0.0:
		return 0.0
	return clampf(sample.gravity / sample.reference_gravity, 0.0, GRAVITIC_SCALE_MAX)


static func thrust_scale_for_ship(
	catalog: Catalog,
	world: WorldPresence,
	position: Vector2,
	assembled: AssembledShip
) -> float:
	if assembled == null:
		return 1.0
	var engine := assembled.get_propulsion_module_def()
	var engine_type := engine.engine_type if engine != null else ""
	var sample := sample(catalog, world, position)
	return gravitic_thrust_scale(engine_type, sample)


static func _world_radii(catalog: Catalog, sector_id: String) -> Dictionary:
	var layout: Dictionary = catalog.get_world(sector_id)
	var planet: Dictionary = layout.get("planet", {})
	var diameter := float(planet.get("diameter", 2000.0))
	var ring: Dictionary = layout.get("orbital_ring", {})
	var gate: Dictionary = layout.get("jump_gate", {})
	return {
		"planet_radius": diameter * 0.5,
		"ring_radius": float(ring.get("radius", 1600.0)),
		"gate_radius": float(gate.get("radius", 5400.0)),
	}


static func _unspace_gravity(gst: float) -> float:
	var wave_a := sin(TAU * gst / 43.0 + 0.4)
	var wave_b := sin(TAU * gst / 59.0 + 2.1)
	var blend := 0.5 + 0.25 * wave_a + 0.25 * wave_b
	return clampf(0.005 + 0.025 * blend, 0.005, 0.03)


static func _unspace_magnetic(gst: float) -> float:
	var wave_a := sin(TAU * gst / 37.0)
	var wave_b := sin(TAU * gst / 53.0 + 1.2)
	var blend := 0.5 + 0.25 * wave_a + 0.25 * wave_b
	return clampf(0.05 + 0.6 * blend, 0.05, 0.65)


static func _unspace_charged_particle(gst: float) -> float:
	var wave_a := sin(TAU * gst / 41.0 + 0.7)
	var wave_b := sin(TAU * gst / 67.0)
	var blend := 0.5 + 0.25 * wave_a + 0.25 * wave_b
	return clampf(0.15 + 0.85 * blend, 0.15, 1.0)
