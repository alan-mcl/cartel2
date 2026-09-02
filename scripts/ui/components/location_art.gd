extends PanelContainer

@onready var _texture: TextureRect = $Frame/TextureRect
@onready var _placeholder: Label = $Frame/Placeholder


func set_art_path(art_path: String, label: String = "") -> void:
	if art_path.is_empty():
		_texture.texture = null
		_placeholder.text = label if not label.is_empty() else "No art"
		_placeholder.visible = true
		return

	var texture := load(art_path) as Texture2D
	if texture == null:
		_texture.texture = null
		_placeholder.text = label if not label.is_empty() else "Missing art"
		_placeholder.visible = true
		return

	_texture.texture = texture
	_placeholder.visible = false
