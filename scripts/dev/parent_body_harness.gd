extends Node2D

const SkyParentBodyScript := preload("res://scripts/presentation/sky_parent_body.gd")
const LocalStarScript := preload("res://scripts/presentation/local_star.gd")

const ZOOM_MIN := 0.02
const ZOOM_MAX := 4.0
const ZOOM_WHEEL_FACTOR := 1.12
const MAX_RING_BANDS := 6
const MAX_RING_GAPS := 4

const RING_MODE_NONE := 0
const RING_MODE_LEGACY_SMALL := 1
const RING_MODE_LEGACY_BROAD := 2
const RING_MODE_ADVANCED := 3

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
var _appearance_type_option: OptionButton
var _art_preset_option: OptionButton
var _band_count_spin: SpinBox
var _band_contrast_slider: HSlider
var _banded_controls: VBoxContainer
var _auto_polar_check: CheckButton
var _polar_inclination_spin: SpinBox
var _auto_meridian_check: CheckButton
var _band_meridian_spin: SpinBox
var _turbulence_slider: HSlider
var _turbulence_label: Label
var _ring_mode_option: OptionButton
var _legacy_ring_box: VBoxContainer
var _ring_scale_spin: SpinBox
var _ring_colour_picker: ColorPickerButton
var _advanced_ring_box: VBoxContainer
var _ring_system_inner_spin: SpinBox
var _ring_system_outer_spin: SpinBox
var _ring_brightness_spin: SpinBox
var _ring_shadow_enabled_check: CheckButton
var _ring_shadow_strength_slider: HSlider
var _ring_shadow_softness_spin: SpinBox
var _ring_use_planet_axis_check: CheckButton
var _ring_tilt_spin: SpinBox
var _ring_position_spin: SpinBox
var _band_editor_host: VBoxContainer
var _gap_editor_host: VBoxContainer
var _ring_bands_data: Array = []
var _ring_gaps_data: Array = []
var _band1_picker: ColorPickerButton
var _band2_picker: ColorPickerButton
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
	panel.offset_right = 500.0
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

	_appearance_type_option = OptionButton.new()
	_appearance_type_option.add_item("banded", 0)
	_appearance_type_option.item_selected.connect(_on_appearance_type_changed)
	vbox.add_child(_labeled_row("Appearance type", _appearance_type_option))

	_art_preset_option = OptionButton.new()
	_art_preset_option.add_item("Custom", 0)
	var preset_index := 1
	for preset_id in SkyParentBodyParams.PRESETS.keys():
		_art_preset_option.add_item(str(preset_id), preset_index)
		preset_index += 1
	_art_preset_option.item_selected.connect(_on_live_tweak_f)
	vbox.add_child(_labeled_row("Atmosphere preset", _art_preset_option))

	_banded_controls = VBoxContainer.new()
	_banded_controls.add_theme_constant_override("separation", 6)
	vbox.add_child(_banded_controls)

	_auto_polar_check = CheckButton.new()
	_auto_polar_check.text = "Polar inclination from seed"
	_auto_polar_check.button_pressed = true
	_auto_polar_check.toggled.connect(_on_polar_auto_toggled)
	_banded_controls.add_child(_auto_polar_check)

	_polar_inclination_spin = _make_spin(0.0, 90.0, 0.5, 30.0)
	_polar_inclination_spin.editable = false
	_polar_inclination_spin.value_changed.connect(_on_live_tweak_f)
	_banded_controls.add_child(_labeled_row("Polar inclination (deg)", _polar_inclination_spin))

	_auto_meridian_check = CheckButton.new()
	_auto_meridian_check.text = "Band meridian from seed"
	_auto_meridian_check.button_pressed = true
	_auto_meridian_check.toggled.connect(_on_meridian_auto_toggled)
	_banded_controls.add_child(_auto_meridian_check)

	_band_meridian_spin = _make_spin(0.0, 360.0, 1.0, 0.0)
	_band_meridian_spin.editable = false
	_band_meridian_spin.value_changed.connect(_on_live_tweak_f)
	_banded_controls.add_child(_labeled_row("Band meridian (deg)", _band_meridian_spin))

	_band1_picker = ColorPickerButton.new()
	_band1_picker.color = Color("#857052")
	_band1_picker.color_changed.connect(_on_live_tweak_color)
	_band_count_spin = _make_spin(4.0, 32.0, 1.0, 12.0)
	_band_count_spin.value_changed.connect(_on_live_tweak_f)
	_banded_controls.add_child(_labeled_row("Band count", _band_count_spin))

	_band_contrast_slider = HSlider.new()
	_band_contrast_slider.min_value = 0.0
	_band_contrast_slider.max_value = 1.0
	_band_contrast_slider.step = 0.01
	_band_contrast_slider.value = 0.55
	_band_contrast_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_band_contrast_slider.value_changed.connect(_on_live_tweak_f)
	_banded_controls.add_child(_labeled_row("Band contrast", _band_contrast_slider))

	_banded_controls.add_child(_labeled_row("Band colour 1", _band1_picker))

	_band2_picker = ColorPickerButton.new()
	_band2_picker.color = Color("#c7ae85")
	_band2_picker.color_changed.connect(_on_live_tweak_color)
	_banded_controls.add_child(_labeled_row("Band colour 2", _band2_picker))

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
	_banded_controls.add_child(turb_row)

	var ring_title := Label.new()
	ring_title.text = "Rings"
	ring_title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(ring_title)

	_ring_mode_option = OptionButton.new()
	_ring_mode_option.add_item("none", RING_MODE_NONE)
	_ring_mode_option.add_item("legacy small", RING_MODE_LEGACY_SMALL)
	_ring_mode_option.add_item("legacy broad", RING_MODE_LEGACY_BROAD)
	_ring_mode_option.add_item("advanced (bands + gaps)", RING_MODE_ADVANCED)
	_ring_mode_option.item_selected.connect(_on_ring_mode_changed)
	vbox.add_child(_labeled_row("Ring mode", _ring_mode_option))

	_legacy_ring_box = VBoxContainer.new()
	_legacy_ring_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_legacy_ring_box)

	_ring_scale_spin = _make_spin(1.05, 2.6, 0.05, 1.4)
	_ring_scale_spin.value_changed.connect(_on_live_tweak_f)
	_legacy_ring_box.add_child(_labeled_row("Outer scale", _ring_scale_spin))

	_ring_colour_picker = ColorPickerButton.new()
	_ring_colour_picker.color = Color("#c7ae85")
	_ring_colour_picker.color_changed.connect(_on_live_tweak_color)
	_legacy_ring_box.add_child(_labeled_row("Colour", _ring_colour_picker))

	_advanced_ring_box = VBoxContainer.new()
	_advanced_ring_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_advanced_ring_box)

	_ring_system_inner_spin = _make_spin(1.0, 3.0, 0.01, 1.12)
	_ring_system_inner_spin.value_changed.connect(_on_live_tweak_f)
	_advanced_ring_box.add_child(_labeled_row("Inner radius", _ring_system_inner_spin))

	_ring_system_outer_spin = _make_spin(1.05, 4.0, 0.01, 2.2)
	_ring_system_outer_spin.value_changed.connect(_on_live_tweak_f)
	_advanced_ring_box.add_child(_labeled_row("Outer radius", _ring_system_outer_spin))

	_ring_brightness_spin = _make_spin(0.0, 2.0, 0.05, 1.0)
	_ring_brightness_spin.value_changed.connect(_on_live_tweak_f)
	_advanced_ring_box.add_child(_labeled_row("Brightness", _ring_brightness_spin))

	_ring_shadow_enabled_check = CheckButton.new()
	_ring_shadow_enabled_check.text = "Planet shadow on rings"
	_ring_shadow_enabled_check.button_pressed = true
	_ring_shadow_enabled_check.toggled.connect(func(_enabled: bool) -> void: _on_live_tweak_f())
	_advanced_ring_box.add_child(_ring_shadow_enabled_check)

	_ring_shadow_strength_slider = HSlider.new()
	_ring_shadow_strength_slider.min_value = 0.0
	_ring_shadow_strength_slider.max_value = 1.0
	_ring_shadow_strength_slider.step = 0.01
	_ring_shadow_strength_slider.value = 0.5
	_ring_shadow_strength_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ring_shadow_strength_slider.value_changed.connect(_on_live_tweak_f)
	_advanced_ring_box.add_child(_labeled_row("Shadow strength", _ring_shadow_strength_slider))

	_ring_shadow_softness_spin = _make_spin(0.0, 0.2, 0.005, 0.03)
	_ring_shadow_softness_spin.value_changed.connect(_on_live_tweak_f)
	_advanced_ring_box.add_child(_labeled_row("Shadow softness", _ring_shadow_softness_spin))

	_ring_use_planet_axis_check = CheckButton.new()
	_ring_use_planet_axis_check.text = "Ring plane = planet equator"
	_ring_use_planet_axis_check.button_pressed = true
	_ring_use_planet_axis_check.toggled.connect(_on_ring_axis_override_toggled)
	_advanced_ring_box.add_child(_ring_use_planet_axis_check)

	_ring_tilt_spin = _make_spin(0.0, 90.0, 0.5, 0.0)
	_ring_tilt_spin.editable = false
	_ring_tilt_spin.value_changed.connect(_on_live_tweak_f)
	_advanced_ring_box.add_child(_labeled_row("Ring tilt (deg)", _ring_tilt_spin))

	_ring_position_spin = _make_spin(0.0, 360.0, 1.0, 0.0)
	_ring_position_spin.editable = false
	_ring_position_spin.value_changed.connect(_on_live_tweak_f)
	_advanced_ring_box.add_child(_labeled_row("Ring position (deg)", _ring_position_spin))

	var band_btn_row := HBoxContainer.new()
	var add_band_btn := Button.new()
	add_band_btn.text = "Add band"
	add_band_btn.pressed.connect(_on_add_ring_band)
	band_btn_row.add_child(add_band_btn)
	var remove_band_btn := Button.new()
	remove_band_btn.text = "Remove last band"
	remove_band_btn.pressed.connect(_on_remove_ring_band)
	band_btn_row.add_child(remove_band_btn)
	_advanced_ring_box.add_child(band_btn_row)

	_band_editor_host = VBoxContainer.new()
	_band_editor_host.add_theme_constant_override("separation", 8)
	_advanced_ring_box.add_child(_band_editor_host)

	var gap_btn_row := HBoxContainer.new()
	var add_gap_btn := Button.new()
	add_gap_btn.text = "Add gap"
	add_gap_btn.pressed.connect(_on_add_ring_gap)
	gap_btn_row.add_child(add_gap_btn)
	var remove_gap_btn := Button.new()
	remove_gap_btn.text = "Remove last gap"
	remove_gap_btn.pressed.connect(_on_remove_ring_gap)
	gap_btn_row.add_child(remove_gap_btn)
	_advanced_ring_box.add_child(gap_btn_row)

	_gap_editor_host = VBoxContainer.new()
	_gap_editor_host.add_theme_constant_override("separation", 8)
	_advanced_ring_box.add_child(_gap_editor_host)

	_ring_bands_data = [_default_ring_band(1.15, 1.35, "#8d7964"), _default_ring_band(1.4, 1.9, "#c7b69c")]
	_ring_gaps_data = [_default_ring_gap(1.35, 1.4, 0.05)]
	_refresh_ring_editors()
	_on_ring_mode_changed(_ring_mode_option.selected)
	_on_ring_axis_override_toggled(_ring_use_planet_axis_check.button_pressed)

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
		_select_appearance_type(str(appearance.get("type", "banded")))
		_band1_picker.color = Color(str(appearance.get("band_colour_1", "#ffffff")))
		_band2_picker.color = Color(str(appearance.get("band_colour_2", "#ffffff")))
		_turbulence_slider.value = float(appearance.get("turbulence", 0.0))
		var has_polar := appearance.has("polar_inclination_deg") or appearance.has("orbital_inclination_deg")
		_auto_polar_check.button_pressed = not has_polar
		if appearance.has("polar_inclination_deg"):
			_polar_inclination_spin.value = float(appearance.get("polar_inclination_deg", 0.0))
		elif appearance.has("orbital_inclination_deg"):
			_polar_inclination_spin.value = float(appearance.get("orbital_inclination_deg", 0.0))
		_auto_meridian_check.button_pressed = not appearance.has("band_meridian_deg")
		if appearance.has("band_meridian_deg"):
			_band_meridian_spin.value = float(appearance.get("band_meridian_deg", 0.0))
		_sync_seed_derived_angles()
	_load_rings_from_catalog(parent.get("rings", {}))
	var angular_min := float(parent.get("angular_diameter_deg_min", 14.0))
	var angular_max := float(parent.get("angular_diameter_deg_max", angular_min))
	_angular_spin.value = (angular_min + angular_max) * 0.5
	_on_ring_mode_changed(_ring_mode_option.selected)
	_update_json_display()


