extends CanvasLayer

signal calculation_requested(target_sector_id: String, n: int)
signal calculation_cancel_requested
signal jump_requested(target_sector_id: String, n: int, solution: int)
signal cancelled

@onready var _title: Label = $Background/Center/Panel/VBox/TitleLabel
@onready var _description: Label = $Background/Center/Panel/VBox/DescriptionLabel
@onready var _main_tabs: TabContainer = $Background/Center/Panel/VBox/MainTabs
@onready var _route_panel: RouteDatabasePanel = $Background/Center/Panel/VBox/MainTabs/Routes/RoutePanel
@onready var _solution_label: Label = $Background/Center/Panel/VBox/MainTabs/Routes/SolutionLabel
@onready var _jump_button: Button = $Background/Center/Panel/VBox/MainTabs/Routes/JumpButton
@onready var _dest_tree: Tree = $Background/Center/Panel/VBox/MainTabs/Compute/DestTree
@onready var _depth_option: OptionButton = $Background/Center/Panel/VBox/MainTabs/Compute/DepthRow/DepthOption
@onready var _estimate: Label = $Background/Center/Panel/VBox/MainTabs/Compute/EstimateLabel
@onready var _compute_progress: ProgressBar = $Background/Center/Panel/VBox/MainTabs/Compute/ComputeProgress
@onready var _compute_status: Label = $Background/Center/Panel/VBox/MainTabs/Compute/ComputeStatus
@onready var _compute_button: Button = $Background/Center/Panel/VBox/MainTabs/Compute/ComputeButton
@onready var _cancel_calc_button: Button = $Background/Center/Panel/VBox/MainTabs/Compute/CancelCalcButton
@onready var _close_button: Button = $Background/Center/Panel/VBox/CloseButton

var _catalog: Catalog
var _session: GameSession
var _assembled_ship: AssembledShip
var _hyperdrive_module: ModuleDef
var _selected_target_id: String = ""
var _depth_values: Array[int] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_main_tabs.set_tab_title(0, "Routes")
	_main_tabs.set_tab_title(1, "Compute solution")
	_route_panel.selection_changed.connect(_on_route_selection_changed)
	_jump_button.pressed.connect(_on_jump_pressed)
	_compute_button.pressed.connect(_on_compute_pressed)
	_cancel_calc_button.pressed.connect(_on_cancel_calc_pressed)
	_close_button.pressed.connect(_on_close_pressed)
	_dest_tree.item_selected.connect(func() -> void: _refresh_compute_estimate())
	_depth_option.item_selected.connect(func(_idx: int) -> void: _refresh_compute_estimate())


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
	_route_panel.bind(catalog, session)


func set_assembled_ship(assembled_ship: AssembledShip) -> void:
	_assembled_ship = assembled_ship


func open(module_title: String) -> void:
	_title.text = module_title if not module_title.is_empty() else "Hyperdrive"
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_route_panel.clear_selection()
	_selected_target_id = ""


func refresh_if_visible() -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	if _catalog == null or _session == null:
		return
	_refresh_routes_tab()
	_refresh_compute_tab()


func _refresh_routes_tab() -> void:
	_route_panel.clear_selection()
	var library: Array = _session.player.translation_library if _session.player != null else []
	var all_offers := TranslationNav.list_offered_translations(
		_catalog,
		_session.sector_id,
		_assembled_ship,
		library,
		_session
	)
	var partitioned := TranslationNav.partition_jump_offers(all_offers)
	var grouped := TranslationNav.group_offered_translations(
		_catalog, _session.sector_id, partitioned.get("public", [])
	)
	_route_panel.populate(
		grouped.get("local", []),
		grouped.get("other", []),
		grouped.get("volatile", []),
		partitioned.get("private", [])
	)
	_update_route_selection_ui()


func _refresh_compute_tab() -> void:
	_build_destination_tree()
	_refresh_depth_options()
	if HyperdriveSolution.is_active(_session):
		_show_active_calculation()
	else:
		_hide_active_calculation()
		_refresh_compute_estimate()


func _show_active_calculation() -> void:
	var calc := _session.player.hyperdrive_calc
	var target := str(calc.get("target", ""))
	var n := int(calc.get("n", 4))
	var remaining := float(calc.get("remaining_seconds", 0.0))
	var total := float(calc.get("total_seconds", remaining))
	var progress := 0.0 if total <= 0.0 else clampf(1.0 - remaining / total, 0.0, 1.0)
	_compute_progress.visible = true
	_compute_progress.value = progress
	_compute_status.text = (
		"Computing %d-space solution to %s — %s GST remaining."
		% [
			n,
			TranslationNav.destination_display_label(_catalog, target),
			GalacticCalendar.format_duration(remaining),
		]
	)
	_compute_button.visible = false
	_compute_button.disabled = true
	_cancel_calc_button.visible = true
	_dest_tree.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_depth_option.disabled = true


func _hide_active_calculation() -> void:
	_compute_progress.visible = false
	_compute_status.text = ""
	_compute_button.visible = true
	_cancel_calc_button.visible = false
	_dest_tree.mouse_filter = Control.MOUSE_FILTER_STOP
	_depth_option.disabled = false


