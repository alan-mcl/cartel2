class_name CharterBoard
extends Control

## Shared charter desk chrome: ship line, three-column tiles, and refresh.
## The owning panel supplies headings, tile copy, and accept or cancel hooks.

const TILE_COLUMNS := 3

var resolve_ship_id: Callable = Callable()
## (ship: OwnedShip) -> float. When unset, an unknown charter ship falls back to the first docked ship.
var ship_score: Callable = Callable()
var rerender: Callable = Callable()
var expand_plain_labels: bool = false

var _context: UiContext


static func reputation_line(entry: Dictionary) -> String:
	var minimum := int(entry.get("min_reputation", 0))
	if minimum <= 0:
		return ""
	return "Requires reputation %d" % minimum


static func habitat_name(catalog: Catalog, habitat_id: String) -> String:
	if catalog == null:
		return habitat_id
	var habitat := catalog.get_habitat(habitat_id)
	if habitat.is_empty():
		return habitat_id
	return str(habitat.get("name", habitat_id))


static func ship_name(session: GameSession, ship_id: String) -> String:
	if session == null:
		return ship_id
	var ship := session.get_owned_ship(ship_id)
	if ship == null:
		return ship_id
	return ship.name


## Round-robin merge of chit groups; empty groups are skipped. Order is stable for the day.
static func interleave(groups: Array) -> Array:
	var lists: Array = []
	for group_variant in groups:
		if typeof(group_variant) != TYPE_ARRAY:
			continue
		var group: Array = group_variant
		if group.is_empty():
			continue
		lists.append(group.duplicate())
	if lists.is_empty():
		return []
	var out: Array = []
	var index := 0
	while true:
		var any := false
		for list_variant in lists:
			var list: Array = list_variant
			if index < list.size():
				out.append(list[index])
				any = true
		if not any:
			break
		index += 1
	return out


func present(context: UiContext, build_sections: Callable, blocked_text: String = "") -> void:
	_context = context
	_clear_children(self)
	if not blocked_text.is_empty():
		add_child(_plain_label(blocked_text))
		return
	if context == null or context.session == null:
		return

	var docked := context.session.ships_at(context.session.habitat_id)
	_sync_ship(docked)
	var sections: Array = []
	if build_sections.is_valid():
		var built: Variant = build_sections.call()
		if typeof(built) == TYPE_ARRAY:
			sections = built

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	_add_ship_line(body, docked)
	for section_variant in sections:
		if section_variant is CharterBoardSection:
			_add_section(body, section_variant)


func _sync_ship(docked: Array[OwnedShip]) -> void:
	if docked.is_empty():
		_context.charter_ship_id = ""
		return
	for ship in docked:
		if ship.id == _context.charter_ship_id:
			return
	if resolve_ship_id.is_valid():
		var resolved := str(resolve_ship_id.call()).strip_edges()
		if not resolved.is_empty():
			for ship in docked:
				if ship.id == resolved:
					_context.charter_ship_id = resolved
					return
	if ship_score.is_valid():
		_context.charter_ship_id = _best_ship_id(docked)
	else:
		_context.charter_ship_id = docked[0].id


func _best_ship_id(docked: Array[OwnedShip]) -> String:
	var preferred := _context.session.current_ship_id
	for ship in docked:
		if ship.id == preferred and _score(ship) > 0.0:
			return ship.id
	var best_id := ""
	var best_cap := -1.0
	for ship in docked:
		var cap := _score(ship)
		if cap > best_cap:
			best_cap = cap
			best_id = ship.id
	return best_id


func _score(ship: OwnedShip) -> float:
	if not ship_score.is_valid():
		return 0.0
	return float(ship_score.call(ship))


func _active_ship_id() -> String:
	if resolve_ship_id.is_valid():
		var resolved := str(resolve_ship_id.call()).strip_edges()
		if not resolved.is_empty():
			return resolved
	return _context.charter_ship_id


func _add_ship_line(body: VBoxContainer, docked: Array[OwnedShip]) -> void:
	if docked.is_empty():
		body.add_child(_plain_label("No ships docked at this habitat."))
	elif docked.size() > 1:
		body.add_child(_ship_selector(docked))
	else:
		body.add_child(_plain_label("Charter ship: %s" % docked[0].name))


func _ship_selector(docked: Array[OwnedShip]) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var caption := Label.new()
	caption.text = "Charter ship:"
	row.add_child(caption)
	var menu := OptionButton.new()
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected_index := 0
	for index in docked.size():
		var ship: OwnedShip = docked[index]
		menu.add_item(ship.name)
		if ship.id == _context.charter_ship_id:
			selected_index = index
	menu.select(selected_index)
	menu.item_selected.connect(func(index: int) -> void:
		if index < 0 or index >= docked.size():
			return
		_context.charter_ship_id = docked[index].id
		if rerender.is_valid():
			rerender.call()
	)
	row.add_child(menu)
	return row


func _add_section(body: VBoxContainer, section: CharterBoardSection) -> void:
	if not section.heading.is_empty():
		body.add_child(_section_label(section.heading))
	var chits: Array = []
	for chit_variant in section.chits:
		if chit_variant is CharterChit:
			chits.append(chit_variant)
	if chits.is_empty():
		body.add_child(_plain_label(section.empty_text))
		return
	var grid := _new_tile_grid()
	var ship_id := _active_ship_id()
	for chit_variant in chits:
		grid.add_child(_tile(chit_variant as CharterChit, ship_id))
	body.add_child(grid)


func _tile(chit: CharterChit, ship_id: String) -> Control:
	var spec: Dictionary = {}
	if chit.describe.is_valid():
		var described: Variant = chit.describe.call(chit.entry, ship_id)
		if typeof(described) == TYPE_DICTIONARY:
			spec = described
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	inner.add_child(_one_line_label(str(spec.get("title", ""))))
	var lines: Variant = spec.get("lines", [])
	if typeof(lines) == TYPE_ARRAY:
		for line_variant in lines:
			var line := str(line_variant)
			if line.is_empty():
				continue
			inner.add_child(_one_line_label(line, &"Muted"))
	if spec.has("body"):
		inner.add_child(_tile_body_label(str(spec.get("body", ""))))
	var button_text := str(spec.get("button_text", ""))
	if not button_text.is_empty():
		var button := Button.new()
		button.text = button_text
		button.disabled = not bool(spec.get("button_enabled", true))
		if chit.act.is_valid():
			button.pressed.connect(func() -> void:
				if bool(chit.act.call(chit.entry, ship_id)):
					if rerender.is_valid():
						rerender.call()
			)
		inner.add_child(button)
	else:
		var status := str(spec.get("status", ""))
		if not status.is_empty():
			inner.add_child(_one_line_label(status, &"Muted"))
	return _surface_tile(inner, str(spec.get("tooltip", "")))


func _new_tile_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = TILE_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return grid


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Section"
	return label


func _surface_tile(inner: VBoxContainer, tooltip: String = "") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Surface"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(inner)
	if not tooltip.is_empty():
		panel.tooltip_text = tooltip
	return panel


func _one_line_label(text: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		label.theme_type_variation = variation
	return label


func _tile_body_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = &"Muted"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _plain_label(text: String) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	if expand_plain_labels:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	return label


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
