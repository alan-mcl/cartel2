extends Node2D

const LocalStarScript := preload("res://scripts/presentation/local_star.gd")
const SkyBackdropLayout := preload("res://scripts/presentation/sky_backdrop_layout.gd")

const ZOOM_MIN := 0.002
const ZOOM_MAX := 8.0
const ZOOM_WHEEL_FACTOR := 1.12
const SKY_RADIUS := 8000.0
const DEFAULT_STAR := "Alpha Centauri A"

@onready var _starfield: Node2D = $Starfield
@onready var _world: Node2D = $World
@onready var _camera: Camera2D = $Camera2D
@onready var _overlay_layer: CanvasLayer = $Overlay

var catalog: Catalog
var _all_star_names: Array[String] = []
var _filtered_names: Array[String] = []

var _overlay_root: Control
var _panel: PanelContainer
var _filter_edit: LineEdit
var _star_list: ItemList
var _distance_spin: SpinBox
var _companions_check: CheckButton
var _world_layout_check: CheckButton
var _status_label: Label
var _frame_button: Button

var _selected_star: String = DEFAULT_STAR
var _panning: bool = false
var _last_pointer: Vector2 = Vector2.ZERO
var _rebuild_queued: bool = false
var _spawn_layout: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	catalog = Catalog.load_default()
	_collect_star_names()
	_build_overlay()
	if _starfield.has_method("bind_camera"):
		_starfield.bind_camera(_camera)
	_camera.make_current()
	_camera.position = Vector2.ZERO
	_apply_filter("")
	_select_star_in_list(DEFAULT_STAR)
	call_deferred("_rebuild_stars")
	call_deferred("_frame_view")


func _collect_star_names() -> void:
	_all_star_names.clear()
	for name_variant in catalog.list_star_names_outside_system(""):
		_all_star_names.append(str(name_variant))


func _build_overlay() -> void:
	_overlay_root = Control.new()
	_overlay_root.name = "Root"
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_overlay_root)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_right = 360.0
	_panel.offset_bottom = 520.0
	_overlay_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Star rendering harness"
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "LMB pan on sky · wheel zoom · F frame (sky only; wheel over panel scrolls the list)"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "Filter catalog stars…"
	_filter_edit.text_changed.connect(_on_filter_changed)
	vbox.add_child(_filter_edit)

	_star_list = ItemList.new()
	_star_list.custom_minimum_size = Vector2(320, 280)
	_star_list.item_selected.connect(_on_star_selected)
	vbox.add_child(_star_list)

	_distance_spin = _labeled_spin(vbox, "Distance (AU)", 0.01, 500.0, 1.0, 0.01)
	_distance_spin.focus_mode = Control.FOCUS_CLICK
	_distance_spin.value_changed.connect(func(_v: float) -> void: _queue_rebuild())

	_companions_check = CheckButton.new()
	_companions_check.text = "Include companions"
	_companions_check.button_pressed = true
	_companions_check.toggled.connect(_queue_rebuild)
	vbox.add_child(_companions_check)

	_world_layout_check = CheckButton.new()
	_world_layout_check.text = "Prefer world companion_stars layout"
	_world_layout_check.button_pressed = true
	_world_layout_check.toggled.connect(_queue_rebuild)
	vbox.add_child(_world_layout_check)

	_frame_button = Button.new()
	_frame_button.text = "Frame (F)"
	_frame_button.pressed.connect(_frame_view)
	vbox.add_child(_frame_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)


func _labeled_spin(
	parent: Control,
	label_text: String,
	min_v: float,
	max_v: float,
	default_v: float,
	step: float
) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 120.0
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = default_v
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	parent.add_child(row)
	return spin


func _on_filter_changed(text: String) -> void:
	_apply_filter(text)


func _apply_filter(text: String) -> void:
	var needle := text.strip_edges().to_lower()
	_filtered_names.clear()
	for star_name in _all_star_names:
		if needle.is_empty() or star_name.to_lower().contains(needle):
			_filtered_names.append(star_name)
	_star_list.clear()
	for star_name in _filtered_names:
		_star_list.add_item(star_name)


