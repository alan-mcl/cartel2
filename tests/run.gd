extends SceneTree


func _init() -> void:
	var runner := TestRunner.new()
	var filter := _parse_suite_filter()
	if filter.has("__error__"):
		quit(1)
		return
	var unknown := _unknown_suite_names(filter)
	if not unknown.is_empty():
		push_error("Unknown --suite name(s): %s" % ", ".join(unknown))
		print("Unknown --suite name(s): %s" % ", ".join(unknown))
		quit(1)
		return
	var suites: Array = _suite_entries(runner)
	for entry_variant in suites:
		var entry: Dictionary = entry_variant
		var name: String = str(entry.get("name", ""))
		if not filter.is_empty() and not filter.has(name):
			continue
		var t0 := Time.get_ticks_msec()
		(entry["run"] as Callable).call()
		print("SUITE: %s %d ms" % [name, Time.get_ticks_msec() - t0])

	if runner.failures > 0:
		print("=== %d test failure(s) ===" % runner.failures)
		quit(1)
	else:
		print("=== all tests passed ===")
		quit(0)


func _parse_suite_filter() -> Dictionary:
	var out := {}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--suite":
			if i + 1 >= args.size():
				push_error("--suite requires a class name")
				return {"__error__": true}
			out[str(args[i + 1])] = true
			i += 2
		else:
			i += 1
	return out


func _unknown_suite_names(filter: Dictionary) -> PackedStringArray:
	if filter.has("__error__"):
		return PackedStringArray()
	var known := {}
	for e in _suite_entries(TestRunner.new()):
		known[str((e as Dictionary).get("name", ""))] = true
	var bad: PackedStringArray = PackedStringArray()
	for k in filter.keys():
		if not known.has(str(k)):
			bad.append(str(k))
	return bad


