class_name HyperdriveSolution
extends RefCounted

const BEST_N := -1
const OFF_NETWORK_MIN_N := 6
const DISCONNECTED_FRICTION := 70

const MIN_CALC_SECONDS := 15.0
const MAX_CALC_SECONDS := 180.0
const BASE_SECONDS_PER_FRICTION := 1.05


static func is_active(session: GameSession) -> bool:
	return _calc(session).get("active", false) == true


static func calc_progress(session: GameSession) -> float:
	if not is_active(session):
		return 0.0
	var total := float(_calc(session).get("total_seconds", 0.0))
	var remaining := float(_calc(session).get("remaining_seconds", 0.0))
	if total <= 0.0:
		return 0.0
	return clampf(1.0 - remaining / total, 0.0, 1.0)


static func direct_route_friction(catalog: Catalog, source_sector_id: String, target_sector_id: String) -> int:
	if catalog == null or source_sector_id.is_empty() or target_sector_id.is_empty():
		return -1
	for route_variant in catalog.list_routes():
		if typeof(route_variant) != TYPE_DICTIONARY:
			continue
		var route: Dictionary = route_variant
		var a := str(route.get("a", ""))
		var b := str(route.get("b", ""))
		if (a == source_sector_id and b == target_sector_id) or (
			a == target_sector_id and b == source_sector_id
		):
			return int(route.get("friction", 0))
	return -1


static func is_direct_public_edge(catalog: Catalog, source_sector_id: String, target_sector_id: String) -> bool:
	return direct_route_friction(catalog, source_sector_id, target_sector_id) >= 0


static func shortest_path_friction_sum(
	catalog: Catalog,
	source_sector_id: String,
	target_sector_id: String
) -> int:
	if catalog == null or source_sector_id.is_empty() or target_sector_id.is_empty():
		return -1
	if source_sector_id == target_sector_id:
		return 0
	var adj := _route_adjacency(catalog)
	if not adj.has(source_sector_id):
		return -1
	var queue: Array = [source_sector_id]
	var cost_by_id: Dictionary = {source_sector_id: 0}
	var head := 0
	while head < queue.size():
		var current := str(queue[head])
		head += 1
		var current_cost := int(cost_by_id.get(current, 0))
		for edge_variant in adj.get(current, []):
			if typeof(edge_variant) != TYPE_DICTIONARY:
				continue
			var edge: Dictionary = edge_variant
			var neighbor := str(edge.get("id", ""))
			if neighbor.is_empty():
				continue
			var next_cost := current_cost + int(edge.get("friction", 0))
			if not cost_by_id.has(neighbor) or next_cost < int(cost_by_id[neighbor]):
				cost_by_id[neighbor] = next_cost
				queue.append(neighbor)
	if not cost_by_id.has(target_sector_id):
		return -1
	return int(cost_by_id[target_sector_id])


static func friction_for_compute(catalog: Catalog, source_sector_id: String, target_sector_id: String) -> int:
	var direct := direct_route_friction(catalog, source_sector_id, target_sector_id)
	if direct >= 0:
		return direct
	var path_sum := shortest_path_friction_sum(catalog, source_sector_id, target_sector_id)
	if path_sum >= 0:
		return path_sum
	return DISCONNECTED_FRICTION


static func build_compute_spanning_tree(catalog: Catalog, source_sector_id: String) -> Array:
	var rows: Array = []
	if catalog == null or source_sector_id.is_empty():
		return rows
	var adj := _route_adjacency(catalog)
	var visited: Dictionary = {source_sector_id: true}
	var queue: Array = [source_sector_id]
	var head := 0
	while head < queue.size():
		var parent := str(queue[head])
		head += 1
		var edges: Array = adj.get(parent, [])
		edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("label", "")) < str(b.get("label", ""))
		)
		for edge_variant in edges:
			if typeof(edge_variant) != TYPE_DICTIONARY:
				continue
			var edge: Dictionary = edge_variant
			var child_id := str(edge.get("id", ""))
			if child_id.is_empty() or visited.has(child_id):
				continue
			visited[child_id] = true
			queue.append(child_id)
			rows.append({
				"target": child_id,
				"label": str(edge.get("label", child_id)),
				"parent": parent,
				"depth": _tree_depth(rows, parent, source_sector_id) + 1,
			})

	var uncharted: Array = []
	for sector_variant in catalog.list_sectors():
		if typeof(sector_variant) != TYPE_DICTIONARY:
			continue
		var sector: Dictionary = sector_variant
		var sector_id := str(sector.get("id", ""))
		if sector_id.is_empty() or sector_id == source_sector_id or visited.has(sector_id):
			continue
		if VolatileTranslation.is_volatile_sector_id(sector_id):
			continue
		uncharted.append({
			"target": sector_id,
			"label": TranslationNav.destination_display_label(catalog, sector_id),
			"parent": "__uncharted__",
			"depth": 1,
		})
	uncharted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("label", "")) < str(b.get("label", ""))
	)
	for row in uncharted:
		rows.append(row)
	return rows


