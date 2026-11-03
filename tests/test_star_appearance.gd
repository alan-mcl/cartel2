class_name TestStarAppearance
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_sun_at_one_au(runner)
	_test_size_scaling(runner)
	_test_irradiance_examples(runner)
	_test_brightness_monotonic_and_clamped(runner)
	_test_disc_override(runner)
	_test_spectral_presets(runner)


static func _test_sun_at_one_au(runner: TestRunner) -> void:
	var angular := StarAppearance.angular_diameter_deg(1.0, 1.0)
	runner.check(absf(angular - 0.533) < 0.01, "star appearance: Sun angular diameter at 1 AU")
	var disc := StarAppearance.physical_disc_radius(1.0, 1.0)
	runner.check(absf(disc - 24.0) < 0.01, "star appearance: Sun disc radius at 1 AU")


static func _test_size_scaling(runner: TestRunner) -> void:
	var base := StarAppearance.physical_disc_radius(1.0, 1.0)
	var half_dist := StarAppearance.physical_disc_radius(1.0, 2.0)
	var double_radius := StarAppearance.physical_disc_radius(2.0, 1.0)
	runner.check(absf(half_dist - base * 0.5) < 0.01, "star appearance: half distance halves disc")
	runner.check(absf(double_radius - base * 2.0) < 0.01, "star appearance: double radius doubles disc")


static func _test_irradiance_examples(runner: TestRunner) -> void:
	runner.check(absf(StarAppearance.irradiance(1.0, 1.0) - 1.0) < 0.001, "star appearance: irradiance Sun 1 AU")
	runner.check(absf(StarAppearance.irradiance(1.0, 2.0) - 0.25) < 0.001, "star appearance: irradiance 2 AU")
	runner.check(
		absf(StarAppearance.irradiance(4.0, 2.0) - 1.0) < 0.001,
		"star appearance: irradiance 4 L at 2 AU"
	)


static func _test_brightness_monotonic_and_clamped(runner: TestRunner) -> void:
	var low := StarAppearance.apparent_brightness(0.01)
	var mid := StarAppearance.apparent_brightness(1.0)
	var high := StarAppearance.apparent_brightness(400.0)
	runner.check(mid > low, "star appearance: brightness increases with irradiance")
	runner.check(high >= mid, "star appearance: high irradiance not dimmer than mid")
	runner.check(high <= 1.0 + 0.001, "star appearance: tone-mapped brightness capped near 1")
	runner.check(low >= 0.0, "star appearance: brightness non-negative")


static func _test_disc_override(runner: TestRunner) -> void:
	var resolved := StarAppearance.resolve(
		{"temperature_k": 5800.0, "luminosity": 1.0, "disc_radius": 3.0},
		1.0,
		1.0
	)
	runner.check(absf(float(resolved.get("disc_radius", 0.0)) - 3.0) < 0.01, "star appearance: display disc override")
	runner.check(
		absf(float(resolved.get("physical_disc_radius", 0.0)) - 24.0) < 0.01,
		"star appearance: physical disc unchanged by override"
	)
	runner.check(
		absf(float(resolved.get("irradiance", 0.0)) - 1.0) < 0.001,
		"star appearance: irradiance unchanged by disc override"
	)


static func _test_spectral_presets(runner: TestRunner) -> void:
	var m_data := {"temperature_k": 3000.0, "luminosity": 0.01, "spectral_class": "M5V"}
	var b_data := {"temperature_k": 12000.0, "luminosity": 100.0, "spectral_class": "B8IV"}
	var m := StarAppearance.resolve(m_data, 1.0, 0.2)
	var b := StarAppearance.resolve(b_data, 1.0, 4.0)
	var m_style: Dictionary = m.get("style", {})
	var b_style: Dictionary = b.get("style", {})
	runner.check(
		float(m_style.get("corona_radius_multiplier", 0.0))
			< float(b_style.get("corona_radius_multiplier", 0.0)),
		"star appearance: M corona multiplier below B"
	)
	var m_disc := float(m.get("disc_radius", 0.0))
	var b_disc := float(b.get("disc_radius", 0.0))
	runner.check(
		absf(m_disc - StarAppearance.physical_disc_radius(0.2, 1.0)) < 0.01,
		"star appearance: M disc from radius over AU"
	)
	runner.check(
		absf(b_disc - StarAppearance.physical_disc_radius(4.0, 1.0)) < 0.01,
		"star appearance: B disc from radius over AU not preset"
	)
