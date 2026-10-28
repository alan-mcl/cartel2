class_name FluxLightningPulse
extends RefCounted

## Irregular flash envelope (0..1) for N-space flux presentation.

var _intensity: float = 0.0
var _refractory: float = 0.0
var _rng := RandomNumberGenerator.new()


func reset(seed_value: int = 0) -> void:
	_intensity = 0.0
	_refractory = 0.0
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func advance(delta: float) -> float:
	if delta <= 0.0:
		return clampf(_intensity, 0.0, 1.0)

	if _intensity > 0.0:
		_intensity = maxf(0.0, _intensity - delta * 12.5)

	_refractory -= delta
	if _refractory > 0.0:
		return clampf(_intensity, 0.0, 1.0)

	if _rng.randf() < 0.18:
		_refractory = _rng.randf_range(0.04, 0.22)
		return clampf(_intensity, 0.0, 1.0)

	_intensity = _rng.randf_range(0.5, 1.0)
	if _rng.randf() < 0.24:
		_refractory = _rng.randf_range(0.015, 0.06)
	else:
		_refractory = _rng.randf_range(0.07, 0.48)

	return clampf(_intensity, 0.0, 1.0)
