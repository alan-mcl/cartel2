class_name WeaponAttribution
extends RefCounted

## Snapshots session, catalog, and shooter id off a presentation shooter.
## Gameplay hit resolution reads the returned context and does not touch the node.


static func capture(shooter: Variant) -> WeaponHitContext:
	var context := WeaponHitContext.new()
	if shooter == null or not shooter is Object or not is_instance_valid(shooter):
		return context
	var session_value: Variant = shooter.get("session")
	if session_value is GameSession:
		context.session = session_value
		context.player_shot = true
	var catalog_value: Variant = shooter.get("catalog")
	if catalog_value is Catalog:
		context.catalog = catalog_value
	context.shooter_id = _shooter_id(shooter)
	return context


static func _shooter_id(shooter: Object) -> String:
	var owned: Variant = shooter.get("owned_ship")
	if owned is OwnedShip and not owned.id.is_empty():
		return owned.id
	var actor: Variant = shooter.get("actor")
	if actor != null:
		var actor_id := str(actor.get("id"))
		if not actor_id.is_empty():
			return actor_id
	var ship_id := str(shooter.get("ship_id"))
	if not ship_id.is_empty():
		return ship_id
	return ""
