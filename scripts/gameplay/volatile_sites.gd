class_name VolatileSites
extends RefCounted

const ORBITAL_SPRITES: Array[String] = [
	"res://assets/world/orbitals/array.svg",
	"res://assets/world/orbitals/platform.svg",
	"res://assets/world/orbitals/tank_farm.svg",
	"res://assets/world/orbitals/torus.svg",
	"res://assets/world/orbitals/tower.svg",
	"res://assets/world/orbitals/yard.svg",
]

const CARGO_SPRITE := "res://assets/world/cargo_container.svg"
const MARKER_SPRITES := {
	"buoy": "res://assets/world/nav_buoy.svg",
	"survey": "res://assets/world/survey_marker.svg",
}
const MARKER_LABELS := {
	"buoy": "Nav buoy",
	"survey": "Survey marker",
}

const DEFAULT_MINE_RADIUS := 180.0
const DEFAULT_MINE_KINETIC := 25.0

const PLACE_MIN_RADIUS := 1800.0
const PLACE_MAX_RADIUS := 6400.0
const MIN_SEPARATION := 500.0
const PLACE_ATTEMPTS := 16

const STATIC_OBJECT_KINDS: Array[String] = [
	"debris",
	"orbital",
	"derelict",
	"cargo",
	"marker",
	"mine",
]
const SHIP_OBJECT_KINDS: Array[String] = ["ship", "npc_ship"]

const _PRESERVE_TOKENS: Array[String] = [
	"Lagrange",
	"Lyapunov",
	"Molniya",
	"Hohmann",
	"Kirkwood",
	"Trojan",
	"Hill",
	"Oberth",
	"Kozai",
	"Oort",
]


static func pick_site(catalog: Catalog, rng: RandomNumberGenerator) -> Dictionary:
	var sites := catalog.list_volatile_sites()
	if sites.is_empty():
		return _fallback_site()
	return sites[rng.randi_range(0, sites.size() - 1)].duplicate(true)


static func site_label(site: Dictionary) -> String:
	return str(site.get("label", "Survey site")).strip_edges()


static func site_id(site: Dictionary) -> String:
	return str(site.get("id", "")).strip_edges()


static func description_phrase(site: Dictionary) -> String:
	if site.is_empty():
		return "a survey site"
	var article := str(site.get("article", "a")).strip_edges()
	if article not in ["a", "an", "the"]:
		article = "a"
	var title := sentence_case_title(site_label(site))
	return "%s %s" % [article, title]


static func sentence_case_title(title: String) -> String:
	var trimmed := title.strip_edges()
	if trimmed.is_empty():
		return ""
	var lower := trimmed.to_lower()
	for point in range(1, 6):
		var plain := "l%d" % point
		var capped := "L%d" % point
		lower = lower.replace(plain, capped)
	for token in _PRESERVE_TOKENS:
		lower = _replace_insensitive(lower, token.to_lower(), token)
	return lower


static func description_phrase_for_catalog(catalog: Catalog, volatile_site_id: String) -> String:
	if volatile_site_id.is_empty() or catalog == null:
		return ""
	return description_phrase(catalog.get_volatile_site(volatile_site_id))


static func count_range(site: Dictionary, kind: String) -> Vector2i:
	var objects: Variant = site.get("objects", [])
	if typeof(objects) != TYPE_ARRAY:
		return Vector2i.ZERO
	for entry_variant in objects:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var entry_kind := _normalise_object_kind(str(entry.get("kind", "")))
		if entry_kind != kind:
			continue
		return _parse_count(entry.get("count", [0, 0]))
	return Vector2i.ZERO


static func apply_site_to_setup(
	setup: Dictionary,
	site: Dictionary,
	catalog: Catalog,
	rng: RandomNumberGenerator = null
) -> void:
	if site.is_empty():
		return
	if not bool(site.get("star", true)):
		setup["omit_star"] = true
	var roller := rng
	if roller == null:
		roller = RandomNumberGenerator.new()
		roller.randomize()
	var play_bounds := float(setup.get("play_bounds", 7500.0))
	var layout := generate_site_layout(site, catalog, roller, play_bounds)
	_merge_entities(setup, layout.get("entities", []))
	_merge_ambient_ships(setup, layout.get("ambient_ships", []))


static func generate_site_layout(
	site: Dictionary,
	catalog: Catalog,
	rng: RandomNumberGenerator,
	play_bounds: float = 7500.0
) -> Dictionary:
	var entities: Array = []
	var ambient_ships: Array = []
	var objects: Variant = site.get("objects", [])
	if typeof(objects) != TYPE_ARRAY or rng == null or catalog == null:
		return {"entities": entities, "ambient_ships": ambient_ships}
	var placed: Array[Vector2] = []
	var max_radius := minf(PLACE_MAX_RADIUS, maxf(play_bounds * 0.82, PLACE_MIN_RADIUS))
	for entry_variant in objects:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var kind := _normalise_object_kind(str(entry.get("kind", "")).strip_edges())
		if kind.is_empty():
			continue
		var span := _parse_count(entry.get("count", [0, 0]))
		var count := rng.randi_range(span.x, span.y)
		for index in range(count):
			var pos := _pick_position(rng, placed, max_radius)
			placed.append(pos)
			if kind == "ship":
				ambient_ships.append(_ambient_ship_record(catalog, rng, pos, index))
			else:
				entities.append(_entity_for_kind(kind, rng, catalog, pos, index))
	return {"entities": entities, "ambient_ships": ambient_ships}


static func generate_entities(
	site: Dictionary,
	catalog: Catalog,
	rng: RandomNumberGenerator,
	play_bounds: float = 7500.0
) -> Array:
	return generate_site_layout(site, catalog, rng, play_bounds).get("entities", [])


