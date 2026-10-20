extends GameScreen

const TILE_COLUMNS := 3

var _building_id: String = ""
var _resolve_ship_id: Callable = Callable()


func configure(building: Dictionary) -> void:
	_building_id = str(building.get("id", ""))


func set_ship_resolver(resolver: Callable) -> void:
	_resolve_ship_id = resolver


func refresh() -> void:
	if not is_node_ready() or _context == null or _context.session == null or _context.catalog == null:
		return
	_clear_children(self)
	_build_content()


func _build_content() -> void:
	var missions := _missions()
	if missions == null or _building_id.is_empty():
		add_child(_plain_label("Scan charter desk unavailable."))
		return

	missions.ensure_boards(_context.session, _context.catalog)
	var habitat_id := _context.session.habitat_id
	var docked := _context.session.ships_at(habitat_id)
	_sync_charter_ship_id(docked)
	var offers := missions.list_scan_offers(habitat_id, _building_id)
	var accepted := _accepted_for_building(missions)
	var bounty_offers := missions.list_bounty_offers(habitat_id, _building_id)
	var bounty_accepted := _bounty_accepted_for_building(missions)

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

	if docked.is_empty():
		body.add_child(_plain_label("No ships docked at this habitat."))
	elif docked.size() > 1:
		body.add_child(_charter_ship_selector(docked))
	else:
		body.add_child(_plain_label("Charter ship: %s" % docked[0].name))

	body.add_child(_section_label("POSTED SCANS"))
	if offers.is_empty():
		body.add_child(_plain_label("No scan work posted today."))
	else:
		var offer_grid := _new_tile_grid()
		for offer_variant in offers:
			if typeof(offer_variant) != TYPE_DICTIONARY:
				continue
			offer_grid.add_child(_offer_tile(missions, offer_variant))
		body.add_child(offer_grid)

	body.add_child(_section_label("YOUR SCANS"))
	if accepted.is_empty():
		body.add_child(_plain_label("No accepted scan charters."))
	else:
		var accepted_grid := _new_tile_grid()
		for charter_variant in accepted:
			if typeof(charter_variant) != TYPE_DICTIONARY:
				continue
			accepted_grid.add_child(_accepted_tile(missions, charter_variant))
		body.add_child(accepted_grid)

	body.add_child(_section_label("POSTED BOUNTIES"))
	if bounty_offers.is_empty():
		body.add_child(_plain_label("No bounties posted today."))
	else:
		var bounty_grid := _new_tile_grid()
		for offer_variant in bounty_offers:
			if typeof(offer_variant) != TYPE_DICTIONARY:
				continue
			bounty_grid.add_child(_bounty_offer_tile(missions, offer_variant))
		body.add_child(bounty_grid)

	body.add_child(_section_label("YOUR BOUNTIES"))
	if bounty_accepted.is_empty():
		body.add_child(_plain_label("No accepted bounties."))
	else:
		var bounty_accepted_grid := _new_tile_grid()
		for charter_variant in bounty_accepted:
			if typeof(charter_variant) != TYPE_DICTIONARY:
				continue
			bounty_accepted_grid.add_child(_bounty_accepted_tile(missions, charter_variant))
		body.add_child(bounty_accepted_grid)


func _accepted_for_building(missions: MissionSubsystem) -> Array:
	var out: Array = []
	for entry_variant in missions.list_scan_accepted():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("building_id", "")) != _building_id:
			continue
		out.append(entry)
	return out


func _bounty_accepted_for_building(missions: MissionSubsystem) -> Array:
	var out: Array = []
	for entry_variant in missions.list_bounty_accepted():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("building_id", "")) != _building_id:
			continue
		out.append(entry)
	return out


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

	inner.add_child(_one_line_label(str(offer.get("designation", "Survey"))))
	var meta := _offer_meta_line(offer)
	inner.add_child(_one_line_label(meta, &"Muted"))
	var reputation_line := _reputation_requirement_line(offer)
	if not reputation_line.is_empty():
		inner.add_child(_one_line_label(reputation_line, &"Muted"))
	var timing := _charter_timing_line(offer)
	if not timing.is_empty():
		inner.add_child(_one_line_label(timing, &"Muted"))
	inner.add_child(_tile_body_label(str(offer.get("description", ""))))

	var ship_id := _active_ship_id()
	var check := missions.evaluate_scan_offer(
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
		if missions.accept_scan_offer(_context.session, _context.catalog, offer_id, ship_id):
			refresh()
	)
	inner.add_child(accept)

	var tooltip := CharterTooltipText.format_scan(
		offer,
		str(check.get("reason", "")),
		"",
		"",
		_context.session.gst_seconds,
		_context.catalog
	)
	return _surface_tile(inner, tooltip)


