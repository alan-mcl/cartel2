extends SceneTree
## Generates res://themes/cartel_theme.tres from Cartel design tokens.
## Run: ~/opt/Godot_v4.7.2-stable_linux.x86_64 --headless -s scripts/tools/build_cartel_theme.gd

const OUTPUT_PATH := "res://themes/cartel_theme.tres"

const C := {
	"bg": Color("#0E1216"),
	"surface": Color("#161C22"),
	"surface_alt": Color("#1C242C"),
	"elevated": Color("#232C35"),
	"border": Color("#33404A"),
	"text": Color("#E4E2D8"),
	"text_muted": Color("#8A959E"),
	"accent": Color("#C9A227"),
	"positive": Color("#3E8F73"),
	"warning": Color("#C9892E"),
	"negative": Color("#C45C4A"),
	"info": Color("#5A7A94"),
}

const FONT_SANS_REGULAR := "res://assets/ui/fonts/IBMPlexSans-Regular.ttf"
const FONT_SANS_MEDIUM := "res://assets/ui/fonts/IBMPlexSans-Medium.ttf"
const FONT_MONO_MEDIUM := "res://assets/ui/fonts/IBMPlexMono-Medium.ttf"

const TYPE := {
	"title": 24,
	"headline": 20,
	"body": 15,
	"section": 15,
	"muted": 14,
	"meta": 12,
	"numeric": 15,
	"status": 15,
}


func _init() -> void:
	var theme := _build_theme()
	var err := ResourceSaver.save(theme, OUTPUT_PATH)
	if err != OK:
		push_error("Failed to save theme (%s): %s" % [err, OUTPUT_PATH])
		quit(1)
	print("Wrote ", OUTPUT_PATH)
	quit(0)


func _build_theme() -> Theme:
	var theme := Theme.new()

	_register_tokens(theme)
	_register_fonts(theme)
	_style_labels(theme)
	_style_buttons(theme)
	_style_panels(theme)
	_style_separators(theme)
	_style_line_edit(theme)
	_style_scrollbars(theme)
	_style_tab_container(theme)
	_style_check_box(theme)
	_style_option_button(theme)
	_style_progress_bar(theme)
	_style_item_list(theme)
	_style_tree(theme)
	_style_tooltip(theme)

	return theme


func _register_tokens(theme: Theme) -> void:
	for key in C:
		theme.set_color(StringName(key), &"Cartel", C[key])

	theme.set_constant(&"margin_sm", &"Cartel", 8)
	theme.set_constant(&"margin_md", &"Cartel", 12)
	theme.set_constant(&"list_row", &"Cartel", 4)
	theme.set_constant(&"separator", &"Cartel", 1)
	theme.set_constant(&"radius", &"Cartel", 2)


func _load_font(path: String) -> FontFile:
	var font := FontFile.new()
	font.load_dynamic_font(path)
	return font


func _register_fonts(theme: Theme) -> void:
	var sans_regular := _load_font(FONT_SANS_REGULAR)
	var sans_medium := _load_font(FONT_SANS_MEDIUM)
	var mono_medium := _load_font(FONT_MONO_MEDIUM)

	# Default body typography.
	for control_type in [&"Label", &"Button", &"LineEdit", &"ItemList", &"Tree", &"CheckBox", &"OptionButton", &"TabBar"]:
		theme.set_font(&"font", control_type, sans_regular)
		theme.set_font_size(&"font_size", control_type, TYPE.body)

	theme.set_font(&"font", &"Label", sans_regular)
	theme.set_font_size(&"font_size", &"Label", TYPE.body)
	theme.set_color(&"font_color", &"Label", C.text)

	# Label type variations.
	_set_label_variation(theme, &"Title", sans_medium, TYPE.title, C.text)
	_set_label_variation(theme, &"Headline", sans_medium, TYPE.headline, C.text)
	_set_label_variation(theme, &"Section", sans_medium, TYPE.section, C.text_muted)
	_set_label_variation(theme, &"Muted", sans_regular, TYPE.muted, C.text_muted)
	_set_label_variation(theme, &"Meta", sans_regular, TYPE.meta, C.text_muted)
	_set_label_variation(theme, &"Numeric", mono_medium, TYPE.numeric, C.accent)
	_set_label_variation(theme, &"Alert", sans_medium, TYPE.status, C.negative)
	_set_label_variation(theme, &"Positive", sans_medium, TYPE.status, C.positive)
	_set_label_variation(theme, &"Warning", sans_medium, TYPE.status, C.warning)
	_set_label_variation(theme, &"Negative", sans_medium, TYPE.status, C.negative)
	_set_label_variation(theme, &"Info", sans_regular, TYPE.status, C.info)


func _set_label_variation(
	theme: Theme,
	variation: StringName,
	font: Font,
	size: int,
	color: Color
) -> void:
	theme.set_type_variation(variation, &"Label")
	theme.set_font(&"font", variation, font)
	theme.set_font_size(&"font_size", variation, size)
	theme.set_color(&"font_color", variation, color)


