shader_type canvas_item;

const int MAX_PLANES = 12;
const int MAX_CRATERS = 4;
const int RAY_STEPS = 22;
const float PLANE_DOT_FLOOR = 0.2;
const float CHIP_FREQUENCY = 5.0;

uniform int plane_count = 10;
uniform vec3 plane_dirs[MAX_PLANES];
uniform float plane_offsets[MAX_PLANES];
uniform float chip_amplitude = 0.065;
uniform int crater_count = 0;
uniform vec3 crater_dirs[MAX_CRATERS];
uniform float crater_angular_radii[MAX_CRATERS];
uniform float crater_depths[MAX_CRATERS];
uniform float crater_phases[MAX_CRATERS];
uniform vec3 colour_a = vec3(0.54, 0.49, 0.45);
uniform vec3 colour_b = vec3(0.36, 0.33, 0.31);
uniform float spec_strength = 0.08;
uniform float relief_scale = 1.0;
uniform float shape_seed = 0.0;
uniform float radius_max = 1.05;
uniform vec3 sun_direction = vec3(-0.6, -0.5, 0.62);
uniform float sun_irradiance = 1.0;
uniform float display_exposure = 2.5;

float asteroid_night_irradiance(float irradiance) {
	return min(0.035, 0.55 * max(irradiance, 0.0));
}

vec3 asteroid_tonemap_reinhard_chroma(vec3 rgb) {
	float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	if (luma <= 1e-8) {
		return rgb;
	}
	float mapped = luma / (1.0 + luma);
	return rgb * (mapped / luma);
}

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7)) + shape_seed * 17.0) * 43758.5453);
}

float value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	float n00 = mix(n000, n100, u.x);
	float n10 = mix(n010, n110, u.x);
	float n01 = mix(n001, n101, u.x);
	float n11 = mix(n011, n111, u.x);
	float n0 = mix(n00, n10, u.y);
	float n1 = mix(n01, n11, u.y);
	return mix(n0, n1, u.z);
}

