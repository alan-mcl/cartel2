extends Control

const LOCATION_ART := preload("res://scenes/ui/components/location_art.tscn")

var _context: UiContext
var _building: Dictionary = {}
var _selected_dealer_stock_id: String = ""
var _dealer_stock_ids: PackedStringArray = PackedStringArray()
var _dealer_item_list: ItemList
var _suppress_dealer_select: bool = false


func bind(context: UiContext) -> void:
	_context = context
	if _context.session != null and not _context.session.changed.is_connected(refresh):
		_context.session.changed.connect(refresh, CONNECT_DEFERRED)


func configure(building: Dictionary) -> void:
	_building = building


func refresh() -> void:
	if not is_node_ready() or _context == null or _context.session == null:
		return
	if _building.is_empty():
		_building = _context.session.get_current_building(_context.catalog)
	_clear_children(self)
	_dealer_item_list = null
	var building_type := _context.catalog.get_building_type(_building)
	if building_type == "ship_dealer":
		_build_ship_dealer_content(_building)
	elif building_type == "chassis_dealer":
		_build_chassis_dealer_content(_building)


func _build_ship_dealer_content(building: Dictionary) -> void:
	_dealer_stock_ids.clear()
	var stock: Variant = building.get("stock", [])
	if typeof(stock) != TYPE_ARRAY or stock.is_empty():
		var empty := Label.new()
		empty.text = "No ships in stock."
		add_child(empty)
		return

	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 320)
	add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(320, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	split.add_child(left)

	left.add_child(_section_label("USED SCOUT SHIPS"))

	_dealer_item_list = ItemList.new()
	_dealer_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dealer_item_list.select_mode = ItemList.SELECT_SINGLE
	_dealer_item_list.allow_reselect = true
	_dealer_item_list.item_selected.connect(_on_dealer_item_selected)
	left.add_child(_dealer_item_list)

	var detail := _add_scroll_pane(split, "dealer_detail_host")

	for template_id in stock:
		var id := str(template_id)
		var template := _context.catalog.get_ship(id)
		if template.is_empty():
			continue
		_dealer_stock_ids.append(id)
		var price := ShipAssembly.used_ship_price(_context.catalog, id)
		_dealer_item_list.add_item(
			"%s · d%d" % [str(template.get("name", id)), price]
		)

	_sync_dealer_selection(detail)
	_rebuild_ship_dealer_detail(detail)


func _build_chassis_dealer_content(building: Dictionary) -> void:
	_dealer_stock_ids.clear()
	var stock: Variant = building.get("stock", [])
	if typeof(stock) != TYPE_ARRAY or stock.is_empty():
		var empty := Label.new()
		empty.text = "No chassis in stock."
		add_child(empty)
		return

	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 320)
	add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(320, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	split.add_child(left)

	left.add_child(_section_label("UNFITTED FRAMES"))

	_dealer_item_list = ItemList.new()
	_dealer_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dealer_item_list.select_mode = ItemList.SELECT_SINGLE
	_dealer_item_list.allow_reselect = true
	_dealer_item_list.item_selected.connect(_on_dealer_item_selected)
	left.add_child(_dealer_item_list)

	var detail := _add_scroll_pane(split, "dealer_detail_host")

	for chassis_id in stock:
		var id := str(chassis_id)
		var chassis := _context.catalog.get_chassis(id)
		if chassis.is_empty():
			continue
		_dealer_stock_ids.append(id)
		var price := ShipAssembly.chassis_price(_context.catalog, id)
		_dealer_item_list.add_item(
			"%s · d%d" % [str(chassis.get("name", id)), price]
		)

	_sync_dealer_selection(detail)
	_rebuild_chassis_dealer_detail(detail)


func _sync_dealer_selection(detail: VBoxContainer) -> void:
	if _selected_dealer_stock_id.is_empty() and not _dealer_stock_ids.is_empty():
		_selected_dealer_stock_id = _dealer_stock_ids[0]
	elif not _dealer_stock_ids.has(_selected_dealer_stock_id):
		_selected_dealer_stock_id = _dealer_stock_ids[0] if not _dealer_stock_ids.is_empty() else ""

	_select_item_by_id(
		_dealer_item_list,
		_dealer_stock_ids,
		_selected_dealer_stock_id,
		"_suppress_dealer_select"
	)


func _on_dealer_item_selected(index: int) -> void:
	if _suppress_dealer_select:
		return
	if index < 0 or index >= _dealer_stock_ids.size():
		return
	_selected_dealer_stock_id = _dealer_stock_ids[index]
	var detail := _find_meta_host("dealer_detail_host")
	if detail == null:
		return
	var building_type := _context.catalog.get_building_type(_building)
	if building_type == "ship_dealer":
		_rebuild_ship_dealer_detail(detail)
	elif building_type == "chassis_dealer":
		_rebuild_chassis_dealer_detail(detail)


func _rebuild_ship_dealer_detail(detail: VBoxContainer) -> void:
	_clear_children(detail)
	if _selected_dealer_stock_id.is_empty():
		return

	var template := _context.catalog.get_ship(_selected_dealer_stock_id)
	if template.is_empty():
		return

	var chassis := _context.catalog.get_chassis(str(template.get("chassis", "")))
	var assembled := ShipAssembly.preview_from_template(_context.catalog, _selected_dealer_stock_id)
	var price := ShipAssembly.used_ship_price(_context.catalog, _selected_dealer_stock_id)

	var art_host := VBoxContainer.new()
	detail.add_child(art_host)
	var art := LOCATION_ART.instantiate()
	art_host.add_child(art)
	art.set_art_path(str(chassis.get("sprite", "")), str(template.get("name", _selected_dealer_stock_id)))

	detail.add_child(_headline_label(str(template.get("name", _selected_dealer_stock_id))))
	detail.add_child(_detail_row("Maker", str(template.get("maker", ""))))
	detail.add_child(_detail_row("Price", "d%d" % price))
	detail.add_child(_detail_row("Chassis", str(chassis.get("name", ""))))

	if assembled != null:
		var summary := Label.new()
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.text = assembled.get_summary()
		detail.add_child(summary)

	var buy := Button.new()
	buy.text = "Buy"
	buy.pressed.connect(_on_buy_used_ship.bind(_selected_dealer_stock_id))
	detail.add_child(buy)


func _rebuild_chassis_dealer_detail(detail: VBoxContainer) -> void:
	_clear_children(detail)
	if _selected_dealer_stock_id.is_empty():
		return

	var chassis := _context.catalog.get_chassis(_selected_dealer_stock_id)
	if chassis.is_empty():
		return

	var price := ShipAssembly.chassis_price(_context.catalog, _selected_dealer_stock_id)

	var art_host := VBoxContainer.new()
	detail.add_child(art_host)
	var art := LOCATION_ART.instantiate()
	art_host.add_child(art)
	art.set_art_path(str(chassis.get("sprite", "")), str(chassis.get("name", _selected_dealer_stock_id)))

	detail.add_child(_headline_label(str(chassis.get("name", _selected_dealer_stock_id))))
	detail.add_child(_detail_row("Maker", str(chassis.get("maker", ""))))
	detail.add_child(_detail_row("Price", "d%d" % price))
	detail.add_child(_detail_row("Maneuver", str(chassis.get("maneuver", ""))))
	detail.add_child(_detail_row("Mass limit", str(chassis.get("mass_limit", ""))))

	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Unfitted frame. Visit the Shipyard to install modules before undocking."
	detail.add_child(note)

	var buy := Button.new()
	buy.text = "Buy"
	buy.pressed.connect(_on_buy_chassis.bind(_selected_dealer_stock_id))
	detail.add_child(buy)


func _on_buy_used_ship(template_id: String) -> void:
	_selected_dealer_stock_id = template_id
	_context.session.buy_used_ship(_context.catalog, template_id)


func _on_buy_chassis(chassis_id: String) -> void:
	_selected_dealer_stock_id = chassis_id
	_context.session.buy_chassis(_context.catalog, chassis_id)


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


func _detail_row(label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var key := Label.new()
	key.text = "%s:" % label_text
	key.theme_type_variation = &"Muted"
	key.custom_minimum_size = Vector2(120, 0)
	row.add_child(key)

	var value := Label.new()
	value.text = value_text
	value.theme_type_variation = &"Numeric"
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)

	return row


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Section"
	return label


func _headline_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Headline"
	return label
