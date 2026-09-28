class_name TestFieldConditions
extends RefCounted

const TOL := 0.02


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_proxima_gravity(runner, catalog)
	_test_titania_magnetic(runner, catalog)
	_test_magnetosphere_shielding(runner, catalog)
	_test_tycho_magnetic_fluctuation(runner, catalog)
	_test_unspace_profile(runner, catalog)
	_test_gravitic_engine_scale(runner, catalog)
	_test_integrated_sail_scale(runner, catalog)
	_test_non_gravitic_engine_scale(runner, catalog)


static func _world(catalog: Catalog, sector_id: String) -> WorldPresence:
	var world := WorldPresence.new()
	world.sector_id = sector_id
	world.in_unspace = false
	world.gst_seconds = 0.0
	return world


static func _world_unspace(catalog: Catalog, gst: float) -> WorldPresence:
	var world := WorldPresence.new()
	world.in_unspace = true
	world.gst_seconds = gst
	return world


static func _radii(catalog: Catalog) -> Dictionary:
	return FieldConditions._world_radii(catalog, "proxima")


static func _test_proxima_gravity(runner: TestRunner, catalog: Catalog) -> void:
	var world := _world(catalog, "proxima")
	var radii := _radii(catalog)
	var R: float = radii.planet_radius
	var ring: float = radii.ring_radius
	var gate: float = radii.gate_radius

	var at_limb := FieldConditions.sample(catalog, world, Vector2(R, 0.0))
	runner.check(
		absf(at_limb.gravity - 0.98) < TOL,
		"proxima gravity at limb ~0.98 G"
	)

	var at_ring := FieldConditions.sample(catalog, world, Vector2(ring, 0.0))
	var expected_ring := 0.98 * pow(R / ring, 2.0)
	runner.check(
		absf(at_ring.gravity - expected_ring) < TOL,
		"proxima gravity at habitat ring matches inverse-square"
	)

	var at_gate := FieldConditions.sample(catalog, world, Vector2(gate, 0.0))
	var expected_gate := 0.98 * pow(R / gate, 2.0)
	runner.check(
		absf(at_gate.gravity - expected_gate) < TOL,
		"proxima gravity at jump gate matches inverse-square"
	)


static func _test_titania_magnetic(runner: TestRunner, catalog: Catalog) -> void:
	var world := _world(catalog, "titania")
	var radii := FieldConditions._world_radii(catalog, "titania")
	var ring: float = radii.ring_radius
	var sample := FieldConditions.sample(catalog, world, Vector2(ring, 0.0))
	runner.check_eq(sample.magnetic, 0.0, "titania has no intrinsic magnetic dipole")
	runner.check(sample.charged_particle > 0.5, "titania particles not fully magnetically shielded")


static func _test_magnetosphere_shielding(runner: TestRunner, catalog: Catalog) -> void:
	var world := _world(catalog, "proxima")
	var radii := _radii(catalog)
	var ring: float = radii.ring_radius
	var gate: float = radii.gate_radius
	var at_ring := FieldConditions.sample(catalog, world, Vector2(ring, 0.0))
	var at_gate := FieldConditions.sample(catalog, world, Vector2(gate, 0.0))
	runner.check(
		at_ring.charged_particle < at_gate.charged_particle,
		"magnetic world has lower particle flux near planet than at gate"
	)


static func _test_tycho_magnetic_fluctuation(runner: TestRunner, catalog: Catalog) -> void:
	var world_a := _world(catalog, "tycho")
	world_a.gst_seconds = 0.0
	var world_b := _world(catalog, "tycho")
	world_b.gst_seconds = 120.0
	var pos := Vector2(1600.0, 0.0)
	var ty_a := FieldConditions.sample(catalog, world_a, pos)
	var ty_b := FieldConditions.sample(catalog, world_b, pos)
	runner.check(
		absf(ty_a.magnetic - ty_b.magnetic) > 0.05,
		"tycho magnetic field changes with GST"
	)

	var prox_world_a := _world(catalog, "proxima")
	var prox_world_b := _world(catalog, "proxima")
	prox_world_b.gst_seconds = 120.0
	var prox_a := FieldConditions.sample(catalog, prox_world_a, pos)
	var prox_b := FieldConditions.sample(catalog, prox_world_b, pos)
	runner.check(
		absf(prox_a.magnetic - prox_b.magnetic) < TOL,
		"proxima magnetic field steady when fluctuation is zero"
	)


