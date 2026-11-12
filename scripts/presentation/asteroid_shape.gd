class_name AsteroidShape
extends RefCounted

const MAX_PLANES := 12
const MAX_CRATERS := 4
const CHIP_FREQUENCY := 5.0
const PLANE_DOT_FLOOR := 0.2

const COMPOSITION_STONY := "stony"
const COMPOSITION_CARBONACEOUS := "carbonaceous"
const COMPOSITION_METALLIC := "metallic"
const COMPOSITION_ICY := "icy"

const DEFAULT_COMPOSITION := COMPOSITION_STONY

const DEBRIS_WORLD_SIZE := 80.0

const COMPOSITIONS := {
	COMPOSITION_STONY: {
		"colour_a": Color("#8a7d72"),
		"colour_b": Color("#5c554e"),
		"spec_strength": 0.08,
		"crater_depth_scale": 1.0,
		"relief_scale": 1.0,
	},
	COMPOSITION_CARBONACEOUS: {
		"colour_a": Color("#4a443e"),
		"colour_b": Color("#2e2a26"),
		"spec_strength": 0.04,
		"crater_depth_scale": 0.85,
		"relief_scale": 0.9,
	},
	COMPOSITION_METALLIC: {
		"colour_a": Color("#8a8580"),
		"colour_b": Color("#5e5954"),
		"spec_strength": 0.35,
		"crater_depth_scale": 1.1,
		"relief_scale": 0.75,
	},
	COMPOSITION_ICY: {
		"colour_a": Color("#c8d2dc"),
		"colour_b": Color("#8a96a4"),
		"spec_strength": 0.12,
		"crater_depth_scale": 0.7,
		"relief_scale": 0.65,
	},
}

static func _radius_sample_dirs() -> PackedVector3Array:
	return PackedVector3Array(
		[
			Vector3(1.0, 0.0, 0.0),
			Vector3(-1.0, 0.0, 0.0),
			Vector3(0.0, 1.0, 0.0),
			Vector3(0.0, -1.0, 0.0),
			Vector3(0.0, 0.0, 1.0),
			Vector3(0.0, 0.0, -1.0),
			Vector3(0.577350269, 0.577350269, 0.577350269),
			Vector3(-0.408248291, 0.816496581, 0.408248291),
			Vector3(0.267261242, -0.534522484, 0.801783726),
		]
	)


static func entity_render_seed(entity_id: String) -> int:
	return absi(entity_id.hash())


static func composition_for_seed(seed: int) -> String:
	var bucket := absi(seed) % 100
	if bucket < 65:
		return COMPOSITION_CARBONACEOUS
	if bucket < 95:
		return COMPOSITION_STONY
	if bucket < 99:
		return COMPOSITION_METALLIC
	return COMPOSITION_ICY


static func normalize_composition(composition: String) -> String:
	var key := composition.strip_edges().to_lower()
	if COMPOSITIONS.has(key):
		return key
	return DEFAULT_COMPOSITION


