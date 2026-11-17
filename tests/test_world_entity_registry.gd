class_name TestWorldEntityRegistry
extends RefCounted


static func run(runner: TestRunner) -> void:
	for kind in WorldEntityRegistry.registered_kinds():
		runner.check(
			not WorldEntityRegistry.scene_path_for(kind).is_empty(),
			"%s has scene path" % kind
		)

	runner.check_eq(
		WorldEntityRegistry.volatile_contact_profile("debris"),
		{},
		"debris has no volatile contact profile"
	)

	var mine_profile := WorldEntityRegistry.volatile_contact_profile("mine")
	runner.check_eq(str(mine_profile.get("fixed_name", "")), "Mine", "mine fixed contact name")
	runner.check(
		absf(float(mine_profile.get("lock_sprite_radius", 0.0)) - 36.0) < 0.001,
		"mine lock sprite radius"
	)

	var cargo_profile := WorldEntityRegistry.volatile_contact_profile("cargo")
	runner.check_eq(
		str(cargo_profile.get("contact_kind", "")),
		"debris",
		"cargo uses debris contact kind"
	)
	runner.check(
		bool(cargo_profile.get("use_health_ratio", false)),
		"cargo contact includes health ratio"
	)