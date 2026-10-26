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
