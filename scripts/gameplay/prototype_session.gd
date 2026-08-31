class_name PrototypeSession
extends RefCounted

signal changed

var location_name: String = "Proxima near orbit"
var credits: int = 3000
var objective: String = "Investigate the wreck near Beacon 3"
var last_log: String = "Flare-ON SS ready. Thrusters online."
var salvaged_wreck: bool = false
var inspected_ids: Array[String] = []


func inspect(definition: InteractableDef) -> String:
	if definition.id.is_empty():
		return ""

	if definition.id not in inspected_ids:
		inspected_ids.append(definition.id)

	last_log = definition.inspect_text
	changed.emit()
	return definition.inspect_text


func salvage(definition: InteractableDef) -> bool:
	if definition.kind != InteractableDef.Kind.SALVAGE:
		return false
	if salvaged_wreck:
		return false

	salvaged_wreck = true
	credits += definition.salvage_reward
	objective = "Continue exploring Proxima orbit"
	last_log = "Salvage secured from %s. +d%d credited." % [definition.title, definition.salvage_reward]
	changed.emit()
	return true
