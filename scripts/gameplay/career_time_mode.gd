class_name CareerTimeMode
extends RefCounted

const UNLIMITED := "unlimited"
const MONTH := "month"
const YEAR := "year"

const VALID: Array[String] = [UNLIMITED, MONTH, YEAR]


static func normalise(mode: String) -> String:
	var id := mode.strip_edges().to_lower()
	if id in VALID:
		return id
	return UNLIMITED


static func is_timed(mode: String) -> bool:
	return normalise(mode) == MONTH or normalise(mode) == YEAR


static func allowance_seconds(mode: String, gst_origin_seconds: float) -> float:
	var id := normalise(mode)
	if id == UNLIMITED:
		return -1.0
	if id == YEAR:
		return float(GalacticCalendar.SECONDS_PER_YEAR)
	if not is_nan(gst_origin_seconds):
		var parts := GalacticCalendar.from_seconds(gst_origin_seconds)
		var month_index := clampi(int(parts.month) - 1, 0, GalacticCalendar.MONTH_LENGTHS.size() - 1)
		return float(GalacticCalendar.MONTH_LENGTHS[month_index] * GalacticCalendar.SECONDS_PER_DAY)
	return float(GalacticCalendar.MONTH_LENGTHS[0] * GalacticCalendar.SECONDS_PER_DAY)


static func display_label(mode: String) -> String:
	match normalise(mode):
		MONTH:
			return "1 month"
		YEAR:
			return "1 year"
		_:
			return "Unlimited"
