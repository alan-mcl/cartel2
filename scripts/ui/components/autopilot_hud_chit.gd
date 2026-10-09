class_name AutopilotHudChit
extends PanelContainer

@onready var _mode: Label = $VBox/ModeLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_children_mouse_ignore(self)


func _set_children_mouse_ignore(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_children_mouse_ignore(child)


func set_mode(ap_mode: int) -> void:
	if not is_node_ready():
		return
	var manual := ap_mode == Autopilot.Mode.MANUAL
	visible = not manual
	if manual:
		return
	_mode.text = Autopilot.mode_label(ap_mode as Autopilot.Mode)
