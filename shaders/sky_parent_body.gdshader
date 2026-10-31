shader_type canvas_item;

uniform vec3 colours[6];
uniform int colour_count = 2;
uniform vec3 sun_direction = vec3(0.85, 0.25, 0.45);
uniform vec3 axis = vec3(0.0, 0.0, 1.0);
uniform float seed = 0.0;
uniform float rotation_phase = 0.0;
uniform float band_count = 12.0;
uniform float band_frequency = 1.0;
uniform float band_width_variation = 0.35;
uniform float band_contrast = 0.55;
uniform float band_distortion = 0.2;
uniform float band_turbulence = 0.0;
uniform float band_edge_softness = 0.25;
uniform float band_fine_detail = 0.2;
uniform float turbulence_scale = 2.0;
uniform float turbulence_octaves = 2.0;
uniform vec3 polar_colour : source_color = vec3(1.0, 1.0, 1.0);
uniform float polar_blend = 0.0;
uniform float ambient_light = 0.12;
uniform float light_intensity = 1.0;
uniform float limb_darkening = 1.0;
uniform float limb_curve = 0.35;
uniform float terminator_softness = 0.08;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, float octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		if (float(i) >= octaves) {
			break;
		}
		value += amplitude * value_noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

vec3 sample_palette(float t) {
	int count = clamp(colour_count, 2, 6);
	float scaled = clamp(t, 0.0, 1.0) * float(count - 1);
	float idx = floor(scaled);
	float frac = fract(scaled);
	vec3 c0 = colours[int(idx)];
	vec3 c1 = colours[int(min(idx + 1.0, float(count - 1)))];
	return mix(c0, c1, frac);
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float euc_dist = length(centered);
	float disc_r = 0.5;
	COLOR = vec4(0.0);
	if (euc_dist <= disc_r + 0.015) {
		float edge_aa = smoothstep(disc_r + 0.015, disc_r - 0.01, euc_dist);
		vec2 sphere_uv = centered / disc_r;
		float z = sqrt(max(0.0, 1.0 - dot(sphere_uv, sphere_uv)));
		vec3 normal = normalize(vec3(sphere_uv, z));
		vec3 spin_axis = normalize(axis);
		vec3 ref = abs(spin_axis.z) < 0.92 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		vec3 tangent = normalize(cross(ref, spin_axis));
		vec3 bitangent = cross(spin_axis, tangent);
		float latitude = asin(clamp(dot(normal, spin_axis), -1.0, 1.0));
		float longitude = atan(dot(normal, tangent), dot(normal, bitangent)) + rotation_phase;
		vec2 warp_uv = vec2(longitude * 2.0 + seed, latitude * 4.0 + seed * 1.7);
		float warp = (fbm(warp_uv * turbulence_scale, turbulence_octaves) - 0.5) * 2.0;
		latitude += warp * band_turbulence * 0.35 + sin(longitude * 3.0 + seed) * band_distortion * 0.12;
		float band_phase = latitude * band_count * band_frequency;
		band_phase += sin(longitude * 2.0 + seed * 2.0) * band_width_variation;
		band_phase += fbm(vec2(longitude, latitude) * 3.0 + seed, 2.0) * band_fine_detail;
		float bands = sin(band_phase) * 0.5 + 0.5;
		bands = mix(0.5, bands, band_contrast);
		float soft = mix(0.02, 0.2, band_edge_softness);
		bands = smoothstep(0.5 - soft, 0.5 + soft, bands);
		vec3 albedo = sample_palette(bands);
		float polar = smoothstep(0.55, 1.2, abs(latitude));
		albedo = mix(albedo, polar_colour, polar * polar_blend);
		vec3 light_dir = normalize(sun_direction);
		float ndl = dot(normal, light_dir);
		ndl = smoothstep(-terminator_softness, 1.0, ndl);
		ndl = max(ndl, 0.0);
		float limb = pow(z, limb_curve);
		float shade = mix(ambient_light, 1.0, ndl * light_intensity);
		shade *= mix(1.0, limb, limb_darkening);
		COLOR = vec4(albedo * shade, edge_aa);
	}
}
