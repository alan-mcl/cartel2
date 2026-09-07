class_name GalacticCalendar
extends RefCounted

## Galactic Standard Calendar (364-day year, 4-4-5 months) and GST formatting.

const SECONDS_PER_MINUTE := 60
const SECONDS_PER_HOUR := 3600
const SECONDS_PER_DAY := 86400
const DAYS_PER_YEAR := 364
const SECONDS_PER_YEAR := SECONDS_PER_DAY * DAYS_PER_YEAR

const MONTH_LENGTHS: Array[int] = [28, 28, 35, 28, 28, 35, 28, 28, 35, 28, 28, 35]
const MONTH_NAMES: Array[String] = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]
const QUARTER_LABELS: Array[String] = [
	"Q1", "Q1", "Q1", "Q2", "Q2", "Q2", "Q3", "Q3", "Q3", "Q4", "Q4", "Q4",
]

const DEFAULT_YEAR := 2646
const DEFAULT_MONTH := 1
const DEFAULT_DAY := 1
const DEFAULT_HOUR := 8
const DEFAULT_MINUTE := 0
const DEFAULT_SECOND := 0


static func default_start_seconds() -> float:
	return float(to_seconds(DEFAULT_YEAR, DEFAULT_MONTH, DEFAULT_DAY, DEFAULT_HOUR, DEFAULT_MINUTE, DEFAULT_SECOND))


static func start_seconds_from_player(player_data: Dictionary) -> float:
	var gst: Variant = player_data.get("gst", {})
	if typeof(gst) != TYPE_DICTIONARY or gst.is_empty():
		return default_start_seconds()

	return float(to_seconds(
		int(gst.get("year", DEFAULT_YEAR)),
		int(gst.get("month", DEFAULT_MONTH)),
		int(gst.get("day", DEFAULT_DAY)),
		int(gst.get("hour", DEFAULT_HOUR)),
		int(gst.get("minute", DEFAULT_MINUTE)),
		int(gst.get("second", DEFAULT_SECOND)),
	))


static func to_seconds(
	year: int,
	month: int,
	day: int,
	hour: int = 0,
	minute: int = 0,
	second: int = 0
) -> int:
	var total := year * SECONDS_PER_YEAR
	var day_of_year := 0
	for month_index in range(clampi(month, 1, 12) - 1):
		day_of_year += MONTH_LENGTHS[month_index]
	day_of_year += clampi(day, 1, MONTH_LENGTHS[clampi(month, 1, 12) - 1])
	total += (day_of_year - 1) * SECONDS_PER_DAY
	total += clampi(hour, 0, 23) * SECONDS_PER_HOUR
	total += clampi(minute, 0, 59) * SECONDS_PER_MINUTE
	total += maxi(0, second)
	return total


static func from_seconds(total_seconds: float) -> Dictionary:
	var remaining := maxi(0, int(floor(total_seconds)))
	var year := remaining / SECONDS_PER_YEAR
	remaining %= SECONDS_PER_YEAR

	var day_of_year := remaining / SECONDS_PER_DAY
	remaining %= SECONDS_PER_DAY

	var month := 1
	var month_day := day_of_year + 1
	for month_index in range(MONTH_LENGTHS.size()):
		var month_length := MONTH_LENGTHS[month_index]
		if month_day <= month_length:
			month = month_index + 1
			break
		month_day -= month_length

	var hour := remaining / SECONDS_PER_HOUR
	remaining %= SECONDS_PER_HOUR
	var minute := remaining / SECONDS_PER_MINUTE
	var second := remaining % SECONDS_PER_MINUTE

	return {
		"year": year,
		"month": month,
		"day": month_day,
		"quarter": QUARTER_LABELS[month - 1],
		"hour": hour,
		"minute": minute,
		"second": second,
		"day_of_year": day_of_year + 1,
		"weekday": day_of_year % 7,
	}


static func format_timestamp(total_seconds: float) -> String:
	var parts := from_seconds(total_seconds)
	return "%d %s %s %d, %02d:%02d:%02d GST" % [
		parts.day,
		MONTH_NAMES[parts.month - 1],
		parts.quarter,
		parts.year,
		parts.hour,
		parts.minute,
		parts.second,
	]


static func format_date_only(total_seconds: float) -> String:
	var parts := from_seconds(total_seconds)
	return "%d %s %s %d GST" % [
		parts.day,
		MONTH_NAMES[parts.month - 1],
		parts.quarter,
		parts.year,
	]


static func format_duration(total_seconds: float) -> String:
	var remaining := maxi(0, int(round(total_seconds)))
	if remaining <= 0:
		return "0s"

	var days := remaining / SECONDS_PER_DAY
	remaining %= SECONDS_PER_DAY
	var hours := remaining / SECONDS_PER_HOUR
	remaining %= SECONDS_PER_HOUR
	var minutes := remaining / SECONDS_PER_MINUTE
	var seconds := remaining % SECONDS_PER_MINUTE

	var chunks: PackedStringArray = PackedStringArray()
	if days > 0:
		chunks.append("%dd" % days)
	if hours > 0:
		chunks.append("%dh" % hours)
	if minutes > 0:
		chunks.append("%02dm" % minutes)
	if seconds > 0 and days == 0 and hours == 0:
		chunks.append("%02ds" % seconds)
	elif seconds > 0 and chunks.is_empty():
		chunks.append("%02ds" % seconds)

	if chunks.is_empty():
		return "0s"
	return " ".join(chunks)
