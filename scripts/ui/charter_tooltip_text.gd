class_name CharterTooltipText
extends RefCounted

const BULLET := "• "


static func format_passenger(
	entry: Dictionary,
	extra: String = "",
	accepted_origin: String = "",
	accepted_ship: String = ""
) -> String:
	var lines: PackedStringArray = PackedStringArray()

	var title := str(entry.get("role_title", "Charter")).strip_edges()
	if not title.is_empty():
		lines.append(title)

	var contract := _passenger_contract_line(entry, accepted_origin, accepted_ship)
	if not contract.is_empty():
		_append_section(lines, contract)

	var description := str(entry.get("description", "")).strip_edges()
	if not description.is_empty():
		_append_section(lines, description)

	var deadline := _deadline_line(entry)
	if not deadline.is_empty():
		_append_section(lines, deadline)

	var suggested := _suggested_route_line(entry)
	if not suggested.is_empty():
		_append_section(lines, suggested)

	var requirements := _passenger_requirement_lines(entry)
	if not requirements.is_empty():
		_append_section(lines, "Requirements")
		for req_line in requirements:
			lines.append(BULLET + req_line)

	var extra_trimmed := extra.strip_edges()
	if not extra_trimmed.is_empty():
		_append_section(lines, extra_trimmed)

	return "\n".join(lines)


static func format_freight(
	entry: Dictionary,
	extra: String = "",
	accepted_origin: String = "",
	accepted_ship: String = ""
) -> String:
	var lines: PackedStringArray = PackedStringArray()

	var title := _freight_title(entry)
	if not title.is_empty():
		lines.append(title)

	var description := str(entry.get("description", "")).strip_edges()
	if not description.is_empty() and description != title:
		_append_section(lines, description)
	elif description.is_empty() and title.is_empty():
		pass

	var contract := _freight_contract_line(entry, accepted_origin, accepted_ship)
	if not contract.is_empty():
		_append_section(lines, contract)

	var deadline := _deadline_line(entry)
	if not deadline.is_empty():
		_append_section(lines, deadline)

	var suggested := _suggested_route_line(entry)
	if not suggested.is_empty():
		_append_section(lines, suggested)

	var requirements := _freight_requirement_lines(entry)
	if not requirements.is_empty():
		_append_section(lines, "Requirements")
		for req_line in requirements:
			lines.append(BULLET + req_line)

	var extra_trimmed := extra.strip_edges()
	if not extra_trimmed.is_empty():
		_append_section(lines, extra_trimmed)

	return "\n".join(lines)


static func _passenger_contract_line(
	entry: Dictionary,
	accepted_origin: String,
	accepted_ship: String
) -> String:
	var destination := str(entry.get("destination_name", "")).strip_edges()
	var reward := int(entry.get("reward", 0))
	var quantity := int(entry.get("quantity", 0))
	var origin := accepted_origin.strip_edges()
	var ship := accepted_ship.strip_edges()
	if not origin.is_empty() and not ship.is_empty():
		return "%s → %s · %s · d%d" % [origin, destination, ship, reward]
	var parts: PackedStringArray = PackedStringArray()
	if not destination.is_empty():
		parts.append(destination)
	if quantity > 0:
		parts.append("%d pax" % quantity)
	parts.append("d%d" % reward)
	var corp := str(entry.get("corporation_name", "")).strip_edges()
	if not corp.is_empty():
		parts.append(corp)
	return " · ".join(parts)


static func _freight_contract_line(
	entry: Dictionary,
	accepted_origin: String,
	accepted_ship: String
) -> String:
	var destination := str(entry.get("destination_name", "")).strip_edges()
	var reward := int(entry.get("reward", 0))
	var tonnes := float(entry.get("tonnes", 0.0))
	var origin := accepted_origin.strip_edges()
	var ship := accepted_ship.strip_edges()
	if not origin.is_empty() and not ship.is_empty():
		return "%s → %s · %s · d%d" % [origin, destination, ship, reward]
	var parts: PackedStringArray = PackedStringArray()
	if not destination.is_empty():
		parts.append(destination)
	parts.append("%.1f t" % tonnes)
	parts.append("d%d" % reward)
	return " · ".join(parts)


static func _freight_title(entry: Dictionary) -> String:
	var title := str(entry.get("cargo_title", "")).strip_edges()
	if not title.is_empty():
		return title
	var description := str(entry.get("description", "")).strip_edges()
	if description.is_empty():
		return ""
	var newline := description.find("\n")
	if newline >= 0:
		return description.substr(0, newline).strip_edges()
	return description


static func _deadline_line(entry: Dictionary) -> String:
	var hours := int(entry.get("deadline_hours", 0))
	if hours <= 0:
		return ""
	return "Within %d h" % hours


static func _suggested_route_line(entry: Dictionary) -> String:
	var hops := int(entry.get("hops", 1))
	if hops <= 1:
		return ""
	var via := str(entry.get("via_label", ""))
	if via.strip_edges().is_empty():
		return "Suggested route: %d hops" % hops
	return "Suggested route: %d hops%s" % [hops, via]


static func _passenger_requirement_lines(entry: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	out.append("%s life support" % _life_support_tier_display(str(entry.get("life_support", "spartan"))))
	if PassengerCharters.requires_habitat_life_support(entry):
		out.append("Habitat life support")
	var quantity := int(entry.get("quantity", 0))
	if quantity > 0:
		out.append("%d passenger seats" % quantity)
	var min_reputation := int(entry.get("min_reputation", 0))
	if min_reputation > 0:
		out.append("Reputation %d" % min_reputation)
	if bool(entry.get("requires_player_affiliation", false)):
		var corp := str(entry.get("corporation_name", "")).strip_edges()
		if corp.is_empty():
			corp = str(entry.get("corporation_id", "")).strip_edges()
		if corp.is_empty():
			out.append("Affiliation with posting corporation")
		else:
			out.append("Affiliation with %s" % corp)
	return out


static func _freight_requirement_lines(entry: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var caps: Variant = entry.get("requires_capabilities", [])
	if typeof(caps) == TYPE_ARRAY and not caps.is_empty():
		for cap_variant in caps:
			out.append(CargoRequirements.requirement_label(str(cap_variant)))
	else:
		out.append("Dry hold")
	var tonnes := float(entry.get("tonnes", 0.0))
	if tonnes > 0.001:
		out.append("%.1f t cargo" % tonnes)
	var ls_seats := int(entry.get("life_support_seats", 0))
	if ls_seats > 0:
		out.append("%d life support seats" % ls_seats)
	var compute_cu := float(entry.get("compute_demand", 0.0))
	if compute_cu > 0.001:
		out.append("%.1f CU" % compute_cu)
	var power_mw := float(entry.get("power_demand", 0.0))
	if power_mw > 0.001:
		out.append("%.1f MW" % power_mw)
	var min_reputation := int(entry.get("min_reputation", 0))
	if min_reputation > 0:
		out.append("Reputation %d" % min_reputation)
	return out


static func _life_support_tier_display(tier: String) -> String:
	match tier:
		"luxury":
			return "Luxury"
		"comfort":
			return "Comfort"
		_:
			return "Spartan"


static func _append_section(lines: PackedStringArray, text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	if not lines.is_empty():
		lines.append("")
	lines.append(trimmed)
