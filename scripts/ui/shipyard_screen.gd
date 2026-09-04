extends Control

const LOCATION_ART := preload("res://scenes/ui/components/location_art.tscn")
const MODULE_SLOT := preload("res://scenes/ui/components/module_slot.tscn")
const MODULE_STOCK_ITEM := preload("res://scenes/ui/components/module_stock_item.tscn")
const INVENTORY_DROP_TARGET := preload("res://scripts/ui/components/inventory_drop_target.gd")

const STOCK_CATEGORIES := [
	"propulsion",
	"power",
	"computer",
	"life_support",
	"thermal",
	"sensor",
	"weapon",
	"armour",
	"cargo",
	"fuel",
	"ammunition",
]

const SLOT_GROUPS := [
	{"label": "Propulsion", "prefixes": ["main_engine", "maneuver"]},
	{"label": "Power", "prefixes": ["power"]},
	{"label": "Systems", "prefixes": ["system"]},
	{"label": "Weapons", "prefixes": ["light_weapon", "medium_weapon", "heavy_weapon"]},
	{"label": "Utilities", "prefixes": ["utility"]},
	{"label": "Internal", "prefixes": ["internal"]},
]

@onready var _header: PanelContainer = $Layout/Header
@onready var _title: Label = $Layout/Header/HeaderBox/Title
@onready var _credits: Label = $Layout/Header/HeaderBox/Credits
@onready var _back_button: Button = $Layout/Footer/FooterBox/BackButton
@onready var _ship_item_list: ItemList = $Layout/Body/Split/ShipColumn/ShipItemList
@onready var _ship_art_host: VBoxContainer = $Layout/Body/Split/ShipColumn/ShipInfoScroll/ShipInfo/ShipArtHost
@onready var _ship_stats_body: VBoxContainer = $Layout/Body/Split/ShipColumn/ShipInfoScroll/ShipInfo/ShipStatsBody
@onready var _config_body: VBoxContainer = $Layout/Body/Split/ConfigColumn/ConfigScroll/ConfigBody
@onready var _inventory_column = $Layout/Body/Split/InventoryColumn
@onready var _stock_tabs: TabContainer = $Layout/Body/Split/InventoryColumn/StockTabs
@onready var _log: Label = $Layout/Footer/FooterBox/Log

var _context: UiContext
var _embedded := false
var _sandbox := false
var _selected_ship_id: String = ""
var _selected_part_id: String = ""
var _selected_slot: String = ""
var _selected_stock_tab: int = 0
var _ship_ids: PackedStringArray = PackedStringArray()
var _suppress_ship_select: bool = false
var _ship_art_frame: PanelContainer
var _refresh_pending := false


func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	$Layout/Body/Split/InventoryColumn/Actions/BuyButton.pressed.connect(_on_buy_pressed)
	$Layout/Body/Split/InventoryColumn/Actions/SellButton.pressed.connect(_on_sell_pressed)
	$Layout/Body/Split/InventoryColumn/Actions/RefuelButton.pressed.connect(_on_refuel_pressed)
	_ship_item_list.item_selected.connect(_on_ship_item_selected)
	_ship_item_list.item_clicked.connect(_on_ship_item_clicked)
	_bind_inventory_drop_target(_inventory_column)
	_bind_inventory_drop_target(_stock_tabs)
	_apply_sandbox_chrome()


func configure_embedded(enabled: bool) -> void:
	_embedded = enabled
	if is_node_ready():
		_apply_embedded_chrome()
	else:
		if not ready.is_connected(_apply_embedded_chrome):
			ready.connect(_apply_embedded_chrome, CONNECT_ONE_SHOT)


func configure_sandbox(enabled: bool) -> void:
	_sandbox = enabled
	if is_node_ready():
		_apply_sandbox_chrome()
	else:
		if not ready.is_connected(_apply_sandbox_chrome):
			ready.connect(_apply_sandbox_chrome, CONNECT_ONE_SHOT)


