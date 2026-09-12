class_name Wallet
extends RefCounted

var credits: int = 3000


func apply(delta: int) -> void:
	credits += delta


func can_afford(cost: int) -> bool:
	return credits >= cost


func try_spend(cost: int) -> bool:
	if not can_afford(cost):
		return false
	credits -= cost
	return true


func to_session_dict() -> Dictionary:
	return {"credits": credits}


func load_session_dict(data: Dictionary) -> void:
	credits = int(data.get("credits", 0))
