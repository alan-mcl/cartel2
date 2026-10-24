class_name PlanetSurfaceLabels
extends RefCounted

## Projects City-Mall anchors from a night-lights habitations sidecar onto the
## flight plane. Directions are Godot SphereMesh locals: +Z faces the camera
## before the planet root yaws and pitches.

const LIMB_Z := 0.08
const CAMERA_VIEW_HEIGHT := 2.05


static func habitations_path_for_night(night_path: String) -> String:
	const SUFFIX := "_night.png"
	if night_path.ends_with(SUFFIX):
		return night_path.trim_suffix(SUFFIX) + "_night_habitations.json"
	return ""


static func load_anchors(path: String) -> Array:
	if path.is_empty() or not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return anchors_from_data(parsed)


static func anchors_from_data(data: Variant) -> Array:
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var raw: Variant = data.get("anchors", [])
	if typeof(raw) != TYPE_ARRAY:
		return []
	var anchors: Array = []
	for item_variant in raw:
		if typeof(item_variant) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_variant
		var anchor_name := str(item.get("name", "")).strip_edges()
		if anchor_name.is_empty():
			continue
		var local_raw: Variant = item.get("local", [])
		if typeof(local_raw) != TYPE_ARRAY or local_raw.size() < 3:
			continue
		var local := Vector3(float(local_raw[0]), float(local_raw[1]), float(local_raw[2]))
		if local.length_squared() < 0.000001:
			continue
		anchors.append({
			"name": anchor_name,
			"local": local.normalized(),
		})
	return anchors


static func project_offset(local: Vector3, pitch: float, yaw: float, diameter: float) -> Variant:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)
	var facing := basis * local
	if facing.z <= LIMB_Z:
		return null
	var scale := diameter / CAMERA_VIEW_HEIGHT
	return Vector2(facing.x, -facing.y) * scale
