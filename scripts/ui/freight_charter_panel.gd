extends GameScreen

const TILE_COLUMNS := 3

var _resolve_ship_id: Callable = Callable()


func set_ship_resolver(resolver: Callable) -> void:
	_resolve_ship_id = resolver


func refresh() -> void:
	if not is_node_ready() or _context == null or _context.session == null or _context.catalog == null:
		return
	_clear_children(self)
	_build_content()


func _build_content() -> void:
	var missions := _missions()
	if missions == null:
		add_child(_plain_label("Freight services unavailable."))
		return

	missions.ensure_boards(_context.session, _context.catalog)
	var habitat_id := _context.session.habitat_id
	var docked := _context.session.ships_at(habitat_id)
	_sync_charter_ship_id(docked)
	var offers := missions.list_freight_offers(habitat_id)
	var accepted := missions.list_freight_accepted()

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	if docked.is_empty():
		body.add_child(_plain_label("No ships docked at this habitat."))
	elif docked.size() > 1:
		body.add_child(_charter_ship_selector(docked))
	else:
		body.add_child(_plain_label("Charter ship: %s" % docked[0].name))

	body.add_child(_section_label("POSTED FREIGHT"))
	if offers.is_empty():
		body.add_child(_plain_label("No freight posted today."))
	else:
		var offer_grid := _new_tile_grid()
		for offer_variant in offers:
			if typeof(offer_variant) != TYPE_DICTIONARY:
				continue
			offer_grid.add_child(_offer_tile(missions, offer_variant))
		body.add_child(offer_grid)

	body.add_child(_section_label("YOUR FREIGHT"))
	if accepted.is_empty():
		body.add_child(_plain_label("No accepted freight."))
	else:
		var accepted_grid := _new_tile_grid()
		for charter_variant in accepted:
			if typeof(charter_variant) != TYPE_DICTIONARY:
				continue
			accepted_grid.add_child(_accepted_tile(missions, charter_variant))
		body.add_child(accepted_grid)


func _new_tile_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = TILE_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return grid


func _offer_tile(missions: MissionSubsystem, offer: Dictionary) -> PanelContainer:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)

	inner.add_child(_one_line_label(str(offer.get("description", "Freight"))))

	var meta := _offer_meta_line(offer)
	inner.add_child(_one_line_label(meta, &"Muted"))
	inner.add_child(_one_line_label(_budget_line(offer), &"Muted"))
	var timing := _charter_timing_line(offer)
	if not timing.is_empty():
		inner.add_child(_one_line_label(timing, &"Muted"))
	inner.add_child(_one_line_label(str(offer.get("hold_label", "Dry hold")), &"Muted"))
	var reputation_line := _reputation_requirement_line(offer)
	if not reputation_line.is_empty():
		inner.add_child(_one_line_label(reputation_line, &"Muted"))

	var ship_id := _active_ship_id()
	var check := missions.evaluate_freight_offer(
		_context.session,
		_context.catalog,
		str(offer.get("id", "")),
		ship_id
	)

	var accept := Button.new()
	accept.text = "Accept"
	accept.disabled = not bool(check.get("ok", false))
	var offer_id := str(offer.get("id", ""))
	accept.pressed.connect(func() -> void:
		if missions.accept_freight_offer(_context.session, _context.catalog, offer_id, ship_id):
			refresh()
	)
	inner.add_child(accept)

	var tooltip := CharterTooltipText.format_freight(offer, str(check.get("reason", "")))
	return _surface_tile(inner, tooltip)


func _accepted_tile(missions: MissionSubsystem, charter: Dictionary) -> PanelContainer:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)

	inner.add_child(_one_line_label(str(charter.get("description", "Freight"))))

	var ship := _context.session.get_owned_ship(str(charter.get("ship_id", "")))
	var ship_name := ship.name if ship != null else str(charter.get("ship_id", ""))
	var origin := _habitat_name(str(charter.get("origin_habitat_id", "")))
	var meta := _accepted_meta_line(charter, origin, ship_name)
	inner.add_child(_one_line_label(meta, &"Muted"))
	inner.add_child(_one_line_label(_budget_line(charter), &"Muted"))
	var timing := _charter_timing_line(charter)
	if not timing.is_empty():
		inner.add_child(_one_line_label(timing, &"Muted"))

	var charter_id := str(charter.get("charter_id", ""))
	var status_line := ""
	if missions.cancel_freight_charter_eligible(_context.session, charter_id):
		var cfg := FreightCharters.config(_context.catalog)
		var penalty := FreightCharters.cancel_penalty(cfg, int(charter.get("reward", 0)))
		var cancel := Button.new()
		cancel.text = "Cancel (fee d%d)" % penalty
		cancel.pressed.connect(func() -> void:
			if missions.cancel_freight_charter(_context.session, _context.catalog, charter_id):
				refresh()
		)
		inner.add_child(cancel)
	else:
		status_line = "In transit — cannot cancel."
		inner.add_child(_one_line_label(status_line, &"Muted"))

	var tooltip := CharterTooltipText.format_freight(
		charter,
		status_line,
		origin,
		ship_name
	)
	return _surface_tile(inner, tooltip)


