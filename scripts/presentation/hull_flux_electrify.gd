class_name HullFluxElectrify
extends Node2D

const FluxLightningPulse := preload("res://scripts/presentation/flux_lightning_pulse.gd")

const ARC_SEGMENTS := 5
const ARC_REFRESH_SEC := 0.07

var _hull: Sprite2D
var _glow: Sprite2D
var _arc_timer: float = 0.0
var _arcs: Array = []
var _rng := RandomNumberGenerator.new()
var _lightning := FluxLightningPulse.new()
var _flash_level: float = 0.0


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
	_lightning.reset(44107)
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
		_lightning.reset(44107)
		return
	_flash_level = _lightning.advance(delta)
	_arc_timer -= delta
	var flash := _flash_level
	var arc_interval := lerpf(0.11, 0.04, flash)
	if _arc_timer <= 0.0:
		_arc_timer = arc_interval
		_rebuild_arcs()
	var cyan := Color(0.35, 0.92, 1.0, 0.12 + 0.55 * flash)
	var violet := Color(0.82, 0.48, 1.0, 0.08 + 0.42 * flash * _rng.randf_range(0.65, 1.0))
	_glow.modulate = cyan.lerp(violet, flash)
	_glow.scale = Vector2.ONE * (1.0 + 0.09 * flash)
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
	var core := Color(0.75, 0.95, 1.0, 0.2 + 0.75 * _flash_level)
	var halo := Color(0.55, 0.35, 1.0, 0.12 + 0.55 * _flash_level)
	for arc_variant in _arcs:
		if typeof(arc_variant) != TYPE_PACKED_VECTOR2_ARRAY:
			continue
		var points: PackedVector2Array = arc_variant
		if points.size() < 2:
			continue
		draw_polyline(points, halo, 4.0, true)
		draw_polyline(points, core, 1.6, true)
