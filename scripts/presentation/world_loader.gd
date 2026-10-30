class_name WorldLoader
extends RefCounted

const OrbitalRingScript := preload("res://scripts/presentation/orbital_ring.gd")
const NspaceField := preload("res://scripts/presentation/nspace_field.gd")
const PlanetBackdropScript := preload("res://scripts/presentation/planet_backdrop.gd")
const LocalStarScript := preload("res://scripts/presentation/local_star.gd")
const SkyParentBodyScript := preload("res://scripts/presentation/sky_parent_body.gd")

const STAR_MIN_RADIUS := 7000.0
const STAR_MAX_RADIUS := 12000.0
const STAR_GATE_CLEARANCE := 800.0
const STAR_HABITAT_ALIGN_MAX := 0.35

const SCENES := {
	"habitat": "res://scenes/world/habitat.tscn",
	"jump_gate": "res://scenes/world/jump_gate.tscn",
	"debris": "res://scenes/world/debris_rock.tscn",
	"orbital": "res://scenes/world/orbital.tscn",
	"derelict": "res://scenes/world/volatile_static.tscn",
	"cargo": "res://scenes/world/volatile_static.tscn",
	"marker": "res://scenes/world/volatile_static.tscn",
	"mine": "res://scenes/world/proximity_mine.tscn",
}

const LAUNCH_OFFSET := 220.0
const GATE_APPROACH_OFFSET := 280.0
const UNDOCK_LAUNCH_SPEED := 140.0

var spawned_by_id: Dictionary = {}
var _orbital_ring: Node2D = null
var _habitat_node: Node2D = null
var _jump_gate_node: Node2D = null
var _orbital_entries: Array = []
var _dock_nodes_by_location_id: Dictionary = {}
var _ring_radius: float = 0.0
var _ring_period_seconds: float = 720.0
var _habitat_slot_angle: float = 0.0
var _gate_radius: float = 0.0
var _gate_angle: float = 0.0
var _sector_id: String = ""
var _nav := WorldNav.new()
var _nspace_field: NspaceField = null
var _uses_translation_beacon: bool = false
var _debris_entity_ids: Array[String] = []
var _planet_diameter: float = 2000.0
var _habitat_interactable_id: String = ""
var _gate_interactable_id: String = ""
var _habitat_sprite_path: String = ""
var _gate_sprite_path: String = ""
var _volatile_scan_contact: Dictionary = {}
var _volatile_orbital_entity_ids: Array[String] = []
var _volatile_entity_contact_meta: Dictionary = {}
var _volatile_star_setup: Dictionary = {}
var _sky_companion_nav: Array = []
var _sky_parent_nav: Dictionary = {}


func clear_world(world_root: Node2D) -> void:
	for child in world_root.get_children():
		child.free()
	spawned_by_id.clear()
	_orbital_ring = null
	_habitat_node = null
	_jump_gate_node = null
	_orbital_entries.clear()
	_dock_nodes_by_location_id.clear()
	_ring_radius = 0.0
	_ring_period_seconds = 720.0
	_habitat_slot_angle = 0.0
	_gate_radius = 0.0
	_gate_angle = 0.0
	_sector_id = ""
	_nav.reset()
	_nspace_field = null
	_uses_translation_beacon = false
	_debris_entity_ids.clear()
	_volatile_entity_contact_meta.clear()
	_planet_diameter = 2000.0
	_habitat_interactable_id = ""
	_gate_interactable_id = ""
	_habitat_sprite_path = ""
	_gate_sprite_path = ""
	_volatile_scan_contact = {}
	_volatile_orbital_entity_ids.clear()
	_volatile_entity_contact_meta.clear()
	_volatile_star_setup = {}
	_sky_companion_nav.clear()
	_sky_parent_nav = {}


func load_sector(
	world_root: Node2D,
	catalog: Catalog,
	session: GameSession,
	sector_id: String
) -> float:
	clear_world(world_root)

	if VolatileTranslation.is_volatile_sector_id(sector_id):
		return _load_volatile_sector(world_root, catalog, session, sector_id)

	var sector := catalog.get_sector_def(sector_id)
	var play_bounds := 3500.0
	if sector != null:
		play_bounds = sector.play_bounds
	var world_data := catalog.get_world(sector_id)

	_spawn_dust_ring(world_root, play_bounds)

	if world_data.has("planet"):
		_sector_id = sector_id
		_spawn_planetary_layout(world_root, world_data, catalog, session, sector_id)
	elif (
		world_data.has("orbital_ring")
		or world_data.has("jump_gate")
		or world_data.has("translation_beacon")
	):
		_sector_id = sector_id
		_spawn_orbital_station_layout(world_root, world_data, catalog, session, sector_id)
	else:
		_spawn_world_entities(world_root, world_data, catalog, session, play_bounds)

	return play_bounds


