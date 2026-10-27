class_name CommodityMessageEmitter
extends PoolMessageEmitter


func sample(
	channel: String,
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator,
	_simulation: Simulation = null
) -> Dictionary:
	var bindings := MessageEmitterTokens.build_sector_bindings(session, catalog, rng)
	if not bindings.has("price"):
		return _empty_sample()
	var templates: Array = _def.get("templates", [])
	return _sample_from_templates(channel, templates, session, catalog, rng, bindings)
