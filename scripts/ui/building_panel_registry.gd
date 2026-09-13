class_name BuildingPanelRegistry
extends RefCounted

const MODE_STACK := "stack"
const MODE_EMBED := "embed"
const MODE_PLACEHOLDER := "placeholder"

const _EMBED_SCENES: Dictionary = {
	"terminal": preload("res://scenes/ui/terminal_panel.tscn"),
	"market": preload("res://scenes/ui/market_panel.tscn"),
	"ship_dealer": preload("res://scenes/ui/dealer_panel.tscn"),
	"chassis_dealer": preload("res://scenes/ui/dealer_panel.tscn"),
	"shipyard": preload("res://scenes/ui/shipyard_screen.tscn"),
}

const _EMBED_TYPES: Array[String] = [
	"terminal",
	"market",
	"ship_dealer",
	"chassis_dealer",
	"shipyard",
]


static func mode_for(building_type: String) -> String:
	if building_type in _EMBED_TYPES:
		return MODE_EMBED
	return MODE_PLACEHOLDER


static func embed_scene(building_type: String) -> PackedScene:
	var scene: Variant = _EMBED_SCENES.get(building_type, null)
	if scene is PackedScene:
		return scene
	return null


static func embed_scene_path(building_type: String) -> String:
	var scene := embed_scene(building_type)
	if scene == null:
		return ""
	return scene.resource_path
