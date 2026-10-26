extends PanelContainer
class_name AudioSettingsPanel

signal closed

const BUS_LABELS := {
	"master": "Master Volume",
	"music": "Music Volume",
	"sfx": "SFX Volume",
	"ambience": "Ambience Volume",
	"ui": "UI Volume",
}

var _sliders: Dictionary = {}


func _ready() -> void:
	theme_type_variation = &"Surface"
	custom_minimum_size = Vector2(420, 0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var title := Label.new()
	title.text = "Audio"
	title.theme_type_variation = &"Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	for key in ["master", "music", "sfx", "ambience", "ui"]:
		root.add_child(_make_row(key))

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close_pressed)
	root.add_child(close_btn)
	_refresh_from_manager()


func open() -> void:
	visible = true
	_refresh_from_manager()


func close_panel() -> void:
	visible = false
	closed.emit()


func _make_row(bus_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = BUS_LABELS.get(bus_key, bus_key)
	label.custom_minimum_size = Vector2(160, 0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_slider_changed.bind(bus_key))
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(40, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	_sliders[bus_key] = {"slider": slider, "value": value_label}
	return row


func _refresh_from_manager() -> void:
	for key in _sliders.keys():
		var linear := AudioService.get_volume(key)
		var row: Dictionary = _sliders[key]
		var slider: HSlider = row["slider"]
		slider.set_value_no_signal(roundi(linear * 100.0))
		row["value"].text = str(int(slider.value))


func _on_slider_changed(value: float, bus_key: String) -> void:
	var linear := clampf(value / 100.0, 0.0, 1.0)
	AudioService.set_volume(bus_key, linear)
	if _sliders.has(bus_key):
		_sliders[bus_key]["value"].text = str(int(value))


func _on_close_pressed() -> void:
	AudioService.play_ui("click")
	close_panel()
