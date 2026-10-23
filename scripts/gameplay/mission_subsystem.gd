class_name MissionSubsystem
extends SimSubsystem

## Daily passenger and freight charter offers and accepted contracts.

var generated_day: int = -1
var passengers := CharterBook.new("charter_")
var freight := CharterBook.new("freight_", true)
var scans := CharterBook.new("scan_")
var bounties := CharterBook.new("bounty_")


func _init() -> void:
	id = "missions"
	save_version = 5


func on_day(_session: GameSession, _catalog: Catalog, day: int) -> void:
	_invalidate_boards(day)


func on_hour(session: GameSession, catalog: Catalog, _hour: int) -> void:
	_enforce_late_passengers_at_dock(session, catalog)


func on_event(session: GameSession, catalog: Catalog, evt: Dictionary) -> void:
	if session == null or evt.is_empty():
		return
	if str(evt.get("type", "")) != SimEvent.DOCKED:
		return
	var habitat_id := str(evt.get("habitat_id", ""))
	_enforce_late_passengers_at_dock(session, catalog)
	_enforce_late_scan_charters_at_dock(session, catalog)
	_enforce_late_bounty_charters_at_dock(session, catalog)
	_try_complete_charters(session, catalog, habitat_id)
	_try_complete_freight_charters(session, catalog, habitat_id)
	_try_complete_scan_charters(session, catalog, habitat_id)
	_try_complete_bounty_charters(session, catalog, habitat_id)


func ensure_boards(session: GameSession, catalog: Catalog) -> void:
	var day := CommodityEconomy.gst_day(session.gst_seconds)
	if generated_day != day:
		_invalidate_boards(day)
	var habitat_id := str(session.habitat_id)
	if habitat_id.is_empty():
		return
	_ensure_habitat_boards(session, catalog, habitat_id, day)


## Dev harness only. One peacekeeping scan offer, built by ScanCharters, replaces today's board.
func seed_harness_scan_offer(
	session: GameSession,
	catalog: Catalog,
	habitat_id: String,
	type_key: String,
	target_kind: String,
	volatile_site: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	ensure_boards(session, catalog)
	var sector_id := catalog.get_habitat_sector_id(habitat_id)
	var building_id := ScanCharters.peacekeeping_building_id(sector_id)
	var offer := ScanCharters.build_pinned_offer(
		catalog,
		habitat_id,
		building_id,
		rng,
		0,
		type_key,
		target_kind,
		volatile_site,
		4
	)
	if offer.is_empty():
		return {}
	scans.offers[habitat_id] = {building_id: [offer]}
	return offer


## Dev harness only. One peacekeeping bounty offer, built by BountyCharters, replaces today's board.
func seed_harness_bounty_offer(
	session: GameSession,
	catalog: Catalog,
	habitat_id: String,
	template_id: String,
	volatile_site: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	ensure_boards(session, catalog)
	var sector_id := catalog.get_habitat_sector_id(habitat_id)
	var building_id := ScanCharters.peacekeeping_building_id(sector_id)
	var offer := BountyCharters.build_pinned_offer(
		catalog,
		habitat_id,
		building_id,
		rng,
		0,
		template_id,
		volatile_site,
		4
	)
	if offer.is_empty():
		return {}
	bounties.offers[habitat_id] = {building_id: [offer]}
	return offer


func list_offers(habitat_id: String, board: String) -> Array:
	return passengers.list_board(habitat_id, board)


func list_freight_offers(habitat_id: String) -> Array:
	return freight.list_flat(habitat_id)


func list_accepted() -> Array:
	return passengers.list_accepted()


func list_freight_accepted() -> Array:
	return freight.list_accepted()


func list_scan_offers(habitat_id: String, building_id: String) -> Array:
	return scans.list_board(habitat_id, building_id)


func list_scan_accepted() -> Array:
	return scans.list_accepted()


func list_bounty_offers(habitat_id: String, building_id: String) -> Array:
	return bounties.list_board(habitat_id, building_id)


func list_bounty_accepted() -> Array:
	return bounties.list_accepted()


func find_offer(offer_id: String) -> Dictionary:
	return passengers.find_offer(offer_id)


func find_freight_offer(offer_id: String) -> Dictionary:
	return freight.find_offer(offer_id)


func find_scan_offer(offer_id: String) -> Dictionary:
	return scans.find_offer(offer_id)


func find_bounty_offer(offer_id: String) -> Dictionary:
	return bounties.find_offer(offer_id)


func committed_passengers_for_ship(ship_id: String) -> int:
	var total := 0
	for entry_variant in passengers.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("ship_id", "")) == ship_id:
			total += int(entry.get("quantity", 0))
	return total


func committed_freight_life_support_for_ship(ship_id: String) -> int:
	var total := 0
	for entry_variant in freight.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("ship_id", "")) == ship_id:
			total += int(entry.get("life_support_seats", 0))
	return total


