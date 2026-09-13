class_name AssembledShip
extends RefCounted

var id: String = ""
var name: String = ""
var maker: String = ""
var chassis: Dictionary = {}
var installed_modules: Array = []
var mounts: Dictionary = {}
var capacities: Dictionary = {}
var capabilities: Dictionary = {}
var envelope: Dictionary = {}
var stats: ShipStats = ShipStats.new()
var signature: Dictionary = {}
var sensor_profile: Dictionary = {}
var signature_basis: Dictionary = {}
var modules_by_category: Dictionary = {}
var _module_caches_ready: bool = false
var has_transponder_installed: bool = false
var has_active_sensor_package_installed: bool = false
var propulsion_module: ModuleDef = null
var armour_module: ModuleDef = null


func has_capability(id: String) -> bool:
	return capabilities.get(id, false)


func has_transponder() -> bool:
	if not _module_caches_ready:
		_rebuild_module_caches()
	return has_transponder_installed


func has_active_sensor_package() -> bool:
	if not _module_caches_ready:
		_rebuild_module_caches()
	return has_active_sensor_package_installed


func get_summary() -> String:
	var parts: PackedStringArray = PackedStringArray([name])
	if not chassis.is_empty():
		parts.append(str(chassis.get("name", "")))

	var engine := get_propulsion_module_def()
	if engine != null:
		parts.append(engine.name)

	return " · ".join(parts)


func get_module_def(slot: String) -> ModuleDef:
	for entry in installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("slot", "")) == slot:
			var module_data: Variant = entry.get("data", null)
			if module_data is ModuleDef:
				return module_data
	return null


func get_module(slot: String) -> Dictionary:
	var module_def := get_module_def(slot)
	if module_def == null:
		return {}
	return module_def.to_dict()


func get_module_id(slot: String) -> String:
	for entry in installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("slot", "")) == slot:
			return str(entry.get("module_id", ""))
	return ""


func modules_in_category(category: String) -> Array:
	if not _module_caches_ready:
		_rebuild_module_caches()
	var cached: Variant = modules_by_category.get(category, null)
	if cached == null:
		return []
	return cached as Array


func get_propulsion_module_def() -> ModuleDef:
	if not _module_caches_ready:
		_rebuild_module_caches()
	return propulsion_module


func get_armour_module_def() -> ModuleDef:
	if not _module_caches_ready:
		_rebuild_module_caches()
	return armour_module


func get_propulsion_module() -> Dictionary:
	var module_def := get_propulsion_module_def()
	if module_def == null:
		return {}
	return module_def.to_dict()


func get_armour_module() -> Dictionary:
	var module_def := get_armour_module_def()
	if module_def == null:
		return {}
	return module_def.to_dict()


func ensure_signature_basis() -> void:
	if signature_basis.is_empty():
		signature_basis = SensorSystem.compute_signature_basis(self)


func build_caches() -> void:
	_rebuild_module_caches()
	signature_basis = SensorSystem.compute_signature_basis(self)


func _rebuild_module_caches() -> void:
	_module_caches_ready = true
	modules_by_category = {}
	for entry in installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_data: Variant = entry.get("data", null)
		if module_data == null or not module_data is ModuleDef:
			continue
		var category := str(module_data.category)
		if not modules_by_category.has(category):
			modules_by_category[category] = []
		(modules_by_category[category] as Array).append(entry)

	has_transponder_installed = modules_by_category.has("transponder") and not (
		modules_by_category["transponder"] as Array
	).is_empty()

	has_active_sensor_package_installed = false
	for entry_variant in modules_in_category("sensor"):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var module_data: Variant = (entry_variant as Dictionary).get("data", null)
		if module_data == null or not module_data is ModuleDef:
			continue
		if module_data.has_active:
			has_active_sensor_package_installed = true
			break

	propulsion_module = null
	for entry_variant in modules_in_category("propulsion"):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var module_data: Variant = (entry_variant as Dictionary).get("data", null)
		if module_data is ModuleDef:
			propulsion_module = module_data
			break

	armour_module = null
	for entry_variant in modules_in_category("armour"):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var module_data: Variant = (entry_variant as Dictionary).get("data", null)
		if module_data is ModuleDef:
			armour_module = module_data
			break
