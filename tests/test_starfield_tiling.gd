class_name TestStarfieldTiling
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_tiles_on_lattice(runner)
	_test_parallax_layer_offset(runner)
	_test_far_view_coverage(runner)


static func _test_tiles_on_lattice(runner: TestRunner) -> void:
	var tile_size := Vector2(512.0, 512.0)
	var anchor := Vector2(50000.0, -32000.0)
	var half_visible := Vector2(960.0, 540.0) / 0.72
	var indices := StarfieldTiling.compute_tile_indices(
		anchor, half_visible, 0.08, tile_size, 1
	)
	var tiles := StarfieldTiling.enumerate_tiles(indices, tile_size)
	runner.check(tiles.size() > 0, "starfield tiling: far view produces tiles")
	for entry_variant in tiles:
		var entry: Dictionary = entry_variant
		var i: int = entry.get("i", 0)
		var j: int = entry.get("j", 0)
		var local: Vector2 = entry.get("local", Vector2.ZERO)
		runner.check(
			is_equal_approx(local.x, float(i) * tile_size.x),
			"starfield tiling: tile x on lattice"
		)
		runner.check(
			is_equal_approx(local.y, float(j) * tile_size.y),
			"starfield tiling: tile y on lattice"
		)


static func _test_parallax_layer_offset(runner: TestRunner) -> void:
	var anchor := Vector2(12000.0, -8000.0)
	var far := StarfieldTiling.layer_offset(anchor, 0.08)
	var near := StarfieldTiling.layer_offset(anchor, 0.22)
	runner.check(is_equal_approx(far.x, anchor.x * 0.08), "starfield tiling: far parallax x")
	runner.check(is_equal_approx(near.y, anchor.y * 0.22), "starfield tiling: near parallax y")


static func _test_far_view_coverage(runner: TestRunner) -> void:
	var tile_size := Vector2(512.0, 588.8)
	var anchor := Vector2(88000.0, 41000.0)
	var half_visible := Vector2(960.0, 540.0) / 0.72
	runner.check(
		StarfieldTiling.view_rect_covers(anchor, half_visible, 0.08, tile_size, 1),
		"starfield tiling: far layer covers view corners"
	)
	runner.check(
		StarfieldTiling.view_rect_covers(anchor, half_visible, 0.22, tile_size, 1),
		"starfield tiling: near layer covers view corners"
	)
