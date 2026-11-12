extends Node2D

const AsteroidViewScript := preload("res://scripts/presentation/asteroid_view.gd")

const ZOOM_MIN := 0.05
const ZOOM_MAX := 8.0
const ZOOM_WHEEL_FACTOR := 1.12
const FLIGHT_ZOOM := 0.72
const GALLERY_SEED_SPAN := 6
const INSPECTION_SIZE := 280.0

@onready var _starfield: Node2D = $Starfield
@onready var _world: Node2D = $World
@onready var _camera: Camera2D = $Camera2D
@onready var _overlay_layer: CanvasLayer = $Overlay

var _overlay_root: Control
var _seed_spin: SpinBox
var _composition_option: OptionButton
var _size_option: OptionButton
var _azimuth_spin: SpinBox
var _elevation_spin: SpinBox
var _flight_zoom_check: CheckButton
var _status_label: Label
var _preview_20_box: VBoxContainer
var _preview_72_box: VBoxContainer
var _viewport_20: SubViewport
var _viewport_72: SubViewport

var _panning: bool = false
var _last_pointer: Vector2 = Vector2.ZERO
var _rebuild_queued: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	if _starfield.has_method("bind_camera"):
		_starfield.bind_camera(_camera)
	_camera.make_current()
	_camera.zoom = Vector2.ONE * 1.2
	call_deferred("_rebuild_preview")
	call_deferred("_frame_view")


func _build_overlay() -> void:
	_overlay_root = Control.new()
	_overlay_root.name = "Root"
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_overlay_root)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.anchor_bottom = 1.0
	panel.offset_left = 12.0
	panel.offset_top = 12.0
	panel.offset_right = 420.0
	panel.offset_bottom = -12.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Asteroid harness"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "LMB pan · wheel zoom · F frame · judge debris (20 px) and sample (72 px) presets."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	_seed_spin = _make_spin(0.0, 999999.0, 1.0, 42017.0)
	_seed_spin.value_changed.connect(_queue_rebuild)
	vbox.add_child(_labeled_row("Seed", _seed_spin))

	_composition_option = OptionButton.new()
	_composition_option.add_item("stony", 0)
	_composition_option.add_item("carbonaceous", 1)
	_composition_option.add_item("metallic", 2)
	_composition_option.add_item("icy", 3)
	_composition_option.item_selected.connect(_queue_rebuild_i)
	vbox.add_child(_labeled_row("Composition", _composition_option))

	_size_option = OptionButton.new()
	_size_option.add_item("20 px (debris)", 0)
	_size_option.add_item("72 px (sample)", 1)
	_size_option.add_item("256 px", 2)
	_size_option.select(1)
	_size_option.item_selected.connect(_queue_rebuild_i)
	vbox.add_child(_labeled_row("Gallery size", _size_option))

	_azimuth_spin = _make_spin(0.0, 360.0, 1.0, 220.0)
	_azimuth_spin.value_changed.connect(_queue_rebuild_f)
	vbox.add_child(_labeled_row("Light azimuth (deg)", _azimuth_spin))

	_elevation_spin = _make_spin(5.0, 85.0, 1.0, 38.0)
	_elevation_spin.value_changed.connect(_queue_rebuild_f)
	vbox.add_child(_labeled_row("Light elevation (deg)", _elevation_spin))

	_flight_zoom_check = CheckButton.new()
	_flight_zoom_check.text = "Flight camera zoom (0.72)"
	_flight_zoom_check.toggled.connect(_on_flight_zoom_toggled)
	vbox.add_child(_flight_zoom_check)

	var frame_btn := Button.new()
	frame_btn.text = "Frame (F)"
	frame_btn.pressed.connect(_frame_view)
	vbox.add_child(frame_btn)

	vbox.add_child(_section_label("Honest pixel preview (nearest upscale)"))

	_viewport_20 = SubViewport.new()
	_viewport_20.size = Vector2i(20, 20)
	_viewport_20.transparent_bg = true
	_viewport_20.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_20.handle_input_locally = false
	_overlay_root.add_child(_viewport_20)

	_preview_20_box = _make_preview_rect(_viewport_20, "20 px")
	vbox.add_child(_preview_20_box)

	_viewport_72 = SubViewport.new()
	_viewport_72.size = Vector2i(72, 72)
	_viewport_72.transparent_bg = true
	_viewport_72.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_72.handle_input_locally = false
	_overlay_root.add_child(_viewport_72)

	_preview_72_box = _make_preview_rect(_viewport_72, "72 px")
	vbox.add_child(_preview_72_box)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)


