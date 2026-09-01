extends Area2D
class_name NspaceHazard

var radius: float = 120.0
var shear_strength: float = 520.0
var hull_stress: float = 2.0

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _ring: Line2D = $Ring


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	monitoring = true
	monitorable = false


func configure(entity: Dictionary) -> void:
	var pos: Dictionary = entity.get("position", {})
	position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	radius = float(entity.get("radius", 120.0))
	shear_strength = float(entity.get("shear_strength", 520.0))
	hull_stress = float(entity.get("hull_stress", 2.0))
	_apply_radius()


func get_shear_strength() -> float:
	return shear_strength


func get_hull_stress() -> float:
	return hull_stress


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


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("enter_shear"):
		body.enter_shear(self)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("exit_shear"):
		body.exit_shear(self)