func _apply_sandbox_chrome() -> void:
	var buy := $Layout/Body/Split/InventoryColumn/Actions/BuyButton
	var sell := $Layout/Body/Split/InventoryColumn/Actions/SellButton
	buy.visible = not _sandbox
	sell.visible = not _sandbox


func _apply_embedded_chrome() -> void:
	_header.visible = not _embedded
	_back_button.visible = not _embedded


func bind(context: UiContext) -> void:
	_context = context
	if _context.session != null and not _context.session.changed.is_connected(_request_refresh):
		_context.session.changed.connect(_request_refresh)
	_refresh_when_ready()


func _request_refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_run_deferred_refresh")


func _run_deferred_refresh() -> void:
	_refresh_pending = false
	refresh()


func _refresh_when_ready() -> void:
	if is_node_ready():
		refresh()
	else:
		if not ready.is_connected(refresh):
			ready.connect(refresh, CONNECT_ONE_SHOT)


func refresh() -> void:
	if not is_node_ready() or _context == null:
		return

	if _stock_tabs.get_tab_count() > 0:
		_selected_stock_tab = _stock_tabs.current_tab

	if not _embedded:
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
	_rebuild_stock_tabs()
	_update_actions()


func handle_back() -> bool:
	if _embedded:
		return false
	_on_back_pressed()
	return true


func get_selected_ship_id() -> String:
	return _selected_ship_id


func _rebuild_ship_list() -> void:
	_ship_ids.clear()
	_ship_item_list.clear()

	var ships := _context.session.ships_at(_context.session.habitat_id)
	if _selected_ship_id.is_empty() and not ships.is_empty():
		_selected_ship_id = ships[0].id

	for ship in ships:
		_ship_ids.append(ship.id)
		_ship_item_list.add_item(ship.name)

	if not _ship_ids.has(_selected_ship_id):
		_selected_ship_id = _ship_ids[0] if not _ship_ids.is_empty() else ""

	_select_item_by_id(_ship_item_list, _ship_ids, _selected_ship_id)


func _on_ship_item_selected(index: int) -> void:
	_select_ship_at_index(index)


func _on_ship_item_clicked(index: int, _at_position: Vector2, _mouse_button_index: int) -> void:
	_select_ship_at_index(index)


func _select_ship_at_index(index: int) -> void:
	if _suppress_ship_select:
		return
	if index < 0 or index >= _ship_ids.size():
		return
	var ship_id := _ship_ids[index]
	if ship_id == _selected_ship_id:
		return
	_selected_ship_id = ship_id
	_selected_slot = ""
	_selected_part_id = ""
	_rebuild_ship_detail()
	_rebuild_stock_tabs()
	_update_actions()


