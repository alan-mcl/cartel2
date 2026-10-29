class_name ShipyardRefitScreen
extends GameScreen

const SHIP_DETAIL_PANEL := preload("res://scenes/ui/ship_detail_panel.tscn")

const _REFIT_ENGINEERING_OPTS := {
	"show_chassis_art": false,
	"show_summary": false,
	"show_engineering": true,
	"show_flight": false,
	"show_signature": false,
}
const MODULE_SLOT := preload("res://scenes/ui/components/module_slot.tscn")
const MODULE_STOCK_ITEM := preload("res://scenes/ui/components/module_stock_item.tscn")
const INVENTORY_DROP_TARGET := preload("res://scripts/ui/components/inventory_drop_target.gd")

const SORTABLE_STOCK_CATEGORIES := ["propulsion", "power", "computer", "life_support", "weapon", "armour", "shield"]

const STOCK_SORT_KEYS := {
	"propulsion": ["price", "type", "thrust"],
	"power": ["price", "type", "mw"],
	"computer": ["price", "type", "cu"],
	"life_support": ["price", "crew"],
	"weapon": ["price", "type", "damage"],
	"armour": ["price", "hits"],
	"shield": ["price", "type", "capacity"],
}

const STOCK_CATEGORIES := [
	"propulsion",
	"power",
	"computer",
	"navigation",
	"life_support",
	"sensor",
	"transponder",
	"hyperdrive",
	"weapon",
	"armour",
	"shield",
	"point_defence",
	"cyber_defence",
	"cargo",
	"fuel",
	"ammunition",
]

const SLOT_GROUPS := [
	{"label": "Propulsion", "prefixes": ["main_engine", "maneuver"]},
	{"label": "Power", "prefixes": ["power"]},
	{"label": "Systems", "prefixes": ["system"]},
	{"label": "Weapons", "prefixes": ["light_weapon", "medium_weapon", "heavy_weapon"]},
	{"label": "Other", "prefixes": ["other"]},
]

@onready var _ship_name: Label = $Layout/Header/HeaderBox/ShipName
@onready var _credits: Label = $Layout/Header/HeaderBox/Credits
@onready var _close_button: Button = $Layout/Footer/FooterBox/CloseButton
@onready var _config_body: VBoxContainer = $Layout/Body/Split/ConfigColumn/ConfigScroll/ConfigBody
@onready var _inventory_column = $Layout/Body/Split/InventoryColumn
@onready var _stock_tabs: TabContainer = $Layout/Body/Split/InventoryColumn/StockTabs
@onready var _log: Control = $Layout/Footer/FooterBox/Log
@onready var _footer: PanelContainer = $Layout/Footer

var _sandbox := false
var _ship_id: String = ""
var _selected_part_id: String = ""
var _selected_slot: String = ""
var _selected_stock_tab: int = 0
var _engineering_panel: VBoxContainer
var _refresh_pending := false
var _stock_sort: Dictionary = {
	"propulsion": {"key": "price", "asc": true},
	"power": {"key": "price", "asc": true},
	"computer": {"key": "price", "asc": true},
	"life_support": {"key": "price", "asc": true},
	"weapon": {"key": "price", "asc": true},
	"armour": {"key": "price", "asc": true},
	"shield": {"key": "price", "asc": true},
}


func _ready() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	$Layout/Body/Split/InventoryColumn/Actions/BuyButton.pressed.connect(_on_buy_pressed)
	$Layout/Body/Split/InventoryColumn/Actions/SellButton.pressed.connect(_on_sell_pressed)
	_bind_inventory_drop_target(_inventory_column)
	_bind_inventory_drop_target(_stock_tabs)
	_apply_sandbox_chrome()


func configure_sandbox(enabled: bool) -> void:
	_sandbox = enabled
	if is_node_ready():
		_apply_sandbox_chrome()
	else:
		if not ready.is_connected(_apply_sandbox_chrome):
			ready.connect(_apply_sandbox_chrome, CONNECT_ONE_SHOT)


func configure_embedded_in_host(enabled: bool) -> void:
	if is_node_ready():
		_apply_embedded_host_chrome(enabled)
	else:
		ready.connect(func() -> void:
			_apply_embedded_host_chrome(enabled)
		, CONNECT_ONE_SHOT)


