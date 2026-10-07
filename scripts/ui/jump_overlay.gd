extends CanvasLayer

signal jump_requested(target_sector_id: String, n: int, solution: int)
signal cancelled

const N_COLUMNS: Array[int] = [4, 5, 6]
const COL_DEST_MIN_WIDTH := 240
const COL_N_MIN_WIDTH := 148
## Destination + three N-space columns + h_separation between them (8px × 3).
const TABLE_MIN_WIDTH := 708

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
var _selected_offer: Dictionary = {}


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
	_selected_offer = {}
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_selected_offer = {}


func _refresh() -> void:
	_title.text = _gate_title
	_clear_container(_route_list)

	if _catalog == null or _session == null:
		return

	var beacon_destination := _translation_beacon_destination()
	if beacon_destination.is_empty():
		_description.text = (
			"Higher N-space is faster but less accurate. Pick a destination and depth, then confirm."
		)
	else:
		var dest_label := TranslationNav.destination_display_label(_catalog, beacon_destination)
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
	var offers := _filter_beacon_offers(all_offers, beacon_destination)
	var grouped := TranslationNav.group_offered_translations(_catalog, _session.sector_id, offers)
	var local_rows: Array = grouped.get("local", [])
	var other_rows: Array = grouped.get("other", [])

	_build_route_tables(local_rows, other_rows)

	_hint.text = "Esc or Cancel to stay in orbit"
	if local_rows.is_empty() and other_rows.is_empty():
		if beacon_destination.is_empty():
			_solution_label.text = "No translations available from this gate."
		else:
			_solution_label.text = "No public translation to the tuned destination."
		_confirm_button.disabled = true
		return

	_update_selection_ui()


func _filter_beacon_offers(all_offers: Array, beacon_destination: String) -> Array:
	if beacon_destination.is_empty():
		return all_offers
	var filtered: Array = []
	for offer_variant in all_offers:
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = offer_variant
		var translation: Dictionary = offer.get("translation", {})
		if int(translation.get("n", 0)) != 4:
			continue
		if str(translation.get("target", "")) != beacon_destination:
			continue
		filtered.append(offer)
	return filtered


func _build_route_tables(local_rows: Array, other_rows: Array) -> void:
	var has_local := not local_rows.is_empty()
	var has_other := not other_rows.is_empty()
	if has_local and has_other:
		var tabs := TabContainer.new()
		tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_route_list.add_child(tabs)
		var local_scroll := _build_table_scroll(local_rows)
		tabs.add_child(local_scroll)
		tabs.set_tab_title(0, "Local Star System")
		var other_scroll := _build_table_scroll(other_rows)
		tabs.add_child(other_scroll)
		tabs.set_tab_title(1, "Other star systems")
	elif has_local:
		_route_list.add_child(_build_table_scroll(local_rows))
	elif has_other:
		_route_list.add_child(_build_table_scroll(other_rows))


func _build_table_scroll(rows: Array) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(float(TABLE_MIN_WIDTH), 280.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var table := _build_table(rows)
	scroll.add_child(table)
	return scroll


func _build_table(rows: Array) -> VBoxContainer:
	var table := VBoxContainer.new()
	table.custom_minimum_size = Vector2(float(TABLE_MIN_WIDTH), 0.0)
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("separation", 4)

	var header := _new_table_row()
	_add_dest_cell(header, "Destination", true)
	for n in N_COLUMNS:
		_add_n_label_cell(header, "%d-space" % n, true)
	table.add_child(header)

	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		var data_row := _new_table_row()
		_add_dest_cell(data_row, str(row.get("label", "")), false)
		var by_n: Dictionary = row.get("by_n", {})
		for n in N_COLUMNS:
			var offer: Variant = by_n.get(n, null)
			if typeof(offer) == TYPE_DICTIONARY and not offer.is_empty():
				_add_offer_cell(data_row, offer)
			else:
				_add_n_label_cell(data_row, "—", false)
		table.add_child(data_row)

	return table


func _new_table_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


func _add_dest_cell(row: HBoxContainer, text: String, header: bool) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(float(COL_DEST_MIN_WIDTH), 0.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = 1.6
	if header:
		label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)


func _add_n_label_cell(row: HBoxContainer, text: String, header: bool) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(float(COL_N_MIN_WIDTH), 0.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if header:
		label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)


func _add_offer_cell(row: HBoxContainer, offer: Dictionary) -> void:
	var button := Button.new()
	button.text = TranslationNav.format_cell_summary(
		float(offer.get("accuracy", 0.0)),
		float(offer.get("duration_seconds", 0.0))
	)
	button.custom_minimum_size = Vector2(float(COL_N_MIN_WIDTH), 0.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.set_meta("translation_offer", offer)
	button.button_pressed = _offers_equal(offer, _selected_offer)
	button.pressed.connect(_on_offer_cell_pressed.bind(offer, button))
	row.add_child(button)


func _offers_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	var ta: Dictionary = a.get("translation", {})
	var tb: Dictionary = b.get("translation", {})
	return (
		str(ta.get("target", "")) == str(tb.get("target", ""))
		and int(ta.get("n", 0)) == int(tb.get("n", 0))
		and int(ta.get("solution", 0)) == int(tb.get("solution", 0))
	)


func _on_offer_cell_pressed(offer: Dictionary, _button: Button) -> void:
	_selected_offer = offer
	_sync_offer_cell_selection()
	_update_selection_ui()


func _sync_offer_cell_selection() -> void:
	for button in _route_list.find_children("*", "Button", true, false):
		if button is Button:
			var offer: Dictionary = button.get_meta("translation_offer", {})
			button.button_pressed = _offers_equal(offer, _selected_offer)


func _update_selection_ui() -> void:
	if _selected_offer.is_empty():
		_solution_label.text = "No translation selected."
		_confirm_button.disabled = true
		return

	var translation: Dictionary = _selected_offer.get("translation", {})
	var accuracy := float(_selected_offer.get("accuracy", 0.0))
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
	if _selected_offer.is_empty():
		return
	var translation: Dictionary = _selected_offer.get("translation", {})
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
