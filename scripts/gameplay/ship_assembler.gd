class_name ShipAssembler
extends RefCounted

const THRUST_SCALE := 1.25
const REVERSE_RATIO := 0.6153846153846154
const BOOST_SPEED_CAP := 980.0
const FUEL_MASS_PER_UNIT := 0.05

const MANEUVER_ROTATION := {
	"low": 2.0,
	"medium": 2.6,
	"high": 3.2,
}

const MANEUVER_DAMP := {
	"low": 0.45,
	"medium": 0.40,
	"high": 0.35,
}

const PROVIDES_KEYS := [
	"power_generation",
	"power_distribution",
	"compute_capacity",
	"heat_dissipation",
	"life_support_capacity",
	"cargo_capacity",
	"fuel_capacity",
]

const MOUNT_CATEGORIES := [
	"main_engine",
	"power",
	"maneuver",
	"system",
	"utility",
	"light_weapon",
	"medium_weapon",
	"heavy_weapon",
]


static func assemble(catalog: Catalog, ship_id: String) -> AssembledShip:
	var template := catalog.get_ship(ship_id)
	if template.is_empty():
		push_error("Cannot assemble unknown ship: %s" % ship_id)
		return AssembledShip.new()

	var chassis := catalog.get_chassis(str(template.get("chassis", "")))
	var module_ids: Array = []
	var raw_modules: Variant = template.get("modules", [])
	if typeof(raw_modules) == TYPE_ARRAY:
		for module_id in raw_modules:
			module_ids.append(str(module_id))

	var owned := OwnedShip.new()
	owned.id = ship_id
	owned.name = str(template.get("name", ship_id))
	owned.template_id = ship_id
	owned.chassis_id = str(template.get("chassis", ""))
	owned.modules = assign_modules_to_slots(catalog, chassis, module_ids)
	return assemble_owned(catalog, owned)


static func assemble_owned(catalog: Catalog, owned: OwnedShip, load_state: bool = true) -> AssembledShip:
	if owned == null or owned.id.is_empty():
		push_error("Cannot assemble invalid owned ship.")
		return AssembledShip.new()

	var template: Dictionary = {}
	if not owned.template_id.is_empty():
		template = catalog.get_ship(owned.template_id)

	var chassis_data := catalog.get_chassis(owned.chassis_id)
	var assembled := AssembledShip.new()
	assembled.id = owned.id
	assembled.name = owned.name
	assembled.maker = str(template.get("maker", chassis_data.get("maker", "")))
	assembled.chassis = chassis_data
	assembled.installed_modules = _resolve_installed_modules(catalog, owned)
	assembled.mounts = _calculate_mount_usage(assembled.chassis, assembled.installed_modules)
	assembled.capacities = _calculate_capacities(catalog, assembled)
	assembled.envelope = _calculate_envelope(assembled)

	if load_state:
		var loaded_mass := calculate_loaded_mass(catalog, owned, assembled)
		assembled.stats = derive_stats(assembled, loaded_mass)
	else:
		assembled.stats = derive_stats(assembled, float(assembled.envelope.get("dry_mass", 0.0)))

	return assembled


static func assign_modules_to_slots(catalog: Catalog, chassis: Dictionary, module_ids: Array) -> Array:
	var result: Array = []
	var mount_usage: Dictionary = {}
	var internal_index := 1

	for module_id in module_ids:
		var module_def := catalog.get_module(str(module_id))
		if module_def.is_empty():
			continue

		var mount := str(module_def.get("mount", ""))
		if mount.is_empty():
			result.append({"slot": "internal_%d" % internal_index, "module_id": str(module_id)})
			internal_index += 1
			continue

		var slot := _next_free_mount_slot(chassis, mount, mount_usage)
		if slot.is_empty():
			push_error("No free slot for module '%s' mount '%s'." % [module_id, mount])
			continue
		result.append({"slot": slot, "module_id": str(module_id)})

	return result


static func validate_install(
	catalog: Catalog,
	owned: OwnedShip,
	slot: String,
	module_id: String
) -> Dictionary:
	var result := {"ok": false, "reason": ""}
	if owned == null or module_id.is_empty() or slot.is_empty():
		result["reason"] = "Invalid install request."
		return result

	var module_def := catalog.get_module(module_id)
	if module_def.is_empty():
		result["reason"] = "Unknown module."
		return result

	var chassis := catalog.get_chassis(owned.chassis_id)
	if chassis.is_empty():
		result["reason"] = "Unknown chassis."
		return result

	if not _slot_compatible(catalog, chassis, slot, module_def):
		result["reason"] = "Module incompatible with slot."
		return result

	var trial: OwnedShip = OwnedShip.from_dict(owned.to_dict())
	trial.set_module(slot, module_id)
	var assembled := assemble_owned(catalog, trial, false)

	var dry_mass := float(assembled.envelope.get("dry_mass", 0.0))
	var mass_limit := float(assembled.envelope.get("mass_limit", 0.0))
	if dry_mass > mass_limit:
		result["reason"] = "Exceeds mass limit (%.1f / %.1f t)." % [dry_mass, mass_limit]
		return result

	var volume_used := float(assembled.envelope.get("volume_used", 0.0))
	var volume_limit := float(assembled.envelope.get("volume", 0.0))
	if volume_used > volume_limit:
		result["reason"] = "Exceeds internal volume (%.1f / %.1f m³)." % [volume_used, volume_limit]
		return result

	result["ok"] = true
	return result


