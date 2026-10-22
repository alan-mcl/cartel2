class_name MissionSubsystem
extends SimSubsystem

## Daily passenger and freight charter offers and accepted contracts.

var generated_day: int = -1
var offers_by_habitat: Dictionary = {}
var accepted: Array = []
var freight_offers_by_habitat: Dictionary = {}
var freight_accepted: Array = []
var scan_offers_by_habitat: Dictionary = {}
var scan_accepted: Array = []
var bounty_offers_by_habitat: Dictionary = {}
var bounty_accepted: Array = []
var _next_charter_id: int = 1
var _next_freight_charter_id: int = 1
var _next_scan_charter_id: int = 1
var _next_bounty_charter_id: int = 1


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


func list_offers(habitat_id: String, board: String) -> Array:
	var habitat_boards: Variant = offers_by_habitat.get(habitat_id, {})
	if typeof(habitat_boards) != TYPE_DICTIONARY:
		return []
	var offers: Variant = habitat_boards.get(board, [])
	if typeof(offers) != TYPE_ARRAY:
		return []
	return offers.duplicate(true)


func list_freight_offers(habitat_id: String) -> Array:
	var offers: Variant = freight_offers_by_habitat.get(habitat_id, [])
	if typeof(offers) != TYPE_ARRAY:
		return []
	return offers.duplicate(true)


func list_accepted() -> Array:
	return accepted.duplicate(true)


func list_freight_accepted() -> Array:
	return freight_accepted.duplicate(true)


func list_scan_offers(habitat_id: String, building_id: String) -> Array:
	var habitat_boards: Variant = scan_offers_by_habitat.get(habitat_id, {})
	if typeof(habitat_boards) != TYPE_DICTIONARY:
		return []
	var offers: Variant = habitat_boards.get(building_id, [])
	if typeof(offers) != TYPE_ARRAY:
		return []
	return offers.duplicate(true)


func list_scan_accepted() -> Array:
	return scan_accepted.duplicate(true)


func list_bounty_offers(habitat_id: String, building_id: String) -> Array:
	var habitat_boards: Variant = bounty_offers_by_habitat.get(habitat_id, {})
	if typeof(habitat_boards) != TYPE_DICTIONARY:
		return []
	var offers: Variant = habitat_boards.get(building_id, [])
	if typeof(offers) != TYPE_ARRAY:
		return []
	return offers.duplicate(true)


func list_bounty_accepted() -> Array:
	return bounty_accepted.duplicate(true)


func find_offer(offer_id: String) -> Dictionary:
	for habitat_boards in offers_by_habitat.values():
		if typeof(habitat_boards) != TYPE_DICTIONARY:
			continue
		for board in habitat_boards.keys():
			for offer_variant in habitat_boards[board]:
				if typeof(offer_variant) != TYPE_DICTIONARY:
					continue
				var offer: Dictionary = offer_variant
				if str(offer.get("id", "")) == offer_id:
					return offer.duplicate(true)
	return {}


func find_freight_offer(offer_id: String) -> Dictionary:
	for habitat_id in freight_offers_by_habitat.keys():
		for offer_variant in freight_offers_by_habitat[habitat_id]:
			if typeof(offer_variant) != TYPE_DICTIONARY:
				continue
			var offer: Dictionary = offer_variant
			if str(offer.get("id", "")) == offer_id:
				return offer.duplicate(true)
	return {}


func find_scan_offer(offer_id: String) -> Dictionary:
	for habitat_boards in scan_offers_by_habitat.values():
		if typeof(habitat_boards) != TYPE_DICTIONARY:
			continue
		for building_id in habitat_boards.keys():
			for offer_variant in habitat_boards[building_id]:
				if typeof(offer_variant) != TYPE_DICTIONARY:
					continue
				var offer: Dictionary = offer_variant
				if str(offer.get("id", "")) == offer_id:
					return offer.duplicate(true)
	return {}


func find_bounty_offer(offer_id: String) -> Dictionary:
	for habitat_boards in bounty_offers_by_habitat.values():
		if typeof(habitat_boards) != TYPE_DICTIONARY:
			continue
		for building_id in habitat_boards.keys():
			for offer_variant in habitat_boards[building_id]:
				if typeof(offer_variant) != TYPE_DICTIONARY:
					continue
				var offer: Dictionary = offer_variant
				if str(offer.get("id", "")) == offer_id:
					return offer.duplicate(true)
	return {}


