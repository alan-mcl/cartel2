class_name LocationArtFactory
extends RefCounted

const SCENE := preload("res://scenes/ui/components/location_art.tscn")


static func create_banner(art_path: String, label: String = "") -> PanelContainer:
	var art: PanelContainer = SCENE.instantiate()
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.configure_header_mode(true)
	art.set_art_path(art_path, label)
	return art
