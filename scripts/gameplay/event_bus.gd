class_name EventBus
extends RefCounted

## In-process pub/sub for typed gameplay events on [GameSession].

var _typed: Dictionary = {}
var _all: Array[Callable] = []


func publish(evt: Dictionary) -> void:
	if evt.is_empty():
		return
	var type := str(evt.get("type", ""))
	if type.is_empty():
		return

	var typed_list: Variant = _typed.get(type, null)
	if typed_list is Array:
		for listener in typed_list:
			var callable: Callable = listener
			if callable.is_valid():
				callable.call(evt)

	for listener in _all:
		if listener.is_valid():
			listener.call(evt)


func subscribe(type: String, listener: Callable) -> void:
	var event_type := str(type).strip_edges()
	if event_type.is_empty() or not listener.is_valid():
		return
	if not _typed.has(event_type):
		_typed[event_type] = []
	(_typed[event_type] as Array).append(listener)


func unsubscribe(type: String, listener: Callable) -> bool:
	var event_type := str(type).strip_edges()
	if event_type.is_empty() or not _typed.has(event_type):
		return false
	var listeners: Array = _typed[event_type]
	var index := listeners.find(listener)
	if index < 0:
		return false
	listeners.remove_at(index)
	if listeners.is_empty():
		_typed.erase(event_type)
	return true


func subscribe_all(listener: Callable) -> void:
	if not listener.is_valid():
		return
	if _all.has(listener):
		return
	_all.append(listener)


func unsubscribe_all(listener: Callable) -> bool:
	var index := _all.find(listener)
	if index < 0:
		return false
	_all.remove_at(index)
	return true
