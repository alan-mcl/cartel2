extends VBoxContainer

var _label: Label
var _value: Label


func _bind_nodes() -> void:
	if _label != null:
		return
	_label = $Label
	_value = $Value


func configure(label_text: String, value_text: String) -> void:
	_bind_nodes()
	_label.text = label_text
	_value.text = value_text
