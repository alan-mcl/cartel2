extends GameScreen

var _building: Dictionary = {}
var _shelf_id: String = LibraryIndex.SHELF_WORLDS
var _entry_ids: PackedStringArray = PackedStringArray()
var _selected_entry_id: String = ""
var _suppress_item_select: bool = false

var _root: VBoxContainer
var _shelf_buttons: Dictionary = {}
var _filter_line: LineEdit
var _item_list: ItemList
var _detail_host: VBoxContainer


func session_changed() -> void:
	pass


func configure(building: Dictionary) -> void:
	_building = building.duplicate(true)


func refresh() -> void:
	if not is_node_ready() or _context == null or _context.catalog == null:
		return
	if _building.is_empty():
		_building = _context.session.get_current_building(_context.catalog)
	_rebuild_list()
	_rebuild_detail()


func _ready() -> void:
	_root = VBoxContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 8)
	add_child(_root)

	var shelf_row := HBoxContainer.new()
	shelf_row.add_theme_constant_override("separation", 6)
	_root.add_child(shelf_row)
	for shelf_id in LibraryIndex.list_shelf_ids():
		var button := Button.new()
		button.toggle_mode = true
		button.text = LibraryIndex.shelf_label(shelf_id)
		button.pressed.connect(_on_shelf_pressed.bind(shelf_id))
		shelf_row.add_child(button)
		_shelf_buttons[shelf_id] = button

	_filter_line = LineEdit.new()
	_filter_line.placeholder_text = "Filter entries"
	_filter_line.text_changed.connect(_on_filter_changed)
	_root.add_child(_filter_line)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 320)
	_root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left)

	left.add_child(_section_label("ENTRIES"))

	_item_list = ItemList.new()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.select_mode = ItemList.SELECT_SINGLE
	_item_list.allow_reselect = true
	_item_list.item_selected.connect(_on_item_selected)
	left.add_child(_item_list)

	_detail_host = _add_scroll_pane(split, "library_detail_host")
	_sync_shelf_buttons()
	refresh()


func _on_shelf_pressed(shelf_id: String) -> void:
	if _shelf_id == shelf_id:
		return
	_shelf_id = shelf_id
	_sync_shelf_buttons()
	_rebuild_list()
	_rebuild_detail()


func _on_filter_changed(_new_text: String) -> void:
	_rebuild_list()
	_rebuild_detail()


func _on_item_selected(index: int) -> void:
	if _suppress_item_select:
		return
	if index < 0 or index >= _entry_ids.size():
		return
	_selected_entry_id = _entry_ids[index]
	_rebuild_detail()


func _sync_shelf_buttons() -> void:
	for shelf_id in _shelf_buttons.keys():
		var button: Button = _shelf_buttons[shelf_id]
		button.button_pressed = shelf_id == _shelf_id


func _rebuild_list() -> void:
	if _item_list == null or _context == null or _context.catalog == null:
		return
	var filter_text := ""
	if _filter_line != null:
		filter_text = _filter_line.text
	var rows: Array = LibraryIndex.list_rows(_context.catalog, _shelf_id, filter_text)
	_entry_ids.clear()
	_item_list.clear()
	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		var entry_id := str(row.get("id", ""))
		if entry_id.is_empty():
			continue
		_entry_ids.append(entry_id)
		_item_list.add_item(str(row.get("label", entry_id)))

	if _selected_entry_id.is_empty() and not _entry_ids.is_empty():
		_selected_entry_id = _entry_ids[0]
	elif not _entry_ids.has(_selected_entry_id):
		_selected_entry_id = _entry_ids[0] if not _entry_ids.is_empty() else ""

	_select_item_by_id(_item_list, _entry_ids, _selected_entry_id, "_suppress_item_select")


func _rebuild_detail() -> void:
	if _detail_host == null or _context == null or _context.catalog == null:
		return
	_clear_children(_detail_host)
	if _selected_entry_id.is_empty():
		return
	var body := LibraryIndex.detail_text(_context.catalog, _shelf_id, _selected_entry_id)
	if body.is_empty():
		return
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = body
	_detail_host.add_child(label)


func _add_scroll_pane(parent: Node, meta_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	body.set_meta(meta_name, true)
	scroll.add_child(body)
	return body


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _select_item_by_id(
	list: ItemList,
	ids: PackedStringArray,
	target_id: String,
	suppress_flag_name: String
) -> void:
	set(suppress_flag_name, true)
	var index := ids.find(target_id)
	if index >= 0:
		list.select(index)
	else:
		list.deselect_all()
	set(suppress_flag_name, false)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Section"
	return label
