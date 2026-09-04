extends Node2D
class_name OrbitalStation


func configure(entity: Dictionary) -> void:
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
