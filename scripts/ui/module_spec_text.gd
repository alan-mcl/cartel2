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
	"description": true,
	"mount": true,
	"capabilities": true,
	"ammunition_capacity": true,
	"mounts": true,
}


static func format_tooltip(module_def: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()

	var name := str(module_def.get("name", ""))
	if not name.is_empty():
		lines.append(name)

	for identity_key in ["maker", "brand", "category", "plant_type", "core_type"]:
		var value := str(module_def.get(identity_key, ""))
		if value.is_empty():
			continue
		if identity_key in ["plant_type", "core_type"]:
			value = value.capitalize()
		lines.append("%s: %s" % [identity_key.capitalize(), value])

	var stat_lines := _format_stat_lines(module_def)
	if not stat_lines.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append("SPECS")
		for stat_line in stat_lines:
			lines.append(stat_line)

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

	return "\n".join(lines)


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
	if key in ["plant_type", "core_type"]:
		text = text.capitalize()
	return "%s: %s%s" % [label, text, suffix]


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
