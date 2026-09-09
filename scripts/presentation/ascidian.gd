extends Node2D
class_name Ascidian

const NspaceField := preload("res://scripts/presentation/nspace_field.gd")

var _field: NspaceField = null
var _visit_rng := RandomNumberGenerator.new()

var _radius: float = 120.0
var _speed: float = 45.0
var _wander_radius: float = 6000.0
var _altitude: float = 0.45
var _altitude_min: float = 0.12
var _altitude_max: float = 0.88
var _altitude_target: float = 0.5
var _altitude_speed: float = 0.06
var _altitude_wobble_amp: float = 0.05
var _altitude_wobble_speed: float = 0.22
var _segment_count: int = 24
var _wobble_amp: float = 18.0
var _pulse_speed: float = 0.55
var _phase_offset: float = 0.0
var _warm_a: Color = Color(1.0, 0.72, 0.38, 0.85)
var _warm_b: Color = Color(1.0, 0.42, 0.52, 0.85)
var _color_lerp: float = 0.0
var _color_drift_speed: float = 0.08
var _filament_count: int = 4
var _filament_angles: PackedFloat32Array = PackedFloat32Array()
var _core_offsets: Array = []

var _waypoint: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _fixed_swim_depth: float = -1.0


func configure(field: NspaceField, cfg: Dictionary, start_pos: Vector2, visit_rng: RandomNumberGenerator) -> void:
	_field = field
	_visit_rng = visit_rng
	_radius = visit_rng.randf_range(
		float(cfg.get("radius_min", 90.0)),
		float(cfg.get("radius_max", 180.0))
	)
	_speed = visit_rng.randf_range(
		float(cfg.get("speed_min", 22.0)),
		float(cfg.get("speed_max", 48.0))
	)
	_wander_radius = float(cfg.get("wander_radius_fraction", 0.72)) * float(cfg.get("play_bounds", 8000.0))
	if cfg.has("fixed_swim_depth"):
		_fixed_swim_depth = float(cfg["fixed_swim_depth"])
		_altitude_min = _fixed_swim_depth
		_altitude_max = _fixed_swim_depth
		_altitude = _fixed_swim_depth
		_altitude_target = _fixed_swim_depth
	else:
		_altitude_min = float(cfg.get("altitude_min", cfg.get("swim_depth_min", 0.12)))
		_altitude_max = float(cfg.get("altitude_max", cfg.get("swim_depth_max", 0.88)))
		_altitude = visit_rng.randf_range(_altitude_min, _altitude_max)
		_altitude_target = _pick_altitude_target()
	_altitude_speed = visit_rng.randf_range(
		float(cfg.get("altitude_drift_min", 0.035)),
		float(cfg.get("altitude_drift_max", 0.09))
	)
	_altitude_wobble_amp = visit_rng.randf_range(0.03, 0.07)
	_altitude_wobble_speed = visit_rng.randf_range(0.16, 0.32)
	_segment_count = visit_rng.randi_range(20, 28)
	_wobble_amp = _radius * visit_rng.randf_range(0.14, 0.24)
	_pulse_speed = visit_rng.randf_range(0.35, 0.75)
	_phase_offset = visit_rng.randf() * TAU
	_color_drift_speed = visit_rng.randf_range(0.05, 0.11)
	_warm_a = _pick_warm_color(visit_rng)
	_warm_b = _pick_warm_color(visit_rng)
	_color_lerp = visit_rng.randf()
	_filament_count = visit_rng.randi_range(3, 5)
	_filament_angles = PackedFloat32Array()
	for _i in range(_filament_count):
		_filament_angles.append(visit_rng.randf() * TAU)
	_core_offsets.clear()
	for _i in range(visit_rng.randi_range(2, 4)):
		_core_offsets.append({
			"angle": visit_rng.randf() * TAU,
			"dist": visit_rng.randf_range(0.08, 0.38),
			"size": visit_rng.randf_range(0.16, 0.32),
			"phase": visit_rng.randf() * TAU,
		})

	position = start_pos
	_velocity = Vector2.from_angle(visit_rng.randf() * TAU) * _speed * 0.15
	_pick_waypoint()
	z_index = 5
	visible = false


func get_visibility() -> float:
	return 1.0


func get_swim_depth() -> float:
	return _current_altitude()


