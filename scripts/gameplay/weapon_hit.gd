class_name WeaponHit
extends RefCounted


static func apply(collider: Object, damage: float) -> void:
	if collider != null and collider.has_method("take_weapon_hit"):
		collider.call("take_weapon_hit", damage)
