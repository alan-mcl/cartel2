class_name CareerStats
extends RefCounted

## Lifetime career ledger (persisted in save session). Skip updates when [GameSession.sandbox].

const REV_CHARTERS := "charters"
const REV_COMMODITIES := "commodities"
const REV_SALVAGE := "salvage"
const REV_PARTS := "parts"

const EXP_COMMODITIES := "commodities"
const EXP_SHIPS := "ships"
const EXP_PARTS := "parts"
const EXP_FUEL := "fuel"
const EXP_SANCTIONS := "sanctions"
const EXP_MISSION_PENALTIES := "mission_penalties"

static var _career_id_factory: Callable = Callable()

var career_id: String = ""
var flight_gst_seconds_real: float = 0.0
var flight_gst_seconds_unspace: float = 0.0
var played_seconds: float = 0.0
var translations_count: int = 0
var translations_by_n: Dictionary = {}
var sectors_visited: Dictionary = {}
var habitats_visited: Dictionary = {}
var buildings_visited: Dictionary = {}
var dock_count: int = 0
var shots_fired: int = 0
var kills: int = 0
var hull_damage_taken: float = 0.0
var hull_breaches: int = 0
var tonnes_bought: float = 0.0
var tonnes_sold: float = 0.0
var revenue_by_source: Dictionary = {}
var expenses_by_source: Dictionary = {}
var missions_accepted: int = 0
var missions_completed_on_time: int = 0
var missions_late: int = 0
var missions_missed_deadline: int = 0
var missions_cancelled: int = 0
var mission_reward_total: int = 0
var mission_penalty_total: int = 0
var sanctions_payments: int = 0
var sanctions_paid_total: int = 0
var infractions_incurred: int = 0
var salvage_count: int = 0
var ships_purchased: int = 0


static func generate_career_id() -> String:
	if _career_id_factory.is_valid():
		return str(_career_id_factory.call())
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()


static func reset_factory() -> void:
	_career_id_factory = Callable()


func reset_for_new_career() -> void:
	career_id = generate_career_id()
	flight_gst_seconds_real = 0.0
	flight_gst_seconds_unspace = 0.0
	played_seconds = 0.0
	translations_count = 0
	translations_by_n.clear()
	sectors_visited.clear()
	habitats_visited.clear()
	buildings_visited.clear()
	dock_count = 0
	shots_fired = 0
	kills = 0
	hull_damage_taken = 0.0
	hull_breaches = 0
	tonnes_bought = 0.0
	tonnes_sold = 0.0
	revenue_by_source.clear()
	expenses_by_source.clear()
	missions_accepted = 0
	missions_completed_on_time = 0
	missions_late = 0
	missions_missed_deadline = 0
	missions_cancelled = 0
	mission_reward_total = 0
	mission_penalty_total = 0
	sanctions_payments = 0
	sanctions_paid_total = 0
	infractions_incurred = 0
	salvage_count = 0
	ships_purchased = 0


func ensure_career_id() -> void:
	if career_id.is_empty():
		career_id = generate_career_id()


func total_revenue() -> int:
	return _sum_int_dict(revenue_by_source)


func total_expenses() -> int:
	return _sum_int_dict(expenses_by_source)


func nett_profit() -> int:
	return total_revenue() - total_expenses()


func tonnes_traded() -> float:
	return tonnes_bought + tonnes_sold


func missions_completed() -> int:
	return missions_completed_on_time


func record_played_seconds(delta: float) -> void:
	if delta <= 0.0:
		return
	played_seconds += delta


func record_flight_gst(gst_delta: float, in_unspace: bool) -> void:
	if gst_delta <= 0.0:
		return
	if in_unspace:
		flight_gst_seconds_unspace += gst_delta
	else:
		flight_gst_seconds_real += gst_delta


func record_translation(n: int) -> void:
	translations_count += 1
	var key := str(n)
	translations_by_n[key] = int(translations_by_n.get(key, 0)) + 1


func record_sector_visited(sector_id: String) -> void:
	if sector_id.is_empty():
		return
	sectors_visited[sector_id] = true


func record_habitat_visited(habitat_id: String) -> void:
	if habitat_id.is_empty():
		return
	habitats_visited[habitat_id] = true


func record_building_visited(building_id: String) -> void:
	if building_id.is_empty():
		return
	buildings_visited[building_id] = true


func record_dock() -> void:
	dock_count += 1


func record_shots(count: int) -> void:
	if count <= 0:
		return
	shots_fired += count


func record_kill() -> void:
	kills += 1


func record_hull_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	hull_damage_taken += amount


func record_hull_breach() -> void:
	hull_breaches += 1


func record_commodity_buy(quantity: int, tonnes: float, cost: int) -> void:
	if quantity > 0 and tonnes > 0.0:
		tonnes_bought += tonnes
	if cost > 0:
		_add_expense(EXP_COMMODITIES, cost)


func record_commodity_sell(quantity: int, tonnes: float, proceeds: int) -> void:
	if quantity > 0 and tonnes > 0.0:
		tonnes_sold += tonnes
	if proceeds > 0:
		_add_revenue(REV_COMMODITIES, proceeds)


func record_charter_reward(amount: int) -> void:
	if amount <= 0:
		return
	mission_reward_total += amount
	_add_revenue(REV_CHARTERS, amount)


func record_mission_penalty(amount: int) -> void:
	if amount <= 0:
		return
	mission_penalty_total += amount
	_add_expense(EXP_MISSION_PENALTIES, amount)


func record_salvage(reward: int) -> void:
	salvage_count += 1
	if reward > 0:
		_add_revenue(REV_SALVAGE, reward)


func record_part_sale(proceeds: int) -> void:
	if proceeds > 0:
		_add_revenue(REV_PARTS, proceeds)


