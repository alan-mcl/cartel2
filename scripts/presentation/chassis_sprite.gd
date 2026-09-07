class_name ChassisSprite
extends RefCounted

static var _cache: Dictionary = {}
static var _fallback: Texture2D


static func get_texture(sprite_path: String) -> Texture2D:
	if sprite_path.is_empty():
		return _fallback_texture()

	if _cache.has(sprite_path):
		return _cache[sprite_path]

	var texture: Texture2D = null
	if _import_sidecar_exists(sprite_path):
		texture = ResourceLoader.load(sprite_path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE) as Texture2D

	if texture == null:
		push_warning(
			"Chassis sprite not imported: %s (run: godot --path . --import --headless --quit)" % sprite_path
		)
		texture = _fallback_texture()

	_cache[sprite_path] = texture
	return texture


static func _import_sidecar_exists(sprite_path: String) -> bool:
	return FileAccess.file_exists("%s.import" % sprite_path)


static func _fallback_texture() -> Texture2D:
	if _fallback != null:
		return _fallback

	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(64):
		for x in range(64):
			var dx := absf(x - 31.5) / 16.0
			var dy := (y - 8.0) / 48.0
			if dy >= 0.0 and dy <= 1.0 and dx <= 1.0 - dy * 0.35:
				image.set_pixel(x, y, Color(0.55, 0.75, 0.85, 1.0))

	_fallback = ImageTexture.create_from_image(image)
	return _fallback
