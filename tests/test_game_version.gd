class_name TestGameVersion
extends RefCounted


static func run(runner: TestRunner) -> void:
	var project_version := str(
		ProjectSettings.get_setting("application/config/version", "")
	).strip_edges()
	runner.check_eq(
		GameVersion.VERSION,
		project_version,
		"GameVersion.VERSION matches project.godot config/version"
	)