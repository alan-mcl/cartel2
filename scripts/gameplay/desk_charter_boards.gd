class_name DeskCharterBoards
extends RefCounted

const FREIGHT_BOARD_TERMINAL := "terminal"

const WEIGHT_SCAN_DUAL := 40
const WEIGHT_BOUNTY_DUAL := 40
const WEIGHT_RETRIEVAL_DUAL := 20

const BAR_WEIGHT_PASSENGER := 55
const BAR_WEIGHT_FREIGHT := 20
const BAR_WEIGHT_SCAN := 10
const BAR_WEIGHT_BOUNTY := 5
const BAR_WEIGHT_RETRIEVAL := 10

const BAR_ROUND_OFFER_INDEX_START := 1000


static func bar_round_run_seed(session_run_seed: int, building_id: String) -> int:
	return int(hash("%d:%s:bar_round" % [session_run_seed, building_id]))


static func desk_seed(day: int, habitat_id: String, building_id: String, run_seed: int) -> int:
	return int(hash("%d:%d:%s:%s:desk" % [run_seed, day, habitat_id, building_id]))


static func roll_desk_total(rng: RandomNumberGenerator, population_billions: float) -> int:
	return DealerStock.roll_charter_offer_count(rng, population_billions)


static func split_dual_desk(total: int, rng: RandomNumberGenerator) -> Dictionary:
	var scan := 0
	var bounty := 0
	var retrieval := 0
	var dual_total := WEIGHT_SCAN_DUAL + WEIGHT_BOUNTY_DUAL + WEIGHT_RETRIEVAL_DUAL
	for _i in range(total):
		var roll := rng.randi_range(1, dual_total)
		if roll <= WEIGHT_SCAN_DUAL:
			scan += 1
		elif roll <= WEIGHT_SCAN_DUAL + WEIGHT_BOUNTY_DUAL:
			bounty += 1
		else:
			retrieval += 1
	return {"scan": scan, "bounty": bounty, "retrieval": retrieval}


static func split_bar_desk(total: int, rng: RandomNumberGenerator) -> Dictionary:
	var passenger := 0
	var freight := 0
	var scan := 0
	var bounty := 0
	var retrieval := 0
	for _i in range(total):
		var roll := rng.randi_range(1, 100)
		if roll <= BAR_WEIGHT_PASSENGER:
			passenger += 1
		elif roll <= BAR_WEIGHT_PASSENGER + BAR_WEIGHT_FREIGHT:
			freight += 1
		elif roll <= BAR_WEIGHT_PASSENGER + BAR_WEIGHT_FREIGHT + BAR_WEIGHT_SCAN:
			scan += 1
		elif roll <= BAR_WEIGHT_PASSENGER + BAR_WEIGHT_FREIGHT + BAR_WEIGHT_SCAN + BAR_WEIGHT_BOUNTY:
			bounty += 1
		else:
			retrieval += 1
	return {
		"passenger": passenger,
		"freight": freight,
		"scan": scan,
		"bounty": bounty,
		"retrieval": retrieval,
	}


