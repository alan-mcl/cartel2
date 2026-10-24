class_name BalanceMetrics
extends RefCounted

## Balance measurements behind docs/design/content/balance.md and the reports in docs/reports/.
##
## Every figure comes from the game's own assembler, pricing, economy, combat, and charter code,
## so a rule change shows up on the next run instead of drifting from a copied formula. Builders
## return sections shaped {"id", "title", "columns", "rows", "notes"}. Cells are ints, floats, or
## strings, and `render_markdown` formats them. Run it through res://scripts/tools/balance_report.gd.

const EXCLUDED_BACKGROUNDS: Array[String] = ["tester"]
const PROBE_CALLSIGN := "Balance Probe"
const PROBE_DOCK := "balance_probe_dock"
const NONE := "-"

const DEFAULT_OPTIONS := {
	"trade_days": 30,
	"charter_days": 6,
	"charter_seeds": [101, 202, 303],
	"max_hops": 3,
	"top_routes": 15,
	"top_outliers": 25,
}

## Paid repairs are not in the game yet. Until they land, the tool prices them with these proposal
## values; once they ship, read the shipped rule instead.
const REPAIR_INDEX_COMMODITY := "industrial_components"
const REPAIR_PRICE_PER_HULL_POINT := 30.0
const REPAIR_DAMAGE_LEVELS: Array[float] = [0.25, 0.6, 1.0]
const BOUNTY_KEEP_TARGET := 0.6
const BOUNTY_DAMAGE_LEVEL := 0.25
const BREACH_RUNS_LOW := 1.0
const BREACH_RUNS_HIGH := 2.0

const REFIT_STRIP_CATEGORIES: Array[String] = [
	"weapon", "ammunition", "shield", "armour", "point_defence", "cyber_defence", "hyperdrive", "cargo",
]

const SHOT_LIMIT := 300
const COMMON_WEAPON_COUNT := 4
const OUTLIER_RATIO := 1.6
const EPSILON := 0.0001


static func build_all(catalog: Catalog, options: Dictionary = {}) -> Array:
	var ctx := build_context(catalog, options)
	return [
		run_settings_section(ctx),
		templates_section(ctx),
		template_loads_section(ctx),
		template_earnings_section(ctx),
		refit_holds_section(ctx),
		trade_commodities_section(ctx),
		trade_routes_section(ctx),
		charters_section(ctx),
		module_dominance_section(ctx),
		dominated_modules_section(ctx),
		price_curves_section(ctx),
		price_outliers_section(ctx),
		weapons_section(ctx),
		mount_tiers_section(ctx),
		fuel_bands_section(ctx),
		fuel_templates_section(ctx),
		repair_rates_section(ctx),
		repair_yards_section(ctx),
		repair_templates_section(ctx),
		repair_hits_section(ctx),
		bounty_targets_section(ctx),
		bounty_costs_section(ctx),
		backgrounds_section(ctx),
		code_checks_section(ctx),
	]


## Shared, expensive intermediate data. Sections only read from it.
static func build_context(catalog: Catalog, options: Dictionary = {}) -> Dictionary:
	var opts: Dictionary = DEFAULT_OPTIONS.duplicate(true)
	opts.merge(options, true)
	var start_seconds := GalacticCalendar.start_seconds_from_player(catalog.get_player())
	var ctx := {
		"catalog": catalog,
		"options": opts,
		"start_day": CommodityEconomy.gst_day(start_seconds),
		"part_sale_cache": {},
	}
	ctx["trade"] = _build_trade(ctx)
	ctx["fuel_observed"] = _observe_fuel_quotes(ctx)
	ctx["weapons"] = _build_weapon_stats(ctx)
	ctx["templates"] = _build_template_probes(ctx)
	ctx["refits"] = _build_refits(ctx)
	ctx["charters"] = _sample_charters(ctx)
	ctx["bounty"] = _build_bounty_costs(ctx)
	_attach_template_earnings(ctx)
	ctx["repair"] = _build_repair_model(ctx)
	return ctx


# --- Sections ---------------------------------------------------------------------------------


static func run_settings_section(ctx: Dictionary) -> Dictionary:
	var opts: Dictionary = ctx["options"]
	var seeds: Array = opts["charter_seeds"]
	var rows: Array = [
		["Start day (GST day number)", int(ctx["start_day"])],
		["Trade window (days)", int(opts["trade_days"])],
		["Charter sample (days x run seeds)", "%d x %d" % [int(opts["charter_days"]), seeds.size()]],
		["Route search depth (hops)", int(opts["max_hops"])],
		["Reference armour for weapon tables", str(ctx.get("reference_armour_id", NONE))],
		["Repair price index commodity", REPAIR_INDEX_COMMODITY],
		["Proposed hull repair price per point at index 1.0", REPAIR_PRICE_PER_HULL_POINT],
	]
	return _section("settings", "Run settings", ["Setting", "Value"], rows)


static func templates_section(ctx: Dictionary) -> Dictionary:
	var rows: Array = []
	for probe_variant in ctx["templates"]:
		var probe: Dictionary = probe_variant
		var best: Dictionary = probe["best_weapon"]
		rows.append([
			probe["id"],
			int(probe["build_cost"]),
			int(probe["used_price"]),
			int(probe["parts_sale"]),
			int(probe["hull"]),
			float(probe["hold"]),
			int(probe["seats"]),
			float(probe["max_speed"]),
			str(best.get("id", NONE)),
			float(best.get("hull_dps", 0.0)),
		])
	return _section(
		"templates",
		"Ship templates",
		[
			"Template", "Build cost", "Used price", "Parts sale", "Hull", "Hold t", "Seats",
			"Top speed", "Best weapon", "Hull DPS",
		],
		rows,
		[
			"Build cost is the chassis plus every module at full price. Parts sale is what"
			+ " `ShipAssembly.sell_part` pays for the stripped modules. Seats exclude the pilot. Hull"
			+ " DPS is the best fitted weapon against an unprotected hull.",
		]
	)


static func template_loads_section(ctx: Dictionary) -> Dictionary:
	var rows: Array = []
	for probe_variant in ctx["templates"]:
		var probe: Dictionary = probe_variant
		var starved: Array = probe["starved"]
		rows.append([
			probe["id"],
			float(probe["dry_mass"]),
			float(probe["fuel_mass"]),
			float(probe["ammo_mass"]),
			float(probe["unfired_ammo_mass"]),
			float(probe["loaded_mass"]),
			float(probe["mass_limit"]),
			float(probe["accel_loaded"]),
			float(probe["accel_dry"]),
			float(probe["power_margin"]),
			float(probe["combat_power_margin"]),
			", ".join(starved) if not starved.is_empty() else "none",
			float(probe["compute_margin"]),
		])
	return _section(
		"template_loads",
		"Template mass and power",
		[
			"Template", "Dry t", "Fuel t", "Ammo t", "Unfired ammo t", "Loaded t", "Limit t",
			"Accel loaded", "Accel dry", "Power margin", "Power margin firing",
			"Starved when firing", "Compute margin",
		],
		rows,
		[
			"Loaded mass is `ShipAssembler.calculate_loaded_mass` with full fuel and the magazines"
			+ " `ShipAssembler.seed_ammunition` fills. Unfired ammo is the part of that load no fitted"
			+ " weapon fires. The fitting check compares dry mass only with the limit. Acceleration is"
			+ " `forward_thrust` from `ShipAssembler.derive_stats`. Power margins come from"
			+ " `ShipOperations` with the engine on, then with the best weapon firing; starved"
			+ " categories get less power than they ask for while firing.",
		]
	)


static func template_earnings_section(ctx: Dictionary) -> Dictionary:
	var rows: Array = []
	for probe_variant in ctx["templates"]:
		var probe: Dictionary = probe_variant
		var earnings: Dictionary = probe["earnings"]
		var trade_income := float(earnings["trade_income"])
		var payback: Variant = NONE
		if trade_income > 0.0:
			payback = float(probe["used_price"]) / trade_income
		rows.append([
			probe["id"],
			int(probe["used_price"]),
			trade_income,
			float(earnings["trade_capital"]),
			payback,
			str(earnings["trade_pick"]),
			float(earnings["charter_one_hop"]),
			float(earnings["charter_per_hop"]),
			float(earnings["typical_run"]),
		])
	return _section(
		"template_earnings",
		"Template earning power",
		[
			"Template", "Used price", "Trade per hop", "Trade capital", "Payback hops",
			"Trade pick", "Best 1-hop charter", "Best charter per hop", "Typical run",
		],
		rows,
		[
			"Trade per hop is the median, over the trade window, of the best 1-hop run with a full"
			+ " hold of the best commodity the hull may carry, with unlimited credits. Charter columns"
			+ " are medians over sampled boards of the best single offer the hull passes"
			+ " `evaluate_offer_for_ship` for, at reputation 0. Typical run is the best 1-hop charter,"
			+ " or the median bounty pay for an armed hull when that is higher.",
		]
	)


static func refit_holds_section(ctx: Dictionary) -> Dictionary:
	var rows: Array = []
	for refit_variant in ctx["refits"]:
		var refit: Dictionary = refit_variant
		rows.append([
			refit["id"],
			float(refit["hold_built"]),
			float(refit["hold"]),
			float(refit["dry_mass"]),
			float(refit["full_mass"]),
			float(refit["mass_limit"]),
			float(refit["accel_full"]),
			int(refit["outlay"]),
			float(refit["trade_income"]),
			int(refit["blockers"]),
		])
	return _section(
		"refit_holds",
		"Hold after a cargo refit",
		[
			"Template", "Hold as built t", "Refit hold t", "Refit dry t", "Loaded, full hold t",
			"Limit t", "Accel, full hold", "Refit outlay", "Trade per hop after refit",
			"Launch blockers",
		],
		rows,
		[
			"The refit strips weapons, magazines, shields, armour, point defence, cyber defence, the"
			+ " hyperdrive, and the holds, then fills every free slot with the largest cargo module"
			+ " `ShipAssembler.validate_install` accepts. It is greedy, so the hold is a floor, not"
			+ " a maximum. Loaded mass adds full fuel and a full hold. Outlay is the new holds at"
			+ " full price less what `ShipAssembly.sell_part` pays for the stripped parts. Trade per"
			+ " hop uses the same rule as the earning-power table. Launch blockers counts"
			+ " `ShipAssembly.undock_blockers` for a solo pilot.",
		]
	)


static func trade_commodities_section(ctx: Dictionary) -> Dictionary:
	var trade: Dictionary = ctx["trade"]
	var rows: Array = []
	for commodity_variant in trade["commodities"]:
		var commodity: CommodityDef = commodity_variant
		var one_hop_margins: Array = []
		var returns: Array = []
		var rates: Array = []
		var rate_hops: Array = []
		var route_counts := {}
		for best_variant in trade["daily_best"]:
			var best_today: Dictionary = (best_variant as Dictionary).get(commodity.id, {})
			var one_hop: Dictionary = best_today.get("one_hop", {})
			if not one_hop.is_empty():
				one_hop_margins.append(int(one_hop["margin"]))
				returns.append(float(one_hop["margin"]) / float(one_hop["buy"]))
				var route_key := "%s > %s" % [one_hop["from"], one_hop["to"]]
				route_counts[route_key] = int(route_counts.get(route_key, 0)) + 1
			var per_hop: Dictionary = best_today.get("per_hop", {})
			if not per_hop.is_empty():
				rates.append(float(per_hop["rate"]))
				rate_hops.append(int(per_hop["hops"]))
		var top_route := _most_common(route_counts)
		var day_count := maxi(1, (trade["daily_best"] as Array).size())
		var margin := _median(one_hop_margins)
		rows.append([
			commodity.id,
			int(commodity.base_price),
			commodity.mass,
			_capability_label(commodity.requires_capabilities),
			margin,
			margin / commodity.mass,
			_median(returns) * 100.0,
			top_route if not top_route.is_empty() else NONE,
			float(route_counts.get(top_route, 0)) / float(day_count) * 100.0,
			_median(rates),
			_median(rate_hops),
		])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[5]) > float(b[5]))
	return _section(
		"trade_commodities",
		"Trade margins by commodity",
		[
			"Commodity", "Base price", "Mass t", "Hold flags", "Best 1-hop margin", "Per tonne",
			"Return %", "Usual best route", "Days best %", "Best margin per hop", "Hops",
		],
		rows,
		[
			"Margins are `CommodityEconomy.sell_price` at the destination minus the buy quote at the"
			+ " origin, between market sectors, for each day of the window. Medians over days. The"
			+ " per-hop columns allow routes of up to the search depth and divide by hops.",
		]
	)


static func trade_routes_section(ctx: Dictionary) -> Dictionary:
	var trade: Dictionary = ctx["trade"]
	var catalog: Catalog = ctx["catalog"]
	var candidates: Array = []
	for record_variant in (trade["route_margins"] as Dictionary).values():
		var record: Dictionary = record_variant
		var commodity := catalog.get_commodity_def(str(record["commodity"]))
		var margins: Array = record["margins"]
		var hops := int(record["hops"])
		var margin := _median(margins)
		var positive := 0
		for value in margins:
			if int(value) > 0:
				positive += 1
		candidates.append([
			record["commodity"],
			record["from"],
			record["to"],
			hops,
			margin,
			margin / commodity.mass,
			margin / commodity.mass / float(hops),
			_percentile(margins, 0.1),
			float(positive) / float(maxi(1, margins.size())) * 100.0,
		])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[6]) > float(b[6]))
	var limit := int((ctx["options"] as Dictionary).get("top_routes", 15))
	return _section(
		"trade_routes",
		"Top trade routes (up to 2 hops)",
		[
			"Commodity", "From", "To", "Hops", "Median margin", "Per tonne", "Per tonne per hop",
			"10th percentile", "Days positive %",
		],
		candidates.slice(0, limit),
		["Ranked by median margin per tonne per hop. Trades do not move prices and volume is unlimited."]
	)


