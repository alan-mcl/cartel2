extends Node2D
class_name NspaceField

const InteractableScene := preload("res://scenes/world/interactable_marker.tscn")

var _play_bounds: float = 8000.0
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()

var _topo: Dictionary = {}
var _kick: Dictionary = {}
var _bound: Dictionary = {}
var _edge_cfg: Dictionary = {}
var _portal_config: Dictionary = {}
var _palette: Dictionary = {}

var _route_seed: int = 0
var _seed_phase: float = 0.0

var _rest: PackedVector2Array = PackedVector2Array()
var _animated: PackedVector2Array = PackedVector2Array()
var _heights: PackedFloat32Array = PackedFloat32Array()
var _faces: Array = []
var _edges: Array = []
var _outer_indices: PackedInt32Array = PackedInt32Array()
var _outer_index_set: Dictionary = {}
var _portal_face_index: int = -1

var _portal_node: Node2D = null
var _interactable: Interactable = null

var _last_ship_pos: Vector2 = Vector2.INF
var _edge_cooldown: float = 0.0
var _disarmed_edges: Dictionary = {}

var _deform_active: bool = false
var _deform_lerp: float = 0.0
var _deform_start: PackedVector2Array = PackedVector2Array()
var _deform_target: PackedVector2Array = PackedVector2Array()


func configure(unspace: Dictionary, catalog: Catalog, session: GameSession, play_bounds: float) -> void:
	_play_bounds = play_bounds
	z_index = -80

	var field_data: Dictionary = unspace.get("field", {})
	_palette = _dict(field_data.get("palette", {}))
	_topo = _dict(field_data.get("topo", {}))
	_kick = _dict(field_data.get("kick", {}))
	_bound = _dict(field_data.get("bound", {}))
	_edge_cfg = _dict(field_data.get("edge", {}))
	_portal_config = _dict(field_data.get("portal", {}))

	var solution := 0
	var n := int(unspace.get("n", 4))
	if session != null:
		solution = session.unspace_solution
		n = session.unspace_n
		if solution == 0 and not session.pending_destination_id.is_empty():
			var mapping := catalog.get_mapping(
				session.sector_id,
				session.pending_destination_id,
				session.unspace_n
			)
			solution = int(mapping.get("solution", 0))

	var seed_salt := int(_topo.get("seed_salt", _topo.get("seed", 0)))
	_route_seed = _derive_route_seed(solution, n, seed_salt)
	_seed_phase = float(_route_seed) * 0.017
	_rng.seed = _route_seed

	_build_topo_mesh()
	_build_edge_catalog()
	_pick_portal_face()
	_setup_portal(catalog, session)
	queue_redraw()


func get_portal_position() -> Vector2:
	if _portal_node != null:
		return _portal_node.global_position
	return Vector2.ZERO


func get_portal_node() -> Node2D:
	return _portal_node


func apply_forces(ship: CharacterBody2D, session: GameSession, delta: float) -> void:
	if ship == null or delta <= 0.0 or not ship.get("motion") is ShipMotion:
		return

	var ship_pos := ship.global_position
	var motion: ShipMotion = ship.get("motion")

	_check_edge_crossings(ship_pos, motion)
	_apply_boundary_push(ship_pos, motion, delta)

	_last_ship_pos = ship_pos


func _physics_process(delta: float) -> void:
	_time += delta
	if _edge_cooldown > 0.0:
		_edge_cooldown = maxf(0.0, _edge_cooldown - delta)
	_update_deform(delta)
	_update_animated_vertices()
	_update_portal()
	_update_disarmed_edges()
	queue_redraw()


