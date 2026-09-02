extends CanvasLayer

signal new_game_requested
signal load_requested
signal exit_requested

@onready var _load_button: Button = $Center/Panel/VBox/LoadButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	$Center/Panel/VBox/NewGameButton.pressed.connect(_on_new_game_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	$Center/Panel/VBox/ExitButton.pressed.connect(_on_exit_pressed)


func open() -> void:
	visible = true
	_refresh_load_button()


func close() -> void:
	visible = false


func _refresh_load_button() -> void:
	var has_save := false
	for slot_info in SaveStore.list_slots():
		if bool(slot_info.get("occupied", false)):
			has_save = true
			break
	_load_button.disabled = not has_save


func _on_new_game_pressed() -> void:
	new_game_requested.emit()


func _on_load_pressed() -> void:
	load_requested.emit()


func _on_exit_pressed() -> void:
	exit_requested.emit()
