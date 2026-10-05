class_name PassengerCharters
extends RefCounted

const BOARD_TERMINAL := "terminal"
const BOARD_BAR := "bar"
## Pilot always occupies one life-support seat when launched; must match `MissionSubsystem.launch_occupant_count`.
const PILOT_LIFE_SUPPORT_SEATS := 1


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


static func max_hops_from_config(cfg: Dictionary) -> int:
	return maxi(1, int(cfg.get("max_hops", 3)))


static func path_translation_seconds(catalog: Catalog, path_sectors: Array) -> float:
	var total := 0.0
	if path_sectors.size() < 2:
		return total
	for index in path_sectors.size() - 1:
		var from_sector := str(path_sectors[index])
		var to_sector := str(path_sectors[index + 1])
		var friction := friction_between(catalog, from_sector, to_sector)
		if friction < 0:
			continue
		var lump := float(friction) * Catalog.ROUTE_SECONDS_PER_FRICTION
		total += lump * 2.0
	return total


static func offer_deadline_hours(
	catalog: Catalog,
	cfg: Dictionary,
	path_sectors: Array
) -> int:
	var slack := int(cfg.get("deadline_slack_hours", 8))
	var hops := maxi(0, path_sectors.size() - 1)
	var orbit_hours_per_hop := float(cfg.get("deadline_orbit_hours_per_hop", 2.0))
	var translation := path_translation_seconds(catalog, path_sectors)
	var orbit_seconds := float(hops) * orbit_hours_per_hop * float(GalacticCalendar.SECONDS_PER_HOUR)
	var total_seconds := translation + orbit_seconds
	var transit_hours := ceili(total_seconds / float(GalacticCalendar.SECONDS_PER_HOUR))
	return transit_hours + slack


static func roll_offer_hops(cfg: Dictionary, board: String, rng: RandomNumberGenerator) -> int:
	if board == BOARD_BAR:
		return 1
	var max_hops := max_hops_from_config(cfg)
	var weights: Variant = cfg.get("hop_offer_weights", {"1": 70, "2": 25, "3": 5})
	var total := 0
	var entries: Array = []
	if typeof(weights) == TYPE_DICTIONARY:
		for hop in range(1, max_hops + 1):
			var key := str(hop)
			var weight := int(weights.get(key, 0))
			if weight > 0:
				entries.append({"hop": hop, "weight": weight})
				total += weight
	if entries.is_empty() or total <= 0:
		return 1
	var roll := rng.randi_range(1, total)
	for entry in entries:
		var bucket: Dictionary = entry
		roll -= int(bucket.get("weight", 0))
		if roll <= 0:
			return int(bucket.get("hop", 1))
	return 1


static func multi_hop_destinations(
	catalog: Catalog,
	origin_habitat_id: String,
	max_hops: int
) -> Array:
	var origin := catalog.get_habitat(origin_habitat_id)
	var origin_sector := str(origin.get("sector_id", ""))
	if origin_sector.is_empty() or max_hops < 1:
		return []

	var results: Array = []
	var queue: Array = [
		{"sector": origin_sector, "hops": 0, "friction": 0, "path": [origin_sector]},
	]
	while not queue.is_empty():
		var node: Dictionary = queue.pop_front()
		var sector := str(node.get("sector", ""))
		var hops := int(node.get("hops", 0))
		var friction := int(node.get("friction", 0))
		var path: Array = node.get("path", [])

		if hops > 0:
			var dest_habitat := habitat_for_sector(catalog, sector)
			if not dest_habitat.is_empty() and dest_habitat != origin_habitat_id:
				var dest := catalog.get_habitat(dest_habitat)
				results.append({
					"habitat_id": dest_habitat,
					"habitat_name": str(dest.get("name", dest_habitat)),
					"sector_id": sector,
					"friction": friction,
					"hops": hops,
					"path_sectors": path.duplicate(),
					"via_label": via_label_for_path(catalog, path),
				})

		if hops >= max_hops:
			continue

		for route in catalog.list_routes():
			if typeof(route) != TYPE_DICTIONARY:
				continue
			var left := str(route.get("a", ""))
			var right := str(route.get("b", ""))
			var next_sector := ""
			if left == sector:
				next_sector = right
			elif right == sector:
				next_sector = left
			else:
				continue
			if next_sector.is_empty():
				continue
			var visited := false
			for seen in path:
				if str(seen) == next_sector:
					visited = true
					break
			if visited:
				continue
			var next_path: Array = path.duplicate()
			next_path.append(next_sector)
			queue.append({
				"sector": next_sector,
				"hops": hops + 1,
				"friction": friction + int(route.get("friction", 0)),
				"path": next_path,
			})
	return results


static func via_label_for_path(catalog: Catalog, path_sectors: Array) -> String:
	if path_sectors.size() <= 2:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for index in range(1, path_sectors.size() - 1):
		var sector := str(path_sectors[index])
		var habitat_id := habitat_for_sector(catalog, sector)
		if habitat_id.is_empty():
			continue
		var habitat := catalog.get_habitat(habitat_id)
		parts.append(str(habitat.get("name", habitat_id)))
	if parts.is_empty():
		return ""
	return " via " + ", ".join(parts)


