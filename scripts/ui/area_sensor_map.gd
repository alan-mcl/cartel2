extends Control

signal closed
signal lock_contact_requested(contact_id: String)

const MAP_VIEWPORT_FRACTION := 0.78
const LEGEND_PANEL_SIZE := 220.0
const LEGEND_MARGIN := 12.0
const INNER_PADDING := 14.0
const CONTACT_HIT_RADIUS := 12.0
const BACKDROP_ALPHA := 0.35
const GRID_ALPHA := 0.22
const GRID_MAJOR_ALPHA := 0.38
const BORDER_WIDTH := 1.5
const VELOCITY_TICK_SEC := 0.4
const MAX_VELOCITY_TICK_PX := 4.8
const SENSOR_COLOR_KEYS := ["accent", "info", "warning", "negative"]

@onready var _legend_panel: PanelContainer = $LegendPanel
@onready var _legend_scale: Label = $LegendPanel/VBox/LegendScale
@onready var _legend_list: VBoxContainer = $LegendPanel/VBox/LegendList

var _view_half_extent_m: float = 3500.0
var _grid_step_m: float = 500.0
var _ship_pos: Vector2 = Vector2.ZERO
var _ship_heading_deg: float = 0.0
var _ship_velocity: Vector2 = Vector2.ZERO
var _contacts: Array = []
var _circles: Array = []
var _locked_contact_id: String = ""
var _player_broadcast_text: String = ""
var _camera: Camera2D = null
var _can_lock: bool = false
var _show_beacon_names: bool = false
var _last_hover_pos: Vector2 = Vector2(-99999.0, -99999.0)


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _legend_panel != null:
		_legend_panel.z_index = 1
		_legend_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layout_legend_panel()


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	set_process(true)
	queue_redraw()
	_refresh_legend()


func close() -> bool:
	if not visible:
		return false
	visible = false
	set_process(false)
	tooltip_text = ""
	closed.emit()
	return true


func set_player_broadcast(text: String) -> void:
	_player_broadcast_text = text


func set_frame(
	snapshot: Dictionary,
	ship_pos: Vector2,
	ship_heading_deg: float,
	ship_velocity: Vector2,
	contacts: Array,
	locked_contact: Dictionary,
	camera: Camera2D,
	can_target_lock: bool,
	show_beacon_names: bool
) -> void:
	_view_half_extent_m = maxf(float(snapshot.get("view_half_extent_m", 3500.0)), 1.0)
	_grid_step_m = maxf(float(snapshot.get("grid_step_m", 500.0)), 1.0)
	_circles = snapshot.get("circles", [])
	_ship_pos = ship_pos
	_ship_heading_deg = ship_heading_deg
	_ship_velocity = ship_velocity
	_contacts = contacts
	_locked_contact_id = str(locked_contact.get("id", ""))
	_camera = camera
	_can_lock = can_target_lock
	_show_beacon_names = show_beacon_names
	if visible:
		_refresh_legend()
	queue_redraw()


