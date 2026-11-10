class_name PlanetExposure
extends RefCounted

## Display exposure for planet and parent-body shaders. [irradiance] is physical (L / d²); not rewritten here.

const REFERENCE_IRRADIANCE := 2.5
const EXPOSURE_MIN := 0.03
const EXPOSURE_MAX := 10000.0
const IRRADIANCE_ADAPT_EXPONENT := 0.75
const NIGHT_IRRADIANCE_MAX := 0.02
const NIGHT_IRRADIANCE_SCALE := 0.4
const LUMINANCE_WEIGHTS := Vector3(0.2126, 0.7152, 0.0722)


static func night_irradiance(irradiance: float) -> float:
	return minf(NIGHT_IRRADIANCE_MAX, NIGHT_IRRADIANCE_SCALE * maxf(irradiance, 0.0))


static func display_exposure(irradiance: float) -> float:
	if irradiance <= 0.0:
		return EXPOSURE_MAX
	var scaled := pow(maxf(irradiance, 0.0), IRRADIANCE_ADAPT_EXPONENT)
	if scaled <= 0.0:
		return EXPOSURE_MAX
	return clampf(REFERENCE_IRRADIANCE / scaled, EXPOSURE_MIN, EXPOSURE_MAX)


static func linear_irradiance_at_surface(irradiance: float, day_factor: float) -> float:
	return night_irradiance(irradiance) + irradiance * clampf(day_factor, 0.0, 1.0)


static func tonemap_reinhard_chroma(rgb: Vector3) -> Vector3:
	var luma := rgb.dot(LUMINANCE_WEIGHTS)
	if luma <= 1.0e-8:
		return rgb
	var mapped := luma / (1.0 + luma)
	return rgb * (mapped / luma)


static func display_from_radiance(radiance: Vector3, irradiance: float) -> Vector3:
	return tonemap_reinhard_chroma(radiance * display_exposure(irradiance))
