class_name MissionSubsystem
extends SimSubsystem

## Daily passenger charter offers and accepted contracts.

var generated_day: int = -1
var offers_by_habitat: Dictionary = {}
var accepted: Array = []
var _next_charter_id: int = 1


func _init() -> void:
	id = "missions"
	save_version = 2


func on_day(session: GameSession, catalog: Catalog, day: int) -> void:
	_refresh_boards(session, catalog, day)


func on_event(session: GameSession, catalog: Catalog, evt: Dictionary) -> void:
	if session == null or evt.is_empty():
		return
	if str(evt.get("type", "")) != SimEvent.DOCKED:
		return
	_try_complete_charters(session, catalog, str(evt.get("habitat_id", "")))


func ensure_boards(session: GameSession, catalog: Catalog) -> void:
	var day := CommodityEconomy.gst_day(session.gst_seconds)
	if generated_day != day:
		_refresh_boards(session, catalog, day)


func list_offers(habitat_id: String, board: String) -> Array:
	var habitat_boards: Variant = offers_by_habitat.get(habitat_id, {})
	if typeof(habitat_boards) != TYPE_DICTIONARY:
		return []
	var offers: Variant = habitat_boards.get(board, [])
	if typeof(offers) != TYPE_ARRAY:
		return []
	return offers.duplicate(true)


func list_accepted() -> Array:
	return accepted.duplicate(true)


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


func committed_passengers_for_ship(ship_id: String) -> int:
	var total := 0
	for entry_variant in accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("ship_id", "")) == ship_id:
			total += int(entry.get("quantity", 0))
	return total


func evaluate_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> Dictionary:
	var offer := find_offer(offer_id)
	if offer.is_empty():
		return {"ok": false, "reason": "Offer no longer available."}
	var committed := committed_passengers_for_ship(ship_id)
	return PassengerCharters.evaluate_offer_for_ship(session, catalog, offer, ship_id, committed)


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
	if penalty > 0 and not session.try_spend_credits(penalty):
		session.last_log = "Cannot pay cancellation fee (d%d)." % penalty
		session.changed.emit()
		return false

	_remove_charter(charter_id)
	if penalty > 0:
		session.last_log = "Charter cancelled. Fee d%d." % penalty
	else:
		session.last_log = "Charter cancelled."
	session.changed.emit()
	return true


func cancel_charter_eligible(session: GameSession, charter_id: String) -> bool:
	var charter := _find_charter(charter_id)
	if charter.is_empty():
		return false
	return _charter_at_origin(session, charter)


func to_dict() -> Dictionary:
	return {
		"generated_day": generated_day,
		"offers_by_habitat": offers_by_habitat.duplicate(true),
		"accepted": accepted.duplicate(true),
		"next_charter_id": _next_charter_id,
	}


func migrate(data: Dictionary, from_version: int) -> Dictionary:
	if from_version < save_version:
		return {}
	return data.duplicate(true)


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		generated_day = -1
		offers_by_habitat = {}
		accepted = []
		_next_charter_id = 1
		return
	generated_day = int(data.get("generated_day", -1))
	offers_by_habitat = data.get("offers_by_habitat", {})
	if typeof(offers_by_habitat) != TYPE_DICTIONARY:
		offers_by_habitat = {}
	accepted = []
	for entry_variant in data.get("accepted", []):
		if typeof(entry_variant) == TYPE_DICTIONARY:
			accepted.append(entry_variant)
	_next_charter_id = int(data.get("next_charter_id", 1))


func _refresh_boards(session: GameSession, catalog: Catalog, day: int) -> void:
	generated_day = day
	offers_by_habitat = {}
	var cfg := PassengerCharters.config(catalog)
	var terminal_count := int(cfg.get("terminal_offers_per_day", 4))
	var bar_count := int(cfg.get("bar_offers_per_day", 2))
	var run_seed := session.run_seed

	for habitat in catalog.list_habitat_dicts():
		if typeof(habitat) != TYPE_DICTIONARY:
			continue
		var habitat_id := str(habitat.get("id", ""))
		if habitat_id.is_empty():
			continue
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


func _try_complete_charters(session: GameSession, _catalog: Catalog, habitat_id: String) -> void:
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
		_complete_charter(session, charter_id)


func _complete_charter(session: GameSession, charter_id: String) -> void:
	var charter := _find_charter(charter_id)
	if charter.is_empty():
		return
	var reward := int(charter.get("reward", 0))
	_remove_charter(charter_id)
	if reward > 0:
		session.add_credits(reward)
	session.last_log = "Charter complete to %s. +d%d." % [
		str(charter.get("destination_name", "")),
		reward,
	]
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


func _find_charter(charter_id: String) -> Dictionary:
	for entry_variant in accepted:
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
