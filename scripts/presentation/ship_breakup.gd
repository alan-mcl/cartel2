class_name ShipBreakup
extends Node2D

const FRAGMENT_COUNT := 7
const LIFETIME_MIN := 0.5
const LIFETIME_MAX := 0.9
const CORE_FLASH := 0.15
const KICK_SPEED_MIN := 120.0
const KICK_SPEED_MAX := 420.0

var _fragments: Array[Dictionary] = []
var _elapsed := 0.0
var _tint := Color.WHITE


static func spawn(
	parent: Node2D,
	world_position: Vector2,
	ship_velocity: Vector2,
	tint: Color = Color.WHITE
) -> void:
	if parent == null:
		return
	var breakup := ShipBreakup.new()
	breakup.z_index = 10
	breakup.process_mode = Node.PROCESS_MODE_ALWAYS
	breakup._tint = tint
	breakup._build_fragments(ship_velocity)
	parent.add_child(breakup)
	breakup.global_position = world_position


func _build_fragments(ship_velocity: Vector2) -> void:
	_fragments.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i in FRAGMENT_COUNT:
		var inherit := rng.randf_range(0.5, 0.9)
		var kick_dir := Vector2.from_angle(rng.randf() * TAU)
		var kick := kick_dir * rng.randf_range(KICK_SPEED_MIN, KICK_SPEED_MAX)
		var lifetime := rng.randf_range(LIFETIME_MIN, LIFETIME_MAX)
		var spin := rng.randf_range(-9.0, 9.0)
		var size := rng.randf_range(6.0, 16.0)
		_fragments.append({
			"pos": Vector2.ZERO,
			"vel": ship_velocity * inherit + kick,
			"angle": rng.randf() * TAU,
			"spin": spin,
			"lifetime": lifetime,
			"age": 0.0,
			"poly": _random_shard_polygon(rng, size),
		})


func _random_shard_polygon(rng: RandomNumberGenerator, size: float) -> PackedVector2Array:
	var verts := rng.randi_range(4, 6)
	var points := PackedVector2Array()
	for i in verts:
		var r := size * rng.randf_range(0.55, 1.0)
		var a := TAU * float(i) / float(verts) + rng.randf_range(-0.35, 0.35)
		points.append(Vector2.from_angle(a) * r)
	return points


func _process(delta: float) -> void:
	_elapsed += delta
	var alive := false
	for frag in _fragments:
		var age: float = float(frag.get("age", 0.0)) + delta
		frag["age"] = age
		var lifetime: float = float(frag.get("lifetime", 1.0))
		if age >= lifetime:
			continue
		alive = true
		var pos: Vector2 = frag.get("pos", Vector2.ZERO)
		var vel: Vector2 = frag.get("vel", Vector2.ZERO)
		frag["pos"] = pos + vel * delta
		frag["angle"] = float(frag.get("angle", 0.0)) + float(frag.get("spin", 0.0)) * delta
	if not alive and _elapsed >= CORE_FLASH:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _elapsed <= CORE_FLASH:
		var core_alpha := 1.0 - _elapsed / CORE_FLASH
		draw_circle(Vector2.ZERO, 18.0, Color(1.0, 0.65, 0.35, core_alpha * 0.75))
		draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.9, 0.75, core_alpha))

	for frag in _fragments:
		var age: float = float(frag.get("age", 0.0))
		var lifetime: float = float(frag.get("lifetime", 1.0))
		if age >= lifetime:
			continue
		var t := age / lifetime
		var alpha := 1.0 - t * t
		var poly: PackedVector2Array = frag.get("poly", PackedVector2Array())
		if poly.is_empty():
			continue
		var angle: float = float(frag.get("angle", 0.0))
		var pos: Vector2 = frag.get("pos", Vector2.ZERO)
		var xf := Transform2D(angle, pos)
		var world_poly := PackedVector2Array()
		for p in poly:
			world_poly.append(xf * p)
		var fill := Color(
			_tint.r * 0.85 + 0.15,
			_tint.g * 0.7 + 0.1,
			_tint.b * 0.65 + 0.08,
			alpha * 0.95
		)
		draw_colored_polygon(world_poly, fill)
		draw_polyline(world_poly + PackedVector2Array([world_poly[0]]), Color(0.2, 0.22, 0.28, alpha * 0.6), 1.0)