func get_body_color() -> Color:
	return _warm_a.lerp(_warm_b, _color_lerp)


func get_radius() -> float:
	return _radius


func get_render_time() -> float:
	return _time


func get_pulse_speed() -> float:
	return _pulse_speed


func get_phase_offset() -> float:
	return _phase_offset


func build_outline() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(_segment_count):
		var angle := TAU * float(i) / float(_segment_count)
		var radial := _radius
		radial += sin(_time * _pulse_speed + angle * 2.1 + _phase_offset) * _wobble_amp * 0.52
		radial += sin(_time * _pulse_speed * 0.61 + angle * 3.4 + _phase_offset * 1.6) * _wobble_amp * 0.34
		radial += cos(_time * _pulse_speed * 0.43 + angle * 1.7 - _phase_offset * 0.8) * _wobble_amp * 0.22
		radial += sin(_time * _pulse_speed * 1.15 + angle * 5.2) * _wobble_amp * 0.08
		points.append(Vector2.from_angle(angle) * radial)
	return points


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return

	_time += delta
	_color_lerp = fmod(_color_lerp + _color_drift_speed * delta, 1.0)
	_update_altitude(delta)
	_wander(delta)


func _wander(delta: float) -> void:
	var to_waypoint := _waypoint - position
	var dist := to_waypoint.length()
	if dist < maxf(_radius * 2.2, 140.0):
		_pick_waypoint()
		if _fixed_swim_depth < 0.0 and _visit_rng.randf() < 0.55:
			_altitude_target = _pick_altitude_target()
		to_waypoint = _waypoint - position
		dist = to_waypoint.length()

	var desired := Vector2.ZERO
	if dist > 0.001:
		var urgency := clampf(dist / maxf(_radius * 5.0, 300.0), 0.15, 1.0)
		desired = to_waypoint / dist * _speed * urgency

	var drift := Vector2(
		sin(_time * 0.27 + _phase_offset),
		cos(_time * 0.23 + _phase_offset * 1.4)
	) * _speed * 0.18
	desired += drift

	var blend := 1.0 - exp(-delta * 0.65)
	_velocity = _velocity.lerp(desired, blend)
	position += _velocity * delta

	if position.length() > _wander_radius:
		position = position.normalized() * _wander_radius
		_velocity *= 0.5
		_pick_waypoint()


func _pick_waypoint() -> void:
	for _attempt in range(12):
		var angle := _visit_rng.randf() * TAU
		var radial := _visit_rng.randf_range(_wander_radius * 0.15, _wander_radius * 0.92)
		var candidate := Vector2.from_angle(angle) * radial
		if candidate.distance_to(position) > maxf(_radius * 2.5, 160.0):
			_waypoint = candidate
			return
	_waypoint = Vector2.from_angle(_visit_rng.randf() * TAU) * _wander_radius * 0.5


func _pick_altitude_target() -> float:
	return _visit_rng.randf_range(_altitude_min, _altitude_max)


func _current_altitude() -> float:
	if _fixed_swim_depth >= 0.0:
		return _fixed_swim_depth
	var wobble := sin(_time * _altitude_wobble_speed + _phase_offset) * _altitude_wobble_amp
	return clampf(_altitude + wobble, _altitude_min, _altitude_max)


func _update_altitude(delta: float) -> void:
	if _fixed_swim_depth >= 0.0:
		return
	if absf(_altitude - _altitude_target) < 0.025:
		_altitude_target = _pick_altitude_target()

	var blend := 1.0 - exp(-delta * _altitude_speed * 8.0)
	_altitude = lerpf(_altitude, _altitude_target, blend)


func _pick_warm_color(rng: RandomNumberGenerator) -> Color:
	var palette: Array = [
		Color(1.0, 0.88, 0.42, 0.90),
		Color(1.0, 0.62, 0.28, 0.90),
		Color(1.0, 0.48, 0.22, 0.90),
		Color(1.0, 0.38, 0.42, 0.90),
		Color(1.0, 0.52, 0.68, 0.90),
		Color(0.95, 0.45, 0.82, 0.90),
		Color(0.88, 0.52, 1.0, 0.88),
		Color(1.0, 0.72, 0.55, 0.90),
	]
	return palette[rng.randi_range(0, palette.size() - 1)]