func _destination_label(entry: Dictionary) -> String:
	return str(entry.get("destination_name", "")) + str(entry.get("via_label", ""))


func _charter_timing_line(entry: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var hours := int(entry.get("deadline_hours", 0))
	if hours > 0:
		parts.append("Within %d h" % hours)
	var hops := int(entry.get("hops", 1))
	if hops > 1:
		parts.append("%d-hop" % hops)
	if parts.is_empty():
		return ""
	return ", ".join(parts)


func _offer_meta_line(offer: Dictionary) -> String:
	return "%s · %.1f t · d%d" % [
		_destination_label(offer),
		float(offer.get("tonnes", 0.0)),
		int(offer.get("reward", 0)),
	]


func _accepted_meta_line(charter: Dictionary, origin: String, ship_name: String) -> String:
	return "%s → %s · %s · d%d" % [
		origin,
		_destination_label(charter),
		ship_name,
		int(charter.get("reward", 0)),
	]


func _reputation_requirement_line(entry: Dictionary) -> String:
	var minimum := int(entry.get("min_reputation", 0))
	if minimum <= 0:
		return ""
	return "Requires reputation %d" % minimum


func _budget_line(entry: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var ls := int(entry.get("life_support_seats", 0))
	if ls > 0:
		parts.append("%d seats" % ls)
	var cu := float(entry.get("compute_demand", 0.0))
	if cu > 0.001:
		parts.append("%.1f CU" % cu)
	var mw := float(entry.get("power_demand", 0.0))
	if mw > 0.001:
		parts.append("%.1f MW" % mw)
	if parts.is_empty():
		return "No extra ship budgets"
	return "Draw: " + ", ".join(parts)


func _active_ship_id() -> String:
	if _resolve_ship_id.is_valid():
		var resolved := str(_resolve_ship_id.call()).strip_edges()
		if not resolved.is_empty():
			return resolved
	return _context.charter_ship_id


func _sync_charter_ship_id(docked: Array[OwnedShip]) -> void:
	if docked.is_empty():
		_context.charter_ship_id = ""
		return
	for ship in docked:
		if ship.id == _context.charter_ship_id:
			return
	if _resolve_ship_id.is_valid():
		var resolved := str(_resolve_ship_id.call()).strip_edges()
		if not resolved.is_empty():
			for ship in docked:
				if ship.id == resolved:
					_context.charter_ship_id = resolved
					return
	_context.charter_ship_id = _best_charter_ship_id_among(docked)


func _best_charter_ship_id_among(docked: Array[OwnedShip]) -> String:
	var preferred := _context.session.current_ship_id
	for ship in docked:
		if ship.id == preferred and _cargo_capacity(ship) > 0.0:
			return ship.id
	var best_id := ""
	var best_cap := -1.0
	for ship in docked:
		var cap := _cargo_capacity(ship)
		if cap > best_cap:
			best_cap = cap
			best_id = ship.id
	return best_id


func _cargo_capacity(ship: OwnedShip) -> float:
	var assembled := ShipAssembler.assemble_owned(_context.catalog, ship)
	return float(assembled.capacities.get("cargo_capacity", 0.0))


func _charter_ship_selector(docked: Array[OwnedShip]) -> HBoxContainer:
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
		refresh()
	)
	row.add_child(menu)
	return row


func _habitat_name(habitat_id: String) -> String:
	var habitat := _context.catalog.get_habitat(habitat_id)
	if habitat.is_empty():
		return habitat_id
	return str(habitat.get("name", habitat_id))


func _missions() -> MissionSubsystem:
	if _context.simulation == null:
		return null
	return _context.simulation.get_subsystem("missions") as MissionSubsystem


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


func _plain_label(text: String) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	return label


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
