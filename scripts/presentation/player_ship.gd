extends CharacterBody2D

signal interaction_target_changed(interactable: Interactable)
signal motion_changed(speed: float, heading_deg: float, boosting: bool)
signal operating_state_changed(state: ShipOperatingState)
signal weapon_selection_changed
signal autopilot_mode_changed(mode: int)

const THRUST_SPRITE := "res://assets/ships/fx/thrust.svg"
const ShipWeapons := preload("res://scripts/gameplay/ship_weapons.gd")
const ShipSimCoreScript := preload("res://scripts/gameplay/ship_sim_core.gd")
const ShipBreakup := preload("res://scripts/presentation/ship_breakup.gd")
const _WEAPON_MASK := 2 | 16 | 1

@export var ship_id: String = "flare_on_ss"

var assembled_ship: AssembledShip
var owned_ship: OwnedShip
var catalog: Catalog
var session: GameSession
var operating_state: ShipOperatingState = ShipOperatingState.new()
var motion := ShipMotion.new()
var weapons: ShipWeapons = ShipWeapons.new()
var _sim: ShipSimCore = ShipSimCoreScript.new()

@onready var _thrust_flame: Sprite2D = $Visual/ThrustFlame
@onready var _engine_exhaust: EngineExhaust = $Visual/EngineExhaust
@onready var _hull: Sprite2D = $Visual/Hull
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _interact_area: Area2D = $InteractSensor
@onready var _visual_root: Node2D = $Visual

var _defence_visual: CombatDefenceVisual
var _focused_interactables: Array[Interactable] = []
var _current_target: Interactable = null
var locked_target_id: String = ""
var _guidance_lock_position: Vector2 = Vector2.ZERO
var _guidance_lock_active: bool = false
var _autopilot := Autopilot.new()
var _autopilot_target: Dictionary = {}
var _hull_destroyed_fx_played := false
var _try_interact: Callable = Callable()
var _weapon_spawn_root: Node2D


func set_presentation_hooks(try_interact: Callable, weapon_spawn_root: Node2D) -> void:
	_try_interact = try_interact
	_weapon_spawn_root = weapon_spawn_root


func configure(
	ship: AssembledShip,
	owned: OwnedShip = null,
	game_catalog: Catalog = null,
	game_session: GameSession = null
) -> void:
	assembled_ship = ship
	owned_ship = owned
	catalog = game_catalog
	session = game_session
	weapons.reset()
	weapons.sync_selection(ship)
	_sim.bind(catalog, assembled_ship, owned_ship, motion, operating_state, weapons)
	_autopilot.reset_to_manual()
	_reset_destroyed_presentation()
	_apply_hull_visual()
	_sim.refresh_stats(ShipSimCore.StatsCadence.EVERY_FRAME)


func _apply_hull_visual() -> void:
	if _hull == null or assembled_ship == null or not assembled_ship.has_chassis():
		return

	var sprite_path := assembled_ship.chassis_sprite()
	if sprite_path.is_empty():
		push_error("Chassis '%s' is missing sprite path." % assembled_ship.chassis_id())
	else:
		ShipVisual.apply_hull(_hull, _thrust_flame, _collision_shape, sprite_path)
		ShipVisual.sync_engine_exhaust(_engine_exhaust, _thrust_flame, assembled_ship, sprite_path)

	_hull.modulate = Color.WHITE


func freeze_motion() -> void:
	velocity = Vector2.ZERO
	motion.velocity = Vector2.ZERO


func apply_launch_velocity(launch_velocity: Vector2, facing: float) -> void:
	motion.velocity = launch_velocity
	velocity = launch_velocity
	motion.facing = facing
	rotation = facing + PI / 2.0


func get_stats() -> ShipStats:
	if assembled_ship == null:
		return ShipStats.new()
	return assembled_ship.stats


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("player")
	var thrust_texture := load(THRUST_SPRITE) as Texture2D
	if _thrust_flame and thrust_texture:
		_thrust_flame.texture = thrust_texture

	_interact_area.area_entered.connect(_on_interact_area_entered)
	_interact_area.area_exited.connect(_on_interact_area_exited)

	for child in get_tree().get_nodes_in_group("interactable"):
		_register_interactable(child as Interactable)

	_defence_visual = CombatDefenceVisual.new()
	_defence_visual.z_index = 2
	_defence_visual.bind_owner(self)
	if _visual_root != null:
		_visual_root.add_child(_defence_visual)


