extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")
const HARNESS_CALLSIGN := "SYS"
const SKIP_BACKGROUND_IDS := ["tester"]

var _main: Node2D
var _catalog: Catalog
var _overlay_layer: CanvasLayer
var _overlay_root: Control
var _sector_option: OptionButton
var _background_option: OptionButton
var _ship_option: OptionButton
var _encounter_option: OptionButton
var _run_seed_edit: LineEdit
var _encounter_choice_keys: Array[String] = []
var _sector_ids: Array[String] = []
var _background_ids: Array[String] = []
var _ship_entries: Array[Dictionary] = []
var _begin_button: Button
var _status_label: Label
var _run_active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = MAIN_SCENE.instantiate() as Node2D
	add_child(_main)
	_catalog = _main.catalog
	await get_tree().process_frame
	_suppress_production_menu()
	_build_setup_overlay()
	_populate_options()
	_background_option.item_selected.connect(func(_i: int) -> void: _refresh_ship_options())
	_sector_option.item_selected.connect(func(_i: int) -> void: _refresh_encounter_options())
	_begin_button.pressed.connect(_on_begin_pressed)
	get_tree().paused = true


func _suppress_production_menu() -> void:
	var main_menu := _main.get_node_or_null("MainMenu") as CanvasLayer
	if main_menu != null and main_menu.has_method("close"):
		main_menu.close()
	_main.get_node("HUD").visible = false
	_main.game_active = false


func _build_setup_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "SetupLayer"
	_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay_layer)

	_overlay_root = Control.new()
	_overlay_root.name = "Root"
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_layer.add_child(_overlay_root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.04, 0.82)
	_overlay_root.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -480.0
	panel.offset_top = -320.0
	panel.offset_right = 480.0
	panel.offset_bottom = 320.0
	_overlay_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "System sandbox"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = (
		"Catalog space with ambient NPC traffic. Choose a sector, a starter-kit ship, "
		+ "and an optional random encounter. Begin launches from the habitat; F8 reloads this setup."
	)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)

	left.add_child(_field_label("Location (catalog sector)"))
	_sector_option = OptionButton.new()
	left.add_child(_sector_option)

	left.add_child(_field_label("Starter kit"))
	_background_option = OptionButton.new()
	left.add_child(_background_option)

	left.add_child(_field_label("Ship from kit"))
	_ship_option = OptionButton.new()
	left.add_child(_ship_option)

	right.add_child(_field_label("Random encounter"))
	_encounter_option = OptionButton.new()
	right.add_child(_encounter_option)

	right.add_child(_field_label("Run seed"))
	_run_seed_edit = LineEdit.new()
	_run_seed_edit.placeholder_text = "Empty = random (new career roll)"
	_run_seed_edit.tooltip_text = (
		"Career run_seed for this session. Mixed into forced encounter grants "
		+ "(e.g. which celebrity visits). Change seed and reload setup to try another pilot."
	)
	right.add_child(_run_seed_edit)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vbox.add_child(footer)

	_begin_button = Button.new()
	_begin_button.text = "Begin flight"
	footer.add_child(_begin_button)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_status_label)


static func _field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _populate_options() -> void:
	_populate_sectors()
	_populate_backgrounds()
	_refresh_ship_options()
	_refresh_encounter_options()
	if _sector_option.item_count > 0:
		var proxima_idx := _sector_ids.find("proxima")
		_sector_option.select(maxi(0, proxima_idx))
	if _background_option.item_count > 0:
		var trader_idx := _background_ids.find("trader")
		_background_option.select(maxi(0, trader_idx))
		_refresh_ship_options()


func _populate_sectors() -> void:
	_sector_ids.clear()
	_sector_option.clear()
	var rows: Array[Dictionary] = []
	for sector_variant in _catalog.list_sectors():
		if typeof(sector_variant) != TYPE_DICTIONARY:
			continue
		var sector: Dictionary = sector_variant
		var sector_id := str(sector.get("id", "")).strip_edges()
		if sector_id.is_empty():
			continue
		if VolatileTranslation.is_volatile_sector_id(sector_id):
			continue
		if _catalog.get_world(sector_id).is_empty():
			continue
		rows.append({"id": sector_id, "label": _sector_label(sector_id, sector)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("label", "")) < str(b.get("label", ""))
	)
	for row in rows:
		_sector_ids.append(str(row.get("id", "")))
		_sector_option.add_item(str(row.get("label", "")))


