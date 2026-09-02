extends Control

const LOCATION_ART := preload("res://scenes/ui/components/location_art.tscn")

@onready var _title: Label = $Layout/Header/HeaderBox/Title
@onready var _credits: Label = $Layout/Header/HeaderBox/Credits
@onready var _ship_list: VBoxContainer = $Layout/Body/Split/Left/ShipList
@onready var _ship_detail: VBoxContainer = $Layout/Body/Split/Left/ShipDetail
@onready var _parts_list: VBoxContainer = $Layout/Body/Split/Right/PartsList
@onready var _part_detail: VBoxContainer = $Layout/Body/Split/Right/PartDetail
@onready var _actions: HBoxContainer = $Layout/Body/Split/Right/Actions
@onready var _log: Label = $Layout/Footer/FooterBox/Log

var _context: UiContext
var _selected_ship_id: String = ""
var _selected_part_id: String = ""
var _selected_part_category: String = ""


func _ready() -> void:
	$Layout/Footer/FooterBox/BackButton.pressed.connect(_on_back_pressed)
	$Layout/Body/Split/Right/Actions/BuyButton.pressed.connect(_on_buy_pressed)
	$Layout/Body/Split/Right/Actions/SellButton.pressed.connect(_on_sell_pressed)
	$Layout/Body/Split/Right/Actions/InstallButton.pressed.connect(_on_install_pressed)
	$Layout/Body/Split/Right/Actions/RemoveButton.pressed.connect(_on_remove_pressed)


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
	if not is_node_ready() or _context == null:
		return

	var building := _context.session.get_current_building(_context.catalog)
	_title.text = str(building.get("name", "Shipyard"))

	var art_host: VBoxContainer = $Layout/Header/HeaderBox/ArtHost
	if art_host.get_child_count() == 0:
		var art := LOCATION_ART.instantiate()
		art_host.add_child(art)
		art.set_art_path(_context.catalog.get_building_art(building), str(building.get("name", "")))

	_credits.text = "Credits: d%d" % _context.session.credits
	_log.text = _context.session.last_log
	_rebuild_ship_list()
	_rebuild_ship_detail()
	_rebuild_parts_list()
	_rebuild_part_detail()
	_update_actions()


func handle_back() -> bool:
	_on_back_pressed()
	return true


func _rebuild_ship_list() -> void:
	for child in _ship_list.get_children():
		child.queue_free()

	var ships := _context.session.ships_at(_context.session.habitat_id)
	if _selected_ship_id.is_empty() and not ships.is_empty():
		_selected_ship_id = ships[0].id

	var heading := _section_label("DOCKED SHIPS")
	_ship_list.add_child(heading)

	for ship in ships:
		var button := Button.new()
		var prefix := "> " if ship.id == _selected_ship_id else ""
		button.text = "%s%s" % [prefix, ship.name]
		button.pressed.connect(_on_ship_selected.bind(ship.id))
		_ship_list.add_child(button)


func _rebuild_ship_detail() -> void:
	for child in _ship_detail.get_children():
		child.queue_free()

	var ship := _context.session.get_owned_ship(_selected_ship_id)
	if ship == null:
		return

	var assembled := ShipAssembly.preview_stats(_context.catalog, ship)
	var stats := ShipAssembly.get_stat_block(_context.catalog, ship)

	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = assembled.get_summary()
	_ship_detail.add_child(summary)

	var chassis := Label.new()
	chassis.text = "Chassis (fixed): %s" % str(assembled.chassis.get("name", ship.chassis_id))
	chassis.theme_type_variation = &"Numeric"
	_ship_detail.add_child(chassis)

	var engine := Label.new()
	engine.text = "Engine: %s" % str(assembled.engine.get("name", ship.engine_id))
	_ship_detail.add_child(engine)

	var armour_text := "None"
	if not ship.armour_id.is_empty():
		armour_text = str(assembled.armour.get("name", ship.armour_id))
	var armour := Label.new()
	armour.text = "Armour: %s" % armour_text
	_ship_detail.add_child(armour)

	if not stats.is_empty():
		var stats_heading := _section_label("STATS")
		_ship_detail.add_child(stats_heading)

		for key in ["mass", "thrust", "max_speed", "boost_max_speed", "maneuver", "armour_hits"]:
			if stats.has(key):
				var row := Label.new()
				row.text = "%s: %s" % [key, str(stats[key])]
				_ship_detail.add_child(row)


