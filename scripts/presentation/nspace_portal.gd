extends Node2D

var _palette: Dictionary = {}


func configure(palette: Dictionary) -> void:
	_palette = palette
	# Portal visuals are rendered in 3D by NspaceBackdrop3D; keep this node interact-only.


func _draw() -> void:
	pass
