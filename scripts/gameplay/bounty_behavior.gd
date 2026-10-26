class_name BountyBehavior
extends RefCounted

const TARGET_BEACON_MIN_DIST := 2000.0
const WANDER_RADIUS := 1200.0
const STEALTHY_COMMIT_RANGE := 1000.0
const DEEP_SPACE_MARGIN := 400.0
const PURSUIT_UNSPACE_SECONDS := 90.0
const PURSUIT_ORIGIN_DOCK_SECONDS := 60.0

const POSTURES: Array[String] = ["stealthy", "aggressive", "oblivious"]
const RESOLVES: Array[String] = ["fight", "flee"]
const STATIONS: Array[String] = ["hold", "wander"]
const FLEE_ROUTES: Array[String] = ["beacon", "hyperdrive", "deep_space"]
const SKILLS: Array[String] = ["novice", "experienced", "elite"]


static func grant_rng(offer: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(str(offer.get("id", "bounty")).hash())
	return rng


static func roll_layout(play_bounds: float, rng: RandomNumberGenerator) -> Dictionary:
	var min_radius := VolatileSites.PLACE_MIN_RADIUS
	var max_radius := minf(
		VolatileSites.PLACE_MAX_RADIUS,
		maxf(play_bounds * 0.82, min_radius)
	)
	var placed: Array[Vector2] = []
	var entry := _pick_annulus_point(rng, min_radius, max_radius, placed)
	placed.append(entry)
	var target := _pick_annulus_point(
		rng,
		min_radius,
		max_radius,
		placed,
		TARGET_BEACON_MIN_DIST,
		entry
	)
	return {
		"entry_position": entry,
		"target_position": target,
	}


static func escort_positions(
	target_pos: Vector2,
	entry_pos: Vector2,
	escort_count: int,
	rng: RandomNumberGenerator
) -> Array:
	var out: Array = []
	if escort_count <= 0:
		return out
	for index in escort_count:
		var angle := TAU * float(index) / float(escort_count) + rng.randf_range(-0.2, 0.2)
		var pos := target_pos + Vector2.from_angle(angle) * 480.0
		if pos.distance_to(entry_pos) < 800.0:
			pos = target_pos + Vector2.from_angle(angle + PI * 0.5) * 520.0
		out.append(pos)
	return out


static func apply_hidden_behaviors(
	catalog: Catalog,
	offer: Dictionary,
	setup: Dictionary,
	rng: RandomNumberGenerator
) -> void:
	var template_id := str(offer.get("target_template_id", ""))
	var profile: Dictionary = offer.get("threat_profile", {})
	if typeof(profile) != TYPE_DICTIONARY:
		profile = BountyCharters._threat_profile({"profile": profile})
	var escort_count := maxi(0, int(profile.get("escort_count", 0)))
	var threat_skill := str(profile.get("pilot_skill", ""))
	var entry_pos := _vec_from_setup(setup.get("entry_position", {}))

	var pattern := _pick_group_pattern(rng, escort_count)
	var target: Dictionary = setup.get("bounty_target", {})
	if typeof(target) != TYPE_DICTIONARY:
		return
	_fill_ship_behavior(
		catalog,
		rng,
		target,
		template_id,
		threat_skill,
		true,
		pattern,
		entry_pos,
		0
	)
	setup["bounty_target"] = target

	var escorts: Variant = setup.get("bounty_escorts", [])
	if typeof(escorts) != TYPE_ARRAY:
		return
	for index in range(escorts.size()):
		var escort_variant = escorts[index]
		if typeof(escort_variant) != TYPE_DICTIONARY:
			continue
		var escort: Dictionary = escort_variant
		_fill_ship_behavior(
			catalog,
			rng,
			escort,
			template_id,
			threat_skill,
			false,
			pattern,
			entry_pos,
			index + 1
		)
		escorts[index] = escort
	setup["bounty_escorts"] = escorts


static func ship_record_to_actor_fields(record: Dictionary, entry_pos: Vector2, play_bounds: float) -> Dictionary:
	return {
		"posture": str(record.get("posture", "aggressive")),
		"resolve": str(record.get("resolve", "fight")),
		"station": str(record.get("station", "hold")),
		"flee_route": str(record.get("flee_route", "beacon")),
		"transponder": bool(record.get("transponder", true)),
		"is_named_target": bool(record.get("is_named_target", false)),
		"entry_beacon": entry_pos,
		"play_bounds": play_bounds,
	}


static func find_charter_for_target(missions: MissionSubsystem, target_id: String) -> Dictionary:
	if missions == null or target_id.is_empty():
		return {}
	for entry_variant in missions.list_bounty_accepted():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("bounty_target_id", "")) == target_id:
			return entry
	return {}