func committed_freight_reserves_for_ship(ship_id: String) -> Dictionary:
	var tonnes := 0.0
	var life_support := 0
	var compute := 0.0
	var power := 0.0
	for entry_variant in freight.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("ship_id", "")) != ship_id:
			continue
		tonnes += float(entry.get("tonnes", 0.0))
		life_support += int(entry.get("life_support_seats", 0))
		compute += float(entry.get("compute_demand", 0.0))
		power += float(entry.get("power_demand", 0.0))
	return {
		"tonnes": tonnes,
		"life_support_seats": life_support,
		"compute": compute,
		"power": power,
	}


func launch_occupant_count(ship_id: String) -> int:
	return (
		PassengerCharters.PILOT_LIFE_SUPPORT_SEATS
		+ committed_passengers_for_ship(ship_id)
		+ committed_freight_life_support_for_ship(ship_id)
	)


func _freight_commitment_for_evaluate(ship_id: String) -> Dictionary:
	var reserves := committed_freight_reserves_for_ship(ship_id)
	return {
		"passengers": committed_passengers_for_ship(ship_id),
		"tonnes": float(reserves.get("tonnes", 0.0)),
		"life_support_seats": int(reserves.get("life_support_seats", 0)),
		"compute": float(reserves.get("compute", 0.0)),
		"power": float(reserves.get("power", 0.0)),
	}


func evaluate_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> Dictionary:
	var offer := find_offer(offer_id)
	if offer.is_empty():
		return {"ok": false, "reason": "Offer no longer available."}
	var committed_passengers := (
		committed_passengers_for_ship(ship_id)
		+ committed_freight_life_support_for_ship(ship_id)
	)
	return PassengerCharters.evaluate_offer_for_ship(
		session,
		catalog,
		offer,
		ship_id,
		committed_passengers
	)


func evaluate_freight_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> Dictionary:
	var offer := find_freight_offer(offer_id)
	if offer.is_empty():
		return {"ok": false, "reason": "Offer no longer available."}
	return FreightCharters.evaluate_offer_for_ship(
		session,
		catalog,
		offer,
		ship_id,
		_freight_commitment_for_evaluate(ship_id)
	)


func evaluate_scan_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> Dictionary:
	var offer := find_scan_offer(offer_id)
	if offer.is_empty():
		return {"ok": false, "reason": "Offer no longer available."}
	return ScanCharters.evaluate_offer_for_ship(session, catalog, offer, ship_id)


func evaluate_bounty_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> Dictionary:
	var offer := find_bounty_offer(offer_id)
	if offer.is_empty():
		return {"ok": false, "reason": "Offer no longer available."}
	return BountyCharters.evaluate_offer_for_ship(session, catalog, offer, ship_id)


func _take_offer(book: CharterBook, offer: Dictionary, ship_id: String) -> Dictionary:
	book.remove_offer(str(offer.get("id", "")))
	var charter := offer.duplicate(true)
	charter["charter_id"] = book.allocate_id()
	charter["ship_id"] = ship_id
	return charter


func _commit_accepted(
	session: GameSession,
	book: CharterBook,
	charter: Dictionary,
	log_line: String
) -> void:
	book.accepted.append(charter)
	session.last_log = log_line
	if not session.player.sandbox:
		session.career.missions_accepted += 1
	session.changed.emit()