static func charters_section(ctx: Dictionary) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var samples: Dictionary = (ctx["charters"] as Dictionary)["samples"]
	var passenger_cfg := PassengerCharters.config(catalog)
	var freight_cfg := FreightCharters.config(catalog)
	var adjacency: Dictionary = (ctx["trade"] as Dictionary)["adjacency"]
	var rows: Array = []
	var kinds := [
		["terminal", "Passengers (terminal)", passenger_cfg],
		["bar", "Passengers (bar)", passenger_cfg],
		["freight", "Freight", freight_cfg],
		["scan", "Scan", {}],
		["bounty", "Bounty", {}],
	]
	for kind_variant in kinds:
		var kind: Array = kind_variant
		var offers: Array = samples.get(str(kind[0]), [])
		var cfg: Dictionary = kind[2]
		var rewards: Array = []
		var one_hop: Array = []
		var per_hop: Array = []
		var per_unit: Array = []
		var per_hour: Array = []
		var gated := 0
		for offer_variant in offers:
			var offer: Dictionary = offer_variant
			var reward := int(offer.get("reward", 0))
			rewards.append(reward)
			if int(offer.get("min_reputation", 0)) > 0:
				gated += 1
			if cfg.is_empty():
				continue
			var hops := maxi(1, int(offer.get("hops", 1)))
			if hops == 1:
				one_hop.append(reward)
			per_hop.append(float(reward) / float(hops))
			var units := float(offer.get("tonnes", offer.get("quantity", 0)))
			if units > 0.0:
				per_unit.append(float(reward) / units)
			var hours := _transit_hours(catalog, cfg, offer.get("path_sectors", []), adjacency)
			if hours > 0.0:
				per_hour.append(float(reward) / hours)
		var has_route := not cfg.is_empty()
		rows.append([
			str(kind[1]),
			offers.size(),
			float(gated) / float(maxi(1, offers.size())) * 100.0,
			_percentile(rewards, 0.1),
			_median(rewards),
			_percentile(rewards, 0.9),
			_median(one_hop) if has_route else NONE,
			_median(per_hop) if has_route else NONE,
			_median(per_unit) if has_route else NONE,
			_median(per_hour) if has_route else NONE,
		])
	return _section(
		"charters",
		"Charter pay",
		[
			"Board", "Offers", "Gated %", "10th percentile", "Median", "90th percentile",
			"Median 1-hop", "Per hop", "Per passenger or tonne", "Per GST hour",
		],
		rows,
		[
			"Offers come from the real generators across every habitat that posts them, over the"
			+ " sample days and run seeds. Gated offers need reputation above 0. GST hours are the"
			+ " translation time plus the deadline model's in-system allowance per hop.",
		]
	)


static func module_dominance_section(ctx: Dictionary) -> Dictionary:
	var with_signature := dominated_pairs(module_dominance_entries(ctx, true))
	var without_signature := dominated_pairs(module_dominance_entries(ctx, false))
	var totals := {}
	for def in _sorted_module_defs(ctx["catalog"], ""):
		totals[def.category] = int(totals.get(def.category, 0)) + 1
	var counted := _count_by_category(ctx, with_signature)
	var ignored := _count_by_category(ctx, without_signature)
	var categories: Array = totals.keys()
	categories.sort()
	var rows: Array = []
	for category in categories:
		rows.append([
			str(category),
			int(totals[category]),
			int(counted.get(category, 0)),
			int(ignored.get(category, 0)),
		])
	return _section(
		"module_dominance",
		"Strictly dominated modules by category",
		["Category", "Modules", "Dominated, signature counted", "Dominated, signature ignored"],
		rows,
		[
			"A module is dominated when another module for the same mounts is at least as good on"
			+ " every metric, has every capability it has, and is strictly better on at least one."
			+ " Cost is one of the metrics.",
		]
	)


static func dominated_modules_section(ctx: Dictionary) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var rows: Array = []
	for pair_variant in dominated_pairs(module_dominance_entries(ctx, true)):
		var pair: Dictionary = pair_variant
		var module := catalog.get_module_def(str(pair["id"]))
		var dominator := catalog.get_module_def(str(pair["by"]))
		rows.append([module.category, module.id, int(module.cost), dominator.id, int(dominator.cost)])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if str(a[0]) != str(b[0]):
			return str(a[0]) < str(b[0])
		return str(a[1]) < str(b[1])
	)
	return _section(
		"dominated_modules",
		"Dominated modules (signature counted)",
		["Category", "Module", "Cost", "Cheapest dominating module", "Its cost"],
		rows
	)


static func price_curves_section(ctx: Dictionary) -> Dictionary:
	var rows: Array = []
	for curve_variant in _price_curves(ctx):
		var curve: Dictionary = curve_variant
		var points: Array = curve["points"]
		var high: Dictionary = points[0]
		var low: Dictionary = points[points.size() - 1]
		rows.append([
			curve["group"],
			points.size(),
			str(curve["stat"]),
			float(curve["exponent"]),
			"%s (%.2f)" % [high["id"], float(high["ratio"])],
			"%s (%.2f)" % [low["id"], float(low["ratio"])],
		])
	return _section(
		"price_curves",
		"Module price curves",
		["Group", "Modules", "Main stat", "Cost exponent", "Most overpriced", "Most underpriced"],
		rows,
		[
			"Least-squares fit of log cost against log main stat within each subtype. The exponent"
			+ " is how cost scales with the stat (above 1 is a progression premium). Ratios are cost"
			+ " over fitted cost, so they include whatever the main stat leaves out, such as"
			+ " capability flags.",
		]
	)


static func price_outliers_section(ctx: Dictionary) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var rows: Array = []
	for curve_variant in _price_curves(ctx):
		var curve: Dictionary = curve_variant
		for point_variant in curve["points"]:
			var point: Dictionary = point_variant
			var ratio := float(point["ratio"])
			if ratio < OUTLIER_RATIO and ratio > 1.0 / OUTLIER_RATIO:
				continue
			var def := catalog.get_module_def(str(point["id"]))
			rows.append([
				curve["group"],
				point["id"],
				float(point["stat"]),
				int(point["cost"]),
				float(point["fitted"]),
				ratio,
				_capability_label(def.capabilities),
			])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		return absf(log(float(a[5]))) > absf(log(float(b[5])))
	)
	var limit := int((ctx["options"] as Dictionary).get("top_outliers", 25))
	return _section(
		"price_outliers",
		"Price-curve outliers",
		["Group", "Module", "Main stat", "Cost", "Fitted cost", "Ratio", "Capabilities"],
		rows.slice(0, limit),
		["Modules priced at least %.1fx above or below their subtype curve, largest first." % OUTLIER_RATIO]
	)


static func weapons_section(ctx: Dictionary) -> Dictionary:
	var dominated := {}
	for pair_variant in dominated_pairs(module_dominance_entries(ctx, true, "weapon")):
		dominated[str((pair_variant as Dictionary)["id"])] = str((pair_variant as Dictionary)["by"])
	var rows: Array = []
	for stats_variant in _sorted_weapon_stats(ctx):
		var stats: Dictionary = stats_variant
		var hull_dps := float(stats["hull_dps"])
		rows.append([
			stats["id"],
			stats["mount"],
			stats["weapon_type"],
			stats["delivery"],
			int(stats["cost"]),
			float(stats["raw_dps"]),
			hull_dps,
			float(stats["armoured_hull_dps"]),
			float(stats["power_dps"]),
			float(stats["compute_dps"]),
			float(stats["range"]),
			float(stats["ammo_per_second"]),
			float(stats["ammo_cost_per_second"]),
			float(stats["ammo_mass_per_minute"]),
			bool(stats["pd_interceptable"]),
			float(stats["cost"]) / hull_dps if hull_dps > 0.0 else NONE,
			str(dominated.get(str(stats["id"]), NONE)),
		])
	return _section(
		"weapons",
		"Weapons",
		[
			"Weapon", "Mount", "Type", "Delivery", "Cost", "Raw DPS", "Hull DPS",
			"Hull DPS vs armour", "Power DPS", "Compute DPS", "Range", "Rounds/s", "Ammo d/s",
			"Ammo t/min", "PD can stop", "Cost per hull DPS", "Dominated by",
		],
		rows,
		[
			"One trigger pull through `ShipWeapons.tick`, then `ShipCombat.resolve_hit` per projectile"
			+ " (scatter assumes every pellet lands). The armour column uses the reference armour from"
			+ " the run settings. Ammo costs use the ammunition `cost` field, which nothing charges"
			+ " today.",
		]
	)


static func mount_tiers_section(ctx: Dictionary) -> Dictionary:
	var by_mount := {}
	for stats_variant in _sorted_weapon_stats(ctx):
		var stats: Dictionary = stats_variant
		var mount := str(stats["mount"])
		var group: Array = by_mount.get(mount, [])
		group.append(stats)
		by_mount[mount] = group
	var rows: Array = []
	for mount in ["light_weapon", "medium_weapon", "heavy_weapon"]:
		var group: Array = by_mount.get(mount, [])
		if group.is_empty():
			continue
		var costs: Array = []
		var dps: Array = []
		var best_value := {}
		var best_dps := {}
		for stats_variant in group:
			var stats: Dictionary = stats_variant
			costs.append(int(stats["cost"]))
			dps.append(float(stats["hull_dps"]))
			if best_dps.is_empty() or float(stats["hull_dps"]) > float(best_dps["hull_dps"]):
				best_dps = stats
			var value := float(stats["hull_dps"]) / maxf(1.0, float(stats["cost"])) * 1000.0
			if best_value.is_empty() or value > float(best_value["value"]):
				best_value = {"id": stats["id"], "value": value}
		rows.append([
			mount,
			group.size(),
			_median(costs),
			_median(dps),
			"%s (%.1f)" % [best_dps["id"], float(best_dps["hull_dps"])],
			"%s (%.2f)" % [best_value["id"], float(best_value["value"])],
		])
	return _section(
		"mount_tiers",
		"Weapon mount tiers",
		["Mount", "Weapons", "Median cost", "Median hull DPS", "Highest hull DPS", "Best hull DPS per 1,000 d"],
		rows
	)


static func fuel_bands_section(ctx: Dictionary) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var observed: Dictionary = ctx["fuel_observed"]
	var engines := {}
	for def in _sorted_module_defs(catalog, "propulsion"):
		var fuel_id := ShipFuel.fuel_id_for_engine(def)
		if not fuel_id.is_empty():
			engines[fuel_id] = int(engines.get(fuel_id, 0)) + 1
	var rows: Array = []
	for fuel_variant in catalog.list_fuels():
		var fuel: Dictionary = fuel_variant
		var fuel_id := str(fuel.get("id", ""))
		var prices: Array = observed.get(fuel_id, [])
		rows.append([
			fuel_id,
			int(fuel.get("price_min", 0)),
			int(fuel.get("price_max", 0)),
			_percentile(prices, 0.0),
			_median(prices),
			_percentile(prices, 1.0),
			int(engines.get(fuel_id, 0)),
		])
	return _section(
		"fuel_bands",
		"Fuel price bands",
		["Fuel", "Band min", "Band max", "Seen min", "Seen median", "Seen max", "Engines"],
		rows,
		["Seen prices are `FuelEconomy.compute_quotes` across market sectors over the trade window."]
	)


static func fuel_templates_section(ctx: Dictionary) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var rows: Array = []
	for probe_variant in ctx["templates"]:
		var probe: Dictionary = probe_variant
		var fuel_id := str(probe["fuel_id"])
		if fuel_id.is_empty():
			rows.append([probe["id"], NONE, 0.0, 0.0, NONE, 0, 0, 0, 0.0, 0.0])
			continue
		var fuel := catalog.get_fuel(fuel_id)
		var price_min := float(fuel.get("price_min", 0))
		var price_max := float(fuel.get("price_max", price_min))
		var price_mid := (price_min + price_max) * 0.5
		var capacity := float(probe["fuel_capacity"])
		var rate := float(probe["fuel_rate"])
		rows.append([
			probe["id"],
			fuel_id,
			capacity,
			rate,
			capacity / rate if rate > 0.0 else NONE,
			ceili(capacity * price_min),
			ceili(capacity * price_mid),
			ceili(capacity * price_max),
			rate * price_mid,
			capacity * price_mid / maxf(1.0, float(probe["used_price"])) * 100.0,
		])
	return _section(
		"fuel_templates",
		"Fuel running cost by template",
		[
			"Template", "Fuel", "Capacity", "Use per thrust-second", "Thrust-seconds", "Refill at min",
			"Refill at mid", "Refill at max", "d per thrust-second", "Refill % of used price",
		],
		rows,
		[
			"Use per thrust-second is `ShipOperations` fuel consumption with the engine on and no"
			+ " boost. Refills price a full tank the way `ShipAssembly.refuel_quote` does, at the band"
			+ " minimum, midpoint, and maximum.",
		]
	)


