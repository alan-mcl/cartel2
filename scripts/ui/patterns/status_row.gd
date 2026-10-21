extends HBoxContainer

var _key: Label
var _value: Label


func _bind_nodes() -> void:
	if _key != null:
		return
	_key = $Key
	_value = $Value


func configure(
	label_text: String,
	value_text: String,
	key_min_width: float = 120.0,
	wrap_value: bool = false,
	value_min_width: float = 0.0
) -> void:
	_bind_nodes()
	_key.text = "%s:" % label_text
	_key.custom_minimum_size.x = key_min_width
	_key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_value.text = value_text
	_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wrap_value:
		_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if value_min_width > 0.0:
			_value.custom_minimum_size.x = value_min_width
	else:
		_value.autowrap_mode = TextServer.AUTOWRAP_OFF
		_value.custom_minimum_size.x = 0.0