func _select_appearance_type(type_id: String) -> void:
	if type_id == "banded":
		_appearance_type_option.select(0)
	_on_appearance_type_changed(_appearance_type_option.selected)


func _on_appearance_type_changed(_index: int) -> void:
	var is_banded := _current_appearance_type() == "banded"
	_banded_controls.visible = is_banded
	_queue_rebuild()


func _current_appearance_type() -> String:
	match _appearance_type_option.get_item_id(_appearance_type_option.selected):
		0:
			return "banded"
		_:
			return "banded"


func _seed_key_text() -> String:
	var seed_key := _seed_edit.text.strip_edges()
	if seed_key.is_empty():
		return "harness"
	return seed_key


func _sync_seed_derived_angles() -> void:
	var seed_text := _seed_key_text()
	var seed_val := SkyParentBodyParams.seed_value(seed_text)
	if _auto_polar_check.button_pressed:
		var incl_rad := SkyParentBodyParams.default_axis_inclination_rad(seed_val)
		_polar_inclination_spin.set_value_no_signal(rad_to_deg(incl_rad))
	if _auto_meridian_check.button_pressed:
		var mer_rad := SkyParentBodyParams.default_axis_position_rad(seed_text)
		_band_meridian_spin.set_value_no_signal(rad_to_deg(mer_rad))


