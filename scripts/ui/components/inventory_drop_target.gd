extends Control

signal module_dropped(data: Dictionary)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return _accepts_slot_drop(data)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _accepts_slot_drop(data):
		module_dropped.emit(data)


func _accepts_slot_drop(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if str(data.get("type", "")) != "slot":
		return false
	return not str(data.get("module_id", "")).is_empty()
