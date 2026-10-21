extends Control

const REFRESH_INTERVAL_SEC := 1.0
const ROW_VALUE_WRAP_WIDTH := 340.0

@onready var _title: Label = $Center/Panel/VBox/Title
@onready var _rows_scroll: ScrollContainer = $Center/Panel/VBox/RowsScroll
@onready var _rows_list: VBoxContainer = $Center/Panel/VBox/RowsScroll/RowsList

var _session: GameSession
var _catalog: Catalog
var _locked_contact: Dictionary = {}
var _observer_pos: Vector2 = Vector2.ZERO
var _beacon_destination: String = ""
var _refresh_accum := 0.0


func _ready() -> void:
	visible = false
	set_process(false)
	var panel := get_node_or_null("Center/Panel") as Control
	if panel != null:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if _title != null:
		_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _rows_scroll != null:
		_rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func bind(session: GameSession, catalog: Catalog) -> void:
	_session = session
	_catalog = catalog


func is_open() -> bool:
	return visible


func open(
	locked_contact: Dictionary,
	observer_pos: Vector2,
	beacon_destination: String = ""
) -> void:
	if _session == null or _catalog == null or locked_contact.is_empty():
		return
	_locked_contact = locked_contact
	_observer_pos = observer_pos
	_beacon_destination = beacon_destination
	visible = true
	_refresh_accum = 0.0
	_refresh_content()
	set_process(true)


func close() -> bool:
	if not visible:
		return false
	visible = false
	_locked_contact = {}
	set_process(false)
	return true


func refresh_if_open(locked_contact: Dictionary, observer_pos: Vector2) -> void:
	if not visible:
		return
	if locked_contact.is_empty() or str(locked_contact.get("id", "")) != str(_locked_contact.get("id", "")):
		close()
		return
	_locked_contact = locked_contact
	_observer_pos = observer_pos
	if _refresh_accum >= REFRESH_INTERVAL_SEC:
		_refresh_accum = 0.0
		_refresh_content()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL_SEC:
		_refresh_accum = 0.0
		_refresh_content()


func _refresh_content() -> void:
	var snapshot := TargetScan.build(
		_session,
		_catalog,
		_locked_contact,
		_observer_pos,
		_beacon_destination
	)
	_title.text = str(snapshot.get("title", "Target"))
	_clear_children(_rows_list)
	var rows: Array = snapshot.get("rows", []) as Array
	if rows.is_empty():
		_rows_list.add_child(_muted_label("No scan data"))
		return
	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		_rows_list.add_child(
			UiPatterns.status_row(
				str(row.get("label", "")),
				str(row.get("value", "")),
				120.0,
				true,
				ROW_VALUE_WRAP_WIDTH
			)
		)


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Muted"
	label.text = text
	return label