func _suite_entries(runner: TestRunner) -> Array:
	return [
		{"name": "TestCatalog", "run": func() -> void: TestCatalog.run(runner)},
		{"name": "TestPopulationSplit", "run": func() -> void: TestPopulationSplit.run(runner)},
		{"name": "TestAudio", "run": func() -> void: TestAudio.run(runner)},
		{"name": "TestUiRegistry", "run": func() -> void: TestUiRegistry.run(runner)},
		{"name": "TestLibrary", "run": func() -> void: TestLibrary.run(runner)},
		{"name": "TestGameScreen", "run": func() -> void: TestGameScreen.run(runner, self)},
		{"name": "TestSession", "run": func() -> void: TestSession.run(runner)},
		{"name": "TestDealerStock", "run": func() -> void: TestDealerStock.run(runner)},
		{"name": "TestDeskCharterBoards", "run": func() -> void: TestDeskCharterBoards.run(runner)},
		{"name": "TestTranslation", "run": func() -> void: TestTranslation.run(runner)},
		{"name": "TestVolatileTranslation", "run": func() -> void: TestVolatileTranslation.run(runner)},
		{"name": "TestSave", "run": func() -> void: TestSave.run(runner)},
		{"name": "TestCareer", "run": func() -> void: TestCareer.run(runner)},
		{"name": "TestCareerDeath", "run": func() -> void: TestCareerDeath.run(runner)},
		{"name": "TestSanctions", "run": func() -> void: TestSanctions.run(runner)},
		{"name": "TestRepairs", "run": func() -> void: TestRepairs.run(runner)},
		{"name": "TestAssembler", "run": func() -> void: TestAssembler.run(runner, self)},
		{"name": "TestCombat", "run": func() -> void: TestCombat.run(runner)},
		{"name": "TestDrones", "run": func() -> void: TestDrones.run(runner)},
		{"name": "TestCombatPersistence", "run": func() -> void: TestCombatPersistence.run(runner)},
		{"name": "TestBallisticHit", "run": func() -> void: TestBallisticHit.run(runner)},
		{"name": "TestProjectGuidance", "run": func() -> void: TestProjectGuidance.run(runner)},
		{"name": "TestSensors", "run": func() -> void: TestSensors.run(runner)},
		{"name": "TestAreaRadar", "run": func() -> void: TestAreaRadar.run(runner)},
		{"name": "TestTargetLock", "run": func() -> void: TestTargetLock.run(runner)},
		{"name": "TestTargetScan", "run": func() -> void: TestTargetScan.run(runner)},
		{"name": "TestAutopilot", "run": func() -> void: TestAutopilot.run(runner)},
		{"name": "TestFieldConditions", "run": func() -> void: TestFieldConditions.run(runner)},
		{"name": "TestHyperdrive", "run": func() -> void: TestHyperdrive.run(runner)},
		{"name": "TestUnspaceFlux", "run": func() -> void: TestUnspaceFlux.run(runner)},
		{"name": "TestUnspaceFold", "run": func() -> void: TestUnspaceFold.run(runner)},
		{"name": "TestUnspaceShards", "run": func() -> void: TestUnspaceShards.run(runner)},
		{"name": "TestUnspaceAscidianHazards", "run": func() -> void: TestUnspaceAscidianHazards.run(runner)},
		{"name": "TestEconomy", "run": func() -> void: TestEconomy.run(runner)},
		{"name": "TestCommodityCargo", "run": func() -> void: TestCommodityCargo.run(runner)},
		{"name": "TestCargoRequirements", "run": func() -> void: TestCargoRequirements.run(runner)},
		{"name": "TestClock", "run": func() -> void: TestClock.run(runner)},
		{"name": "TestSimulation", "run": func() -> void: TestSimulation.run(runner)},
		{"name": "TestEvents", "run": func() -> void: TestEvents.run(runner)},
		{"name": "TestMissions", "run": func() -> void: TestMissions.run(runner)},
		{"name": "TestBarRound", "run": func() -> void: TestBarRound.run(runner)},
		{"name": "TestTranslationMarket", "run": func() -> void: TestTranslationMarket.run(runner)},
		{"name": "TestCharterResolution", "run": func() -> void: TestCharterResolution.run(runner)},
		{"name": "TestCharterBoard", "run": func() -> void: TestCharterBoard.run(runner)},
		{"name": "TestScanCharters", "run": func() -> void: TestScanCharters.run(runner)},
		{"name": "TestBountyCharters", "run": func() -> void: TestBountyCharters.run(runner)},
		{"name": "TestRetrievalCharters", "run": func() -> void: TestRetrievalCharters.run(runner)},
		{"name": "TestFreight", "run": func() -> void: TestFreight.run(runner)},
		{"name": "TestCharterHopsDeadlines", "run": func() -> void: TestCharterHopsDeadlines.run(runner)},
		{"name": "TestTraffic", "run": func() -> void: TestTraffic.run(runner, self)},
		{"name": "TestCorporatePresence", "run": func() -> void: TestCorporatePresence.run(runner)},
		{"name": "TestShipSim", "run": func() -> void: TestShipSim.run(runner)},
		{"name": "TestShipVisual", "run": func() -> void: TestShipVisual.run(runner)},
		{"name": "TestPresentation", "run": func() -> void: TestPresentation.run(runner)},
		{"name": "TestStarfieldTiling", "run": func() -> void: TestStarfieldTiling.run(runner)},
		{"name": "TestStarAppearance", "run": func() -> void: TestStarAppearance.run(runner)},
		{"name": "TestPlanetSurfaceLabels", "run": func() -> void: TestPlanetSurfaceLabels.run(runner)},
		{"name": "TestSkyBackdrop", "run": func() -> void: TestSkyBackdrop.run(runner, self)},
		{"name": "TestAsteroidShape", "run": func() -> void: TestAsteroidShape.run(runner)},
		{"name": "TestFlightSandbox", "run": func() -> void: TestFlightSandbox.run(runner)},
		{"name": "TestMotion", "run": func() -> void: TestMotion.run(runner)},
		{"name": "TestDebris", "run": func() -> void: TestDebris.run(runner)},
		{"name": "TestMessageBar", "run": func() -> void: TestMessageBar.run(runner, self)},
		{"name": "TestMessageEmitters", "run": func() -> void: TestMessageEmitters.run(runner)},
		{"name": "TestPlotlines", "run": func() -> void: TestPlotlines.run(runner)},
		{"name": "TestEncounters", "run": func() -> void: TestEncounters.run(runner)},
		{"name": "TestCorporateOfficeTape", "run": func() -> void: TestCorporateOfficeTape.run(runner)},
		{"name": "TestExchangePriceTape", "run": func() -> void: TestExchangePriceTape.run(runner)},
		{"name": "TestFuel", "run": func() -> void: TestFuel.run(runner)},
		{"name": "TestFlightManifest", "run": func() -> void: TestFlightManifest.run(runner)},
		{"name": "TestBalanceMetrics", "run": func() -> void: TestBalanceMetrics.run(runner)},
		{"name": "TestWeaponMountBands", "run": func() -> void: TestWeaponMountBands.run(runner)},
		{"name": "TestTemplatePower", "run": func() -> void: TestTemplatePower.run(runner)},
		{"name": "TestModuleDominance", "run": func() -> void: TestModuleDominance.run(runner)},
	]
