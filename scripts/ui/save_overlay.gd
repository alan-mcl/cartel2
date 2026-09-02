extends CanvasLayer

signal slot_chosen(slot_index: int)
signal cancelled

enum Mode { LOAD, SAVE }

@onready var _title: Label = $Background/Center/Panel/VBox/TitleLabel
@onready var _slot_list: VBoxContainer = $Background/Center/Panel/VBox/SlotList
@onready var _status: Label = $Background/Center/Panel/VBox/StatusLabel

var _mode: Mode = Mode.LOAD
var _pending_overwrite_slot: int = -1


func is_save_mode() -> bool:
	return _mode == Mode.SAVE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	$Background/Center/Panel/VBox/BackButton.pressed.connect(_on_back_pressed)


func open(mode: Mode) -> void:
	_mode = mode
	_pending_overwrite_slot = -1
	visible = true
	_title.text = "Load Game" if _mode == Mode.LOAD else "Save Game"
	_status.text = ""
	_refresh_slots()


func close() -> void:
	visible = false
	_pending_overwrite_slot = -1


func _refresh_slots() -> void:
	for child in _slot_list.get_children():
		child.queue_free()

	for slot_info in SaveStore.list_slots():
		var slot_index := int(slot_info.get("slot", 0))
		var occupied := bool(slot_info.get("occupied", false))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_slot_list.add_child(row)

		if occupied:
			var player_name := str(slot_info.get("player_name", ""))
			var callsign := str(slot_info.get("callsign", ""))
			var location := str(slot_info.get("location", ""))
			var saved_at := str(slot_info.get("saved_at", ""))
			var label := Label.new()
			label.text = 'Slot %d: %s "%s" — %s — %s' % [
				slot_index,
				player_name,
				callsign,
				location,
				saved_at,
			]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)

			var button := Button.new()
			if _mode == Mode.LOAD:
				button.text = "Load"
				button.pressed.connect(_on_slot_pressed.bind(slot_index))
			elif _pending_overwrite_slot == slot_index:
				button.text = "Confirm overwrite"
				button.pressed.connect(_on_overwrite_confirmed.bind(slot_index))
			else:
				button.text = "Overwrite"
				button.pressed.connect(_on_overwrite_requested.bind(slot_index))
			row.add_child(button)
		else:
			var label := Label.new()
			label.text = "Slot %d: Empty" % slot_index
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)

			if _mode == Mode.SAVE:
				var button := Button.new()
				button.text = "Save here"
				button.pressed.connect(_on_slot_pressed.bind(slot_index))
				row.add_child(button)


func _on_slot_pressed(slot_index: int) -> void:
	slot_chosen.emit(slot_index)


func _on_overwrite_requested(slot_index: int) -> void:
	_pending_overwrite_slot = slot_index
	_status.text = "Slot %d will be overwritten. Confirm to continue." % slot_index
	_refresh_slots()


func _on_overwrite_confirmed(slot_index: int) -> void:
	slot_chosen.emit(slot_index)


func _on_back_pressed() -> void:
	if _pending_overwrite_slot >= 0:
		_pending_overwrite_slot = -1
		_status.text = ""
		_refresh_slots()
		return
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
