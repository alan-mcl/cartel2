extends Area2D

const BallisticHitScript := preload("res://scripts/presentation/ballistic_hit.gd")

var _spent: bool = false
var _entity_id: String = ""
var _delivery: String = "ballistic"
var _packets: Dictionary = {}
var _trigger_radius: float = 180.0


func configure(entity: Dictionary) -> void:
	_entity_id = str(entity.get("id", ""))
	var pos: Dictionary = entity.get("position", {})
	position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	if entity.has("rotation"):
		rotation = float(entity.get("rotation", 0.0))
	_trigger_radius = float(entity.get("radius", 180.0))
	_delivery = str(entity.get("delivery", "ballistic"))
	var packets: Variant = entity.get("packets", {})
	if typeof(packets) == TYPE_DICTIONARY:
		_packets = (packets as Dictionary).duplicate(true)
	else:
		var damage := float(entity.get("damage", 25.0))
		_packets = {"kinetic": damage}

	var shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape_node != null and shape_node.shape is CircleShape2D:
		(shape_node.shape as CircleShape2D).radius = _trigger_radius


func entity_id() -> String:
	return _entity_id


func take_weapon_hit(_damage: float) -> void:
	_detonate(null)


func _physics_process(_delta: float) -> void:
	if _spent:
		return
	for body_index in range(get_overlapping_bodies().size()):
		var body: Node = get_overlapping_bodies()[body_index]
		if body == null:
			continue
		if body.is_in_group("player") or body.is_in_group("npc_ship"):
			_detonate(body)
			return


func _detonate(target: Variant) -> void:
	if _spent:
		return
	_spent = true
	if target != null:
		BallisticHitScript.apply(
			target,
			_delivery,
			_packets.duplicate(true),
			null,
			Vector2.ZERO,
			null
		)
	queue_free()