func committed_passengers_for_ship(ship_id: String) -> int:
	var total := 0
	for entry_variant in accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("ship_id", "")) == ship_id:
			total += int(entry.get("quantity", 0))
	return total


func committed_freight_life_support_for_ship(ship_id: String) -> int:
	var total := 0
	for entry_variant in freight_accepted:
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
	for entry_variant in freight_accepted:
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

	_remove_offer(offer_id)
	var charter_id := "charter_%d" % _next_charter_id
	_next_charter_id += 1

	var charter := offer.duplicate(true)
	charter["charter_id"] = charter_id
	charter["ship_id"] = ship_id
	_apply_charter_deadline(session, charter)
	accepted.append(charter)

	session.last_log = (
		"Charter accepted: %s to %s for d%d."
		% [
			str(offer.get("role_title", "Passengers")),
			str(offer.get("destination_name", "")),
			int(offer.get("reward", 0)),
		]
	)
	if not session.player.sandbox:
		session.career.missions_accepted += 1
	session.changed.emit()
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

	_remove_freight_offer(offer_id)
	var charter_id := "freight_%d" % _next_freight_charter_id
	_next_freight_charter_id += 1

	var charter := offer.duplicate(true)
	charter["charter_id"] = charter_id
	charter["ship_id"] = ship_id
	_apply_charter_deadline(session, charter)
	freight_accepted.append(charter)

	session.last_log = (
		"Freight accepted to %s for d%d."
		% [str(offer.get("destination_name", "")), int(offer.get("reward", 0))]
	)
	if not session.player.sandbox:
		session.career.missions_accepted += 1
	session.changed.emit()
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

	_remove_scan_offer(offer_id)
	var charter_id := "scan_%d" % _next_scan_charter_id
	_next_scan_charter_id += 1

	var charter := offer.duplicate(true)
	charter["charter_id"] = charter_id
	charter["ship_id"] = ship_id
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

	scan_accepted.append(charter)
	session.last_log = (
		"Scan charter accepted: %s at %s for d%d."
		% [
			str(offer.get("designation", "Survey")),
			str(offer.get("site_label", "")),
			int(offer.get("reward", 0)),
		]
	)
	if not session.player.sandbox:
		session.career.missions_accepted += 1
	session.changed.emit()
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

	_remove_bounty_offer(offer_id)
	var charter_id := "bounty_%d" % _next_bounty_charter_id
	_next_bounty_charter_id += 1

	var charter := offer.duplicate(true)
	charter["charter_id"] = charter_id
	charter["ship_id"] = ship_id
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

	bounty_accepted.append(charter)
	session.last_log = (
		"Bounty accepted: %s at %s for d%d."
		% [
			str(offer.get("target_callsign", "")),
			str(offer.get("site_label", "")),
			int(offer.get("reward", 0)),
		]
	)
	if not session.player.sandbox:
		session.career.missions_accepted += 1
	session.changed.emit()
	return true


func cancel_charter(session: GameSession, catalog: Catalog, charter_id: String) -> bool:
	var charter := _find_charter(charter_id)
	if charter.is_empty():
		return false
	if not _charter_at_origin(session, charter):
		session.last_log = "Cannot cancel charter after departure."
		session.changed.emit()
		return false

	var cfg := PassengerCharters.config(catalog)
	var penalty := PassengerCharters.cancel_penalty(cfg, int(charter.get("reward", 0)))
	session.assess_penalty_credits(penalty)

	_remove_charter(charter_id)
	var log := "Charter cancelled. Fee d%d." % penalty if penalty > 0 else "Charter cancelled."
	_log_with_reputation_delta(session, -1, log)
	if not session.player.sandbox:
		session.career.missions_cancelled += 1
		session.career.record_mission_penalty(penalty)
	session.changed.emit()
	return true


