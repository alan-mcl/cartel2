shader_type canvas_item;

uniform float fade_end : hint_range(0.01, 0.5) = 0.12;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float edge = smoothstep(0.0, fade_end, UV.x);
	COLOR = vec4(tex_color.rgb, tex_color.a * edge);
}
