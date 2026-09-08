extends Control

const PANEL_SIZE := 220.0
const INNER_PADDING := 14.0
const CONTACT_HIT_RADIUS := 10.0
const CONTACT_DRAW_RADIUS := 4.0
const TRAFFIC_DRAW_RADIUS := 1.5
const ASCIDIAN_DRAW_RADIUS := 2.0
const ORBITAL_DRAW_RADIUS := 3.0
const BACKGROUND_ALPHA := 0.25
const BORDER_WIDTH := 1.5

var _nav_radius: float = 3500.0
var _ship_pos: Vector2 = Vector2.ZERO
var _ship_heading_deg: float = 0.0
var _contacts: Array = []
var _player_broadcast_text: String = ""
var _last_hover_pos: Vector2 = Vector2(-99999.0, -99999.0)


func set_player_broadcast(text: String) -> void:
	_player_broadcast_text = text


func set_nav_state(
	nav_radius: float,
	ship_pos: Vector2,
	ship_heading_deg: float,
	contacts: Array
) -> void:
	_nav_radius = maxf(nav_radius, 1.0)
	_ship_pos = ship_pos
	_ship_heading_deg = ship_heading_deg
	_contacts = contacts
	queue_redraw()


func set_feature_visible(active: bool) -> void:
	visible = active
	if not active:
		tooltip_text = ""


func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_SIZE, PANEL_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
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
	var map_radius: float = layout["radius"]
	var scale: float = layout["scale"]

	var surface := get_theme_color("surface", "Cartel")
	surface.a = BACKGROUND_ALPHA
	var border := get_theme_color("text", "Cartel")
	var accent := get_theme_color("accent", "Cartel")
	var info := get_theme_color("info", "Cartel")
	var muted := get_theme_color("text_muted", "Cartel")

	draw_circle(map_center, map_radius, surface)
	_draw_contacts(map_center, map_radius, scale, info, muted)
	_draw_ship(map_center, accent)
	draw_arc(map_center, map_radius, 0.0, TAU, 64, border, BORDER_WIDTH)


func _map_layout() -> Dictionary:
	var map_center := size * 0.5
	var map_radius := minf(size.x, size.y) * 0.5 - INNER_PADDING
	var view_radius := maxf(_nav_radius, 1.0)
	var scale := map_radius / view_radius
	return {
		"center": map_center,
		"radius": map_radius,
		"scale": scale,
		"view_radius": view_radius,
	}


func _world_to_map(world_pos: Vector2, center: Vector2, scale: float) -> Vector2:
	return center + (world_pos - _ship_pos) * scale


func _is_inside_map(map_pos: Vector2, center: Vector2, radius: float, inset: float = 0.0) -> bool:
	var effective_radius := maxf(radius - inset, 0.0)
	return map_pos.distance_squared_to(center) <= effective_radius * effective_radius


func _draw_contacts(center: Vector2, map_radius: float, scale: float, color: Color, label_color: Color) -> void:
	var label_inset := CONTACT_DRAW_RADIUS + 12.0
	for contact_variant in _contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if str(contact.get("id", "")) == "player":
			continue

		var world_pos: Vector2 = contact.get("position", Vector2.ZERO)
		var map_pos := _world_to_map(world_pos, center, scale)
		var contact_kind := str(contact.get("contact_kind", "landmark"))
		var draw_radius := _contact_draw_radius(contact_kind)
		if not _is_inside_map(map_pos, center, map_radius, draw_radius):
			continue

		var dot_color := _contact_color(contact_kind, color, label_color)
		draw_circle(map_pos, draw_radius, dot_color)

		var short_label := str(contact.get("short_label", ""))
		if short_label.is_empty():
			continue
		if not _is_inside_map(map_pos, center, map_radius, label_inset):
			continue

		var font := ThemeDB.fallback_font
		var font_size := ThemeDB.fallback_font_size - 2
		draw_string(font, map_pos + Vector2(6.0, 4.0), short_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)


func _contact_draw_radius(contact_kind: String) -> float:
	match contact_kind:
		"traffic_npc":
			return TRAFFIC_DRAW_RADIUS
		"ascidian":
			return ASCIDIAN_DRAW_RADIUS
		"orbital":
			return ORBITAL_DRAW_RADIUS
		_:
			return CONTACT_DRAW_RADIUS


func _contact_color(contact_kind: String, info: Color, muted: Color) -> Color:
	match contact_kind:
		"traffic_npc":
			return muted
		"ascidian":
			return Color(info.r, info.g, info.b, info.a * 0.42)
		"orbital":
			return Color(info.r, info.g, info.b, info.a * 0.65)
		_:
			return info


func _draw_ship(center: Vector2, color: Color) -> void:
	var heading_rad := deg_to_rad(_ship_heading_deg)
	var forward := Vector2.from_angle(heading_rad)
	var right := Vector2.from_angle(heading_rad + PI * 0.5)

	var tip := center + forward * 8.0
	var left := center - forward * 4.0 + right * 4.0
	var right_pt := center - forward * 4.0 - right * 4.0
	draw_colored_polygon(PackedVector2Array([tip, left, right_pt]), color)


func _update_hover_tooltip(local_pos: Vector2) -> void:
	_last_hover_pos = local_pos
	var layout := _map_layout()
	var map_center: Vector2 = layout["center"]
	if local_pos.distance_to(map_center) <= CONTACT_HIT_RADIUS + 4.0:
		tooltip_text = _player_broadcast_text
		return

	var contact := _find_contact_at(local_pos)
	if contact.is_empty():
		tooltip_text = ""
		return

	var contact_kind := str(contact.get("contact_kind", ""))
	if contact_kind == "traffic_npc":
		if bool(contact.get("broadcasting", false)):
			tooltip_text = str(contact.get("name", ""))
		else:
			tooltip_text = ""
		return

	tooltip_text = str(contact.get("name", ""))


func _find_contact_at(local_pos: Vector2) -> Dictionary:
	var layout := _map_layout()
	var map_center: Vector2 = layout["center"]
	var map_radius: float = layout["radius"]
	var scale: float = layout["scale"]

	if not _is_inside_map(local_pos, map_center, map_radius):
		return {}

	var hit_radius_sq := CONTACT_HIT_RADIUS * CONTACT_HIT_RADIUS
	for contact_variant in _contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if str(contact.get("id", "")) == "player":
			continue

		var world_pos: Vector2 = contact.get("position", Vector2.ZERO)
		var map_pos := _world_to_map(world_pos, map_center, scale)
		var draw_radius := _contact_draw_radius(str(contact.get("contact_kind", "landmark")))
		if not _is_inside_map(map_pos, map_center, map_radius, draw_radius):
			continue
		if map_pos.distance_squared_to(local_pos) <= hit_radius_sq:
			return contact

	return {}
