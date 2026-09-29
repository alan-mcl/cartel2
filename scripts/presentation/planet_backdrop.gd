extends Node2D

const PLANET_SHADER := preload("res://shaders/planet_backdrop.gdshader")

const VIEWPORT_SIZE := 1024
const SPHERE_RADIUS := 1.0
const CAMERA_DISTANCE := 3.2

var _viewport: SubViewport
var _planet_root: Node3D
var _material: ShaderMaterial
var _sprite: Sprite2D
var _spin_period: float = 600.0


func configure(planet_data: Dictionary, sector_id: String = "") -> void:
	var diameter := float(planet_data.get("diameter", 2000.0))
	var tint := Color(str(planet_data.get("modulate", "#ffffff")))

	if planet_data.has("rotation_period_seconds"):
		_spin_period = maxf(float(planet_data.get("rotation_period_seconds")), 1.0)
	else:
		var seed_id := sector_id if not sector_id.is_empty() else "planet"
		var hash_value := absi(seed_id.hash())
		_spin_period = lerpf(480.0, 1200.0, float(hash_value % 10000) / 10000.0)

	position = Vector2.ZERO
	z_index = -50
	process_mode = Node.PROCESS_MODE_PAUSABLE

	_build_viewport_scene(planet_data, tint)
	_sprite.scale = Vector2.ONE * (diameter / float(VIEWPORT_SIZE))
	_sprite.modulate = Color.WHITE


func _build_viewport_scene(planet_data: Dictionary, tint: Color) -> void:
	if _viewport != null:
		_viewport.queue_free()
		_viewport = null
	if _sprite != null:
		_sprite.queue_free()
		_sprite = null

	_viewport = SubViewport.new()
	_viewport.name = "PlanetViewport"
	_viewport.size = Vector2i(VIEWPORT_SIZE, VIEWPORT_SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport.disable_3d = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.10, 0.14)
	env.ambient_light_energy = 0.15
	world_env.environment = env
	_viewport.add_child(world_env)

	var scene_root := Node3D.new()
	scene_root.name = "PlanetScene"
	_viewport.add_child(scene_root)

	var camera := Camera3D.new()
	camera.name = "PlanetCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0.0, 0.0, CAMERA_DISTANCE)
	camera.rotation_degrees = Vector3.ZERO
	camera.size = SPHERE_RADIUS * 2.05
	camera.near = 0.05
	camera.far = 100.0
	camera.current = true
	scene_root.add_child(camera)

	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-35.0, 42.0, 0.0)
	sun.light_energy = 0.0
	sun.visible = false
	scene_root.add_child(sun)

	_planet_root = Node3D.new()
	_planet_root.name = "PlanetRoot"
	scene_root.add_child(_planet_root)

	_material = ShaderMaterial.new()
	_material.shader = PLANET_SHADER
	_material.set_shader_parameter("planet_tint", tint)
	_material.set_shader_parameter("use_albedo_map", 0.0)
	_material.set_shader_parameter("use_night_lights", 0.0)
	_apply_optional_textures(planet_data)

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = SPHERE_RADIUS
	sphere_mesh.height = SPHERE_RADIUS * 2.0
	sphere_mesh.radial_segments = 64
	sphere_mesh.rings = 32

	var sphere := MeshInstance3D.new()
	sphere.name = "PlanetSphere"
	sphere.mesh = sphere_mesh
	sphere.material_override = _material
	_planet_root.add_child(sphere)

	_sprite = Sprite2D.new()
	_sprite.name = "PlanetSprite"
	_sprite.centered = true
	_sprite.texture = _viewport.get_texture()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_sprite)


func _apply_optional_textures(planet_data: Dictionary) -> void:
	if _material == null:
		return

	if planet_data.has("albedo"):
		var albedo_path := str(planet_data.get("albedo", ""))
		if not albedo_path.is_empty() and ResourceLoader.exists(albedo_path):
			var albedo_tex := load(albedo_path) as Texture2D
			if albedo_tex != null:
				_material.set_shader_parameter("albedo_map", albedo_tex)
				_material.set_shader_parameter("use_albedo_map", 1.0)

	if planet_data.has("night_lights"):
		var night_path := str(planet_data.get("night_lights", ""))
		if not night_path.is_empty() and ResourceLoader.exists(night_path):
			var night_tex := load(night_path) as Texture2D
			if night_tex != null:
				_material.set_shader_parameter("night_lights", night_tex)
				_material.set_shader_parameter("use_night_lights", 1.0)


func _process(delta: float) -> void:
	if _planet_root == null or _spin_period <= 0.0:
		return
	if get_tree().paused:
		return
	_planet_root.rotation.y += TAU / _spin_period * delta
