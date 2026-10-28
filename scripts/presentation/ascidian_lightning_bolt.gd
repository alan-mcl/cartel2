class_name AscidianLightningBolt
extends RefCounted

const LIFETIME := 0.35


static func build_polylines(from_pos: Vector2, to_pos: Vector2, rng: RandomNumberGenerator = null) -> Array:
	var lines: Array = []
	var roll := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		roll.randomize()
	var main_line := _jagged_line(from_pos, to_pos, 7, roll)
	lines.append(main_line)
	var fork_count := roll.randi_range(2, 3)
	for _i in fork_count:
		var t := roll.randf_range(0.25, 0.72)
		var fork_start := from_pos.lerp(to_pos, t)
		var fork_end := fork_start + (to_pos - from_pos).rotated(roll.randf_range(-1.1, 1.1)) * roll.randf_range(0.15, 0.38)
		lines.append(_jagged_line(fork_start, fork_end, 4, roll))
	return lines


static func draw_polylines(canvas: CanvasItem, polylines: Array, elapsed: float) -> void:
	if canvas == null or polylines.is_empty():
		return
	var alpha := 1.0 - elapsed / LIFETIME
	if alpha <= 0.0:
		return
	var core := Color(0.85, 0.96, 1.0, 0.92 * alpha)
	var halo := Color(0.55, 0.35, 1.0, 0.55 * alpha)
	for line_variant in polylines:
		if typeof(line_variant) != TYPE_PACKED_VECTOR2_ARRAY:
			continue
		var points: PackedVector2Array = line_variant
		if points.size() < 2:
			continue
		canvas.draw_polyline(points, halo, 7.0, true)
		canvas.draw_polyline(points, core, 3.0, true)


static func _jagged_line(a: Vector2, b: Vector2, segments: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var points := PackedVector2Array()
	var span := b - a
	if span.length_squared() < 1.0:
		points.append(a)
		points.append(b)
		return points
	var perp := span.orthogonal().normalized()
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var p := a.lerp(b, t)
		if i > 0 and i < segments:
			p += perp * rng.randf_range(-28.0, 28.0)
		points.append(p)
	return points
