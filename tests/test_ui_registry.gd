class_name TestUiRegistry
extends RefCounted


static func run(runner: TestRunner) -> void:
	runner.check_eq(
		BuildingPanelRegistry.mode_for("shipyard"),
		BuildingPanelRegistry.MODE_STACK,
		"shipyard uses stack mode"
	)
	runner.check(
		BuildingPanelRegistry.stack_scene("shipyard") != null,
		"shipyard has stack scene"
	)

	for embed_type in ["terminal", "market", "ship_dealer", "chassis_dealer"]:
		runner.check_eq(
			BuildingPanelRegistry.mode_for(embed_type),
			BuildingPanelRegistry.MODE_EMBED,
			"%s uses embed mode" % embed_type
		)

	runner.check_eq(
		BuildingPanelRegistry.mode_for("bar"),
		BuildingPanelRegistry.MODE_PLACEHOLDER,
		"bar uses placeholder mode"
	)
	runner.check_eq(
		BuildingPanelRegistry.mode_for("comms"),
		BuildingPanelRegistry.MODE_PLACEHOLDER,
		"unknown type uses placeholder mode"
	)