func _select_star_in_list(star_name: String) -> void:
	for idx in _filtered_names.size():
		if _filtered_names[idx] == star_name:
			_star_list.select(idx)
			_selected_star = star_name
			return
	_selected_star = star_name


func _on_star_selected(index: int) -> void:
	if index < 0 or index >= _filtered_names.size():
		return
	_selected_star = _filtered_names[index]
	_queue_rebuild()


func _queue_rebuild(_unused: Variant = null) -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_rebuild_stars")


func _rebuild_stars() -> void:
	_rebuild_queued = false
	_spawn_layout.clear()
	for child in _world.get_children():
		child.free()

	var primary_name := _selected_star.strip_edges()
	if primary_name.is_empty():
		_status_label.text = "Select a catalog star."
		return

	var facts := catalog.get_star(primary_name)
	if facts.is_empty():
		_status_label.text = "Unknown star: %s" % primary_name
		return

	var distance_au := float(_distance_spin.value)
	var radius_solar := float(facts.get("radius_solar", 1.0))
	var render_primary := facts.duplicate(true)
	render_primary["name"] = primary_name

	var primary_game_pos := Vector2(SKY_RADIUS, 0.0)
	var center_offset := -primary_game_pos

	var primary := LocalStarScript.new()
	primary.name = "LocalStar"
	_world.add_child(primary)
	var primary_pos := primary_game_pos + center_offset
	primary.configure(render_primary, primary_pos, distance_au, radius_solar)
	_record_spawn_layout(render_primary, primary_pos, distance_au, radius_solar)

	var companion_count := 0
	if _companions_check.button_pressed:
		companion_count = _spawn_companions(
			primary_name,
			primary_game_pos,
			center_offset,
			distance_au
		)

	var resolved := LocalStarScript.defaults_from_star_data(render_primary, distance_au, radius_solar)
	var angular := float(resolved.get("angular_diameter_deg", 0.0))
	var irr := float(resolved.get("irradiance", 0.0))
	_status_label.text = (
		"%s · %s · disc r %.1f · θ %.3f deg · irradiance %.3f · %d companion(s)"
		% [
			primary_name,
			str(facts.get("spectral_class", "")),
			float(resolved.get("disc_radius", 0.0)),
			angular,
			irr,
			companion_count,
		]
	)
	call_deferred("_frame_view")


func _spawn_companions(
	primary_name: String,
	primary_game_pos: Vector2,
	center_offset: Vector2,
	primary_distance_au: float
) -> int:
	var entries := _companion_entries(primary_name)
	var index := 0
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var separation_deg := float(entry.get("separation_deg", 0.0))
		var comp_game_pos := SkyBackdropLayout.companion_world_position(primary_game_pos, separation_deg)
		var world_pos := comp_game_pos + center_offset
		var render_data: Dictionary = {}
		if entry.has("star"):
			var catalog_star_name := str(entry.get("star", "")).strip_edges()
			if catalog_star_name.is_empty():
				continue
			var comp_facts := catalog.get_star(catalog_star_name)
			if comp_facts.is_empty():
				continue
			render_data = comp_facts.duplicate(true)
			render_data["name"] = catalog_star_name
			var comp_au := primary_distance_au
			var entry_au: Variant = entry.get("distance_au", null)
			if typeof(entry_au) == TYPE_FLOAT or typeof(entry_au) == TYPE_INT:
				if float(entry_au) > 0.0:
					comp_au = float(entry_au)
			var comp_radius := float(comp_facts.get("radius_solar", 1.0))
			var companion := LocalStarScript.new()
			companion.name = "CompanionStar%d" % index
			_world.add_child(companion)
			companion.configure(render_data, world_pos, comp_au, comp_radius)
			_record_spawn_layout(render_data, world_pos, comp_au, comp_radius)
		else:
			var contact_name := str(entry.get("name", "")).strip_edges()
			if contact_name.is_empty():
				continue
			render_data = {
				"name": contact_name,
				"temperature_k": float(entry.get("temperature_k", 10000.0)),
				"luminosity": float(entry.get("luminosity", 0.35)),
				"disc_radius": float(entry.get("disc_radius", 3.0)),
			}
			if entry.has("preset"):
				render_data["preset"] = entry.get("preset")
			var companion := LocalStarScript.new()
			companion.name = "CompanionStar%d" % index
			_world.add_child(companion)
			companion.configure(render_data, world_pos, primary_distance_au, 1.0)
			_record_spawn_layout(render_data, world_pos, primary_distance_au, 1.0)
		index += 1
	return index


