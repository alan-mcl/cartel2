class_name MockCombatTarget
extends RefCounted

var destroy_on_hit: bool = true
var hit_count: int = 0


func take_combat_hit(_delivery_type: String, _packets: Dictionary) -> Dictionary:
	hit_count += 1
	if destroy_on_hit and hit_count == 1:
		return {"destroyed": true, "hull_damage": 1.0, "intercepted": false}
	return {"intercepted": false, "hull_damage": 0.0}
