extends Node2D

const SkyParentBodyScript := preload("res://scripts/presentation/sky_parent_body.gd")
const LocalStarScript := preload("res://scripts/presentation/local_star.gd")

const ZOOM_MIN := 0.02
const ZOOM_MAX := 4.0
const ZOOM_WHEEL_FACTOR := 1.12

@onready var _starfield: Node2D = $Starfield
@onready var _world: Node2D = $World
@onready var _camera: Camera2D = $Camera2D
@onready var _overlay_layer: CanvasLayer = $Overlay

var catalog: Catalog
var _overlay_root: Control
var _preset_option: OptionButton
var _name_edit: LineEdit
var _angular_spin: SpinBox
var _star_angle_spin: SpinBox
var _parent_angle_spin: SpinBox
var _star_distance_spin: SpinBox
var _seed_edit: LineEdit
var _turbulence_slider: HSlider
var _turbulence_label: Label
var _ring_type_option: OptionButton
var _ring_scale_spin: SpinBox
var _band1_picker: ColorPickerButton
var _band2_picker: ColorPickerButton
var _ring_colour_picker: ColorPickerButton
var _json_output: TextEdit
var _status_label: Label

var _preset_rows: Array[Dictionary] = []
var _panning: bool = false
var _last_pointer: Vector2 = Vector2.ZERO
var _star_data: Dictionary = {"temperature_k": 2800.0, "luminosity": 0.12}
var _rebuild_queued: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	catalog = Catalog.load_default()
	_collect_presets()
	_build_overlay()
	if _starfield.has_method("bind_camera"):
		_starfield.bind_camera(_camera)
	_camera.make_current()
	_camera.zoom = Vector2.ONE * 0.08
	if not _preset_rows.is_empty():
		_preset_option.select(1)
		_load_preset_index(0)
	call_deferred("_rebuild_preview")
	call_deferred("_frame_view")


func _collect_presets() -> void:
	_preset_rows.clear()
	var worlds: Dictionary = catalog.worlds_by_id
	var ids: Array = worlds.keys()
	ids.sort()
	for world_id_variant in ids:
		var world_id := str(world_id_variant)
		var world_data: Dictionary = worlds.get(world_id, {})
		var parent_raw: Variant = world_data.get("parent_body", {})
		if typeof(parent_raw) != TYPE_DICTIONARY or parent_raw.is_empty():
			continue
		var parent: Dictionary = parent_raw
		var display := str(parent.get("name", world_id))
		_preset_rows.append({
			"world_id": world_id,
			"label": "%s (%s)" % [display, world_id],
			"parent_body": parent.duplicate(true),
			"star": _star_block_from_world(world_data),
		})


