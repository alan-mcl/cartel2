class_name TestModuleDominance
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var ctx := BalanceMetrics.build_context(catalog, {})
	var pairs: Array = BalanceMetrics.dominated_pairs(
		BalanceMetrics.module_dominance_entries(ctx, true)
	)
	for pair_variant in pairs:
		var pair: Dictionary = pair_variant
		runner.check(
			false,
			"dominated module %s by %s" % [str(pair.get("id", "")), str(pair.get("by", ""))]
		)
	runner.check(pairs.is_empty(), "no strictly dominated modules with signature counted")
