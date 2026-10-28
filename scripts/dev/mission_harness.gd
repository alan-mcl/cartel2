extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")
const DEFAULT_PLAYER_TEMPLATE := "flare_on_ss"
const HARNESS_CALLSIGN := "MHAR"
const HARNESS_BACKGROUND := "trader"

enum JobKind { SCAN, BOUNTY, SITE_ONLY }

var _main: Node2D
var _catalog: Catalog
var _overlay_layer: CanvasLayer
var _overlay_root: Control
var _player_option: OptionButton
var _source_option: OptionButton
var _job_option: OptionButton
var _scan_type_option: OptionButton
var _scan_target_option: OptionButton
var _bounty_target_option: OptionButton
var _site_option: OptionButton
var _scan_row: HBoxContainer
var _bounty_row: HBoxContainer
var _player_spec_host: VBoxContainer
var _begin_button: Button
var _status_label: Label

var _ship_template_ids: Array[String] = []
var _habitat_entries: Array[Dictionary] = []
var _site_ids: Array[String] = []
var _scan_type_keys: Array[String] = []
var _bounty_template_ids: Array[String] = []
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
	_refresh_job_controls()
	_refresh_spec_panel()
	_player_option.item_selected.connect(func(_i: int) -> void: _refresh_spec_panel())
	_job_option.item_selected.connect(func(_i: int) -> void: _refresh_job_controls())
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
	panel.offset_left = -520.0
	panel.offset_top = -360.0
	panel.offset_right = 520.0
	panel.offset_bottom = 360.0
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
	title.text = "Mission harness"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Pick a ship and volatile site scenario. Begin drops you in flight at the site."
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

	left.add_child(_field_label("Ship"))
	_player_option = OptionButton.new()
	_player_option.custom_minimum_size = Vector2(0, 36)
	left.add_child(_player_option)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_player_spec_host = VBoxContainer.new()
	_player_spec_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_player_spec_host)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)

	right.add_child(_field_label("Source system"))
	_source_option = OptionButton.new()
	right.add_child(_source_option)

	right.add_child(_field_label("Job"))
	_job_option = OptionButton.new()
	_job_option.add_item("Scan charter")
	_job_option.add_item("Bounty")
	_job_option.add_item("Site only")
	right.add_child(_job_option)

	_scan_row = HBoxContainer.new()
	_scan_row.add_theme_constant_override("separation", 8)
	right.add_child(_scan_row)
	var scan_type_box := VBoxContainer.new()
	scan_type_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scan_type_box.add_child(_field_label("Scan type"))
	_scan_type_option = OptionButton.new()
	scan_type_box.add_child(_scan_type_option)
	_scan_row.add_child(scan_type_box)
	var scan_target_box := VBoxContainer.new()
	scan_target_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scan_target_box.add_child(_field_label("Scan target"))
	_scan_target_option = OptionButton.new()
	scan_target_box.add_child(_scan_target_option)
	_scan_row.add_child(scan_target_box)

	_bounty_row = HBoxContainer.new()
	right.add_child(_bounty_row)
	var bounty_box := VBoxContainer.new()
	bounty_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bounty_box.add_child(_field_label("Bounty target hull"))
	_bounty_target_option = OptionButton.new()
	bounty_box.add_child(_bounty_target_option)
	_bounty_row.add_child(bounty_box)

	right.add_child(_field_label("Volatile site"))
	_site_option = OptionButton.new()
	right.add_child(_site_option)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vbox.add_child(footer)

	_begin_button = Button.new()
	_begin_button.text = "Begin"
	footer.add_child(_begin_button)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_status_label)


func _field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	return label


