class_name WeaponHudStack
extends VBoxContainer

signal weapon_selected(slot_id: String)

const CHIT_SCENE := preload("res://scenes/ui/components/weapon_hud_chit.tscn")

var _signature: String = ""
var _chits_by_slot: Dictionary = {}


func rebuild_if_needed(
	assembled: AssembledShip,
	weapons: ShipWeapons,
	owned: OwnedShip
) -> void:
	var signature := _build_signature(assembled)
	if signature == _signature:
		return
	_signature = signature
	_clear_chits()
	if assembled == null or weapons == null:
		return
	var index := 0
	for entry in assembled.modules_in_category("weapon"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		if slot.is_empty():
			continue
		var module_def: ModuleDef = entry.get("data", null)
		var display_name := module_def.name if module_def != null else str(entry.get("module_id", slot))
		var hotkey := str(index + 1) if index < 9 else ""
		var chit: WeaponHudChit = CHIT_SCENE.instantiate()
		add_child(chit)
		chit.chit_pressed.connect(_on_chit_pressed)
		chit.configure(
			slot,
			display_name,
			hotkey,
			_format_ammo(module_def, owned),
			slot == weapons.selected_slot,
			_cooldown_fraction(weapons, module_def, slot)
		)
		_chits_by_slot[slot] = chit
		index += 1
	visible = index > 0


func refresh_states(assembled: AssembledShip, weapons: ShipWeapons, owned: OwnedShip) -> void:
	if _signature.is_empty() or weapons == null:
		return
	for entry in assembled.modules_in_category("weapon"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		var chit: WeaponHudChit = _chits_by_slot.get(slot, null)
		if chit == null:
			continue
		var module_def: ModuleDef = entry.get("data", null)
		chit.update_state(
			_format_ammo(module_def, owned),
			slot == weapons.selected_slot,
			_cooldown_fraction(weapons, module_def, slot)
		)


func _on_chit_pressed(slot_id: String) -> void:
	weapon_selected.emit(slot_id)


func _clear_chits() -> void:
	for child in get_children():
		child.queue_free()
	_chits_by_slot.clear()


func _build_signature(assembled: AssembledShip) -> String:
	if assembled == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for entry in assembled.modules_in_category("weapon"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		parts.append("%s:%s" % [str(entry.get("slot", "")), str(entry.get("module_id", ""))])
	return "|".join(parts)


static func _format_ammo(module_def: ModuleDef, owned: OwnedShip) -> String:
	if module_def == null:
		return "—"
	if module_def.ammunition_type.is_empty():
		return "—"
	if owned == null:
		return "0"
	return str(owned.get_ammo_count(module_def.ammunition_type))


static func _cooldown_fraction(
	weapons: ShipWeapons,
	module_def: ModuleDef,
	slot: String
) -> float:
	if weapons == null or module_def == null:
		return 0.0
	return weapons.cooldown_fraction(slot, ShipWeapons.fire_cycle_seconds(module_def))
