class_name WorldNav
extends RefCounted

const HullHitboxScript := preload("res://scripts/presentation/hull_hitbox.gd")
const DEBRIS_SPRITE := "res://assets/world/debris.svg"

var _sector_nav_cache: Array = []
var _sector_nav_cache_ready: bool = false


func reset() -> void:
	_sector_nav_cache.clear()
	_sector_nav_cache_ready = false


func invalidate() -> void:
	_sector_nav_cache_ready = false


func get_nav_contacts(loader: WorldLoader, catalog: Catalog, in_unspace: bool) -> Array:
	if in_unspace:
		return _build_unspace_nav_contacts(loader, catalog)

	if VolatileTranslation.is_volatile_sector_id(loader._sector_id):
		return _build_volatile_site_contacts(loader, catalog)

	_ensure_sector_nav_cache(loader, catalog)
	_refresh_sector_nav_positions(loader)
	var contacts: Array = []
	contacts.append_array(_sector_nav_cache)
	contacts.append_array(_build_debris_contacts(loader))
	return contacts

func _build_unspace_nav_contacts(loader: WorldLoader, catalog: Catalog) -> Array:
	if loader._nspace_field == null:
		return []

	var portal_title := "Exit Portal"
	var interactable_data := catalog.get_interactable("unspace_exit")
	if not interactable_data.is_empty():
		portal_title = str(interactable_data.get("title", portal_title))

	var portal_contact := {
		"id": "exit_portal",
		"name": portal_title,
		"short_label": "X",
		"contact_kind": "landmark",
		"position": loader._nspace_field.get_portal_position(),
		"interactable_id": "unspace_exit",
	}
	_merge_lock_display_fields(loader, portal_contact, "", 120.0)
	var contacts: Array = [portal_contact]
	for inhabitant_variant in loader._nspace_field.get_inhabitant_contacts():
		if typeof(inhabitant_variant) != TYPE_DICTIONARY:
			continue
		var inhabitant: Dictionary = inhabitant_variant
		_merge_lock_display_fields(loader, inhabitant, "", 36.0)
		contacts.append(inhabitant)
	return contacts

