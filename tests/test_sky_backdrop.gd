class_name TestSkyBackdrop
extends RefCounted

const LocalStarScript := preload("res://scripts/presentation/local_star.gd")
const PlanetBackdropScript := preload("res://scripts/presentation/planet_backdrop.gd")
const SkyParentBodyScript := preload("res://scripts/presentation/sky_parent_body.gd")
const WorldLoaderScript := preload("res://scripts/presentation/world_loader.gd")


static func run(runner: TestRunner, tree: SceneTree = null) -> void:
	_test_parent_sun_direction_canvas(runner)
	_test_planet_display_exposure(runner)
	_test_planet_irradiance_at_orbit(runner)
	_test_angular_radius_math(runner)
	_test_parent_params(runner)
	_test_titania_angular_roll(runner, tree)
	_test_sector_spawns(runner, tree)
	_test_interchangeable_renderers(runner, tree)
	_test_atmosphere_strength(runner)


static func _test_atmosphere_strength(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	runner.check(
		absf(
			PlanetBackdropScript.resolve_atmosphere_strength(catalog.get_world("proxima").get("planet", {}))
			- PlanetBackdropScript.DEFAULT_ATMOSPHERE_STRENGTH
		) < 0.001,
		"atmosphere strength: proxima defaults to 0.42"
	)
	var acb2: Dictionary = catalog.get_world("acb2").get("planet", {})
	runner.check(
		absf(PlanetBackdropScript.resolve_atmosphere_strength(acb2)) < 0.001,
		"atmosphere strength: acb2 airless is 0"
	)
	var new_ceres: Dictionary = catalog.get_world("new_ceres").get("planet", {})
	runner.check(
		PlanetBackdropScript.resolve_atmosphere_strength(new_ceres)
		> PlanetBackdropScript.DEFAULT_ATMOSPHERE_STRENGTH,
		"atmosphere strength: new_ceres above default"
	)


static func _test_parent_sun_direction_canvas(runner: TestRunner) -> void:
	var star_above := Vector2(0.0, -8000.0)
	var canvas := PlanetBackdropScript.sun_direction_canvas_from_star(star_above)
	runner.check(
		canvas.y < 0.0,
		"parent sun: star above yields negative canvas Y"
	)
	runner.check(
		absf(canvas.z) < 0.001,
		"parent sun: canvas sun stays in the play plane"
	)
	var star_right := Vector2(9000.0, 0.0)
	var right_canvas := PlanetBackdropScript.sun_direction_canvas_from_star(star_right)
	runner.check(right_canvas.x > 0.0, "parent sun: star to the right yields positive canvas X")
	runner.check(
		absf(right_canvas.z) < 0.001,
		"parent sun: right-bearing sun has no depth tilt"
	)


static func _test_planet_display_exposure(runner: TestRunner) -> void:
	runner.check(
		absf(PlanetExposure.display_exposure(1.0) - 2.5) < 0.001,
		"planet exposure: 1 AU reference exposure"
	)
	var pluto_irradiance := 1.0 / 900.0
	var pluto_dayside := PlanetExposure.display_from_radiance(
		Vector3.ONE * PlanetExposure.linear_irradiance_at_surface(pluto_irradiance, 1.0),
		pluto_irradiance
	)
	var close_irradiance := StarAppearance.irradiance(1.0, 0.05)
	runner.check(
		close_irradiance > 300.0,
		"planet exposure: close orbit irradiance stays physical"
	)
	var close_display := PlanetExposure.display_from_radiance(
		Vector3.ONE * close_irradiance,
		close_irradiance
	)
	runner.check(
		close_display.x < 0.95,
		"planet exposure: close-orbit dayside tonemaps below white clip"
	)
	var one_au := PlanetExposure.display_from_radiance(
		Vector3.ONE * PlanetExposure.linear_irradiance_at_surface(1.0, 1.0),
		1.0
	)
	runner.check(
		one_au.x > 0.35 and one_au.x < 0.88,
		"planet exposure: 1 AU dayside lands mid-bright"
	)
	runner.check(
		pluto_dayside.x < one_au.x,
		"planet exposure: ~30 AU Pluto dayside dimmer than 1 AU midday"
	)
	runner.check(
		pluto_dayside.x > 0.22 and pluto_dayside.x < 0.45,
		"planet exposure: Pluto dayside reads as dusk band"
	)
	var dim_irradiance := StarAppearance.irradiance(1.0, 32.0)
	var dim_display := PlanetExposure.display_from_radiance(
		Vector3.ONE * PlanetExposure.linear_irradiance_at_surface(dim_irradiance, 1.0),
		dim_irradiance
	)
	runner.check(
		dim_display.x > PlanetExposure.display_from_radiance(
			Vector3.ONE * PlanetExposure.night_irradiance(dim_irradiance),
			dim_irradiance
		).x,
		"planet exposure: dim dayside brighter than night side"
	)
	runner.check(dim_display.x > 0.03, "planet exposure: dim dayside stays above black floor")
	var kuiper_irradiance := StarAppearance.irradiance(0.34, 85.0)
	var kuiper_display := PlanetExposure.display_from_radiance(
		Vector3.ONE * PlanetExposure.linear_irradiance_at_surface(kuiper_irradiance, 1.0),
		kuiper_irradiance
	)
	runner.check(kuiper_display.x < pluto_dayside.x, "planet exposure: 85 AU dimmer than Pluto-scale dusk")
	runner.check(kuiper_display.x > 0.1, "planet exposure: 85 AU outer belt stays above black floor")


static func _test_planet_irradiance_at_orbit(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_sector_irradiance_matches_radiant(runner, catalog, "horizon", "Epsilon Eridani")
	_test_sector_irradiance_matches_radiant(runner, catalog, "new_carthage", "61 Cygni A")
	_test_sector_irradiance_matches_radiant(runner, catalog, "depot_61c", "61 Cygni A")
	_test_sector_irradiance_matches_radiant(runner, catalog, "nightjar", "61 Cygni B")
	var sector := catalog.get_sector_def("titania")
	var world := catalog.get_world("titania")
	var star_data: Dictionary = world.get("star", {})
	var lum := float(star_data.get("luminosity", 1.0))
	var au := sector.star_distance_au
	var irradiance := PlanetBackdropScript.irradiance_index(lum, au)
	runner.check(
		absf(irradiance - sector.neighborhood.radiant) < 0.02,
		"planet irradiance matches sector radiant for titania"
	)
	var star_facts := catalog.get_star("Epsilon Reticuli A")
	var angular := LocalStarScript.angular_disc_scale(
		float(star_facts.get("radius_solar", 1.0)),
		au
	)
	runner.check(
		absf(angular - 3.18 / 3.2) < 0.05,
		"titania primary angular disc scale is radius over distance"
	)


static func _test_sector_irradiance_matches_radiant(
	runner: TestRunner,
	catalog: Catalog,
	sector_id: String,
	catalog_star_name: String
) -> void:
	var sector := catalog.get_sector_def(sector_id)
	var facts := catalog.get_star(catalog_star_name)
	var lum := float(facts.get("luminosity", 1.0))
	var ir := PlanetBackdropScript.irradiance_index(lum, sector.star_distance_au)
	runner.check(
		absf(ir - sector.neighborhood.radiant) < 0.02,
		"%s catalog irradiance matches sector radiant" % sector_id
	)


static func _test_angular_radius_math(runner: TestRunner) -> void:
	var distance := 8000.0
	var radius := SkyBackdropLayout.disc_radius_from_angular(14.0, distance)
	runner.check(radius > 900.0 and radius < 1100.0, "sky backdrop: 14 deg disc radius at 8k")
	var min_dist := SkyBackdropLayout.min_distance_for_parent(20.0, 2.2)
	runner.check(min_dist >= SkyBackdropLayout.STAR_MIN_RADIUS, "sky backdrop: parent min distance on annulus")
	runner.check(
		min_dist - SkyBackdropLayout.disc_radius_from_angular(20.0, min_dist) * 2.2
		>= SkyBackdropLayout.INNER_CLEARANCE_RADIUS - 1.0,
		"sky backdrop: broad parent clears play ring"
	)


static func _test_parent_params(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var world := catalog.get_world("titania")
	var parent_data: Dictionary = world.get("parent_body", {})
	var resolved := SkyParentBodyParams.resolve_from_parent(parent_data)
	runner.check(str(resolved.get("type_label", "")) == "Gas giant", "sky backdrop: type label")
	var appearance: Dictionary = resolved.get("appearance", {})
	runner.check(
		str(appearance.get("band_colour_1", "")) == "#857052",
		"sky backdrop: band colour from world"
	)
	var rings: Dictionary = resolved.get("rings", {})
	runner.check(
		absf(SkyParentBodyParams.ring_outer_scale(rings) - 1.0) < 0.001,
		"sky backdrop: none ring outer_scale 1"
	)
	var typhon_world := catalog.get_world("typhon_xvi")
	var typhon: Dictionary = typhon_world.get("parent_body", {})
	var typhon_resolved := SkyParentBodyParams.resolve_from_parent(typhon)
	var typhon_rings: Dictionary = typhon_resolved.get("rings", {})
	runner.check(
		absf(SkyParentBodyParams.ring_outer_scale(typhon_rings) - 2.2) < 0.01,
		"sky backdrop: broad legacy ring outer radius 2.2"
	)
	_test_appearance_schemes(runner)


static func _test_appearance_schemes(runner: TestRunner) -> void:
	var uniform_parent := {
		"name": "Test Uniform",
		"type": "gas_giant",
		"appearance": {
			"type": "uniform",
			"atmosphere": {"colours": ["#445566"]},
		},
	}
	var uniform_resolved := SkyParentBodyParams.resolve_from_parent(uniform_parent, "scheme-test")
	runner.check(not uniform_resolved.is_empty(), "sky backdrop: uniform appearance resolves")
	runner.check(
		SkyParentBodyParams.appearance_scheme_index("uniform") == 1,
		"sky backdrop: uniform scheme index"
	)
	var mottled_parent := {
		"name": "Test Mottled",
		"type": "gas_giant",
		"appearance": {
			"type": "mottled",
			"atmosphere": {
				"colours": ["#112233", "#445566", "#778899"],
				"band_edge_softness": 0.4,
			},
		},
	}
	runner.check(
		not SkyParentBodyParams.resolve_from_parent(mottled_parent, "mottled").is_empty(),
		"sky backdrop: mottled appearance resolves"
	)
	var atm: Dictionary = {"band_edge_softness": 0.2}
	runner.check(
		absf(SkyParentBodyParams.resolve_band_edge_softness(atm) - 0.2) < 0.001,
		"sky backdrop: band_edge_softness"
	)
	atm = {"band_blur": 0.15}
	runner.check(
		absf(SkyParentBodyParams.resolve_band_edge_softness(atm) - 0.15) < 0.001,
		"sky backdrop: band_blur aliases to edge softness"
	)
	atm = {}
	runner.check(
		absf(
			SkyParentBodyParams.resolve_band_edge_softness(atm)
			- SkyParentBodyParams.DEFAULT_BAND_EDGE_SOFTNESS
		) < 0.001,
		"sky backdrop: default edge softness"
	)
	var palette := SkyParentBodyParams.build_band_palette("palette-test", 4)
	runner.check(palette.size() == SkyParentBodyParams.BAND_PALETTE_SIZE, "sky backdrop: band_palette length")
	for i in range(1, palette.size()):
		if palette[i - 1] == palette[i]:
			runner.check(false, "sky backdrop: adjacent band_palette indices differ")
			return
		runner.check(palette[i] >= 0 and palette[i] < 4, "sky backdrop: band_palette index in range")
	runner.check(true, "sky backdrop: adjacent band_palette indices differ")


static func _test_titania_angular_roll(runner: TestRunner, tree: SceneTree) -> void:
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		runner.check(false, "sky backdrop: SceneTree for titania roll")
		return
	var catalog := Catalog.load_default()
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "SKY-2", "tester"), "sky backdrop: session for titania roll")
	var host := Node2D.new()
	tree.root.add_child(host)
	for _attempt in range(12):
		for child in host.get_children():
			child.free()
		var loader := WorldLoader.new()
		loader.load_sector(host, catalog, session, "titania")
		var parent: Variant = loader.spawned_by_id.get("parent_body")
		runner.check(parent != null, "sky backdrop: titania parent on roll attempt")
		if parent != null and parent.has_method("get_angular_diameter_deg"):
			var angular := float(parent.call("get_angular_diameter_deg"))
			runner.check(angular >= 10.0 and angular <= 16.0, "sky backdrop: titania angular in 10-16")
	host.queue_free()


static func _test_interchangeable_renderers(runner: TestRunner, tree: SceneTree) -> void:
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		runner.check(false, "interchangeable renderers: SceneTree available")
		return
	var catalog := Catalog.load_default()
	var vulcan_world := catalog.get_world("vulcan_research")
	var vulcan_planet: Dictionary = vulcan_world.get("planet", {})
	runner.check(
		str(vulcan_planet.get("renderer", "")) == "procedural",
		"interchangeable: vulcan_research planet is procedural"
	)
	runner.check(
		not SkyParentBodyParams.resolve_from_parent(vulcan_planet, "vulcan_research").is_empty(),
		"interchangeable: vulcan procedural appearance resolves"
	)
	var byrsa_world := catalog.get_world("byrsa")
	var byrsa_parent: Dictionary = byrsa_world.get("parent_body", {})
	runner.check(
		str(byrsa_parent.get("renderer", "")) == "textured",
		"interchangeable: byrsa parent is textured"
	)
	runner.check(
		str(byrsa_parent.get("texture_sector", "")) == "new_carthage",
		"interchangeable: byrsa parent texture_sector"
	)
	var carthage: Dictionary = catalog.get_world("new_carthage").get("planet", {})
	runner.check(carthage.has("albedo"), "interchangeable: new_carthage albedo for byrsa parent")

	var host := Node2D.new()
	tree.root.add_child(host)
	var session := GameSession.new()
	runner.check(
		session.start_new_game(catalog, "INT-1", "tester"),
		"interchangeable: session starts"
	)
	for child in host.get_children():
		child.free()
	var vulcan_loader := WorldLoaderScript.new()
	vulcan_loader.load_sector(host, catalog, session, "vulcan_research")
	var vulcan_planet_node: Variant = vulcan_loader.spawned_by_id.get("planet")
	runner.check(vulcan_planet_node is SkyParentBodyScript, "interchangeable: vulcan spawns SkyParentBody at planet")
	if vulcan_planet_node != null and vulcan_planet_node.has_method("get_disc_radius"):
		runner.check(
			absf(float(vulcan_planet_node.call("get_disc_radius")) - 1400.0) < 0.01,
			"interchangeable: vulcan disc radius 1400"
		)
		runner.check(
			(vulcan_planet_node as Node2D).global_position.length_squared() < 1.0,
			"interchangeable: vulcan procedural planet at origin"
		)

	for child in host.get_children():
		child.free()
	var byrsa_loader := WorldLoaderScript.new()
	byrsa_loader.load_sector(host, catalog, session, "byrsa")
	var byrsa_parent_node: Variant = byrsa_loader.spawned_by_id.get("parent_body")
	runner.check(byrsa_parent_node is PlanetBackdropScript, "interchangeable: byrsa parent is PlanetBackdrop")
	if byrsa_parent_node is Node2D:
		runner.check(
			(byrsa_parent_node as Node2D).global_position.length_squared() > 1.0,
			"interchangeable: byrsa textured parent off origin"
		)
	if byrsa_parent_node != null and byrsa_parent_node.has_method("visible_surface_labels"):
		runner.check(
			(byrsa_parent_node.call("visible_surface_labels") as Array).is_empty(),
			"interchangeable: distant parent has no surface labels"
		)
	host.queue_free()


static func _test_sector_spawns(runner: TestRunner, tree: SceneTree) -> void:
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		runner.check(false, "sky backdrop: SceneTree available")
		return

	var catalog := Catalog.load_default()
	var host := Node2D.new()
	tree.root.add_child(host)
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "SKY-1", "tester"), "sky backdrop: session starts")

	_assert_world(runner, host, catalog, session, "titania", true, 0, 0)
	_assert_world(runner, host, catalog, session, "proxima", false, 2, 0)
	_assert_world(runner, host, catalog, session, "bela", false, 0, 0)
	_assert_world(runner, host, catalog, session, "pelagos", false, 1, 0)
	_assert_tycho_widow(runner, host, catalog, session)

	host.queue_free()


