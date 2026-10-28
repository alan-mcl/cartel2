extends CanvasLayer

signal jump_requested(target_sector_id: String, n: int, solution: int)
signal cancelled

@onready var _title: Label = $Background/Center/Panel/VBox/TitleLabel
@onready var _description: Label = $Background/Center/Panel/VBox/DescriptionLabel
@onready var _route_panel: RouteDatabasePanel = $Background/Center/Panel/VBox/RouteList
@onready var _solution_label: Label = $Background/Center/Panel/VBox/SolutionLabel
@onready var _confirm_button: Button = $Background/Center/Panel/VBox/ConfirmButton
@onready var _cancel_button: Button = $Background/Center/Panel/VBox/CancelButton
@onready var _hint: Label = $Background/Center/Panel/VBox/HintLabel

var _catalog: Catalog
var _session: GameSession
var _assembled_ship: AssembledShip
var _gate_title: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_route_panel.selection_changed.connect(_on_route_selection_changed)


func bind(catalog: Catalog, session: GameSession, assembled_ship: AssembledShip = null) -> void:
	_catalog = catalog
	_session = session
	_assembled_ship = assembled_ship
	_route_panel.bind(catalog, session)


func set_assembled_ship(assembled_ship: AssembledShip) -> void:
	_assembled_ship = assembled_ship


func open(gate_title: String) -> void:
	_gate_title = gate_title
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_route_panel.clear_selection()


func _refresh() -> void:
	_title.text = _gate_title
	_route_panel.clear_selection()

	if _catalog == null or _session == null:
		return

	var beacon_destination := _translation_beacon_destination()
	if beacon_destination.is_empty():
		_description.text = (
			"Higher N-space is faster but less accurate. Pick a destination and depth, then confirm."
		)
	else:
		var dest_label := TranslationNav.destination_display_label(_catalog, beacon_destination)
		_description.text = (
			"This translation beacon is tuned to %s. Only the public 4-space hop is available."
			% dest_label
		)

	var on_volatile_site := VolatileTranslation.is_volatile_sector_id(_session.sector_id)
	var all_offers: Array = []
	if on_volatile_site:
		all_offers = TranslationNav.list_volatile_site_offers(
			_session,
			_catalog,
			_session.sector_id,
			_assembled_ship
		)
		_description.text = (
			"Temporary return gate. Translate back before the gate collapses."
		)
	else:
		var library: Array = _session.player.translation_library if _session.player != null else []
		all_offers = TranslationNav.list_offered_translations(
			_catalog,
			_session.sector_id,
			_assembled_ship,
			library,
			_session
		)
	var offers := all_offers if on_volatile_site else _filter_beacon_offers(all_offers, beacon_destination)
	var partitioned := TranslationNav.partition_jump_offers(offers)
	var public_offers: Array = partitioned.get("public", [])
	var private_offers: Array = partitioned.get("private", [])
	var grouped := TranslationNav.group_offered_translations(_catalog, _session.sector_id, public_offers)
	var local_rows: Array = grouped.get("local", [])
	var other_rows: Array = grouped.get("other", [])
	var volatile_rows: Array = grouped.get("volatile", [])

	_route_panel.populate(local_rows, other_rows, volatile_rows, private_offers)

	_hint.text = "Esc or Cancel to stay in orbit"
	if (
		local_rows.is_empty()
		and other_rows.is_empty()
		and volatile_rows.is_empty()
		and private_offers.is_empty()
	):
		if on_volatile_site:
			_solution_label.text = "The temporary return gate is no longer available."
		elif beacon_destination.is_empty():
			_solution_label.text = "No translations available from this gate."
		else:
			_solution_label.text = "No public translation to the tuned destination."
		_confirm_button.disabled = true
		return

	_update_selection_ui()


func _filter_beacon_offers(all_offers: Array, beacon_destination: String) -> Array:
	if beacon_destination.is_empty():
		return all_offers
	var filtered: Array = []
	for offer_variant in all_offers:
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = offer_variant
		var translation: Dictionary = offer.get("translation", {})
		if int(translation.get("n", 0)) != 4:
			continue
		if str(translation.get("target", "")) != beacon_destination:
			continue
		filtered.append(offer)
	return filtered


func _on_route_selection_changed(_offer: Dictionary) -> void:
	_update_selection_ui()


func _update_selection_ui() -> void:
	var detail := RouteDatabasePanel.format_selection_detail(
		_catalog, _session, _route_panel.get_selected_offer()
	)
	_solution_label.text = str(detail.get("text", ""))
	_confirm_button.disabled = bool(detail.get("confirm_disabled", true))
	_confirm_button.text = str(detail.get("confirm_text", "Translate"))


func _on_confirm_pressed() -> void:
	var selected := _route_panel.get_selected_offer()
	if selected.is_empty():
		return
	var translation: Dictionary = selected.get("translation", {})
	var target_id := str(translation.get("target", ""))
	var n := int(translation.get("n", 4))
	var solution := int(translation.get("solution", 0))
	if target_id.is_empty():
		return
	jump_requested.emit(target_id, n, solution)


func _on_cancel_pressed() -> void:
	close()
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()


func _translation_beacon_destination() -> String:
	if _catalog == null or _session == null:
		return ""
	var world_data := _catalog.get_world(_session.sector_id)
	var beacon: Variant = world_data.get("translation_beacon", {})
	if typeof(beacon) != TYPE_DICTIONARY or beacon.is_empty():
		return ""
	return str(beacon.get("destination", ""))
