class_name FreightCharters
extends RefCounted


static func config(catalog: Catalog) -> Dictionary:
	return catalog.get_freight_missions_config()


static func board_seed(day: int, habitat_id: String, run_seed: int) -> int:
	return int(hash("%d:%d:%s:freight" % [run_seed, day, habitat_id]))


static func find_cargo(cfg: Dictionary, cargo_id: String) -> Dictionary:
	for entry_variant in cfg.get("cargos", []):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("id", "")) == cargo_id:
			return entry
	return {}


static func resolve_cargo(catalog: Catalog, cargo: Dictionary) -> Dictionary:
	var commodity_id := str(cargo.get("commodity_id", ""))
	var mass_per_unit := float(cargo.get("mass_per_unit", 0.0))
	var caps: Array = []
	if not commodity_id.is_empty():
		var commodity := catalog.get_commodity(commodity_id)
		mass_per_unit = float(commodity.get("mass", mass_per_unit))
		caps = CargoRequirements.required_capabilities(commodity)
	else:
		caps = _capability_array(cargo.get("requires_capabilities", []))
	return {
		"commodity_id": commodity_id,
		"mass_per_unit": mass_per_unit,
		"requires_capabilities": caps,
		"life_support_per_unit": float(cargo.get("life_support_per_unit", 0.0)),
		"compute_per_unit": float(cargo.get("compute_per_unit", 0.0)),
		"power_per_unit": float(cargo.get("power_per_unit", 0.0)),
	}


static func offer_tonnes(catalog: Catalog, cargo: Dictionary, quantity: int) -> float:
	var resolved := resolve_cargo(catalog, cargo)
	return float(quantity) * float(resolved.get("mass_per_unit", 0.0))


static func offer_life_support_seats(cargo: Dictionary, quantity: int) -> int:
	return int(round(float(quantity) * float(cargo.get("life_support_per_unit", 0.0))))


static func offer_compute_demand(cargo: Dictionary, quantity: int) -> float:
	return float(quantity) * float(cargo.get("compute_per_unit", 0.0))


static func offer_power_demand(cargo: Dictionary, quantity: int) -> float:
	return float(quantity) * float(cargo.get("power_per_unit", 0.0))


static func compute_reward(
	cfg: Dictionary,
	quantity: int,
	mass_per_unit: float,
	pay_multiplier: float,
	friction: int
) -> int:
	var base_pay := float(cfg.get("base_pay", 90))
	var friction_pay := float(cfg.get("friction_pay", 6))
	var raw := (
		float(quantity)
		* mass_per_unit
		* pay_multiplier
		* (base_pay + float(friction) * friction_pay)
	)
	return int(round(raw))


static func cancel_penalty(cfg: Dictionary, reward: int) -> int:
	var fraction := float(cfg.get("cancel_penalty_fraction", 0.25))
	return int(round(float(reward) * fraction))


static func format_description(
	template: String,
	quantity: int,
	destination_name: String,
	commodity_name: String
) -> String:
	return (
		template.replace("{quantity}", str(quantity))
		.replace("{destination}", destination_name)
		.replace("{commodity}", commodity_name)
	)


static func pick_description(
	cfg: Dictionary,
	cargo_id: String,
	rng: RandomNumberGenerator
) -> String:
	var matches: Array = []
	for entry_variant in cfg.get("descriptions", []):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var allowed: Variant = entry.get("cargos", [])
		if typeof(allowed) != TYPE_ARRAY:
			continue
		for ref in allowed:
			if str(ref) == cargo_id:
				matches.append(entry)
				break
	if matches.is_empty():
		return "{quantity} freight lot for {destination}."
	var picked: Dictionary = matches[rng.randi() % matches.size()]
	return str(picked.get("text", ""))


static func hold_requirement_phrase(caps: Array) -> String:
	if caps.is_empty():
		return "Dry hold"
	var parts: PackedStringArray = PackedStringArray()
	for cap_id in caps:
		parts.append(CargoRequirements.requirement_label(str(cap_id)))
	return ", ".join(parts)