func _ensure_sector_nav_cache(loader: WorldLoader, catalog: Catalog) -> void:
	if _sector_nav_cache_ready:
		return

	_sector_nav_cache.clear()
	var sector: SectorDef = null
	if not loader._sector_id.is_empty():
		sector = catalog.get_sector_def(loader._sector_id)
	var world_data := catalog.get_world(loader._sector_id) if not loader._sector_id.is_empty() else {}
	var star_data: Dictionary = world_data.get("star", {})
	if loader.spawned_by_id.has("planet"):
		var planet_contact := {
			"id": "planet",
			"name": _planet_contact_name(sector),
			"short_label": "P",
			"contact_kind": "landmark",
			"landmark_role": "planet",
			"position": Vector2.ZERO,
			"planet_diameter_m": loader._planet_diameter,
		}
		_merge_lock_display_fields(loader, planet_contact, "", loader._planet_diameter * 0.5)
		_sector_nav_cache.append(planet_contact)
	if loader._habitat_node != null:
		var habitat_contact := {
			"id": "habitat",
			"name": _resolve_contact_name(loader, loader._habitat_node, catalog, "Habitat"),
			"short_label": "H",
			"contact_kind": "landmark",
			"landmark_role": "habitat",
			"position": Vector2.ZERO,
			"interactable_id": loader._habitat_interactable_id,
		}
		_merge_lock_display_fields(loader, habitat_contact, loader._habitat_sprite_path)
		_sector_nav_cache.append(habitat_contact)
	if loader._jump_gate_node != null:
		var gate_short := "B" if loader._uses_translation_beacon else "G"
		var gate_default := "Translation Beacon" if loader._uses_translation_beacon else "Jump Gate"
		var gate_contact := {
			"id": "jump_gate",
			"name": _resolve_contact_name(loader, loader._jump_gate_node, catalog, gate_default),
			"short_label": gate_short,
			"contact_kind": "landmark",
			"landmark_role": "jump_gate" if not loader._uses_translation_beacon else "translation_beacon",
			"position": Vector2.ZERO,
			"interactable_id": loader._gate_interactable_id,
			"translation_beacon": loader._uses_translation_beacon,
		}
		_merge_lock_display_fields(loader, gate_contact, loader._gate_sprite_path, 140.0)
		_sector_nav_cache.append(gate_contact)
	if loader.spawned_by_id.has("local_star"):
		var star_label := _star_contact_name(sector)
		var star_contact := {
			"id": "local_star",
			"name": star_label,
			"short_label": "S",
			"contact_kind": "star",
			"position": Vector2.ZERO,
			"star_name": star_label,
			"star_temperature_k": float(star_data.get("temperature_k", 0.0)),
			"star_luminosity": float(star_data.get("luminosity", 0.0)),
		}
		_merge_lock_display_fields(loader, star_contact, "", 220.0)
		_sector_nav_cache.append(star_contact)
	for entry_variant in loader._orbital_entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var orbital_node: Variant = entry.get("node")
		if orbital_node is Node2D and loader._orbital_ring != null:
			var orbital_sprite := str(entry.get("sprite", ""))
			var orbital_contact := {
				"id": str(entry.get("id", "")),
				"name": str(entry.get("label", "")),
				"short_label": "",
				"contact_kind": "orbital",
				"position": Vector2.ZERO,
				"orbital_sprite": orbital_sprite,
				"interactable_id": str(entry.get("interactable_id", "")),
			}
			_merge_lock_display_fields(loader, orbital_contact, orbital_sprite, 48.0)
			_sector_nav_cache.append(orbital_contact)
	_sector_nav_cache_ready = true

func _refresh_sector_nav_positions(loader: WorldLoader) -> void:
	for entry_variant in _sector_nav_cache:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		match str(entry.get("id", "")):
			"habitat":
				entry["position"] = loader.get_habitat_world_position()
			"jump_gate":
				entry["position"] = loader.get_jump_gate_world_position()
			"local_star":
				var star_display := loader.get_local_star_display()
				if star_display.is_empty():
					entry["position"] = Vector2.ZERO
				else:
					entry["position"] = star_display.get("world_position", Vector2.ZERO)
					entry["nav_color"] = star_display.get("color", Color.WHITE)
			"planet":
				entry["position"] = Vector2.ZERO
			_:
				if str(entry.get("contact_kind", "")) == "orbital":
					entry["position"] = _orbital_contact_position(loader, str(entry.get("id", "")))
					entry["heading_rad"] = _orbital_contact_heading(loader, str(entry.get("id", "")))

func _orbital_contact_position(loader: WorldLoader, orbital_id: String) -> Vector2:
	for entry_variant in loader._orbital_entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("id", "")) != orbital_id:
			continue
		var orbital_node: Variant = entry.get("node")
		if orbital_node is Node2D and loader._orbital_ring != null:
			return loader._orbital_ring.global_transform * orbital_node.position
	return Vector2.ZERO

func _orbital_contact_heading(loader: WorldLoader, orbital_id: String) -> float:
	for entry_variant in loader._orbital_entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("id", "")) != orbital_id:
			continue
		var orbital_node: Variant = entry.get("node")
		if orbital_node is Node2D and loader._orbital_ring != null:
			return orbital_node.global_rotation - PI * 0.5
	return 0.0

