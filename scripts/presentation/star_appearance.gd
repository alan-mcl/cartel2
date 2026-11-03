class_name StarAppearance
extends RefCounted

## Resolves stellar disc size, irradiance, tone-mapped brightness, and shader style from catalog data.

const STAR_SIZE_SCALE := 24.0
const SMALL_ANGLE_DEG_PER_AU := 0.533

const DEFAULT_RADIUS_SOLAR := 1.0
const DEFAULT_LUMINOSITY := 1.0
const DEFAULT_TEMPERATURE_K := 5800.0

const BRIGHTNESS_SCALE := 1.0
const BRIGHTNESS_EXPONENT := 0.65
const BRIGHTNESS_MIN := 0.08
const BRIGHTNESS_MAX := 8.0
const EXPOSURE := 1.4

const GIANT_RADIUS_SOLAR_THRESHOLD := 5.0


static func angular_diameter_deg(radius_solar: float, distance_au: float) -> float:
	var r := maxf(radius_solar, 0.01)
	var d := maxf(distance_au, 0.01)
	return SMALL_ANGLE_DEG_PER_AU * r / d


static func physical_disc_radius(radius_solar: float, distance_au: float) -> float:
	var r := maxf(radius_solar, 0.01)
	var d := maxf(distance_au, 0.01)
	return STAR_SIZE_SCALE * r / d


## Legacy ratio: radius_solar / distance_au (1.0 = Sun at 1 AU).
static func angular_disc_scale(radius_solar: float, distance_au: float) -> float:
	return maxf(radius_solar, 0.01) / maxf(distance_au, 0.01)


static func irradiance(luminosity: float, distance_au: float) -> float:
	var au := maxf(distance_au, 0.01)
	return luminosity / (au * au)


static func apparent_brightness(irradiance_value: float) -> float:
	var scaled := BRIGHTNESS_SCALE * pow(maxf(irradiance_value, 0.0), BRIGHTNESS_EXPONENT)
	var clamped := clampf(scaled, BRIGHTNESS_MIN, BRIGHTNESS_MAX)
	return 1.0 - exp(-clamped * EXPOSURE)


static func color_from_temperature_k(temperature_k: float) -> Color:
	var temp := clampf(temperature_k, 2500.0, 12000.0) / 100.0
	var red := 1.0
	var green := 0.0
	var blue := 0.0
	if temp <= 66.0:
		green = clampf(0.39 * log(maxf(temp, 1.0)) - 0.63, 0.0, 1.0)
	else:
		green = clampf(1.29 * pow(temp - 60.0, -0.133), 0.0, 1.0)
	if temp >= 66.0:
		blue = clampf(1.29 * pow(temp - 60.0, -0.133), 0.0, 1.0)
	else:
		if temp <= 19.0:
			blue = 0.0
		else:
			blue = clampf(0.39 * log(temp - 10.0) - 0.63, 0.0, 1.0)
	return Color(red, green, blue, 1.0)


static func presentation_seed(star_data: Dictionary) -> float:
	var key := "%s|%s|%s|%s" % [
		star_data.get("name", ""),
		star_data.get("temperature_k", 0.0),
		star_data.get("luminosity", 0.0),
		star_data.get("spectral_class", ""),
	]
	return float(absi(key.hash()) % 10000) / 10000.0


static func resolve(
	star_data: Dictionary,
	distance_au: float = 1.0,
	radius_solar: float = DEFAULT_RADIUS_SOLAR
) -> Dictionary:
	var temperature_k := float(star_data.get("temperature_k", DEFAULT_TEMPERATURE_K))
	var luminosity := float(star_data.get("luminosity", DEFAULT_LUMINOSITY))
	var r_solar := maxf(radius_solar, 0.01)
	var d_au := maxf(distance_au, 0.01)

	var physical := physical_disc_radius(r_solar, d_au)
	var displayed := physical
	if star_data.has("disc_radius"):
		displayed = maxf(float(star_data.get("disc_radius", physical)), 0.01)

	var irr := irradiance(luminosity, d_au)
	var brightness := apparent_brightness(irr)
	var angular_deg := angular_diameter_deg(r_solar, d_au)
	var spectral := str(star_data.get("spectral_class", "")).strip_edges()
	var preset_key := str(star_data.get("preset", "")).strip_edges()
	var style := _style_preset(preset_key, spectral, r_solar)
	if star_data.has("flares_enabled"):
		style["flares_enabled"] = 1.0 if bool(star_data.get("flares_enabled", false)) else 0.0
	if star_data.has("spikes_enabled"):
		style["spikes_enabled"] = 1.0 if bool(star_data.get("spikes_enabled", false)) else 0.0

	var disc_colour := color_from_temperature_k(temperature_k)
	var seed := presentation_seed(star_data)

	return {
		"temperature_k": temperature_k,
		"luminosity": luminosity,
		"radius_solar": r_solar,
		"distance_au": d_au,
		"angular_diameter_deg": angular_deg,
		"angular_disc_scale": angular_disc_scale(r_solar, d_au),
		"physical_disc_radius": physical,
		"disc_radius": displayed,
		"irradiance": irr,
		"apparent_brightness": brightness,
		"color": disc_colour,
		"spectral_class": spectral,
		"presentation_seed": seed,
		"style": style,
	}


