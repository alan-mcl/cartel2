extends CanvasLayer

signal calculation_requested(target_sector_id: String, n: int)
signal jump_requested(target_sector_id: String, n: int, solution: int)
signal cancelled

@onready var _title: Label = $Background/Center/Panel/VBox/TitleLabel
@onready var _description: Label = $Background/Center/Panel/VBox/DescriptionLabel
@onready var _dest_option: OptionButton = $Background/Center/Panel/VBox/FormRow/DestOption
@onready var _depth_option: OptionButton = $Background/Center/Panel/VBox/FormRow/DepthOption
@onready var _estimate: Label = $Background/Center/Panel/VBox/EstimateLabel
@onready var _library_list: VBoxContainer = $Background/Center/Panel/VBox/LibraryScroll/LibraryList
@onready var _status: Label = $Background/Center/Panel/VBox/StatusLabel
@onready var _compute_button: Button = $Background/Center/Panel/VBox/ComputeButton
@onready var _jump_button: Button = $Background/Center/Panel/VBox/JumpButton
@onready var _cancel_button: Button = $Background/Center/Panel/VBox/CancelButton

var _catalog: Catalog
var _session: GameSession
var _assembled_ship: AssembledShip
var _hyperdrive_module: ModuleDef
var _destinations: Array = []
var _depth_values: Array[int] = []
var _selected_library: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_dest_option.item_selected.connect(func(_idx: int) -> void: _refresh_estimate())
	_depth_option.item_selected.connect(func(_idx: int) -> void: _refresh_estimate())
	_compute_button.pressed.connect(_on_compute_pressed)
	_jump_button.pressed.connect(_on_jump_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)


func bind(
	catalog: Catalog,
	session: GameSession,
	assembled_ship: AssembledShip,
	hyperdrive_module: ModuleDef
) -> void:
	_catalog = catalog
	_session = session
	_assembled_ship = assembled_ship
	_hyperdrive_module = hyperdrive_module


func set_assembled_ship(assembled_ship: AssembledShip) -> void:
	_assembled_ship = assembled_ship


func open(module_title: String) -> void:
	_title.text = module_title if not module_title.is_empty() else "Hyperdrive"
	_selected_library = {}
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_selected_library = {}


func _refresh() -> void:
	_clear_container(_library_list)
	_dest_option.clear()
	_depth_option.clear()
	_destinations = []
	_depth_values = []
	_compute_button.disabled = true
	_jump_button.disabled = true
	_status.text = ""

	if _catalog == null or _session == null:
		return

	if HyperdriveSolution.is_active(_session):
		var calc := _session.player.hyperdrive_calc
		_description.text = "Solution calculation in progress. Keep spool power and compute available."
		_status.text = (
			"Computing %d-space route to %s — %s GST remaining."
			% [
				int(calc.get("n", 4)),
				TranslationNav.destination_display_label(
					_catalog, str(calc.get("target", ""))
				),
				GalacticCalendar.format_duration(float(calc.get("remaining_seconds", 0.0))),
			]
		)
		_compute_button.disabled = true
		_jump_button.disabled = true
		return

	_description.text = (
		"Pick a destination on the public network and an N-space depth to compute a private solution. "
		+ "Or translate immediately using a stored library record."
	)

	_destinations = HyperdriveSolution.list_compute_destinations(_catalog, _session.sector_id)
	for index in _destinations.size():
		var row: Dictionary = _destinations[index]
		_dest_option.add_item(str(row.get("label", row.get("target", ""))), index)

	var nav_rating := float(
		TranslationNav.nav_stats_from_ship(_assembled_ship, _catalog).get("nav_rating", 0.0)
	)
	var max_n := TranslationNav.max_n_for_nav_rating(nav_rating)
	for n in range(4, max_n + 1):
		_depth_values.append(n)
		_depth_option.add_item("%d-space" % n, _depth_values.size() - 1)

	_refresh_estimate()
	_build_library_list()


func _refresh_estimate() -> void:
	if _destinations.is_empty() or _depth_values.is_empty() or _hyperdrive_module == null:
		_estimate.text = "No routable destinations from this system."
		_compute_button.disabled = true
		return
	var dest_index := _dest_option.selected
	if dest_index < 0:
		dest_index = 0
		_dest_option.select(dest_index)
	var depth_index := _depth_option.selected
	if depth_index < 0:
		depth_index = 0
		_depth_option.select(depth_index)
	var dest_row: Dictionary = _destinations[dest_index]
	var n := _depth_values[depth_index]
	var nav_rating := float(
		TranslationNav.nav_stats_from_ship(_assembled_ship, _catalog).get("nav_rating", 0.0)
	)
	var skill := HyperdriveSolution.solution_skill_for_module(_hyperdrive_module)
	var seconds := HyperdriveSolution.calculation_seconds(
		int(dest_row.get("friction", 0)), n, nav_rating, skill
	)
	var chance := HyperdriveSolution.success_chance(nav_rating, skill, n) * 100.0
	_estimate.text = (
		"Estimated GST cost %s · convergence chance ~%d%% (coil skill %d, nav %d)."
		% [
			GalacticCalendar.format_duration(seconds),
			int(round(chance)),
			int(round(skill)),
			int(round(nav_rating)),
		]
	)
	_compute_button.disabled = seconds <= 0.0


func _build_library_list() -> void:
	var library: Array = _session.player.translation_library if _session.player != null else []
	var offers := HyperdriveSolution.list_library_jump_offers(
		_catalog, _session.sector_id, _assembled_ship, library
	)
	if offers.is_empty():
		var empty := Label.new()
		empty.text = "No library translations from this system."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_library_list.add_child(empty)
		return
	for offer_variant in offers:
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = offer_variant
		var translation: Dictionary = offer.get("translation", {})
		var button := Button.new()
		button.toggle_mode = true
		var dest := TranslationNav.destination_display_label(
			_catalog, str(translation.get("target", ""))
		)
		var n := int(translation.get("n", 4))
		button.text = "%s · %d-space\n%s" % [
			dest,
			n,
			TranslationNav.format_cell_summary(
				float(offer.get("accuracy", 0.0)),
				float(offer.get("duration_seconds", 0.0)),
				translation
			),
		]
		button.pressed.connect(_on_library_pressed.bind(offer, button))
		_library_list.add_child(button)


func _on_library_pressed(offer: Dictionary, button: Button) -> void:
	for child in _library_list.get_children():
		if child is Button and child != button:
			(child as Button).button_pressed = false
	_selected_library = offer
	_jump_button.disabled = offer.is_empty()


func _on_compute_pressed() -> void:
	if _destinations.is_empty() or _depth_values.is_empty():
		return
	var dest_row: Dictionary = _destinations[_dest_option.selected]
	var n := _depth_values[_depth_option.selected]
	calculation_requested.emit(str(dest_row.get("target", "")), n)
	close()


func _on_jump_pressed() -> void:
	if _selected_library.is_empty():
		return
	var translation: Dictionary = _selected_library.get("translation", {})
	var target := str(translation.get("target", ""))
	var n := int(translation.get("n", 4))
	var solution := int(translation.get("solution", 0))
	if target.is_empty() or solution == 0:
		return
	jump_requested.emit(target, n, solution)
	close()


func _on_cancel_pressed() -> void:
	cancelled.emit()
	close()


static func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