func _star_block_from_world(world_data: Dictionary) -> Dictionary:
	var star_raw: Variant = world_data.get("star", {})
	if typeof(star_raw) != TYPE_DICTIONARY:
		return {"temperature_k": 5800.0, "luminosity": 1.0}
	return {
		"temperature_k": float(star_raw.get("temperature_k", 5800.0)),
		"luminosity": float(star_raw.get("luminosity", 1.0)),
	}


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
	panel.offset_right = 440.0
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

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "Parent body harness"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "LMB pan · wheel zoom · F frame · tweak values then copy JSON into worlds.json parent_body."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	_preset_option = OptionButton.new()
	_preset_option.add_item("Custom (manual)", -1)
	for i in _preset_rows.size():
		_preset_option.add_item(str(_preset_rows[i].get("label", "?")), i)
	_preset_option.item_selected.connect(_on_preset_selected)
	vbox.add_child(_labeled_row("Catalog preset", _preset_option))

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Parent display name"
	_name_edit.text_changed.connect(_on_live_tweak)
	vbox.add_child(_labeled_row("Name", _name_edit))

	_angular_spin = _make_spin(2.0, 20.0, 0.5, 14.0)
	_angular_spin.value_changed.connect(_on_live_tweak_f)
	vbox.add_child(_labeled_row("Angular diameter (deg)", _angular_spin))

	_star_angle_spin = _make_spin(0.0, 360.0, 1.0, 25.0)
	_star_angle_spin.value_changed.connect(_on_live_tweak_f)
	vbox.add_child(_labeled_row("Star angle (deg)", _star_angle_spin))

	_parent_angle_spin = _make_spin(0.0, 360.0, 1.0, 205.0)
	_parent_angle_spin.value_changed.connect(_on_live_tweak_f)
	vbox.add_child(_labeled_row("Parent angle (deg)", _parent_angle_spin))

	_star_distance_spin = _make_spin(
		SkyBackdropLayout.STAR_MIN_RADIUS,
		SkyBackdropLayout.STAR_MAX_RADIUS,
		50.0,
		8500.0
	)
	_star_distance_spin.value_changed.connect(_on_live_tweak_f)
	vbox.add_child(_labeled_row("Backdrop distance", _star_distance_spin))

	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "Sector id or seed key"
	_seed_edit.text_changed.connect(_on_live_tweak)
	vbox.add_child(_labeled_row("Seed key", _seed_edit))

	_band1_picker = ColorPickerButton.new()
	_band1_picker.color = Color("#857052")
	_band1_picker.color_changed.connect(_on_live_tweak_color)
	vbox.add_child(_labeled_row("Band colour 1", _band1_picker))

	_band2_picker = ColorPickerButton.new()
	_band2_picker.color = Color("#c7ae85")
	_band2_picker.color_changed.connect(_on_live_tweak_color)
	vbox.add_child(_labeled_row("Band colour 2", _band2_picker))

	_turbulence_slider = HSlider.new()
	_turbulence_slider.min_value = 0.0
	_turbulence_slider.max_value = 1.0
	_turbulence_slider.step = 0.01
	_turbulence_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turbulence_slider.value_changed.connect(_on_turbulence_changed)
	var turb_row := HBoxContainer.new()
	turb_row.add_theme_constant_override("separation", 8)
	var turb_caption := Label.new()
	turb_caption.text = "Turbulence"
	turb_caption.custom_minimum_size.x = 120.0
	turb_row.add_child(turb_caption)
	turb_row.add_child(_turbulence_slider)
	_turbulence_label = Label.new()
	_turbulence_label.custom_minimum_size.x = 36.0
	_turbulence_label.text = "0.00"
	turb_row.add_child(_turbulence_label)
	vbox.add_child(turb_row)

	_ring_type_option = OptionButton.new()
	_ring_type_option.add_item("none", 0)
	_ring_type_option.add_item("small", 1)
	_ring_type_option.add_item("broad", 2)
	_ring_type_option.item_selected.connect(_on_ring_type_changed)
	vbox.add_child(_labeled_row("Rings", _ring_type_option))

	_ring_scale_spin = _make_spin(1.05, 2.6, 0.05, 1.4)
	_ring_scale_spin.value_changed.connect(_on_live_tweak_f)
	vbox.add_child(_labeled_row("Ring outer scale", _ring_scale_spin))

	_ring_colour_picker = ColorPickerButton.new()
	_ring_colour_picker.color = Color("#c7ae85")
	_ring_colour_picker.color_changed.connect(_on_live_tweak_color)
	vbox.add_child(_labeled_row("Ring colour", _ring_colour_picker))

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	var frame_btn := Button.new()
	frame_btn.text = "Frame (F)"
	frame_btn.pressed.connect(_frame_view)
	button_row.add_child(frame_btn)
	var match_btn := Button.new()
	match_btn.text = "Ring = band 2"
	match_btn.pressed.connect(_match_ring_to_band2)
	button_row.add_child(match_btn)
	var copy_btn := Button.new()
	copy_btn.text = "Copy JSON"
	copy_btn.pressed.connect(_copy_json)
	button_row.add_child(copy_btn)
	vbox.add_child(button_row)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	_json_output = TextEdit.new()
	_json_output.custom_minimum_size = Vector2(0, 160)
	_json_output.editable = false
	_json_output.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(_json_output)


