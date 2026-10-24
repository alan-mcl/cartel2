extends Control

const LABEL_OFFSET := Vector2(14.0, -12.0)
const SCREEN_MARGIN := 24.0

var _labels: Array = []
var _camera: Camera2D = null


func set_overlay_state(labels: Array, camera: Camera2D) -> void:
	_labels = labels
	_camera = camera
	queue_redraw()


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

	for label_variant in _labels:
		if typeof(label_variant) != TYPE_DICTIONARY:
			continue
		var label: Dictionary = label_variant
		var anchor_name := str(label.get("name", "")).strip_edges()
		if anchor_name.is_empty():
			continue
		var world_pos: Vector2 = label.get("position", Vector2.ZERO)
		var screen_pos := get_viewport().get_canvas_transform() * world_pos
		if not _is_on_screen(screen_pos, viewport_size):
			continue
		draw_string(
			font,
			screen_pos + LABEL_OFFSET,
			anchor_name,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			muted
		)


func _is_on_screen(screen_pos: Vector2, viewport_size: Vector2) -> bool:
	return (
		screen_pos.x >= SCREEN_MARGIN
		and screen_pos.y >= SCREEN_MARGIN
		and screen_pos.x <= viewport_size.x - SCREEN_MARGIN
		and screen_pos.y <= viewport_size.y - SCREEN_MARGIN
	)