func register_world_interactables() -> void:
	for node in get_tree().get_nodes_in_group("interactable"):
		_register_interactable(node as Interactable)


func _physics_process(delta: float) -> void:
	var stats := get_stats()
	if stats.max_speed <= 0.0:
		return

	var thrust := Input.is_action_pressed("thrust")
	var reverse := Input.is_action_pressed("reverse")
	var rotate_left := Input.is_action_pressed("rotate_left")
	var rotate_right := Input.is_action_pressed("rotate_right")
	var boost := Input.is_action_pressed("boost")
	var firing := _wants_to_fire()
	var stick := {
		"thrust": thrust,
		"reverse": reverse,
		"rotate_left": rotate_left,
		"rotate_right": rotate_right,
		"boost": boost,
	}
	var physics_inputs := stick.duplicate()
	var precision_clamp := false
	if Autopilot.has_capability(assembled_ship):
		var ap_result := _autopilot.tick(
			global_position,
			motion.facing,
			motion.velocity,
			_autopilot_target,
			stick,
			stats.max_speed
		)
		physics_inputs = ap_result.get("physics", stick)
		precision_clamp = bool(ap_result.get("precision_clamp", false))
		var snap_facing: Variant = ap_result.get("snap_facing", null)
		if snap_facing != null:
			motion.facing = float(snap_facing)
		if bool(ap_result.get("mode_changed", false)):
			autopilot_mode_changed.emit(_autopilot.mode)

	if session != null and catalog != null and owned_ship != null and assembled_ship != null:
		# Display-rate cadence: HUD ops telemetry and signature readout need every-frame updates.
		var combat_state := session.build_combat_state(assembled_ship)
		_sim.tick_shields(combat_state, delta)
		session.apply_combat_state(combat_state)
		if _defence_visual != null and assembled_ship != null:
			_defence_visual.bind_ship(assembled_ship, combat_state)

		var inputs := {
			"thrust": bool(physics_inputs.get("thrust", false)),
			"boost": bool(physics_inputs.get("boost", false)),
			"in_flight": not session.docked,
			"fire": firing,
			"active_weapon_slot": weapons.selected_slot if firing else "",
			"hyperdrive_spool": HyperdriveSolution.is_active(session),
		}
		if HyperdriveSolution.is_active(session):
			HyperdriveSolution.sustain_spool(
				catalog,
				session,
				assembled_ship,
				owned_ship,
				global_position,
				bool(physics_inputs.get("thrust", false)),
				bool(physics_inputs.get("boost", false))
			)
		_sim.step_operating(delta, inputs, 1, combat_state)
		_sim.refresh_signature(delta)
		_sim.refresh_stats(ShipSimCore.StatsCadence.EVERY_FRAME)
		_apply_hull_damage_visual(session.hull / maxf(session.max_hull, 1.0))
		_maybe_play_hull_destroyed()
		operating_state_changed.emit(operating_state)

		var weapon_result: Dictionary = _sim.step_weapons(delta, firing, _weapon_guidance_context())
		session.apply_player_flight_step(operating_state, physics_inputs, firing, weapon_result)
		var orders: Array = weapon_result.get("orders", [])
		if not orders.is_empty():
			_spawn_weapon_orders(orders)

	var environment_scale := 1.0
	if session != null and catalog != null:
		environment_scale = FieldConditions.thrust_scale_for_ship(
			catalog,
			session.world,
			global_position,
			assembled_ship
		)
	_sim.step_physics(delta, physics_inputs, false, environment_scale)
	if precision_clamp:
		var speed_cap := Autopilot.precision_speed_cap(stats.max_speed)
		if motion.velocity.length() > speed_cap:
			motion.velocity = motion.velocity.normalized() * speed_cap

	rotation = motion.facing + PI / 2.0
	velocity = motion.velocity
	move_and_slide()
	motion.velocity = velocity
	_report_slide_collisions()

	_update_thrust_visual(
		bool(physics_inputs.get("thrust", false)) or bool(physics_inputs.get("reverse", false))
	)
	motion_changed.emit(motion.get_speed(), rad_to_deg(motion.facing), motion.is_boosting())