func _populate_options() -> void:
	_ship_template_ids.clear()
	_player_option.clear()
	var ships: Array = _catalog.list_ships()
	ships.sort_custom(func(a: Variant, b: Variant) -> bool:
		if typeof(a) != TYPE_DICTIONARY or typeof(b) != TYPE_DICTIONARY:
			return false
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)
	for ship_def_variant in ships:
		if typeof(ship_def_variant) != TYPE_DICTIONARY:
			continue
		var ship_def: Dictionary = ship_def_variant
		var template_id := str(ship_def.get("id", ""))
		if template_id.is_empty():
			continue
		_ship_template_ids.append(template_id)
		_player_option.add_item(str(ship_def.get("name", template_id)))
	_select_template_option(_player_option, DEFAULT_PLAYER_TEMPLATE)

	_habitat_entries.clear()
	_source_option.clear()
	for habitat_variant in _catalog.list_habitat_dicts():
		if typeof(habitat_variant) != TYPE_DICTIONARY:
			continue
		var habitat: Dictionary = habitat_variant
		var habitat_id := str(habitat.get("id", ""))
		if habitat_id.is_empty():
			continue
		if not ScanCharters.habitat_has_peacekeeping(_catalog, habitat_id):
			continue
		var sector_id := str(habitat.get("sector_id", ""))
		var label := _sector_source_label(sector_id)
		_habitat_entries.append({"habitat_id": habitat_id, "sector_id": sector_id, "label": label})
	_habitat_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("label", "")) < str(b.get("label", ""))
	)
	for entry in _habitat_entries:
		_source_option.add_item(str(entry.get("label", "")))
	if _source_option.item_count > 0:
		var proxima_idx := -1
		for i in range(_habitat_entries.size()):
			if str(_habitat_entries[i].get("sector_id", "")) == "proxima":
				proxima_idx = i
				break
		_source_option.select(maxi(0, proxima_idx))

	_scan_type_keys.clear()
	_scan_type_option.clear()
	var scan_cfg := ScanCharters.config(_catalog)
	var types: Dictionary = scan_cfg.get("types", {})
	for key in types.keys():
		_scan_type_keys.append(str(key))
	_scan_type_keys.sort()
	for key in _scan_type_keys:
		_scan_type_option.add_item(key.capitalize())
	if _scan_type_option.item_count > 0:
		_scan_type_option.select(0)

	_scan_target_option.clear()
	for target in ["volatile_debris", "volatile_orbital", "volatile_ship"]:
		_scan_target_option.add_item(target.replace("volatile_", "").capitalize())
	_scan_target_option.select(0)

	_bounty_template_ids.clear()
	_bounty_target_option.clear()
	var bounty_cfg := BountyCharters.config(_catalog)
	var templates: Array = bounty_cfg.get("target_templates", [])
	for template_variant in templates:
		var template_id := str(template_variant)
		if template_id.is_empty():
			continue
		var ship_def := _catalog.get_ship_def(template_id)
		if ship_def == null:
			continue
		_bounty_template_ids.append(template_id)
		var ship_label := template_id
		if ship_def.has_source_key("name"):
			ship_label = ship_def.name
		_bounty_target_option.add_item(ship_label)
	if _bounty_template_ids.is_empty():
		for template_id in _ship_template_ids:
			var assembled := ShipAssembler.assemble_owned(
				_catalog,
				_owned_ship_from_template(template_id, "preview")
			)
			if not assembled.modules_in_category("weapon").is_empty():
				_bounty_template_ids.append(template_id)
				var ship_def := _catalog.get_ship_def(template_id)
				var ship_label := template_id
				if ship_def != null and ship_def.has_source_key("name"):
					ship_label = ship_def.name
				_bounty_target_option.add_item(ship_label)
	if _bounty_target_option.item_count > 0:
		_bounty_target_option.select(0)

	_site_ids.clear()
	_site_option.clear()
	_site_option.add_item("Random")
	for site_variant in _catalog.list_volatile_sites():
		if typeof(site_variant) != TYPE_DICTIONARY:
			continue
		var site: Dictionary = site_variant
		var site_id := VolatileSites.site_id(site)
		if site_id.is_empty():
			continue
		_site_ids.append(site_id)
		_site_option.add_item(VolatileSites.site_label(site))
	_site_option.select(0)


func _refresh_job_controls() -> void:
	var job := _job_option.selected as JobKind
	_scan_row.visible = job == JobKind.SCAN
	_bounty_row.visible = job == JobKind.BOUNTY


func _select_template_option(option: OptionButton, template_id: String) -> void:
	var index := _ship_template_ids.find(template_id)
	if index >= 0:
		option.select(index)


func _template_id_at(option: OptionButton, ids: Array[String]) -> String:
	var index := option.selected
	if index < 0 or index >= ids.size():
		return ""
	return ids[index]