func _on_polar_auto_toggled(enabled: bool) -> void:
	_polar_inclination_spin.editable = not enabled
	_sync_seed_derived_angles()
	_on_live_tweak_f()


func _on_meridian_auto_toggled(enabled: bool) -> void:
	_band_meridian_spin.editable = not enabled
	_sync_seed_derived_angles()
	_on_live_tweak_f()


func _on_ring_mode_changed(_index: int) -> void:
	var mode := _current_ring_mode()
	var is_legacy := mode == RING_MODE_LEGACY_SMALL or mode == RING_MODE_LEGACY_BROAD
	_legacy_ring_box.visible = is_legacy
	_advanced_ring_box.visible = mode == RING_MODE_ADVANCED
	if mode == RING_MODE_LEGACY_SMALL:
		_ring_scale_spin.min_value = 1.05
		_ring_scale_spin.max_value = 1.8
	elif mode == RING_MODE_LEGACY_BROAD:
		_ring_scale_spin.min_value = 1.8
		_ring_scale_spin.max_value = 2.6
	_queue_rebuild()


func _on_ring_axis_override_toggled(_enabled: bool) -> void:
	var locked := _ring_use_planet_axis_check.button_pressed
	_ring_tilt_spin.editable = not locked
	_ring_position_spin.editable = not locked
	_queue_rebuild()