static func _style_preset(preset_override: String, spectral_class: String, radius_solar: float) -> Dictionary:
	if not preset_override.is_empty():
		return _preset_table().get(preset_override, _preset_g())
	var letter := _spectral_letter(spectral_class)
	var base: Dictionary = _preset_for_letter(letter)
	var is_giant := radius_solar >= GIANT_RADIUS_SOLAR_THRESHOLD or _luminosity_class_is_giant(spectral_class)
	if is_giant:
		base = _merge_style(base, _preset_giant())
	if _is_emission_class(spectral_class):
		base["flares_enabled"] = 1.0
	return base


static func _spectral_letter(spectral_class: String) -> String:
	var s := spectral_class.strip_edges().to_upper()
	if s.is_empty():
		return "G"
	return s.substr(0, 1)


static func _is_emission_class(spectral_class: String) -> bool:
	return spectral_class.strip_edges().to_lower().ends_with("e")


static func _luminosity_class_is_giant(spectral_class: String) -> bool:
	var s := spectral_class.strip_edges().to_upper()
	if s.contains("III"):
		return true
	if s.contains(" II") or s.ends_with("II"):
		return true
	if s.contains("IA") or s.contains("IB"):
		return true
	if s.ends_with("I") and not s.ends_with("VI") and not s.ends_with("IV"):
		return true
	return false


static func _preset_for_letter(letter: String) -> Dictionary:
	match letter:
		"M":
			return _preset_m()
		"K":
			return _preset_k()
		"G":
			return _preset_g()
		"F":
			return _preset_f()
		"A":
			return _preset_a()
		"B", "O":
			return _preset_b()
		_:
			return _preset_g()


