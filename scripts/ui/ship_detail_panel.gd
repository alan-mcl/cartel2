extends VBoxContainer

var _catalog: Catalog
var _ship: OwnedShip

var _show_name: bool = false
var _show_summary: bool = false
var _chassis_style: String = "row"
var _show_modules: bool = false
var _show_engineering: bool = false
var _show_flight: bool = false
var _flight_keys: Array[String] = []
var _flight_section_title: String = "STATS"
var _flight_row_style: String = "HBox"
var _show_signature: bool = true
var _show_chassis_art: bool = true


func configure(opts: Dictionary) -> void:
	_show_name = bool(opts.get("show_name", false))
	_show_summary = bool(opts.get("show_summary", false))
	_chassis_style = str(opts.get("chassis_style", "row"))
	_show_modules = bool(opts.get("show_modules", false))
	_show_engineering = bool(opts.get("show_engineering", false))
	_show_flight = bool(opts.get("show_flight", false))
	_flight_section_title = str(opts.get("flight_section_title", "STATS"))
	_flight_row_style = str(opts.get("flight_row_style", "HBox"))
	_show_signature = bool(opts.get("show_signature", true))
	_show_chassis_art = bool(opts.get("show_chassis_art", true))
	_flight_keys.clear()
	var keys: Variant = opts.get("flight_keys", [])
	if typeof(keys) == TYPE_ARRAY:
		for key in keys:
			_flight_keys.append(str(key))


func bind_ship(catalog: Catalog, ship: OwnedShip) -> void:
	_catalog = catalog
	_ship = ship


func refresh() -> void:
	_clear_children(self)
	if _catalog == null or _ship == null:
		return

	var assembled := ShipAssembly.preview_stats(_catalog, _ship)
	var chassis_data := _catalog.get_chassis(_ship.chassis_id)

	if _show_chassis_art:
		add_child(
			LocationArtFactory.create_banner(str(chassis_data.get("header", "")), _ship.name)
		)

	if _show_summary:
		var summary := Label.new()
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.text = assembled.get_summary()
		add_child(summary)

	if _show_name:
		add_child(UiPatterns.headline_item(_ship.name))

	if _chassis_style == "row":
		add_child(UiPatterns.status_row("Chassis", str(assembled.chassis.get("name", _ship.chassis_id))))
	elif _chassis_style == "fixed":
		var chassis := Label.new()
		chassis.text = "Chassis (fixed): %s" % str(assembled.chassis.get("name", _ship.chassis_id))
		chassis.theme_type_variation = &"Numeric"
		add_child(chassis)

	if _show_modules:
		add_child(_section_label("MODULES"))
		for entry in assembled.installed_modules:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var slot := str(entry.get("slot", ""))
			var module_data: ModuleDef = entry.get("data", null)
			var module_name := module_data.name if module_data != null else str(entry.get("module_id", ""))
			var category := module_data.category if module_data != null else ""
			add_child(ModuleIcons.make_module_status_row(slot, module_name, category))

	var engineering := ShipAssembly.get_engineering_block(_catalog, _ship)
	var stats: Dictionary = engineering.get("stats", {})

	if _show_engineering:
		var capacities: Dictionary = engineering.get("capacities", {})
		var envelope: Dictionary = engineering.get("envelope", {})
		var mounts: Dictionary = engineering.get("mounts", {})

		add_child(_section_label("ENGINEERING"))
		add_child(_detail_label(
			"MASS",
			"%.1f / %.1f t" % [float(envelope.get("dry_mass", 0.0)), float(envelope.get("mass_limit", 0.0))]
		))
		add_child(_detail_label(
			"VOLUME",
			"%.1f / %.1f m³" % [float(envelope.get("volume_used", 0.0)), float(envelope.get("volume", 0.0))]
		))
		add_child(_detail_label(
			"POWER",
			"%.0f / %.0f MW idle" % [float(engineering.get("idle_power_requested", 0.0)), float(engineering.get("idle_power_available", 0.0))]
		))
		add_child(_detail_label(
			"COMPUTE",
			"%.0f / %.0f CU idle" % [float(engineering.get("idle_compute_demand", 0.0)), float(capacities.get("compute_capacity", 0.0))]
		))
		add_child(_detail_label(
			"LIFE SUPPORT",
			"%.0f people" % float(capacities.get("life_support_capacity", 0.0))
		))
		add_child(_detail_label(
			"CARGO",
			"%.0f t capacity" % float(capacities.get("cargo_capacity", 0.0))
		))
		add_child(_detail_label("FUEL", ShipFuel.format_gauge(_catalog, _ship)))

		for mount_type in ["light_weapon", "medium_weapon", "heavy_weapon"]:
			if mounts.has(mount_type):
				var usage: Dictionary = mounts[mount_type]
				var mount_label: String = mount_type.replace("_", " ").capitalize()
				add_child(_detail_label(
					mount_label.to_upper(),
					"%d / %d" % [int(usage.get("used", 0)), int(usage.get("total", 0))]
				))

	if _show_flight:
		var flight_stats := stats
		if not _show_engineering:
			flight_stats = ShipAssembly.get_stat_block(_catalog, _ship)
		if not flight_stats.is_empty():
			add_child(_section_label(_flight_section_title))
			for key in _flight_keys:
				if flight_stats.has(key):
					if _flight_row_style == "HBox":
						add_child(UiPatterns.status_row(key, str(flight_stats[key])))
					else:
						add_child(_detail_label(key, str(flight_stats[key])))

	if _show_signature:
		ModuleSpecText.append_ship_signature_rows(
			self,
			engineering.get("signature", {}),
			str(engineering.get("transponder_label", "off"))
		)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _detail_label(label_text: String, value_text: String) -> Label:
	var label := Label.new()
	label.text = "%s: %s" % [label_text, value_text]
	label.theme_type_variation = &"Numeric"
	return label


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Section"
	return label
