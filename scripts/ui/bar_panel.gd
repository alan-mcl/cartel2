extends GameScreen

const CHARTER_PANEL := preload("res://scenes/ui/passenger_charter_panel.tscn")
const GOSSIP_TAPE_TOP_UP_MAX_TRIES := 12

var _layout: VBoxContainer
var _charter_host: Control
var _charter_panel: Control
var _gossip_bar: MessageBar
var _gossip_rng := RandomNumberGenerator.new()
var _gossip_started := false


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

	_charter_host = Control.new()
	_charter_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_charter_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_child(_charter_host)

	_gossip_rng.randomize()
	set_process(false)


func refresh() -> void:
	if not is_node_ready() or _context == null:
		return
	_reset_gossip_tape()
	_ensure_charter_panel()
	if _charter_panel != null and _charter_panel.has_method("refresh"):
		_charter_panel.refresh()


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


func _ensure_charter_panel() -> void:
	if _charter_host == null or not is_instance_valid(_charter_host):
		return
	if _charter_panel != null and is_instance_valid(_charter_panel):
		return
	_clear_children(_charter_host)
	_charter_panel = CHARTER_PANEL.instantiate()
	_charter_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_charter_panel.board_mode = PassengerCharters.BOARD_BAR
	_charter_host.add_child(_charter_panel)
	if _charter_panel.has_method("bind"):
		_charter_panel.bind(_context)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