static func append_entity(setup: Dictionary, entity: Dictionary) -> void:
	if entity.is_empty():
		return
	_merge_entities(setup, [entity])


static func _entity_for_kind(
	kind: String,
	rng: RandomNumberGenerator,
	catalog: Catalog,
	pos: Vector2,
	index: int
) -> Dictionary:
	var entity := {
		"id": "ambient_%s_%d_{{ID}}" % [kind, index],
		"kind": kind,
		"position": {"x": pos.x, "y": pos.y},
		"rotation": rng.randf() * TAU,
	}
	match kind:
		"orbital":
			entity["sprite"] = ORBITAL_SPRITES[rng.randi_range(0, ORBITAL_SPRITES.size() - 1)]
		"derelict":
			entity["label"] = "Derelict"
			entity["sprite"] = _pick_chassis_sprite(catalog, rng)
		"cargo":
			entity["label"] = "Cargo container"
			entity["sprite"] = CARGO_SPRITE
		"marker":
			var variant := "buoy" if rng.randf() > 0.5 else "survey"
			entity["variant"] = variant
			entity["label"] = MARKER_LABELS.get(variant, "Marker")
			entity["sprite"] = MARKER_SPRITES.get(variant, MARKER_SPRITES.survey)
		"mine":
			entity["radius"] = DEFAULT_MINE_RADIUS
			entity["delivery"] = "ballistic"
			entity["packets"] = {"kinetic": DEFAULT_MINE_KINETIC}
	return entity


static func _ambient_ship_record(
	catalog: Catalog,
	rng: RandomNumberGenerator,
	pos: Vector2,
	index: int
) -> Dictionary:
	var template_id := _pick_ship_template(catalog, rng)
	return {
		"id": "ambient_ship_%d_{{ID}}" % index,
		"template_id": template_id,
		"position": {"x": pos.x, "y": pos.y},
		"heading_rad": rng.randf_range(-PI, PI),
		"anonymous": true,
	}


static func _pick_chassis_sprite(catalog: Catalog, rng: RandomNumberGenerator) -> String:
	var chassis_list := catalog.list_chassis()
	if chassis_list.is_empty():
		return CARGO_SPRITE
	var pick: Dictionary = chassis_list[rng.randi_range(0, chassis_list.size() - 1)]
	return str(pick.get("sprite", CARGO_SPRITE))


static func _pick_ship_template(catalog: Catalog, rng: RandomNumberGenerator) -> String:
	var ships := catalog.list_ships()
	if ships.is_empty():
		return ""
	var pick: Dictionary = ships[rng.randi_range(0, ships.size() - 1)]
	return str(pick.get("id", ""))


static func _merge_entities(setup: Dictionary, additions: Array) -> void:
	if additions.is_empty():
		return
	var merged: Array = []
	var existing: Variant = setup.get("entities", [])
	if typeof(existing) == TYPE_ARRAY:
		for entry_variant in existing:
			if typeof(entry_variant) == TYPE_DICTIONARY:
				merged.append((entry_variant as Dictionary).duplicate(true))
	for entry_variant in additions:
		if typeof(entry_variant) == TYPE_DICTIONARY:
			merged.append(entry_variant)
	setup["entities"] = merged


static func _merge_ambient_ships(setup: Dictionary, additions: Array) -> void:
	if additions.is_empty():
		return
	var merged: Array = []
	var existing: Variant = setup.get("ambient_ships", [])
	if typeof(existing) == TYPE_ARRAY:
		for entry_variant in existing:
			if typeof(entry_variant) == TYPE_DICTIONARY:
				merged.append((entry_variant as Dictionary).duplicate(true))
	for entry_variant in additions:
		if typeof(entry_variant) == TYPE_DICTIONARY:
			merged.append(entry_variant)
	setup["ambient_ships"] = merged


static func _normalise_object_kind(kind: String) -> String:
	if kind == "npc_ship":
		return "ship"
	return kind


static func _parse_count(raw: Variant) -> Vector2i:
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
		var lo := maxi(int((raw as Array)[0]), 0)
		var hi := maxi(int((raw as Array)[1]), lo)
		return Vector2i(lo, hi)
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		var n := maxi(int(raw), 0)
		return Vector2i(n, n)
	return Vector2i.ZERO


static func _pick_position(rng: RandomNumberGenerator, placed: Array[Vector2], max_radius: float) -> Vector2:
	var best := Vector2.ZERO
	var min_radius := minf(PLACE_MIN_RADIUS, max_radius)
	for _attempt in range(PLACE_ATTEMPTS):
		var radius := rng.randf_range(min_radius, max_radius)
		var angle := rng.randf() * TAU
		var candidate := Vector2(cos(angle), sin(angle)) * radius
		if _separated(candidate, placed):
			return candidate
		best = candidate
	return best


static func _separated(candidate: Vector2, placed: Array[Vector2]) -> bool:
	for other in placed:
		if candidate.distance_to(other) < MIN_SEPARATION:
			return false
	return true


static func _replace_insensitive(text: String, needle: String, replacement: String) -> String:
	if needle.is_empty():
		return text
	var lower_text := text.to_lower()
	var lower_needle := needle.to_lower()
	var out := text
	var search_from := 0
	while true:
		var index := lower_text.find(lower_needle, search_from)
		if index < 0:
			break
		out = out.substr(0, index) + replacement + out.substr(index + needle.length())
		lower_text = out.to_lower()
		search_from = index + replacement.length()
	return out


static func _fallback_site() -> Dictionary:
	return {
		"id": "deep_space",
		"label": "Deep space",
		"star": false,
		"article": "a",
	}
