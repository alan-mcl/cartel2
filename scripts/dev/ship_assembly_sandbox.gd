extends Control

const SHIPYARD_REFIT_SCREEN := preload("res://scenes/ui/shipyard_refit_screen.tscn")

const SANDBOX_HABITAT_ID := "proxima_habitat"

@onready var _strip_button: Button = $Layout/Header/HeaderBox/Toolbar/StripButton
@onready var _restore_button: Button = $Layout/Header/HeaderBox/Toolbar/RestoreButton
@onready var _chassis_option: OptionButton = $Layout/Header/HeaderBox/Toolbar/ChassisOption
@onready var _add_hull_button: Button = $Layout/Header/HeaderBox/Toolbar/AddHullButton
@onready var _yard_host: Control = $Layout/YardHost
@onready var _screen_stack: ScreenStack = $ScreenStack

var _catalog: Catalog
var _session: GameSession
var _context: UiContext
var _refit: ShipyardRefitScreen
var _ship_item_list: ItemList
var _ship_ids: PackedStringArray = PackedStringArray()
var _selected_ship_id: String = ""
var _suppress_ship_select: bool = false
var _ship_id_counter: int = 0


func _ready() -> void:
	_catalog = Catalog.load_default()
	_session = _build_session()
	_context = _build_context()
	_populate_chassis_options()
	_mount_shipyard()

	_strip_button.pressed.connect(_on_strip_pressed)
	_restore_button.pressed.connect(_on_restore_pressed)
	_add_hull_button.pressed.connect(_on_add_hull_pressed)
	if not _session.changed.is_connected(_on_sandbox_session_changed):
		_session.changed.connect(_on_sandbox_session_changed)


func _build_session() -> GameSession:
	var session := GameSession.new()
	session.sandbox = true
	session.docked = true
	session.habitat_id = SANDBOX_HABITAT_ID
	session.building_id = "proxima_shipyard"
	session.callsign = "SBX"
	session.last_log = "Assembly sandbox ready."

	var kit := _catalog.get_background(_catalog.get_default_background_id())
	var ships_data: Variant = kit.get("ships", [])
	if typeof(ships_data) == TYPE_ARRAY:
		for ship_data in ships_data:
			if typeof(ship_data) != TYPE_DICTIONARY:
				continue
			var modules_data: Variant = ship_data.get("modules", [])
			var ship: OwnedShip
			if typeof(modules_data) == TYPE_ARRAY and not modules_data.is_empty():
				ship = OwnedShip.from_dict(ship_data)
			else:
				ship = OwnedShip.from_template(_catalog, ship_data)
			ship.location = SANDBOX_HABITAT_ID
			session.owned_ships.append(ship)
			_ship_id_counter += 1

	for chassis_id_variant in _catalog.chassis_by_id.keys():
		var chassis_id := str(chassis_id_variant)
		if chassis_id.is_empty():
			continue
		var chassis_def: ChassisDef = _catalog.chassis_by_id[chassis_id]
		if chassis_def == null:
			continue
		session.owned_ships.append(_make_empty_hull(chassis_def))

	return session


func _build_context() -> UiContext:
	var context := UiContext.new()
	context.catalog = _catalog
	context.session = _session
	context.stack = _screen_stack
	context.on_ship_changed = func(_ship_id: String) -> void:
		pass
	return context


func _populate_chassis_options() -> void:
	_chassis_option.clear()
	for chassis_def in _catalog.list_chassis():
		if typeof(chassis_def) != TYPE_DICTIONARY:
			continue
		var chassis_id := str(chassis_def.get("id", ""))
		if chassis_id.is_empty():
			continue
		_chassis_option.add_item(str(chassis_def.get("name", chassis_id)), _chassis_option.item_count)
		_chassis_option.set_item_metadata(_chassis_option.item_count - 1, chassis_id)


func _mount_shipyard() -> void:
	for child in _yard_host.get_children():
		child.queue_free()

	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 12)
	_yard_host.add_child(split)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.35
	left.add_theme_constant_override("separation", 4)
	split.add_child(left)

	var heading := Label.new()
	heading.text = "SHIPS"
	heading.theme_type_variation = &"Section"
	left.add_child(heading)

	_ship_item_list = ItemList.new()
	_ship_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ship_item_list.select_mode = ItemList.SELECT_SINGLE
	_ship_item_list.allow_reselect = true
	_ship_item_list.item_selected.connect(_on_sandbox_ship_selected)
	left.add_child(_ship_item_list)

	_refit = SHIPYARD_REFIT_SCREEN.instantiate()
	_refit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_refit.size_flags_stretch_ratio = 1.65
	split.add_child(_refit)

	_refit.configure_sandbox(true)
	_refit.configure_embedded_in_host(true)
	_refit.bind(_context)

	_rebuild_sandbox_ship_list()