static func translation_already_available(
	session: GameSession,
	catalog: Catalog,
	source_sector_id: String,
	target_sector_id: String,
	n: int
) -> bool:
	if not catalog.get_public_translation(source_sector_id, target_sector_id, n).is_empty():
		return true
	if session == null or session.player == null:
		return false
	for entry_variant in session.player.translation_library:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("source", "")) != source_sector_id:
			continue
		if str(entry.get("target", "")) != target_sector_id:
			continue
		if int(entry.get("n", 0)) == n:
			return true
	return false


static func list_available_compute_n(
	session: GameSession,
	catalog: Catalog,
	assembled: AssembledShip,
	source_sector_id: String,
	target_sector_id: String
) -> Array[int]:
	var out: Array[int] = []
	if catalog == null or source_sector_id.is_empty() or target_sector_id.is_empty():
		return out
	if source_sector_id == target_sector_id:
		return out
	var nav_rating := float(
		TranslationNav.nav_stats_from_ship(assembled, catalog).get("nav_rating", 0.0)
	)
	var max_n := TranslationNav.max_n_for_nav_rating(nav_rating)
	var min_n := 4 if is_direct_public_edge(catalog, source_sector_id, target_sector_id) else OFF_NETWORK_MIN_N
	for n in range(min_n, max_n + 1):
		if not translation_already_available(session, catalog, source_sector_id, target_sector_id, n):
			out.append(n)
	return out


static func resolve_compute_n(
	session: GameSession,
	catalog: Catalog,
	assembled: AssembledShip,
	source_sector_id: String,
	target_sector_id: String,
	requested_n: int
) -> int:
	if requested_n != BEST_N:
		return requested_n
	var available := list_available_compute_n(
		session, catalog, assembled, source_sector_id, target_sector_id
	)
	if available.is_empty():
		return 0
	return available[0]


static func list_library_jump_offers(
	catalog: Catalog,
	source_sector_id: String,
	assembled: AssembledShip,
	player_library: Array
) -> Array:
	if catalog == null or source_sector_id.is_empty() or player_library.is_empty():
		return []
	var stats := TranslationNav.nav_stats_from_ship(assembled, catalog)
	var nav_rating := float(stats.get("nav_rating", 0.0))
	var offers: Array = []
	for entry_variant in player_library:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var record := TranslationNav.resolve_library_translation(
			catalog, source_sector_id, entry_variant
		)
		if record.is_empty():
			continue
		if str(record.get("source", "")) != source_sector_id:
			continue
		var accuracy := TranslationNav.compute_accuracy(
			nav_rating,
			int(record.get("n", 4)),
			float(record.get("ease", 0.5))
		)
		offers.append({
			"translation": record,
			"accuracy": accuracy,
			"duration_seconds": TranslationNav.translation_duration_seconds(record),
		})
	offers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var lt := str(left.get("translation", {}).get("label", ""))
		var rt := str(right.get("translation", {}).get("label", ""))
		if lt != rt:
			return lt < rt
		return int(left.get("translation", {}).get("n", 99)) < int(
			right.get("translation", {}).get("n", 99)
		)
	)
	return offers


