class_name CharterDeskPanel
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
		_board.rerender = Callable(self, "refresh")
		_configure_board(_board)
		add_child(_board)
	var blocked := _blocked_text()
	if blocked.is_empty():
		_ensure_mission_boards()
	_board.present(_context, Callable(self, "_sections"), blocked)


func _configure_board(_board_node: CharterBoard) -> void:
	pass


func _blocked_text() -> String:
	return ""


func _sections() -> Array:
	return []


func _ensure_mission_boards() -> void:
	var missions := _missions()
	if missions != null:
		missions.ensure_boards(_context.session, _context.catalog)


func _missions() -> MissionSubsystem:
	if _context == null or _context.simulation == null:
		return null
	return _context.simulation.get_subsystem("missions") as MissionSubsystem


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()