func _load_volatile_sector(
	world_root: Node2D,
	catalog: Catalog,
	session: GameSession,
	sector_id: String
) -> float:
	var record := VolatileTranslation.find_by_sector_id(session, sector_id)
	if record.is_empty():
		return 8000.0

	_sector_id = sector_id
	var setup: Dictionary = record.get("setup", {})
	var play_bounds := VolatileTranslation.play_bounds_for(record)
	_spawn_dust_ring(world_root, play_bounds)

	var entry_pos := _entry_position_from_setup(setup)
	if entry_pos.length_squared() > 1.0:
		_gate_radius = entry_pos.length()
		_gate_angle = entry_pos.angle()
	else:
		_gate_radius = 5400.0
		_gate_angle = _gate_angle_for_sector(sector_id)

	_volatile_star_setup = {}
	var star_raw: Variant = setup.get("star", null)
	var star_data: Dictionary = star_raw if typeof(star_raw) == TYPE_DICTIONARY else {}
	_volatile_star_setup = star_data.duplicate(true)
	var contact_name := VolatileTranslation.volatile_star_contact_name(star_data)
	if not contact_name.is_empty():
		var render_data := VolatileTranslation.star_setup_for_render(star_data)
		_spawn_volatile_star(
			world_root,
			render_data,
			setup,
			str(record.get("id", sector_id)),
			session.run_seed
		)

	if VolatileTranslation.return_gate_open(session, sector_id):
		var gate_entity := {
			"id": "volatile_return_gate",
			"kind": "jump_gate",
			"label": "Temporary return gate",
			"interactable": "volatile_return_gate",
		}
		if entry_pos.length_squared() > 1.0:
			gate_entity["position"] = {"x": entry_pos.x, "y": entry_pos.y}
		_spawn_sector_jump_gate(world_root, gate_entity, catalog, session, sector_id)

	var entities: Variant = setup.get("entities", [])
	if typeof(entities) == TYPE_ARRAY:
		for entity_variant in entities:
			if typeof(entity_variant) != TYPE_DICTIONARY:
				continue
			var entity: Dictionary = entity_variant
			_spawn_entity(world_root, entity, catalog, session)
			var entity_id := str(entity.get("id", ""))
			var entity_kind := str(entity.get("kind", ""))
			if entity_kind == "orbital" and not entity_id.is_empty():
				_volatile_orbital_entity_ids.append(entity_id)
			elif entity_kind in ["derelict", "cargo", "marker", "mine"] and not entity_id.is_empty():
				_volatile_entity_contact_meta[entity_id] = entity.duplicate(true)

	var scan_contact: Variant = setup.get("scan_contact", {})
	if typeof(scan_contact) == TYPE_DICTIONARY and not scan_contact.is_empty():
		_spawn_volatile_scan_contact(world_root, scan_contact as Dictionary)

	return play_bounds


func _spawn_volatile_star(
	world_root: Node2D,
	star_data: Dictionary,
	setup: Dictionary,
	seed_key: String,
	run_seed: int = 0
) -> void:
	var rng := RandomNumberGenerator.new()
	var seed_text := "%s:%d:%s" % [str(setup.get("seed", seed_key)), run_seed, seed_key]
	rng.seed = absi(seed_text.hash())
	var entry_pos := _entry_position_from_setup(setup)
	var ref_pos := entry_pos if entry_pos.length_squared() > 1.0 else Vector2(_gate_radius * 0.35, 0.0)
	var star_pos := _pick_star_position(rng, ref_pos)

	var star := LocalStarScript.new()
	star.name = "LocalStar"
	world_root.add_child(star)
	star.configure(star_data, star_pos)
	spawned_by_id["local_star"] = star


func refresh_volatile_return_gate(session: GameSession) -> void:
	if not VolatileTranslation.is_volatile_sector_id(_sector_id):
		return
	if VolatileTranslation.return_gate_open(session, _sector_id):
		return
	if _jump_gate_node == null or not is_instance_valid(_jump_gate_node):
		return
	_jump_gate_node.queue_free()
	_jump_gate_node = null
	spawned_by_id.erase("volatile_return_gate")
	_nav.invalidate()