func _layout_legend_panel() -> void:
	if _legend_panel == null:
		return
	_legend_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_legend_panel.offset_left = -LEGEND_PANEL_SIZE - LEGEND_MARGIN
	_legend_panel.offset_top = -LEGEND_PANEL_SIZE - LEGEND_MARGIN
	_legend_panel.offset_right = -LEGEND_MARGIN
	_legend_panel.offset_bottom = -LEGEND_MARGIN
	_legend_panel.custom_minimum_size = Vector2(LEGEND_PANEL_SIZE, LEGEND_PANEL_SIZE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var layout := _map_layout()
			var map_center: Vector2 = layout["center"]
			var half_px: float = layout["half_px"]
			if not _point_in_square(mb.position, map_center, half_px):
				close()
				return
			if _can_lock:
				var contact := _find_contact_at(mb.position)
				if not contact.is_empty():
					lock_contact_requested.emit(str(contact.get("id", "")))
					accept_event()
			return
	if event is InputEventMouseMotion:
		_update_hover_tooltip(event.position)


func _process(_delta: float) -> void:
	if not visible:
		return
	var mouse_pos := get_local_mouse_position()
	if mouse_pos.distance_squared_to(_last_hover_pos) <= 0.25:
		return
	_update_hover_tooltip(mouse_pos)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		tooltip_text = ""


func _draw() -> void:
	if not visible:
		return
	var layout := _map_layout()
	var map_center: Vector2 = layout["center"]
	var half_px: float = layout["half_px"]
	var scale: float = layout["scale"]

	var backdrop := get_theme_color("bg", "Cartel")
	backdrop.a = BACKDROP_ALPHA
	draw_rect(Rect2(Vector2.ZERO, size), backdrop)

	var surface := get_theme_color("surface", "Cartel")
	surface.a = 0.55
	var border := get_theme_color("text", "Cartel")
	var accent := get_theme_color("accent", "Cartel")
	var info := get_theme_color("info", "Cartel")
	var muted := get_theme_color("text_muted", "Cartel")

	var map_rect := Rect2(map_center - Vector2(half_px, half_px), Vector2(half_px * 2.0, half_px * 2.0))
	draw_rect(map_rect, surface)
	draw_rect(map_rect, border, false, BORDER_WIDTH)

	_draw_world_grid(map_center, half_px, scale, muted)
	_draw_range_circles(map_center, half_px, scale)
	_draw_camera_view(map_center, half_px, scale, muted)
	_draw_contacts(map_center, half_px, scale, info, muted)
	_draw_velocity_ticks(map_center, scale, accent, info)
	_draw_lock_marker(map_center, scale, accent)
	_draw_ship(map_center, accent)


func _map_layout() -> Dictionary:
	var half_px := minf(size.x, size.y) * MAP_VIEWPORT_FRACTION * 0.5 - INNER_PADDING
	half_px = maxf(half_px, 40.0)
	var map_center := size * 0.5
	var scale := half_px / _view_half_extent_m
	return {
		"center": map_center,
		"half_px": half_px,
		"scale": scale,
	}


func _draw_world_grid(center: Vector2, half_px: float, scale: float, muted: Color) -> void:
	var step := _grid_step_m
	if step <= 0.0:
		return
	var world_min := _ship_pos - Vector2(_view_half_extent_m, _view_half_extent_m)
	var world_max := _ship_pos + Vector2(_view_half_extent_m, _view_half_extent_m)
	var k_min_x := int(floor(world_min.x / step))
	var k_max_x := int(ceil(world_max.x / step))
	var k_min_y := int(floor(world_min.y / step))
	var k_max_y := int(ceil(world_max.y / step))
	for kx in range(k_min_x, k_max_x + 1):
		var world_x := float(kx) * step
		var map_x := center.x + (world_x - _ship_pos.x) * scale
		if map_x < center.x - half_px or map_x > center.x + half_px:
			continue
		var major := kx % 4 == 0
		var col := muted
		col.a = GRID_MAJOR_ALPHA if major else GRID_ALPHA
		draw_line(
			Vector2(map_x, center.y - half_px),
			Vector2(map_x, center.y + half_px),
			col,
			1.0 if not major else 1.5
		)
	for ky in range(k_min_y, k_max_y + 1):
		var world_y := float(ky) * step
		var map_y := center.y + (world_y - _ship_pos.y) * scale
		if map_y < center.y - half_px or map_y > center.y + half_px:
			continue
		var major := ky % 4 == 0
		var col := muted
		col.a = GRID_MAJOR_ALPHA if major else GRID_ALPHA
		draw_line(
			Vector2(center.x - half_px, map_y),
			Vector2(center.x + half_px, map_y),
			col,
			1.0 if not major else 1.5
		)


func _circle_color(circle: Dictionary, sensor_index: int) -> Color:
	if str(circle.get("kind", "")) == "visual":
		return get_theme_color("positive", "Cartel")
	var key: String = SENSOR_COLOR_KEYS[sensor_index % SENSOR_COLOR_KEYS.size()]
	var col := get_theme_color(StringName(key), "Cartel")
	var tier := sensor_index / SENSOR_COLOR_KEYS.size()
	for _i in range(tier):
		col = col.darkened(0.18)
	return col


func _draw_range_circles(center: Vector2, half_px: float, scale: float) -> void:
	var sensor_circles: Array = []
	var visual_circle: Dictionary = {}
	for circle_variant in _circles:
		if typeof(circle_variant) != TYPE_DICTIONARY:
			continue
		var circle: Dictionary = circle_variant
		if str(circle.get("kind", "")) == "visual":
			visual_circle = circle
		else:
			sensor_circles.append(circle)
	sensor_circles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("range_m", 0.0)) > float(b.get("range_m", 0.0))
	)
	var sensor_drawn := 0
	for circle in sensor_circles:
		var radius_px := float(circle.get("range_m", 0.0)) * scale
		if radius_px <= 0.0:
			continue
		var col := _circle_color(circle, sensor_drawn)
		col.a = 0.85
		_draw_range_circle(center, radius_px, col, 1.25)
		sensor_drawn += 1
	if not visual_circle.is_empty():
		var visual_px := float(visual_circle.get("range_m", 0.0)) * scale
		if visual_px > 0.0:
			var vcol := _circle_color(visual_circle, 0)
			vcol.a = 0.95
			_draw_range_circle(center, visual_px, vcol, 1.5)