func cancel_freight_charter(session: GameSession, catalog: Catalog, charter_id: String) -> bool:
	var charter := _find_freight_charter(charter_id)
	if charter.is_empty():
		return false
	if not _freight_charter_at_origin(session, charter):
		session.last_log = "Cannot cancel freight after departure."
		session.changed.emit()
		return false

	var cfg := FreightCharters.config(catalog)
	var penalty := FreightCharters.cancel_penalty(cfg, int(charter.get("reward", 0)))
	session.assess_penalty_credits(penalty)

	_remove_freight_charter(charter_id)
	var log := "Freight cancelled. Fee d%d." % penalty if penalty > 0 else "Freight cancelled."
	_log_with_reputation_delta(session, -1, log)
	if not session.player.sandbox:
		session.career.missions_cancelled += 1
		session.career.record_mission_penalty(penalty)
	session.changed.emit()
	return true


func cancel_charter_eligible(session: GameSession, charter_id: String) -> bool:
	var charter := _find_charter(charter_id)
	if charter.is_empty():
		return false
	return _charter_at_origin(session, charter)


func cancel_freight_charter_eligible(session: GameSession, charter_id: String) -> bool:
	var charter := _find_freight_charter(charter_id)
	if charter.is_empty():
		return false
	return _freight_charter_at_origin(session, charter)


func cancel_scan_charter(session: GameSession, catalog: Catalog, charter_id: String) -> bool:
	var charter := _find_scan_charter(charter_id)
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

	_remove_scan_charter(charter_id)
	var log := "Scan charter cancelled. Fee d%d." % penalty if penalty > 0 else "Scan charter cancelled."
	_log_with_reputation_delta(session, -1, log)
	if not session.player.sandbox:
		session.career.missions_cancelled += 1
		session.career.record_mission_penalty(penalty)
	session.changed.emit()
	return true


func cancel_scan_charter_eligible(session: GameSession, charter_id: String) -> bool:
	var charter := _find_scan_charter(charter_id)
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
	var charter := _find_bounty_charter(charter_id)
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

	_remove_bounty_charter(charter_id)
	var log := "Bounty cancelled. Fee d%d." % penalty if penalty > 0 else "Bounty cancelled."
	_log_with_reputation_delta(session, -1, log)
	if not session.player.sandbox:
		session.career.missions_cancelled += 1
		session.career.record_mission_penalty(penalty)
	session.changed.emit()
	return true


func cancel_bounty_charter_eligible(session: GameSession, charter_id: String) -> bool:
	var charter := _find_bounty_charter(charter_id)
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
		"offers_by_habitat": offers_by_habitat.duplicate(true),
		"accepted": accepted.duplicate(true),
		"freight_offers_by_habitat": freight_offers_by_habitat.duplicate(true),
		"freight_accepted": freight_accepted.duplicate(true),
		"scan_offers_by_habitat": scan_offers_by_habitat.duplicate(true),
		"scan_accepted": scan_accepted.duplicate(true),
		"bounty_offers_by_habitat": bounty_offers_by_habitat.duplicate(true),
		"bounty_accepted": bounty_accepted.duplicate(true),
		"next_charter_id": _next_charter_id,
		"next_freight_charter_id": _next_freight_charter_id,
		"next_scan_charter_id": _next_scan_charter_id,
		"next_bounty_charter_id": _next_bounty_charter_id,
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
		offers_by_habitat = {}
		accepted = []
		freight_offers_by_habitat = {}
		freight_accepted = []
		scan_offers_by_habitat = {}
		scan_accepted = []
		bounty_offers_by_habitat = {}
		bounty_accepted = []
		_next_charter_id = 1
		_next_freight_charter_id = 1
		_next_scan_charter_id = 1
		_next_bounty_charter_id = 1
		return
	generated_day = int(data.get("generated_day", -1))
	offers_by_habitat = data.get("offers_by_habitat", {})
	if typeof(offers_by_habitat) != TYPE_DICTIONARY:
		offers_by_habitat = {}
	freight_offers_by_habitat = data.get("freight_offers_by_habitat", {})
	if typeof(freight_offers_by_habitat) != TYPE_DICTIONARY:
		freight_offers_by_habitat = {}
	accepted = []
	for entry_variant in data.get("accepted", []):
		if typeof(entry_variant) == TYPE_DICTIONARY:
			accepted.append(entry_variant)
	freight_accepted = []
	for entry_variant in data.get("freight_accepted", []):
		if typeof(entry_variant) == TYPE_DICTIONARY:
			freight_accepted.append(entry_variant)
	scan_offers_by_habitat = data.get("scan_offers_by_habitat", {})
	if typeof(scan_offers_by_habitat) != TYPE_DICTIONARY:
		scan_offers_by_habitat = {}
	scan_accepted = []
	for entry_variant in data.get("scan_accepted", []):
		if typeof(entry_variant) == TYPE_DICTIONARY:
			scan_accepted.append(entry_variant)
	bounty_offers_by_habitat = data.get("bounty_offers_by_habitat", {})
	if typeof(bounty_offers_by_habitat) != TYPE_DICTIONARY:
		bounty_offers_by_habitat = {}
	bounty_accepted = []
	for entry_variant in data.get("bounty_accepted", []):
		if typeof(entry_variant) == TYPE_DICTIONARY:
			bounty_accepted.append(entry_variant)
	_next_charter_id = int(data.get("next_charter_id", 1))
	_next_freight_charter_id = int(data.get("next_freight_charter_id", 1))
	_next_scan_charter_id = int(data.get("next_scan_charter_id", 1))
	_next_bounty_charter_id = int(data.get("next_bounty_charter_id", 1))