static func counts_for_building(
	catalog: Catalog,
	habitat_id: String,
	building_id: String,
	building_type: String,
	day: int,
	run_seed: int
) -> Dictionary:
	var pop := DealerStock.population_for_habitat(catalog, habitat_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = desk_seed(day, habitat_id, building_id, run_seed)
	var total := roll_desk_total(rng, pop)
	if total <= 0:
		return _empty_counts(building_type)
	match building_type:
		ScanCharters.BOARD_PEACEKEEPING, ScanCharters.BOARD_CORPORATE:
			var dual := split_dual_desk(total, rng)
			return {
				"passenger": 0,
				"freight": 0,
				"scan": int(dual["scan"]),
				"bounty": int(dual["bounty"]),
				"retrieval": int(dual["retrieval"]),
			}
		ScanCharters.BOARD_BAR:
			var bar := split_bar_desk(total, rng)
			return {
				"passenger": int(bar["passenger"]),
				"freight": int(bar["freight"]),
				"scan": int(bar["scan"]),
				"bounty": int(bar["bounty"]),
				"retrieval": int(bar["retrieval"]),
			}
		_:
			return _empty_counts(building_type)


static func _empty_counts(_building_type: String) -> Dictionary:
	return {"passenger": 0, "freight": 0, "scan": 0, "bounty": 0, "retrieval": 0}


static func generate_bar_building(
	catalog: Catalog,
	habitat_id: String,
	building_id: String,
	day: int,
	run_seed: int,
	passenger_index_start: int = 0,
	scan_index_start: int = 0,
	bounty_index_start: int = 0,
	retrieval_index_start: int = 0
) -> Dictionary:
	var building := catalog.get_building(building_id)
	if building.is_empty():
		return _empty_bar_slices()
	var building_type := catalog.get_building_type(building)
	if building_type != ScanCharters.BOARD_BAR:
		return _empty_bar_slices()

	var counts := counts_for_building(
		catalog, habitat_id, building_id, building_type, day, run_seed
	)
	var passenger_offers: Array = []
	var passenger_count := int(counts.get("passenger", 0))
	if passenger_count > 0:
		passenger_offers = PassengerCharters.generate_offers(
			catalog,
			habitat_id,
			PassengerCharters.BOARD_BAR,
			day,
			passenger_count,
			run_seed,
			false,
			passenger_index_start
		)
	var freight_offers: Array = []
	var freight_count := int(counts.get("freight", 0))
	if freight_count > 0:
		freight_offers = FreightCharters.generate_offers(
			catalog,
			habitat_id,
			day,
			freight_count,
			run_seed,
			false,
			passenger_index_start
		)
	var scan_count := int(counts.get("scan", 0))
	var scan_offers := ScanCharters.generate_offers_for_building(
		catalog,
		habitat_id,
		building_id,
		building_type,
		day,
		run_seed,
		scan_index_start,
		scan_count
	)
	var bounty_count := int(counts.get("bounty", 0))
	var bounty_offers := BountyCharters.generate_offers_for_building(
		catalog,
		habitat_id,
		building_id,
		building_type,
		day,
		run_seed,
		bounty_index_start,
		bounty_count
	)
	var retrieval_count := int(counts.get("retrieval", 0))
	var retrieval_offers := RetrievalCharters.generate_offers_for_building(
		catalog,
		habitat_id,
		building_id,
		building_type,
		day,
		run_seed,
		retrieval_index_start,
		retrieval_count
	)
	return {
		"passenger": passenger_offers,
		"freight": freight_offers,
		"scan": scan_offers,
		"bounty": bounty_offers,
		"retrieval": retrieval_offers,
	}


static func _empty_bar_slices() -> Dictionary:
	return {
		"passenger": [],
		"freight": [],
		"scan": [],
		"bounty": [],
		"retrieval": [],
	}


## Same desk totals and mixes as `MissionSubsystem._populate_habitat_boards`.
static func generate_for_habitat(
	catalog: Catalog,
	habitat_id: String,
	day: int,
	run_seed: int
) -> Dictionary:
	var is_station := catalog.location_is_station(habitat_id)
	var passenger_boards: Dictionary = {}
	var freight_boards: Dictionary = {}
	var scan_boards: Dictionary = {}
	var bounty_boards: Dictionary = {}
	var retrieval_boards: Dictionary = {}
	var scan_index := 0
	var bounty_index := 0
	var retrieval_index := 0

	if not is_station:
		passenger_boards[PassengerCharters.BOARD_TERMINAL] = PassengerCharters.generate_offers(
			catalog,
			habitat_id,
			PassengerCharters.BOARD_TERMINAL,
			day,
			0,
			run_seed,
			true
		)
		freight_boards[FREIGHT_BOARD_TERMINAL] = FreightCharters.generate_offers(
			catalog,
			habitat_id,
			day,
			0,
			run_seed,
			true
		)

	for building_id_variant in ScanCharters.scan_building_ids(catalog, habitat_id):
		var building_id := str(building_id_variant)
		var building := catalog.get_building(building_id)
		if building.is_empty():
			continue
		var building_type := catalog.get_building_type(building)
		var counts := counts_for_building(
			catalog, habitat_id, building_id, building_type, day, run_seed
		)
		if building_type == ScanCharters.BOARD_BAR:
			var bar_slices := generate_bar_building(
				catalog,
				habitat_id,
				building_id,
				day,
				run_seed,
				0,
				scan_index,
				bounty_index,
				retrieval_index
			)
			var bar_passenger: Array = bar_slices.get("passenger", [])
			if not bar_passenger.is_empty():
				passenger_boards[building_id] = bar_passenger
			var bar_freight: Array = bar_slices.get("freight", [])
			if not bar_freight.is_empty():
				freight_boards[building_id] = bar_freight
			var bar_scan: Array = bar_slices.get("scan", [])
			scan_index += bar_scan.size()
			if not bar_scan.is_empty():
				scan_boards[building_id] = bar_scan
			var bar_bounty: Array = bar_slices.get("bounty", [])
			bounty_index += bar_bounty.size()
			if not bar_bounty.is_empty():
				bounty_boards[building_id] = bar_bounty
			var bar_retrieval: Array = bar_slices.get("retrieval", [])
			retrieval_index += bar_retrieval.size()
			if not bar_retrieval.is_empty():
				retrieval_boards[building_id] = bar_retrieval
			continue
		var scan_count := int(counts.get("scan", 0))
		var scan_offers := ScanCharters.generate_offers_for_building(
			catalog,
			habitat_id,
			building_id,
			building_type,
			day,
			run_seed,
			scan_index,
			scan_count
		)
		scan_index += scan_offers.size()
		if not scan_offers.is_empty():
			scan_boards[building_id] = scan_offers
		var bounty_count := int(counts.get("bounty", 0))
		var bounty_offers := BountyCharters.generate_offers_for_building(
			catalog,
			habitat_id,
			building_id,
			building_type,
			day,
			run_seed,
			bounty_index,
			bounty_count
		)
		bounty_index += bounty_offers.size()
		if not bounty_offers.is_empty():
			bounty_boards[building_id] = bounty_offers
		var retrieval_count := int(counts.get("retrieval", 0))
		var retrieval_offers := RetrievalCharters.generate_offers_for_building(
			catalog,
			habitat_id,
			building_id,
			building_type,
			day,
			run_seed,
			retrieval_index,
			retrieval_count
		)
		retrieval_index += retrieval_offers.size()
		if not retrieval_offers.is_empty():
			retrieval_boards[building_id] = retrieval_offers

	return {
		"passenger": passenger_boards,
		"freight": freight_boards,
		"scan": scan_boards,
		"bounty": bounty_boards,
		"retrieval": retrieval_boards,
	}
