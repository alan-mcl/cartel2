class_name CharterChit
extends RefCounted

## One tile on a charter board: row data plus per-row describe and act hooks.

var entry: Dictionary = {}
## (entry: Dictionary, ship_id: String) -> Dictionary
var describe: Callable = Callable()
## (entry: Dictionary, ship_id: String) -> bool
var act: Callable = Callable()


static func from_entry(
	entry: Dictionary,
	describe: Callable,
	act: Callable
) -> CharterChit:
	var chit := CharterChit.new()
	chit.entry = entry
	chit.describe = describe
	chit.act = act
	return chit


static func from_rows(rows: Array, describe_fn: Callable, act_fn: Callable) -> Array:
	var out: Array = []
	for entry_variant in rows:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		out.append(from_entry(entry_variant, describe_fn, act_fn))
	return out