func _invalidate_boards(day: int) -> void:
	generated_day = day
	offers_by_habitat = {}
	freight_offers_by_habitat = {}
	scan_offers_by_habitat = {}
	bounty_offers_by_habitat = {}


func _ensure_habitat_boards(
	session: GameSession,
	catalog: Catalog,
	habitat_id: String,
	day: int
) -> void:
	var need_passenger := not offers_by_habitat.has(habitat_id)
	var need_freight := not freight_offers_by_habitat.has(habitat_id)
	var need_scan := not scan_offers_by_habitat.has(habitat_id)
	var need_bounty := not bounty_offers_by_habitat.has(habitat_id)
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
		offers_by_habitat[habitat_id] = boards
	elif need_passenger and is_station:
		offers_by_habitat[habitat_id] = {}
	if need_freight and not is_station:
		freight_offers_by_habitat[habitat_id] = FreightCharters.generate_offers(
			catalog,
			habitat_id,
			day,
			freight_count,
			run_seed
		)
	elif need_freight and is_station:
		freight_offers_by_habitat[habitat_id] = {}
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
	scan_offers_by_habitat[habitat_id] = boards


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
	bounty_offers_by_habitat[habitat_id] = boards


func _try_complete_charters(session: GameSession, catalog: Catalog, habitat_id: String) -> void:
	if habitat_id.is_empty():
		return
	var current_ship := session.get_current_owned_ship()
	if current_ship == null:
		return

	var completed: Array = []
	for entry_variant in accepted:
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
	for entry_variant in freight_accepted:
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
	for entry_variant in scan_accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("origin_habitat_id", "")) != habitat_id:
			continue
		if str(entry.get("ship_id", "")) != current_ship.id:
			continue
		if not _scan_charter_satisfied(session, entry):
			continue
		completed.append(str(entry.get("charter_id", "")))

	for charter_id in completed:
		_resolve_scan_charter_on_dock(session, catalog, charter_id)


func _scan_charter_satisfied(session: GameSession, charter: Dictionary) -> bool:
	var contact_id := str(charter.get("scan_contact_id", ""))
	var sector_id := ScanCharters.scan_sector_for_contract(charter)
	var accepted_gst := float(charter.get("accepted_gst", 0.0))
	return session.player.scan_satisfies_contract(contact_id, sector_id, accepted_gst)


func _enforce_late_scan_charters_at_dock(session: GameSession, catalog: Catalog) -> void:
	if not session.docked:
		return
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	var habitat_id := session.habitat_id
	var failed: Array = []
	for entry_variant in scan_accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("ship_id", "")) != ship.id:
			continue
		if str(entry.get("origin_habitat_id", "")) != habitat_id:
			continue
		if not _charter_is_late(session, entry):
			continue
		if _scan_charter_satisfied(session, entry):
			continue
		failed.append(str(entry.get("charter_id", "")))
	for charter_id in failed:
		_fail_scan_charter_missed_deadline(session, catalog, charter_id)


