class_name TestAudio
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_library(runner)
	_test_settings(runner)
	_test_volume_curve(runner)
	_test_gates(runner)


static func _test_library(runner: TestRunner) -> void:
	var lib := AudioLibrary.load_default()
	runner.check(lib.has_music_context("exploration"), "audio: exploration music context")
	runner.check(lib.has_ambience_context("space"), "audio: space ambience context")
	runner.check(lib.has_sfx("ship.collision"), "audio: collision sfx id")
	runner.check_eq(lib.sfx_variant_count("ship.collision"), 3, "audio: collision variants")
	runner.check(
		lib.music_track_for_context("missing_context").is_empty(),
		"audio: unknown music context has no track"
	)
	runner.check(lib.sfx_entry("not.real").is_empty(), "audio: unknown sfx entry empty")


static func _writable_settings_path() -> String:
	var project_root := ProjectSettings.globalize_path("res://")
	return project_root.path_join(".test_audio_settings_%d.json" % randi())


static func _test_settings(runner: TestRunner) -> void:
	var prior := AudioSettings.settings_path
	var temp := _writable_settings_path()
	AudioSettings.settings_path = temp

	var defaults := AudioSettings.default_volumes()
	runner.check(defaults.has("master"), "audio: default volumes include master")

	var loaded := AudioSettings.read_volumes()
	runner.check_eq(loaded["music"], defaults["music"], "audio: missing file uses defaults")

	var custom := defaults.duplicate(true)
	custom["ui"] = 0.25
	runner.check(AudioSettings.write_volumes(custom), "audio: write settings")
	var round_trip := AudioSettings.read_volumes()
	runner.check(absf(float(round_trip["ui"]) - 0.25) < 0.001, "audio: settings round-trip ui")

	if FileAccess.file_exists(temp):
		DirAccess.remove_absolute(temp)
	AudioSettings.settings_path = prior


static func _test_volume_curve(runner: TestRunner) -> void:
	runner.check_eq(AudioSettings.linear_to_bus_db(0.0), -80.0, "audio: zero linear mutes bus")
	var mid := AudioSettings.linear_to_bus_db(0.5)
	runner.check(absf(mid - linear_to_db(0.5)) < 0.01, "audio: mid linear uses linear_to_db")


static func _test_gates(runner: TestRunner) -> void:
	var gates := AudioGates.new()
	runner.check(gates.request_music("menu"), "audio: first music request accepted")
	runner.check(not gates.request_music("menu"), "audio: repeat music context ignored")
	runner.check(gates.request_music("habitat"), "audio: music context change accepted")
	runner.check_eq(gates.music_context, "habitat", "audio: music context updated")

	runner.check(gates.request_ambience("space"), "audio: first ambience request accepted")
	runner.check(not gates.request_ambience("space"), "audio: repeat ambience ignored")

	runner.check(gates.allow_sfx("ship.collision", 0.12, 1000), "audio: first sfx allowed")
	runner.check(not gates.allow_sfx("ship.collision", 0.12, 1050), "audio: sfx rate limited")
	runner.check(gates.allow_sfx("ship.collision", 0.12, 1200), "audio: sfx allowed after interval")
