class_name TestAsteroidShape
extends RefCounted

const AsteroidViewScript := preload("res://scripts/presentation/asteroid_view.gd")


static func run(runner: TestRunner) -> void:
	_test_deterministic_params(runner)
	_test_seed_variation(runner)
	_test_seed_spread(runner)
	_test_radius_max(runner)
	_test_composition_brightness(runner)
	_test_sun_normalisation(runner)
	_test_static_sun_direction(runner)
	_test_composition_for_seed(runner)
	_test_sun_from_star_position(runner)
	_test_asteroid_display_exposure(runner)


static func _test_deterministic_params(runner: TestRunner) -> void:
	var a := AsteroidShape.params_for(42017, AsteroidShape.COMPOSITION_STONY)
	var b := AsteroidShape.params_for(42017, AsteroidShape.COMPOSITION_STONY)
	runner.check_eq(int(a["plane_count"]), int(b["plane_count"]), "asteroid: deterministic plane_count")
	runner.check_eq(int(a["crater_count"]), int(b["crater_count"]), "asteroid: deterministic crater_count")
	var dir := Vector3(0.3, -0.6, 0.74).normalized()
	runner.check(
		absf(AsteroidShape.radius(dir, a) - AsteroidShape.radius(dir, b)) < 1e-5,
		"asteroid: deterministic radius sample"
	)


static func _test_seed_variation(runner: TestRunner) -> void:
	var p1 := AsteroidShape.params_for(101, AsteroidShape.COMPOSITION_STONY)
	var p2 := AsteroidShape.params_for(202, AsteroidShape.COMPOSITION_STONY)
	var dir := Vector3(0.2, 0.5, 0.84).normalized()
	var delta := absf(AsteroidShape.radius(dir, p1) - AsteroidShape.radius(dir, p2))
	runner.check(delta > 0.01, "asteroid: distinct seeds differ in radius")


static func _test_seed_spread(runner: TestRunner) -> void:
	var dir := Vector3(0.577, 0.577, 0.577).normalized()
	var radii: Array[float] = []
	var seeds := [11, 42, 137, 999, 42017]
	for seed_val in seeds:
		var params := AsteroidShape.params_for(seed_val, AsteroidShape.COMPOSITION_STONY)
		radii.append(AsteroidShape.radius(dir, params))
	var min_delta := INF
	for i in radii.size():
		for j in range(i + 1, radii.size()):
			min_delta = minf(min_delta, absf(radii[i] - radii[j]))
	runner.check(min_delta > 0.008, "asteroid: seed list not near-identical")


static func _test_radius_max(runner: TestRunner) -> void:
	var params := AsteroidShape.params_for(7, AsteroidShape.COMPOSITION_METALLIC)
	var max_r := float(params.get("radius_max", 0.0))
	runner.check(max_r > 0.4, "asteroid: radius_max plausible")
	var samples: Array[Vector3] = [
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.58, 0.58, 0.58).normalized(),
	]
	for sample in samples:
		runner.check(
			AsteroidShape.radius(sample, params) <= max_r + 1e-4,
			"asteroid: radius_max covers sample direction"
		)


static func _test_composition_brightness(runner: TestRunner) -> void:
	var stony := AsteroidShape.params_for(1, AsteroidShape.COMPOSITION_STONY)
	var carbon := AsteroidShape.params_for(1, AsteroidShape.COMPOSITION_CARBONACEOUS)
	var icy := AsteroidShape.params_for(1, AsteroidShape.COMPOSITION_ICY)
	var b_stony := AsteroidShape.palette_mean_brightness(stony)
	var b_carbon := AsteroidShape.palette_mean_brightness(carbon)
	var b_icy := AsteroidShape.palette_mean_brightness(icy)
	runner.check(b_carbon < b_stony, "asteroid: carbonaceous darker than stony")
	runner.check(b_icy > b_stony, "asteroid: icy brighter than stony")
	runner.check(
		float(carbon["spec_strength"]) < float(stony["spec_strength"]),
		"asteroid: carbonaceous less specular than stony"
	)


static func _test_sun_normalisation(runner: TestRunner) -> void:
	var view := AsteroidViewScript.new()
	view.configure(5, AsteroidShape.COMPOSITION_STONY, 48.0)
	view.set_sun(Vector3(3.0, 4.0, 0.0), 1.0)
	var sun := view.get_sun_direction()
	runner.check(absf(sun.length() - 1.0) < 1e-5, "asteroid view: set_sun normalises direction")
	view.set_sun(Vector3.ZERO, 1.0)
	var fallback := view.get_sun_direction()
	runner.check(fallback.length() > 0.9, "asteroid view: zero sun falls back")