func accept_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> bool:
	ensure_boards(session, catalog)
	var check := evaluate_offer(session, catalog, offer_id, ship_id)
	if not bool(check.get("ok", false)):
		session.last_log = str(check.get("reason", "Cannot accept charter."))
		session.changed.emit()
		return false

	var offer := find_offer(offer_id)
	if offer.is_empty():
		return false

	var charter := _take_offer(passengers, offer, ship_id)
	_apply_charter_deadline(session, charter)
	_commit_accepted(
		session,
		passengers,
		charter,
		"Charter accepted: %s to %s for d%d."
		% [
			str(offer.get("role_title", "Passengers")),
			str(offer.get("destination_name", "")),
			int(offer.get("reward", 0)),
		]
	)
	return true


func accept_freight_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> bool:
	ensure_boards(session, catalog)
	var check := evaluate_freight_offer(session, catalog, offer_id, ship_id)
	if not bool(check.get("ok", false)):
		session.last_log = str(check.get("reason", "Cannot accept freight charter."))
		session.changed.emit()
		return false

	var offer := find_freight_offer(offer_id)
	if offer.is_empty():
		return false

	var charter := _take_offer(freight, offer, ship_id)
	_apply_charter_deadline(session, charter)
	_commit_accepted(
		session,
		freight,
		charter,
		"Freight accepted to %s for d%d."
		% [str(offer.get("destination_name", "")), int(offer.get("reward", 0))]
	)
	return true


func accept_scan_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> bool:
	ensure_boards(session, catalog)
	var check := evaluate_scan_offer(session, catalog, offer_id, ship_id)
	if not bool(check.get("ok", false)):
		session.last_log = str(check.get("reason", "Cannot accept scan charter."))
		session.changed.emit()
		return false

	var offer := find_scan_offer(offer_id)
	if offer.is_empty():
		return false

	var charter := _take_offer(scans, offer, ship_id)
	charter["accepted_gst"] = session.gst_seconds

	var target_kind := str(offer.get("target_kind", ""))
	if target_kind == "planet":
		charter["scan_contact_id"] = "planet"
		charter["volatile_record_id"] = ""
		_apply_charter_deadline(session, charter)
	else:
		var record_id := VolatileTranslation.grant(
			session,
			catalog,
			ScanCharters.build_volatile_grant_params(catalog, offer)
		)
		if record_id.is_empty():
			session.last_log = "Could not open survey site."
			session.changed.emit()
			return false
		charter["volatile_record_id"] = record_id
		charter["scan_contact_id"] = ScanCharters.scan_contact_id_for_offer(offer, record_id)
		var record := VolatileTranslation.find_by_id(session, record_id)
		if not record.is_empty():
			charter["deadline_gst"] = float(record.get("return_expires_gst", 0.0))

	_commit_accepted(
		session,
		scans,
		charter,
		"Scan charter accepted: %s at %s for d%d."
		% [
			str(offer.get("designation", "Survey")),
			str(offer.get("site_label", "")),
			int(offer.get("reward", 0)),
		]
	)
	return true


func accept_bounty_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> bool:
	ensure_boards(session, catalog)
	var check := evaluate_bounty_offer(session, catalog, offer_id, ship_id)
	if not bool(check.get("ok", false)):
		session.last_log = str(check.get("reason", "Cannot accept bounty."))
		session.changed.emit()
		return false

	var offer := find_bounty_offer(offer_id)
	if offer.is_empty():
		return false

	var charter := _take_offer(bounties, offer, ship_id)
	charter["accepted_gst"] = session.gst_seconds

	var record_id := VolatileTranslation.grant(
		session,
		catalog,
		BountyCharters.build_volatile_grant_params(catalog, offer)
	)
	if record_id.is_empty():
		session.last_log = "Could not open bounty site."
		session.changed.emit()
		return false
	charter["volatile_record_id"] = record_id
	charter["bounty_target_id"] = BountyCharters.bounty_target_id_for_record(record_id)
	var record := VolatileTranslation.find_by_id(session, record_id)
	if not record.is_empty():
		charter["deadline_gst"] = float(record.get("return_expires_gst", 0.0))

	_commit_accepted(
		session,
		bounties,
		charter,
		"Bounty accepted: %s at %s for d%d."
		% [
			str(offer.get("target_callsign", "")),
			str(offer.get("site_label", "")),
			int(offer.get("reward", 0)),
		]
	)
	return true


