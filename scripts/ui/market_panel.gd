extends Control

var _context: UiContext
var _selected_commodity_id: String = ""
var _market_commodity_ids: PackedStringArray = PackedStringArray()
var _market_listings: Array[Dictionary] = []
var _commodity_item_list: ItemList
var _suppress_commodity_select: bool = false
var _cargo_ship_id: String = ""


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
	_commodity_item_list = null
	_build_content()


func _build_content() -> void:
	_context.session.refresh_market_quotes(_context.catalog)
	var listings := _context.session.get_sector_quote_listings(_context.catalog)
	if listings.is_empty():
		var empty := Label.new()
		empty.text = "No market listings available."
		add_child(empty)
		return

	_market_commodity_ids.clear()
	_market_listings.clear()

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

	left.add_child(_section_label("EXCHANGE LISTINGS"))
	var quote_day := Label.new()
	quote_day.text = "Quotes as of %s" % _context.session.get_market_quote_day_label()
	left.add_child(quote_day)

	_commodity_item_list = ItemList.new()
	_commodity_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_commodity_item_list.select_mode = ItemList.SELECT_SINGLE
	_commodity_item_list.allow_reselect = true
	_commodity_item_list.item_selected.connect(_on_commodity_item_selected)
	left.add_child(_commodity_item_list)

	var detail := _add_scroll_pane(split, "detail_host")

	for listing_variant in listings:
		if typeof(listing_variant) != TYPE_DICTIONARY:
			continue
		var listing: Dictionary = listing_variant
		var commodity_id := str(listing.get("commodity_id", ""))
		var commodity := _context.catalog.get_commodity(commodity_id)
		if commodity.is_empty():
			continue

		_market_commodity_ids.append(commodity_id)
		_market_listings.append(listing)

		var price := int(listing.get("price", commodity.get("base_price", 0)))
		_commodity_item_list.add_item(
			"%s · d%d" % [str(commodity.get("name", commodity_id)), price]
		)

	if _selected_commodity_id.is_empty() and not _market_commodity_ids.is_empty():
		_selected_commodity_id = _market_commodity_ids[0]
	elif not _market_commodity_ids.has(_selected_commodity_id):
		_selected_commodity_id = _market_commodity_ids[0] if not _market_commodity_ids.is_empty() else ""

	_select_item_by_id(
		_commodity_item_list,
		_market_commodity_ids,
		_selected_commodity_id,
		"_suppress_commodity_select"
	)
	_rebuild_commodity_detail(detail)


func _on_commodity_item_selected(index: int) -> void:
	if _suppress_commodity_select:
		return
	if index < 0 or index >= _market_commodity_ids.size():
		return
	_selected_commodity_id = _market_commodity_ids[index]
	var detail := _find_meta_host("detail_host")
	if detail != null:
		_rebuild_commodity_detail(detail)


func _rebuild_commodity_detail(detail: VBoxContainer) -> void:
	_clear_children(detail)

	if _selected_commodity_id.is_empty():
		return

	var listing := _find_market_listing(_selected_commodity_id)
	var commodity := _context.catalog.get_commodity(_selected_commodity_id)
	if commodity.is_empty():
		return

	var price := int(listing.get("price", commodity.get("base_price", 0)))
	var store_qty := int(listing.get("quantity", 0))
	var cargo_ship := _context.session.get_cargo_ship(_cargo_ship_id)
	var cargo_qty := 0
	var cargo_cap := 0.0
	var cargo_mass := 0.0
	if cargo_ship != null:
		cargo_qty = _context.session.get_cargo_count(cargo_ship, _selected_commodity_id)
		cargo_cap = _context.session.get_ship_cargo_capacity(_context.catalog, cargo_ship)
		cargo_mass = _context.session.get_ship_cargo_mass(_context.catalog, cargo_ship)

	detail.add_child(_headline_label(str(commodity.get("name", _selected_commodity_id))))

	var desc_text := str(commodity.get("description", ""))
	if not desc_text.is_empty():
		var desc := Label.new()
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.text = desc_text
		detail.add_child(desc)

	detail.add_child(_detail_row("Price", "d%d" % price))
	detail.add_child(_detail_row("Sell price", "d%d" % _context.session.commodity_sell_price(price)))
	detail.add_child(_detail_row("Contract depth", str(store_qty)))
	if cargo_ship != null:
		detail.add_child(_detail_row("Ship cargo", str(cargo_qty)))
		detail.add_child(_detail_row("Hold used", "%.1f / %.1f t" % [cargo_mass, cargo_cap]))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	detail.add_child(actions)

	var buy := Button.new()
	buy.text = "Buy 1"
	buy.pressed.connect(_on_buy_commodity.bind(_selected_commodity_id))
	actions.add_child(buy)

	var sell := Button.new()
	sell.text = "Sell 1"
	sell.pressed.connect(_on_sell_commodity.bind(_selected_commodity_id))
	actions.add_child(sell)


func _find_market_listing(commodity_id: String) -> Dictionary:
	for listing in _market_listings:
		if str(listing.get("commodity_id", "")) == commodity_id:
			return listing
	return {}


func _on_buy_commodity(commodity_id: String) -> void:
	_selected_commodity_id = commodity_id
	_context.session.buy_commodity(
		_context.catalog,
		_context.session.building_id,
		commodity_id,
		1,
		_cargo_ship_id
	)


func _on_sell_commodity(commodity_id: String) -> void:
	_selected_commodity_id = commodity_id
	_context.session.sell_commodity(
		_context.catalog,
		_context.session.building_id,
		commodity_id,
		1,
		_cargo_ship_id
	)


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
