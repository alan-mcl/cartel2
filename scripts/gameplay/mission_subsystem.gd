class_name MissionSubsystem
extends SimSubsystem

## Daily passenger and freight charter offers and accepted contracts.

var generated_day: int = -1
var passengers := CharterBook.new("charter_")
var freight := CharterBook.new("freight_", false)
var scans := CharterBook.new("scan_")
var bounties := CharterBook.new("bounty_")
var retrievals := CharterBook.new("retrieval_")
var bar_rounds_by_building: Dictionary = {}
var _pursuit_spawned_charter_id: String = ""
var _charter_kind_configs: Array = []


func _init() -> void:
	id = "missions"
	save_version = 8
	_charter_kind_configs = CharterKind.all_configs()


func on_day(_session: GameSession, _catalog: Catalog, day: int) -> void:
	_invalidate_boards(day)


func on_hour(session: GameSession, catalog: Catalog, _hour: int) -> void:
	_enforce_late_passengers_at_dock(session, catalog)


func on_tick(session: GameSession, catalog: Catalog, delta: float) -> void:
	if session == null or session.world.docked or delta <= 0.0:
		return
	_tick_bounty_pursuits(session, catalog, delta)


func on_event(session: GameSession, catalog: Catalog, evt: Dictionary) -> void:
	if session == null or evt.is_empty():
		return
	if str(evt.get("type", "")) != SimEvent.DOCKED:
		return
	var habitat_id := str(evt.get("habitat_id", ""))
	_enforce_late_passengers_at_dock(session, catalog)
	for kind_variant in _charter_kind_configs:
		var kind: CharterKind = kind_variant
		if kind.enforce_late_origin_unsatisfied():
			_enforce_late_origin_charters_at_dock(session, catalog, kind)
	for kind_variant in _charter_kind_configs:
		var kind_complete: CharterKind = kind_variant
		_try_complete_kind(session, catalog, habitat_id, kind_complete)


func ensure_boards(session: GameSession, catalog: Catalog) -> void:
	var day := CommodityEconomy.gst_day(session.world.gst_seconds)
	if generated_day != day:
		_invalidate_boards(day)
	var habitat_id := str(session.world.habitat_id)
	if habitat_id.is_empty():
		return
	_ensure_habitat_boards(session, catalog, habitat_id, day)


func bar_round_cost_for_habitat(catalog: Catalog, habitat_id: String) -> int:
	var pop := DealerStock.population_for_habitat(catalog, habitat_id)
	return DealerStock.bar_round_cost(pop)


func bar_round_used_today(building_id: String, day: int) -> bool:
	if building_id.is_empty():
		return false
	return int(bar_rounds_by_building.get(building_id, -1)) == day


func buy_bar_round(session: GameSession, catalog: Catalog, building_id: String) -> Dictionary:
	var result := {"ok": false, "reason": "", "cost": 0}
	if session == null or catalog == null:
		result["reason"] = "unavailable"
		return result
	if not session.world.docked:
		result["reason"] = "not_docked"
		return result
	var habitat_id := str(session.world.habitat_id)
	if habitat_id.is_empty():
		result["reason"] = "no_habitat"
		return result
	var building := catalog.get_building(building_id)
	if building.is_empty():
		result["reason"] = "unknown_building"
		return result
	if catalog.get_building_type(building) != ScanCharters.BOARD_BAR:
		result["reason"] = "not_a_bar"
		return result
	if not catalog.habitat_allows_building(catalog.get_habitat(habitat_id), building_id):
		result["reason"] = "wrong_habitat"
		return result
	var day := CommodityEconomy.gst_day(session.world.gst_seconds)
	if bar_round_used_today(building_id, day):
		result["reason"] = "already_bought"
		return result
	var cost := bar_round_cost_for_habitat(catalog, habitat_id)
	result["cost"] = cost
	if session.wallet.credits < cost:
		result["reason"] = "insufficient_credits"
		return result
	ensure_boards(session, catalog)
	if not session.try_spend_credits(cost):
		result["reason"] = "insufficient_credits"
		return result
	var round_seed := DeskCharterBoards.bar_round_run_seed(session.world.run_seed, building_id)
	var start := DeskCharterBoards.BAR_ROUND_OFFER_INDEX_START
	var slices := DeskCharterBoards.generate_bar_building(
		catalog,
		habitat_id,
		building_id,
		day,
		round_seed,
		start,
		start,
		start,
		start
	)
	_apply_bar_board_slices(habitat_id, building_id, slices)
	bar_rounds_by_building[building_id] = day
	session.player.last_log = "You bought a round for d%d. Fresh charters are on the board." % cost
	session.changed.emit()
	result["ok"] = true
	return result


