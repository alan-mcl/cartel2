## Generated — do not edit. Run scripts/tools/generate_catalog_records.py.

class_name EconomyDef
extends RefCounted

var _present_keys: Dictionary = {}

var id: String = ""
var tier: String = ""
var wealth: float = 0
var produce: Dictionary = {}
var consume: Dictionary = {}

static func from_dict(data: Dictionary) -> EconomyDef:
	var def := EconomyDef.new()
	for key in data.keys():
		def._present_keys[str(key)] = true
	def.id = str(data.get("id", ""))
	def.tier = str(data.get("tier", ""))
	def.wealth = float(data.get("wealth", 0))
	var raw_produce: Variant = data.get("produce", {})
	if typeof(raw_produce) == TYPE_DICTIONARY:
		def.produce = raw_produce.duplicate()
	var raw_consume: Variant = data.get("consume", {})
	if typeof(raw_consume) == TYPE_DICTIONARY:
		def.consume = raw_consume.duplicate()
	return def

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	out["id"] = id
	out["tier"] = tier
	out["wealth"] = wealth
	out["produce"] = produce.duplicate()
	out["consume"] = consume.duplicate()
	return out

static func allowed_keys() -> PackedStringArray:
	return PackedStringArray(["id", "tier", "wealth", "produce", "consume"])

static func required_keys() -> PackedStringArray:
	return PackedStringArray(["id", "tier", "wealth", "produce", "consume"])

func has_source_key(key: String) -> bool:
	return _present_keys.has(key)