static func generate_offers(
	catalog: Catalog,
	origin_habitat_id: String,
	day: int,
	count: int,
	run_seed: int = 0
) -> Array:
	var cfg := config(catalog)
	var destinations := PassengerCharters.neighbor_destinations(catalog, origin_habitat_id)
	var cargos: Array = []
	for cargo_variant in cfg.get("cargos", []):
		if typeof(cargo_variant) == TYPE_DICTIONARY:
			cargos.append(cargo_variant)
	if destinations.is_empty() or cargos.is_empty() or count <= 0:
		return []

	var rng := RandomNumberGenerator.new()
	rng.seed = board_seed(day, origin_habitat_id, run_seed)

	var offers: Array = []
	for index in count:
		var cargo: Dictionary = cargos[rng.randi() % cargos.size()]
		var cargo_id := str(cargo.get("id", ""))
		var dest: Dictionary = destinations[rng.randi() % destinations.size()]
		var qty_min := int(cargo.get("quantity_min", 1))
		var qty_max := int(cargo.get("quantity_max", qty_min))
		if qty_max < qty_min:
			qty_max = qty_min
		var quantity := rng.randi_range(qty_min, qty_max)
		var pay_multiplier := float(cargo.get("pay_multiplier", 1.0))
		var friction := int(dest.get("friction", 0))
		var resolved := resolve_cargo(catalog, cargo)
		var mass_per_unit := float(resolved.get("mass_per_unit", 0.0))
		var reward := compute_reward(cfg, quantity, mass_per_unit, pay_multiplier, friction)

		var commodity_name := ""
		var commodity_id := str(resolved.get("commodity_id", ""))
		if not commodity_id.is_empty():
			var commodity := catalog.get_commodity(commodity_id)
			commodity_name = str(commodity.get("name", commodity_id))

		var desc_template := pick_description(cfg, cargo_id, rng)
		var description := format_description(
			desc_template,
			quantity,
			str(dest.get("habitat_name", "")),
			commodity_name
		)
		var tonnes := float(quantity) * mass_per_unit
		var caps: Array = resolved.get("requires_capabilities", [])
		var ls_seats := offer_life_support_seats(cargo, quantity)
		var compute_cu := offer_compute_demand(cargo, quantity)
		var power_mw := offer_power_demand(cargo, quantity)

		offers.append({
			"id": "%d_%s_freight_%d" % [day, origin_habitat_id, index],
			"origin_habitat_id": origin_habitat_id,
			"destination_habitat_id": str(dest.get("habitat_id", "")),
			"destination_name": str(dest.get("habitat_name", "")),
			"destination_sector_id": str(dest.get("sector_id", "")),
			"friction": friction,
			"cargo_id": cargo_id,
			"cargo_title": str(cargo.get("title", cargo_id)),
			"commodity_id": commodity_id,
			"quantity": quantity,
			"mass_per_unit": mass_per_unit,
			"tonnes": tonnes,
			"requires_capabilities": caps.duplicate(),
			"life_support_seats": ls_seats,
			"compute_demand": compute_cu,
			"power_demand": power_mw,
			"pay_multiplier": pay_multiplier,
			"description": description,
			"hold_label": hold_requirement_phrase(caps),
			"reward": reward,
		})
	return offers


static func evaluate_offer_for_ship(
	session: GameSession,
	catalog: Catalog,
	offer: Dictionary,
	ship_id: String,
	committed: Dictionary
) -> Dictionary:
	var ship := session.get_owned_ship(ship_id)
	if ship == null:
		return {"ok": false, "reason": "Select a docked ship."}
	if ship.location != session.habitat_id:
		return {"ok": false, "reason": "Ship must be docked here."}

	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	var quantity := int(offer.get("quantity", 0))
	var tonnes := float(offer.get("tonnes", 0.0))
	var caps: Array = offer.get("requires_capabilities", [])

	for cap_id in caps:
		if not assembled.has_capability(str(cap_id)):
			return {
				"ok": false,
				"reason": "Need a %s hold."
				% CargoRequirements.requirement_label(str(cap_id)),
			}

	var cargo_capacity := float(assembled.capacities.get("cargo_capacity", 0.0))
	var mass_aboard := ShipOperations.get_cargo_mass(catalog, ship)
	var committed_tonnes := float(committed.get("tonnes", 0.0))
	if mass_aboard + committed_tonnes + tonnes > cargo_capacity + 0.001:
		return {
			"ok": false,
			"reason": "Need %.1f t free (%.1f committed)." % [tonnes, committed_tonnes],
		}

	var committed_passengers := int(committed.get("passengers", 0))
	var committed_freight_ls := int(committed.get("life_support_seats", 0))
	var offer_ls := int(offer.get("life_support_seats", 0))
	var ls_needed := committed_passengers + committed_freight_ls + offer_ls
	var ls_capacity := float(assembled.capacities.get("life_support_capacity", 0.0))
	if ls_capacity < float(ls_needed):
		return {
			"ok": false,
			"reason": "Need %d life support seats (%d committed)."
			% [ls_needed, committed_passengers + committed_freight_ls],
		}

	var occupant_for_idle := maxi(1, ls_needed)
	var idle := ShipOperations.idle_snapshot(catalog, assembled, ship, occupant_for_idle)
	var committed_compute := float(committed.get("compute", 0.0))
	var offer_compute := float(offer.get("compute_demand", 0.0))
	var spare_compute := idle.compute_capacity - idle.compute_demand - committed_compute
	if offer_compute > spare_compute + 0.001:
		return {"ok": false, "reason": "Not enough spare compute for this lot."}

	var committed_power := float(committed.get("power", 0.0))
	var offer_power := float(offer.get("power_demand", 0.0))
	var spare_power := idle.power_available - idle.power_requested - committed_power
	if offer_power > spare_power + 0.001:
		return {"ok": false, "reason": "Not enough spare power for this lot."}

	return {"ok": true, "reason": ""}


static func _capability_array(raw: Variant) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		return []
	var out: Array = []
	for cap_variant in raw:
		var cap_id := str(cap_variant)
		if not cap_id.is_empty():
			out.append(cap_id)
	return out