static func _merge_style(base: Dictionary, overlay: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in overlay:
		out[key] = overlay[key]
	return out


static func _preset_table() -> Dictionary:
	return {
		"red_dwarf": _preset_m(),
		"orange_dwarf": _preset_k(),
		"sun_like": _preset_g(),
		"white": _preset_a(),
		"blue_white": _preset_b(),
		"blue_giant": _merge_style(_preset_b(), _preset_giant()),
	}


static func _preset_m() -> Dictionary:
	return {
		"corona_radius_multiplier": 3.0,
		"corona_brightness": 0.75,
		"inner_glow_strength": 0.5,
		"corona_falloff": 2.4,
		"limb_darkening": 0.35,
		"limb_curve": 1.8,
		"limb_colour_shift": 0.12,
		"surface_variation_strength": 0.08,
		"surface_variation_scale": 8.0,
		"colour_saturation": 1.15,
		"core_colour_mix": 0.55,
		"corona_colour_mix": 0.85,
		"corona_distortion": 0.04,
		"corona_noise_strength": 0.06,
		"flares_enabled": 0.0,
		"spikes_enabled": 0.0,
	}


static func _preset_k() -> Dictionary:
	return {
		"corona_radius_multiplier": 3.5,
		"corona_brightness": 0.85,
		"inner_glow_strength": 0.55,
		"corona_falloff": 2.2,
		"limb_darkening": 0.4,
		"limb_curve": 1.7,
		"limb_colour_shift": 0.1,
		"surface_variation_strength": 0.1,
		"surface_variation_scale": 7.0,
		"colour_saturation": 1.1,
		"core_colour_mix": 0.58,
		"corona_colour_mix": 0.88,
		"corona_distortion": 0.05,
		"corona_noise_strength": 0.07,
		"flares_enabled": 0.0,
		"spikes_enabled": 0.0,
	}


static func _preset_g() -> Dictionary:
	return {
		"corona_radius_multiplier": 4.0,
		"corona_brightness": 0.9,
		"inner_glow_strength": 0.6,
		"corona_falloff": 2.2,
		"limb_darkening": 0.45,
		"limb_curve": 1.6,
		"limb_colour_shift": 0.08,
		"surface_variation_strength": 0.12,
		"surface_variation_scale": 6.0,
		"colour_saturation": 1.0,
		"core_colour_mix": 0.62,
		"corona_colour_mix": 0.9,
		"corona_distortion": 0.06,
		"corona_noise_strength": 0.08,
		"flares_enabled": 0.0,
		"spikes_enabled": 0.0,
	}


static func _preset_f() -> Dictionary:
	return {
		"corona_radius_multiplier": 4.0,
		"corona_brightness": 0.95,
		"inner_glow_strength": 0.65,
		"corona_falloff": 2.0,
		"limb_darkening": 0.42,
		"limb_curve": 1.55,
		"limb_colour_shift": 0.06,
		"surface_variation_strength": 0.1,
		"surface_variation_scale": 5.5,
		"colour_saturation": 0.92,
		"core_colour_mix": 0.68,
		"corona_colour_mix": 0.82,
		"corona_distortion": 0.07,
		"corona_noise_strength": 0.09,
		"flares_enabled": 0.0,
		"spikes_enabled": 0.0,
	}


static func _preset_a() -> Dictionary:
	return {
		"corona_radius_multiplier": 4.2,
		"corona_brightness": 1.0,
		"inner_glow_strength": 0.7,
		"corona_falloff": 1.95,
		"limb_darkening": 0.38,
		"limb_curve": 1.5,
		"limb_colour_shift": 0.05,
		"surface_variation_strength": 0.08,
		"surface_variation_scale": 5.0,
		"colour_saturation": 0.85,
		"core_colour_mix": 0.72,
		"corona_colour_mix": 0.78,
		"corona_distortion": 0.08,
		"corona_noise_strength": 0.1,
		"flares_enabled": 0.0,
		"spikes_enabled": 0.0,
	}


static func _preset_b() -> Dictionary:
	return {
		"corona_radius_multiplier": 4.8,
		"corona_brightness": 1.05,
		"inner_glow_strength": 0.75,
		"corona_falloff": 1.85,
		"limb_darkening": 0.35,
		"limb_curve": 1.45,
		"limb_colour_shift": 0.04,
		"surface_variation_strength": 0.06,
		"surface_variation_scale": 4.5,
		"colour_saturation": 0.88,
		"core_colour_mix": 0.75,
		"corona_colour_mix": 0.92,
		"corona_distortion": 0.1,
		"corona_noise_strength": 0.12,
		"flares_enabled": 0.0,
		"spikes_enabled": 0.0,
	}


static func _preset_giant() -> Dictionary:
	return {
		"corona_radius_multiplier": 5.5,
		"corona_brightness": 1.15,
		"inner_glow_strength": 0.8,
		"corona_falloff": 1.75,
		"surface_variation_strength": 0.14,
	}


static func apply_shader_material(material: ShaderMaterial, resolved: Dictionary) -> void:
	var style: Dictionary = resolved.get("style", {})
	var disc_colour: Color = resolved.get("color", Color.WHITE)
	var brightness := float(resolved.get("apparent_brightness", 1.0))
	var disc_r := float(resolved.get("disc_radius", STAR_SIZE_SCALE))
	var corona_mult := float(style.get("corona_radius_multiplier", 4.0))
	var corona_world_r := disc_r * corona_mult
	var disc_uv := 0.5 / maxf(corona_mult, 0.01)

	var limb := float(style.get("limb_darkening", 0.45))
	var disc_world := disc_r * 2.0
	var limb_fade := clampf(disc_world / 48.0, 0.0, 1.0)

	material.set_shader_parameter("disc_colour", Vector3(disc_colour.r, disc_colour.g, disc_colour.b))
	material.set_shader_parameter("corona_colour", Vector3(disc_colour.r, disc_colour.g, disc_colour.b))
	material.set_shader_parameter("apparent_brightness", brightness)
	material.set_shader_parameter("disc_uv_radius", disc_uv)
	material.set_shader_parameter("corona_uv_radius", 0.5)
	material.set_shader_parameter("corona_radius_multiplier", corona_mult)
	material.set_shader_parameter("disc_radius_world", disc_r)
	material.set_shader_parameter("limb_darkening", limb * limb_fade)
	material.set_shader_parameter("limb_curve", float(style.get("limb_curve", 1.6)))
	material.set_shader_parameter("limb_colour_shift", float(style.get("limb_colour_shift", 0.08)))
	material.set_shader_parameter("surface_variation_strength", float(style.get("surface_variation_strength", 0.1)) * limb_fade)
	material.set_shader_parameter("surface_variation_scale", float(style.get("surface_variation_scale", 6.0)))
	material.set_shader_parameter("colour_saturation", float(style.get("colour_saturation", 1.0)))
	material.set_shader_parameter("core_colour_mix", float(style.get("core_colour_mix", 0.62)))
	material.set_shader_parameter("corona_colour_mix", float(style.get("corona_colour_mix", 0.9)))
	material.set_shader_parameter("corona_brightness", float(style.get("corona_brightness", 0.9)))
	material.set_shader_parameter("inner_glow_strength", float(style.get("inner_glow_strength", 0.6)))
	material.set_shader_parameter("corona_falloff", float(style.get("corona_falloff", 2.2)))
	material.set_shader_parameter("corona_distortion", float(style.get("corona_distortion", 0.06)))
	material.set_shader_parameter("corona_noise_strength", float(style.get("corona_noise_strength", 0.08)))
	material.set_shader_parameter("presentation_seed", float(resolved.get("presentation_seed", 0.0)))
	material.set_shader_parameter("flares_enabled", float(style.get("flares_enabled", 0.0)))
	material.set_shader_parameter("spikes_enabled", float(style.get("spikes_enabled", 0.0)))


static func corona_world_radius(resolved: Dictionary) -> float:
	var disc_r := float(resolved.get("disc_radius", STAR_SIZE_SCALE))
	var style: Dictionary = resolved.get("style", {})
	var corona_mult := float(style.get("corona_radius_multiplier", 4.0))
	return disc_r * corona_mult
