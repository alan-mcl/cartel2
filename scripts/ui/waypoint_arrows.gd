extends Control

const EDGE_PADDING := 36.0
const ARROW_SIZE := 10.0
const LABEL_INSET := 18.0

var _ship_pos: Vector2 = Vector2.ZERO
var _contacts: Array = []
var _camera: Camera2D = null
var _waypoint_ids: PackedStringArray = PackedStringArray(["habitat", "jump_gate", "exit_portal"])


func set_nav_state(ship_pos: Vector2, contacts: Array, camera: Camera2D) -> void:
	_ship_pos = ship_pos
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
	var accent := get_theme_color("accent", "Cartel")
	var muted := get_theme_color("text_muted", "Cartel")
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size - 1

	for contact_variant in _contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		var contact_id := str(contact.get("id", ""))
		if not _waypoint_ids.has(contact_id):
			continue

		var world_pos: Vector2 = contact.get("position", Vector2.ZERO)
		var screen_pos := _world_to_screen(world_pos)
		if _is_on_screen(screen_pos, viewport_size):
			continue

		var edge_pos := _clamp_to_edge(screen_pos, viewport_size)
		var direction := (screen_pos - edge_pos).normalized()
		if direction.length_squared() < 0.001:
			direction = Vector2.UP

		_draw_arrow(edge_pos, direction, accent)
		var name := str(contact.get("name", ""))
		if not name.is_empty():
			var text_size := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var preferred := edge_pos + direction * LABEL_INSET - text_size * 0.5
			preferred.y += text_size.y * 0.35
			var text_pos := _fit_label_pos(preferred, text_size, viewport_size, EDGE_PADDING)
			draw_string(font, text_pos, name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, muted)


func _world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos


func _is_on_screen(screen_pos: Vector2, viewport_size: Vector2) -> bool:
	var margin := EDGE_PADDING
	return (
		screen_pos.x >= margin
		and screen_pos.y >= margin
		and screen_pos.x <= viewport_size.x - margin
		and screen_pos.y <= viewport_size.y - margin
	)


func _clamp_to_edge(screen_pos: Vector2, viewport_size: Vector2) -> Vector2:
	var center := viewport_size * 0.5
	var direction := screen_pos - center
	if direction.length_squared() < 0.001:
		return center + Vector2(0.0, -EDGE_PADDING)

	var half_size := viewport_size * 0.5 - Vector2(EDGE_PADDING, EDGE_PADDING)
	var abs_dir := direction.abs()
	var scale := 1.0
	if abs_dir.x > 0.001:
		scale = minf(scale, half_size.x / abs_dir.x)
	if abs_dir.y > 0.001:
		scale = minf(scale, half_size.y / abs_dir.y)
	return center + direction * scale


func _fit_label_pos(
	preferred: Vector2,
	text_size: Vector2,
	viewport_size: Vector2,
	margin: float
) -> Vector2:
	var pos := preferred
	pos.x = clampf(pos.x, margin, viewport_size.x - margin - text_size.x)
	pos.y = clampf(pos.y, margin, viewport_size.y - margin - text_size.y)
	return pos


func _draw_arrow(center: Vector2, direction: Vector2, color: Color) -> void:
	var forward := direction.normalized()
	var right := Vector2(-forward.y, forward.x)
	var tip := center + forward * ARROW_SIZE
	var left := center - forward * ARROW_SIZE * 0.55 + right * ARROW_SIZE * 0.55
	var right_pt := center - forward * ARROW_SIZE * 0.55 - right * ARROW_SIZE * 0.55
	draw_colored_polygon(PackedVector2Array([tip, left, right_pt]), color)
