class_name LibraryIndex
extends RefCounted

const SHELF_STARS := "stars"
const SHELF_WORLDS := "worlds"
const SHELF_CORPORATIONS := "corporations"
const SHELF_MODULES := "modules"
const SHELF_HULLS := "hulls"
const SHELF_COMMODITIES := "commodities"

const SHELF_LABELS := {
	SHELF_STARS: "Stars",
	SHELF_WORLDS: "Worlds",
	SHELF_CORPORATIONS: "Corporations",
	SHELF_MODULES: "Modules",
	SHELF_HULLS: "Hulls",
	SHELF_COMMODITIES: "Commodities",
}

const SHELF_ORDER: Array[String] = [
	SHELF_STARS,
	SHELF_WORLDS,
	SHELF_CORPORATIONS,
	SHELF_MODULES,
	SHELF_HULLS,
	SHELF_COMMODITIES,
]


static func list_shelf_ids() -> Array:
	return SHELF_ORDER.duplicate()


static func shelf_label(shelf_id: String) -> String:
	return str(SHELF_LABELS.get(shelf_id, shelf_id.capitalize()))


static func list_rows(catalog: Catalog, shelf_id: String, filter_text: String = "") -> Array:
	var rows: Array = []
	match shelf_id:
		SHELF_STARS:
			rows = _star_rows(catalog)
		SHELF_WORLDS:
			rows = _world_rows(catalog)
		SHELF_CORPORATIONS:
			rows = _corporation_rows(catalog)
		SHELF_MODULES:
			rows = _module_rows(catalog)
		SHELF_HULLS:
			rows = _hull_rows(catalog)
		SHELF_COMMODITIES:
			rows = _commodity_rows(catalog)
		_:
			return []
	return _apply_filter(rows, filter_text)


static func detail_text(catalog: Catalog, shelf_id: String, entry_id: String) -> String:
	if entry_id.is_empty():
		return ""
	match shelf_id:
		SHELF_STARS:
			return _star_detail(catalog, entry_id)
		SHELF_WORLDS:
			return _world_detail(catalog, entry_id)
		SHELF_CORPORATIONS:
			return _corporation_detail(catalog, entry_id)
		SHELF_MODULES:
			return _module_detail(catalog, entry_id)
		SHELF_HULLS:
			return _hull_detail(catalog, entry_id)
		SHELF_COMMODITIES:
			return _commodity_detail(catalog, entry_id)
		_:
			return ""
	return ""


static func _apply_filter(rows: Array, filter_text: String) -> Array:
	var needle := filter_text.strip_edges().to_lower()
	if needle.is_empty():
		return rows
	var out: Array = []
	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		var label := str(row.get("label", "")).to_lower()
		var entry_id := str(row.get("id", "")).to_lower()
		if needle in label or needle in entry_id:
			out.append(row)
	return out


static func _star_rows(catalog: Catalog) -> Array:
	var rows: Array = []
	for star_name_variant in catalog.list_star_names_outside_system(""):
		var star_name := str(star_name_variant)
		var star := catalog.get_star(star_name)
		if star.is_empty():
			continue
		rows.append({
			"id": star_name,
			"label": star_name,
			"sort_key": star_name,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("sort_key", "")) < str(b.get("sort_key", ""))
	)
	return rows


static func _world_rows(catalog: Catalog) -> Array:
	var rows: Array = []
	for sector_variant in catalog.list_sectors():
		if typeof(sector_variant) != TYPE_DICTIONARY:
			continue
		var sector: Dictionary = sector_variant
		var sector_id := str(sector.get("id", ""))
		if sector_id.is_empty():
			continue
		var title := str(sector.get("planet_name", "")).strip_edges()
		if title.is_empty():
			title = str(sector.get("name", sector_id))
		var classification := str(sector.get("classification", ""))
		var e_rank := 0 if classification.begins_with("E") else 1
		rows.append({
			"id": sector_id,
			"label": title,
			"sort_key": "%d|%s" % [e_rank, title],
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("sort_key", "")) < str(b.get("sort_key", ""))
	)
	return rows


static func _corporation_rows(catalog: Catalog) -> Array:
	var rows: Array = []
	for corp_variant in catalog.list_corporations():
		if typeof(corp_variant) != TYPE_DICTIONARY:
			continue
		var corp: Dictionary = corp_variant
		var corp_id := str(corp.get("id", ""))
		var name := str(corp.get("name", corp_id))
		rows.append({
			"id": corp_id,
			"label": name,
			"sort_key": name,
		})
	return rows


static func _module_rows(catalog: Catalog) -> Array:
	var rows: Array = []
	for module_variant in catalog.list_modules():
		if typeof(module_variant) != TYPE_DICTIONARY:
			continue
		var module_def: Dictionary = module_variant
		var module_id := str(module_def.get("id", ""))
		if module_id.is_empty():
			continue
		var category := str(module_def.get("category", ""))
		var name := str(module_def.get("name", module_id))
		rows.append({
			"id": module_id,
			"label": name,
			"sort_key": "%s|%s" % [category, name],
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("sort_key", "")) < str(b.get("sort_key", ""))
	)
	return rows


