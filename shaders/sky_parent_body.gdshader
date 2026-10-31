shader_type canvas_item;

uniform vec3 band_colour_1 : source_color = vec3(0.55, 0.48, 0.42);
uniform vec3 band_colour_2 : source_color = vec3(0.72, 0.68, 0.62);
uniform vec3 ring_colour : source_color = vec3(0.72, 0.68, 0.62);
uniform vec3 sun_direction = vec3(0.85, 0.25, 0.45);
uniform float appearance_mix = 0.0;
uniform float ring_outer_scale = 1.0;
uniform float seed = 0.0;
uniform float band_angle = 0.0;
uniform float axis_inclination = 0.524;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float band_noise(vec2 uv, float s) {
	vec2 p = uv * vec2(3.0 + s * 0.7, 8.0 + s * 1.3);
	float n = sin(p.y + sin(p.x * 2.1 + s) * 0.6);
	n += 0.5 * sin(p.y * 1.7 + p.x * 0.4 + s * 2.0);
	return n * 0.5 + 0.5;
}

vec3 band_pole(float angle, float tilt) {
	return normalize(vec3(sin(angle) * cos(tilt), sin(tilt), cos(angle) * cos(tilt)));
}

vec4 sample_equatorial_ring(
	vec2 centered,
	float disc_r,
	float uv_outer,
	float ring_scale,
	vec3 pole
) {
	if (ring_scale <= 1.001) {
		return vec4(0.0);
	}
	vec2 pole_xy = pole.xy;
	float plen = length(pole_xy);
	vec2 minor_dir = plen > 0.0001 ? pole_xy / plen : vec2(1.0, 0.0);
	vec2 major_dir = vec2(-minor_dir.y, minor_dir.x);
	float face_on = max(abs(pole.z), 0.06);
	float along_major = dot(centered, major_dir);
	float along_minor = dot(centered, minor_dir);
	float ring_dist = length(vec2(along_major, along_minor / face_on));
	if (ring_dist <= disc_r || ring_dist > uv_outer) {
		return vec4(0.0);
	}
	vec3 eq_a = cross(vec3(0.0, 0.0, 1.0), pole);
	float eq_a_len = length(eq_a);
	if (eq_a_len < 0.001) {
		eq_a = cross(vec3(1.0, 0.0, 0.0), pole);
		eq_a_len = length(eq_a);
	}
	eq_a /= eq_a_len;
	vec3 eq_b = cross(pole, eq_a);
	vec3 plane_pos = eq_a * (along_major / max(disc_r, 0.001))
		+ eq_b * (along_minor / max(disc_r, 0.001));
	float plane_len = length(plane_pos);
	float ring_z = plane_len > 0.001 ? plane_pos.z / plane_len : pole.z;
	if (ring_z < 0.0) {
		return vec4(0.0);
	}
	float ring_mid = disc_r + (uv_outer - disc_r) * 0.55;
	float band = smoothstep(ring_mid - 0.04, ring_mid, ring_dist)
		* (1.0 - smoothstep(ring_mid + 0.02, uv_outer, ring_dist));
	return vec4(ring_colour, band * 0.55);
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float euc_dist = length(centered);
	float ring_scale = max(ring_outer_scale, 1.0);
	float disc_r = 0.5 / ring_scale;
	float uv_outer = 0.5;

	COLOR = vec4(0.0);
	if (euc_dist <= uv_outer + 0.02) {
		vec3 pole = band_pole(band_angle, axis_inclination);
		vec4 ring_sample = sample_equatorial_ring(centered, disc_r, uv_outer, ring_scale, pole);

		if (euc_dist <= disc_r) {
			vec2 sphere_uv = centered / disc_r;
			float z = sqrt(max(0.0, 1.0 - dot(sphere_uv, sphere_uv)));
			vec3 normal = normalize(vec3(sphere_uv, z));
			vec3 light_dir = normalize(sun_direction);
			float ndl = clamp(dot(normal, light_dir), 0.0, 1.0);
			float limb = pow(z, 0.35);
			vec3 ref_dir = abs(pole.y) < 0.92 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
			vec3 tangent = normalize(cross(ref_dir, pole));
			float band_lat = dot(normal, pole);
			float band_lon = dot(normal, tangent);
			float bands = band_noise(vec2(band_lat * 4.0 + seed, band_lon * 6.0 + seed * 1.7), seed);
			float ca = cos(band_angle);
			float sa = sin(band_angle);
			vec2 rot_uv = vec2(
				sphere_uv.x * ca - sphere_uv.y * sa,
				sphere_uv.x * sa + sphere_uv.y * ca
			);
			bands = mix(bands, hash21(rot_uv * 4.0 + seed), appearance_mix * 0.85);
			vec3 albedo = mix(band_colour_1, band_colour_2, bands * 0.55);
			albedo = mix(albedo, albedo * vec3(0.85, 0.9, 1.0), appearance_mix * 0.25);
			float shade = mix(0.12, 1.0, ndl) * limb;
			vec4 disc_color = vec4(albedo * shade, 1.0);
			COLOR = disc_color;
			if (ring_sample.a > 0.0) {
				vec3 eq_a = cross(vec3(0.0, 0.0, 1.0), pole);
				float eq_a_len = length(eq_a);
				if (eq_a_len < 0.001) {
					eq_a = cross(vec3(1.0, 0.0, 0.0), pole);
					eq_a_len = length(eq_a);
				}
				eq_a /= eq_a_len;
				vec3 eq_b = cross(pole, eq_a);
				vec2 pole_xy = pole.xy;
				float plen = length(pole_xy);
				vec2 minor_dir = plen > 0.0001 ? pole_xy / plen : vec2(1.0, 0.0);
				vec2 major_dir = vec2(-minor_dir.y, minor_dir.x);
				float along_major = dot(centered, major_dir);
				float along_minor = dot(centered, minor_dir);
				vec3 plane_pos = eq_a * (along_major / max(disc_r, 0.001))
					+ eq_b * (along_minor / max(disc_r, 0.001));
				float plane_len = length(plane_pos);
				float ring_z = plane_len > 0.001 ? plane_pos.z / plane_len : pole.z;
				if (ring_z > z) {
					COLOR = ring_sample;
				}
			}
		} else {
			COLOR = ring_sample;
		}
	}
}
