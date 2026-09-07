extends CanvasLayer

signal jump_requested(target_sector_id: String, n: int)
signal cancelled

@onready var _title: Label = $Background/Center/Panel/VBox/TitleLabel
@onready var _description: Label = $Background/Center/Panel/VBox/DescriptionLabel
@onready var _route_list: VBoxContainer = $Background/Center/Panel/VBox/RouteList
@onready var _solution_label: Label = $Background/Center/Panel/VBox/SolutionLabel
@onready var _confirm_button: Button = $Background/Center/Panel/VBox/ConfirmButton
@onready var _cancel_button: Button = $Background/Center/Panel/VBox/CancelButton
@onready var _hint: Label = $Background/Center/Panel/VBox/HintLabel

var _catalog: Catalog
var _session: GameSession
var _gate_title: String = ""
var _selected_target_id: String = ""
var _selected_n: int = 4
var _selected_solution: int = 0
var _selected_label: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)


func bind(catalog: Catalog, session: GameSession) -> void:
	_catalog = catalog
	_session = session


func open(gate_title: String) -> void:
	_gate_title = gate_title
	_selected_target_id = ""
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_selected_target_id = ""


func _refresh() -> void:
	_title.text = _gate_title
	_description.text = "Select a destination, then confirm translation depth."

	_clear_container(_route_list)

	if _catalog == null or _session == null:
		return

	var sector := _catalog.get_sector(_session.sector_id)
	var mappings: Variant = sector.get("mappings", [])
	if typeof(mappings) != TYPE_ARRAY:
		return

	for mapping_variant in mappings:
		if typeof(mapping_variant) != TYPE_DICTIONARY:
			continue

		var mapping: Dictionary = mapping_variant
		var target_id := str(mapping.get("target", ""))
		if target_id.is_empty():
			continue

		var target_sector := _catalog.get_sector(target_id)
		var label := str(mapping.get("label", target_sector.get("name", target_id)))

		var button := Button.new()
		var prefix := "> " if target_id == _selected_target_id else ""
		button.text = "%s%s" % [prefix, label]
		button.pressed.connect(_on_route_pressed.bind(mapping))
		_route_list.add_child(button)

	_update_selection_ui()
	_hint.text = "Esc or Cancel to stay in orbit"


func _on_route_pressed(mapping: Dictionary) -> void:
	_selected_target_id = str(mapping.get("target", ""))
	_selected_n = int(mapping.get("n", 4))
	_selected_solution = int(mapping.get("solution", 0))
	_selected_label = str(mapping.get("label", _selected_target_id))
	_refresh()


func _update_selection_ui() -> void:
	if _selected_target_id.is_empty():
		_solution_label.text = "No destination selected."
		_confirm_button.disabled = true
		return

	_solution_label.text = (
		"Route: %s via %d-space (known solution %d). Shallow transit — slower, safer."
		% [_selected_label, _selected_n, _selected_solution]
	)
	var mapping := _catalog.get_mapping(_session.sector_id, _selected_target_id, _selected_n)
	var entry_seconds := float(mapping.get("entry_seconds", 0.0))
	var exit_seconds := float(mapping.get("exit_seconds", 0.0))
	if entry_seconds > 0.0 or exit_seconds > 0.0:
		_solution_label.text += (
			" Nominal translation lag: %s entry, %s exit GST."
			% [
				GalacticCalendar.format_duration(entry_seconds),
				GalacticCalendar.format_duration(exit_seconds),
			]
		)
	_confirm_button.disabled = false
	_confirm_button.text = "Translate via %d-space" % _selected_n


func _on_confirm_pressed() -> void:
	if _selected_target_id.is_empty():
		return
	jump_requested.emit(_selected_target_id, _selected_n)


func _on_cancel_pressed() -> void:
	close()
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