func _apply_bar_board_slices(habitat_id: String, building_id: String, slices: Dictionary) -> void:
	_set_habitat_board_slice(passengers, habitat_id, building_id, slices.get("passenger", []))
	_set_habitat_board_slice(freight, habitat_id, building_id, slices.get("freight", []))
	_set_habitat_board_slice(scans, habitat_id, building_id, slices.get("scan", []))
	_set_habitat_board_slice(bounties, habitat_id, building_id, slices.get("bounty", []))
	_set_habitat_board_slice(retrievals, habitat_id, building_id, slices.get("retrieval", []))


func _set_habitat_board_slice(book: CharterBook, habitat_id: String, board_key: String, rows: Array) -> void:
	if not book.offers.has(habitat_id):
		book.offers[habitat_id] = {}
	var habitat_boards: Dictionary = book.offers[habitat_id]
	if typeof(rows) != TYPE_ARRAY or rows.is_empty():
		habitat_boards.erase(board_key)
	else:
		habitat_boards[board_key] = rows


## Harness/tests that inject offers for one book call this so `ensure_boards` does not rebuild the habitat.
func mark_habitat_boards_materialised(habitat_id: String) -> void:
	if habitat_id.is_empty():
		return
	if not passengers.offers.has(habitat_id):
		passengers.offers[habitat_id] = {}
	if not freight.offers.has(habitat_id):
		freight.offers[habitat_id] = {}
	if not scans.offers.has(habitat_id):
		scans.offers[habitat_id] = {}
	if not bounties.offers.has(habitat_id):
		bounties.offers[habitat_id] = {}
	if not retrievals.offers.has(habitat_id):
		retrievals.offers[habitat_id] = {}


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

## Dev harness only. One peacekeeping retrieval offer, built by RetrievalCharters, replaces today's board.
func seed_harness_retrieval_offer(
	session: GameSession,
	catalog: Catalog,
	habitat_id: String,
	type_key: String,
	volatile_site: Dictionary,
	rng: RandomNumberGenerator,
	volatile_n: int = 4
) -> Dictionary:
	ensure_boards(session, catalog)
	var sector_id := catalog.get_habitat_sector_id(habitat_id)
	var building_id := ScanCharters.peacekeeping_building_id(sector_id)
	var offer := RetrievalCharters.build_pinned_offer(
		catalog,
		habitat_id,
		building_id,
		rng,
		0,
		type_key,
		volatile_site,
		volatile_n
	)
	if offer.is_empty():
		return {}
	retrievals.offers[habitat_id] = {building_id: [offer]}
	return offer


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
	return freight.list_board(habitat_id, DeskCharterBoards.FREIGHT_BOARD_TERMINAL)


func list_bar_freight_offers(habitat_id: String, building_id: String) -> Array:
	return freight.list_board(habitat_id, building_id)


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


func list_retrieval_offers(habitat_id: String, building_id: String) -> Array:
	return retrievals.list_board(habitat_id, building_id)


func list_retrieval_accepted() -> Array:
	return retrievals.list_accepted()



func list_plot_gigs(habitat_id: String, desk: String, session: GameSession, catalog: Catalog) -> Array:
	var plotlines := _plotline_subsystem(session)
	if plotlines == null:
		return []
	return plotlines.contribute_gigs(desk, habitat_id, session, catalog)


func _plotline_subsystem(session: GameSession) -> PlotlineSubsystem:
	if session == null:
		return null
	return session.bound_plotlines


func find_offer(offer_id: String) -> Dictionary:
	return passengers.find_offer(offer_id)


func find_freight_offer(offer_id: String) -> Dictionary:
	return freight.find_offer(offer_id)


func find_scan_offer(offer_id: String) -> Dictionary:
	return scans.find_offer(offer_id)


