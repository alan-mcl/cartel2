extends SceneTree

## Headless runner for `TestEconomy` only.


func _init() -> void:
	var runner := TestRunner.new()
	TestEconomy.run(runner)
	if runner.failures > 0:
		print("=== %d economy test failure(s) ===" % runner.failures)
		quit(1)
	else:
		print("=== economy tests passed ===")
		quit(0)
