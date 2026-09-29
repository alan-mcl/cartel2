class_name WorldLoader
extends RefCounted

const OrbitalRingScript := preload("res://scripts/presentation/orbital_ring.gd")
const NspaceField := preload("res://scripts/presentation/nspace_field.gd")
const PlanetBackdropScript := preload("res://scripts/presentation/planet_backdrop.gd")
const LocalStarScript := preload("res://scripts/presentation/local_star.gd")

const STAR_MIN_RADIUS := 7000.0
const STAR_MAX_RADIUS := 12000.0
const STAR_GATE_CLEARANCE := 800.0
const STAR_HABITAT_ALIGN_MAX := 0.35

const SCENES := {
	"habitat": "res://scenes/world/habitat.tscn",
	"jump_gate": "res://scenes/world/jump_gate.tscn",
	"debris": "res://scenes/world/debris_rock.tscn",
	"orbital": "res://scenes/world/orbital.tscn",
}

const LAUNCH_OFFSET := 220.0
const GATE_APPROACH_OFFSET := 280.0
const UNDOCK_LAUNCH_SPEED := 140.0

var spawned_by_id: Dictionary = {}
var _orbital_ring: Node2D = null
var _habitat_node: Node2D = null
var _jump_gate_node: Node2D = null
var _orbital_entries: Array = []
var _ring_radius: float = 0.0
var _ring_period_seconds: float = 720.0
var _habitat_slot_angle: float = 0.0
var _gate_radius: float = 0.0
var _gate_angle: float = 0.0
var _sector_id: String = ""
var _sector_nav_cache: Array = []
var _sector_nav_cache_ready: bool = false
var _nspace_field: NspaceField = null


func clear_world(world_root: Node2D) -> void:
	for child in world_root.get_children():
		child.queue_free()
	spawned_by_id.clear()
	_orbital_ring = null
	_habitat_node = null
	_jump_gate_node = null
	_orbital_entries.clear()
	_ring_radius = 0.0
	_ring_period_seconds = 720.0
	_habitat_slot_angle = 0.0
	_gate_radius = 0.0
	_gate_angle = 0.0
	_sector_id = ""
	_sector_nav_cache.clear()
	_sector_nav_cache_ready = false
	_nspace_field = null


func load_sector(
	world_root: Node2D,
	catalog: Catalog,
	session: GameSession,
	sector_id: String
) -> float:
	clear_world(world_root)

	var sector := catalog.get_sector(sector_id)
	var play_bounds := float(sector.get("play_bounds", 3500.0))
	var world_data := catalog.get_world(sector_id)

	_spawn_dust_ring(world_root, play_bounds)

	if world_data.has("planet"):
		_sector_id = sector_id
		_spawn_planetary_layout(world_root, world_data, catalog, session, sector_id)
	else:
		_spawn_world_entities(world_root, world_data, catalog, session, play_bounds)

	return play_bounds


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


func apply_salvage_visuals(session: GameSession) -> void:
	for entity_id in spawned_by_id:
		var node: Node = spawned_by_id[entity_id]
		if node is WorldObject:
			node.apply_salvage_state(session)


func get_habitat_world_position() -> Vector2:
	if _habitat_node == null or _orbital_ring == null:
		return Vector2.ZERO
	return _orbital_ring.global_transform * _habitat_node.position


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


func get_habitat_orbital_velocity() -> Vector2:
	var habitat_world := get_habitat_world_position()
	if habitat_world.length_squared() < 0.001 or _ring_period_seconds <= 0.0:
		return Vector2.ZERO
	var omega := TAU / _ring_period_seconds
	return Vector2(habitat_world.y, -habitat_world.x) * omega


func get_undock_exit_velocity() -> Vector2:
	var habitat_world := get_habitat_world_position()
	var outward := habitat_world.normalized()
	if outward.length_squared() < 0.001:
		outward = Vector2.UP
	return get_habitat_orbital_velocity() + outward * UNDOCK_LAUNCH_SPEED


func get_habitat_launch_position() -> Vector2:
	if _habitat_node == null or _orbital_ring == null:
		return Vector2.ZERO

	var habitat_world: Vector2 = _orbital_ring.global_transform * _habitat_node.position
	var outward: Vector2 = habitat_world.normalized()
	if outward.length_squared() < 0.001:
		outward = Vector2.UP
	return habitat_world + outward * LAUNCH_OFFSET


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

	var ring_data: Dictionary = world_data.get("orbital_ring", {})
	_spawn_orbital_ring(world_root, ring_data, catalog, session, sector_id)

	var gate_data: Dictionary = world_data.get("jump_gate", {})
	_spawn_sector_jump_gate(world_root, gate_data, catalog, session, sector_id)

	_spawn_local_star(world_root, world_data, planet)

	var entities: Variant = world_data.get("entities", [])
	if typeof(entities) == TYPE_ARRAY:
		for entity_variant in entities:
			if typeof(entity_variant) == TYPE_DICTIONARY:
				_spawn_entity(world_root, entity_variant, catalog, session)