func cancel_charter(session: GameSession, catalog: Catalog, charter_id: String) -> bool:
	var charter := passengers.find_accepted(charter_id)
	if charter.is_empty():
		return false
	if not _charter_at_origin(session, charter):
		session.last_log = "Cannot cancel charter after departure."
		session.changed.emit()
		return false

	var cfg := PassengerCharters.config(catalog)
	var penalty := PassengerCharters.cancel_penalty(cfg, int(charter.get("reward", 0)))
	session.assess_penalty_credits(penalty)

	passengers.remove_accepted(charter_id)
	var log := "Charter cancelled. Fee d%d." % penalty if penalty > 0 else "Charter cancelled."
	_log_with_reputation_delta(session, -1, log)
	if not session.player.sandbox:
		session.career.missions_cancelled += 1
		session.career.record_mission_penalty(penalty)
	session.changed.emit()
	return true


func cancel_freight_charter(session: GameSession, catalog: Catalog, charter_id: String) -> bool:
	var charter := freight.find_accepted(charter_id)
	if charter.is_empty():
		return false
	if not _freight_charter_at_origin(session, charter):
		session.last_log = "Cannot cancel freight after departure."
		session.changed.emit()
		return false

	var cfg := FreightCharters.config(catalog)
	var penalty := FreightCharters.cancel_penalty(cfg, int(charter.get("reward", 0)))
	session.assess_penalty_credits(penalty)

	freight.remove_accepted(charter_id)
	var log := "Freight cancelled. Fee d%d." % penalty if penalty > 0 else "Freight cancelled."
	_log_with_reputation_delta(session, -1, log)
	if not session.player.sandbox:
		session.career.missions_cancelled += 1
		session.career.record_mission_penalty(penalty)
	session.changed.emit()
	return true


func cancel_charter_eligible(session: GameSession, charter_id: String) -> bool:
	var charter := passengers.find_accepted(charter_id)
	if charter.is_empty():
		return false
	return _charter_at_origin(session, charter)


func cancel_freight_charter_eligible(session: GameSession, charter_id: String) -> bool:
	var charter := freight.find_accepted(charter_id)
	if charter.is_empty():
		return false
	return _freight_charter_at_origin(session, charter)


func cancel_scan_charter(session: GameSession, catalog: Catalog, charter_id: String) -> bool:
	var charter := scans.find_accepted(charter_id)
	if charter.is_empty():
		return false
	if not cancel_scan_charter_eligible(session, charter_id):
		session.last_log = "Cannot cancel scan charter after departure."
		session.changed.emit()
		return false

	var cfg := ScanCharters.config(catalog)
	var penalty := ScanCharters.cancel_penalty(cfg, int(charter.get("reward", 0)))
	session.assess_penalty_credits(penalty)

	var volatile_id := str(charter.get("volatile_record_id", ""))
	if not volatile_id.is_empty():
		VolatileTranslation.discard_record(session, volatile_id)

	scans.remove_accepted(charter_id)
	var log := "Scan charter cancelled. Fee d%d." % penalty if penalty > 0 else "Scan charter cancelled."
	_log_with_reputation_delta(session, -1, log)
	if not session.player.sandbox:
		session.career.missions_cancelled += 1
		session.career.record_mission_penalty(penalty)
	session.changed.emit()
	return true


func cancel_scan_charter_eligible(session: GameSession, charter_id: String) -> bool:
	var charter := scans.find_accepted(charter_id)
	if charter.is_empty():
		return false
	if not _charter_at_origin(session, charter):
		return false
	var volatile_id := str(charter.get("volatile_record_id", ""))
	if volatile_id.is_empty():
		return true
	var record := VolatileTranslation.find_by_id(session, volatile_id)
	if record.is_empty():
		return true
	return not bool(record.get("consumed", false))


func cancel_bounty_charter(session: GameSession, catalog: Catalog, charter_id: String) -> bool:
	var charter := bounties.find_accepted(charter_id)
	if charter.is_empty():
		return false
	if not cancel_bounty_charter_eligible(session, charter_id):
		session.last_log = "Cannot cancel bounty after departure."
		session.changed.emit()
		return false

	var cfg := BountyCharters.config(catalog)
	var penalty := BountyCharters.cancel_penalty(cfg, int(charter.get("reward", 0)))
	session.assess_penalty_credits(penalty)

	var volatile_id := str(charter.get("volatile_record_id", ""))
	if not volatile_id.is_empty():
		VolatileTranslation.discard_record(session, volatile_id)

	bounties.remove_accepted(charter_id)
	var log := "Bounty cancelled. Fee d%d." % penalty if penalty > 0 else "Bounty cancelled."
	_log_with_reputation_delta(session, -1, log)
	if not session.player.sandbox:
		session.career.missions_cancelled += 1
		session.career.record_mission_penalty(penalty)
	session.changed.emit()
	return true


