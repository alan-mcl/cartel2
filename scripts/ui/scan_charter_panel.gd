extends GameScreen

var _building_id: String = ""
var _resolve_ship_id: Callable = Callable()
var _board: CharterBoard


func configure(building: Dictionary) -> void:
	_building_id = str(building.get("id", ""))


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
		_board.rerender = Callable(self, "refresh")
		_board.expand_plain_labels = true
		add_child(_board)
	var blocked := _blocked_text()
	if blocked.is_empty():
		var missions := _missions()
		if missions != null:
			missions.ensure_boards(_context.session, _context.catalog)
	_board.present(_context, Callable(self, "_sections"), blocked)


func _blocked_text() -> String:
	if _missions() == null or _building_id.is_empty():
		return "Scan charter desk unavailable."
	return ""


func _sections() -> Array:
	var missions := _missions()
	var habitat_id := _context.session.habitat_id
	var scans := CharterBoardSection.new()
	scans.heading = "POSTED SCANS"
	scans.empty_text = "No scan work posted today."
	scans.rows = missions.list_scan_offers(habitat_id, _building_id)
	scans.describe = Callable(self, "_describe_scan_offer")
	scans.act = Callable(self, "_accept_scan")

	var your_scans := CharterBoardSection.new()
	your_scans.heading = "YOUR SCANS"
	your_scans.empty_text = "No accepted scan charters."
	your_scans.rows = _accepted_for_building(missions.list_scan_accepted())
	your_scans.describe = Callable(self, "_describe_scan_accepted")
	your_scans.act = Callable(self, "_cancel_scan")

	var bounties := CharterBoardSection.new()
	bounties.heading = "POSTED BOUNTIES"
	bounties.empty_text = "No bounties posted today."
	bounties.rows = missions.list_bounty_offers(habitat_id, _building_id)
	bounties.describe = Callable(self, "_describe_bounty_offer")
	bounties.act = Callable(self, "_accept_bounty")

	var your_bounties := CharterBoardSection.new()
	your_bounties.heading = "YOUR BOUNTIES"
	your_bounties.empty_text = "No accepted bounties."
	your_bounties.rows = _accepted_for_building(missions.list_bounty_accepted())
	your_bounties.describe = Callable(self, "_describe_bounty_accepted")
	your_bounties.act = Callable(self, "_cancel_bounty")
	return [scans, your_scans, bounties, your_bounties]


func _accepted_for_building(entries: Array) -> Array:
	var out: Array = []
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("building_id", "")) != _building_id:
			continue
		out.append(entry)
	return out


func _describe_scan_offer(offer: Dictionary, ship_id: String) -> Dictionary:
	var lines := _scan_offer_lines(offer)
	var check := _missions().evaluate_scan_offer(
		_context.session,
		_context.catalog,
		str(offer.get("id", "")),
		ship_id
	)
	return {
		"title": str(offer.get("designation", "Survey")),
		"lines": lines,
		"body": str(offer.get("description", "")),
		"button_text": "Accept",
		"button_enabled": bool(check.get("ok", false)),
		"tooltip": CharterTooltipText.format_scan(
			offer,
			str(check.get("reason", "")),
			"",
			"",
			_context.session.gst_seconds,
			_context.catalog
		),
		"status": "",
	}


func _describe_bounty_offer(offer: Dictionary, ship_id: String) -> Dictionary:
	var lines: Array = []
	lines.append("%s · d%d" % [str(offer.get("site_label", "")), int(offer.get("reward", 0))])
	var timing := _charter_timing_line(offer)
	if not timing.is_empty():
		lines.append(timing)
	var check := _missions().evaluate_bounty_offer(
		_context.session,
		_context.catalog,
		str(offer.get("id", "")),
		ship_id
	)
	return {
		"title": str(offer.get("target_callsign", "Target")),
		"lines": lines,
		"body": str(offer.get("description", "")),
		"button_text": "Accept",
		"button_enabled": bool(check.get("ok", false)),
		"tooltip": CharterTooltipText.format_bounty(
			offer,
			str(check.get("reason", "")),
			"",
			"",
			_context.session.gst_seconds,
			_context.catalog
		),
		"status": "",
	}