func _bounty_offer_tile(missions: MissionSubsystem, offer: Dictionary) -> PanelContainer:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)

	inner.add_child(_one_line_label(str(offer.get("target_callsign", "Target"))))
	var meta := "%s · d%d" % [str(offer.get("site_label", "")), int(offer.get("reward", 0))]
	inner.add_child(_one_line_label(meta, &"Muted"))
	var timing := _charter_timing_line(offer)
	if not timing.is_empty():
		inner.add_child(_one_line_label(timing, &"Muted"))
	inner.add_child(_tile_body_label(str(offer.get("description", ""))))

	var ship_id := _active_ship_id()
	var check := missions.evaluate_bounty_offer(
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
		if missions.accept_bounty_offer(_context.session, _context.catalog, offer_id, ship_id):
			refresh()
	)
	inner.add_child(accept)

	var tooltip := CharterTooltipText.format_bounty(
		offer,
		str(check.get("reason", "")),
		"",
		"",
		_context.session.gst_seconds,
		_context.catalog
	)
	return _surface_tile(inner, tooltip)


func _bounty_accepted_tile(missions: MissionSubsystem, charter: Dictionary) -> PanelContainer:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)

	inner.add_child(_one_line_label(str(charter.get("target_callsign", "Target"))))
	var ship := _context.session.get_owned_ship(str(charter.get("ship_id", "")))
	var ship_name := ship.name if ship != null else str(charter.get("ship_id", ""))
	var origin := _habitat_name(str(charter.get("origin_habitat_id", "")))
	inner.add_child(_one_line_label(_accepted_meta_line(charter, origin, ship_name), &"Muted"))
	var timing := _charter_timing_line(charter)
	if not timing.is_empty():
		inner.add_child(_one_line_label(timing, &"Muted"))
	inner.add_child(_tile_body_label(str(charter.get("description", ""))))

	var charter_id := str(charter.get("charter_id", ""))
	var status_line := ""
	if missions.cancel_bounty_charter_eligible(_context.session, charter_id):
		var cfg := BountyCharters.config(_context.catalog)
		var penalty := BountyCharters.cancel_penalty(cfg, int(charter.get("reward", 0)))
		var cancel := Button.new()
		cancel.text = "Cancel (fee d%d)" % penalty
		cancel.pressed.connect(func() -> void:
			if missions.cancel_bounty_charter(_context.session, _context.catalog, charter_id):
				refresh()
		)
		inner.add_child(cancel)
	else:
		status_line = "In progress - cannot cancel."
		inner.add_child(_one_line_label(status_line, &"Muted"))

	var tooltip := CharterTooltipText.format_bounty(
		charter,
		status_line,
		origin,
		ship_name,
		_context.session.gst_seconds,
		_context.catalog
	)
	return _surface_tile(inner, tooltip)


func _accepted_tile(missions: MissionSubsystem, charter: Dictionary) -> PanelContainer:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)

	inner.add_child(_one_line_label(str(charter.get("designation", "Survey"))))
	var ship := _context.session.get_owned_ship(str(charter.get("ship_id", "")))
	var ship_name := ship.name if ship != null else str(charter.get("ship_id", ""))
	var origin := _habitat_name(str(charter.get("origin_habitat_id", "")))
	inner.add_child(_one_line_label(_accepted_meta_line(charter, origin, ship_name), &"Muted"))
	var timing := _charter_timing_line(charter)
	if not timing.is_empty():
		inner.add_child(_one_line_label(timing, &"Muted"))
	inner.add_child(_tile_body_label(str(charter.get("description", ""))))

	var charter_id := str(charter.get("charter_id", ""))
	var status_line := ""
	if missions.cancel_scan_charter_eligible(_context.session, charter_id):
		var cfg := ScanCharters.config(_context.catalog)
		var penalty := ScanCharters.cancel_penalty(cfg, int(charter.get("reward", 0)))
		var cancel := Button.new()
		cancel.text = "Cancel (fee d%d)" % penalty
		cancel.pressed.connect(func() -> void:
			if missions.cancel_scan_charter(_context.session, _context.catalog, charter_id):
				refresh()
		)
		inner.add_child(cancel)
	else:
		status_line = "In progress - cannot cancel."
		inner.add_child(_one_line_label(status_line, &"Muted"))

	var tooltip := CharterTooltipText.format_scan(
		charter,
		status_line,
		origin,
		ship_name,
		_context.session.gst_seconds,
		_context.catalog
	)
	return _surface_tile(inner, tooltip)


func _offer_meta_line(offer: Dictionary) -> String:
	return "%s · d%d" % [str(offer.get("site_label", "")), int(offer.get("reward", 0))]


func _accepted_meta_line(charter: Dictionary, origin: String, ship_name: String) -> String:
	return "%s → %s → %s · %s · d%d" % [
		origin,
		str(charter.get("site_label", "")),
		origin,
		ship_name,
		int(charter.get("reward", 0)),
	]


func _charter_timing_line(entry: Dictionary) -> String:
	if entry.has("deadline_gst"):
		var remaining := float(entry.get("deadline_gst", 0.0)) - _context.session.gst_seconds
		if remaining <= 0.0:
			return "Past deadline"
		return "%s remaining" % GalacticCalendar.format_duration(remaining)
	var hours := int(entry.get("deadline_hours", 0))
	if hours <= 0:
		return ""
	return "Within %d h" % hours


func _reputation_requirement_line(entry: Dictionary) -> String:
	var minimum := int(entry.get("min_reputation", 0))
	if minimum <= 0:
		return ""
	return "Requires reputation %d" % minimum


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
	_context.charter_ship_id = docked[0].id


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


func _tile_body_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = &"Muted"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


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
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.text = text
	return label


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
