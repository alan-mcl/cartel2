class_name HullHitbox
extends RefCounted

const ELLIPSE_SAMPLES := 16

static var _cache: Dictionary = {}


static func nose_extent(sprite_path: String, fallback: float = 20.0) -> float:
	var hull := hull_polygon_for_sprite(sprite_path)
	if hull.is_empty():
		return fallback
	var extent := 0.0
	for point in hull:
		extent = maxf(extent, -point.y)
	return maxf(extent, fallback)


static func muzzle_offset(
	sprite_path: String,
	projectile_radius: float = 5.0,
	fallback: float = 20.0
) -> float:
	return maxf(
		nose_extent(sprite_path, fallback) + projectile_radius + 2.0,
		fallback
	)


static func apply_from_chassis_sprite(collision_shape: CollisionShape2D, sprite_path: String) -> void:
	if collision_shape == null:
		return
	var hull := hull_polygon_for_sprite(sprite_path)
	if hull.is_empty():
		return
	var shape := ConvexPolygonShape2D.new()
	shape.points = hull
	collision_shape.shape = shape
	collision_shape.rotation = 0.0


static func hull_polygon_for_sprite(sprite_path: String) -> PackedVector2Array:
	if sprite_path.is_empty():
		return PackedVector2Array()
	if _cache.has(sprite_path):
		return (_cache[sprite_path] as PackedVector2Array).duplicate()

	var points := _parse_svg_points(sprite_path)
	var hull := _convex_hull(points)
	_cache[sprite_path] = hull
	return hull.duplicate()


static func _parse_svg_points(sprite_path: String) -> PackedVector2Array:
	var file := FileAccess.open(sprite_path, FileAccess.READ)
	if file == null:
		push_warning("HullHitbox: cannot read %s" % sprite_path)
		return PackedVector2Array()

	var text := file.get_as_text()
	file.close()

	var view_box := _parse_view_box(text)
	var img_size := _parse_image_size(text, view_box)
	var points: PackedVector2Array = []

	for match_result in RegEx.create_from_string(
		"<polygon[^>]*points\\s*=\\s*\"([^\"]+)\""
	).search_all(text):
		_append_polygon_points(points, match_result.get_string(1), view_box, img_size)

	for match_result in RegEx.create_from_string(
		"<rect[^>]*x\\s*=\\s*\"([^\"]+)\"[^>]*y\\s*=\\s*\"([^\"]+)\"[^>]*width\\s*=\\s*\"([^\"]+)\"[^>]*height\\s*=\\s*\"([^\"]+)\""
	).search_all(text):
		var rx := float(match_result.get_string(1))
		var ry := float(match_result.get_string(2))
		var rw := float(match_result.get_string(3))
		var rh := float(match_result.get_string(4))
		for corner in [Vector2(rx, ry), Vector2(rx + rw, ry), Vector2(rx + rw, ry + rh), Vector2(rx, ry + rh)]:
			points.append(_map_svg_point(corner, view_box, img_size))

	for match_result in RegEx.create_from_string(
		"<ellipse[^>]*cx\\s*=\\s*\"([^\"]+)\"[^>]*cy\\s*=\\s*\"([^\"]+)\"[^>]*rx\\s*=\\s*\"([^\"]+)\"[^>]*ry\\s*=\\s*\"([^\"]+)\""
	).search_all(text):
		var cx := float(match_result.get_string(1))
		var cy := float(match_result.get_string(2))
		var rx := float(match_result.get_string(3))
		var ry := float(match_result.get_string(4))
		for i in ELLIPSE_SAMPLES:
			var angle := TAU * float(i) / float(ELLIPSE_SAMPLES)
			var pt := Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry)
			points.append(_map_svg_point(pt, view_box, img_size))

	return points


static func _parse_view_box(text: String) -> Vector4:
	var regex := RegEx.create_from_string("viewBox\\s*=\\s*\"([^\"]+)\"")
	var result := regex.search(text)
	if result == null:
		return Vector4(0.0, 0.0, 64.0, 64.0)
	var parts := result.get_string(1).split(" ", false)
	if parts.size() != 4:
		return Vector4(0.0, 0.0, 64.0, 64.0)
	return Vector4(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))


static func _parse_image_size(text: String, view_box: Vector4) -> Vector2:
	var width_regex := RegEx.create_from_string("width\\s*=\\s*\"([0-9.]+)\"")
	var height_regex := RegEx.create_from_string("height\\s*=\\s*\"([0-9.]+)\"")
	var width_match := width_regex.search(text)
	var height_match := height_regex.search(text)
	if width_match != null and height_match != null:
		return Vector2(float(width_match.get_string(1)), float(height_match.get_string(1)))
	return Vector2(view_box.z, view_box.w)


static func _append_polygon_points(
	points: PackedVector2Array,
	points_attr: String,
	view_box: Vector4,
	img_size: Vector2
) -> void:
	var normalized := points_attr.replace(",", " ")
	var tokens := normalized.split(" ", false)
	var i := 0
	while i + 1 < tokens.size():
		if tokens[i].is_empty():
			i += 1
			continue
		var vx := float(tokens[i])
		var vy := float(tokens[i + 1])
		points.append(_map_svg_point(Vector2(vx, vy), view_box, img_size))
		i += 2


static func _map_svg_point(v: Vector2, view_box: Vector4, img_size: Vector2) -> Vector2:
	var cx := view_box.x + view_box.z * 0.5
	var cy := view_box.y + view_box.w * 0.5
	var sx := img_size.x / view_box.z if view_box.z > 0.001 else 1.0
	var sy := img_size.y / view_box.w if view_box.w > 0.001 else 1.0
	return Vector2((v.x - cx) * sx, (v.y - cy) * sy)


static func _convex_hull(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= 2:
		return points.duplicate()

	var sorted: Array = points.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if is_equal_approx(a.x, b.x):
			return a.y < b.y
		return a.x < b.x
	)

	var lower: PackedVector2Array = []
	for p in sorted:
		while lower.size() >= 2 and _cross(lower[-2], lower[-1], p) <= 0.0:
			lower.remove_at(lower.size() - 1)
		lower.append(p)

	var upper: PackedVector2Array = []
	for i in range(sorted.size() - 1, -1, -1):
		var p: Vector2 = sorted[i]
		while upper.size() >= 2 and _cross(upper[-2], upper[-1], p) <= 0.0:
			upper.remove_at(upper.size() - 1)
		upper.append(p)

	var hull := PackedVector2Array()
	for i in range(lower.size() - 1):
		hull.append(lower[i])
	for i in range(upper.size() - 1):
		hull.append(upper[i])
	return hull


static func _cross(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
