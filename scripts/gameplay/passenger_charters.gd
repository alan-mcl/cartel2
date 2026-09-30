class_name PassengerCharters
extends RefCounted

const BOARD_TERMINAL := "terminal"
const BOARD_BAR := "bar"


static func config(catalog: Catalog) -> Dictionary:
	return catalog.get_passenger_missions_config()


static func habitat_has_bar(catalog: Catalog, habitat_id: String) -> bool:
	var habitat := catalog.get_habitat(habitat_id)
	if habitat.is_empty():
		return false
	for building_id_variant in habitat.get("buildings", []):
		var building := catalog.get_building(str(building_id_variant))
		if str(building.get("type", "")) == "bar":
			return true
	return false


static func friction_between(catalog: Catalog, sector_a: String, sector_b: String) -> int:
	if sector_a.is_empty() or sector_b.is_empty() or sector_a == sector_b:
		return -1
	for route in catalog.list_routes():
		if typeof(route) != TYPE_DICTIONARY:
			continue
		var left := str(route.get("a", ""))
		var right := str(route.get("b", ""))
		if (left == sector_a and right == sector_b) or (left == sector_b and right == sector_a):
			return int(route.get("friction", 0))
	return -1


static func habitat_for_sector(catalog: Catalog, sector_id: String) -> String:
	for habitat in catalog.list_habitat_dicts():
		if typeof(habitat) != TYPE_DICTIONARY:
			continue
		if str(habitat.get("sector_id", "")) == sector_id:
			return str(habitat.get("id", ""))
	return ""


static func neighbor_destinations(catalog: Catalog, origin_habitat_id: String) -> Array:
	var origin := catalog.get_habitat(origin_habitat_id)
	var origin_sector := str(origin.get("sector_id", ""))
	var out: Array = []
	for route in catalog.list_routes():
		if typeof(route) != TYPE_DICTIONARY:
			continue
		var left := str(route.get("a", ""))
		var right := str(route.get("b", ""))
		var other_sector := ""
		if left == origin_sector:
			other_sector = right
		elif right == origin_sector:
			other_sector = left
		else:
			continue
		var dest_habitat := habitat_for_sector(catalog, other_sector)
		if dest_habitat.is_empty() or dest_habitat == origin_habitat_id:
			continue
		var dest := catalog.get_habitat(dest_habitat)
		out.append({
			"habitat_id": dest_habitat,
			"habitat_name": str(dest.get("name", dest_habitat)),
			"sector_id": other_sector,
			"friction": int(route.get("friction", 0)),
		})
	return out


static func compute_reward(
	cfg: Dictionary,
	quantity: int,
	pay_multiplier: float,
	friction: int
) -> int:
	var base_pay := float(cfg.get("base_pay", 120))
	var friction_pay := float(cfg.get("friction_pay", 8))
	var raw := float(quantity) * pay_multiplier * (base_pay + float(friction) * friction_pay)
	return int(round(raw))


static func cancel_penalty(cfg: Dictionary, reward: int) -> int:
	var fraction := float(cfg.get("cancel_penalty_fraction", 0.25))
	return int(round(float(reward) * fraction))


static func format_description(
	template: String,
	quantity: int,
	destination_name: String,
	corporation_name: String
) -> String:
	return template.replace("{quantity}", str(quantity)).replace(
		"{destination}", destination_name
	).replace("{corporation}", corporation_name)


static func life_support_tier_satisfied(assembled: AssembledShip, tier: String) -> bool:
	match tier:
		"luxury":
			return assembled.has_capability("ls_luxury")
		"comfort":
			return assembled.has_capability("ls_comfort") or assembled.has_capability("ls_luxury")
		_:
			return true


static func life_support_tier_label(tier: String) -> String:
	match tier:
		"luxury":
			return "luxury life support"
		"comfort":
			return "comfort life support"
		_:
			return "life support capacity"


static func role_boards(role: Dictionary) -> Array:
	var boards: Variant = role.get("boards", ["terminal"])
	if typeof(boards) != TYPE_ARRAY or boards.is_empty():
		return ["terminal"]
	var out: Array = []
	for board_variant in boards:
		out.append(str(board_variant))
	return out


static func description_boards(entry: Dictionary) -> Array:
	var boards: Variant = entry.get("boards", [])
	if typeof(boards) != TYPE_ARRAY or boards.is_empty():
		return ["terminal"]
	var out: Array = []
	for board_variant in boards:
		out.append(str(board_variant))
	return out


static func roles_for_board(cfg: Dictionary, board: String) -> Array:
	var roles: Array = []
	for role_variant in cfg.get("roles", []):
		if typeof(role_variant) != TYPE_DICTIONARY:
			continue
		var role: Dictionary = role_variant
		if board in role_boards(role):
			roles.append(role)
	return roles


