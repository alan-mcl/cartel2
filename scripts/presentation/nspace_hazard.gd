extends Area2D
class_name NspaceHazard

var radius: float = 120.0

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _ring: Line2D = $Ring


func _ready() -> void:
	monitoring = false
	monitorable = false


func configure(entity: Dictionary) -> void:
	var pos: Dictionary = entity.get("position", {})
	position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	radius = float(entity.get("radius", 120.0))
	_apply_radius()


func _apply_radius() -> void:
	if _shape != null and _shape.shape is CircleShape2D:
		(_shape.shape as CircleShape2D).radius = radius

	if _ring != null:
		var points := PackedVector2Array()
		var segments := 24
		for i in range(segments + 1):
			var angle := TAU * float(i) / float(segments)
			points.append(Vector2(cos(angle), sin(angle)) * radius)
		_ring.points = points
