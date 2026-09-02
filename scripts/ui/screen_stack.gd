class_name ScreenStack
extends Control

signal screen_pushed(screen: Control)
signal screen_popped(screen: Control)

var _screens: Array[Control] = []


func push_screen(screen: Control) -> void:
	if screen.get_parent() != self:
		add_child(screen)
	screen.visible = true
	_screens.append(screen)
	screen_pushed.emit(screen)


func pop_screen() -> Control:
	if _screens.is_empty():
		return null
	var screen: Control = _screens.pop_back()
	screen.visible = false
	screen_popped.emit(screen)
	if not _screens.is_empty():
		_screens.back().visible = true
	return screen


func replace_screen(screen: Control) -> void:
	for existing in _screens:
		existing.visible = false
	_screens.clear()
	push_screen(screen)


func get_depth() -> int:
	return _screens.size()


func get_top_screen() -> Control:
	if _screens.is_empty():
		return null
	return _screens.back()


func clear() -> void:
	for screen in _screens:
		screen.visible = false
	_screens.clear()