static func pick_description(
	cfg: Dictionary,
	board: String,
	role_id: String,
	rng: RandomNumberGenerator
) -> String:
	var matches: Array = []
	for entry_variant in cfg.get("descriptions", []):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if board not in description_boards(entry):
			continue
		var allowed: Variant = entry.get("roles", [])
		if typeof(allowed) != TYPE_ARRAY or allowed.is_empty():
			matches.append(entry)
			continue
		for role_ref in allowed:
			if str(role_ref) == role_id:
				matches.append(entry)
				break
	if matches.is_empty():
		if board == BOARD_BAR:
			return "Informal fare: {quantity} need a lift to {destination}."
		return "Passengers need transport to {destination}."
	var picked: Dictionary = matches[rng.randi() % matches.size()]
	return str(picked.get("text", ""))


static func board_seed(day: int, habitat_id: String, board: String) -> int:
	return int(hash("%d:%s:%s" % [day, habitat_id, board]))


static func generate_offers(
	catalog: Catalog,
	origin_habitat_id: String,
	board: String,
	day: int,
	count: int
) -> Array:
	var cfg := config(catalog)
	var destinations := neighbor_destinations(catalog, origin_habitat_id)
	var roles := roles_for_board(cfg, board)
	if destinations.is_empty() or roles.is_empty() or count <= 0:
		return []

	var origin := catalog.get_habitat(origin_habitat_id)
	var origin_sector := str(origin.get("sector_id", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = board_seed(day, origin_habitat_id, board)

	var offers: Array = []
	for index in count:
		var role: Dictionary = roles[rng.randi() % roles.size()]
		var dest: Dictionary = destinations[rng.randi() % destinations.size()]
		var qty_min := int(role.get("quantity_min", 1))
		var qty_max := int(role.get("quantity_max", qty_min))
		if qty_max < qty_min:
			qty_max = qty_min
		var quantity := rng.randi_range(qty_min, qty_max)
		var pay_multiplier := float(role.get("pay_multiplier", 1.0))
		var friction := int(dest.get("friction", 0))
		var reward := compute_reward(cfg, quantity, pay_multiplier, friction)

		var corporation_id := ""
		var corporation_name := ""
		if str(role.get("affiliation", "")) == "corporate":
			var corp := CorporatePresence.pick_corporation(
				catalog,
				origin_sector,
				rng.randf()
			)
			corporation_id = str(corp.get("id", ""))
			corporation_name = str(corp.get("name", ""))

		var desc_template := pick_description(cfg, board, str(role.get("id", "")), rng)
		var description := format_description(
			desc_template,
			quantity,
			str(dest.get("habitat_name", "")),
			corporation_name
		)

		offers.append({
			"id": "%d_%s_%s_%d" % [day, origin_habitat_id, board, index],
			"board": board,
			"origin_habitat_id": origin_habitat_id,
			"destination_habitat_id": str(dest.get("habitat_id", "")),
			"destination_name": str(dest.get("habitat_name", "")),
			"destination_sector_id": str(dest.get("sector_id", "")),
			"friction": friction,
			"role_id": str(role.get("id", "")),
			"role_title": str(role.get("title", "")),
			"affiliation": str(role.get("affiliation", "civilian")),
			"life_support": str(role.get("life_support", "spartan")),
			"quantity": quantity,
			"pay_multiplier": pay_multiplier,
			"requires_player_affiliation": bool(role.get("requires_player_affiliation", false)),
			"corporation_id": corporation_id,
			"corporation_name": corporation_name,
			"description": description,
			"reward": reward,
		})
	return offers


static func evaluate_offer_for_ship(
	session: GameSession,
	catalog: Catalog,
	offer: Dictionary,
	ship_id: String,
	committed_passengers: int
) -> Dictionary:
	var ship := session.get_owned_ship(ship_id)
	if ship == null:
		return {"ok": false, "reason": "Select a docked ship."}
	if ship.location != session.habitat_id:
		return {"ok": false, "reason": "Ship must be docked here."}

	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	var capacity := float(assembled.capacities.get("life_support_capacity", 0.0))
	var quantity := int(offer.get("quantity", 0))
	var needed := committed_passengers + quantity
	if capacity < float(needed):
		return {
			"ok": false,
			"reason": "Need %d life support seats (%d committed)." % [needed, committed_passengers],
		}

	var tier := str(offer.get("life_support", "spartan"))
	if not life_support_tier_satisfied(assembled, tier):
		return {"ok": false, "reason": "Ship lacks %s." % life_support_tier_label(tier)}

	if bool(offer.get("requires_player_affiliation", false)):
		var corp_id := str(offer.get("corporation_id", ""))
		if not PlayerAffiliation.is_affiliated(session, corp_id):
			return {"ok": false, "reason": "Requires affiliation with %s." % offer.get("corporation_name", corp_id)}

	return {"ok": true, "reason": ""}
