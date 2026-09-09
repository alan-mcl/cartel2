class_name ModuleStockItem
extends PanelContainer

signal stock_selected(module_id: String)
signal stock_drag_started(module_id: String)
signal module_dropped_on_stock(data: Dictionary)

var module_id: String = ""
var spare_count: int = 0
var selected: bool = false
var sandbox_mode: bool = false
var category_text: String = ""
var _name_text: String = ""
var _cost: int = 0
var _meta_detail: String = ""

@onready var _label: Label = $HBox/NameLabel
@onready var _meta: Label = $HBox/MetaLabel


func configure(
	p_module_id: String,
	name_text: String,
	cost: int,
	spare: int,
	is_selected: bool,
	sandbox: bool = false,
	category: String = "",
	meta_detail: String = "",
	tooltip: String = ""
) -> void:
	module_id = p_module_id
	spare_count = spare
	selected = is_selected
	sandbox_mode = sandbox
	category_text = category
	_name_text = name_text
	_cost = cost
	_meta_detail = meta_detail
	tooltip_text = tooltip
	_apply_labels_if_ready()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_apply_labels_if_ready()


func _apply_labels_if_ready() -> void:
	if is_node_ready() and not module_id.is_empty():
		_apply_labels(_name_text, _cost, spare_count, selected)


func set_selected_state(is_selected: bool) -> void:
	selected = is_selected
	_apply_labels_if_ready()


func _apply_labels(name_text: String, cost: int, spare: int, is_selected: bool) -> void:
	if _label:
		var prefix := "> " if is_selected else ""
		_label.text = "%s%s" % [prefix, name_text]
	if _meta:
		if sandbox_mode:
			var meta := category_text if not category_text.is_empty() else "module"
			if not _meta_detail.is_empty():
				meta = "%s · %s" % [meta, _meta_detail]
			_meta.text = meta.capitalize()
		else:
			var meta := "d%d · x%d" % [cost, spare]
			if not _meta_detail.is_empty():
				meta = "%s · %s" % [_meta_detail, meta]
			_meta.text = meta
	if is_selected:
		theme_type_variation = &"Elevated"
	else:
		theme_type_variation = &"Surface"


func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		stock_selected.emit(module_id)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if module_id.is_empty():
		return null
	if not sandbox_mode and spare_count <= 0:
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
