class_name SimSubsystem
extends RefCounted

## Base contract for gameplay systems registered on [Simulation].
## GDScript has no interfaces; override only the hooks a subsystem needs.

var id: String = ""
var save_version: int = 1


func on_tick(_session: GameSession, _catalog: Catalog, _delta: float) -> void:
	pass


func on_hour(_session: GameSession, _catalog: Catalog, _hour: int) -> void:
	pass


func on_day(_session: GameSession, _catalog: Catalog, _day: int) -> void:
	pass


func on_event(_session: GameSession, _catalog: Catalog, _evt: Dictionary) -> void:
	pass


func migrate(data: Dictionary, from_version: int) -> Dictionary:
	return data.duplicate(true)


func to_dict() -> Dictionary:
	return {}


func from_dict(_data: Dictionary) -> void:
	pass
