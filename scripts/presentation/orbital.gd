extends Node2D
class_name OrbitalStation

var _spin_period: float = 0.0


func configure(entity: Dictionary) -> void:
	var entity_id := str(entity.get("id", name))
	_init_axial_spin(entity_id)

	var visual: Sprite2D = get_node_or_null("Visual")
	var sprite_path := str(entity.get("sprite", ""))
	if visual != null and not sprite_path.is_empty():
		var texture := load(sprite_path) as Texture2D
		if texture != null:
			visual.texture = texture
		else:
			push_error("Failed to load orbital sprite: %s" % sprite_path)

	if visual != null and entity.has("modulate"):
		visual.modulate = Color(str(entity.get("modulate")))

	if entity.has("scale"):
		var scale_data: Dictionary = entity.get("scale", {})
		scale = Vector2(float(scale_data.get("x", 1.0)), float(scale_data.get("y", 1.0)))


func _init_axial_spin(seed_id: String) -> void:
	var hash_value := absi(seed_id.hash())
	_spin_period = lerpf(180.0, 480.0, float(hash_value % 10000) / 10000.0)


func _process(delta: float) -> void:
	if _spin_period <= 0.0 or get_tree().paused:
		return
	rotation += TAU / _spin_period * delta