func load_unspace(
	world_root: Node2D,
	catalog: Catalog,
	session: GameSession,
	unspace_id: String
) -> float:
	clear_world(world_root)

	var unspace := catalog.get_unspace(unspace_id)
	var play_bounds := float(unspace.get("play_bounds", 8000.0))

	var field: NspaceField = NspaceField.new()
	field.name = "NspaceField"
	world_root.add_child(field)
	field.configure(unspace, catalog, session, play_bounds)
	_nspace_field = field

	var portal_node: Node2D = field.get_portal_node()
	if portal_node != null:
		spawned_by_id["n4_exit_portal"] = portal_node

	return play_bounds


func get_nspace_field() -> NspaceField:
	return _nspace_field


func set_unspace_flux_storm(active: bool) -> void:
	if _nspace_field != null and is_instance_valid(_nspace_field):
		_nspace_field.set_flux_storm_active(active)


func start_unspace_fold_animation(
	pivot: Vector2,
	delta_rad: float,
	duration: float = UnspaceFold.FOLD_ANIM_SECONDS
) -> void:
	if _nspace_field != null and is_instance_valid(_nspace_field):
		_nspace_field.start_fold_animation(pivot, delta_rad, duration)


func is_unspace_fold_animating() -> bool:
	if _nspace_field == null or not is_instance_valid(_nspace_field):
		return false
	return _nspace_field.is_fold_animating()


func sync_unspace_shards(session: GameSession, delta: float) -> void:
	if _nspace_field != null and is_instance_valid(_nspace_field):
		_nspace_field.sync_shard_visuals(session, delta)


func apply_salvage_visuals(session: GameSession) -> void:
	for entity_id in spawned_by_id:
		var node: Node = spawned_by_id[entity_id]
		if node is WorldObject:
			node.apply_salvage_state(session)


func get_habitat_world_position() -> Vector2:
	if _habitat_node == null or _orbital_ring == null:
		return Vector2.ZERO
	return _orbital_ring.global_transform * _habitat_node.position


func get_dock_world_position(dock_location_id: String) -> Vector2:
	if not dock_location_id.is_empty() and _dock_nodes_by_location_id.has(dock_location_id):
		var dock_node: Variant = _dock_nodes_by_location_id[dock_location_id]
		if dock_node is Node2D and _orbital_ring != null:
			return _orbital_ring.global_transform * (dock_node as Node2D).position
	return get_habitat_world_position()


func get_jump_gate_world_position() -> Vector2:
	if _jump_gate_node != null:
		return _jump_gate_node.global_position
	return Vector2(cos(_gate_angle) * _gate_radius, sin(_gate_angle) * _gate_radius)


func get_content_radius() -> float:
	return maxf(_gate_radius, _ring_radius) * 1.15


func get_traffic_envelope_radius() -> float:
	if _gate_radius > 0.0:
		return _gate_radius * 1.25
	return 5000.0


func get_dock_orbital_velocity(dock_location_id: String) -> Vector2:
	var dock_world := get_dock_world_position(dock_location_id)
	if dock_world.length_squared() < 0.001 or _ring_period_seconds <= 0.0:
		return Vector2.ZERO
	var omega := TAU / _ring_period_seconds
	return Vector2(dock_world.y, -dock_world.x) * omega


func get_habitat_orbital_velocity() -> Vector2:
	return get_dock_orbital_velocity("")


func get_undock_exit_velocity(dock_location_id: String = "") -> Vector2:
	var dock_world := get_dock_world_position(dock_location_id)
	var outward := dock_world.normalized()
	if outward.length_squared() < 0.001:
		outward = Vector2.UP
	return get_dock_orbital_velocity(dock_location_id) + outward * UNDOCK_LAUNCH_SPEED


func get_dock_launch_position(dock_location_id: String = "") -> Vector2:
	if _orbital_ring == null:
		return Vector2.ZERO

	var dock_world := get_dock_world_position(dock_location_id)
	var outward: Vector2 = dock_world.normalized()
	if outward.length_squared() < 0.001:
		outward = Vector2.UP
	return dock_world + outward * LAUNCH_OFFSET


func get_habitat_launch_position() -> Vector2:
	return get_dock_launch_position("")


func get_jump_gate_approach_position() -> Vector2:
	if _jump_gate_node != null:
		var gate_pos := _jump_gate_node.global_position
		var inward := (Vector2.ZERO - gate_pos).normalized()
		if inward.length_squared() < 0.001:
			inward = Vector2.LEFT
		return gate_pos + inward * GATE_APPROACH_OFFSET

	return Vector2(
		cos(_gate_angle) * _gate_radius,
		sin(_gate_angle) * _gate_radius
	) + Vector2.from_angle(_gate_angle + PI) * GATE_APPROACH_OFFSET


