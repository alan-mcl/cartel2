extends StaticBody2D

var _health := DebrisHealth.new()


func take_weapon_hit(damage: float) -> void:
	_health.apply_damage(damage)
	if _health.is_destroyed():
		queue_free()
		return

	var visual := get_node_or_null("Visual") as Sprite2D
	if visual != null:
		var health_ratio := _health.health_ratio()
		visual.modulate = Color(1.0, health_ratio, health_ratio)