static func params_for(seed: int, composition: String = DEFAULT_COMPOSITION) -> Dictionary:
	var comp := normalize_composition(composition)
	var comp_data: Dictionary = COMPOSITIONS[comp]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var ax := rng.randf_range(0.62, 1.0)
	var ay := rng.randf_range(0.62, 1.0)
	var az := rng.randf_range(0.62, 1.0)
	var scale := 1.0 / maxf(maxf(ax, ay), az)
	var ellipsoid := Vector3(ax, ay, az) * scale

	var plane_count := rng.randi_range(8, MAX_PLANES)
	var planes: Array[Dictionary] = []
	for _i in plane_count:
		var normal := _random_unit(rng)
		var along := _ellipsoid_radius(normal, ellipsoid)
		var offset := along * rng.randf_range(0.82, 1.12)
		planes.append({"normal": normal, "offset": offset})

	var crater_count := rng.randi_range(0, MAX_CRATERS)
	var craters: Array[Dictionary] = []
	var min_sep := cos(deg_to_rad(28.0))
	for _j in crater_count:
		var attempts := 0
		while attempts < 24:
			attempts += 1
			var cdir := _random_unit(rng)
			var ok := true
			for existing in craters:
				var edir: Vector3 = existing["dir"]
				if cdir.dot(edir) > min_sep:
					ok = false
					break
			if not ok:
				continue
			var angular_radius := rng.randf_range(0.08, 0.22)
			var depth := rng.randf_range(0.035, 0.07) * float(comp_data["crater_depth_scale"])
			craters.append({
				"dir": cdir,
				"angular_radius": angular_radius,
				"depth": depth,
				"phase": rng.randf() * TAU,
			})
			break

	var seed_f := float(absi(seed) % 10000) / 10000.0
	var chip_amplitude := rng.randf_range(0.05, 0.08)
	var params := {
		"seed": seed,
		"seed_f": seed_f,
		"composition": comp,
		"ellipsoid": ellipsoid,
		"planes": planes,
		"plane_count": plane_count,
		"chip_amplitude": chip_amplitude,
		"chip_frequency": CHIP_FREQUENCY,
		"craters": craters,
		"crater_count": craters.size(),
		"colour_a": _colour_to_vec3(comp_data["colour_a"]),
		"colour_b": _colour_to_vec3(comp_data["colour_b"]),
		"spec_strength": float(comp_data["spec_strength"]),
		"relief_scale": float(comp_data["relief_scale"]),
		"crater_depth_scale": float(comp_data["crater_depth_scale"]),
	}
	params["radius_max"] = compute_radius_max(params)
	return params


static func radius(dir: Vector3, params: Dictionary) -> float:
	var d := dir
	if d.length_squared() < 1e-8:
		return 0.0
	d = d.normalized()
	var r := _polyhedron_radius(d, params)
	r += _chip_relief(d, params)

	var craters: Variant = params.get("craters", [])
	if typeof(craters) == TYPE_ARRAY:
		for crater_variant in craters:
			if typeof(crater_variant) != TYPE_DICTIONARY:
				continue
			var crater: Dictionary = crater_variant
			r += _crater_radius_delta(d, crater)
	return maxf(r, 0.05)


static func compute_radius_max(params: Dictionary) -> float:
	var max_r := 0.0
	for sample in _radius_sample_dirs():
		max_r = maxf(max_r, radius(sample, params))
	for planes_variant in [params.get("planes", []), params.get("craters", [])]:
		if typeof(planes_variant) != TYPE_ARRAY:
			continue
		for entry in planes_variant:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var dir: Vector3 = entry.get("normal", entry.get("dir", Vector3.UP))
			max_r = maxf(max_r, radius(dir, params))
	return max_r * 1.06


static func shader_plane_dirs(params: Dictionary) -> PackedVector3Array:
	var packed := PackedVector3Array()
	packed.resize(MAX_PLANES)
	for i in MAX_PLANES:
		packed[i] = Vector3(0.0, 0.0, 1.0)
	var planes: Variant = params.get("planes", [])
	if typeof(planes) != TYPE_ARRAY:
		return packed
	for i in mini(planes.size(), MAX_PLANES):
		var plane: Dictionary = planes[i]
		packed[i] = plane.get("normal", Vector3.UP)
	return packed


static func shader_plane_offsets(params: Dictionary) -> PackedFloat32Array:
	var packed := PackedFloat32Array()
	packed.resize(MAX_PLANES)
	for i in MAX_PLANES:
		packed[i] = 1.0
	var planes: Variant = params.get("planes", [])
	if typeof(planes) != TYPE_ARRAY:
		return packed
	for i in mini(planes.size(), MAX_PLANES):
		var plane: Dictionary = planes[i]
		packed[i] = float(plane.get("offset", 1.0))
	return packed