func _on_sandbox_session_changed() -> void:
	_rebuild_sandbox_ship_list()


func _rebuild_sandbox_ship_list() -> void:
	if _ship_item_list == null:
		return

	var preserve_id := _selected_ship_id
	_ship_ids.clear()
	_ship_item_list.clear()

	var ships := _session.ships_at(SANDBOX_HABITAT_ID)
	for ship in ships:
		_ship_ids.append(ship.id)
		_ship_item_list.add_item(ship.name)

	if preserve_id.is_empty() and not _ship_ids.is_empty():
		preserve_id = _ship_ids[0]
	if not _ship_ids.has(preserve_id):
		preserve_id = _ship_ids[0] if not _ship_ids.is_empty() else ""

	_selected_ship_id = preserve_id
	_suppress_ship_select = true
	var index := _ship_ids.find(_selected_ship_id)
	if index >= 0:
		_ship_item_list.select(index)
	else:
		_ship_item_list.deselect_all()
	_suppress_ship_select = false

	if _refit != null:
		_refit.set_ship_id(_selected_ship_id)


func _on_sandbox_ship_selected(index: int) -> void:
	if _suppress_ship_select:
		return
	if index < 0 or index >= _ship_ids.size():
		return
	_selected_ship_id = _ship_ids[index]
	if _refit != null:
		_refit.set_ship_id(_selected_ship_id)


func _make_empty_hull(chassis_def: ChassisDef) -> OwnedShip:
	if chassis_def == null:
		return OwnedShip.new()
	var chassis_id := chassis_def.id
	var ship := OwnedShip.new()
	ship.id = _next_ship_id(chassis_id)
	var label := chassis_id
	if chassis_def.has_source_key("name"):
		label = chassis_def.name
	ship.name = "%s (empty)" % label
	ship.chassis_id = chassis_id
	ship.location = SANDBOX_HABITAT_ID
	return ship


func _next_ship_id(chassis_id: String) -> String:
	_ship_id_counter += 1
	return "sandbox_%s_%d" % [chassis_id, _ship_id_counter]


func _get_selected_ship() -> OwnedShip:
	if _selected_ship_id.is_empty():
		return null
	return _session.get_owned_ship(_selected_ship_id)


func _on_strip_pressed() -> void:
	var ship := _get_selected_ship()
	if ship == null:
		_session.last_log = "Select a ship to strip."
		_session.changed.emit()
		return

	ship.modules.clear()
	ship.fuels.clear()
	ship.ammunition.clear()
	_session.last_log = "Stripped %s." % ship.name
	_session.changed.emit()


func _on_restore_pressed() -> void:
	var ship := _get_selected_ship()
	if ship == null:
		_session.last_log = "Select a ship to restore."
		_session.changed.emit()
		return

	if ship.template_id.is_empty():
		_session.last_log = "No manufacturer template for this hull."
		_session.changed.emit()
		return

	var template := _catalog.get_ship_def(ship.template_id)
	if template == null:
		_session.last_log = "Template %s not found." % ship.template_id
		_session.changed.emit()
		return

	var chassis := _catalog.get_chassis_def(ship.chassis_id)
	var module_ids: Array = template.modules.duplicate()

	ship.modules = ShipAssembler.assign_modules_to_slots(_catalog, chassis, module_ids)
	var assembled := ShipAssembler.assemble_owned(_catalog, ship)
	ShipFuel.fill_active_to_capacity(_catalog, ship)
	ship.ammunition.clear()
	ShipAssembler.seed_ammunition(_catalog, ship)

	_session.last_log = "Restored %s template." % ship.name
	_session.changed.emit()


func _on_add_hull_pressed() -> void:
	if _chassis_option.item_count <= 0:
		return

	var index := _chassis_option.selected
	var chassis_id := str(_chassis_option.get_item_metadata(index))
	var chassis_def := _catalog.get_chassis_def(chassis_id)
	if chassis_def == null:
		return

	var ship := _make_empty_hull(chassis_def)
	_session.owned_ships.append(ship)
	_selected_ship_id = ship.id
	_session.last_log = "Added empty %s." % ship.name
	_session.changed.emit()