func _rebuild_ship_detail() -> void:
	for child in _ship_art_host.get_children():
		child.queue_free()
	for child in _ship_stats_body.get_children():
		child.queue_free()
	for child in _config_body.get_children():
		child.queue_free()

	var ship := _context.session.get_owned_ship(_selected_ship_id)
	if ship == null:
		return

	var engineering := ShipAssembly.get_engineering_block(_context.catalog, ship)
	var stats: Dictionary = engineering.get("stats", {})
	var capacities: Dictionary = engineering.get("capacities", {})
	var envelope: Dictionary = engineering.get("envelope", {})
	var mounts: Dictionary = engineering.get("mounts", {})
	var assembled := ShipAssembly.preview_stats(_context.catalog, ship)
	var chassis_data := _context.catalog.get_chassis(ship.chassis_id)

	_ship_art_frame = LOCATION_ART.instantiate()
	_ship_art_host.add_child(_ship_art_frame)
	_ship_art_frame.set_art_path(str(chassis_data.get("sprite", "")), ship.name)

	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = assembled.get_summary()
	_ship_stats_body.add_child(summary)

	var chassis := Label.new()
	chassis.text = "Chassis (fixed): %s" % str(assembled.chassis.get("name", ship.chassis_id))
	chassis.theme_type_variation = &"Numeric"
	_ship_stats_body.add_child(chassis)

	_add_slot_board(ship)

	_ship_stats_body.add_child(_section_label("ENGINEERING"))
	_ship_stats_body.add_child(_detail_label(
		"MASS",
		"%.1f / %.1f t" % [float(envelope.get("dry_mass", 0.0)), float(envelope.get("mass_limit", 0.0))]
	))
	_ship_stats_body.add_child(_detail_label(
		"VOLUME",
		"%.1f / %.1f m³" % [float(envelope.get("volume_used", 0.0)), float(envelope.get("volume", 0.0))]
	))
	_ship_stats_body.add_child(_detail_label(
		"POWER",
		"%.0f / %.0f MW idle" % [float(engineering.get("idle_power_requested", 0.0)), float(engineering.get("idle_power_available", 0.0))]
	))
	_ship_stats_body.add_child(_detail_label(
		"COMPUTE",
		"%.0f / %.0f CU idle" % [float(engineering.get("idle_compute_demand", 0.0)), float(capacities.get("compute_capacity", 0.0))]
	))
	_ship_stats_body.add_child(_detail_label(
		"HEAT",
		"%.0f / %.0f HU/s" % [float(engineering.get("idle_heat_generation", 0.0)), float(capacities.get("heat_dissipation", 0.0))]
	))
	_ship_stats_body.add_child(_detail_label(
		"LIFE SUPPORT",
		"%.0f people" % float(capacities.get("life_support_capacity", 0.0))
	))
	_ship_stats_body.add_child(_detail_label(
		"CARGO",
		"%.0f t capacity" % float(capacities.get("cargo_capacity", 0.0))
	))
	_ship_stats_body.add_child(_detail_label(
		"FUEL",
		"%.0f / %.0f" % [ship.fuel_current, float(capacities.get("fuel_capacity", 0.0))]
	))

	for mount_type in ["light_weapon", "medium_weapon", "heavy_weapon"]:
		if mounts.has(mount_type):
			var usage: Dictionary = mounts[mount_type]
			var mount_label: String = mount_type.replace("_", " ").capitalize()
			_ship_stats_body.add_child(_detail_label(
				mount_label.to_upper(),
				"%d / %d" % [int(usage.get("used", 0)), int(usage.get("total", 0))]
			))

	if not stats.is_empty():
		_ship_stats_body.add_child(_section_label("FLIGHT"))
		for key in ["loaded_mass", "thrust", "max_speed", "boost_max_speed", "maneuver"]:
			if stats.has(key):
				_ship_stats_body.add_child(_detail_label(key, str(stats[key])))


func _slot_group_for(slot: String) -> String:
	var mount_type := ShipAssembler.slot_mount_type(slot)
	for group in SLOT_GROUPS:
		var prefixes: Array = group.get("prefixes", [])
		if prefixes.has(mount_type):
			return str(group.get("label", ""))
	return ""


func _add_slot_board(ship: OwnedShip) -> void:
	var visible_slots := ShipAssembler.list_visible_slots(_context.catalog, ship)
	var grouped: Dictionary = {}
	for slot in visible_slots:
		var slot_id := str(slot)
		var group_label := _slot_group_for(slot_id)
		if group_label.is_empty():
			continue
		if not grouped.has(group_label):
			grouped[group_label] = []
		grouped[group_label].append(slot_id)

	for group in SLOT_GROUPS:
		var label := str(group.get("label", ""))
		if not grouped.has(label):
			continue

		_config_body.add_child(_section_label(label.to_upper()))
		for slot_id in grouped[label]:
			var module_id := ship.get_module_id(slot_id)
			var module_name := "(empty)"
			if not module_id.is_empty():
				module_name = str(_context.catalog.get_module(module_id).get("name", module_id))

			var slot_panel := MODULE_SLOT.instantiate()
			var compatible := _selected_part_id if not _selected_part_id.is_empty() else ""
			slot_panel.configure(
				slot_id,
				module_id,
				module_name,
				ship.id,
				compatible,
				Callable(self, "_validate_slot_drop")
			)
			slot_panel.slot_clicked.connect(_on_slot_clicked)
			slot_panel.module_dropped.connect(_on_module_dropped_on_slot)
			_config_body.add_child(slot_panel)