static func repair_rates_section(ctx: Dictionary) -> Dictionary:
	var model: Dictionary = ctx["repair"]
	var index: Dictionary = model["index"]
	var yards: Dictionary = model["yard_ids"]
	var calibration: Dictionary = model["calibration"]
	var rows: Array = [
		["Index commodity base price", float(model["base_price"]), NONE],
		[
			"Index at the cheapest, median, and dearest shipyard",
			"%.2f / %.2f / %.2f" % [float(index["cheapest"]), float(index["median"]), float(index["dearest"])],
			"%s / %s / %s" % [yards["cheapest"], yards["median"], yards["dearest"]],
		],
		[
			"Hull repair per point (cheapest / median / dearest)",
			"%.0f / %.0f / %.0f" % [
				float(model["hull_rate"]) * float(index["cheapest"]),
				float(model["hull_rate"]) * float(index["median"]),
				float(model["hull_rate"]) * float(index["dearest"]),
			],
			"Proposal constant times the local index",
		],
		["Median chassis value per hull point", float(model["hull_point_value"]), "Chassis cost over chassis hits"],
		["Repair price as a share of hull value", float(model["fraction"]), NONE],
		[
			"Power repair per unit at index 1.0",
			float(model["power_rate"]),
			"Same share of the median power-plant cost per unit of generation (%.1f)" % float(model["power_unit_value"]),
		],
		[
			"Compute repair per unit at index 1.0",
			float(model["compute_rate"]),
			"Same share of the median computer cost per compute unit (%.1f)" % float(model["compute_unit_value"]),
		],
		[
			"Breach target band per hull point (median hull)",
			"%.0f to %.0f" % [float(calibration["breach_low"]), float(calibration["breach_high"])],
			"%.0f to %.0f typical runs per breach" % [BREACH_RUNS_LOW, BREACH_RUNS_HIGH],
		],
		[
			"Bounty target ceiling per hull point (median armed hull)",
			float(calibration["bounty_ceiling"]),
			"Keep %.0f%% of pay after rearming and a %.0f%% hull repair" % [BOUNTY_KEEP_TARGET * 100.0, BOUNTY_DAMAGE_LEVEL * 100.0],
		],
	]
	return _section(
		"repair_rates",
		"Repair price proposal",
		["Item", "Value", "Basis"],
		rows,
		[
			(
				"Paid repairs do not exist yet; these rates are the proposal constants in this tool,"
				+ " scaled by the local %s quote over its base price. Target rows are prices at the"
				+ " median shipyard index."
			) % REPAIR_INDEX_COMMODITY,
		]
	)


static func repair_yards_section(ctx: Dictionary) -> Dictionary:
	var model: Dictionary = ctx["repair"]
	var median_hull := _median(((ctx["templates"] as Array).map(func(probe: Dictionary) -> float: return float(probe["hull"]))))
	var rows: Array = []
	for yard_variant in model["yards"]:
		var yard: Dictionary = yard_variant
		var per_point := float(model["hull_rate"]) * float(yard["index"])
		rows.append([
			yard["habitat_id"],
			yard["sector_id"],
			float(yard["quote"]),
			float(yard["index"]),
			per_point,
			per_point * median_hull,
		])
	return _section(
		"repair_yards",
		"Proposed hull repair price by shipyard",
		["Shipyard", "Sector", "Index quote", "Index", "Per hull point", "Full repair, median hull"],
		rows,
		[
			"Index quote is the median %s buy quote in the shipyard's sector over the trade window."
			% REPAIR_INDEX_COMMODITY
			+ " The median hull is %.0f points." % median_hull,
		]
	)


static func repair_templates_section(ctx: Dictionary) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var model: Dictionary = ctx["repair"]
	var rows: Array = []
	for probe_variant in ctx["templates"]:
		var probe: Dictionary = probe_variant
		var assembled: AssembledShip = probe["assembled"]
		var chassis := catalog.get_chassis_def(str(probe["chassis_id"]))
		var armour := assembled.get_armour_module_def()
		var hull := float(probe["hull"])
		var armour_value: Variant = NONE
		if armour != null and armour.hits > 0.0:
			armour_value = armour.cost / armour.hits
		var typical_run := float((probe["earnings"] as Dictionary)["typical_run"])
		var breach := repair_bill(model, hull, 0.0, 0.0, "median")
		rows.append([
			probe["id"],
			int(hull),
			int(probe["chassis_hits"]),
			int(hull - float(probe["chassis_hits"])),
			chassis.cost / maxf(1.0, chassis.hits),
			armour_value,
			repair_bill(model, hull * REPAIR_DAMAGE_LEVELS[0], 0.0, 0.0, "median"),
			repair_bill(model, hull * REPAIR_DAMAGE_LEVELS[1], 0.0, 0.0, "median"),
			repair_bill(model, hull, 0.0, 0.0, "cheapest"),
			breach,
			repair_bill(model, hull, 0.0, 0.0, "dearest"),
			typical_run,
			breach / typical_run if typical_run > 0.0 else NONE,
		])
	return _section(
		"repair_templates",
		"Hull repair bills by template",
		[
			"Template", "Hull", "Chassis hits", "Armour hits", "Chassis d per point",
			"Armour d per point", "25% at median", "60% at median", "100% at cheapest",
			"100% at median", "100% at dearest", "Typical run", "Breach in runs",
		],
		rows,
		["Bills cover hull points only. Power and compute damage are priced separately in the next table."]
	)


static func repair_hits_section(ctx: Dictionary) -> Dictionary:
	var model: Dictionary = ctx["repair"]
	var weapons: Dictionary = ctx["weapons"]
	var common := _common_weapon_ids(ctx)
	var columns: Array = ["Template"]
	for weapon_id in common:
		columns.append("Hit from %s" % weapon_id)
	columns.append_array(["Full repair", "Defence cost", "Saving per hit", "Payback hits"])
	var catalog: Catalog = ctx["catalog"]
	var rows: Array = []
	for probe_variant in ctx["templates"]:
		var probe: Dictionary = probe_variant
		var assembled: AssembledShip = probe["assembled"]
		var bare := _without_defences(catalog, probe["owned"])
		var row: Array = [probe["id"]]
		var first_cost := 0.0
		for index in common.size():
			var stats: Dictionary = weapons[common[index]]
			var cost := _hit_repair_cost(model, assembled, stats)
			if index == 0:
				first_cost = cost
			row.append(cost)
		var defence_cost := 0
		for category in ["armour", "shield"]:
			for entry_variant in assembled.modules_in_category(category):
				var def: ModuleDef = (entry_variant as Dictionary).get("data", null)
				if def != null:
					defence_cost += int(def.cost)
		var saving := 0.0
		if not common.is_empty():
			saving = _hit_repair_cost(model, bare, weapons[common[0]]) - first_cost
		row.append(repair_bill(model, float(probe["hull"]), 0.0, 0.0, "median"))
		row.append(defence_cost)
		row.append(saving)
		row.append(float(defence_cost) / saving if saving > 0.0 and defence_cost > 0 else NONE)
		rows.append(row)
	return _section(
		"repair_hits",
		"Repair cost of one hit",
		columns,
		rows,
		[
			"One trigger pull from each of the most-fitted weapons against the template with fresh"
			+ " shields, through `ShipCombat.resolve_hit`, priced at the median shipyard. Bills stop at"
			+ " what the ship can lose, so a hit near the full-repair column all but breaches the hull."
			+ " Saving per hit compares the first weapon against the same template without its armour"
			+ " and shields, and payback hits is that armour and shield cost over the saving. Point"
			+ " defence is left out.",
		]
	)


static func bounty_costs_section(ctx: Dictionary) -> Dictionary:
	var bounty: Dictionary = ctx["bounty"]
	var model: Dictionary = ctx["repair"]
	var pay := float(bounty["pay"])
	var hunters: Dictionary = bounty["hunters"]
	var rows: Array = []
	for probe_variant in ctx["templates"]:
		var probe: Dictionary = probe_variant
		if not hunters.has(probe["id"]):
			continue
		var hunter: Dictionary = hunters[probe["id"]]
		var hull := float(probe["hull"])
		var rearm := float(hunter["rearm"])
		var scenario := repair_bill(model, hull * BOUNTY_DAMAGE_LEVEL, 0.0, 0.0, "median")
		var completes := float(hunter["completion_share"])
		var done := pay > 0.0 and completes > 0.0
		var won := float(hunter["duels_won"]) > 0.0
		var measured: Variant = NONE
		var kept_measured: Variant = NONE
		if won:
			var bill := repair_bill(
				model,
				float(hunter["won_hull"]),
				float(hunter["won_power"]),
				float(hunter["won_compute"]),
				"median"
			)
			measured = bill
			if done:
				kept_measured = (pay - rearm - bill) / pay * 100.0
		rows.append([
			probe["id"],
			str((probe["best_weapon"] as Dictionary).get("id", NONE)),
			completes * 100.0,
			float(hunter["mean_shots"]) if completes > 0.0 else NONE,
			float(hunter["kill_seconds"]) if completes > 0.0 else NONE,
			rearm,
			float(hunter["duels_lost_share"]) * 100.0,
			float(hunter["won_hull"]) if won else NONE,
			measured,
			scenario,
			pay,
			kept_measured,
			(pay - rearm - scenario) / pay * 100.0 if done else NONE,
		])
	return _section(
		"bounty_costs",
		"Bounty pay after rearming and repairs",
		[
			"Hunter", "Weapon", "Completes %", "Shots", "Seconds", "Rearm", "Duels lost %",
			"Hull lost, won duels", "Repair, won duels", "Repair at 25%", "Median pay",
			"Kept, won duels %", "Kept at 25% %",
		],
		rows,
		[
			"Each armed template fights every sampled bounty target with its best weapon, through"
			+ " `ShipCombat.resolve_hit` and `tick_shields` between shots, including the threat hull"
			+ " scale. Disable objectives end when the target's power is gone. Shots include the"
			+ " target's point-defence intercept chance, and seconds run from the first shot to the"
			+ " kill. For the duel columns the target and each"
			+ " escort fire the target template's best weapon back for the same time with every round"
			+ " landing; a duel is lost when that breaches the hunter first. Both sides hit every"
			+ " shot, so read the duel columns as relative lethality, not odds. The 25% columns"
			+ " repair a quarter of the hull instead. Rearm prices spent rounds at the ammunition"
			+ " `cost` field.",
		]
	)


static func bounty_targets_section(ctx: Dictionary) -> Dictionary:
	var offers: Array = ((ctx["charters"] as Dictionary)["samples"] as Dictionary)["bounty"]
	var probes := {}
	for probe_variant in ctx["templates"]:
		probes[(probe_variant as Dictionary)["id"]] = probe_variant
	var by_target := {}
	for offer_variant in offers:
		var offer: Dictionary = offer_variant
		var target_id := str(offer.get("target_template_id", ""))
		if not by_target.has(target_id):
			by_target[target_id] = {"rewards": [], "hulls": [], "escorted": 0}
		var bucket: Dictionary = by_target[target_id]
		var profile: Dictionary = offer.get("threat_profile", {})
		(bucket["rewards"] as Array).append(int(offer.get("reward", 0)))
		var probe: Dictionary = probes.get(target_id, {})
		(bucket["hulls"] as Array).append(float(probe.get("hull", 0.0)) * float(profile.get("hull_scale", 1.0)))
		if int(profile.get("escort_count", 0)) > 0:
			bucket["escorted"] = int(bucket["escorted"]) + 1
	var ids: Array = by_target.keys()
	ids.sort()
	var rows: Array = []
	for target_variant in ids:
		var bucket: Dictionary = by_target[target_variant]
		var probe: Dictionary = probes.get(target_variant, {})
		var best: Dictionary = probe.get("best_weapon", {})
		var count := (bucket["rewards"] as Array).size()
		rows.append([
			str(target_variant),
			count,
			_median(bucket["rewards"]),
			_median(bucket["hulls"]),
			str(best.get("id", NONE)),
			float(best.get("hull_dps", 0.0)),
			int(probe.get("used_price", 0)),
			float(bucket["escorted"]) / float(maxi(1, count)) * 100.0,
		])
	return _section(
		"bounty_targets",
		"Bounty pay by target",
		["Target", "Offers", "Median pay", "Median scaled hull", "Best weapon", "Hull DPS", "Used price", "Escorted %"],
		rows,
		["Escorted offers add escort ships of the target template at the same hull scale. Pay is the offer reward, before any cancel penalty."]
	)


static func backgrounds_section(ctx: Dictionary) -> Dictionary:
	var rows: Array = []
	var notes: Array = [
		"Start value is liquid credits plus the used value of the kit. Liquidation strips every"
		+ " module and sells it, with spare parts, through `ShipAssembly`; the leaderboard column is"
		+ " `CareerStats.nett_profit()` afterwards. First-run figures use the start-day quotes, the"
		+ " kit ship's hold and flags, and liquid credits. Test-only kits are skipped.",
	]
	for background_variant in _probe_backgrounds(ctx):
		var probe: Dictionary = background_variant
		rows.append([
			probe["id"],
			probe["habitat_id"],
			int(probe["credits"]),
			int(probe["fine"]),
			int(probe["liquid"]),
			int(probe["kit_used_value"]),
			int(probe["liquid"]) + int(probe["kit_used_value"]),
			int(probe["liquidation"]),
			int(probe["leaderboard_after_liquidation"]),
			float(probe["hold"]),
			int(probe["seats"]),
			int(probe["reputation"]),
			str(probe["unlocks"]),
			_run_label(probe["first_run"]["one_hop"]),
			_run_label(probe["first_run"]["any"]),
			str(probe["first_ship"]),
		])
		if not str(probe.get("note", "")).is_empty():
			notes.append(str(probe["note"]))
	return _section(
		"backgrounds",
		"Backgrounds",
		[
			"Background", "Start", "Credits", "Fine", "Liquid", "Kit used value", "Start value",
			"Liquidation", "Leaderboard after liquidation", "Hold t", "Seats", "Reputation",
			"Unlocks", "First run, 1 hop", "First run, best", "First-run ship",
		],
		rows,
		notes
	)


static func code_checks_section(ctx: Dictionary) -> Dictionary:
	var rows: Array = [
		_check_dock_repair(ctx),
		_check_unspace_arrival(ctx),
		_check_undock_hull_carry_over(ctx),
	]
	return _section(
		"code_checks",
		"Repair preconditions (current behaviour)",
		["Check", "Observed", "Detail"],
		rows,
		["Headless runs of the real session flow. These describe today's code, not targets."]
	)