static func derive_stats(assembled: AssembledShip, loaded_mass: float) -> ShipStats:
	var stats := ShipStats.new()
	if assembled.chassis.is_empty():
		return stats

	var engine := assembled.get_propulsion_module()
	if engine.is_empty():
		return stats

	var mass: float = maxf(loaded_mass, 0.1)
	var engine_thrust := float(engine.get("thrust", 0.0))
	var max_speed := float(engine.get("max_speed", 0.0))
	var boost_multiplier := float(engine.get("boost_multiplier", 1.0))
	var maneuver := str(assembled.chassis.get("maneuver", "medium"))

	stats.forward_thrust = engine_thrust / mass * THRUST_SCALE
	stats.reverse_thrust = stats.forward_thrust * REVERSE_RATIO
	stats.boost_multiplier = boost_multiplier
	stats.max_speed = max_speed
	stats.boost_max_speed = min(max_speed * boost_multiplier, BOOST_SPEED_CAP)
	stats.rotation_speed = float(MANEUVER_ROTATION.get(maneuver, MANEUVER_ROTATION["medium"]))
	stats.linear_damp = float(MANEUVER_DAMP.get(maneuver, MANEUVER_DAMP["medium"]))
	return stats


static func calculate_loaded_mass(catalog: Catalog, owned: OwnedShip, assembled: AssembledShip) -> float:
	var mass := float(assembled.envelope.get("dry_mass", 0.0))
	mass += owned.fuel_current * FUEL_MASS_PER_UNIT

	for commodity_id in owned.cargo.keys():
		var qty := owned.get_cargo_count(str(commodity_id))
		var commodity := catalog.get_commodity(str(commodity_id))
		mass += float(commodity.get("mass", 0.0)) * qty

	for ammo_id in owned.ammunition.keys():
		var qty := owned.get_ammo_count(str(ammo_id))
		var ammo := catalog.get_ammunition(str(ammo_id))
		mass += float(ammo.get("mass", 0.5)) * qty

	return mass


static func get_stat_block(catalog: Catalog, owned: OwnedShip) -> Dictionary:
	var assembled := assemble_owned(catalog, owned)
	if assembled.chassis.is_empty():
		return {}

	var loaded_mass := calculate_loaded_mass(catalog, owned, assembled)
	var maneuver := str(assembled.chassis.get("maneuver", "medium"))
	var armour := assembled.get_armour_module()
	return {
		"dry_mass": float(assembled.envelope.get("dry_mass", 0.0)),
		"loaded_mass": loaded_mass,
		"mass_limit": float(assembled.envelope.get("mass_limit", 0.0)),
		"volume_used": float(assembled.envelope.get("volume_used", 0.0)),
		"volume": float(assembled.envelope.get("volume", 0.0)),
		"thrust": assembled.stats.forward_thrust,
		"max_speed": assembled.stats.max_speed,
		"boost_max_speed": assembled.stats.boost_max_speed,
		"maneuver": maneuver,
		"armour_hits": int(armour.get("hits", 0)) if not armour.is_empty() else 0,
		"chassis_hits": int(assembled.chassis.get("hits", 0)),
		"capacities": assembled.capacities.duplicate(true),
		"mounts": assembled.mounts.duplicate(true),
	}


static func list_slots_for_chassis(chassis: Dictionary) -> Array:
	var slots: Array = []
	var mounts: Variant = chassis.get("mounts", {})
	if typeof(mounts) != TYPE_DICTIONARY:
		return slots

	for mount_category in MOUNT_CATEGORIES:
		var count := int(mounts.get(mount_category, 0))
		for i in range(count):
			slots.append("%s_%d" % [mount_category, i + 1])

	for i in range(1, 13):
		slots.append("internal_%d" % i)
	return slots


static func list_visible_slots(catalog: Catalog, owned: OwnedShip) -> Array:
	var slots: Array = []
	if owned == null:
		return slots

	var chassis := catalog.get_chassis(owned.chassis_id)
	var mounts: Variant = chassis.get("mounts", {})
	if typeof(mounts) == TYPE_DICTIONARY:
		for mount_category in MOUNT_CATEGORIES:
			var count := int(mounts.get(mount_category, 0))
			for i in range(count):
				slots.append("%s_%d" % [mount_category, i + 1])

	var max_internal_index := 0
	for entry in owned.modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		if not slot.begins_with("internal_"):
			continue
		if not slots.has(slot):
			slots.append(slot)
		var index := int(slot.trim_prefix("internal_"))
		max_internal_index = maxi(max_internal_index, index)

	var empty_internal := "internal_%d" % (max_internal_index + 1)
	if max_internal_index == 0:
		empty_internal = "internal_1"
	if not slots.has(empty_internal):
		slots.append(empty_internal)

	return slots