func _build_destination_tree() -> void:
	_dest_tree.clear()
	var root := _dest_tree.create_item()
	var source := _session.sector_id
	var rows := HyperdriveSolution.build_compute_spanning_tree(_catalog, source)
	var items_by_id: Dictionary = {source: root}
	var uncharted_root: TreeItem = null

	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		var target_id := str(row.get("target", ""))
		var parent_id := str(row.get("parent", ""))
		if target_id.is_empty():
			continue
		var parent_item: TreeItem
		if parent_id == "__uncharted__":
			if uncharted_root == null:
				uncharted_root = _dest_tree.create_item(root)
				uncharted_root.set_text(0, "Uncharted")
				uncharted_root.set_selectable(0, false)
			parent_item = uncharted_root
		else:
			parent_item = items_by_id.get(parent_id, root) as TreeItem
		var item := _dest_tree.create_item(parent_item)
		item.set_text(0, str(row.get("label", target_id)))
		item.set_metadata(0, target_id)
		items_by_id[target_id] = item

	if _selected_target_id.is_empty() and not rows.is_empty():
		var first: Dictionary = rows[0]
		_selected_target_id = str(first.get("target", ""))
	_select_tree_target(_selected_target_id)


func _select_tree_target(target_id: String) -> void:
	if target_id.is_empty():
		return
	var item := _dest_tree.get_root()
	item = _find_tree_item_by_metadata(item, target_id)
	if item != null:
		item.select(0)
		_selected_target_id = target_id


func _find_tree_item_by_metadata(item: TreeItem, target_id: String) -> TreeItem:
	if item == null:
		return null
	if item.get_metadata(0) == target_id:
		return item
	var child := item.get_first_child()
	while child != null:
		var found := _find_tree_item_by_metadata(child, target_id)
		if found != null:
			return found
		child = child.get_next()
	return null


func _refresh_depth_options() -> void:
	_depth_option.clear()
	_depth_values = []
	if _selected_target_id.is_empty() or _assembled_ship == null:
		return
	var available := HyperdriveSolution.list_available_compute_n(
		_session, _catalog, _assembled_ship, _session.sector_id, _selected_target_id
	)
	if available.is_empty():
		return
	_depth_values.append(HyperdriveSolution.BEST_N)
	_depth_option.add_item("Best N", 0)
	for n in available:
		_depth_values.append(n)
		_depth_option.add_item("%d-space" % n, _depth_values.size() - 1)
	_depth_option.select(0)


func _refresh_compute_estimate() -> void:
	if HyperdriveSolution.is_active(_session):
		return
	var selected := _dest_tree.get_selected()
	if selected != null:
		var meta: Variant = selected.get_metadata(0)
		if meta != null:
			_selected_target_id = str(meta)
	_refresh_depth_options()
	if _selected_target_id.is_empty() or _depth_values.is_empty() or _hyperdrive_module == null:
		_estimate.text = "Select a destination."
		_compute_button.disabled = true
		return
	var depth_index := _depth_option.selected
	if depth_index < 0:
		depth_index = 0
		_depth_option.select(depth_index)
	var requested_n := _depth_values[depth_index]
	var resolved_n := HyperdriveSolution.resolve_compute_n(
		_session, _catalog, _assembled_ship, _session.sector_id, _selected_target_id, requested_n
	)
	if resolved_n < 4:
		_estimate.text = "No remaining depth to compute for that destination."
		_compute_button.disabled = true
		return
	var friction := HyperdriveSolution.friction_for_compute(
		_catalog, _session.sector_id, _selected_target_id
	)
	var nav_rating := float(
		TranslationNav.nav_stats_from_ship(_assembled_ship, _catalog).get("nav_rating", 0.0)
	)
	var skill := HyperdriveSolution.solution_skill_for_module(_hyperdrive_module)
	var seconds := HyperdriveSolution.calculation_seconds(friction, resolved_n, nav_rating, skill)
	var chance := HyperdriveSolution.success_chance(nav_rating, skill, resolved_n) * 100.0
	var n_label := "Best N → %d-space" % resolved_n if requested_n == HyperdriveSolution.BEST_N else "%d-space" % resolved_n
	_estimate.text = (
		"%s · estimated GST %s · convergence ~%d%% (coil %d, nav %d)."
		% [
			n_label,
			GalacticCalendar.format_duration(seconds),
			int(round(chance)),
			int(round(skill)),
			int(round(nav_rating)),
		]
	)
	_compute_button.disabled = seconds <= 0.0


func _on_route_selection_changed(_offer: Dictionary) -> void:
	_update_route_selection_ui()


func _update_route_selection_ui() -> void:
	var detail := RouteDatabasePanel.format_selection_detail(
		_catalog, _session, _route_panel.get_selected_offer()
	)
	_solution_label.text = str(detail.get("text", ""))
	_jump_button.disabled = bool(detail.get("confirm_disabled", true))
	_jump_button.text = str(detail.get("confirm_text", "Translate"))


func _on_compute_pressed() -> void:
	if _selected_target_id.is_empty() or _depth_values.is_empty():
		return
	var depth_index := _depth_option.selected
	if depth_index < 0:
		return
	var n := _depth_values[depth_index]
	calculation_requested.emit(_selected_target_id, n)
	close()


func _on_cancel_calc_pressed() -> void:
	calculation_cancel_requested.emit()
	_refresh_compute_tab()


func _on_jump_pressed() -> void:
	var selected := _route_panel.get_selected_offer()
	if selected.is_empty():
		return
	var translation: Dictionary = selected.get("translation", {})
	var target := str(translation.get("target", ""))
	var n := int(translation.get("n", 4))
	var solution := int(translation.get("solution", 0))
	if target.is_empty() or solution == 0:
		return
	jump_requested.emit(target, n, solution)
	close()


func _on_close_pressed() -> void:
	cancelled.emit()
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()
