class_name EngineExhaust
extends Node2D

enum Placement { STERN, BOW, HULL }
enum WakeMode { NONE, SHORT, LONG, VERY_LONG }

const DEFAULT_ENGINE_TYPE := "unknown"
const AFT_NOZZLE_CLEARANCE := 4.0

const _STYLE_BY_TYPE: Dictionary = {
	"chemical": {"placement": Placement.STERN, "wake": WakeMode.SHORT},
	"hydro_thermal": {"placement": Placement.STERN, "wake": WakeMode.VERY_LONG},
	"direct_fusion": {"placement": Placement.STERN, "wake": WakeMode.NONE},
	"antimatter": {"placement": Placement.STERN, "wake": WakeMode.NONE},
	"integrated_sail": {"placement": Placement.BOW, "wake": WakeMode.NONE},
	"electric_plasma": {"placement": Placement.STERN, "wake": WakeMode.LONG},
	"gravitic": {"placement": Placement.HULL, "wake": WakeMode.NONE},
	DEFAULT_ENGINE_TYPE: {"placement": Placement.STERN, "wake": WakeMode.NONE},
}


static func style_for_engine_type(engine_type: String) -> Dictionary:
	var key := engine_type if _STYLE_BY_TYPE.has(engine_type) else DEFAULT_ENGINE_TYPE
	return _STYLE_BY_TYPE[key] as Dictionary


static func placement_for_engine_type(engine_type: String) -> int:
	return int(style_for_engine_type(engine_type).get("placement", Placement.STERN))


static func uses_wake_for_engine_type(engine_type: String) -> bool:
	var wake: int = int(style_for_engine_type(engine_type).get("wake", WakeMode.NONE))
	return wake != WakeMode.NONE


static func nozzle_aft_y(stern_extent_y: float) -> float:
	return stern_extent_y + AFT_NOZZLE_CLEARANCE


var _engine_type: String = DEFAULT_ENGINE_TYPE
var _thrusting: bool = false
var _strength: float = 0.0
var _stern_extent_y: float = 18.0
var _bow_extent_y: float = 18.0
var _trail_cap: int = 48
var _trail: Array = []
var _trail_emit_accum: float = 0.0


func set_engine_type(engine_type: String) -> void:
	var normalized := engine_type if not engine_type.is_empty() else DEFAULT_ENGINE_TYPE
	if normalized == _engine_type:
		return
	_engine_type = normalized
	_trail.clear()
	queue_redraw()


func set_hull_extents(stern_y: float, bow_y: float) -> void:
	_stern_extent_y = maxf(stern_y, 1.0)
	_bow_extent_y = maxf(bow_y, 1.0)


func set_trail_cap(cap: int) -> void:
	_trail_cap = maxi(cap, 8)


func set_thrusting(active: bool, strength: float = 1.0) -> void:
	var next_strength := clampf(strength, 0.0, 1.0) if active else 0.0
	var changed := _thrusting != active or not is_equal_approx(_strength, next_strength)
	_thrusting = active and next_strength > 0.001
	_strength = next_strength
	if changed:
		queue_redraw()


func _ready() -> void:
	z_index = -1
	set_process(true)


func _process(delta: float) -> void:
	var style := style_for_engine_type(_engine_type)
	var wake: int = int(style.get("wake", WakeMode.NONE))
	for i in range(_trail.size() - 1, -1, -1):
		var entry: Dictionary = _trail[i]
		entry["age"] = float(entry.get("age", 0.0)) + delta
		if float(entry["age"]) >= float(entry.get("life", 1.0)):
			_trail.remove_at(i)
		else:
			_trail[i] = entry

	if _thrusting and wake != WakeMode.NONE:
		_emit_trail_samples(delta, wake)
	queue_redraw()


func _emit_trail_samples(delta: float, wake: int) -> void:
	var interval := 0.06
	var life := 0.45
	match wake:
		WakeMode.SHORT:
			interval = 0.05
			life = 0.35
		WakeMode.LONG:
			interval = 0.04
			life = 0.9
		WakeMode.VERY_LONG:
			interval = 0.07
			life = 1.6
		_:
			return

	interval /= maxf(_strength, 0.35)
	_trail_emit_accum += delta
	while _trail_emit_accum >= interval:
		_trail_emit_accum -= interval
		_trail.append({"world_pos": to_global(_nozzle_local()), "age": 0.0, "life": life})
	while _trail.size() > _trail_cap:
		_trail.pop_front()


