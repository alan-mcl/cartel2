extends Control

const PROMPT_OFFSET := Vector2(0.0, -90.0)

var _target: Interactable = null
var _camera: Camera2D = null


func set_target(target: Interactable) -> void:
	_target = target
	queue_redraw()


func set_camera(camera: Camera2D) -> void:
	_camera = camera
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if _camera == null or _target == null or not is_instance_valid(_target):
		return

	var text := _target.get_interaction_prompt()
	if text.is_empty():
		return

	var world_pos := _target.global_position
	var screen_pos := get_viewport().get_canvas_transform() * world_pos
	var draw_pos := screen_pos + PROMPT_OFFSET

	var font := ThemeDB.fallback_font
	var font_size := 14
	var color := Color(0.55, 0.98, 1.0, 1.0)
	if has_theme_color("info", "Cartel"):
		color = get_theme_color("info", "Cartel")

	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string(
		font,
		draw_pos - Vector2(text_width * 0.5, 0.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		color
	)