func cancel_bounty_charter_eligible(session: GameSession, charter_id: String) -> bool:
	var charter := bounties.find_accepted(charter_id)
	if charter.is_empty():
		return false
	if not _charter_at_origin(session, charter):
		return false
	var volatile_id := str(charter.get("volatile_record_id", ""))
	if volatile_id.is_empty():
		return true
	var record := VolatileTranslation.find_by_id(session, volatile_id)
	if record.is_empty():
		return true
	return not bool(record.get("consumed", false))


func to_dict() -> Dictionary:
	return {
		"generated_day": generated_day,
		"offers_by_habitat": passengers.duplicate_offers(),
		"accepted": passengers.duplicate_accepted(),
		"freight_offers_by_habitat": freight.duplicate_offers(),
		"freight_accepted": freight.duplicate_accepted(),
		"scan_offers_by_habitat": scans.duplicate_offers(),
		"scan_accepted": scans.duplicate_accepted(),
		"bounty_offers_by_habitat": bounties.duplicate_offers(),
		"bounty_accepted": bounties.duplicate_accepted(),
		"next_charter_id": passengers.next_id,
		"next_freight_charter_id": freight.next_id,
		"next_scan_charter_id": scans.next_id,
		"next_bounty_charter_id": bounties.next_id,
	}


func migrate(data: Dictionary, from_version: int) -> Dictionary:
	if from_version >= save_version:
		return data.duplicate(true)
	var out := data.duplicate(true)
	if from_version <= 2:
		if not out.has("freight_offers_by_habitat"):
			out["freight_offers_by_habitat"] = {}
		if not out.has("freight_accepted"):
			out["freight_accepted"] = []
		if not out.has("next_freight_charter_id"):
			out["next_freight_charter_id"] = 1
	if from_version <= 3:
		if not out.has("scan_offers_by_habitat"):
			out["scan_offers_by_habitat"] = {}
		if not out.has("scan_accepted"):
			out["scan_accepted"] = []
		if not out.has("next_scan_charter_id"):
			out["next_scan_charter_id"] = 1
	if from_version <= 4:
		if not out.has("bounty_offers_by_habitat"):
			out["bounty_offers_by_habitat"] = {}
		if not out.has("bounty_accepted"):
			out["bounty_accepted"] = []
		if not out.has("next_bounty_charter_id"):
			out["next_bounty_charter_id"] = 1
	return out


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		generated_day = -1
		passengers.reset()
		freight.reset()
		scans.reset()
		bounties.reset()
		return
	generated_day = int(data.get("generated_day", -1))
	passengers.load_state(
		data.get("offers_by_habitat", {}),
		data.get("accepted", []),
		data.get("next_charter_id", 1)
	)
	freight.load_state(
		data.get("freight_offers_by_habitat", {}),
		data.get("freight_accepted", []),
		data.get("next_freight_charter_id", 1)
	)
	scans.load_state(
		data.get("scan_offers_by_habitat", {}),
		data.get("scan_accepted", []),
		data.get("next_scan_charter_id", 1)
	)
	bounties.load_state(
		data.get("bounty_offers_by_habitat", {}),
		data.get("bounty_accepted", []),
		data.get("next_bounty_charter_id", 1)
	)


func _invalidate_boards(day: int) -> void:
	generated_day = day
	passengers.clear_offers()
	freight.clear_offers()
	scans.clear_offers()
	bounties.clear_offers()


