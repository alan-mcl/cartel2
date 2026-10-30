class_name SkyParentBodyParams
extends RefCounted

const APPEARANCE_BANDED := "banded"
const RING_NONE := "none"
const RING_SMALL := "small"
const RING_BROAD := "broad"


static func body_type_label(body_type_id: String) -> String:
	var id := body_type_id.strip_edges()
	if id.is_empty():
		return "Parent planet"
	var spaced := id.replace("_", " ")
	if spaced.is_empty():
		return "Parent planet"
	return spaced.substr(0, 1).to_upper() + spaced.substr(1).to_lower()


static func hex_tint_to_vec3(hex: String) -> Vector3:
	var colour := Color(str(hex))
	return Vector3(colour.r, colour.g, colour.b)


static func resolve_from_parent(parent_data: Dictionary) -> Dictionary:
	if parent_data.is_empty():
		return {}
	var appearance_raw: Variant = parent_data.get("appearance", {})
	var rings_raw: Variant = parent_data.get("rings", {})
	if typeof(appearance_raw) != TYPE_DICTIONARY or typeof(rings_raw) != TYPE_DICTIONARY:
		return {}
	var appearance: Dictionary = appearance_raw
	var rings: Dictionary = rings_raw
	if str(appearance.get("type", "")).strip_edges() != APPEARANCE_BANDED:
		return {}
	var ring_render := _resolve_ring(rings)
	if ring_render.is_empty():
		return {}
	return {
		"type_label": body_type_label(str(parent_data.get("type", ""))),
		"appearance": appearance,
		"ring": ring_render,
	}


static func ring_outer_scale(ring_render: Dictionary) -> float:
	return float(ring_render.get("outer_scale", 1.0))


static func _resolve_ring(rings: Dictionary) -> Dictionary:
	var ring_type := str(rings.get("type", "")).strip_edges()
	match ring_type:
		RING_NONE:
			return {"type": RING_NONE, "outer_scale": 1.0, "colour": "#ffffff"}
		RING_SMALL, RING_BROAD:
			return {
				"type": ring_type,
				"outer_scale": float(rings.get("outer_scale", 1.0)),
				"colour": str(rings.get("colour", "#ffffff")),
			}
		_:
			return {}
