extends CanvasLayer

signal new_game_requested
signal load_requested
signal leaderboard_requested
signal exit_requested
signal audio_settings_requested

@onready var _load_button: Button = $Center/Panel/VBox/LoadButton
@onready var _version_label: Label = $Center/Panel/VBox/VersionLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if _version_label != null:
		_version_label.text = GameVersion.VERSION
	$Center/Panel/VBox/NewGameButton.pressed.connect(_on_new_game_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	$Center/Panel/VBox/LeaderboardButton.pressed.connect(_on_leaderboard_pressed)
	$Center/Panel/VBox/AudioButton.pressed.connect(_on_audio_pressed)
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
	_ui_click()
	new_game_requested.emit()


func _on_load_pressed() -> void:
	_ui_click()
	load_requested.emit()


func _on_leaderboard_pressed() -> void:
	_ui_click()
	leaderboard_requested.emit()


func _on_audio_pressed() -> void:
	_ui_click()
	audio_settings_requested.emit()


func _on_exit_pressed() -> void:
	_ui_click()
	exit_requested.emit()


func _ui_click() -> void:
	AudioService.play_ui("click")