func _draw() -> void:
	if not _thrusting and _trail.is_empty():
		return

	var style := style_for_engine_type(_engine_type)
	var wake: int = int(style.get("wake", WakeMode.NONE))
	if wake != WakeMode.NONE:
		_draw_wake(wake)

	if not _thrusting:
		return

	match _engine_type:
		"chemical":
			_draw_chemical()
		"hydro_thermal":
			_draw_hydro_thermal()
		"direct_fusion":
			_draw_direct_fusion()
		"antimatter":
			_draw_antimatter()
		"integrated_sail":
			_draw_integrated_sail()
		"electric_plasma":
			_draw_electric_plasma()
		"gravitic":
			_draw_gravitic()
		_:
			_draw_fallback()


func _hull_center_local() -> Vector2:
	return Vector2.ZERO


func _bow_local() -> Vector2:
	return Vector2(0.0, -_bow_extent_y)


func _nozzle_local() -> Vector2:
	return Vector2(0.0, EngineExhaust.nozzle_aft_y(_stern_extent_y))


func _time_phase() -> float:
	return float(Time.get_ticks_msec()) * 0.001


func _draw_wake(wake: int) -> void:
	for entry_variant in _trail:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var world_pos: Vector2 = entry.get("world_pos", Vector2.ZERO)
		var age: float = float(entry.get("age", 0.0))
		var life: float = maxf(float(entry.get("life", 1.0)), 0.001)
		var t := clampf(1.0 - age / life, 0.0, 1.0)
		var local_pos := to_local(world_pos)
		var radius := 2.0 + (1.0 - t) * 3.0
		var alpha := t * 0.55 * _strength
		var color := Color(1.0, 0.55, 0.2, alpha)
		if _engine_type == "hydro_thermal":
			color = Color(0.85, 0.92, 1.0, alpha * 0.7)
			radius = 1.2 + (1.0 - t) * 2.2
		elif _engine_type == "electric_plasma":
			color = Color(0.2, 0.95, 0.85, alpha * (0.35 + 0.65 * t))
			radius = 2.5 + (1.0 - t) * 4.0
		elif wake == WakeMode.SHORT:
			color = Color(1.0, 0.65, 0.25, alpha * 0.8)
		draw_circle(local_pos, radius, color)


func _draw_chemical() -> void:
	var nozzle := _nozzle_local()
	var phase := _time_phase()
	var flicker := 0.85 + sin(phase * 22.0) * 0.08 + sin(phase * 7.3) * 0.05
	var len := (14.0 + sin(phase * 11.0) * 2.0) * _strength * flicker
	var half_w := 5.5 * _strength
	var pts := PackedVector2Array([
		nozzle + Vector2(-half_w, 0.0),
		nozzle + Vector2(half_w, 0.0),
		nozzle + Vector2(half_w * 0.35, len),
		nozzle + Vector2(0.0, len + 4.0),
		nozzle + Vector2(-half_w * 0.35, len),
	])
	draw_colored_polygon(pts, Color(1.0, 0.72, 0.18, 0.82 * _strength))
	draw_colored_polygon(pts, Color(1.0, 0.9, 0.45, 0.35 * _strength))


func _draw_hydro_thermal() -> void:
	var nozzle := _nozzle_local()
	var phase := _time_phase()
	var puff := 4.0 + sin(phase * 16.0) * 1.2
	var alpha := 0.65 * _strength
	draw_circle(nozzle, puff, Color(1.0, 1.0, 1.0, alpha * 0.55))
	draw_circle(nozzle + Vector2(0.0, 2.0), puff * 0.65, Color(0.75, 0.85, 0.95, alpha * 0.35))


