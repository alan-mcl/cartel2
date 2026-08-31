extends CharacterBody2D

signal interaction_target_changed(interactable: Interactable)
signal motion_changed(speed: float, heading_deg: float, boosting: bool)

const THRUST_SPRITE := "res://assets/ships/fx/thrust.svg"

@export var ship_id: String = "flare_on_ss"

var assembled_ship: AssembledShip
var motion := ShipMotion.new()

@onready var _thrust_flame: Sprite2D = $Visual/ThrustFlame
@onready var _hull: Sprite2D = $Visual/Hull
@onready var _interact_area: Area2D = $InteractSensor

var _focused_interactables: Array[Interactable] = []
var _current_target: Interactable = null


func configure(ship: AssembledShip) -> void:
	assembled_ship = ship
	_apply_hull_visual()


func _apply_hull_visual() -> void:
	if _hull == null or assembled_ship == null or assembled_ship.chassis.is_empty():
		return

	var sprite_path := str(assembled_ship.chassis.get("sprite", ""))
	if sprite_path.is_empty():
		push_error("Chassis '%s' is missing sprite path." % str(assembled_ship.chassis.get("id", "")))
	else:
		var texture := load(sprite_path) as Texture2D
		if texture == null:
			push_error("Failed to load chassis sprite: %s" % sprite_path)
		else:
			_hull.texture = texture

	var color_text := str(assembled_ship.chassis.get("hull_color", "#ffffff"))
	_hull.modulate = Color.html(color_text)


func freeze_motion() -> void:
	velocity = Vector2.ZERO
	motion.velocity = Vector2.ZERO


func get_stats() -> ShipStats:
	if assembled_ship == null:
		return ShipStats.new()
	return assembled_ship.stats


func _ready() -> void:
	add_to_group("player")

	var thrust_texture := load(THRUST_SPRITE) as Texture2D
	if _thrust_flame and thrust_texture:
		_thrust_flame.texture = thrust_texture

	_interact_area.area_entered.connect(_on_interact_area_entered)
	_interact_area.area_exited.connect(_on_interact_area_exited)

	for child in get_tree().get_nodes_in_group("interactable"):
		_register_interactable(child as Interactable)


func register_world_interactables() -> void:
	for node in get_tree().get_nodes_in_group("interactable"):
		_register_interactable(node as Interactable)


func _register_interactable(interactable: Interactable) -> void:
	if interactable == null:
		return
	if not interactable.focus_changed.is_connected(_on_interactable_focus_changed):
		interactable.focus_changed.connect(_on_interactable_focus_changed)


func _physics_process(delta: float) -> void:
	var stats := get_stats()
	if stats.max_speed <= 0.0:
		return

	var thrust := Input.is_action_pressed("thrust")
	var reverse := Input.is_action_pressed("reverse")
	var rotate_left := Input.is_action_pressed("rotate_left")
	var rotate_right := Input.is_action_pressed("rotate_right")
	var boost := Input.is_action_pressed("boost")

	motion.step(stats, delta, thrust, reverse, rotate_left, rotate_right, boost)

	rotation = motion.facing + PI / 2.0
	velocity = motion.velocity
	move_and_slide()

	_update_thrust_visual(thrust or reverse)
	motion_changed.emit(motion.get_speed(), rad_to_deg(motion.facing), motion.is_boosting())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _current_target and _current_target.can_interact():
			get_parent().try_interact(_current_target)


func get_current_target() -> Interactable:
	return _current_target


func _update_thrust_visual(active: bool) -> void:
	if _thrust_flame:
		_thrust_flame.visible = active and motion.is_thrusting()


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
