class_name FlightSandboxBase
extends Node2D

const NPC_SHIP_SCENE := preload("res://scenes/npc_ship.tscn")

const DEFAULT_PLAYER_TEMPLATE := "flare_on_ss"
const DEFAULT_OPPONENT_TEMPLATE := "pegasus_p103a"

@onready var _starfield: Node2D = $Starfield
@onready var _world: Node2D = $World
@onready var _player: CharacterBody2D = $PlayerShip
@onready var _hud: CanvasLayer = $HUD
@onready var _camera: Camera2D = $PlayerShip/FollowCamera
@onready var _setup_layer: CanvasLayer = $SetupLayer
@onready var _player_option: OptionButton = $SetupLayer/Root/Panel/Margin/VBox/Body/PlayerColumn/PlayerOption
@onready var _player_spec_host: VBoxContainer = $SetupLayer/Root/Panel/Margin/VBox/Body/PlayerColumn/PlayerScroll/PlayerSpec
@onready var _opponent_option: OptionButton = $SetupLayer/Root/Panel/Margin/VBox/Body/OpponentColumn/OpponentOption
@onready var _opponent_spec_host: VBoxContainer = $SetupLayer/Root/Panel/Margin/VBox/Body/OpponentColumn/OpponentScroll/OpponentSpec
@onready var _attitude_option: OptionButton = $SetupLayer/Root/Panel/Margin/VBox/Footer/AttitudeOption
@onready var _skill_option: OptionButton = $SetupLayer/Root/Panel/Margin/VBox/Footer/SkillOption
@onready var _begin_button: Button = $SetupLayer/Root/Panel/Margin/VBox/Footer/BeginButton
@onready var _status_label: Label = $SetupLayer/Root/Panel/Margin/VBox/Footer/StatusLabel

var session: GameSession
var catalog: Catalog

var _ship_template_ids: Array[String] = []
var _traffic_root: Node2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	catalog = Catalog.load_default()
	session = _build_session()
	_camera.bind_session(session)

	if _starfield.has_method("bind_camera"):
		_starfield.bind_camera(_camera)

	_player.motion_changed.connect(_on_motion_changed)
	_player.operating_state_changed.connect(_on_operating_state_changed)

	_populate_ship_options()
	_populate_attitude_options()
	_populate_skill_options()
	_on_sandbox_ready()
	_refresh_spec_panels()

	_begin_button.pressed.connect(_on_begin_pressed)
	_player_option.item_selected.connect(func(_index: int) -> void: _refresh_spec_panels())
	_opponent_option.item_selected.connect(func(_index: int) -> void: _refresh_spec_panels())

	_hud.visible = false
	_setup_layer.visible = true
	get_tree().paused = true


func _sandbox_callsign() -> String:
	return "SBX"


func _sandbox_ready_log() -> String:
	return "Flight sandbox ready."


func _on_sandbox_ready() -> void:
	pass


func _is_run_active() -> bool:
	return false


func _end_run() -> void:
	pass


func _collect_nav_contacts() -> Array:
	return []


func _nav_radius_for_hud() -> float:
	return 3000.0


func _build_session() -> GameSession:
	var new_session := GameSession.new()
	new_session.sandbox = true
	new_session.docked = false
	new_session.callsign = _sandbox_callsign()
	new_session.last_log = _sandbox_ready_log()
	return new_session


func try_interact(_target: Interactable) -> void:
	pass


func _on_begin_pressed() -> void:
	pass


func _populate_ship_options() -> void:
	_ship_template_ids.clear()
	_player_option.clear()
	_opponent_option.clear()

	var ships: Array = catalog.list_ships()
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
		var label := str(ship_def.get("name", template_id))
		_player_option.add_item(label)
		_opponent_option.add_item(label)

	_select_template_option(_player_option, DEFAULT_PLAYER_TEMPLATE)
	_select_template_option(_opponent_option, DEFAULT_OPPONENT_TEMPLATE)


func _populate_attitude_options() -> void:
	_attitude_option.clear()
	_attitude_option.add_item("Fight to the death")
	_attitude_option.add_item("Standard NPC")
	_attitude_option.selected = 0


func _populate_skill_options() -> void:
	_skill_option.clear()
	_skill_option.add_item("Random")
	_skill_option.add_item("Novice")
	_skill_option.add_item("Experienced")
	_skill_option.add_item("Elite")
	_skill_option.selected = 2


func _selected_pilot_skill() -> int:
	match _skill_option.selected:
		1:
			return CombatPilot.Skill.NOVICE
		2:
			return CombatPilot.Skill.EXPERIENCED
		3:
			return CombatPilot.Skill.ELITE
		_:
			return -1