func _labeled_row(caption: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 120.0
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _make_spin(min_v: float, max_v: float, step: float, initial: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = initial
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.allow_greater = false
	spin.allow_lesser = false
	return spin


func _on_preset_selected(index: int) -> void:
	var preset_id := _preset_option.get_item_id(index)
	_load_preset_index(preset_id)
	_queue_rebuild()


func _load_preset_index(preset_id: int) -> void:
	if preset_id < 0 or preset_id >= _preset_rows.size():
		return
	var row: Dictionary = _preset_rows[preset_id]
	var parent: Dictionary = row.get("parent_body", {})
	_star_data = row.get("star", _star_data).duplicate(true)
	_name_edit.text = str(parent.get("name", ""))
	_seed_edit.text = str(row.get("world_id", "harness"))
	var appearance: Dictionary = parent.get("appearance", {})
	if typeof(appearance) == TYPE_DICTIONARY:
		_band1_picker.color = Color(str(appearance.get("band_colour_1", "#ffffff")))
		_band2_picker.color = Color(str(appearance.get("band_colour_2", "#ffffff")))
		_turbulence_slider.value = float(appearance.get("turbulence", 0.0))
	var rings: Dictionary = parent.get("rings", {})
	if typeof(rings) == TYPE_DICTIONARY:
		var ring_type := str(rings.get("type", "none"))
		_select_ring_type(ring_type)
		if ring_type != "none":
			_ring_scale_spin.value = float(rings.get("outer_scale", 1.4))
			_ring_colour_picker.color = Color(str(rings.get("colour", "#ffffff")))
		else:
			_ring_colour_picker.color = _band2_picker.color
	var angular_min := float(parent.get("angular_diameter_deg_min", 14.0))
	var angular_max := float(parent.get("angular_diameter_deg_max", angular_min))
	_angular_spin.value = (angular_min + angular_max) * 0.5
	_on_ring_type_changed(_ring_type_option.selected)
	_update_json_display()


func _select_ring_type(ring_type: String) -> void:
	match ring_type:
		"small":
			_ring_type_option.select(1)
		"broad":
			_ring_type_option.select(2)
		_:
			_ring_type_option.select(0)


func _on_ring_type_changed(_index: int) -> void:
	var ring_type := _current_ring_type()
	var is_none := ring_type == "none"
	_ring_scale_spin.editable = not is_none
	_ring_colour_picker.disabled = is_none
	match ring_type:
		"small":
			_ring_scale_spin.min_value = 1.05
			_ring_scale_spin.max_value = 1.8
		"broad":
			_ring_scale_spin.min_value = 1.8
			_ring_scale_spin.max_value = 2.6
	_queue_rebuild()


func _on_turbulence_changed(value: float) -> void:
	_turbulence_label.text = "%.2f" % value
	_queue_rebuild()


func _on_live_tweak(_unused: String = "") -> void:
	_preset_option.select(0)
	_queue_rebuild()


func _on_live_tweak_f(_value: float = 0.0) -> void:
	_preset_option.select(0)
	_queue_rebuild()


func _on_live_tweak_color(_color: Color) -> void:
	_preset_option.select(0)
	_queue_rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_rebuild_preview")


func _current_ring_type() -> String:
	match _ring_type_option.selected:
		1:
			return "small"
		2:
			return "broad"
		_:
			return "none"


func _build_appearance_dict() -> Dictionary:
	return {
		"type": "banded",
		"band_colour_1": _color_to_hex(_band1_picker.color),
		"band_colour_2": _color_to_hex(_band2_picker.color),
		"turbulence": snappedf(float(_turbulence_slider.value), 0.01),
	}


func _build_rings_dict() -> Dictionary:
	var ring_type := _current_ring_type()
	if ring_type == "none":
		return {"type": "none"}
	return {
		"type": ring_type,
		"outer_scale": snappedf(float(_ring_scale_spin.value), 0.01),
		"colour": _color_to_hex(_ring_colour_picker.color),
	}


func _build_parent_data() -> Dictionary:
	return {
		"name": _name_edit.text.strip_edges(),
		"type": "gas_giant",
		"angular_diameter_deg_min": int(round(_angular_spin.value)),
		"angular_diameter_deg_max": int(round(_angular_spin.value)),
		"appearance": _build_appearance_dict(),
		"rings": _build_rings_dict(),
	}


func _color_to_hex(color: Color) -> String:
	return ("#" + color.to_html(false)).to_lower()


func _update_json_display() -> void:
	var appearance := _build_appearance_dict()
	var rings := _build_rings_dict()
	var block := {
		"appearance": appearance,
		"rings": rings,
	}
	_json_output.text = JSON.stringify(block, "\t")
	var resolved := SkyParentBodyParams.resolve_from_parent(_build_parent_data())
	if resolved.is_empty():
		_status_label.text = "Current parameters do not pass catalog validation."
	else:
		_status_label.text = "Valid · scan label: %s" % str(resolved.get("type_label", ""))


func _rebuild_preview() -> void:
	_rebuild_queued = false
	_update_json_display()
	for child in _world.get_children():
		child.free()

	var parent_data := _build_parent_data()
	var resolved := SkyParentBodyParams.resolve_from_parent(parent_data)
	if resolved.is_empty():
		return

	var appearance: Dictionary = resolved.get("appearance", {})
	var ring: Dictionary = resolved.get("ring", {})
	var distance := float(_star_distance_spin.value)
	var star_angle := deg_to_rad(float(_star_angle_spin.value))
	var parent_angle := deg_to_rad(float(_parent_angle_spin.value))
	var star_pos := Vector2.from_angle(star_angle) * distance
	var parent_pos := Vector2.from_angle(parent_angle) * distance
	var angular_deg := float(_angular_spin.value)
	var seed_key := _seed_edit.text.strip_edges()
	if seed_key.is_empty():
		seed_key = "harness"

	var star := LocalStarScript.new()
	star.name = "LocalStar"
	_world.add_child(star)
	star.configure(_star_data, star_pos)

	var parent := SkyParentBodyScript.new()
	parent.name = "ParentBody"
	_world.add_child(parent)
	parent.configure(
		parent_data,
		parent_pos,
		star_pos,
		angular_deg,
		appearance,
		ring,
		seed_key
	)


func _match_ring_to_band2() -> void:
	_ring_colour_picker.color = _band2_picker.color
	_queue_rebuild()


func _copy_json() -> void:
	DisplayServer.clipboard_set(_json_output.text)
	_status_label.text = "Copied appearance + rings JSON to clipboard."


func _frame_view() -> void:
	var star: Node2D = _world.get_node_or_null("LocalStar") as Node2D
	var parent: Node2D = _world.get_node_or_null("ParentBody") as Node2D
	if parent == null:
		_camera.position = Vector2.ZERO
		return
	var points: PackedVector2Array = PackedVector2Array([parent.position])
	if star != null:
		points.append(star.position)
	var min_p := points[0]
	var max_p := points[0]
	for p in points:
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
	var bounds := Rect2(min_p, max_p - min_p)
	var margin := 400.0
	bounds = bounds.grow(margin)
	var viewport_size := get_viewport().get_visible_rect().size
	var usable := viewport_size - Vector2(480.0, 160.0)
	var zoom_level := clampf(
		minf(usable.x / bounds.size.x, usable.y / bounds.size.y),
		ZOOM_MIN,
		ZOOM_MAX
	)
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
		var delta_pos := motion.position - _last_pointer
		_last_pointer = motion.position
		if _panning:
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
