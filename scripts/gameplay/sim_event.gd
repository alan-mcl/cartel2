class_name SimEvent
extends RefCounted

## Typed gameplay event vocabulary. Each factory returns a Dictionary with a `type` key.

const SECTOR_ENTERED := "sector_entered"
const DOCKED := "docked"
const UNDOCKED := "undocked"
const COMMODITY_TRADED := "commodity_traded"
const SHIP_PURCHASED := "ship_purchased"
const MODULE_INSTALLED := "module_installed"
const CREDITS_CHANGED := "credits_changed"
const SHIP_DESTROYED := "ship_destroyed"
const SALVAGE_TAKEN := "salvage_taken"


static func make(type: String, payload: Dictionary = {}) -> Dictionary:
	var evt := payload.duplicate(true)
	evt["type"] = type
	return evt


static func sector_entered(sector_id: String) -> Dictionary:
	return make(SECTOR_ENTERED, {"sector_id": sector_id})


static func docked(habitat_id: String) -> Dictionary:
	return make(DOCKED, {"habitat_id": habitat_id})


static func undocked(ship_id: String, sector_id: String) -> Dictionary:
	return make(UNDOCKED, {"ship_id": ship_id, "sector_id": sector_id})


static func commodity_traded(
	sector_id: String,
	commodity_id: String,
	quantity: int,
	unit_price: int,
	side: String
) -> Dictionary:
	return make(COMMODITY_TRADED, {
		"sector_id": sector_id,
		"commodity_id": commodity_id,
		"quantity": quantity,
		"unit_price": unit_price,
		"side": side,
	})


static func ship_purchased(ship_id: String, kind: String, cost: int) -> Dictionary:
	return make(SHIP_PURCHASED, {
		"ship_id": ship_id,
		"kind": kind,
		"cost": cost,
	})


static func module_installed(ship_id: String, slot: String, module_id: String) -> Dictionary:
	return make(MODULE_INSTALLED, {
		"ship_id": ship_id,
		"slot": slot,
		"module_id": module_id,
	})


static func credits_changed(delta: int, credits: int) -> Dictionary:
	return make(CREDITS_CHANGED, {
		"delta": delta,
		"credits": credits,
	})


static func ship_destroyed(ship_id: String) -> Dictionary:
	return make(SHIP_DESTROYED, {"ship_id": ship_id})


static func salvage_taken(interactable_id: String, reward: int) -> Dictionary:
	return make(SALVAGE_TAKEN, {
		"interactable_id": interactable_id,
		"reward": reward,
	})