# --- Rendering --------------------------------------------------------------------------------


static func render_markdown(sections: Array, heading_level: int = 2) -> String:
	var lines := PackedStringArray()
	var prefix := "#".repeat(heading_level)
	for section_variant in sections:
		var section: Dictionary = section_variant
		lines.append("%s %s" % [prefix, str(section.get("title", ""))])
		lines.append("")
		for note in section.get("notes", []):
			lines.append(str(note))
			lines.append("")
		var columns: Array = section.get("columns", [])
		if columns.is_empty():
			continue
		var rows: Array = section.get("rows", [])
		var header := PackedStringArray()
		var rule := PackedStringArray()
		for index in columns.size():
			header.append(str(columns[index]))
			rule.append("---:" if _column_is_numeric(rows, index) else "---")
		lines.append("| %s |" % " | ".join(header))
		lines.append("| %s |" % " | ".join(rule))
		for row_variant in rows:
			var row: Array = row_variant
			var cells := PackedStringArray()
			for cell in row:
				cells.append(format_cell(cell))
			lines.append("| %s |" % " | ".join(cells))
		lines.append("")
	return "\n".join(lines)


static func format_cell(value: Variant) -> String:
	match typeof(value):
		TYPE_INT:
			return _group_digits(int(value))
		TYPE_FLOAT:
			var number := float(value)
			if not is_finite(number):
				return NONE
			var magnitude := absf(number)
			if magnitude < 0.005:
				return "0.00"
			if magnitude >= 1000.0:
				return _group_digits(int(round(number)))
			if magnitude >= 100.0:
				return "%.0f" % number
			if magnitude >= 10.0:
				return "%.1f" % number
			return "%.2f" % number
		TYPE_BOOL:
			return "yes" if bool(value) else "no"
	return str(value).replace("|", "/")


# --- Dominance and price curves ---------------------------------------------------------------


## Entries are {"id", "group", "cost", "high": {metric: value}, "low": {metric: value},
## "capabilities": Array}. Returns one {"id", "group", "by"} per dominated entry, naming the
## cheapest entry that dominates it.
static func dominated_pairs(entries: Array) -> Array:
	var out: Array = []
	for candidate_variant in entries:
		var candidate: Dictionary = candidate_variant
		var cheapest := {}
		for other_variant in entries:
			var other: Dictionary = other_variant
			if str(other["id"]) == str(candidate["id"]) or str(other["group"]) != str(candidate["group"]):
				continue
			if not dominates(other, candidate):
				continue
			if cheapest.is_empty() or float(other["cost"]) < float(cheapest["cost"]):
				cheapest = other
		if not cheapest.is_empty():
			out.append({"id": candidate["id"], "group": candidate["group"], "by": cheapest["id"]})
	return out


static func dominates(a: Dictionary, b: Dictionary) -> bool:
	var strictly := false
	var a_high: Dictionary = a.get("high", {})
	var b_high: Dictionary = b.get("high", {})
	for key in _merged_keys(a_high, b_high):
		var difference := float(a_high.get(key, 0.0)) - float(b_high.get(key, 0.0))
		if difference < -EPSILON:
			return false
		if difference > EPSILON:
			strictly = true
	var a_low: Dictionary = a.get("low", {})
	var b_low: Dictionary = b.get("low", {})
	for key in _merged_keys(a_low, b_low):
		var difference := float(b_low.get(key, 0.0)) - float(a_low.get(key, 0.0))
		if difference < -EPSILON:
			return false
		if difference > EPSILON:
			strictly = true
	var a_caps: Array = a.get("capabilities", [])
	var b_caps: Array = b.get("capabilities", [])
	for cap in b_caps:
		if not a_caps.has(cap):
			return false
	if a_caps.size() > b_caps.size():
		strictly = true
	return strictly


static func module_dominance_entries(ctx: Dictionary, include_signature: bool, category: String = "") -> Array:
	var entries: Array = []
	for def in _sorted_module_defs(ctx["catalog"], category):
		var metrics := _module_metrics(ctx, def)
		var low: Dictionary = (metrics["low"] as Dictionary).duplicate()
		if include_signature:
			var signature := def.signature.to_dict()
			for channel in signature.keys():
				low["signature_%s" % channel] = float(signature[channel])
		entries.append({
			"id": def.id,
			"group": "%s|%s" % [def.category, "/".join(PackedStringArray(_sorted_mounts(def)))],
			"cost": def.cost,
			"high": metrics["high"],
			"low": low,
			"capabilities": def.capabilities,
		})
	return entries


## Least-squares fit of log(y) = log(scale) + exponent * log(x). Points are {"x", "y"}, both > 0.
static func fit_power_law(points: Array) -> Dictionary:
	var count := float(points.size())
	if count < 1.0:
		return {"exponent": 0.0, "scale": 0.0}
	var sum_x := 0.0
	var sum_y := 0.0
	var sum_xx := 0.0
	var sum_xy := 0.0
	for point_variant in points:
		var point: Dictionary = point_variant
		var lx := log(float(point["x"]))
		var ly := log(float(point["y"]))
		sum_x += lx
		sum_y += ly
		sum_xx += lx * lx
		sum_xy += lx * ly
	var denominator := count * sum_xx - sum_x * sum_x
	if absf(denominator) < EPSILON:
		return {"exponent": 0.0, "scale": exp(sum_y / count)}
	var exponent := (count * sum_xy - sum_x * sum_y) / denominator
	return {"exponent": exponent, "scale": exp((sum_y - exponent * sum_x) / count)}


static func _price_curves(ctx: Dictionary) -> Array:
	if ctx.has("price_curves"):
		var cached: Array = ctx["price_curves"]
		return cached
	var groups := {}
	var stat_names := {}
	for def in _sorted_module_defs(ctx["catalog"], ""):
		var main := _main_stat(ctx, def)
		if main.is_empty() or float(main["value"]) <= 0.0 or def.cost <= 0.0:
			continue
		var group_id := _curve_group(def)
		var points: Array = groups.get(group_id, [])
		points.append({"id": def.id, "x": float(main["value"]), "y": def.cost})
		groups[group_id] = points
		stat_names[group_id] = main["name"]
	var curves: Array = []
	var group_ids: Array = groups.keys()
	group_ids.sort()
	for group_id in group_ids:
		var points: Array = groups[group_id]
		if points.size() < 3:
			continue
		var fit := fit_power_law(points)
		var scored: Array = []
		for point_variant in points:
			var point: Dictionary = point_variant
			var fitted := float(fit["scale"]) * pow(float(point["x"]), float(fit["exponent"]))
			scored.append({
				"id": point["id"],
				"stat": point["x"],
				"cost": point["y"],
				"fitted": fitted,
				"ratio": float(point["y"]) / fitted if fitted > 0.0 else 1.0,
			})
		scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["ratio"]) > float(b["ratio"]))
		curves.append({
			"group": group_id,
			"stat": stat_names[group_id],
			"exponent": fit["exponent"],
			"points": scored,
		})
	ctx["price_curves"] = curves
	return curves


static func _module_metrics(ctx: Dictionary, def: ModuleDef) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var high := {}
	var low := {
		"cost": def.cost,
		"mass": def.mass,
		"volume": def.volume,
		"power_demand": def.power_demand,
		"compute_demand": def.compute_demand,
	}
	match def.category:
		"propulsion":
			high["thrust"] = def.thrust
			high["max_speed"] = def.max_speed
			high["boost"] = def.boost_multiplier
			high["thrust_seconds"] = def.fuel_capacity / def.fuel_consumption if def.fuel_consumption > 0.0 else 1000000.0
			low["fuel_cost_per_second"] = def.fuel_consumption * _fuel_mid_price(catalog, ShipFuel.fuel_id_for_engine(def))
		"power":
			high["power_generation"] = def.power_generation
		"computer":
			high["compute_capacity"] = def.compute_capacity
		"life_support":
			high["life_support_capacity"] = def.life_support_capacity
		"cargo":
			high["cargo_capacity"] = def.cargo_capacity
		"fuel":
			high["fuel_capacity"] = def.fuel_capacity
		"armour", "shield", "cyber_defence":
			high["hits"] = def.hits
			high["shield_capacity"] = def.shield_capacity
			high["regen"] = def.regen
			var protection := def.protection.to_dict()
			for packet_type in protection.keys():
				high["protection_%s" % packet_type] = float(protection[packet_type])
		"sensor":
			high["sensor_range"] = def.sensor_range
			high["has_active"] = 1.0 if def.has_active else 0.0
			var active := def.sensor_sensitivity.to_dict()
			var passive := def.sensor_sensitivity_passive.to_dict()
			for channel in active.keys():
				high["active_%s" % channel] = float(active[channel])
			for channel in passive.keys():
				high["passive_%s" % channel] = float(passive[channel])
		"point_defence":
			high["intercept_chance"] = def.intercept_chance
		"navigation":
			high["nav_rating"] = def.nav_rating
			high["translation_capacity"] = def.translation_capacity
		"ammunition":
			for ammo_id in def.ammunition_capacity.keys():
				high["capacity_%s" % ammo_id] = float(def.ammunition_capacity[ammo_id])
		"weapon":
			var stats: Dictionary = (ctx["weapons"] as Dictionary).get(def.id, {})
			high["hull_dps"] = float(stats.get("hull_dps", 0.0))
			high["power_dps"] = float(stats.get("power_dps", 0.0))
			high["compute_dps"] = float(stats.get("compute_dps", 0.0))
			high["range"] = def.range
			low["ammo_cost_per_second"] = float(stats.get("ammo_cost_per_second", 0.0))
			low["ammo_mass_per_minute"] = float(stats.get("ammo_mass_per_minute", 0.0))
	return {"high": high, "low": low}


static func _main_stat(ctx: Dictionary, def: ModuleDef) -> Dictionary:
	match def.category:
		"propulsion":
			return {"name": "thrust", "value": def.thrust}
		"power":
			return {"name": "power_generation", "value": def.power_generation}
		"computer":
			return {"name": "compute_capacity", "value": def.compute_capacity}
		"life_support":
			return {"name": "life_support_capacity", "value": def.life_support_capacity}
		"cargo":
			return {"name": "cargo_capacity", "value": def.cargo_capacity}
		"armour":
			return {"name": "hits", "value": def.hits}
		"shield":
			return {"name": "shield_capacity", "value": def.shield_capacity}
		"sensor":
			return {"name": "sensor_range", "value": def.sensor_range}
		"point_defence":
			return {"name": "intercept_chance", "value": def.intercept_chance}
		"fuel":
			return {"name": "fuel_capacity", "value": def.fuel_capacity}
		"navigation":
			return {"name": "nav_rating", "value": def.nav_rating}
		"cyber_defence":
			return {"name": "cyber protection", "value": def.protection.cyber}
		"weapon":
			var stats: Dictionary = (ctx["weapons"] as Dictionary).get(def.id, {})
			return {"name": "hull DPS", "value": float(stats.get("hull_dps", 0.0))}
	return {}


static func _curve_group(def: ModuleDef) -> String:
	match def.category:
		"weapon":
			return "weapon|%s" % "/".join(PackedStringArray(_sorted_mounts(def)))
		"propulsion":
			return "propulsion|%s" % def.engine_type
		"power":
			return "power|%s" % def.plant_type
		"computer":
			return "computer|%s" % def.core_type
		"shield":
			return "shield|%s" % def.shield_type
	return def.category


static func _count_by_category(ctx: Dictionary, pairs: Array) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var counts := {}
	for pair_variant in pairs:
		var def := catalog.get_module_def(str((pair_variant as Dictionary)["id"]))
		counts[def.category] = int(counts.get(def.category, 0)) + 1
	return counts


# --- Weapons ----------------------------------------------------------------------------------


static func _build_weapon_stats(ctx: Dictionary) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var bare := AssembledShip.new()
	var reference := _reference_armour(catalog)
	ctx["reference_armour_id"] = str(reference.get("armour_id", NONE))
	var armoured: AssembledShip = reference.get("assembled", bare)
	var out := {}
	for weapon in _sorted_module_defs(catalog, "weapon"):
		out[weapon.id] = weapon_stats(catalog, weapon, bare, armoured)
	return out


## One trigger pull through the real weapon tick, resolved against `bare` and `armoured`.
static func weapon_stats(
	catalog: Catalog,
	weapon: ModuleDef,
	bare: AssembledShip,
	armoured: AssembledShip
) -> Dictionary:
	var mount := str(ShipAssembler.module_mounts(weapon)[0])
	var slot := "%s_1" % mount
	var host := OwnedShip.new()
	host.id = "weapon_probe_%s" % weapon.id
	host.chassis_id = _probe_chassis_id(catalog)
	host.modules = [{"slot": slot, "module_id": weapon.id}]
	var ammo_id := weapon.ammunition_type
	if not ammo_id.is_empty():
		host.ammunition = {ammo_id: 1000.0}
	var assembled := ShipAssembler.assemble_owned(catalog, host)
	var trigger := ShipWeapons.new()
	trigger.select_slot(slot)
	var ammo_before := host.get_ammo_count(ammo_id)
	var fired := trigger.tick(catalog, assembled, host, 0.0, true, true)
	var rounds := ammo_before - host.get_ammo_count(ammo_id)
	var volley: Array = []
	for order_variant in fired.get("orders", []):
		volley.append((order_variant as Dictionary).get("packets", {}))
	var raw := 0.0
	for packets in volley:
		raw += ShipCombat.sum_packets(packets)
	var cycle := ShipWeapons.fire_cycle_seconds(weapon)
	var rate := 1.0 / cycle if cycle > 0.0 else 0.0
	var bare_hit := _volley_damage(bare, ShipCombatState.from_assembled(bare), volley)
	var armoured_hit := _volley_damage(armoured, ShipCombatState.from_assembled(armoured), volley)
	var ammo_cost := 0.0
	var ammo_mass := 0.0
	if not ammo_id.is_empty():
		var ammo := catalog.get_ammunition_def(ammo_id)
		if ammo != null:
			ammo_cost = ammo.cost
			ammo_mass = ammo.mass
	var delivery := ShipCombat.delivery_type_from_module(weapon)
	return {
		"id": weapon.id,
		"mount": mount,
		"weapon_type": weapon.weapon_type,
		"delivery": delivery,
		"cost": int(weapon.cost),
		"cycle": cycle,
		"volley": volley,
		"raw_dps": raw * rate,
		"hull_dps": float(bare_hit["hull"]) * rate,
		"power_dps": float(bare_hit["power"]) * rate,
		"compute_dps": float(bare_hit["compute"]) * rate,
		"armoured_hull_dps": float(armoured_hit["hull"]) * rate,
		"range": weapon.range,
		"rounds_per_shot": rounds,
		"ammo_cost_per_shot": float(rounds) * ammo_cost,
		"ammo_per_second": float(rounds) * rate,
		"ammo_cost_per_second": float(rounds) * rate * ammo_cost,
		"ammo_mass_per_minute": float(rounds) * rate * 60.0 * ammo_mass,
		"pd_interceptable": delivery in ShipCombat.PD_DELIVERIES,
	}