func _spawn_planet(world_root: Node2D, planet_data: Dictionary) -> Node2D:
	var planet := PlanetBackdropScript.new()
	planet.name = "Planet"
	world_root.add_child(planet)
	planet.configure(planet_data, _sector_id)
	spawned_by_id["planet"] = planet
	return planet


func _spawn_local_star(world_root: Node2D, world_data: Dictionary, planet: Node2D) -> void:
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
func get_nav_contacts(catalog: Catalog, in_unspace: bool) -> Array:
	if in_unspace:
		return _build_unspace_nav_contacts(catalog)

	_ensure_sector_nav_cache(catalog)
	_refresh_sector_nav_positions()
	return _sector_nav_cache


func _build_unspace_nav_contacts(catalog: Catalog) -> Array:
	if _nspace_field == null:
		return []

	var portal_title := "Exit Portal"
	var interactable_data := catalog.get_interactable("unspace_exit")
	if not interactable_data.is_empty():
		portal_title = str(interactable_data.get("title", portal_title))

	return [{
		"id": "exit_portal",
		"name": portal_title,
		"short_label": "X",
		"contact_kind": "landmark",
		"position": _nspace_field.get_portal_position(),
	}] + _nspace_field.get_inhabitant_contacts()


func _ensure_sector_nav_cache(catalog: Catalog) -> void:
	if _sector_nav_cache_ready:
		return

	_sector_nav_cache.clear()
	var sector := catalog.get_sector(_sector_id) if not _sector_id.is_empty() else {}
	_sector_nav_cache.append({
		"id": "planet",
		"name": str(sector.get("name", "Planet")),
		"short_label": "P",
		"contact_kind": "landmark",
		"position": Vector2.ZERO,
	})
	if _habitat_node != null:
		_sector_nav_cache.append({
			"id": "habitat",
			"name": _resolve_contact_name(_habitat_node, catalog, "Habitat"),
			"short_label": "H",
			"contact_kind": "landmark",
			"position": Vector2.ZERO,
		})
	if _jump_gate_node != null:
		_sector_nav_cache.append({
			"id": "jump_gate",
			"name": _resolve_contact_name(_jump_gate_node, catalog, "Jump Gate"),
			"short_label": "G",
			"contact_kind": "landmark",
			"position": Vector2.ZERO,
		})
	if spawned_by_id.has("local_star"):
		_sector_nav_cache.append({
			"id": "local_star",
			"name": "Local Star",
			"short_label": "S",
			"contact_kind": "star",
			"position": Vector2.ZERO,
		})
	for entry_variant in _orbital_entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var orbital_node: Variant = entry.get("node")
		if orbital_node is Node2D and _orbital_ring != null:
			_sector_nav_cache.append({
				"id": str(entry.get("id", "")),
				"name": str(entry.get("label", "")),
				"short_label": "",
				"contact_kind": "orbital",
				"position": Vector2.ZERO,
			})
	_sector_nav_cache_ready = true


func _refresh_sector_nav_positions() -> void:
	for entry_variant in _sector_nav_cache:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		match str(entry.get("id", "")):
			"habitat":
				entry["position"] = get_habitat_world_position()
			"jump_gate":
				entry["position"] = get_jump_gate_world_position()
			"local_star":
				var star_display := get_local_star_display()
				if star_display.is_empty():
					entry["position"] = Vector2.ZERO
				else:
					entry["position"] = star_display.get("world_position", Vector2.ZERO)
					entry["nav_color"] = star_display.get("color", Color.WHITE)
			"planet":
				entry["position"] = Vector2.ZERO
			_:
				if str(entry.get("contact_kind", "")) == "orbital":
					entry["position"] = _orbital_contact_position(str(entry.get("id", "")))


func _orbital_contact_position(orbital_id: String) -> Vector2:
	for entry_variant in _orbital_entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("id", "")) != orbital_id:
			continue
		var orbital_node: Variant = entry.get("node")
		if orbital_node is Node2D and _orbital_ring != null:
			return _orbital_ring.global_transform * orbital_node.position
	return Vector2.ZERO


func get_traffic_anchors() -> Array:
	var anchors: Array = []
	if _habitat_node != null:
		anchors.append({
			"id": "habitat",
			"kind": "habitat",
			"position": get_habitat_world_position(),
		})
	if _jump_gate_node != null:
		anchors.append({
			"id": "jump_gate",
			"kind": "jump_gate",
			"position": get_jump_gate_world_position(),
		})
	for entry_variant in _orbital_entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var orbital_node: Variant = entry.get("node")
		if orbital_node is Node2D and _orbital_ring != null:
			anchors.append({
				"id": str(entry.get("id", "")),
				"kind": "orbital",
				"position": _orbital_ring.global_transform * orbital_node.position,
			})
	return anchors


func is_traffic_at_destination(world_pos: Vector2, destination_id: String, traffic_config: Dictionary = {}) -> bool:
	return is_traffic_route_arrived(world_pos, world_pos, destination_id, traffic_config)


