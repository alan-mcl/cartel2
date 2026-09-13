class_name GameScreen
extends Control

var _context: UiContext


func bind(context: UiContext) -> void:
	_context = context
	if _context.session != null and not _context.session.changed.is_connected(_on_session_changed):
		_context.session.changed.connect(_on_session_changed, CONNECT_DEFERRED)
	_refresh_when_ready()


func configure(_building: Dictionary) -> void:
	pass


func refresh() -> void:
	pass


func handle_back() -> bool:
	if _context != null and _context.stack != null and _context.stack.get_depth() > 1:
		_context.stack.pop_screen()
		return true
	return false


func _on_session_changed() -> void:
	refresh()


func _refresh_when_ready() -> void:
	if is_node_ready():
		refresh()
	else:
		if not ready.is_connected(refresh):
			ready.connect(refresh, CONNECT_ONE_SHOT)
