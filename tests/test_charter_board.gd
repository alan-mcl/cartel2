class_name TestCharterBoard
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_blocked_label(runner)
	_test_ship_choice(runner)
	_test_offer_button(runner)
	_test_panels_keep_their_copy(runner, catalog)


static func _test_blocked_label(runner: TestRunner) -> void:
	var board := CharterBoard.new()
	board.expand_plain_labels = true
	board.present(null, Callable(), "Scan charter desk unavailable.")
	runner.check(
		_texts(board).has("Scan charter desk unavailable."),
		"charter board: a blocked desk shows only its notice"
	)
	runner.check(not _texts(board).has("Charter ship:"), "charter board: a blocked desk skips the ship line")
	var label := _first_label(board)
	runner.check(
		label != null and label.size_flags_horizontal == Control.SIZE_EXPAND_FILL,
		"charter board: scan notices keep the wide label"
	)
	board.free()


static func _test_ship_choice(runner: TestRunner) -> void:
	var session := GameSession.new()
	session.habitat_id = "proxima_habitat"
	var low := _ship("low", "Low", "proxima_habitat")
	var high := _ship("high", "High", "proxima_habitat")
	session.fleet.owned_ships.append(low)
	session.fleet.owned_ships.append(high)
	session.fleet.current_ship_id = "low"
	var context := UiContext.new()
	context.session = session
	var board := CharterBoard.new()
	board.ship_score = func(ship: OwnedShip) -> float:
		return 5.0 if ship.id == "high" else 0.0
	board.present(context, Callable(), "")
	runner.check_eq(context.charter_ship_id, "high", "charter board: an unfit current ship yields the higher score")
	var pick := {"id": "low"}
	board.resolve_ship_id = func() -> String:
		return str(pick["id"])
	context.charter_ship_id = ""
	board.present(context, Callable(), "")
	runner.check_eq(context.charter_ship_id, "low", "charter board: the ship resolver wins over the score")
	context.charter_ship_id = "high"
	board.present(context, Callable(), "")
	runner.check_eq(context.charter_ship_id, "high", "charter board: a docked charter ship stays selected")
	board.ship_score = Callable()
	board.resolve_ship_id = Callable()
	context.charter_ship_id = ""
	board.present(context, Callable(), "")
	runner.check_eq(context.charter_ship_id, "low", "charter board: without a score the first docked ship is used")
	var menu := _option_button(board)
	runner.check(menu != null and menu.item_count == 2, "charter board: two docked ships open the selector")
	session.fleet.owned_ships.clear()
	session.fleet.owned_ships.append(high)
	context.charter_ship_id = ""
	board.present(context, Callable(), "")
	runner.check(
		_texts(board).has("Charter ship: High"),
		"charter board: one docked ship is named in the ship line"
	)
	board.free()


static func _test_offer_button(runner: TestRunner) -> void:
	var session := GameSession.new()
	session.habitat_id = "proxima_habitat"
	session.fleet.owned_ships.append(_ship("ship-a", "Ada", "proxima_habitat"))
	var context := UiContext.new()
	context.session = session
	context.charter_ship_id = "ship-a"
	var acted := {"n": 0}
	var redraws := {"n": 0}
	var describe_offer := func(entry: Dictionary, ship_id: String) -> Dictionary:
		return {
			"title": str(entry.get("role_title", "")),
			"lines": ["Bela · 2 pax · d100"],
			"body": "Quiet cabin.",
			"button_text": "Accept",
			"button_enabled": ship_id == "ship-a",
			"tooltip": "Need a hold.",
			"status": "",
		}
	var act_offer := func(_entry: Dictionary, _ship_id: String) -> bool:
		acted["n"] = int(acted["n"]) + 1
		return int(acted["n"]) > 1
	var describe_held := func(entry: Dictionary, _ship_id: String) -> Dictionary:
		return {
			"title": str(entry.get("role_title", "")),
			"lines": [],
			"body": "",
			"button_text": "",
			"button_enabled": false,
			"tooltip": "In transit.",
			"status": "In transit - cannot cancel.",
		}
	var posted := CharterBoardSection.new()
	posted.heading = "POSTED CHARTERS"
	posted.empty_text = "No departures posted today."
	posted.chits = [
		CharterChit.from_entry(
			{"id": "o1", "role_title": "Night courier"},
			describe_offer,
			act_offer
		),
	]
	var accepted := CharterBoardSection.new()
	accepted.heading = "YOUR CHARTERS"
	accepted.empty_text = "No accepted charters."
	accepted.chits = [
		CharterChit.from_entry(
			{"charter_id": "charter_1", "role_title": "Held fare"},
			describe_held,
			Callable()
		),
	]
	var board := CharterBoard.new()
	board.rerender = func() -> void:
		redraws["n"] = int(redraws["n"]) + 1
	board.present(context, func() -> Array:
		return [posted, accepted]
	)
	runner.check(_texts(board).has("POSTED CHARTERS"), "charter board: posted heading is drawn")
	runner.check(_texts(board).has("Night courier"), "charter board: offer title is drawn")
	runner.check(_texts(board).has("Quiet cabin."), "charter board: offer body is drawn")
	runner.check(_texts(board).has("In transit - cannot cancel."), "charter board: a stuck contract shows its status")
	var accept := _button_named(board, "Accept")
	runner.check(accept != null and not accept.disabled, "charter board: a fitting ship enables Accept")
	runner.check(_tooltips(board).has("Need a hold."), "charter board: the offer tooltip is on the tile")
	var grid := _grid(board)
	runner.check(grid != null and grid.columns == 3, "charter board: tiles use three columns")
	if accept != null:
		accept.pressed.emit()
	runner.check_eq(int(acted["n"]), 1, "charter board: Accept calls the hook")
	runner.check_eq(int(redraws["n"]), 0, "charter board: a refused accept does not redraw")
	if accept != null:
		accept.pressed.emit()
	runner.check_eq(int(redraws["n"]), 1, "charter board: a successful accept redraws")
	runner.check(_button_named(board, "Cancel (fee d0)") == null, "charter board: a stuck contract has no cancel button")
	board.free()


