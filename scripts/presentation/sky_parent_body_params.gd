class_name SkyParentBodyParams
extends RefCounted

const APPEARANCE_BANDED := "banded"
const APPEARANCE_GAS_GIANT := "gas_giant"
const APPEARANCE_UNIFORM := "uniform"
const APPEARANCE_MOTTLED := "mottled"
const APPEARANCE_GRADIENT := "gradient"
const BAND_PALETTE_SIZE := 32
const DEFAULT_BAND_EDGE_SOFTNESS := 0.4
const RING_NONE := "none"
const RING_SMALL := "small"
const RING_BROAD := "broad"

const PRESETS := {
	"smooth_banded": {
		"band_count": 10,
		"band_contrast": 0.45,
		"band_turbulence": 0.1,
		"band_distortion": 0.15,
	},
	"turbulent_banded": {
		"band_count": 14,
		"band_contrast": 0.7,
		"band_turbulence": 0.55,
		"band_distortion": 0.4,
		"turbulence_octaves": 3,
	},
	"subtle_banded": {
		"band_count": 8,
		"band_contrast": 0.3,
		"band_turbulence": 0.05,
		"band_distortion": 0.1,
	},
	"high_contrast": {
		"band_count": 16,
		"band_contrast": 0.85,
		"band_turbulence": 0.25,
		"band_distortion": 0.35,
	},
	"stormy": {
		"band_count": 12,
		"band_contrast": 0.75,
		"band_turbulence": 0.65,
		"band_distortion": 0.5,
		"turbulence_octaves": 4,
	},
}


static func body_type_label(body_type_id: String) -> String:
	var id := body_type_id.strip_edges()
	if id.is_empty():
		return "Parent planet"
	var spaced := id.replace("_", " ")
	if spaced.is_empty():
		return "Parent planet"
	return spaced.substr(0, 1).to_upper() + spaced.substr(1).to_lower()


static func hex_tint_to_vec3(hex: String) -> Vector3:
	var colour := Color(str(hex))
	return Vector3(colour.r, colour.g, colour.b)


static func seed_value(seed_text: String) -> float:
	return float(absi(seed_text.hash()) % 10000) / 10000.0


static func resolve_from_parent(parent_data: Dictionary, seed_key: String = "") -> Dictionary:
	if parent_data.is_empty():
		return {}
	var appearance_raw: Variant = parent_data.get("appearance", {})
	if typeof(appearance_raw) != TYPE_DICTIONARY:
		return {}
	var appearance_type := str(appearance_raw.get("type", "")).strip_edges()
	if not _is_supported_appearance_type(appearance_type):
		return {}
	var seed_text := seed_key if not seed_key.strip_edges().is_empty() else str(parent_data.get("name", "parent"))
	var seed_val := seed_value(seed_text)
	var merged := _merge_appearance(appearance_raw, seed_text, seed_val)
	var rings_cfg := _resolve_rings(parent_data.get("rings", {}))
	return {
		"type_label": body_type_label(str(parent_data.get("type", ""))),
		"appearance": merged,
		"rings": rings_cfg,
		"seed_text": seed_text,
		"seed_val": seed_val,
	}


static func ring_outer_scale(rings_cfg: Dictionary) -> float:
	if not bool(rings_cfg.get("enabled", false)):
		return 1.0
	return maxf(float(rings_cfg.get("outer_radius", 1.0)), 1.0)


