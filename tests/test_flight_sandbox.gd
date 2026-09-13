class_name TestFlightSandbox
extends RefCounted


static func run(runner: TestRunner) -> void:
	var base_script := load("res://scripts/dev/flight_sandbox_base.gd") as GDScript
	runner.check(
		base_script != null and base_script.get_global_name() == &"FlightSandboxBase",
		"FlightSandboxBase global class name"
	)