func _draw() -> void:
	if _faces.is_empty():
		return

	var peak := _color("peak", Color(0.66, 0.96, 1.0, 0.94))
	var trough := _color("trough", Color(0.16, 0.10, 0.38, 0.94))
	var accent_violet := _color("accent_violet", Color(0.58, 0.38, 0.98, 0.92))
	var accent_teal := _color("accent_teal", Color(0.28, 0.88, 0.82, 0.92))
	var accent_amber := _color("accent_amber", Color(1.0, 0.72, 0.38, 0.90))
	var accent_rose := _color("accent_rose", Color(0.98, 0.48, 0.72, 0.90))
	var edge_base := _color("edge", Color(0.48, 0.82, 0.98, 0.88))
	var ridge := _color("ridge", Color(0.82, 0.98, 1.0, 0.98))

	for face_index in range(_faces.size()):
		var face_variant = _faces[face_index]
		if typeof(face_variant) != TYPE_ARRAY:
			continue
		var face: Array = face_variant
		if face.size() < 3:
			continue
		var i0 := int(face[0])
		var i1 := int(face[1])
		var i2 := int(face[2])
		if i0 >= _animated.size() or i1 >= _animated.size() or i2 >= _animated.size():
			continue

		var h := (_heights[i0] + _heights[i1] + _heights[i2]) / 3.0
		var centroid := (_animated[i0] + _animated[i1] + _animated[i2]) / 3.0
		var angle := atan2(centroid.y, centroid.x)
		var diversity := (sin(angle * 2.1 + _seed_phase) * 0.5 + 0.5)
		var accent_mix := accent_teal.lerp(accent_amber, diversity)
		accent_mix = accent_mix.lerp(accent_rose, sin(angle * 3.7 - _seed_phase * 0.6) * 0.5 + 0.5)
		var low := trough.lerp(accent_violet, diversity * 0.55)
		var high := peak.lerp(accent_mix, 0.35 + diversity * 0.25)
		var fill := low.lerp(high, h).lightened(0.14)
		fill.a = minf(fill.a + 0.08, 1.0)
		if face_index == _portal_face_index:
			fill = fill.lerp(_color("portal_host", Color(0.95, 0.55, 0.25, 0.45)), 0.35)

		var p0 := _animated[i0]
		var p1 := _animated[i1]
		var p2 := _animated[i2]
		if not _is_valid_triangle(p0, p1, p2):
			continue

		draw_colored_polygon(PackedVector2Array([p0, p1, p2]), fill)

	for edge in _edges:
		var v0: int = edge.get("v0", 0)
		var v1: int = edge.get("v1", 0)
		if v0 >= _animated.size() or v1 >= _animated.size():
			continue
		var p0 := _animated[v0]
		var p1 := _animated[v1]
		var height_delta := absf(_heights[v0] - _heights[v1])
		var width := lerpf(1.2, 2.8, clampf(height_delta * 2.5, 0.0, 1.0))
		var edge_col := edge_base.lerp(ridge, clampf(height_delta * 1.8, 0.0, 1.0))
		draw_line(p0, p1, edge_col, width)


func _build_topo_mesh() -> void:
	_rest.clear()
	_faces.clear()
	_outer_indices.clear()

	var ring_count := maxi(3, int(_topo.get("ring_count", 7)))
	var points_per_ring := maxi(6, int(_topo.get("points_per_ring", 8)))
	var jitter := float(_topo.get("jitter", 0.22))

	var ring_starts: Array = []
	var ring_counts: Array = []

	_rest.append(Vector2.ZERO)
	ring_starts.append(0)
	ring_counts.append(1)

	for ring in range(1, ring_count + 1):
		var radius := _play_bounds * float(ring) / float(ring_count)
		var count := points_per_ring + ring * 3
		ring_starts.append(_rest.size())
		ring_counts.append(count)

		for i in range(count):
			var angle := TAU * float(i) / float(count) + _rng.randf_range(-jitter, jitter)
			var radial := radius * _rng.randf_range(1.0 - jitter * 0.35, 1.0 + jitter * 0.15)
			if ring == ring_count:
				radial = _play_bounds * _rng.randf_range(0.94, 1.0)
			_rest.append(Vector2(cos(angle), sin(angle)) * radial)

		if ring == ring_count:
			for idx in range(count):
				_outer_indices.append(int(ring_starts[ring]) + idx)

	var outer_set: Dictionary = {}
	for idx in _outer_indices:
		outer_set[idx] = true

	# Fan from center to first ring.
	var r1_start: int = ring_starts[1]
	var r1_count: int = ring_counts[1]
	for i in range(r1_count):
		_faces.append([0, r1_start + i, r1_start + ((i + 1) % r1_count)])

	# Stitch rings together.
	for ring in range(1, ring_count):
		var inner_start: int = ring_starts[ring]
		var inner_count: int = ring_counts[ring]
		var outer_start: int = ring_starts[ring + 1]
		var outer_count: int = ring_counts[ring + 1]
		for inner_i in range(inner_count):
			var next_inner := (inner_i + 1) % inner_count
			var o_start := int(floor(float(inner_i) / float(inner_count) * outer_count))
			var o_end := int(floor(float(inner_i + 1) / float(inner_count) * outer_count))
			o_end = o_end % outer_count
			if o_end == o_start:
				o_end = (o_start + 1) % outer_count
			var i0 := inner_start + inner_i
			var i1 := inner_start + next_inner
			var o0 := outer_start + o_start
			var o1 := outer_start + o_end
			_faces.append([i0, i1, o1])
			_faces.append([i0, o1, o0])

	_recompute_heights()
	_animated = _rest.duplicate()
	_outer_index_set = outer_set


