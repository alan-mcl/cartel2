extends PanelContainer

const HEADER_HEIGHT := 160.0
const LEFT_FADE_WIDTH_PX := 72
const BANNER_FADE_SHADER := preload("res://shaders/location_art_banner.gdshader")

var _frame: AspectRatioContainer
var _texture: TextureRect
var _placeholder: Label
var _logo_host: Control
var _logo: TextureRect
var _banner_fade_material: ShaderMaterial
var _header_mode: bool = false


func _bind_nodes() -> void:
	if _texture != null:
		return
	_frame = $Frame
	_texture = $Frame/TextureRect
	_placeholder = $Frame/Placeholder
	_logo_host = $LogoHost
	_logo = $LogoHost/Logo


func configure_header_mode(enabled: bool) -> void:
	_bind_nodes()
	if _header_mode == enabled:
		return
	_header_mode = enabled
	if enabled:
		custom_minimum_size = Vector2(0, HEADER_HEIGHT)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		clip_contents = true
		add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
		_frame.visible = true
		_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_frame.stretch_mode = AspectRatioContainer.STRETCH_COVER
		_apply_full_rect_art()
		_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_apply_banner_fade(true)
	else:
		custom_minimum_size = Vector2(0, HEADER_HEIGHT)
		size_flags_vertical = Control.SIZE_SHRINK_END
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		clip_contents = false
		remove_theme_stylebox_override(&"panel")
		_frame.visible = true
		_frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_frame.offset_left = 0
		_frame.offset_top = 0
		_frame.offset_right = 0
		_frame.offset_bottom = 0
		_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_frame.size_flags_vertical = Control.SIZE_SHRINK_END
		_apply_frame_art()
		_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_texture.material = null
		_frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
		_hide_logo()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _header_mode:
		_update_banner_fade_width()
		_update_logo_layout()


func _apply_banner_fade(enabled: bool) -> void:
	if not enabled:
		_texture.material = null
		return
	if _banner_fade_material == null:
		_banner_fade_material = ShaderMaterial.new()
		_banner_fade_material.shader = BANNER_FADE_SHADER
	_texture.material = _banner_fade_material
	_update_banner_fade_width()


func _update_banner_fade_width() -> void:
	if _banner_fade_material == null or size.x <= 0.0:
		return
	var fade_end := clampf(float(LEFT_FADE_WIDTH_PX) / size.x, 0.02, 0.35)
	_banner_fade_material.set_shader_parameter(&"fade_end", fade_end)


func _apply_full_rect_art() -> void:
	for node in [_texture, _placeholder]:
		node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		node.offset_left = 0
		node.offset_top = 0
		node.offset_right = 0
		node.offset_bottom = 0
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _apply_frame_art() -> void:
	for node in [_texture, _placeholder]:
		node.set_anchors_preset(Control.PRESET_TOP_LEFT)
		node.offset_left = 0
		node.offset_top = 0
		node.offset_right = 0
		node.offset_bottom = 0
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.size_flags_vertical = Control.SIZE_EXPAND_FILL


func set_art_path(art_path: String, label: String = "") -> void:
	_bind_nodes()
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


func set_logo_path(logo_path: String) -> void:
	_bind_nodes()
	if not _header_mode or logo_path.is_empty():
		_hide_logo()
		return

	var texture := load(logo_path) as Texture2D
	if texture == null:
		_hide_logo()
		return

	_logo.texture = texture
	_logo.visible = true
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP
	_logo_host.visible = true
	_update_logo_layout()


func _hide_logo() -> void:
	if _logo_host == null:
		return
	_logo.texture = null
	_logo_host.custom_minimum_size = Vector2.ZERO
	_logo_host.visible = false


func _update_logo_layout() -> void:
	if _logo_host == null or not _logo_host.visible or _logo.texture == null:
		return
	# The host fills the banner and clips. Minimum height stays 0 so a taller logo
	# cannot grow the header. The texture stays at authored size, centred in that window.
	var tex_size := _logo.texture.get_size()
	_logo_host.custom_minimum_size = Vector2(tex_size.x, 0)
	_logo_host.size_flags_horizontal = Control.SIZE_SHRINK_END
	_logo_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_logo.anchor_left = 0.0
	_logo.anchor_right = 0.0
	_logo.anchor_top = 0.5
	_logo.anchor_bottom = 0.5
	_logo.offset_left = 0.0
	_logo.offset_right = tex_size.x
	_logo.offset_top = -tex_size.y * 0.5
	_logo.offset_bottom = tex_size.y * 0.5
