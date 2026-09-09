extends Node3D
class_name NspaceBackdrop3D

const Ascidian := preload("res://scripts/presentation/ascidian.gd")
const NspaceField := preload("res://scripts/presentation/nspace_field.gd")

var _field: NspaceField = null
var _height_scale: float = 600.0
var _camera_z: float = 2500.0

var _camera: Camera3D
var _topo_mesh_instance: MeshInstance3D
var _edge_mesh_instance: MeshInstance3D
var _ascidian_root: Node3D
var _ascidian_instances: Array = []

var _topo_material: StandardMaterial3D
var _edge_material: StandardMaterial3D
var _ascidian_material: StandardMaterial3D


func configure(field: NspaceField, height_scale: float) -> void:
	_field = field
	_height_scale = height_scale
	_setup_camera()
	_setup_materials()
	_setup_mesh_instances()


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "BackdropCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 10.0
	_camera.far = 8000.0
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.current = true
	add_child(_camera)


func _setup_materials() -> void:
	_topo_material = StandardMaterial3D.new()
	_topo_material.vertex_color_use_as_albedo = true
	_topo_material.albedo_color = Color.WHITE
	_topo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_topo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_topo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_edge_material = StandardMaterial3D.new()
	_edge_material.vertex_color_use_as_albedo = true
	_edge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_ascidian_material = StandardMaterial3D.new()
	_ascidian_material.vertex_color_use_as_albedo = true
	_ascidian_material.albedo_color = Color.WHITE
	_ascidian_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ascidian_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ascidian_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _setup_mesh_instances() -> void:
	_topo_mesh_instance = MeshInstance3D.new()
	_topo_mesh_instance.name = "TopoMesh"
	_topo_mesh_instance.material_override = _topo_material
	add_child(_topo_mesh_instance)

	_edge_mesh_instance = MeshInstance3D.new()
	_edge_mesh_instance.name = "EdgeMesh"
	_edge_mesh_instance.material_override = _edge_material
	add_child(_edge_mesh_instance)

	_ascidian_root = Node3D.new()
	_ascidian_root.name = "Ascidians"
	add_child(_ascidian_root)


func sync_camera_from_2d(camera: Camera2D, viewport_size: Vector2) -> void:
	if _camera == null or camera == null:
		return

	var center := camera.get_screen_center_position()
	# Default Camera3D orientation looks down world -Z; keep identity rotation so
	# 2D world XY maps to 3D XY (with Y flipped at vertex mapping time).
	_camera.position = Vector3(center.x, -center.y, _camera_z)
	_camera.basis = Basis.IDENTITY

	var visible_height := viewport_size.y / maxf(camera.zoom.y, 0.001)
	_camera.size = visible_height * 0.5


func rebuild() -> void:
	if _field == null:
		return

	_topo_mesh_instance.mesh = _build_topo_mesh()
	_edge_mesh_instance.mesh = _build_edge_mesh()
	_rebuild_ascidians()


func _build_topo_mesh() -> ArrayMesh:
	var animated: PackedVector2Array = _field.get_animated_vertices()
	var heights: PackedFloat32Array = _field.get_heights()
	var faces: Array = _field.get_faces()

	if animated.is_empty() or faces.is_empty():
		return ArrayMesh.new()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for face_index in range(faces.size()):
		var face_variant = faces[face_index]
		if typeof(face_variant) != TYPE_ARRAY:
			continue
		var face: Array = face_variant
		if face.size() < 3:
			continue

		var i0 := int(face[0])
		var i1 := int(face[1])
		var i2 := int(face[2])
		if i0 >= animated.size() or i1 >= animated.size() or i2 >= animated.size():
			continue

		var p0 := _map_vertex(animated[i0], heights[i0])
		var p1 := _map_vertex(animated[i1], heights[i1])
		var p2 := _map_vertex(animated[i2], heights[i2])

		if p0.is_equal_approx(p1) or p1.is_equal_approx(p2) or p2.is_equal_approx(p0):
			continue

		var fill: Color = _field.get_face_fill_color(face_index)
		fill.a = maxf(fill.a, 0.92)

		for vertex in [p0, p1, p2]:
			st.set_color(fill)
			st.add_vertex(vertex)

	st.generate_normals()
	return st.commit()


func _build_edge_mesh() -> ArrayMesh:
	var animated: PackedVector2Array = _field.get_animated_vertices()
	var heights: PackedFloat32Array = _field.get_heights()
	var edges: Array = _field.get_edges()

	if animated.is_empty() or edges.is_empty():
		return ArrayMesh.new()

	var edge_base: Color = _field.get_palette_color("edge", Color(0.35, 0.72, 0.92, 0.82))
	var ridge: Color = _field.get_palette_color("ridge", Color(0.72, 0.96, 1.0, 0.95))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for edge in edges:
		var v0: int = edge.get("v0", 0)
		var v1: int = edge.get("v1", 0)
		if v0 >= animated.size() or v1 >= animated.size():
			continue

		var p0 := _map_vertex(animated[v0], heights[v0])
		var p1 := _map_vertex(animated[v1], heights[v1])
		var height_delta := absf(heights[v0] - heights[v1])
		var edge_col := edge_base.lerp(ridge, clampf(height_delta * 1.8, 0.0, 1.0))
		var width := lerpf(2.0, 5.0, clampf(height_delta * 2.5, 0.0, 1.0))

		_add_edge_quad(st, p0, p1, width, edge_col)

	return st.commit()