func _sector_label(sector_id: String, sector: Dictionary) -> String:
	var display := str(sector.get("name", sector_id))
	var planet := str(sector.get("planet_name", "")).strip_edges()
	if not planet.is_empty():
		display = planet
	var star := str(sector.get("star_system", "")).strip_edges()
	if star.is_empty():
		return display
	return "%s — %s" % [display, star]


func _populate_backgrounds() -> void:
	_background_ids.clear()
	_background_option.clear()
	for entry_variant in _catalog.list_backgrounds():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var bg_id := str(entry.get("id", "")).strip_edges()
		if bg_id.is_empty() or SKIP_BACKGROUND_IDS.has(bg_id):
			continue
		var ships: Variant = entry.get("ships", [])
		if typeof(ships) != TYPE_ARRAY or ships.is_empty():
			continue
		_background_ids.append(bg_id)
		_background_option.add_item(str(entry.get("name", bg_id)))


func _refresh_ship_options() -> void:
	_ship_entries.clear()
	_ship_option.clear()
	var bg_index := _background_option.selected
	if bg_index < 0 or bg_index >= _background_ids.size():
		return
	var kit: Dictionary = _catalog.get_background(_background_ids[bg_index])
	var ships: Variant = kit.get("ships", [])
	if typeof(ships) != TYPE_ARRAY:
		return
	for ship_variant in ships:
		if typeof(ship_variant) != TYPE_DICTIONARY:
			continue
		var ship: Dictionary = ship_variant
		var instance_id := str(ship.get("id", "")).strip_edges()
		var template_id := str(ship.get("template_id", "")).strip_edges()
		if instance_id.is_empty() and template_id.is_empty():
			continue
		var label := str(ship.get("name", template_id))
		if label.is_empty():
			label = template_id
		_ship_entries.append(
			{"instance_id": instance_id, "template_id": template_id, "label": label}
		)
		_ship_option.add_item(label)
	if _ship_option.item_count > 0:
		_ship_option.select(0)


func _refresh_encounter_options() -> void:
	_encounter_choice_keys.clear()
	_encounter_option.clear()
	_encounter_option.add_item("Default (catalog chance)")
	_encounter_choice_keys.append("default")
	_encounter_option.add_item("Off")
	_encounter_choice_keys.append("off")
	_encounter_option.add_item("Random (class pool)")
	_encounter_choice_keys.append("random")

	var sector_id := _selected_sector_id()
	var location_class := _location_class_for_sector(_catalog, sector_id)
	for def_variant in EncounterSubsystem.list_defs_for_class(_catalog, location_class):
		if typeof(def_variant) != TYPE_DICTIONARY:
			continue
		var def: Dictionary = def_variant
		var encounter_id := str(def.get("id", "")).strip_edges()
		if encounter_id.is_empty():
			continue
		_encounter_choice_keys.append(encounter_id)
		_encounter_option.add_item(_encounter_harness_label(encounter_id))
	_encounter_option.select(0)


static func _encounter_harness_label(encounter_id: String) -> String:
	return encounter_id.replace("_", " ").capitalize()


static func _location_class_for_sector(catalog: Catalog, sector_id: String) -> String:
	if MessageEmitterTokens.is_planetary_hub(catalog, sector_id):
		return "hub"
	return "branch"


func _selected_sector_id() -> String:
	var index := _sector_option.selected
	if index < 0 or index >= _sector_ids.size():
		return ""
	return _sector_ids[index]


func _primary_habitat_for_sector(sector_id: String) -> String:
	var fallback := ""
	for habitat_variant in _catalog.list_habitat_dicts():
		if typeof(habitat_variant) != TYPE_DICTIONARY:
			continue
		var habitat: Dictionary = habitat_variant
		if str(habitat.get("sector_id", "")) != sector_id:
			continue
		var habitat_id := str(habitat.get("id", "")).strip_edges()
		if habitat_id.is_empty():
			continue
		if not str(habitat.get("default_building", "")).is_empty():
			return habitat_id
		if fallback.is_empty():
			fallback = habitat_id
	return fallback


