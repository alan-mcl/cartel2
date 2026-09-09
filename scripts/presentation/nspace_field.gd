extends Node2D
class_name NspaceField

const InteractableScene := preload("res://scenes/world/interactable_marker.tscn")
const Ascidian := preload("res://scripts/presentation/ascidian.gd")
const NspaceBackdrop3D := preload("res://scripts/presentation/nspace_backdrop_3d.gd")

var _play_bounds: float = 8000.0
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()

var _topo: Dictionary = {}
var _kick: Dictionary = {}
var _bound: Dictionary = {}
var _edge_cfg: Dictionary = {}
var _portal_config: Dictionary = {}
var _palette: Dictionary = {}
var _inhabitants_cfg: Dictionary = {}

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
var _ascidians: Array = []
var _visit_rng := RandomNumberGenerator.new()

var _last_ship_pos: Vector2 = Vector2.INF
var _edge_cooldown: float = 0.0
var _disarmed_edges: Dictionary = {}

var _deform_active: bool = false
var _deform_lerp: float = 0.0
var _deform_start: PackedVector2Array = PackedVector2Array()
var _deform_target: PackedVector2Array = PackedVector2Array()

var _backdrop_viewport: SubViewport = null
var _backdrop_3d: NspaceBackdrop3D = null
var _height_scale: float = 600.0


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
	_inhabitants_cfg = _dict(field_data.get("inhabitants", {}))

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

	_height_scale = float(_topo.get("height_scale", 600.0))
	process_priority = 10

	_build_topo_mesh()
	_build_edge_catalog()
	_pick_portal_face()
	_setup_backdrop_3d()
	_setup_portal(catalog, session)
	_update_portal()
	_spawn_ascidians(unspace)
	_update_backdrop()


func sample_height(world_pos: Vector2) -> float:
	var local_pos := to_local(world_pos)
	if _faces.is_empty() or _animated.is_empty() or _heights.is_empty():
		return 0.0

	for face_variant in _faces:
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

		var a := _animated[i0]
		var b := _animated[i1]
		var c := _animated[i2]
		var bary := _barycentric(local_pos, a, b, c)
		if bary.x < -0.001 or bary.y < -0.001 or bary.z < -0.001:
			continue
		return _heights[i0] * bary.x + _heights[i1] * bary.y + _heights[i2] * bary.z

	return 0.0


func get_inhabitant_contacts() -> Array:
	var contacts: Array = []
	for index in range(_ascidians.size()):
		var ascidian_variant = _ascidians[index]
		if not ascidian_variant is Ascidian:
			continue
		var ascidian: Ascidian = ascidian_variant
		contacts.append({
			"id": "ascidian_%d" % index,
			"name": "Ascidian",
			"short_label": "",
			"contact_kind": "ascidian",
			"position": ascidian.global_position,
		})
	return contacts


func get_portal_position() -> Vector2:
	if _portal_node != null:
		return _portal_node.global_position
	return Vector2.ZERO


func get_portal_node() -> Node2D:
	return _portal_node


func get_animated_vertices() -> PackedVector2Array:
	return _animated


func get_heights() -> PackedFloat32Array:
	return _heights


func get_faces() -> Array:
	return _faces


func get_edges() -> Array:
	return _edges


func get_ascidians() -> Array:
	return _ascidians


func get_seed_phase() -> float:
	return _seed_phase


func get_portal_face_index() -> int:
	return _portal_face_index


func get_height_scale() -> float:
	return _height_scale


func get_ascidian_depth_bias() -> float:
	return float(_inhabitants_cfg.get("depth_bias", 12.0))


func get_palette_color(key: String, fallback: Color) -> Color:
	return _color(key, fallback)


func get_face_fill_color(face_index: int) -> Color:
	var peak := _color("peak", Color(0.49, 0.91, 1.0, 0.90))
	var trough := _color("trough", Color(0.10, 0.05, 0.23, 0.92))
	var shallow := _color("shallow", Color(0.14, 0.12, 0.42, 0.92))
	var bright := _color("bright", Color(0.62, 0.98, 1.0, 0.94))
	var portal_host := _color("portal_host", Color(0.95, 0.55, 0.25, 0.45))
	return _compute_face_fill(face_index, peak, trough, shallow, bright, portal_host)


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


func _process(_delta: float) -> void:
	_update_backdrop()


