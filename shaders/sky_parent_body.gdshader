shader_type canvas_item;

uniform vec3 base_tint : source_color = vec3(0.55, 0.48, 0.42);
uniform vec3 highlight_tint : source_color = vec3(0.72, 0.68, 0.62);
uniform vec3 sun_direction = vec3(0.85, 0.25, 0.45);
uniform float appearance_mix = 0.0;
uniform float ring_mode = 0.0;
uniform float seed = 0.0;
uniform float band_angle = 0.0;

const float SMALL_RING = 1.4;
const float BROAD_RING = 2.2;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float band_noise(vec2 uv, float s) {
	vec2 p = uv * vec2(3.0 + s * 0.7, 8.0 + s * 1.3);
	float n = sin(p.y + sin(p.x * 2.1 + s) * 0.6);
	n += 0.5 * sin(p.y * 1.7 + p.x * 0.4 + s * 2.0);
	return n * 0.5 + 0.5;
}

vec3 band_pole(float angle, float s) {
	float tilt = 0.2 + 0.65 * fract(s * 17.0 + 0.31);
	return normalize(vec3(sin(angle) * cos(tilt), sin(tilt), cos(angle) * cos(tilt)));
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered);
	float disc_r = 0.42;
	float ring_scale = mix(SMALL_RING, BROAD_RING, smoothstep(0.01, 0.99, ring_mode));
	float ring_outer = disc_r * mix(1.0, ring_scale, step(0.01, ring_mode));

	if (dist > ring_outer + 0.02) {
		COLOR = vec4(0.0);
	} else if (ring_mode > 0.01 && dist > disc_r && dist <= ring_outer) {
		float ring_mid = disc_r + (ring_outer - disc_r) * 0.55;
		float band = smoothstep(ring_mid - 0.04, ring_mid, dist) * (1.0 - smoothstep(ring_mid + 0.02, ring_outer, dist));
		float tilt = 0.35 + 0.15 * sin(seed);
		float edge = abs(centered.y / max(disc_r, 0.001)) - tilt;
		float ring_alpha = band * smoothstep(0.15, 0.0, edge) * 0.55;
		vec3 ring_col = mix(base_tint, highlight_tint, 0.35);
		COLOR = vec4(ring_col, ring_alpha);
	} else if (dist <= disc_r) {
		vec2 sphere_uv = centered / disc_r;
		float z = sqrt(max(0.0, 1.0 - dot(sphere_uv, sphere_uv)));
		vec3 normal = normalize(vec3(sphere_uv, z));
		vec3 light_dir = normalize(sun_direction);
		float ndl = clamp(dot(normal, light_dir), 0.0, 1.0);
		float limb = pow(z, 0.35);
		vec3 pole = band_pole(band_angle, seed);
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
		vec3 albedo = mix(base_tint, highlight_tint, bands * 0.55);
		albedo = mix(albedo, albedo * vec3(0.85, 0.9, 1.0), appearance_mix * 0.25);
		float shade = mix(0.12, 1.0, ndl) * limb;
		COLOR = vec4(albedo * shade, 1.0);
	} else {
		COLOR = vec4(0.0);
	}
}
