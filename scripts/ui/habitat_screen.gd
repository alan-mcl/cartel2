extends Control

const LOCATION_ART := preload("res://scenes/ui/components/location_art.tscn")
const SHIPYARD_SCREEN := preload("res://scenes/ui/shipyard_screen.tscn")

@onready var _title: Label = $Layout/Header/HeaderBox/Title
@onready var _description: Label = $Layout/Header/HeaderBox/Description
@onready var _pilot: Label = $Layout/Header/HeaderBox/Pilot
@onready var _credits: Label = $Layout/Header/HeaderBox/Credits
@onready var _building_item_list: ItemList = $Layout/Body/Split/Left/BuildingItemList
@onready var _art_host: VBoxContainer = $Layout/Body/Split/Right/ArtHost
@onready var _content_host: VBoxContainer = $Layout/Body/Split/Right/ContentHost
@onready var _log: Label = $Layout/Body/Split/Right/Log

var _context: UiContext
var _art_frame: PanelContainer

var _building_ids: PackedStringArray = PackedStringArray()
var _suppress_building_select: bool = false

var _selected_commodity_id: String = ""
var _market_commodity_ids: PackedStringArray = PackedStringArray()
var _market_listings: Array[Dictionary] = []
var _commodity_item_list: ItemList
var _suppress_commodity_select: bool = false

var _selected_terminal_ship_id: String = ""
var _terminal_ship_ids: PackedStringArray = PackedStringArray()
var _terminal_ship_item_list: ItemList
var _suppress_terminal_ship_select: bool = false


func _ready() -> void:
	$Layout/Footer/SaveButton.pressed.connect(_on_save_pressed)
	$Layout/Footer/MenuButton.pressed.connect(_on_menu_pressed)
	_building_item_list.item_selected.connect(_on_building_item_selected)
	_building_item_list.item_clicked.connect(_on_building_item_clicked)


func bind(context: UiContext) -> void:
	_context = context
	if _context.session != null and not _context.session.changed.is_connected(refresh):
		_context.session.changed.connect(refresh)
	_refresh_when_ready()


func _refresh_when_ready() -> void:
	if is_node_ready():
		refresh()
	else:
		if not ready.is_connected(refresh):
			ready.connect(refresh, CONNECT_ONE_SHOT)


func refresh() -> void:
	if not is_node_ready() or _context == null or _context.session == null or _context.catalog == null:
		return

	var habitat := _context.session.get_current_habitat(_context.catalog)
	var building := _context.session.get_current_building(_context.catalog)
	if habitat.is_empty():
		return

	_title.text = str(habitat.get("name", "Habitat"))
	var habitat_desc := str(habitat.get("description", habitat.get("short_desc", "")))
	_description.text = habitat_desc
	_pilot.text = 'Pilot: %s "%s"' % [_context.session.player_name, _context.session.callsign]
	_credits.text = "Credits: d%d" % _context.session.credits
	_log.text = _context.session.last_log

	_rebuild_building_list(habitat)
	_update_art(habitat, building)
	_rebuild_content(building)


func handle_back() -> bool:
	if _context != null and _context.stack.get_depth() > 1:
		_context.stack.pop_screen()
		return true
	return false


func _rebuild_building_list(habitat: Dictionary) -> void:
	_building_ids.clear()
	_building_item_list.clear()

	var building_ids: Variant = habitat.get("buildings", [])
	if typeof(building_ids) != TYPE_ARRAY:
		return

	for building_id_variant in building_ids:
		var building_id := str(building_id_variant)
		var building := _context.catalog.get_building(building_id)
		if building.is_empty():
			continue
		_building_ids.append(building_id)
		_building_item_list.add_item(str(building.get("name", building_id)))

	_select_item_by_id(_building_item_list, _building_ids, _context.session.building_id, "_suppress_building_select")


func _on_building_item_selected(index: int) -> void:
	_select_building_at_index(index)


func _on_building_item_clicked(index: int, _at_position: Vector2, _mouse_button_index: int) -> void:
	_select_building_at_index(index)


