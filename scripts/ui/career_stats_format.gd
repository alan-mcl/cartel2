class_name CareerStatsFormat
extends RefCounted


static func format_flight_time(seconds: float) -> String:
	var total_minutes := int(floor(seconds / 60.0))
	var hours := total_minutes / 60
	var minutes := total_minutes % 60
	return "%d h %d m" % [hours, minutes]


static func format_gst_career_time(seconds: float) -> String:
	return "%s GST" % format_flight_time(seconds)


static func format_credits(amount: int) -> String:
	return "d%d" % amount


static func format_tonnes(tonnes: float) -> String:
	return "%.1f t" % tonnes


static func revenue_label(source: String) -> String:
	match source:
		CareerStats.REV_CHARTERS:
			return "Charters"
		CareerStats.REV_COMMODITIES:
			return "Commodity sales"
		CareerStats.REV_SALVAGE:
			return "Salvage"
		CareerStats.REV_PARTS:
			return "Spare parts sold"
		_:
			return source.capitalize()


static func expense_label(source: String) -> String:
	match source:
		CareerStats.EXP_COMMODITIES:
			return "Commodity purchases"
		CareerStats.EXP_SHIPS:
			return "Ships"
		CareerStats.EXP_PARTS:
			return "Spare parts"
		CareerStats.EXP_FUEL:
			return "Fuel"
		CareerStats.EXP_SANCTIONS:
			return "Sanctions"
		CareerStats.EXP_MISSION_PENALTIES:
			return "Mission penalties"
		_:
			return source.capitalize()