func _fail_scan_charter_missed_deadline(
	session: GameSession,
	catalog: Catalog,
	charter_id: String
) -> void:
	var charter := _find_scan_charter(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var cfg := ScanCharters.config(catalog)
	var penalty := ScanCharters.cancel_penalty(cfg, reward)
	_remove_scan_charter(charter_id)
	session.assess_penalty_credits(penalty)
	_log_with_reputation_delta(
		session,
		-1,
		"Scan charter missed deadline. Fee d%d." % penalty
	)
	if not session.player.sandbox:
		session.career.missions_missed_deadline += 1
		session.career.record_mission_penalty(penalty)
	session.changed.emit()


func _resolve_scan_charter_on_dock(
	session: GameSession,
	catalog: Catalog,
	charter_id: String
) -> void:
	var charter := _find_scan_charter(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var site := str(charter.get("site_label", ""))
	_remove_scan_charter(charter_id)
	if _charter_is_late(session, charter):
		var penalty := ScanCharters.cancel_penalty(ScanCharters.config(catalog), reward)
		session.assess_penalty_credits(penalty)
		_log_with_reputation_delta(
			session,
			-1,
			"Scan charter late to %s. Fee d%d." % [site, penalty]
		)
		if not session.player.sandbox:
			session.career.missions_late += 1
			session.career.record_mission_penalty(penalty)
	elif reward > 0:
		session.add_credits(reward)
		_log_with_reputation_delta(
			session,
			1,
			"Scan charter complete. +d%d." % reward
		)
		if not session.player.sandbox:
			session.career.missions_completed_on_time += 1
			session.career.record_charter_reward(reward)
	else:
		_log_with_reputation_delta(session, 1, "Scan charter complete.")
		if not session.player.sandbox:
			session.career.missions_completed_on_time += 1
	session.changed.emit()


func _try_complete_bounty_charters(session: GameSession, catalog: Catalog, habitat_id: String) -> void:
	if habitat_id.is_empty():
		return
	var current_ship := session.get_current_owned_ship()
	if current_ship == null:
		return

	var completed: Array = []
	for entry_variant in bounty_accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("origin_habitat_id", "")) != habitat_id:
			continue
		if str(entry.get("ship_id", "")) != current_ship.id:
			continue
		if not _bounty_charter_satisfied(session, entry):
			continue
		completed.append(str(entry.get("charter_id", "")))

	for charter_id in completed:
		_resolve_bounty_charter_on_dock(session, catalog, charter_id)


func _bounty_charter_satisfied(session: GameSession, charter: Dictionary) -> bool:
	return BountyCharters.charter_satisfied(session, charter)


func _enforce_late_bounty_charters_at_dock(session: GameSession, catalog: Catalog) -> void:
	if not session.docked:
		return
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	var habitat_id := session.habitat_id
	var failed: Array = []
	for entry_variant in bounty_accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("ship_id", "")) != ship.id:
			continue
		if str(entry.get("origin_habitat_id", "")) != habitat_id:
			continue
		if not _charter_is_late(session, entry):
			continue
		if _bounty_charter_satisfied(session, entry):
			continue
		failed.append(str(entry.get("charter_id", "")))
	for charter_id in failed:
		_fail_bounty_charter_missed_deadline(session, catalog, charter_id)


