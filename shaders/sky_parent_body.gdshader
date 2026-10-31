shader_type canvas_item;

uniform vec3 colours[6];
uniform int colour_count = 2;
uniform int band_palette[32];
uniform int scheme = 0;
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
uniform float band_edge_softness = 0.4;
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

vec3 palette_mean() {
	int n = clamp(colour_count, 1, 6);
	vec3 sum = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		if (i >= n) {
			break;
		}
		sum += colours[i];
	}
	return sum / float(n);
}

vec3 sample_palette_ramp(float t) {
	int count = clamp(colour_count, 1, 6);
	if (count <= 1) {
		return colours[0];
	}
	float scaled = clamp(t, 0.0, 1.0) * float(count - 1);
	float idx = floor(scaled);
	float frac = fract(scaled);
	vec3 c0 = colours[int(idx)];
	vec3 c1 = colours[int(min(idx + 1.0, float(count - 1)))];
	return mix(c0, c1, frac);
}

vec3 colour_at(int idx) {
	vec3 result = colours[0];
	for (int i = 0; i < 6; i++) {
		if (i == idx) {
			result = colours[i];
		}
	}
	return result;
}

int palette_at(int slot) {
	int s = clamp(slot, 0, 31);
	int value = band_palette[0];
	for (int i = 0; i < 32; i++) {
		if (i == s) {
			value = band_palette[i];
		}
	}
	return clamp(value, 0, 5);
}

vec3 belt_colour(int belt_index) {
	return colour_at(palette_at(belt_index));
}

vec3 blend_belts(float coord, float softness) {
	float half_span = clamp(softness, 0.0, 1.0) * 0.5;
	half_span = max(half_span, fwidth(coord));
	float f = fract(coord);
	int i0 = int(floor(coord));
	vec3 here = belt_colour(i0);
	vec3 prev_c = belt_colour(i0 - 1);
	vec3 next_c = belt_colour(i0 + 1);
	float span = max(half_span, 0.0001);
	float w_prev = (1.0 - smoothstep(0.0, span, f)) * 0.5;
	float w_next = smoothstep(1.0 - span, 1.0, f) * 0.5;
	float w_here = max(0.0, 1.0 - w_prev - w_next);
	float w_sum = w_here + w_prev + w_next;
	if (w_sum > 0.0001) {
		w_here /= w_sum;
		w_prev /= w_sum;
		w_next /= w_sum;
	}
	return here * w_here + prev_c * w_prev + next_c * w_next;
}

vec3 apply_contrast(vec3 c) {
	return mix(palette_mean(), c, band_contrast);
}

vec3 sample_banded_albedo(float latitude, float longitude, vec2 warp_uv) {
	float norm_lat = (latitude + 1.5707963) / 3.14159265;
	float band_coord = norm_lat * band_count * band_frequency;
	band_coord += sin(longitude * 2.0 + seed * 2.0) * band_width_variation * 0.35;
	vec3 c = blend_belts(band_coord, band_edge_softness);
	float detail = fbm(vec2(longitude, latitude) * 3.0 + seed, 2.0);
	c *= mix(1.0, 0.78 + detail * 0.44, band_fine_detail);
	return apply_contrast(c);
}

vec3 sample_mottled_albedo(vec2 warp_uv) {
	float mottle = fbm(warp_uv * turbulence_scale * 0.45, turbulence_octaves);
	float cells = mottle * float(max(colour_count, 1)) * 5.0 + seed * 17.0;
	return apply_contrast(blend_belts(cells, band_edge_softness));
}

vec3 sample_gradient_albedo(float latitude, vec2 warp_uv) {
	float norm_lat = (latitude + 1.5707963) / 3.14159265;
	float warp = (fbm(warp_uv * turbulence_scale * 0.35, turbulence_octaves) - 0.5) * band_edge_softness * 0.2;
	norm_lat = clamp(norm_lat + warp, 0.0, 1.0);
	return sample_palette_ramp(norm_lat);
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
		float warped_lat = latitude + warp * band_turbulence * 0.35 + sin(longitude * 3.0 + seed) * band_distortion * 0.12;
		vec3 albedo = colours[0];
		if (scheme == 1) {
			albedo = colours[0];
		} else if (scheme == 2) {
			albedo = sample_mottled_albedo(warp_uv);
		} else if (scheme == 3) {
			albedo = sample_gradient_albedo(warped_lat, warp_uv);
		} else {
			albedo = sample_banded_albedo(warped_lat, longitude, warp_uv);
		}
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
