extends GameScreen

var board_mode: String = PassengerCharters.BOARD_TERMINAL
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
		add_child(_plain_label("Charter services unavailable."))
		return

	missions.ensure_boards(_context.session, _context.catalog)
	var habitat_id := _context.session.habitat_id
	var docked := _context.session.ships_at(habitat_id)
	_sync_charter_ship_id(docked)
	var offers := missions.list_offers(habitat_id, board_mode)
	var accepted := missions.list_accepted()

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

	if board_mode == PassengerCharters.BOARD_BAR:
		body.add_child(_section_label("INFORMAL FARES"))
		if offers.is_empty():
			body.add_child(_plain_label("No word-of-mouth fares tonight."))
	else:
		body.add_child(_section_label("POSTED CHARTERS"))
		if offers.is_empty():
			body.add_child(_plain_label("No departures posted today."))
	if not offers.is_empty():
		for offer_variant in offers:
			if typeof(offer_variant) != TYPE_DICTIONARY:
				continue
			body.add_child(_offer_row(missions, offer_variant))

	body.add_child(_section_label("YOUR CHARTERS"))
	if accepted.is_empty():
		body.add_child(_plain_label("No accepted charters."))
	else:
		for charter_variant in accepted:
			if typeof(charter_variant) != TYPE_DICTIONARY:
				continue
			body.add_child(_accepted_row(missions, charter_variant))


func _offer_row(missions: MissionSubsystem, offer: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := _plain_label(
		"%s · d%d · %s" % [
			str(offer.get("role_title", "Charter")),
			int(offer.get("reward", 0)),
			str(offer.get("destination_name", "")),
		]
	)
	box.add_child(title)

	var detail := _plain_label(str(offer.get("description", "")))
	box.add_child(detail)

	var corp := str(offer.get("corporation_name", ""))
	if not corp.is_empty():
		box.add_child(_plain_label("Affiliation: %s" % corp))

	var ship_id := _active_ship_id()
	var check := missions.evaluate_offer(
		_context.session,
		_context.catalog,
		str(offer.get("id", "")),
		ship_id
	)
	if not bool(check.get("ok", false)):
		box.add_child(_plain_label(str(check.get("reason", ""))))

	var accept := Button.new()
	accept.text = "Accept"
	accept.disabled = not bool(check.get("ok", false))
	var offer_id := str(offer.get("id", ""))
	accept.pressed.connect(func() -> void:
		if missions.accept_offer(_context.session, _context.catalog, offer_id, ship_id):
			refresh()
	)
	box.add_child(accept)
	return box


func _accepted_row(missions: MissionSubsystem, charter: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var ship := _context.session.get_owned_ship(str(charter.get("ship_id", "")))
	var ship_name := ship.name if ship != null else str(charter.get("ship_id", ""))
	var origin := _habitat_name(str(charter.get("origin_habitat_id", "")))
	box.add_child(
		_plain_label(
			"%s · %s → %s · %s · d%d" % [
				str(charter.get("role_title", "Charter")),
				origin,
				str(charter.get("destination_name", "")),
				ship_name,
				int(charter.get("reward", 0)),
			]
		)
	)
	box.add_child(_plain_label(str(charter.get("description", ""))))

	var charter_id := str(charter.get("charter_id", ""))
	if missions.cancel_charter_eligible(_context.session, charter_id):
		var cfg := PassengerCharters.config(_context.catalog)
		var penalty := PassengerCharters.cancel_penalty(cfg, int(charter.get("reward", 0)))
		var cancel := Button.new()
		cancel.text = "Cancel (fee d%d)" % penalty
		cancel.pressed.connect(func() -> void:
			if missions.cancel_charter(_context.session, _context.catalog, charter_id):
				refresh()
		)
		box.add_child(cancel)
	else:
		box.add_child(_plain_label("In transit — cannot cancel."))
	return box


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
		if ship.id == preferred and _life_support_capacity(ship) > 0.0:
			return ship.id
	var best_id := ""
	var best_cap := -1.0
	for ship in docked:
		var cap := _life_support_capacity(ship)
		if cap > best_cap:
			best_cap = cap
			best_id = ship.id
	return best_id


func _life_support_capacity(ship: OwnedShip) -> float:
	var assembled := ShipAssembler.assemble_owned(_context.catalog, ship)
	return float(assembled.capacities.get("life_support_capacity", 0.0))


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


func _plain_label(text: String) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	return label


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