func _ensure_habitat_boards(
	session: GameSession,
	catalog: Catalog,
	habitat_id: String,
	day: int
) -> void:
	var need_passenger := not passengers.offers.has(habitat_id)
	var need_freight := not freight.offers.has(habitat_id)
	var need_scan := not scans.offers.has(habitat_id)
	var need_bounty := not bounties.offers.has(habitat_id)
	if not need_passenger and not need_freight and not need_scan and not need_bounty:
		return
	var is_station := catalog.location_is_station(habitat_id)
	var cfg := PassengerCharters.config(catalog)
	var terminal_count := int(cfg.get("terminal_offers_per_day", 4))
	var bar_count := int(cfg.get("bar_offers_per_day", 2))
	var freight_cfg := FreightCharters.config(catalog)
	var freight_count := int(freight_cfg.get("offers_per_day", 4))
	var run_seed := session.run_seed
	if need_passenger and not is_station:
		var boards := {
			PassengerCharters.BOARD_TERMINAL: PassengerCharters.generate_offers(
				catalog,
				habitat_id,
				PassengerCharters.BOARD_TERMINAL,
				day,
				terminal_count,
				run_seed
			),
		}
		if PassengerCharters.habitat_has_bar(catalog, habitat_id):
			boards[PassengerCharters.BOARD_BAR] = PassengerCharters.generate_offers(
				catalog,
				habitat_id,
				PassengerCharters.BOARD_BAR,
				day,
				bar_count,
				run_seed
			)
		passengers.offers[habitat_id] = boards
	elif need_passenger and is_station:
		passengers.offers[habitat_id] = {}
	if need_freight and not is_station:
		freight.offers[habitat_id] = FreightCharters.generate_offers(
			catalog,
			habitat_id,
			day,
			freight_count,
			run_seed
		)
	elif need_freight and is_station:
		freight.offers[habitat_id] = {}
	if need_scan:
		_ensure_scan_boards_for_habitat(session, catalog, habitat_id, day, run_seed)
	if need_bounty:
		_ensure_bounty_boards_for_habitat(session, catalog, habitat_id, day, run_seed)


func _ensure_scan_boards_for_habitat(
	session: GameSession,
	catalog: Catalog,
	habitat_id: String,
	day: int,
	run_seed: int
) -> void:
	var boards: Dictionary = {}
	var next_index := 0
	for building_id_variant in ScanCharters.scan_building_ids(catalog, habitat_id):
		var building_id := str(building_id_variant)
		var building := catalog.get_building(building_id)
		if building.is_empty():
			continue
		var building_type := catalog.get_building_type(building)
		var offers := ScanCharters.generate_offers_for_building(
			catalog,
			habitat_id,
			building_id,
			building_type,
			day,
			run_seed,
			next_index
		)
		next_index += offers.size()
		if not offers.is_empty():
			boards[building_id] = offers
	scans.offers[habitat_id] = boards


func _ensure_bounty_boards_for_habitat(
	session: GameSession,
	catalog: Catalog,
	habitat_id: String,
	day: int,
	run_seed: int
) -> void:
	var boards: Dictionary = {}
	var next_index := 0
	for building_id_variant in ScanCharters.scan_building_ids(catalog, habitat_id):
		var building_id := str(building_id_variant)
		var building := catalog.get_building(building_id)
		if building.is_empty():
			continue
		var building_type := catalog.get_building_type(building)
		var offers := BountyCharters.generate_offers_for_building(
			catalog,
			habitat_id,
			building_id,
			building_type,
			day,
			run_seed,
			next_index
		)
		next_index += offers.size()
		if not offers.is_empty():
			boards[building_id] = offers
	bounties.offers[habitat_id] = boards


func _try_complete_charters(session: GameSession, catalog: Catalog, habitat_id: String) -> void:
	if habitat_id.is_empty():
		return
	var current_ship := session.get_current_owned_ship()
	if current_ship == null:
		return

	var completed: Array = []
	for entry_variant in passengers.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("destination_habitat_id", "")) != habitat_id:
			continue
		if str(entry.get("ship_id", "")) != current_ship.id:
			continue
		completed.append(str(entry.get("charter_id", "")))

	for charter_id in completed:
		_resolve_passenger_charter_on_dock(session, catalog, charter_id)


