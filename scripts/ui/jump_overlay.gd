extends CanvasLayer

signal jump_requested(target_sector_id: String, n: int, solution: int)
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
var _assembled_ship: AssembledShip
var _gate_title: String = ""
var _offers: Array = []
var _selected_index: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)


func bind(catalog: Catalog, session: GameSession, assembled_ship: AssembledShip = null) -> void:
	_catalog = catalog
	_session = session
	_assembled_ship = assembled_ship


func set_assembled_ship(assembled_ship: AssembledShip) -> void:
	_assembled_ship = assembled_ship


func open(gate_title: String) -> void:
	_gate_title = gate_title
	_selected_index = -1
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_selected_index = -1
	_offers.clear()


func _refresh() -> void:
	_title.text = _gate_title

	_clear_container(_route_list)
	_offers.clear()

	if _catalog == null or _session == null:
		return

	var beacon_destination := _translation_beacon_destination()
	if beacon_destination.is_empty():
		_description.text = "Select a translation, then confirm."
	else:
		var dest_sector := _catalog.get_sector(beacon_destination)
		var dest_label := str(dest_sector.get("planet_name", ""))
		if dest_label.is_empty():
			dest_label = str(dest_sector.get("name", beacon_destination))
		_description.text = (
			"This translation beacon is tuned to %s. Only the public 4-space hop is available."
			% dest_label
		)

	var library: Array = _session.player.translation_library if _session.player != null else []
	var all_offers := TranslationNav.list_offered_translations(
		_catalog,
		_session.sector_id,
		_assembled_ship,
		library
	)
	if beacon_destination.is_empty():
		_offers = all_offers
	else:
		for offer_variant in all_offers:
			if typeof(offer_variant) != TYPE_DICTIONARY:
				continue
			var offer: Dictionary = offer_variant
			var translation: Dictionary = offer.get("translation", {})
			if int(translation.get("n", 0)) != 4:
				continue
			if str(translation.get("target", "")) != beacon_destination:
				continue
			_offers.append(offer)

	for index in _offers.size():
		var offer_variant: Variant = _offers[index]
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = offer_variant
		var translation: Dictionary = offer.get("translation", {})
		var line := TranslationNav.format_offer_line(
			translation,
			float(offer.get("accuracy", 0.0)),
			float(offer.get("duration_seconds", 0.0))
		)
		var button := Button.new()
		var prefix := "> " if index == _selected_index else ""
		button.text = "%s%s" % [prefix, line]
		button.pressed.connect(_on_route_pressed.bind(index))
		_route_list.add_child(button)

	_hint.text = "Esc or Cancel to stay in orbit"
	if _offers.is_empty():
		if beacon_destination.is_empty():
			_solution_label.text = "No translations available from this gate."
		else:
			_solution_label.text = "No public translation to the tuned destination."
		_confirm_button.disabled = true
		return

	_update_selection_ui()


func _on_route_pressed(index: int) -> void:
	_selected_index = index
	_refresh()


func _update_selection_ui() -> void:
	if _selected_index < 0 or _selected_index >= _offers.size():
		_solution_label.text = "No translation selected."
		_confirm_button.disabled = true
		return

	var offer: Dictionary = _offers[_selected_index]
	var translation: Dictionary = offer.get("translation", {})
	var accuracy := float(offer.get("accuracy", 0.0))
	var n := int(translation.get("n", 4))
	var label := str(translation.get("label", translation.get("target", "")))
	var solution := int(translation.get("solution", 0))
	_solution_label.text = (
		"Selected: %d → %s via %d-space. Nav accuracy %d%% before jump."
		% [solution, label, n, int(round(accuracy))]
	)
	_confirm_button.disabled = false
	_confirm_button.text = "Translate via %d-space" % n


func _on_confirm_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _offers.size():
		return
	var offer: Dictionary = _offers[_selected_index]
	var translation: Dictionary = offer.get("translation", {})
	var target_id := str(translation.get("target", ""))
	var n := int(translation.get("n", 4))
	var solution := int(translation.get("solution", 0))
	if target_id.is_empty():
		return
	jump_requested.emit(target_id, n, solution)


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


func _translation_beacon_destination() -> String:
	if _catalog == null or _session == null:
		return ""
	var world_data := _catalog.get_world(_session.sector_id)
	var beacon: Variant = world_data.get("translation_beacon", {})
	if typeof(beacon) != TYPE_DICTIONARY or beacon.is_empty():
		return ""
	return str(beacon.get("destination", ""))