static func _hull_rows(catalog: Catalog) -> Array:
	var rows: Array = []
	for chassis_variant in catalog.list_chassis():
		if typeof(chassis_variant) != TYPE_DICTIONARY:
			continue
		var chassis: Dictionary = chassis_variant
		var chassis_id := str(chassis.get("id", ""))
		if chassis_id.is_empty():
			continue
		var name := str(chassis.get("name", chassis_id))
		rows.append({
			"id": chassis_id,
			"label": name,
			"sort_key": name,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("sort_key", "")) < str(b.get("sort_key", ""))
	)
	return rows


static func _commodity_rows(catalog: Catalog) -> Array:
	var rows: Array = []
	for commodity_variant in catalog.list_commodities():
		if typeof(commodity_variant) != TYPE_DICTIONARY:
			continue
		var commodity: Dictionary = commodity_variant
		var commodity_id := str(commodity.get("id", ""))
		if commodity_id.is_empty():
			continue
		var name := str(commodity.get("name", commodity_id))
		rows.append({
			"id": commodity_id,
			"label": name,
			"sort_key": name,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("sort_key", "")) < str(b.get("sort_key", ""))
	)
	return rows


static func _star_detail(catalog: Catalog, star_name: String) -> String:
	var star := catalog.get_star(star_name)
	if star.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append(star_name)
	_append_line(lines, "Star system", str(star.get("star_system", "")))
	_append_line(lines, "Spectral class", str(star.get("spectral_class", "")))
	_append_float_line(lines, "Temperature", float(star.get("temperature_k", 0.0)), " K")
	_append_float_line(lines, "Luminosity", float(star.get("luminosity", 0.0)), " L☉")
	_append_float_line(lines, "Mass", float(star.get("mass_solar", 0.0)), " M☉")
	_append_float_line(lines, "Radius", float(star.get("radius_solar", 0.0)), " R☉")
	var description := str(star.get("description", "")).strip_edges()
	if not description.is_empty():
		lines.append("")
		lines.append(description)
	return "\n".join(lines)


static func _world_detail(catalog: Catalog, sector_id: String) -> String:
	var sector := catalog.get_sector(sector_id)
	if sector.is_empty():
		return ""
	var title := str(sector.get("planet_name", "")).strip_edges()
	if title.is_empty():
		title = str(sector.get("name", sector_id))
	var lines: PackedStringArray = PackedStringArray()
	lines.append(title)
	_append_line(lines, "Sector", str(sector.get("name", sector_id)))
	_append_line(lines, "Classification", str(sector.get("classification", "")))
	_append_line(lines, "Star", str(sector.get("star", "")))
	_append_line(lines, "Star system", str(sector.get("star_system", "")))
	_append_line(lines, "Climate", str(sector.get("climate", "")))
	_append_float_line(lines, "Gravity", float(sector.get("gravity", 0.0)), " g")
	_append_float_line(lines, "Population", float(sector.get("population_billions", 0.0)), " bn")
	if sector.has("surface_population_billions"):
		_append_float_line(
			lines,
			"Surface",
			float(sector.get("surface_population_billions", 0.0)),
			" bn"
		)
	for habitat_variant in catalog.list_habitat_dicts():
		if typeof(habitat_variant) != TYPE_DICTIONARY:
			continue
		var habitat: Dictionary = habitat_variant
		if str(habitat.get("sector_id", "")) != sector_id:
			continue
		if not habitat.has("population_billions"):
			continue
		var orbital_pop := float(habitat.get("population_billions", 0.0))
		if orbital_pop <= 0.0:
			continue
		var habitat_name := str(habitat.get("name", habitat.get("id", "")))
		_append_float_line(lines, "Orbital (%s)" % habitat_name, orbital_pop, " bn")
	_append_float_line(lines, "Ocean coverage", float(sector.get("ocean_coverage", 0.0)), "")
	var malls: Variant = sector.get("city_malls", [])
	if typeof(malls) == TYPE_ARRAY and not (malls as Array).is_empty():
		var mall_names: PackedStringArray = PackedStringArray()
		for entry in malls:
			mall_names.append(str(entry))
		_append_line(lines, "City-malls", ", ".join(mall_names))
	var description := str(sector.get("description", "")).strip_edges()
	if not description.is_empty():
		lines.append("")
		lines.append(description)
	return "\n".join(lines)


