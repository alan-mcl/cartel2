extends Node2D
class_name OrbitalRing

var period_seconds: float = 720.0
var sector_id: String = ""
var session: GameSession = null


func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	if session == null or session.docked or session.in_unspace:
		return

	rotation = session.get_orbital_phase(sector_id)
	_update_label_counter_rotation()


func _update_label_counter_rotation() -> void:
	for child in get_children():
		var label: Label = child.get_node_or_null("Label")
		if label != null:
			label.rotation = -(rotation + child.rotation)
