extends Control

var _status: Label
var _thrust_slider: HSlider
var _boost_check: CheckBox
var _marker: Marker2D
var _listener: AudioListener2D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.054902, 0.070588, 0.086275, 0.94)
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	var title := Label.new()
	title.text = "Audio sandbox"
	title.theme_type_variation = &"Title"
	body.add_child(title)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)

	body.add_child(_section_label("Music"))
	for ctx in ["menu", "exploration", "habitat"]:
		body.add_child(_action_button("Play %s" % ctx, _play_music.bind(ctx)))

	body.add_child(_section_label("Ambience"))
	for ctx in ["space", "habitat"]:
		body.add_child(_action_button("Play %s" % ctx, _play_ambience.bind(ctx)))

	body.add_child(_section_label("SFX"))
	for sfx in ["click", "confirm", "collision", "salvage", "alert"]:
		body.add_child(_action_button("UI/SFX: %s" % sfx, _play_sfx.bind(sfx)))

	body.add_child(_section_label("Ship"))
	_thrust_slider = HSlider.new()
	_thrust_slider.min_value = 0.0
	_thrust_slider.max_value = 1.0
	_thrust_slider.step = 0.01
	_thrust_slider.value = 0.0
	_thrust_slider.value_changed.connect(_on_thrust_changed)
	body.add_child(_thrust_slider)
	_boost_check = CheckBox.new()
	_boost_check.text = "Boost"
	_boost_check.toggled.connect(_on_boost_toggled)
	body.add_child(_boost_check)

	body.add_child(_section_label("Positional"))
	body.add_child(_action_button("Marker left", _move_marker.bind(-320.0)))
	body.add_child(_action_button("Marker right", _move_marker.bind(320.0)))
	body.add_child(_action_button("Play collision at marker", _play_marker_collision))

	var settings := AudioSettingsPanel.new()
	body.add_child(settings)

	_marker = Marker2D.new()
	_marker.position = Vector2(320, 540)
	add_child(_marker)
	_listener = AudioListener2D.new()
	_listener.position = Vector2(960, 540)
	add_child(_listener)
	_listener.make_current()

	set_process(true)


func _process(_delta: float) -> void:
	var music_ctx := AudioService.get_music_context()
	var amb_ctx := AudioService.get_ambience_context()
	_status.text = (
		"Music: %s\nAmbience: %s\nEngine: %s"
		% [
			music_ctx if not music_ctx.is_empty() else "(none)",
			amb_ctx if not amb_ctx.is_empty() else "(none)",
			"playing" if AudioService.is_engine_playing() else "silent",
		]
	)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Meta"
	return label


func _action_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func _play_music(context: String) -> void:
	AudioService.play_ui("click")
	AudioService.play_music(context)


func _play_ambience(context: String) -> void:
	AudioService.play_ui("click")
	AudioService.play_ambience(context)


func _play_sfx(kind: String) -> void:
	AudioService.play_ui("click")
	match kind:
		"click":
			AudioService.play_ui("click")
		"confirm":
			AudioService.play_ui("confirm")
		"collision":
			AudioService.play_sfx_at("ship.collision", _marker.global_position)
		"salvage":
			AudioService.play_sfx("interaction.salvage")
		"alert":
			AudioService.play_sfx("notification.alert")


func _on_thrust_changed(value: float) -> void:
	AudioService.set_ship_thrust(value, _boost_check.button_pressed, _marker.global_position)


func _on_boost_toggled(_pressed: bool) -> void:
	_on_thrust_changed(_thrust_slider.value)


func _move_marker(offset_x: float) -> void:
	_marker.position.x = offset_x
	AudioService.play_ui("click")


func _play_marker_collision() -> void:
	AudioService.play_ui("click")
	AudioService.play_sfx_at("ship.collision", _marker.global_position)