func _setup_backdrop_3d() -> void:
	_backdrop_viewport = SubViewport.new()
	_backdrop_viewport.name = "BackdropViewport"
	_backdrop_viewport.own_world_3d = true
	_backdrop_viewport.transparent_bg = false
	_backdrop_viewport.handle_input_locally = false
	_backdrop_viewport.disable_3d = false
	_backdrop_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_backdrop_viewport.size = _get_render_size()
	add_child(_backdrop_viewport)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.03, 0.07, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.32, 0.45)
	env.ambient_light_energy = 1.0
	world_env.environment = env
	_backdrop_viewport.add_child(world_env)

	var root_3d := Node3D.new()
	root_3d.name = "BackdropRoot"
	_backdrop_viewport.add_child(root_3d)

	var light := DirectionalLight3D.new()
	light.name = "TopoLight"
	light.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	light.light_energy = 1.35
	light.light_color = Color(0.85, 0.92, 1.0)
	root_3d.add_child(light)

	var fill := OmniLight3D.new()
	fill.name = "TopoFill"
	fill.light_energy = 0.85
	fill.light_color = Color(0.55, 0.62, 0.82)
	fill.omni_range = 20000.0
	fill.position = Vector3(0.0, 0.0, 1200.0)
	root_3d.add_child(fill)

	_backdrop_3d = NspaceBackdrop3D.new()
	_backdrop_3d.name = "Backdrop3D"
	_backdrop_3d.configure(self, _height_scale)
	root_3d.add_child(_backdrop_3d)

	call_deferred("queue_redraw")