func _make_preview_rect(viewport: SubViewport, caption: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = caption
	box.add_child(label)
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(160, 160)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.texture = viewport.get_texture()
	box.add_child(rect)
	return box


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	return label


func _labeled_row(caption: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 150.0
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _make_spin(min_v: float, max_v: float, step: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _queue_rebuild(_unused = null) -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_rebuild_preview")


func _queue_rebuild_f(_value: float) -> void:
	_queue_rebuild()


func _queue_rebuild_i(_index: int) -> void:
	_queue_rebuild()


func _on_flight_zoom_toggled(pressed: bool) -> void:
	if pressed:
		_camera.zoom = Vector2.ONE * FLIGHT_ZOOM
	else:
		_camera.zoom = Vector2.ONE * 1.2
	_frame_view()


func _current_composition() -> String:
	var idx := _composition_option.get_selected_id()
	match idx:
		1:
			return AsteroidShape.COMPOSITION_CARBONACEOUS
		2:
			return AsteroidShape.COMPOSITION_METALLIC
		3:
			return AsteroidShape.COMPOSITION_ICY
		_:
			return AsteroidShape.COMPOSITION_STONY


func _gallery_size() -> float:
	match _size_option.get_selected_id():
		0:
			return 20.0
		2:
			return 256.0
		_:
			return 72.0


func _sun_direction() -> Vector3:
	var probe := AsteroidViewScript.new()
	return probe.static_sun_direction(float(_azimuth_spin.value), float(_elevation_spin.value))


func _rebuild_preview() -> void:
	_rebuild_queued = false
	var seed_val := int(_seed_spin.value)
	var composition := _current_composition()
	var gallery_size := _gallery_size()
	var sun := _sun_direction()

	for child in _world.get_children():
		child.queue_free()

	var primary := AsteroidViewScript.new()
	primary.name = "PrimaryAsteroid"
	_world.add_child(primary)
	primary.configure(seed_val, composition, INSPECTION_SIZE)
	primary.set_sun(sun, 1.0)
	primary.position = Vector2(-120.0, -40.0)

	var gallery := Node2D.new()
	gallery.name = "Gallery"
	_world.add_child(gallery)
	var spacing := gallery_size * 1.35 + 24.0
	var start_x := -spacing * float(GALLERY_SEED_SPAN - 1) * 0.5
	for i in GALLERY_SEED_SPAN:
		var view := AsteroidViewScript.new()
		view.name = "Rock%d" % i
		gallery.add_child(view)
		view.configure(seed_val + i * 7919, composition, gallery_size)
		view.set_sun(sun, 1.0)
		view.position = Vector2(start_x + float(i) * spacing, gallery_size * 0.85 + 120.0)

	_fill_viewport_preview(_viewport_20, seed_val, composition, 20.0, sun)
	_fill_viewport_preview(_viewport_72, seed_val, composition, 72.0, sun)

	if _preview_20_box != null and _preview_20_box.get_child_count() > 1:
		var r20: TextureRect = _preview_20_box.get_child(1) as TextureRect
		if r20 != null:
			r20.texture = _viewport_20.get_texture()
	if _preview_72_box != null and _preview_72_box.get_child_count() > 1:
		var r72: TextureRect = _preview_72_box.get_child(1) as TextureRect
		if r72 != null:
			r72.texture = _viewport_72.get_texture()

	_status_label.text = (
		"Seed %d · %s · gallery %.0f px · radius_max %.3f"
		% [seed_val, composition, gallery_size, float(primary.get_params().get("radius_max", 1.0))]
	)


func _fill_viewport_preview(viewport: SubViewport, seed_val: int, composition: String, size_px: float, sun: Vector3) -> void:
	for child in viewport.get_children():
		child.queue_free()
	var view := AsteroidViewScript.new()
	viewport.add_child(view)
	view.position = Vector2(size_px * 0.5, size_px * 0.5)
	view.configure(seed_val, composition, size_px)
	view.set_sun(sun, 1.0)


func _frame_view() -> void:
	var primary: Node2D = _world.get_node_or_null("PrimaryAsteroid") as Node2D
	if primary == null:
		_camera.position = Vector2.ZERO
		return
	var gallery: Node2D = _world.get_node_or_null("Gallery") as Node2D
	var min_p := primary.global_position
	var max_p := primary.global_position
	if gallery != null:
		for child in gallery.get_children():
			if child is Node2D:
				var p: Vector2 = (child as Node2D).global_position
				min_p.x = minf(min_p.x, p.x)
				min_p.y = minf(min_p.y, p.y)
				max_p.x = maxf(max_p.x, p.x)
				max_p.y = maxf(max_p.y, p.y)
	var bounds := Rect2(min_p, max_p - min_p)
	bounds = bounds.grow(maxf(_gallery_size(), INSPECTION_SIZE) * 0.6)
	var viewport_size := get_viewport().get_visible_rect().size
	var usable := viewport_size - Vector2(440.0, 80.0)
	var zoom_level := clampf(
		minf(usable.x / maxf(bounds.size.x, 1.0), usable.y / maxf(bounds.size.y, 1.0)),
		ZOOM_MIN,
		ZOOM_MAX
	)
	if _flight_zoom_check.button_pressed:
		zoom_level = FLIGHT_ZOOM
	_camera.zoom = Vector2.ONE * zoom_level
	_camera.position = bounds.get_center()


func _unhandled_input(event: InputEvent) -> void:
	if _pointer_over_overlay():
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_F:
			_frame_view()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_panning = mb.pressed
			_last_pointer = mb.position
		elif mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(mb.position, 1.0 / ZOOM_WHEEL_FACTOR)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(mb.position, ZOOM_WHEEL_FACTOR)
				get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _panning:
			var delta_pos := motion.position - _last_pointer
			_last_pointer = motion.position
			_pan_camera(-delta_pos / _camera.zoom)
			get_viewport().set_input_as_handled()


func _pointer_over_overlay() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	return hovered == _overlay_root or _overlay_root.is_ancestor_of(hovered)


func _pan_camera(screen_delta: Vector2) -> void:
	_camera.position -= screen_delta


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var old_zoom := _camera.zoom.x
	var new_zoom := clampf(old_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(old_zoom, new_zoom):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var zoom_ratio := old_zoom / new_zoom
	var offset := (screen_pos - viewport_size * 0.5) / old_zoom
	_camera.position += offset * (1.0 - zoom_ratio)
	_camera.zoom = Vector2.ONE * new_zoom
