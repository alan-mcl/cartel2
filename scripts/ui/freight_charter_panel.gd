extends GameScreen

var _resolve_ship_id: Callable = Callable()
var _board: CharterBoard


func set_ship_resolver(resolver: Callable) -> void:
	_resolve_ship_id = resolver


func refresh() -> void:
	if not is_node_ready() or _context == null or _context.session == null or _context.catalog == null:
		return
	if _board == null or not is_instance_valid(_board):
		_clear_children(self)
		_board = CharterBoard.new()
		_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_board.resolve_ship_id = _resolve_ship_id
		_board.ship_score = Callable(self, "_ship_score")
		_board.rerender = Callable(self, "refresh")
		add_child(_board)
	var blocked := _blocked_text()
	if blocked.is_empty():
		var missions := _missions()
		if missions != null:
			missions.ensure_boards(_context.session, _context.catalog)
	_board.present(_context, Callable(self, "_sections"), blocked)


func _blocked_text() -> String:
	if _missions() == null:
		return "Freight services unavailable."
	return ""


func _sections() -> Array:
	var missions := _missions()
	var habitat_id := _context.session.habitat_id
	var posted := CharterBoardSection.new()
	posted.heading = "POSTED FREIGHT"
	posted.empty_text = "No freight posted today."
	posted.rows = missions.list_freight_offers(habitat_id)
	posted.describe = Callable(self, "_describe_offer")
	posted.act = Callable(self, "_accept_offer")

	var yours := CharterBoardSection.new()
	yours.heading = "YOUR FREIGHT"
	yours.empty_text = "No accepted freight."
	yours.rows = missions.list_freight_accepted()
	yours.describe = Callable(self, "_describe_accepted")
	yours.act = Callable(self, "_cancel_charter")
	return [posted, yours]


func _describe_offer(offer: Dictionary, ship_id: String) -> Dictionary:
	var lines: Array = []
	lines.append(_offer_meta_line(offer))
	lines.append(_budget_line(offer))
	var timing := _charter_timing_line(offer)
	if not timing.is_empty():
		lines.append(timing)
	lines.append(str(offer.get("hold_label", "Dry hold")))
	var reputation_line := CharterBoard.reputation_line(offer)
	if not reputation_line.is_empty():
		lines.append(reputation_line)
	var check := _missions().evaluate_freight_offer(
		_context.session,
		_context.catalog,
		str(offer.get("id", "")),
		ship_id
	)
	return {
		"title": str(offer.get("description", "Freight")),
		"lines": lines,
		"button_text": "Accept",
		"button_enabled": bool(check.get("ok", false)),
		"tooltip": CharterTooltipText.format_freight(offer, str(check.get("reason", ""))),
		"status": "",
	}


func _describe_accepted(charter: Dictionary, _ship_id: String) -> Dictionary:
	var ship_name := CharterBoard.ship_name(_context.session, str(charter.get("ship_id", "")))
	var origin := CharterBoard.habitat_name(_context.catalog, str(charter.get("origin_habitat_id", "")))
	var lines: Array = []
	lines.append(_accepted_meta_line(charter, origin, ship_name))
	lines.append(_budget_line(charter))
	var timing := _charter_timing_line(charter)
	if not timing.is_empty():
		lines.append(timing)
	var charter_id := str(charter.get("charter_id", ""))
	var status_line := ""
	var button_text := ""
	if _missions().cancel_freight_charter_eligible(_context.session, charter_id):
		var cfg := FreightCharters.config(_context.catalog)
		var penalty := FreightCharters.cancel_penalty(cfg, int(charter.get("reward", 0)))
		button_text = "Cancel (fee d%d)" % penalty
	else:
		status_line = "In transit - cannot cancel."
	return {
		"title": str(charter.get("description", "Freight")),
		"lines": lines,
		"button_text": button_text,
		"button_enabled": true,
		"tooltip": CharterTooltipText.format_freight(charter, status_line, origin, ship_name),
		"status": status_line,
	}


func _accept_offer(offer: Dictionary, ship_id: String) -> bool:
	return _missions().accept_freight_offer(
		_context.session,
		_context.catalog,
		str(offer.get("id", "")),
		ship_id
	)


func _cancel_charter(charter: Dictionary, _ship_id: String) -> bool:
	return _missions().cancel_freight_charter(
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


func _ship_score(ship: OwnedShip) -> float:
	var assembled := ShipAssembler.assemble_owned(_context.catalog, ship)
	return float(assembled.capacities.get("cargo_capacity", 0.0))


func _missions() -> MissionSubsystem:
	if _context == null or _context.simulation == null:
		return null
	return _context.simulation.get_subsystem("missions") as MissionSubsystem


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
