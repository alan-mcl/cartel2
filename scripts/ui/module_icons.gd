class_name ModuleIcons
extends RefCounted

const ROW_ICON_SIZE := 24

const MODULE_CATEGORIES: Array[String] = [
	"propulsion",
	"power",
	"computer",
	"life_support",
	"sensor",
	"navigation",
	"hyperdrive",
	"weapon",
	"armour",
	"cargo",
	"fuel",
	"ammunition",
	"shield",
	"point_defence",
	"cyber_defence",
	"transponder",
]

const _PATH_TEMPLATE := "res://assets/ui/modules/%s.png"


static func path_for_category(category: String) -> String:
	var cat := category.strip_edges()
	if cat.is_empty():
		return ""
	return _PATH_TEMPLATE % cat


static func texture_for_category(category: String) -> Texture2D:
	var path := path_for_category(category)
	if path.is_empty():
		return null
	return load(path) as Texture2D


static func configure_texture_rect(rect: TextureRect, category: String) -> void:
	if rect == null:
		return
	var tex := texture_for_category(category)
	rect.texture = tex
	rect.visible = tex != null
	if tex != null:
		rect.custom_minimum_size = Vector2(ROW_ICON_SIZE, ROW_ICON_SIZE)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


static func make_drag_preview(name_text: String, category: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var icon := TextureRect.new()
	configure_texture_rect(icon, category)
	row.add_child(icon)
	var label := Label.new()
	label.text = name_text
	row.add_child(label)
	return row


static func make_module_status_row(
	slot_text: String,
	module_name: String,
	category: String,
	key_min_width: float = 120.0
) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var icon := TextureRect.new()
	configure_texture_rect(icon, category)
	row.add_child(icon)
	var status := UiPatterns.status_row(slot_text, module_name, key_min_width)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(status)
	return row