func _select_building_at_index(index: int) -> void:
	if _suppress_building_select:
		return
	if index < 0 or index >= _building_ids.size():
		return
	var building_id := _building_ids[index]
	if building_id == _context.session.building_id:
		return
	var was_connected := _context.session.changed.is_connected(refresh)
	if was_connected:
		_context.session.changed.disconnect(refresh)
	var visited := _context.session.visit(_context.catalog, building_id)
	if was_connected and not _context.session.changed.is_connected(refresh):
		_context.session.changed.connect(refresh)
	if not visited:
		return
	_selected_commodity_id = ""
	_selected_terminal_ship_id = ""
	_update_building_panels()


func _update_building_panels() -> void:
	if _context == null or _context.session == null or _context.catalog == null:
		return
	var habitat := _context.session.get_current_habitat(_context.catalog)
	var building := _context.session.get_current_building(_context.catalog)
	if habitat.is_empty():
		return
	_log.text = _context.session.last_log
	_select_item_by_id(_building_item_list, _building_ids, _context.session.building_id, "_suppress_building_select")
	_update_art(habitat, building)
	_rebuild_content(building)


func _update_art(habitat: Dictionary, building: Dictionary) -> void:
	if _art_frame == null:
		_art_frame = LOCATION_ART.instantiate()
		_art_host.add_child(_art_frame)

	var art_path := _context.catalog.get_building_art(building)
	var label := str(building.get("name", ""))
	if art_path.is_empty():
		art_path = _context.catalog.get_habitat_art(habitat)
		label = str(habitat.get("name", ""))
	_art_frame.set_art_path(art_path, label)


func _rebuild_content(building: Dictionary) -> void:
	_clear_children(_content_host)

	_commodity_item_list = null
	_terminal_ship_item_list = null

	if building.is_empty():
		return

	var building_type := _context.catalog.get_building_type(building)
	var name_label := _headline_label(str(building.get("name", "")))
	_content_host.add_child(name_label)

	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.text = _context.catalog.get_building_description(building)
	_content_host.add_child(desc)

	match building_type:
		"market":
			_build_market_content(building)
		"shipyard":
			_build_shipyard_overview(building)
		"terminal":
			_build_terminal_content(building)
		_:
			pass


