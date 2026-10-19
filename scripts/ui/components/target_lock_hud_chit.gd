class_name TargetLockHudChit
extends PanelContainer

signal scan_requested

const TransponderBroadcastScript := preload("res://scripts/gameplay/transponder_broadcast.gd")

@onready var _sprite_slot: TargetLockChitSprite = $VBox/HBox/SpriteSlot
@onready var _distance: Label = $VBox/HBox/Body/DistanceLabel
@onready var _line1: Label = $VBox/HBox/Body/Line1Label
@onready var _line2: Label = $VBox/HBox/Body/Line2Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)
	_set_children_mouse_ignore(self)


func _set_children_mouse_ignore(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_children_mouse_ignore(child)


func _on_gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			scan_requested.emit()
			accept_event()


func update_lock(ship_pos: Vector2, contact: Dictionary) -> void:
	if not is_node_ready():
		return
	var has_lock := not contact.is_empty()
	visible = has_lock
	mouse_filter = Control.MOUSE_FILTER_STOP if has_lock else Control.MOUSE_FILTER_IGNORE
	if not has_lock:
		return

	var target_pos: Vector2 = contact.get("position", Vector2.ZERO)
	_distance.text = _format_distance(ship_pos.distance_to(target_pos))

	var contact_kind := str(contact.get("contact_kind", ""))
	if contact_kind == "traffic_npc":
		var broadcast := {
			"registration": str(contact.get("registration", "")),
			"callsign": str(contact.get("callsign", "")),
			"ship_name": str(contact.get("ship_name", "")),
			"affiliation": str(contact.get("affiliation", "")),
		}
		var lines := TransponderBroadcastScript.format_lines(broadcast)
		_line1.text = lines[0] if lines.size() > 0 else "—"
		_line2.text = lines[1] if lines.size() > 1 else ""
	else:
		_line1.text = _display_name(contact)
		_line2.text = _kind_label(contact_kind)

	var sprite_path := str(contact.get("sprite_path", ""))
	var heading := float(contact.get("heading_rad", 0.0)) + PI * 0.5
	_sprite_slot.set_sprite(sprite_path, heading)


func _display_name(contact: Dictionary) -> String:
	var name := str(contact.get("name", "")).strip_edges()
	if not name.is_empty():
		return name
	var kind := str(contact.get("contact_kind", ""))
	match kind:
		"orbital":
			return "Unnamed orbital"
		"debris":
			return "Debris"
		_:
			return "—"


func _kind_label(contact_kind: String) -> String:
	match contact_kind:
		"traffic_npc":
			return "Ship"
		"landmark":
			return "Landmark"
		"orbital":
			return "Orbital"
		"star":
			return "Star"
		"debris":
			return "Debris"
		"ascidian":
			return "Ascidian"
		_:
			return contact_kind.capitalize() if not contact_kind.is_empty() else "Contact"


static func _format_distance(metres: float) -> String:
	if metres >= 1000.0:
		return "%.1f km" % (metres / 1000.0)
	return "%.0f m" % metres