static func _test_unspace_profile(runner: TestRunner, catalog: Catalog) -> void:
	var a := FieldConditions.sample(catalog, _world_unspace(catalog, 0.0), Vector2.ZERO)
	runner.check(a.gravity >= 0.005 and a.gravity <= 0.03, "unspace gravity in low band")
	runner.check(
		absf(a.radiant - FieldConditions.UNSPACE_RADIANT) < TOL,
		"unspace radiant constant"
	)

	var b := FieldConditions.sample(catalog, _world_unspace(catalog, 500.0), Vector2.ZERO)
	runner.check(
		absf(a.gravity - b.gravity) > 0.001,
		"unspace gravity fluctuates"
	)
	runner.check(
		absf(a.magnetic - b.magnetic) > 0.01,
		"unspace magnetic fluctuates"
	)
	runner.check(
		absf(a.charged_particle - b.charged_particle) > 0.01,
		"unspace particles fluctuate"
	)
	runner.check(a.magnetic >= 0.05 and a.magnetic <= 0.65, "unspace magnetic in range")
	runner.check(
		a.charged_particle >= 0.15 and a.charged_particle <= 1.0,
		"unspace particles in range"
	)


static func _test_gravitic_engine_scale(runner: TestRunner, catalog: Catalog) -> void:
	var world := _world(catalog, "proxima")
	var radii := _radii(catalog)
	var R: float = radii.planet_radius
	var ring: float = radii.ring_radius
	var gate: float = radii.gate_radius

	var ring_sample := FieldConditions.sample(catalog, world, Vector2(ring, 0.0))
	var ring_scale := FieldConditions.gravitic_thrust_scale("gravitic", ring_sample)
	runner.check(absf(ring_scale - 1.0) < TOL, "gravitic scale ~1 at habitat ring")

	var gate_sample := FieldConditions.sample(catalog, world, Vector2(gate, 0.0))
	var gate_scale := FieldConditions.gravitic_thrust_scale("gravitic", gate_sample)
	runner.check(gate_scale < 0.15, "gravitic scale weak at jump gate")

	var limb_sample := FieldConditions.sample(catalog, world, Vector2(R, 0.0))
	var limb_scale := FieldConditions.gravitic_thrust_scale("gravitic", limb_sample)
	runner.check(absf(limb_scale - 1.5) < TOL, "gravitic scale capped at 1.5 at limb")

	var unspace_sample := FieldConditions.sample(
		catalog,
		_world_unspace(catalog, 0.0),
		Vector2.ZERO
	)
	var unspace_scale := FieldConditions.gravitic_thrust_scale("gravitic", unspace_sample)
	runner.check(unspace_scale > 0.0, "gravitic scale non-zero in unspace")
	runner.check(unspace_scale < 0.12, "gravitic scale weak in unspace")


static func _test_integrated_sail_scale(runner: TestRunner, catalog: Catalog) -> void:
	var world := _world(catalog, "proxima")
	var radii := _radii(catalog)
	var ring: float = radii.ring_radius

	var ring_sample := FieldConditions.sample(catalog, world, Vector2(ring, 0.0))
	var ring_scale := FieldConditions.integrated_sail_thrust_scale("integrated_sail", ring_sample)
	runner.check(absf(ring_scale - 1.0) < TOL, "sail scale ~1 at proxima habitat ring")

	var unspace_sample := FieldConditions.sample(
		catalog,
		_world_unspace(catalog, 0.0),
		Vector2.ZERO
	)
	var unspace_scale := FieldConditions.integrated_sail_thrust_scale("integrated_sail", unspace_sample)
	runner.check(unspace_scale > 0.0, "sail scale non-zero in unspace")
	runner.check(unspace_scale < 0.5, "sail scale weak in unspace")

	var titania_world := _world(catalog, "titania")
	var titania_radii := FieldConditions._world_radii(catalog, "titania")
	var titania_ring := float(titania_radii.ring_radius)
	var titania_sample := FieldConditions.sample(
		catalog,
		titania_world,
		Vector2(titania_ring, 0.0)
	)
	var titania_scale := FieldConditions.integrated_sail_thrust_scale("integrated_sail", titania_sample)
	runner.check(titania_scale > 0.35, "sail still works on titania without magnetic dipole")


static func _test_non_gravitic_engine_scale(runner: TestRunner, catalog: Catalog) -> void:
	var sample := FieldConditions.sample(catalog, _world(catalog, "proxima"), Vector2(1000.0, 0.0))
	runner.check_eq(
		FieldConditions.environment_thrust_scale("direct_fusion", sample),
		1.0,
		"direct fusion ignores field scale"
	)
	runner.check_eq(
		FieldConditions.integrated_sail_thrust_scale("direct_fusion", sample),
		1.0,
		"direct fusion ignores sail scale helper"
	)
