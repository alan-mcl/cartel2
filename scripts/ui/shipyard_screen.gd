class_name ShipyardScreen
extends GameScreen

const SHIP_DETAIL_PANEL := preload("res://scenes/ui/ship_detail_panel.tscn")
const SHIPYARD_REFIT_SCREEN := preload("res://scenes/ui/shipyard_refit_screen.tscn")

const _DOCKING_BAY_SHIP_DETAIL_OPTS := {
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

const _MODULE_TAPE_TOP_UP_MAX_TRIES := 12

var _embedded := false
var _selected_ship_id: String = ""
var _ship_ids: PackedStringArray = PackedStringArray()
var _ship_item_list: ItemList
var _suppress_ship_select: bool = false
var _refresh_pending := false

var _module_tape_bar: MessageBar
var _module_tape := YardModuleTape.new()
var _module_tape_active := false


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if not _module_tape_active or _module_tape_bar == null:
		return
	if _context == null or _context.session == null or _context.catalog == null:
		return
	var tries := 0
	while _module_tape_bar.wants_more_log_lines() and tries < _MODULE_TAPE_TOP_UP_MAX_TRIES:
		var line := _module_tape.next_line()
		if line.is_empty() or not _module_tape_bar.play_line(line, true, true):
			break
		tries += 1


func configure_embedded(enabled: bool) -> void:
	_embedded = enabled
	if enabled:
		_disconnect_session_changed()
	elif _context != null:
		_connect_session_changed()


func bind(context: UiContext) -> void:
	super.bind(context)


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
	if _can_soft_refresh():
		_soft_refresh()
		return
	_full_refresh()


func _can_soft_refresh() -> bool:
	return (
		_module_tape_bar != null
		and is_instance_valid(_module_tape_bar)
		and _module_tape_active
		and _ship_item_list != null
	)


func _soft_refresh() -> void:
	_sync_ship_list_labels()
	_rebuild_ship_panels()


func _full_refresh() -> void:
	_module_tape_active = false
	set_process(false)
	_module_tape_bar = null
	_module_tape.reset(_context.catalog if _context != null else null)
	_clear_children(self)
	_ship_item_list = null
	_build_content()


func get_selected_ship_id() -> String:
	return _selected_ship_id


func _build_content() -> void:
	if _context == null or _context.session == null or _context.catalog == null:
		return

	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	var ships := _context.session.ships_at(_context.session.habitat_id)

	var columns := HBoxContainer.new()
	_fill_remaining_area(columns)
	columns.add_theme_constant_override("separation", 12)
	outer.add_child(columns)

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

	_ship_ids.clear()

	_ship_item_list = ItemList.new()
	_ship_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ship_item_list.select_mode = ItemList.SELECT_SINGLE
	_ship_item_list.allow_reselect = true
	_ship_item_list.item_selected.connect(_on_ship_item_selected)
	left.add_child(_ship_item_list)

	var right_pane := VBoxContainer.new()
	right_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_pane.size_flags_stretch_ratio = 2.0
	right_pane.add_theme_constant_override("separation", 8)
	columns.add_child(right_pane)

	_module_tape_bar = UiPatterns.message_bar()
	_module_tape_bar.set_tag("YARD STOCK")
	right_pane.add_child(_module_tape_bar)
	_module_tape.reset(_context.catalog)
	_module_tape_bar.play_line("Today's module list prices:")
	_module_tape_active = true
	set_process(true)

	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 12)
	right_pane.add_child(content_row)

	var detail := _add_scroll_pane(content_row, "yard_detail_host")
	var detail_scroll := detail.get_parent() as ScrollContainer
	if detail_scroll != null:
		detail_scroll.size_flags_stretch_ratio = 1.0

	var admin := VBoxContainer.new()
	admin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	admin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	admin.size_flags_stretch_ratio = 1.0
	admin.add_theme_constant_override("separation", 8)
	admin.set_meta("yard_admin_host", true)
	content_row.add_child(admin)

	for ship in ships:
		_ship_ids.append(ship.id)
		_ship_item_list.add_item(ship.name)

	_sync_ship_selection()

	_select_item_by_id(_ship_item_list, _ship_ids, _selected_ship_id)
	_rebuild_ship_panels()


func _on_ship_item_selected(index: int) -> void:
	if _suppress_ship_select:
		return
	if index < 0 or index >= _ship_ids.size():
		return
	_selected_ship_id = _ship_ids[index]
	_rebuild_ship_panels()


func _sync_ship_selection() -> void:
	if _ship_ids.is_empty():
		for ship in _context.session.ships_at(_context.session.habitat_id):
			_ship_ids.append(ship.id)
	if _ship_ids.is_empty():
		_selected_ship_id = ""
		return
	if _ship_ids.has(_selected_ship_id):
		return
	var preferred := _context.session.current_ship_id
	if _ship_ids.has(preferred):
		_selected_ship_id = preferred
	else:
		_selected_ship_id = _ship_ids[0]