func _draw_range_circle(center: Vector2, radius_px: float, color: Color, width: float) -> void:
	if radius_px <= 0.0:
		return
	draw_circle(center, radius_px, Color(color.r, color.g, color.b, color.a * 0.08))
	draw_arc(center, radius_px, 0.0, TAU, 96, color, width)


func _draw_camera_view(center: Vector2, half_px: float, scale: float, muted: Color) -> void:
	if _camera == null:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var zoom := _camera.zoom
	var half_world := (viewport_size * 0.5) / zoom
	var cam_pos := _camera.global_position
	var top_left := cam_pos - half_world
	var bottom_right := cam_pos + half_world
	var tl_map := center + (top_left - _ship_pos) * scale
	var br_map := center + (bottom_right - _ship_pos) * scale
	if br_map.x < tl_map.x:
		var swap_x := tl_map.x
		tl_map.x = br_map.x
		br_map.x = swap_x
	if br_map.y < tl_map.y:
		var swap_y := tl_map.y
		tl_map.y = br_map.y
		br_map.y = swap_y
	var rect := Rect2(tl_map, br_map - tl_map)
	var col := muted
	col.a = 0.35
	draw_rect(rect, col, false, 1.0)


func _draw_contacts(center: Vector2, half_px: float, scale: float, info: Color, muted: Color) -> void:
	var label_inset := NavMapDraw.contact_draw_radius("landmark", {}, true) + 12.0
	for contact_variant in _contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if str(contact.get("id", "")) == "player":
			continue
		var contact_kind := str(contact.get("contact_kind", "landmark"))
		var draw_radius := NavMapDraw.contact_draw_radius(contact_kind, contact, true)
		var world_pos: Vector2 = contact.get("position", Vector2.ZERO)
		var map_pos := NavMapDraw.contact_map_pos(
			world_pos, _ship_pos, center, half_px, scale, contact_kind, draw_radius
		)
		if map_pos.x == INF:
			continue
		var dot_color := NavMapDraw.contact_color(contact_kind, info, muted, contact)
		var is_locked := str(contact.get("id", "")) == _locked_contact_id
		if is_locked:
			dot_color = get_theme_color("accent", "Cartel")
		draw_circle(map_pos, draw_radius, dot_color)
		if contact_kind == "traffic_npc":
			continue
		var short_label := str(contact.get("short_label", ""))
		if short_label.is_empty():
			continue
		if not NavMapDraw.is_inside_square(map_pos, center, half_px, label_inset):
			continue
		var font := ThemeDB.fallback_font
		var font_size := ThemeDB.fallback_font_size - 2
		draw_string(
			font, map_pos + Vector2(6.0, 4.0), short_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, muted
		)


func _draw_velocity_ticks(center: Vector2, scale: float, accent: Color, info: Color) -> void:
	_draw_velocity_tick(center, _ship_velocity, scale, accent)
	for contact_variant in _contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if str(contact.get("id", "")) == _locked_contact_id:
			var pos: Vector2 = contact.get("position", Vector2.ZERO)
			var map_pos := center + (pos - _ship_pos) * scale
			_draw_velocity_tick(map_pos, contact.get("velocity", Vector2.ZERO), scale, accent)
		elif str(contact.get("contact_kind", "")) == "traffic_npc":
			var pos: Vector2 = contact.get("position", Vector2.ZERO)
			var map_pos := center + (pos - _ship_pos) * scale
			_draw_velocity_tick(map_pos, contact.get("velocity", Vector2.ZERO), scale, info)


func _draw_velocity_tick(origin: Vector2, velocity: Vector2, scale: float, color: Color) -> void:
	if velocity.length_squared() < 1.0:
		return
	var tick := velocity * VELOCITY_TICK_SEC * scale
	if tick.length() > MAX_VELOCITY_TICK_PX:
		tick = tick.normalized() * MAX_VELOCITY_TICK_PX
	draw_line(origin, origin + tick, color, 1.5)


