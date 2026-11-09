extends GameScreen

const SCAN_PANEL := preload("res://scenes/ui/scan_charter_panel.tscn")
const TAPE_TOP_UP_MAX_TRIES := 12

var _layout: VBoxContainer
var _tape_bar: MessageBar
var _scan_panel: Control
var _tabs: TabContainer
var _solutions_board: CharterBoard
var _building: Dictionary = {}
var _tape_rng := RandomNumberGenerator.new()
var _tape_started := false
var _built_selling := false
var _structure_ready := false


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


func session_changed() -> void:
	if not is_node_ready() or _context == null:
		return
	if _can_soft_refresh() and _selling() == _built_selling:
		_top_up_tape()
		_apply_tab_titles()
		if _scan_panel != null and _scan_panel.has_method("session_changed"):
			_scan_panel.session_changed()
		elif _scan_panel != null and _scan_panel.has_method("refresh"):
			_scan_panel.refresh()
		_present_solutions()
		return
	refresh()


func refresh() -> void:
	if not is_node_ready() or _context == null:
		return
	_reset_tape()
	_ensure_structure()
	if _scan_panel != null and is_instance_valid(_scan_panel):
		if _scan_panel.has_method("configure"):
			_scan_panel.configure(_building)
		if _scan_panel.has_method("refresh"):
			_scan_panel.refresh()
	_present_solutions()


func _can_soft_refresh() -> bool:
	return _tape_started and _scan_panel != null and is_instance_valid(_scan_panel)


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


func _selling() -> bool:
	if _context == null or _context.catalog == null:
		return false
	return TranslationMarket.corporate_sells(_context.catalog, _building)


func _ensure_structure() -> void:
	if _layout == null or not is_instance_valid(_layout):
		return
	var selling := _selling()
	if _structure_ready and selling == _built_selling and _scan_panel != null and is_instance_valid(_scan_panel):
		_apply_tab_titles()
		return
	_destroy_structure()
	_built_selling = selling
	_structure_ready = true
	if not selling:
		_mount_scan_panel(_layout)
		return
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_child(_tabs)
	var charter_host := _tab_host()
	_tabs.add_child(charter_host)
	_mount_scan_panel(charter_host)
	var solutions_host := _tab_host()
	_tabs.add_child(solutions_host)
	_solutions_board = CharterBoard.new()
	_solutions_board.include_ship_line = false
	_solutions_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_solutions_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_solutions_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_solutions_board.rerender = Callable(self, "refresh")
	solutions_host.add_child(_solutions_board)
	_apply_tab_titles()


func _tab_host() -> Control:
	var host := Control.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return host


func _apply_tab_titles() -> void:
	if _tabs == null or not is_instance_valid(_tabs) or _tabs.get_tab_count() < 2:
		return
	var voice := ""
	if _context != null and _context.catalog != null:
		var corp := _context.catalog.get_corporation(str(_building.get("corporation_id", "")))
		voice = str(corp.get("ad_voice", ""))
	_tabs.set_tab_title(0, TranslationMarket.charter_tab_title(voice))
	_tabs.set_tab_title(1, TranslationMarket.SOLUTIONS_TAB_TITLE)


func _present_solutions() -> void:
	if _solutions_board == null or not is_instance_valid(_solutions_board):
		return
	if _context == null:
		return
	_solutions_board.present(_context, Callable(self, "_solution_sections"))


func _solution_sections() -> Array:
	var section := CharterBoardSection.new()
	section.empty_text = "Nothing listed today."
	var market: TranslationMarket = null
	if _context != null and _context.simulation != null:
		market = _context.simulation.get_subsystem("translation_market") as TranslationMarket
	var building_id := str(_building.get("id", ""))
	if (
		market == null
		or _context == null
		or _context.session == null
		or _context.catalog == null
		or building_id.is_empty()
	):
		section.chits = []
	else:
		section.chits = TranslationSolutionChits.for_board(
			_context.session,
			_context.catalog,
			market,
			building_id
		)
	return [section]


func _destroy_structure() -> void:
	if _tabs != null and is_instance_valid(_tabs):
		_tabs.queue_free()
	elif _scan_panel != null and is_instance_valid(_scan_panel):
		_scan_panel.queue_free()
	_scan_panel = null
	_tabs = null
	_solutions_board = null
	_structure_ready = false


func _mount_scan_panel(parent: Node) -> void:
	_scan_panel = SCAN_PANEL.instantiate()
	_scan_panel.layout_mode = 2
	_scan_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scan_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_scan_panel)
	if _scan_panel.has_method("bind"):
		_scan_panel.bind(_context)
	if _scan_panel.has_method("configure"):
		_scan_panel.configure(_building)
