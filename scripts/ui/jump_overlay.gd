extends CanvasLayer

signal jump_requested(target_sector_id: String, n: int, solution: int)
signal cancelled

const N_COLUMNS: Array[int] = [4, 5, 6]
const COL_DEST_MIN_WIDTH := 320
const COL_N_MIN_WIDTH := 148
const ROUTE_SCROLL_HEIGHT := 420.0
## Destination + three N-space columns + h_separation between them (8px × 3).
const TABLE_MIN_WIDTH := 960

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

	var on_volatile_site := VolatileTranslation.is_volatile_sector_id(_session.sector_id)
	var all_offers: Array = []
	if on_volatile_site:
		all_offers = TranslationNav.list_volatile_site_offers(
			_session,
			_catalog,
			_session.sector_id,
			_assembled_ship
		)
		_description.text = (
			"Temporary return gate. Translate back before the gate collapses."
		)
	else:
		var library: Array = _session.player.translation_library if _session.player != null else []
		all_offers = TranslationNav.list_offered_translations(
			_catalog,
			_session.sector_id,
			_assembled_ship,
			library,
			_session
		)
	var offers := all_offers if on_volatile_site else _filter_beacon_offers(all_offers, beacon_destination)
	var partitioned := TranslationNav.partition_jump_offers(offers)
	var public_offers: Array = partitioned.get("public", [])
	var private_offers: Array = partitioned.get("private", [])
	var grouped := TranslationNav.group_offered_translations(_catalog, _session.sector_id, public_offers)
	var local_rows: Array = grouped.get("local", [])
	var other_rows: Array = grouped.get("other", [])
	var volatile_rows: Array = grouped.get("volatile", [])

	_build_route_tables(local_rows, other_rows, volatile_rows)
	_build_private_library_strip(private_offers)

	_hint.text = "Esc or Cancel to stay in orbit"
	if (
		local_rows.is_empty()
		and other_rows.is_empty()
		and volatile_rows.is_empty()
		and private_offers.is_empty()
	):
		if on_volatile_site:
			_solution_label.text = "The temporary return gate is no longer available."
		elif beacon_destination.is_empty():
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


func _build_private_library_strip(private_offers: Array) -> void:
	if private_offers.is_empty():
		return
	var header := Label.new()
	header.text = "Private library translations"
	header.add_theme_font_size_override("font_size", 14)
	_route_list.add_child(header)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route_list.add_child(list)
	for offer_variant in private_offers:
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = offer_variant
		var button := Button.new()
		var translation: Dictionary = offer.get("translation", {})
		var dest := TranslationNav.destination_display_label(
			_catalog,
			str(translation.get("target", ""))
		)
		var n := int(translation.get("n", 4))
		button.text = "%s · %d-space\n%s" % [
			dest,
			n,
			TranslationNav.format_cell_summary(
				float(offer.get("accuracy", 0.0)),
				float(offer.get("duration_seconds", 0.0)),
				translation
			),
		]
		button.toggle_mode = true
		button.set_meta("translation_offer", offer)
		button.button_pressed = _offers_equal(offer, _selected_offer)
		button.pressed.connect(_on_offer_cell_pressed.bind(offer, button))
		list.add_child(button)


func _build_route_tables(local_rows: Array, other_rows: Array, volatile_rows: Array) -> void:
	var sections: Array = []
	if not local_rows.is_empty():
		sections.append({
			"title": TranslationNav.local_system_tab_title(_catalog, _session.sector_id),
			"rows": local_rows,
		})
	if not other_rows.is_empty():
		sections.append({"title": "Other star systems", "rows": other_rows})
	if not volatile_rows.is_empty():
		sections.append({"title": "Volatile translations", "rows": volatile_rows})

	if sections.is_empty():
		return
	if sections.size() == 1:
		_route_list.add_child(_build_table_scroll(sections[0].get("rows", [])))
		return

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_route_list.add_child(tabs)
	for index in sections.size():
		var section: Dictionary = sections[index]
		var scroll := _build_table_scroll(section.get("rows", []))
		tabs.add_child(scroll)
		tabs.set_tab_title(index, str(section.get("title", "")))


func _build_table_scroll(rows: Array) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(float(TABLE_MIN_WIDTH), ROUTE_SCROLL_HEIGHT)
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
	_add_dest_cell(header, {}, true)
	for n in N_COLUMNS:
		_add_n_label_cell(header, "%d-space" % n, true)
	table.add_child(header)

	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		var data_row := _new_table_row()
		_add_dest_cell(data_row, row, false)
		var by_n: Dictionary = row.get("by_n", {})
		for n in N_COLUMNS:
			var offer: Variant = by_n.get(n, null)
			if typeof(offer) == TYPE_DICTIONARY and not offer.is_empty():
				_add_offer_cell(data_row, offer)
			else:
				_add_n_label_cell(data_row, "-", false)
		table.add_child(data_row)

	return table


func _new_table_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


func _add_dest_cell(row: HBoxContainer, row_data: Variant, header: bool) -> void:
	if header:
		var header_label := Label.new()
		header_label.text = "Destination"
		header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header_label.custom_minimum_size = Vector2(float(COL_DEST_MIN_WIDTH), 0.0)
		header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_label.size_flags_stretch_ratio = 1.6
		header_label.add_theme_font_size_override("font_size", 14)
		row.add_child(header_label)
		return

	if typeof(row_data) != TYPE_DICTIONARY:
		return
	var dest_row: Dictionary = row_data
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(float(COL_DEST_MIN_WIDTH), 0.0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.6
	column.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	name_label.text = str(dest_row.get("label", ""))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(name_label)

	var description := str(dest_row.get("description", "")).strip_edges()
	if not description.is_empty():
		var desc_label := Label.new()
		desc_label.text = description
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.theme_type_variation = &"Muted"
		column.add_child(desc_label)

	row.add_child(column)


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
	var translation: Dictionary = offer.get("translation", {})
	button.text = TranslationNav.format_cell_summary(
		float(offer.get("accuracy", 0.0)),
		float(offer.get("duration_seconds", 0.0)),
		translation
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
	var detail := (
		"Selected: %d → %s via %d-space. Nav accuracy %d%% before jump."
		% [solution, label, n, int(round(accuracy))]
	)
	if bool(translation.get("volatile", false)):
		detail += " %s" % TranslationNav.format_lag_pair(translation)
	if bool(_selected_offer.get("volatile", false)) and bool(translation.get("volatile", false)):
		var record := VolatileTranslation.find_by_solution(_session, _session.sector_id, solution)
		if not record.is_empty():
			var remaining := float(record.get("expires_gst", 0.0)) - _session.gst_seconds
			if remaining > 0.0:
				detail += " Single-use; offer expires in %s." % GalacticCalendar.format_duration(remaining)
			else:
				detail += " Single-use."
	elif bool(_selected_offer.get("volatile_return", false)) and bool(translation.get("volatile", false)):
		var record := VolatileTranslation.find_by_sector_id(_session, _session.sector_id)
		if not record.is_empty():
			var remaining := float(record.get("return_expires_gst", 0.0)) - _session.gst_seconds
			if remaining > 0.0:
				detail += " Gate collapses in %s." % GalacticCalendar.format_duration(remaining)
	_solution_label.text = detail
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