func _merge_lock_display_fields(loader: WorldLoader, contact: Dictionary,
	sprite_path: String,
	radius_override: float = -1.0) -> void:
	contact["sprite_path"] = sprite_path
	contact["lock_hull_display_scale"] = 1.0
	if not sprite_path.is_empty():
		var canvas: Vector2 = HullHitboxScript.sprite_canvas_size(sprite_path)
		var half := maxf(canvas.x, canvas.y) * 0.5
		contact["lock_hull_radius"] = maxf(half, TargetLock.MIN_HULL_RADIUS)
	elif radius_override >= 0.0:
		contact["lock_hull_radius"] = radius_override
	else:
		contact["lock_hull_radius"] = 18.0
	contact["heading_rad"] = float(contact.get("heading_rad", 0.0))

func _build_volatile_site_contacts(loader: WorldLoader, _catalog: Catalog) -> Array:
	var contacts: Array = []
	if loader._jump_gate_node != null and is_instance_valid(loader._jump_gate_node):
		var gate_contact := {
			"id": "jump_gate",
			"name": "Temporary return gate",
			"short_label": "G",
			"contact_kind": "landmark",
			"landmark_role": "jump_gate",
			"position": loader.get_jump_gate_world_position(),
			"interactable_id": "volatile_return_gate",
		}
		_merge_lock_display_fields(loader, gate_contact, loader._gate_sprite_path, 140.0)
		contacts.append(gate_contact)

	for orbital_id in loader._volatile_orbital_entity_ids:
		var node: Variant = loader.spawned_by_id.get(orbital_id)
		if node == null or not is_instance_valid(node) or not (node is Node2D):
			continue
		var orbital_node := node as Node2D
		var orbital_contact := {
			"id": orbital_id,
			"name": "Survey contact",
			"short_label": "",
			"contact_kind": "orbital",
			"position": orbital_node.global_position,
			"heading_rad": orbital_node.global_rotation - PI * 0.5,
		}
		_merge_lock_display_fields(loader, orbital_contact, "res://assets/world/orbitals/array.svg", 48.0)
		contacts.append(orbital_contact)

	contacts.append_array(_build_debris_contacts(loader))
	contacts.append_array(_build_volatile_prop_contacts(loader))

	if loader.spawned_by_id.has("local_star"):
		var star_display := loader.get_local_star_display()
		var volatile_star_name := VolatileTranslation.volatile_star_contact_name(loader._volatile_star_setup)
		if volatile_star_name.is_empty():
			volatile_star_name = VolatileTranslation.UNCATALOGUED_STAR_LABEL
		var star_contact := {
			"id": "local_star",
			"name": volatile_star_name,
			"short_label": "S",
			"contact_kind": "star",
			"position": star_display.get("world_position", Vector2.ZERO),
			"star_name": volatile_star_name,
			"star_temperature_k": float(star_display.get("temperature_k", 0.0)),
			"star_luminosity": float(star_display.get("luminosity", 0.0)),
		}
		_merge_lock_display_fields(loader, star_contact, "", 220.0)
		contacts.append(star_contact)

	if not loader._volatile_scan_contact.is_empty():
		var scan_id := str(loader._volatile_scan_contact.get("id", ""))
		var scan_node: Variant = loader.spawned_by_id.get(scan_id)
		var world_pos: Vector2 = Vector2.ZERO
		if scan_node is Node2D and is_instance_valid(scan_node):
			world_pos = (scan_node as Node2D).global_position
		else:
			var pos_dict: Dictionary = loader._volatile_scan_contact.get("position", {})
			world_pos = Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0)))
		var ship_contact := loader._volatile_scan_contact.duplicate(true)
		ship_contact["name"] = str(loader._volatile_scan_contact.get("ship_name", "Survey contact"))
		ship_contact["contact_kind"] = "traffic_npc"
		ship_contact["position"] = world_pos
		ship_contact["velocity"] = Vector2.ZERO
		ship_contact["has_sim_slot"] = true
		_merge_lock_display_fields(
			loader,
			ship_contact,
			str(loader._volatile_scan_contact.get("sprite_path", ""))
		)
		contacts.append(ship_contact)

	return contacts