func _validate_slot_drop(slot_id: String, data: Dictionary) -> bool:
	var ship := _context.session.get_owned_ship(_selected_ship_id)
	if ship == null:
		return false

	var spare := -1
	if not _sandbox and str(data.get("type", "")) == "stock":
		spare = _context.session.get_spare_part_count(str(data.get("module_id", "")))

	return ShipAssembly.can_drop_on_slot(_context.catalog, ship, slot_id, data, spare)


func _on_slot_clicked(slot_id: String) -> void:
	if not _selected_part_id.is_empty():
		var ship := _context.session.get_owned_ship(_selected_ship_id)
		if ship != null:
			var spare := -1 if _sandbox else _context.session.get_spare_part_count(_selected_part_id)
			var data := {"type": "stock", "module_id": _selected_part_id}
			if ShipAssembly.can_drop_on_slot(_context.catalog, ship, slot_id, data, spare):
				_on_module_dropped_on_slot(slot_id, data)
				return

	_selected_slot = slot_id
	_update_actions()


func _on_module_dropped_on_slot(slot_id: String, data: Dictionary) -> void:
	var drag_type := str(data.get("type", ""))
	var changed := false

	if drag_type == "stock":
		var part_id := str(data.get("module_id", ""))
		changed = ShipAssembly.install_module(
			_context.session,
			_context.catalog,
			_selected_ship_id,
			slot_id,
			part_id
		)
	elif drag_type == "slot":
		var from_slot := str(data.get("slot", ""))
		changed = ShipAssembly.relocate_module(
			_context.session,
			_context.catalog,
			_selected_ship_id,
			from_slot,
			slot_id
		)

	if changed:
		if _context.on_ship_changed.is_valid():
			_context.on_ship_changed.call(_selected_ship_id)
		_selected_slot = slot_id


func _on_module_dropped_on_stock(data: Dictionary) -> void:
	if str(data.get("type", "")) != "slot":
		return
	var from_slot := str(data.get("slot", ""))
	if from_slot.is_empty():
		return
	if ShipAssembly.remove_module(_context.session, _context.catalog, _selected_ship_id, from_slot):
		if _context.on_ship_changed.is_valid():
			_context.on_ship_changed.call(_selected_ship_id)
		if _selected_slot == from_slot:
			_selected_slot = ""


func _rebuild_stock_tabs() -> void:
	if _stock_tabs.get_tab_count() > 0:
		_selected_stock_tab = _stock_tabs.current_tab

	for child in _stock_tabs.get_children():
		_stock_tabs.remove_child(child)
		child.free()

	var parts_by_category: Dictionary = {}
	for category in STOCK_CATEGORIES:
		parts_by_category[category] = []

	for part_entry in ShipAssembly.list_yard_parts(_context.catalog):
		var part_id := str(part_entry.get("id", ""))
		var category := str(part_entry.get("category", ""))
		if not parts_by_category.has(category):
			parts_by_category[category] = []
		parts_by_category[category].append(part_entry)

	for category in STOCK_CATEGORIES:
		var entries: Array = parts_by_category.get(category, [])
		if entries.is_empty():
			continue

		var scroll := ScrollContainer.new()
		scroll.set_script(INVENTORY_DROP_TARGET)
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_stock_tabs.add_child(scroll)
		_bind_inventory_drop_target(scroll)

		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 4)
		scroll.add_child(list)

		for part_entry in entries:
			var part_id := str(part_entry.get("id", ""))
			var data: Dictionary = part_entry.get("data", {})
			var category_label := str(part_entry.get("category", data.get("category", "")))
			var spare := _context.session.get_spare_part_count(part_id)
			var row := MODULE_STOCK_ITEM.instantiate()
			row.configure(
				part_id,
				str(data.get("name", part_id)),
				int(data.get("cost", 0)),
				spare,
				part_id == _selected_part_id,
				_sandbox,
				category_label
			)
			row.stock_selected.connect(_on_part_selected)
			row.module_dropped_on_stock.connect(_on_module_dropped_on_stock)
			list.add_child(row)

		_stock_tabs.set_tab_title(_stock_tabs.get_tab_count() - 1, category.capitalize())

	if _stock_tabs.get_tab_count() > 0:
		_stock_tabs.current_tab = clampi(_selected_stock_tab, 0, _stock_tabs.get_tab_count() - 1)


