extends Area2D
class_name Interactable

signal focus_changed(interactable: Interactable, focused: bool)

var definition: InteractableDef = null

var is_focused: bool = false
var is_consumed: bool = false

@onready var _prompt: Label = $Prompt
@onready var _ring: Node2D = $RangeRing


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update_prompt()


func get_title() -> String:
	return definition.title if definition != null else "Unknown"


func can_interact() -> bool:
	if definition == null or is_consumed:
		return false
	return true


func interact(session: PrototypeSession) -> String:
	if not can_interact() or session == null:
		return ""

	if definition.kind == InteractableDef.Kind.SALVAGE:
		if session.is_salvaged(definition.id):
			return session.inspect(definition)
		if session.salvage(definition):
			is_consumed = true
			_set_focused(false)
			_update_prompt()
			queue_redraw()
			return session.last_log

	return session.inspect(definition)


func mark_consumed() -> void:
	is_consumed = true
	_set_focused(false)
	_update_prompt()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_set_focused(true)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_set_focused(false)


func _set_focused(value: bool) -> void:
	if is_focused == value:
		return
	is_focused = value
	focus_changed.emit(self, value)
	_update_prompt()


func _update_prompt() -> void:
	if _prompt == null:
		return

	if is_consumed:
		_prompt.text = ""
	elif is_focused and definition != null:
		match definition.kind:
			InteractableDef.Kind.SALVAGE:
				_prompt.text = "[E] Salvage %s" % definition.title
			InteractableDef.Kind.DOCK:
				_prompt.text = "[E] Dock %s" % definition.title
			InteractableDef.Kind.TRANSLATE:
				_prompt.text = "[E] Translate via %s" % definition.title
			_:
				_prompt.text = "[E] Inspect %s" % definition.title
	else:
		_prompt.text = ""

	if _ring:
		_ring.visible = is_focused and not is_consumed