static func _volley_damage(target: AssembledShip, state: ShipCombatState, volley: Array) -> Dictionary:
	var totals := {"hull": 0.0, "power": 0.0, "compute": 0.0}
	for packets in volley:
		var result := ShipCombat.resolve_hit(target, state, "beam", packets)
		totals["hull"] = float(totals["hull"]) + float(result.get("hull_damage", 0.0))
		totals["power"] = float(totals["power"]) + float(result.get("power_lost", 0.0))
		totals["compute"] = float(totals["compute"]) + float(result.get("compute_lost", 0.0))
	return totals


## Same product of miss chances that `ShipCombat._roll_point_defence_intercept` rolls against.
static func point_defence_intercept_chance(target: AssembledShip) -> float:
	var miss := 1.0
	for entry_variant in target.modules_in_category("point_defence"):
		var def: ModuleDef = (entry_variant as Dictionary).get("data", null)
		if def != null:
			miss *= 1.0 - clampf(def.intercept_chance, 0.0, 1.0)
	return 1.0 - miss


## Trigger pulls until the target breaks, or loses all power when `allow_disable`. -1 if never.
static func shots_to_finish(
	stats: Dictionary,
	target: AssembledShip,
	hull_scale: float,
	allow_disable: bool
) -> float:
	if float(stats.get("hull_dps", 0.0)) <= 0.0 and (not allow_disable or float(stats.get("power_dps", 0.0)) <= 0.0):
		return -1.0
	var state := ShipCombatState.from_assembled(target)
	state.hull_max *= hull_scale
	state.hull_current = state.hull_max
	var volley: Array = stats["volley"]
	var cycle := float(stats["cycle"])
	var shots := -1
	for shot in range(1, SHOT_LIMIT + 1):
		_volley_damage(target, state, volley)
		if state.is_hull_disabled():
			shots = shot
			break
		if allow_disable and ShipCombat.get_effective_power_generation(target, state) <= 0.0:
			shots = shot
			break
		ShipCombat.tick_shields(state, target, cycle)
	if shots < 0:
		return -1.0
	if bool(stats.get("pd_interceptable", false)):
		var intercept := point_defence_intercept_chance(target)
		if intercept >= 0.999:
			return -1.0
		return float(shots) / (1.0 - intercept)
	return float(shots)


static func _sorted_weapon_stats(ctx: Dictionary) -> Array:
	var order := {"light_weapon": 0, "medium_weapon": 1, "heavy_weapon": 2}
	var list: Array = (ctx["weapons"] as Dictionary).values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var mount_a := int(order.get(str(a["mount"]), 3))
		var mount_b := int(order.get(str(b["mount"]), 3))
		if mount_a != mount_b:
			return mount_a < mount_b
		return float(a["hull_dps"]) > float(b["hull_dps"])
	)
	return list


static func _common_weapon_ids(ctx: Dictionary) -> Array:
	var counts := {}
	for probe_variant in ctx["templates"]:
		var assembled: AssembledShip = (probe_variant as Dictionary)["assembled"]
		for entry_variant in assembled.modules_in_category("weapon"):
			var weapon_id := str((entry_variant as Dictionary).get("module_id", ""))
			counts[weapon_id] = int(counts.get(weapon_id, 0)) + 1
	var ids: Array = counts.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		if int(counts[a]) != int(counts[b]):
			return int(counts[a]) > int(counts[b])
		return a < b
	)
	return ids.slice(0, COMMON_WEAPON_COUNT)


static func _reference_armour(catalog: Catalog) -> Dictionary:
	var counts := {}
	for template_id in _sorted_template_ids(catalog):
		for module_id in catalog.get_ship_def(template_id).modules:
			var def := catalog.get_module_def(str(module_id))
			if def != null and def.category == "armour":
				counts[def.id] = int(counts.get(def.id, 0)) + 1
	var armour_id := _most_common(counts)
	if armour_id.is_empty():
		return {}
	var host := OwnedShip.new()
	host.id = "armour_probe"
	host.chassis_id = _probe_chassis_id(catalog)
	host.modules = [{"slot": "other_1", "module_id": armour_id}]
	return {"armour_id": armour_id, "assembled": ShipAssembler.assemble_owned(catalog, host)}


# --- Templates --------------------------------------------------------------------------------


static func _build_template_probes(ctx: Dictionary) -> Array:
	var probes: Array = []
	for template_id in _sorted_template_ids(ctx["catalog"]):
		probes.append(_probe_template(ctx, template_id))
	return probes


static func _probe_template(ctx: Dictionary, template_id: String) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var template := catalog.get_ship_def(template_id)
	var owned := OwnedShip.from_template(
		catalog,
		{"id": "probe_%s" % template_id, "template_id": template_id, "chassis_id": template.chassis}
	)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_cost := 0
	for module_id in template.modules:
		module_cost += ShipAssembly.get_part_cost(catalog, str(module_id))
	var dry_mass := float(assembled.envelope.get("dry_mass", 0.0))
	var loaded_mass := ShipAssembler.calculate_loaded_mass(catalog, owned, assembled)
	var launch := ShipOperations.launch_snapshot(catalog, assembled, owned, 1)
	var weapons: Dictionary = ctx["weapons"]
	var best := {}
	var best_slot := ""
	for entry_variant in assembled.modules_in_category("weapon"):
		var entry: Dictionary = entry_variant
		var stats: Dictionary = weapons.get(str(entry.get("module_id", "")), {})
		if stats.is_empty():
			continue
		if best.is_empty() or float(stats["hull_dps"]) > float(best["hull_dps"]):
			best = stats
			best_slot = str(entry.get("slot", ""))
	var firing := launch
	if not best_slot.is_empty():
		firing = ShipOperations.tick(
			catalog,
			assembled,
			owned,
			0.0,
			{"thrust": true, "in_flight": true, "fire": true, "active_weapon_slot": best_slot},
			1
		)
	var starved: Array[String] = []
	for category_variant in firing.power_requested_by_category.keys():
		var category := str(category_variant)
		var requested := float(firing.power_requested_by_category[category_variant])
		if float(firing.power_allocated_by_category.get(category_variant, 0.0)) + EPSILON < requested:
			starved.append(category)
	starved.sort()
	var fuel_mass := ShipFuel.propulsion_fuel_mass(catalog, owned)
	var fired_ammo := {}
	for entry_variant in assembled.modules_in_category("weapon"):
		var weapon_def: ModuleDef = (entry_variant as Dictionary).get("data", null)
		if weapon_def != null and not weapon_def.ammunition_type.is_empty():
			fired_ammo[weapon_def.ammunition_type] = true
	var unfired := OwnedShip.from_dict(owned.to_dict())
	for ammo_variant in unfired.ammunition.keys():
		if fired_ammo.has(str(ammo_variant)):
			unfired.ammunition.erase(ammo_variant)
	var unfired_mass := ShipAssembler.calculate_loaded_mass(catalog, unfired, assembled) - dry_mass - fuel_mass
	var life_support := int(assembled.capacities.get("life_support_capacity", 0.0))
	return {
		"id": template_id,
		"chassis_id": template.chassis,
		"owned": owned,
		"assembled": assembled,
		"build_cost": ShipAssembly.chassis_price(catalog, template.chassis) + module_cost,
		"used_price": ShipAssembly.used_ship_price(catalog, template_id),
		"parts_sale": parts_sale_value(catalog, template_id, ctx["part_sale_cache"]),
		"dry_mass": dry_mass,
		"fuel_mass": fuel_mass,
		"ammo_mass": loaded_mass - dry_mass - fuel_mass,
		"unfired_ammo_mass": unfired_mass,
		"loaded_mass": loaded_mass,
		"mass_limit": float(assembled.envelope.get("mass_limit", 0.0)),
		"accel_loaded": assembled.stats.forward_thrust,
		"accel_dry": ShipAssembler.derive_stats(assembled, dry_mass).forward_thrust,
		"max_speed": assembled.stats.max_speed,
		"hull": float(assembled.capacities.get("hull_hits", 0)),
		"chassis_hits": float(assembled.chassis_hits()),
		"hold": float(assembled.capacities.get("cargo_capacity", 0.0)),
		"seats": maxi(0, life_support - PassengerCharters.PILOT_LIFE_SUPPORT_SEATS),
		"power_margin": launch.power_available - launch.power_requested,
		"combat_power_margin": firing.power_available - firing.power_requested,
		"starved": starved,
		"compute_margin": launch.compute_capacity - launch.compute_demand,
		"best_weapon": best,
		"armed": not assembled.modules_in_category("weapon").is_empty(),
		"fuel_id": ShipFuel.active_fuel_id(catalog, owned),
		"fuel_capacity": ShipFuel.active_capacity(catalog, owned),
		"fuel_rate": launch.fuel_consumption,
	}


static func part_sale_price(catalog: Catalog, part_id: String, cache: Dictionary = {}) -> int:
	if cache.has(part_id):
		return int(cache[part_id])
	var probe := GameSession.new()
	probe.add_spare_part(part_id, 1)
	var before := probe.wallet.credits
	var price := 0
	if ShipAssembly.sell_part(probe, catalog, part_id):
		price = probe.wallet.credits - before
	cache[part_id] = price
	return price


## What stripping a template and selling every module through `ShipAssembly.sell_part` pays.
static func parts_sale_value(catalog: Catalog, template_id: String, cache: Dictionary = {}) -> int:
	var template := catalog.get_ship_def(template_id)
	if template == null:
		return 0
	var total := 0
	for module_id in template.modules:
		total += part_sale_price(catalog, str(module_id), cache)
	return total


static func _build_refits(ctx: Dictionary) -> Array:
	var catalog: Catalog = ctx["catalog"]
	var refits: Array = []
	for probe_variant in ctx["templates"]:
		var probe: Dictionary = probe_variant
		var refit := refit_for_hold(catalog, str(probe["id"]), ctx["part_sale_cache"])
		var trade := _template_trade(ctx, refit)
		refit["hold_built"] = probe["hold"]
		refit["trade_income"] = trade["income"]
		refits.append(refit)
	return refits


## Greedy cargo refit of a template: strip combat gear and holds, then fill free slots with the
## largest cargo modules `ShipAssembler.validate_install` accepts. The hold is a floor on what the
## hull can carry.
static func refit_for_hold(catalog: Catalog, template_id: String, sale_cache: Dictionary = {}) -> Dictionary:
	var template := catalog.get_ship_def(template_id)
	var owned := OwnedShip.from_template(
		catalog,
		{"id": "refit_%s" % template_id, "template_id": template_id, "chassis_id": template.chassis}
	)
	var outlay := 0
	var built := ShipAssembler.assemble_owned(catalog, owned)
	for category in REFIT_STRIP_CATEGORIES:
		for entry_variant in built.modules_in_category(category):
			var removed := owned.remove_module(str((entry_variant as Dictionary).get("slot", "")))
			if not removed.is_empty():
				outlay -= part_sale_price(catalog, removed, sale_cache)
	owned.ammunition.clear()

	var bays := _sorted_module_defs(catalog, "cargo")
	bays.sort_custom(func(a: ModuleDef, b: ModuleDef) -> bool:
		if not is_equal_approx(a.cargo_capacity, b.cargo_capacity):
			return a.cargo_capacity > b.cargo_capacity
		if not is_equal_approx(a.volume, b.volume):
			return a.volume < b.volume
		if not is_equal_approx(a.mass, b.mass):
			return a.mass < b.mass
		return a.cost < b.cost
	)
	var candidates: Array[ModuleDef] = []
	var seen := {}
	for def in bays:
		var shape := "%.3f|%.3f|%.3f" % [def.cargo_capacity, def.volume, def.mass]
		if def.cargo_capacity <= 0.0 or seen.has(shape):
			continue
		seen[shape] = true
		candidates.append(def)

	for slot_variant in ShipAssembler.list_slots_for_chassis(catalog.get_chassis_def(template.chassis)):
		var slot := str(slot_variant)
		if not owned.get_module_id(slot).is_empty():
			continue
		for def in candidates:
			if bool(ShipAssembler.validate_install(catalog, owned, slot, def.id).get("ok", false)):
				owned.set_module(slot, def.id)
				outlay += ShipAssembly.get_part_cost(catalog, def.id)
				break

	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var hold := float(assembled.capacities.get("cargo_capacity", 0.0))
	var full_mass := ShipAssembler.calculate_loaded_mass(catalog, owned, assembled) + hold
	return {
		"id": template_id,
		"owned": owned,
		"assembled": assembled,
		"hold": hold,
		"dry_mass": float(assembled.envelope.get("dry_mass", 0.0)),
		"full_mass": full_mass,
		"mass_limit": float(assembled.envelope.get("mass_limit", 0.0)),
		"accel_full": ShipAssembler.derive_stats(assembled, full_mass).forward_thrust,
		"outlay": outlay,
		"blockers": ShipAssembly.undock_blockers(catalog, owned, 1).size(),
	}


