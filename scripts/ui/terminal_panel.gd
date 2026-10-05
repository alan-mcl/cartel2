extends GameScreen

const SHIP_DETAIL_PANEL := preload("res://scenes/ui/ship_detail_panel.tscn")
const CHARTER_PANEL := preload("res://scenes/ui/passenger_charter_panel.tscn")
const FREIGHT_PANEL := preload("res://scenes/ui/freight_charter_panel.tscn")

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

var _selected_terminal_ship_id: String = ""
var _terminal_ship_ids: PackedStringArray = PackedStringArray()
var _terminal_ship_item_list: ItemList
var _suppress_terminal_ship_select: bool = false
var _show_rename_field: bool = false
var _view_mode: String = "ships"

const _FUEL_TAPE_TOP_UP_MAX_TRIES := 12

var _fuel_tape_bar: MessageBar
var _fuel_tape := FuelPriceTape.new()
var _fuel_tape_active := false


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if not _fuel_tape_active or _fuel_tape_bar == null:
		return
	if _context == null or _context.session == null or _context.catalog == null:
		return
	var tries := 0
	while _fuel_tape_bar.wants_more_log_lines() and tries < _FUEL_TAPE_TOP_UP_MAX_TRIES:
		var line := _fuel_tape.next_line(_context.session, _context.catalog)
		if line.is_empty() or not _fuel_tape_bar.play_line(line, true, true):
			break
		tries += 1


func refresh() -> void:
	if not is_node_ready() or _context == null or _context.session == null:
		return
	if _can_soft_refresh_docking_bay():
		_soft_refresh_docking_bay()
		return
	_full_rebuild()


func _can_soft_refresh_docking_bay() -> bool:
	return (
		_view_mode == "ships"
		and _fuel_tape_bar != null
		and is_instance_valid(_fuel_tape_bar)
		and _fuel_tape_active
	)


func _soft_refresh_docking_bay() -> void:
	_sync_docked_ship_list_labels()
	_rebuild_terminal_ship_panels()


func _sync_docked_ship_list_labels() -> void:
	if _terminal_ship_item_list == null:
		return
	for i in range(_terminal_ship_ids.size()):
		var ship := _context.session.get_owned_ship(_terminal_ship_ids[i])
		if ship != null:
			_terminal_ship_item_list.set_item_text(i, ship.name)


func _full_rebuild() -> void:
	_fuel_tape_active = false
	set_process(false)
	_fuel_tape_bar = null
	_fuel_tape.reset()
	_clear_children(self)
	_terminal_ship_item_list = null
	_build_content()


func _build_content() -> void:
	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	outer.add_child(tab_row)

	var ships_tab := Button.new()
	ships_tab.text = "Docking Bay"
	ships_tab.disabled = _view_mode == "ships"
	ships_tab.pressed.connect(func() -> void:
		if _view_mode != "ships":
			_view_mode = "ships"
			_full_rebuild()
	)
	tab_row.add_child(ships_tab)

	var departures_tab := Button.new()
	departures_tab.text = "Departures Terminal"
	departures_tab.disabled = _view_mode == "departures"
	departures_tab.pressed.connect(func() -> void:
		if _view_mode != "departures":
			_view_mode = "departures"
			_full_rebuild()
	)
	tab_row.add_child(departures_tab)

	var freight_tab := Button.new()
	freight_tab.text = "Freight Terminal"
	freight_tab.disabled = _view_mode == "freight"
	freight_tab.pressed.connect(func() -> void:
		if _view_mode != "freight":
			_view_mode = "freight"
			_full_rebuild()
	)
	tab_row.add_child(freight_tab)

	if _view_mode == "freight":
		_sync_terminal_ship_selection()
		var freight_host := Control.new()
		_fill_remaining_area(freight_host)
		outer.add_child(freight_host)
		var freight_panel: Control = FREIGHT_PANEL.instantiate()
		_fill_remaining_area(freight_panel)
		freight_host.add_child(freight_panel)
		if freight_panel.has_method("bind"):
			freight_panel.bind(_context)
		if freight_panel.has_method("set_ship_resolver"):
			freight_panel.set_ship_resolver(func() -> String:
				return _selected_terminal_ship_id
			)
		if freight_panel.has_method("refresh"):
			freight_panel.refresh()
		return

	if _view_mode == "departures":
		_sync_terminal_ship_selection()
		var charter_host := Control.new()
		_fill_remaining_area(charter_host)
		outer.add_child(charter_host)
		var charter_panel: Control = CHARTER_PANEL.instantiate()
		_fill_remaining_area(charter_panel)
		charter_panel.board_mode = PassengerCharters.BOARD_TERMINAL
		charter_host.add_child(charter_panel)
		if charter_panel.has_method("bind"):
			charter_panel.bind(_context)
		if charter_panel.has_method("set_ship_resolver"):
			charter_panel.set_ship_resolver(func() -> String:
				return _selected_terminal_ship_id
			)
		if charter_panel.has_method("refresh"):
			charter_panel.refresh()
		return

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

	_terminal_ship_ids.clear()

	_terminal_ship_item_list = ItemList.new()
	_terminal_ship_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_terminal_ship_item_list.select_mode = ItemList.SELECT_SINGLE
	_terminal_ship_item_list.allow_reselect = true
	_terminal_ship_item_list.item_selected.connect(_on_terminal_ship_item_selected)
	left.add_child(_terminal_ship_item_list)

	var right_pane := VBoxContainer.new()
	right_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_pane.size_flags_stretch_ratio = 2.0
	right_pane.add_theme_constant_override("separation", 8)
	columns.add_child(right_pane)

	_fuel_tape_bar = UiPatterns.message_bar()
	_fuel_tape_bar.set_tag("FUEL PRICES")
	right_pane.add_child(_fuel_tape_bar)
	_fuel_tape.reset()
	_fuel_tape_bar.play_line("Today's propulsion fuel prices:")
	_fuel_tape_active = true
	set_process(true)

	var content_row := HBoxContainer.new()
	content_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 12)
	right_pane.add_child(content_row)

	var detail := _add_scroll_pane(content_row, "terminal_detail_host")
	var detail_scroll := detail.get_parent() as ScrollContainer
	if detail_scroll != null:
		detail_scroll.size_flags_stretch_ratio = 1.0

	var admin := VBoxContainer.new()
	admin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	admin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	admin.size_flags_stretch_ratio = 1.0
	admin.add_theme_constant_override("separation", 8)
	admin.set_meta("terminal_admin_host", true)
	content_row.add_child(admin)

	for ship in ships:
		_terminal_ship_ids.append(ship.id)
		_terminal_ship_item_list.add_item(ship.name)

	_sync_terminal_ship_selection()

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
	if _context != null:
		_context.charter_ship_id = _selected_terminal_ship_id
	_show_rename_field = false
	_rebuild_terminal_ship_panels()