static func shader_crater_dirs(params: Dictionary) -> PackedVector3Array:
	var packed := PackedVector3Array()
	packed.resize(MAX_CRATERS)
	for i in MAX_CRATERS:
		packed[i] = Vector3.UP
	var craters: Variant = params.get("craters", [])
	if typeof(craters) != TYPE_ARRAY:
		return packed
	for i in mini(craters.size(), MAX_CRATERS):
		var crater: Dictionary = craters[i]
		packed[i] = crater.get("dir", Vector3.UP)
	return packed


static func shader_crater_angular_radii(params: Dictionary) -> PackedFloat32Array:
	var packed := PackedFloat32Array()
	packed.resize(MAX_CRATERS)
	for i in MAX_CRATERS:
		packed[i] = 0.0
	var craters: Variant = params.get("craters", [])
	if typeof(craters) != TYPE_ARRAY:
		return packed
	for i in mini(craters.size(), MAX_CRATERS):
		var crater: Dictionary = craters[i]
		packed[i] = float(crater.get("angular_radius", 0.0))
	return packed


static func shader_crater_depths(params: Dictionary) -> PackedFloat32Array:
	var packed := PackedFloat32Array()
	packed.resize(MAX_CRATERS)
	for i in MAX_CRATERS:
		packed[i] = 0.0
	var craters: Variant = params.get("craters", [])
	if typeof(craters) != TYPE_ARRAY:
		return packed
	for i in mini(craters.size(), MAX_CRATERS):
		var crater: Dictionary = craters[i]
		packed[i] = float(crater.get("depth", 0.0))
	return packed


static func shader_crater_phases(params: Dictionary) -> PackedFloat32Array:
	var packed := PackedFloat32Array()
	packed.resize(MAX_CRATERS)
	for i in MAX_CRATERS:
		packed[i] = 0.0
	var craters: Variant = params.get("craters", [])
	if typeof(craters) != TYPE_ARRAY:
		return packed
	for i in mini(craters.size(), MAX_CRATERS):
		var crater: Dictionary = craters[i]
		packed[i] = float(crater.get("phase", 0.0))
	return packed


static func palette_mean_brightness(params: Dictionary) -> float:
	var a: Vector3 = params.get("colour_a", Vector3.ONE)
	var b: Vector3 = params.get("colour_b", Vector3.ONE)
	return (a.x + a.y + a.z + b.x + b.y + b.z) / 6.0


static func _polyhedron_radius(dir: Vector3, params: Dictionary) -> float:
	var rho := INF
	var planes: Variant = params.get("planes", [])
	if typeof(planes) != TYPE_ARRAY or planes.is_empty():
		return _ellipsoid_radius(dir, params.get("ellipsoid", Vector3.ONE))
	for plane_variant in planes:
		if typeof(plane_variant) != TYPE_DICTIONARY:
			continue
		var plane: Dictionary = plane_variant
		var normal: Vector3 = plane.get("normal", Vector3.UP)
		var offset := float(plane.get("offset", 1.0))
		var dot_dn := maxf(dir.dot(normal.normalized()), PLANE_DOT_FLOOR)
		rho = minf(rho, offset / dot_dn)
	return rho if is_finite(rho) else 1.0


static func _chip_relief(dir: Vector3, params: Dictionary) -> float:
	var amp := float(params.get("chip_amplitude", 0.06))
	var freq := float(params.get("chip_frequency", CHIP_FREQUENCY))
	var relief := float(params.get("relief_scale", 1.0))
	var seed_f := float(params.get("seed_f", 0.0))
	var sample := dir * freq
	var noise := _value_noise3(sample, seed_f)
	var ridge := 1.0 - absf(2.0 * noise - 1.0)
	return amp * ridge * relief