func _spawn_world_entities(
	world_root: Node2D,
	world_data: Dictionary,
	catalog: Catalog,
	session: GameSession,
	fallback_bounds: float
) -> float:
	var entities: Variant = world_data.get("entities", [])
	if typeof(entities) != TYPE_ARRAY:
		return fallback_bounds

	for entity_variant in entities:
		if typeof(entity_variant) != TYPE_DICTIONARY:
			continue
		_spawn_entity(world_root, entity_variant, catalog, session)

	return fallback_bounds


func _spawn_planetary_layout(
	world_root: Node2D,
	world_data: Dictionary,
	catalog: Catalog,
	session: GameSession,
	sector_id: String
) -> void:
	var planet_data: Dictionary = world_data.get("planet", {})
	var planet := _spawn_planet(world_root, planet_data)
	_spawn_orbital_station_layout(world_root, world_data, catalog, session, sector_id, planet)


func _spawn_orbital_station_layout(
	world_root: Node2D,
	world_data: Dictionary,
	catalog: Catalog,
	session: GameSession,
	sector_id: String,
	planet: Node2D = null
) -> void:
	var ring_data: Dictionary = world_data.get("orbital_ring", {})
	_spawn_orbital_ring(world_root, ring_data, catalog, session, sector_id)

	var beacon_data: Variant = world_data.get("translation_beacon", {})
	if typeof(beacon_data) == TYPE_DICTIONARY and not beacon_data.is_empty():
		_spawn_sector_translation_beacon(world_root, beacon_data, catalog, session, sector_id)
	else:
		var gate_data: Dictionary = world_data.get("jump_gate", {})
		_spawn_sector_jump_gate(world_root, gate_data, catalog, session, sector_id)

	var star_pos := _spawn_local_star(world_root, world_data, planet)
	_spawn_sky_backdrop(world_root, world_data, catalog, sector_id, star_pos)

	var entities: Variant = world_data.get("entities", [])
	if typeof(entities) == TYPE_ARRAY:
		for entity_variant in entities:
			if typeof(entity_variant) == TYPE_DICTIONARY:
				_spawn_entity(world_root, entity_variant, catalog, session)


func _spawn_planet(world_root: Node2D, planet_data: Dictionary) -> Node2D:
	_planet_diameter = float(planet_data.get("diameter", 2000.0))
	var planet := PlanetBackdropScript.new()
	planet.name = "Planet"
	world_root.add_child(planet)
	planet.configure(planet_data, _sector_id)
	spawned_by_id["planet"] = planet
	return planet


func _spawn_local_star(world_root: Node2D, world_data: Dictionary, planet: Node2D) -> Vector2:
	var star_data: Variant = world_data.get("star", {})
	if typeof(star_data) != TYPE_DICTIONARY:
		star_data = {"temperature_k": 5800.0, "luminosity": 1.0}

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ref_pos := get_habitat_world_position()
	var star_pos := _pick_star_position(rng, ref_pos)

	var star := LocalStarScript.new()
	star.name = "LocalStar"
	world_root.add_child(star)
	star.configure(star_data, star_pos)
	spawned_by_id["local_star"] = star

	if planet != null and planet.has_method("set_sun"):
		planet.call("set_sun", star_pos, star.get_light_color(), star.get_luminosity())
	return star_pos