static func _test_composition_for_seed(runner: TestRunner) -> void:
	runner.check_eq(
		AsteroidShape.composition_for_seed(0),
		AsteroidShape.COMPOSITION_CARBONACEOUS,
		"asteroid: composition bucket 0 carbonaceous"
	)
	runner.check_eq(
		AsteroidShape.composition_for_seed(65),
		AsteroidShape.COMPOSITION_STONY,
		"asteroid: composition bucket 65 stony"
	)
	runner.check_eq(
		AsteroidShape.composition_for_seed(95),
		AsteroidShape.COMPOSITION_METALLIC,
		"asteroid: composition bucket 95 metallic"
	)
	runner.check_eq(
		AsteroidShape.composition_for_seed(99),
		AsteroidShape.COMPOSITION_ICY,
		"asteroid: composition bucket 99 icy"
	)
	var counts := {
		AsteroidShape.COMPOSITION_CARBONACEOUS: 0,
		AsteroidShape.COMPOSITION_STONY: 0,
		AsteroidShape.COMPOSITION_METALLIC: 0,
		AsteroidShape.COMPOSITION_ICY: 0,
	}
	for seed_val in 10_000:
		var comp := AsteroidShape.composition_for_seed(seed_val)
		counts[comp] = int(counts.get(comp, 0)) + 1
	runner.check(
		absf(float(counts[AsteroidShape.COMPOSITION_CARBONACEOUS]) / 10000.0 - 0.65) < 0.02,
		"asteroid: composition mix near 65% carbonaceous"
	)
	runner.check(
		absf(float(counts[AsteroidShape.COMPOSITION_STONY]) / 10000.0 - 0.30) < 0.02,
		"asteroid: composition mix near 30% stony"
	)


static func _test_asteroid_display_exposure(runner: TestRunner) -> void:
	runner.check(
		absf(PlanetExposure.asteroid_display_exposure(1.0) - PlanetExposure.display_exposure(1.0)) < 0.001,
		"asteroid exposure: 1 AU matches planet curve"
	)
	var close_irradiance := StarAppearance.irradiance(1.0, 0.05)
	var albedo := Vector3(0.45, 0.42, 0.4)
	var close_rad := albedo * (
		PlanetExposure.asteroid_night_irradiance(close_irradiance) + close_irradiance
	)
	var close_display := PlanetExposure.asteroid_display_from_radiance(close_rad, close_irradiance)
	runner.check(close_display.x < 0.95, "asteroid exposure: close orbit below white clip")
	runner.check(close_display.x > 0.15, "asteroid exposure: close orbit stays visible")

	var pluto_irradiance := 1.0 / 900.0
	var far_rad := albedo * (
		PlanetExposure.asteroid_night_irradiance(pluto_irradiance) + pluto_irradiance
	)
	var far_display := PlanetExposure.asteroid_display_from_radiance(far_rad, pluto_irradiance)
	runner.check(far_display.x > 0.12, "asteroid exposure: distant dayside above black floor")
	runner.check(
		PlanetExposure.asteroid_display_exposure(pluto_irradiance)
			> PlanetExposure.display_exposure(pluto_irradiance),
		"asteroid exposure: far orbit gets readability boost"
	)

	var kuiper_irradiance := StarAppearance.irradiance(0.34, 85.0)
	var kuiper_rad := albedo * (
		PlanetExposure.asteroid_night_irradiance(kuiper_irradiance) + kuiper_irradiance
	)
	var kuiper_display := PlanetExposure.asteroid_display_from_radiance(kuiper_rad, kuiper_irradiance)
	runner.check(kuiper_display.x > 0.14, "asteroid exposure: outer belt stays readable")

	var view := AsteroidViewScript.new()
	view.configure(9, AsteroidShape.COMPOSITION_STONY, 48.0)
	view.set_sun(AsteroidViewScript.sun_direction_for_star_position(Vector2(100.0, -80.0)), close_irradiance)
	runner.check(
		absf(view.get_display_exposure() - PlanetExposure.asteroid_display_exposure(close_irradiance))
			< 0.01,
		"asteroid view: display_exposure tracks irradiance"
	)


static func _test_sun_from_star_position(runner: TestRunner) -> void:
	var view := AsteroidViewScript.new()
	var star_pos := Vector2(400.0, -500.0)
	view.set_sun_from_star_position(star_pos, 1.2)
	var expected := AsteroidViewScript.sun_direction_for_star_position(star_pos)
	var actual := view.get_sun_direction()
	runner.check(actual.distance_to(expected) < 1e-4, "asteroid view: star position sets canvas sun bearing")
	runner.check(
		absf(float(view.get_sun_direction().length()) - 1.0) < 1e-5,
		"asteroid view: star bearing is unit length"
	)


static func _test_static_sun_direction(runner: TestRunner) -> void:
	var view := AsteroidViewScript.new()
	var dir := view.static_sun_direction(30.0, 45.0)
	runner.check(absf(dir.length() - 1.0) < 1e-5, "asteroid view: static sun direction is unit length")
