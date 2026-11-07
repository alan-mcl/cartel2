class_name TestDeskCharterBoards
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_weighted_splits(runner)
	_test_peacekeeping_desk_total(runner)
	_test_bar_desk_total(runner)


static func _test_weighted_splits(runner: TestRunner) -> void:
	var dual_scan := 0
	var dual_bounty := 0
	var dual_retrieval := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for _i in 1000:
		var split := DeskCharterBoards.split_dual_desk(1, rng)
		dual_scan += int(split["scan"])
		dual_bounty += int(split["bounty"])
		dual_retrieval += int(split["retrieval"])
	runner.check(dual_scan >= 350 and dual_scan <= 450, "desk mix: dual scan near 40%")
	runner.check(dual_bounty >= 350 and dual_bounty <= 450, "desk mix: dual bounty near 40%")
	runner.check(dual_retrieval >= 150 and dual_retrieval <= 250, "desk mix: dual retrieval near 20%")

	var bar_passenger := 0
	var bar_freight := 0
	var bar_scan := 0
	var bar_bounty := 0
	var bar_retrieval := 0
	rng.seed = 99
	for _i in 2000:
		var bar := DeskCharterBoards.split_bar_desk(1, rng)
		bar_passenger += int(bar["passenger"])
		bar_freight += int(bar["freight"])
		bar_scan += int(bar["scan"])
		bar_bounty += int(bar["bounty"])
		bar_retrieval += int(bar["retrieval"])
	runner.check(bar_passenger >= 1000 and bar_passenger <= 1200, "desk mix: bar passenger near 55%")
	runner.check(bar_freight >= 300 and bar_freight <= 500, "desk mix: bar freight near 20%")
	runner.check(bar_scan >= 150 and bar_scan <= 250, "desk mix: bar scan near 10%")
	runner.check(bar_bounty >= 50 and bar_bounty <= 150, "desk mix: bar bounty near 5%")
	runner.check(bar_retrieval >= 150 and bar_retrieval <= 250, "desk mix: bar retrieval near 10%")


static func _test_peacekeeping_desk_total(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var habitat_id := "proxima_habitat"
	var building_id := ScanCharters.peacekeeping_building_id(
		catalog.get_habitat_sector_id(habitat_id)
	)
	var day := 3
	var run_seed := 4242
	var counts := DeskCharterBoards.counts_for_building(
		catalog, habitat_id, building_id, ScanCharters.BOARD_PEACEKEEPING, day, run_seed
	)
	var total := int(counts["scan"]) + int(counts["bounty"]) + int(counts["retrieval"])
	var band := DealerStock.charter_offer_band(60.0)
	runner.check(total >= band.x and total <= band.y, "desk total: peacekeeping sum matches band")
	var generated := DeskCharterBoards.generate_for_habitat(catalog, habitat_id, day, run_seed)
	var scan_rows: Array = generated["scan"].get(building_id, [])
	var bounty_rows: Array = generated["bounty"].get(building_id, [])
	var retrieval_rows: Array = generated["retrieval"].get(building_id, [])
	runner.check_eq(
		scan_rows.size() + bounty_rows.size() + retrieval_rows.size(),
		total,
		"desk total: peacekeeping posted count matches roll"
	)


static func _test_bar_desk_total(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var habitat_id := "proxima_habitat"
	var building_id := "davidsons"
	var day := 7
	var run_seed := 777
	var counts := DeskCharterBoards.counts_for_building(
		catalog, habitat_id, building_id, ScanCharters.BOARD_BAR, day, run_seed
	)
	var total := (
		int(counts["passenger"])
		+ int(counts["freight"])
		+ int(counts["scan"])
		+ int(counts["bounty"])
		+ int(counts["retrieval"])
	)
	var band := DealerStock.charter_offer_band(60.0)
	runner.check(total >= band.x and total <= band.y, "desk total: bar sum matches band")
	var generated := DeskCharterBoards.generate_for_habitat(catalog, habitat_id, day, run_seed)
	var passenger_rows: Array = generated["passenger"].get(building_id, [])
	var freight_rows: Array = generated["freight"].get(building_id, [])
	var scan_rows: Array = generated["scan"].get(building_id, [])
	var bounty_rows: Array = generated["bounty"].get(building_id, [])
	var retrieval_rows: Array = generated["retrieval"].get(building_id, [])
	runner.check_eq(
		passenger_rows.size()
		+ freight_rows.size()
		+ scan_rows.size()
		+ bounty_rows.size()
		+ retrieval_rows.size(),
		total,
		"desk total: bar posted count matches roll"
	)