static func _test_panels_keep_their_copy(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "BOARD", "scan_tester"), "charter board: session starts")
	var simulation := Simulation.new()
	var context := UiContext.new()
	context.catalog = catalog
	context.session = session
	context.simulation = simulation
	var missions := simulation.get_subsystem("missions") as MissionSubsystem

	var passengers = load("res://scripts/ui/passenger_charter_panel.gd").new()
	passengers._context = context
	passengers.board_mode = PassengerCharters.BOARD_TERMINAL
	var board := CharterBoard.new()
	board.present(context, Callable(passengers, "_sections"), passengers._blocked_text())
	runner.check(_texts(board).has("POSTED CHARTERS"), "charter board: terminal keeps posted charters")
	runner.check(_texts(board).has("No departures posted today."), "charter board: terminal keeps the empty departures line")
	runner.check(_texts(board).has("YOUR CHARTERS"), "charter board: terminal keeps your charters")
	missions.passengers.offers[session.habitat_id] = {
		PassengerCharters.BOARD_TERMINAL: [{
			"id": "offer_night",
			"role_title": "Night courier",
			"destination_name": "Bela",
			"quantity": 1,
			"reward": 40,
			"description": "Quiet cabin.",
			"life_support": "spartan",
		}],
	}
	passengers.board_mode = PassengerCharters.BOARD_TERMINAL
	board.present(context, Callable(passengers, "_sections"), passengers._blocked_text())
	runner.check(_texts(board).has("Night courier"), "charter board: a passenger offer uses the panel title")
	runner.check(_texts(board).has("Life support: Spartan"), "charter board: a passenger offer keeps the life-support line")
	var accept := _button_named(board, "Accept")
	runner.check(accept != null, "charter board: a passenger offer keeps Accept")

	var freight = load("res://scripts/ui/freight_charter_panel.gd").new()
	freight._context = context
	board.present(context, Callable(freight, "_sections"), freight._blocked_text())
	runner.check(_texts(board).has("POSTED FREIGHT"), "charter board: freight keeps its posted heading")
	runner.check(_texts(board).has("No freight posted today."), "charter board: freight keeps its empty line")
	runner.check(_texts(board).has("YOUR FREIGHT"), "charter board: freight keeps your freight")

	var scan = load("res://scripts/ui/scan_charter_panel.gd").new()
	scan._context = context
	runner.check_eq(
		str(scan._blocked_text()),
		"Scan charter desk unavailable.",
		"charter board: a scan desk without a building stays closed"
	)
	scan.configure({"id": "proxima_peaceforce"})
	missions.scans.accepted = [
		{"charter_id": "scan_1", "building_id": "proxima_peaceforce", "designation": "Mine survey"},
		{"charter_id": "scan_2", "building_id": "other_desk", "designation": "Other survey"},
	]
	missions.bounties.accepted = [
		{"charter_id": "bounty_1", "building_id": "proxima_peaceforce", "target_callsign": "Kept"},
		{"charter_id": "bounty_2", "building_id": "other_desk", "target_callsign": "Dropped"},
	]
	board.present(context, Callable(scan, "_sections"), scan._blocked_text())
	var shown := _texts(board)
	runner.check(not shown.has("POSTED SCANS"), "charter board: mixed desk drops scan type headings")
	runner.check(not shown.has("POSTED BOUNTIES"), "charter board: mixed desk drops bounty type headings")
	runner.check(shown.has("ACCEPTED"), "charter board: mixed desk keeps accepted heading")
	runner.check(shown.has("Mine survey"), "charter board: an accepted scan for this building stays")
	runner.check(not shown.has("Other survey"), "charter board: another building's scan stays off this desk")
	runner.check(shown.has("Kept"), "charter board: an accepted bounty for this building stays")
	runner.check(not shown.has("Dropped"), "charter board: another building's bounty stays off this desk")

	board.free()
	passengers.free()
	freight.free()
	scan.free()


static func _ship(id: String, ship_name: String, location: String) -> OwnedShip:
	var ship := OwnedShip.new()
	ship.id = id
	ship.name = ship_name
	ship.location = location
	return ship


static func _texts(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		out.append_array(_texts(child))
	return out


static func _tooltips(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node is Control:
		var tip := (node as Control).tooltip_text
		if not tip.is_empty():
			out.append(tip)
	for child in node.get_children():
		out.append_array(_tooltips(child))
	return out


static func _first_label(node: Node) -> Label:
	if node is Label:
		return node as Label
	for child in node.get_children():
		var found := _first_label(child)
		if found != null:
			return found
	return null


static func _option_button(node: Node) -> OptionButton:
	if node is OptionButton:
		return node as OptionButton
	for child in node.get_children():
		var found := _option_button(child)
		if found != null:
			return found
	return null


static func _button_named(node: Node, text: String) -> Button:
	if node is Button and not node is OptionButton and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _button_named(child, text)
		if found != null:
			return found
	return null


static func _grid(node: Node) -> GridContainer:
	if node is GridContainer:
		return node as GridContainer
	for child in node.get_children():
		var found := _grid(child)
		if found != null:
			return found
	return null
