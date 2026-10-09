extends Control

const HullHitboxScript := preload("res://scripts/presentation/hull_hitbox.gd")

const SCREEN_MARGIN := 24.0
const FRAME_PADDING := 1.12
const MIN_SCREEN_HALF := 22.0

var _locked_contact: Dictionary = {}
var _camera: Camera2D = null


func set_lock_state(locked_contact: Dictionary, camera: Camera2D) -> void:
	_locked_contact = locked_contact
	_camera = camera
	queue_redraw()


func set_feature_visible(active: bool) -> void:
	visible = active
	if not active:
		_locked_contact = {}
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if not visible or _camera == null or _locked_contact.is_empty():
		return

	var world_pos: Vector2 = _locked_contact.get("position", Vector2.ZERO)
	var screen_pos := _world_to_screen(world_pos)
	var viewport_size := get_viewport_rect().size
	if not _is_on_screen(screen_pos, viewport_size):
		return

	var half := _screen_frame_half(world_pos)
	var heading := float(_locked_contact.get("heading_rad", 0.0)) + PI * 0.5
	var accent := get_theme_color("accent", "Cartel")
	var shadow := Color(0.02, 0.03, 0.05, 0.85)
	var tick := Color(accent.r, accent.g, accent.b, accent.a * 0.55)

	var xform := Transform2D(heading, screen_pos)
	draw_set_transform_matrix(xform)
	_draw_military_frame(Vector2.ZERO, half, shadow, accent, tick)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _screen_frame_half(world_pos: Vector2) -> Vector2:
	var world_half := _world_frame_half(_locked_contact)
	var sx := _world_length_to_screen(world_pos, Vector2(world_half.x, 0.0))
	var sy := _world_length_to_screen(world_pos, Vector2(0.0, world_half.y))
	return Vector2(
		maxf(sx * FRAME_PADDING, MIN_SCREEN_HALF),
		maxf(sy * FRAME_PADDING, MIN_SCREEN_HALF)
	)


func _world_frame_half(contact: Dictionary) -> Vector2:
	var sprite_path := str(contact.get("sprite_path", ""))
	var display_scale := float(contact.get("lock_hull_display_scale", 1.0))
	if not sprite_path.is_empty():
		var canvas := HullHitboxScript.sprite_canvas_size(sprite_path)
		return canvas * 0.5 * display_scale
	var radius := float(contact.get("lock_hull_radius", 18.0))
	return Vector2(radius, radius)


func _world_length_to_screen(world_origin: Vector2, world_offset: Vector2) -> float:
	var centre := _world_to_screen(world_origin)
	var edge := _world_to_screen(world_origin + world_offset)
	return maxf((edge - centre).length(), 1.0)


func _draw_military_frame(
	centre: Vector2,
	half: Vector2,
	shadow: Color,
	accent: Color,
	tick_muted: Color
) -> void:
	var arm := clampf(minf(half.x, half.y) * 0.34, 14.0, 72.0)
	var chamfer := clampf(arm * 0.22, 4.0, 14.0)
	var line_w := clampf(minf(half.x, half.y) * 0.028, 1.75, 3.25)
	var shadow_w := line_w + 1.4

	_draw_corner_brackets(centre, half, arm, chamfer, shadow_w, shadow)
	_draw_corner_brackets(centre, half, arm, chamfer, line_w, accent)
	_draw_edge_ticks(centre, half, tick_muted, line_w)
	_draw_lead_mark(centre, half.y, accent, line_w)
	_draw_inner_diamond(centre, half * 0.42, tick_muted, line_w * 0.65)
	draw_circle(centre, line_w * 1.1, accent)


