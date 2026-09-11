class_name ShipOperatingState
extends RefCounted

var power_available: float = 0.0
var power_requested: float = 0.0
var power_allocated: float = 0.0
var power_deficit: float = 0.0

var compute_capacity: float = 0.0
var compute_demand: float = 0.0

var life_support_capacity: float = 0.0
var life_support_demand: float = 0.0
var life_support_overloaded: bool = false

var fuel_consumption: float = 0.0
var fuel_current: float = 0.0
var fuel_capacity: float = 0.0
var fuel_empty: bool = false

var thrust_factor: float = 1.0
var boost_allowed: bool = true

var weapon_power_requested: float = 0.0
var weapon_power_allocated: float = 0.0
var weapons_allowed: bool = true

var active_systems: Dictionary = {}
var transponder_broadcasting: bool = false
var power_allocated_by_category: Dictionary = {}
var power_requested_by_category: Dictionary = {}
var signature_glow_propulsion: float = 0.0
var signature_glow_weapon: float = 0.0