func _build_debris_contacts(loader: WorldLoader) -> Array:
	var contacts: Array = []
	var surviving_ids: Array[String] = []
	for debris_id in loader._debris_entity_ids:
		var node: Variant = loader.spawned_by_id.get(debris_id)
		if node == null or not is_instance_valid(node) or not (node is Node2D):
			continue
		surviving_ids.append(debris_id)
		var debris_node := node as Node2D
		var health_ratio := 1.0
		if debris_node.has_method("health_ratio"):
			health_ratio = float(debris_node.call("health_ratio"))
		var debris_contact := {
			"id": debris_id,
			"name": "Debris",
			"short_label": "",
			"contact_kind": "debris",
			"position": debris_node.global_position,
			"velocity": Vector2.ZERO,
			"debris_health_ratio": health_ratio,
			"heading_rad": debris_node.global_rotation - PI * 0.5,
		}
		_merge_lock_display_fields(loader, debris_contact, DEBRIS_SPRITE)
		contacts.append(debris_contact)
	loader._debris_entity_ids = surviving_ids
	return contacts

func _build_volatile_prop_contacts(loader: WorldLoader) -> Array:
	var contacts: Array = []
	var surviving: Dictionary = {}
	for entity_id in loader._volatile_entity_contact_meta.keys():
		var meta: Dictionary = loader._volatile_entity_contact_meta[entity_id]
		var node: Variant = loader.spawned_by_id.get(entity_id)
		if node == null or not is_instance_valid(node) or not (node is Node2D):
			continue
		surviving[entity_id] = meta
		var prop_node := node as Node2D
		var kind := str(meta.get("kind", ""))
		var label := str(meta.get("label", kind.capitalize()))
		var sprite_path := str(meta.get("sprite", DEBRIS_SPRITE))
		var contact := {
			"id": entity_id,
			"name": label,
			"short_label": "",
			"position": prop_node.global_position,
			"velocity": Vector2.ZERO,
			"heading_rad": prop_node.global_rotation - PI * 0.5,
		}
		match kind:
			"derelict", "cargo":
				contact["contact_kind"] = "debris"
				var health_ratio := 1.0
				if prop_node.has_method("health_ratio"):
					health_ratio = float(prop_node.call("health_ratio"))
				contact["debris_health_ratio"] = health_ratio
				_merge_lock_display_fields(loader, contact, sprite_path)
			"marker":
				contact["contact_kind"] = "landmark"
				_merge_lock_display_fields(loader, contact, sprite_path, 40.0)
			"mine":
				contact["contact_kind"] = "landmark"
				contact["name"] = "Mine"
				_merge_lock_display_fields(loader, contact, sprite_path, 36.0)
			_:
				continue
		contacts.append(contact)
	loader._volatile_entity_contact_meta = surviving
	return contacts

func get_traffic_anchors(loader: WorldLoader) -> Array:
	var anchors: Array = []
	if loader._habitat_node != null:
		anchors.append({
			"id": "habitat",
			"kind": "habitat",
			"position": loader.get_habitat_world_position(),
		})
	if loader._jump_gate_node != null:
		anchors.append({
			"id": "jump_gate",
			"kind": "jump_gate",
			"position": loader.get_jump_gate_world_position(),
		})
	for entry_variant in loader._orbital_entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var orbital_node: Variant = entry.get("node")
		if orbital_node is Node2D and loader._orbital_ring != null:
			anchors.append({
				"id": str(entry.get("id", "")),
				"kind": "orbital",
				"position": loader._orbital_ring.global_transform * orbital_node.position,
			})
	return anchors

func is_traffic_at_destination(loader: WorldLoader, world_pos: Vector2, destination_id: String, traffic_config: Dictionary = {}) -> bool:
	return is_traffic_route_arrived(loader, world_pos, world_pos, destination_id, traffic_config)

