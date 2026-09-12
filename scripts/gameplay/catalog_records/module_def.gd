## Generated — do not edit. Run scripts/tools/generate_catalog_records.py.

class_name ModuleDef
extends RefCounted

var _present_keys: Dictionary = {}

var id: String = ""
var name: String = ""
var maker: String = ""
var brand: String = ""
var category: String = ""
var mount: String = ""
var mounts: Array = []
var mass: float = 0
var volume: float = 0
var cost: float = 0
var description: String = ""
var capabilities: Array = []
var signature: CatalogSignature = CatalogSignature.new()
var engine_type: String = ""
var thrust: float = 0.0
var max_speed: float = 0.0
var boost_multiplier: float = 0.0
var fuel_consumption: float = 0.0
var plant_type: String = ""
var power_generation: float = 0.0
var power_demand: float = 0.0
var core_type: String = ""
var compute_capacity: float = 0.0
var compute_demand: float = 0.0
var life_support_capacity: float = 0.0
var hits: float = 0.0
var protection: CatalogDamagePackets = CatalogDamagePackets.new()
var cargo_capacity: float = 0.0
var fuel_capacity: float = 0.0
var weapon_type: String = ""
var delivery_type: String = ""
var rate_of_fire: float = 0.0
var range: float = 0.0
var projectile_speed: float = 0.0
var ammunition_type: String = ""
var ammunition_per_shot: float = 0.0
var ammunition_capacity: Dictionary = {}
var damage_packets: CatalogDamagePackets = CatalogDamagePackets.new()
var shield_type: String = ""
var shield_capacity: float = 0.0
var regen: float = 0.0
var has_active: bool = false
var sensor_range: float = 0.0
var sensor_sensitivity: CatalogSignature = CatalogSignature.new()
var sensor_sensitivity_passive: CatalogSignature = CatalogSignature.new()
var area_effect: bool = false
var intercept_chance: float = 0.0