func _draw_corner_brackets(
	centre: Vector2,
	half: Vector2,
	arm: float,
	chamfer: float,
	width: float,
	color: Color
) -> void:
	var tl := centre + Vector2(-half.x, -half.y)
	var tr := centre + Vector2(half.x, -half.y)
	var bl := centre + Vector2(-half.x, half.y)
	var br := centre + Vector2(half.x, half.y)

	# Top-left
	draw_line(tl, tl + Vector2(arm, 0.0), color, width)
	draw_line(tl, tl + Vector2(0.0, arm), color, width)
	draw_line(tl + Vector2(arm, 0.0), tl + Vector2(arm - chamfer, chamfer), color, width)
	draw_line(tl + Vector2(0.0, arm), tl + Vector2(chamfer, arm - chamfer), color, width)
	# Top-right
	draw_line(tr, tr + Vector2(-arm, 0.0), color, width)
	draw_line(tr, tr + Vector2(0.0, arm), color, width)
	draw_line(tr + Vector2(-arm, 0.0), tr + Vector2(chamfer - arm, chamfer), color, width)
	draw_line(tr + Vector2(0.0, arm), tr + Vector2(-chamfer, arm - chamfer), color, width)
	# Bottom-left
	draw_line(bl, bl + Vector2(arm, 0.0), color, width)
	draw_line(bl, bl + Vector2(0.0, -arm), color, width)
	draw_line(bl + Vector2(arm, 0.0), bl + Vector2(arm - chamfer, -chamfer), color, width)
	draw_line(bl + Vector2(0.0, -arm), bl + Vector2(chamfer, chamfer - arm), color, width)
	# Bottom-right
	draw_line(br, br + Vector2(-arm, 0.0), color, width)
	draw_line(br, br + Vector2(0.0, -arm), color, width)
	draw_line(br + Vector2(-arm, 0.0), br + Vector2(chamfer - arm, -chamfer), color, width)
	draw_line(br + Vector2(0.0, -arm), br + Vector2(-chamfer, chamfer - arm), color, width)


func _draw_edge_ticks(
	centre: Vector2,
	half: Vector2,
	color: Color,
	width: float
) -> void:
	var tick_len := clampf(minf(half.x, half.y) * 0.12, 6.0, 18.0)
	var inset := 0.18
	for side_idx in 2:
		var side: float = -1.0 if side_idx == 0 else 1.0
		var y: float = centre.y + side * half.y
		for tick_idx in 3:
			var t: float = [-0.35, 0.0, 0.35][tick_idx]
			var x: float = centre.x + t * half.x * (1.0 - inset)
			draw_line(Vector2(x, y), Vector2(x, y - side * tick_len), color, width * 0.85)
		var x_side: float = centre.x + side * half.x
		for tick_idx in 3:
			var t: float = [-0.35, 0.0, 0.35][tick_idx]
			var y_tick: float = centre.y + t * half.y * (1.0 - inset)
			draw_line(Vector2(x_side, y_tick), Vector2(x_side - side * tick_len, y_tick), color, width * 0.85)


func _draw_lead_mark(centre: Vector2, half_y: float, color: Color, width: float) -> void:
	var mark_len := clampf(half_y * 0.14, 8.0, 22.0)
	var gap := mark_len * 0.35
	var frame_top := centre.y - half_y
	var tip := Vector2(centre.x, frame_top - gap - mark_len)
	var base := Vector2(centre.x, frame_top - gap)
	draw_line(tip, base, color, width)
	var mid := (tip + base) * 0.5
	draw_line(
		mid + Vector2(-mark_len * 0.35, 0.0),
		mid + Vector2(mark_len * 0.35, 0.0),
		color,
		width * 0.9
	)


func _draw_inner_diamond(centre: Vector2, half: Vector2, color: Color, width: float) -> void:
	if half.x < 28.0 or half.y < 28.0:
		return
	var top := centre + Vector2(0.0, -half.y)
	var bottom := centre + Vector2(0.0, half.y)
	var left := centre + Vector2(-half.x, 0.0)
	var right := centre + Vector2(half.x, 0.0)
	draw_line(top, right, color, width)
	draw_line(right, bottom, color, width)
	draw_line(bottom, left, color, width)
	draw_line(left, top, color, width)


func _world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos


func _is_on_screen(screen_pos: Vector2, viewport_size: Vector2) -> bool:
	return (
		screen_pos.x >= SCREEN_MARGIN
		and screen_pos.y >= SCREEN_MARGIN
		and screen_pos.x <= viewport_size.x - SCREEN_MARGIN
		and screen_pos.y <= viewport_size.y - SCREEN_MARGIN
	)