func _draw_lock_marker(center: Vector2, scale: float, accent: Color) -> void:
	if _locked_contact_id.is_empty():
		return
	var locked := _contact_by_id(_locked_contact_id)
	if locked.is_empty():
		return
	var target_pos: Vector2 = locked.get("position", Vector2.ZERO)
	var target_map := center + (target_pos - _ship_pos) * scale
	draw_line(center, target_map, Color(accent.r, accent.g, accent.b, accent.a * 0.65), 1.0)
	var half := 7.0
	draw_line(target_map + Vector2(-half, -half), target_map + Vector2(-half * 0.4, -half), accent, 1.5)
	draw_line(target_map + Vector2(-half, -half), target_map + Vector2(-half, -half * 0.4), accent, 1.5)
	draw_line(target_map + Vector2(half, -half), target_map + Vector2(half * 0.4, -half), accent, 1.5)
	draw_line(target_map + Vector2(half, -half), target_map + Vector2(half, -half * 0.4), accent, 1.5)
	draw_line(target_map + Vector2(-half, half), target_map + Vector2(-half * 0.4, half), accent, 1.5)
	draw_line(target_map + Vector2(-half, half), target_map + Vector2(-half, half * 0.4), accent, 1.5)
	draw_line(target_map + Vector2(half, half), target_map + Vector2(half * 0.4, half), accent, 1.5)
	draw_line(target_map + Vector2(half, half), target_map + Vector2(half, half * 0.4), accent, 1.5)


func _draw_ship(center: Vector2, color: Color) -> void:
	var heading_rad := deg_to_rad(_ship_heading_deg)
	var forward := Vector2.from_angle(heading_rad)
	var right := Vector2.from_angle(heading_rad + PI * 0.5)
	var tip := center + forward * 10.0
	var left := center - forward * 5.0 + right * 5.0
	var right_pt := center - forward * 5.0 - right * 5.0
	draw_colored_polygon(PackedVector2Array([tip, left, right_pt]), color)


func _refresh_legend() -> void:
	if _legend_scale != null:
		var step_m := int(round(_grid_step_m))
		_legend_scale.text = "Grid squares: %d m" % step_m
	if _legend_list == null:
		return
	for child in _legend_list.get_children():
		child.queue_free()
	var sensor_index := 0
	for circle_variant in _circles:
		if typeof(circle_variant) != TYPE_DICTIONARY:
			continue
		var circle: Dictionary = circle_variant
		var labels: PackedStringArray = circle.get("labels", PackedStringArray())
		var label_text := ", ".join(labels)
		var color: Color
		if str(circle.get("kind", "")) == "visual":
			color = get_theme_color("positive", "Cartel")
		else:
			color = _circle_color(circle, sensor_index)
			sensor_index += 1
		var range_m := int(round(float(circle.get("range_m", 0.0))))
		_legend_list.add_child(_legend_row(color, label_text, range_m))


func _legend_row(swatch_color: Color, label: String, range_m: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(14.0, 14.0)
	swatch.color = swatch_color
	row.add_child(swatch)
	var text := Label.new()
	text.text = "%s  %d m" % [label, range_m]
	text.theme_type_variation = &"Meta"
	row.add_child(text)
	return row


func _point_in_square(point: Vector2, center: Vector2, half_px: float) -> bool:
	var delta := point - center
	return absf(delta.x) <= half_px and absf(delta.y) <= half_px


func _contact_by_id(contact_id: String) -> Dictionary:
	for contact_variant in _contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if str(contact.get("id", "")) == contact_id:
			return contact
	return {}


func _find_contact_at(local_pos: Vector2) -> Dictionary:
	var layout := _map_layout()
	var center: Vector2 = layout["center"]
	var half_px: float = layout["half_px"]
	var scale: float = layout["scale"]
	if not _point_in_square(local_pos, center, half_px):
		return {}
	var hit_radius_sq := CONTACT_HIT_RADIUS * CONTACT_HIT_RADIUS
	for contact_variant in _contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if str(contact.get("id", "")) == "player":
			continue
		var contact_kind := str(contact.get("contact_kind", "landmark"))
		var draw_radius := NavMapDraw.contact_draw_radius(contact_kind, contact, true)
		var world_pos: Vector2 = contact.get("position", Vector2.ZERO)
		var map_pos := NavMapDraw.contact_map_pos(
			world_pos, _ship_pos, center, half_px, scale, contact_kind, draw_radius
		)
		if map_pos.x == INF:
			continue
		if map_pos.distance_squared_to(local_pos) <= hit_radius_sq:
			return contact
	return {}


func _update_hover_tooltip(local_pos: Vector2) -> void:
	_last_hover_pos = local_pos
	var layout := _map_layout()
	var center: Vector2 = layout["center"]
	if local_pos.distance_to(center) <= CONTACT_HIT_RADIUS + 4.0:
		tooltip_text = _player_broadcast_text
		return
	var contact := _find_contact_at(local_pos)
	if contact.is_empty():
		tooltip_text = ""
		return
	var contact_kind := str(contact.get("contact_kind", ""))
	if contact_kind == "traffic_npc":
		if _show_beacon_names and bool(contact.get("broadcasting", false)):
			tooltip_text = str(contact.get("name", ""))
		else:
			tooltip_text = ""
		return
	tooltip_text = str(contact.get("name", ""))