func _rebuild_ship_panels() -> void:
	var detail := _find_meta_host("yard_detail_host")
	var admin := _find_meta_host("yard_admin_host")
	if detail != null:
		_rebuild_ship_detail(detail)
	if admin != null:
		_rebuild_admin_panel(admin)


func _rebuild_ship_detail(detail: VBoxContainer) -> void:
	if _selected_ship_id.is_empty():
		_clear_children(detail)
		return

	var ship := _context.session.get_owned_ship(_selected_ship_id)
	if ship == null:
		_clear_children(detail)
		return

	var panel := _ensure_ship_detail_panel(detail)
	panel.configure(_DOCKING_BAY_SHIP_DETAIL_OPTS)
	panel.bind_ship(_context.catalog, ship)
	panel.refresh()


func _ensure_ship_detail_panel(detail: VBoxContainer) -> VBoxContainer:
	for child in detail.get_children():
		if child.has_method("bind_ship"):
			return child as VBoxContainer
	var panel: VBoxContainer = SHIP_DETAIL_PANEL.instantiate()
	detail.add_child(panel)
	return panel


func _rebuild_admin_panel(admin: VBoxContainer) -> void:
	_clear_children(admin)

	if _selected_ship_id.is_empty():
		return

	var ship := _context.session.get_owned_ship(_selected_ship_id)
	if ship == null:
		return

	admin.add_child(_section_label("YARD SERVICES"))

	var refit := Button.new()
	refit.text = "Refit"
	refit.disabled = false
	refit.pressed.connect(_on_refit_pressed)
	admin.add_child(refit)

	var refuel_quote := ShipAssembly.refuel_quote(_context.session, _context.catalog, ship.id)
	var refuel := Button.new()
	refuel.text = str(refuel_quote.get("button_text", "Refuel"))
	refuel.disabled = not bool(refuel_quote.get("enabled", false))
	refuel.pressed.connect(_on_refuel_pressed)
	admin.add_child(refuel)

	var rearm_quote := ShipAssembly.rearm_quote(_context.session, _context.catalog, ship.id)
	var rearm := Button.new()
	rearm.text = str(rearm_quote.get("button_text", "Rearm"))
	rearm.disabled = not bool(rearm_quote.get("enabled", false))
	rearm.pressed.connect(_on_rearm_pressed)
	admin.add_child(rearm)

	var repair_quote := ShipAssembly.repair_quote(_context.session, _context.catalog, ship.id)
	var repair := Button.new()
	repair.text = str(repair_quote.get("button_text", "Repair"))
	repair.disabled = not bool(repair_quote.get("enabled", false))
	repair.pressed.connect(_on_repair_pressed)
	admin.add_child(repair)


func _sync_ship_list_labels() -> void:
	if _ship_item_list == null:
		return
	for i in range(_ship_ids.size()):
		var ship := _context.session.get_owned_ship(_ship_ids[i])
		if ship != null:
			_ship_item_list.set_item_text(i, ship.name)


func _select_item_by_id(list: ItemList, ids: PackedStringArray, target_id: String) -> void:
	_suppress_ship_select = true
	var index := ids.find(target_id)
	if index >= 0:
		list.select(index)
	else:
		list.deselect_all()
	_suppress_ship_select = false


func _on_refit_pressed() -> void:
	if _selected_ship_id.is_empty() or _context == null or _context.stack == null:
		return
	var refit: ShipyardRefitScreen = SHIPYARD_REFIT_SCREEN.instantiate()
	refit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refit.set_ship_id(_selected_ship_id)
	refit.bind(_context)
	_context.stack.push_screen(refit)


func _on_refuel_pressed() -> void:
	if _selected_ship_id.is_empty():
		return
	if ShipAssembly.refuel_ship(_context.session, _context.catalog, _selected_ship_id):
		_rebuild_ship_panels()
		if _context.on_ship_changed.is_valid():
			_context.on_ship_changed.call(_selected_ship_id)


func _on_rearm_pressed() -> void:
	if _selected_ship_id.is_empty():
		return
	if ShipAssembly.rearm_ship(_context.session, _context.catalog, _selected_ship_id):
		_rebuild_ship_panels()
		if _context.on_ship_changed.is_valid():
			_context.on_ship_changed.call(_selected_ship_id)


func _on_repair_pressed() -> void:
	if _selected_ship_id.is_empty():
		return
	if ShipAssembly.repair_ship(_context.session, _context.catalog, _selected_ship_id):
		_rebuild_ship_panels()
		if _context.on_ship_changed.is_valid():
			_context.on_ship_changed.call(_selected_ship_id)


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


func _fill_remaining_area(control: Control) -> void:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Section"
	return label


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