static func _crater_radius_delta(dir: Vector3, crater: Dictionary) -> float:
	var cdir: Vector3 = crater.get("dir", Vector3.UP)
	var angular_radius := float(crater.get("angular_radius", 0.15))
	var depth := float(crater.get("depth", 0.04))
	var phase := float(crater.get("phase", 0.0))
	var cn := cdir.normalized()
	var cdot := clampf(dir.dot(cn), -1.0, 1.0)
	var cangle := acos(cdot)
	var tangent_angle := _crater_tangent_angle(dir, cn)
	var wobble := 1.0 + 0.12 * sin(tangent_angle * 3.0 + phase)
	var eff_r := angular_radius * wobble
	if cangle > eff_r * 1.2:
		return 0.0
	var u := cangle / maxf(eff_r, 1e-5)
	var bowl := 0.0
	if u < 0.28:
		bowl = 1.0
	elif u < 0.52:
		var t := (u - 0.28) / 0.24
		bowl = 1.0 - pow(t, 0.35)
	elif u < 0.78:
		bowl = 0.0
	else:
		return 0.0
	var rim := 0.0
	if u >= 0.52 and u < 0.78:
		rim = smoothstep(0.52, 0.62, u) * (1.0 - smoothstep(0.68, 0.78, u))
	return -depth * bowl + depth * 0.5 * rim


static func _crater_tangent_angle(dir: Vector3, cn: Vector3) -> float:
	var ref := Vector3(0.0, 0.0, 1.0)
	if absf(cn.dot(ref)) > 0.92:
		ref = Vector3(1.0, 0.0, 0.0)
	var tangent := ref.cross(cn).normalized()
	var bitangent := cn.cross(tangent).normalized()
	var proj := dir - cn * dir.dot(cn)
	if proj.length_squared() < 1e-8:
		return 0.0
	proj = proj.normalized()
	return atan2(proj.dot(bitangent), proj.dot(tangent))


static func _hash31(p: Vector3, seed_f: float) -> float:
	var dot := p.x * 127.1 + p.y * 311.7 + p.z * 74.7 + seed_f * 17.0
	return fposmod(sin(dot) * 43758.5453, 1.0)


static func _value_noise3(p: Vector3, seed_f: float) -> float:
	var i := p.floor()
	var f := p - i
	var u := Vector3(
		f.x * f.x * (3.0 - 2.0 * f.x),
		f.y * f.y * (3.0 - 2.0 * f.y),
		f.z * f.z * (3.0 - 2.0 * f.z)
	)
	var n000 := _hash31(i, seed_f)
	var n100 := _hash31(i + Vector3(1, 0, 0), seed_f)
	var n010 := _hash31(i + Vector3(0, 1, 0), seed_f)
	var n110 := _hash31(i + Vector3(1, 1, 0), seed_f)
	var n001 := _hash31(i + Vector3(0, 0, 1), seed_f)
	var n101 := _hash31(i + Vector3(1, 0, 1), seed_f)
	var n011 := _hash31(i + Vector3(0, 1, 1), seed_f)
	var n111 := _hash31(i + Vector3(1, 1, 1), seed_f)
	var n00 := lerpf(n000, n100, u.x)
	var n10 := lerpf(n010, n110, u.x)
	var n01 := lerpf(n001, n101, u.x)
	var n11 := lerpf(n011, n111, u.x)
	var n0 := lerpf(n00, n10, u.y)
	var n1 := lerpf(n01, n11, u.y)
	return lerpf(n0, n1, u.z)


static func _ellipsoid_radius(dir: Vector3, ellipsoid: Vector3) -> float:
	var ex := maxf(ellipsoid.x, 0.01)
	var ey := maxf(ellipsoid.y, 0.01)
	var ez := maxf(ellipsoid.z, 0.01)
	var inv := Vector3(dir.x / ex, dir.y / ey, dir.z / ez)
	var denom := inv.length()
	if denom < 1e-8:
		return maxf(maxf(ex, ey), ez)
	return 1.0 / denom


static func _random_unit(rng: RandomNumberGenerator) -> Vector3:
	var u := rng.randf()
	var v := rng.randf()
	var theta := TAU * u
	var phi := acos(clampf(2.0 * v - 1.0, -1.0, 1.0))
	return Vector3(sin(phi) * cos(theta), sin(phi) * sin(theta), cos(phi))


static func _colour_to_vec3(colour: Color) -> Vector3:
	return Vector3(colour.r, colour.g, colour.b)
