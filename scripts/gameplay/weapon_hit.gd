class_name WeaponHit
extends RefCounted


static func apply(collider: Object, delivery_type: String, packets: Dictionary) -> void:
	if collider == null:
		return
	if collider.has_method("take_combat_hit"):
		collider.call("take_combat_hit", delivery_type, packets)
		return
	if collider.has_method("take_weapon_hit"):
		collider.call("take_weapon_hit", ShipCombat.sum_packets(packets))
