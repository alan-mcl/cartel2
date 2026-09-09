extends CanvasLayer

signal confirmed(callsign: String, background_id: String, portrait_path: String)
signal cancelled

const PORTRAITS_DIR := "res://assets/ui/portraits/"
const PORTRAIT_EXTENSIONS := ["png", "webp", "jpg", "jpeg"]

@onready var _callsign_field: LineEdit = $Background/Center/Panel/VBox/BodySplit/Right/CallsignRow/CallsignField
@onready var _random_callsign_button: Button = $Background/Center/Panel/VBox/BodySplit/Right/CallsignRow/RandomCallsignButton
@onready var _portrait_preview: TextureRect = $Background/Center/Panel/VBox/BodySplit/Right/PortraitRow/PortraitPreview
@onready var _background_list: ItemList = $Background/Center/Panel/VBox/BodySplit/Left/BackgroundList
@onready var _detail_label: Label = $Background/Center/Panel/VBox/BodySplit/Center/DetailScroll/DetailLabel
@onready var _confirm_button: Button = $Background/Center/Panel/VBox/ConfirmButton

var _catalog: Catalog
var _background_ids: PackedStringArray = PackedStringArray()
var _selected_background_id: String = ""
var _portrait_paths: PackedStringArray = PackedStringArray()
var _portrait_index: int = -1
var _suppress_background_select: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_callsign_field.text_changed.connect(_on_field_changed)
	_background_list.item_selected.connect(_on_background_selected)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_random_callsign_button.pressed.connect(_on_random_callsign_pressed)
	$Background/Center/Panel/VBox/BackButton.pressed.connect(_on_back_pressed)
	$Background/Center/Panel/VBox/BodySplit/Right/PortraitRow/PrevPortrait.pressed.connect(_on_prev_portrait)
	$Background/Center/Panel/VBox/BodySplit/Right/PortraitRow/NextPortrait.pressed.connect(_on_next_portrait)


func bind(catalog: Catalog) -> void:
	_catalog = catalog


func open(default_callsign: String = "") -> void:
	visible = true
	_scan_portraits()
	_rebuild_background_list()
	_callsign_field.text = default_callsign
	_portrait_index = 0 if not _portrait_paths.is_empty() else -1
	_update_portrait_preview()
	_select_default_background()
	_on_field_changed("")


func close() -> void:
	visible = false


func _scan_portraits() -> void:
	_portrait_paths.clear()
	var dir := DirAccess.open(PORTRAITS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name != ".gitkeep":
			var ext := file_name.get_extension().to_lower()
			if ext in PORTRAIT_EXTENSIONS:
				_portrait_paths.append(PORTRAITS_DIR.path_join(file_name))
		file_name = dir.get_next()
	_portrait_paths.sort()


func _rebuild_background_list() -> void:
	_background_list.clear()
	_background_ids.clear()
	if _catalog == null:
		return

	for background in _catalog.list_backgrounds():
		if typeof(background) != TYPE_DICTIONARY:
			continue
		var background_id := str(background.get("id", ""))
		if background_id.is_empty():
			continue
		_background_ids.append(background_id)
		_background_list.add_item(str(background.get("name", background_id)))


func _select_default_background() -> void:
	if _catalog == null or _background_ids.is_empty():
		_selected_background_id = ""
		_update_background_detail()
		return

	var default_id := _catalog.get_default_background_id()
	var default_index := _background_ids.find(default_id)
	if default_index < 0:
		default_index = 0
	_selected_background_id = _background_ids[default_index]
	_suppress_background_select = true
	_background_list.select(default_index)
	_suppress_background_select = false
	_update_background_detail()
	_callsign_field.grab_focus()


func _update_background_detail() -> void:
	if _catalog == null or _selected_background_id.is_empty():
		_detail_label.text = ""
		return

	var kit := _catalog.get_background(_selected_background_id)
	if kit.is_empty():
		_detail_label.text = ""
		return

	var lines: PackedStringArray = PackedStringArray()
	lines.append(str(kit.get("description", "")))
	if not str(kit.get("background", "")).is_empty():
		lines.append("")
		lines.append(str(kit.get("background", "")))
	if not str(kit.get("starting_location", "")).is_empty():
		lines.append("")
		lines.append("Start: "+str(kit.get("starting_location", "")))
	if not str(kit.get("ship", "")).is_empty():
		lines.append("")
		lines.append("Ship: "+str(kit.get("ship", "")))
	if not str(kit.get("money", "")).is_empty():
		lines.append("")
		lines.append("Funds: "+str(kit.get("money", "")))
	_detail_label.text = "\n".join(lines)


func _update_portrait_preview() -> void:
	if _portrait_paths.is_empty():
		_portrait_preview.texture = null
		return

	if _portrait_index < 0 or _portrait_index >= _portrait_paths.size():
		_portrait_index = 0

	var path := _portrait_paths[_portrait_index]
	_portrait_preview.texture = load(path) as Texture2D


func _current_portrait_path() -> String:
	if _portrait_paths.is_empty() or _portrait_index < 0:
		return ""
	return _portrait_paths[_portrait_index]


func _on_field_changed(_text: String) -> void:
	var callsign := _callsign_field.text.strip_edges()
	_confirm_button.disabled = callsign.is_empty() or _selected_background_id.is_empty()


func _on_background_selected(index: int) -> void:
	if _suppress_background_select:
		return
	if index < 0 or index >= _background_ids.size():
		return
	_selected_background_id = _background_ids[index]
	_update_background_detail()
	_on_field_changed("")


func _on_random_callsign_pressed() -> void:
	if _catalog == null:
		return
	_callsign_field.text = TransponderBroadcast.generate_independent_callsign(
		_catalog.get_traffic_config()
	)
	if not _portrait_paths.is_empty():
		_portrait_index = randi() % _portrait_paths.size()
		_update_portrait_preview()
	_on_field_changed("")


func _on_prev_portrait() -> void:
	if _portrait_paths.is_empty():
		return
	_portrait_index = (_portrait_index - 1 + _portrait_paths.size()) % _portrait_paths.size()
	_update_portrait_preview()


func _on_next_portrait() -> void:
	if _portrait_paths.is_empty():
		return
	_portrait_index = (_portrait_index + 1) % _portrait_paths.size()
	_update_portrait_preview()


func _on_confirm_pressed() -> void:
	var callsign := _callsign_field.text.strip_edges()
	if callsign.is_empty() or _selected_background_id.is_empty():
		return
	confirmed.emit(callsign, _selected_background_id, _current_portrait_path())


func _on_back_pressed() -> void:
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		cancelled.emit()
		get_viewport().set_input_as_handled()
