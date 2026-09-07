extends Label

var _session: GameSession


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if theme_type_variation.is_empty():
		theme_type_variation = &"Numeric"


func bind(session: GameSession) -> void:
	_session = session
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _session == null:
		text = ""
		return
	text = _session.get_gst_timestamp()
