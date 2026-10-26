extends CanvasLayer

signal resume_requested
signal career_requested
signal leaderboard_requested
signal save_requested
signal load_requested
signal quit_to_menu_requested
signal audio_settings_requested

@onready var _resume_button: Button = $Center/Panel/VBox/ResumeButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_resume_button.pressed.connect(_on_resume_pressed)
	$Center/Panel/VBox/CareerButton.pressed.connect(_on_career_pressed)
	$Center/Panel/VBox/LeaderboardButton.pressed.connect(_on_leaderboard_pressed)
	$Center/Panel/VBox/SaveButton.pressed.connect(_on_save_pressed)
	$Center/Panel/VBox/LoadButton.pressed.connect(_on_load_pressed)
	$Center/Panel/VBox/AudioButton.pressed.connect(_on_audio_pressed)
	$Center/Panel/VBox/QuitButton.pressed.connect(_on_quit_pressed)


func open() -> void:
	visible = true


func close() -> void:
	visible = false


func _on_resume_pressed() -> void:
	_ui_click()
	resume_requested.emit()


func _on_career_pressed() -> void:
	_ui_click()
	career_requested.emit()


func _on_leaderboard_pressed() -> void:
	_ui_click()
	leaderboard_requested.emit()


func _on_save_pressed() -> void:
	_ui_click()
	save_requested.emit()


func _on_load_pressed() -> void:
	_ui_click()
	load_requested.emit()


func _on_audio_pressed() -> void:
	_ui_click()
	audio_settings_requested.emit()


func _on_quit_pressed() -> void:
	_ui_click()
	quit_to_menu_requested.emit()


func _ui_click() -> void:
	AudioService.play_ui("click")
