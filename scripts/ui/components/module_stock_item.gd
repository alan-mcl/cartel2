class_name ModuleStockItem
extends PanelContainer

signal stock_selected(module_id: String)
signal stock_drag_started(module_id: String)
signal module_dropped_on_stock(data: Dictionary)

var module_id: String = ""
var spare_count: int = 0
var selected: bool = false

@onready var _label: Label = $HBox/NameLabel
@onready var _meta: Label = $HBox/MetaLabel


func configure(p_module_id: String, name_text: String, cost: int, spare: int, is_selected: bool) -> void:
	module_id = p_module_id
	spare_count = spare
	selected = is_selected
	if is_node_ready():
		_apply_labels(name_text, cost, spare, is_selected)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)


func _apply_labels(name_text: String, cost: int, spare: int, is_selected: bool) -> void:
	if _label:
		var prefix := "> " if is_selected else ""
		_label.text = "%s%s" % [prefix, name_text]
	if _meta:
		_meta.text = "d%d · x%d" % [cost, spare]
	if is_selected:
		theme_type_variation = &"Elevated"
	else:
		theme_type_variation = &"Surface"


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		stock_selected.emit(module_id)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if module_id.is_empty() or spare_count <= 0:
		return null
	var preview := Label.new()
	preview.text = _label.text if _label else module_id
	set_drag_preview(preview)
	stock_drag_started.emit(module_id)
	return {
		"type": "stock",
		"module_id": module_id,
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	return str(data.get("type", "")) == "slot"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	if str(data.get("type", "")) == "slot":
		module_dropped_on_stock.emit(data)
