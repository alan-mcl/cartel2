class_name MessageSubsystem
extends SimSubsystem

const MAX_SAMPLE_ATTEMPTS := 24

var _push_queues: Dictionary = {}
var _last_line_by_channel: Dictionary = {}
var _headlines_sector_id: String = ""


func _init() -> void:
	id = "messages"


func clear_channel(channel: String) -> void:
	_push_queues[channel] = []
	_last_line_by_channel[channel] = ""


func note_headlines_sector(sector_id: String) -> bool:
	var sector := sector_id.strip_edges()
	if sector.is_empty():
		return false
	if sector == _headlines_sector_id:
		return false
	_headlines_sector_id = sector
	clear_channel(MessageChannels.HEADLINES)
	return true


func push(channel: String, text: String, tone: String = "") -> void:
	var line := text.strip_edges()
	if line.is_empty():
		return
	if not _push_queues.has(channel):
		_push_queues[channel] = []
	var queue: Array = _push_queues[channel]
	queue.append({
		"text": line,
		"tone": tone,
		"emitter_id": "push",
	})


func next_line(
	channel: String,
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator,
	simulation: Simulation = null
) -> Dictionary:
	if session == null or catalog == null or rng == null:
		return {}
	if channel == MessageChannels.HEADLINES:
		note_headlines_sector(session.sector_id)

	var pushed := _dequeue_push(channel)
	if not pushed.is_empty():
		_remember_line(channel, str(pushed.get("text", "")))
		return pushed

	for _attempt in range(MAX_SAMPLE_ATTEMPTS):
		var picked := _pick_weighted(channel, session, catalog, rng, simulation)
		if picked.is_empty():
			break
		var sample: Dictionary
		if str(picked.get("source", "")) == "plotline":
			sample = _sample_plotline(picked, session, catalog, rng)
		else:
			var emitter := picked.get("emitter") as MessageEmitter
			if emitter == null:
				continue
			sample = emitter.sample(channel, session, catalog, rng, simulation)
		var text := str(sample.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		if text == str(_last_line_by_channel.get(channel, "")):
			continue
		_remember_line(channel, text)
		return sample
	return {}


func _dequeue_push(channel: String) -> Dictionary:
	if not _push_queues.has(channel):
		return {}
	var queue: Array = _push_queues[channel]
	if queue.is_empty():
		return {}
	var sample: Dictionary = queue.pop_front()
	return sample.duplicate(true)


func _remember_line(channel: String, text: String) -> void:
	_last_line_by_channel[channel] = text


func _pick_weighted(
	channel: String,
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator,
	simulation: Simulation = null
) -> Dictionary:
	var emitters := _build_emitters(catalog)
	var total := 0.0
	var weighted: Array[Dictionary] = []
	for emitter in emitters:
		if not emitter.has_templates_for_channel(channel):
			continue
		var w := emitter.weight(channel, session, catalog)
		if w <= 0.0:
			continue
		total += w
		weighted.append({"source": "emitter", "emitter": emitter, "weight": w})

	var plotlines := _plotline_subsystem(simulation, session)
	if plotlines != null:
		for entry in plotlines.contribute_messages(channel, session, catalog):
			var plot_weight := float(entry.get("weight", 1.0))
			if plot_weight <= 0.0:
				continue
			total += plot_weight
			weighted.append({"source": "plotline", "entry": entry, "weight": plot_weight})

	if weighted.is_empty() or total <= 0.0:
		return {}

	var roll := rng.randf() * total
	var cumulative := 0.0
	for entry in weighted:
		cumulative += float(entry.get("weight", 0.0))
		if roll <= cumulative:
			return entry
	return weighted[weighted.size() - 1]


func _plotline_subsystem(simulation: Simulation, session: GameSession) -> PlotlineSubsystem:
	if simulation != null and simulation.has_subsystem("plotlines"):
		return simulation.get_subsystem("plotlines") as PlotlineSubsystem
	if session != null and session.bound_plotlines != null:
		return session.bound_plotlines
	return null


func _sample_plotline(
	picked: Dictionary,
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator
) -> Dictionary:
	var entry: Dictionary = picked.get("entry", {})
	var template := str(entry.get("text", "")).strip_edges()
	if template.is_empty():
		return {}
	var bindings := MessageEmitterTokens.build_sector_bindings(session, catalog, rng)
	var extra: Variant = entry.get("extra_bindings", {})
	if typeof(extra) == TYPE_DICTIONARY:
		for key_variant in extra.keys():
			bindings[key_variant] = extra[key_variant]
	for _attempt in range(12):
		var text := MessageEmitterTokens.apply_template(template, bindings, rng)
		if MessageEmitterTokens.has_placeholders(text):
			continue
		var plotline_id := str(entry.get("plotline_id", ""))
		return {
			"text": text,
			"tone": str(entry.get("tone", "")),
			"emitter_id": "plotline:%s" % plotline_id if not plotline_id.is_empty() else "plotline",
		}
	return {}


static func _build_emitters(catalog: Catalog) -> Array[MessageEmitter]:
	var built: Array[MessageEmitter] = []
	for def_variant in catalog.list_message_emitters():
		if typeof(def_variant) != TYPE_DICTIONARY:
			continue
		var def: Dictionary = def_variant
		var emitter_id := str(def.get("id", ""))
		if emitter_id.is_empty():
			continue
		var emitter: MessageEmitter
		if emitter_id == "commodities":
			emitter = CommodityMessageEmitter.new(def)
		elif emitter_id == "charters":
			emitter = CharterMessageEmitter.new(def)
		else:
			emitter = PoolMessageEmitter.new(def)
		built.append(emitter)
	return built
