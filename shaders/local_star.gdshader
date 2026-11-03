shader_type canvas_item;
render_mode blend_mix;

uniform vec3 disc_colour : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 corona_colour : source_color = vec3(1.0, 0.95, 0.85);
uniform float apparent_brightness = 1.0;
uniform float disc_uv_radius = 0.125;
uniform float corona_uv_radius = 0.5;
uniform float corona_radius_multiplier = 4.0;
uniform float disc_radius_world = 24.0;

uniform float limb_darkening = 0.45;
uniform float limb_curve = 1.6;
uniform float limb_colour_shift = 0.08;
uniform float surface_variation_strength = 0.1;
uniform float surface_variation_scale = 6.0;
uniform float colour_saturation = 1.0;
uniform float core_colour_mix = 0.62;
uniform float corona_colour_mix = 0.9;
uniform float corona_brightness = 0.9;
uniform float inner_glow_strength = 0.6;
uniform float corona_falloff = 2.2;
uniform float corona_distortion = 0.06;
uniform float corona_noise_strength = 0.08;
uniform float presentation_seed = 0.0;
uniform float flares_enabled = 0.0;
uniform float spikes_enabled = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

vec3 saturate_colour(vec3 rgb, float sat) {
	float l = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(l), rgb, sat);
}

vec3 limb_tint(vec3 base, float mu, float shift) {
	return mix(base, base * vec3(1.0 + shift, 1.0 - shift * 0.5, 1.0 - shift), 1.0 - mu);
}

float spike_term(vec2 centered, float dist, float angle) {
	if (spikes_enabled < 0.5) {
		return 0.0;
	}
	float spikes = 4.0;
	float rot = presentation_seed * 6.283;
	float a = atan(centered.y, centered.x) + rot;
	float spike = pow(abs(cos(a * spikes * 0.5)), 8.0);
	float len = smoothstep(disc_uv_radius, corona_uv_radius * 0.95, dist);
	return spike * len * 0.35;
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered);
	float angle = atan(centered.y, centered.x);

	if (dist > corona_uv_radius) {
		COLOR = vec4(0.0);
	} else {
		vec3 base = saturate_colour(disc_colour, colour_saturation);
		vec3 core_rgb = mix(base, vec3(1.0), core_colour_mix);
		vec3 corona_rgb = mix(base, corona_colour, corona_colour_mix);

		float disc_r = max(disc_uv_radius, 0.0001);
		float radial = clamp(1.0 - dist / disc_r, 0.0, 1.0);
		float mu = pow(radial, limb_curve);
		float limb_floor = 1.0 - limb_darkening * 0.55;
		vec3 disc_rgb = limb_tint(core_rgb, mu, limb_colour_shift) * mix(limb_floor, 1.0, mu);
		if (surface_variation_strength > 0.001) {
			vec2 sp = centered * surface_variation_scale + vec2(presentation_seed * 17.0, TIME * 0.05);
			float surf = (noise(sp) - 0.5) * surface_variation_strength;
			disc_rgb *= clamp(1.0 + surf, 0.85, 1.15);
		}

		// Opaque photosphere. blend_add cannot hide the starfield; mix with alpha 1 does.
		float disc_a = 1.0 - smoothstep(disc_r * 0.97, disc_r * 1.04, dist);
		vec3 body = mix(disc_rgb, vec3(1.0), clamp(apparent_brightness * 0.35, 0.0, 0.55));

		float corona_dist = dist;
		if (corona_distortion > 0.001) {
			float n = noise(centered * 12.0 + vec2(presentation_seed * 31.0, angle));
			corona_dist += (n - 0.5) * corona_distortion * 0.08;
		}

		float glow_in = disc_r * 0.88;
		float glow_out = disc_r * 1.12;
		float inner_t = 1.0 - smoothstep(glow_in, glow_out, corona_dist);
		float inner_glow = pow(max(inner_t, 0.0), 1.2) * inner_glow_strength;

		float outer_t = (corona_dist - glow_in) / max(corona_uv_radius - glow_in, 0.001);
		float outer_falloff = pow(1.0 - clamp(outer_t, 0.0, 1.0), corona_falloff);
		float corona_a = (inner_glow + outer_falloff * corona_brightness) * apparent_brightness;
		corona_a *= smoothstep(disc_r * 0.9, disc_r * 1.05, dist);

		if (flares_enabled > 0.5) {
			float flare_a = angle + TIME * 0.4 + presentation_seed * 12.0;
			float flare = pow(max(cos(flare_a * 3.0), 0.0), 6.0);
			flare *= smoothstep(disc_r * 0.9, corona_uv_radius, dist);
			corona_a += flare * 0.2 * apparent_brightness;
		}

		corona_a += spike_term(centered, dist, angle) * apparent_brightness;
		corona_a = clamp(corona_a, 0.0, 0.85);

		float out_a = disc_a + corona_a * (1.0 - disc_a);
		if (out_a < 0.00001) {
			COLOR = vec4(0.0);
		} else {
			vec3 out_rgb = (body * disc_a + corona_rgb * corona_a * (1.0 - disc_a)) / out_a;
			COLOR = vec4(clamp(out_rgb, vec3(0.0), vec3(1.0)), out_a);
		}
	}
}