func _spawn_sky_backdrop(
	world_root: Node2D,
	world_data: Dictionary,
	catalog: Catalog,
	sector_id: String,
	primary_star_pos: Vector2
) -> void:
	_sky_companion_nav.clear()
	_sky_parent_nav = {}

	var star_block: Dictionary = world_data.get("star", {})
	if typeof(star_block) != TYPE_DICTIONARY:
		star_block = {}
	var primary_resolved := LocalStarScript.defaults_from_star_data(star_block)
	var primary_disc := float(primary_resolved.get("disc_radius", LocalStarScript.DISC_RADIUS_BASE))

	var sector := catalog.get_sector_def(sector_id)
	var primary_catalog_name := _resolve_primary_catalog_star_name(catalog, sector, star_block)
	var primary_catalog := catalog.get_star(primary_catalog_name)
	var primary_cat_lum := float(primary_catalog.get("luminosity", primary_resolved.get("luminosity", 1.0)))

	var companions_raw: Variant = world_data.get("companion_stars", [])
	if typeof(companions_raw) == TYPE_ARRAY:
		var companion_index := 0
		for entry_variant in companions_raw:
			if typeof(entry_variant) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_variant
			var separation_deg := float(entry.get("separation_deg", 0.0))
			var comp_pos := SkyBackdropLayout.companion_world_position(primary_star_pos, separation_deg)
			var render_data: Dictionary = {}
			var contact_name := ""
			var catalog_star_name := ""
			var presentation_only := false
			if entry.has("star"):
				catalog_star_name = str(entry.get("star", "")).strip_edges()
				if catalog_star_name.is_empty():
					continue
				var facts := catalog.get_star(catalog_star_name)
				if facts.is_empty():
					continue
				var disc := SkyBackdropLayout.companion_disc_radius(
					primary_disc, primary_cat_lum, float(facts.get("luminosity", 1.0))
				)
				render_data = {
					"temperature_k": float(facts.get("temperature_k", 5800.0)),
					"luminosity": float(facts.get("luminosity", 1.0)),
					"disc_radius": disc,
				}
				contact_name = catalog_star_name
			else:
				presentation_only = true
				contact_name = str(entry.get("name", "")).strip_edges()
				if contact_name.is_empty():
					continue
				render_data = {
					"temperature_k": float(entry.get("temperature_k", 10000.0)),
					"luminosity": float(entry.get("luminosity", 0.35)),
					"disc_radius": float(entry.get("disc_radius", 3.0)),
				}

			var companion := LocalStarScript.new()
			companion.name = "CompanionStar%d" % companion_index
			world_root.add_child(companion)
			companion.configure(render_data, comp_pos)
			var nav_id := "companion_star_%d" % companion_index
			spawned_by_id[nav_id] = companion
			_sky_companion_nav.append({
				"id": nav_id,
				"name": contact_name,
				"star_name": catalog_star_name if not presentation_only else contact_name,
				"presentation_only": presentation_only,
				"star_temperature_k": render_data.get("temperature_k", 5800.0),
				"star_luminosity": render_data.get("luminosity", 1.0),
			})
			companion_index += 1

	var parent_raw: Variant = world_data.get("parent_body", {})
	if typeof(parent_raw) == TYPE_DICTIONARY and not parent_raw.is_empty():
		var parent_data: Dictionary = parent_raw
		var angular_deg := float(parent_data.get("angular_diameter_deg", 10.0))
		var rings := str(parent_data.get("rings", "none"))
		var distance := SkyBackdropLayout.min_distance_for_parent(angular_deg, rings)
		var rng := RandomNumberGenerator.new()
		rng.seed = absi(("%s:parent" % sector_id).hash())
		var angle := SkyBackdropLayout.pick_parent_angle(primary_star_pos, rng)
		var parent_pos := Vector2.from_angle(angle) * distance
		var parent := SkyParentBodyScript.new()
		parent.name = "ParentBody"
		world_root.add_child(parent)
		parent.configure(parent_data, parent_pos, primary_star_pos, sector_id)
		spawned_by_id["parent_body"] = parent
		_sky_parent_nav = {
			"id": "parent_body",
			"name": parent.get_display_name(),
		}


func _resolve_primary_catalog_star_name(
	catalog: Catalog,
	sector: SectorDef,
	world_star_data: Dictionary
) -> String:
	if sector != null:
		var named := sector.star.strip_edges()
		if not named.is_empty():
			return named
		var system := sector.star_system.strip_edges()
		if system.is_empty():
			return ""
		var names := catalog.list_star_names_for_system(system)
		if names.is_empty():
			return ""
		if names.size() == 1:
			return str(names[0])
		var target_temp := float(world_star_data.get("temperature_k", 0.0))
		var best_name := str(names[0])
		var best_delta := INF
		for star_name in names:
			var facts := catalog.get_star(str(star_name))
			if facts.is_empty():
				continue
			var delta := absf(float(facts.get("temperature_k", 0.0)) - target_temp)
			if delta < best_delta:
				best_delta = delta
				best_name = str(star_name)
		return best_name
	return ""


func get_companion_star_nav_entries() -> Array:
	return _sky_companion_nav.duplicate(true)


func get_parent_body_nav_entry() -> Dictionary:
	return _sky_parent_nav.duplicate(true)


func get_surface_labels() -> Array:
	var planet: Variant = spawned_by_id.get("planet")
	if planet == null or not is_instance_valid(planet):
		return []
	if not planet.has_method("visible_surface_labels"):
		return []
	return planet.visible_surface_labels()