func _refresh_spec_panel() -> void:
	for child in _player_spec_host.get_children():
		child.queue_free()
	var template_id := _template_id_at(_player_option, _ship_template_ids)
	if template_id.is_empty():
		return
	var owned := _owned_ship_from_template(template_id, "preview")
	var assembled := ShipAssembler.assemble_owned(_catalog, owned)
	var engineering := ShipAssembly.get_engineering_block(_catalog, owned)
	var stats: Dictionary = engineering.get("stats", {})
	var capacities: Dictionary = engineering.get("capacities", {})
	_player_spec_host.add_child(_summary_label(assembled.get_summary()))
	_player_spec_host.add_child(
		_detail_label(
			"CHASSIS",
			"%s (%d Hits, %s maneuver)" % [
				assembled.chassis_name() if not assembled.chassis_name().is_empty() else owned.chassis_id,
				int(capacities.get("hull_hits", 0.0)),
				assembled.chassis_maneuver(),
			]
		)
	)
	for key in ["loaded_mass", "thrust", "max_speed", "boost_max_speed"]:
		if stats.has(key):
			_player_spec_host.add_child(_detail_label(key.to_upper(), str(stats[key])))


func _owned_ship_from_template(template_id: String, ship_id: String) -> OwnedShip:
	var template := _catalog.get_ship_def(template_id)
	var ship_name := template_id
	var chassis_id := ""
	if template != null:
		chassis_id = template.chassis
		if template.has_source_key("name"):
			ship_name = template.name
	var ship_data := {
		"id": ship_id,
		"template_id": template_id,
		"chassis_id": chassis_id,
		"name": ship_name,
	}
	return OwnedShip.from_template(_catalog, ship_data)


func _sector_source_label(sector_id: String) -> String:
	if sector_id.is_empty():
		return ""
	var sector := _catalog.get_sector_def(sector_id)
	if sector == null:
		return sector_id
	var display_name := sector.planet_name.strip_edges()
	if display_name.is_empty() and sector.has_source_key("name"):
		display_name = sector.name
	var star_label := sector.star.strip_edges()
	if star_label.is_empty():
		star_label = sector.star_system.strip_edges()
	if star_label.is_empty():
		return display_name
	return "%s - %s" % [display_name, star_label]


func _selected_habitat_entry() -> Dictionary:
	var index := _source_option.selected
	if index < 0 or index >= _habitat_entries.size():
		return {}
	return _habitat_entries[index]


func _resolve_volatile_site(rng: RandomNumberGenerator) -> Dictionary:
	if _site_option.selected <= 0:
		return VolatileSites.pick_site(_catalog, rng)
	var site_index := _site_option.selected - 1
	if site_index < 0 or site_index >= _site_ids.size():
		return VolatileSites.pick_site(_catalog, rng)
	return _catalog.get_volatile_site(_site_ids[site_index])


func _on_begin_pressed() -> void:
	if _run_active:
		return
	_status_label.text = ""
	var session: GameSession = _main.session
	session.sandbox = true
	if not session.start_new_game(_catalog, HARNESS_CALLSIGN, HARNESS_BACKGROUND):
		_status_label.text = "Could not start harness session."
		return

	var habitat_entry := _selected_habitat_entry()
	var habitat_id := str(habitat_entry.get("habitat_id", ""))
	var sector_id := str(habitat_entry.get("sector_id", ""))
	if habitat_id.is_empty() or sector_id.is_empty():
		_status_label.text = "Invalid source system."
		return

	var template_id := _template_id_at(_player_option, _ship_template_ids)
	if template_id.is_empty():
		_status_label.text = "Select a ship."
		return

	var ship := _owned_ship_from_template(template_id, "harness_ship")
	OwnedShip.finalize_loaded_ship(ship, _catalog)
	ship.location = habitat_id
	session.owned_ships.clear()
	session.owned_ships.append(ship)
	session.current_ship_id = ship.id
	if not session.dock(_catalog, habitat_id):
		_status_label.text = session.last_log
		return

	var missions := _main.get_simulation().get_subsystem("missions") as MissionSubsystem
	if missions == null:
		_status_label.text = "Mission subsystem unavailable."
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var volatile_site := _resolve_volatile_site(rng)
	var record_id := ""

	match _job_option.selected as JobKind:
		JobKind.SCAN:
			var type_key := _scan_type_keys[_scan_type_option.selected] if _scan_type_option.selected >= 0 else "survey"
			var target_kinds: Array[String] = ["volatile_debris", "volatile_orbital", "volatile_ship"]
			var target_kind: String = target_kinds[_scan_target_option.selected]
			var offer := missions.seed_harness_scan_offer(
				session, _catalog, habitat_id, type_key, target_kind, volatile_site, rng
			)
			if offer.is_empty():
				_status_label.text = "Could not build scan offer."
				return
			if not missions.accept_scan_offer(session, _catalog, str(offer.get("id", "")), ship.id):
				_status_label.text = session.last_log
				return
			record_id = _volatile_record_from_scan(missions)
		JobKind.BOUNTY:
			var player_assembled := ShipAssembler.assemble_owned(_catalog, ship)
			if player_assembled.modules_in_category("weapon").is_empty():
				_status_label.text = "Contract requires an armed ship."
				return
			var target_template_id := _template_id_at(_bounty_target_option, _bounty_template_ids)
			var offer := missions.seed_harness_bounty_offer(
				session, _catalog, habitat_id, target_template_id, volatile_site, rng
			)
			if offer.is_empty():
				_status_label.text = "Could not build bounty offer."
				return
			if not missions.accept_bounty_offer(session, _catalog, str(offer.get("id", "")), ship.id):
				_status_label.text = session.last_log
				return
			record_id = _volatile_record_from_bounty(missions)
		JobKind.SITE_ONLY:
			var params := _build_site_only_grant_params(sector_id, volatile_site, rng)
			record_id = VolatileTranslation.grant(session, _catalog, params)
			if record_id.is_empty():
				_status_label.text = "Could not grant volatile site."
				return

	if record_id.is_empty():
		_status_label.text = "No volatile record created."
		return

	if not session.undock(_catalog, ship.id, missions):
		_status_label.text = session.last_log
		return

	var record := VolatileTranslation.find_by_id(session, record_id)
	if record.is_empty():
		_status_label.text = "Volatile record missing after accept."
		return
	VolatileTranslation.mark_outbound_consumed(session, record)
	var volatile_sector := VolatileTranslation.sector_id_for(record_id)
	if not session.enter_sector(_catalog, volatile_sector):
		_status_label.text = "Could not enter volatile sector."
		return

	_main.dev_set_quit_to_menu(Callable(self, "_reload_harness"))
	_main.dev_start_game_from_session()
	_run_active = true
	_overlay_layer.visible = false
	_overlay_layer.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false