func is_traffic_route_arrived(
	prev_pos: Vector2,
	world_pos: Vector2,
	destination_id: String,
	traffic_config: Dictionary = {}
) -> bool:
	var node := _destination_node(destination_id)
	if node == null or not is_instance_valid(node):
		return false

	var interactable := node.get_node_or_null("Interactable") as Area2D
	if interactable != null and is_instance_valid(interactable):
		if _point_in_interactable(world_pos, interactable):
			return true
		return _segment_intersects_interactable(prev_pos, world_pos, interactable)

	var anchor_pos := _destination_world_position(node, destination_id)
	if anchor_pos.length_squared() < 1.0:
		return false
	var radius := float(traffic_config.get("orbital_arrival_radius", 90.0))
	if world_pos.distance_to(anchor_pos) <= radius:
		return true
	return _segment_intersects_circle(prev_pos, world_pos, anchor_pos, radius)


func _destination_node(destination_id: String) -> Node2D:
	if destination_id == "habitat":
		return _habitat_node
	if destination_id == "jump_gate":
		return _jump_gate_node
	for entry_variant in _orbital_entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("id", "")) == destination_id:
			var orbital_node: Variant = entry.get("node")
			if orbital_node is Node2D:
				return orbital_node
	return null


func _destination_world_position(node: Node2D, destination_id: String) -> Vector2:
	if destination_id == "habitat":
		return get_habitat_world_position()
	if destination_id == "jump_gate":
		return get_jump_gate_world_position()
	if _orbital_ring != null and node.get_parent() == _orbital_ring:
		return _orbital_ring.global_transform * node.position
	return node.global_position


func _point_in_interactable(world_pos: Vector2, area: Area2D) -> bool:
	var collision := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		return false
	if collision.shape is CircleShape2D:
		var circle := collision.shape as CircleShape2D
		var center := collision.global_transform.origin
		var scale := maxf(collision.global_scale.x, collision.global_scale.y)
		return world_pos.distance_to(center) <= circle.radius * scale
	return false


func _segment_intersects_interactable(from_pos: Vector2, to_pos: Vector2, area: Area2D) -> bool:
	var collision := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		return false
	if collision.shape is CircleShape2D:
		var circle := collision.shape as CircleShape2D
		var center := collision.global_transform.origin
		var scale := maxf(collision.global_scale.x, collision.global_scale.y)
		return _segment_intersects_circle(from_pos, to_pos, center, circle.radius * scale)
	return false


func _segment_intersects_circle(from_pos: Vector2, to_pos: Vector2, center: Vector2, radius: float) -> bool:
	if from_pos.distance_to(center) <= radius or to_pos.distance_to(center) <= radius:
		return true
	var ab := to_pos - from_pos
	var ab_len_sq := ab.length_squared()
	if ab_len_sq < 0.001:
		return from_pos.distance_to(center) <= radius
	var ac := center - from_pos
	var t := clampf(ac.dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest := from_pos + ab * t
	return closest.distance_to(center) <= radius


func _resolve_contact_name(node: Node, _catalog: Catalog, fallback: String) -> String:
	if node is WorldObject:
		var world_object: WorldObject = node
		var interactable: Interactable = world_object.get_node_or_null("Interactable")
		if interactable != null and interactable.definition != null:
			return interactable.get_title()

	var label: Label = node.get_node_or_null("Label")
	if label != null and not label.text.is_empty():
		return label.text

	return fallback


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
		if kind == "habitat":
			_habitat_node = instance
			_habitat_slot_angle = angle
		elif kind == "orbital":
			_orbital_entries.append({
				"id": entity_id,
				"node": instance,
				"kind": "orbital",
				"label": str(orbital_def.get("label", "")),
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
	var scene_path: String = SCENES.get(kind, "")
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


func _spawn_sector_jump_gate(
	world_root: Node2D,
	gate_data: Dictionary,
	catalog: Catalog,
	session: GameSession,
	sector_id: String
) -> void:
	var gate_radius := float(gate_data.get("radius", 5400.0))
	_gate_radius = gate_radius
	_gate_angle = _gate_angle_for_sector(sector_id)

	var entity := gate_data.duplicate()
	entity["kind"] = "jump_gate"
	entity["position"] = {
		"x": cos(_gate_angle) * gate_radius,
		"y": sin(_gate_angle) * gate_radius,
	}

	var instance := _spawn_entity(world_root, entity, catalog, session)
	if instance is Node2D:
		_jump_gate_node = instance


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
		_configure_debris(instance, entity)
	elif instance is WorldObject:
		instance.configure(entity, catalog, session)
	elif instance.has_method("configure"):
		instance.call("configure", entity, catalog, session)

	return instance


func _configure_debris(instance: Node2D, entity: Dictionary) -> void:
	var pos: Dictionary = entity.get("position", {})
	instance.position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))

	if entity.has("rotation"):
		instance.rotation = float(entity.get("rotation", 0.0))

	if entity.has("scale"):
		var scale_data: Dictionary = entity.get("scale", {})
		instance.scale = Vector2(float(scale_data.get("x", 1.0)), float(scale_data.get("y", 1.0)))