func _on_turbulence_changed(value: float) -> void:
	_turbulence_label.text = "%.2f" % value
	_queue_rebuild()


func _on_live_tweak(_unused: String = "") -> void:
	_preset_option.select(0)
	_sync_seed_derived_angles()
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


func _current_ring_mode() -> int:
	return _ring_mode_option.get_item_id(_ring_mode_option.selected)


func _build_appearance_dict() -> Dictionary:
	var appearance_type := _current_appearance_type()
	var row := {"type": appearance_type}
	if appearance_type != "banded" and appearance_type != "gas_giant":
		return row
	if _art_preset_option.selected > 0:
		row["preset"] = _art_preset_option.get_item_text(_art_preset_option.selected)
	row["band_colour_1"] = _color_to_hex(_band1_picker.color)
	row["band_colour_2"] = _color_to_hex(_band2_picker.color)
	row["turbulence"] = snappedf(float(_turbulence_slider.value), 0.01)
	var atmosphere := {
		"colours": [row["band_colour_1"], row["band_colour_2"]],
		"band_count": int(_band_count_spin.value),
		"band_contrast": snappedf(float(_band_contrast_slider.value), 0.01),
		"band_turbulence": snappedf(float(_turbulence_slider.value), 0.01),
	}
	row["atmosphere"] = atmosphere
	var orientation := {}
	if not _auto_polar_check.button_pressed:
		orientation["axis_inclination_deg"] = snappedf(float(_polar_inclination_spin.value), 0.1)
	if not _auto_meridian_check.button_pressed:
		orientation["axis_position_angle_deg"] = snappedf(float(_band_meridian_spin.value), 0.1)
	if not orientation.is_empty():
		row["orientation"] = orientation
	if not _auto_polar_check.button_pressed:
		row["polar_inclination_deg"] = snappedf(float(_polar_inclination_spin.value), 0.1)
	if not _auto_meridian_check.button_pressed:
		row["band_meridian_deg"] = snappedf(float(_band_meridian_spin.value), 0.1)
	return row