func find_bounty_offer(offer_id: String) -> Dictionary:
	return bounties.find_offer(offer_id)


func find_retrieval_offer(offer_id: String) -> Dictionary:
	return retrievals.find_offer(offer_id)


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



func evaluate_retrieval_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> Dictionary:
	var offer := find_retrieval_offer(offer_id)
	if offer.is_empty():
		return {"ok": false, "reason": "Offer no longer available."}
	return RetrievalCharters.evaluate_offer_for_ship(session, catalog, offer, ship_id)


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
	if not charter.has("accepted_gst"):
		charter["accepted_gst"] = session.world.gst_seconds
	book.accepted.append(charter)
	session.player.last_log = log_line
	if not session.player.sandbox:
		session.career.missions_accepted += 1
	session.changed.emit()


func _kind_config(type: CharterKind.Type) -> CharterKind:
	for kind_variant in _charter_kind_configs:
		var kind: CharterKind = kind_variant
		if kind.kind_type == type:
			return kind
	return null


func _evaluate_for_kind(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String,
	kind: CharterKind
) -> Dictionary:
	match kind.kind_type:
		CharterKind.Type.PASSENGER:
			return evaluate_offer(session, catalog, offer_id, ship_id)
		CharterKind.Type.FREIGHT:
			return evaluate_freight_offer(session, catalog, offer_id, ship_id)
		CharterKind.Type.SCAN:
			return evaluate_scan_offer(session, catalog, offer_id, ship_id)
		CharterKind.Type.BOUNTY:
			return evaluate_bounty_offer(session, catalog, offer_id, ship_id)
		CharterKind.Type.RETRIEVAL:
			return evaluate_retrieval_offer(session, catalog, offer_id, ship_id)
	return {"ok": false, "reason": kind.reject_reason_default()}


func _accept_kind(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String,
	kind: CharterKind
) -> bool:
	ensure_boards(session, catalog)
	var check := _evaluate_for_kind(session, catalog, offer_id, ship_id, kind)
	if not bool(check.get("ok", false)):
		session.player.last_log = str(check.get("reason", kind.reject_reason_default()))
		session.changed.emit()
		return false
	var book := kind.book_for(self)
	var offer := book.find_offer(offer_id)
	if offer.is_empty():
		return false
	var charter := _take_offer(book, offer, ship_id)
	if not kind.prepare_accept(session, catalog, offer, charter, self):
		var failure_log := kind.grant_failure_log()
		if not failure_log.is_empty():
			session.player.last_log = failure_log
			session.changed.emit()
		return false
	_commit_accepted(session, book, charter, kind.accept_log(offer))
	return true


func _cancel_at_origin(session: GameSession, charter: Dictionary) -> bool:
	return _charter_at_origin(session, charter)


func _cancel_kind(session: GameSession, catalog: Catalog, charter_id: String, kind: CharterKind) -> bool:
	var book := kind.book_for(self)
	var charter := book.find_accepted(charter_id)
	if charter.is_empty():
		return false
	if not kind.cancel_eligible(session, charter, Callable(self, "_cancel_at_origin")):
		session.player.last_log = kind.cancel_blocked_log()
		session.changed.emit()
		return false
	var penalty := kind.cancel_penalty(catalog, int(charter.get("reward", 0)))
	session.assess_penalty_credits(penalty)
	kind.discard_volatile_on_cancel(session, charter)
	kind.clear_bounty_contract_on_cancel(session, charter)
	book.remove_accepted(charter_id)
	_log_with_reputation_delta(session, -1, kind.cancel_log(penalty))
	if not session.player.sandbox:
		session.career.missions_cancelled += 1
		session.career.record_mission_penalty(penalty)
	session.changed.emit()
	return true


func _cancel_kind_eligible(session: GameSession, charter_id: String, kind: CharterKind) -> bool:
	var book := kind.book_for(self)
	var charter := book.find_accepted(charter_id)
	if charter.is_empty():
		return false
	return kind.cancel_eligible(session, charter, Callable(self, "_cancel_at_origin"))