func _describe_scan_accepted(charter: Dictionary, _ship_id: String) -> Dictionary:
	return _describe_accepted_contract(
		charter,
		str(charter.get("designation", "Survey")),
		_missions().cancel_scan_charter_eligible(_context.session, str(charter.get("charter_id", ""))),
		ScanCharters.cancel_penalty(
			ScanCharters.config(_context.catalog),
			int(charter.get("reward", 0))
		),
		true
	)


func _describe_bounty_accepted(charter: Dictionary, _ship_id: String) -> Dictionary:
	return _describe_accepted_contract(
		charter,
		str(charter.get("target_callsign", "Target")),
		_missions().cancel_bounty_charter_eligible(_context.session, str(charter.get("charter_id", ""))),
		BountyCharters.cancel_penalty(
			BountyCharters.config(_context.catalog),
			int(charter.get("reward", 0))
		),
		false
	)


func _describe_accepted_contract(
	charter: Dictionary,
	title: String,
	eligible: bool,
	penalty: int,
	scan_tooltip: bool
) -> Dictionary:
	var ship_name := CharterBoard.ship_name(_context.session, str(charter.get("ship_id", "")))
	var origin := CharterBoard.habitat_name(_context.catalog, str(charter.get("origin_habitat_id", "")))
	var lines: Array = []
	lines.append(_accepted_meta_line(charter, origin, ship_name))
	var timing := _charter_timing_line(charter)
	if not timing.is_empty():
		lines.append(timing)
	var status_line := ""
	var button_text := ""
	if eligible:
		button_text = "Cancel (fee d%d)" % penalty
	else:
		status_line = "In progress - cannot cancel."
	var tooltip := ""
	if scan_tooltip:
		tooltip = CharterTooltipText.format_scan(
			charter,
			status_line,
			origin,
			ship_name,
			_context.session.gst_seconds,
			_context.catalog
		)
	else:
		tooltip = CharterTooltipText.format_bounty(
			charter,
			status_line,
			origin,
			ship_name,
			_context.session.gst_seconds,
			_context.catalog
		)
	return {
		"title": title,
		"lines": lines,
		"body": str(charter.get("description", "")),
		"button_text": button_text,
		"button_enabled": true,
		"tooltip": tooltip,
		"status": status_line,
	}


func _accept_scan(offer: Dictionary, ship_id: String) -> bool:
	return _missions().accept_scan_offer(
		_context.session,
		_context.catalog,
		str(offer.get("id", "")),
		ship_id
	)


func _cancel_scan(charter: Dictionary, _ship_id: String) -> bool:
	return _missions().cancel_scan_charter(
		_context.session,
		_context.catalog,
		str(charter.get("charter_id", ""))
	)


func _accept_bounty(offer: Dictionary, ship_id: String) -> bool:
	return _missions().accept_bounty_offer(
		_context.session,
		_context.catalog,
		str(offer.get("id", "")),
		ship_id
	)


func _cancel_bounty(charter: Dictionary, _ship_id: String) -> bool:
	return _missions().cancel_bounty_charter(
		_context.session,
		_context.catalog,
		str(charter.get("charter_id", ""))
	)


func _scan_offer_lines(offer: Dictionary) -> Array:
	var lines: Array = []
	lines.append("%s · d%d" % [str(offer.get("site_label", "")), int(offer.get("reward", 0))])
	var reputation_line := CharterBoard.reputation_line(offer)
	if not reputation_line.is_empty():
		lines.append(reputation_line)
	var timing := _charter_timing_line(offer)
	if not timing.is_empty():
		lines.append(timing)
	return lines


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


func _missions() -> MissionSubsystem:
	if _context == null or _context.simulation == null:
		return null
	return _context.simulation.get_subsystem("missions") as MissionSubsystem


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
