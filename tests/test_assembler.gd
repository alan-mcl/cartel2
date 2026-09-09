class_name TestAssembler
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()

	for ship_id in ["flare_on_ss", "pegasus_p101"]:
		var assembled := ShipAssembler.assemble(catalog, ship_id)
		runner.check(not assembled.id.is_empty(), "%s assembles" % ship_id)
		runner.check(assembled.stats.max_speed > 0.0, "%s max_speed > 0" % ship_id)
		runner.check(assembled.stats.forward_thrust > 0.0, "%s forward_thrust > 0" % ship_id)