func _rebuild_parts_list() -> void:
	for child in _parts_list.get_children():
		child.queue_free()

	var heading := _section_label("YARD STOCK / INVENTORY")
	_parts_list.add_child(heading)

	for part_entry in ShipAssembly.list_yard_parts(_context.catalog):
		var part_id := str(part_entry.get("id", ""))
		var category := str(part_entry.get("category", ""))
		var data: Dictionary = part_entry.get("data", {})
		var spare := _context.session.get_spare_part_count(part_id)
		var button := Button.new()
		var prefix := "> " if part_id == _selected_part_id else ""
		button.text = "%s%s (d%d) x%d spare" % [
			prefix,
			str(data.get("name", part_id)),
			int(data.get("cost", 0)),
			spare,
		]
		button.pressed.connect(_on_part_selected.bind(part_id, category))
		_parts_list.add_child(button)


func _rebuild_part_detail() -> void:
	for child in _part_detail.get_children():
		child.queue_free()

	if _selected_part_id.is_empty():
		return

	var part := ShipAssembly.get_part_def(_context.catalog, _selected_part_id, _selected_part_category)
	if part.is_empty():
		return

	var name_label := _headline_label(str(part.get("name", _selected_part_id)))
	_part_detail.add_child(name_label)

	var category := Label.new()
	category.text = "Category: %s" % _selected_part_category
	_part_detail.add_child(category)

	var mass := Label.new()
	mass.text = "Mass: %s t" % str(part.get("mass", "?"))
	_part_detail.add_child(mass)

	var cost := Label.new()
	cost.text = "Cost: d%d" % int(part.get("cost", 0))
	_part_detail.add_child(cost)

	var desc := str(part.get("description", ""))
	if not desc.is_empty():
		var desc_label := Label.new()
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.text = desc
		_part_detail.add_child(desc_label)


func _update_actions() -> void:
	var buy := $Layout/Body/Split/Right/Actions/BuyButton
	var sell := $Layout/Body/Split/Right/Actions/SellButton
	var install := $Layout/Body/Split/Right/Actions/InstallButton
	var remove := $Layout/Body/Split/Right/Actions/RemoveButton

	buy.disabled = _selected_part_id.is_empty()
	sell.disabled = _selected_part_id.is_empty() or _context.session.get_spare_part_count(_selected_part_id) <= 0
	install.disabled = _selected_ship_id.is_empty() or _selected_part_id.is_empty() or _context.session.get_spare_part_count(_selected_part_id) <= 0
	remove.disabled = _selected_ship_id.is_empty()

	var ship := _context.session.get_owned_ship(_selected_ship_id)
	remove.disabled = ship == null or ship.armour_id.is_empty()


func _on_ship_selected(ship_id: String) -> void:
	_selected_ship_id = ship_id
	refresh()


func _on_part_selected(part_id: String, category: String) -> void:
	_selected_part_id = part_id
	_selected_part_category = category
	refresh()


func _on_buy_pressed() -> void:
	if ShipAssembly.buy_part(_context.session, _context.catalog, _selected_part_id, _selected_part_category):
		refresh()


func _on_sell_pressed() -> void:
	if ShipAssembly.sell_part(_context.session, _context.catalog, _selected_part_id, _selected_part_category):
		refresh()


func _on_install_pressed() -> void:
	if ShipAssembly.install_part(
		_context.session,
		_context.catalog,
		_selected_ship_id,
		_selected_part_category,
		_selected_part_id
	):
		if _context.on_ship_changed.is_valid():
			_context.on_ship_changed.call(_selected_ship_id)
		refresh()


func _on_remove_pressed() -> void:
	if ShipAssembly.remove_part(_context.session, _context.catalog, _selected_ship_id, "armour"):
		if _context.on_ship_changed.is_valid():
			_context.on_ship_changed.call(_selected_ship_id)
		refresh()


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


func _on_back_pressed() -> void:
	_context.stack.pop_screen()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
