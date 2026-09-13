extends Control

const SHIP_DETAIL_PANEL := preload("res://scenes/ui/ship_detail_panel.tscn")

const _TERMINAL_SHIP_DETAIL_OPTS := {
	"show_name": true,
	"chassis_style": "row",
	"show_modules": true,
	"show_flight": true,
	"flight_section_title": "STATS",
	"flight_row_style": "HBox",
	"flight_keys": [
		"dry_mass",
		"loaded_mass",
		"thrust",
		"max_speed",
		"boost_max_speed",
		"maneuver",
		"armour_hits",
	],
	"show_signature": true,
}

var _context: UiContext
var _selected_terminal_ship_id: String = ""
var _terminal_ship_ids: PackedStringArray = PackedStringArray()
var _terminal_ship_item_list: ItemList
var _suppress_terminal_ship_select: bool = false
var _show_rename_field: bool = false


func bind(context: UiContext) -> void:
	_context = context
	if _context.session != null and not _context.session.changed.is_connected(refresh):
		_context.session.changed.connect(refresh, CONNECT_DEFERRED)


func configure(_building: Dictionary) -> void:
	pass


func refresh() -> void:
	if not is_node_ready() or _context == null or _context.session == null:
		return
	_clear_children(self)
	_terminal_ship_item_list = null
	_build_content()


func _build_content() -> void:
	var ships := _context.session.ships_at(_context.session.habitat_id)

	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 12)
	add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	left.add_theme_constant_override("separation", 4)
	columns.add_child(left)

	left.add_child(_section_label("YOUR DOCKED SHIPS"))

	if ships.is_empty():
		var empty := Label.new()
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.text = (
			"No ships docked at this habitat. "
			+ "Visit Concord Scouts for a used ship or Skyedge for an unfitted frame."
		)
		left.add_child(empty)
		return

	_terminal_ship_ids.clear()

	_terminal_ship_item_list = ItemList.new()
	_terminal_ship_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_terminal_ship_item_list.select_mode = ItemList.SELECT_SINGLE
	_terminal_ship_item_list.allow_reselect = true
	_terminal_ship_item_list.item_selected.connect(_on_terminal_ship_item_selected)
	left.add_child(_terminal_ship_item_list)

	var detail := _add_scroll_pane(columns, "terminal_detail_host")
	var detail_scroll := detail.get_parent() as ScrollContainer
	if detail_scroll != null:
		detail_scroll.size_flags_stretch_ratio = 1.0

	var admin := VBoxContainer.new()
	admin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	admin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	admin.size_flags_stretch_ratio = 1.0
	admin.add_theme_constant_override("separation", 8)
	admin.set_meta("terminal_admin_host", true)
	columns.add_child(admin)

	for ship in ships:
		_terminal_ship_ids.append(ship.id)
		_terminal_ship_item_list.add_item(ship.name)

	if _selected_terminal_ship_id.is_empty() and not _terminal_ship_ids.is_empty():
		_selected_terminal_ship_id = _terminal_ship_ids[0]
	elif not _terminal_ship_ids.has(_selected_terminal_ship_id):
		_selected_terminal_ship_id = _terminal_ship_ids[0] if not _terminal_ship_ids.is_empty() else ""

	_select_item_by_id(
		_terminal_ship_item_list,
		_terminal_ship_ids,
		_selected_terminal_ship_id,
		"_suppress_terminal_ship_select"
	)
	_rebuild_terminal_ship_panels()


func _on_terminal_ship_item_selected(index: int) -> void:
	if _suppress_terminal_ship_select:
		return
	if index < 0 or index >= _terminal_ship_ids.size():
		return
	_selected_terminal_ship_id = _terminal_ship_ids[index]
	_show_rename_field = false
	_rebuild_terminal_ship_panels()


func _rebuild_terminal_ship_panels() -> void:
	var detail := _find_meta_host("terminal_detail_host")
	var admin := _find_meta_host("terminal_admin_host")
	if detail != null:
		_rebuild_terminal_ship_detail(detail)
	if admin != null:
		_rebuild_terminal_admin_panel(admin)