func _try_complete_kind(
	session: GameSession,
	catalog: Catalog,
	habitat_id: String,
	kind: CharterKind
) -> void:
	if habitat_id.is_empty():
		return
	var current_ship := session.get_current_owned_ship()
	if current_ship == null:
		return
	var book := kind.book_for(self)
	var habitat_field := kind.completion_habitat_field()
	var completed: Array = []
	for entry_variant in book.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get(habitat_field, "")) != habitat_id:
			continue
		if str(entry.get("ship_id", "")) != current_ship.id:
			continue
		if kind.requires_satisfied_for_complete() and not kind.charter_satisfied(session, entry):
			continue
		completed.append(str(entry.get("charter_id", "")))
	for charter_id in completed:
		_resolve_charter_on_dock(session, catalog, charter_id, kind)


func _enforce_late_origin_charters_at_dock(
	session: GameSession,
	catalog: Catalog,
	kind: CharterKind
) -> void:
	if not session.world.docked:
		return
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	var habitat_id := session.world.habitat_id
	var book := kind.book_for(self)
	var failed: Array = []
	for entry_variant in book.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("ship_id", "")) != ship.id:
			continue
		if str(entry.get("origin_habitat_id", "")) != habitat_id:
			continue
		if not _charter_is_late(session, entry):
			continue
		if kind.charter_satisfied(session, entry):
			continue
		failed.append(str(entry.get("charter_id", "")))
	for charter_id in failed:
		_fail_charter_missed_deadline(session, catalog, charter_id, kind)


func _fail_charter_missed_deadline(
	session: GameSession,
	catalog: Catalog,
	charter_id: String,
	kind: CharterKind
) -> void:
	var book := kind.book_for(self)
	var charter := book.find_accepted(charter_id)
	if charter.is_empty():
		return
	kind.clear_bounty_contract_on_resolve(session, charter)
	var reward := int(charter.get("reward", 0))
	var penalty := kind.cancel_penalty(catalog, reward)
	book.remove_accepted(charter_id)
	CharterResolution.fail_missed_deadline(session, penalty, kind.missed_deadline_log(penalty))


func _resolve_charter_on_dock(
	session: GameSession,
	catalog: Catalog,
	charter_id: String,
	kind: CharterKind
) -> void:
	var book := kind.book_for(self)
	var charter := book.find_accepted(charter_id)
	if charter.is_empty():
		return
	kind.clear_bounty_contract_on_resolve(session, charter)
	var reward := int(charter.get("reward", 0))
	var penalty := kind.cancel_penalty(catalog, reward)
	var logs := kind.settle_logs(charter, penalty)
	book.remove_accepted(charter_id)
	CharterResolution.settle_on_dock(
		session,
		charter,
		penalty,
		str(logs.get("late", "")),
		str(logs.get("paid", "")),
		str(logs.get("unpaid", ""))
	)
	session.events.publish(
		SimEvent.charter_completed(kind.slice_key, charter_id, reward)
	)


func accept_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> bool:
	return _accept_kind(session, catalog, offer_id, ship_id, _kind_config(CharterKind.Type.PASSENGER))


func accept_freight_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> bool:
	return _accept_kind(session, catalog, offer_id, ship_id, _kind_config(CharterKind.Type.FREIGHT))


func accept_scan_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> bool:
	return _accept_kind(session, catalog, offer_id, ship_id, _kind_config(CharterKind.Type.SCAN))


func accept_bounty_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> bool:
	return _accept_kind(session, catalog, offer_id, ship_id, _kind_config(CharterKind.Type.BOUNTY))


func accept_retrieval_offer(
	session: GameSession,
	catalog: Catalog,
	offer_id: String,
	ship_id: String
) -> bool:
	return _accept_kind(session, catalog, offer_id, ship_id, _kind_config(CharterKind.Type.RETRIEVAL))


func cancel_charter(session: GameSession, catalog: Catalog, charter_id: String) -> bool:
	return _cancel_kind(session, catalog, charter_id, _kind_config(CharterKind.Type.PASSENGER))


func cancel_freight_charter(session: GameSession, catalog: Catalog, charter_id: String) -> bool:
	return _cancel_kind(session, catalog, charter_id, _kind_config(CharterKind.Type.FREIGHT))


func cancel_charter_eligible(session: GameSession, charter_id: String) -> bool:
	return _cancel_kind_eligible(session, charter_id, _kind_config(CharterKind.Type.PASSENGER))


