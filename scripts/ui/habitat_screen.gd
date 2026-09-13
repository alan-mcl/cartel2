extends Control

const LOCATION_ART := preload("res://scenes/ui/components/location_art.tscn")

@onready var _title: Label = $Layout/Header/HeaderBox/Title
@onready var _description: Label = $Layout/Header/HeaderBox/Description
@onready var _portrait: TextureRect = $Layout/Header/HeaderBox/PilotRow/Portrait
@onready var _pilot: Label = $Layout/Header/HeaderBox/PilotRow/Pilot
@onready var _credits: Label = $Layout/Header/HeaderBox/Credits
@onready var _gst_clock: Label = $Layout/Header/HeaderBox/GstClockLabel
@onready var _building_item_list: ItemList = $Layout/Body/Split/Left/BuildingItemList
@onready var _building_title: Label = $Layout/Body/Split/Right/BuildingHeader/BuildingInfo/BuildingTitle
@onready var _building_description: Label = $Layout/Body/Split/Right/BuildingHeader/BuildingInfo/BuildingDescription
@onready var _art_host: VBoxContainer = $Layout/Body/Split/Right/BuildingHeader/ArtHost
@onready var _content_scroll: ScrollContainer = $Layout/Body/Split/Right/ContentScroll
@onready var _content_host: VBoxContainer = $Layout/Body/Split/Right/ContentScroll/ContentHost
@onready var _terminal_host: VBoxContainer = $Layout/Body/Split/Right/TerminalHost
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

var _selected_dealer_stock_id: String = ""
var _dealer_stock_ids: PackedStringArray = PackedStringArray()
var _dealer_item_list: ItemList
var _suppress_dealer_select: bool = false

var _show_rename_field: bool = false


func _ready() -> void:
	$Layout/Footer/SaveButton.pressed.connect(_on_save_pressed)
	$Layout/Footer/MenuButton.pressed.connect(_on_menu_pressed)
	_building_item_list.item_selected.connect(_on_building_item_selected)
	_building_item_list.item_clicked.connect(_on_building_item_clicked)


func bind(context: UiContext) -> void:
	_context = context
	if _context.session != null and not _context.session.changed.is_connected(refresh):
		_context.session.changed.connect(refresh, CONNECT_DEFERRED)
	if _gst_clock != null and _gst_clock.has_method("bind") and _context.session != null:
		_gst_clock.bind(_context.session)
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
	_pilot.text = 'Pilot: "%s"' % _context.session.callsign
	_update_portrait(_context.session.portrait_path)
	_credits.text = "Credits: d%d" % _context.session.credits
	_log.text = _context.session.last_log

	_rebuild_building_list(habitat)
	_update_building_header(habitat, building)
	_show_building_content(habitat, building)


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
		var index := _building_item_list.add_item(str(building.get("name", building_id)))
		_building_item_list.set_item_tooltip(index, str(building.get("short_desc", "")))

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
		_context.session.changed.connect(refresh, CONNECT_DEFERRED)
	if not visited:
		return
	_selected_commodity_id = ""
	_selected_terminal_ship_id = ""
	_selected_dealer_stock_id = ""
	_show_rename_field = false
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
	_update_building_header(habitat, building)
	_show_building_content(habitat, building)


func _update_building_header(habitat: Dictionary, building: Dictionary) -> void:
	if building.is_empty():
		_building_title.text = ""
		_building_description.text = ""
		return

	_building_title.text = str(building.get("name", ""))
	_building_description.text = _context.catalog.get_building_description(building)

	if _art_frame == null:
		_art_frame = LOCATION_ART.instantiate()
		_art_host.add_child(_art_frame)
	if _art_frame.has_method("configure_header_mode"):
		_art_frame.configure_header_mode(true)

	var art_path := _context.catalog.get_building_art(building)
	var label := str(building.get("name", ""))
	if art_path.is_empty():
		art_path = _context.catalog.get_habitat_art(habitat)
		label = str(habitat.get("name", ""))
	_art_frame.set_art_path(art_path, label)


