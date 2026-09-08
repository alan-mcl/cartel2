extends Control

const LINE_HEIGHT := 14.0
const LABEL_OFFSET := Vector2(18.0, -10.0)
const SCREEN_MARGIN := 24.0
const TransponderBroadcastScript := preload("res://scripts/gameplay/transponder_broadcast.gd")

var _contacts: Array = []
var _camera: Camera2D = null


func set_overlay_state(contacts: Array, camera: Camera2D) -> void:
	_contacts = contacts
	_camera = camera
	queue_redraw()


func set_feature_visible(active: bool) -> void:
	visible = active


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if not visible or _camera == null:
		return

	var viewport_size := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size - 2
	var muted := get_theme_color("text_muted", "Cartel")

	for contact_variant in _contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		var lines := _lines_for_contact(contact)
		if lines.is_empty():
			continue

		var world_pos: Vector2 = contact.get("position", Vector2.ZERO)
		var screen_pos := _world_to_screen(world_pos)
		if not _is_on_screen(screen_pos, viewport_size):
			continue

		var draw_pos := screen_pos + LABEL_OFFSET
		for i in range(lines.size()):
			draw_string(
				font,
				draw_pos + Vector2(0.0, i * LINE_HEIGHT),
				lines[i],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				muted
			)


func _lines_for_contact(contact: Dictionary) -> PackedStringArray:
	var contact_kind := str(contact.get("contact_kind", "landmark"))
	if contact_kind == "traffic_npc":
		if not bool(contact.get("broadcasting", false)):
			return PackedStringArray()
		return TransponderBroadcastScript.format_lines({
			"registration": contact.get("registration", ""),
			"callsign": contact.get("callsign", ""),
			"ship_name": contact.get("ship_name", ""),
			"affiliation": contact.get("affiliation", ""),
		})

	var name := str(contact.get("name", ""))
	if name.is_empty():
		return PackedStringArray()
	return PackedStringArray([name])


func _world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos


func _is_on_screen(screen_pos: Vector2, viewport_size: Vector2) -> bool:
	return (
		screen_pos.x >= SCREEN_MARGIN
		and screen_pos.y >= SCREEN_MARGIN
		and screen_pos.x <= viewport_size.x - SCREEN_MARGIN
		and screen_pos.y <= viewport_size.y - SCREEN_MARGIN
	)
