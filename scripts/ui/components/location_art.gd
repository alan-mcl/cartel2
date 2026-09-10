extends PanelContainer

@onready var _frame: AspectRatioContainer = $Frame
@onready var _texture: TextureRect = $Frame/TextureRect
@onready var _placeholder: Label = $Frame/Placeholder


func configure_header_mode(enabled: bool) -> void:
	if enabled:
		custom_minimum_size = Vector2(0, 160)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
	else:
		custom_minimum_size = Vector2(0, 160)
		size_flags_vertical = Control.SIZE_SHRINK_END
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_frame.stretch_mode = AspectRatioContainer.STRETCH_FIT


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
