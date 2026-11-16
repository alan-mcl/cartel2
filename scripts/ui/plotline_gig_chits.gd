class_name PlotlineGigChits
extends RefCounted

## Bar desk tiles for catalog plotline gigs (accept and complete actions).


static func chits(
	gigs: Array,
	session: GameSession,
	catalog: Catalog
) -> Array:
	var out: Array = []
	if session == null or catalog == null:
		return out
	var accept_act := _accept_callable(session, catalog)
	var complete_act := _complete_callable(session, catalog)
	for gig_variant in gigs:
		if typeof(gig_variant) != TYPE_DICTIONARY:
			continue
		var gig: Dictionary = gig_variant
		var plotline_id := str(gig.get("plotline_id", ""))
		var gig_id := str(gig.get("gig_id", ""))
		if plotline_id.is_empty() or gig_id.is_empty():
			continue
		out.append(CharterChit.from_entry(gig, Callable(PlotlineGigChits, "_describe_accept"), accept_act))
		out.append(CharterChit.from_entry(gig, Callable(PlotlineGigChits, "_describe_complete"), complete_act))
	return out


static func _accept_callable(session: GameSession, catalog: Catalog) -> Callable:
	return func(entry: Dictionary, _ship_id: String) -> bool:
		return _act_accept(entry, session, catalog)


static func _complete_callable(session: GameSession, catalog: Catalog) -> Callable:
	return func(entry: Dictionary, _ship_id: String) -> bool:
		return _act_complete(entry, session, catalog)


static func _describe_accept(entry: Dictionary, _ship_id: String) -> Dictionary:
	return _describe_gig(entry, "Accept")


static func _describe_complete(entry: Dictionary, _ship_id: String) -> Dictionary:
	return _describe_gig(entry, "Complete")


static func _describe_gig(entry: Dictionary, button_text: String) -> Dictionary:
	return {
		"title": str(entry.get("title", "Plot gig")),
		"body": str(entry.get("text", "")),
		"button_text": button_text,
	}


static func _plotlines(session: GameSession) -> PlotlineSubsystem:
	if session == null:
		return null
	return session.bound_plotlines


static func _act_accept(entry: Dictionary, session: GameSession, catalog: Catalog) -> bool:
	var plotlines := _plotlines(session)
	if plotlines == null:
		return false
	return plotlines.accept_gig(
		session,
		catalog,
		str(entry.get("plotline_id", "")),
		str(entry.get("gig_id", ""))
	)


static func _act_complete(entry: Dictionary, session: GameSession, catalog: Catalog) -> bool:
	var plotlines := _plotlines(session)
	if plotlines == null:
		return false
	return plotlines.complete_gig(
		session,
		catalog,
		str(entry.get("plotline_id", "")),
		str(entry.get("gig_id", ""))
	)