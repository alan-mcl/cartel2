class_name WorldLoader
extends RefCounted

const SCENES := {
	"habitat": "res://scenes/world/habitat.tscn",
	"jump_gate": "res://scenes/world/jump_gate.tscn",
	"beacon": "res://scenes/world/beacon.tscn",
	"wreck": "res://scenes/world/wreck.tscn",
	"debris": "res://scenes/world/debris_rock.tscn",
	"hazard": "res://scenes/world/hazard.tscn",
}

var spawned_by_id: Dictionary = {}


func clear_world(world_root: Node2D) -> void:
	for child in world_root.get_children():
		child.queue_free()
	spawned_by_id.clear()


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

	return _spawn_world_entities(world_root, world_data, catalog, session, play_bounds)


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
) -> void:
	var kind := str(entity.get("kind", ""))
	var entity_id := str(entity.get("id", ""))

	if kind == "planet_limb":
		_spawn_planet_limb(world_root, entity)
		return

	var scene_path: String = SCENES.get(kind, "")
	if scene_path.is_empty():
		push_error("Unknown world entity kind: %s" % kind)
		return

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Failed to load world scene: %s" % scene_path)
		return

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