func _record_spawn_layout(
	render_data: Dictionary,
	world_pos: Vector2,
	distance_au: float,
	radius_solar: float
) -> void:
	var resolved := LocalStarScript.defaults_from_star_data(render_data, distance_au, radius_solar)
	var corona_r := StarAppearance.corona_world_radius(resolved)
	_spawn_layout.append({"position": world_pos, "corona_radius": corona_r})


func _companion_entries(primary_name: String) -> Array:
	if _world_layout_check.button_pressed:
		var from_world := _companion_entries_from_worlds(primary_name)
		if not from_world.is_empty():
			return from_world
	return _companion_entries_from_system(primary_name)


func _companion_entries_from_worlds(primary_name: String) -> Array:
	for sector_row_variant in catalog.list_sectors():
		if typeof(sector_row_variant) != TYPE_DICTIONARY:
			continue
		var sector_row: Dictionary = sector_row_variant
		var sector_id := str(sector_row.get("id", "")).strip_edges()
		if sector_id.is_empty():
			continue
		var sector_star := str(sector_row.get("star", "")).strip_edges()
		if sector_star != primary_name:
			continue
		var world := catalog.get_world(sector_id)
		var companions_raw: Variant = world.get("companion_stars", [])
		if typeof(companions_raw) != TYPE_ARRAY or companions_raw.is_empty():
			continue
		return (companions_raw as Array).duplicate(true)
	return []


func _companion_entries_from_system(primary_name: String) -> Array:
	var facts := catalog.get_star(primary_name)
	var system := str(facts.get("star_system", "")).strip_edges()
	if system.is_empty():
		return []
	var out: Array = []
	var index := 0
	for star_name_variant in catalog.list_star_names_for_system(system):
		var star_name := str(star_name_variant)
		if star_name == primary_name:
			continue
		out.append({"star": star_name, "separation_deg": 35.0 * float(index + 1)})
		index += 1
	return out


func _frame_view() -> void:
	var bounds := _layout_bounds_rect()
	if bounds.size.x < 1.0 or bounds.size.y < 1.0:
		_camera.position = Vector2.ZERO
		_camera.zoom = Vector2.ONE * 0.35
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var usable := viewport_size - Vector2(380.0, 80.0)
	usable.x = maxf(usable.x, 64.0)
	usable.y = maxf(usable.y, 64.0)
	var zoom_level := clampf(
		minf(usable.x / bounds.size.x, usable.y / bounds.size.y),
		ZOOM_MIN,
		ZOOM_MAX
	)
	_camera.zoom = Vector2.ONE * zoom_level
	_camera.position = bounds.get_center()


func _layout_bounds_rect() -> Rect2:
	if _spawn_layout.is_empty():
		return Rect2()
	var min_p: Vector2 = _spawn_layout[0].get("position", Vector2.ZERO)
	var max_p: Vector2 = min_p
	for entry_variant in _spawn_layout:
		var entry: Dictionary = entry_variant
		var pos: Vector2 = entry.get("position", Vector2.ZERO)
		var corona_r := float(entry.get("corona_radius", 120.0))
		min_p = min_p.min(pos - Vector2.ONE * corona_r)
		max_p = max_p.max(pos + Vector2.ONE * corona_r)
	var bounds := Rect2(min_p, max_p - min_p)
	return bounds.grow(120.0)


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
			_pan_camera(-delta_pos)
			get_viewport().set_input_as_handled()


func _pointer_over_overlay() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	return hovered == _overlay_root or _overlay_root.is_ancestor_of(hovered)


func _pan_camera(screen_delta: Vector2) -> void:
	_camera.position += screen_delta / _camera.zoom.x


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