func _apply_embedded_host_chrome(enabled: bool) -> void:
	_footer.visible = not enabled
	_close_button.visible = not enabled


func _apply_sandbox_chrome() -> void:
	var buy := $Layout/Body/Split/InventoryColumn/Actions/BuyButton
	var sell := $Layout/Body/Split/InventoryColumn/Actions/SellButton
	buy.visible = not _sandbox
	sell.visible = not _sandbox


func set_ship_id(ship_id: String) -> void:
	if ship_id == _ship_id:
		return
	_ship_id = ship_id
	_selected_slot = ""
	_selected_part_id = ""
	if is_node_ready() and _context != null:
		refresh()


func get_ship_id() -> String:
	return _ship_id


func session_changed() -> void:
	_request_refresh()


func _request_refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_run_deferred_refresh")


func _run_deferred_refresh() -> void:
	_refresh_pending = false
	refresh()


func refresh() -> void:
	if not is_node_ready() or _context == null:
		return
	if _ship_id.is_empty():
		return
	if _can_soft_refresh():
		_soft_refresh()
		return
	_full_refresh()


func _can_soft_refresh() -> bool:
	return _stock_tabs.get_tab_count() > 0


func _soft_refresh() -> void:
	_credits.text = "Credits: d%d" % _context.session.credits
	_sync_log()
	_sync_stock_spare_counts()
	_rebuild_configuration()
	_update_actions()


func _full_refresh() -> void:
	if _stock_tabs.get_tab_count() > 0:
		_selected_stock_tab = _stock_tabs.current_tab

	var ship := _context.session.get_owned_ship(_ship_id)
	if ship != null:
		_ship_name.text = ship.name
	else:
		_ship_name.text = ""

	_credits.text = "Credits: d%d" % _context.session.credits
	_sync_log()
	_rebuild_configuration()
	_rebuild_stock_tabs()
	_update_actions()


func _sync_log() -> void:
	var bar := _log as MessageBar
	if bar == null or _context == null or _context.session == null:
		return
	bar.play_line(_context.session.last_log)


func _sync_stock_spare_counts() -> void:
	if _sandbox or _stock_tabs == null or _context == null:
		return
	for tab_index in range(_stock_tabs.get_tab_count()):
		var tab_root := _stock_tabs.get_tab_control(tab_index)
		if tab_root == null:
			continue
		_for_each_stock_row(tab_root, func(row: ModuleStockItem) -> void:
			if row.sandbox_mode:
				return
			row.set_spare_count(_context.session.get_spare_part_count(row.module_id))
		)


func _rebuild_configuration() -> void:
	for child in _config_body.get_children():
		child.queue_free()

	var ship := _context.session.get_owned_ship(_ship_id)
	if ship == null:
		_engineering_panel = null
		return

	if _engineering_panel == null or not is_instance_valid(_engineering_panel):
		_engineering_panel = SHIP_DETAIL_PANEL.instantiate()
		_config_body.add_child(_engineering_panel)

	_engineering_panel.configure(_REFIT_ENGINEERING_OPTS)
	_engineering_panel.bind_ship(_context.catalog, ship)
	_engineering_panel.refresh()

	_add_slot_board(ship)


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
			var slot_tooltip := ""
			var module_category := ""
			if not module_id.is_empty():
				var module_def := _context.catalog.get_module_def(module_id)
				if module_def != null:
					module_name = module_def.name if module_def.has_source_key("name") else module_id
					slot_tooltip = ModuleSpecText.format_tooltip(module_def.to_dict())
					module_category = module_def.category
				else:
					module_name = module_id

			var slot_panel := MODULE_SLOT.instantiate()
			var compatible := _selected_part_id if not _selected_part_id.is_empty() else ""
			slot_panel.configure(
				slot_id,
				module_id,
				module_name,
				ship.id,
				compatible,
				Callable(self, "_validate_slot_drop"),
				slot_tooltip,
				module_category
			)
			slot_panel.slot_clicked.connect(_on_slot_clicked)
			slot_panel.module_dropped.connect(_on_module_dropped_on_slot)
			_config_body.add_child(slot_panel)


