class_name OwnedShip
extends RefCounted

var id: String = ""
var name: String = ""
var template_id: String = ""
var chassis_id: String = ""
var engine_id: String = ""
var armour_id: String = ""
var location: String = "aboard"


static func from_dict(data: Dictionary) -> OwnedShip:
	var ship := OwnedShip.new()
	ship.id = str(data.get("id", ""))
	ship.name = str(data.get("name", ship.id))
	ship.template_id = str(data.get("template_id", ""))
	ship.chassis_id = str(data.get("chassis_id", ""))
	ship.engine_id = str(data.get("engine_id", ""))

	var armour: Variant = data.get("armour_id")
	if armour == null or str(armour) == "null":
		ship.armour_id = ""
	else:
		ship.armour_id = str(armour)

	ship.location = str(data.get("location", "aboard"))
	return ship


func to_dict() -> Dictionary:
	var data := {
		"id": id,
		"name": name,
		"template_id": template_id,
		"chassis_id": chassis_id,
		"engine_id": engine_id,
		"location": location,
	}
	if armour_id.is_empty():
		data["armour_id"] = null
	else:
		data["armour_id"] = armour_id
	return data