func _show_building_content(habitat: Dictionary, building: Dictionary) -> void:
	var building_type := _context.catalog.get_building_type(building)
	match BuildingPanelRegistry.mode_for(building_type):
		BuildingPanelRegistry.MODE_STACK:
			_show_stack_panel(building_type)
		BuildingPanelRegistry.MODE_EMBED:
			_pop_stacked_panel_if_needed()
			if building_type == "terminal":
				_show_terminal_embedded(building)
			else:
				_hide_terminal_embedded()
				_content_scroll.visible = true
				_log.visible = true
				_rebuild_content(building)
		_:
			_pop_stacked_panel_if_needed()
			_hide_terminal_embedded()
			_content_scroll.visible = true
			_log.visible = true
			_show_placeholder_content(building)


func _rebuild_content(building: Dictionary) -> void:
	_clear_children(_content_host)

	_commodity_item_list = null
	_terminal_ship_item_list = null
	_dealer_item_list = null

	if building.is_empty():
		return

	var building_type := _context.catalog.get_building_type(building)
	match building_type:
		"market":
			_build_market_content(building)
		"ship_dealer":
			_build_ship_dealer_content(building)
		"chassis_dealer":
			_build_chassis_dealer_content(building)
		_:
			pass


func _show_stack_panel(building_type: String) -> void:
	_hide_terminal_embedded()
	_content_scroll.visible = false
	_log.visible = false

	if _context == null or _context.stack == null:
		return

	var scene_path := BuildingPanelRegistry.stack_scene_path(building_type)
	if scene_path.is_empty():
		return

	var top := _context.stack.get_top_screen()
	if top != null and top != self and _screen_matches_stack_scene(top, scene_path):
		if top.has_method("configure_embedded"):
			top.configure_embedded(false)
		if top.has_method("bind"):
			top.bind(_context)
		if top.has_method("refresh"):
			top.refresh()
		return

	_pop_stacked_panel_if_needed()

	var scene := BuildingPanelRegistry.stack_scene(building_type)
	if scene == null:
		return

	var panel: Control = scene.instantiate()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if panel.has_method("configure_embedded"):
		panel.configure_embedded(false)
	if panel.has_method("bind"):
		panel.bind(_context)
	_context.stack.push_screen(panel)


func _pop_stacked_panel_if_needed() -> void:
	if _context == null or _context.stack == null:
		return
	if _context.stack.get_depth() <= 1:
		return
	var top := _context.stack.get_top_screen()
	if top == null or top == self:
		return
	if _screen_is_any_stack_panel(top):
		_context.stack.pop_screen()


func _screen_is_any_stack_panel(screen: Control) -> bool:
	for building_type in BuildingPanelRegistry.stack_building_types():
		var path := BuildingPanelRegistry.stack_scene_path(str(building_type))
		if not path.is_empty() and _screen_matches_stack_scene(screen, path):
			return true
	return false


func _screen_matches_stack_scene(screen: Control, scene_path: String) -> bool:
	if screen.get_scene_file_path() == scene_path:
		return true
	var script: Variant = screen.get_script()
	if script != null and str(script.resource_path).ends_with("shipyard_screen.gd"):
		return scene_path.ends_with("shipyard_screen.tscn")
	return false


func _show_placeholder_content(building: Dictionary) -> void:
	_clear_children(_content_host)
	_commodity_item_list = null
	_terminal_ship_item_list = null
	_dealer_item_list = null

	if building.is_empty():
		return

	var name := str(building.get("name", "This location"))
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "%s — No services at this location yet." % name
	_content_host.add_child(label)