static func destinations_for_hops(
	catalog: Catalog,
	origin_habitat_id: String,
	desired_hops: int,
	max_hops: int
) -> Array:
	var all := multi_hop_destinations(catalog, origin_habitat_id, max_hops)
	var filtered: Array = []
	for entry_variant in all:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if int(entry.get("hops", 0)) == desired_hops:
			filtered.append(entry)
	return filtered


static func pick_destination(
	catalog: Catalog,
	origin_habitat_id: String,
	board: String,
	cfg: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var max_hops := max_hops_from_config(cfg)
	var desired_hops := roll_offer_hops(cfg, board, rng)
	var matches := destinations_for_hops(catalog, origin_habitat_id, desired_hops, max_hops)
	if matches.is_empty():
		matches = multi_hop_destinations(catalog, origin_habitat_id, max_hops)
	if matches.is_empty():
		return {}
	return matches[rng.randi() % matches.size()]


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


static func requires_habitat_life_support(offer: Dictionary) -> bool:
	return int(offer.get("hops", 1)) > 1


static func habitat_life_support_satisfied(assembled: AssembledShip) -> bool:
	return assembled.has_capability("ls_habitat")


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


static func board_seed(day: int, habitat_id: String, board: String, run_seed: int) -> int:
	return int(hash("%d:%d:%s:%s" % [run_seed, day, habitat_id, board]))


static func generate_offers(
	catalog: Catalog,
	origin_habitat_id: String,
	board: String,
	day: int,
	count: int,
	run_seed: int = 0
) -> Array:
	var cfg := config(catalog)
	var roles := roles_for_board(cfg, board)
	if roles.is_empty() or count <= 0:
		return []

	var origin := catalog.get_habitat(origin_habitat_id)
	var origin_sector := str(origin.get("sector_id", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = board_seed(day, origin_habitat_id, board, run_seed)

	var offers: Array = []
	for index in count:
		var role: Dictionary = roles[rng.randi() % roles.size()]
		var dest: Dictionary = pick_destination(catalog, origin_habitat_id, board, cfg, rng)
		if dest.is_empty():
			continue
		var qty_min := int(role.get("quantity_min", 1))
		var qty_max := int(role.get("quantity_max", qty_min))
		if qty_max < qty_min:
			qty_max = qty_min
		var quantity := rng.randi_range(qty_min, qty_max)
		var pay_multiplier := float(role.get("pay_multiplier", 1.0))
		var friction := int(dest.get("friction", 0))
		var hops := int(dest.get("hops", 1))
		var path_sectors: Array = dest.get("path_sectors", [])
		var deadline_hours := offer_deadline_hours(catalog, cfg, path_sectors)
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
		var destination_label := str(dest.get("habitat_name", "")) + str(dest.get("via_label", ""))
		var description := format_description(
			desc_template,
			quantity,
			destination_label,
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
			"hops": hops,
			"via_label": str(dest.get("via_label", "")),
			"path_sectors": path_sectors.duplicate(),
			"deadline_hours": deadline_hours,
			"role_id": str(role.get("id", "")),
			"role_title": str(role.get("title", "")),
			"affiliation": str(role.get("affiliation", "civilian")),
			"life_support": str(role.get("life_support", "spartan")),
			"quantity": quantity,
			"pay_multiplier": pay_multiplier,
			"requires_player_affiliation": bool(role.get("requires_player_affiliation", false)),
			"min_reputation": maxi(0, int(role.get("min_reputation", 0))),
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
	var needed := PILOT_LIFE_SUPPORT_SEATS + committed_passengers + quantity
	if capacity < float(needed):
		return {
			"ok": false,
			"reason": "Need %d life support seats (%d committed)."
			% [needed, committed_passengers + PILOT_LIFE_SUPPORT_SEATS],
		}

	var tier := str(offer.get("life_support", "spartan"))
	if not life_support_tier_satisfied(assembled, tier):
		return {"ok": false, "reason": "Ship lacks %s." % life_support_tier_label(tier)}

	if requires_habitat_life_support(offer) and not habitat_life_support_satisfied(assembled):
		return {"ok": false, "reason": "Need habitat life support for multi-hop charter."}

	if bool(offer.get("requires_player_affiliation", false)):
		var corp_id := str(offer.get("corporation_id", ""))
		if not PlayerAffiliation.is_affiliated(session, corp_id):
			return {"ok": false, "reason": "Requires affiliation with %s." % offer.get("corporation_name", corp_id)}

	var min_reputation := int(offer.get("min_reputation", 0))
	if min_reputation > 0 and session.player.reputation < min_reputation:
		return {
			"ok": false,
			"reason": "Requires reputation %d (yours is %d)."
			% [min_reputation, session.player.reputation],
		}

	return {"ok": true, "reason": ""}