func _recompute_heights() -> void:
	_heights.resize(_rest.size())
	var freq := float(_topo.get("height_freq", 0.0028))
	var seed_offset := _seed_phase
	for i in range(_rest.size()):
		var pos := _rest[i]
		var n := sin(pos.x * freq + seed_offset) * cos(pos.y * freq * 0.73 + seed_offset * 1.7)
		n += sin(pos.x * freq * 2.15 + pos.y * freq * 1.45 + seed_offset) * 0.42
		n += cos(pos.length() * freq * 0.55 + seed_offset * 2.3) * 0.28
		_heights[i] = clampf((n + 1.45) / 2.9, 0.0, 1.0)


func _update_animated_vertices() -> void:
	var shimmer_amp := float(_topo.get("shimmer_amp", 4.0))
	var shimmer_speed := float(_topo.get("shimmer_speed", 0.35))
	_animated = _rest.duplicate()
	for i in range(_rest.size()):
		var wobble := Vector2(
			sin(_time * shimmer_speed + float(i) * 0.91),
			cos(_time * shimmer_speed * 0.83 + float(i) * 1.37)
		) * shimmer_amp
		_animated[i] = _rest[i] + wobble


func _build_edge_catalog() -> void:
	_edges.clear()
	var seen: Dictionary = {}
	for face_variant in _faces:
		if typeof(face_variant) != TYPE_ARRAY:
			continue
		var face: Array = face_variant
		for i in range(face.size()):
			var v0 := int(face[i])
			var v1 := int(face[(i + 1) % face.size()])
			var lo := mini(v0, v1)
			var hi := maxi(v0, v1)
			var key := "%d:%d" % [lo, hi]
			if seen.has(key):
				continue
			seen[key] = true
			_edges.append({"v0": lo, "v1": hi, "key": key})


func _check_edge_crossings(ship_pos: Vector2, motion: ShipMotion) -> void:
	if _last_ship_pos == Vector2.INF or _deform_active or _edge_cooldown > 0.0:
		return

	var travel := ship_pos - _last_ship_pos
	if travel.length_squared() < 4.0:
		return

	var thickness := float(_edge_cfg.get("thickness", 45.0))
	for edge in _edges:
		var key: String = edge.get("key", "")
		if _disarmed_edges.has(key):
			continue

		var v0: int = edge.get("v0", 0)
		var v1: int = edge.get("v1", 0)
		if v0 >= _animated.size() or v1 >= _animated.size():
			continue

		var a := _animated[v0]
		var b := _animated[v1]
		if not _segment_crosses_thick_edge(_last_ship_pos, ship_pos, a, b, thickness):
			continue

		_apply_edge_kick(motion)
		var deform_chance := float(_topo.get("deform_chance", 0.35))
		if _rng.randf() <= deform_chance:
			_trigger_deform()

		_disarmed_edges[key] = true
		_edge_cooldown = float(_edge_cfg.get("cooldown", 1.0))
		return


func _apply_edge_kick(motion: ShipMotion) -> void:
	var kick_min := float(_kick.get("min", 35.0))
	var kick_max := float(_kick.get("max", 95.0))
	var magnitude := _rng.randf_range(kick_min, kick_max)
	var angle := _rng.randf() * TAU
	motion.velocity += Vector2.from_angle(angle) * magnitude


func _apply_boundary_push(ship_pos: Vector2, motion: ShipMotion, delta: float) -> void:
	var band_fraction := float(_bound.get("band_fraction", 0.18))
	var strength := float(_bound.get("strength", 280.0))
	var dist := ship_pos.length()
	var inner := _play_bounds * (1.0 - band_fraction)
	if dist <= inner or dist < 0.001:
		return

	var t := clampf((dist - inner) / maxf(_play_bounds - inner, 1.0), 0.0, 1.0)
	var inward := -ship_pos.normalized()
	motion.velocity += inward * strength * t * t * delta