static func calculation_seconds(
	friction: int,
	n: int,
	nav_rating: float,
	solution_skill: float
) -> float:
	if friction < 1:
		return 0.0
	var depth_burden := pow(1.38, maxf(0.0, float(n) - 4.0))
	var skill_factor := clampf(0.3 + solution_skill / 85.0, 0.3, 1.45)
	var nav_factor := clampf(0.3 + nav_rating / 85.0, 0.3, 1.45)
	var raw := (
		float(friction) * BASE_SECONDS_PER_FRICTION * depth_burden / (skill_factor * nav_factor)
	)
	return clampf(raw, MIN_CALC_SECONDS, MAX_CALC_SECONDS)


static func success_chance(nav_rating: float, solution_skill: float, n: int) -> float:
	var chance := 0.18 + nav_rating * 0.0045 + solution_skill * 0.0055
	chance -= 0.042 * maxf(0.0, float(n) - 4.0)
	if n > 6:
		chance -= 0.02 * maxf(0.0, float(n) - 6.0)
	return clampf(chance, 0.06, 0.93)


static func derive_solution_id(source: String, target: String, n: int, salt: int) -> int:
	var h := hash("%s:%s:%d:%d" % [source, target, n, salt])
	return int(absi(h) % 900000) + 100000


static func solution_skill_for_module(module_def: ModuleDef) -> float:
	if module_def == null:
		return 0.0
	if module_def.has_source_key("solution_skill"):
		return clampf(float(module_def.solution_skill), 0.0, 100.0)
	return 40.0


static func start_calculation(
	session: GameSession,
	catalog: Catalog,
	assembled: AssembledShip,
	target_sector_id: String,
	n: int,
	hyperdrive_module: ModuleDef
) -> Dictionary:
	if session == null or catalog == null or assembled == null:
		return {"ok": false, "message": "Hyperdrive unavailable."}
	if is_active(session):
		return {"ok": false, "message": "A solution calculation is already running."}
	if session.in_unspace or session.docked:
		return {"ok": false, "message": "Cannot calculate a solution here."}
	var source := session.sector_id
	if target_sector_id.is_empty() or target_sector_id == source:
		return {"ok": false, "message": "Pick a different destination."}
	if catalog.get_sector_def(target_sector_id) == null:
		return {"ok": false, "message": "Unknown destination."}

	var resolved_n := resolve_compute_n(session, catalog, assembled, source, target_sector_id, n)
	if resolved_n < 4:
		return {"ok": false, "message": "No remaining N-space depth to compute for that pair."}

	var available := list_available_compute_n(
		session, catalog, assembled, source, target_sector_id
	)
	if not available.has(resolved_n):
		return {"ok": false, "message": "That depth is already available or beyond nav tier."}

	var friction := friction_for_compute(catalog, source, target_sector_id)
	var skill := solution_skill_for_module(hyperdrive_module)
	var nav_rating := float(
		TranslationNav.nav_stats_from_ship(assembled, catalog).get("nav_rating", 0.0)
	)
	var seconds := calculation_seconds(friction, resolved_n, nav_rating, skill)
	if seconds <= 0.0:
		return {"ok": false, "message": "Cannot calculate a solution for that route."}
	var salt := randi()
	var solution := derive_solution_id(source, target_sector_id, resolved_n, salt)
	while _library_has_solution(session, source, solution):
		salt = randi()
		solution = derive_solution_id(source, target_sector_id, resolved_n, salt)
	_calc(session).clear()
	_calc(session)["active"] = true
	_calc(session)["source"] = source
	_calc(session)["target"] = target_sector_id
	_calc(session)["n"] = resolved_n
	_calc(session)["total_seconds"] = seconds
	_calc(session)["remaining_seconds"] = seconds
	_calc(session)["salt"] = salt
	_calc(session)["solution"] = solution
	_calc(session)["hyperdrive_module_id"] = hyperdrive_module.id if hyperdrive_module != null else ""
	_calc(session)["nav_rating"] = nav_rating
	_calc(session)["solution_skill"] = skill
	return {
		"ok": true,
		"message": (
			"Computing %d-space solution to %s (%s GST)."
			% [
				resolved_n,
				TranslationNav.destination_display_label(catalog, target_sector_id),
				GalacticCalendar.format_duration(seconds),
			]
		),
	}


