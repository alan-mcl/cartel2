class_name HyperdriveSolution
extends RefCounted

const BASE_SECONDS_PER_FRICTION := 520.0


static func is_active(session: GameSession) -> bool:
	return _calc(session).get("active", false) == true


static func list_compute_destinations(catalog: Catalog, source_sector_id: String) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	if catalog == null or source_sector_id.is_empty():
		return out
	for record_variant in catalog.list_translations_from(source_sector_id):
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_variant
		if int(record.get("n", 0)) != 4:
			continue
		var target := str(record.get("target", "")).strip_edges()
		if target.is_empty() or seen.has(target):
			continue
		seen[target] = true
		out.append({
			"target": target,
			"label": TranslationNav.destination_display_label(catalog, target),
			"friction": int(record.get("friction", 0)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("label", "")) < str(b.get("label", ""))
	)
	return out


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
	return (
		float(friction) * BASE_SECONDS_PER_FRICTION * depth_burden / (skill_factor * nav_factor)
	)


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
	var public4 := catalog.get_public_translation(source, target_sector_id, 4)
	if public4.is_empty():
		return {"ok": false, "message": "No public route to that destination."}
	var max_n := TranslationNav.max_n_for_nav_rating(
		float(TranslationNav.nav_stats_from_ship(assembled, catalog).get("nav_rating", 0.0))
	)
	if n < 4 or n > max_n:
		return {"ok": false, "message": "Navigation computer cannot target that depth."}
	var friction := int(public4.get("friction", 0))
	var skill := solution_skill_for_module(hyperdrive_module)
	var nav_rating := float(
		TranslationNav.nav_stats_from_ship(assembled, catalog).get("nav_rating", 0.0)
	)
	var seconds := calculation_seconds(friction, n, nav_rating, skill)
	if seconds <= 0.0:
		return {"ok": false, "message": "Cannot calculate a solution for that route."}
	var salt := randi()
	var solution := derive_solution_id(source, target_sector_id, n, salt)
	while _library_has_solution(session, source, solution):
		salt = randi()
		solution = derive_solution_id(source, target_sector_id, n, salt)
	_calc(session).clear()
	_calc(session)["active"] = true
	_calc(session)["source"] = source
	_calc(session)["target"] = target_sector_id
	_calc(session)["n"] = n
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
				n,
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


static func sustain_spool(
	catalog: Catalog,
	session: GameSession,
	assembled: AssembledShip,
	owned: OwnedShip,
	position: Vector2,
	thrusting: bool,
	boosting: bool
) -> bool:
	if not is_active(session):
		return true
	var block := Hyperdrive.spool_block(
		catalog, session, assembled, owned, position, thrusting, boosting
	)
	if bool(block.get("ok", false)):
		return true
	cancel(session, str(block.get("message", "Solution calculation cancelled.")))
	return false


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