func _try_complete_freight_charters(session: GameSession, catalog: Catalog, habitat_id: String) -> void:
	if habitat_id.is_empty():
		return
	var current_ship := session.get_current_owned_ship()
	if current_ship == null:
		return

	var completed: Array = []
	for entry_variant in freight.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("destination_habitat_id", "")) != habitat_id:
			continue
		if str(entry.get("ship_id", "")) != current_ship.id:
			continue
		completed.append(str(entry.get("charter_id", "")))

	for charter_id in completed:
		_resolve_freight_charter_on_dock(session, catalog, charter_id)


func _try_complete_scan_charters(session: GameSession, catalog: Catalog, habitat_id: String) -> void:
	if habitat_id.is_empty():
		return
	var current_ship := session.get_current_owned_ship()
	if current_ship == null:
		return

	var completed: Array = []
	for entry_variant in scans.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("origin_habitat_id", "")) != habitat_id:
			continue
		if str(entry.get("ship_id", "")) != current_ship.id:
			continue
		if not ScanCharters.charter_satisfied(session, entry):
			continue
		completed.append(str(entry.get("charter_id", "")))

	for charter_id in completed:
		_resolve_scan_charter_on_dock(session, catalog, charter_id)


func _enforce_late_scan_charters_at_dock(session: GameSession, catalog: Catalog) -> void:
	if not session.docked:
		return
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	var habitat_id := session.habitat_id
	var failed: Array = []
	for entry_variant in scans.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("ship_id", "")) != ship.id:
			continue
		if str(entry.get("origin_habitat_id", "")) != habitat_id:
			continue
		if not _charter_is_late(session, entry):
			continue
		if ScanCharters.charter_satisfied(session, entry):
			continue
		failed.append(str(entry.get("charter_id", "")))
	for charter_id in failed:
		_fail_scan_charter_missed_deadline(session, catalog, charter_id)


func _fail_scan_charter_missed_deadline(
	session: GameSession,
	catalog: Catalog,
	charter_id: String
) -> void:
	var charter := scans.find_accepted(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var penalty := ScanCharters.cancel_penalty(ScanCharters.config(catalog), reward)
	scans.remove_accepted(charter_id)
	CharterResolution.fail_missed_deadline(
		session,
		penalty,
		"Scan charter missed deadline. Fee d%d." % penalty
	)


func _resolve_scan_charter_on_dock(
	session: GameSession,
	catalog: Catalog,
	charter_id: String
) -> void:
	var charter := scans.find_accepted(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var site := str(charter.get("site_label", ""))
	var penalty := ScanCharters.cancel_penalty(ScanCharters.config(catalog), reward)
	scans.remove_accepted(charter_id)
	CharterResolution.settle_on_dock(
		session,
		charter,
		penalty,
		"Scan charter late to %s. Fee d%d." % [site, penalty],
		"Scan charter complete. +d%d." % reward,
		"Scan charter complete."
	)


func _try_complete_bounty_charters(session: GameSession, catalog: Catalog, habitat_id: String) -> void:
	if habitat_id.is_empty():
		return
	var current_ship := session.get_current_owned_ship()
	if current_ship == null:
		return

	var completed: Array = []
	for entry_variant in bounties.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("origin_habitat_id", "")) != habitat_id:
			continue
		if str(entry.get("ship_id", "")) != current_ship.id:
			continue
		if not BountyCharters.charter_satisfied(session, entry):
			continue
		completed.append(str(entry.get("charter_id", "")))

	for charter_id in completed:
		_resolve_bounty_charter_on_dock(session, catalog, charter_id)


func _enforce_late_bounty_charters_at_dock(session: GameSession, catalog: Catalog) -> void:
	if not session.docked:
		return
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	var habitat_id := session.habitat_id
	var failed: Array = []
	for entry_variant in bounties.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("ship_id", "")) != ship.id:
			continue
		if str(entry.get("origin_habitat_id", "")) != habitat_id:
			continue
		if not _charter_is_late(session, entry):
			continue
		if BountyCharters.charter_satisfied(session, entry):
			continue
		failed.append(str(entry.get("charter_id", "")))
	for charter_id in failed:
		_fail_bounty_charter_missed_deadline(session, catalog, charter_id)


