class_name WorldLoader
extends RefCounted

const OrbitalRingScript := preload("res://scripts/presentation/orbital_ring.gd")

const SCENES := {
	"habitat": "res://scenes/world/habitat.tscn",
	"jump_gate": "res://scenes/world/jump_gate.tscn",
	"beacon": "res://scenes/world/beacon.tscn",
	"wreck": "res://scenes/world/wreck.tscn",
	"debris": "res://scenes/world/debris_rock.tscn",
	"hazard": "res://scenes/world/hazard.tscn",
	"orbital": "res://scenes/world/orbital.tscn",
}

const LAUNCH_OFFSET := 220.0
const GATE_APPROACH_OFFSET := 280.0

var spawned_by_id: Dictionary = {}
var _orbital_ring: Node2D = null
var _habitat_node: Node2D = null
var _jump_gate_node: Node2D = null
var _ring_radius: float = 0.0
var _habitat_slot_angle: float = 0.0
var _gate_radius: float = 0.0
var _gate_angle: float = 0.0
var _sector_id: String = ""


func clear_world(world_root: Node2D) -> void:
	for child in world_root.get_children():
		child.queue_free()
	spawned_by_id.clear()
	_orbital_ring = null
	_habitat_node = null
	_jump_gate_node = null
	_ring_radius = 0.0
	_habitat_slot_angle = 0.0
	_gate_radius = 0.0
	_gate_angle = 0.0
	_sector_id = ""


func load_sector(
	world_root: Node2D,
	catalog: Catalog,
	session: PrototypeSession,
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
	session: PrototypeSession,
	unspace_id: String
) -> float:
	clear_world(world_root)

	var unspace := catalog.get_unspace(unspace_id)
	var play_bounds := float(unspace.get("play_bounds", 4000.0))
	var world_id := str(unspace.get("world_id", unspace_id))
	var world_data := catalog.get_world(world_id)

	_spawn_dust_ring(
		world_root,
		play_bounds,
		Color(0.55, 0.25, 0.75, 0.42)
	)

	return _spawn_world_entities(world_root, world_data, catalog, session, play_bounds)


func apply_salvage_visuals(session: PrototypeSession) -> void:
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
	session: PrototypeSession,
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
	session: PrototypeSession,
	sector_id: String
) -> void:
	var planet_data: Dictionary = world_data.get("planet", {})
	_spawn_planet(world_root, planet_data)

	var ring_data: Dictionary = world_data.get("orbital_ring", {})
	_spawn_orbital_ring(world_root, ring_data, catalog, session, sector_id)

	var gate_data: Dictionary = world_data.get("jump_gate", {})
	_spawn_sector_jump_gate(world_root, gate_data, catalog, session, sector_id)


func _spawn_planet(world_root: Node2D, planet_data: Dictionary) -> void:
	var planet := Sprite2D.new()
	planet.name = "Planet"
	planet.z_index = -50

	var sprite_path := str(planet_data.get("sprite", "res://assets/world/planet.png"))
	var texture := load(sprite_path) as Texture2D
	if texture != null:
		planet.texture = texture

	planet.centered = true
	planet.position = Vector2.ZERO

	var diameter := float(planet_data.get("diameter", 2000.0))
	if texture != null:
		var tex_size := texture.get_size()
		if tex_size.x > 0.0:
			planet.scale = Vector2.ONE * (diameter / tex_size.x)

	if planet_data.has("modulate"):
		planet.modulate = Color(str(planet_data.get("modulate")))

	world_root.add_child(planet)


func _spawn_orbital_ring(
	world_root: Node2D,
	ring_data: Dictionary,
	catalog: Catalog,
	session: PrototypeSession,
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

	world_root.add_child(ring)
	_orbital_ring = ring_ref
	if ring_ref.has_method("_update_label_counter_rotation"):
		ring_ref.call_deferred("_update_label_counter_rotation")


func _spawn_orbital_instance(
	orbital_def: Dictionary,
	catalog: Catalog,
	session: PrototypeSession
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
	session: PrototypeSession
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
	session: PrototypeSession,
	sector_id: String
) -> void:
	var gate_radius := float(gate_data.get("radius", 2700.0))
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
	session: PrototypeSession
) -> Node:
	var kind := str(entity.get("kind", ""))
	var entity_id := str(entity.get("id", ""))

	if kind == "planet_limb":
		_spawn_planet_limb(world_root, entity)
		return null

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
	elif kind == "hazard" and instance is NspaceHazard:
		instance.configure(entity)
	elif instance is WorldObject:
		instance.configure(entity, catalog, session)
	elif instance.has_method("configure"):
		instance.call("configure", entity, catalog, session)

	return instance


func _spawn_planet_limb(world_root: Node2D, entity: Dictionary) -> void:
	var limb := Sprite2D.new()
	limb.name = str(entity.get("id", "PlanetLimb"))

	var pos: Dictionary = entity.get("position", {})
	limb.position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))

	if entity.has("scale"):
		var scale_data: Dictionary = entity.get("scale", {})
		limb.scale = Vector2(float(scale_data.get("x", 1.0)), float(scale_data.get("y", 1.0)))

	var sprite_path := str(entity.get("sprite", "res://assets/world/planet_limb.png"))
	var texture := load(sprite_path) as Texture2D
	if texture != null:
		limb.texture = texture

	limb.centered = true

	if entity.has("modulate"):
		limb.modulate = Color(str(entity.get("modulate")))

	world_root.add_child(limb)
	var entity_id := str(entity.get("id", ""))
	if not entity_id.is_empty():
		spawned_by_id[entity_id] = limb


func _configure_debris(instance: Node2D, entity: Dictionary) -> void:
	var pos: Dictionary = entity.get("position", {})
	instance.position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))

	if entity.has("rotation"):
		instance.rotation = float(entity.get("rotation", 0.0))

	if entity.has("scale"):
		var scale_data: Dictionary = entity.get("scale", {})
		instance.scale = Vector2(float(scale_data.get("x", 1.0)), float(scale_data.get("y", 1.0)))
