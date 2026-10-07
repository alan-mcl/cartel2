class_name TranslationNav
extends RefCounted

const ACCURACY_MIN := 1.0
const ACCURACY_MAX := 99.0

const N_DEPTH_EXPONENT := 1.85
const N_DEPTH_BASE_PENALTY := 0.42

const STABILITY_RANDOM_MAX := 6.0
const STABILITY_COMPUTE_FLOOR := 0.55


static func max_n_for_nav_rating(nav_rating: float) -> int:
	if nav_rating >= 75.0:
		return 6
	if nav_rating >= 55.0:
		return 5
	return 4


static func nav_stats_from_ship(assembled: AssembledShip, catalog: Catalog) -> Dictionary:
	var rating := 0.0
	var capacity := 0.0
	if assembled == null or catalog == null:
		return {"nav_rating": rating, "translation_capacity": capacity}

	for entry_variant in assembled.modules_in_category("navigation"):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var module_id := str(entry_variant.get("module_id", ""))
		if module_id.is_empty():
			continue
		var module_def := catalog.get_module_def(module_id)
		if module_def == null:
			continue
		var module_rating := float(module_def.nav_rating)
		if module_rating <= 0.0:
			continue
		if module_rating > rating:
			rating = module_rating
			capacity = float(module_def.translation_capacity)

	return {"nav_rating": rating, "translation_capacity": int(capacity)}


static func list_offered_translations(
	catalog: Catalog,
	source_sector_id: String,
	assembled: AssembledShip,
	player_library: Array
) -> Array:
	if catalog == null or source_sector_id.is_empty():
		return []

	var stats := nav_stats_from_ship(assembled, catalog)
	var nav_rating := float(stats.get("nav_rating", 0.0))
	var capacity := int(stats.get("translation_capacity", 0))
	if nav_rating <= 0.0 or capacity <= 0:
		return []

	var all_from := catalog.list_translations_from(source_sector_id)
	var public_4: Array = []
	var higher: Array = []
	for record_variant in all_from:
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_variant
		if int(record.get("n", 0)) == 4:
			public_4.append(record)
		else:
			higher.append(record)

	higher.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var ln := int(left.get("n", 99))
		var rn := int(right.get("n", 99))
		if ln != rn:
			return ln < rn
		return float(left.get("ease", 0.0)) > float(right.get("ease", 0.0))
	)

	var selected: Array = public_4.duplicate()
	var max_n := max_n_for_nav_rating(nav_rating)
	var eligible_higher: Array = []
	for record_variant in higher:
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_variant
		if int(record.get("n", 0)) <= max_n:
			eligible_higher.append(record)

	var slots_left := maxi(0, capacity - public_4.size())
	for index in mini(slots_left, eligible_higher.size()):
		selected.append(eligible_higher[index])

	var library_keys := _library_key_set(player_library)
	for record_variant in all_from:
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_variant
		var key := _library_key(record)
		if not library_keys.has(key):
			continue
		if _contains_translation(selected, record):
			continue
		selected.append(record)

	selected.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_label := str(left.get("label", left.get("target", "")))
		var right_label := str(right.get("label", right.get("target", "")))
		if left_label != right_label:
			return left_label < right_label
		return int(left.get("n", 99)) < int(right.get("n", 99))
	)

	var offered: Array = []
	for record_variant in selected:
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_variant
		var accuracy := compute_accuracy(nav_rating, int(record.get("n", 4)), float(record.get("ease", 0.5)))
		var duration_seconds := translation_duration_seconds(record)
		offered.append({
			"translation": record,
			"accuracy": accuracy,
			"duration_seconds": duration_seconds,
		})
	return offered


static func translation_duration_seconds(translation: Dictionary) -> float:
	if translation.is_empty():
		return 0.0
	var entry := float(translation.get("entry_seconds", 0.0))
	var exit := float(translation.get("exit_seconds", 0.0))
	return entry + exit


static func compute_accuracy(nav_rating: float, n: int, ease: float) -> float:
	var ease_clamped := clampf(ease, 0.0, 1.0)
	if n <= 4:
		return clampf(
			72.0 + nav_rating * 0.22 + ease_clamped * 12.0,
			ACCURACY_MIN,
			ACCURACY_MAX
		)

	var depth := maxf(0.0, float(n) - 4.0)
	var depth_penalty := pow(N_DEPTH_BASE_PENALTY, depth * N_DEPTH_EXPONENT)
	var rating_factor := clampf(0.45 + nav_rating / 180.0, 0.0, 1.0)
	var ease_factor := clampf(0.25 + ease_clamped * 0.75, 0.0, 1.0)
	var raw := rating_factor * ease_factor * depth_penalty
	return clampf(raw * 100.0, ACCURACY_MIN, ACCURACY_MAX)


