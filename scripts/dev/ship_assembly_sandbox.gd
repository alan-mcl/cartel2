extends Control

const SHIPYARD_SCREEN := preload("res://scenes/ui/shipyard_screen.tscn")

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
var _yard: Control
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


func _build_session() -> GameSession:
	var session := GameSession.new()
	session.sandbox = true
	session.docked = true
	session.habitat_id = SANDBOX_HABITAT_ID
	session.building_id = "habitat_workshop"
	session.player_name = "Sandbox"
	session.callsign = "SBX"
	session.last_log = "Assembly sandbox ready."

	var player_data := _catalog.get_player()
	var ships_data: Variant = player_data.get("ships", [])
	if typeof(ships_data) == TYPE_ARRAY:
		for ship_data in ships_data:
			if typeof(ship_data) != TYPE_DICTIONARY:
				continue
			var ship := OwnedShip.from_dict(ship_data)
			ship.location = SANDBOX_HABITAT_ID
			session.owned_ships.append(ship)
			_ship_id_counter += 1

	for chassis_def in _catalog.list_chassis():
		if typeof(chassis_def) != TYPE_DICTIONARY:
			continue
		var chassis_id := str(chassis_def.get("id", ""))
		if chassis_id.is_empty():
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
	_yard = SHIPYARD_SCREEN.instantiate()
	_yard_host.add_child(_yard)
	_yard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_yard.configure_embedded(true)
	_yard.configure_sandbox(true)
	_yard.bind(_context)


func _make_empty_hull(chassis_def: Dictionary) -> OwnedShip:
	var chassis_id := str(chassis_def.get("id", ""))
	var ship := OwnedShip.new()
	ship.id = _next_ship_id(chassis_id)
	ship.name = "%s (empty)" % str(chassis_def.get("name", chassis_id))
	ship.chassis_id = chassis_id
	ship.location = SANDBOX_HABITAT_ID
	return ship


func _next_ship_id(chassis_id: String) -> String:
	_ship_id_counter += 1
	return "sandbox_%s_%d" % [chassis_id, _ship_id_counter]


func _get_selected_ship() -> OwnedShip:
	if _yard == null:
		return null
	var ship_id: String = _yard.get_selected_ship_id()
	if ship_id.is_empty():
		return null
	return _session.get_owned_ship(ship_id)


func _on_strip_pressed() -> void:
	var ship := _get_selected_ship()
	if ship == null:
		_session.last_log = "Select a ship to strip."
		_session.changed.emit()
		return

	ship.modules.clear()
	ship.fuel_current = 0.0
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

	var template := _catalog.get_ship(ship.template_id)
	if template.is_empty():
		_session.last_log = "Template %s not found." % ship.template_id
		_session.changed.emit()
		return

	var chassis := _catalog.get_chassis(ship.chassis_id)
	var module_ids: Array = []
	var raw_modules: Variant = template.get("modules", [])
	if typeof(raw_modules) == TYPE_ARRAY:
		for module_id in raw_modules:
			module_ids.append(str(module_id))

	ship.modules = ShipAssembler.assign_modules_to_slots(_catalog, chassis, module_ids)
	var assembled := ShipAssembler.assemble_owned(_catalog, ship)
	ship.fuel_current = float(assembled.capacities.get("fuel_capacity", 0.0))
	ship.ammunition.clear()
	if ship.template_id == "pegasus_p101":
		ship.ammunition["mass_driver_round"] = 120.0

	_session.last_log = "Restored %s template." % ship.name
	_session.changed.emit()


func _on_add_hull_pressed() -> void:
	if _chassis_option.item_count <= 0:
		return

	var index := _chassis_option.selected
	var chassis_id := str(_chassis_option.get_item_metadata(index))
	var chassis_def := _catalog.get_chassis(chassis_id)
	if chassis_def.is_empty():
		return

	var ship := _make_empty_hull(chassis_def)
	_session.owned_ships.append(ship)
	_session.last_log = "Added empty %s." % ship.name
	_session.changed.emit()