func cancel_freight_charter_eligible(session: GameSession, charter_id: String) -> bool:
	return _cancel_kind_eligible(session, charter_id, _kind_config(CharterKind.Type.FREIGHT))


func cancel_scan_charter(session: GameSession, catalog: Catalog, charter_id: String) -> bool:
	return _cancel_kind(session, catalog, charter_id, _kind_config(CharterKind.Type.SCAN))


func cancel_scan_charter_eligible(session: GameSession, charter_id: String) -> bool:
	return _cancel_kind_eligible(session, charter_id, _kind_config(CharterKind.Type.SCAN))


func cancel_bounty_charter(session: GameSession, catalog: Catalog, charter_id: String) -> bool:
	return _cancel_kind(session, catalog, charter_id, _kind_config(CharterKind.Type.BOUNTY))


func cancel_retrieval_charter(session: GameSession, catalog: Catalog, charter_id: String) -> bool:
	return _cancel_kind(session, catalog, charter_id, _kind_config(CharterKind.Type.RETRIEVAL))


func cancel_retrieval_charter_eligible(session: GameSession, charter_id: String) -> bool:
	return _cancel_kind_eligible(session, charter_id, _kind_config(CharterKind.Type.RETRIEVAL))


func notify_retrieval_pickup(session: GameSession, contact_id: String) -> void:
	if session == null or contact_id.is_empty():
		return
	var sector_id := session.world.sector_id
	var updated := false
	for i in retrievals.accepted.size():
		var entry_variant = retrievals.accepted[i]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if bool(entry.get("retrieved", false)):
			continue
		if str(entry.get("retrieval_contact_id", "")) != contact_id:
			continue
		if RetrievalCharters.retrieval_sector_for_contract(entry) != sector_id:
			continue
		entry["retrieved"] = true
		retrievals.accepted[i] = entry
		updated = true
		session.player.last_log = "Specimen secured. Return to %s to collect payment." % str(
			entry.get("origin_habitat_id", "origin")
		)
	if updated:
		session.changed.emit()


func cancel_bounty_charter_eligible(session: GameSession, charter_id: String) -> bool:
	return _cancel_kind_eligible(session, charter_id, _kind_config(CharterKind.Type.BOUNTY))


func to_dict() -> Dictionary:
	var out := {"generated_day": generated_day, "bar_rounds_by_building": bar_rounds_by_building.duplicate(true)}
	for kind_variant in _charter_kind_configs:
		var kind: CharterKind = kind_variant
		var book := kind.book_for(self)
		out[kind.offers_save_key] = book.duplicate_offers()
		out[kind.accepted_save_key] = book.duplicate_accepted()
		out[kind.next_id_save_key] = book.next_id
	return out


func migrate(data: Dictionary, from_version: int) -> Dictionary:
	if from_version >= save_version:
		return data.duplicate(true)
	var out := data.duplicate(true)
	for kind_variant in _charter_kind_configs:
		var kind: CharterKind = kind_variant
		if from_version <= kind.migrate_introduced_at and kind.migrate_introduced_at > 1:
			if not out.has(kind.offers_save_key):
				out[kind.offers_save_key] = {}
			if not out.has(kind.accepted_save_key):
				out[kind.accepted_save_key] = []
			if not out.has(kind.next_id_save_key):
				out[kind.next_id_save_key] = 1
	if from_version <= 5:
		for kind_variant in _charter_kind_configs:
			var kind_v5: CharterKind = kind_variant
			if kind_v5.migrate_introduced_at <= 4:
				out[kind_v5.offers_save_key] = {}
	if from_version <= 6:
		var retrieval_kind := _kind_config(CharterKind.Type.RETRIEVAL)
		if retrieval_kind != null:
			if not out.has(retrieval_kind.offers_save_key):
				out[retrieval_kind.offers_save_key] = {}
			if not out.has(retrieval_kind.accepted_save_key):
				out[retrieval_kind.accepted_save_key] = []
			if not out.has(retrieval_kind.next_id_save_key):
				out[retrieval_kind.next_id_save_key] = 1
		for kind_variant in _charter_kind_configs:
			var kind_v6: CharterKind = kind_variant
			if kind_v6.migrate_clear_offers_at_v6:
				out[kind_v6.offers_save_key] = {}
	if from_version <= 7:
		if not out.has("bar_rounds_by_building"):
			out["bar_rounds_by_building"] = {}
	return out


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		generated_day = -1
		bar_rounds_by_building = {}
		passengers.reset()
		freight.reset()
		scans.reset()
		bounties.reset()
		retrievals.reset()
		return
	generated_day = int(data.get("generated_day", -1))
	for kind_variant in _charter_kind_configs:
		var kind: CharterKind = kind_variant
		var book := kind.book_for(self)
		book.load_state(
			data.get(kind.offers_save_key, {}),
			data.get(kind.accepted_save_key, []),
			data.get(kind.next_id_save_key, 1)
		)
	bar_rounds_by_building = {}
	var stored_rounds: Variant = data.get("bar_rounds_by_building", {})
	if typeof(stored_rounds) == TYPE_DICTIONARY:
		bar_rounds_by_building = (stored_rounds as Dictionary).duplicate(true)


