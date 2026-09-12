class_name EconomySubsystem
extends SimSubsystem


func _init() -> void:
	id = "economy"


func on_day(session: GameSession, catalog: Catalog, _day: int) -> void:
	CommodityEconomy.ensure_quotes(session, catalog)
