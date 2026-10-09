class_name TargetLockHudChit
extends PanelContainer

const TransponderBroadcastScript := preload("res://scripts/gameplay/transponder_broadcast.gd")

@onready var _sprite_slot: TargetLockChitSprite = $VBox/HBox/SpriteSlot
@onready var _distance: Label = $VBox/HBox/Body/DistanceLabel
@onready var _line1: Label = $VBox/HBox/Body/Line1Label
@onready var _line2: Label = $VBox/HBox/Body/Line2Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_children_mouse_ignore(self)


func _set_children_mouse_ignore(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_children_mouse_ignore(child)


func update_lock(ship_pos: Vector2, contact: Dictionary) -> void:
	if not is_node_ready():
		return
	var has_lock := not contact.is_empty()
	visible = has_lock
	if not has_lock:
		return

	var target_pos: Vector2 = contact.get("position", Vector2.ZERO)
	_distance.text = _format_distance(ship_pos.distance_to(target_pos))

	var broadcast := {
		"registration": str(contact.get("registration", "")),
		"callsign": str(contact.get("callsign", "")),
		"ship_name": str(contact.get("ship_name", "")),
		"affiliation": str(contact.get("affiliation", "")),
	}
	var lines := TransponderBroadcastScript.format_lines(broadcast)
	_line1.text = lines[0] if lines.size() > 0 else "—"
	_line2.text = lines[1] if lines.size() > 1 else ""

	var sprite_path := str(contact.get("sprite_path", ""))
	var heading := float(contact.get("heading_rad", 0.0)) + PI * 0.5
	_sprite_slot.set_sprite(sprite_path, heading)


static func _format_distance(metres: float) -> String:
	if metres >= 1000.0:
		return "%.1f km" % (metres / 1000.0)
	return "%.0f m" % metres