func _draw_direct_fusion() -> void:
	var nozzle := _nozzle_local()
	var phase := _time_phase()
	var flicker := 0.92 + sin(phase * 28.0) * 0.06
	var len := 11.0 * _strength * flicker
	var half_w := 3.5 * _strength
	var core := PackedVector2Array([
		nozzle + Vector2(-half_w, 0.0),
		nozzle + Vector2(half_w, 0.0),
		nozzle + Vector2(0.0, len),
	])
	draw_colored_polygon(core, Color(0.75, 0.92, 1.0, 0.95 * _strength))
	draw_colored_polygon(core, Color(1.0, 1.0, 1.0, 0.55 * _strength))


func _draw_antimatter() -> void:
	var nozzle := _nozzle_local()
	var phase := _time_phase()
	var pulse := 0.65 + sin(phase * 18.0) * 0.35
	var r := (8.0 + sin(phase * 9.0) * 2.0) * _strength
	draw_circle(nozzle, r, Color(0.85, 0.55, 1.0, 0.55 * pulse * _strength))
	draw_circle(nozzle, r * 0.45, Color(1.0, 1.0, 1.0, 0.9 * pulse * _strength))


func _draw_integrated_sail() -> void:
	var bow := _bow_local()
	var phase := _time_phase()
	var sway := sin(phase * 5.5) * 6.0 + sin(phase * 2.1) * 3.0
	var arc_center := bow + Vector2(sway * 0.15, -8.0)
	var radius := 22.0 + sin(phase * 4.0) * 3.0
	var start := PI * 0.55 + sway * 0.01
	var end := PI * 1.45 + sway * 0.01
	var points := PackedVector2Array()
	var steps := 14
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := lerpf(start, end, t)
		points.append(arc_center + Vector2.from_angle(angle) * radius)
	var alpha := 0.55 + sin(phase * 7.0) * 0.15
	draw_polyline(points, Color(0.55, 0.85, 1.0, alpha * _strength), 2.5, true)
	draw_circle(bow + Vector2(sway * 0.2, -2.0), 3.5, Color(1.0, 0.95, 0.75, 0.45 * _strength))


func _draw_electric_plasma() -> void:
	var nozzle := _nozzle_local()
	var phase := _time_phase()
	var len := 9.0 * _strength
	var half_w := 4.0 * _strength
	var pts := PackedVector2Array([
		nozzle + Vector2(-half_w, 0.0),
		nozzle + Vector2(half_w, 0.0),
		nozzle + Vector2(half_w * 0.2, len),
		nozzle + Vector2(0.0, len + 2.0),
		nozzle + Vector2(-half_w * 0.2, len),
	])
	var teal := Color(0.15, 0.95, 0.82, 0.75 * _strength)
	draw_colored_polygon(pts, teal)
	draw_circle(
		nozzle,
		3.5 + sin(phase * 20.0),
		Color(0.4, 1.0, 0.95, 0.85 * _strength)
	)


func _draw_gravitic() -> void:
	var center := _hull_center_local()
	var phase := _time_phase()
	var pulse := 0.85 + sin(phase * 3.5) * 0.12
	var rx := 20.0 * pulse
	var ry := 24.0 * pulse
	var steps := 16
	var ring := PackedVector2Array()
	for i in range(steps):
		var angle := TAU * float(i) / float(steps)
		ring.append(
			center
			+ Vector2(
				cos(angle) * rx,
				sin(angle) * ry * 1.15 + maxf(_stern_extent_y * 0.12, 2.0)
			)
		)
	draw_colored_polygon(ring, Color(0.55, 0.25, 0.95, 0.18 * _strength))
	draw_circle(
		center + Vector2(0.0, _stern_extent_y * 0.35),
		8.0,
		Color(0.75, 0.45, 1.0, 0.28 * _strength)
	)


func _draw_fallback() -> void:
	var nozzle := _nozzle_local()
	var len := 12.0 * _strength
	var pts := PackedVector2Array([
		nozzle + Vector2(-6.0, 0.0),
		nozzle + Vector2(6.0, 0.0),
		nozzle + Vector2(0.0, len),
	])
	draw_colored_polygon(pts, Color(1.0, 0.55, 0.2, 0.85 * _strength))
