shader_type canvas_item;
render_mode blend_add;

uniform vec2 flare_center = vec2(0.5, 0.5);
uniform float intensity = 0.0;
uniform vec3 flare_color : source_color = vec3(1.0, 0.92, 0.78);

void fragment() {
	vec2 screen_center = vec2(0.5);
	vec2 centered = UV - screen_center;
	vec2 axis_vec = flare_center - screen_center;
	float axis_len = length(axis_vec);
	vec2 axis = axis_len > 0.001 ? axis_vec / axis_len : vec2(1.0, 0.0);
	vec2 perp_axis = vec2(-axis.y, axis.x);

	float along = dot(centered, axis);
	float perp = dot(centered, perp_axis);

	float dist_star = length(UV - flare_center);
	float core = exp(-dist_star * dist_star * 140.0) * intensity;
	float halo = exp(-dist_star * 16.0) * intensity * 0.28;

	float main_streak = exp(-perp * perp * 700.0) * exp(-abs(along) * 4.5);
	main_streak *= intensity * 0.45;

	float ghost_a = exp(-length(centered - axis * 0.18) * 55.0) * intensity * 0.12;
	float ghost_b = exp(-length(centered + axis * 0.12) * 70.0) * intensity * 0.08;
	float ghost_c = exp(-length(centered - axis * 0.32) * 45.0) * intensity * 0.06;

	vec3 rgb = flare_color * (core + halo + main_streak + ghost_a + ghost_b + ghost_c);
	float alpha = core + halo * 0.5 + main_streak * 0.35 + (ghost_a + ghost_b + ghost_c) * 0.5;
	COLOR = vec4(rgb, alpha);
}