func _draw() -> void:
	if _backdrop_viewport == null:
		return

	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return

	var tex := _backdrop_viewport.get_texture()
	if tex == null:
		return

	var tex_size := tex.get_size()
	var center := to_local(camera.get_screen_center_position())
	var scale := Vector2.ONE / camera.zoom
	draw_set_transform_matrix(Transform2D(Vector2(scale.x, 0.0), Vector2(0.0, -scale.y), center))
	draw_texture_rect(tex, Rect2(-tex_size * 0.5, tex_size), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _update_backdrop() -> void:
	if _backdrop_3d == null or _backdrop_viewport == null:
		return

	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return

	var vp_size := _get_render_size()
	if _backdrop_viewport.size != vp_size:
		_backdrop_viewport.size = vp_size

	_backdrop_3d.sync_camera_from_2d(camera, Vector2(vp_size))
	_backdrop_3d.rebuild()
	queue_redraw()


func _compute_face_fill(
	face_index: int,
	peak: Color,
	trough: Color,
	shallow: Color,
	bright: Color,
	portal_host: Color
) -> Color:
	var fallback := trough
	if face_index < 0 or face_index >= _faces.size():
		return fallback

	var face_variant = _faces[face_index]
	if typeof(face_variant) != TYPE_ARRAY:
		return fallback
	var face: Array = face_variant
	if face.size() < 3:
		return fallback

	var i0 := int(face[0])
	var i1 := int(face[1])
	var i2 := int(face[2])
	if i0 >= _animated.size() or i1 >= _animated.size() or i2 >= _animated.size():
		return fallback

	var h := (_heights[i0] + _heights[i1] + _heights[i2]) / 3.0
	var centroid := (_animated[i0] + _animated[i1] + _animated[i2]) / 3.0
	var angle := atan2(centroid.y, centroid.x)
	var blue_shift := sin(angle * 1.8 + _seed_phase) * 0.5 + 0.5
	var low := trough.lerp(shallow, blue_shift * 0.35)
	var high := peak.lerp(bright, blue_shift * 0.25)
	var fill := low.lerp(high, h)
	fill = fill.lerp(fill.lightened(0.12), 0.55)
	fill.a = minf(fill.a + 0.06, 1.0)
	if face_index == _portal_face_index:
		fill = fill.lerp(portal_host, 0.35)

	return fill


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
	var amplitude := float(_topo.get("height_amplitude", 1.0))
	var contrast := float(_topo.get("height_contrast", 1.0))
	var seed_offset := _seed_phase
	for i in range(_rest.size()):
		var pos := _rest[i]
		var n := sin(pos.x * freq + seed_offset) * cos(pos.y * freq * 0.73 + seed_offset * 1.7)
		n += sin(pos.x * freq * 2.15 + pos.y * freq * 1.45 + seed_offset) * 0.55
		n += cos(pos.length() * freq * 0.55 + seed_offset * 2.3) * 0.36
		n += sin(pos.x * freq * 3.4 - pos.y * freq * 2.8 + seed_offset * 0.6) * 0.22
		var t := clampf((n + 1.65) / 2.85, 0.0, 1.0)
		t = clampf((t - 0.5) * amplitude + 0.5, 0.0, 1.0)
		if contrast > 0.001 and absf(contrast - 1.0) > 0.001:
			t = pow(t, 1.0 / contrast)
		_heights[i] = t


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
	var portal_pos := _face_centroid_rest(face_variant as Array)
	portal_pos = _leash_position(portal_pos)
	_portal_node.position = portal_pos
	if _portal_node.has_method("queue_redraw"):
		_portal_node.queue_redraw()


func _face_centroid_rest(face: Array) -> Vector2:
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


func _spawn_ascidians(unspace: Dictionary) -> void:
	_clear_ascidians()

	if _inhabitants_cfg.is_empty():
		return

	_visit_rng.seed = int(Time.get_ticks_usec())
	var count_min := maxi(0, int(_inhabitants_cfg.get("count_min", 1)))
	var count_max := maxi(count_min, int(_inhabitants_cfg.get("count_max", 3)))
	var count := _visit_rng.randi_range(count_min, count_max)
	if count <= 0:
		return

	var spawn_data: Dictionary = _dict(unspace.get("spawn", {}))
	var spawn_hint := Vector2(
		float(spawn_data.get("x", -_play_bounds * 0.45)),
		float(spawn_data.get("y", 0.0))
	)
	var portal_pos := get_portal_position()
	var min_spawn_dist := float(_inhabitants_cfg.get("min_spawn_dist", 900.0))
	var wander_fraction := float(_inhabitants_cfg.get("wander_radius_fraction", 0.72))
	var wander_radius := _play_bounds * wander_fraction

	var spawn_cfg := _inhabitants_cfg.duplicate()
	spawn_cfg["play_bounds"] = _play_bounds
	spawn_cfg["wander_radius_fraction"] = wander_fraction

	for _i in range(count):
		var start_pos := _pick_ascidian_spawn(spawn_hint, portal_pos, wander_radius, min_spawn_dist)
		var ascidian: Ascidian = Ascidian.new()
		ascidian.name = "Ascidian_%d" % (_ascidians.size() + 1)
		add_child(ascidian)
		ascidian.configure(self, spawn_cfg, start_pos, _visit_rng)
		_ascidians.append(ascidian)


func _pick_ascidian_spawn(
	spawn_hint: Vector2,
	portal_pos: Vector2,
	wander_radius: float,
	min_spawn_dist: float
) -> Vector2:
	for _attempt in range(24):
		var angle := _visit_rng.randf() * TAU
		var radial := _visit_rng.randf_range(wander_radius * 0.2, wander_radius * 0.88)
		var candidate := Vector2(cos(angle), sin(angle)) * radial
		if candidate.distance_to(spawn_hint) < min_spawn_dist:
			continue
		if portal_pos != Vector2.ZERO and candidate.distance_to(portal_pos) < min_spawn_dist:
			continue
		return candidate

	return Vector2(
		cos(_visit_rng.randf() * TAU),
		sin(_visit_rng.randf() * TAU)
	) * wander_radius * 0.55


func _clear_ascidians() -> void:
	for ascidian_variant in _ascidians:
		if ascidian_variant is Node:
			(ascidian_variant as Node).queue_free()
	_ascidians.clear()


func _barycentric(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := c - a
	var v1 := b - a
	var v2 := point - a
	var dot00 := v0.dot(v0)
	var dot01 := v0.dot(v1)
	var dot02 := v0.dot(v2)
	var dot11 := v1.dot(v1)
	var dot12 := v1.dot(v2)
	var denom := dot00 * dot11 - dot01 * dot01
	if absf(denom) < 0.000001:
		return Vector3(-1.0, -1.0, -1.0)
	var inv_denom := 1.0 / denom
	var v := (dot11 * dot02 - dot01 * dot12) * inv_denom
	var w := (dot00 * dot12 - dot01 * dot02) * inv_denom
	var u := 1.0 - v - w
	return Vector3(u, v, w)


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


func _get_render_size() -> Vector2i:
	var vp := get_viewport()
	if vp != null:
		var size := vp.get_visible_rect().size
		if size.x >= 1.0 and size.y >= 1.0:
			return Vector2i(size)
	var window := DisplayServer.window_get_size()
	if window.x >= 1 and window.y >= 1:
		return window
	return Vector2i(1920, 1080)


func _dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
