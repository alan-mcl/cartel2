extends Control

const LOCATION_ART := preload("res://scenes/ui/components/location_art.tscn")

@onready var _title: Label = $Layout/Header/HeaderBox/Title
@onready var _description: Label = $Layout/Header/HeaderBox/Description
@onready var _portrait: TextureRect = $Layout/Header/HeaderBox/PilotRow/Portrait
@onready var _pilot: Label = $Layout/Header/HeaderBox/PilotRow/Pilot
@onready var _credits: Label = $Layout/Header/HeaderBox/Credits
@onready var _gst_clock: Label = $Layout/Header/HeaderBox/GstClockLabel
@onready var _building_item_list: ItemList = $Layout/Body/Split/Left/BuildingItemList
@onready var _building_title: Label = $Layout/Body/Split/Right/BuildingHeader/BuildingInfo/BuildingTitle
@onready var _building_description: Label = $Layout/Body/Split/Right/BuildingHeader/BuildingInfo/BuildingDescription
@onready var _art_host: VBoxContainer = $Layout/Body/Split/Right/BuildingHeader/ArtHost
@onready var _content_pane: Control = $Layout/Body/Split/Right/ContentPane
@onready var _log: Label = $Layout/Body/Split/Right/Log

var _context: UiContext
var _art_frame: PanelContainer
var _building_ids: PackedStringArray = PackedStringArray()
var _suppress_building_select: bool = false
var _embedded_panel: Control = null
var _embedded_panel_type: String = ""


func _ready() -> void:
	$Layout/Footer/SaveButton.pressed.connect(_on_save_pressed)
	$Layout/Footer/MenuButton.pressed.connect(_on_menu_pressed)
	_building_item_list.item_selected.connect(_on_building_item_selected)
	_building_item_list.item_clicked.connect(_on_building_item_clicked)


func bind(context: UiContext) -> void:
	_context = context
	if _context.session != null and not _context.session.changed.is_connected(refresh):
		_context.session.changed.connect(refresh, CONNECT_DEFERRED)
	if _gst_clock != null and _gst_clock.has_method("bind") and _context.session != null:
		_gst_clock.bind(_context.session)
	_refresh_when_ready()


func _refresh_when_ready() -> void:
	if is_node_ready():
		refresh()
	else:
		if not ready.is_connected(refresh):
			ready.connect(refresh, CONNECT_ONE_SHOT)


func refresh() -> void:
	if not is_node_ready() or _context == null or _context.session == null or _context.catalog == null:
		return

	var habitat := _context.session.get_current_habitat(_context.catalog)
	var building := _context.session.get_current_building(_context.catalog)
	if habitat.is_empty():
		return

	_title.text = str(habitat.get("name", "Habitat"))
	var habitat_desc := str(habitat.get("description", habitat.get("short_desc", "")))
	_description.text = habitat_desc
	_pilot.text = 'Pilot: "%s"' % _context.session.callsign
	_update_portrait(_context.session.portrait_path)
	_credits.text = "Credits: d%d" % _context.session.credits
	_log.text = _context.session.last_log

	_rebuild_building_list(habitat)
	_update_building_header(habitat, building)
	_show_building_content(habitat, building)


func handle_back() -> bool:
	if _context != null and _context.stack.get_depth() > 1:
		_context.stack.pop_screen()
		return true
	return false


func _rebuild_building_list(habitat: Dictionary) -> void:
	_building_ids.clear()
	_building_item_list.clear()

	var building_ids: Variant = habitat.get("buildings", [])
	if typeof(building_ids) != TYPE_ARRAY:
		return

	for building_id_variant in building_ids:
		var building_id := str(building_id_variant)
		var building := _context.catalog.get_building(building_id)
		if building.is_empty():
			continue
		_building_ids.append(building_id)
		var index := _building_item_list.add_item(str(building.get("name", building_id)))
		_building_item_list.set_item_tooltip(index, str(building.get("short_desc", "")))

	_select_item_by_id(_building_item_list, _building_ids, _context.session.building_id, "_suppress_building_select")


func _on_building_item_selected(index: int) -> void:
	_select_building_at_index(index)


func _on_building_item_clicked(index: int, _at_position: Vector2, _mouse_button_index: int) -> void:
	_select_building_at_index(index)


func _select_building_at_index(index: int) -> void:
	if _suppress_building_select:
		return
	if index < 0 or index >= _building_ids.size():
		return
	var building_id := _building_ids[index]
	if building_id == _context.session.building_id:
		return
	var was_connected := _context.session.changed.is_connected(refresh)
	if was_connected:
		_context.session.changed.disconnect(refresh)
	var visited := _context.session.visit(_context.catalog, building_id)
	if was_connected and not _context.session.changed.is_connected(refresh):
		_context.session.changed.connect(refresh, CONNECT_DEFERRED)
	if not visited:
		return
	_embedded_panel_type = ""
	_update_building_panels()


