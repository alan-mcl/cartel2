extends Node2D
class_name NspaceField

const InteractableScene := preload("res://scenes/world/interactable_marker.tscn")
const Ascidian := preload("res://scripts/presentation/ascidian.gd")
const NspaceBackdrop3D := preload("res://scripts/presentation/nspace_backdrop_3d.gd")

var _play_bounds: float = 8000.0
var _rng := RandomNumberGenerator.new()

var _topo: Dictionary = {}
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

var _portal_face_index: int = -1
var _portal_world_pos: Vector2 = Vector2.INF
var _portal_node: Node2D = null
var _interactable: Interactable = null
var _ascidians: Array = []
var _visit_rng := RandomNumberGenerator.new()

var _backdrop_viewport: SubViewport = null
var _backdrop_3d: NspaceBackdrop3D = null
var _height_scale: float = 600.0
var _static_backdrop_built: bool = false


func configure(unspace: Dictionary, catalog: Catalog, session: GameSession, play_bounds: float) -> void:
	_play_bounds = play_bounds
	z_index = -80

	var field_data: Dictionary = unspace.get("field", {})
	_palette = _dict(field_data.get("palette", {}))
	_topo = _dict(field_data.get("topo", {}))
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
	process_priority = -10

	var spawn_data: Dictionary = _dict(unspace.get("spawn", {}))
	var spawn_hint := Vector2(
		float(spawn_data.get("x", -_play_bounds * 0.45)),
		float(spawn_data.get("y", 0.0))
	)

	_build_scatter_mesh()
	_build_edge_catalog()
	_pick_portal_face(spawn_hint)

	_setup_backdrop_3d()
	_setup_portal(catalog, session)
	_spawn_ascidians(unspace)
	_update_backdrop(0.0)


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
		var poly := PackedVector2Array()
		for index_variant in face:
			var index := int(index_variant)
			if index < 0 or index >= _animated.size():
				continue
			poly.append(_animated[index])
		if poly.size() < 3:
			continue
		if not Geometry2D.is_point_in_polygon(local_pos, poly):
			continue
		if face.size() == 3:
			var i0 := int(face[0])
			var i1 := int(face[1])
			var i2 := int(face[2])
			var bary := _barycentric(local_pos, _animated[i0], _animated[i1], _animated[i2])
			if bary.x < -0.001 or bary.y < -0.001 or bary.z < -0.001:
				continue
			return _heights[i0] * bary.x + _heights[i1] * bary.y + _heights[i2] * bary.z
		var total := 0.0
		for index_variant in face:
			total += _heights[int(index_variant)]
		return total / float(face.size())

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
	if _portal_world_pos != Vector2.INF:
		return _portal_world_pos
	if _portal_node != null:
		return _portal_node.global_position
	return Vector2.ZERO


func get_portal_node() -> Node2D:
	return _portal_node


func get_portal_face_index() -> int:
	return _portal_face_index


func get_portal_host_height() -> float:
	if _portal_face_index < 0:
		return 0.5
	return _face_avg_height(_portal_face_index)


func get_portal_visual_radius() -> float:
	return float(_portal_config.get("interact_radius", 220.0)) * 0.5


func get_mid_vertex_height() -> float:
	if _heights.is_empty():
		return 0.5
	var min_h := _heights[0]
	var max_h := _heights[0]
	for i in range(1, _heights.size()):
		min_h = minf(min_h, _heights[i])
		max_h = maxf(max_h, _heights[i])
	return (min_h + max_h) * 0.5


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


func get_height_scale() -> float:
	return _height_scale


func get_palette_color(key: String, fallback: Color) -> Color:
	return _color(key, fallback)


func get_face_fill_color(face_index: int) -> Color:
	var peak := _color("peak", Color(0.49, 0.91, 1.0, 0.90))
	var trough := _color("trough", Color(0.10, 0.05, 0.23, 0.92))
	var shallow := _color("shallow", Color(0.14, 0.12, 0.42, 0.92))
	var bright := _color("bright", Color(0.62, 0.98, 1.0, 0.94))
	var portal_host := _color("portal_host", Color(0.95, 0.55, 0.25, 0.45))
	return _compute_face_fill(face_index, peak, trough, shallow, bright, portal_host)