func _select_template_option(option: OptionButton, template_id: String) -> void:
	var index := _ship_template_ids.find(template_id)
	if index >= 0:
		option.select(index)


func _template_id_at(option: OptionButton) -> String:
	var index := option.selected
	if index < 0 or index >= _ship_template_ids.size():
		return ""
	return _ship_template_ids[index]


func _refresh_spec_panels() -> void:
	_rebuild_spec_panel(_player_spec_host, _template_id_at(_player_option))
	_rebuild_spec_panel(_opponent_spec_host, _template_id_at(_opponent_option))


func _rebuild_spec_panel(host: VBoxContainer, template_id: String) -> void:
	for child in host.get_children():
		child.queue_free()

	if template_id.is_empty():
		return

	var owned := _owned_ship_from_template(template_id, "preview")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var engineering := ShipAssembly.get_engineering_block(catalog, owned)
	var stats: Dictionary = engineering.get("stats", {})
	var capacities: Dictionary = engineering.get("capacities", {})

	host.add_child(_summary_label(assembled.get_summary()))
	host.add_child(_detail_label(
		"CHASSIS",
		"%s (%d Hits, %s maneuver)" % [
			str(assembled.chassis.get("name", owned.chassis_id)),
			int(capacities.get("hull_hits", 0.0)),
			str(assembled.chassis.get("maneuver", "medium")),
		]
	))

	host.add_child(_section_label("FLIGHT"))
	for key in ["loaded_mass", "thrust", "max_speed", "boost_max_speed"]:
		if stats.has(key):
			host.add_child(_detail_label(key.to_upper(), str(stats[key])))

	host.add_child(_section_label("ENGINEERING"))
	host.add_child(_detail_label(
		"POWER",
		"%.0f / %.0f MW idle" % [
			float(engineering.get("idle_power_requested", 0.0)),
			float(engineering.get("idle_power_available", 0.0)),
		]
	))
	host.add_child(_detail_label(
		"COMPUTE",
		"%.0f / %.0f CU idle" % [
			float(engineering.get("idle_compute_demand", 0.0)),
			float(capacities.get("compute_capacity", 0.0)),
		]
	))
	host.add_child(_detail_label(
		"FUEL",
		"%.0f / %.0f" % [owned.fuel_current, float(capacities.get("fuel_capacity", 0.0))]
	))
	ModuleSpecText.append_ship_signature_rows(
		host,
		engineering.get("signature", {}),
		str(engineering.get("transponder_label", "off"))
	)

	host.add_child(_section_label("SYSTEMS"))
	if assembled.modules_in_category("weapon").is_empty():
		host.add_child(_detail_label("WEAPONS", "Unarmed"))
	_add_module_groups(host, assembled)


func _add_module_groups(host: VBoxContainer, assembled: AssembledShip) -> void:
	var grouped: Dictionary = {}
	for entry_variant in assembled.installed_modules:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var module_data: Variant = entry.get("data", null)
		if module_data == null or not module_data is ModuleDef:
			continue
		var module_def: ModuleDef = module_data
		var category := module_def.category if not module_def.category.is_empty() else "other"
		if not grouped.has(category):
			grouped[category] = []
		grouped[category].append(module_def)

	for category in grouped.keys():
		host.add_child(_detail_label(category.replace("_", " ").to_upper(), ""))
		for mod in grouped[category]:
			if mod == null or not mod is ModuleDef:
				continue
			var module_def: ModuleDef = mod
			var line: String = module_def.name if not module_def.name.is_empty() else module_def.id
			if category == "weapon":
				var delivery: String = module_def.delivery_type
				var weapon_range: float = module_def.range
				if not delivery.is_empty() or weapon_range > 0.0:
					line += " (%s, %.0f m)" % [delivery, weapon_range]
			host.add_child(_detail_label(" ", line))


func _owned_ship_from_template(template_id: String, ship_id: String) -> OwnedShip:
	var template := catalog.get_ship(template_id)
	var ship_data := {
		"id": ship_id,
		"template_id": template_id,
		"chassis_id": str(template.get("chassis", "")),
		"name": str(template.get("name", template_id)),
	}
	return OwnedShip.from_template(catalog, ship_data)


