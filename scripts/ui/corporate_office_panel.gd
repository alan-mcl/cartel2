extends GameScreen

const SCAN_PANEL := preload("res://scenes/ui/scan_charter_panel.tscn")
const TAPE_TOP_UP_MAX_TRIES := 12

var _layout: VBoxContainer
var _tape_bar: MessageBar
var _scan_panel: Control
var _building: Dictionary = {}
var _tape_rng := RandomNumberGenerator.new()
var _tape_started := false


func _ready() -> void:
	_layout = VBoxContainer.new()
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_theme_constant_override("separation", 8)
	add_child(_layout)

	_tape_bar = UiPatterns.message_bar()
	_tape_bar.custom_minimum_size = Vector2(0, 28)
	_tape_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout.add_child(_tape_bar)

	_tape_rng.randomize()
	set_process(false)
	_apply_tape_tag()


func configure(building: Dictionary) -> void:
	_building = building.duplicate(true)
	_apply_tape_tag()


func _apply_tape_tag() -> void:
	if _tape_bar == null:
		return
	var corp_id := str(_building.get("corporation_id", "")).strip_edges()
	var tag := "CORP"
	if not corp_id.is_empty() and _context != null and _context.catalog != null:
		var corp := _context.catalog.get_corporation(corp_id)
		tag = str(corp.get("callsign_prefix", tag)).strip_edges()
	if tag.is_empty():
		tag = "CORP"
	_tape_bar.set_tag(tag)


func refresh() -> void:
	if not is_node_ready() or _context == null:
		return
	_reset_tape()
	_ensure_scan_panel()
	if _scan_panel != null and is_instance_valid(_scan_panel):
		if _scan_panel.has_method("configure"):
			_scan_panel.configure(_building)
		if _scan_panel.has_method("refresh"):
			_scan_panel.refresh()


func _process(_delta: float) -> void:
	if not _tape_started or not is_inside_tree():
		return
	_top_up_tape()


func _reset_tape() -> void:
	if _tape_bar != null:
		_tape_bar.clear_queued_lines()
	_tape_started = true
	set_process(true)
	_top_up_tape()


func _enqueue_tape_line() -> bool:
	if (
		_tape_bar == null
		or _context == null
		or _context.session == null
		or _context.catalog == null
		or _building.is_empty()
	):
		return false
	var line := CorporateOfficeTape.next_line(
		_context.catalog,
		_context.session,
		_context.simulation,
		_building,
		_tape_rng
	)
	if line.is_empty():
		return false
	return _tape_bar.play_line(line, true, true)


func _top_up_tape() -> void:
	if _tape_bar == null:
		return
	var tries := 0
	while _tape_bar.wants_more_log_lines() and tries < TAPE_TOP_UP_MAX_TRIES:
		if not _enqueue_tape_line():
			break
		tries += 1


func _ensure_scan_panel() -> void:
	if _layout == null or not is_instance_valid(_layout):
		return
	if _scan_panel != null and is_instance_valid(_scan_panel):
		return
	_scan_panel = SCAN_PANEL.instantiate()
	_scan_panel.layout_mode = 2
	_scan_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scan_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_child(_scan_panel)
	if _scan_panel.has_method("bind"):
		_scan_panel.bind(_context)
	if _scan_panel.has_method("configure"):
		_scan_panel.configure(_building)
