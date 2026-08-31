extends Node2D
class_name WorldObject

var entity_id: String = ""
var interactable_id: String = ""

@onready var _label: Label = get_node_or_null("Label")
@onready var _visual: Sprite2D = get_node_or_null("Visual")
@onready var _interactable: Interactable = get_node_or_null("Interactable")


func configure(entity: Dictionary, catalog: Catalog, session: PrototypeSession) -> void:
	entity_id = str(entity.get("id", ""))
	var pos: Dictionary = entity.get("position", {})
	position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))

	if entity.has("rotation"):
		rotation = float(entity.get("rotation", 0.0))

	if entity.has("scale"):
		var scale_data: Dictionary = entity.get("scale", {})
		scale = Vector2(float(scale_data.get("x", 1.0)), float(scale_data.get("y", 1.0)))

	var label_text := str(entity.get("label", ""))
	if _label != null and not label_text.is_empty():
		_label.text = label_text

	var sprite_path := str(entity.get("sprite", ""))
	if _visual != null and not sprite_path.is_empty():
		var texture := load(sprite_path) as Texture2D
		if texture != null:
			_visual.texture = texture

	if _visual != null and entity.has("modulate"):
		_visual.modulate = Color(str(entity.get("modulate")))

	interactable_id = str(entity.get("interactable", ""))
	if _interactable == null:
		return

	if interactable_id.is_empty():
		_interactable.visible = false
		return

	var data := catalog.get_interactable(interactable_id)
	if data.is_empty():
		_interactable.visible = false
		return

	_interactable.definition = InteractableDef.from_dict(data)
	_interactable.visible = true
	apply_salvage_state(session)


func apply_salvage_state(session: PrototypeSession) -> void:
	if interactable_id.is_empty() or _interactable == null or session == null:
		return

	if session.is_salvaged(interactable_id):
		_interactable.mark_consumed()
		if _visual != null:
			_visual.modulate = Color(0.45, 0.45, 0.45, 0.6)
