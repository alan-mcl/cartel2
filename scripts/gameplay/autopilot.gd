class_name Autopilot
extends RefCounted

enum Mode {
	MANUAL,
	TARGET_ALIGN,
	PURSUIT,
	PRECISION,
	MATCH_VELOCITY,
	HOLD_VELOCITY,
	ALIGN_VELOCITY,
	REVERSE_ALIGN,
	FULL_STOP,
}

const CAPABILITY_ID := "autopilot_basic"
const ROTATE_THRESHOLD := TrafficRouting.ROTATE_THRESHOLD
const PURSUIT_BRAKE_DISTANCE := 150.0
const ARRIVAL_DISTANCE := TrafficRouting.ARRIVAL_DISTANCE
const STOP_SPEED := 2.5
const MIN_VELOCITY_ALIGN := 3.0
const PRECISION_SPEED_FRACTION := 0.2
const TEMPORARY_ALIGN_THRESHOLD := ROTATE_THRESHOLD * 0.5

var mode: Mode = Mode.MANUAL
var _latched_world_velocity: Vector2 = Vector2.ZERO
var _latched_align_facing: float = 0.0
var _has_latched_align_facing: bool = false


static func has_capability(assembled: AssembledShip) -> bool:
	return assembled != null and assembled.has_capability(CAPABILITY_ID)


static func mode_from_hotkey(index: int) -> Mode:
	match index:
		1:
			return Mode.MANUAL
		2:
			return Mode.TARGET_ALIGN
		3:
			return Mode.PURSUIT
		4:
			return Mode.PRECISION
		5:
			return Mode.MATCH_VELOCITY
		6:
			return Mode.HOLD_VELOCITY
		7:
			return Mode.ALIGN_VELOCITY
		8:
			return Mode.REVERSE_ALIGN
		9:
			return Mode.FULL_STOP
		_:
			return Mode.MANUAL


static func mode_label(ap_mode: Mode) -> String:
	match ap_mode:
		Mode.MANUAL:
			return "Manual"
		Mode.TARGET_ALIGN:
			return "Target align"
		Mode.PURSUIT:
			return "Pursuit"
		Mode.PRECISION:
			return "Precision"
		Mode.MATCH_VELOCITY:
			return "Match velocity"
		Mode.HOLD_VELOCITY:
			return "Hold velocity"
		Mode.ALIGN_VELOCITY:
			return "Align velocity"
		Mode.REVERSE_ALIGN:
			return "Reverse align"
		Mode.FULL_STOP:
			return "Full stop"
		_:
			return "Manual"


static func precision_speed_cap(max_speed: float) -> float:
	return maxf(max_speed * PRECISION_SPEED_FRACTION, 0.0)


func reset_to_manual() -> void:
	mode = Mode.MANUAL
	_latched_world_velocity = Vector2.ZERO
	_has_latched_align_facing = false


func request_mode(
	requested: Mode,
	has_target: bool,
	ship_velocity: Vector2,
	has_capability: bool
) -> bool:
	if requested == Mode.MANUAL:
		if mode != Mode.MANUAL:
			reset_to_manual()
			return true
		return false
	if not has_capability:
		return false
	if _requires_target(requested) and not has_target:
		return false
	if requested == Mode.HOLD_VELOCITY:
		_latched_world_velocity = ship_velocity
	if requested == Mode.ALIGN_VELOCITY or requested == Mode.REVERSE_ALIGN:
		if ship_velocity.length() < MIN_VELOCITY_ALIGN:
			return false
		var bearing := ship_velocity.angle()
		_latched_align_facing = bearing + (PI if requested == Mode.REVERSE_ALIGN else 0.0)
		_has_latched_align_facing = true
	if mode != requested:
		mode = requested
		return true
	return false


