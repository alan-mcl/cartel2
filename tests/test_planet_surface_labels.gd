class_name TestPlanetSurfaceLabels
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_path_and_parse(runner)
	_test_projection(runner)
	_test_proxima_sidecar(runner)


static func _test_path_and_parse(runner: TestRunner) -> void:
	runner.check_eq(
		PlanetSurfaceLabels.habitations_path_for_night("res://assets/world/planets/proxima_night.png"),
		"res://assets/world/planets/proxima_night_habitations.json",
		"surface labels: night path maps to the habitations sidecar"
	)
	runner.check_eq(
		PlanetSurfaceLabels.habitations_path_for_night("res://assets/world/planets/proxima_albedo.png"),
		"",
		"surface labels: non-night paths have no sidecar"
	)
	var anchors := PlanetSurfaceLabels.anchors_from_data({
		"anchors": [
			{"name": " Concord ", "local": [0.0, 0.0, 1.0]},
			{"name": "", "local": [1.0, 0.0, 0.0]},
			{"name": "Broken", "local": [1.0]},
			{"name": "Zero", "local": [0.0, 0.0, 0.0]},
		],
	})
	runner.check_eq(anchors.size(), 1, "surface labels: parse keeps one valid anchor")
	if anchors.is_empty():
		return
	runner.check_eq(str(anchors[0]["name"]), "Concord", "surface labels: parse trims the name")


static func _test_projection(runner: TestRunner) -> void:
	var diameter := PlanetSurfaceLabels.CAMERA_VIEW_HEIGHT
	var facing: Variant = PlanetSurfaceLabels.project_offset(Vector3(0.0, 0.0, 1.0), 0.0, 0.0, diameter)
	runner.check(facing is Vector2, "surface labels: camera-facing point is visible")
	if facing is Vector2:
		runner.check(
			(facing as Vector2).length() < 0.001,
			"surface labels: camera-facing point sits at the disc centre"
		)
	runner.check(
		PlanetSurfaceLabels.project_offset(Vector3(0.0, 0.0, -1.0), 0.0, 0.0, diameter) == null,
		"surface labels: far side is hidden"
	)
	var east_local := Vector3(0.6, 0.0, 0.8)
	var east: Variant = PlanetSurfaceLabels.project_offset(east_local, 0.0, 0.0, diameter)
	runner.check(
		east is Vector2 and (east as Vector2).distance_to(Vector2(0.6, 0.0)) < 0.001,
		"surface labels: +X component lands on +X of the flight plane"
	)
	var north_local := Vector3(0.0, 0.6, 0.8)
	var north: Variant = PlanetSurfaceLabels.project_offset(north_local, 0.0, 0.0, diameter)
	runner.check(
		north is Vector2 and (north as Vector2).distance_to(Vector2(0.0, -0.6)) < 0.001,
		"surface labels: +Y component lands up on the flight plane"
	)
	runner.check(
		PlanetSurfaceLabels.project_offset(Vector3(0.0, 0.0, 1.0), 0.0, PI, diameter) == null,
		"surface labels: half a turn carries the near point to the far side"
	)


static func _test_proxima_sidecar(runner: TestRunner) -> void:
	var anchors := PlanetSurfaceLabels.load_anchors(
		"res://assets/world/planets/proxima_night_habitations.json"
	)
	runner.check(anchors.size() >= 6, "surface labels: Proxima sidecar has the named city-malls")
	if anchors.is_empty():
		return
	runner.check_eq(str(anchors[0]["name"]), "Concord", "surface labels: Proxima's largest metro is Concord")
	var local: Vector3 = anchors[0]["local"]
	runner.check(absf(local.length() - 1.0) < 0.001, "surface labels: Proxima local is a unit direction")