func _apply_harness_encounter(session: GameSession, sector_id: String) -> void:
	var choice := "default"
	var index := _encounter_option.selected
	if index >= 0 and index < _encounter_choice_keys.size():
		choice = _encounter_choice_keys[index]
	session.harness_encounter_roll = "off" if choice == "off" else "default"
	var encounters := _main.get_simulation().get_subsystem("encounters") as EncounterSubsystem
	if encounters == null:
		return
	encounters.clear_active()
	var location_class := _location_class_for_sector(_catalog, sector_id)
	match choice:
		"off":
			pass
		"default":
			encounters.try_arrival_roll(session, _catalog)
		"random":
			if not encounters.grant_random_for_class(
				session,
				_catalog,
				location_class,
				sector_id
			):
				push_warning("System sandbox: no encounter available for random grant.")
		_:
			if not encounters.grant_for_location(
				session,
				_catalog,
				choice,
				sector_id,
				location_class
			):
				push_warning("System sandbox: could not grant encounter '%s'." % choice)


func _on_begin_pressed() -> void:
	if _run_active:
		return
	_status_label.text = ""

	var sector_id := _selected_sector_id()
	if sector_id.is_empty():
		_status_label.text = "Select a sector."
		return

	var habitat_id := _primary_habitat_for_sector(sector_id)
	if habitat_id.is_empty():
		_status_label.text = "Sector has no dockable habitat."
		return

	var bg_index := _background_option.selected
	if bg_index < 0 or bg_index >= _background_ids.size():
		_status_label.text = "Select a starter kit."
		return
	var background_id := _background_ids[bg_index]

	var ship_index := _ship_option.selected
	if ship_index < 0 or ship_index >= _ship_entries.size():
		_status_label.text = "Select a ship from the kit."
		return
	var ship_pick: Dictionary = _ship_entries[ship_index]
	var pick_instance_id := str(ship_pick.get("instance_id", "")).strip_edges()

	var session: GameSession = _main.session
	session.sandbox = true
	session.harness_encounter_roll = "off"
	if not session.start_new_game(_catalog, HARNESS_CALLSIGN, background_id):
		_status_label.text = "Could not start harness session."
		return

	var seed_text := _run_seed_edit.text.strip_edges()
	if not seed_text.is_empty():
		if not seed_text.is_valid_int():
			_status_label.text = "Run seed must be a whole number."
			return
		session.run_seed = int(seed_text)

	if not session.enter_sector(_catalog, sector_id, false):
		_status_label.text = "Could not enter sector '%s'." % sector_id
		return

	var chosen_id := ""
	for ship_variant in session.owned_ships:
		if typeof(ship_variant) != TYPE_OBJECT:
			continue
		var owned: OwnedShip = ship_variant
		if not pick_instance_id.is_empty() and owned.id == pick_instance_id:
			chosen_id = owned.id
			break
	if chosen_id.is_empty():
		for ship_variant in session.owned_ships:
			if typeof(ship_variant) != TYPE_OBJECT:
				continue
			var owned: OwnedShip = ship_variant
			if str(ship_pick.get("template_id", "")) == owned.template_id:
				chosen_id = owned.id
				break
	if chosen_id.is_empty() and not session.owned_ships.is_empty():
		chosen_id = session.owned_ships[0].id
	if chosen_id.is_empty():
		_status_label.text = "Kit ship not found on session."
		return

	for ship_variant in session.owned_ships:
		if typeof(ship_variant) != TYPE_OBJECT:
			continue
		var owned: OwnedShip = ship_variant
		owned.location = habitat_id
	session.current_ship_id = chosen_id

	if not session.dock(_catalog, habitat_id):
		_status_label.text = session.last_log
		return

	var missions := _main.get_simulation().get_subsystem("missions") as MissionSubsystem
	if not session.undock(_catalog, chosen_id, missions):
		_status_label.text = session.last_log
		return

	_apply_harness_encounter(session, sector_id)

	_main.dev_set_quit_to_menu(Callable(self, "_reload_harness"))
	_main.dev_start_game_from_session()
	_run_active = true
	_overlay_layer.visible = false
	_overlay_layer.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false


func smoke_begin_proxima_trader() -> bool:
	var proxima_idx := _sector_ids.find("proxima")
	if proxima_idx >= 0:
		_sector_option.select(proxima_idx)
	var trader_idx := _background_ids.find("trader")
	if trader_idx >= 0:
		_background_option.select(trader_idx)
		_refresh_ship_options()
	_refresh_encounter_options()
	_encounter_option.select(_encounter_choice_keys.find("celebrity_arrival") if _encounter_choice_keys.has("celebrity_arrival") else 0)
	_on_begin_pressed()
	return _run_active


func smoke_shutdown() -> void:
	get_tree().paused = false
	if _run_active and _main != null and is_instance_valid(_main):
		_main.dev_teardown_active_run()
	_run_active = false


func _reload_harness() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_reload_harness()
		get_viewport().set_input_as_handled()
