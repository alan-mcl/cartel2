extends CanvasLayer

signal confirmed(player_name: String, callsign: String)
signal cancelled

@onready var _name_field: LineEdit = $Background/Center/Panel/VBox/NameField
@onready var _callsign_field: LineEdit = $Background/Center/Panel/VBox/CallsignField
@onready var _confirm_button: Button = $Background/Center/Panel/VBox/ConfirmButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_name_field.text_changed.connect(_on_field_changed)
	_callsign_field.text_changed.connect(_on_field_changed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	$Background/Center/Panel/VBox/BackButton.pressed.connect(_on_back_pressed)


func open(default_callsign: String = "") -> void:
	visible = true
	_name_field.text = ""
	_callsign_field.text = default_callsign
	_on_field_changed("")
	_name_field.grab_focus()


func close() -> void:
	visible = false


func _on_field_changed(_text: String) -> void:
	var player_name := _name_field.text.strip_edges()
	var callsign := _callsign_field.text.strip_edges()
	_confirm_button.disabled = player_name.is_empty() or callsign.is_empty()


func _on_confirm_pressed() -> void:
	var player_name := _name_field.text.strip_edges()
	var callsign := _callsign_field.text.strip_edges()
	if player_name.is_empty() or callsign.is_empty():
		return
	confirmed.emit(player_name, callsign)


func _on_back_pressed() -> void:
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		cancelled.emit()
		get_viewport().set_input_as_handled()
