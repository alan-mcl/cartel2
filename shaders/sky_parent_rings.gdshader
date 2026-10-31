shader_type canvas_item;

uniform sampler2D ring_profile : repeat_disable, filter_linear;
uniform vec3 sun_direction = vec3(0.85, 0.25, 0.45);
uniform vec3 axis = vec3(0.0, 0.0, 1.0);
uniform float outer_radius = 2.0;
uniform float ring_brightness = 1.0;
uniform float shadow_strength = 0.5;
uniform float shadow_softness = 0.03;
uniform float render_front = 1.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float quad_r = length(centered);
	COLOR = vec4(0.0);
	if (quad_r <= 0.5 + 0.01) {
		vec3 spin_axis = normalize(axis);
		// Screen position in planetary radii (quad edge = outer_radius).
		vec2 planetary_xy = centered * 2.0 * outer_radius;
		// Point on the equatorial plane (normal = spin axis) under this screen pixel.
		float axis_z = spin_axis.z;
		if (abs(axis_z) < 0.001) {
			axis_z = 0.001 * sign(axis_z + 0.0001);
		}
		float z_on_plane = -(planetary_xy.x * spin_axis.x + planetary_xy.y * spin_axis.y) / axis_z;
		vec3 plane_point = vec3(planetary_xy.x, planetary_xy.y, z_on_plane);
		float radial = length(plane_point);
		bool is_front = plane_point.z >= 0.0;
		bool want_front = render_front > 0.5;
		if (is_front == want_front && radial >= 0.98 && radial <= outer_radius + 0.03) {
			float profile_u = clamp(radial / outer_radius, 0.0, 1.0);
			vec4 profile = texture(ring_profile, vec2(profile_u, 0.5));
			if (profile.a > 0.001) {
				vec3 light_dir = normalize(sun_direction);
				vec3 ring_normal = spin_axis;
				float ndl = max(dot(ring_normal, light_dir), 0.0);
				float lit = 0.35 + ndl * 0.65;
				vec3 light_from = normalize(-light_dir);
				float t_hit = 1.0;
				float denom = dot(light_from, ring_normal);
				if (abs(denom) > 0.001) {
					float t = -dot(vec3(0.0), ring_normal) / denom;
					vec3 hit = light_from * t;
					if (length(hit.xy) < 1.0 && hit.z > 0.0) {
						t_hit = smoothstep(0.0, shadow_softness + 0.001, t - 1.0);
					}
				}
				float shadow = mix(1.0 - shadow_strength, 1.0, t_hit);
				vec3 col = profile.rgb * ring_brightness * lit * shadow;
				COLOR = vec4(col, profile.a);
			}
		}
	}
}
