extends CanvasLayer

signal visit_requested(building_id: String)
signal undock_ship_selected(ship_id: String)
signal module_changed(ship_id: String, slot: String, module_id: String)
signal save_requested
signal quit_to_menu_requested

@onready var _title: Label = $Dim/Center/Panel/TitleLabel
@onready var _building_name: Label = $Dim/Center/Panel/BuildingNameLabel
@onready var _description: Label = $Dim/Center/Panel/DescriptionLabel
@onready var _status: Label = $Dim/Center/Panel/StatusLabel
@onready var _workshop_panel: VBoxContainer = $Dim/Center/Panel/WorkshopPanel
@onready var _workshop_ships: VBoxContainer = $Dim/Center/Panel/WorkshopPanel/ShipList
@onready var _workshop_summary: Label = $Dim/Center/Panel/WorkshopPanel/SummaryLabel
@onready var _workshop_modules: VBoxContainer = $Dim/Center/Panel/WorkshopPanel/ModuleOptions
@onready var _building_list: VBoxContainer = $Dim/Center/Panel/BuildingList
@onready var _undock_button: Button = $Dim/Center/Panel/UndockButton
@onready var _save_menu_button: Button = $Dim/Center/Panel/SaveMenuButton
@onready var _save_menu_panel: VBoxContainer = $Dim/Center/Panel/SaveMenuPanel
@onready var _save_button: Button = $Dim/Center/Panel/SaveMenuPanel/SaveButton
@onready var _quit_button: Button = $Dim/Center/Panel/SaveMenuPanel/QuitButton
@onready var _save_menu_back_button: Button = $Dim/Center/Panel/SaveMenuPanel/BackButton
@onready var _undock_picker: VBoxContainer = $Dim/Center/Panel/UndockPicker
@onready var _hint: Label = $Dim/Center/Panel/HintLabel

