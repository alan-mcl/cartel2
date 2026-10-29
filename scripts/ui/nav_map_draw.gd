class_name NavMapDraw
extends RefCounted

const TRAFFIC_DRAW_RADIUS := 1.5
const TRAFFIC_BEACON_DRAW_RADIUS := 2.5
const ASCIDIAN_DRAW_RADIUS := 2.0
const ORBITAL_DRAW_RADIUS := 3.0
const STAR_DRAW_RADIUS := 5.0
const STAR_RIM_INSET := 6.0
const CONTACT_DRAW_RADIUS := 4.0
const AREA_CONTACT_SCALE := 1.35


static func contact_draw_radius(contact_kind: String, contact: Dictionary = {}, area_map: bool = false) -> float:
	var base := _base_contact_draw_radius(contact_kind, contact)
	if area_map:
		return base * AREA_CONTACT_SCALE
	return base


static func _base_contact_draw_radius(contact_kind: String, contact: Dictionary = {}) -> float:
	match contact_kind:
		"traffic_npc":
			if bool(contact.get("broadcasting", false)):
				return TRAFFIC_BEACON_DRAW_RADIUS
			return TRAFFIC_DRAW_RADIUS
		"ascidian":
			return ASCIDIAN_DRAW_RADIUS
		"shard":
			return TRAFFIC_DRAW_RADIUS * 0.55
		"debris":
			return TRAFFIC_DRAW_RADIUS * 0.65
		"orbital":
			return ORBITAL_DRAW_RADIUS
		"star":
			return STAR_DRAW_RADIUS
		_:
			return CONTACT_DRAW_RADIUS


static func contact_color(
	contact_kind: String,
	info: Color,
	muted: Color,
	contact: Dictionary = {}
) -> Color:
	match contact_kind:
		"traffic_npc":
			if bool(contact.get("broadcasting", false)):
				return info
			return muted
		"ascidian":
			return Color(info.r, info.g, info.b, info.a * 0.42)
		"shard":
			return Color(0.75, 0.92, 1.0, 0.85)
		"debris":
			return muted
		"orbital":
			return Color(info.r, info.g, info.b, info.a * 0.65)
		"star":
			var tint: Variant = contact.get("nav_color", null)
			if tint is Color:
				return tint as Color
			return Color(1.0, 0.88, 0.55, 1.0)
		_:
			return info


static func contact_map_pos(
	world_pos: Vector2,
	ship_pos: Vector2,
	center: Vector2,
	map_extent: float,
	scale: float,
	contact_kind: String,
	draw_radius: float
) -> Vector2:
	var map_pos := center + (world_pos - ship_pos) * scale
	if is_inside_square(map_pos, center, map_extent, draw_radius):
		return map_pos
	if contact_kind != "star":
		return Vector2(INF, INF)
	var offset := map_pos - center
	if offset.length_squared() < 0.001:
		return Vector2(INF, INF)
	var rim := maxf(map_extent - STAR_RIM_INSET - draw_radius, 1.0)
	return center + offset.normalized() * rim


static func is_inside_square(map_pos: Vector2, center: Vector2, half_extent: float, inset: float = 0.0) -> bool:
	var effective := maxf(half_extent - inset, 0.0)
	var delta := map_pos - center
	return absf(delta.x) <= effective and absf(delta.y) <= effective