func toggle_target_lock(contacts: Array) -> void:
	locked_target_id = TargetLock.toggle(
		locked_target_id, assembled_ship, contacts, global_position
	)


func cycle_target_lock(contacts: Array) -> void:
	locked_target_id = TargetLock.cycle_next(
		locked_target_id, assembled_ship, contacts, global_position
	)


func retain_target_lock(contacts: Array) -> void:
	locked_target_id = TargetLock.retain(
		locked_target_id, assembled_ship, contacts, global_position
	)


func clear_target_lock() -> void:
	locked_target_id = TargetLock.clear()
	_guidance_lock_active = false


func set_guidance_lock_contact(contact: Dictionary) -> void:
	_guidance_lock_active = not contact.is_empty()
	if _guidance_lock_active:
		_guidance_lock_position = contact.get("position", Vector2.ZERO)


func query_weapon_guidance(target_id: String) -> Dictionary:
	if locked_target_id != target_id or target_id.is_empty() or not _guidance_lock_active:
		return {"active": false}
	return {"active": true, "position": _guidance_lock_position}


func _weapon_guidance_context() -> Dictionary:
	return {
		"lock_active": _guidance_lock_active and not locked_target_id.is_empty(),
		"target_id": locked_target_id,
	}


func set_autopilot_target(contact: Dictionary) -> void:
	_autopilot_target = contact


func reset_autopilot() -> void:
	if _autopilot.mode == Autopilot.Mode.MANUAL:
		return
	_autopilot.reset_to_manual()
	autopilot_mode_changed.emit(_autopilot.mode)


func get_autopilot_mode() -> int:
	return _autopilot.mode


func request_autopilot_hotkey(index: int) -> void:
	var requested := Autopilot.mode_from_hotkey(index)
	if index == 1:
		if _autopilot.request_mode(Autopilot.Mode.MANUAL, false, motion.velocity, true):
			autopilot_mode_changed.emit(_autopilot.mode)
		return
	if not Autopilot.has_capability(assembled_ship):
		return
	var has_target := Autopilot.has_target(_autopilot_target)
	if _autopilot.request_mode(requested, has_target, motion.velocity, true):
		autopilot_mode_changed.emit(_autopilot.mode)


func select_weapon_slot(slot: String) -> void:
	if assembled_ship == null:
		return
	weapons.select_slot(slot)
	weapons.sync_selection(assembled_ship)
	weapon_selection_changed.emit()


func _input(event: InputEvent) -> void:
	if not _weapon_select_input_allowed():
		return
	if event.is_echo():
		return
	for i in range(9):
		if event.is_action_pressed("weapon_select_%d" % (i + 1), true):
			select_weapon_hotkey_index(i)
			get_viewport().set_input_as_handled()
			return


func _weapon_select_input_allowed() -> bool:
	return (
		session != null
		and not session.docked
		and not get_tree().paused
		and assembled_ship != null
	)


func select_weapon_hotkey_index(index: int) -> void:
	var slots := ShipWeapons.weapon_slot_order(assembled_ship)
	if index < 0 or index >= slots.size():
		return
	select_weapon_slot(slots[index])


func _wants_to_fire() -> bool:
	if not Input.is_action_pressed("fire"):
		return false
	if session == null or session.docked or get_tree().paused:
		return false
	# LMB is bound to fire; over a weapon chit it selects - block mouse-only fire, not Space.
	if _pointer_over_weapon_chit():
		var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		var space := Input.is_physical_key_pressed(KEY_SPACE)
		if lmb and not space:
			return false
	return true


func _pointer_over_weapon_chit() -> bool:
	var node: Node = get_viewport().gui_get_hovered_control()
	while node != null:
		if node is WeaponHudChit:
			return true
		node = node.get_parent()
	return false


