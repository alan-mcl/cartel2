extends Node2D
class_name WorldObject

var entity_id: String = ""
var interactable_id: String = ""

@onready var _label: Label = get_node_or_null("Label")
@onready var _visual: Sprite2D = get_node_or_null("Visual")
@onready var _interactable: Interactable = get_node_or_null("Interactable")


func configure(entity: Dictionary, catalog: Catalog, session: GameSession) -> void:
	entity_id = str(entity.get("id", ""))
	if entity.has("position"):
		var pos: Dictionary = entity.get("position", {})
		position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))

	if entity.has("rotation"):
		rotation = float(entity.get("rotation", 0.0))

	if entity.has("scale"):
		var scale_data: Dictionary = entity.get("scale", {})
		scale = Vector2(float(scale_data.get("x", 1.0)), float(scale_data.get("y", 1.0)))

	var label: Label = get_node_or_null("Label")
	var visual: Sprite2D = get_node_or_null("Visual")

	var label_text := str(entity.get("label", ""))
	if label != null and not label_text.is_empty():
		label.text = label_text

	var sprite_path := str(entity.get("sprite", ""))
	if visual != null and not sprite_path.is_empty():
		var texture := load(sprite_path) as Texture2D
		if texture != null:
			visual.texture = texture

	if visual != null and entity.has("modulate"):
		visual.modulate = Color(str(entity.get("modulate")))

	interactable_id = str(entity.get("interactable", ""))
	var interactable: Interactable = get_node_or_null("Interactable")
	if interactable == null:
		return

	if interactable_id.is_empty():
		interactable.visible = false
		return

	var data := catalog.get_interactable(interactable_id)
	if data.is_empty():
		interactable.visible = false
		return

	interactable.definition = InteractableDef.from_dict(data)
	interactable.visible = true
	apply_salvage_state(session)


func apply_salvage_state(session: GameSession) -> void:
	if interactable_id.is_empty() or session == null:
		return

	var interactable: Interactable = get_node_or_null("Interactable")
	if interactable == null:
		return

	if session.is_salvaged(interactable_id):
		interactable.mark_consumed()
		var visual: Sprite2D = get_node_or_null("Visual")
		if visual != null:
			visual.modulate = Color(0.45, 0.45, 0.45, 0.6)
