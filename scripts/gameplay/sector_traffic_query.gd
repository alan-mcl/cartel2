class_name SectorTrafficQuery
extends RefCounted

## Snapshot of sector anchor positions, spawn offsets, and arrival circles for traffic gameplay.

var anchors: Array = []
var habitat_launch: Vector2 = Vector2.ZERO
var gate_approach: Vector2 = Vector2.ZERO
var envelope_radius: float = 5000.0

var _arrivals: Dictionary = {}


func load_arrivals(arrivals: Dictionary) -> void:
	_arrivals = arrivals.duplicate(true)


func is_route_arrived(
	prev_pos: Vector2,
	world_pos: Vector2,
	destination_id: String,
	_traffic_config: Dictionary = {}
) -> bool:
	var dest_key := destination_id.strip_edges()
	if dest_key.is_empty() or not _arrivals.has(dest_key):
		return false
	var circle: Dictionary = _arrivals[dest_key]
	var center: Vector2 = circle.get("center", Vector2.ZERO)
	var radius := float(circle.get("radius", 0.0))
	if radius <= 0.0:
		return false
	if world_pos.distance_to(center) <= radius:
		return true
	return TrafficRouting.segment_intersects_circle(prev_pos, world_pos, center, radius)


## Matches an unloaded WorldLoader envelope default for headless traffic tests.
static func minimal(envelope_radius: float = 5000.0) -> SectorTrafficQuery:
	var query := SectorTrafficQuery.new()
	query.envelope_radius = envelope_radius
	return query


## Approximate Proxima layout without scene nodes (ring radius 1600, gate 5400).
static func synthetic_proxima(catalog: Catalog) -> SectorTrafficQuery:
	var traffic_config := catalog.get_traffic_config() if catalog != null else {}
	var fallback := float(traffic_config.get("orbital_arrival_radius", 90.0))
	var habitat_pos := Vector2(1600, 0)
	var gate_pos := Vector2(5400, 0)
	var query := SectorTrafficQuery.new()
	query.envelope_radius = 6750.0
	query.habitat_launch = habitat_pos + Vector2.UP * 220.0
	query.gate_approach = gate_pos + Vector2.LEFT * 280.0
	query.anchors = [
		{"id": "habitat", "kind": "habitat", "position": habitat_pos},
		{"id": "jump_gate", "kind": "jump_gate", "position": gate_pos},
	]
	query.load_arrivals({
		"habitat": {"center": habitat_pos, "radius": fallback},
		"jump_gate": {"center": gate_pos, "radius": fallback},
	})
	return query