func _trigger_deform() -> void:
	if _deform_active:
		return

	var pivot := Vector2(
		_rng.randf_range(-_play_bounds * 0.18, _play_bounds * 0.18),
		_rng.randf_range(-_play_bounds * 0.18, _play_bounds * 0.18)
	)
	var rotate_max := float(_topo.get("deform_rotate_max", 0.35))
	var scale_min := float(_topo.get("deform_scale_min", 0.93))
	var scale_max := float(_topo.get("deform_scale_max", 1.07))
	var angle := _rng.randf_range(-rotate_max, rotate_max)
	var scale := _rng.randf_range(scale_min, scale_max)
	var jitter := float(_topo.get("jitter", 0.22)) * _play_bounds * 0.035

	_deform_start = _rest.duplicate()
	_deform_target = PackedVector2Array()
	for i in range(_rest.size()):
		var offset := _rest[i] - pivot
		var transformed := pivot + offset.rotated(angle) * scale
		transformed += Vector2(
			_rng.randf_range(-jitter, jitter),
			_rng.randf_range(-jitter, jitter)
		)
		if _outer_index_set.has(i):
			var dist := transformed.length()
			if dist > 0.001:
				transformed = transformed / dist * _play_bounds * _rng.randf_range(0.94, 1.0)
		_deform_target.append(transformed)

	_deform_active = true
	_deform_lerp = 0.0


func _update_deform(delta: float) -> void:
	if not _deform_active:
		return

	var duration := float(_topo.get("deform_duration", 0.62))
	_deform_lerp += delta / duration
	var t := clampf(_deform_lerp, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)

	_rest = PackedVector2Array()
	for i in range(_deform_start.size()):
		_rest.append(_deform_start[i].lerp(_deform_target[i], t))

	if _deform_lerp >= 1.0:
		_rest = _deform_target.duplicate()
		_recompute_heights()
		_deform_active = false
		_deform_start.clear()
		_deform_target.clear()
	else:
		_recompute_heights()


func _update_disarmed_edges() -> void:
	if _disarmed_edges.is_empty() or _last_ship_pos == Vector2.INF:
		return

	var thickness := float(_edge_cfg.get("thickness", 45.0))
	var rearm: Array = []
	for key in _disarmed_edges.keys():
		if not _ship_near_edge(str(key), thickness * 3.0):
			rearm.append(str(key))

	for key in rearm:
		_disarmed_edges.erase(key)


func _ship_near_edge(edge_key: String, distance: float) -> bool:
	var parts := edge_key.split(":")
	if parts.size() != 2:
		return false
	var v0 := int(parts[0])
	var v1 := int(parts[1])
	if v0 >= _animated.size() or v1 >= _animated.size():
		return false
	var closest := Geometry2D.get_closest_point_to_segment(_last_ship_pos, _animated[v0], _animated[v1])
	return _last_ship_pos.distance_to(closest) <= distance


func _segment_crosses_thick_edge(from_pos: Vector2, to_pos: Vector2, a: Vector2, b: Vector2, thickness: float) -> bool:
	if Geometry2D.segment_intersects_segment(from_pos, to_pos, a, b) != null:
		return true

	var edge_dir := b - a
	if edge_dir.length_squared() < 0.001:
		return false

	var normal := Vector2(-edge_dir.y, edge_dir.x).normalized()
	var d_from := (from_pos - a).dot(normal)
	var d_to := (to_pos - a).dot(normal)
	if d_from * d_to >= 0.0:
		return false
	if absf(d_from) > thickness and absf(d_to) > thickness:
		return false

	var travel := to_pos - from_pos
	var denom := edge_dir.x * travel.y - edge_dir.y * travel.x
	if absf(denom) < 0.001:
		return false

	var diff := from_pos - a
	var t := (diff.x * travel.y - diff.y * travel.x) / denom
	if t < 0.0 or t > 1.0:
		return false

	var u := (diff.x * edge_dir.y - diff.y * edge_dir.x) / denom
	return u >= 0.0 and u <= 1.0


