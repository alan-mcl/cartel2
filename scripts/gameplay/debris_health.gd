class_name DebrisHealth
extends RefCounted

const DEFAULT_HP := 40.0

var _hp: float = DEFAULT_HP


func apply_damage(damage: float) -> void:
	if damage <= 0.0:
		return
	_hp = maxf(_hp - damage, 0.0)


func is_destroyed() -> bool:
	return _hp <= 0.0


func health_ratio() -> float:
	return clampf(_hp / DEFAULT_HP, 0.2, 1.0)
