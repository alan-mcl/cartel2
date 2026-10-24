class_name TestBalanceMetrics
extends RefCounted

const QUICK_OPTIONS := {"trade_days": 2, "charter_days": 1, "charter_seeds": [7]}

## Sections that stay populated whatever the catalog holds. The rest (dominated modules, outliers,
## bounty tables) may legitimately empty out once their findings are fixed.
const ALWAYS_POPULATED: Array[String] = [
	"settings",
	"templates",
	"template_loads",
	"template_earnings",
	"refit_holds",
	"trade_commodities",
	"charters",
	"module_dominance",
	"weapons",
	"mount_tiers",
	"fuel_bands",
	"fuel_templates",
	"repair_rates",
	"repair_templates",
	"backgrounds",
	"code_checks",
]


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_dominance_fixture(runner)
	_test_power_law_fit(runner)
	_test_cell_format(runner)
	_test_markdown_alignment(runner)
	_test_parts_sale_below_used_price(runner, catalog)
	_test_sections(runner, catalog)


static func _entry(id: String, cost: float, high: Dictionary, low: Dictionary, capabilities: Array = [], group: String = "g") -> Dictionary:
	var lows := low.duplicate()
	lows["cost"] = cost
	return {"id": id, "group": group, "cost": cost, "high": high, "low": lows, "capabilities": capabilities}


static func _test_dominance_fixture(runner: TestRunner) -> void:
	var entries := [
		_entry("base", 100.0, {"output": 10.0}, {"mass": 1.0}),
		_entry("pricier_clone", 120.0, {"output": 10.0}, {"mass": 1.0}),
		_entry("twin", 100.0, {"output": 10.0}, {"mass": 1.0}),
		_entry("cheap_weak", 90.0, {"output": 9.0}, {"mass": 1.0}),
		_entry("special", 150.0, {"output": 10.0}, {"mass": 1.0}, ["luxury"]),
		_entry("other_mount", 120.0, {"output": 10.0}, {"mass": 1.0}, [], "h"),
	]
	var by := {}
	for pair_variant in BalanceMetrics.dominated_pairs(entries):
		var pair: Dictionary = pair_variant
		by[pair["id"]] = pair["by"]
	runner.check(by.has("pricier_clone"), "balance: dearer clone is dominated")
	runner.check(str(by.get("pricier_clone", "")) in ["base", "twin"], "balance: dominator is a cheaper equal")
	runner.check(not by.has("base") and not by.has("twin"), "balance: identical modules do not dominate each other")
	runner.check(not by.has("cheap_weak"), "balance: cheaper and weaker is a trade-off, not dominated")
	runner.check(not by.has("special"), "balance: a capability the others lack prevents dominance")
	runner.check(not by.has("other_mount"), "balance: different mount groups are not compared")
	var plain := _entry("plain", 100.0, {"output": 10.0}, {"mass": 1.0})
	var flagged := _entry("flagged", 100.0, {"output": 10.0}, {"mass": 1.0}, ["luxury"])
	runner.check(BalanceMetrics.dominates(flagged, plain), "balance: extra capability at equal stats dominates")
	runner.check(not BalanceMetrics.dominates(plain, flagged), "balance: missing capability never dominates")


static func _test_power_law_fit(runner: TestRunner) -> void:
	var points: Array = []
	for x in [1.0, 2.0, 4.0, 8.0]:
		points.append({"x": x, "y": 3.0 * pow(x, 1.5)})
	var fit := BalanceMetrics.fit_power_law(points)
	runner.check(absf(float(fit["exponent"]) - 1.5) < 0.001, "balance: power-law exponent recovered")
	runner.check(absf(float(fit["scale"]) - 3.0) < 0.001, "balance: power-law scale recovered")