static func build_planet_shader_params(
	merged_appearance: Dictionary,
	seed_val: float,
	seed_text: String = ""
) -> Dictionary:
	var atm: Dictionary = _dict(merged_appearance.get("atmosphere", {}))
	var light: Dictionary = _dict(merged_appearance.get("lighting", {}))
	var orient: Dictionary = _dict(merged_appearance.get("orientation", {}))
	var appearance_type := str(merged_appearance.get("type", APPEARANCE_BANDED)).strip_edges()
	var colours := _resolve_colours(atm, merged_appearance, appearance_type)
	var colour_count := colours.size()
	var palette_key := seed_text if not seed_text.strip_edges().is_empty() else "parent"
	return {
		"colours": colours,
		"colour_count": colour_count,
		"band_palette": build_band_palette(palette_key, colour_count),
		"scheme": appearance_scheme_index(appearance_type),
		"seed": seed_val,
		"rotation_phase": deg_to_rad(float(orient.get("rotation_phase_deg", 0.0))),
		"axis": _resolve_axis_vector(orient, merged_appearance, seed_val),
		"band_count": float(atm.get("band_count", 12.0)),
		"band_frequency": float(atm.get("band_frequency", 1.0)),
		"band_width_variation": float(atm.get("band_width_variation", 0.35)),
		"band_contrast": float(atm.get("band_contrast", 0.55)),
		"band_distortion": float(atm.get("band_distortion", 0.2)),
		"band_turbulence": float(atm.get("band_turbulence", 0.0)),
		"band_edge_softness": resolve_band_edge_softness(atm),
		"band_fine_detail": float(atm.get("band_fine_detail", 0.2)),
		"turbulence_scale": float(atm.get("turbulence_scale", 2.0)),
		"turbulence_octaves": float(atm.get("turbulence_octaves", 2.0)),
		"polar_colour": hex_tint_to_vec3(str(atm.get("polar_colour", "#ffffff"))),
		"polar_blend": float(atm.get("polar_blend", 0.0)),
		"ambient_light": float(light.get("ambient_light", 0.12)),
		"light_intensity": float(light.get("light_intensity", 1.0)),
		"limb_darkening": float(light.get("limb_darkening", 1.0)),
		"limb_curve": float(light.get("limb_curve", 0.35)),
		"terminator_softness": float(light.get("terminator_softness", 0.08)),
	}


static func _is_supported_appearance_type(appearance_type: String) -> bool:
	return (
		appearance_type == APPEARANCE_BANDED
		or appearance_type == APPEARANCE_GAS_GIANT
		or appearance_type == APPEARANCE_UNIFORM
		or appearance_type == APPEARANCE_MOTTLED
		or appearance_type == APPEARANCE_GRADIENT
	)


static func appearance_scheme_index(appearance_type: String) -> int:
	match appearance_type.strip_edges():
		APPEARANCE_UNIFORM:
			return 1
		APPEARANCE_MOTTLED:
			return 2
		APPEARANCE_GRADIENT:
			return 3
		_:
			return 0


static func resolve_band_edge_softness(atm: Dictionary) -> float:
	if atm.has("band_edge_softness"):
		return clampf(float(atm.get("band_edge_softness", DEFAULT_BAND_EDGE_SOFTNESS)), 0.0, 1.0)
	if atm.has("band_blur"):
		return clampf(float(atm.get("band_blur", DEFAULT_BAND_EDGE_SOFTNESS)), 0.0, 1.0)
	return DEFAULT_BAND_EDGE_SOFTNESS


static func build_band_palette(seed_text: String, colour_count: int) -> PackedInt32Array:
	var count := clampi(colour_count, 1, 6)
	var out := PackedInt32Array()
	out.resize(BAND_PALETTE_SIZE)
	var prev := -1
	for i in BAND_PALETTE_SIZE:
		var slot_key := "%s:belt:%d" % [seed_text, i]
		var h := absi(slot_key.hash())
		var idx := h % count if count > 0 else 0
		if count >= 2 and idx == prev:
			idx = (idx + 1) % count
		out[i] = idx
		prev = idx
	return out


static func build_ring_shader_params(
	rings_cfg: Dictionary,
	merged_appearance: Dictionary,
	render_front: bool,
	seed_val: float = 0.0
) -> Dictionary:
	var orient: Dictionary = _dict(merged_appearance.get("orientation", {}))
	var ring_orient: Dictionary = _dict(rings_cfg.get("orientation", {}))
	var axis := _resolve_axis_vector(orient, merged_appearance, seed_val)
	if ring_orient.has("ring_tilt_deg") or ring_orient.has("position_angle_deg"):
		axis = _resolve_ring_axis(orient, ring_orient, merged_appearance)
	var shadow_on := bool(rings_cfg.get("shadow_enabled", true))
	return {
		"render_front": render_front,
		"outer_radius": float(rings_cfg.get("outer_radius", 1.0)),
		"ring_brightness": float(rings_cfg.get("brightness", 1.0)),
		"shadow_enabled": shadow_on,
		"shadow_strength": float(rings_cfg.get("shadow_strength", 0.5)),
		"shadow_softness": float(rings_cfg.get("shadow_softness", 0.03)),
		"axis": axis,
	}


