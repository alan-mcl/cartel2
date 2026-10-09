class_name CharterMessageEmitter
extends PoolMessageEmitter


func sample(
	channel: String,
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator,
	simulation: Simulation = null
) -> Dictionary:
	if channel != MessageChannels.GOSSIP or simulation == null or session == null or catalog == null:
		return _empty_sample()

	var habitat_id := str(session.habitat_id).strip_edges()
	if habitat_id.is_empty():
		return _empty_sample()

	var missions := simulation.get_subsystem("missions") as MissionSubsystem
	if missions == null:
		return _empty_sample()

	missions.ensure_boards(session, catalog)
	var entries := _collect_offer_entries(missions, habitat_id)
	if entries.is_empty():
		return _empty_sample()

	var entry: Dictionary = entries[rng.randi_range(0, entries.size() - 1)]
	var extra_bindings := _bindings_for_entry(entry)
	if str(extra_bindings.get("destination", "")).is_empty():
		return _empty_sample()

	var templates: Array = _def.get("templates", [])
	return _sample_from_templates(channel, templates, session, catalog, rng, extra_bindings)


static func _collect_offer_entries(missions: MissionSubsystem, habitat_id: String) -> Array:
	var entries: Array = []
	for offer_variant in missions.list_offers(habitat_id, PassengerCharters.BOARD_BAR):
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		entries.append({"offer": offer_variant, "desk": "bar", "kind": "passenger"})
	for offer_variant in missions.list_offers(habitat_id, PassengerCharters.BOARD_TERMINAL):
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		entries.append({"offer": offer_variant, "desk": "terminal", "kind": "passenger"})
	for offer_variant in missions.list_freight_offers(habitat_id):
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		entries.append({"offer": offer_variant, "desk": "terminal", "kind": "freight"})
	return entries


static func _bindings_for_entry(entry: Dictionary) -> Dictionary:
	var offer: Dictionary = entry.get("offer", {})
	var kind := str(entry.get("kind", ""))
	var label := ""
	if kind == "freight":
		label = str(offer.get("cargo_title", "")).strip_edges()
	else:
		label = str(offer.get("role_title", "")).strip_edges()
	return {
		"destination": str(offer.get("destination_name", "")).strip_edges(),
		"quantity": str(int(offer.get("quantity", 0))),
		"label": label,
		"desk": str(entry.get("desk", "")).strip_edges(),
	}
