class_name DeskCharterBoards
extends RefCounted

const FREIGHT_BOARD_TERMINAL := "terminal"

const WEIGHT_SCAN_DUAL := 50
const WEIGHT_BOUNTY_DUAL := 50

const BAR_WEIGHT_PASSENGER := 60
const BAR_WEIGHT_FREIGHT := 20
const BAR_WEIGHT_SCAN := 15
const BAR_WEIGHT_BOUNTY := 5


static func desk_seed(day: int, habitat_id: String, building_id: String, run_seed: int) -> int:
	return int(hash("%d:%d:%s:%s:desk" % [run_seed, day, habitat_id, building_id]))


static func roll_desk_total(rng: RandomNumberGenerator, population_billions: float) -> int:
	return DealerStock.roll_charter_offer_count(rng, population_billions)


static func split_dual_desk(total: int, rng: RandomNumberGenerator) -> Dictionary:
	var scan := 0
	var bounty := 0
	for _i in range(total):
		if rng.randi_range(1, WEIGHT_SCAN_DUAL + WEIGHT_BOUNTY_DUAL) <= WEIGHT_SCAN_DUAL:
			scan += 1
		else:
			bounty += 1
	return {"scan": scan, "bounty": bounty}


static func split_bar_desk(total: int, rng: RandomNumberGenerator) -> Dictionary:
	var passenger := 0
	var freight := 0
	var scan := 0
	var bounty := 0
	for _i in range(total):
		var roll := rng.randi_range(1, 100)
		if roll <= BAR_WEIGHT_PASSENGER:
			passenger += 1
		elif roll <= BAR_WEIGHT_PASSENGER + BAR_WEIGHT_FREIGHT:
			freight += 1
		elif roll <= BAR_WEIGHT_PASSENGER + BAR_WEIGHT_FREIGHT + BAR_WEIGHT_SCAN:
			scan += 1
		else:
			bounty += 1
	return {
		"passenger": passenger,
		"freight": freight,
		"scan": scan,
		"bounty": bounty,
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
			}
		ScanCharters.BOARD_BAR:
			var bar := split_bar_desk(total, rng)
			return {
				"passenger": int(bar["passenger"]),
				"freight": int(bar["freight"]),
				"scan": int(bar["scan"]),
				"bounty": int(bar["bounty"]),
			}
		_:
			return _empty_counts(building_type)


static func _empty_counts(_building_type: String) -> Dictionary:
	return {"passenger": 0, "freight": 0, "scan": 0, "bounty": 0}


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
	var scan_index := 0
	var bounty_index := 0

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
			var passenger_count := int(counts.get("passenger", 0))
			if passenger_count > 0:
				passenger_boards[building_id] = PassengerCharters.generate_offers(
					catalog,
					habitat_id,
					PassengerCharters.BOARD_BAR,
					day,
					passenger_count,
					run_seed,
					false
				)
			var freight_count := int(counts.get("freight", 0))
			if freight_count > 0:
				freight_boards[building_id] = FreightCharters.generate_offers(
					catalog,
					habitat_id,
					day,
					freight_count,
					run_seed,
					false
				)
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

	return {
		"passenger": passenger_boards,
		"freight": freight_boards,
		"scan": scan_boards,
		"bounty": bounty_boards,
	}