func is_traffic_route_arrived(loader: WorldLoader, prev_pos: Vector2,
	world_pos: Vector2,
	destination_id: String,
	traffic_config: Dictionary = {}) -> bool:
	var node := _destination_node(loader, destination_id)
	if node == null or not is_instance_valid(node):
		return false

	var interactable := node.get_node_or_null("Interactable") as Area2D
	if interactable != null and is_instance_valid(interactable):
		if _point_in_interactable(loader, world_pos, interactable):
			return true
		return _segment_intersects_interactable(loader, prev_pos, world_pos, interactable)

	var anchor_pos := _destination_world_position(loader, node, destination_id)
	if anchor_pos.length_squared() < 1.0:
		return false
	var radius := float(traffic_config.get("orbital_arrival_radius", 90.0))
	if world_pos.distance_to(anchor_pos) <= radius:
		return true
	return _segment_intersects_circle(loader, prev_pos, world_pos, anchor_pos, radius)

func _destination_node(loader: WorldLoader, destination_id: String) -> Node2D:
	if destination_id == "habitat":
		return loader._habitat_node
	if destination_id == "jump_gate":
		return loader._jump_gate_node
	for entry_variant in loader._orbital_entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("id", "")) == destination_id:
			var orbital_node: Variant = entry.get("node")
			if orbital_node is Node2D:
				return orbital_node
	return null

func _destination_world_position(loader: WorldLoader, node: Node2D, destination_id: String) -> Vector2:
	if destination_id == "habitat":
		return loader.get_habitat_world_position()
	if destination_id == "jump_gate":
		return loader.get_jump_gate_world_position()
	if loader._orbital_ring != null and node.get_parent() == loader._orbital_ring:
		return loader._orbital_ring.global_transform * node.position
	return node.global_position

func _point_in_interactable(loader: WorldLoader, world_pos: Vector2, area: Area2D) -> bool:
	var collision := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		return false
	if collision.shape is CircleShape2D:
		var circle := collision.shape as CircleShape2D
		var center := collision.global_transform.origin
		var scale := maxf(collision.global_scale.x, collision.global_scale.y)
		return world_pos.distance_to(center) <= circle.radius * scale
	return false

func _segment_intersects_interactable(loader: WorldLoader, from_pos: Vector2, to_pos: Vector2, area: Area2D) -> bool:
	var collision := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		return false
	if collision.shape is CircleShape2D:
		var circle := collision.shape as CircleShape2D
		var center := collision.global_transform.origin
		var scale := maxf(collision.global_scale.x, collision.global_scale.y)
		return _segment_intersects_circle(loader, from_pos, to_pos, center, circle.radius * scale)
	return false

func _segment_intersects_circle(loader: WorldLoader, from_pos: Vector2, to_pos: Vector2, center: Vector2, radius: float) -> bool:
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

func _resolve_contact_name(loader: WorldLoader, node: Node, _catalog: Catalog, fallback: String) -> String:
	if node is WorldObject:
		var world_object: WorldObject = node
		var interactable: Interactable = world_object.get_node_or_null("Interactable")
		if interactable != null and interactable.definition != null:
			return interactable.get_title()

	var label: Label = node.get_node_or_null("Label")
	if label != null and not label.text.is_empty():
		return label.text

	return fallback

static func _planet_contact_name(sector: SectorDef) -> String:
	if sector == null:
		return "Planet"
	var planet_name := sector.planet_name.strip_edges()
	if not planet_name.is_empty():
		return planet_name
	var sector_name := sector.name.strip_edges() if sector.has_source_key("name") else "Planet"
	if sector_name.ends_with(" Sector"):
		return sector_name.substr(0, sector_name.length() - " Sector".length())
	return sector_name

static func _star_contact_name(sector: SectorDef) -> String:
	if sector == null:
		return "Local star"
	var star := sector.star.strip_edges()
	if not star.is_empty():
		return star
	var system := sector.star_system.strip_edges()
	if not system.is_empty():
		return system
	return "Local star"