func _validate_slot_drop(slot_id: String, data: Dictionary) -> bool:
	var ship := _context.session.get_owned_ship(_ship_id)
	if ship == null:
		return false

	var spare := -1
	if not _sandbox and str(data.get("type", "")) == "stock":
		spare = _context.session.get_spare_part_count(str(data.get("module_id", "")))

	return ShipAssembly.can_drop_on_slot(_context.catalog, ship, slot_id, data, spare)


func _on_slot_clicked(slot_id: String) -> void:
	if not _selected_part_id.is_empty():
		var ship := _context.session.get_owned_ship(_ship_id)
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
			_ship_id,
			slot_id,
			part_id
		)
	elif drag_type == "slot":
		var from_slot := str(data.get("slot", ""))
		changed = ShipAssembly.relocate_module(
			_context.session,
			_context.catalog,
			_ship_id,
			from_slot,
			slot_id
		)

	if changed:
		if _context.on_ship_changed.is_valid():
			_context.on_ship_changed.call(_ship_id)
		_selected_slot = slot_id


func _on_module_dropped_on_stock(data: Dictionary) -> void:
	if str(data.get("type", "")) != "slot":
		return
	var from_slot := str(data.get("slot", ""))
	if from_slot.is_empty():
		return
	if ShipAssembly.remove_module(_context.session, _context.catalog, _ship_id, from_slot):
		if _context.on_ship_changed.is_valid():
			_context.on_ship_changed.call(_ship_id)
		if _selected_slot == from_slot:
			_selected_slot = ""


func _rebuild_stock_tabs() -> void:
	if _stock_tabs.get_tab_count() > 0:
		_selected_stock_tab = _stock_tabs.current_tab

	for child in _stock_tabs.get_children():
		_stock_tabs.remove_child(child)
		child.queue_free()

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

		var tab_root: Control
		var list_parent: Control

		if category in SORTABLE_STOCK_CATEGORIES:
			entries = _sort_stock_entries(category, entries)
			var tab_column := VBoxContainer.new()
			tab_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tab_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
			tab_column.add_theme_constant_override("separation", 4)
			tab_root = tab_column
			tab_column.add_child(_build_stock_sort_bar(category))
			var scroll := ScrollContainer.new()
			scroll.set_script(INVENTORY_DROP_TARGET)
			scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			tab_column.add_child(scroll)
			_bind_inventory_drop_target(scroll)
			list_parent = VBoxContainer.new()
			list_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			list_parent.add_theme_constant_override("separation", 4)
			scroll.add_child(list_parent)
		else:
			var scroll := ScrollContainer.new()
			scroll.set_script(INVENTORY_DROP_TARGET)
			scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			tab_root = scroll
			_bind_inventory_drop_target(scroll)
			list_parent = VBoxContainer.new()
			list_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			list_parent.add_theme_constant_override("separation", 4)
			scroll.add_child(list_parent)

		_stock_tabs.add_child(tab_root)

		for part_entry in entries:
			var part_id := str(part_entry.get("id", ""))
			var data: Dictionary = part_entry.get("data", {})
			var category_label := str(part_entry.get("category", data.get("category", "")))
			var spare := _context.session.get_spare_part_count(part_id)
			var meta_detail := ""
			if category in SORTABLE_STOCK_CATEGORIES:
				meta_detail = ModuleSpecText.format_stock_list_meta(category, data)
			var row := MODULE_STOCK_ITEM.instantiate()
			row.configure(
				part_id,
				str(data.get("name", part_id)),
				int(data.get("cost", 0)),
				spare,
				part_id == _selected_part_id,
				_sandbox,
				category_label,
				meta_detail,
				ModuleSpecText.format_tooltip(data)
			)
			row.stock_selected.connect(_on_part_selected)
			row.module_dropped_on_stock.connect(_on_module_dropped_on_stock)
			list_parent.add_child(row)

		_stock_tabs.set_tab_title(_stock_tabs.get_tab_count() - 1, category.capitalize())

	if _stock_tabs.get_tab_count() > 0:
		_stock_tabs.current_tab = clampi(_selected_stock_tab, 0, _stock_tabs.get_tab_count() - 1)