static func cancel(session: GameSession, reason: String = "") -> void:
	if not is_active(session):
		return
	_calc(session).clear()
	if session != null and not reason.is_empty():
		session.last_log = reason


static func advance(session: GameSession, catalog: Catalog, gst_delta: float) -> void:
	if session == null or not is_active(session) or gst_delta <= 0.0:
		return
	if session.in_unspace or session.docked:
		cancel(session, "Solution calculation aborted.")
		return
	if str(_calc(session).get("source", "")) != session.sector_id:
		cancel(session, "Solution calculation aborted — left the origin system.")
		return
	var remaining := float(_calc(session).get("remaining_seconds", 0.0))
	remaining = maxf(0.0, remaining - gst_delta)
	_calc(session)["remaining_seconds"] = remaining
	if remaining > 0.0:
		return
	_finish(session, catalog)


static func force_complete_for_tests(
	session: GameSession,
	catalog: Catalog,
	succeed: bool
) -> void:
	if not is_active(session):
		return
	_finish(session, catalog, succeed)


static func _finish(
	session: GameSession,
	catalog: Catalog,
	force_success: Variant = null
) -> void:
	var calc := _calc(session)
	var source := str(calc.get("source", ""))
	var target := str(calc.get("target", ""))
	var n := int(calc.get("n", 4))
	var solution := int(calc.get("solution", 0))
	var salt := int(calc.get("salt", 0))
	var nav_rating := float(calc.get("nav_rating", 0.0))
	var skill := float(calc.get("solution_skill", 0.0))
	calc.clear()
	var success := false
	if force_success != null:
		success = bool(force_success)
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d:%d" % [solution, salt])
		success = rng.randf() <= success_chance(nav_rating, skill, n)
	if not success:
		session.last_log = (
			"Hyperdrive failed to converge a %d-space solution to %s."
			% [n, TranslationNav.destination_display_label(catalog, target)]
		)
		session.changed.emit()
		return
	if _library_has_solution(session, source, solution):
		session.last_log = "Hyperdrive solution collided with an existing record; try again."
		session.changed.emit()
		return
	session.player.translation_library.append({
		"source": source,
		"solution": solution,
		"target": target,
		"n": n,
	})
	session.last_log = (
		"Stored private %d-space solution %d → %s."
		% [n, solution, TranslationNav.destination_display_label(catalog, target)]
	)
	session.changed.emit()


static func _library_has_solution(session: GameSession, source: String, solution: int) -> bool:
	if session == null or session.player == null:
		return false
	for entry_variant in session.player.translation_library:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("source", "")) == source and int(entry.get("solution", 0)) == solution:
			return true
	return false


static func _calc(session: GameSession) -> Dictionary:
	if session == null or session.player == null:
		return {}
	if session.player.hyperdrive_calc.is_empty():
		session.player.hyperdrive_calc = {}
	return session.player.hyperdrive_calc


static func _route_adjacency(catalog: Catalog) -> Dictionary:
	var adj: Dictionary = {}
	for route_variant in catalog.list_routes():
		if typeof(route_variant) != TYPE_DICTIONARY:
			continue
		var route: Dictionary = route_variant
		var a := str(route.get("a", ""))
		var b := str(route.get("b", ""))
		if a.is_empty() or b.is_empty():
			continue
		var friction := int(route.get("friction", 0))
		_append_edge(adj, a, b, friction, catalog)
		_append_edge(adj, b, a, friction, catalog)
	return adj


static func _append_edge(
	adj: Dictionary,
	from_id: String,
	to_id: String,
	friction: int,
	catalog: Catalog
) -> void:
	if not adj.has(from_id):
		adj[from_id] = []
	var list: Array = adj[from_id]
	list.append({
		"id": to_id,
		"friction": friction,
		"label": TranslationNav.destination_display_label(catalog, to_id),
	})
	adj[from_id] = list


static func _tree_depth(rows: Array, sector_id: String, root_id: String) -> int:
	if sector_id == root_id:
		return 0
	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if str(row.get("target", "")) == sector_id:
			var parent := str(row.get("parent", ""))
			if parent == root_id:
				return 1
			return _tree_depth(rows, parent, root_id) + 1
	return 0
