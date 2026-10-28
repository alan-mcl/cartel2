class_name PlotlineSubsystem
extends SimSubsystem

## Catalog-driven background arcs: per-plotline state, flags, and hooks for messages and gigs.

const MAX_TRANSITION_CHAIN := 4

var _instances: Dictionary = {}


func _init() -> void:
	id = "plotlines"
	save_version = 1


func on_day(session: GameSession, catalog: Catalog, _day: int) -> void:
	if session == null or catalog == null:
		return
	_ensure_instances(session, catalog)
	for plotline_id_variant in _instances.keys():
		var plotline_id := str(plotline_id_variant)
		_try_transitions_for_stimulus(
			session,
			catalog,
			plotline_id,
			{"kind": "days_in_state"}
		)


func on_event(session: GameSession, catalog: Catalog, evt: Dictionary) -> void:
	if session == null or catalog == null or evt.is_empty():
		return
	_ensure_instances(session, catalog)
	var stimulus := evt.duplicate(true)
	stimulus["kind"] = "event"
	for plotline_id_variant in _instances.keys():
		var plotline_id := str(plotline_id_variant)
		_try_transitions_for_stimulus(session, catalog, plotline_id, stimulus)


func accept_gig(session: GameSession, catalog: Catalog, plotline_id: String, gig_id: String) -> bool:
	return _apply_gig_stimulus(session, catalog, plotline_id, gig_id, "gig_accepted")


func complete_gig(session: GameSession, catalog: Catalog, plotline_id: String, gig_id: String) -> bool:
	return _apply_gig_stimulus(session, catalog, plotline_id, gig_id, "gig_completed")


