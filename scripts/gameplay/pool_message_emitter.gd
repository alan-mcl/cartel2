class_name PoolMessageEmitter
extends MessageEmitter

var _def: Dictionary = {}


func _init(def: Dictionary) -> void:
	_def = def.duplicate(true)
	emitter_id = str(_def.get("id", ""))


func weight(_channel: String, _session: GameSession, _catalog: Catalog) -> float:
	return maxf(0.0, float(_def.get("weight", 0.0)))


func has_templates_for_channel(channel: String) -> bool:
	for entry_variant in _def.get("templates", []):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		if str(entry_variant.get("channel", "")) == channel:
			return true
	return false


func sample(
	channel: String,
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator,
	simulation: Simulation = null
) -> Dictionary:
	var templates: Array = _def.get("templates", [])
	return _sample_from_templates(channel, templates, session, catalog, rng)
