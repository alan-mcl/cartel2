class_name ModuleSlot
extends PanelContainer

signal slot_clicked(slot_id: String)
signal module_dropped(slot_id: String, data: Dictionary)

var slot_id: String = ""
var module_id: String = ""
var module_name: String = ""
var ship_id: String = ""
var compatible_module_id: String = ""
var drop_validator: Callable = Callable()
var _click_pending := false

@onready var _slot_label: Label = $HBox/SlotLabel
@onready var _module_label: Label = $HBox/ModuleLabel


func configure(
	p_slot_id: String,
	p_module_id: String,
	p_module_name: String,
	p_ship_id: String,
	p_compatible_module_id: String = "",
	p_drop_validator: Callable = Callable()
) -> void:
	slot_id = p_slot_id
	module_id = p_module_id
	module_name = p_module_name
	ship_id = p_ship_id
	compatible_module_id = p_compatible_module_id
	drop_validator = p_drop_validator
	if is_node_ready():
		_apply_labels()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	if not slot_id.is_empty():
		_apply_labels()


func _apply_labels() -> void:
	if _slot_label:
		_slot_label.text = slot_id
	if _module_label:
		_module_label.text = module_name if not module_name.is_empty() else "(empty)"


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if module_id.is_empty():
				slot_clicked.emit(slot_id)
			else:
				_click_pending = true
		elif _click_pending:
			_click_pending = false
			slot_clicked.emit(slot_id)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if module_id.is_empty():
		return null
	_click_pending = false
	var preview := Label.new()
	preview.text = module_name
	set_drag_preview(preview)
	return {
		"type": "slot",
		"slot": slot_id,
		"module_id": module_id,
		"ship_id": ship_id,
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	return _accepts_drop(data)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	if _accepts_drop(data):
		module_dropped.emit(slot_id, data)


func _accepts_drop(data: Dictionary) -> bool:
	if drop_validator.is_valid():
		return bool(drop_validator.call(slot_id, data))

	var drag_type := str(data.get("type", ""))
	if drag_type == "stock":
		var part_id := str(data.get("module_id", ""))
		if part_id.is_empty():
			return false
		if not compatible_module_id.is_empty():
			return part_id == compatible_module_id
		return true
	if drag_type == "slot":
		var from_slot := str(data.get("slot", ""))
		var from_ship := str(data.get("ship_id", ""))
		if from_slot.is_empty() or from_slot == slot_id:
			return false
		return from_ship == ship_id or ship_id.is_empty()
	return false
