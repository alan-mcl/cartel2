extends StaticBody2D

const AsteroidViewScript := preload("res://scripts/presentation/asteroid_view.gd")

var _health := DebrisHealth.new()
var _entity_id: String = ""
var _asteroid: Node2D


func configure(entity: Dictionary) -> void:
	_entity_id = str(entity.get("id", ""))
	var pos: Dictionary = entity.get("position", {})
	position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	if entity.has("rotation"):
		rotation = float(entity.get("rotation", 0.0))
	if entity.has("scale"):
		var scale_data: Dictionary = entity.get("scale", {})
		scale = Vector2(float(scale_data.get("x", 1.0)), float(scale_data.get("y", 1.0)))
	_configure_asteroid_visual()


func _configure_asteroid_visual() -> void:
	_ensure_asteroid()
	if _asteroid == null:
		return
	var seed_val := AsteroidShape.entity_render_seed(_entity_id)
	var composition := AsteroidShape.composition_for_seed(seed_val)
	_asteroid.configure(seed_val, composition, AsteroidShape.DEBRIS_WORLD_SIZE)
	var ratio := _health.health_ratio()
	_asteroid.set_visual_modulate(Color(1.0, ratio, ratio))


func _ensure_asteroid() -> void:
	var existing := get_node_or_null("Asteroid")
	if existing is Node2D:
		_asteroid = existing as Node2D
		return
	_asteroid = AsteroidViewScript.new()
	_asteroid.name = "Asteroid"
	add_child(_asteroid)


func entity_id() -> String:
	return _entity_id


func render_seed() -> int:
	return AsteroidShape.entity_render_seed(_entity_id)


func apply_star_light(star_world_position: Vector2, irradiance: float = 1.0) -> void:
	_ensure_asteroid()
	if _asteroid != null and _asteroid.has_method("set_sun_from_star_position"):
		_asteroid.call("set_sun_from_star_position", star_world_position, maxf(irradiance, 0.0))


func health_ratio() -> float:
	return _health.health_ratio()


func take_weapon_hit(damage: float) -> void:
	_health.apply_damage(damage)
	if _health.is_destroyed():
		queue_free()
		return
	if _asteroid != null and is_instance_valid(_asteroid):
		var health_ratio := _health.health_ratio()
		_asteroid.set_visual_modulate(Color(1.0, health_ratio, health_ratio))
