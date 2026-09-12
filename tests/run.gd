extends SceneTree


func _init() -> void:
	var runner := TestRunner.new()
	TestCatalog.run(runner)
	TestSession.run(runner)
	TestSave.run(runner)
	TestAssembler.run(runner)
	TestCombat.run(runner)
	TestSensors.run(runner)
	TestEconomy.run(runner)
	TestClock.run(runner)
	TestSimulation.run(runner)
	TestEvents.run(runner)
	TestMissions.run(runner)
	TestTraffic.run(runner)
	TestMotion.run(runner)

	if runner.failures > 0:
		print("=== %d test failure(s) ===" % runner.failures)
		quit(1)
	else:
		print("=== all tests passed ===")
		quit(0)