func _sync_terminal_ship_selection() -> void:
	if _terminal_ship_ids.is_empty():
		for ship in _context.session.ships_at(_context.session.habitat_id):
			_terminal_ship_ids.append(ship.id)
	if _terminal_ship_ids.is_empty():
		_selected_terminal_ship_id = ""
		return
	if _terminal_ship_ids.has(_selected_terminal_ship_id):
		return
	var preferred := _context.session.current_ship_id
	if _terminal_ship_ids.has(preferred):
		_selected_terminal_ship_id = preferred
	else:
		_selected_terminal_ship_id = _terminal_ship_ids[0]
	if _context != null:
		_context.charter_ship_id = _selected_terminal_ship_id


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

	admin.add_child(_section_label("LAUNCH STATUS"))

	var occupant_count := 1
	var freight_power := 0.0
	var freight_compute := 0.0
	if _context.simulation != null:
		var missions := _context.simulation.get_subsystem("missions") as MissionSubsystem
		if missions != null:
			occupant_count = missions.launch_occupant_count(ship.id)
			var reserves := missions.committed_freight_reserves_for_ship(ship.id)
			freight_power = float(reserves.get("power", 0.0))
			freight_compute = float(reserves.get("compute", 0.0))
	var sanction_total := Sanctions.total_fine(_context.session.player.sanctions)
	if sanction_total > 0:
		for entry_variant in _context.session.player.sanctions:
			if typeof(entry_variant) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_variant
			var line := Label.new()
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.text = Sanctions.format_terminal_line(_context.catalog, entry)
			admin.add_child(line)
		var pay := Button.new()
		pay.text = "Pay sanctions (d%d)" % sanction_total
		pay.pressed.connect(_on_pay_sanctions_pressed)
		admin.add_child(pay)
	else:
		var blockers := ShipAssembly.undock_blockers(
			_context.catalog,
			ship,
			occupant_count,
			freight_power,
			freight_compute
		)
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

	var refuel_quote := ShipAssembly.refuel_quote(_context.session, _context.catalog, ship.id)
	var refuel := Button.new()
	refuel.text = str(refuel_quote.get("button_text", "Refuel"))
	refuel.disabled = not bool(refuel_quote.get("enabled", false))
	refuel.pressed.connect(_on_refuel_ship_pressed)
	admin.add_child(refuel)

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


func _on_pay_sanctions_pressed() -> void:
	if _context == null or _context.session == null or _context.catalog == null:
		return
	_context.session.pay_sanctions(_context.catalog)
	refresh()


func _on_undock_ship(ship_id: String) -> void:
	if _context.on_undock_requested.is_valid():
		_context.on_undock_requested.call(ship_id)


func _on_refuel_ship_pressed() -> void:
	if _selected_terminal_ship_id.is_empty():
		return
	if ShipAssembly.refuel_ship(_context.session, _context.catalog, _selected_terminal_ship_id):
		_rebuild_terminal_ship_panels()
		if _context.on_ship_changed.is_valid():
			_context.on_ship_changed.call(_selected_terminal_ship_id)


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