func _refresh_part_selection() -> void:
	_rebuild_configuration()
	_update_stock_selection()
	_update_actions()


func _update_stock_selection() -> void:
	for tab_index in range(_stock_tabs.get_tab_count()):
		var tab_root := _stock_tabs.get_tab_control(tab_index)
		if tab_root == null:
			continue
		_for_each_stock_row(tab_root, func(row: ModuleStockItem) -> void:
			var is_selected := row.module_id == _selected_part_id
			if row.selected != is_selected:
				row.set_selected_state(is_selected)
		)


func _bind_inventory_drop_target(node: Node) -> void:
	if not node.has_signal("module_dropped"):
		return
	if not node.module_dropped.is_connected(_on_module_dropped_on_stock):
		node.module_dropped.connect(_on_module_dropped_on_stock)


func _update_actions() -> void:
	var buy := $Layout/Body/Split/InventoryColumn/Actions/BuyButton
	var sell := $Layout/Body/Split/InventoryColumn/Actions/SellButton

	if not _sandbox:
		buy.disabled = _selected_part_id.is_empty()
		sell.disabled = _selected_part_id.is_empty() or _context.session.get_spare_part_count(_selected_part_id) <= 0


func _on_part_selected(part_id: String) -> void:
	if part_id == _selected_part_id:
		return
	_selected_part_id = part_id
	if not _ship_id.is_empty() and _selected_slot.is_empty():
		var ship := _context.session.get_owned_ship(_ship_id)
		if ship != null:
			var slots := ShipAssembly.find_compatible_slots(_context.catalog, ship, part_id)
			if slots.size() == 1:
				_selected_slot = str(slots[0])
	_refresh_part_selection()


func _on_buy_pressed() -> void:
	ShipAssembly.buy_part(_context.session, _context.catalog, _selected_part_id)


func _on_sell_pressed() -> void:
	ShipAssembly.sell_part(_context.session, _context.catalog, _selected_part_id)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Section"
	return label


func _build_stock_sort_bar(category: String) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	var sort_label := Label.new()
	sort_label.text = "SORT"
	sort_label.theme_type_variation = &"Section"
	bar.add_child(sort_label)
	for sort_key in STOCK_SORT_KEYS.get(category, []):
		var button := Button.new()
		button.text = _stock_sort_button_label(category, sort_key)
		button.pressed.connect(_on_stock_sort_pressed.bind(category, sort_key))
		bar.add_child(button)
	return bar


func _stock_sort_button_label(category: String, sort_key: String) -> String:
	var label := sort_key.to_upper()
	if sort_key == "mw":
		label = "MW"
	if sort_key == "cu":
		label = "CU"
	if sort_key == "crew":
		label = "CREW"
	var sort_state: Dictionary = _stock_sort.get(category, {"key": "price", "asc": true})
	if str(sort_state.get("key", "")) == sort_key:
		label = "%s %s" % ["^" if bool(sort_state.get("asc", true)) else "v", label]
	return label


func _on_stock_sort_pressed(category: String, sort_key: String) -> void:
	var sort_state: Dictionary = _stock_sort.get(category, {"key": "price", "asc": true})
	if str(sort_state.get("key", "")) == sort_key:
		sort_state["asc"] = not bool(sort_state.get("asc", true))
	else:
		sort_state["key"] = sort_key
		sort_state["asc"] = true
	_stock_sort[category] = sort_state
	call_deferred("_rebuild_stock_tabs")