func _build_rings_dict() -> Dictionary:
	var mode := _current_ring_mode()
	if mode == RING_MODE_NONE:
		return {"type": "none"}
	if mode == RING_MODE_LEGACY_SMALL:
		return {
			"type": "small",
			"outer_scale": snappedf(float(_ring_scale_spin.value), 0.01),
			"colour": _color_to_hex(_ring_colour_picker.color),
		}
	if mode == RING_MODE_LEGACY_BROAD:
		return {
			"type": "broad",
			"outer_scale": snappedf(float(_ring_scale_spin.value), 0.01),
			"colour": _color_to_hex(_ring_colour_picker.color),
		}
	var bands := _collect_ring_bands_from_ui()
	if bands.is_empty():
		return {"type": "none"}
	var row := {
		"enabled": true,
		"inner_radius": snappedf(float(_ring_system_inner_spin.value), 0.01),
		"outer_radius": snappedf(float(_ring_system_outer_spin.value), 0.01),
		"brightness": snappedf(float(_ring_brightness_spin.value), 0.01),
		"shadow_enabled": _ring_shadow_enabled_check.button_pressed,
		"shadow_strength": snappedf(float(_ring_shadow_strength_slider.value), 0.01),
		"shadow_softness": snappedf(float(_ring_shadow_softness_spin.value), 0.01),
		"bands": bands,
		"gaps": _collect_ring_gaps_from_ui(),
	}
	if not _ring_use_planet_axis_check.button_pressed:
		row["orientation"] = {
			"ring_tilt_deg": snappedf(float(_ring_tilt_spin.value), 0.1),
			"position_angle_deg": snappedf(float(_ring_position_spin.value), 0.1),
		}
	return row


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
	var parent_data := _build_parent_data()
	var seed_key := _seed_key_text()
	var resolved := SkyParentBodyParams.resolve_from_parent(parent_data, seed_key)
	var block := {
		"appearance": resolved.get("appearance", parent_data.get("appearance", {})),
		"rings": _build_rings_dict(),
	}
	_json_output.text = JSON.stringify(block, "\t")
	if resolved.is_empty():
		_status_label.text = "Current parameters do not pass catalog validation."
	else:
		_status_label.text = "Valid · scan label: %s" % str(resolved.get("type_label", ""))


