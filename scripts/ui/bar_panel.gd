extends GameScreen

const CHARTER_PANEL := preload("res://scenes/ui/passenger_charter_panel.tscn")

var _charter_panel: Control


func refresh() -> void:
	if not is_node_ready() or _context == null:
		return
	_ensure_charter_panel()
	if _charter_panel != null and _charter_panel.has_method("refresh"):
		_charter_panel.refresh()


func _ensure_charter_panel() -> void:
	if _charter_panel != null and is_instance_valid(_charter_panel):
		return
	_clear_children(self)
	_charter_panel = CHARTER_PANEL.instantiate()
	_charter_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_charter_panel.board_mode = PassengerCharters.BOARD_BAR
	add_child(_charter_panel)
	if _charter_panel.has_method("bind"):
		_charter_panel.bind(_context)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