func _add_edge_quad(st: SurfaceTool, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var dir := (b - a)
	if dir.length_squared() < 0.001:
		return
	dir = dir.normalized()
	var side := dir.cross(Vector3(0.0, 0.0, 1.0)).normalized()
	if side.length_squared() < 0.001:
		side = Vector3(0.0, 1.0, 0.0)
	var half := side * width * 0.5

	var v0 := a - half
	var v1 := a + half
	var v2 := b + half
	var v3 := b - half
	var normal := Vector3(0.0, 0.0, 1.0)

	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(v0)
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(v1)
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(v2)

	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(v0)
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(v2)
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(v3)


func _rebuild_ascidians() -> void:
	var ascidians: Array = _field.get_ascidians()

	while _ascidian_instances.size() > ascidians.size():
		var extra: MeshInstance3D = _ascidian_instances.pop_back()
		extra.queue_free()

	while _ascidian_instances.size() < ascidians.size():
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.material_override = _ascidian_material
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_inst.sorting_offset = 2.0
		_ascidian_root.add_child(mesh_inst)
		_ascidian_instances.append(mesh_inst)

	for index in range(ascidians.size()):
		var ascidian_variant = ascidians[index]
		if not ascidian_variant is Ascidian:
			continue
		var ascidian: Ascidian = ascidian_variant
		var mesh_inst: MeshInstance3D = _ascidian_instances[index]
		mesh_inst.mesh = _build_ascidian_mesh(ascidian)
		var swim := ascidian.get_swim_depth()
		var terrain_h := _field.sample_height(ascidian.global_position)
		var depth := swim * _height_scale
		if swim >= terrain_h - 0.05:
			depth += _field.get_ascidian_depth_bias()
		var pos := ascidian.position
		mesh_inst.position = Vector3(pos.x, -pos.y, depth)
		mesh_inst.visible = true


func _build_ascidian_mesh(ascidian: Ascidian) -> ArrayMesh:
	var outline := ascidian.build_outline()
	if outline.size() < 3:
		return ArrayMesh.new()

	var warm_body := ascidian.get_body_color()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var aura_col := warm_body.lightened(0.28)
	aura_col.a = 0.20
	var aura_outline := PackedVector2Array()
	for point in outline:
		aura_outline.append(point * 1.38)
	_add_polygon_fan(st, aura_outline, aura_col)

	var membrane_col := warm_body
	membrane_col.a = 0.58
	_add_polygon_fan(st, outline, membrane_col)

	var sheen_col := warm_body.lightened(0.35)
	sheen_col.a = 0.28
	var sheen_outline := PackedVector2Array()
	for point in outline:
		sheen_outline.append(point * 0.82)
	_add_polygon_fan(st, sheen_outline, sheen_col)

	var core_col := warm_body.lightened(0.22)
	core_col.a = 0.68
	_add_circle_fan(st, Vector2.ZERO, ascidian.get_radius() * 0.34, core_col, 16)

	var heart_col := warm_body.lightened(0.42)
	heart_col.a = 0.82
	var pulse := sin(ascidian.get_render_time() * ascidian.get_pulse_speed() * 1.35 + ascidian.get_phase_offset()) * 0.5 + 0.5
	var heart_r := ascidian.get_radius() * lerpf(0.12, 0.20, pulse)
	_add_circle_fan(st, Vector2.ZERO, heart_r, heart_col, 12)

	return st.commit()


func _add_polygon_fan(st: SurfaceTool, points: PackedVector2Array, color: Color, normal: Vector3 = Vector3(0, 0, 1)) -> void:
	if points.size() < 3:
		return
	var center := Vector2.ZERO
	for point in points:
		center += point
	center /= float(points.size())

	var center_3d := Vector3(center.x, -center.y, 0.0)
	for i in range(points.size()):
		var a := Vector3(points[i].x, -points[i].y, 0.0)
		var b := Vector3(points[(i + 1) % points.size()].x, -points[(i + 1) % points.size()].y, 0.0)
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(center_3d)
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(a)
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(b)


func _add_circle_fan(st: SurfaceTool, center: Vector2, radius: float, color: Color, segments: int) -> void:
	if radius <= 0.001:
		return
	var center_3d := Vector3(center.x, -center.y, 0.0)
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := center + Vector2.from_angle(a0) * radius
		var p1 := center + Vector2.from_angle(a1) * radius
		st.set_normal(Vector3(0, 0, 1))
		st.set_color(color)
		st.add_vertex(center_3d)
		st.set_normal(Vector3(0, 0, 1))
		st.set_color(color)
		st.add_vertex(Vector3(p0.x, -p0.y, 0.0))
		st.set_normal(Vector3(0, 0, 1))
		st.set_color(color)
		st.add_vertex(Vector3(p1.x, -p1.y, 0.0))


func _map_vertex(pos: Vector2, height: float) -> Vector3:
	return Vector3(pos.x, -pos.y, height * _height_scale)
