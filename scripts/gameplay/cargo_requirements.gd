class_name CargoRequirements
extends RefCounted

const CAPABILITY_LABELS := {
	"life_support_integrated": "live cargo",
	"refrigerated": "refrigerated",
	"compute_integrated": "compute-integrated",
	"biohazard": "biohazard",
	"secure_cargo": "secure / bonded",
	"military_grade": "military grade",
}


static func required_capabilities(commodity: Dictionary) -> Array:
	var caps: Variant = commodity.get("requires_capabilities", [])
	if typeof(caps) != TYPE_ARRAY:
		return []
	var out: Array = []
	for cap_variant in caps:
		var cap_id := str(cap_variant)
		if not cap_id.is_empty():
			out.append(cap_id)
	return out


static func assembled_meets_commodity(assembled: AssembledShip, commodity: CommodityDef) -> bool:
	if commodity == null:
		return false
	for cap_id in commodity.requires_capabilities:
		var cap := str(cap_id).strip_edges()
		if cap.is_empty():
			continue
		if not assembled.has_capability(cap):
			return false
	return true


static func requirement_label(cap_id: String) -> String:
	return str(CAPABILITY_LABELS.get(cap_id, cap_id))


static func commodity_requirement_phrase(commodity: Dictionary) -> String:
	var caps := required_capabilities(commodity)
	if caps.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for cap_id in caps:
		parts.append(requirement_label(str(cap_id)))
	return ", ".join(parts)


static func cannot_carry_reason(
	catalog: Catalog,
	assembled: AssembledShip,
	commodity: CommodityDef
) -> String:
	if commodity == null:
		return ""
	if commodity.requires_capabilities.is_empty():
		return ""
	for cap_id in commodity.requires_capabilities:
		var cap := str(cap_id).strip_edges()
		if cap.is_empty():
			continue
		if not assembled.has_capability(cap):
			var label := commodity.id
			if commodity.has_source_key("name"):
				label = commodity.name
			return (
				"Need a %s hold to carry %s."
				% [requirement_label(cap), label]
			)
	return ""


static func cargo_aboard_violation_reason(catalog: Catalog, ship: OwnedShip) -> String:
	if ship == null:
		return ""
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	for commodity_id_variant in ship.cargo.keys():
		var commodity_id := str(commodity_id_variant)
		if ship.get_cargo_count(commodity_id) <= 0:
			continue
		var commodity := catalog.get_commodity_def(commodity_id)
		if commodity == null:
			continue
		var reason := cannot_carry_reason(catalog, assembled, commodity)
		if not reason.is_empty():
			var aboard_name := commodity_id
			if commodity.has_source_key("name"):
				aboard_name = commodity.name
			return (
				"Cannot change cargo bays: %s is still aboard."
				% aboard_name
			)
	return ""
