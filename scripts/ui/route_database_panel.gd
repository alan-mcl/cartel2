class_name RouteDatabasePanel
extends VBoxContainer

signal selection_changed(offer: Dictionary)

const N_COLUMNS: Array[int] = [4, 5, 6]
const COL_DEST_MIN_WIDTH := 320
const COL_N_MIN_WIDTH := 148
const ROUTE_SCROLL_HEIGHT := 420.0
const TABLE_MIN_WIDTH := 960

var _catalog: Catalog
var _session: GameSession
var _selected_offer: Dictionary = {}
var _route_list: VBoxContainer


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, ROUTE_SCROLL_HEIGHT)
	_route_list = VBoxContainer.new()
	_route_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_route_list.add_theme_constant_override("separation", 8)
	add_child(_route_list)


func bind(catalog: Catalog, session: GameSession) -> void:
	_catalog = catalog
	_session = session


func clear_selection() -> void:
	_selected_offer = {}
	selection_changed.emit(_selected_offer)


func get_selected_offer() -> Dictionary:
	return _selected_offer


func populate(
	local_rows: Array,
	other_rows: Array,
	volatile_rows: Array,
	private_offers: Array
) -> void:
	_clear_container(_route_list)
	_selected_offer = {}
	if _catalog == null or _session == null:
		return
	_build_route_tables(local_rows, other_rows, volatile_rows)
	_build_private_library_strip(private_offers)


func _build_private_library_strip(private_offers: Array) -> void:
	if private_offers.is_empty():
		return
	var header := Label.new()
	header.text = "Library solutions"
	header.add_theme_font_size_override("font_size", 14)
	_route_list.add_child(header)
	var blurb := Label.new()
	blurb.text = "Private routes from your hyperdrive or saved solutions — not on the public gate book."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.theme_type_variation = &"Muted"
	_route_list.add_child(blurb)
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
			_catalog, str(translation.get("target", ""))
		)
		var n := int(translation.get("n", 4))
		button.text = "%s · %d-space\n%s" % [
			dest,
			n,
			TranslationNav.format_offer_cell_summary(offer),
		]
		button.toggle_mode = true
		_style_library_offer_button(button)
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
	button.text = TranslationNav.format_offer_cell_summary(offer)
	if TranslationNav.is_library_offer(offer):
		_style_library_offer_button(button)
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
	selection_changed.emit(_selected_offer)


func sync_selection_display() -> void:
	_sync_offer_cell_selection()


func _sync_offer_cell_selection() -> void:
	for button in _route_list.find_children("*", "Button", true, false):
		if button is Button:
			var offer: Dictionary = button.get_meta("translation_offer", {})
			button.button_pressed = _offers_equal(offer, _selected_offer)


static func format_selection_detail(
	catalog: Catalog,
	session: GameSession,
	selected_offer: Dictionary
) -> Dictionary:
	if selected_offer.is_empty() or session == null:
		return {"text": "No translation selected.", "confirm_disabled": true, "confirm_text": "Translate"}
	var translation: Dictionary = selected_offer.get("translation", {})
	var accuracy := float(selected_offer.get("accuracy", 0.0))
	var n := int(translation.get("n", 4))
	var label := str(translation.get("label", translation.get("target", "")))
	var solution := int(translation.get("solution", 0))
	var detail := (
		"Selected: %d → %s via %d-space. Nav accuracy %d%% before jump."
		% [solution, label, n, int(round(accuracy))]
	)
	if TranslationNav.is_library_offer(selected_offer):
		detail += " Library-only route (private solution)."
	if bool(translation.get("volatile", false)):
		detail += " %s" % TranslationNav.format_lag_pair(translation)
	if bool(selected_offer.get("volatile", false)) and bool(translation.get("volatile", false)):
		var record := VolatileTranslation.find_by_solution(session, session.sector_id, solution)
		if not record.is_empty():
			var remaining := float(record.get("expires_gst", 0.0)) - session.gst_seconds
			if remaining > 0.0:
				detail += " Single-use; offer expires in %s." % GalacticCalendar.format_duration(remaining)
			else:
				detail += " Single-use."
	elif bool(selected_offer.get("volatile_return", false)) and bool(translation.get("volatile", false)):
		var record := VolatileTranslation.find_by_sector_id(session, session.sector_id)
		if not record.is_empty():
			var remaining := float(record.get("return_expires_gst", 0.0)) - session.gst_seconds
			if remaining > 0.0:
				detail += " Gate collapses in %s." % GalacticCalendar.format_duration(remaining)
	return {
		"text": detail,
		"confirm_disabled": false,
		"confirm_text": "Translate via %d-space" % n,
	}


static func _style_library_offer_button(button: Button) -> void:
	button.add_theme_color_override("font_color", Color(0.72, 0.88, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.85, 0.95, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.92, 0.98, 1.0, 1.0))


static func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
