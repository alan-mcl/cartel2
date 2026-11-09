extends GameScreen

const PASSENGER_CHARTER := preload("res://scripts/ui/passenger_charter_panel.gd")
const SCAN_CHARTER := preload("res://scripts/ui/scan_charter_panel.gd")
const FREIGHT_CHARTER := preload("res://scripts/ui/freight_charter_panel.gd")
const GOSSIP_TAPE_TOP_UP_MAX_TRIES := 12

var _layout: VBoxContainer
var _charter_host: Control
var _board: CharterBoard
var _passenger_factory: Control
var _scan_factory: Control
var _freight_factory: Control
var _gossip_bar: MessageBar
var _round_button: Button
var _gossip_rng := RandomNumberGenerator.new()
var _gossip_started := false
var _building: Dictionary = {}


func _ready() -> void:
	_layout = VBoxContainer.new()
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_theme_constant_override("separation", 8)
	add_child(_layout)

	_gossip_bar = UiPatterns.message_bar()
	_gossip_bar.set_tag("BAR")
	_gossip_bar.custom_minimum_size = Vector2(0, 28)
	_gossip_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout.add_child(_gossip_bar)

	_round_button = Button.new()
	_round_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_round_button.pressed.connect(_on_buy_round_pressed)
	add_child(_round_button)
	_round_button.visible = false

	_charter_host = Control.new()
	_charter_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_charter_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_child(_charter_host)

	_gossip_rng.randomize()
	set_process(false)


func configure(building: Dictionary) -> void:
	_building = building.duplicate(true)
	if _scan_factory != null and is_instance_valid(_scan_factory) and _scan_factory.has_method("configure"):
		_scan_factory.configure(_building)
	if _passenger_factory != null and is_instance_valid(_passenger_factory) and _passenger_factory.has_method("configure"):
		_passenger_factory.configure(_building)
	if _freight_factory != null and is_instance_valid(_freight_factory) and _freight_factory.has_method("configure_bar"):
		_freight_factory.configure_bar(str(_building.get("id", "")))


func session_changed() -> void:
	if not is_node_ready() or _context == null:
		return
	if _can_soft_refresh():
		_top_up_gossip_tape()
		_refresh_board()
		return
	refresh()


func refresh() -> void:
	if not is_node_ready() or _context == null:
		return
	_reset_gossip_tape()
	_refresh_round_button()
	_refresh_board()


func _can_soft_refresh() -> bool:
	return _gossip_started and _board != null and is_instance_valid(_board)


func _process(_delta: float) -> void:
	if not _gossip_started or not is_inside_tree():
		return
	_top_up_gossip_tape()


func _reset_gossip_tape() -> void:
	var messages := _messages_subsystem()
	if messages != null:
		messages.clear_channel(MessageChannels.GOSSIP)
	if _gossip_bar != null:
		_gossip_bar.clear_queued_lines()
	_gossip_started = true
	set_process(true)
	_top_up_gossip_tape()


func _messages_subsystem() -> MessageSubsystem:
	if _context == null or _context.simulation == null:
		return null
	return _context.simulation.get_subsystem("messages") as MessageSubsystem


func _enqueue_gossip_line() -> bool:
	var messages := _messages_subsystem()
	if messages == null or _context.session == null or _context.catalog == null or _gossip_bar == null:
		return false
	var sample := messages.next_line(
		MessageChannels.GOSSIP,
		_context.session,
		_context.catalog,
		_gossip_rng,
		_context.simulation
	)
	var line := _format_overheard(str(sample.get("text", "")))
	if line.is_empty():
		return false
	return _gossip_bar.play_line(line, true, true)


static func _format_overheard(text: String) -> String:
	var line := text.strip_edges()
	if line.is_empty():
		return ""
	if line.begins_with("\"") and line.ends_with("\""):
		return line
	return "\"%s\"" % line


func _top_up_gossip_tape() -> void:
	if _gossip_bar == null:
		return
	var tries := 0
	while _gossip_bar.wants_more_log_lines() and tries < GOSSIP_TAPE_TOP_UP_MAX_TRIES:
		if not _enqueue_gossip_line():
			break
		tries += 1


