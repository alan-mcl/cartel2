extends CanvasLayer

signal resume_requested
signal save_requested
signal load_requested
signal quit_to_menu_requested

@onready var _resume_button: Button = $Center/Panel/VBox/ResumeButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_resume_button.pressed.connect(_on_resume_pressed)
	$Center/Panel/VBox/SaveButton.pressed.connect(_on_save_pressed)
	$Center/Panel/VBox/LoadButton.pressed.connect(_on_load_pressed)
	$Center/Panel/VBox/QuitButton.pressed.connect(_on_quit_pressed)


func open() -> void:
	visible = true


func close() -> void:
	visible = false


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_save_pressed() -> void:
	save_requested.emit()


func _on_load_pressed() -> void:
	load_requested.emit()


func _on_quit_pressed() -> void:
	quit_to_menu_requested.emit()
