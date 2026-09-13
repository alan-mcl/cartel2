class_name BuildingPanelRegistry
extends RefCounted

const MODE_STACK := "stack"
const MODE_EMBED := "embed"
const MODE_PLACEHOLDER := "placeholder"

const _STACK_SCENES: Dictionary = {
	"shipyard": preload("res://scenes/ui/shipyard_screen.tscn"),
}

const _EMBED_TYPES: Array[String] = [
	"terminal",
	"market",
	"ship_dealer",
	"chassis_dealer",
]


static func mode_for(building_type: String) -> String:
	if _STACK_SCENES.has(building_type):
		return MODE_STACK
	if building_type in _EMBED_TYPES:
		return MODE_EMBED
	return MODE_PLACEHOLDER


static func stack_scene(building_type: String) -> PackedScene:
	var scene: Variant = _STACK_SCENES.get(building_type, null)
	if scene is PackedScene:
		return scene
	return null


static func stack_scene_path(building_type: String) -> String:
	var scene := stack_scene(building_type)
	if scene == null:
		return ""
	return scene.resource_path


static func stack_building_types() -> Array:
	return _STACK_SCENES.keys()