static func contract_volatile_sector(charter: Dictionary) -> String:
	return BountyCharters.bounty_sector_for_contract(charter)


static func record_bounty_contact(
	session: GameSession,
	charter: Dictionary,
	target_id: String,
	kind: String
) -> void:
	if session == null or charter.is_empty() or target_id.is_empty():
		return
	var sector_id := contract_volatile_sector(charter)
	if sector_id.is_empty():
		return
	var accepted_gst := float(charter.get("accepted_gst", 0.0))
	session.player.record_target_scan(
		target_id,
		kind,
		sector_id,
		maxf(float(session.gst_seconds), accepted_gst + 0.001)
	)
	session.changed.emit()


static func start_pursuit(charter: Dictionary, flee_route: String) -> Dictionary:
	var pursuit: Dictionary = {}
	var raw: Variant = charter.get("bounty_pursuit", {})
	if typeof(raw) == TYPE_DICTIONARY:
		pursuit = raw
	if str(pursuit.get("phase", "")) not in ["", "none"]:
		return pursuit
	pursuit = {
		"phase": "unspace",
		"elapsed": 0.0,
		"flee_route": flee_route,
	}
	return pursuit


static func tick_pursuit(pursuit: Dictionary, delta: float, in_flight: bool) -> Dictionary:
	if pursuit.is_empty():
		return {}
	var phase := str(pursuit.get("phase", ""))
	if phase.is_empty() or phase == "none" or phase == "failed":
		return pursuit
	if not in_flight or delta <= 0.0:
		return pursuit
	var elapsed := float(pursuit.get("elapsed", 0.0)) + delta
	pursuit["elapsed"] = elapsed
	var limit := PURSUIT_UNSPACE_SECONDS if phase == "unspace" else PURSUIT_ORIGIN_DOCK_SECONDS
	if elapsed >= limit:
		pursuit["phase"] = "failed"
	return pursuit


static func advance_pursuit_phase(
	pursuit: Dictionary,
	charter: Dictionary,
	session: GameSession
) -> Dictionary:
	if pursuit.is_empty() or session == null:
		return pursuit
	var phase := str(pursuit.get("phase", ""))
	if phase != "unspace":
		return pursuit
	if session.in_unspace:
		return pursuit
	var origin := str(charter.get("origin_sector_id", ""))
	if not origin.is_empty() and session.sector_id != origin:
		return pursuit
	pursuit["phase"] = "origin_dock"
	pursuit["elapsed"] = 0.0
	return pursuit


static func pursuit_failed(pursuit: Dictionary) -> bool:
	return str(pursuit.get("phase", "")) == "failed"


static func _pick_group_pattern(rng: RandomNumberGenerator, escort_count: int) -> String:
	if escort_count <= 0:
		return "solo"
	var roll := rng.randf()
	if roll < 0.28:
		return "matched"
	if roll < 0.52:
		return "bodyguard"
	if roll < 0.76:
		return "ambush"
	return "decoy"