func contribute_messages(
	channel: String,
	session: GameSession,
	catalog: Catalog
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if session == null or catalog == null or channel.is_empty():
		return out
	_ensure_instances(session, catalog)
	for plotline_id_variant in _instances.keys():
		var plotline_id := str(plotline_id_variant)
		var def := _def_for_instance(catalog, plotline_id)
		if def.is_empty():
			continue
		var instance: Dictionary = _instances[plotline_id]
		var state_id := str(instance.get("state", ""))
		var state := _state_def(def, state_id)
		if state.is_empty():
			continue
		var flags: Dictionary = instance.get("flags", {})
		for entry_variant in state.get("messages", []):
			if typeof(entry_variant) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_variant
			if str(entry.get("channel", "")) != channel:
				continue
			var weight := float(entry.get("weight", 1.0))
			if weight <= 0.0:
				continue
			out.append({
				"text": str(entry.get("text", "")),
				"tone": str(entry.get("tone", "")),
				"weight": weight,
				"plotline_id": plotline_id,
				"extra_bindings": flags.duplicate(true),
			})
	return out


func contribute_gigs(
	desk: String,
	habitat_id: String,
	session: GameSession,
	catalog: Catalog
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if session == null or catalog == null:
		return out
	var desk_key := desk.strip_edges()
	if desk_key.is_empty():
		return out
	_ensure_instances(session, catalog)
	for plotline_id_variant in _instances.keys():
		var plotline_id := str(plotline_id_variant)
		var def := _def_for_instance(catalog, plotline_id)
		if def.is_empty():
			continue
		var instance: Dictionary = _instances[plotline_id]
		var state_id := str(instance.get("state", ""))
		var state := _state_def(def, state_id)
		if state.is_empty():
			continue
		for entry_variant in state.get("gigs", []):
			if typeof(entry_variant) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_variant
			var gig_desk := str(entry.get("desk", ""))
			if gig_desk != "any" and gig_desk != desk_key:
				continue
			if entry.has("habitats"):
				var habitats: Array = entry.get("habitats", [])
				if not habitats.has(habitat_id):
					continue
			var gig_id := str(entry.get("id", ""))
			if gig_id.is_empty():
				continue
			var record := entry.duplicate(true)
			record["source"] = "plotline"
			record["plotline_id"] = plotline_id
			record["gig_id"] = gig_id
			out.append(record)
	return out


func get_instance(plotline_id: String) -> Dictionary:
	var key := plotline_id.strip_edges()
	if key.is_empty() or not _instances.has(key):
		return {}
	return (_instances[key] as Dictionary).duplicate(true)


func to_dict() -> Dictionary:
	return {"instances": _instances.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	_instances = {}
	if typeof(data.get("instances", {})) == TYPE_DICTIONARY:
		_instances = data.get("instances", {}).duplicate(true)


func _apply_gig_stimulus(
	session: GameSession,
	catalog: Catalog,
	plotline_id: String,
	gig_id: String,
	kind: String
) -> bool:
	if session == null or catalog == null:
		return false
	var pid := plotline_id.strip_edges()
	var gid := gig_id.strip_edges()
	if pid.is_empty() or gid.is_empty():
		return false
	_ensure_instances(session, catalog)
	if not _instances.has(pid):
		return false
	var before := str(_instances[pid].get("state", ""))
	_try_transitions_for_stimulus(
		session,
		catalog,
		pid,
		{"kind": kind, "gig_id": gid}
	)
	var after := str(_instances[pid].get("state", ""))
	return before != after


func _try_transitions_for_stimulus(
	session: GameSession,
	catalog: Catalog,
	plotline_id: String,
	stimulus: Dictionary
) -> void:
	for _step in range(MAX_TRANSITION_CHAIN):
		if not _instances.has(plotline_id):
			return
		var def := _def_for_instance(catalog, plotline_id)
		if def.is_empty():
			return
		var instance: Dictionary = _instances[plotline_id]
		var state_id := str(instance.get("state", ""))
		var state := _state_def(def, state_id)
		if state.is_empty():
			return
		if bool(state.get("terminal", false)):
			return
		var transition := _first_matching_transition(
			session,
			catalog,
			plotline_id,
			instance,
			state,
			stimulus
		)
		if transition.is_empty():
			return
		_apply_transition(session, catalog, plotline_id, instance, transition)


func _first_matching_transition(
	session: GameSession,
	catalog: Catalog,
	plotline_id: String,
	instance: Dictionary,
	state: Dictionary,
	stimulus: Dictionary
) -> Dictionary:
	for entry_variant in state.get("transitions", []):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if not _transition_matches(session, catalog, plotline_id, instance, entry, stimulus):
			continue
		return entry
	return {}


func _transition_matches(
	session: GameSession,
	catalog: Catalog,
	plotline_id: String,
	instance: Dictionary,
	transition: Dictionary,
	stimulus: Dictionary
) -> bool:
	if not _require_flags_match(instance, transition):
		return false
	if not _require_plotline_match(catalog, transition):
		return false
	var when: Dictionary = transition.get("when", {})
	if typeof(when) != TYPE_DICTIONARY:
		return false
	var kind := str(when.get("kind", ""))
	var stimulus_kind := str(stimulus.get("kind", ""))
	if kind != stimulus_kind:
		return false
	match kind:
		"event":
			var event_type := str(when.get("type", ""))
			if event_type.is_empty() or event_type != str(stimulus.get("type", "")):
				return false
			for key_variant in when.keys():
				var key := str(key_variant)
				if key in ["kind", "type"]:
					continue
				if str(stimulus.get(key, "")) != str(when.get(key, "")):
					return false
			return true
		"days_in_state":
			var need_days := int(when.get("days", -1))
			if need_days < 0:
				return false
			var entered := float(instance.get("entered_gst", 0.0))
			var elapsed_days := CommodityEconomy.gst_day(session.gst_seconds) - CommodityEconomy.gst_day(
				entered
			)
			return elapsed_days >= need_days
		"gig_accepted", "gig_completed":
			return str(when.get("gig_id", "")) == str(stimulus.get("gig_id", ""))
		_:
			return false


func _require_flags_match(instance: Dictionary, transition: Dictionary) -> bool:
	if not transition.has("require_flags"):
		return true
	var required: Variant = transition.get("require_flags")
	if typeof(required) != TYPE_DICTIONARY:
		return false
	var flags: Dictionary = instance.get("flags", {})
	for key_variant in required.keys():
		var key := str(key_variant)
		if str(flags.get(key, "")) != str(required.get(key, "")):
			return false
	return true


func _require_plotline_match(catalog: Catalog, transition: Dictionary) -> bool:
	if not transition.has("require_plotline"):
		return true
	var req: Variant = transition.get("require_plotline")
	if typeof(req) != TYPE_DICTIONARY:
		return false
	var other_id := str(req.get("id", ""))
	var other_state := str(req.get("state", ""))
	if other_id.is_empty() or other_state.is_empty():
		return false
	if not _instances.has(other_id):
		return false
	var other_def := _def_for_instance(catalog, other_id)
	if other_def.is_empty():
		return false
	return str(_instances[other_id].get("state", "")) == other_state


func _apply_transition(
	session: GameSession,
	catalog: Catalog,
	plotline_id: String,
	instance: Dictionary,
	transition: Dictionary
) -> void:
	var to_state := str(transition.get("to", "")).strip_edges()
	if to_state.is_empty():
		return
	var def := _def_for_instance(catalog, plotline_id)
	if def.is_empty() or not _state_def(def, to_state):
		return
	if transition.has("set_flags"):
		var set_flags: Variant = transition.get("set_flags")
		if typeof(set_flags) == TYPE_DICTIONARY:
			var flags: Dictionary = instance.get("flags", {})
			for key_variant in set_flags.keys():
				flags[str(key_variant)] = str(set_flags[key_variant])
			instance["flags"] = flags
	instance["state"] = to_state
	instance["entered_gst"] = session.gst_seconds
	_instances[plotline_id] = instance


func _ensure_instances(session: GameSession, catalog: Catalog) -> void:
	for def_variant in catalog.list_plotlines():
		if typeof(def_variant) != TYPE_DICTIONARY:
			continue
		var def: Dictionary = def_variant
		var plotline_id := str(def.get("id", "")).strip_edges()
		if plotline_id.is_empty():
			continue
		if not _instances.has(plotline_id):
			_instances[plotline_id] = _fresh_instance(session, def)
			continue
		_reconcile_instance(session, catalog, plotline_id, def)


func _reconcile_instance(
	session: GameSession,
	catalog: Catalog,
	plotline_id: String,
	def: Dictionary
) -> void:
	var instance: Dictionary = _instances[plotline_id]
	var state_id := str(instance.get("state", ""))
	if _state_def(def, state_id).is_empty():
		_instances[plotline_id] = _fresh_instance(session, def)


func _fresh_instance(session: GameSession, def: Dictionary) -> Dictionary:
	return {
		"state": str(def.get("initial", "")),
		"entered_gst": session.gst_seconds if session != null else 0.0,
		"flags": {},
	}


func _def_for_instance(catalog: Catalog, plotline_id: String) -> Dictionary:
	if catalog.plotlines_by_id.has(plotline_id):
		return catalog.plotlines_by_id[plotline_id]
	return {}


func _state_def(def: Dictionary, state_id: String) -> Dictionary:
	var states: Variant = def.get("states", {})
	if typeof(states) != TYPE_DICTIONARY:
		return {}
	var state: Variant = states.get(state_id, null)
	if typeof(state) != TYPE_DICTIONARY:
		return {}
	return state
