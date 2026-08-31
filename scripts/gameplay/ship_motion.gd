class_name ShipMotion
extends RefCounted

var velocity: Vector2 = Vector2.ZERO
var facing: float = -PI / 2.0

var _thrusting: bool = false
var _reversing: bool = false
var _boosting: bool = false


func step(
	stats: ShipStats,
	delta: float,
	thrust: bool,
	reverse: bool,
	rotate_left: bool,
	rotate_right: bool,
	boost: bool
) -> void:
	_thrusting = thrust
	_reversing = reverse
	_boosting = boost and thrust

	var rotate_input := float(rotate_right) - float(rotate_left)
	facing += rotate_input * stats.rotation_speed * delta

	var forward := Vector2.from_angle(facing)
	var thrust_force := 0.0

	if thrust:
		thrust_force = stats.forward_thrust
		if _boosting:
			thrust_force *= stats.boost_multiplier
	elif reverse:
		thrust_force = -stats.reverse_thrust

	velocity += forward * thrust_force * delta

	var damp := exp(-stats.linear_damp * delta)
	velocity *= damp

	var speed_cap := stats.boost_max_speed if _boosting else stats.max_speed
	if velocity.length() > speed_cap:
		velocity = velocity.normalized() * speed_cap


func get_speed() -> float:
	return velocity.length()


func is_boosting() -> bool:
	return _boosting


func is_thrusting() -> bool:
	return _thrusting or _reversing
