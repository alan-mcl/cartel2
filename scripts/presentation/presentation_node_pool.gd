class_name PresentationNodePool
extends RefCounted

var _packed: PackedScene
var _available: Array[Node] = []
var _max_size: int = 32


func setup(packed: PackedScene, max_size: int = 32) -> void:
	_packed = packed
	_max_size = maxi(max_size, 1)


func acquire(parent: Node) -> Node:
	while not _available.is_empty():
		var node: Node = _available.pop_back()
		if is_instance_valid(node):
			if node.get_parent() != parent:
				parent.add_child(node)
			node.visible = true
			return node
	if _packed == null:
		return null
	var created := _packed.instantiate()
	if created != null and parent != null:
		parent.add_child(created)
	return created


func release(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _available.size() >= _max_size:
		node.queue_free()
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.visible = false
	_available.append(node)


func clear() -> void:
	for node in _available:
		if is_instance_valid(node):
			node.queue_free()
	_available.clear()
