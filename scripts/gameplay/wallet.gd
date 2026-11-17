class_name Wallet
extends RefCounted

var credits: int = 3000


func apply(delta: int) -> void:
	credits += delta


func can_afford(cost: int) -> bool:
	return credits >= cost


func try_spend(cost: int) -> bool:
	if not can_afford(cost):
		return false
	credits -= cost
	return true


func assess_penalty(cost: int) -> void:
	if cost <= 0:
		return
	credits -= cost


func buy_commodity(
	catalog: Catalog,
	building_id: String,
	commodity_id: String,
	amount: int,
	ship: OwnedShip,
	player: PlayerState,
	fleet: Fleet,
	listing: Dictionary,
	missions: MissionSubsystem
) -> Dictionary:
	var fail := {"ok": false}
	if amount <= 0:
		return fail
	if ship == null:
		fail["error"] = "No ship selected for cargo."
		return fail
	var building := catalog.get_building(building_id)
	if catalog.get_building_type(building) != "market":
		return fail
	if listing.is_empty():
		return fail
	var commodity := catalog.get_commodity_def(commodity_id)
	if commodity == null:
		return fail
	var block_reason := fleet.cargo_carry_block_reason(catalog, ship, commodity_id, amount, missions)
	if not block_reason.is_empty():
		fail["error"] = block_reason
		return fail
	var available := int(listing.get("quantity", 0))
	if amount > available:
		fail["error"] = "The exchange has only %d on the board." % available
		return fail
	var price := int(listing.get("price", commodity.base_price))
	var total_cost := price * amount
	if not try_spend(total_cost):
		return fail
	ship.add_cargo(commodity_id, amount)
	var commodity_name := commodity_id
	if commodity.has_source_key("name"):
		commodity_name = commodity.name
	player.last_log = "Bought %d x %s for d%d." % [amount, commodity_name, total_cost]
	return {
		"ok": true,
		"price": price,
		"total_cost": total_cost,
		"commodity_name": commodity_name,
		"commodity": commodity,
	}


func sell_commodity(
	catalog: Catalog,
	building_id: String,
	commodity_id: String,
	amount: int,
	ship: OwnedShip,
	player: PlayerState,
	listing: Dictionary
) -> Dictionary:
	var fail := {"ok": false}
	if amount <= 0:
		return fail
	if ship == null:
		fail["error"] = "No ship selected for cargo."
		return fail
	var building := catalog.get_building(building_id)
	if catalog.get_building_type(building) != "market":
		return fail
	if listing.is_empty():
		return fail
	if ship.get_cargo_count(commodity_id) < amount:
		fail["error"] = "Not enough cargo to sell."
		return fail
	var available := int(listing.get("quantity", 0))
	if amount > available:
		fail["error"] = "The exchange has only %d on the board." % available
		return fail
	var commodity := catalog.get_commodity_def(commodity_id)
	var base_price := 0
	if commodity != null:
		base_price = int(commodity.base_price)
	var price := int(listing.get("price", base_price))
	var sell_price := CommodityEconomy.sell_price(price)
	var total := sell_price * amount
	if not ship.remove_cargo(commodity_id, amount):
		return fail
	apply(total)
	var commodity_name := commodity_id
	if commodity != null and commodity.has_source_key("name"):
		commodity_name = commodity.name
	player.last_log = "Sold %d x %s for d%d." % [amount, commodity_name, total]
	return {
		"ok": true,
		"sell_price": sell_price,
		"total": total,
		"commodity_name": commodity_name,
		"commodity": commodity,
	}


func to_session_dict() -> Dictionary:
	return {"credits": credits}


func load_session_dict(data: Dictionary) -> void:
	credits = int(data.get("credits", 0))