static func _merge_appearance(raw: Dictionary, seed_text: String, seed_val: float) -> Dictionary:
	var merged := raw.duplicate(true)
	if merged.has("preset"):
		var preset_id := str(merged.get("preset", "")).strip_edges()
		if PRESETS.has(preset_id):
			var preset: Dictionary = PRESETS[preset_id]
			for key in preset.keys():
				if not _has_nested(merged, "atmosphere", key):
					_set_nested(merged, "atmosphere", key, preset[key])
	var raw_type := str(raw.get("type", "")).strip_edges()
	if raw_type == APPEARANCE_BANDED or raw_type == APPEARANCE_GAS_GIANT:
		var atm := _dict(merged.get("atmosphere", {}))
		if not atm.has("colours"):
			var c1 := str(raw.get("band_colour_1", "#857052"))
			var c2 := str(raw.get("band_colour_2", "#c7ae85"))
			atm["colours"] = [c1, c2]
			merged["atmosphere"] = atm
		if not atm.has("band_turbulence") and raw.has("turbulence"):
			atm["band_turbulence"] = float(raw.get("turbulence", 0.0))
			merged["atmosphere"] = atm
		merged["band_colour_1"] = raw.get("band_colour_1", "#857052")
		merged["band_colour_2"] = raw.get("band_colour_2", "#c7ae85")
	var orient := _dict(merged.get("orientation", {}))
	if not orient.has("axis_inclination_deg"):
		if raw.has("polar_inclination_deg"):
			orient["axis_inclination_deg"] = raw.get("polar_inclination_deg")
		elif raw.has("orbital_inclination_deg"):
			orient["axis_inclination_deg"] = raw.get("orbital_inclination_deg")
		else:
			orient["axis_inclination_deg"] = rad_to_deg(default_axis_inclination_rad(seed_val))
	if not orient.has("axis_position_angle_deg"):
		if raw.has("band_meridian_deg"):
			orient["axis_position_angle_deg"] = raw.get("band_meridian_deg")
		else:
			orient["axis_position_angle_deg"] = rad_to_deg(default_axis_position_rad(seed_text))
	merged["orientation"] = orient
	if not merged.has("atmosphere"):
		merged["atmosphere"] = {}
	if not merged.has("lighting"):
		merged["lighting"] = {}
	return merged


static func default_axis_inclination_rad(seed_val: float) -> float:
	return 0.2 + 0.65 * fmod(seed_val * 17.0 + 0.31, 1.0)


static func default_axis_position_rad(seed_text: String) -> float:
	var band_axis_hash := absi((seed_text + ":bands").hash())
	return float(band_axis_hash % 628318) / 100000.0


static func _resolve_colours(atm: Dictionary, merged: Dictionary, appearance_type: String = "") -> Array:
	var raw: Variant = atm.get("colours", [])
	var out: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for entry in raw:
			out.append(hex_tint_to_vec3(str(entry)))
	if out.is_empty():
		out.append(hex_tint_to_vec3(str(merged.get("band_colour_1", "#857052"))))
		if appearance_type != APPEARANCE_UNIFORM:
			out.append(hex_tint_to_vec3(str(merged.get("band_colour_2", "#c7ae85"))))
	while out.size() > 6:
		out.pop_back()
	if out.is_empty():
		out.append(hex_tint_to_vec3("#857052"))
	return out