func tick(
	ship_pos: Vector2,
	ship_facing: float,
	ship_velocity: Vector2,
	target_contact: Dictionary,
	stick: Dictionary,
	max_speed: float
) -> Dictionary:
	var previous_mode := mode
	if _requires_target(mode) and not has_target(target_contact):
		reset_to_manual()

	var result := {
		"physics": _stick_physics(stick),
		"precision_clamp": false,
		"mode_changed": mode != previous_mode,
		"snap_facing": null,
	}

	if mode == Mode.MANUAL:
		return result

	if _stick_overrides_mode(mode, stick):
		reset_to_manual()
		result["physics"] = _stick_physics(stick)
		result["mode_changed"] = previous_mode != Mode.MANUAL
		return result

	match mode:
		Mode.TARGET_ALIGN:
			if _stick_rotate(stick):
				reset_to_manual()
				result["physics"] = _stick_physics(stick)
				result["mode_changed"] = true
				return result
			var target_pos: Vector2 = target_contact.get("position", Vector2.ZERO)
			var rotate := _rotate_toward(ship_facing, (target_pos - ship_pos).angle())
			result["physics"] = _merge_stick_motion(stick, rotate, true)
		Mode.PURSUIT:
			result["physics"] = _tick_pursuit(ship_pos, ship_facing, ship_velocity, target_contact)
		Mode.PRECISION:
			result["physics"] = _stick_physics(stick)
			result["physics"]["boost"] = false
			result["precision_clamp"] = true
		Mode.MATCH_VELOCITY:
			var target_vel: Vector2 = target_contact.get("velocity", Vector2.ZERO)
			result["physics"] = _tick_velocity_match(ship_facing, ship_velocity, target_vel)
		Mode.HOLD_VELOCITY:
			result["physics"] = _tick_velocity_match(ship_facing, ship_velocity, _latched_world_velocity)
		Mode.ALIGN_VELOCITY, Mode.REVERSE_ALIGN:
			var align_result := _tick_temporary_align(ship_facing, ship_velocity)
			result["physics"] = align_result.get("physics", _idle_physics())
			if align_result.has("snap_facing"):
				result["snap_facing"] = align_result["snap_facing"]
			if mode == Mode.MANUAL:
				result["mode_changed"] = true
		Mode.FULL_STOP:
			result["physics"] = _tick_full_stop(ship_facing, ship_velocity)
			if mode == Mode.MANUAL:
				result["mode_changed"] = true

	if mode != previous_mode:
		result["mode_changed"] = true
	return result


static func _requires_target(ap_mode: Mode) -> bool:
	return (
		ap_mode == Mode.TARGET_ALIGN
		or ap_mode == Mode.PURSUIT
		or ap_mode == Mode.MATCH_VELOCITY
		or ap_mode == Mode.HOLD_VELOCITY
	)


static func has_target(contact: Dictionary) -> bool:
	return (
		not contact.is_empty()
		and str(contact.get("contact_kind", "")) == "traffic_npc"
	)


static func _stick_physics(stick: Dictionary) -> Dictionary:
	return {
		"thrust": bool(stick.get("thrust", false)),
		"reverse": bool(stick.get("reverse", false)),
		"rotate_left": bool(stick.get("rotate_left", false)),
		"rotate_right": bool(stick.get("rotate_right", false)),
		"boost": bool(stick.get("boost", false)),
	}


static func _stick_rotate(stick: Dictionary) -> bool:
	return bool(stick.get("rotate_left", false)) or bool(stick.get("rotate_right", false))


static func _stick_motion(stick: Dictionary) -> bool:
	return (
		bool(stick.get("thrust", false))
		or bool(stick.get("reverse", false))
		or _stick_rotate(stick)
	)


static func _stick_overrides_mode(ap_mode: Mode, stick: Dictionary) -> bool:
	match ap_mode:
		Mode.TARGET_ALIGN:
			return _stick_rotate(stick)
		Mode.PRECISION:
			return false
		_:
			return _stick_motion(stick)


static func _merge_stick_motion(stick: Dictionary, rotate: Dictionary, allow_boost: bool) -> Dictionary:
	return {
		"thrust": bool(stick.get("thrust", false)),
		"reverse": bool(stick.get("reverse", false)),
		"rotate_left": bool(rotate.get("rotate_left", false)),
		"rotate_right": bool(rotate.get("rotate_right", false)),
		"boost": bool(stick.get("boost", false)) and allow_boost,
	}


static func _rotate_toward(facing: float, desired: float) -> Dictionary:
	var delta := wrapf(desired - facing, -PI, PI)
	if delta > ROTATE_THRESHOLD:
		return {"rotate_left": false, "rotate_right": true}
	if delta < -ROTATE_THRESHOLD:
		return {"rotate_left": true, "rotate_right": false}
	return {"rotate_left": false, "rotate_right": false}