func _rebuild_preview() -> void:
	_rebuild_queued = false
	_sync_seed_derived_angles()
	_update_json_display()
	for child in _world.get_children():
		child.free()

	var parent_data := _build_parent_data()
	var seed_key := _seed_key_text()
	var resolved := SkyParentBodyParams.resolve_from_parent(parent_data, seed_key)
	if resolved.is_empty():
		return

	var distance := float(_star_distance_spin.value)
	var star_angle := deg_to_rad(float(_star_angle_spin.value))
	var parent_angle := deg_to_rad(float(_parent_angle_spin.value))
	var star_pos := Vector2.from_angle(star_angle) * distance
	var parent_pos := Vector2.from_angle(parent_angle) * distance
	var angular_deg := float(_angular_spin.value)

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
		resolved,
		seed_key
	)


func _match_ring_to_band2() -> void:
	_ring_colour_picker.color = _band2_picker.color
	if not _ring_bands_data.is_empty():
		_ring_bands_data[0]["colour"] = _color_to_hex(_band2_picker.color)
		_refresh_ring_editors()
	_queue_rebuild()


func _default_ring_band(inner: float, outer: float, colour_hex: String) -> Dictionary:
	return {
		"inner_radius": inner,
		"outer_radius": outer,
		"colour": colour_hex,
		"opacity": 0.85,
		"density": 0.75,
		"brightness": 1.0,
		"noise_strength": 0.15,
		"noise_scale": 8.0,
		"edge_softness": 0.02,
	}


func _default_ring_gap(inner: float, outer: float, opacity_mult: float) -> Dictionary:
	return {
		"inner_radius": inner,
		"outer_radius": outer,
		"opacity_multiplier": opacity_mult,
	}


func _load_rings_from_catalog(rings_raw: Variant) -> void:
	if typeof(rings_raw) != TYPE_DICTIONARY:
		_select_ring_mode(RING_MODE_NONE)
		return
	var rings: Dictionary = rings_raw
	if rings.has("type"):
		var ring_type := str(rings.get("type", "none"))
		if ring_type == "small":
			_select_ring_mode(RING_MODE_LEGACY_SMALL)
			_ring_scale_spin.value = float(rings.get("outer_scale", 1.4))
			_ring_colour_picker.color = Color(str(rings.get("colour", "#c7ae85")))
		elif ring_type == "broad":
			_select_ring_mode(RING_MODE_LEGACY_BROAD)
			_ring_scale_spin.value = float(rings.get("outer_scale", 2.2))
			_ring_colour_picker.color = Color(str(rings.get("colour", "#c7ae85")))
		else:
			_select_ring_mode(RING_MODE_NONE)
		return
	if bool(rings.get("enabled", false)) and typeof(rings.get("bands")) == TYPE_ARRAY:
		_select_ring_mode(RING_MODE_ADVANCED)
		_ring_system_inner_spin.set_value_no_signal(float(rings.get("inner_radius", 1.12)))
		_ring_system_outer_spin.set_value_no_signal(float(rings.get("outer_radius", 2.2)))
		_ring_brightness_spin.set_value_no_signal(float(rings.get("brightness", 1.0)))
		_ring_shadow_enabled_check.button_pressed = bool(rings.get("shadow_enabled", true))
		_ring_shadow_strength_slider.value = float(rings.get("shadow_strength", 0.5))
		_ring_shadow_softness_spin.set_value_no_signal(float(rings.get("shadow_softness", 0.03)))
		var orient: Dictionary = rings.get("orientation", {})
		if typeof(orient) == TYPE_DICTIONARY and (
			orient.has("ring_tilt_deg") or orient.has("position_angle_deg")
		):
			_ring_use_planet_axis_check.button_pressed = false
			_ring_tilt_spin.value = float(orient.get("ring_tilt_deg", 0.0))
			_ring_position_spin.value = float(orient.get("position_angle_deg", 0.0))
		else:
			_ring_use_planet_axis_check.button_pressed = true
		_ring_bands_data.clear()
		for band_variant in rings.get("bands", []):
			if typeof(band_variant) == TYPE_DICTIONARY:
				_ring_bands_data.append(band_variant.duplicate(true))
		_ring_gaps_data.clear()
		if typeof(rings.get("gaps")) == TYPE_ARRAY:
			for gap_variant in rings.get("gaps", []):
				if typeof(gap_variant) == TYPE_DICTIONARY:
					_ring_gaps_data.append(gap_variant.duplicate(true))
		_refresh_ring_editors()
		return
	_select_ring_mode(RING_MODE_NONE)