func _fail_bounty_charter_missed_deadline(
	session: GameSession,
	catalog: Catalog,
	charter_id: String
) -> void:
	var charter := bounties.find_accepted(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var penalty := BountyCharters.cancel_penalty(BountyCharters.config(catalog), reward)
	bounties.remove_accepted(charter_id)
	CharterResolution.fail_missed_deadline(
		session,
		penalty,
		"Bounty missed deadline. Fee d%d." % penalty
	)


func _resolve_bounty_charter_on_dock(
	session: GameSession,
	catalog: Catalog,
	charter_id: String
) -> void:
	var charter := bounties.find_accepted(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var callsign := str(charter.get("target_callsign", ""))
	var penalty := BountyCharters.cancel_penalty(BountyCharters.config(catalog), reward)
	bounties.remove_accepted(charter_id)
	CharterResolution.settle_on_dock(
		session,
		charter,
		penalty,
		"Bounty late (%s). Fee d%d." % [callsign, penalty],
		"Bounty complete (%s). +d%d." % [callsign, reward],
		"Bounty complete (%s)." % callsign
	)


func _apply_charter_deadline(session: GameSession, charter: Dictionary) -> void:
	var hours := int(charter.get("deadline_hours", 0))
	if hours <= 0:
		return
	charter["deadline_gst"] = (
		session.gst_seconds + float(hours) * float(GalacticCalendar.SECONDS_PER_HOUR)
	)


func _charter_is_late(session: GameSession, charter: Dictionary) -> bool:
	return CharterResolution.is_late(session, charter)


func _enforce_late_passengers_at_dock(session: GameSession, catalog: Catalog) -> void:
	if not session.docked:
		return
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	var habitat_id := session.habitat_id
	var failed: Array = []
	for entry_variant in passengers.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("ship_id", "")) != ship.id:
			continue
		if not _charter_is_late(session, entry):
			continue
		if str(entry.get("destination_habitat_id", "")) == habitat_id:
			continue
		failed.append(str(entry.get("charter_id", "")))
	for charter_id in failed:
		_fail_passenger_charter_missed_deadline(session, catalog, charter_id)


func _fail_passenger_charter_missed_deadline(
	session: GameSession,
	catalog: Catalog,
	charter_id: String
) -> void:
	var charter := passengers.find_accepted(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var penalty := PassengerCharters.cancel_penalty(PassengerCharters.config(catalog), reward)
	passengers.remove_accepted(charter_id)
	CharterResolution.fail_missed_deadline(
		session,
		penalty,
		"Passengers left charter after deadline. Fee d%d." % penalty
	)


func _resolve_passenger_charter_on_dock(
	session: GameSession,
	catalog: Catalog,
	charter_id: String
) -> void:
	var charter := passengers.find_accepted(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var dest_name := str(charter.get("destination_name", ""))
	var penalty := PassengerCharters.cancel_penalty(PassengerCharters.config(catalog), reward)
	passengers.remove_accepted(charter_id)
	CharterResolution.settle_on_dock(
		session,
		charter,
		penalty,
		"Charter late to %s. Fee d%d." % [dest_name, penalty],
		"Charter complete to %s. +d%d." % [dest_name, reward],
		"Charter complete to %s." % dest_name
	)


func _resolve_freight_charter_on_dock(
	session: GameSession,
	catalog: Catalog,
	charter_id: String
) -> void:
	var charter := freight.find_accepted(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var dest_name := str(charter.get("destination_name", ""))
	var penalty := FreightCharters.cancel_penalty(FreightCharters.config(catalog), reward)
	freight.remove_accepted(charter_id)
	CharterResolution.settle_on_dock(
		session,
		charter,
		penalty,
		"Freight late to %s. Fee d%d." % [dest_name, penalty],
		"Freight delivered to %s. +d%d." % [dest_name, reward],
		"Freight delivered to %s." % dest_name
	)


func _charter_at_origin(session: GameSession, charter: Dictionary) -> bool:
	if not session.docked:
		return false
	if str(charter.get("origin_habitat_id", "")) != session.habitat_id:
		return false
	var ship := session.get_owned_ship(str(charter.get("ship_id", "")))
	if ship == null:
		return false
	return ship.location == session.habitat_id


func _freight_charter_at_origin(session: GameSession, charter: Dictionary) -> bool:
	return _charter_at_origin(session, charter)


static func _log_with_reputation_delta(session: GameSession, delta: int, message: String) -> void:
	CharterResolution.log_with_reputation_delta(session, delta, message)
