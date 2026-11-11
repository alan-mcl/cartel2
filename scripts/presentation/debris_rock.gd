extends StaticBody2D

var _health := DebrisHealth.new()
var _entity_id: String = ""


func configure(entity: Dictionary) -> void:
	_entity_id = str(entity.get("id", ""))
	var pos: Dictionary = entity.get("position", {})
	position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	if entity.has("rotation"):
		rotation = float(entity.get("rotation", 0.0))
	if entity.has("scale"):
		var scale_data: Dictionary = entity.get("scale", {})
		scale = Vector2(float(scale_data.get("x", 1.0)), float(scale_data.get("y", 1.0)))
	var visual: Sprite2D = get_node_or_null("Visual")
	var sprite_path := str(entity.get("sprite", ""))
	if visual != null and not sprite_path.is_empty():
		var texture := load(sprite_path) as Texture2D
		if texture != null:
			visual.texture = texture


func entity_id() -> String:
	return _entity_id


func health_ratio() -> float:
	return _health.health_ratio()


func take_weapon_hit(damage: float) -> void:
	_health.apply_damage(damage)
	if _health.is_destroyed():
		queue_free()
		return

	var visual := get_node_or_null("Visual") as Sprite2D
	if visual != null:
		var health_ratio := _health.health_ratio()
		visual.modulate = Color(1.0, health_ratio, health_ratio)
