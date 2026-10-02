extends TextureRect

## UI pilot portrait: fixed box, linear filter, aspect-centered (no layout-driven rescale).

@export var display_size: Vector2i = Vector2i(160, 160)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	custom_minimum_size = Vector2(display_size)
	size = Vector2(display_size)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
