extends SceneTree


func _init() -> void:
	var runner := TestRunner.new()
	TestCatalog.run(runner)
	TestUiRegistry.run(runner)
	TestSession.run(runner)
	TestSave.run(runner)
	TestAssembler.run(runner)
	TestCombat.run(runner)
	TestSensors.run(runner)
	TestFieldConditions.run(runner)
	TestEconomy.run(runner)
	TestCommodityCargo.run(runner)
	TestClock.run(runner)
	TestSimulation.run(runner)
	TestEvents.run(runner)
	TestMissions.run(runner)
	TestFreight.run(runner)
	TestTraffic.run(runner)
	TestCorporatePresence.run(runner)
	TestShipSim.run(runner)
	TestShipVisual.run(runner)
	TestPresentation.run(runner)
	TestFlightSandbox.run(runner)
	TestMotion.run(runner)
	TestDebris.run(runner)
	TestMessageBar.run(runner, self)

	if runner.failures > 0:
		print("=== %d test failure(s) ===" % runner.failures)
		quit(1)
	else:
		print("=== all tests passed ===")
		quit(0)
