class_name TestTemplatePower
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var ctx := BalanceMetrics.build_context(catalog, {})
	var probes: Array = ctx["templates"]
	runner.check(probes.size() >= 1, "template power: probes built")
	for probe_variant in probes:
		var probe: Dictionary = probe_variant
		var template_id := str(probe.get("id", ""))
		var margin := float(probe.get("power_margin", -999.0))
		var combat_margin := float(probe.get("combat_power_margin", -999.0))
		var starved: Array = probe.get("starved_when_firing", [])
		runner.check(
			margin >= -BalanceMetrics.EPSILON,
			"template %s engine-on power margin (%.2f)" % [template_id, margin]
		)
		runner.check(
			combat_margin >= -BalanceMetrics.EPSILON,
			"template %s firing power margin (%.2f)" % [template_id, combat_margin]
		)
		runner.check(
			starved.is_empty(),
			"template %s no starved categories while firing (%s)" % [template_id, ", ".join(starved)]
		)