func _rebuild_terminal_ship_detail(detail: VBoxContainer) -> void:
	if _selected_terminal_ship_id.is_empty():
		_clear_children(detail)
		return

	var ship := _context.session.get_owned_ship(_selected_terminal_ship_id)
	if ship == null:
		_clear_children(detail)
		return

	var panel := _ensure_ship_detail_panel(detail)
	panel.configure(_TERMINAL_SHIP_DETAIL_OPTS)
	panel.bind_ship(_context.catalog, ship)
	panel.refresh()


func _ensure_ship_detail_panel(detail: VBoxContainer) -> VBoxContainer:
	for child in detail.get_children():
		if child.has_method("bind_ship"):
			return child as VBoxContainer
	var panel: VBoxContainer = SHIP_DETAIL_PANEL.instantiate()
	detail.add_child(panel)
	return panel


func _rebuild_terminal_admin_panel(admin: VBoxContainer) -> void:
	_clear_children(admin)

	if _selected_terminal_ship_id.is_empty():
		return

	var ship := _context.session.get_owned_ship(_selected_terminal_ship_id)
	if ship == null:
		return

	var rename := Button.new()
	rename.text = "Rename Ship"
	rename.pressed.connect(_on_rename_ship_pressed)
	admin.add_child(rename)

	if _show_rename_field:
		var rename_row := HBoxContainer.new()
		rename_row.add_theme_constant_override("separation", 8)
		admin.add_child(rename_row)

		var field := LineEdit.new()
		field.text = ship.name
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.text_submitted.connect(_on_rename_ship_submitted)
		rename_row.add_child(field)

		var confirm := Button.new()
		confirm.text = "Confirm"
		confirm.pressed.connect(func() -> void:
			_on_rename_ship_submitted(field.text)
		)
		rename_row.add_child(confirm)

	admin.add_child(_section_label("LAUNCH STATUS"))

	var blockers := ShipAssembly.undock_blockers(_context.catalog, ship)
	if blockers.is_empty():
		var cleared := Label.new()
		cleared.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cleared.text = "All checks green - cleared for launch."
		admin.add_child(cleared)

		var launch := Button.new()
		launch.text = "Launch"
		launch.pressed.connect(_on_undock_ship.bind(ship.id))
		admin.add_child(launch)
	else:
		for reason in blockers:
			var hint := Label.new()
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.text = reason
			admin.add_child(hint)


func _on_rename_ship_pressed() -> void:
	_show_rename_field = true
	call_deferred("_refresh_terminal_admin_panel")


func _refresh_terminal_admin_panel() -> void:
	var admin := _find_meta_host("terminal_admin_host")
	if admin != null:
		_rebuild_terminal_admin_panel(admin)


func _on_rename_ship_submitted(new_name: String) -> void:
	if _selected_terminal_ship_id.is_empty():
		return
	if not _context.session.rename_ship(_selected_terminal_ship_id, new_name):
		return
	_show_rename_field = false
	var index := _terminal_ship_ids.find(_selected_terminal_ship_id)
	if index >= 0 and _terminal_ship_item_list != null:
		_terminal_ship_item_list.set_item_text(index, new_name.strip_edges())
	call_deferred("_rebuild_terminal_ship_panels")


func _on_undock_ship(ship_id: String) -> void:
	if _context.on_undock_requested.is_valid():
		_context.on_undock_requested.call(ship_id)


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


func _find_meta_host(meta_name: String) -> VBoxContainer:
	return _find_meta_host_in(self, meta_name)


func _find_meta_host_in(node: Node, meta_name: String) -> VBoxContainer:
	if node is VBoxContainer and node.has_meta(meta_name):
		return node as VBoxContainer
	for child in node.get_children():
		var found := _find_meta_host_in(child, meta_name)
		if found != null:
			return found
	return null


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Section"
	return label


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