static func _attach_template_earnings(ctx: Dictionary) -> void:
	var bounty: Dictionary = ctx["bounty"]
	var hunters: Dictionary = bounty["hunters"]
	for probe_variant in ctx["templates"]:
		var probe: Dictionary = probe_variant
		var trade := _template_trade(ctx, probe)
		var charters := _template_charters(ctx, probe)
		var typical_run := float(charters["one_hop"])
		if hunters.has(probe["id"]) and float((hunters[probe["id"]] as Dictionary)["completion_share"]) >= 0.5:
			typical_run = maxf(typical_run, float(bounty["pay"]))
		probe["earnings"] = {
			"trade_income": trade["income"],
			"trade_capital": trade["capital"],
			"trade_pick": trade["commodity"],
			"charter_one_hop": charters["one_hop"],
			"charter_per_hop": charters["per_hop"],
			"typical_run": typical_run,
		}


static func _template_trade(ctx: Dictionary, probe: Dictionary) -> Dictionary:
	var trade: Dictionary = ctx["trade"]
	var assembled: AssembledShip = probe["assembled"]
	var hold := float(probe["hold"])
	if hold <= 0.0:
		return {"income": 0.0, "capital": 0.0, "commodity": NONE}
	var incomes: Array = []
	var capitals: Array = []
	var picks := {}
	for best_variant in trade["daily_best"]:
		var best_today: Dictionary = best_variant
		var top_income := 0
		var top_capital := 0
		var top_id := ""
		for commodity_variant in trade["commodities"]:
			var commodity: CommodityDef = commodity_variant
			if not CargoRequirements.assembled_meets_commodity(assembled, commodity):
				continue
			var one_hop: Dictionary = (best_today.get(commodity.id, {}) as Dictionary).get("one_hop", {})
			if one_hop.is_empty():
				continue
			var units := int(floor(hold / commodity.mass + EPSILON))
			var income := units * int(one_hop["margin"])
			if income > top_income:
				top_income = income
				top_capital = units * int(one_hop["buy"])
				top_id = commodity.id
		incomes.append(top_income)
		capitals.append(top_capital)
		if not top_id.is_empty():
			picks[top_id] = int(picks.get(top_id, 0)) + 1
	var pick := _most_common(picks)
	return {"income": _median(incomes), "capital": _median(capitals), "commodity": pick if not pick.is_empty() else NONE}


static func _template_charters(ctx: Dictionary, probe: Dictionary) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var session := GameSession.new()
	session.world.docked = true
	session.world.habitat_id = PROBE_DOCK
	var ship := OwnedShip.from_dict((probe["owned"] as OwnedShip).to_dict())
	ship.location = PROBE_DOCK
	session.fleet.owned_ships.append(ship)
	var verdicts := {}
	var one_hop: Array = []
	var per_hop: Array = []
	for board_variant in (ctx["charters"] as Dictionary)["boards"]:
		var board: Dictionary = board_variant
		var best_one := 0
		var best_rate := 0.0
		for kind in ["passenger", "freight"]:
			for offer_variant in board[kind]:
				var offer: Dictionary = offer_variant
				if not _offer_feasible(session, catalog, ship.id, kind, offer, verdicts):
					continue
				var reward := int(offer.get("reward", 0))
				var hops := maxi(1, int(offer.get("hops", 1)))
				if hops == 1:
					best_one = maxi(best_one, reward)
				best_rate = maxf(best_rate, float(reward) / float(hops))
		one_hop.append(best_one)
		per_hop.append(best_rate)
	return {"one_hop": _median(one_hop), "per_hop": _median(per_hop)}


static func _offer_feasible(
	session: GameSession,
	catalog: Catalog,
	ship_id: String,
	kind: String,
	offer: Dictionary,
	verdicts: Dictionary
) -> bool:
	var key := _feasibility_key(kind, offer)
	if verdicts.has(key):
		return bool(verdicts[key])
	var verdict: Dictionary
	if kind == "passenger":
		verdict = PassengerCharters.evaluate_offer_for_ship(session, catalog, offer, ship_id, 0)
	else:
		verdict = FreightCharters.evaluate_offer_for_ship(session, catalog, offer, ship_id, {})
	var ok := bool(verdict.get("ok", false))
	verdicts[key] = ok
	return ok


## Everything `evaluate_offer_for_ship` reads from an offer, so equal keys get equal verdicts.
static func _feasibility_key(kind: String, offer: Dictionary) -> String:
	if kind == "passenger":
		return "p|%d|%s|%s|%s|%d" % [
			int(offer.get("quantity", 0)),
			str(offer.get("life_support", "")),
			str(int(offer.get("hops", 1)) > 1),
			str(bool(offer.get("requires_player_affiliation", false))),
			int(offer.get("min_reputation", 0)),
		]
	var caps := PackedStringArray()
	for cap in offer.get("requires_capabilities", []):
		caps.append(str(cap))
	caps.sort()
	return "f|%s|%.4f|%d|%.4f|%.4f|%d" % [
		",".join(caps),
		float(offer.get("tonnes", 0.0)),
		int(offer.get("life_support_seats", 0)),
		float(offer.get("compute_demand", 0.0)),
		float(offer.get("power_demand", 0.0)),
		int(offer.get("min_reputation", 0)),
	]


# --- Trade and fuel ---------------------------------------------------------------------------


static func _build_trade(ctx: Dictionary) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var opts: Dictionary = ctx["options"]
	var max_hops := int(opts.get("max_hops", 3))
	var adjacency := PassengerCharters.sector_adjacency(catalog)
	var sector_habitats := PassengerCharters.sector_habitat_index(catalog)
	var market_sectors := {}
	for habitat_id in _habitat_ids_with_building_type(catalog, "market"):
		market_sectors[catalog.get_habitat_sector_id(habitat_id)] = habitat_id
	var routes: Array = []
	var origins: Array = market_sectors.keys()
	origins.sort()
	for origin_variant in origins:
		var origin := str(origin_variant)
		var nearest := {}
		for dest_variant in PassengerCharters.multi_hop_destinations(
			catalog, str(market_sectors[origin]), max_hops, adjacency, sector_habitats
		):
			var dest: Dictionary = dest_variant
			var sector_id := str(dest.get("sector_id", ""))
			if sector_id == origin or not market_sectors.has(sector_id):
				continue
			var known: Dictionary = nearest.get(sector_id, {})
			if known.is_empty() or int(dest.get("hops", 0)) < int(known.get("hops", 0)):
				nearest[sector_id] = dest
		var destinations: Array = nearest.keys()
		destinations.sort()
		for sector_id in destinations:
			routes.append({"from": origin, "to": str(sector_id), "hops": int((nearest[sector_id] as Dictionary).get("hops", 1))})

	var commodities: Array = []
	var commodity_ids: Array = catalog.commodities_by_id.keys()
	commodity_ids.sort()
	for commodity_id in commodity_ids:
		var commodity := catalog.get_commodity_def(str(commodity_id))
		if commodity != null and commodity.mass > 0.0:
			commodities.append(commodity)

	var days: Array = []
	var daily_best: Array = []
	var route_margins := {}
	var index_prices := {}
	var start_day := int(ctx["start_day"])
	for offset in range(maxi(1, int(opts.get("trade_days", 30)))):
		var day := start_day + offset
		days.append(day)
		var quotes := CommodityEconomy.compute_quotes(catalog, day)
		for sector_id in market_sectors.keys():
			var prices: Array = index_prices.get(sector_id, [])
			prices.append(_quote_price(quotes, str(sector_id), REPAIR_INDEX_COMMODITY))
			index_prices[sector_id] = prices
		var best_today := {}
		for commodity_variant in commodities:
			var commodity: CommodityDef = commodity_variant
			var best_one := {}
			var best_rate := {}
			for route_variant in routes:
				var route: Dictionary = route_variant
				var buy := _quote_price(quotes, str(route["from"]), commodity.id)
				if buy <= 0:
					continue
				var margin := CommodityEconomy.sell_price(_quote_price(quotes, str(route["to"]), commodity.id)) - buy
				var hops := int(route["hops"])
				var candidate := {
					"margin": margin,
					"buy": buy,
					"from": route["from"],
					"to": route["to"],
					"hops": hops,
					"rate": float(margin) / float(hops),
				}
				if hops == 1 and (best_one.is_empty() or margin > int(best_one["margin"])):
					best_one = candidate
				if best_rate.is_empty() or float(candidate["rate"]) > float(best_rate["rate"]):
					best_rate = candidate
				if hops <= 2:
					var key := "%s|%s|%s" % [commodity.id, route["from"], route["to"]]
					if not route_margins.has(key):
						route_margins[key] = {
							"commodity": commodity.id,
							"from": route["from"],
							"to": route["to"],
							"hops": hops,
							"margins": [],
						}
					((route_margins[key] as Dictionary)["margins"] as Array).append(margin)
			best_today[commodity.id] = {"one_hop": best_one, "per_hop": best_rate}
		daily_best.append(best_today)
	return {
		"adjacency": adjacency,
		"sector_habitats": sector_habitats,
		"market_sectors": market_sectors,
		"routes": routes,
		"commodities": commodities,
		"days": days,
		"daily_best": daily_best,
		"route_margins": route_margins,
		"index_prices": index_prices,
	}


static func _observe_fuel_quotes(ctx: Dictionary) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var trade: Dictionary = ctx["trade"]
	var market_sectors: Dictionary = trade["market_sectors"]
	var observed := {}
	for day in trade["days"]:
		var quotes := FuelEconomy.compute_quotes(catalog, int(day))
		for sector_id in market_sectors.keys():
			var sector_quotes: Dictionary = quotes.get(sector_id, {})
			for fuel_id in sector_quotes.keys():
				var prices: Array = observed.get(fuel_id, [])
				prices.append(int((sector_quotes[fuel_id] as Dictionary).get("price", 0)))
				observed[fuel_id] = prices
	return observed


static func _quote_price(quotes: Dictionary, sector_id: String, commodity_id: String) -> int:
	var sector_quotes: Variant = quotes.get(sector_id, {})
	if typeof(sector_quotes) != TYPE_DICTIONARY:
		return 0
	var listing: Variant = (sector_quotes as Dictionary).get(commodity_id, {})
	if typeof(listing) != TYPE_DICTIONARY:
		return 0
	return int((listing as Dictionary).get("price", 0))


static func _fuel_mid_price(catalog: Catalog, fuel_id: String) -> float:
	if fuel_id.is_empty():
		return 0.0
	var fuel := catalog.get_fuel(fuel_id)
	var price_min := float(fuel.get("price_min", 0))
	return (price_min + float(fuel.get("price_max", price_min))) * 0.5


static func _transit_hours(catalog: Catalog, cfg: Dictionary, path_sectors: Array, adjacency: Dictionary) -> float:
	var hops := maxi(0, path_sectors.size() - 1)
	var orbit_hours := float(cfg.get("deadline_orbit_hours_per_hop", 2.0)) * float(hops)
	var translation := PassengerCharters.path_translation_seconds(catalog, path_sectors, adjacency)
	return translation / float(GalacticCalendar.SECONDS_PER_HOUR) + orbit_hours


# --- Charters and bounties --------------------------------------------------------------------


## Board generation mirrors `MissionSubsystem._ensure_habitat_boards`.
static func _sample_charters(ctx: Dictionary) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var opts: Dictionary = ctx["options"]
	var passenger_cfg := PassengerCharters.config(catalog)
	var terminal_count := int(passenger_cfg.get("terminal_offers_per_day", 4))
	var bar_count := int(passenger_cfg.get("bar_offers_per_day", 2))
	var freight_count := int(FreightCharters.config(catalog).get("offers_per_day", 4))
	var samples := {"terminal": [], "bar": [], "freight": [], "scan": [], "bounty": []}
	var boards: Array = []
	var habitat_ids: Array = catalog.habitats_by_id.keys()
	habitat_ids.sort()
	for habitat_variant in habitat_ids:
		var habitat_id := str(habitat_variant)
		var is_station := catalog.location_is_station(habitat_id)
		var has_bar := PassengerCharters.habitat_has_bar(catalog, habitat_id)
		for day_offset in range(maxi(1, int(opts.get("charter_days", 1)))):
			var day := int(ctx["start_day"]) + day_offset
			for run_seed_variant in opts.get("charter_seeds", [0]):
				var run_seed := int(run_seed_variant)
				var board := {"passenger": [], "freight": []}
				if not is_station:
					var terminal := PassengerCharters.generate_offers(
						catalog, habitat_id, PassengerCharters.BOARD_TERMINAL, day, terminal_count, run_seed
					)
					(samples["terminal"] as Array).append_array(terminal)
					(board["passenger"] as Array).append_array(terminal)
					if has_bar:
						var bar := PassengerCharters.generate_offers(
							catalog, habitat_id, PassengerCharters.BOARD_BAR, day, bar_count, run_seed
						)
						(samples["bar"] as Array).append_array(bar)
						(board["passenger"] as Array).append_array(bar)
					var freight := FreightCharters.generate_offers(catalog, habitat_id, day, freight_count, run_seed)
					(samples["freight"] as Array).append_array(freight)
					(board["freight"] as Array).append_array(freight)
					boards.append(board)
				for building_variant in ScanCharters.scan_building_ids(catalog, habitat_id):
					var building_id := str(building_variant)
					if not catalog.buildings_by_id.has(building_id):
						continue
					var building_type := catalog.get_building_type(catalog.get_building(building_id))
					(samples["scan"] as Array).append_array(ScanCharters.generate_offers_for_building(
						catalog, habitat_id, building_id, building_type, day, run_seed, 0
					))
					(samples["bounty"] as Array).append_array(BountyCharters.generate_offers_for_building(
						catalog, habitat_id, building_id, building_type, day, run_seed, 0
					))
	return {"samples": samples, "boards": boards}


