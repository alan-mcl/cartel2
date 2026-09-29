shader_type spatial;
render_mode cull_back, unshaded;

uniform vec4 planet_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D night_lights : filter_linear_mipmap, repeat_enable;
uniform float use_albedo_map = 0.0;
uniform float use_night_lights = 0.0;
uniform vec3 sun_direction = vec3(0.85, 0.25, 0.45);
uniform float night_emission_strength = 1.6;
uniform float atmosphere_strength = 0.42;
uniform vec3 atmosphere_color : source_color = vec3(0.42, 0.62, 0.98);

float procedural_land(vec2 uv) {
	float a = sin(uv.x * TAU * 3.0 + sin(uv.y * TAU * 2.0) * 1.7) * 0.5 + 0.5;
	float b = cos(uv.y * TAU * 4.0 + cos(uv.x * TAU * 2.5) * 1.3) * 0.5 + 0.5;
	return smoothstep(0.38, 0.62, a * 0.55 + b * 0.45);
}

void fragment() {
	vec3 normal = normalize(NORMAL);
	vec3 sun_dir = normalize(sun_direction);
	vec3 view_dir = normalize(VIEW);
	float ndotl = dot(normal, sun_dir);

	vec3 base_color;
	if (use_albedo_map > 0.5) {
		base_color = texture(albedo_map, UV).rgb;
	} else {
		float land = procedural_land(UV);
		vec3 ocean = vec3(0.07, 0.14, 0.34);
		vec3 land_color = vec3(0.16, 0.30, 0.20);
		base_color = mix(ocean, land_color, land);
		base_color *= planet_tint.rgb;
	}

	float day = clamp(ndotl * 0.55 + 0.45, 0.0, 1.0);
	float night = 1.0 - day;
	vec3 lit = base_color * mix(0.06, 1.0, day);

	vec3 night_glow = vec3(0.0);
	if (use_night_lights > 0.5) {
		night_glow = texture(night_lights, UV).rgb * night_emission_strength * night;
	}

	float fresnel = pow(1.0 - clamp(abs(dot(normal, view_dir)), 0.0, 1.0), 2.8);
	vec3 atmosphere = atmosphere_color * fresnel * atmosphere_strength;

	vec3 final_color = lit + night_glow + atmosphere;
	ALBEDO = final_color;
}