func _build_market_content(building: Dictionary) -> void:
	_context.session.refresh_market_quotes(_context.catalog)
	var listings := _context.session.get_sector_quote_listings(_context.catalog)
	if listings.is_empty():
		var empty := Label.new()
		empty.text = "No market listings available."
		_content_host.add_child(empty)
		return

	_market_commodity_ids.clear()
	_market_listings.clear()

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 320)
	_content_host.add_child(split)

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
			"%s · d%d · depth %d" % [
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
	var cargo_ship := _context.session.get_cargo_ship(_selected_terminal_ship_id)
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
	detail.add_child(_detail_row("Sell price", "d%d" % CommodityEconomy.sell_price(price)))
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


func _update_portrait(portrait_path: String) -> void:
	if _portrait == null:
		return
	if portrait_path.is_empty() or not ResourceLoader.exists(portrait_path):
		_portrait.texture = null
		_portrait.visible = false
		return
	var texture := load(portrait_path) as Texture2D
	_portrait.texture = texture
	_portrait.visible = texture != null


func _show_terminal_embedded(_building: Dictionary) -> void:
	_content_scroll.visible = false
	_terminal_host.visible = true
	_log.visible = true
	_clear_children(_terminal_host)
	_build_terminal_content(_building)


func _hide_terminal_embedded() -> void:
	_terminal_host.visible = false


func _build_terminal_content(_building: Dictionary) -> void:
	var ships := _context.session.ships_at(_context.session.habitat_id)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	_terminal_host.add_child(columns)

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
	detail.add_child(_detail_row("Chassis", str(assembled.chassis.get("name", ship.chassis_id))))

	detail.add_child(_section_label("MODULES"))
	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		var module_data: ModuleDef = entry.get("data", null)
		var module_name := module_data.name if module_data != null else str(entry.get("module_id", ""))
		detail.add_child(_detail_row(slot, module_name))

	if not stats.is_empty():
		detail.add_child(_section_label("STATS"))
		for key in ["dry_mass", "loaded_mass", "thrust", "max_speed", "boost_max_speed", "maneuver", "armour_hits"]:
			if stats.has(key):
				detail.add_child(_detail_row(key, str(stats[key])))

	var engineering := ShipAssembly.get_engineering_block(_context.catalog, ship)
	ModuleSpecText.append_ship_signature_rows(
		detail,
		engineering.get("signature", {}),
		str(engineering.get("transponder_label", "off"))
	)


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


func _on_buy_commodity(commodity_id: String) -> void:
	_selected_commodity_id = commodity_id
	_context.session.buy_commodity(
		_context.catalog,
		_context.session.building_id,
		commodity_id,
		1,
		_selected_terminal_ship_id
	)


func _on_sell_commodity(commodity_id: String) -> void:
	_selected_commodity_id = commodity_id
	_context.session.sell_commodity(
		_context.catalog,
		_context.session.building_id,
		commodity_id,
		1,
		_selected_terminal_ship_id
	)


func _build_ship_dealer_content(building: Dictionary) -> void:
	_dealer_stock_ids.clear()
	var stock: Variant = building.get("stock", [])
	if typeof(stock) != TYPE_ARRAY or stock.is_empty():
		var empty := Label.new()
		empty.text = "No ships in stock."
		_content_host.add_child(empty)
		return

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 320)
	_content_host.add_child(split)

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
	_rebuild_ship_dealer_detail(detail)


func _build_chassis_dealer_content(building: Dictionary) -> void:
	_dealer_stock_ids.clear()
	var stock: Variant = building.get("stock", [])
	if typeof(stock) != TYPE_ARRAY or stock.is_empty():
		var empty := Label.new()
		empty.text = "No chassis in stock."
		_content_host.add_child(empty)
		return

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 320)
	_content_host.add_child(split)

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
	_rebuild_chassis_dealer_detail(detail)


func _on_dealer_item_selected(index: int) -> void:
	if _suppress_dealer_select:
		return
	if index < 0 or index >= _dealer_stock_ids.size():
		return
	_selected_dealer_stock_id = _dealer_stock_ids[index]
	var detail := _find_meta_host("dealer_detail_host")
	if detail == null:
		return
	var building := _context.session.get_current_building(_context.catalog)
	var building_type := _context.catalog.get_building_type(building)
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
	var preview_ship := OwnedShip.from_template(_context.catalog, {
		"id": "preview",
		"name": str(template.get("name", _selected_dealer_stock_id)),
		"template_id": _selected_dealer_stock_id,
		"chassis_id": str(template.get("chassis", "")),
	})
	var assembled := ShipAssembly.preview_stats(_context.catalog, preview_ship)
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


func _on_undock_ship(ship_id: String) -> void:
	if _context.on_undock_requested.is_valid():
		_context.on_undock_requested.call(ship_id)


func _on_save_pressed() -> void:
	if _context.on_save_requested.is_valid():
		_context.on_save_requested.call()


func _on_menu_pressed() -> void:
	if _context.on_quit_to_menu_requested.is_valid():
		_context.on_quit_to_menu_requested.call()


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
	var found := _find_meta_host_in(_content_host, meta_name)
	if found != null:
		return found
	return _find_meta_host_in(_terminal_host, meta_name)


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


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if handle_back():
			get_viewport().set_input_as_handled()
