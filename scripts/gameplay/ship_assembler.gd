class_name ShipAssembler
extends RefCounted

const THRUST_SCALE := 1.25
const REVERSE_RATIO := 0.6153846153846154
const BOOST_SPEED_CAP := 980.0

const MANEUVER_ROTATION := {
	"low": 2.0,
	"medium": 2.6,
	"high": 3.2,
}

const MANEUVER_DAMP := {
	"low": 0.45,
	"medium": 0.40,
	"high": 0.35,
}


static func assemble(catalog: Catalog, ship_id: String) -> AssembledShip:
	var template := catalog.get_ship(ship_id)
	if template.is_empty():
		push_error("Cannot assemble unknown ship: %s" % ship_id)
		return AssembledShip.new()

	var assembled := AssembledShip.new()
	assembled.id = ship_id
	assembled.name = str(template.get("name", ship_id))
	assembled.maker = str(template.get("maker", ""))
	assembled.chassis = catalog.get_chassis(str(template.get("chassis", "")))
	assembled.engine = catalog.get_engine(str(template.get("engine", "")))

	var armour_id: Variant = template.get("armour")
	if armour_id != null and str(armour_id) != "" and str(armour_id) != "null":
		assembled.armour = catalog.get_armour(str(armour_id))

	var weapons: Variant = template.get("weapons", [])
	if typeof(weapons) == TYPE_ARRAY:
		assembled.weapons = weapons

	assembled.stats = _derive_stats(assembled)
	return assembled


static func assemble_owned(catalog: Catalog, owned: OwnedShip) -> AssembledShip:
	if owned == null or owned.id.is_empty():
		push_error("Cannot assemble invalid owned ship.")
		return AssembledShip.new()

	var template := catalog.get_ship(owned.template_id)
	var assembled := AssembledShip.new()
	assembled.id = owned.id
	assembled.name = owned.name
	assembled.maker = str(template.get("maker", ""))
	assembled.chassis = catalog.get_chassis(owned.chassis_id)
	assembled.engine = catalog.get_engine(owned.engine_id)

	if not owned.armour_id.is_empty():
		assembled.armour = catalog.get_armour(owned.armour_id)

	var weapons: Variant = template.get("weapons", [])
	if typeof(weapons) == TYPE_ARRAY:
		assembled.weapons = weapons

	assembled.stats = _derive_stats(assembled)
	return assembled


static func _derive_stats(ship: AssembledShip) -> ShipStats:
	var stats := ShipStats.new()

	if ship.chassis.is_empty() or ship.engine.is_empty():
		push_error("Ship '%s' is missing required chassis or engine." % ship.id)
		return stats

	var mass := (
		float(ship.chassis.get("mass", 0.0))
		+ float(ship.engine.get("mass", 0.0))
		+ float(ship.armour.get("mass", 0.0))
	)
	if mass <= 0.0:
		push_error("Ship '%s' has invalid mass." % ship.id)
		return stats

	var engine_thrust := float(ship.engine.get("thrust", 0.0))
	var max_speed := float(ship.engine.get("max_speed", 0.0))
	var boost_multiplier := float(ship.engine.get("boost_multiplier", 1.0))
	var maneuver := str(ship.chassis.get("maneuver", "medium"))

	stats.forward_thrust = engine_thrust / mass * THRUST_SCALE
	stats.reverse_thrust = stats.forward_thrust * REVERSE_RATIO
	stats.boost_multiplier = boost_multiplier
	stats.max_speed = max_speed
	stats.boost_max_speed = min(max_speed * boost_multiplier, BOOST_SPEED_CAP)
	stats.rotation_speed = float(MANEUVER_ROTATION.get(maneuver, MANEUVER_ROTATION["medium"]))
	stats.linear_damp = float(MANEUVER_DAMP.get(maneuver, MANEUVER_DAMP["medium"]))

	return stats
