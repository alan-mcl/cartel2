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
		var date_line := GalacticCalendar.format_date_only(_session.gst_seconds)
		var time_line := GalacticCalendar.format_time_only(_session.gst_seconds)
		if _session.career.time_limit_pending:
			time_line = "%s — Time up" % time_line
		else:
			var remaining := _session.career.remaining_gst_seconds(_session.gst_seconds)
			if remaining >= 0.0:
				time_line = "%s — %s left" % [time_line, GalacticCalendar.format_duration(remaining)]
		text = "%s\n%s" % [date_line, time_line]
	else:
		var stamp := _session.get_gst_timestamp()
		if _session.career.time_limit_pending:
			text = "%s\nTime up" % stamp
		else:
			var remaining := _session.career.remaining_gst_seconds(_session.gst_seconds)
			if remaining >= 0.0:
				text = "%s\n%s left" % [stamp, GalacticCalendar.format_duration(remaining)]
			else:
				text = stamp
