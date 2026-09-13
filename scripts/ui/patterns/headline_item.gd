extends VBoxContainer

var _headline: Label
var _meta: Label


func _bind_nodes() -> void:
	if _headline != null:
		return
	_headline = $Headline
	_meta = $Meta


func configure(title: String, meta: String = "") -> void:
	_bind_nodes()
	_headline.text = title
	if meta.is_empty():
		_meta.visible = false
		_meta.text = ""
	else:
		_meta.visible = true
		_meta.text = meta