func get_local_star_display() -> Dictionary:
	var star: Variant = spawned_by_id.get("local_star")
	if star == null or not is_instance_valid(star):
		return {}
	if not star.has_method("get_light_color"):
		return {}
	return {
		"world_position": star.global_position,
		"color": star.get_light_color(),
		"luminosity": star.get_luminosity() if star.has_method("get_luminosity") else 1.0,
		"temperature_k": star.get_temperature_k() if star.has_method("get_temperature_k") else 5800.0,
	}


func _pick_star_position(rng: RandomNumberGenerator, ref_pos: Vector2) -> Vector2:
	var gate_pos := Vector2(cos(_gate_angle) * _gate_radius, sin(_gate_angle) * _gate_radius)
	if ref_pos.length_squared() < 1.0:
		ref_pos = Vector2(_ring_radius, 0.0)

	var best_pos := Vector2.ZERO
	var best_score := -INF
	for _attempt in range(48):
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(STAR_MIN_RADIUS, STAR_MAX_RADIUS)
		var pos := Vector2(cos(angle), sin(angle)) * radius
		if pos.distance_to(gate_pos) < STAR_GATE_CLEARANCE:
			continue
		var score := _star_visibility_score(pos, ref_pos)
		if score > best_score:
			best_score = score
			best_pos = pos
		if not _star_hidden_behind_planet_from_ref(pos, ref_pos):
			return pos

	if best_pos.length_squared() > 1.0:
		return best_pos

	var away := ref_pos.angle() + PI + rng.randf_range(-0.9, 0.9)
	return Vector2.from_angle(away) * rng.randf_range(STAR_MIN_RADIUS, STAR_MAX_RADIUS)


func _star_hidden_behind_planet_from_ref(star_pos: Vector2, ref_pos: Vector2) -> bool:
	if star_pos.length_squared() < 1.0 or ref_pos.length_squared() < 1.0:
		return false
	var cos_align := star_pos.normalized().dot(ref_pos.normalized())
	return cos_align > STAR_HABITAT_ALIGN_MAX


func _star_visibility_score(star_pos: Vector2, ref_pos: Vector2) -> float:
	if star_pos.length_squared() < 1.0 or ref_pos.length_squared() < 1.0:
		return 0.0
	return -star_pos.normalized().dot(ref_pos.normalized())


## Returns the live sector nav cache. Callers must not mutate entries; compose a new Array if appending.







func _spawn_volatile_scan_contact(world_root: Node2D, scan_contact: Dictionary) -> void:
	var contact_id := str(scan_contact.get("id", ""))
	if contact_id.is_empty():
		return
	var pos_dict: Dictionary = scan_contact.get("position", {})
	var pos := Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0)))
	var node := Node2D.new()
	node.name = "ScanContact"
	node.position = pos
	node.rotation = float(scan_contact.get("heading_rad", 0.0)) + PI * 0.5
	var sprite_path := str(scan_contact.get("sprite_path", ""))
	if not sprite_path.is_empty():
		var visual := Sprite2D.new()
		var texture := load(sprite_path) as Texture2D
		if texture != null:
			visual.texture = texture
			visual.centered = true
		node.add_child(visual)
	world_root.add_child(node)
	spawned_by_id[contact_id] = node
	_volatile_scan_contact = scan_contact.duplicate(true)


func get_nav_contacts(catalog: Catalog, in_unspace: bool) -> Array:
	return _nav.get_nav_contacts(self, catalog, in_unspace)


func get_traffic_anchors() -> Array:
	return _nav.get_traffic_anchors(self)


func is_traffic_at_destination(world_pos: Vector2, destination_id: String, traffic_config: Dictionary = {}) -> bool:
	return _nav.is_traffic_at_destination(self, world_pos, destination_id, traffic_config)


func is_traffic_route_arrived(
	prev_pos: Vector2,
	world_pos: Vector2,
	destination_id: String,
	traffic_config: Dictionary = {}
) -> bool:
	return _nav.is_traffic_route_arrived(
		self, prev_pos, world_pos, destination_id, traffic_config
	)


