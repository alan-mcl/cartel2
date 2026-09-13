class_name TestUiRegistry
extends RefCounted

static func run(runner: TestRunner) -> void:
	var game_screen_script := load("res://scripts/ui/game_screen.gd") as GDScript
	runner.check(
		game_screen_script != null and game_screen_script.get_global_name() == &"GameScreen",
		"GameScreen global class name"
	)

	for embed_type in ["terminal", "market", "ship_dealer", "chassis_dealer", "shipyard"]:
		runner.check_eq(
			BuildingPanelRegistry.mode_for(embed_type),
			BuildingPanelRegistry.MODE_EMBED,
			"%s uses embed mode" % embed_type
		)
		runner.check(
			BuildingPanelRegistry.embed_scene(embed_type) != null,
			"%s has embed scene" % embed_type
		)

	runner.check_eq(
		BuildingPanelRegistry.embed_scene_path("ship_dealer"),
		BuildingPanelRegistry.embed_scene_path("chassis_dealer"),
		"ship and chassis dealers share dealer_panel scene"
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