func _invalidate_boards(day: int) -> void:
	generated_day = day
	for kind_variant in _charter_kind_configs:
		var kind: CharterKind = kind_variant
		kind.book_for(self).clear_offers()


func _ensure_habitat_boards(
	session: GameSession,
	catalog: Catalog,
	habitat_id: String,
	day: int
) -> void:
	if _habitat_boards_complete(habitat_id):
		return
	_populate_habitat_boards(catalog, habitat_id, day, session.world.run_seed)


func _habitat_boards_complete(habitat_id: String) -> bool:
	for kind_variant in _charter_kind_configs:
		var kind: CharterKind = kind_variant
		if not kind.book_for(self).has_habitat(habitat_id):
			return false
	return true


func _populate_habitat_boards(
	catalog: Catalog,
	habitat_id: String,
	day: int,
	run_seed: int
) -> void:
	var generated := DeskCharterBoards.generate_for_habitat(catalog, habitat_id, day, run_seed)
	for kind_variant in _charter_kind_configs:
		var kind: CharterKind = kind_variant
		kind.book_for(self).offers[habitat_id] = generated[kind.slice_key]


func _apply_charter_deadline(session: GameSession, charter: Dictionary) -> void:
	var hours := int(charter.get("deadline_hours", 0))
	if hours <= 0:
		return
	charter["deadline_gst"] = (
		session.world.gst_seconds + float(hours) * float(GalacticCalendar.SECONDS_PER_HOUR)
	)


func _charter_is_late(session: GameSession, charter: Dictionary) -> bool:
	return CharterResolution.is_late(session, charter)


func _enforce_late_passengers_at_dock(session: GameSession, catalog: Catalog) -> void:
	if not session.world.docked:
		return
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	var habitat_id := session.world.habitat_id
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
		_fail_charter_missed_deadline(
			session,
			catalog,
			charter_id,
			_kind_config(CharterKind.Type.PASSENGER)
		)


func _charter_at_origin(session: GameSession, charter: Dictionary) -> bool:
	if not session.world.docked:
		return false
	if str(charter.get("origin_habitat_id", "")) != session.world.habitat_id:
		return false
	var ship := session.get_owned_ship(str(charter.get("ship_id", "")))
	if ship == null:
		return false
	return ship.location == session.world.habitat_id


func _freight_charter_at_origin(session: GameSession, charter: Dictionary) -> bool:
	return _charter_at_origin(session, charter)


func notify_pending_bounty_escapes(
	session: GameSession,
	catalog: Catalog,
	escapes: Array
) -> void:
	for escape_variant in escapes:
		if typeof(escape_variant) != TYPE_DICTIONARY:
			continue
		var escape: Dictionary = escape_variant
		notify_bounty_ship_escaped(
			session,
			catalog,
			str(escape.get("actor_id", "")),
			bool(escape.get("named_target", false)),
			str(escape.get("route", ""))
		)


func notify_bounty_ship_escaped(
	session: GameSession,
	catalog: Catalog,
	target_id: String,
	is_named_target: bool,
	flee_route: String
) -> void:
	if not is_named_target or target_id.is_empty():
		return
	var charter := _find_bounty_charter_by_target(target_id)
	if charter.is_empty():
		return
	var charter_id := str(charter.get("charter_id", ""))
	if flee_route == "deep_space":
		_fail_bounty_escape(
			session,
			catalog,
			charter_id,
			"Target escaped into deep space. Bounty closed."
		)
		return
	charter["bounty_pursuit"] = BountyBehavior.start_pursuit(charter, flee_route)
	_upsert_bounty_accepted(charter)
	session.player.last_log = "Target is fleeing. Intercept before they reach dock."
	session.changed.emit()