func _build_market_content(building: Dictionary) -> void:
	var market := _context.catalog.get_market_for_building(str(building.get("id", "")))
	if market.is_empty():
		var empty := Label.new()
		empty.text = "No market listings available."
		_content_host.add_child(empty)
		return

	_market_commodity_ids.clear()
	_market_listings.clear()

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_host.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(320, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	split.add_child(left)

	left.add_child(_section_label("EXCHANGE LISTINGS"))

	_commodity_item_list = ItemList.new()
	_commodity_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_commodity_item_list.select_mode = ItemList.SELECT_SINGLE
	_commodity_item_list.allow_reselect = true
	_commodity_item_list.item_selected.connect(_on_commodity_item_selected)
	left.add_child(_commodity_item_list)

	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	split.add_child(detail)
	detail.set_meta("detail_host", true)

	var listings: Variant = market.get("listings", [])
	if typeof(listings) != TYPE_ARRAY:
		return

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
			"%s · d%d · store %d" % [
				str(commodity.get("name", commodity_id)),
				price,
				int(listing.get("quantity", 0)),
			]
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
	for child in _content_host.get_children():
		if child is HSplitContainer:
			for panel in child.get_children():
				if panel.has_meta("detail_host"):
					_rebuild_commodity_detail(panel as VBoxContainer)
					return


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
	var cargo_qty := _context.session.get_cargo_count(_selected_commodity_id)

	detail.add_child(_headline_label(str(commodity.get("name", _selected_commodity_id))))

	var desc_text := str(commodity.get("description", ""))
	if not desc_text.is_empty():
		var desc := Label.new()
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.text = desc_text
		detail.add_child(desc)

	detail.add_child(_detail_row("Price", "d%d" % price))
	detail.add_child(_detail_row("Store stock", str(store_qty)))
	detail.add_child(_detail_row("Your cargo", str(cargo_qty)))

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


func _build_terminal_content(_building: Dictionary) -> void:
	var ships := _context.session.ships_at(_context.session.habitat_id)
	if ships.is_empty():
		var empty := Label.new()
		empty.text = "No ships docked at this habitat."
		_content_host.add_child(empty)
		return

	_terminal_ship_ids.clear()

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_host.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	split.add_child(left)

	left.add_child(_section_label("DOCKED SHIPS"))

	_terminal_ship_item_list = ItemList.new()
	_terminal_ship_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_terminal_ship_item_list.select_mode = ItemList.SELECT_SINGLE
	_terminal_ship_item_list.allow_reselect = true
	_terminal_ship_item_list.item_selected.connect(_on_terminal_ship_item_selected)
	left.add_child(_terminal_ship_item_list)

	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	split.add_child(detail)
	detail.set_meta("terminal_detail_host", true)

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
	_rebuild_terminal_ship_detail(detail)


func _on_terminal_ship_item_selected(index: int) -> void:
	if _suppress_terminal_ship_select:
		return
	if index < 0 or index >= _terminal_ship_ids.size():
		return
	_selected_terminal_ship_id = _terminal_ship_ids[index]
	for child in _content_host.get_children():
		if child is HSplitContainer:
			for panel in child.get_children():
				if panel.has_meta("terminal_detail_host"):
					_rebuild_terminal_ship_detail(panel as VBoxContainer)
					return


func _rebuild_terminal_ship_detail(detail: VBoxContainer) -> void:
	_clear_children(detail)

	if _selected_terminal_ship_id.is_empty():
		return

	var ship := _context.session.get_owned_ship(_selected_terminal_ship_id)
	if ship == null:
		return

	var assembled := ShipAssembly.preview_stats(_context.catalog, ship)
	var stats := ShipAssembly.get_stat_block(_context.catalog, ship)
	var chassis := _context.catalog.get_chassis(ship.chassis_id)

	var art_host := VBoxContainer.new()
	detail.add_child(art_host)
	var art := LOCATION_ART.instantiate()
	art_host.add_child(art)
	var sprite_path := str(chassis.get("sprite", ""))
	art.set_art_path(sprite_path, ship.name)

	detail.add_child(_headline_label(ship.name))

	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = assembled.get_summary()
	detail.add_child(summary)

	detail.add_child(_detail_row("Chassis", str(assembled.chassis.get("name", ship.chassis_id))))
	detail.add_child(_detail_row("Engine", str(assembled.engine.get("name", ship.engine_id))))

	var armour_text := "None"
	if not ship.armour_id.is_empty():
		armour_text = str(assembled.armour.get("name", ship.armour_id))
	detail.add_child(_detail_row("Armour", armour_text))

	if not stats.is_empty():
		detail.add_child(_section_label("STATS"))
		for key in ["mass", "thrust", "max_speed", "boost_max_speed", "maneuver", "armour_hits"]:
			if stats.has(key):
				detail.add_child(_detail_row(key, str(stats[key])))

	var undock := Button.new()
	undock.text = "Undock"
	undock.pressed.connect(_on_undock_ship.bind(ship.id))
	detail.add_child(undock)


func _build_shipyard_overview(_building: Dictionary) -> void:
	var ships := _context.session.ships_at(_context.session.habitat_id)
	var ship_label := Label.new()
	if ships.is_empty():
		ship_label.text = "No ships docked at this habitat."
	else:
		var names: PackedStringArray = PackedStringArray()
		for ship in ships:
			names.append(ship.name)
		ship_label.text = "Docked ships: %s" % ", ".join(names)
	ship_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_host.add_child(ship_label)

	var open := Button.new()
	open.text = "Open Assembly"
	open.pressed.connect(_on_open_shipyard)
	_content_host.add_child(open)


func _on_buy_commodity(commodity_id: String) -> void:
	if _context.session.buy_commodity(_context.catalog, _context.session.building_id, commodity_id):
		_selected_commodity_id = commodity_id
		refresh()


func _on_sell_commodity(commodity_id: String) -> void:
	if _context.session.sell_commodity(_context.catalog, _context.session.building_id, commodity_id):
		_selected_commodity_id = commodity_id
		refresh()


func _on_open_shipyard() -> void:
	var screen := SHIPYARD_SCREEN.instantiate()
	_context.stack.push_screen(screen)
	screen.bind(_context)


func _on_undock_ship(ship_id: String) -> void:
	if _context.on_undock_requested.is_valid():
		_context.on_undock_requested.call(ship_id)


func _on_save_pressed() -> void:
	if _context.on_save_requested.is_valid():
		_context.on_save_requested.call()


func _on_menu_pressed() -> void:
	if _context.on_quit_to_menu_requested.is_valid():
		_context.on_quit_to_menu_requested.call()


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()


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


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if handle_back():
			get_viewport().set_input_as_handled()