func _spawn_orbital_ring(
	world_root: Node2D,
	ring_data: Dictionary,
	catalog: Catalog,
	session: GameSession,
	sector_id: String
) -> void:
	var ring_script: Script = OrbitalRingScript
	var ring := Node2D.new()
	ring.set_script(ring_script)
	ring.name = "OrbitalRing"

	var ring_ref: Node2D = ring
	ring_ref.set("period_seconds", float(ring_data.get("period_seconds", 720.0)))
	ring_ref.set("sector_id", sector_id)
	ring_ref.set("session", session)
	ring_ref.rotation = session.get_orbital_phase(sector_id)

	_ring_radius = float(ring_data.get("radius", 1600.0))
	_ring_period_seconds = float(ring_data.get("period_seconds", 720.0))
	var orbitals: Variant = ring_data.get("orbitals", [])
	if typeof(orbitals) != TYPE_ARRAY:
		world_root.add_child(ring)
		_orbital_ring = ring_ref
		return

	var count: int = orbitals.size()
	for i in range(count):
		if typeof(orbitals[i]) != TYPE_DICTIONARY:
			continue
		var orbital_def: Dictionary = orbitals[i]
		var angle := TAU * float(i) / float(count)
		var instance := _spawn_orbital_instance(orbital_def, catalog, session)
		if instance == null:
			continue

		instance.position = Vector2(cos(angle), sin(angle)) * _ring_radius
		ring.add_child(instance)
		_configure_orbital_instance(instance, orbital_def, catalog, session)

		var entity_id := str(orbital_def.get("id", ""))
		if not entity_id.is_empty():
			spawned_by_id[entity_id] = instance

		var kind := str(orbital_def.get("kind", ""))
		var interactable_id := str(orbital_def.get("interactable", ""))
		if kind == "habitat":
			_habitat_node = instance
			_habitat_slot_angle = angle
			_habitat_sprite_path = str(orbital_def.get("sprite", ""))
			_habitat_interactable_id = interactable_id
		elif kind == "orbital":
			if not interactable_id.is_empty():
				var dock_data := catalog.get_interactable(interactable_id)
				var dock_location_id := str(dock_data.get("dock_location_id", ""))
				if not dock_location_id.is_empty():
					_dock_nodes_by_location_id[dock_location_id] = instance
			_orbital_entries.append({
				"id": entity_id,
				"node": instance,
				"kind": "orbital",
				"label": str(orbital_def.get("label", "")),
				"sprite": str(orbital_def.get("sprite", "")),
				"interactable_id": interactable_id,
			})

	world_root.add_child(ring)
	_orbital_ring = ring_ref
	if ring_ref.has_method("_update_label_counter_rotation"):
		ring_ref.call_deferred("_update_label_counter_rotation")


func _spawn_orbital_instance(
	orbital_def: Dictionary,
	catalog: Catalog,
	session: GameSession
) -> Node2D:
	var kind := str(orbital_def.get("kind", ""))
	var scene_kind := kind
	if kind == "orbital" and not str(orbital_def.get("interactable", "")).is_empty():
		scene_kind = "habitat"
	var scene_path: String = SCENES.get(scene_kind, "")
	if scene_path.is_empty():
		push_error("Unknown orbital kind: %s" % kind)
		return null

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Failed to load orbital scene: %s" % scene_path)
		return null

	var instance: Node2D = packed.instantiate()
	return instance


func _configure_orbital_instance(
	instance: Node2D,
	orbital_def: Dictionary,
	catalog: Catalog,
	session: GameSession
) -> void:
	if instance is WorldObject:
		instance.configure(orbital_def, catalog, session)
	elif instance.has_method("configure"):
		var arg_count := instance.get_method_argument_count("configure")
		if arg_count == 1:
			instance.call("configure", orbital_def)
		else:
			instance.call("configure", orbital_def, catalog, session)


func uses_translation_beacon() -> bool:
	return _uses_translation_beacon


func get_translation_beacon_destination(catalog: Catalog) -> String:
	if not _uses_translation_beacon or catalog == null or _sector_id.is_empty():
		return ""
	var world_data := catalog.get_world(_sector_id)
	var beacon: Variant = world_data.get("translation_beacon", {})
	if typeof(beacon) != TYPE_DICTIONARY:
		return ""
	return str(beacon.get("destination", ""))


func _spawn_sector_jump_gate(
	world_root: Node2D,
	gate_data: Dictionary,
	catalog: Catalog,
	session: GameSession,
	sector_id: String
) -> void:
	_uses_translation_beacon = false
	var instance := _spawn_translate_structure(
		world_root, gate_data, catalog, session, sector_id, false
	)
	if instance is Node2D:
		_jump_gate_node = instance


