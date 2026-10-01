extends Label

@export var multiline_date_time: bool = false

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
	if multiline_date_time:
		text = "%s\n%s" % [
			GalacticCalendar.format_date_only(_session.gst_seconds),
			GalacticCalendar.format_time_only(_session.gst_seconds),
		]
	else:
		text = _session.get_gst_timestamp()