func _refresh_part_selection() -> void:
	_rebuild_ship_detail()
	_update_stock_selection()
	_update_actions()


func _update_stock_selection() -> void:
	for tab_index in range(_stock_tabs.get_tab_count()):
		var scroll := _stock_tabs.get_tab_control(tab_index)
		if scroll == null:
			continue
		for list in scroll.get_children():
			if not list is VBoxContainer:
				continue
			for child in list.get_children():
				if not child is ModuleStockItem:
					continue
				var row: ModuleStockItem = child
				var is_selected := row.module_id == _selected_part_id
				if row.selected != is_selected:
					row.set_selected_state(is_selected)


func _bind_inventory_drop_target(node: Node) -> void:
	if not node.has_signal("module_dropped"):
		return
	if not node.module_dropped.is_connected(_on_module_dropped_on_stock):
		node.module_dropped.connect(_on_module_dropped_on_stock)


func _update_actions() -> void:
	var buy := $Layout/Body/Split/InventoryColumn/Actions/BuyButton
	var sell := $Layout/Body/Split/InventoryColumn/Actions/SellButton
	var refuel := $Layout/Body/Split/InventoryColumn/Actions/RefuelButton

	if not _sandbox:
		buy.disabled = _selected_part_id.is_empty()
		sell.disabled = _selected_part_id.is_empty() or _context.session.get_spare_part_count(_selected_part_id) <= 0

	var ship := _context.session.get_owned_ship(_selected_ship_id)
	refuel.disabled = ship == null


func _select_item_by_id(list: ItemList, ids: PackedStringArray, target_id: String) -> void:
	_suppress_ship_select = true
	var index := ids.find(target_id)
	if index >= 0:
		list.select(index)
	else:
		list.deselect_all()
	_suppress_ship_select = false


func _on_part_selected(part_id: String) -> void:
	if part_id == _selected_part_id:
		return
	_selected_part_id = part_id
	if not _selected_ship_id.is_empty() and _selected_slot.is_empty():
		var ship := _context.session.get_owned_ship(_selected_ship_id)
		if ship != null:
			var slots := ShipAssembly.find_compatible_slots(_context.catalog, ship, part_id)
			if slots.size() == 1:
				_selected_slot = str(slots[0])
	_refresh_part_selection()


func _on_buy_pressed() -> void:
	ShipAssembly.buy_part(_context.session, _context.catalog, _selected_part_id)


func _on_sell_pressed() -> void:
	ShipAssembly.sell_part(_context.session, _context.catalog, _selected_part_id)


func _on_refuel_pressed() -> void:
	if ShipAssembly.refuel_ship(_context.session, _context.catalog, _selected_ship_id):
		if _context.on_ship_changed.is_valid():
			_context.on_ship_changed.call(_selected_ship_id)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Section"
	return label


func _detail_label(label_text: String, value_text: String) -> Label:
	var label := Label.new()
	label.text = "%s: %s" % [label_text, value_text]
	label.theme_type_variation = &"Numeric"
	return label


func _on_back_pressed() -> void:
	_context.stack.pop_screen()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _embedded:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