static func _build_bounty_costs(ctx: Dictionary) -> Dictionary:
	var offers: Array = ((ctx["charters"] as Dictionary)["samples"] as Dictionary)["bounty"]
	var rewards: Array = []
	var groups := {}
	for offer_variant in offers:
		var offer: Dictionary = offer_variant
		rewards.append(int(offer.get("reward", 0)))
		var profile: Dictionary = offer.get("threat_profile", {})
		var hull_scale := float(profile.get("hull_scale", 1.0))
		var completion := str(offer.get("objective_completion", "destroy"))
		var target_id := str(offer.get("target_template_id", ""))
		var escorts := int(profile.get("escort_count", 0))
		var key := "%s|%.3f|%s|%d" % [target_id, hull_scale, completion, escorts]
		if not groups.has(key):
			groups[key] = {
				"target": target_id,
				"hull_scale": hull_scale,
				"disable": completion == "disable",
				"escorts": escorts,
				"count": 0,
			}
		(groups[key] as Dictionary)["count"] = int((groups[key] as Dictionary)["count"]) + 1
	var targets := {}
	var target_weapons := {}
	for probe_variant in ctx["templates"]:
		var probe: Dictionary = probe_variant
		targets[probe["id"]] = probe["assembled"]
		target_weapons[probe["id"]] = probe["best_weapon"]
	var memo := {}
	var hunters := {}
	for probe_variant in ctx["templates"]:
		var probe: Dictionary = probe_variant
		var stats: Dictionary = probe["best_weapon"]
		if stats.is_empty():
			continue
		var hunter_ship: AssembledShip = probe["assembled"]
		var total := 0
		var completed := 0
		var shots_sum := 0.0
		var taken := {"hull": 0.0, "power": 0.0, "compute": 0.0, "lost": 0.0, "won": 0.0}
		for key in groups.keys():
			var group: Dictionary = groups[key]
			var target: AssembledShip = targets.get(group["target"], null)
			if target == null:
				continue
			var memo_key := "%s|%s" % [stats["id"], key]
			if not memo.has(memo_key):
				memo[memo_key] = shots_to_finish(stats, target, float(group["hull_scale"]), bool(group["disable"]))
			var count := int(group["count"])
			total += count
			var shots := float(memo[memo_key])
			if shots < 0.0:
				continue
			completed += count
			shots_sum += shots * float(count)
			var attackers := 1 + int(group["escorts"])
			var exposure := maxf(0.0, shots - 1.0) * float(stats["cycle"])
			var hit := return_fire(hunter_ship, target_weapons.get(group["target"], {}), attackers, exposure)
			if bool(hit["breached"]):
				taken["lost"] = float(taken["lost"]) + float(count)
				continue
			taken["won"] = float(taken["won"]) + float(count)
			for field in ["hull", "power", "compute"]:
				taken[field] = float(taken[field]) + float(hit[field]) * float(count)
		var mean_shots := shots_sum / float(completed) if completed > 0 else 0.0
		var won := float(taken["won"])
		var per_win := 1.0 / won if won > 0.0 else 0.0
		hunters[probe["id"]] = {
			"completion_share": float(completed) / float(maxi(1, total)),
			"mean_shots": mean_shots,
			"kill_seconds": maxf(0.0, mean_shots - 1.0) * float(stats["cycle"]),
			"rearm": mean_shots * float(stats["ammo_cost_per_shot"]),
			"duels_lost_share": float(taken["lost"]) / float(completed) if completed > 0 else 0.0,
			"duels_won": won,
			"won_hull": float(taken["hull"]) * per_win,
			"won_power": float(taken["power"]) * per_win,
			"won_compute": float(taken["compute"]) * per_win,
		}
	return {"pay": _median(rewards), "offers": offers.size(), "hunters": hunters}


## Damage the hunter takes between its first shot and the kill `seconds` later: each attacker opens
## fire at the same moment and fires `weapon` on its own cycle with every round landing, less the
## hunter's point-defence share, and shields recharge between volleys. NPCs fire one weapon at a
## time, so the best weapon is the worst case per ship.
static func return_fire(hunter: AssembledShip, weapon: Dictionary, attackers: int, seconds: float) -> Dictionary:
	var out := {"hull": 0.0, "power": 0.0, "compute": 0.0, "breached": false}
	var cycle := float(weapon.get("cycle", 0.0))
	if weapon.is_empty() or attackers <= 0 or seconds < 0.0 or cycle <= 0.0:
		return out
	var state := ShipCombatState.from_assembled(hunter)
	var hull_before := state.hull_current
	var volley: Array = weapon["volley"]
	var lands := 1.0
	if bool(weapon.get("pd_interceptable", false)):
		lands = 1.0 - point_defence_intercept_chance(hunter)
	var credit := 0.0
	for _volley_index in int(floor(seconds / cycle + EPSILON)) + 1:
		credit += lands * float(attackers)
		while credit >= 1.0 - EPSILON:
			credit -= 1.0
			_volley_damage(hunter, state, volley)
		if state.is_hull_disabled():
			out["breached"] = true
			break
		ShipCombat.tick_shields(state, hunter, cycle)
	out["hull"] = hull_before - state.hull_current
	out["power"] = minf(state.power_integrity_lost, float(hunter.capacities.get("power_generation", 0.0)))
	out["compute"] = minf(state.compute_integrity_lost, float(hunter.capacities.get("compute_capacity", 0.0)))
	return out


# --- Repairs ----------------------------------------------------------------------------------


static func _build_repair_model(ctx: Dictionary) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var index_prices: Dictionary = (ctx["trade"] as Dictionary)["index_prices"]
	var index_def := catalog.get_commodity_def(REPAIR_INDEX_COMMODITY)
	var base_price := index_def.base_price if index_def != null and index_def.base_price > 0.0 else 1.0
	var yards: Array = []
	for habitat_id in _habitat_ids_with_building_type(catalog, "shipyard"):
		var sector_id := catalog.get_habitat_sector_id(habitat_id)
		var prices: Array = index_prices.get(sector_id, [])
		if not prices.is_empty():
			yards.append({
				"habitat_id": habitat_id,
				"sector_id": sector_id,
				"quote": _median(prices),
				"index": _median(prices) / base_price,
			})
	yards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["index"]) < float(b["index"]))
	var index := {"cheapest": 1.0, "median": 1.0, "dearest": 1.0}
	var yard_ids := {"cheapest": NONE, "median": NONE, "dearest": NONE}
	if not yards.is_empty():
		var picks := {"cheapest": yards[0], "median": yards[int(yards.size() / 2.0)], "dearest": yards[yards.size() - 1]}
		for slot in picks.keys():
			index[slot] = float((picks[slot] as Dictionary)["index"])
			yard_ids[slot] = str((picks[slot] as Dictionary)["habitat_id"])

	var hull_values: Array = []
	for chassis_id in catalog.chassis_by_id.keys():
		var chassis := catalog.get_chassis_def(str(chassis_id))
		if chassis != null and chassis.hits > 0.0:
			hull_values.append(chassis.cost / chassis.hits)
	var power_values: Array = []
	for def in _sorted_module_defs(catalog, "power"):
		if def.power_generation > 0.0:
			power_values.append(def.cost / def.power_generation)
	var compute_values: Array = []
	for def in _sorted_module_defs(catalog, "computer"):
		if def.compute_capacity > 0.0:
			compute_values.append(def.cost / def.compute_capacity)
	var hull_point_value := _median(hull_values)
	var fraction := REPAIR_PRICE_PER_HULL_POINT / hull_point_value if hull_point_value > 0.0 else 0.0
	var model := {
		"base_price": base_price,
		"index": index,
		"yard_ids": yard_ids,
		"yards": yards,
		"hull_rate": REPAIR_PRICE_PER_HULL_POINT,
		"hull_point_value": hull_point_value,
		"fraction": fraction,
		"power_unit_value": _median(power_values),
		"compute_unit_value": _median(compute_values),
		"power_rate": fraction * _median(power_values),
		"compute_rate": fraction * _median(compute_values),
	}
	model["calibration"] = _repair_calibration(ctx, float(index["median"]))
	return model


## Hull price per point at the median shipyard that would put each template on its target.
static func _repair_calibration(ctx: Dictionary, median_index: float) -> Dictionary:
	var bounty: Dictionary = ctx["bounty"]
	var hunters: Dictionary = bounty["hunters"]
	var pay := float(bounty["pay"])
	var breach_low: Array = []
	var breach_high: Array = []
	var ceilings: Array = []
	for probe_variant in ctx["templates"]:
		var probe: Dictionary = probe_variant
		var hull := float(probe["hull"])
		if hull <= 0.0:
			continue
		var typical_run := float((probe["earnings"] as Dictionary)["typical_run"])
		if typical_run > 0.0:
			breach_low.append(BREACH_RUNS_LOW * typical_run / hull)
			breach_high.append(BREACH_RUNS_HIGH * typical_run / hull)
		if hunters.has(probe["id"]) and pay > 0.0:
			var hunter: Dictionary = hunters[probe["id"]]
			if float(hunter["completion_share"]) >= 0.5:
				var spare := pay * (1.0 - BOUNTY_KEEP_TARGET) - float(hunter["rearm"])
				ceilings.append(spare / (BOUNTY_DAMAGE_LEVEL * hull))
	return {
		"breach_low": _median(breach_low),
		"breach_high": _median(breach_high),
		"bounty_ceiling": _median(ceilings),
		"median_index": median_index,
	}


static func repair_bill(model: Dictionary, hull_points: float, power_units: float, compute_units: float, yard: String) -> float:
	var index := float((model["index"] as Dictionary).get(yard, 1.0))
	var base := (
		hull_points * float(model["hull_rate"])
		+ power_units * float(model["power_rate"])
		+ compute_units * float(model["compute_rate"])
	)
	return base * index


## Priced on what the target can lose, so a hit past a breach bills a full repair, not the overkill.
static func _hit_repair_cost(model: Dictionary, target: AssembledShip, stats: Dictionary) -> float:
	var state := ShipCombatState.from_assembled(target)
	var hull_before := state.hull_current
	_volley_damage(target, state, stats["volley"])
	var power := minf(state.power_integrity_lost, float(target.capacities.get("power_generation", 0.0)))
	var compute := minf(state.compute_integrity_lost, float(target.capacities.get("compute_capacity", 0.0)))
	return repair_bill(model, hull_before - state.hull_current, power, compute, "median")


static func _without_defences(catalog: Catalog, owned: OwnedShip) -> AssembledShip:
	var copy := OwnedShip.from_dict(owned.to_dict())
	var kept: Array = []
	for entry_variant in copy.modules:
		var def := catalog.get_module_def(str((entry_variant as Dictionary).get("module_id", "")))
		if def == null or def.category not in ["armour", "shield"]:
			kept.append(entry_variant)
	copy.modules = kept
	return ShipAssembler.assemble_owned(catalog, copy)


# --- Backgrounds and code checks --------------------------------------------------------------


static func _probe_backgrounds(ctx: Dictionary) -> Array:
	var catalog: Catalog = ctx["catalog"]
	var out: Array = []
	var ids: Array = catalog.backgrounds_by_id.keys()
	ids.sort()
	for background_variant in ids:
		var background_id := str(background_variant)
		if background_id in EXCLUDED_BACKGROUNDS:
			continue
		var probe := _probe_background(ctx, background_id)
		if not probe.is_empty():
			out.append(probe)
	return out


static func _probe_background(ctx: Dictionary, background_id: String) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var session := GameSession.new()
	if not session.start_new_game(catalog, PROBE_CALLSIGN, background_id):
		return {}
	var credits := session.wallet.credits
	var fine := session.player.outstanding_sanction_fine()
	var liquid := credits - fine
	var kit_used := 0
	for ship in session.fleet.owned_ships:
		if not ship.template_id.is_empty():
			kit_used += ShipAssembly.used_ship_price(catalog, ship.template_id)
	var probe := {
		"id": background_id,
		"habitat_id": session.world.habitat_id,
		"credits": credits,
		"fine": fine,
		"liquid": liquid,
		"kit_used_value": kit_used,
		"reputation": session.player.reputation,
		"unlocks": _reputation_unlocks(catalog, session.player.reputation),
		"hold": 0.0,
		"seats": 0,
		"first_ship": NONE,
		"note": "",
	}
	var first := session.get_current_owned_ship()
	if first != null:
		var assembled := ShipAssembler.assemble_owned(catalog, first)
		probe["hold"] = float(assembled.capacities.get("cargo_capacity", 0.0))
		probe["seats"] = maxi(0, int(assembled.capacities.get("life_support_capacity", 0.0)) - PassengerCharters.PILOT_LIFE_SUPPORT_SEATS)
		probe["first_ship"] = first.template_id
		probe["first_run"] = _first_run(ctx, session, first, liquid)

	var proceeds_before := session.career.nett_profit()
	for ship in session.fleet.owned_ships:
		for entry_variant in ship.modules.duplicate():
			ShipAssembly.remove_module(session, catalog, ship.id, str((entry_variant as Dictionary).get("slot", "")))
	for part_variant in session.player.spare_parts.keys():
		var part_id := str(part_variant)
		while session.get_spare_part_count(part_id) > 0:
			if not ShipAssembly.sell_part(session, catalog, part_id):
				break
	probe["liquidation"] = session.career.nett_profit() - proceeds_before
	probe["leaderboard_after_liquidation"] = session.career.nett_profit()

	if first == null:
		var buyer := GameSession.new()
		if buyer.start_new_game(catalog, PROBE_CALLSIGN, background_id):
			_probe_first_purchase(ctx, buyer, probe, liquid)
		else:
			probe["first_run"] = {"one_hop": {}, "any": {}}
	return probe