func _pick_portal_face() -> void:
	_portal_face_index = -1
	if _faces.is_empty():
		return

	var best_score := -INF
	var spawn_hint := Vector2(-_play_bounds * 0.45, 0.0)
	for face_index in range(_faces.size()):
		var face_variant = _faces[face_index]
		if typeof(face_variant) != TYPE_ARRAY:
			continue
		var face: Array = face_variant
		if face.size() < 3:
			continue
		var centroid := _face_centroid(face)
		var dist_origin := centroid.length()
		if dist_origin < _play_bounds * 0.25 or dist_origin > _play_bounds * 0.78:
			continue
		if centroid.distance_to(spawn_hint) < _play_bounds * 0.35:
			continue
		var score := dist_origin + centroid.distance_to(spawn_hint) * 0.35
		if score > best_score:
			best_score = score
			_portal_face_index = face_index


func _face_centroid(face: Array) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for index_variant in face:
		var index := int(index_variant)
		if index < 0 or index >= _rest.size():
			continue
		sum += _rest[index]
		count += 1
	if count == 0:
		return Vector2.ZERO
	return sum / float(count)


func _update_portal() -> void:
	if _portal_node == null or _portal_face_index < 0:
		return

	var face_variant = _faces[_portal_face_index]
	if typeof(face_variant) != TYPE_ARRAY:
		return
	var portal_pos := _face_centroid_animated(face_variant as Array)
	portal_pos = _leash_position(portal_pos)
	_portal_node.position = portal_pos
	if _portal_node.has_method("queue_redraw"):
		_portal_node.queue_redraw()


func _face_centroid_animated(face: Array) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for index_variant in face:
		var index := int(index_variant)
		if index < 0 or index >= _animated.size():
			continue
		sum += _animated[index]
		count += 1
	if count == 0:
		return Vector2.ZERO
	return sum / float(count)


func _leash_position(pos: Vector2) -> Vector2:
	var leash_fraction := float(_portal_config.get("leash_fraction", 0.88))
	var leash := _play_bounds * leash_fraction
	if pos.length() <= leash:
		return pos
	return pos.normalized() * leash


func _setup_portal(catalog: Catalog, _session: GameSession) -> void:
	_portal_node = Node2D.new()
	_portal_node.set_script(preload("res://scripts/presentation/nspace_portal.gd"))
	_portal_node.name = "ExitPortal"
	_portal_node.z_index = 10
	add_child(_portal_node)

	var interactable_root: Area2D = InteractableScene.instantiate()
	interactable_root.name = "Interactable"
	_portal_node.add_child(interactable_root)

	var collision := interactable_root.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null and collision.shape is CircleShape2D:
		(collision.shape as CircleShape2D).radius = float(_portal_config.get("interact_radius", 78.0))

	if interactable_root is Interactable:
		_interactable = interactable_root
		var interactable_id := str(_portal_config.get("interactable", "unspace_exit"))
		var data := catalog.get_interactable(interactable_id)
		if not data.is_empty():
			_interactable.definition = InteractableDef.from_dict(data)
			_interactable.visible = true

	if _portal_node.has_method("configure"):
		_portal_node.call("configure", _palette)


func _color(key: String, fallback: Color) -> Color:
	if not _palette.has(key):
		return fallback
	var raw: Variant = _palette[key]
	if typeof(raw) == TYPE_STRING:
		var text := str(raw)
		if text.contains(","):
			var parts := text.split(",")
			if parts.size() >= 4:
				return Color(
					float(parts[0]),
					float(parts[1]),
					float(parts[2]),
					float(parts[3])
				)
		return Color(text)
	return fallback


func _derive_route_seed(solution: int, n: int, salt: int) -> int:
	var packed := "%d:%d:%d" % [solution, n, salt]
	return absi(packed.hash())


func _is_valid_triangle(a: Vector2, b: Vector2, c: Vector2) -> bool:
	if not is_finite(a.x) or not is_finite(a.y):
		return false
	if not is_finite(b.x) or not is_finite(b.y):
		return false
	if not is_finite(c.x) or not is_finite(c.y):
		return false
	if a.is_equal_approx(b) or b.is_equal_approx(c) or c.is_equal_approx(a):
		return false
	var area2 := absf((b - a).cross(c - a))
	return area2 > maxf(4.0, _play_bounds * 0.00005)


func _dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
