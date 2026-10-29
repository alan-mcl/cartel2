class_name YardModuleTape
extends RefCounted

var _lines: PackedStringArray = PackedStringArray()
var _next_index: int = 0


func reset(catalog: Catalog) -> void:
	_lines.clear()
	_next_index = 0
	if catalog == null:
		return
	var entries: Array = []
	for part_entry in ShipAssembly.list_yard_parts(catalog):
		if typeof(part_entry) != TYPE_DICTIONARY:
			continue
		entries.append(part_entry)
	entries.shuffle()
	for part_entry in entries:
		var part_id := str(part_entry.get("id", ""))
		var data: Dictionary = part_entry.get("data", {})
		var name := str(data.get("name", part_id))
		if name.is_empty():
			continue
		var cost := int(data.get("cost", 0))
		_lines.append("%s - d%d" % [name, cost])


func next_line() -> String:
	if _lines.is_empty():
		return ""
	var line := _lines[_next_index % _lines.size()]
	_next_index += 1
	return line
