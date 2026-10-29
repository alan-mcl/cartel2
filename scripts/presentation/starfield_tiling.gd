class_name StarfieldTiling
extends RefCounted

## Repeating starfield tile lattice for camera-centred infinite backgrounds.


static func tile_size(texture_size: Vector2, scale_multiplier: float) -> Vector2:
	return texture_size * scale_multiplier


static func layer_offset(anchor: Vector2, parallax: float) -> Vector2:
	return anchor * parallax


static func layer_centre(anchor: Vector2, parallax: float) -> Vector2:
	return anchor * (1.0 - parallax)


static func compute_tile_indices(
	anchor: Vector2,
	half_visible: Vector2,
	parallax: float,
	tile_size: Vector2,
	margin_tiles: int = 1
) -> Dictionary:
	var centre := layer_centre(anchor, parallax)
	var margin := tile_size * float(margin_tiles)
	var min_l := centre - half_visible - margin
	var max_l := centre + half_visible + margin
	var i_min := int(floor(min_l.x / tile_size.x))
	var i_max := int(floor(max_l.x / tile_size.x))
	var j_min := int(floor(min_l.y / tile_size.y))
	var j_max := int(floor(max_l.y / tile_size.y))
	return {
		"i_min": i_min,
		"i_max": i_max,
		"j_min": j_min,
		"j_max": j_max,
		"layer_offset": layer_offset(anchor, parallax),
	}


static func tile_local_position(i: int, j: int, tile_size: Vector2) -> Vector2:
	return Vector2(float(i) * tile_size.x, float(j) * tile_size.y)


static func tile_world_position(
	i: int,
	j: int,
	anchor: Vector2,
	parallax: float,
	tile_size: Vector2
) -> Vector2:
	return layer_offset(anchor, parallax) + tile_local_position(i, j, tile_size)


static func enumerate_tiles(indices: Dictionary, tile_size: Vector2) -> Array:
	var out: Array = []
	var i_min: int = indices.get("i_min", 0)
	var i_max: int = indices.get("i_max", 0)
	var j_min: int = indices.get("j_min", 0)
	var j_max: int = indices.get("j_max", 0)
	for i in range(i_min, i_max + 1):
		for j in range(j_min, j_max + 1):
			out.append({"i": i, "j": j, "local": tile_local_position(i, j, tile_size)})
	return out


static func view_rect_covers(
	anchor: Vector2,
	half_visible: Vector2,
	parallax: float,
	tile_size: Vector2,
	margin_tiles: int = 1
) -> bool:
	var indices := compute_tile_indices(
		anchor, half_visible, parallax, tile_size, margin_tiles
	)
	var tiles := enumerate_tiles(indices, tile_size)
	var offset := layer_offset(anchor, parallax)
	var min_w := anchor - half_visible
	var max_w := anchor + half_visible
	for corner in [
		Vector2(min_w.x, min_w.y),
		Vector2(max_w.x, min_w.y),
		Vector2(min_w.x, max_w.y),
		Vector2(max_w.x, max_w.y),
	]:
		if not _point_covered_by_tiles(corner, tiles, offset, tile_size):
			return false
	return true


static func _point_covered_by_tiles(
	point: Vector2,
	tiles: Array,
	layer_offset: Vector2,
	tile_size: Vector2
) -> bool:
	for entry_variant in tiles:
		var entry: Dictionary = entry_variant
		var local: Vector2 = entry.get("local", Vector2.ZERO)
		var origin := layer_offset + local
		if (
			point.x >= origin.x
			and point.x < origin.x + tile_size.x
			and point.y >= origin.y
			and point.y < origin.y + tile_size.y
		):
			return true
	return false
