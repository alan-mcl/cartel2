class_name TrafficSpawn
extends RefCounted

const ACTOR_SCRIPT_PATH := "res://scripts/gameplay/traffic_actor.gd"
const TransponderBroadcastScript := preload("res://scripts/gameplay/transponder_broadcast.gd")
const ShipSimCoreScript := preload("res://scripts/gameplay/ship_sim_core.gd")

const LAUNCH_SPEED := 20.0


static func create(
	catalog: Catalog,
	traffic_config: Dictionary,
	role_name: String,
	template: String,
	spawn_pos: Vector2,
	spawn_facing: float,
	sector_id: String
) -> RefCounted:
	var actor: RefCounted = load(ACTOR_SCRIPT_PATH).new()
	actor.id = "traffic_%d" % randi()
	actor.role = role_name
	actor.template_id = template
	actor.hull_color_shift = randf_range(-0.06, 0.06)
	var affiliation_record := _pick_affiliation_record(traffic_config)
	actor.affiliation = str(affiliation_record.get("name", ""))
	var is_independent := str(affiliation_record.get("kind", "corporate")) == "independent"
	actor.callsign = TransponderBroadcastScript.generate_callsign_for_affiliation(
		traffic_config,
		affiliation_record
	)
	actor.owned_ship = _create_owned_ship(catalog, template, traffic_config, is_independent)
	actor.assembled_ship = ShipAssembler.assemble_owned(catalog, actor.owned_ship)
	var loaded_mass := ShipAssembler.calculate_loaded_mass(catalog, actor.owned_ship, actor.assembled_ship)
	actor.assembled_ship.stats = ShipAssembler.derive_stats(actor.assembled_ship, loaded_mass)
	actor.hull_max = float(actor.assembled_ship.capacities.get("hull_hits", 18.0))
	actor.combat_state = ShipCombatState.from_assembled(actor.assembled_ship)
	actor.hull_current = actor.combat_state.hull_current
	actor.hull_max = actor.combat_state.hull_max
	actor.motion.facing = spawn_facing
	actor._position = spawn_pos
	actor.cruise_speed_cap = _pick_cruise_speed(traffic_config, actor.assembled_ship)
	actor.motion.velocity = Vector2.from_angle(spawn_facing) * LAUNCH_SPEED
	actor.loiter_angle = randf() * TAU
	actor.sim = ShipSimCoreScript.new()
	actor.sim.bind(catalog, actor.assembled_ship, actor.owned_ship, actor.motion, actor.operating_state, actor.weapons)
	TrafficRouting.assign_route_endpoints(actor, sector_id)
	return actor


static func _create_owned_ship(
	catalog: Catalog,
	template_id: String,
	traffic_config: Dictionary,
	is_independent: bool
) -> OwnedShip:
	var template := catalog.get_ship(template_id)
	var owned := OwnedShip.new()
	owned.id = "npc_%d" % randi()
	owned.name = _pick_vanity_name(traffic_config) if is_independent else ""
	owned.registration = TransponderBroadcastScript.generate_registration(catalog, template_id)
	owned.template_id = template_id
	owned.chassis_id = str(template.get("chassis", ""))
	var chassis := catalog.get_chassis(owned.chassis_id)
	var module_ids: Array = []
	var raw_modules: Variant = template.get("modules", [])
	if typeof(raw_modules) == TYPE_ARRAY:
		for module_id in raw_modules:
			module_ids.append(str(module_id))
	owned.modules = ShipAssembler.assign_modules_to_slots(catalog, chassis, module_ids)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	owned.fuel_current = float(assembled.capacities.get("fuel_capacity", 0.0))
	ShipAssembler.seed_ammunition(catalog, owned)
	return owned


static func _pick_affiliation_record(traffic_config: Dictionary) -> Dictionary:
	var affiliations: Variant = traffic_config.get("affiliations", [])
	if typeof(affiliations) != TYPE_ARRAY or affiliations.is_empty():
		return {"kind": "independent", "name": "Independent Operator"}

	var independent_weight := float(traffic_config.get("independent_weight", 0.30))
	var corporate: Array = []
	var independent: Dictionary = {}

	for entry_variant in affiliations:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		match str(entry.get("kind", "")):
			"independent":
				independent = entry
			"corporate":
				corporate.append(entry)

	if randf() < independent_weight and not independent.is_empty():
		return independent
	if not corporate.is_empty():
		return corporate[randi() % corporate.size()]
	if not independent.is_empty():
		return independent
	return {"kind": "independent", "name": "Independent Operator"}


static func _pick_vanity_name(traffic_config: Dictionary) -> String:
	var names: Variant = traffic_config.get("vanity_ship_names", [])
	if typeof(names) != TYPE_ARRAY or names.is_empty():
		return "Wayfarer"
	return str(names[randi() % names.size()])


static func _pick_cruise_speed(traffic_config: Dictionary, assembled: AssembledShip) -> float:
	var fraction := float(traffic_config.get("cruise_speed_fraction", 0.33))
	var jitter := float(traffic_config.get("cruise_speed_jitter", 0.2))
	var hull_max_speed := float(assembled.stats.max_speed)
	if hull_max_speed <= 0.0:
		return 100.0
	var jitter_mult := randf_range(1.0 - jitter, 1.0 + jitter)
	return hull_max_speed * fraction * jitter_mult


static func pick_template_for_role(traffic_config: Dictionary, role_name: String) -> String:
	var mapping: Variant = traffic_config.get("role_ship_templates", {})
	var entry: Variant = mapping.get(role_name, "pegasus_p101")
	if typeof(entry) == TYPE_ARRAY:
		var choices: Array = entry
		if choices.is_empty():
			return "pegasus_p101"
		return str(choices[randi() % choices.size()])
	return str(entry)
