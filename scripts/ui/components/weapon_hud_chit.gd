class_name WeaponHudChit
extends PanelContainer

signal chit_pressed(slot_id: String)

var slot_id: String = ""
var _display_name: String = ""
var _hotkey_text: String = ""
var _ammo_text: String = ""
var _selected: bool = false
var _cooldown_fraction: float = 0.0

@onready var _icon: TextureRect = $VBox/HBox/Icon
@onready var _hotkey: Label = $VBox/HBox/Body/TopRow/HotkeyLabel
@onready var _name: Label = $VBox/HBox/Body/TopRow/NameLabel
@onready var _ammo: Label = $VBox/HBox/Body/AmmoLabel
@onready var _cooldown: ProgressBar = $VBox/CooldownBar


func configure(
	p_slot_id: String,
	display_name: String,
	hotkey_text: String,
	ammo_text: String,
	selected: bool,
	cooldown_fraction: float
) -> void:
	slot_id = p_slot_id
	_display_name = display_name
	_hotkey_text = hotkey_text
	_ammo_text = ammo_text
	_selected = selected
	_cooldown_fraction = cooldown_fraction
	if is_node_ready():
		_apply_visuals()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_set_children_mouse_ignore(self)
	if not slot_id.is_empty():
		_apply_visuals()


func _set_children_mouse_ignore(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_children_mouse_ignore(child)


func update_state(
	ammo_text: String,
	selected: bool,
	cooldown_fraction: float
) -> void:
	if not is_node_ready():
		return
	_ammo.text = ammo_text
	_cooldown.value = cooldown_fraction * 100.0
	_selected = selected
	_apply_panel_variation()


func _apply_visuals() -> void:
	ModuleIcons.configure_texture_rect(_icon, "weapon")
	_hotkey.text = _hotkey_text
	_name.text = _display_name
	update_state(_ammo_text, _selected, _cooldown_fraction)


func _apply_panel_variation() -> void:
	if _selected:
		theme_type_variation = &"WeaponHudChitSelected"
	else:
		theme_type_variation = &"WeaponHudChit"


func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		chit_pressed.emit(slot_id)
