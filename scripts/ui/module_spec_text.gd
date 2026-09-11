class_name ModuleSpecText
extends RefCounted

const STAT_ROWS: Array[Dictionary] = [
	{"key": "cost", "label": "Cost", "suffix": " d"},
	{"key": "mass", "label": "Mass", "suffix": " t", "float": true},
	{"key": "volume", "label": "Volume", "suffix": " m³", "float": true},
	{"key": "mount", "label": "Mount"},
	{"key": "power_generation", "label": "Output", "suffix": " MW", "float": true},
	{"key": "plant_type", "label": "Plant type"},
	{"key": "core_type", "label": "Core type"},
	{"key": "engine_type", "label": "Engine type"},
	{"key": "weapon_type", "label": "Weapon type"},
	{"key": "delivery_type", "label": "Delivery type"},
	{"key": "shield_type", "label": "Shield type"},
	{"key": "shield_capacity", "label": "Shield capacity", "float": true},
	{"key": "regen", "label": "Shield regen", "suffix": "/s", "float": true},
	{"key": "intercept_chance", "label": "Intercept chance", "float": true},
	{"key": "fuel_consumption", "label": "Fuel use", "float": true},
	{"key": "thrust", "label": "Thrust", "float": true},
	{"key": "max_speed", "label": "Max speed", "suffix": " km/s", "float": true},
	{"key": "boost_multiplier", "label": "Boost multiplier", "float": true},
	{"key": "power_demand", "label": "Power demand", "suffix": " MW", "float": true},
	{"key": "compute_capacity", "label": "Compute", "suffix": " CU", "float": true},
	{"key": "compute_demand", "label": "Compute demand", "suffix": " CU", "float": true},
	{"key": "life_support_capacity", "label": "Life support", "suffix": " people", "float": true},
	{"key": "damage", "label": "Damage", "float": true},
	{"key": "rate_of_fire", "label": "Rate of fire", "suffix": "/s", "float": true},
	{"key": "range", "label": "Range", "suffix": " m", "float": true},
	{"key": "projectile_speed", "label": "Projectile speed", "suffix": " m/s", "float": true},
	{"key": "hits", "label": "Armour hits", "float": true},
	{"key": "cargo_capacity", "label": "Cargo", "suffix": " t", "float": true},
	{"key": "fuel_capacity", "label": "Fuel capacity", "float": true},
	{"key": "ammunition_type", "label": "Ammunition type"},
	{"key": "ammunition_per_shot", "label": "Ammo per shot", "float": true},
]

const SKIP_EXTRA_KEYS := {
	"id": true,
	"name": true,
	"maker": true,
	"brand": true,
	"category": true,
	"plant_type": true,
	"core_type": true,
	"engine_type": true,
	"weapon_type": true,
	"delivery_type": true,
	"shield_type": true,
	"damage_packets": true,
	"protection": true,
	"description": true,
	"mount": true,
	"capabilities": true,
	"ammunition_capacity": true,
	"mounts": true,
	"signature": true,
	"sensor_type": true,
	"sensor_range": true,
	"sensor_sensitivity": true,
}


