class_name UiContext
extends RefCounted

var catalog: Catalog
var session: GameSession
var stack: ScreenStack
var on_ship_changed: Callable = Callable()
var on_undock_requested: Callable = Callable()
var on_save_requested: Callable = Callable()
var on_quit_to_menu_requested: Callable = Callable()
