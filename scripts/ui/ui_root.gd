extends CanvasLayer

@onready var _root: Control = $Root
@onready var _stack: ScreenStack = $Root/Stack

var catalog: Catalog
var session: GameSession
var simulation: Simulation
var context := UiContext.new()

var on_ship_changed: Callable = Callable()
var on_undock_requested: Callable = Callable()
var on_save_requested: Callable = Callable()
var on_quit_to_menu_requested: Callable = Callable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func configure(
	p_catalog: Catalog,
	p_session: GameSession,
	p_simulation: Simulation,
	ship_changed: Callable,
	undock: Callable,
	save: Callable,
	quit_menu: Callable
) -> void:
	catalog = p_catalog
	session = p_session
	simulation = p_simulation
	on_ship_changed = ship_changed
	on_undock_requested = undock
	on_save_requested = save
	on_quit_to_menu_requested = quit_menu

	context.catalog = catalog
	context.session = session
	context.simulation = p_simulation
	context.stack = _stack
	context.on_ship_changed = on_ship_changed
	context.on_save_requested = on_save_requested
	context.on_quit_to_menu_requested = on_quit_to_menu_requested
	context.on_undock_requested = on_undock_requested


func open_habitat() -> void:
	if session == null or catalog == null:
		return
	context.session = session
	context.catalog = catalog
	context.simulation = simulation
	var habitat_screen := preload("res://scenes/ui/habitat_screen.tscn").instantiate()
	_stack.replace_screen(habitat_screen)
	habitat_screen.bind(context)
	visible = true


func close_ui() -> void:
	_stack.clear()
	for child in _stack.get_children():
		child.queue_free()
	visible = false


func handle_back() -> bool:
	if not visible:
		return false
	var top := _stack.get_top_screen()
	if top != null and top.has_method("handle_back"):
		return bool(top.call("handle_back"))
	if _stack.get_depth() > 1:
		_stack.pop_screen()
		return true
	return false
