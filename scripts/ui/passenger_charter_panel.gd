extends GameScreen

var board_mode: String = PassengerCharters.BOARD_TERMINAL
var _resolve_ship_id: Callable = Callable()


func set_ship_resolver(resolver: Callable) -> void:
	_resolve_ship_id = resolver


func refresh() -> void:
	if not is_node_ready() or _context == null or _context.session == null or _context.catalog == null:
		return
	_clear_children(self)
	var board := CharterBoard.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.resolve_ship_id = _resolve_ship_id
	board.ship_score = Callable(self, "_ship_score")
	board.rerender = Callable(self, "refresh")
	add_child(board)
	var blocked := _blocked_text()
	if blocked.is_empty():
		var missions := _missions()
		if missions != null:
			missions.ensure_boards(_context.session, _context.catalog)
	board.present(_context, Callable(self, "_sections"), blocked)


func _blocked_text() -> String:
	if _missions() == null:
		return "Charter services unavailable."
	return ""


func _sections() -> Array:
	var missions := _missions()
	var habitat_id := _context.session.habitat_id
	var posted := CharterBoardSection.new()
	if board_mode == PassengerCharters.BOARD_BAR:
		posted.heading = "INFORMAL FARES"
		posted.empty_text = "No word-of-mouth fares tonight."
	else:
		posted.heading = "POSTED CHARTERS"
		posted.empty_text = "No departures posted today."
	posted.rows = missions.list_offers(habitat_id, board_mode)
	posted.describe = Callable(self, "_describe_offer")
	posted.act = Callable(self, "_accept_offer")

	var yours := CharterBoardSection.new()
	yours.heading = "YOUR CHARTERS"
	yours.empty_text = "No accepted charters."
	yours.rows = missions.list_accepted()
	yours.describe = Callable(self, "_describe_accepted")
	yours.act = Callable(self, "_cancel_charter")
	return [posted, yours]


func _describe_offer(offer: Dictionary, ship_id: String) -> Dictionary:
	var lines: Array = []
	lines.append(_offer_meta_line(offer))
	lines.append(_life_support_tile_line(offer))
	var reputation_line := CharterBoard.reputation_line(offer)
	if not reputation_line.is_empty():
		lines.append(reputation_line)
	var timing := _charter_timing_line(offer)
	if not timing.is_empty():
		lines.append(timing)
	var check := _missions().evaluate_offer(
		_context.session,
		_context.catalog,
		str(offer.get("id", "")),
		ship_id
	)
	return {
		"title": str(offer.get("role_title", "Charter")),
		"lines": lines,
		"body": str(offer.get("description", "")),
		"button_text": "Accept",
		"button_enabled": bool(check.get("ok", false)),
		"tooltip": CharterTooltipText.format_passenger(offer, str(check.get("reason", ""))),
		"status": "",
	}


func _describe_accepted(charter: Dictionary, _ship_id: String) -> Dictionary:
	var ship_name := CharterBoard.ship_name(_context.session, str(charter.get("ship_id", "")))
	var origin := CharterBoard.habitat_name(_context.catalog, str(charter.get("origin_habitat_id", "")))
	var lines: Array = []
	lines.append(_accepted_meta_line(charter, origin, ship_name))
	lines.append(_life_support_tile_line(charter))
	var timing := _charter_timing_line(charter)
	if not timing.is_empty():
		lines.append(timing)
	var charter_id := str(charter.get("charter_id", ""))
	var status_line := ""
	var button_text := ""
	if _missions().cancel_charter_eligible(_context.session, charter_id):
		var cfg := PassengerCharters.config(_context.catalog)
		var penalty := PassengerCharters.cancel_penalty(cfg, int(charter.get("reward", 0)))
		button_text = "Cancel (fee d%d)" % penalty
	else:
		status_line = "In transit - cannot cancel."
	return {
		"title": str(charter.get("role_title", "Charter")),
		"lines": lines,
		"body": str(charter.get("description", "")),
		"button_text": button_text,
		"button_enabled": true,
		"tooltip": CharterTooltipText.format_passenger(charter, status_line, origin, ship_name),
		"status": status_line,
	}


func _accept_offer(offer: Dictionary, ship_id: String) -> bool:
	return _missions().accept_offer(
		_context.session,
		_context.catalog,
		str(offer.get("id", "")),
		ship_id
	)


func _cancel_charter(charter: Dictionary, _ship_id: String) -> bool:
	return _missions().cancel_charter(
		_context.session,
		_context.catalog,
		str(charter.get("charter_id", ""))
	)


func _destination_label(entry: Dictionary) -> String:
	return str(entry.get("destination_name", "")) + str(entry.get("via_label", ""))


func _charter_timing_line(entry: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var hours := int(entry.get("deadline_hours", 0))
	if hours > 0:
		parts.append("Within %d h" % hours)
	if int(entry.get("hops", 1)) > 1:
		parts.append("%d-hop · habitat life support" % int(entry.get("hops", 1)))
	if parts.is_empty():
		return ""
	return ", ".join(parts)


func _offer_meta_line(offer: Dictionary) -> String:
	var meta := "%s · %d pax · d%d" % [
		_destination_label(offer),
		int(offer.get("quantity", 0)),
		int(offer.get("reward", 0)),
	]
	var corp := str(offer.get("corporation_name", ""))
	if not corp.is_empty():
		meta += " · %s" % corp
	return meta


func _accepted_meta_line(charter: Dictionary, origin: String, ship_name: String) -> String:
	return "%s → %s · %s · d%d" % [
		origin,
		_destination_label(charter),
		ship_name,
		int(charter.get("reward", 0)),
	]


func _life_support_tile_line(entry: Dictionary) -> String:
	var tier := str(entry.get("life_support", "spartan"))
	return "Life support: %s" % _life_support_tier_name(tier)


func _life_support_tier_name(tier: String) -> String:
	match tier:
		"luxury":
			return "Luxury"
		"comfort":
			return "Comfort"
		_:
			return "Spartan"


func _ship_score(ship: OwnedShip) -> float:
	var assembled := ShipAssembler.assemble_owned(_context.catalog, ship)
	return float(assembled.capacities.get("life_support_capacity", 0.0))


func _missions() -> MissionSubsystem:
	if _context == null or _context.simulation == null:
		return null
	return _context.simulation.get_subsystem("missions") as MissionSubsystem


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