static func roll_stability(
	accuracy: float,
	n: int,
	operating_state: ShipOperatingState,
	assembled: AssembledShip,
	combat_state: ShipCombatState,
	rng: RandomNumberGenerator = null
) -> float:
	var accuracy_norm := clampf(accuracy / 100.0, 0.0, 1.0)
	var depth := maxf(0.0, float(n) - 4.0)
	var n_factor := 1.0 if depth <= 0.0 else pow(0.38, depth * 1.6)

	var compute_scale := 1.0
	if operating_state != null and operating_state.compute_capacity > 0.0:
		var demand := operating_state.compute_demand
		var capacity := operating_state.compute_capacity
		if demand > capacity:
			compute_scale = clampf(capacity / demand, STABILITY_COMPUTE_FLOOR, 1.0)

	var integrity_scale := 1.0
	if assembled != null and combat_state != null:
		var base_cu := float(assembled.capacities.get("compute_capacity", 0.0))
		if base_cu > 0.0:
			var remaining := base_cu - combat_state.compute_integrity_lost
			integrity_scale = clampf(remaining / base_cu, 0.0, 1.0)

	var base := accuracy_norm * n_factor * compute_scale * integrity_scale
	base *= 100.0

	var spread := STABILITY_RANDOM_MAX * (1.05 - accuracy_norm)
	if rng == null:
		base += randf_range(-spread, spread)
	else:
		base += rng.randf_range(-spread, spread)

	return clampf(base, ACCURACY_MIN, ACCURACY_MAX)


static func destination_display_label(catalog: Catalog, sector_id: String) -> String:
	if catalog == null or sector_id.is_empty():
		return sector_id
	var sector := catalog.get_sector(sector_id)
	var label := str(sector.get("planet_name", ""))
	if label.is_empty():
		label = str(sector.get("name", sector_id))
	return label


static func same_star_system(catalog: Catalog, sector_a: String, sector_b: String) -> bool:
	if catalog == null or sector_a.is_empty() or sector_b.is_empty():
		return false
	var sys_a := str(catalog.get_sector(sector_a).get("star_system", ""))
	var sys_b := str(catalog.get_sector(sector_b).get("star_system", ""))
	return not sys_a.is_empty() and sys_a == sys_b


static func group_offered_translations(
	catalog: Catalog,
	source_sector_id: String,
	offers: Array
) -> Dictionary:
	var local_by_dest: Dictionary = {}
	var other_by_dest: Dictionary = {}

	for offer_variant in offers:
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = offer_variant
		var translation: Dictionary = offer.get("translation", {})
		var dest_id := str(translation.get("target", ""))
		if dest_id.is_empty():
			continue
		var bucket: Dictionary = (
			local_by_dest if same_star_system(catalog, source_sector_id, dest_id) else other_by_dest
		)
		if not bucket.has(dest_id):
			bucket[dest_id] = {
				"destination_id": dest_id,
				"label": destination_display_label(catalog, dest_id),
				"by_n": {},
			}
		var row: Dictionary = bucket[dest_id]
		var by_n: Dictionary = row.get("by_n", {})
		var n := int(translation.get("n", 4))
		by_n[n] = offer
		row["by_n"] = by_n

	return {
		"local": _sorted_destination_rows(local_by_dest),
		"other": _sorted_destination_rows(other_by_dest),
	}


static func format_cell_summary(accuracy: float, duration_seconds: float) -> String:
	var duration_text := GalacticCalendar.format_duration(duration_seconds)
	return "%d%%\n%s" % [int(round(accuracy)), duration_text]


static func _sorted_destination_rows(by_dest: Dictionary) -> Array:
	var rows: Array = []
	for dest_id in by_dest.keys():
		rows.append(by_dest[dest_id])
	rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("label", "")) < str(right.get("label", ""))
	)
	return rows


static func format_offer_line(translation: Dictionary, accuracy: float, duration_seconds: float) -> String:
	var solution := int(translation.get("solution", 0))
	var label := str(translation.get("label", translation.get("target", "")))
	var n := int(translation.get("n", 4))
	var duration_text := GalacticCalendar.format_duration(duration_seconds)
	return "%d: %s via %d-space, Accuracy %d%%, expected duration %s" % [
		solution,
		label,
		n,
		int(round(accuracy)),
		duration_text,
	]


static func _library_key(record: Dictionary) -> String:
	return "%s:%d" % [str(record.get("source", "")), int(record.get("solution", 0))]


static func _library_key_set(player_library: Array) -> Dictionary:
	var keys := {}
	for entry_variant in player_library:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var source := str(entry.get("source", ""))
		var solution := int(entry.get("solution", 0))
		if source.is_empty():
			continue
		keys["%s:%d" % [source, solution]] = true
	return keys


static func _contains_translation(selected: Array, record: Dictionary) -> bool:
	var solution := int(record.get("solution", 0))
	var source := str(record.get("source", ""))
	for existing_variant in selected:
		if typeof(existing_variant) != TYPE_DICTIONARY:
			continue
		var existing: Dictionary = existing_variant
		if str(existing.get("source", "")) == source and int(existing.get("solution", 0)) == solution:
			return true
	return false