func take_combat_hit(delivery_type: String, packets: Dictionary) -> Dictionary:
	if session == null or catalog == null or assembled_ship == null:
		return {}
	var result := session.apply_combat_hit(catalog, assembled_ship, delivery_type, packets)
	_apply_hull_damage_visual(session.hull / maxf(session.max_hull, 1.0))
	_maybe_play_hull_destroyed()
	if _defence_visual != null:
		var layers: Dictionary = result.get("defence_layers", {})
		_defence_visual.play_hit_layers(layers)
	return result


func take_weapon_hit(damage: float) -> void:
	take_combat_hit("ballistic", {"kinetic": damage})


func apply_weapon_impulse(delta_v: Vector2) -> void:
	motion.velocity += delta_v
	velocity = motion.velocity


func _apply_hull_damage_visual(health_ratio: float) -> void:
	if _hull == null or assembled_ship == null or not assembled_ship.has_chassis():
		return
	ShipVisual.apply_damage_tint(_hull, health_ratio)


func _reset_destroyed_presentation() -> void:
	_hull_destroyed_fx_played = false
	if _visual_root != null:
		_visual_root.visible = true
	if _collision_shape != null:
		_collision_shape.disabled = false


func _maybe_play_hull_destroyed() -> void:
	if session == null or session.max_hull <= 0.0:
		return
	if session.hull > 0.0:
		if _hull_destroyed_fx_played:
			_reset_destroyed_presentation()
		return
	if _hull_destroyed_fx_played:
		return
	_hull_destroyed_fx_played = true
	var tint := _hull.modulate if _hull != null else Color.WHITE
	if _weapon_spawn_root != null and is_instance_valid(_weapon_spawn_root):
		ShipBreakup.spawn(_weapon_spawn_root, global_position, motion.velocity, tint)
	if _visual_root != null:
		_visual_root.visible = false
	if _collision_shape != null:
		_collision_shape.disabled = true


func _spawn_weapon_orders(orders: Array) -> void:
	if _weapon_spawn_root == null or not is_instance_valid(_weapon_spawn_root) or assembled_ship == null:
		return
	ShipVisual.spawn_weapon_orders(
		_weapon_spawn_root,
		orders,
		global_position,
		motion.facing,
		motion.velocity,
		_WEAPON_MASK,
		[self],
		self,
		assembled_ship.chassis_sprite()
	)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _current_target and _current_target.can_interact() and _try_interact.is_valid():
			_try_interact.call(_current_target)


func get_current_target() -> Interactable:
	return _current_target


func _update_thrust_visual(active: bool) -> void:
	var thrusting := active and motion.is_thrusting()
	var strength := operating_state.thrust_factor if thrusting else 0.0
	if _thrust_flame:
		_thrust_flame.visible = false
	if _engine_exhaust:
		_engine_exhaust.set_thrusting(thrusting, strength)
	AudioService.set_ship_thrust(strength, motion.is_boosting(), global_position)


func _report_slide_collisions() -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision == null:
			continue
		AudioService.play_sfx_at("ship.collision", collision.get_position())
		return


func _on_interact_area_entered(area: Area2D) -> void:
	var interactable := area as Interactable
	if interactable and interactable not in _focused_interactables:
		_focused_interactables.append(interactable)
		_refresh_target()


func _on_interact_area_exited(area: Area2D) -> void:
	var interactable := area as Interactable
	if interactable and interactable in _focused_interactables:
		_focused_interactables.erase(interactable)
		_refresh_target()


func _on_interactable_focus_changed(interactable: Interactable, focused: bool) -> void:
	if focused:
		if interactable not in _focused_interactables:
			_focused_interactables.append(interactable)
	else:
		_focused_interactables.erase(interactable)
	_refresh_target()


func _refresh_target() -> void:
	var best: Interactable = null
	var best_distance := INF

	for interactable in _focused_interactables:
		if interactable == null or not interactable.can_interact():
			continue
		var distance := global_position.distance_squared_to(interactable.global_position)
		if distance < best_distance:
			best_distance = distance
			best = interactable

	if _current_target != best:
		_current_target = best
		interaction_target_changed.emit(_current_target)


func _register_interactable(interactable: Interactable) -> void:
	if interactable == null:
		return
	if not interactable.focus_changed.is_connected(_on_interactable_focus_changed):
		interactable.focus_changed.connect(_on_interactable_focus_changed)
