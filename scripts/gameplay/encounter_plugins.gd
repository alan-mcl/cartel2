class_name EncounterPlugins
extends RefCounted

## Optional encounter resolvers keyed by catalog `plugin` id. Validator allow-list only.

const REGISTERED_PLUGIN_IDS: Array[String] = []


static func apply(_plugin_id: String, _session: GameSession, _catalog: Catalog, _rng: RandomNumberGenerator) -> Array:
	return []
