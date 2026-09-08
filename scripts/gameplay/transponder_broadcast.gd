class_name TransponderBroadcast
extends RefCounted


static func generate_registration(catalog: Catalog, template_id: String) -> String:
	var traffic := catalog.get_traffic_config()
	var prefixes: Variant = traffic.get("callsign_prefixes", {})
	var prefix := str(prefixes.get(template_id, "TRF"))
	if prefix.is_empty():
		prefix = "TRF"
	return "VR-%s-%04d" % [prefix, randi() % 10000]


static func generate_corporate_callsign(affiliation: Dictionary) -> String:
	var ticker := str(affiliation.get("callsign_prefix", "CORP")).strip_edges()
	if ticker.is_empty():
		ticker = "CORP"
	return "%s-%d" % [ticker, randi_range(10, 999)]


static func generate_independent_callsign(traffic_config: Dictionary) -> String:
	var full: Variant = traffic_config.get("independent_callsigns", [])
	var prefixes: Variant = traffic_config.get("independent_callsign_prefixes", [])
	var roots: Variant = traffic_config.get("independent_callsign_roots", [])
	var can_combine: bool = (
		typeof(prefixes) == TYPE_ARRAY
		and typeof(roots) == TYPE_ARRAY
		and not prefixes.is_empty()
		and not roots.is_empty()
	)
	if can_combine and (typeof(full) != TYPE_ARRAY or full.is_empty() or randf() < 0.35):
		return "%s %s" % [str(prefixes[randi() % prefixes.size()]), str(roots[randi() % roots.size()])]
	if typeof(full) == TYPE_ARRAY and not full.is_empty():
		return str(full[randi() % full.size()])
	if can_combine:
		return "%s %s" % [str(prefixes[randi() % prefixes.size()]), str(roots[randi() % roots.size()])]
	return "Pilot"


static func generate_callsign_for_affiliation(
	traffic_config: Dictionary,
	affiliation: Dictionary
) -> String:
	if str(affiliation.get("kind", "corporate")) == "independent":
		return generate_independent_callsign(traffic_config)
	return generate_corporate_callsign(affiliation)


static func build(
	registration: String,
	callsign: String,
	ship_name: String = "",
	affiliation: String = ""
) -> Dictionary:
	return {
		"registration": registration.strip_edges(),
		"callsign": callsign.strip_edges(),
		"ship_name": ship_name.strip_edges(),
		"affiliation": affiliation.strip_edges(),
	}


static func player_broadcast(registration: String, callsign: String, ship_name: String = "") -> Dictionary:
	return build(registration, callsign, ship_name, "")


static func format_lines(data: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()

	var registration := str(data.get("registration", "")).strip_edges()
	var ship_name := str(data.get("ship_name", "")).strip_edges()
	if not registration.is_empty() and not ship_name.is_empty():
		lines.append("%s '%s'" % [registration, ship_name])
	elif not registration.is_empty():
		lines.append(registration)
	elif not ship_name.is_empty():
		lines.append("'%s'" % ship_name)

	var callsign := str(data.get("callsign", "")).strip_edges()
	var affiliation := _display_affiliation(str(data.get("affiliation", "")))
	if not callsign.is_empty():
		if affiliation.is_empty():
			lines.append(callsign)
		else:
			lines.append("%s (%s)" % [callsign, affiliation])

	return lines


static func _display_affiliation(affiliation: String) -> String:
	var value := affiliation.strip_edges()
	if value.is_empty() or value == "Independent Operator":
		return ""
	return value


static func format_tooltip(data: Dictionary) -> String:
	return "\n".join(format_lines(data))