func _physics_process(delta: float) -> void:
	_update_backdrop(delta)


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
	# Vertices already map 2D y → 3D -y; viewport pixels are y-down like the canvas — no second flip.
	draw_set_transform_matrix(Transform2D(Vector2(scale.x, 0.0), Vector2(0.0, scale.y), center))
	draw_texture_rect(tex, Rect2(-tex_size * 0.5, tex_size), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _update_backdrop(delta: float) -> void:
	if _backdrop_3d == null or _backdrop_viewport == null:
		return

	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return

	var vp_size := _get_render_size()
	if _backdrop_viewport.size != vp_size:
		_backdrop_viewport.size = vp_size

	_backdrop_3d.sync_camera_from_2d(camera, Vector2(vp_size), camera.get_screen_center_position())
	if not _static_backdrop_built:
		_backdrop_3d.rebuild_static()
		_static_backdrop_built = true
	_backdrop_3d.update_ascidians(delta)
	queue_redraw()


func _compute_scatter_radius() -> float:
	var fov_half := _compute_fov_half_diagonal(null)
	var margin := float(_topo.get("scatter_margin", 1.6))
	return _play_bounds + fov_half * margin


func _compute_fov_half_diagonal(camera: Camera2D) -> float:
	var vp_size := Vector2(_get_render_size())
	var zoom := Vector2(0.72, 0.72)
	if camera != null:
		zoom = camera.zoom
	var half_w := vp_size.x / maxf(zoom.x, 0.001) * 0.5
	var half_h := vp_size.y / maxf(zoom.y, 0.001) * 0.5
	return sqrt(half_w * half_w + half_h * half_h)


func _compute_scatter_target_count() -> int:
	var scatter_radius := _compute_scatter_radius()
	var vp_size := Vector2(_get_render_size())
	var zoom := Vector2(0.72, 0.72)
	var visible_area := (vp_size.x / zoom.x) * (vp_size.y / zoom.y)
	var fov_count := maxi(8, int(_topo.get("fov_vertex_count", 50)))
	var min_dist := sqrt(visible_area / float(fov_count)) * 0.92
	var target_count := int(PI * scatter_radius * scatter_radius / (min_dist * min_dist))
	return clampi(target_count, 120, 6000)


func _build_scatter_mesh() -> void:
	_rest.clear()
	_faces.clear()

	var scatter_radius := _compute_scatter_radius()
	var target_count := _compute_scatter_target_count()

	for _i in range(target_count):
		var angle := _rng.randf() * TAU
		var radial := sqrt(_rng.randf()) * scatter_radius
		_rest.append(Vector2(cos(angle), sin(angle)) * radial)

	_heights.resize(_rest.size())
	for i in range(_rest.size()):
		_heights[i] = _rng.randf()

	_build_delaunay_faces()
	_maybe_merge_quads()
	_animated = _rest.duplicate()


func _build_delaunay_faces() -> void:
	_faces.clear()
	if _rest.size() < 3:
		return

	var indices := Geometry2D.triangulate_delaunay(_rest)
	if indices.is_empty():
		return

	for i in range(0, indices.size(), 3):
		_faces.append([int(indices[i]), int(indices[i + 1]), int(indices[i + 2])])


func _maybe_merge_quads() -> void:
	var merge_chance := float(_topo.get("quad_merge_chance", 0.18))
	if merge_chance <= 0.001:
		return

	var edge_to_tris: Dictionary = {}
	for tri_index in range(_faces.size()):
		var face_variant = _faces[tri_index]
		if typeof(face_variant) != TYPE_ARRAY:
			continue
		var face: Array = face_variant
		if face.size() != 3:
			continue
		for edge_key in _triangle_edge_keys(face):
			if not edge_to_tris.has(edge_key):
				edge_to_tris[edge_key] = []
			edge_to_tris[edge_key].append(tri_index)

	var consumed: Dictionary = {}
	var merged_faces: Array = []

	for edge_key in edge_to_tris.keys():
		var tri_list: Array = edge_to_tris[edge_key]
		if tri_list.size() != 2:
			continue
		if _rng.randf() > merge_chance:
			continue

		var tri_a := int(tri_list[0])
		var tri_b := int(tri_list[1])
		if consumed.has(tri_a) or consumed.has(tri_b):
			continue

		var quad := _merge_triangle_pair(tri_a, tri_b, edge_key)
		if quad.is_empty():
			continue

		consumed[tri_a] = true
		consumed[tri_b] = true
		merged_faces.append(quad)

	var remaining: Array = []
	for tri_index in range(_faces.size()):
		if consumed.has(tri_index):
			continue
		remaining.append(_faces[tri_index])

	_faces = remaining + merged_faces


func _triangle_edge_keys(face: Array) -> Array:
	var keys: Array = []
	for i in range(face.size()):
		var v0 := int(face[i])
		var v1 := int(face[(i + 1) % face.size()])
		keys.append(_edge_key(v0, v1))
	return keys


func _edge_key(v0: int, v1: int) -> int:
	var lo := mini(v0, v1)
	var hi := maxi(v0, v1)
	return (lo << 16) | hi


func _merge_triangle_pair(tri_a: int, tri_b: int, shared_edge_key: int) -> Array:
	var face_a: Array = _faces[tri_a]
	var face_b: Array = _faces[tri_b]
	if face_a.size() != 3 or face_b.size() != 3:
		return []

	var shared_a := shared_edge_key >> 16
	var shared_b := shared_edge_key & 0xFFFF

	var opposite_a := -1
	for index_variant in face_a:
		var index := int(index_variant)
		if index != shared_a and index != shared_b:
			opposite_a = index
			break
	var opposite_b := -1
	for index_variant in face_b:
		var index := int(index_variant)
		if index != shared_a and index != shared_b:
			opposite_b = index
			break
	if opposite_a < 0 or opposite_b < 0:
		return []

	var quad := [opposite_a, shared_a, opposite_b, shared_b]
	if not _is_convex_quad(quad):
		quad = [opposite_a, shared_b, opposite_b, shared_a]
		if not _is_convex_quad(quad):
			return []

	return quad


func _is_convex_quad(indices: Array) -> bool:
	if indices.size() != 4:
		return false

	var points: Array = []
	for index_variant in indices:
		var index := int(index_variant)
		if index < 0 or index >= _rest.size():
			return false
		points.append(_rest[index])

	var sign := 0.0
	for i in range(4):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % 4]
		var c: Vector2 = points[(i + 2) % 4]
		var cross := (b - a).cross(c - b)
		if absf(cross) < 0.001:
			continue
		if sign == 0.0:
			sign = cross
		elif sign * cross < 0.0:
			return false
	return true


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
			var key := _edge_key(v0, v1)
			if seen.has(key):
				continue
			seen[key] = true
			_edges.append({"v0": v0, "v1": v1, "key": key})