static func _assert_world(
	runner: TestRunner,
	host: Node2D,
	catalog: Catalog,
	session: GameSession,
	sector_id: String,
	expect_parent: bool,
	companion_count: int,
	_widow_index: int
) -> void:
	for child in host.get_children():
		child.free()
	var loader := WorldLoader.new()
	loader.load_sector(host, catalog, session, sector_id)
	runner.check(
		loader.spawned_by_id.has("parent_body") == expect_parent,
		"sky backdrop: %s parent_body spawn" % sector_id
	)
	runner.check(
		loader.get_companion_star_nav_entries().size() == companion_count,
		"sky backdrop: %s companion count" % sector_id
	)


static func _assert_tycho_widow(
	runner: TestRunner,
	host: Node2D,
	catalog: Catalog,
	session: GameSession
) -> void:
	for child in host.get_children():
		child.free()
	var loader := WorldLoader.new()
	loader.load_sector(host, catalog, session, "tycho")
	runner.check(loader.get_companion_star_nav_entries().size() == 2, "sky backdrop: tycho two companions")
	var widow_found := false
	for entry_variant in loader.get_companion_star_nav_entries():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("name", "")) == "The Widow":
			widow_found = true
			runner.check(bool(entry.get("presentation_only", false)), "sky backdrop: widow presentation-only")
			var render := {
				"temperature_k": entry.get("star_temperature_k", 0.0),
				"luminosity": entry.get("star_luminosity", 0.0),
				"disc_radius": 3.0,
			}
			var resolved := LocalStarScript.defaults_from_star_data(render)
			runner.check(
				absf(float(resolved.get("disc_radius", 0.0)) - 3.0) < 0.01,
				"sky backdrop: widow disc radius 3"
			)
	var world := catalog.get_world("tycho")
	var companions: Array = world.get("companion_stars", [])
	var widow_sep := -1.0
	for entry_variant in companions:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("name", "")) == "The Widow":
			widow_sep = float(entry.get("separation_deg", -1.0))
	runner.check(widow_found, "sky backdrop: tycho widow nav entry")
	runner.check(absf(widow_sep - 1.4) < 0.01, "sky backdrop: widow separation 1.4 deg at Tycho")
