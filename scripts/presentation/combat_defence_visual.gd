class_name CombatDefenceVisual
extends Node2D

const FLASH_DURATION := 0.35

var _assembled: AssembledShip
var _combat_state: ShipCombatState
var _flash_time := 0.0
var _flash_kind := ""
var _flash_shield_type := ""
var _hull_radius := 42.0


func bind_ship(assembled: AssembledShip, combat_state: ShipCombatState, hull_radius: float = 42.0) -> void:
	_assembled = assembled
	_combat_state = combat_state
	_hull_radius = hull_radius
	queue_redraw()


func play_hit_layers(layers: Dictionary) -> void:
	if layers.is_empty():
		return
	if bool(layers.get("point_defence_intercepted", false)):
		_start_flash("point_defence", "")
		return
	var shield_hits: Array = layers.get("shield_hits", [])
	if not shield_hits.is_empty():
		var hit: Dictionary = shield_hits[0]
		_start_flash("shield", str(hit.get("shield_type", "deflector")))
		return
	if float(layers.get("cyber_defence_absorbed", 0.0)) > 0.0:
		_start_flash("cyber_defence", "")
		return
	var armour: Dictionary = layers.get("armour_absorbed", {})
	if not armour.is_empty():
		_start_flash("armour", "")


func _start_flash(kind: String, shield_type: String) -> void:
	_flash_kind = kind
	_flash_shield_type = shield_type
	_flash_time = FLASH_DURATION
	queue_redraw()


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		queue_redraw()
	elif _assembled != null:
		queue_redraw()


static func style_for_shield_type(shield_type: String) -> Dictionary:
	match shield_type:
		"energy":
			return {
				"fill": Color(0.35, 0.75, 1.0, 0.12),
				"line": Color(0.45, 0.85, 1.0, 0.55),
				"segments": 32,
			}
		"electronic":
			return {
				"fill": Color(0.55, 0.35, 1.0, 0.08),
				"line": Color(0.65, 0.45, 1.0, 0.45),
				"segments": 6,
			}
		_:
			return {
				"fill": Color(0.55, 0.85, 1.0, 0.1),
				"line": Color(0.7, 0.95, 1.0, 0.5),
				"segments": 8,
			}


func _draw() -> void:
	if _assembled == null:
		return
	_draw_active_shields()
	_draw_flash()


func _draw_active_shields() -> void:
	if _combat_state == null:
		return
	for entry in _assembled.modules_in_category("shield"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: ModuleDef = entry.get("data", null)
		var slot := str(entry.get("slot", ""))
		if module_def == null or slot.is_empty():
			continue
		var capacity := module_def.shield_capacity
		if capacity <= 0.0:
			continue
		var charge := float(_combat_state.shield_charges.get(slot, capacity))
		if charge <= 0.01:
			continue
		var frac := charge / capacity
		var style := style_for_shield_type(module_def.shield_type)
		var radius := _hull_radius * (1.05 + 0.08 * (1.0 - frac))
		draw_circle(Vector2.ZERO, radius, style.get("fill", Color.WHITE))
		var segments: int = int(style.get("segments", 8))
		if segments <= 8:
			_draw_faceted_ring(radius, style.get("line", Color.WHITE), segments)
		else:
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, segments, style.get("line", Color.WHITE), 1.5)


func _draw_faceted_ring(radius: float, color: Color, segments: int) -> void:
	var points: PackedVector2Array = []
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2.from_angle(angle) * radius)
	points.append(points[0])
	draw_polyline(points, color, 1.5)


func _draw_flash() -> void:
	if _flash_time <= 0.0:
		return
	var alpha := _flash_time / FLASH_DURATION
	match _flash_kind:
		"point_defence":
			draw_arc(Vector2.ZERO, _hull_radius * 1.2, 0.0, TAU, 24, Color(1.0, 0.85, 0.35, 0.8 * alpha), 3.0)
		"shield":
			var style := style_for_shield_type(_flash_shield_type)
			draw_circle(Vector2.ZERO, _hull_radius * 1.15, Color(style.get("line", Color.WHITE), alpha * 0.35))
		"cyber_defence":
			draw_circle(Vector2.ZERO, _hull_radius * 1.05, Color(0.55, 0.25, 1.0, 0.25 * alpha))
		"armour":
			draw_arc(Vector2.ZERO, _hull_radius * 0.95, 0.0, TAU, 12, Color(0.75, 0.75, 0.8, 0.6 * alpha), 2.0)