func _flat(
	bg: Color,
	border: Color = C.border,
	margin: int = 8,
	radius: int = 0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	return box


func _flat_accent_left(bg: Color, accent_width: int = 3) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = C.accent
	box.border_width_left = accent_width
	box.border_width_top = 0
	box.border_width_right = 0
	box.border_width_bottom = 0
	box.set_content_margin_all(8)
	return box


func _style_labels(theme: Theme) -> void:
	pass


func _style_buttons(theme: Theme) -> void:
	var normal := _flat(C.surface, C.border, 8, 0)
	var hover := _flat(C.surface_alt, C.border, 8, 0)
	var pressed := _flat(C.elevated, C.border, 8, 0)
	var disabled := _flat(C.surface.darkened(0.08), C.border.darkened(0.1), 8, 0)
	disabled.bg_color.a = 0.65
	var focus := normal.duplicate()
	focus.border_color = C.accent
	focus.set_border_width_all(1)

	theme.set_stylebox(&"normal", &"Button", normal)
	theme.set_stylebox(&"hover", &"Button", hover)
	theme.set_stylebox(&"pressed", &"Button", pressed)
	theme.set_stylebox(&"disabled", &"Button", disabled)
	theme.set_stylebox(&"focus", &"Button", focus)
	theme.set_color(&"font_color", &"Button", C.text)
	theme.set_color(&"font_hover_color", &"Button", C.text)
	theme.set_color(&"font_pressed_color", &"Button", C.text)
	theme.set_color(&"font_disabled_color", &"Button", C.text_muted)


func _style_panels(theme: Theme) -> void:
	var panel := _flat(C.surface, C.border, 12, 0)
	theme.set_stylebox(&"panel", &"PanelContainer", panel)
	theme.set_stylebox(&"panel", &"Panel", panel)

	theme.set_type_variation(&"Surface", &"PanelContainer")
	theme.set_stylebox(&"panel", &"Surface", _flat(C.surface, C.border, 12, 0))

	theme.set_type_variation(&"Elevated", &"PanelContainer")
	theme.set_stylebox(&"panel", &"Elevated", _flat(C.elevated, C.border, 12, 0))

	theme.set_type_variation(&"Media", &"PanelContainer")
	theme.set_stylebox(&"panel", &"Media", _flat(C.surface_alt, C.border, 12, 0))

	theme.set_type_variation(&"Alert", &"PanelContainer")
	var alert_panel := _flat_accent_left(C.surface_alt, 3)
	alert_panel.border_color = C.negative
	theme.set_stylebox(&"panel", &"Alert", alert_panel)


func _style_separators(theme: Theme) -> void:
	var h := StyleBoxLine.new()
	h.color = C.border
	h.thickness = 1
	theme.set_stylebox(&"separator", &"HSeparator", h)

	var v := StyleBoxLine.new()
	v.color = C.border
	v.thickness = 1
	v.vertical = true
	theme.set_stylebox(&"separator", &"VSeparator", v)


func _style_line_edit(theme: Theme) -> void:
	var normal := _flat(C.surface, C.border, 8, 0)
	var focus := _flat(C.elevated, C.accent, 8, 0)
	var disabled := _flat(C.surface.darkened(0.06), C.border.darkened(0.08), 8, 0)
	var read_only := _flat(C.surface_alt, C.border, 8, 0)

	theme.set_stylebox(&"normal", &"LineEdit", normal)
	theme.set_stylebox(&"focus", &"LineEdit", focus)
	theme.set_stylebox(&"read_only", &"LineEdit", read_only)
	theme.set_stylebox(&"disabled", &"LineEdit", disabled)
	theme.set_color(&"font_color", &"LineEdit", C.text)
	theme.set_color(&"font_placeholder_color", &"LineEdit", C.text_muted)
	theme.set_color(&"font_uneditable_color", &"LineEdit", C.text_muted)
	theme.set_color(&"font_selected_color", &"LineEdit", C.bg)
	theme.set_color(&"selection_color", &"LineEdit", C.accent.darkened(0.2))
	theme.set_color(&"caret_color", &"LineEdit", C.accent)


func _style_scrollbars(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = C.surface
	track.set_content_margin_all(0)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = C.border
	grabber.set_corner_radius_all(1)

	var grabber_highlight := grabber.duplicate()
	grabber_highlight.bg_color = C.text_muted

	for bar_type in [&"HScrollBar", &"VScrollBar"]:
		theme.set_stylebox(&"scroll", bar_type, track)
		theme.set_stylebox(&"scroll_focus", bar_type, track)
		theme.set_stylebox(&"grabber", bar_type, grabber)
		theme.set_stylebox(&"grabber_highlight", bar_type, grabber_highlight)
		theme.set_stylebox(&"grabber_pressed", bar_type, grabber_highlight)
		theme.set_constant(&"min_width" if bar_type == &"VScrollBar" else &"min_height", bar_type, 8)


func _style_tab_container(theme: Theme) -> void:
	var panel := _flat(C.surface, C.border, 8, 0)
	theme.set_stylebox(&"panel", &"TabContainer", panel)
	theme.set_stylebox(&"tab_selected", &"TabContainer", _flat(C.surface_alt, C.accent, 8, 0))
	theme.set_stylebox(&"tab_unselected", &"TabContainer", _flat(C.surface, C.border, 8, 0))
	theme.set_stylebox(&"tab_disabled", &"TabContainer", _flat(C.surface.darkened(0.06), C.border, 8, 0))
	theme.set_color(&"font_selected_color", &"TabContainer", C.accent)
	theme.set_color(&"font_unselected_color", &"TabContainer", C.text_muted)
	theme.set_color(&"font_disabled_color", &"TabContainer", C.text_muted.darkened(0.15))


func _style_check_box(theme: Theme) -> void:
	theme.set_icon(&"checked", &"CheckBox", _checkbox_icon(true))
	theme.set_icon(&"unchecked", &"CheckBox", _checkbox_icon(false))
	theme.set_color(&"font_color", &"CheckBox", C.text)
	theme.set_color(&"font_hover_color", &"CheckBox", C.text)
	theme.set_color(&"font_pressed_color", &"CheckBox", C.text)
	theme.set_color(&"font_disabled_color", &"CheckBox", C.text_muted)


func _checkbox_icon(checked: bool) -> ImageTexture:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(C.surface)
	for x in range(14):
		for y in range(14):
			if x == 0 or y == 0 or x == 13 or y == 13:
				img.set_pixel(x, y, C.border)
	if checked:
		for x in range(3, 11):
			for y in range(3, 11):
				img.set_pixel(x, y, C.accent)
	var tex := ImageTexture.create_from_image(img)
	return tex


func _style_option_button(theme: Theme) -> void:
	var normal := _flat(C.surface, C.border, 8, 0)
	var hover := _flat(C.surface_alt, C.border, 8, 0)
	var pressed := _flat(C.elevated, C.border, 8, 0)
	var disabled := _flat(C.surface.darkened(0.08), C.border.darkened(0.1), 8, 0)
	var focus := normal.duplicate()
	focus.border_color = C.accent

	theme.set_stylebox(&"normal", &"OptionButton", normal)
	theme.set_stylebox(&"hover", &"OptionButton", hover)
	theme.set_stylebox(&"pressed", &"OptionButton", pressed)
	theme.set_stylebox(&"disabled", &"OptionButton", disabled)
	theme.set_stylebox(&"focus", &"OptionButton", focus)
	theme.set_color(&"font_color", &"OptionButton", C.text)
	theme.set_color(&"font_hover_color", &"OptionButton", C.text)
	theme.set_color(&"font_pressed_color", &"OptionButton", C.text)
	theme.set_color(&"font_disabled_color", &"OptionButton", C.text_muted)


func _style_progress_bar(theme: Theme) -> void:
	var bg := _flat(C.surface_alt, C.border, 2, 0)
	bg.set_content_margin_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = C.accent
	fill.set_corner_radius_all(1)

	theme.set_stylebox(&"background", &"ProgressBar", bg)
	theme.set_stylebox(&"fill", &"ProgressBar", fill)
	theme.set_color(&"font_color", &"ProgressBar", C.text_muted)
	theme.set_color(&"font_outline_color", &"ProgressBar", C.bg)


func _style_item_list(theme: Theme) -> void:
	var panel := _flat(C.surface, C.border, 4, 0)
	var selected := _flat_accent_left(C.elevated, 3)

	theme.set_stylebox(&"panel", &"ItemList", panel)
	theme.set_stylebox(&"selected", &"ItemList", selected)
	theme.set_stylebox(&"selected_focus", &"ItemList", selected)
	theme.set_color(&"font_color", &"ItemList", C.text)
	theme.set_color(&"font_selected_color", &"ItemList", C.text)
	theme.set_color(&"font_outline_color", &"ItemList", C.bg)


func _style_tree(theme: Theme) -> void:
	var panel := _flat(C.surface, C.border, 4, 0)
	var selected := _flat_accent_left(C.elevated, 3)

	theme.set_stylebox(&"panel", &"Tree", panel)
	theme.set_stylebox(&"selected", &"Tree", selected)
	theme.set_stylebox(&"selected_focus", &"Tree", selected)
	theme.set_color(&"font_color", &"Tree", C.text)
	theme.set_color(&"font_selected_color", &"Tree", C.text)
	theme.set_color(&"title_button_color", &"Tree", C.text_muted)
	theme.set_color(&"drop_mark_color", &"Tree", C.accent)
	theme.set_color(&"relationship_line_color", &"Tree", C.border)
	theme.set_color(&"guide_color", &"Tree", C.border)
	theme.set_constant(&"item_margin", &"Tree", 4)
	theme.set_constant(&"h_separation", &"Tree", 4)


func _style_tooltip(theme: Theme) -> void:
	var panel := _flat(C.elevated, C.border, 8, 0)
	theme.set_stylebox(&"panel", &"TooltipPanel", panel)
	theme.set_font(&"font", &"TooltipLabel", _load_font(FONT_SANS_REGULAR))
	theme.set_font_size(&"font_size", &"TooltipLabel", TYPE.body)
	theme.set_color(&"font_color", &"TooltipLabel", C.text)
