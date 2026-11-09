class_name TranslationSolutionChits
extends RefCounted

## Charter tiles for a daily translation-solution board.


static func for_board(
	session: GameSession,
	catalog: Catalog,
	market: TranslationMarket,
	building_id: String
) -> Array:
	if session == null or catalog == null or market == null or building_id.is_empty():
		return []
	var out: Array = []
	for offer_variant in market.visible_offers(session, catalog, building_id):
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = offer_variant
		out.append(CharterChit.from_entry(
			offer,
			func(entry: Dictionary, _ship_id: String) -> Dictionary:
				return _describe(entry, session, catalog),
			func(entry: Dictionary, _ship_id: String) -> bool:
				return _buy(entry, session, catalog, market)
		))
	return out


static func _describe(offer: Dictionary, session: GameSession, catalog: Catalog) -> Dictionary:
	var source := str(offer.get("source", ""))
	var target := str(offer.get("target", ""))
	var n := int(offer.get("n", 4))
	var solution := int(offer.get("solution", 0))
	var price := int(offer.get("price", 0))
	var origin := TranslationNav.destination_display_label(catalog, source)
	var destination := TranslationNav.destination_display_label(catalog, target)
	var can_buy := session != null and session.wallet != null and session.wallet.can_afford(price)
	return {
		"title": destination,
		"lines": [
			"From %s" % origin,
			"%d-space · solution %d" % [n, solution],
		],
		"body": "Private translation. Fly it from the origin.",
		"button_text": "Buy (d%d)" % price,
		"button_enabled": can_buy,
		"tooltip": "Private %d-space solution %d from %s to %s. Accuracy follows the ship's navigation computer." % [
			n, solution, origin, destination
		],
	}


static func _buy(
	offer: Dictionary,
	session: GameSession,
	catalog: Catalog,
	market: TranslationMarket
) -> bool:
	var result := market.buy_offer(
		session,
		catalog,
		str(offer.get("building_id", "")),
		str(offer.get("id", ""))
	)
	return bool(result.get("ok", false)) or str(result.get("reason", "")) == "already_known"