float fbm3(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	vec3 shift = vec3(shape_seed * 3.1, shape_seed * 1.7, shape_seed * 2.3);
	for (int i = 0; i < 3; i++) {
		value += amplitude * value_noise3(p + shift);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

float chip_relief(vec3 dir_n) {
	float noise = value_noise3(dir_n * CHIP_FREQUENCY);
	float ridge = 1.0 - abs(2.0 * noise - 1.0);
	return chip_amplitude * ridge * relief_scale;
}

float polyhedron_radius(vec3 dir_n) {
	float rho = 1e6;
	for (int i = 0; i < MAX_PLANES; i++) {
		if (i >= plane_count) {
			break;
		}
		vec3 normal = normalize(plane_dirs[i]);
		float dot_dn = max(dot(dir_n, normal), PLANE_DOT_FLOOR);
		rho = min(rho, plane_offsets[i] / dot_dn);
	}
	return rho;
}

float crater_tangent_angle(vec3 dir_n, vec3 cn) {
	vec3 ref = abs(cn.z) < 0.92 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(ref, cn));
	vec3 bitangent = cross(cn, tangent);
	vec3 proj = dir_n - cn * dot(dir_n, cn);
	float len2 = dot(proj, proj);
	if (len2 < 1e-6) {
		return 0.0;
	}
	proj = proj * inversesqrt(len2);
	return atan(dot(proj, bitangent), dot(proj, tangent));
}

float crater_radius_delta(vec3 dir_n, vec3 cdir, float angular_radius, float depth, float phase) {
	vec3 cn = normalize(cdir);
	float cdot = clamp(dot(dir_n, cn), -1.0, 1.0);
	float cangle = acos(cdot);
	float tangent_angle = crater_tangent_angle(dir_n, cn);
	float wobble = 1.0 + 0.12 * sin(tangent_angle * 3.0 + phase);
	float eff_r = angular_radius * wobble;
	if (cangle > eff_r * 1.2) {
		return 0.0;
	}
	float u = cangle / max(eff_r, 1e-5);
	float bowl = 0.0;
	if (u < 0.28) {
		bowl = 1.0;
	} else if (u < 0.52) {
		float t = (u - 0.28) / 0.24;
		bowl = 1.0 - pow(t, 0.35);
	} else if (u >= 0.78) {
		return 0.0;
	}
	float rim = 0.0;
	if (u >= 0.52 && u < 0.78) {
		rim = smoothstep(0.52, 0.62, u) * (1.0 - smoothstep(0.68, 0.78, u));
	}
	return -depth * bowl + depth * 0.5 * rim;
}

float support_radius(vec3 dir_n) {
	float r = polyhedron_radius(dir_n);
	r += chip_relief(dir_n);
	for (int j = 0; j < MAX_CRATERS; j++) {
		if (j >= crater_count) {
			break;
		}
		r += crater_radius_delta(
			dir_n,
			crater_dirs[j],
			crater_angular_radii[j],
			crater_depths[j],
			crater_phases[j]
		);
	}
	return max(r, 0.05);
}

float implicit_sdf(vec3 p) {
	float len_p = length(p);
	if (len_p < 1e-5) {
		return -support_radius(vec3(0.0, 0.0, 1.0));
	}
	return len_p - support_radius(p / len_p);
}

void fragment() {
	vec2 centred = UV - vec2(0.5);
	float half_extent = 0.46;
	vec2 plane = centred / half_extent;
	COLOR = vec4(0.0);

	if (length(plane) <= 1.12) {
		vec3 hit = vec3(0.0);
		vec3 normal = vec3(0.0, 0.0, 1.0);
		bool found = false;
		float z_near = radius_max * 1.35;
		float z_far = -radius_max * 1.35;
		float px = plane.x * radius_max;
		float py = plane.y * radius_max;
		float sdf_prev = implicit_sdf(vec3(px, py, z_near));

		for (int step = 1; step < RAY_STEPS; step++) {
			float z = mix(z_near, z_far, float(step) / float(RAY_STEPS - 1));
			vec3 p = vec3(px, py, z);
			float sdf = implicit_sdf(p);
			if (sdf_prev > 0.0 && sdf <= 0.0) {
				float z0 = mix(z_near, z_far, float(step - 1) / float(RAY_STEPS - 1));
				float z1 = z;
				for (int refine = 0; refine < 6; refine++) {
					float zm = 0.5 * (z0 + z1);
					vec3 pm = vec3(px, py, zm);
					if (implicit_sdf(pm) > 0.0) {
						z0 = zm;
					} else {
						z1 = zm;
					}
				}
				hit = vec3(px, py, 0.5 * (z0 + z1));
				found = true;
				break;
			}
			sdf_prev = sdf;
		}

		if (found) {
			float eps = radius_max * 0.0035;
			vec3 dir_n = normalize(hit);
			normal = normalize(vec3(
				implicit_sdf(hit + vec3(eps, 0.0, 0.0)) - implicit_sdf(hit - vec3(eps, 0.0, 0.0)),
				implicit_sdf(hit + vec3(0.0, eps, 0.0)) - implicit_sdf(hit - vec3(0.0, eps, 0.0)),
				implicit_sdf(hit + vec3(0.0, 0.0, eps)) - implicit_sdf(hit - vec3(0.0, 0.0, eps))
			));

			vec3 warp = dir_n * 2.4 + vec3(shape_seed * 4.0, shape_seed * 2.0, shape_seed * 3.0);
			float n = fbm3(warp * 1.8);
			float relief = (n - 0.5) * 0.18 * relief_scale;
			vec3 albedo = mix(colour_a, colour_b, clamp(0.5 + n * 0.55 + relief, 0.0, 1.0));

			vec3 light_dir = normalize(sun_direction);
			float ndl = dot(normal, light_dir);
			float wrap = max(0.0, (ndl + 0.45) / 1.45);
			float cavity = clamp(-dot(normal, dir_n), 0.0, 1.0) * 0.25;
			float day_factor = wrap * (1.0 - cavity * 0.5);
			float stellar_irr = max(sun_irradiance, 0.0);
			float night_side = asteroid_night_irradiance(stellar_irr);
			float illum = night_side + stellar_irr * day_factor;
			vec3 radiance = albedo * illum;

			vec3 view_dir = vec3(0.0, 0.0, 1.0);
			vec3 half_vec = normalize(light_dir + view_dir);
			float spec_env = night_side + stellar_irr * max(ndl, 0.0);
			float spec = pow(max(dot(normal, half_vec), 0.0), 24.0) * spec_strength * spec_env;
			radiance += vec3(spec);

			vec3 lit = asteroid_tonemap_reinhard_chroma(radiance * display_exposure);
			float far_lift = 1.0 - smoothstep(0.00015, 0.045, stellar_irr);
			lit = min(lit + albedo * far_lift * 0.11, vec3(0.94));

			float sdf_edge = abs(implicit_sdf(hit));
			float alpha = 1.0 - smoothstep(radius_max * 0.006, radius_max * 0.016, sdf_edge);
			alpha *= smoothstep(1.05, 0.92, length(plane));
			COLOR = vec4(lit, alpha);
		}
	}
}
