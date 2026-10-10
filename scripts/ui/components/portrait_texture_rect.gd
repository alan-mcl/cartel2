extends TextureRect

## UI pilot portrait: fixed box, linear filter, aspect-centered (no layout-driven rescale).
## Height matches habitat header banner (LocationArt header mode, 160 px).
## Author portrait PNGs at 120×160 (3:4) for 1:1 display.

const BANNER_HEIGHT_PX := 160
const DISPLAY_WIDTH_PX := BANNER_HEIGHT_PX * 3 / 4
const DISPLAY_HEIGHT_PX := BANNER_HEIGHT_PX

@export var display_size: Vector2i = Vector2i(DISPLAY_WIDTH_PX, DISPLAY_HEIGHT_PX)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	custom_minimum_size = Vector2(display_size)
	size = Vector2(display_size)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