static func from_dict(data: Dictionary) -> ModuleDef:
	var def := ModuleDef.new()
	for key in data.keys():
		def._present_keys[str(key)] = true
	def.id = str(data.get("id", ""))
	def.name = str(data.get("name", ""))
	def.maker = str(data.get("maker", ""))
	def.brand = str(data.get("brand", ""))
	def.category = str(data.get("category", ""))
	def.mount = str(data.get("mount", ""))
	def.mounts = []
	var raw_mounts: Variant = data.get("mounts", [])
	if typeof(raw_mounts) == TYPE_ARRAY:
		for item in raw_mounts:
			def.mounts.append(str(item))
	def.mass = float(data.get("mass", 0))
	def.volume = float(data.get("volume", 0))
	def.cost = float(data.get("cost", 0))
	def.description = str(data.get("description", ""))
	def.capabilities = []
	var raw_capabilities: Variant = data.get("capabilities", [])
	if typeof(raw_capabilities) == TYPE_ARRAY:
		for item in raw_capabilities:
			def.capabilities.append(str(item))
	def.signature = CatalogSignature.from_dict(data.get("signature", {}))
	def.engine_type = str(data.get("engine_type", ""))
	def.thrust = float(data.get("thrust", 0.0))
	def.max_speed = float(data.get("max_speed", 0.0))
	def.boost_multiplier = float(data.get("boost_multiplier", 0.0))
	def.fuel_consumption = float(data.get("fuel_consumption", 0.0))
	def.plant_type = str(data.get("plant_type", ""))
	def.power_generation = float(data.get("power_generation", 0.0))
	def.power_demand = float(data.get("power_demand", 0.0))
	def.core_type = str(data.get("core_type", ""))
	def.compute_capacity = float(data.get("compute_capacity", 0.0))
	def.compute_demand = float(data.get("compute_demand", 0.0))
	def.life_support_capacity = float(data.get("life_support_capacity", 0.0))
	def.hits = float(data.get("hits", 0.0))
	def.protection = CatalogDamagePackets.from_dict(data.get("protection", {}))
	def.cargo_capacity = float(data.get("cargo_capacity", 0.0))
	def.fuel_capacity = float(data.get("fuel_capacity", 0.0))
	def.weapon_type = str(data.get("weapon_type", ""))
	def.delivery_type = str(data.get("delivery_type", ""))
	def.rate_of_fire = float(data.get("rate_of_fire", 0.0))
	def.range = float(data.get("range", 0.0))
	def.projectile_speed = float(data.get("projectile_speed", 0.0))
	def.ammunition_type = str(data.get("ammunition_type", ""))
	def.ammunition_per_shot = float(data.get("ammunition_per_shot", 0.0))
	var raw_ammunition_capacity: Variant = data.get("ammunition_capacity", {})
	if typeof(raw_ammunition_capacity) == TYPE_DICTIONARY:
		def.ammunition_capacity = raw_ammunition_capacity.duplicate()
	def.damage_packets = CatalogDamagePackets.from_dict(data.get("damage_packets", {}))
	def.shield_type = str(data.get("shield_type", ""))
	def.shield_capacity = float(data.get("shield_capacity", 0.0))
	def.regen = float(data.get("regen", 0.0))
	def.has_active = bool(data.get("has_active", false))
	def.sensor_range = float(data.get("sensor_range", 0.0))
	def.sensor_sensitivity = CatalogSignature.from_dict(data.get("sensor_sensitivity", {}))
	def.sensor_sensitivity_passive = CatalogSignature.from_dict(data.get("sensor_sensitivity_passive", {}))
	def.area_effect = bool(data.get("area_effect", false))
	def.intercept_chance = float(data.get("intercept_chance", 0.0))
	return def

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	out["id"] = id
	out["name"] = name
	out["maker"] = maker
	if _present_keys.has("brand") or brand != "":
		out["brand"] = brand
	out["category"] = category
	if _present_keys.has("mount") or mount != "":
		out["mount"] = mount
	if _present_keys.has("mounts") or not mounts.is_empty():
		out["mounts"] = mounts.duplicate()
	out["mass"] = mass
	out["volume"] = volume
	out["cost"] = cost
	out["description"] = description
	if _present_keys.has("capabilities") or not capabilities.is_empty():
		out["capabilities"] = capabilities.duplicate()
	out["signature"] = signature.to_dict()
	if _present_keys.has("engine_type") or engine_type != "":
		out["engine_type"] = engine_type
	if _present_keys.has("thrust") or thrust != 0.0:
		out["thrust"] = thrust
	if _present_keys.has("max_speed") or max_speed != 0.0:
		out["max_speed"] = max_speed
	if _present_keys.has("boost_multiplier") or boost_multiplier != 0.0:
		out["boost_multiplier"] = boost_multiplier
	if _present_keys.has("fuel_consumption") or fuel_consumption != 0.0:
		out["fuel_consumption"] = fuel_consumption
	if _present_keys.has("plant_type") or plant_type != "":
		out["plant_type"] = plant_type
	if _present_keys.has("power_generation") or power_generation != 0.0:
		out["power_generation"] = power_generation
	if _present_keys.has("power_demand") or power_demand != 0.0:
		out["power_demand"] = power_demand
	if _present_keys.has("core_type") or core_type != "":
		out["core_type"] = core_type
	if _present_keys.has("compute_capacity") or compute_capacity != 0.0:
		out["compute_capacity"] = compute_capacity
	if _present_keys.has("compute_demand") or compute_demand != 0.0:
		out["compute_demand"] = compute_demand
	if _present_keys.has("life_support_capacity") or life_support_capacity != 0.0:
		out["life_support_capacity"] = life_support_capacity
	if _present_keys.has("hits") or hits != 0.0:
		out["hits"] = hits
	if _present_keys.has("protection") or not CatalogDamagePackets.is_empty(protection):
		out["protection"] = protection.to_dict()
	if _present_keys.has("cargo_capacity") or cargo_capacity != 0.0:
		out["cargo_capacity"] = cargo_capacity
	if _present_keys.has("fuel_capacity") or fuel_capacity != 0.0:
		out["fuel_capacity"] = fuel_capacity
	if _present_keys.has("weapon_type") or weapon_type != "":
		out["weapon_type"] = weapon_type
	if _present_keys.has("delivery_type") or delivery_type != "":
		out["delivery_type"] = delivery_type
	if _present_keys.has("rate_of_fire") or rate_of_fire != 0.0:
		out["rate_of_fire"] = rate_of_fire
	if _present_keys.has("range") or range != 0.0:
		out["range"] = range
	if _present_keys.has("projectile_speed") or projectile_speed != 0.0:
		out["projectile_speed"] = projectile_speed
	if _present_keys.has("ammunition_type") or ammunition_type != "":
		out["ammunition_type"] = ammunition_type
	if _present_keys.has("ammunition_per_shot") or ammunition_per_shot != 0.0:
		out["ammunition_per_shot"] = ammunition_per_shot
	if _present_keys.has("ammunition_capacity") or not ammunition_capacity.is_empty():
		out["ammunition_capacity"] = ammunition_capacity.duplicate()
	if _present_keys.has("damage_packets") or not CatalogDamagePackets.is_empty(damage_packets):
		out["damage_packets"] = damage_packets.to_dict()
	if _present_keys.has("shield_type") or shield_type != "":
		out["shield_type"] = shield_type
	if _present_keys.has("shield_capacity") or shield_capacity != 0.0:
		out["shield_capacity"] = shield_capacity
	if _present_keys.has("regen") or regen != 0.0:
		out["regen"] = regen
	if _present_keys.has("has_active") or has_active != false:
		out["has_active"] = has_active
	if _present_keys.has("sensor_range") or sensor_range != 0.0:
		out["sensor_range"] = sensor_range
	if _present_keys.has("sensor_sensitivity") or not CatalogSignature.is_empty(sensor_sensitivity):
		out["sensor_sensitivity"] = sensor_sensitivity.to_dict()
	if _present_keys.has("sensor_sensitivity_passive") or not CatalogSignature.is_empty(sensor_sensitivity_passive):
		out["sensor_sensitivity_passive"] = sensor_sensitivity_passive.to_dict()
	if _present_keys.has("area_effect") or area_effect != false:
		out["area_effect"] = area_effect
	if _present_keys.has("intercept_chance") or intercept_chance != 0.0:
		out["intercept_chance"] = intercept_chance
	return out

static func allowed_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "maker", "brand", "category", "mount", "mounts", "mass", "volume", "cost", "description", "capabilities", "signature", "engine_type", "thrust", "max_speed", "boost_multiplier", "fuel_consumption", "plant_type", "power_generation", "power_demand", "core_type", "compute_capacity", "compute_demand", "life_support_capacity", "hits", "protection", "cargo_capacity", "fuel_capacity", "weapon_type", "delivery_type", "rate_of_fire", "range", "projectile_speed", "ammunition_type", "ammunition_per_shot", "ammunition_capacity", "damage_packets", "shield_type", "shield_capacity", "regen", "has_active", "sensor_range", "sensor_sensitivity", "sensor_sensitivity_passive", "area_effect", "intercept_chance"])

static func required_keys() -> PackedStringArray:
	return PackedStringArray(["id", "name", "maker", "category", "mass", "volume", "cost", "description", "signature"])