static func _test_cell_format(runner: TestRunner) -> void:
	runner.check_eq(BalanceMetrics.format_cell(1234567), "1,234,567", "balance: ints grouped")
	runner.check_eq(BalanceMetrics.format_cell(-4321), "-4,321", "balance: negative ints grouped")
	runner.check_eq(BalanceMetrics.format_cell(12.345), "12.3", "balance: tens keep one decimal")
	runner.check_eq(BalanceMetrics.format_cell(-0.0001), "0.00", "balance: no negative zero")
	runner.check_eq(BalanceMetrics.format_cell(NAN), BalanceMetrics.NONE, "balance: non-finite shows a dash")
	runner.check_eq(BalanceMetrics.format_cell(true), "yes", "balance: bools read yes or no")
	runner.check_eq(BalanceMetrics.format_cell("a|b"), "a/b", "balance: pipes cannot break a table")


static func _test_markdown_alignment(runner: TestRunner) -> void:
	var text := BalanceMetrics.render_markdown([
		{"id": "fixture", "title": "Fixture", "columns": ["Name", "Value"], "rows": [["a", 1], ["b", 2.5]], "notes": []},
	])
	runner.check(text.contains("## Fixture"), "balance: section heading rendered")
	runner.check(text.contains("| --- | ---: |"), "balance: numeric columns right-aligned")
	runner.check(text.contains("| b | 2.50 |"), "balance: rows rendered through format_cell")


## Stripping a used ship and selling the parts must never pay more than the ship cost.
static func _test_parts_sale_below_used_price(runner: TestRunner, catalog: Catalog) -> void:
	var cache := {}
	var checked := 0
	var cheapest_margin := INF
	for template_variant in catalog.ships_by_id.keys():
		var template_id := str(template_variant)
		var parts := BalanceMetrics.parts_sale_value(catalog, template_id, cache)
		var used := ShipAssembly.used_ship_price(catalog, template_id)
		if used <= 0:
			continue
		checked += 1
		cheapest_margin = minf(cheapest_margin, float(used - parts))
		runner.check(parts < used, "balance: %s parts sale (%d) below used price (%d)" % [template_id, parts, used])
	runner.check(checked >= 1, "balance: at least one template priced")
	runner.check(cheapest_margin > 0.0, "balance: every strip-and-sell loses money")


static func _test_sections(runner: TestRunner, catalog: Catalog) -> void:
	var sections := BalanceMetrics.build_all(catalog, QUICK_OPTIONS)
	runner.check(sections.size() >= ALWAYS_POPULATED.size(), "balance: every section built")
	var by_id := {}
	for section_variant in sections:
		var section: Dictionary = section_variant
		var id := str(section.get("id", ""))
		by_id[id] = section
		var columns: Array = section.get("columns", [])
		var rows: Array = section.get("rows", [])
		runner.check(not id.is_empty() and not str(section.get("title", "")).is_empty(), "balance: section has id and title")
		runner.check(not columns.is_empty(), "balance: %s has columns" % id)
		var shaped := true
		var finite := true
		for row_variant in rows:
			var row: Array = row_variant
			if row.size() != columns.size():
				shaped = false
			for cell in row:
				if typeof(cell) == TYPE_FLOAT and not is_finite(float(cell)):
					finite = false
		runner.check(shaped, "balance: %s rows match its columns" % id)
		runner.check(finite, "balance: %s has only finite numbers" % id)
	for id in ALWAYS_POPULATED:
		runner.check(by_id.has(id), "balance: %s section present" % id)
		if by_id.has(id):
			runner.check(not ((by_id[id] as Dictionary)["rows"] as Array).is_empty(), "balance: %s has rows" % id)

	if by_id.has("backgrounds"):
		var excluded := false
		for row_variant in (by_id["backgrounds"] as Dictionary)["rows"]:
			if str((row_variant as Array)[0]) in BalanceMetrics.EXCLUDED_BACKGROUNDS:
				excluded = true
		runner.check(not excluded, "balance: test-only backgrounds are left out")
	if by_id.has("templates"):
		runner.check(
			((by_id["templates"] as Dictionary)["rows"] as Array).size() == catalog.ships_by_id.size(),
			"balance: one template row per ship template"
		)
	var markdown := BalanceMetrics.render_markdown(sections)
	runner.check(markdown.contains("| Template |"), "balance: markdown renders the template table")
