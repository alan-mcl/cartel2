extends Control

const REFRESH_INTERVAL_SEC := 1.0

@onready var _title: Label = $Center/Panel/VBox/Title
@onready var _modules_list: VBoxContainer = $Center/Panel/VBox/Columns/LeftColumn/ModulesScroll/ModulesList
@onready var _cargo_list: VBoxContainer = $Center/Panel/VBox/Columns/LeftColumn/CargoScroll/CargoList
@onready var _passengers_list: VBoxContainer = $Center/Panel/VBox/Columns/RightColumn/PassengersScroll/PassengersList
@onready var _freight_list: VBoxContainer = $Center/Panel/VBox/Columns/RightColumn/FreightScroll/FreightList

var _session: GameSession
var _catalog: Catalog
var _simulation: Simulation
var _refresh_accum := 0.0


func _ready() -> void:
	visible = false
	set_process(false)
	var panel := get_node_or_null("Center/Panel") as Control
	if panel != null:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP


func bind(session: GameSession, catalog: Catalog, simulation: Simulation) -> void:
	_session = session
	_catalog = catalog
	_simulation = simulation


func is_open() -> bool:
	return visible


func open() -> void:
	if _session == null or _catalog == null:
		return
	visible = true
	_refresh_accum = 0.0
	_refresh_content()
	set_process(true)


func close() -> bool:
	if not visible:
		return false
	visible = false
	set_process(false)
	return true


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func refresh_if_open() -> void:
	if visible:
		_refresh_content()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL_SEC:
		_refresh_accum = 0.0
		_refresh_content()


func _refresh_content() -> void:
	var missions := _missions_subsystem()
	var snapshot := FlightManifest.build(_session, _catalog, missions)
	_title.text = str(snapshot.get("ship_name", "Ship"))
	_populate_modules(snapshot.get("modules", []) as Array)
	_populate_cargo(snapshot)
	_populate_passengers(snapshot.get("passengers", []) as Array)
	_populate_freight(snapshot.get("freight", []) as Array)


func _missions_subsystem() -> MissionSubsystem:
	if _simulation == null:
		return null
	return _simulation.get_subsystem("missions") as MissionSubsystem


func _populate_modules(modules: Array) -> void:
	_clear_children(_modules_list)
	if modules.is_empty():
		_modules_list.add_child(_muted_label("No modules fitted"))
		return
	for row_variant in modules:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		_modules_list.add_child(
			ModuleIcons.make_module_status_row(
				str(row.get("slot", "")),
				str(row.get("name", "")),
				str(row.get("category", ""))
			)
		)


func _populate_cargo(snapshot: Dictionary) -> void:
	_clear_children(_cargo_list)
	var hold_used := float(snapshot.get("hold_used_t", 0.0))
	var hold_capacity := float(snapshot.get("hold_capacity_t", 0.0))
	_cargo_list.add_child(
		UiPatterns.status_row("Hold used", "%.1f / %.1f t" % [hold_used, hold_capacity])
	)
	var cargo: Array = snapshot.get("cargo", []) as Array
	if cargo.is_empty():
		_cargo_list.add_child(_muted_label("Hold empty"))
		return
	for row_variant in cargo:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		var value := "%d (%.1f t)" % [int(row.get("quantity", 0)), float(row.get("tonnes", 0.0))]
		_cargo_list.add_child(UiPatterns.status_row(str(row.get("name", "")), value))


func _populate_passengers(passengers: Array) -> void:
	_clear_children(_passengers_list)
	if passengers.is_empty():
		_passengers_list.add_child(_muted_label("No passengers"))
		return
	for row_variant in passengers:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		_passengers_list.add_child(_charter_block(row_variant as Dictionary))


func _populate_freight(freight: Array) -> void:
	_clear_children(_freight_list)
	if freight.is_empty():
		_freight_list.add_child(_muted_label("No freight"))
		return
	for row_variant in freight:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		_freight_list.add_child(_charter_block(row_variant as Dictionary))


func _charter_block(row: Dictionary) -> Control:
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	inner.add_child(_one_line_label(str(row.get("title", ""))))
	var route := str(row.get("route", "")).strip_edges()
	if not route.is_empty():
		inner.add_child(_one_line_label(route, &"Muted"))
	var meta := str(row.get("meta", "")).strip_edges()
	if not meta.is_empty():
		inner.add_child(_one_line_label(meta, &"Muted"))
	var deadline := str(row.get("deadline", "")).strip_edges()
	if not deadline.is_empty():
		inner.add_child(_one_line_label(deadline, &"Muted"))
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudTicker"
	panel.add_child(inner)
	return panel


func _one_line_label(text: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not variation.is_empty():
		label.theme_type_variation = variation
	return label


func _muted_label(text: String) -> Label:
	return _one_line_label(text, &"Muted")


func _clear_children(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()
