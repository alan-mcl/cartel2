class_name WorldEntityRegistry
extends RefCounted

## Scene path, spawn configuration, and volatile sensor profile per `entities[]` kind.

const SCENE_PATHS := {
	"habitat": "res://scenes/world/habitat.tscn",
	"jump_gate": "res://scenes/world/jump_gate.tscn",
	"debris": "res://scenes/world/debris_rock.tscn",
	"orbital": "res://scenes/world/orbital.tscn",
	"derelict": "res://scenes/world/volatile_static.tscn",
	"cargo": "res://scenes/world/volatile_static.tscn",
	"marker": "res://scenes/world/volatile_static.tscn",
	"mine": "res://scenes/world/proximity_mine.tscn",
}

const CONFIGURE_DEBRIS := "debris"
const CONFIGURE_ENTITY_ONLY := "entity_only"
const CONFIGURE_WORLD_OBJECT := "world_object"

## kind -> { configure, track_debris, apply_star_light, volatile_meta, volatile_contact }
const DEFINITIONS := {
	"habitat": {"configure": CONFIGURE_WORLD_OBJECT},
	"jump_gate": {"configure": CONFIGURE_WORLD_OBJECT},
	"orbital": {"configure": CONFIGURE_WORLD_OBJECT},
	"debris": {
		"configure": CONFIGURE_DEBRIS,
		"track_debris": true,
		"apply_star_light": true,
	},
	"derelict": {
		"configure": CONFIGURE_ENTITY_ONLY,
		"volatile_meta": true,
		"volatile_contact": {
			"contact_kind": "debris",
			"use_health_ratio": true,
		},
	},
	"cargo": {
		"configure": CONFIGURE_ENTITY_ONLY,
		"volatile_meta": true,
		"volatile_contact": {
			"contact_kind": "debris",
			"use_health_ratio": true,
		},
	},
	"marker": {
		"configure": CONFIGURE_ENTITY_ONLY,
		"volatile_meta": true,
		"volatile_contact": {
			"contact_kind": "landmark",
			"lock_sprite_radius": 40.0,
		},
	},
	"mine": {
		"configure": CONFIGURE_ENTITY_ONLY,
		"volatile_meta": true,
		"volatile_contact": {
			"contact_kind": "landmark",
			"fixed_name": "Mine",
			"lock_sprite_radius": 36.0,
		},
	},
}


static func registered_kinds() -> Array:
	return DEFINITIONS.keys()


static func definition(kind: String) -> Dictionary:
	var key := kind.strip_edges()
	if not DEFINITIONS.has(key):
		return {}
	return (DEFINITIONS[key] as Dictionary).duplicate(true)


static func scene_path_for(kind: String, entity: Dictionary = {}) -> String:
	var scene_kind := kind.strip_edges()
	if scene_kind == "orbital" and not str(entity.get("interactable", "")).is_empty():
		scene_kind = "habitat"
	if not SCENE_PATHS.has(scene_kind):
		return ""
	return SCENE_PATHS[scene_kind]


static func tracks_volatile_meta(kind: String) -> bool:
	var def := definition(kind)
	return bool(def.get("volatile_meta", false))


static func volatile_contact_profile(kind: String) -> Dictionary:
	var def := definition(kind)
	var profile: Variant = def.get("volatile_contact", {})
	if typeof(profile) != TYPE_DICTIONARY:
		return {}
	return (profile as Dictionary).duplicate(true)


static func apply_post_spawn(
	loader: WorldLoader,
	kind: String,
	instance: Node,
	entity: Dictionary,
	catalog: Catalog,
	session: GameSession
) -> void:
	var def := definition(kind)
	var style := str(def.get("configure", ""))
	match style:
		CONFIGURE_DEBRIS:
			if instance is Node2D:
				loader._configure_debris(instance as Node2D, entity)
			if bool(def.get("apply_star_light", false)):
				loader._try_apply_star_light_to_debris_node(instance)
		CONFIGURE_ENTITY_ONLY:
			if instance.has_method("configure"):
				instance.call("configure", entity)
		CONFIGURE_WORLD_OBJECT, _:
			_apply_world_object_style(loader, instance, entity, catalog, session)


static func _apply_world_object_style(
	loader: WorldLoader,
	instance: Node,
	entity: Dictionary,
	catalog: Catalog,
	session: GameSession
) -> void:
	if instance is Node2D and entity.has("position"):
		var pos: Dictionary = entity.get("position", {})
		(instance as Node2D).position = Vector2(
			float(pos.get("x", 0.0)),
			float(pos.get("y", 0.0))
		)
	if instance is WorldObject:
		(instance as WorldObject).configure(entity, catalog, session)
	elif instance is Node2D:
		loader._configure_orbital_instance(instance as Node2D, entity, catalog, session)
	elif instance.has_method("configure"):
		var arg_count := instance.get_method_argument_count("configure")
		if arg_count == 1:
			instance.call("configure", entity)
		else:
			instance.call("configure", entity, catalog, session)


static func build_volatile_prop_contact(
	kind: String,
	entity_id: String,
	meta: Dictionary,
	prop_node: Node2D
) -> Dictionary:
	var profile := volatile_contact_profile(kind)
	if profile.is_empty():
		return {}
	var label := str(meta.get("label", kind.capitalize()))
	if profile.has("fixed_name"):
		label = str(profile.get("fixed_name", label))
	var contact := {
		"id": entity_id,
		"name": label,
		"short_label": "",
		"position": prop_node.global_position,
		"velocity": Vector2.ZERO,
		"heading_rad": prop_node.global_rotation - PI * 0.5,
		"contact_kind": str(profile.get("contact_kind", "landmark")),
	}
	if bool(profile.get("use_health_ratio", false)):
		var health_ratio := 1.0
		if prop_node.has_method("health_ratio"):
			health_ratio = float(prop_node.call("health_ratio"))
		contact["debris_health_ratio"] = health_ratio
	return contact


static func volatile_lock_sprite_radius(kind: String) -> float:
	var profile := volatile_contact_profile(kind)
	return float(profile.get("lock_sprite_radius", -1.0))