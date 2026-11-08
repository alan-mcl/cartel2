class_name TestAreaRadar
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_visual_and_grid(runner, catalog)
	_test_one_entry_per_sensor_module(runner, catalog)
	_test_shared_ranges_merged(runner)
	_test_view_half_extent(runner, catalog)
	_test_no_local_sensor_empty_modules(runner)
	_test_sensor_drone_offset_circle(runner, catalog)


static func _assembled_with_sensors(modules: Array) -> AssembledShip:
	var assembled := AssembledShip.new()
	assembled.chassis = {"mass": 3.2}
	assembled.envelope = {"dry_mass": 3.2}
	assembled.capabilities = {"local_sensor": true}
	assembled.installed_modules = modules.duplicate(true)
	return assembled


static func _sensor_module_entry(module_data: Dictionary) -> Dictionary:
	var payload := {
		"id": "test_sensor",
		"name": "Test Sensor",
		"maker": "Test",
		"category": "sensor",
		"mass": 0.3,
		"volume": 0.3,
		"cost": 1,
		"description": "Test",
		"capabilities": ["local_sensor", "basic_target_lock"],
		"signature": {},
		"sensor_range": 6500.0,
	}
	for key in module_data.keys():
		payload[key] = module_data[key]
	var module_def := ModuleDef.from_dict(payload)
	return {
		"slot": "system_1",
		"module_id": module_def.id,
		"data": module_def,
	}


static func _test_visual_and_grid(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := _assembled_with_sensors([_sensor_module_entry({"id": "s1", "name": "Alpha"})])
	var snapshot := AreaRadar.build_snapshot(assembled, null, catalog)
	runner.check_eq(float(snapshot.get("grid_step_m", 0.0)), 500.0, "area radar grid step is 500 m")
	var circles: Array = snapshot.get("circles", [])
	runner.check(circles.size() >= 2, "area radar includes visual and sensor circles")
	runner.check_eq(str(circles[0].get("kind", "")), "visual", "first circle is visual")
	var visual_catalog := float(catalog.get_traffic_config().get("visual_contact_radius", 250.0))
	runner.check_eq(float(circles[0].get("range_m", -1.0)), visual_catalog, "visual range matches catalog")


static func _test_one_entry_per_sensor_module(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := _assembled_with_sensors([
		_sensor_module_entry({"id": "s1", "name": "Alpha", "sensor_range": 6000.0}),
		_sensor_module_entry({"id": "s2", "name": "Beta", "sensor_range": 7200.0}),
	])
	var snapshot := AreaRadar.build_snapshot(assembled, null, catalog)
	var sensor_circles := 0
	for circle_variant in snapshot.get("circles", []):
		if typeof(circle_variant) != TYPE_DICTIONARY:
			continue
		if str(circle_variant.get("kind", "")) == "sensor":
			sensor_circles += 1
	runner.check_eq(sensor_circles, 2, "distinct sensor ranges produce two sensor circles")


static func _test_shared_ranges_merged(runner: TestRunner) -> void:
	var assembled := _assembled_with_sensors([
		_sensor_module_entry({"id": "s1", "name": "Alpha", "sensor_range": 6500.0}),
		_sensor_module_entry({"id": "s2", "name": "Beta", "sensor_range": 6500.5}),
	])
	var snapshot := AreaRadar.build_snapshot(assembled, null, null)
	var sensor_circles := 0
	var merged_labels := PackedStringArray()
	for circle_variant in snapshot.get("circles", []):
		if typeof(circle_variant) != TYPE_DICTIONARY:
			continue
		if str(circle_variant.get("kind", "")) != "sensor":
			continue
		sensor_circles += 1
		merged_labels = circle_variant.get("labels", PackedStringArray())
	runner.check_eq(sensor_circles, 1, "ranges within 1 m merge to one circle")
	runner.check(merged_labels.size() >= 2, "merged legend lists both module names")


static func _test_view_half_extent(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := _assembled_with_sensors([
		_sensor_module_entry({"id": "s1", "name": "Alpha", "sensor_range": 8000.0}),
	])
	var snapshot := AreaRadar.build_snapshot(assembled, null, catalog)
	var half_extent := float(snapshot.get("view_half_extent_m", 0.0))
	runner.check(half_extent > 8000.0, "view half extent exceeds max sensor range")
	runner.check(half_extent <= 8000.0 * 1.13, "view half extent uses margin factor")


static func _test_no_local_sensor_empty_modules(runner: TestRunner) -> void:
	var assembled := AssembledShip.new()
	assembled.capabilities = {}
	var snapshot := AreaRadar.build_snapshot(assembled, null, null)
	var sensor_circles := 0
	for circle_variant in snapshot.get("circles", []):
		if typeof(circle_variant) != TYPE_DICTIONARY:
			continue
		if str(circle_variant.get("kind", "")) == "sensor":
			sensor_circles += 1
	runner.check_eq(sensor_circles, 0, "no local_sensor means no sensor circles")
	runner.check(snapshot.get("circles", []).size() >= 1, "visual circle still present")


static func _test_sensor_drone_offset_circle(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := _assembled_with_sensors([_sensor_module_entry({"id": "s1", "name": "Alpha"})])
	var owned := OwnedShip.new()
	owned.deployed_drone = {
		"active": true,
		"slot": "light_weapon_1",
		"module_id": "merc_lark_survey",
		"task": DroneDirector.TASK_SENSOR,
		"position": {"x": 5000.0, "y": -200.0},
		"velocity": {"x": 0.0, "y": 0.0},
		"facing": 0.0,
	}
	var ship_pos := Vector2.ZERO
	var snapshot := AreaRadar.build_snapshot(assembled, null, catalog)
	AreaRadar.append_sensor_drone_circle(snapshot, catalog, owned, ship_pos, 1.0, true)
	var found := false
	for circle_variant in snapshot.get("circles", []):
		if typeof(circle_variant) != TYPE_DICTIONARY:
			continue
		var circle: Dictionary = circle_variant
		if not circle.has("origin"):
			continue
		found = true
		runner.check(float(circle.get("range_m", 0.0)) > 1000.0, "drone circle carries module sensor range")
		var origin: Dictionary = circle.get("origin", {})
		runner.check_eq(
			float(origin.get("x", -1.0)),
			5000.0,
			"drone circle origin matches airframe"
		)
	runner.check(found, "sensor drone adds offset circle to snapshot")
	runner.check(
		float(snapshot.get("view_half_extent_m", 0.0)) > 5000.0,
		"view extent grows for offset drone envelope"
	)
