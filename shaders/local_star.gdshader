shader_type canvas_item;
render_mode blend_add;

uniform vec3 corona_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float luminosity = 1.0;
uniform float disc_uv_radius = 0.12;
uniform float corona_uv_radius = 0.48;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered);

	if (dist > corona_uv_radius) {
		COLOR = vec4(0.0);
	} else if (dist <= disc_uv_radius) {
		float core = 1.0 - smoothstep(disc_uv_radius * 0.65, disc_uv_radius, dist);
		COLOR = vec4(vec3(1.0), core * luminosity);
	} else {
		float t = (dist - disc_uv_radius) / max(corona_uv_radius - disc_uv_radius, 0.001);
		float falloff = pow(1.0 - clamp(t, 0.0, 1.0), 2.2);
		vec3 glow = corona_color * falloff * luminosity * 0.85;
		COLOR = vec4(glow, falloff * luminosity * 0.55);
	}
}
