class_name AssembledShip
extends RefCounted

var id: String = ""
var name: String = ""
var maker: String = ""
var chassis: Dictionary = {}
var engine: Dictionary = {}
var armour: Dictionary = {}
var weapons: Array = []
var stats: ShipStats = ShipStats.new()


func get_summary() -> String:
	var parts: PackedStringArray = PackedStringArray([name])

	if not chassis.is_empty():
		parts.append(str(chassis.get("name", "")))

	if not engine.is_empty():
		parts.append(str(engine.get("name", "")))

	if not armour.is_empty():
		parts.append(str(armour.get("name", "")))

	return " · ".join(parts)
