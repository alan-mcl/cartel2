extends Node2D

const ZOOM_MIN := 0.02
const ZOOM_MAX := 4.0
const ZOOM_WHEEL_FACTOR := 1.12
const GLOBE_DRAG_SENSITIVITY := 0.005

@onready var _starfield: Node2D = $Starfield
@onready var _world: Node2D = $World
@onready var _camera: Camera2D = $Camera2D
@onready var _overlay_layer: CanvasLayer = $Overlay

var catalog: Catalog
var session: GameSession
var _loader := WorldLoader.new()
var _sector_ids: Array[String] = []

var _overlay_root: Control
var _sector_option: OptionButton
var _auto_spin_check: CheckButton
var _frame_button: Button

var _panning: bool = false
var _globe_dragging: bool = false
var _last_pointer: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	catalog = Catalog.load_default()
	session = _build_session()
	_build_overlay()
	_populate_sector_options()

	if _starfield.has_method("bind_camera"):
		_starfield.bind_camera(_camera)

	_camera.make_current()
	_camera.zoom = Vector2.ONE * 0.35

	if _sector_ids.is_empty():
		push_error("System render tester: no renderable sectors in catalog.")
		return

	var default_idx := _sector_ids.find("proxima")
	if default_idx >= 0:
		_sector_option.selected = default_idx

	_load_selected_sector()


func _build_session() -> GameSession:
	var new_session := GameSession.new()
	new_session.sandbox = true
	new_session.docked = false
	new_session.in_unspace = false
	new_session.callsign = "RENDER"
	new_session.last_log = "System render tester ready."
	return new_session


func _build_overlay() -> void:
	_overlay_root = Control.new()
	_overlay_root.name = "Root"
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_overlay_root)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12.0
	panel.offset_top = 12.0
	panel.offset_right = 420.0
	panel.offset_bottom = 148.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "System render tester"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	_sector_option = OptionButton.new()
	_sector_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sector_option.item_selected.connect(_on_sector_selected)
	vbox.add_child(_sector_option)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)

	_auto_spin_check = CheckButton.new()
	_auto_spin_check.text = "Planet auto-spin"
	_auto_spin_check.button_pressed = true
	_auto_spin_check.toggled.connect(_on_auto_spin_toggled)
	row.add_child(_auto_spin_check)

	_frame_button = Button.new()
	_frame_button.text = "Frame (F)"
	_frame_button.pressed.connect(_frame_view)
	row.add_child(_frame_button)

	var hint := Label.new()
	hint.text = "LMB drag: pan · Wheel: zoom · RMB drag: spin globe · F: frame"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hint)


func _populate_sector_options() -> void:
	_sector_ids.clear()
	_sector_option.clear()

	var entries: Array = []
	for sector_variant in catalog.list_sectors():
		if typeof(sector_variant) != TYPE_DICTIONARY:
			continue
		var sector: Dictionary = sector_variant
		var sector_id := str(sector.get("id", ""))
		if sector_id.is_empty():
			continue
		var world_data := catalog.get_world(sector_id)
		if world_data.is_empty():
			continue
		if not world_data.has("planet") and not world_data.has("orbital_ring"):
			continue
		var display_name := str(sector.get("planet_name", ""))
		if display_name.is_empty():
			display_name = str(sector.get("name", sector_id))
		var star_system := str(sector.get("star_system", ""))
		var label := display_name if star_system.is_empty() else "%s — %s" % [display_name, star_system]
		entries.append({"id": sector_id, "label": label})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("label", "")) < str(b.get("label", ""))
	)

	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var sector_id := str(entry.get("id", ""))
		_sector_ids.append(sector_id)
		_sector_option.add_item(str(entry.get("label", sector_id)))


func _load_selected_sector() -> void:
	if _sector_ids.is_empty():
		return
	var index := clampi(_sector_option.selected, 0, _sector_ids.size() - 1)
	var sector_id := _sector_ids[index]
	session.sector_id = sector_id
	var sector := catalog.get_sector(sector_id)
	session.location_name = str(sector.get("orbit_name", sector_id))

	_loader.load_sector(_world, catalog, session, sector_id)
	_apply_planet_auto_spin()
	_frame_view()


func _get_planet_node() -> Node:
	return _loader.spawned_by_id.get("planet", null)


func _apply_planet_auto_spin() -> void:
	var planet := _get_planet_node()
	if planet != null and planet.has_method("set_auto_spin_enabled"):
		planet.call("set_auto_spin_enabled", _auto_spin_check.button_pressed)


func _on_sector_selected(_index: int) -> void:
	_load_selected_sector()


func _on_auto_spin_toggled(enabled: bool) -> void:
	var planet := _get_planet_node()
	if planet != null and planet.has_method("set_auto_spin_enabled"):
		planet.call("set_auto_spin_enabled", enabled)


func _process(delta: float) -> void:
	if session != null and catalog != null:
		session.advance_orbital_phase(catalog, delta)


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
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_globe_dragging = mb.pressed
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
		elif _globe_dragging:
			_rotate_planet(delta_pos)
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


func _rotate_planet(screen_delta: Vector2) -> void:
	var planet := _get_planet_node()
	if planet == null or not planet.has_method("add_inspection_rotation"):
		return
	planet.call(
		"add_inspection_rotation",
		-screen_delta.x * GLOBE_DRAG_SENSITIVITY,
		screen_delta.y * GLOBE_DRAG_SENSITIVITY
	)


func _frame_view() -> void:
	var bounds := _collect_frame_bounds()
	if bounds.size == Vector2.ZERO:
		_camera.position = Vector2.ZERO
		_camera.zoom = Vector2.ONE * 0.35
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var margin := 80.0
	var usable := viewport_size - Vector2(margin * 2.0, margin * 2.0)
	var zoom_x := usable.x / bounds.size.x
	var zoom_y := usable.y / bounds.size.y
	var zoom_level := clampf(minf(zoom_x, zoom_y), ZOOM_MIN, ZOOM_MAX)
	_camera.zoom = Vector2.ONE * zoom_level
	_camera.position = bounds.get_center()


func _collect_frame_bounds() -> Rect2:
	var points: PackedVector2Array = PackedVector2Array()
	points.append(Vector2.ZERO)

	var content_radius := _loader.get_content_radius()
	if content_radius > 1.0:
		points.append(Vector2(content_radius, 0.0))
		points.append(Vector2(-content_radius, 0.0))
		points.append(Vector2(0.0, content_radius))
		points.append(Vector2(0.0, -content_radius))

	var gate_pos := _loader.get_jump_gate_world_position()
	if gate_pos.length_squared() > 1.0:
		points.append(gate_pos)

	var star_display := _loader.get_local_star_display()
	if not star_display.is_empty():
		var star_pos: Vector2 = star_display.get("world_position", Vector2.ZERO)
		if star_pos.length_squared() > 1.0:
			points.append(star_pos)

	if points.size() < 2:
		return Rect2(Vector2.ZERO, Vector2(4000.0, 4000.0))

	var min_p := points[0]
	var max_p := points[0]
	for i in range(1, points.size()):
		min_p = min_p.min(points[i])
		max_p = max_p.max(points[i])
	return Rect2(min_p, max_p - min_p)
