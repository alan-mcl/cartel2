class_name CharterBook
extends RefCounted

## One charter kind: its offer map, accepted contracts, and the next id.
## Passenger, scan, and bounty offers are habitat -> board -> rows.
## Freight offers are habitat -> rows (`flat_offers`).

var id_prefix: String = ""
var flat_offers: bool = false
var offers: Dictionary = {}
var accepted: Array = []
var next_id: int = 1


func _init(prefix: String = "", flat: bool = false) -> void:
	id_prefix = prefix
	flat_offers = flat


func reset() -> void:
	offers = {}
	accepted = []
	next_id = 1


func clear_offers() -> void:
	offers = {}


func has_habitat(habitat_id: String) -> bool:
	return offers.has(habitat_id)


func list_accepted() -> Array:
	return accepted.duplicate(true)


func list_board(habitat_id: String, board_key: String) -> Array:
	var habitat_boards: Variant = offers.get(habitat_id, {})
	if typeof(habitat_boards) != TYPE_DICTIONARY:
		return []
	var rows: Variant = habitat_boards.get(board_key, [])
	if typeof(rows) != TYPE_ARRAY:
		return []
	return rows.duplicate(true)


func list_flat(habitat_id: String) -> Array:
	var rows: Variant = offers.get(habitat_id, [])
	if typeof(rows) != TYPE_ARRAY:
		return []
	return rows.duplicate(true)


func find_offer(offer_id: String) -> Dictionary:
	if flat_offers:
		return _find_in_rows(offer_id)
	return _find_in_boards(offer_id)


func remove_offer(offer_id: String) -> void:
	if flat_offers:
		_remove_from_rows(offer_id)
	else:
		_remove_from_boards(offer_id)


func find_accepted(charter_id: String) -> Dictionary:
	for entry_variant in accepted:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("charter_id", "")) == charter_id:
			return entry
	return {}


func remove_accepted(charter_id: String) -> void:
	for index in accepted.size():
		var entry: Dictionary = accepted[index]
		if str(entry.get("charter_id", "")) == charter_id:
			accepted.remove_at(index)
			return


func allocate_id() -> String:
	var charter_id := "%s%d" % [id_prefix, next_id]
	next_id += 1
	return charter_id


func duplicate_offers() -> Dictionary:
	return offers.duplicate(true)


func duplicate_accepted() -> Array:
	return accepted.duplicate(true)


func load_state(offer_map: Variant, accepted_rows: Variant, id_value: Variant) -> void:
	offers = offer_map if typeof(offer_map) == TYPE_DICTIONARY else {}
	accepted = []
	if typeof(accepted_rows) == TYPE_ARRAY:
		for entry_variant in accepted_rows:
			if typeof(entry_variant) == TYPE_DICTIONARY:
				accepted.append(entry_variant)
	next_id = int(id_value)


func _find_in_boards(offer_id: String) -> Dictionary:
	for habitat_boards in offers.values():
		if typeof(habitat_boards) != TYPE_DICTIONARY:
			continue
		for board_key in habitat_boards.keys():
			var rows: Variant = habitat_boards[board_key]
			if typeof(rows) != TYPE_ARRAY:
				continue
			for offer_variant in rows:
				if typeof(offer_variant) != TYPE_DICTIONARY:
					continue
				var offer: Dictionary = offer_variant
				if str(offer.get("id", "")) == offer_id:
					return offer.duplicate(true)
	return {}


func _find_in_rows(offer_id: String) -> Dictionary:
	for habitat_id in offers.keys():
		var rows: Variant = offers[habitat_id]
		if typeof(rows) != TYPE_ARRAY:
			continue
		for offer_variant in rows:
			if typeof(offer_variant) != TYPE_DICTIONARY:
				continue
			var offer: Dictionary = offer_variant
			if str(offer.get("id", "")) == offer_id:
				return offer.duplicate(true)
	return {}


func _remove_from_boards(offer_id: String) -> void:
	for habitat_id in offers.keys():
		var habitat_boards: Variant = offers[habitat_id]
		if typeof(habitat_boards) != TYPE_DICTIONARY:
			continue
		for board_key in habitat_boards.keys():
			var rows: Variant = habitat_boards[board_key]
			if typeof(rows) != TYPE_ARRAY:
				continue
			var offer_rows: Array = rows
			for index in offer_rows.size():
				var offer: Dictionary = offer_rows[index]
				if str(offer.get("id", "")) == offer_id:
					offer_rows.remove_at(index)
					return


func _remove_from_rows(offer_id: String) -> void:
	for habitat_id in offers.keys():
		var rows: Variant = offers[habitat_id]
		if typeof(rows) != TYPE_ARRAY:
			continue
		var offer_rows: Array = rows
		for index in offer_rows.size():
			var offer: Dictionary = offer_rows[index]
			if str(offer.get("id", "")) == offer_id:
				offer_rows.remove_at(index)
				return
