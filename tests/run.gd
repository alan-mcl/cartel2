extends SceneTree


func _init() -> void:
	var runner := TestRunner.new()
	TestCatalog.run(runner)
	TestSession.run(runner)
	TestAssembler.run(runner)

	if runner.failures > 0:
		print("=== %d test failure(s) ===" % runner.failures)
		quit(1)
	else:
		print("=== all tests passed ===")
		quit(0)