func _select_ring_mode(mode: int) -> void:
	for i in _ring_mode_option.item_count:
		if _ring_mode_option.get_item_id(i) == mode:
			_ring_mode_option.select(i)
			break


func _on_add_ring_band() -> void:
	if _ring_bands_data.size() >= MAX_RING_BANDS:
		return
	var last_outer := 1.9
	if not _ring_bands_data.is_empty():
		last_outer = float(_ring_bands_data[-1].get("outer_radius", 1.9))
	_ring_bands_data.append(_default_ring_band(last_outer + 0.05, last_outer + 0.45, "#a18e78"))
	_refresh_ring_editors()
	_on_live_tweak_f()


func _on_remove_ring_band() -> void:
	if _ring_bands_data.is_empty():
		return
	_ring_bands_data.pop_back()
	_refresh_ring_editors()
	_on_live_tweak_f()


func _on_add_ring_gap() -> void:
	if _ring_gaps_data.size() >= MAX_RING_GAPS:
		return
	_ring_gaps_data.append(_default_ring_gap(1.9, 2.0, 0.0))
	_refresh_ring_editors()
	_on_live_tweak_f()


func _on_remove_ring_gap() -> void:
	if _ring_gaps_data.is_empty():
		return
	_ring_gaps_data.pop_back()
	_refresh_ring_editors()
	_on_live_tweak_f()


func _refresh_ring_editors() -> void:
	for child in _band_editor_host.get_children():
		child.queue_free()
	for child in _gap_editor_host.get_children():
		child.queue_free()
	for i in _ring_bands_data.size():
		_band_editor_host.add_child(_build_band_editor(i))
	for i in _ring_gaps_data.size():
		_gap_editor_host.add_child(_build_gap_editor(i))


func _build_band_editor(index: int) -> PanelContainer:
	var band: Dictionary = _ring_bands_data[index]
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	var caption := Label.new()
	caption.text = "Band %d" % (index + 1)
	box.add_child(caption)
	box.add_child(_bind_band_spin(index, "inner_radius", "Inner", 1.0, 4.0, 0.01))
	box.add_child(_bind_band_spin(index, "outer_radius", "Outer", 1.0, 4.0, 0.01))
	box.add_child(_bind_band_spin(index, "opacity", "Opacity", 0.0, 1.0, 0.01))
	box.add_child(_bind_band_spin(index, "density", "Density", 0.0, 1.0, 0.01))
	box.add_child(_bind_band_spin(index, "brightness", "Brightness", 0.0, 2.0, 0.05))
	box.add_child(_bind_band_spin(index, "noise_strength", "Noise", 0.0, 1.0, 0.01))
	box.add_child(_bind_band_spin(index, "noise_scale", "Noise scale", 1.0, 24.0, 0.5))
	box.add_child(_bind_band_spin(index, "edge_softness", "Edge soft", 0.0, 0.2, 0.005))
	var colour_row := HBoxContainer.new()
	var colour_label := Label.new()
	colour_label.text = "Colour"
	colour_label.custom_minimum_size.x = 120.0
	colour_row.add_child(colour_label)
	var picker := ColorPickerButton.new()
	picker.color = Color(str(band.get("colour", "#ffffff")))
	picker.color_changed.connect(_on_band_colour_changed.bind(index))
	colour_row.add_child(picker)
	box.add_child(colour_row)
	return panel


