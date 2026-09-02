extends Control

const LOCATION_ART := preload("res://scenes/ui/components/location_art.tscn")
const SHIPYARD_SCREEN := preload("res://scenes/ui/shipyard_screen.tscn")

@onready var _title: Label = $Layout/Header/HeaderBox/Title
@onready var _description: Label = $Layout/Header/HeaderBox/Description
@onready var _pilot: Label = $Layout/Header/HeaderBox/Pilot
@onready var _credits: Label = $Layout/Header/HeaderBox/Credits
@onready var _building_list: VBoxContainer = $Layout/Body/Split/Left/BuildingList
@onready var _art_host: VBoxContainer = $Layout/Body/Split/Right/ArtHost
@onready var _content_host: VBoxContainer = $Layout/Body/Split/Right/ContentHost
@onready var _log: Label = $Layout/Body/Split/Right/Log
@onready var _undock_picker: VBoxContainer = $Layout/UndockPicker

var _context: UiContext
var _art_frame: PanelContainer
var _undock_picker_visible: bool = false


func _ready() -> void:
	$Layout/Footer/BackButton.pressed.connect(_on_back_pressed)
	$Layout/Footer/SaveButton.pressed.connect(_on_save_pressed)
	$Layout/Footer/MenuButton.pressed.connect(_on_menu_pressed)
	_undock_picker.visible = false


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

	_rebuild_building_list(habitat, building)
	_update_art(habitat, building)
	_rebuild_content(building)
	_update_undock_picker()


func handle_back() -> bool:
	if _undock_picker_visible:
		_undock_picker_visible = false
		_undock_picker.visible = false
		refresh()
		return true
	if _context != null and _context.stack.get_depth() > 1:
		_context.stack.pop_screen()
		return true
	return false


func _rebuild_building_list(habitat: Dictionary, current_building: Dictionary) -> void:
	for child in _building_list.get_children():
		child.queue_free()

	var heading := _section_label("BUILDINGS")
	_building_list.add_child(heading)

	var current_id := str(current_building.get("id", ""))
	var building_ids: Variant = habitat.get("buildings", [])
	if typeof(building_ids) != TYPE_ARRAY:
		return

	for building_id_variant in building_ids:
		var building_id := str(building_id_variant)
		var building := _context.catalog.get_building(building_id)
		if building.is_empty():
			continue
		var button := Button.new()
		var prefix := "> " if building_id == current_id else ""
		button.text = "%s%s" % [prefix, str(building.get("name", building_id))]
		button.pressed.connect(_on_building_pressed.bind(building_id))
		_building_list.add_child(button)


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
	for child in _content_host.get_children():
		child.queue_free()

	if building.is_empty():
		return

	if _undock_picker_visible:
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
		_:
			pass


func _build_market_content(building: Dictionary) -> void:
	var market := _context.catalog.get_market_for_building(str(building.get("id", "")))
	if market.is_empty():
		var empty := Label.new()
		empty.text = "No market listings available."
		_content_host.add_child(empty)
		return

	var heading := _section_label("EXCHANGE LISTINGS")
	_content_host.add_child(heading)

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

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_content_host.add_child(row)

		var price := int(listing.get("price", commodity.get("base_price", 0)))
		var cargo_qty := _context.session.get_cargo_count(commodity_id)
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.text = "%s — d%d — store %d — cargo %d" % [
			str(commodity.get("name", commodity_id)),
			price,
			int(listing.get("quantity", 0)),
			cargo_qty,
		]
		row.add_child(info)

		var buy := Button.new()
		buy.text = "Buy 1"
		buy.pressed.connect(_on_buy_commodity.bind(commodity_id))
		row.add_child(buy)

		var sell := Button.new()
		sell.text = "Sell 1"
		sell.pressed.connect(_on_sell_commodity.bind(commodity_id))
		row.add_child(sell)


func _build_shipyard_overview(building: Dictionary) -> void:
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


func _update_undock_picker() -> void:
	for child in _undock_picker.get_children():
		child.queue_free()

	_undock_picker.visible = _undock_picker_visible
	if not _undock_picker_visible:
		return

	var heading := Label.new()
	heading.text = "Choose a ship to launch"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_undock_picker.add_child(heading)

	var ships := _context.session.ships_at(_context.session.habitat_id)
	for ship in ships:
		var button := Button.new()
		button.text = "Launch %s" % ship.name
		button.pressed.connect(_on_undock_ship.bind(ship.id))
		_undock_picker.add_child(button)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_on_undock_cancel)
	_undock_picker.add_child(cancel)


func _on_building_pressed(building_id: String) -> void:
	if _context.session.visit(_context.catalog, building_id):
		refresh()


func _on_buy_commodity(commodity_id: String) -> void:
	if _context.session.buy_commodity(_context.catalog, _context.session.building_id, commodity_id):
		refresh()


func _on_sell_commodity(commodity_id: String) -> void:
	if _context.session.sell_commodity(_context.catalog, _context.session.building_id, commodity_id):
		refresh()


func _on_open_shipyard() -> void:
	var screen := SHIPYARD_SCREEN.instantiate()
	_context.stack.push_screen(screen)
	screen.bind(_context)


func _on_back_pressed() -> void:
	if _undock_picker_visible:
		_on_undock_cancel()
		return
	_start_undock_flow()


func _start_undock_flow() -> void:
	var ships := _context.session.ships_at(_context.session.habitat_id)
	if ships.is_empty():
		return
	if ships.size() == 1:
		_on_undock_ship(ships[0].id)
		return
	_undock_picker_visible = true
	refresh()


func _on_undock_ship(ship_id: String) -> void:
	if _context.on_undock_requested.is_valid():
		_context.on_undock_requested.call(ship_id)


func _on_undock_cancel() -> void:
	_undock_picker_visible = false
	_undock_picker.visible = false
	refresh()


func _on_save_pressed() -> void:
	if _context.on_save_requested.is_valid():
		_context.on_save_requested.call()


func _on_menu_pressed() -> void:
	if _context.on_quit_to_menu_requested.is_valid():
		_context.on_quit_to_menu_requested.call()


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
		elif _context != null and _context.stack.get_depth() <= 1:
			_start_undock_flow()
			get_viewport().set_input_as_handled()