static func _corporation_detail(catalog: Catalog, corp_id: String) -> String:
	var corp := catalog.get_corporation(corp_id)
	if corp.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append(str(corp.get("name", corp_id)))
	_append_line(lines, "Callsign", str(corp.get("callsign_prefix", "")))
	_append_line(lines, "Practice", str(corp.get("practice", "")))
	_append_line(lines, "Trade", str(corp.get("trade", "")))
	var hq: Variant = corp.get("hq", {})
	if typeof(hq) == TYPE_DICTIONARY:
		var hq_line := _format_corp_hq(catalog, hq as Dictionary)
		if not hq_line.is_empty():
			_append_line(lines, "Headquarters", hq_line)
	var brands: Variant = corp.get("brands", [])
	if typeof(brands) == TYPE_ARRAY and not (brands as Array).is_empty():
		var brand_names: PackedStringArray = PackedStringArray()
		for entry in brands:
			brand_names.append(str(entry))
		_append_line(lines, "Brands", ", ".join(brand_names))
	var description := str(corp.get("description", "")).strip_edges()
	if not description.is_empty():
		lines.append("")
		lines.append(description)
	return "\n".join(lines)


static func _module_detail(catalog: Catalog, module_id: String) -> String:
	var module_def := catalog.get_module(module_id)
	if module_def.is_empty():
		return ""
	return ModuleSpecText.format_tooltip(module_def)


static func _hull_detail(catalog: Catalog, chassis_id: String) -> String:
	var chassis := catalog.get_chassis(chassis_id)
	if chassis.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append(str(chassis.get("name", chassis_id)))
	_append_line(lines, "Maker", str(chassis.get("maker", "")))
	_append_line(lines, "Cost", "d%d" % int(chassis.get("cost", 0)))
	_append_float_line(lines, "Mass", float(chassis.get("mass", 0.0)), " t")
	_append_float_line(lines, "Hits", float(chassis.get("hits", 0.0)), "")
	_append_line(lines, "Maneuver", str(chassis.get("maneuver", "")))
	var mounts: Variant = chassis.get("mounts", {})
	if typeof(mounts) == TYPE_DICTIONARY:
		var mount_dict := mounts as Dictionary
		if not mount_dict.is_empty():
			lines.append("")
			lines.append("MOUNTS")
			var keys: Array = mount_dict.keys()
			keys.sort()
			for key_variant in keys:
				var key := str(key_variant)
				lines.append("  %s: %s" % [key, str(mount_dict.get(key, ""))])
	var description := str(chassis.get("description", "")).strip_edges()
	if not description.is_empty():
		lines.append("")
		lines.append(description)
	return "\n".join(lines)


static func _commodity_detail(catalog: Catalog, commodity_id: String) -> String:
	var commodity := catalog.get_commodity(commodity_id)
	if commodity.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append(str(commodity.get("name", commodity_id)))
	_append_float_line(lines, "Mass", float(commodity.get("mass", 0.0)), " t")
	_append_line(lines, "Base price", "d%d" % int(commodity.get("base_price", 0)))
	var caps: Variant = commodity.get("requires_capabilities", [])
	if typeof(caps) == TYPE_ARRAY and not (caps as Array).is_empty():
		var cap_labels: PackedStringArray = PackedStringArray()
		for entry in caps:
			var cap_id := str(entry)
			cap_labels.append(ModuleSpecText.capability_label(cap_id))
		_append_line(lines, "Requires", ", ".join(cap_labels))
	var description := str(commodity.get("description", "")).strip_edges()
	if not description.is_empty():
		lines.append("")
		lines.append(description)
	return "\n".join(lines)


static func _format_corp_hq(catalog: Catalog, hq: Dictionary) -> String:
	var placement := str(hq.get("placement", ""))
	var sector_id := str(hq.get("sector_id", ""))
	var sector := catalog.get_sector(sector_id)
	var sector_label := str(sector.get("planet_name", "")).strip_edges()
	if sector_label.is_empty():
		sector_label = str(sector.get("name", sector_id))
	match placement:
		"planet":
			return "%s, planet" % sector_label
		"habitat":
			var location_id := str(hq.get("location_id", ""))
			if not location_id.is_empty():
				return str(catalog.get_habitat(location_id).get("name", location_id))
			return "%s, habitat" % sector_label
		"orbital":
			return "%s, orbital" % sector_label
		"outlying":
			var location_id := str(hq.get("location_id", ""))
			if not location_id.is_empty():
				return str(catalog.get_habitat(location_id).get("name", location_id))
			return "%s, outlying" % sector_label
		_:
			return sector_label


static func _append_line(lines: PackedStringArray, label: String, value: String) -> void:
	if value.is_empty():
		return
	lines.append("%s: %s" % [label, value])


static func _append_float_line(
	lines: PackedStringArray, label: String, value: float, suffix: String
) -> void:
	if value == 0.0 and label != "Ocean coverage":
		return
	var formatted := "%.2f%s" % [value, suffix] if suffix != "" else "%.2f" % value
	lines.append("%s: %s" % [label, formatted])
