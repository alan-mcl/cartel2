extends CanvasLayer

signal closed
signal leaderboard_requested

@onready var _title: Label = $Center/Panel/VBox/TitleLabel
@onready var _scroll: ScrollContainer = $Center/Panel/VBox/Scroll
@onready var _content: VBoxContainer = $Center/Panel/VBox/Scroll/Content

var _session: GameSession = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	$Center/Panel/VBox/CloseButton.pressed.connect(_on_close_pressed)
	$Center/Panel/VBox/LeaderboardButton.pressed.connect(_on_leaderboard_pressed)


func open(session: GameSession) -> void:
	_session = session
	visible = true
	_title.text = "Career - %s" % str(session.callsign) if session != null else "Career"
	_rebuild()


func close() -> void:
	visible = false
	_session = null


func _rebuild() -> void:
	for child in _content.get_children():
		child.queue_free()
	if _session == null:
		return
	var career := _session.career

	_add_section("Accounts")
	_add_row("Reputation", str(_session.player.reputation))
	_add_row("Ships owned", str(_session.fleet.owned_ships.size()))
	_add_row("Nett profit", CareerStatsFormat.format_credits(career.nett_profit()))
	_add_row("Total revenue", CareerStatsFormat.format_credits(career.total_revenue()))
	_add_money_map("Revenue", career.revenue_by_source, true)
	_add_row("Total expenses", CareerStatsFormat.format_credits(career.total_expenses()))
	_add_money_map("Expenses", career.expenses_by_source, false)

	_add_section("Time")
	var flight_total := career.flight_gst_seconds_real + career.flight_gst_seconds_unspace
	_add_row("Flight time", CareerStatsFormat.format_flight_time(flight_total))
	_add_row("Real-space flight", CareerStatsFormat.format_flight_time(career.flight_gst_seconds_real))
	_add_row("N-space flight", CareerStatsFormat.format_flight_time(career.flight_gst_seconds_unspace))
	_add_row("Total career time", CareerStatsFormat.format_flight_time(career.played_seconds))

	_add_section("Navigation")
	_add_row("Translations", str(career.translations_count))
	_add_row("Sectors visited", str(career.sectors_visited.size()))
	_add_row("Habitats visited", str(career.habitats_visited.size()))
	_add_row("Buildings visited", str(career.buildings_visited.size()))
	_add_row("Dockings", str(career.dock_count))

	_add_section("Combat")
	_add_row("Shots fired", str(career.shots_fired))
	_add_row("Kills", str(career.kills))
	_add_row("Hull damage taken", "%.1f" % career.hull_damage_taken)
	_add_row("Hull breaches", str(career.hull_breaches))

	_add_section("Trade")
	_add_row("Tonnes bought", CareerStatsFormat.format_tonnes(career.tonnes_bought))
	_add_row("Tonnes sold", CareerStatsFormat.format_tonnes(career.tonnes_sold))
	_add_row("Salvage recovered", str(career.salvage_count))
	_add_row("Ships purchased", str(career.ships_purchased))

	_add_section("Missions")
	_add_row("Accepted", str(career.missions_accepted))
	_add_row("Completed on time", str(career.missions_completed_on_time))
	_add_row("Late", str(career.missions_late))
	_add_row("Missed deadline", str(career.missions_missed_deadline))
	_add_row("Cancelled", str(career.missions_cancelled))
	_add_row("Charter rewards", CareerStatsFormat.format_credits(career.mission_reward_total))
	_add_row("Mission penalties", CareerStatsFormat.format_credits(career.mission_penalty_total))

	_add_section("Sanctions")
	_add_row("Payments", str(career.sanctions_payments))
	_add_row("Amount paid", CareerStatsFormat.format_credits(career.sanctions_paid_total))
	_add_row("Infractions incurred", str(career.infractions_incurred))


func _add_section(title: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"Section"
	label.text = title
	_content.add_child(label)


func _add_row(label_text: String, value_text: String) -> void:
	_content.add_child(UiPatterns.status_row(label_text, value_text))


func _add_money_map(title: String, amounts: Dictionary, revenue: bool) -> void:
	var known: PackedStringArray = PackedStringArray()
	if revenue:
		known = PackedStringArray([
			CareerStats.REV_CHARTERS,
			CareerStats.REV_COMMODITIES,
			CareerStats.REV_SALVAGE,
			CareerStats.REV_PARTS,
		])
	else:
		known = PackedStringArray([
			CareerStats.EXP_COMMODITIES,
			CareerStats.EXP_SHIPS,
			CareerStats.EXP_PARTS,
			CareerStats.EXP_FUEL,
			CareerStats.EXP_SANCTIONS,
			CareerStats.EXP_MISSION_PENALTIES,
		])
	var other_total := 0
	for key in amounts.keys():
		var source := str(key)
		var amount := int(amounts.get(key, 0))
		if amount <= 0:
			continue
		if source in known:
			var label := CareerStatsFormat.revenue_label(source) if revenue else CareerStatsFormat.expense_label(source)
			_add_row("  %s" % label, CareerStatsFormat.format_credits(amount))
		else:
			other_total += amount
	if other_total > 0:
		_add_row("  Other", CareerStatsFormat.format_credits(other_total))


func _on_close_pressed() -> void:
	close()
	closed.emit()


func _on_leaderboard_pressed() -> void:
	leaderboard_requested.emit()