static func _aligned(facing: float, desired: float) -> bool:
	return absf(wrapf(desired - facing, -PI, PI)) <= ROTATE_THRESHOLD * 2.0


func _tick_pursuit(
	ship_pos: Vector2,
	ship_facing: float,
	ship_velocity: Vector2,
	target_contact: Dictionary
) -> Dictionary:
	var target_pos: Vector2 = target_contact.get("position", Vector2.ZERO)
	var to_target := target_pos - ship_pos
	var distance := to_target.length()
	var desired: float
	var thrust := false
	var reverse := false

	if distance <= PURSUIT_BRAKE_DISTANCE and ship_velocity.length() > STOP_SPEED:
		desired = ship_velocity.angle() + PI
		var rotate := _rotate_toward(ship_facing, desired)
		if _aligned(ship_facing, desired):
			thrust = true
		return {
			"thrust": thrust,
			"reverse": reverse,
			"rotate_left": bool(rotate.get("rotate_left", false)),
			"rotate_right": bool(rotate.get("rotate_right", false)),
			"boost": false,
		}

	desired = to_target.angle() if to_target.length_squared() > 1.0 else ship_facing
	var rotate_inputs := _rotate_toward(ship_facing, desired)
	if _aligned(ship_facing, desired) and distance > ARRIVAL_DISTANCE:
		thrust = true
	return {
		"thrust": thrust,
		"reverse": reverse,
		"rotate_left": bool(rotate_inputs.get("rotate_left", false)),
		"rotate_right": bool(rotate_inputs.get("rotate_right", false)),
		"boost": false,
	}


func _tick_velocity_match(ship_facing: float, ship_velocity: Vector2, desired_world_vel: Vector2) -> Dictionary:
	var delta_v := desired_world_vel - ship_velocity
	if delta_v.length() < STOP_SPEED:
		return _idle_physics()
	var desired := delta_v.angle()
	var rotate := _rotate_toward(ship_facing, desired)
	var thrust := _aligned(ship_facing, desired)
	return {
		"thrust": thrust,
		"reverse": false,
		"rotate_left": bool(rotate.get("rotate_left", false)),
		"rotate_right": bool(rotate.get("rotate_right", false)),
		"boost": false,
	}


func _tick_temporary_align(ship_facing: float, ship_velocity: Vector2) -> Dictionary:
	if not _has_latched_align_facing:
		reset_to_manual()
		return {"physics": _idle_physics()}
	if ship_velocity.length() < MIN_VELOCITY_ALIGN:
		reset_to_manual()
		return {"physics": _idle_physics()}
	var desired := _latched_align_facing
	var delta := wrapf(desired - ship_facing, -PI, PI)
	if absf(delta) <= TEMPORARY_ALIGN_THRESHOLD:
		reset_to_manual()
		return {
			"physics": _idle_physics(),
			"snap_facing": desired,
		}
	var rotate := _rotate_toward_threshold(ship_facing, desired, TEMPORARY_ALIGN_THRESHOLD)
	return {
		"physics": {
			"thrust": false,
			"reverse": false,
			"rotate_left": bool(rotate.get("rotate_left", false)),
			"rotate_right": bool(rotate.get("rotate_right", false)),
			"boost": false,
		},
	}


static func _rotate_toward_threshold(facing: float, desired: float, threshold: float) -> Dictionary:
	var delta := wrapf(desired - facing, -PI, PI)
	if delta > threshold:
		return {"rotate_left": false, "rotate_right": true}
	if delta < -threshold:
		return {"rotate_left": true, "rotate_right": false}
	return {"rotate_left": false, "rotate_right": false}


func _tick_full_stop(ship_facing: float, ship_velocity: Vector2) -> Dictionary:
	if ship_velocity.length() < STOP_SPEED:
		reset_to_manual()
		return _idle_physics()
	var desired := ship_velocity.angle() + PI
	var rotate := _rotate_toward(ship_facing, desired)
	var thrust := _aligned(ship_facing, desired)
	return {
		"thrust": thrust,
		"reverse": false,
		"rotate_left": bool(rotate.get("rotate_left", false)),
		"rotate_right": bool(rotate.get("rotate_right", false)),
		"boost": false,
	}


static func _idle_physics() -> Dictionary:
	return {
		"thrust": false,
		"reverse": false,
		"rotate_left": false,
		"rotate_right": false,
		"boost": false,
	}
