class_name SkyParentRingProfile
extends RefCounted

const PROFILE_WIDTH := 256


static func build_texture(rings_config: Dictionary, seed_val: float) -> ImageTexture:
	var image := Image.create(PROFILE_WIDTH, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var outer := maxf(float(rings_config.get("outer_radius", 1.0)), 1.001)
	var bands: Array = rings_config.get("bands", [])
	var gaps: Array = rings_config.get("gaps", [])
	for x in PROFILE_WIDTH:
		var radial := outer * (float(x) + 0.5) / float(PROFILE_WIDTH)
		var sample := _sample_radial(radial, bands, gaps, seed_val)
		image.set_pixel(x, 0, sample)
	return ImageTexture.create_from_image(image)


static func _sample_radial(radial: float, bands: Array, gaps: Array, seed_val: float) -> Color:
	var colour := Color(0, 0, 0, 0)
	for band_variant in bands:
		if typeof(band_variant) != TYPE_DICTIONARY:
			continue
		var band: Dictionary = band_variant
		var inner := float(band.get("inner_radius", 0.0))
		var outer_r := float(band.get("outer_radius", 0.0))
		if radial < inner or radial > outer_r:
			continue
		var base := Color(str(band.get("colour", "#ffffff")))
		var opacity := float(band.get("opacity", 0.8))
		var density := float(band.get("density", 0.7))
		var brightness := float(band.get("brightness", 1.0))
		var noise_strength := float(band.get("noise_strength", 0.0))
		var noise_scale := float(band.get("noise_scale", 8.0))
		var edge_softness := float(band.get("edge_softness", 0.02))
		var edge := 1.0
		edge *= smoothstep(inner, inner + edge_softness * outer_r, radial)
		edge *= 1.0 - smoothstep(outer_r - edge_softness * outer_r, outer_r, radial)
		var noise := _hash_noise(radial * noise_scale + seed_val * 13.7)
		var alpha := opacity * density * edge * (1.0 - noise_strength + noise * noise_strength)
		colour = Color(base.r * brightness, base.g * brightness, base.b * brightness, alpha)
	for gap_variant in gaps:
		if typeof(gap_variant) != TYPE_DICTIONARY:
			continue
		var gap: Dictionary = gap_variant
		var inner := float(gap.get("inner_radius", 0.0))
		var outer_r := float(gap.get("outer_radius", 0.0))
		if radial >= inner and radial <= outer_r:
			var mult := float(gap.get("opacity_multiplier", 0.0))
			colour.a *= mult
	return colour


static func _hash_noise(t: float) -> float:
	return fmod(absf(sin(t * 127.1) * 43758.5453), 1.0)
