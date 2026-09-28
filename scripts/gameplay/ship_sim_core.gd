class_name ShipSimCore
extends RefCounted

enum StatsCadence { EVERY_FRAME, INTERVAL }

const STATS_REFRESH_INTERVAL := 15

var _catalog: Catalog
var _assembled: AssembledShip
var _owned: OwnedShip
var _motion: ShipMotion
var _operating_state: ShipOperatingState
var _weapons: ShipWeapons

var _mass_stats_dirty: bool = true
var _stats_refresh_counter: int = 0
var _last_mass_fuel: float = -1.0


func bind(
	catalog: Catalog,
	assembled: AssembledShip,
	owned: OwnedShip,
	motion: ShipMotion,
	operating_state: ShipOperatingState,
	weapons: ShipWeapons
) -> void:
	_catalog = catalog
	_assembled = assembled
	_owned = owned
	_motion = motion
	_operating_state = operating_state
	_weapons = weapons


func mark_stats_dirty() -> void:
	_mass_stats_dirty = true


func tick_shields(combat_state: ShipCombatState, delta: float) -> void:
	if _assembled == null or combat_state == null:
		return
	ShipCombat.tick_shields(combat_state, _assembled, delta)


func step_operating(
	delta: float,
	inputs: Dictionary,
	occupant_count: int,
	combat_state: ShipCombatState = null
) -> void:
	if _catalog == null or _assembled == null or _owned == null:
		return
	ShipOperations.tick_into(
		_operating_state,
		_catalog,
		_assembled,
		_owned,
		delta,
		inputs,
		occupant_count,
		combat_state
	)


func refresh_signature(delta: float) -> void:
	SensorSystem.tick_signature_glow(_operating_state, delta)


func refresh_stats(cadence: StatsCadence) -> bool:
	if _catalog == null or _owned == null or _assembled == null:
		return false

	if cadence == StatsCadence.EVERY_FRAME:
		_recompute_stats()
		return true

	if _owned != null and not is_equal_approx(_last_mass_fuel, _owned.fuel_current):
		_mass_stats_dirty = true
	_stats_refresh_counter += 1
	if not _mass_stats_dirty and _stats_refresh_counter < STATS_REFRESH_INTERVAL:
		return false

	_stats_refresh_counter = 0
	_mass_stats_dirty = false
	_recompute_stats()
	return true


func step_weapons(delta: float, firing: bool) -> Dictionary:
	if _catalog == null or _assembled == null or _owned == null or _weapons == null:
		return {"orders": [], "out_of_ammo": false, "ammo_changed": false}
	return _weapons.tick(
		_catalog,
		_assembled,
		_owned,
		delta,
		firing,
		_operating_state.weapons_allowed
	)


func step_physics(
	delta: float,
	inputs: Dictionary,
	use_full_thrust_authority: bool = false,
	environment_scale: float = 1.0
) -> void:
	if _assembled == null or _motion == null:
		return

	var thrust_factor := 1.0
	var boost_allowed := true
	if not use_full_thrust_authority:
		thrust_factor = _operating_state.thrust_factor
		boost_allowed = _operating_state.boost_allowed

	_motion.step(
		_assembled.stats,
		delta,
		bool(inputs.get("thrust", false)),
		bool(inputs.get("reverse", false)),
		bool(inputs.get("rotate_left", false)),
		bool(inputs.get("rotate_right", false)),
		bool(inputs.get("boost", false)),
		thrust_factor,
		boost_allowed,
		environment_scale
	)


func _recompute_stats() -> void:
	if _owned != null:
		_last_mass_fuel = _owned.fuel_current
	var loaded_mass := ShipAssembler.calculate_loaded_mass(_catalog, _owned, _assembled)
	_assembled.stats = ShipAssembler.derive_stats(_assembled, loaded_mass)