## For a kit with no ship: buy the stocked used hull with the best first run, through the dealer.
static func _probe_first_purchase(ctx: Dictionary, session: GameSession, probe: Dictionary, liquid: int) -> void:
	var catalog: Catalog = ctx["catalog"]
	probe["first_run"] = {"one_hop": {}, "any": {}}
	var habitat := catalog.get_habitat(session.world.habitat_id)
	var dealer_id := ""
	for building_variant in habitat.get("buildings", []):
		var building_id := str(building_variant)
		if catalog.buildings_by_id.has(building_id) and catalog.get_building_type(catalog.get_building(building_id)) == "ship_dealer":
			dealer_id = building_id
	if dealer_id.is_empty():
		return
	var best_template := ""
	var best_run := {}
	var best_profit := -1
	for stock_variant in catalog.get_building(dealer_id).get("stock", []):
		var template_id := str(stock_variant)
		var price := ShipAssembly.used_ship_price(catalog, template_id)
		if price > liquid:
			continue
		var candidate := OwnedShip.from_template(
			catalog,
			{
				"id": "probe_%s" % template_id,
				"template_id": template_id,
				"chassis_id": catalog.get_ship_def(template_id).chassis,
				"location": session.world.habitat_id,
			}
		)
		var run := _first_run(ctx, session, candidate, liquid - price)
		var profit := int((run["any"] as Dictionary).get("profit", 0))
		if profit > best_profit:
			best_profit = profit
			best_template = template_id
			best_run = run
	if best_template.is_empty():
		return
	session.visit(catalog, dealer_id)
	session.buy_used_ship(catalog, best_template)
	var bought := session.get_current_owned_ship()
	if bought != null:
		var assembled := ShipAssembler.assemble_owned(catalog, bought)
		probe["hold"] = float(assembled.capacities.get("cargo_capacity", 0.0))
		probe["seats"] = maxi(0, int(assembled.capacities.get("life_support_capacity", 0.0)) - PassengerCharters.PILOT_LIFE_SUPPORT_SEATS)
	probe["first_ship"] = "bought %s" % best_template
	probe["first_run"] = best_run
	var nett := session.career.nett_profit()
	probe["note"] = (
		"%s starts with no ship. Buying %s for d%s leaves `nett_profit()` at %sd%s before any trade."
		% [
			probe["id"],
			best_template,
			_group_digits(ShipAssembly.used_ship_price(catalog, best_template)),
			"-" if nett < 0 else "",
			_group_digits(absi(nett)),
		]
	)


static func _first_run(ctx: Dictionary, session: GameSession, ship: OwnedShip, credits: int) -> Dictionary:
	var catalog: Catalog = ctx["catalog"]
	var trade: Dictionary = ctx["trade"]
	var origin := session.get_market_sector_id(catalog)
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	var hold := float(assembled.capacities.get("cargo_capacity", 0.0))
	var quotes: Dictionary = session.world.market_quotes
	var best_one := {}
	var best_any := {}
	if hold <= 0.0 or credits <= 0:
		return {"one_hop": best_one, "any": best_any}
	var lots := {}
	for commodity_variant in trade["commodities"]:
		var commodity: CommodityDef = commodity_variant
		if not CargoRequirements.assembled_meets_commodity(assembled, commodity):
			continue
		var buy := _quote_price(quotes, origin, commodity.id)
		if buy <= 0:
			continue
		var units := mini(int(floor(float(credits) / float(buy))), int(floor(hold / commodity.mass + EPSILON)))
		if units > 0 and not session.cargo_carry_block_reason(catalog, ship, commodity.id, units).is_empty():
			units -= 1
		if units <= 0 or not session.cargo_carry_block_reason(catalog, ship, commodity.id, units).is_empty():
			continue
		lots[commodity.id] = {"buy": buy, "units": units}
	for route_variant in trade["routes"]:
		var route: Dictionary = route_variant
		if str(route["from"]) != origin:
			continue
		for commodity_variant in lots.keys():
			var commodity_id := str(commodity_variant)
			var lot: Dictionary = lots[commodity_variant]
			var margin := CommodityEconomy.sell_price(_quote_price(quotes, str(route["to"]), commodity_id)) - int(lot["buy"])
			var pick := {
				"profit": int(lot["units"]) * margin,
				"commodity": commodity_id,
				"to": route["to"],
				"hops": int(route["hops"]),
			}
			if int(route["hops"]) == 1 and int(pick["profit"]) > int(best_one.get("profit", 0)):
				best_one = pick
			if int(pick["profit"]) > int(best_any.get("profit", 0)):
				best_any = pick
	return {"one_hop": best_one, "any": best_any}


static func _reputation_unlocks(catalog: Catalog, reputation: int) -> String:
	var unlocked := PackedStringArray()
	for role_variant in PassengerCharters.config(catalog).get("roles", []):
		var role: Dictionary = role_variant
		var needed := int(role.get("min_reputation", 0))
		if needed > 0 and needed <= reputation:
			unlocked.append(str(role.get("id", "")))
	for cargo_variant in FreightCharters.config(catalog).get("cargos", []):
		var cargo: Dictionary = cargo_variant
		var needed := int(cargo.get("min_reputation", 0))
		if needed > 0 and needed <= reputation:
			unlocked.append(str(cargo.get("id", "")))
	return ", ".join(unlocked) if not unlocked.is_empty() else "none"


static func _check_dock_repair(ctx: Dictionary) -> Array:
	var catalog: Catalog = ctx["catalog"]
	var session := _probe_session(ctx)
	if session == null:
		return ["Docking repairs the hull", "not run", "no background with a ship"]
	session.combat.hull = 1.0
	var credits := session.wallet.credits
	session.dock(catalog, session.world.habitat_id)
	var repaired := is_equal_approx(session.combat.hull, session.combat.max_hull)
	return [
		"Docking repairs the hull",
		"free, full repair" if repaired and session.wallet.credits == credits else "not free",
		"hull 1 -> %.0f of %.0f; credits changed by %d" % [session.combat.hull, session.combat.max_hull, session.wallet.credits - credits],
	]


static func _check_unspace_arrival(ctx: Dictionary) -> Array:
	var catalog: Catalog = ctx["catalog"]
	var session := _probe_session(ctx)
	if session == null:
		return ["Arriving from unspace restores the hull", "not run", "no background with a ship"]
	var ship := session.get_current_owned_ship()
	var origin := session.world.sector_id
	var edges: Array = ((ctx["trade"] as Dictionary)["adjacency"] as Dictionary).get(origin, [])
	if edges.is_empty() or not session.undock(catalog, ship.id):
		return ["Arriving from unspace restores the hull", "not run", session.player.last_log]
	session.combat.hull = 1.0
	session.world.in_unspace = true
	session.world.pending_destination_id = str((edges[0] as Dictionary).get("sector", ""))
	session.arrive_from_unspace(catalog)
	var restored := is_equal_approx(session.combat.hull, session.combat.max_hull)
	return [
		"Arriving from unspace restores the hull",
		"yes" if restored else "no",
		"hull 1 -> %.0f of %.0f after %s -> %s" % [session.combat.hull, session.combat.max_hull, origin, session.world.sector_id],
	]


static func _check_undock_hull_carry_over(ctx: Dictionary) -> Array:
	var catalog: Catalog = ctx["catalog"]
	var session := _probe_session(ctx)
	if session == null:
		return ["Launching a second ship resets hull figures", "not run", "no background with a ship"]
	var first := session.get_current_owned_ship()
	var first_hull := float(ShipAssembler.assemble_owned(catalog, first).capacities.get("hull_hits", 0))
	var other := {}
	for probe_variant in ctx["templates"]:
		var probe: Dictionary = probe_variant
		if not is_equal_approx(float(probe["hull"]), first_hull):
			other = probe
			break
	if other.is_empty():
		return ["Launching a second ship resets hull figures", "not run", "every template has the same hull"]
	var second := OwnedShip.from_template(
		catalog,
		{
			"id": "probe_second_ship",
			"template_id": other["id"],
			"chassis_id": other["chassis_id"],
			"location": session.world.habitat_id,
		}
	)
	session.fleet.owned_ships.append(second)
	session.dock(catalog, session.world.habitat_id)
	if not session.undock(catalog, second.id):
		return ["Launching a second ship resets hull figures", "not run", session.player.last_log]
	var state := session.build_combat_state(ShipAssembler.assemble_owned(catalog, second))
	var reset := is_equal_approx(state.hull_max, float(other["hull"]))
	return [
		"Launching a second ship resets hull figures",
		"yes" if reset else "no, the previous ship's figures carry over",
		"docked %s (hull %.0f), launched %s (hull %.0f): flight state hull %.0f of %.0f" % [
			first.template_id, first_hull, other["id"], float(other["hull"]), state.hull_current, state.hull_max,
		],
	]


## A fresh career on the first shipped background that starts with a ship.
static func _probe_session(ctx: Dictionary) -> GameSession:
	var catalog: Catalog = ctx["catalog"]
	var ids: Array = catalog.backgrounds_by_id.keys()
	ids.sort()
	for background_variant in ids:
		var background_id := str(background_variant)
		if background_id in EXCLUDED_BACKGROUNDS:
			continue
		if (catalog.get_background(background_id).get("ships", []) as Array).is_empty():
			continue
		var session := GameSession.new()
		if session.start_new_game(catalog, PROBE_CALLSIGN, background_id) and session.player.outstanding_sanction_fine() == 0:
			return session
	return null


# --- Helpers ----------------------------------------------------------------------------------


static func _section(id: String, title: String, columns: Array, rows: Array, notes: Array = []) -> Dictionary:
	return {"id": id, "title": title, "columns": columns, "rows": rows, "notes": notes}


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := int(sorted.size() / 2.0)
	if sorted.size() % 2 == 1:
		return float(sorted[middle])
	return (float(sorted[middle - 1]) + float(sorted[middle])) * 0.5


static func _percentile(values: Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(int(round(fraction * float(sorted.size() - 1))), 0, sorted.size() - 1)
	return float(sorted[index])


static func _most_common(counts: Dictionary) -> String:
	var best := ""
	var best_count := 0
	var keys: Array = counts.keys()
	keys.sort()
	for key in keys:
		if int(counts[key]) > best_count:
			best = str(key)
			best_count = int(counts[key])
	return best


static func _merged_keys(a: Dictionary, b: Dictionary) -> Array:
	var keys: Array = a.keys()
	for key in b.keys():
		if not keys.has(key):
			keys.append(key)
	return keys


static func _sorted_module_defs(catalog: Catalog, category: String) -> Array[ModuleDef]:
	var defs: Array[ModuleDef] = []
	for def_variant in catalog.list_module_defs(category):
		defs.append(def_variant as ModuleDef)
	defs.sort_custom(func(a: ModuleDef, b: ModuleDef) -> bool: return a.id < b.id)
	return defs


static func _sorted_template_ids(catalog: Catalog) -> Array[String]:
	var ids: Array[String] = []
	for template_id in catalog.ships_by_id.keys():
		ids.append(str(template_id))
	ids.sort()
	return ids


static func _sorted_mounts(def: ModuleDef) -> Array:
	var mounts := ShipAssembler.module_mounts(def)
	mounts.sort()
	return mounts


static func _probe_chassis_id(catalog: Catalog) -> String:
	var ids: Array = catalog.chassis_by_id.keys()
	ids.sort()
	return str(ids[0]) if not ids.is_empty() else ""


static func _habitat_ids_with_building_type(catalog: Catalog, building_type: String) -> Array[String]:
	var out: Array[String] = []
	for habitat_variant in catalog.list_habitat_dicts():
		var habitat: Dictionary = habitat_variant
		if str(habitat.get("type", "habitat")) == "station":
			continue
		for building_variant in habitat.get("buildings", []):
			var building_id := str(building_variant)
			if not catalog.buildings_by_id.has(building_id):
				continue
			if catalog.get_building_type(catalog.get_building(building_id)) == building_type:
				out.append(str(habitat.get("id", "")))
				break
	out.sort()
	return out


static func _capability_label(capabilities: Array) -> String:
	if capabilities.is_empty():
		return "none"
	var labels := PackedStringArray()
	for cap in capabilities:
		labels.append(str(cap))
	return ", ".join(labels)


static func _run_label(run: Variant) -> String:
	if typeof(run) != TYPE_DICTIONARY or (run as Dictionary).is_empty():
		return NONE
	var pick: Dictionary = run
	return "d%s %s to %s (%d hop%s)" % [
		_group_digits(int(pick["profit"])),
		pick["commodity"],
		pick["to"],
		int(pick["hops"]),
		"" if int(pick["hops"]) == 1 else "s",
	]


static func _column_is_numeric(rows: Array, index: int) -> bool:
	var seen := false
	for row_variant in rows:
		var row: Array = row_variant
		if index >= row.size():
			continue
		var cell: Variant = row[index]
		if typeof(cell) == TYPE_STRING and str(cell) == NONE:
			continue
		if typeof(cell) != TYPE_INT and typeof(cell) != TYPE_FLOAT:
			return false
		seen = true
	return seen


static func _group_digits(number: int) -> String:
	var digits := str(absi(number))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	grouped = digits + grouped
	return "-" + grouped if number < 0 else grouped
