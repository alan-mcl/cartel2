class_name MenuHeadlineTape
extends RefCounted

const TOP_UP_MAX_TRIES := 12


static func next_headline(
	messages: MessageSubsystem,
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator
) -> String:
	if messages == null or session == null or catalog == null or rng == null:
		return ""
	MessageEmitterTokens.assign_random_planetary_hub(session, catalog, rng)
	CommodityEconomy.ensure_quotes(session, catalog)
	var sample := messages.next_line(MessageChannels.HEADLINES, session, catalog, rng, null)
	return str(sample.get("text", "")).strip_edges()


static func hall_line_for_rank(rank: int, entries: Array) -> String:
	if rank < 1 or entries.size() < rank:
		return ""
	var entry_variant = entries[rank - 1]
	if typeof(entry_variant) != TYPE_DICTIONARY:
		return ""
	var entry: Dictionary = entry_variant
	var callsign := str(entry.get("callsign", "")).strip_edges()
	if callsign.is_empty():
		callsign = "Unknown"
	var profit := int(entry.get("profit", 0))
	return "Hall of fame #%d: %s, d%d nett profit." % [rank, callsign, profit]


static func next_menu_line(
	index_after_version: int,
	entries: Array,
	messages: MessageSubsystem,
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator
) -> String:
	var rank := 0
	match index_after_version:
		1:
			rank = 1
		3:
			rank = 2
		5:
			rank = 3
	if rank > 0:
		var hall := hall_line_for_rank(rank, entries)
		if not hall.is_empty():
			return hall
	return next_headline(messages, session, catalog, rng)
