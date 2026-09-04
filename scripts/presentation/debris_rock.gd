extends StaticBody2D

const DEFAULT_HP := 40.0

var _hp: float = DEFAULT_HP


func take_weapon_hit(damage: float) -> void:
	_hp -= damage
	if _hp <= 0.0:
		queue_free()
		return

	var visual := get_node_or_null("Visual") as Sprite2D
	if visual != null:
		var health_ratio := clampf(_hp / DEFAULT_HP, 0.2, 1.0)
		visual.modulate = Color(1.0, health_ratio, health_ratio)