func _build_site_only_grant_params(
	source_sector_id: String,
	volatile_site: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var cfg := ScanCharters.config(_catalog)
	var setup := {
		"play_bounds": 7500.0,
		"seed": "{{ID}}",
	}
	VolatileSites.apply_site_to_setup(setup, volatile_site, _catalog, rng)
	var lump := VolatileTranslation.default_lump_seconds()
	var entry_seconds := float(cfg.get("volatile_entry_seconds", lump))
	var exit_seconds := float(cfg.get("volatile_exit_seconds", lump))
	if entry_seconds <= 0.0:
		entry_seconds = lump
	if exit_seconds <= 0.0:
		exit_seconds = lump
	var site_label := VolatileSites.site_label(volatile_site)
	return {
		"source_sector_id": source_sector_id,
		"label": site_label,
		"description": "Harness site: %s" % VolatileSites.description_phrase(volatile_site),
		"duration_hours": int(cfg.get("volatile_duration_hours", 8)),
		"return_duration_hours": int(cfg.get("volatile_return_hours", 8)),
		"n": 4,
		"entry_seconds": entry_seconds,
		"exit_seconds": exit_seconds,
		"setup": setup,
	}


func _volatile_record_from_scan(missions: MissionSubsystem) -> String:
	var accepted := missions.list_scan_accepted()
	if accepted.is_empty():
		return ""
	var charter: Dictionary = accepted[accepted.size() - 1]
	return str(charter.get("volatile_record_id", ""))


func _volatile_record_from_bounty(missions: MissionSubsystem) -> String:
	var accepted := missions.list_bounty_accepted()
	if accepted.is_empty():
		return ""
	var charter: Dictionary = accepted[accepted.size() - 1]
	return str(charter.get("volatile_record_id", ""))


func smoke_begin_site_only(deep_space_site_id: String = "deep_space") -> bool:
	_select_template_option(_player_option, DEFAULT_PLAYER_TEMPLATE)
	for i in range(_site_ids.size()):
		if _site_ids[i] == deep_space_site_id:
			_site_option.select(i + 1)
			break
	_job_option.select(JobKind.SITE_ONLY)
	_on_begin_pressed()
	return _run_active


## Headless smoke teardown before the harness node is freed.
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


func _summary_label(text: String) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	return label


func _detail_label(label_text: String, value_text: String) -> Label:
	var label := Label.new()
	label.text = "%s: %s" % [label_text, value_text]
	label.add_theme_font_size_override("font_size", 12)
	return label
