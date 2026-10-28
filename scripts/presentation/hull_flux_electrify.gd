class_name HullFluxElectrify
extends Node2D

const ARC_SEGMENTS := 5
const ARC_REFRESH_SEC := 0.07

var _hull: Sprite2D
var _glow: Sprite2D
var _phase: float = 0.0
var _arc_timer: float = 0.0
var _arcs: Array = []
var _rng := RandomNumberGenerator.new()


func setup(hull: Sprite2D) -> void:
	_hull = hull
	z_as_relative = false
	z_index = 6
	visible = false
	if _hull == null:
		return
	_glow = Sprite2D.new()
	_glow.name = "FluxGlow"
	_glow.centered = true
	_glow.texture = _hull.texture
	_glow.z_index = 1
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	add_child(_glow)
	_rebuild_arcs()


func sync_hull_texture() -> void:
	if _glow != null and _hull != null:
		_glow.texture = _hull.texture


func tick(active: bool, delta: float) -> void:
	if _hull == null or _glow == null:
		visible = false
		return
	visible = active
	if not active:
		return
	_phase += delta * 26.0
	_arc_timer -= delta
	if _arc_timer <= 0.0:
		_arc_timer = ARC_REFRESH_SEC
		_rebuild_arcs()
	var pulse_a := (sin(_phase) + 1.0) * 0.5
	var pulse_b := (sin(_phase * 2.35 + 0.8) + 1.0) * 0.5
	var cyan := Color(0.35, 0.92, 1.0, 0.25 + 0.45 * pulse_a)
	var violet := Color(0.82, 0.48, 1.0, 0.18 + 0.35 * pulse_b)
	_glow.modulate = cyan.lerp(violet, pulse_b)
	_glow.scale = Vector2.ONE * (1.0 + 0.06 * pulse_a)
	queue_redraw()


func _rebuild_arcs() -> void:
	_arcs.clear()
	if _hull == null or _hull.texture == null:
		return
	var size := _hull.texture.get_size()
	var rx := size.x * 0.42
	var ry := size.y * 0.44
	for _i in range(3):
		var start_angle := _rng.randf_range(0.0, TAU)
		var span := _rng.randf_range(0.35, 1.1)
		var points := PackedVector2Array()
		for seg in range(ARC_SEGMENTS + 1):
			var t := float(seg) / float(ARC_SEGMENTS)
			var angle := start_angle + span * (t - 0.5)
			var wobble := _rng.randf_range(-5.0, 5.0) if seg > 0 and seg < ARC_SEGMENTS else 0.0
			points.append(
				Vector2(cos(angle) * (rx + wobble), sin(angle) * (ry + wobble * 0.6))
			)
		_arcs.append(points)


func _draw() -> void:
	if not visible or _arcs.is_empty():
		return
	var pulse := (sin(_phase * 1.6) + 1.0) * 0.5
	var core := Color(0.75, 0.95, 1.0, 0.55 + 0.35 * pulse)
	var halo := Color(0.55, 0.35, 1.0, 0.35 + 0.25 * pulse)
	for arc_variant in _arcs:
		if typeof(arc_variant) != TYPE_PACKED_VECTOR2_ARRAY:
			continue
		var points: PackedVector2Array = arc_variant
		if points.size() < 2:
			continue
		draw_polyline(points, halo, 4.0, true)
		draw_polyline(points, core, 1.6, true)
