extends Node2D

var _palette: Dictionary = {}


func configure(palette: Dictionary) -> void:
	_palette = palette
	queue_redraw()


func _draw() -> void:
	var rim := _portal_color("portal_rim", Color(0.85, 0.95, 1.0, 0.95))
	var glow := _portal_color("portal_glow", Color(0.45, 0.75, 1.0, 0.35))
	var core := _portal_color("portal_core", Color(0.02, 0.04, 0.08, 0.9))

	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var segments := 28
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		outer.append(Vector2(cos(angle), sin(angle)) * 110.0)
		inner.append(Vector2(cos(angle), sin(angle)) * 58.0)

	draw_colored_polygon(outer, glow)
	draw_colored_polygon(inner, core)

	outer.append(outer[0])
	draw_polyline(outer, rim, 3.0, true)

	var tick_count := 6
	for i in range(tick_count):
		var angle := TAU * float(i) / float(tick_count)
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(dir * 72.0, dir * 102.0, rim, 2.0)


func _portal_color(key: String, fallback: Color) -> Color:
	if not _palette.has(key):
		return fallback
	var raw := str(_palette[key])
	if raw.contains(","):
		var parts := raw.split(",")
		if parts.size() >= 4:
			return Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))
	return Color(raw)