func _update_building_panels() -> void:
	if _context == null or _context.session == null or _context.catalog == null:
		return
	var habitat := _context.session.get_current_habitat(_context.catalog)
	var building := _context.session.get_current_building(_context.catalog)
	if habitat.is_empty():
		return
	_log.text = _context.session.last_log
	_select_item_by_id(_building_item_list, _building_ids, _context.session.building_id, "_suppress_building_select")
	_update_building_header(habitat, building)
	_show_building_content(habitat, building)


func _update_building_header(habitat: Dictionary, building: Dictionary) -> void:
	if building.is_empty():
		_building_title.text = ""
		_building_description.text = ""
		return

	_building_title.text = str(building.get("name", ""))
	_building_description.text = _context.catalog.get_building_description(building)

	if _art_frame == null:
		_art_frame = LOCATION_ART.instantiate()
		_art_host.add_child(_art_frame)
	if _art_frame.has_method("configure_header_mode"):
		_art_frame.configure_header_mode(true)

	var art_path := _context.catalog.get_building_art(building)
	var label := str(building.get("name", ""))
	if art_path.is_empty():
		art_path = _context.catalog.get_habitat_art(habitat)
		label = str(habitat.get("name", ""))
	_art_frame.set_art_path(art_path, label)


func _show_building_content(habitat: Dictionary, building: Dictionary) -> void:
	var building_type := _context.catalog.get_building_type(building)
	match BuildingPanelRegistry.mode_for(building_type):
		BuildingPanelRegistry.MODE_EMBED:
			_pop_stacked_shipyard_if_needed()
			_show_embed_panel(building_type, building)
		_:
			_pop_stacked_shipyard_if_needed()
			_clear_embed_panel()
			_log.visible = true
			_show_placeholder_content(building)


func _show_embed_panel(building_type: String, building: Dictionary) -> void:
	_log.visible = building_type != "shipyard"

	var scene_path := BuildingPanelRegistry.embed_scene_path(building_type)
	if scene_path.is_empty():
		return

	if (
		_embedded_panel != null
		and is_instance_valid(_embedded_panel)
		and _embedded_panel_type == building_type
		and _embedded_panel.get_parent() == _content_pane
		and _embedded_panel.get_scene_file_path() == scene_path
	):
		if building_type == "shipyard" and _embedded_panel.has_method("configure_embedded"):
			_embedded_panel.configure_embedded(true)
		if _embedded_panel.has_method("configure"):
			_embedded_panel.configure(building)
		if _embedded_panel.has_method("refresh"):
			_embedded_panel.refresh()
		return

	_clear_embed_panel()

	var scene := BuildingPanelRegistry.embed_scene(building_type)
	if scene == null:
		return

	var panel: Control = scene.instantiate()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content_pane.add_child(panel)
	_embedded_panel = panel
	_embedded_panel_type = building_type

	if panel.has_method("bind"):
		panel.bind(_context)
	if building_type == "shipyard" and panel.has_method("configure_embedded"):
		panel.configure_embedded(true)
	if panel.has_method("configure"):
		panel.configure(building)
	if panel.has_method("refresh"):
		panel.refresh()


func _clear_embed_panel() -> void:
	_embedded_panel = null
	_embedded_panel_type = ""
	for child in _content_pane.get_children():
		child.queue_free()


func _pop_stacked_shipyard_if_needed() -> void:
	if _context == null or _context.stack == null:
		return
	if _context.stack.get_depth() <= 1:
		return
	var top := _context.stack.get_top_screen()
	if top == null or top == self:
		return
	var script: Variant = top.get_script()
	if script != null and str(script.resource_path).ends_with("shipyard_screen.gd"):
		_context.stack.pop_screen()


func _show_placeholder_content(building: Dictionary) -> void:
	_clear_embed_panel()

	if building.is_empty():
		return

	var name := str(building.get("name", "This location"))
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "%s — No services at this location yet." % name
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_content_pane.add_child(label)


func _update_portrait(portrait_path: String) -> void:
	if _portrait == null:
		return
	if portrait_path.is_empty() or not ResourceLoader.exists(portrait_path):
		_portrait.texture = null
		_portrait.visible = false
		return
	var texture := load(portrait_path) as Texture2D
	_portrait.texture = texture
	_portrait.visible = texture != null


func _on_save_pressed() -> void:
	if _context.on_save_requested.is_valid():
		_context.on_save_requested.call()


func _on_menu_pressed() -> void:
	if _context.on_quit_to_menu_requested.is_valid():
		_context.on_quit_to_menu_requested.call()


func _select_item_by_id(
	list: ItemList,
	ids: PackedStringArray,
	target_id: String,
	suppress_flag_name: String
) -> void:
	set(suppress_flag_name, true)
	var index := ids.find(target_id)
	if index >= 0:
		list.select(index)
	else:
		list.deselect_all()
	set(suppress_flag_name, false)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if handle_back():
			get_viewport().set_input_as_handled()