func notify_bounty_pursuit_docked(session: GameSession, catalog: Catalog, target_id: String) -> void:
	var charter := _find_bounty_charter_by_target(target_id)
	if charter.is_empty():
		return
	_fail_bounty_escape(
		session,
		catalog,
		str(charter.get("charter_id", "")),
		"Target reached dock under pursuit. Bounty closed."
	)


func pursuit_charter_for_spawn(session: GameSession) -> Dictionary:
	for entry_variant in bounties.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var charter: Dictionary = entry_variant
		var pursuit: Variant = charter.get("bounty_pursuit", {})
		if typeof(pursuit) != TYPE_DICTIONARY or pursuit.is_empty():
			continue
		if str(pursuit.get("phase", "")) != "origin_dock":
			continue
		if str(charter.get("origin_sector_id", "")) != session.world.sector_id:
			continue
		if str(charter.get("charter_id", "")) == _pursuit_spawned_charter_id:
			return {}
		return charter
	return {}


func mark_pursuit_spawned(charter_id: String) -> void:
	_pursuit_spawned_charter_id = charter_id


func build_pursuit_target_record(session: GameSession, charter: Dictionary) -> Dictionary:
	var record_id := str(charter.get("volatile_record_id", ""))
	var record := VolatileTranslation.find_by_id(session, record_id)
	if record.is_empty():
		return {}
	var setup: Variant = record.get("setup", {})
	if typeof(setup) != TYPE_DICTIONARY:
		return {}
	var target: Variant = setup.get("bounty_target", {})
	if typeof(target) != TYPE_DICTIONARY:
		return {}
	return (target as Dictionary).duplicate(true)


func _find_bounty_charter_by_target(target_id: String) -> Dictionary:
	for entry_variant in bounties.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("bounty_target_id", "")) == target_id:
			return entry
	return {}


func _upsert_bounty_accepted(charter: Dictionary) -> void:
	var charter_id := str(charter.get("charter_id", ""))
	if charter_id.is_empty():
		return
	for index in range(bounties.accepted.size()):
		var entry: Dictionary = bounties.accepted[index]
		if str(entry.get("charter_id", "")) == charter_id:
			bounties.accepted[index] = charter.duplicate(true)
			return


func _tick_bounty_pursuits(session: GameSession, catalog: Catalog, delta: float) -> void:
	var failed: Array = []
	for entry_variant in bounties.accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var charter: Dictionary = entry_variant
		var pursuit: Variant = charter.get("bounty_pursuit", {})
		if typeof(pursuit) != TYPE_DICTIONARY or pursuit.is_empty():
			continue
		pursuit = BountyBehavior.advance_pursuit_phase(pursuit, charter, session)
		pursuit = BountyBehavior.tick_pursuit(pursuit, delta, true)
		charter["bounty_pursuit"] = pursuit
		_upsert_bounty_accepted(charter)
		if BountyBehavior.pursuit_failed(pursuit):
			failed.append(str(charter.get("charter_id", "")))
	for charter_id in failed:
		_fail_bounty_escape(
			session,
			catalog,
			charter_id,
			"Target escaped. Bounty closed."
		)


func _fail_bounty_escape(
	session: GameSession,
	catalog: Catalog,
	charter_id: String,
	message: String
) -> void:
	var charter := bounties.find_accepted(charter_id)
	if charter.is_empty():
		return
	session.player.clear_bounty_contract(str(charter.get("bounty_target_id", "")))
	bounties.remove_accepted(charter_id)
	if str(charter_id) == _pursuit_spawned_charter_id:
		_pursuit_spawned_charter_id = ""
	session.player.last_log = message
	if not session.player.sandbox:
		session.career.missions_cancelled += 1
	session.changed.emit()


static func _log_with_reputation_delta(session: GameSession, delta: int, message: String) -> void:
	CharterResolution.log_with_reputation_delta(session, delta, message)
