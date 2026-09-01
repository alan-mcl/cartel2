class_name InteractableDef
extends RefCounted

enum Kind { INSPECT, SALVAGE, DOCK, TRANSLATE, ARRIVE }

var id: String = ""
var title: String = ""
var inspect_text: String = ""
var kind: Kind = Kind.INSPECT
var salvage_reward: int = 0
var dock_location_id: String = ""


static func from_dict(data: Dictionary) -> InteractableDef:
	var def := InteractableDef.new()
	def.id = str(data.get("id", ""))
	def.title = str(data.get("title", def.id))
	def.inspect_text = str(data.get("inspect_text", ""))
	def.kind = _parse_kind(str(data.get("kind", "inspect")))
	def.salvage_reward = int(data.get("salvage_reward", 0))
	def.dock_location_id = str(data.get("dock_location_id", ""))
	return def


static func _parse_kind(kind_name: String) -> Kind:
	match kind_name:
		"salvage":
			return Kind.SALVAGE
		"dock":
			return Kind.DOCK
		"translate":
			return Kind.TRANSLATE
		"arrive":
			return Kind.ARRIVE
		_:
			return Kind.INSPECT