func _configure_player_for_run(player_owned: OwnedShip) -> AssembledShip:
	player_owned.location = "aboard"
	session.owned_ships.clear()
	session.owned_ships.append(player_owned)
	session.current_ship_id = player_owned.id

	var player_assembled := ShipAssembler.assemble_owned(catalog, player_owned)
	session.apply_combat_state(ShipCombatState.from_assembled(player_assembled))

	_player.configure(player_assembled, player_owned, catalog, session)
	_player.global_position = Vector2.ZERO
	_player.motion.facing = 0.0
	_player.freeze_motion()
	_player.rotation = _player.motion.facing + PI / 2.0
	return player_assembled


func _enter_run_ui(player_assembled: AssembledShip) -> void:
	_camera.make_current()
	_hud.bind(session, _player, player_assembled)
	_hud.visible = true
	_setup_layer.visible = false
	_status_label.text = ""
	get_tree().paused = false


func _return_to_setup_ui() -> void:
	_player.freeze_motion()
	_hud.visible = false
	_setup_layer.visible = true
	get_tree().paused = true


func _apply_pilot_skill(actor, pilot_skill: int) -> void:
	if pilot_skill < 0 or actor == null or actor.combat_pilot == null:
		return
	actor.combat_pilot.skill = pilot_skill as CombatPilot.Skill
	actor.combat_pilot._apply_skill_table()


func _ensure_traffic_root() -> Node2D:
	var existing := _world.get_node_or_null("Traffic") as Node2D
	if existing != null:
		return existing
	var traffic_root := Node2D.new()
	traffic_root.name = "Traffic"
	_world.add_child(traffic_root)
	return traffic_root


func _spawn_bound_npc(actor, spawn_pos: Vector2) -> Node2D:
	_traffic_root = _ensure_traffic_root()
	var node: Node2D = NPC_SHIP_SCENE.instantiate()
	_traffic_root.add_child(node)
	node.global_position = spawn_pos
	node.bind_actor(actor, catalog)
	return node


func _sync_npc_node(node: Node2D, actor) -> void:
	if node == null or not is_instance_valid(node) or actor == null:
		return
	if node.has_method("sync_from_actor"):
		node.call("sync_from_actor", actor)
	if node.has_method("apply_hull_damage_visual"):
		node.call(
			"apply_hull_damage_visual",
			actor.hull_current / maxf(actor.hull_max, 1.0)
		)
	if node.has_method("spawn_weapon_orders"):
		node.call("spawn_weapon_orders", actor.pending_weapon_orders)


func _play_destroyed_or_free(node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("play_destroyed"):
		node.call("play_destroyed")
	else:
		node.queue_free()


func _update_hud_nav() -> void:
	var contacts: Array = _collect_nav_contacts()
	_hud.set_nav_state(
		_nav_radius_for_hud(),
		_player.global_position,
		rad_to_deg(_player.motion.facing),
		contacts,
		_camera,
		{}
	)
	var player_signature := SensorSystem.live_signature(
		_player.assembled_ship,
		_player.operating_state
	)
	var transponder_label := "on" if _player.operating_state.transponder_broadcasting else "off"
	var active_sensors_label := FlightLoopController._active_sensors_hud_label(
		_player.assembled_ship,
		_player.operating_state
	)
	_hud.set_signature_state(player_signature, transponder_label, active_sensors_label)


func _clear_traffic_root() -> void:
	if _traffic_root != null and is_instance_valid(_traffic_root):
		_traffic_root.queue_free()
	_traffic_root = null


func _clear_projectiles(preserve: Array = []) -> void:
	for child in _world.get_children():
		if child == _traffic_root:
			continue
		child.queue_free()
	if _traffic_root != null and is_instance_valid(_traffic_root):
		for child in _traffic_root.get_children():
			if child in preserve:
				continue
			child.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_run_active():
		return
	if event.is_action_pressed("toggle_active_sensors"):
		if _player.owned_ship != null and _player.assembled_ship.has_active_sensor_package():
			_player.owned_ship.active_sensors_enabled = not _player.owned_ship.active_sensors_enabled
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		_end_run()
		get_viewport().set_input_as_handled()


func _on_motion_changed(speed: float, heading_deg: float, boosting: bool) -> void:
	_hud.set_motion(speed, heading_deg, boosting)


func _on_operating_state_changed(state: ShipOperatingState) -> void:
	_hud.set_operating_state(state)


func _summary_label(text: String) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	return label


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Section"
	return label


func _detail_label(label_text: String, value_text: String) -> Label:
	var label := Label.new()
	if label_text.strip_edges().is_empty():
		label.text = "  %s" % value_text
	else:
		label.text = "%s: %s" % [label_text, value_text]
	label.theme_type_variation = &"Numeric"
	return label
