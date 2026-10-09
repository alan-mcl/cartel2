class_name MessageEmitter
extends RefCounted

var emitter_id: String = ""


func weight(_channel: String, _session: GameSession, _catalog: Catalog) -> float:
	return 0.0


func has_templates_for_channel(channel: String) -> bool:
	return false


func sample(
	_channel: String,
	_session: GameSession,
	_catalog: Catalog,
	_rng: RandomNumberGenerator,
	_simulation: Simulation = null
) -> Dictionary:
	return {}


func _empty_sample() -> Dictionary:
	return {"text": "", "tone": "", "emitter_id": emitter_id}


func _sample_from_templates(
	channel: String,
	templates: Array,
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator,
	extra_bindings: Dictionary = {}
) -> Dictionary:
	var pool: Array[Dictionary] = []
	for entry_variant in templates:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("channel", "")) != channel:
			continue
		pool.append(entry)
	if pool.is_empty():
		return _empty_sample()

	var bindings := MessageEmitterTokens.build_sector_bindings(session, catalog, rng)
	for key_variant in extra_bindings.keys():
		bindings[key_variant] = extra_bindings[key_variant]

	for _attempt in range(12):
		var pick: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		var template := str(pick.get("text", "")).strip_edges()
		if template.is_empty():
			continue
		var text := MessageEmitterTokens.apply_template(template, bindings)
		if MessageEmitterTokens.has_placeholders(text):
			continue
		return {
			"text": text,
			"tone": str(pick.get("tone", "")),
			"emitter_id": emitter_id,
		}
	return _empty_sample()
