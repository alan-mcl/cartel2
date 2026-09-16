class_name MissionSubsystem
extends SimSubsystem

## Development-only delivery spike: buy food in Proxima, sell in Bela.
##
## Production Simulation deliberately does not register this subsystem. Tests or
## a future mission vertical slice must opt in explicitly; this prevents a
## hardcoded auto-accepted mission becoming default new-game content.

const MISSION_ID := "spike_food_run"
const PICKUP_SECTOR_ID := "proxima"
const DESTINATION_SECTOR_ID := "bela"
const COMMODITY_ID := "food_products"
const PICKUP_QUANTITY := 1
const REWARD_CREDITS := 500

const STATUS_OFFERED := "offered"
const STATUS_ACCEPTED := "accepted"
const STATUS_COMPLETE := "complete"

var status: String = STATUS_OFFERED
var picked_up: bool = false
var arrived: bool = false


func _init() -> void:
	id = "missions"
	save_version = 1


func accept(session: GameSession) -> bool:
	if session == null or status != STATUS_OFFERED:
		return false
	status = STATUS_ACCEPTED
	session.last_log = "Delivery accepted: buy %d x food products in Proxima, sell in Bela." % PICKUP_QUANTITY
	session.changed.emit()
	return true


func on_event(session: GameSession, _catalog: Catalog, evt: Dictionary) -> void:
	if session == null or evt.is_empty() or status == STATUS_COMPLETE:
		return
	if status != STATUS_ACCEPTED:
		return

	var event_type := str(evt.get("type", ""))
	if event_type == SimEvent.COMMODITY_TRADED:
		_handle_commodity_traded(session, evt)
	elif event_type == SimEvent.SECTOR_ENTERED:
		_handle_sector_entered(session, evt)


func to_dict() -> Dictionary:
	return {
		"mission_id": MISSION_ID,
		"status": status,
		"picked_up": picked_up,
		"arrived": arrived,
	}


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		status = STATUS_OFFERED
		picked_up = false
		arrived = false
		return
	status = str(data.get("status", STATUS_OFFERED))
	picked_up = bool(data.get("picked_up", false))
	arrived = bool(data.get("arrived", false))


func _handle_sector_entered(session: GameSession, evt: Dictionary) -> void:
	if str(evt.get("sector_id", "")) != DESTINATION_SECTOR_ID or arrived:
		return

	arrived = true
	session.last_log = "Arrived in Bela. Sell the food products at the Exchange to complete the delivery."
	session.changed.emit()


func _handle_commodity_traded(session: GameSession, evt: Dictionary) -> void:
	var sector_id := str(evt.get("sector_id", ""))
	var commodity_id := str(evt.get("commodity_id", ""))
	var side := str(evt.get("side", ""))
	var quantity := int(evt.get("quantity", 0))

	if commodity_id != COMMODITY_ID or quantity < PICKUP_QUANTITY:
		return

	if side == "buy":
		_handle_pickup(session, sector_id)
	elif side == "sell":
		_handle_delivery(session, sector_id)


func _handle_pickup(session: GameSession, sector_id: String) -> void:
	if sector_id != PICKUP_SECTOR_ID or picked_up:
		return

	picked_up = true
	session.last_log = "Cargo picked up. Deliver the food products to Bela Exchange."
	session.changed.emit()


func _handle_delivery(session: GameSession, sector_id: String) -> void:
	if sector_id != DESTINATION_SECTOR_ID or not picked_up or not arrived:
		return

	status = STATUS_COMPLETE
	session.add_credits(REWARD_CREDITS)
	session.last_log = "Delivery complete. +d%d bonus credited." % REWARD_CREDITS
