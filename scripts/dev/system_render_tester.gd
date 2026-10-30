extends Node2D

const CityMallLabelOverlay := preload("res://scripts/ui/city_mall_label_overlay.gd")

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
var _surface_labels: Control
var _sector_tree: Tree
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
	_populate_sector_tree()

	if _starfield.has_method("bind_camera"):
		_starfield.bind_camera(_camera)

	_camera.make_current()
	_camera.zoom = Vector2.ONE * 0.35

	if _sector_ids.is_empty():
		push_error("System render tester: no renderable sectors in catalog.")
		return

	if not _select_sector_in_tree("proxima"):
		_select_first_sector_in_tree()

	_load_selected_sector()
	call_deferred("_scroll_sector_tree_to_top")


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

	_surface_labels = CityMallLabelOverlay.new()
	_surface_labels.name = "CityMallLabelOverlay"
	_surface_labels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.add_child(_surface_labels)

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
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "System render tester"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	_sector_tree = Tree.new()
	_sector_tree.hide_root = true
	_sector_tree.column_titles_visible = false
	_sector_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sector_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sector_tree.item_selected.connect(_on_sector_tree_item_selected)
	vbox.add_child(_sector_tree)

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


func _sector_tree_label(sector: Dictionary) -> String:
	var sector_id := str(sector.get("id", ""))
	var display_name := str(sector.get("planet_name", ""))
	if display_name.is_empty():
		display_name = str(sector.get("name", sector_id))
	var star_label := str(sector.get("star", ""))
	if star_label.is_empty():
		star_label = str(sector.get("star_system", ""))
	if star_label.is_empty():
		return display_name
	return "%s - %s" % [display_name, star_label]


func _populate_sector_tree() -> void:
	_sector_ids.clear()
	_sector_tree.clear()

	var renderable: Dictionary = {}
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
		renderable[sector_id] = _sector_tree_label(sector)

	var hub_ids: Array[String] = []
	var beacons_by_hub: Dictionary = {}
	var orphan_ids: Array[String] = []

	for sector_id_variant in renderable.keys():
		var sector_id := str(sector_id_variant)
		var world_data := catalog.get_world(sector_id)
		if world_data.has("jump_gate"):
			hub_ids.append(sector_id)
			continue
		var beacon: Variant = world_data.get("translation_beacon", {})
		if typeof(beacon) == TYPE_DICTIONARY and not beacon.is_empty():
			var hub_id := str(beacon.get("destination", ""))
			if not beacons_by_hub.has(hub_id):
				beacons_by_hub[hub_id] = []
			(beacons_by_hub[hub_id] as Array).append(sector_id)
		else:
			orphan_ids.append(sector_id)

	hub_ids.sort_custom(func(a: String, b: String) -> bool:
		return str(renderable.get(a, a)) < str(renderable.get(b, b))
	)

	for hub_id in hub_ids:
		var hub_item := _sector_tree.create_item()
		hub_item.set_text(0, str(renderable.get(hub_id, hub_id)))
		hub_item.set_metadata(0, hub_id)
		_sector_ids.append(hub_id)

		var beacon_ids: Array = beacons_by_hub.get(hub_id, [])
		beacon_ids.sort_custom(func(a: String, b: String) -> bool:
			return str(renderable.get(a, a)) < str(renderable.get(b, b))
		)
		for beacon_id_variant in beacon_ids:
			var beacon_id := str(beacon_id_variant)
			if not renderable.has(beacon_id):
				continue
			var beacon_item := _sector_tree.create_item(hub_item)
			beacon_item.set_text(0, str(renderable.get(beacon_id, beacon_id)))
			beacon_item.set_metadata(0, beacon_id)
			_sector_ids.append(beacon_id)

		hub_item.set_collapsed(false)

	orphan_ids.sort_custom(func(a: String, b: String) -> bool:
		return str(renderable.get(a, a)) < str(renderable.get(b, b))
	)
	for orphan_id in orphan_ids:
		var orphan_item := _sector_tree.create_item()
		orphan_item.set_text(0, str(renderable.get(orphan_id, orphan_id)))
		orphan_item.set_metadata(0, orphan_id)
		_sector_ids.append(orphan_id)


func _select_sector_in_tree(sector_id: String) -> bool:
	var item := _find_tree_item_by_sector_id(sector_id)
	if item == null:
		return false
	item.select(0)
	return true


func _select_first_sector_in_tree() -> void:
	var root := _sector_tree.get_root()
	if root == null:
		return
	var first := root.get_first_child()
	if first != null:
		first.select(0)


func _scroll_sector_tree_to_top() -> void:
	var bar := _sector_tree.get_v_scroll_bar()
	if bar != null:
		bar.value = bar.min_value


func _find_tree_item_by_sector_id(sector_id: String) -> TreeItem:
	var root := _sector_tree.get_root()
	if root == null:
		return null
	var item := root.get_first_child()
	while item != null:
		var found := _find_tree_item_in_subtree(item, sector_id)
		if found != null:
			return found
		item = item.get_next()
	return null


func _find_tree_item_in_subtree(item: TreeItem, sector_id: String) -> TreeItem:
	if str(item.get_metadata(0)) == sector_id:
		return item
	var child := item.get_first_child()
	while child != null:
		var found := _find_tree_item_in_subtree(child, sector_id)
		if found != null:
			return found
		child = child.get_next()
	return null


## Headless smoke teardown before the tester node is freed.
func smoke_unload() -> void:
	_loader.clear_world(_world)


func _load_selected_sector() -> void:
	var item := _sector_tree.get_selected()
	if item == null:
		return
	var sector_id := str(item.get_metadata(0))
	if sector_id.is_empty():
		return
	session.sector_id = sector_id
	var sector := catalog.get_sector_def(sector_id)
	if sector != null and sector.has_source_key("orbit_name") and not sector.orbit_name.is_empty():
		session.location_name = sector.orbit_name
	else:
		session.location_name = sector_id

	_loader.load_sector(_world, catalog, session, sector_id)
	_apply_planet_auto_spin()
	_refresh_surface_labels()
	_frame_view()


func _get_planet_node() -> Node:
	return _loader.spawned_by_id.get("planet", null)


func _apply_planet_auto_spin() -> void:
	var planet := _get_planet_node()
	if planet != null and planet.has_method("set_auto_spin_enabled"):
		planet.call("set_auto_spin_enabled", _auto_spin_check.button_pressed)


func _on_sector_tree_item_selected() -> void:
	_load_selected_sector()


func _on_auto_spin_toggled(enabled: bool) -> void:
	var planet := _get_planet_node()
	if planet != null and planet.has_method("set_auto_spin_enabled"):
		planet.call("set_auto_spin_enabled", enabled)


func _process(delta: float) -> void:
	if session != null and catalog != null:
		session.advance_orbital_phase(catalog, delta)
	_refresh_surface_labels()


func _refresh_surface_labels() -> void:
	if _surface_labels == null or not _surface_labels.has_method("set_overlay_state"):
		return
	_surface_labels.set_overlay_state(_loader.get_surface_labels(), _camera)


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