var _catalog: Catalog
var _session: GameSession
var _workshop_selected_ship_id: String = ""
var _undock_picker_visible: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_undock_button.pressed.connect(_on_undock_pressed)
	_save_menu_button.pressed.connect(_on_save_menu_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_save_menu_back_button.pressed.connect(_on_save_menu_back)
	_workshop_panel.visible = false
	_undock_picker.visible = false
	_save_menu_panel.visible = false


func bind(catalog: Catalog, session: GameSession) -> void:
	_catalog = catalog
	_session = session
	if session != null:
		session.changed.connect(refresh)


func open() -> void:
	visible = true
	_undock_picker_visible = false
	_workshop_selected_ship_id = ""
	_save_menu_panel.visible = false
	refresh()


func close() -> void:
	visible = false
	_undock_picker_visible = false
	_save_menu_panel.visible = false


func refresh() -> void:
	if _session == null or _catalog == null or not _session.docked:
		return

	var habitat := _session.get_current_habitat(_catalog)
	var building := _session.get_current_building(_catalog)
	if habitat.is_empty() or building.is_empty():
		return

	_title.text = str(habitat.get("name", "Habitat"))
	_building_name.text = str(building.get("name", "Building"))
	_description.text = str(building.get("short_desc", ""))

	var save_menu_open: bool = _save_menu_panel.visible
	var kind := str(building.get("kind", ""))
	var is_workshop := kind == "workshop"
	_workshop_panel.visible = is_workshop and not _undock_picker_visible and not save_menu_open
	_status.visible = not is_workshop and not _undock_picker_visible and not save_menu_open
	_building_list.visible = not _undock_picker_visible and not save_menu_open
	_undock_button.visible = not _undock_picker_visible and not save_menu_open
	_save_menu_button.visible = not _undock_picker_visible and not save_menu_open
	_undock_picker.visible = _undock_picker_visible
	_save_menu_panel.visible = save_menu_open

	if _undock_picker_visible:
		_status.text = ""
		_rebuild_undock_picker()
	elif is_workshop:
		_status.text = "Select a docked ship, then choose modules to install."
		_rebuild_workshop_panel()
	else:
		_status.text = _status_for_building(building)
		_clear_container(_workshop_ships)
		_clear_container(_workshop_modules)

	_rebuild_building_list(habitat, building)
	_update_hint(is_workshop)


func _status_for_building(building: Dictionary) -> String:
	var kind := str(building.get("kind", ""))
	match kind:
		"merchant":
			return "Sales and services are closed for the season."
		_:
			return ""


func _update_hint(is_workshop: bool) -> void:
	if _save_menu_panel.visible:
		_hint.text = "Save progress or return to main menu"
	elif _undock_picker_visible:
		_hint.text = "Choose a ship to launch · Esc to cancel"
	elif is_workshop:
		_hint.text = "Click modules to install · Visit other buildings below · Undock to choose a ship"
	else:
		_hint.text = "Click a building to visit · Undock to choose a ship · Save / Menu for progress"


func _on_save_menu_pressed() -> void:
	_undock_picker_visible = false
	_save_menu_panel.visible = true
	refresh()


func _on_save_menu_back() -> void:
	_save_menu_panel.visible = false
	refresh()


func _on_save_pressed() -> void:
	save_requested.emit()


func _on_quit_pressed() -> void:
	quit_to_menu_requested.emit()


func _rebuild_workshop_panel() -> void:
	var ships := _session.ships_at(_session.habitat_id)
	if _workshop_selected_ship_id.is_empty() and not ships.is_empty():
		_workshop_selected_ship_id = ships[0].id

	_clear_container(_workshop_ships)
	for ship in ships:
		var button := Button.new()
		var prefix := "> " if ship.id == _workshop_selected_ship_id else ""
		button.text = "%s%s" % [prefix, ship.name]
		button.pressed.connect(_on_workshop_ship_pressed.bind(ship.id))
		_workshop_ships.add_child(button)

	var selected := _session.get_owned_ship(_workshop_selected_ship_id)
	if selected == null:
		_workshop_summary.text = "No ship selected."
		_clear_container(_workshop_modules)
		return

	var assembled := ShipAssembler.assemble_owned(_catalog, selected)
	_workshop_summary.text = assembled.get_summary()
	_rebuild_module_options(selected)


func _rebuild_module_options(ship: OwnedShip) -> void:
	_clear_container(_workshop_modules)

	var assembled := ShipAssembler.assemble_owned(_catalog, ship)
	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		var module_data: Variant = entry.get("data", {})
		var module_name := str(module_data.get("name", entry.get("module_id", ""))) if typeof(module_data) == TYPE_DICTIONARY else str(entry.get("module_id", ""))
		var label := Label.new()
		label.text = "%s: %s" % [slot, module_name]
		_workshop_modules.add_child(label)

	var note := Label.new()
	note.text = "Use Shipyard assembly for module changes."
	note.theme_type_variation = &"Muted"
	_workshop_modules.add_child(note)


func _add_module_section(
	title: String,
	slot: String,
	options: Array,
	current_id: String,
	ship_id: String,
	allow_none: bool
) -> void:
	var heading := Label.new()
	heading.text = title
	_workshop_modules.add_child(heading)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_workshop_modules.add_child(row)

	if allow_none:
		var none_button := Button.new()
		var none_prefix := "> " if current_id.is_empty() else ""
		none_button.text = "%sNone" % none_prefix
		none_button.pressed.connect(_on_module_pressed.bind(ship_id, slot, ""))
		row.add_child(none_button)

	for option_variant in options:
		if typeof(option_variant) != TYPE_DICTIONARY:
			continue
		var option: Dictionary = option_variant
		var option_id := str(option.get("id", ""))
		if option_id.is_empty():
			continue

		var button := Button.new()
		var prefix := "> " if option_id == current_id else ""
		button.text = "%s%s" % [prefix, str(option.get("name", option_id))]
		button.pressed.connect(_on_module_pressed.bind(ship_id, slot, option_id))
		row.add_child(button)


func _rebuild_building_list(habitat: Dictionary, current_building: Dictionary) -> void:
	_clear_container(_building_list)

	var current_id := str(current_building.get("id", ""))
	var building_ids: Variant = habitat.get("buildings", [])
	if typeof(building_ids) != TYPE_ARRAY:
		return

	for building_id_variant in building_ids:
		var building_id := str(building_id_variant)
		if building_id == current_id:
			continue

		var building := _catalog.get_building(building_id)
		if building.is_empty():
			continue

		var button := Button.new()
		button.text = "Visit %s" % str(building.get("name", building_id))
		button.pressed.connect(_on_visit_pressed.bind(building_id))
		_building_list.add_child(button)


func _rebuild_undock_picker() -> void:
	_clear_container(_undock_picker)

	var heading := Label.new()
	heading.text = "Choose a ship to launch"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_undock_picker.add_child(heading)

	var ships := _session.ships_at(_session.habitat_id)
	for ship in ships:
		var button := Button.new()
		button.text = "Undock %s" % ship.name
		button.pressed.connect(_on_undock_choice_pressed.bind(ship.id))
		_undock_picker.add_child(button)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_on_undock_picker_cancel)
	_undock_picker.add_child(cancel)


func _on_workshop_ship_pressed(ship_id: String) -> void:
	_workshop_selected_ship_id = ship_id
	refresh()


func _on_module_pressed(ship_id: String, slot: String, module_id: String) -> void:
	module_changed.emit(ship_id, slot, module_id)


func _on_visit_pressed(building_id: String) -> void:
	visit_requested.emit(building_id)


func _on_undock_pressed() -> void:
	var ships := _session.ships_at(_session.habitat_id)
	if ships.is_empty():
		return
	if ships.size() == 1:
		undock_ship_selected.emit(ships[0].id)
		return

	_undock_picker_visible = true
	refresh()


func _on_undock_choice_pressed(ship_id: String) -> void:
	undock_ship_selected.emit(ship_id)


func _on_undock_picker_cancel() -> void:
	_undock_picker_visible = false
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if _undock_picker_visible:
			_on_undock_picker_cancel()
		else:
			_on_undock_pressed()
		get_viewport().set_input_as_handled()


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