func record_part_purchase(cost: int) -> void:
	if cost > 0:
		_add_expense(EXP_PARTS, cost)


func record_fuel_spend(cost: int) -> void:
	if cost > 0:
		_add_expense(EXP_FUEL, cost)


func record_ship_purchase(cost: int) -> void:
	ships_purchased += 1
	if cost > 0:
		_add_expense(EXP_SHIPS, cost)


func record_sanctions_paid(amount: int) -> void:
	if amount <= 0:
		return
	sanctions_payments += 1
	sanctions_paid_total += amount
	_add_expense(EXP_SANCTIONS, amount)


func record_infraction_incurred() -> void:
	infractions_incurred += 1


func _add_revenue(source: String, amount: int) -> void:
	if amount <= 0 or source.is_empty():
		return
	revenue_by_source[source] = int(revenue_by_source.get(source, 0)) + amount


func _add_expense(source: String, amount: int) -> void:
	if amount <= 0 or source.is_empty():
		return
	expenses_by_source[source] = int(expenses_by_source.get(source, 0)) + amount


static func _sum_int_dict(dict: Dictionary) -> int:
	var total := 0
	for key in dict.keys():
		total += int(dict.get(key, 0))
	return total


static func _bool_dict_to_save(dict: Dictionary) -> Dictionary:
	var out := {}
	for key in dict.keys():
		if bool(dict.get(key, false)):
			out[str(key)] = true
	return out


static func _bool_dict_from_save(data: Variant) -> Dictionary:
	var out := {}
	if typeof(data) != TYPE_DICTIONARY:
		return out
	for key in data.keys():
		if bool(data.get(key, false)):
			out[str(key)] = true
	return out


static func _int_dict_from_save(data: Variant) -> Dictionary:
	var out := {}
	if typeof(data) != TYPE_DICTIONARY:
		return out
	for key in data.keys():
		out[str(key)] = int(data.get(key, 0))
	return out


func to_session_dict() -> Dictionary:
	return {
		"career_id": career_id,
		"flight_gst_seconds_real": flight_gst_seconds_real,
		"flight_gst_seconds_unspace": flight_gst_seconds_unspace,
		"played_seconds": played_seconds,
		"translations_count": translations_count,
		"translations_by_n": translations_by_n.duplicate(true),
		"sectors_visited": _bool_dict_to_save(sectors_visited),
		"habitats_visited": _bool_dict_to_save(habitats_visited),
		"buildings_visited": _bool_dict_to_save(buildings_visited),
		"dock_count": dock_count,
		"shots_fired": shots_fired,
		"kills": kills,
		"hull_damage_taken": hull_damage_taken,
		"hull_breaches": hull_breaches,
		"tonnes_bought": tonnes_bought,
		"tonnes_sold": tonnes_sold,
		"revenue_by_source": revenue_by_source.duplicate(true),
		"expenses_by_source": expenses_by_source.duplicate(true),
		"missions_accepted": missions_accepted,
		"missions_completed_on_time": missions_completed_on_time,
		"missions_late": missions_late,
		"missions_missed_deadline": missions_missed_deadline,
		"missions_cancelled": missions_cancelled,
		"mission_reward_total": mission_reward_total,
		"mission_penalty_total": mission_penalty_total,
		"sanctions_payments": sanctions_payments,
		"sanctions_paid_total": sanctions_paid_total,
		"infractions_incurred": infractions_incurred,
		"salvage_count": salvage_count,
		"ships_purchased": ships_purchased,
	}


func load_session_dict(data: Dictionary) -> void:
	career_id = str(data.get("career_id", ""))
	flight_gst_seconds_real = float(data.get("flight_gst_seconds_real", 0.0))
	flight_gst_seconds_unspace = float(data.get("flight_gst_seconds_unspace", 0.0))
	played_seconds = float(data.get("played_seconds", 0.0))
	translations_count = int(data.get("translations_count", 0))
	translations_by_n = _int_dict_from_save(data.get("translations_by_n", {}))
	sectors_visited = _bool_dict_from_save(data.get("sectors_visited", {}))
	habitats_visited = _bool_dict_from_save(data.get("habitats_visited", {}))
	buildings_visited = _bool_dict_from_save(data.get("buildings_visited", {}))
	dock_count = int(data.get("dock_count", 0))
	shots_fired = int(data.get("shots_fired", 0))
	kills = int(data.get("kills", 0))
	hull_damage_taken = float(data.get("hull_damage_taken", 0.0))
	hull_breaches = int(data.get("hull_breaches", 0))
	tonnes_bought = float(data.get("tonnes_bought", 0.0))
	tonnes_sold = float(data.get("tonnes_sold", 0.0))
	revenue_by_source = _int_dict_from_save(data.get("revenue_by_source", {}))
	expenses_by_source = _int_dict_from_save(data.get("expenses_by_source", {}))
	missions_accepted = int(data.get("missions_accepted", 0))
	missions_completed_on_time = int(data.get("missions_completed_on_time", 0))
	missions_late = int(data.get("missions_late", 0))
	missions_missed_deadline = int(data.get("missions_missed_deadline", 0))
	missions_cancelled = int(data.get("missions_cancelled", 0))
	mission_reward_total = int(data.get("mission_reward_total", 0))
	mission_penalty_total = int(data.get("mission_penalty_total", 0))
	sanctions_payments = int(data.get("sanctions_payments", 0))
	sanctions_paid_total = int(data.get("sanctions_paid_total", 0))
	infractions_incurred = int(data.get("infractions_incurred", 0))
	salvage_count = int(data.get("salvage_count", 0))
	ships_purchased = int(data.get("ships_purchased", 0))
	ensure_career_id()