static func slot_mount_type(slot: String) -> String:
	if slot.begins_with("internal_"):
		return "internal"
	for mount_category in MOUNT_CATEGORIES:
		if slot.begins_with("%s_" % mount_category):
			return mount_category
	return ""


static func _resolve_installed_modules(catalog: Catalog, owned: OwnedShip) -> Array:
	var result: Array = []
	for entry in owned.modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		var module_id := str(entry.get("module_id", ""))
		if slot.is_empty() or module_id.is_empty():
			continue
		var module_def := catalog.get_module(module_id)
		result.append({
			"slot": slot,
			"module_id": module_id,
			"data": module_def,
		})
	return result


static func _calculate_mount_usage(chassis: Dictionary, installed_modules: Array) -> Dictionary:
	var mounts_def: Variant = chassis.get("mounts", {})
	var usage: Dictionary = {}
	if typeof(mounts_def) == TYPE_DICTIONARY:
		for mount_category in MOUNT_CATEGORIES:
			var total := int(mounts_def.get(mount_category, 0))
			if total > 0:
				usage[mount_category] = {"used": 0, "total": total}

	for entry in installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		var mount_type := slot_mount_type(slot)
		if mount_type == "internal" or mount_type.is_empty():
			continue
		if not usage.has(mount_type):
			usage[mount_type] = {"used": 0, "total": 0}
		usage[mount_type]["used"] = int(usage[mount_type]["used"]) + 1

	return usage


static func _calculate_capacities(catalog: Catalog, assembled: AssembledShip) -> Dictionary:
	var capacities := {
		"power_generation": 0.0,
		"power_distribution": 0.0,
		"compute_capacity": 0.0,
		"heat_dissipation": 0.0,
		"life_support_capacity": 0.0,
		"cargo_capacity": 0.0,
		"fuel_capacity": 0.0,
		"passenger_capacity": 0.0,
		"ammunition_capacity": {},
		"hull_hits": int(assembled.chassis.get("hits", 0)),
		"heat_capacity": float(assembled.chassis.get("heat_capacity", 80.0)),
	}

	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", {})
		if typeof(module_def) != TYPE_DICTIONARY:
			continue

		for key in PROVIDES_KEYS:
			if module_def.has(key):
				capacities[key] = float(capacities[key]) + float(module_def.get(key, 0.0))

		if module_def.has("hits"):
			capacities["hull_hits"] = int(capacities["hull_hits"]) + int(module_def.get("hits", 0))

		var ammo_cap: Variant = module_def.get("ammunition_capacity", {})
		if typeof(ammo_cap) == TYPE_DICTIONARY:
			for ammo_id in ammo_cap.keys():
				var current := int(capacities["ammunition_capacity"].get(ammo_id, 0))
				capacities["ammunition_capacity"][ammo_id] = current + int(ammo_cap[ammo_id])

	return capacities


static func _calculate_envelope(assembled: AssembledShip) -> Dictionary:
	var dry_mass := float(assembled.chassis.get("mass", 0.0))
	var volume_used := 0.0
	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", {})
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		dry_mass += float(module_def.get("mass", 0.0))
		volume_used += float(module_def.get("volume", 0.0))

	return {
		"dry_mass": dry_mass,
		"volume_used": volume_used,
		"mass_limit": float(assembled.chassis.get("mass_limit", dry_mass)),
		"volume": float(assembled.chassis.get("volume", volume_used)),
	}


static func _next_free_mount_slot(chassis: Dictionary, mount: String, mount_usage: Dictionary) -> String:
	var mounts: Variant = chassis.get("mounts", {})
	if typeof(mounts) != TYPE_DICTIONARY:
		return ""

	var total := int(mounts.get(mount, 0))
	if total <= 0:
		return ""

	if not mount_usage.has(mount):
		mount_usage[mount] = 0

	var used := int(mount_usage[mount])
	if used >= total:
		return ""

	mount_usage[mount] = used + 1
	return "%s_%d" % [mount, used + 1]


static func _slot_compatible(_catalog: Catalog, chassis: Dictionary, slot: String, module_def: Dictionary) -> bool:
	var mount := str(module_def.get("mount", ""))
	if slot.begins_with("internal_"):
		return mount.is_empty()

	if mount.is_empty():
		return slot.begins_with("internal_")

	var expected_prefix := "%s_" % mount
	if not slot.begins_with(expected_prefix):
		return false

	var mounts: Variant = chassis.get("mounts", {})
	if typeof(mounts) != TYPE_DICTIONARY:
		return false
	return int(mounts.get(mount, 0)) > 0
