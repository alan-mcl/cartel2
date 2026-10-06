class_name MissionSubsystem
extends SimSubsystem

## Daily passenger and freight charter offers and accepted contracts.

var generated_day: int = -1
var offers_by_habitat: Dictionary = {}
var accepted: Array = []
var freight_offers_by_habitat: Dictionary = {}
var freight_accepted: Array = []
var _next_charter_id: int = 1
var _next_freight_charter_id: int = 1


func _init() -> void:
	id = "missions"
	save_version = 3


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
	_try_complete_charters(session, catalog, habitat_id)
	_try_complete_freight_charters(session, catalog, habitat_id)


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


func to_dict() -> Dictionary:
	return {
		"generated_day": generated_day,
		"offers_by_habitat": offers_by_habitat.duplicate(true),
		"accepted": accepted.duplicate(true),
		"freight_offers_by_habitat": freight_offers_by_habitat.duplicate(true),
		"freight_accepted": freight_accepted.duplicate(true),
		"next_charter_id": _next_charter_id,
		"next_freight_charter_id": _next_freight_charter_id,
	}


func migrate(data: Dictionary, from_version: int) -> Dictionary:
	if from_version >= save_version:
		return data.duplicate(true)
	if from_version == 2 and save_version == 3:
		var out := data.duplicate(true)
		if not out.has("freight_offers_by_habitat"):
			out["freight_offers_by_habitat"] = {}
		if not out.has("freight_accepted"):
			out["freight_accepted"] = []
		if not out.has("next_freight_charter_id"):
			out["next_freight_charter_id"] = 1
		return out
	return {}


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		generated_day = -1
		offers_by_habitat = {}
		accepted = []
		freight_offers_by_habitat = {}
		freight_accepted = []
		_next_charter_id = 1
		_next_freight_charter_id = 1
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
	_next_charter_id = int(data.get("next_charter_id", 1))
	_next_freight_charter_id = int(data.get("next_freight_charter_id", 1))


func _invalidate_boards(day: int) -> void:
	generated_day = day
	offers_by_habitat = {}
	freight_offers_by_habitat = {}


func _ensure_habitat_boards(
	session: GameSession,
	catalog: Catalog,
	habitat_id: String,
	day: int
) -> void:
	var need_passenger := not offers_by_habitat.has(habitat_id)
	var need_freight := not freight_offers_by_habitat.has(habitat_id)
	if not need_passenger and not need_freight:
		return
	var cfg := PassengerCharters.config(catalog)
	var terminal_count := int(cfg.get("terminal_offers_per_day", 4))
	var bar_count := int(cfg.get("bar_offers_per_day", 2))
	var freight_cfg := FreightCharters.config(catalog)
	var freight_count := int(freight_cfg.get("offers_per_day", 4))
	var run_seed := session.run_seed
	if need_passenger:
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
	if need_freight:
		freight_offers_by_habitat[habitat_id] = FreightCharters.generate_offers(
			catalog,
			habitat_id,
			day,
			freight_count,
			run_seed
		)


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
	elif reward > 0:
		session.add_credits(reward)
		_log_with_reputation_delta(
			session,
			1,
			"Charter complete to %s. +d%d." % [dest_name, reward]
		)
	else:
		_log_with_reputation_delta(session, 1, "Charter complete to %s." % dest_name)
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
	elif reward > 0:
		session.add_credits(reward)
		_log_with_reputation_delta(
			session,
			1,
			"Freight delivered to %s. +d%d." % [dest_name, reward]
		)
	else:
		_log_with_reputation_delta(session, 1, "Freight delivered to %s." % dest_name)
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


static func _log_with_reputation_delta(session: GameSession, delta: int, message: String) -> void:
	var applied := session.player.adjust_reputation(delta)
	if applied > 0:
		session.last_log = "%s Reputation +%d." % [message, applied]
	elif applied < 0:
		session.last_log = "%s Reputation %d." % [message, applied]
	else:
		session.last_log = message