static func format_tooltip(module_def: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()

	var name := str(module_def.get("name", ""))
	if not name.is_empty():
		lines.append(name)

	for identity_key in [
		"maker",
		"brand",
		"category",
		"engine_type",
		"plant_type",
		"core_type",
		"weapon_type",
		"delivery_type",
		"shield_type",
	]:
		var value := str(module_def.get(identity_key, ""))
		if value.is_empty():
			continue
		value = _format_type_label(identity_key, value)
		lines.append("%s: %s" % [_identity_label(identity_key), value])

	var stat_lines := _format_stat_lines(module_def)
	if not stat_lines.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append("SPECS")
		for stat_line in stat_lines:
			lines.append(stat_line)

	var signature_lines := format_signature_lines(module_def.get("signature", {}))
	if not signature_lines.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append("SIGNATURE")
		for signature_line in signature_lines:
			lines.append(signature_line)

	var sensor_type := str(module_def.get("sensor_type", ""))
	if not sensor_type.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append("Sensor type: %s" % sensor_type)
		lines.append("Sensor range: %.0f m" % float(module_def.get("sensor_range", 0.0)))
		var sensitivity: Variant = module_def.get("sensor_sensitivity", {})
		if typeof(sensitivity) == TYPE_DICTIONARY:
			for channel in ["thermal", "gravitational", "electromagnetic", "computational"]:
				if sensitivity.has(channel):
					lines.append(
						"%s sensitivity: %.2f" % [channel, float(sensitivity.get(channel, 0.0))]
					)

	var description := str(module_def.get("description", "")).strip_edges()
	if not description.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append(description)

	var capabilities: Variant = module_def.get("capabilities", [])
	if typeof(capabilities) == TYPE_ARRAY and not capabilities.is_empty():
		if not lines.is_empty():
			lines.append("")
		var cap_parts: PackedStringArray = PackedStringArray()
		for entry in capabilities:
			cap_parts.append(str(entry))
		lines.append("Capabilities: %s" % ", ".join(cap_parts))

	var mounts: Variant = module_def.get("mounts", [])
	if typeof(mounts) == TYPE_ARRAY and not mounts.is_empty():
		if not lines.is_empty():
			lines.append("")
		var mount_parts: PackedStringArray = PackedStringArray()
		for entry in mounts:
			mount_parts.append(str(entry))
		lines.append("Compatible mounts: %s" % ", ".join(mount_parts))

	var ammo_capacity: Variant = module_def.get("ammunition_capacity", {})
	if typeof(ammo_capacity) == TYPE_DICTIONARY and not ammo_capacity.is_empty():
		if not lines.is_empty():
			lines.append("")
		for ammo_key in ammo_capacity.keys():
			lines.append(
				"Ammunition %s: %s" % [str(ammo_key), str(ammo_capacity.get(ammo_key, ""))]
			)

	var packets: Variant = module_def.get("damage_packets", {})
	if typeof(packets) == TYPE_DICTIONARY and not packets.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append("Damage packets")
		for packet_key in packets.keys():
			lines.append("  %s: %s" % [str(packet_key).capitalize(), str(packets.get(packet_key, ""))])

	var protection: Variant = module_def.get("protection", {})
	if typeof(protection) == TYPE_DICTIONARY and not protection.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append("Protection")
		for prot_key in protection.keys():
			var frac := float(protection.get(prot_key, 0.0))
			lines.append("  %s: %.0f%%" % [str(prot_key).capitalize(), frac * 100.0])

	return "\n".join(lines)


static func format_signature_lines(signature: Variant) -> PackedStringArray:
	if typeof(signature) != TYPE_DICTIONARY or signature.is_empty():
		return PackedStringArray()
	return SensorSystem.format_signature_lines(signature)


static func append_ship_signature_rows(parent: VBoxContainer, signature: Dictionary, transponder_label: String) -> void:
	if parent == null:
		return
	parent.add_child(_ship_section_label("SIGNATURE"))
	for line in SensorSystem.format_signature_lines(signature, transponder_label):
		var parts := line.split(": ", false, 1)
		var label_text := parts[0] if parts.size() > 0 else line
		var value_text := parts[1] if parts.size() > 1 else ""
		parent.add_child(_ship_detail_label(label_text.to_upper(), value_text))


static func _ship_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Section"
	return label


static func _ship_detail_label(label_text: String, value_text: String) -> Label:
	var row := Label.new()
	row.text = "%s: %s" % [label_text, value_text]
	row.theme_type_variation = &"Numeric"
	return row


static func _format_stat_lines(module_def: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var shown: Dictionary = {}

	for row in STAT_ROWS:
		var key := str(row.get("key", ""))
		if not module_def.has(key):
			continue
		var value: Variant = module_def.get(key)
		if typeof(value) == TYPE_STRING and str(value).strip_edges().is_empty():
			continue
		lines.append(_format_stat_row(row, value))
		shown[key] = true

	var extra_keys: Array = []
	for key in module_def.keys():
		var key_str := str(key)
		if shown.has(key_str) or SKIP_EXTRA_KEYS.has(key_str):
			continue
		extra_keys.append(key_str)
	extra_keys.sort()

	for key_str in extra_keys:
		var value: Variant = module_def.get(key_str)
		if typeof(value) == TYPE_STRING and str(value).strip_edges().is_empty():
			continue
		if typeof(value) in [TYPE_DICTIONARY, TYPE_ARRAY]:
			continue
		lines.append("%s: %s" % [_humanize_key(key_str), _format_value(value)])

	return lines


static func _format_stat_row(row: Dictionary, value: Variant) -> String:
	var key := str(row.get("key", ""))
	var label := str(row.get("label", key))
	var suffix := str(row.get("suffix", ""))
	if bool(row.get("float", false)) or typeof(value) in [TYPE_FLOAT, TYPE_INT]:
		return "%s: %s%s" % [label, _format_number(float(value)), suffix]
	var text := str(value)
	if key in ["plant_type", "core_type", "engine_type", "weapon_type", "delivery_type", "shield_type"]:
		text = _format_type_label(key, text)
	return "%s: %s%s" % [label, text, suffix]


static func _identity_label(key: String) -> String:
	if key == "engine_type":
		return "Engine type"
	return key.capitalize()


static func format_engine_type(value: String) -> String:
	return _format_type_label("engine_type", value)


static func _format_type_label(key: String, value: String) -> String:
	if key == "engine_type":
		match value:
			"chemical":
				return "Chemical"
			"hydro_thermal":
				return "Hydro-thermal"
			"electric_plasma":
				return "Electric plasma"
			"direct_fusion":
				return "Direct fusion"
			"antimatter":
				return "Antimatter"
			"gravitic":
				return "Gravitic"
			_:
				return value.capitalize()
	if key in ["plant_type", "core_type", "weapon_type", "shield_type"]:
		return value.capitalize()
	if key == "delivery_type":
		return value.capitalize()
	return value


static func _format_value(value: Variant) -> String:
	if typeof(value) in [TYPE_FLOAT, TYPE_INT]:
		return _format_number(float(value))
	return str(value)


static func _humanize_key(key: String) -> String:
	return key.replace("_", " ").capitalize()


static func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value