func _spawn_sector_translation_beacon(
	world_root: Node2D,
	beacon_data: Dictionary,
	catalog: Catalog,
	session: GameSession,
	sector_id: String
) -> void:
	_uses_translation_beacon = true
	var instance := _spawn_translate_structure(
		world_root, beacon_data, catalog, session, sector_id, true
	)
	if instance is Node2D:
		_jump_gate_node = instance


func _spawn_translate_structure(
	world_root: Node2D,
	structure_data: Dictionary,
	catalog: Catalog,
	session: GameSession,
	sector_id: String,
	is_beacon: bool
) -> Node:
	var gate_radius := float(structure_data.get("radius", 5400.0))
	_gate_radius = gate_radius
	_gate_angle = _gate_angle_for_sector(sector_id)

	_gate_interactable_id = str(structure_data.get("interactable", ""))
	_gate_sprite_path = str(structure_data.get("sprite", ""))

	var entity := structure_data.duplicate()
	entity["kind"] = "jump_gate"
	var preset_pos: Variant = entity.get("position", {})
	if typeof(preset_pos) != TYPE_DICTIONARY or preset_pos.is_empty():
		entity["position"] = {
			"x": cos(_gate_angle) * gate_radius,
			"y": sin(_gate_angle) * gate_radius,
		}
	else:
		var pos_dict: Dictionary = preset_pos
		var gate_pos := Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0)))
		_gate_radius = gate_pos.length()
		_gate_angle = gate_pos.angle()

	var instance := _spawn_entity(world_root, entity, catalog, session)
	if is_beacon and instance is Node2D:
		instance.scale = Vector2(0.5, 0.5)
	return instance


func _gate_angle_for_sector(sector_id: String) -> float:
	var hash_value := absi(sector_id.hash())
	return float(hash_value % 10000) / 10000.0 * TAU


func _spawn_dust_ring(
	world_root: Node2D,
	radius: float,
	color: Color = Color(0.35, 0.38, 0.45, 0.35)
) -> void:
	var ring := Line2D.new()
	ring.name = "DustRing"
	ring.width = 2.0
	ring.default_color = color

	var points := PackedVector2Array()
	var segments := 8
	for i in range(segments + 1):
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	ring.points = points
	world_root.add_child(ring)




func _spawn_entity(
	world_root: Node2D,
	entity: Dictionary,
	catalog: Catalog,
	session: GameSession
) -> Node:
	var kind := str(entity.get("kind", ""))
	var entity_id := str(entity.get("id", ""))

	var scene_path: String = SCENES.get(kind, "")
	if scene_path.is_empty():
		push_error("Unknown world entity kind: %s" % kind)
		return null

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Failed to load world scene: %s" % scene_path)
		return null

	var instance: Node = packed.instantiate()
	world_root.add_child(instance)

	if not entity_id.is_empty():
		spawned_by_id[entity_id] = instance
		if kind == "debris":
			_debris_entity_ids.append(entity_id)

	if kind == "debris":
		_configure_debris(instance, entity)
	elif kind in ["derelict", "cargo", "marker"]:
		if instance.has_method("configure"):
			instance.call("configure", entity)
	elif kind == "mine":
		if instance.has_method("configure"):
			instance.call("configure", entity)
	else:
		if instance is Node2D and entity.has("position"):
			var pos: Dictionary = entity.get("position", {})
			(instance as Node2D).position = Vector2(
				float(pos.get("x", 0.0)),
				float(pos.get("y", 0.0))
			)
		if instance is WorldObject:
			instance.configure(entity, catalog, session)
		elif instance is Node2D:
			_configure_orbital_instance(instance as Node2D, entity, catalog, session)
		elif instance.has_method("configure"):
			var arg_count := instance.get_method_argument_count("configure")
			if arg_count == 1:
				instance.call("configure", entity)
			else:
				instance.call("configure", entity, catalog, session)

	return instance


func _entry_position_from_setup(setup: Dictionary) -> Vector2:
	var raw: Variant = setup.get("entry_position", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return Vector2.ZERO
	var dict: Dictionary = raw
	return Vector2(float(dict.get("x", 0.0)), float(dict.get("y", 0.0)))


func _configure_debris(instance: Node2D, entity: Dictionary) -> void:
	var pos: Dictionary = entity.get("position", {})
	instance.position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))

	if entity.has("rotation"):
		instance.rotation = float(entity.get("rotation", 0.0))

	if entity.has("scale"):
		var scale_data: Dictionary = entity.get("scale", {})
		instance.scale = Vector2(float(scale_data.get("x", 1.0)), float(scale_data.get("y", 1.0)))
