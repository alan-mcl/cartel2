extends CanvasLayer

signal jump_requested(target_sector_id: String)
signal cancelled

@onready var _title: Label = $Dim/Center/Panel/TitleLabel
@onready var _description: Label = $Dim/Center/Panel/DescriptionLabel
@onready var _route_list: VBoxContainer = $Dim/Center/Panel/RouteList
@onready var _cancel_button: Button = $Dim/Center/Panel/CancelButton
@onready var _hint: Label = $Dim/Center/Panel/HintLabel

var _catalog: Catalog
var _session: PrototypeSession
var _gate_title: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_cancel_button.pressed.connect(_on_cancel_pressed)


func bind(catalog: Catalog, session: PrototypeSession) -> void:
	_catalog = catalog
	_session = session


func open(gate_title: String) -> void:
	_gate_title = gate_title
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _refresh() -> void:
	_title.text = _gate_title
	_description.text = "Select a known Unspace route to translate."

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
		button.text = "Translate to %s" % label
		button.pressed.connect(_on_route_pressed.bind(target_id))
		_route_list.add_child(button)

	_hint.text = "Esc or Cancel to stay in orbit"


func _on_route_pressed(target_sector_id: String) -> void:
	jump_requested.emit(target_sector_id)


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
