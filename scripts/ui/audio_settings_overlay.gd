extends CanvasLayer

@onready var _center: CenterContainer = $Center
var _panel: AudioSettingsPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_panel = AudioSettingsPanel.new()
	_center.add_child(_panel)
	_panel.closed.connect(_on_panel_closed)


func open() -> void:
	visible = true
	_panel.open()


func close() -> void:
	visible = false


func _on_panel_closed() -> void:
	close()