func _sort_stock_entries(category: String, entries: Array) -> Array:
	var sort_state: Dictionary = _stock_sort.get(category, {"key": "price", "asc": true})
	var sort_key := str(sort_state.get("key", "price"))
	var sort_asc := bool(sort_state.get("asc", true))
	var sorted: Array = entries.duplicate()
	sorted.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_data: Dictionary = left.get("data", {})
		var right_data: Dictionary = right.get("data", {})
		var cmp := 0
		match category:
			"propulsion":
				match sort_key:
					"price":
						cmp = int(left_data.get("cost", 0)) - int(right_data.get("cost", 0))
					"type":
						cmp = str(left_data.get("engine_type", "")).nocasecmp_to(
							str(right_data.get("engine_type", ""))
						)
						if cmp == 0:
							cmp = _float_compare(
								float(left_data.get("thrust", 0.0)),
								float(right_data.get("thrust", 0.0))
							)
					"thrust":
						cmp = _float_compare(
							float(left_data.get("thrust", 0.0)),
							float(right_data.get("thrust", 0.0))
						)
			"power":
				match sort_key:
					"price":
						cmp = int(left_data.get("cost", 0)) - int(right_data.get("cost", 0))
					"type":
						cmp = str(left_data.get("plant_type", "")).nocasecmp_to(
							str(right_data.get("plant_type", ""))
						)
						if cmp == 0:
							cmp = _float_compare(
								float(left_data.get("power_generation", 0.0)),
								float(right_data.get("power_generation", 0.0))
							)
					"mw":
						cmp = _float_compare(
							float(left_data.get("power_generation", 0.0)),
							float(right_data.get("power_generation", 0.0))
						)
			"computer":
				match sort_key:
					"price":
						cmp = int(left_data.get("cost", 0)) - int(right_data.get("cost", 0))
					"type":
						cmp = str(left_data.get("core_type", "")).nocasecmp_to(
							str(right_data.get("core_type", ""))
						)
						if cmp == 0:
							cmp = _float_compare(
								float(left_data.get("compute_capacity", 0.0)),
								float(right_data.get("compute_capacity", 0.0))
							)
					"cu":
						cmp = _float_compare(
							float(left_data.get("compute_capacity", 0.0)),
							float(right_data.get("compute_capacity", 0.0))
						)
			"life_support":
				match sort_key:
					"price":
						cmp = int(left_data.get("cost", 0)) - int(right_data.get("cost", 0))
					"crew":
						cmp = _float_compare(
							float(left_data.get("life_support_capacity", 0.0)),
							float(right_data.get("life_support_capacity", 0.0))
						)
			"weapon":
				match sort_key:
					"price":
						cmp = int(left_data.get("cost", 0)) - int(right_data.get("cost", 0))
					"type":
						cmp = str(left_data.get("weapon_type", "")).nocasecmp_to(
							str(right_data.get("weapon_type", ""))
						)
					"damage":
						cmp = _float_compare(
							_weapon_packet_total(left_data),
							_weapon_packet_total(right_data)
						)
			"armour":
				match sort_key:
					"price":
						cmp = int(left_data.get("cost", 0)) - int(right_data.get("cost", 0))
					"hits":
						cmp = int(left_data.get("hits", 0)) - int(right_data.get("hits", 0))
			"shield":
				match sort_key:
					"price":
						cmp = int(left_data.get("cost", 0)) - int(right_data.get("cost", 0))
					"type":
						cmp = str(left_data.get("shield_type", "")).nocasecmp_to(
							str(right_data.get("shield_type", ""))
						)
					"capacity":
						cmp = _float_compare(
							float(left_data.get("shield_capacity", 0.0)),
							float(right_data.get("shield_capacity", 0.0))
						)
		if not sort_asc:
			cmp = -cmp
		return cmp < 0
	)
	return sorted


func _float_compare(left: float, right: float) -> int:
	if left < right:
		return -1
	if left > right:
		return 1
	return 0


func _weapon_packet_total(module_def: Dictionary) -> float:
	var packets: Variant = module_def.get("damage_packets", {})
	if typeof(packets) != TYPE_DICTIONARY:
		return float(module_def.get("rate_of_fire", 0.0))
	var total := 0.0
	for packet_value in packets.values():
		total += float(packet_value)
	return total


func _for_each_stock_row(root: Node, callback: Callable) -> void:
	if root is ModuleStockItem:
		callback.call(root)
		return
	for child in root.get_children():
		_for_each_stock_row(child, callback)


func _close_and_pop() -> void:
	if _context == null or _context.stack == null:
		queue_free()
		return
	if _context.stack.get_top_screen() == self:
		_context.stack.pop_screen()
	queue_free()


func _on_close_pressed() -> void:
	_close_and_pop()


func handle_back() -> bool:
	_close_and_pop()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _footer != null and not _footer.visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_close_and_pop()
		get_viewport().set_input_as_handled()