func _pick_portal_face(spawn_hint: Vector2) -> void:
	_portal_face_index = -1
	_portal_world_pos = Vector2.INF
	if _faces.is_empty():
		return

	var best_score := -INF
	for face_index in range(_faces.size()):
		var centroid := _face_centroid(face_index)
		var dist_origin := centroid.length()
		if dist_origin < _play_bounds * 0.25 or dist_origin > _play_bounds * 0.78:
			continue
		if centroid.distance_to(spawn_hint) < _play_bounds * 0.35:
			continue
		var score := dist_origin + centroid.distance_to(spawn_hint) * 0.35
		if score > best_score:
			best_score = score
			_portal_face_index = face_index

	if _portal_face_index < 0:
		_portal_face_index = 0

	_portal_world_pos = _face_centroid(_portal_face_index)


func _face_centroid(face_index: int) -> Vector2:
	if face_index < 0 or face_index >= _faces.size():
		return Vector2.ZERO

	var face_variant = _faces[face_index]
	if typeof(face_variant) != TYPE_ARRAY:
		return Vector2.ZERO
	var face: Array = face_variant
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


func _face_avg_height(face_index: int) -> float:
	if face_index < 0 or face_index >= _faces.size():
		return 0.5

	var face_variant = _faces[face_index]
	if typeof(face_variant) != TYPE_ARRAY:
		return 0.5
	var face: Array = face_variant
	var total := 0.0
	var count := 0
	for index_variant in face:
		var index := int(index_variant)
		if index < 0 or index >= _heights.size():
			continue
		total += _heights[index]
		count += 1
	if count == 0:
		return 0.5
	return total / float(count)


func _face_contains_point(point: Vector2, face_index: int) -> bool:
	if face_index < 0 or face_index >= _faces.size():
		return false

	var face_variant = _faces[face_index]
	if typeof(face_variant) != TYPE_ARRAY:
		return false
	var face: Array = face_variant
	if face.size() < 3:
		return false

	var poly := PackedVector2Array()
	for index_variant in face:
		var index := int(index_variant)
		if index < 0 or index >= _animated.size():
			continue
		poly.append(_animated[index])
	if poly.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(point, poly)


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

	var h := _face_avg_height(face_index)
	var centroid := _face_centroid(face_index)
	var angle := atan2(centroid.y, centroid.x)
	var blue_shift := sin(angle * 1.8 + _seed_phase) * 0.5 + 0.5
	var low := trough.lerp(shallow, blue_shift * 0.35)
	var high := peak.lerp(bright, blue_shift * 0.25)
	var fill := low.lerp(high, h)
	fill = fill.lerp(fill.lightened(0.12), 0.55)
	fill.a = 1.0
	if face_index == _portal_face_index:
		fill = fill.lerp(portal_host, 0.35)

	return fill


func _setup_portal(catalog: Catalog, _session: GameSession) -> void:
	_portal_node = Node2D.new()
	_portal_node.name = "ExitPortal"
	_portal_node.z_index = 10
	_portal_node.position = _portal_world_pos
	_portal_node.visible = false
	add_child(_portal_node)

	var interactable_root: Area2D = InteractableScene.instantiate()
	interactable_root.name = "Interactable"
	_portal_node.add_child(interactable_root)

	var collision := interactable_root.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null and collision.shape is CircleShape2D:
		(collision.shape as CircleShape2D).radius = float(_portal_config.get("interact_radius", 220.0))

	if interactable_root is Interactable:
		_interactable = interactable_root
		var interactable_id := str(_portal_config.get("interactable", "unspace_exit"))
		var data := catalog.get_interactable(interactable_id)
		if not data.is_empty():
			_interactable.definition = InteractableDef.from_dict(data)
			_interactable.visible = true


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
	var mid_height := get_mid_vertex_height()

	var spawn_cfg := _inhabitants_cfg.duplicate()
	spawn_cfg["play_bounds"] = _play_bounds
	spawn_cfg["wander_radius_fraction"] = wander_fraction
	spawn_cfg["fixed_swim_depth"] = mid_height

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