static func _fill_ship_behavior(
	catalog: Catalog,
	rng: RandomNumberGenerator,
	ship: Dictionary,
	template_id: String,
	threat_skill: String,
	is_target: bool,
	pattern: String,
	entry_pos: Vector2,
	escort_index: int
) -> void:
	var posture := "aggressive"
	var resolve := "fight"
	var station := "hold"
	var transponder := true

	match pattern:
		"solo":
			posture = POSTURES[rng.randi_range(0, POSTURES.size() - 1)]
			resolve = RESOLVES[rng.randi_range(0, RESOLVES.size() - 1)]
			station = STATIONS[rng.randi_range(0, STATIONS.size() - 1)]
			transponder = rng.randf() > 0.35
		"matched":
			posture = POSTURES[rng.randi_range(0, POSTURES.size() - 1)]
			resolve = RESOLVES[rng.randi_range(0, RESOLVES.size() - 1)]
			station = STATIONS[rng.randi_range(0, STATIONS.size() - 1)]
			transponder = rng.randf() > 0.4
		"bodyguard":
			if is_target:
				posture = "stealthy" if rng.randf() > 0.5 else "oblivious"
				resolve = "flee" if rng.randf() > 0.45 else "fight"
				station = "hold"
				transponder = false
			else:
				posture = "aggressive"
				resolve = "fight"
				station = "wander" if rng.randf() > 0.35 else "hold"
				transponder = true
		"ambush":
			posture = "stealthy"
			resolve = "fight"
			station = "hold"
			transponder = false
		"decoy":
			if is_target:
				posture = "stealthy"
				resolve = "flee" if rng.randf() > 0.55 else "fight"
				station = "hold"
				transponder = false
			elif escort_index == 1:
				posture = "aggressive"
				resolve = "fight"
				station = "wander"
				transponder = true
			else:
				posture = "aggressive"
				resolve = "fight"
				station = "hold"
				transponder = rng.randf() > 0.3

	var pilot_skill := _roll_pilot_skill(rng, threat_skill, is_target)
	var flee_route := ""
	if resolve == "flee":
		flee_route = _roll_flee_route(catalog, template_id, rng)

	ship["posture"] = posture
	ship["resolve"] = resolve
	ship["station"] = station
	ship["transponder"] = transponder
	ship["pilot_skill"] = pilot_skill
	ship["is_named_target"] = is_target
	if not flee_route.is_empty():
		ship["flee_route"] = flee_route
	ship["entry_beacon"] = {"x": entry_pos.x, "y": entry_pos.y}


static func _roll_pilot_skill(
	rng: RandomNumberGenerator,
	threat_skill: String,
	is_target: bool
) -> String:
	if not threat_skill.is_empty() and is_target:
		return threat_skill
	if not threat_skill.is_empty() and rng.randf() < 0.55:
		return threat_skill
	return SKILLS[rng.randi_range(0, SKILLS.size() - 1)]


static func _roll_flee_route(catalog: Catalog, template_id: String, rng: RandomNumberGenerator) -> String:
	var can_hd := _template_has_hyperdrive(catalog, template_id)
	var roll := rng.randf()
	if can_hd and roll < 0.28:
		return "hyperdrive"
	if roll < 0.62:
		return "beacon"
	return "deep_space"


static func _template_has_hyperdrive(catalog: Catalog, template_id: String) -> bool:
	if catalog == null or template_id.is_empty():
		return false
	var template := catalog.get_ship_def(template_id)
	if template == null:
		return false
	var owned := OwnedShip.from_template(
		catalog,
		{"id": "bounty_hd_%s" % template_id, "template_id": template_id, "chassis_id": template.chassis}
	)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	return Hyperdrive.fitted_module(assembled) != null


static func _pick_annulus_point(
	rng: RandomNumberGenerator,
	min_radius: float,
	max_radius: float,
	placed: Array,
	min_sep: float = VolatileSites.MIN_SEPARATION,
	avoid_point: Vector2 = Vector2.ZERO,
	avoid_dist: float = 0.0
) -> Vector2:
	var best := Vector2.ZERO
	for _attempt in range(VolatileSites.PLACE_ATTEMPTS * 2):
		var radius := rng.randf_range(min_radius, max_radius)
		var angle := rng.randf() * TAU
		var candidate := Vector2(cos(angle), sin(angle)) * radius
		if avoid_dist > 0.0 and candidate.distance_to(avoid_point) < avoid_dist:
			continue
		if _separated(candidate, placed, min_sep):
			return candidate
		best = candidate
	if best.length_squared() > 1.0:
		return best
	return Vector2(cos(rng.randf() * TAU), sin(rng.randf() * TAU)) * rng.randf_range(min_radius, max_radius)


static func _separated(candidate: Vector2, placed: Array, min_sep: float) -> bool:
	for other_variant in placed:
		if typeof(other_variant) != TYPE_VECTOR2:
			continue
		var other: Vector2 = other_variant
		if candidate.distance_to(other) < min_sep:
			return false
	return true


static func _vec_from_setup(raw: Variant) -> Vector2:
	if typeof(raw) != TYPE_DICTIONARY:
		return Vector2.ZERO
	var dict: Dictionary = raw
	return Vector2(float(dict.get("x", 0.0)), float(dict.get("y", 0.0)))
