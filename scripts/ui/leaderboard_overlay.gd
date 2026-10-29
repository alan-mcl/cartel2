extends CanvasLayer

signal closed

const COLUMNS := [
	{"id": LeaderboardStore.SortColumn.PROFIT, "label": "Nett profit", "width": 96},
	{"id": LeaderboardStore.SortColumn.NET_WORTH, "label": "Nett worth", "width": 96},
	{"id": LeaderboardStore.SortColumn.REVENUE, "label": "Revenue", "width": 88},
	{"id": LeaderboardStore.SortColumn.EXPENSES, "label": "Expenses", "width": 88},
	{"id": LeaderboardStore.SortColumn.TONNES, "label": "Freight", "width": 72},
	{"id": LeaderboardStore.SortColumn.MISSIONS, "label": "Missions", "width": 76},
	{"id": LeaderboardStore.SortColumn.KILLS, "label": "Kills", "width": 52},
	{"id": LeaderboardStore.SortColumn.REPUTATION, "label": "Reputation", "width": 88},
	{"id": LeaderboardStore.SortColumn.CAREER_TIME, "label": "Career time", "width": 108},
]

@onready var _title: Label = $Center/Panel/VBox/TitleLabel
@onready var _header_row: HBoxContainer = $Center/Panel/VBox/HeaderRow
@onready var _rows: VBoxContainer = $Center/Panel/VBox/Scroll/Rows
@onready var _empty: Label = $Center/Panel/VBox/EmptyLabel

var _sort_column: LeaderboardStore.SortColumn = LeaderboardStore.SortColumn.PROFIT
var _sort_descending: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	$Center/Panel/VBox/CloseButton.pressed.connect(_on_close_pressed)
	_build_headers()


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _build_headers() -> void:
	var rank := Label.new()
	rank.custom_minimum_size.x = 40
	rank.theme_type_variation = &"Section"
	rank.text = "#"
	_header_row.add_child(rank)
	var callsign := Label.new()
	callsign.custom_minimum_size.x = 140
	callsign.theme_type_variation = &"Section"
	callsign.text = "Callsign"
	_header_row.add_child(callsign)
	for col in COLUMNS:
		var button := Button.new()
		button.custom_minimum_size.x = float(col["width"])
		button.text = str(col["label"])
		button.focus_mode = Control.FOCUS_NONE
		var column_id: LeaderboardStore.SortColumn = col["id"]
		button.pressed.connect(func() -> void:
			_on_header_pressed(column_id)
		)
		button.set_meta("column_id", column_id)
		_header_row.add_child(button)


func _on_header_pressed(column: LeaderboardStore.SortColumn) -> void:
	if _sort_column == column:
		_sort_descending = not _sort_descending
	else:
		_sort_column = column
		_sort_descending = true
	_refresh()


func _refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var entries := LeaderboardStore.sorted_entries(_sort_column, _sort_descending)
	_empty.visible = entries.is_empty()
	if entries.is_empty():
		_empty.text = "No careers saved yet."
		return
	var rank := 1
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		_rows.add_child(_make_row(rank, entry))
		rank += 1
	_update_header_labels()


func _update_header_labels() -> void:
	var index := 0
	for child in _header_row.get_children():
		if not child is Button:
			continue
		var column_id: LeaderboardStore.SortColumn = child.get_meta("column_id")
		for col in COLUMNS:
			if col["id"] == column_id:
				var suffix := ""
				if _sort_column == column_id:
					suffix = " ▼" if _sort_descending else " ▲"
				child.text = str(col["label"]) + suffix
				break
		index += 1


func _make_row(rank: int, entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var rank_label := Label.new()
	rank_label.custom_minimum_size.x = 40
	rank_label.text = str(rank)
	row.add_child(rank_label)
	var callsign := Label.new()
	callsign.custom_minimum_size.x = 140
	callsign.text = str(entry.get("callsign", ""))
	row.add_child(callsign)
	for col in COLUMNS:
		var value := Label.new()
		value.custom_minimum_size.x = float(col["width"])
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.text = _format_cell(entry, col["id"])
		row.add_child(value)
	return row


func _format_cell(entry: Dictionary, column: LeaderboardStore.SortColumn) -> String:
	match column:
		LeaderboardStore.SortColumn.PROFIT:
			return CareerStatsFormat.format_credits(int(entry.get("profit", 0)))
		LeaderboardStore.SortColumn.NET_WORTH:
			if not entry.has("net_worth"):
				return "—"
			return CareerStatsFormat.format_credits(int(entry.get("net_worth", 0)))
		LeaderboardStore.SortColumn.REVENUE:
			return CareerStatsFormat.format_credits(int(entry.get("revenue", 0)))
		LeaderboardStore.SortColumn.EXPENSES:
			return CareerStatsFormat.format_credits(int(entry.get("expenses", 0)))
		LeaderboardStore.SortColumn.TONNES:
			return CareerStatsFormat.format_tonnes(float(entry.get("tonnes_traded", 0.0)))
		LeaderboardStore.SortColumn.MISSIONS:
			return str(int(entry.get("missions_completed", 0)))
		LeaderboardStore.SortColumn.KILLS:
			return str(int(entry.get("kills", 0)))
		LeaderboardStore.SortColumn.REPUTATION:
			return str(int(entry.get("reputation", 0)))
		LeaderboardStore.SortColumn.CAREER_TIME:
			if not bool(entry.get("career_time_gst", false)):
				return "—"
			return CareerStatsFormat.format_gst_career_time(float(entry.get("career_time", 0.0)))
	return ""


func _on_close_pressed() -> void:
	close()
	closed.emit()
