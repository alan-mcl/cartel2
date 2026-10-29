class_name AreaRadar
extends RefCounted

const GRID_STEP_M := 500.0
const VIEW_MARGIN_FACTOR := 1.12
const RANGE_MERGE_TOLERANCE_M := 1.0
const DEFAULT_MODULE_RANGE_M := 6500.0
const VISUAL_LABEL := "Visual"


static func build_snapshot(
	assembled: AssembledShip,
	operating_state: ShipOperatingState,
	catalog: Catalog
) -> Dictionary:
	var visual_range := _visual_contact_radius(catalog)
	var effectiveness := SensorSystem.sensor_effectiveness(assembled, operating_state)
	var module_entries: Array = _sensor_module_entries(assembled, effectiveness)
	var sensor_clusters := _cluster_by_range(module_entries)
	var max_range := visual_range
	for cluster in sensor_clusters:
		max_range = maxf(max_range, float(cluster.get("range_m", 0.0)))

	var circles: Array = []
	circles.append({
		"kind": "visual",
		"range_m": visual_range,
		"labels": PackedStringArray([VISUAL_LABEL]),
	})
	for cluster in sensor_clusters:
		circles.append({
			"kind": "sensor",
			"range_m": float(cluster.get("range_m", 0.0)),
			"labels": cluster.get("labels", PackedStringArray()),
		})

	return {
		"visual_range_m": visual_range,
		"circles": circles,
		"view_half_extent_m": maxf(max_range, 1.0) * VIEW_MARGIN_FACTOR,
		"grid_step_m": GRID_STEP_M,
		"effectiveness": effectiveness,
	}


static func _visual_contact_radius(catalog: Catalog) -> float:
	if catalog == null:
		return 250.0
	return float(catalog.get_traffic_config().get("visual_contact_radius", 250.0))


static func _sensor_module_entries(assembled: AssembledShip, effectiveness: float) -> Array:
	var entries: Array = []
	if assembled == null or not assembled.has_capability("local_sensor"):
		return entries
	for entry_variant in assembled.modules_in_category("sensor"):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var module_data: Variant = entry.get("data", null)
		if module_data == null or not module_data is ModuleDef:
			continue
		var module_def: ModuleDef = module_data
		var base_range := module_def.sensor_range
		if base_range <= 0.0:
			base_range = DEFAULT_MODULE_RANGE_M
		var effective_range := base_range * effectiveness
		entries.append({
			"name": module_def.name,
			"range_m": effective_range,
		})
	return entries


static func _cluster_by_range(module_entries: Array) -> Array:
	if module_entries.is_empty():
		return []
	var sorted: Array = module_entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("range_m", 0.0)) < float(b.get("range_m", 0.0))
	)
	var clusters: Array = []
	for entry_variant in sorted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var range_m := float(entry.get("range_m", 0.0))
		var name := str(entry.get("name", ""))
		if clusters.is_empty():
			clusters.append({"range_m": range_m, "labels": PackedStringArray([name])})
			continue
		var last: Dictionary = clusters[clusters.size() - 1]
		if absf(range_m - float(last.get("range_m", 0.0))) <= RANGE_MERGE_TOLERANCE_M:
			var labels: PackedStringArray = last.get("labels", PackedStringArray())
			labels.append(name)
			last["labels"] = labels
		else:
			clusters.append({"range_m": range_m, "labels": PackedStringArray([name])})
	return clusters