func _build_gap_editor(index: int) -> PanelContainer:
	var gap: Dictionary = _ring_gaps_data[index]
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	var caption := Label.new()
	caption.text = "Gap %d" % (index + 1)
	box.add_child(caption)
	box.add_child(_bind_gap_spin(index, "inner_radius", "Inner", 1.0, 4.0, 0.01))
	box.add_child(_bind_gap_spin(index, "outer_radius", "Outer", 1.0, 4.0, 0.01))
	box.add_child(_bind_gap_spin(index, "opacity_multiplier", "Opacity mult", 0.0, 1.0, 0.01))
	return panel


func _bind_band_spin(index: int, key: String, caption: String, min_v: float, max_v: float, step: float) -> HBoxContainer:
	var band: Dictionary = _ring_bands_data[index]
	var spin := _make_spin(min_v, max_v, step, float(band.get(key, min_v)))
	spin.value_changed.connect(_on_band_field_changed.bind(index, key))
	return _labeled_row(caption, spin)


func _bind_gap_spin(index: int, key: String, caption: String, min_v: float, max_v: float, step: float) -> HBoxContainer:
	var gap: Dictionary = _ring_gaps_data[index]
	var spin := _make_spin(min_v, max_v, step, float(gap.get(key, min_v)))
	spin.value_changed.connect(_on_gap_field_changed.bind(index, key))
	return _labeled_row(caption, spin)


func _on_band_field_changed(value: float, index: int, key: String) -> void:
	if index < 0 or index >= _ring_bands_data.size():
		return
	_ring_bands_data[index][key] = value
	_on_live_tweak_f()


func _on_gap_field_changed(value: float, index: int, key: String) -> void:
	if index < 0 or index >= _ring_gaps_data.size():
		return
	_ring_gaps_data[index][key] = value
	_on_live_tweak_f()


func _on_band_colour_changed(colour: Color, index: int) -> void:
	if index < 0 or index >= _ring_bands_data.size():
		return
	_ring_bands_data[index]["colour"] = _color_to_hex(colour)
	_on_live_tweak_color(colour)


func _collect_ring_bands_from_ui() -> Array:
	var out: Array = []
	for band_variant in _ring_bands_data:
		if typeof(band_variant) != TYPE_DICTIONARY:
			continue
		var band: Dictionary = band_variant.duplicate(true)
		if float(band.get("outer_radius", 0.0)) <= float(band.get("inner_radius", 0.0)):
			continue
		out.append({
			"inner_radius": snappedf(float(band.get("inner_radius", 1.0)), 0.01),
			"outer_radius": snappedf(float(band.get("outer_radius", 1.2)), 0.01),
			"colour": str(band.get("colour", "#ffffff")),
			"opacity": snappedf(float(band.get("opacity", 0.8)), 0.01),
			"density": snappedf(float(band.get("density", 0.7)), 0.01),
			"brightness": snappedf(float(band.get("brightness", 1.0)), 0.01),
			"noise_strength": snappedf(float(band.get("noise_strength", 0.0)), 0.01),
			"noise_scale": snappedf(float(band.get("noise_scale", 8.0)), 0.01),
			"edge_softness": snappedf(float(band.get("edge_softness", 0.02)), 0.01),
		})
	return out


func _collect_ring_gaps_from_ui() -> Array:
	var out: Array = []
	for gap_variant in _ring_gaps_data:
		if typeof(gap_variant) != TYPE_DICTIONARY:
			continue
		var gap: Dictionary = gap_variant
		if float(gap.get("outer_radius", 0.0)) <= float(gap.get("inner_radius", 0.0)):
			continue
		out.append({
			"inner_radius": snappedf(float(gap.get("inner_radius", 1.0)), 0.01),
			"outer_radius": snappedf(float(gap.get("outer_radius", 1.1)), 0.01),
			"opacity_multiplier": snappedf(float(gap.get("opacity_multiplier", 0.0)), 0.01),
		})
	return out


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