func _ensure_board() -> void:
	if _charter_host == null or not is_instance_valid(_charter_host):
		return
	if _board != null and is_instance_valid(_board):
		return
	_clear_children(_charter_host)
	_board = CharterBoard.new()
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.rerender = Callable(self, "refresh")
	_charter_host.add_child(_board)
	if _passenger_factory == null or not is_instance_valid(_passenger_factory):
		_passenger_factory = PASSENGER_CHARTER.new()
		_passenger_factory.board_mode = PassengerCharters.BOARD_BAR
	if _scan_factory == null or not is_instance_valid(_scan_factory):
		_scan_factory = SCAN_CHARTER.new()
	if _freight_factory == null or not is_instance_valid(_freight_factory):
		_freight_factory = FREIGHT_CHARTER.new()


func _sync_factories() -> void:
	if _passenger_factory != null and _passenger_factory.has_method("bind"):
		_passenger_factory.bind(_context)
	if _scan_factory != null:
		if _scan_factory.has_method("bind"):
			_scan_factory.bind(_context)
		if _scan_factory.has_method("configure"):
			_scan_factory.configure(_building)
	if _freight_factory != null:
		if _freight_factory.has_method("bind"):
			_freight_factory.bind(_context)
		if _freight_factory.has_method("configure_bar"):
			_freight_factory.configure_bar(str(_building.get("id", "")))


func _refresh_round_button() -> void:
	if _round_button == null or _context == null or _context.session == null or _context.catalog == null:
		return
	var building_id := str(_building.get("id", ""))
	if building_id.is_empty():
		building_id = str(_context.session.building_id)
	var missions := _missions()
	var habitat_id := str(_context.session.habitat_id)
	var cost := 0
	var day := CommodityEconomy.gst_day(_context.session.gst_seconds)
	if missions != null:
		cost = missions.bar_round_cost_for_habitat(_context.catalog, habitat_id)
	if missions != null and missions.bar_round_used_today(building_id, day):
		_round_button.disabled = true
		_round_button.text = "Round bought today"
	elif _context.session.credits < cost:
		_round_button.disabled = true
		_round_button.text = "Buy a round (d%d) — insufficient credits" % cost
	else:
		_round_button.disabled = false
		_round_button.text = "Buy a round (d%d)" % cost


func _on_buy_round_pressed() -> void:
	if _context == null or _context.session == null or _context.catalog == null:
		return
	var missions := _missions()
	if missions == null:
		return
	var building_id := str(_building.get("id", ""))
	if building_id.is_empty():
		building_id = str(_context.session.building_id)
	var result := missions.buy_bar_round(_context.session, _context.catalog, building_id)
	if not bool(result.get("ok", false)):
		var reason := str(result.get("reason", ""))
		if reason == "already_bought":
			_context.session.last_log = "You have already bought a round here today."
		elif reason == "insufficient_credits":
			_context.session.last_log = "Not enough credits for a round."
		else:
			_context.session.last_log = "Could not buy a round."
		_context.session.changed.emit()


func _refresh_board() -> void:
	if not is_node_ready() or _context == null:
		return
	_ensure_board()
	_sync_factories()
	if _board == null:
		return
	_board.ship_score = Callable(_passenger_factory, "_ship_score")
	_board.ship_line_trailing = _round_button
	_round_button.visible = true
	var blocked := _blocked_text()
	if blocked.is_empty():
		var missions := _missions()
		if missions != null:
			missions.ensure_boards(_context.session, _context.catalog)
	_board.present(_context, Callable(self, "_sections"), blocked)


func _blocked_text() -> String:
	if _missions() == null:
		return "Charter services unavailable."
	return ""


func _sections() -> Array:
	var posted := CharterBoardSection.new()
	posted.empty_text = "Nothing posted tonight."
	posted.chits = CharterBoard.interleave([
		_passenger_factory.posted_chits(),
		_freight_factory.posted_chits(),
		_scan_factory.posted_scan_chits(),
		_scan_factory.posted_bounty_chits(),
	])

	var accepted := CharterBoardSection.new()
	accepted.heading = "ACCEPTED"
	accepted.empty_text = "Nothing accepted."
	accepted.chits = CharterBoard.interleave([
		_passenger_factory.accepted_chits(),
		_freight_factory.accepted_chits(),
		_scan_factory.accepted_scan_chits(),
		_scan_factory.accepted_bounty_chits(),
	])
	return [posted, accepted]


func _missions() -> MissionSubsystem:
	if _context == null or _context.simulation == null:
		return null
	return _context.simulation.get_subsystem("missions") as MissionSubsystem


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
