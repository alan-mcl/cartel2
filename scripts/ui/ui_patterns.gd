class_name UiPatterns
extends RefCounted

const STATUS_ROW := preload("res://scenes/ui/patterns/status_row.tscn")
const HEADLINE_ITEM := preload("res://scenes/ui/patterns/headline_item.tscn")
const METRIC_BLOCK := preload("res://scenes/ui/patterns/metric_block.tscn")


static func status_row(label_text: String, value_text: String, key_min_width: float = 120.0) -> Control:
	var row: Control = STATUS_ROW.instantiate()
	if row.has_method("configure"):
		row.configure(label_text, value_text, key_min_width)
	return row


static func headline_item(title: String, meta: String = "") -> Control:
	var item: Control = HEADLINE_ITEM.instantiate()
	if item.has_method("configure"):
		item.configure(title, meta)
	return item


static func metric_block(label_text: String, value_text: String) -> Control:
	var block: Control = METRIC_BLOCK.instantiate()
	if block.has_method("configure"):
		block.configure(label_text, value_text)
	return block
