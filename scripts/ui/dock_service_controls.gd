class_name DockServiceControls
extends RefCounted

const META_SERVICE_ROW := &"dock_service_row"
const META_SERVICE_KEY := &"dock_service_key"


static func build_fill_service_row(
	parent: Node,
	default_fill_ratio: float,
	quote: Dictionary,
	on_confirm: Callable,
	on_ratio_changed: Callable,
	service_key: String = ""
) -> void:
	if not bool(quote.get("has_shortfall", false)):
		var button := Button.new()
		button.text = str(quote.get("button_text", "Service"))
		button.disabled = not bool(quote.get("enabled", false))
		button.pressed.connect(on_confirm)
		parent.add_child(button)
		return

	var column := VBoxContainer.new()
	column.set_meta(META_SERVICE_ROW, true)
	if not service_key.is_empty():
		column.set_meta(META_SERVICE_KEY, service_key)
	parent.add_child(column)

	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 8)
	column.add_child(slider_row)

	var fill_label := Label.new()
	fill_label.text = "Fill"
	slider_row.add_child(fill_label)

	var slider := HSlider.new()
	slider.min_value = 1.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 120.0
	slider.value = clampf(default_fill_ratio, 0.01, 1.0) * 100.0
	slider_row.add_child(slider)

	var percent := Label.new()
	percent.custom_minimum_size = Vector2(44, 0)
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent.text = "%d%%" % int(slider.value)
	slider_row.add_child(percent)

	var button := Button.new()
	button.pressed.connect(on_confirm)
	column.add_child(button)

	apply_quote_to_button(button, quote)

	slider.value_changed.connect(func(value: float) -> void:
		percent.text = "%d%%" % int(value)
		var ratio := clampf(value / 100.0, 0.01, 1.0)
		if on_ratio_changed.is_valid():
			var next_quote: Variant = on_ratio_changed.call(ratio)
			if typeof(next_quote) == TYPE_DICTIONARY:
				apply_quote_to_button(button, next_quote)
	)


static func apply_quote_to_button(button: Button, quote: Dictionary) -> void:
	if button == null:
		return
	button.text = str(quote.get("button_text", "Service"))
	button.disabled = not bool(quote.get("enabled", false))


static func slider_fill_ratio(row: VBoxContainer) -> float:
	if row == null:
		return 1.0
	for child in row.get_children():
		if child is HBoxContainer:
			for part in child.get_children():
				if part is HSlider:
					return clampf((part as HSlider).value / 100.0, 0.01, 1.0)
	return 1.0


static func apply_quote_on_row(row: VBoxContainer, quote: Dictionary) -> void:
	if row == null:
		return
	for child in row.get_children():
		if child is Button:
			apply_quote_to_button(child as Button, quote)
			return
