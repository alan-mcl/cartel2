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
	"life_support_capacity",
	"cargo_capacity",
]

const MOUNT_CATEGORIES := [
	"main_engine",
	"power",
	"maneuver",
	"system",
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
	assembled.capabilities = _aggregate_capabilities(assembled)
	assembled.envelope = _calculate_envelope(assembled)
	assembled.build_caches()

	if load_state:
		var loaded_mass := calculate_loaded_mass(catalog, owned, assembled)
		assembled.stats = derive_stats(assembled, loaded_mass)
		assembled.signature = SensorSystem.compute_ship_signature(assembled, loaded_mass)
	else:
		var dry_mass := float(assembled.envelope.get("dry_mass", 0.0))
		assembled.stats = derive_stats(assembled, dry_mass)
		assembled.signature = SensorSystem.compute_ship_signature(assembled, dry_mass)

	assembled.sensor_profile = SensorSystem.compute_static_sensor_profile(assembled)

	return assembled


static func module_mounts(module_def: ModuleDef) -> Array:
	if module_def == null:
		return ["other"]
	if not module_def.mounts.is_empty():
		return module_def.mounts.duplicate()
	if not module_def.mount.is_empty():
		return [module_def.mount]
	return ["other"]


static func seed_ammunition(catalog: Catalog, owned: OwnedShip, fill_ratio: float = 1.0) -> void:
	if owned == null:
		return
	var assembled := assemble_owned(catalog, owned)
	var caps: Variant = assembled.capacities.get("ammunition_capacity", {})
	if typeof(caps) != TYPE_DICTIONARY:
		return
	for ammo_type in caps.keys():
		var capacity := int(caps[ammo_type])
		if capacity <= 0:
			continue
		var fill_amount := int(float(capacity) * clampf(fill_ratio, 0.0, 1.0))
		if fill_amount > 0:
			owned.ammunition[str(ammo_type)] = float(fill_amount)


static func assign_modules_to_slots(catalog: Catalog, chassis: Dictionary, module_ids: Array) -> Array:
	var result: Array = []
	var mount_usage: Dictionary = {}
	var other_index := 1

	for module_id in module_ids:
		var module_def := catalog.get_module_def(str(module_id))
		if module_def == null:
			continue

		var allowed_mounts := module_mounts(module_def)
		var placed := false
		for mount in allowed_mounts:
			if str(mount) == "other":
				result.append({"slot": "other_%d" % other_index, "module_id": str(module_id)})
				other_index += 1
				placed = true
				break

			var slot := _next_free_mount_slot(chassis, str(mount), mount_usage)
			if not slot.is_empty():
				result.append({"slot": slot, "module_id": str(module_id)})
				placed = true
				break

		if not placed:
			push_error("No free slot for module '%s'." % module_id)

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

	var module_def := catalog.get_module_def(module_id)
	if module_def == null:
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

	var engine := assembled.get_propulsion_module_def()
	if engine == null:
		return stats

	var mass: float = maxf(loaded_mass, 0.1)
	var engine_thrust := engine.thrust
	var max_speed := engine.max_speed
	var boost_multiplier := engine.boost_multiplier
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
	mass += ShipFuel.propulsion_fuel_mass(catalog, owned)

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
	var armour := assembled.get_armour_module_def()
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
		"armour_hits": int(armour.hits) if armour != null else 0,
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
		slots.append("other_%d" % i)
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

	var max_other_index := 0
	for entry in owned.modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		if not slot.begins_with("other_"):
			continue
		if not slots.has(slot):
			slots.append(slot)
		var index := int(slot.trim_prefix("other_"))
		max_other_index = maxi(max_other_index, index)

	var empty_other := "other_%d" % (max_other_index + 1)
	if max_other_index == 0:
		empty_other = "other_1"
	if not slots.has(empty_other):
		slots.append(empty_other)

	return slots


static func slot_mount_type(slot: String) -> String:
	if slot.begins_with("other_"):
		return "other"
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
		var module_def := catalog.get_module_def(module_id)
		if module_def == null:
			continue
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
		if mount_type == "other" or mount_type.is_empty():
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
		"life_support_capacity": 0.0,
		"cargo_capacity": 0.0,
		"fuel_capacity": 0.0,
		"passenger_capacity": 0.0,
		"ammunition_capacity": {},
		"hull_hits": int(assembled.chassis.get("hits", 0)),
	}

	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", null)
		if module_def == null or not module_def is ModuleDef:
			continue

		for key in PROVIDES_KEYS:
			if not _module_provides_key(module_def, key):
				continue
			capacities[key] = float(capacities[key]) + _module_provides_value(module_def, key)

		if module_def.has_source_key("hits"):
			capacities["hull_hits"] = int(capacities["hull_hits"]) + int(module_def.hits)

		for ammo_id in module_def.ammunition_capacity.keys():
			var current := int(capacities["ammunition_capacity"].get(ammo_id, 0))
			capacities["ammunition_capacity"][ammo_id] = (
				current + int(module_def.ammunition_capacity[ammo_id])
			)

	capacities["fuel_capacity"] = _propulsion_fuel_capacity(assembled)
	return capacities


static func _propulsion_fuel_capacity(assembled: AssembledShip) -> float:
	var total := 0.0
	var engine := assembled.get_propulsion_module_def()
	if engine != null:
		total += engine.fuel_capacity
	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", null)
		if module_def == null or not module_def is ModuleDef:
			continue
		if module_def.category == "fuel":
			total += module_def.fuel_capacity
	return total


static func _aggregate_capabilities(assembled: AssembledShip) -> Dictionary:
	var capabilities: Dictionary = {}
	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", null)
		if module_def == null or not module_def is ModuleDef:
			continue
		for cap in module_def.capabilities:
			capabilities[str(cap)] = true
	return capabilities


static func _calculate_envelope(assembled: AssembledShip) -> Dictionary:
	var dry_mass := float(assembled.chassis.get("mass", 0.0))
	var volume_used := 0.0
	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", null)
		if module_def == null or not module_def is ModuleDef:
			continue
		dry_mass += module_def.mass
		volume_used += module_def.volume

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


static func _module_provides_key(module_def: ModuleDef, key: String) -> bool:
	return module_def.has_source_key(key)


static func _module_provides_value(module_def: ModuleDef, key: String) -> float:
	match key:
		"power_generation":
			return module_def.power_generation
		"power_distribution":
			return 0.0
		"compute_capacity":
			return module_def.compute_capacity
		"life_support_capacity":
			return module_def.life_support_capacity
		"cargo_capacity":
			return module_def.cargo_capacity
		"fuel_capacity":
			return module_def.fuel_capacity
		_:
			return 0.0


static func _slot_compatible(_catalog: Catalog, chassis: Dictionary, slot: String, module_def: ModuleDef) -> bool:
	if module_def == null:
		return false
	var slot_type := slot_mount_type(slot)
	if slot_type.is_empty():
		return false

	var allowed_mounts := module_mounts(module_def)
	if not allowed_mounts.has(slot_type):
		return false

	if slot_type == "other":
		return slot.begins_with("other_")

	var expected_prefix := "%s_" % slot_type
	if not slot.begins_with(expected_prefix):
		return false

	var mounts: Variant = chassis.get("mounts", {})
	if typeof(mounts) != TYPE_DICTIONARY:
		return false
	return int(mounts.get(slot_type, 0)) > 0