static func _resolve_axis_vector(orient: Dictionary, merged: Dictionary, seed_val: float) -> Vector3:
	var inc_deg := float(orient.get("axis_inclination_deg", rad_to_deg(default_axis_inclination_rad(seed_val))))
	var pos_deg := float(orient.get("axis_position_angle_deg", 0.0))
	return _axis_from_angles(inc_deg, pos_deg)


static func _resolve_ring_axis(
	planet_orient: Dictionary,
	ring_orient: Dictionary,
	merged: Dictionary
) -> Vector3:
	var inc_deg := float(ring_orient.get("ring_tilt_deg", planet_orient.get("axis_inclination_deg", 30.0)))
	var pos_deg := float(
		ring_orient.get(
			"position_angle_deg",
			planet_orient.get("axis_position_angle_deg", 0.0)
		)
	)
	return _axis_from_angles(inc_deg, pos_deg)


static func _axis_from_angles(inclination_deg: float, position_angle_deg: float) -> Vector3:
	var inc := deg_to_rad(clampf(inclination_deg, 0.0, 90.0))
	var pos := deg_to_rad(position_angle_deg)
	var axis := Vector3(
		sin(inc) * cos(pos),
		sin(inc) * sin(pos),
		cos(inc)
	)
	if axis.length_squared() < 0.0001:
		return Vector3(0, 0, 1)
	return axis.normalized()


static func _resolve_rings(rings_raw: Variant) -> Dictionary:
	var disabled := {
		"enabled": false,
		"outer_radius": 1.0,
		"bands": [],
		"gaps": [],
	}
	if typeof(rings_raw) != TYPE_DICTIONARY:
		return disabled
	var rings: Dictionary = rings_raw
	if rings.has("type"):
		var legacy_type := str(rings.get("type", RING_NONE)).strip_edges()
		if legacy_type == RING_NONE:
			return disabled
		if legacy_type == RING_SMALL or legacy_type == RING_BROAD:
			var outer := float(rings.get("outer_scale", 1.4))
			return {
				"enabled": true,
				"outer_radius": outer,
				"brightness": 1.0,
				"shadow_enabled": true,
				"shadow_strength": 0.45,
				"shadow_softness": 0.03,
				"orientation": {},
				"bands": [
					{
						"inner_radius": 1.12,
						"outer_radius": outer,
						"colour": str(rings.get("colour", "#c7ae85")),
						"opacity": 0.75,
						"density": 0.7,
						"brightness": 1.0,
						"noise_strength": 0.12,
					}
				],
				"gaps": [],
			}
		return disabled
	if not bool(rings.get("enabled", false)):
		return disabled
	var bands: Array = []
	if typeof(rings.get("bands")) == TYPE_ARRAY:
		for band_variant in rings.get("bands", []):
			if typeof(band_variant) != TYPE_DICTIONARY:
				continue
			var band: Dictionary = band_variant
			var inner := float(band.get("inner_radius", 0.0))
			var outer_r := float(band.get("outer_radius", 0.0))
			if outer_r <= inner:
				continue
			bands.append(band)
	if bands.is_empty():
		return disabled
	var outer_radius := float(rings.get("outer_radius", 1.0))
	for band in bands:
		outer_radius = maxf(outer_radius, float(band.get("outer_radius", 1.0)))
	return {
		"enabled": true,
		"outer_radius": maxf(outer_radius, 1.001),
		"brightness": float(rings.get("brightness", 1.0)),
		"shadow_enabled": bool(rings.get("shadow_enabled", true)),
		"shadow_strength": float(rings.get("shadow_strength", 0.5)),
		"shadow_softness": float(rings.get("shadow_softness", 0.03)),
		"orientation": _dict(rings.get("orientation", {})),
		"bands": bands,
		"gaps": rings.get("gaps", []) if typeof(rings.get("gaps")) == TYPE_ARRAY else [],
	}


static func _dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


static func _has_nested(root: Dictionary, section: String, key: String) -> bool:
	var block := _dict(root.get(section, {}))
	return block.has(key)


static func _set_nested(root: Dictionary, section: String, key: String, value: Variant) -> void:
	var block := _dict(root.get(section, {}))
	block[key] = value
	root[section] = block