func _fail_bounty_charter_missed_deadline(
	session: GameSession,
	catalog: Catalog,
	charter_id: String
) -> void:
	var charter := _find_bounty_charter(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var cfg := BountyCharters.config(catalog)
	var penalty := BountyCharters.cancel_penalty(cfg, reward)
	_remove_bounty_charter(charter_id)
	session.assess_penalty_credits(penalty)
	_log_with_reputation_delta(
		session,
		-1,
		"Bounty missed deadline. Fee d%d." % penalty
	)
	if not session.player.sandbox:
		session.career.missions_missed_deadline += 1
		session.career.record_mission_penalty(penalty)
	session.changed.emit()


func _resolve_bounty_charter_on_dock(
	session: GameSession,
	catalog: Catalog,
	charter_id: String
) -> void:
	var charter := _find_bounty_charter(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var callsign := str(charter.get("target_callsign", ""))
	_remove_bounty_charter(charter_id)
	if _charter_is_late(session, charter):
		var penalty := BountyCharters.cancel_penalty(BountyCharters.config(catalog), reward)
		session.assess_penalty_credits(penalty)
		_log_with_reputation_delta(
			session,
			-1,
			"Bounty late (%s). Fee d%d." % [callsign, penalty]
		)
		if not session.player.sandbox:
			session.career.missions_late += 1
			session.career.record_mission_penalty(penalty)
	elif reward > 0:
		session.add_credits(reward)
		_log_with_reputation_delta(
			session,
			1,
			"Bounty complete (%s). +d%d." % [callsign, reward]
		)
		if not session.player.sandbox:
			session.career.missions_completed_on_time += 1
			session.career.record_charter_reward(reward)
	else:
		_log_with_reputation_delta(session, 1, "Bounty complete (%s)." % callsign)
		if not session.player.sandbox:
			session.career.missions_completed_on_time += 1
	session.changed.emit()


func _apply_charter_deadline(session: GameSession, charter: Dictionary) -> void:
	var hours := int(charter.get("deadline_hours", 0))
	if hours <= 0:
		return
	charter["deadline_gst"] = (
		session.gst_seconds + float(hours) * float(GalacticCalendar.SECONDS_PER_HOUR)
	)


func _charter_is_late(session: GameSession, charter: Dictionary) -> bool:
	if not charter.has("deadline_gst"):
		return false
	return session.gst_seconds > float(charter.get("deadline_gst", 0.0))


func _enforce_late_passengers_at_dock(session: GameSession, catalog: Catalog) -> void:
	if not session.docked:
		return
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	var habitat_id := session.habitat_id
	var failed: Array = []
	for entry_variant in accepted:
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
	var charter := _find_charter(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var cfg := PassengerCharters.config(catalog)
	var penalty := PassengerCharters.cancel_penalty(cfg, reward)
	_remove_charter(charter_id)
	session.assess_penalty_credits(penalty)
	_log_with_reputation_delta(
		session,
		-1,
		"Passengers left charter after deadline. Fee d%d." % penalty
	)
	if not session.player.sandbox:
		session.career.missions_missed_deadline += 1
		session.career.record_mission_penalty(penalty)
	session.changed.emit()


func _resolve_passenger_charter_on_dock(
	session: GameSession,
	catalog: Catalog,
	charter_id: String
) -> void:
	var charter := _find_charter(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var dest_name := str(charter.get("destination_name", ""))
	_remove_charter(charter_id)
	if _charter_is_late(session, charter):
		var penalty := PassengerCharters.cancel_penalty(PassengerCharters.config(catalog), reward)
		session.assess_penalty_credits(penalty)
		_log_with_reputation_delta(
			session,
			-1,
			"Charter late to %s. Fee d%d." % [dest_name, penalty]
		)
		if not session.player.sandbox:
			session.career.missions_late += 1
			session.career.record_mission_penalty(penalty)
	elif reward > 0:
		session.add_credits(reward)
		_log_with_reputation_delta(
			session,
			1,
			"Charter complete to %s. +d%d." % [dest_name, reward]
		)
		if not session.player.sandbox:
			session.career.missions_completed_on_time += 1
			session.career.record_charter_reward(reward)
	else:
		_log_with_reputation_delta(session, 1, "Charter complete to %s." % dest_name)
		if not session.player.sandbox:
			session.career.missions_completed_on_time += 1
	session.changed.emit()


func _resolve_freight_charter_on_dock(
	session: GameSession,
	catalog: Catalog,
	charter_id: String
) -> void:
	var charter := _find_freight_charter(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	var dest_name := str(charter.get("destination_name", ""))
	_remove_freight_charter(charter_id)
	if _charter_is_late(session, charter):
		var penalty := FreightCharters.cancel_penalty(FreightCharters.config(catalog), reward)
		session.assess_penalty_credits(penalty)
		_log_with_reputation_delta(
			session,
			-1,
			"Freight late to %s. Fee d%d." % [dest_name, penalty]
		)
		if not session.player.sandbox:
			session.career.missions_late += 1
			session.career.record_mission_penalty(penalty)
	elif reward > 0:
		session.add_credits(reward)
		_log_with_reputation_delta(
			session,
			1,
			"Freight delivered to %s. +d%d." % [dest_name, reward]
		)
		if not session.player.sandbox:
			session.career.missions_completed_on_time += 1
			session.career.record_charter_reward(reward)
	else:
		_log_with_reputation_delta(session, 1, "Freight delivered to %s." % dest_name)
		if not session.player.sandbox:
			session.career.missions_completed_on_time += 1
	session.changed.emit()


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


func _find_charter(charter_id: String) -> Dictionary:
	for entry_variant in accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("charter_id", "")) == charter_id:
			return entry
	return {}


func _find_freight_charter(charter_id: String) -> Dictionary:
	for entry_variant in freight_accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("charter_id", "")) == charter_id:
			return entry
	return {}


func _find_scan_charter(charter_id: String) -> Dictionary:
	for entry_variant in scan_accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("charter_id", "")) == charter_id:
			return entry
	return {}


func _find_bounty_charter(charter_id: String) -> Dictionary:
	for entry_variant in bounty_accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("charter_id", "")) == charter_id:
			return entry
	return {}


func _remove_charter(charter_id: String) -> void:
	for index in accepted.size():
		var entry: Dictionary = accepted[index]
		if str(entry.get("charter_id", "")) == charter_id:
			accepted.remove_at(index)
			return


func _remove_freight_charter(charter_id: String) -> void:
	for index in freight_accepted.size():
		var entry: Dictionary = freight_accepted[index]
		if str(entry.get("charter_id", "")) == charter_id:
			freight_accepted.remove_at(index)
			return


func _remove_scan_charter(charter_id: String) -> void:
	for index in scan_accepted.size():
		var entry: Dictionary = scan_accepted[index]
		if str(entry.get("charter_id", "")) == charter_id:
			scan_accepted.remove_at(index)
			return


func _remove_bounty_charter(charter_id: String) -> void:
	for index in bounty_accepted.size():
		var entry: Dictionary = bounty_accepted[index]
		if str(entry.get("charter_id", "")) == charter_id:
			bounty_accepted.remove_at(index)
			return


func _remove_offer(offer_id: String) -> void:
	for habitat_id in offers_by_habitat.keys():
		var habitat_boards: Dictionary = offers_by_habitat[habitat_id]
		for board in habitat_boards.keys():
			var offers: Array = habitat_boards[board]
			for index in offers.size():
				var offer: Dictionary = offers[index]
				if str(offer.get("id", "")) == offer_id:
					offers.remove_at(index)
					return


func _remove_freight_offer(offer_id: String) -> void:
	for habitat_id in freight_offers_by_habitat.keys():
		var offers: Array = freight_offers_by_habitat[habitat_id]
		for index in offers.size():
			var offer: Dictionary = offers[index]
			if str(offer.get("id", "")) == offer_id:
				offers.remove_at(index)
				return


func _remove_scan_offer(offer_id: String) -> void:
	for habitat_id in scan_offers_by_habitat.keys():
		var habitat_boards: Dictionary = scan_offers_by_habitat[habitat_id]
		for building_id in habitat_boards.keys():
			var offers: Array = habitat_boards[building_id]
			for index in offers.size():
				var offer: Dictionary = offers[index]
				if str(offer.get("id", "")) == offer_id:
					offers.remove_at(index)
					return


func _remove_bounty_offer(offer_id: String) -> void:
	for habitat_id in bounty_offers_by_habitat.keys():
		var habitat_boards: Dictionary = bounty_offers_by_habitat[habitat_id]
		for building_id in habitat_boards.keys():
			var offers: Array = habitat_boards[building_id]
			for index in offers.size():
				var offer: Dictionary = offers[index]
				if str(offer.get("id", "")) == offer_id:
					offers.remove_at(index)
					return


static func _log_with_reputation_delta(session: GameSession, delta: int, message: String) -> void:
	var applied := session.player.adjust_reputation(delta)
	if applied > 0:
		session.last_log = "%s Reputation +%d." % [message, applied]
	elif applied < 0:
		session.last_log = "%s Reputation %d." % [message, applied]
	else:
		session.last_log = message
