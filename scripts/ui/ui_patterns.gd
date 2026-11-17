class_name UiPatterns
extends RefCounted

const STATUS_ROW := preload("res://scenes/ui/patterns/status_row.tscn")
const HEADLINE_ITEM := preload("res://scenes/ui/patterns/headline_item.tscn")
const METRIC_BLOCK := preload("res://scenes/ui/patterns/metric_block.tscn")
const MESSAGE_BAR := preload("res://scenes/ui/patterns/message_bar.tscn")


static func status_row(
	label_text: String,
	value_text: String,
	key_min_width: float = 120.0,
	wrap_value: bool = false,
	value_min_width: float = 0.0
) -> Control:
	var row: Control = STATUS_ROW.instantiate()
	if row.has_method("configure"):
		row.configure(label_text, value_text, key_min_width, wrap_value, value_min_width)
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


static func message_bar() -> MessageBar:
	return MESSAGE_BAR.instantiate() as MessageBar


static func find_meta_host(root: Node, meta_name: String) -> VBoxContainer:
	return _find_meta_host_in(root, meta_name)


static func _find_meta_host_in(node: Node, meta_name: String) -> VBoxContainer:
	if node is VBoxContainer and node.has_meta(meta_name):
		return node as VBoxContainer
	for child in node.get_children():
		var found := _find_meta_host_in(child, meta_name)
		if found != null:
			return found
	return null


static func select_item_by_id(
	list: ItemList,
	ids: PackedStringArray,
	target_id: String,
	suppress_on: Callable = Callable(),
	suppress_off: Callable = Callable()
) -> void:
	if suppress_on.is_valid():
		suppress_on.call()
	var index := ids.find(target_id)
	if index >= 0:
		list.select(index)
	else:
		list.deselect_all()
	if suppress_off.is_valid():
		suppress_off.call()


static func refresh_soft_or_full(can_soft: Callable, soft: Callable, full: Callable) -> void:
	if can_soft.is_valid() and bool(can_soft.call()):
		if soft.is_valid():
			soft.call()
		return
	if full.is_valid():
		full.call()
