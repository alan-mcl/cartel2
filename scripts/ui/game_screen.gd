class_name GameScreen
extends Control

var _context: UiContext
var _bound_session: GameSession
var _session_forwarded: bool = false


func bind(context: UiContext) -> void:
	_disconnect_session_changed()
	_context = context
	_bound_session = _context.session if _context != null else null
	_connect_session_changed()
	_refresh_when_ready()


func configure(_building: Dictionary) -> void:
	pass


## When true, habitat (or another host) forwards `session.changed`; this panel does not subscribe.
func set_session_forwarded(forwarded: bool) -> void:
	if _session_forwarded == forwarded:
		return
	_session_forwarded = forwarded
	if forwarded:
		_disconnect_session_changed()
	else:
		_connect_session_changed()


func refresh() -> void:
	pass


func handle_back() -> bool:
	if _context != null and _context.stack != null and _context.stack.get_depth() > 1:
		_context.stack.pop_screen()
		return true
	return false


func session_changed() -> void:
	refresh()


func _on_session_changed() -> void:
	session_changed()


func _connect_session_changed() -> void:
	if _session_forwarded or _bound_session == null:
		return
	if not _bound_session.changed.is_connected(_on_session_changed):
		_bound_session.changed.connect(_on_session_changed, CONNECT_DEFERRED)


func _disconnect_session_changed() -> void:
	if _bound_session == null:
		return
	if _bound_session.changed.is_connected(_on_session_changed):
		_bound_session.changed.disconnect(_on_session_changed)


func _exit_tree() -> void:
	_disconnect_session_changed()
	_bound_session = null


func _refresh_when_ready() -> void:
	if is_node_ready():
		refresh()
	else:
		if not ready.is_connected(refresh):
			ready.connect(refresh, CONNECT_ONE_SHOT)
