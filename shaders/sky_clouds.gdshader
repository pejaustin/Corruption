// PLACEHOLDER: the cloud look (every cloud uniform default and value set in world.tscn), not designed by Austin.
// The world's sky: Godot's ProceduralSkyMaterial gradient and sun disc (same parameter names, so the day/night clock
// tints it the same way), plus a drifting cloud layer. Clouds are lit by the sun or moon (LIGHT0), so they darken at
// night on their own, and fade out toward the horizon so far views stay clear.
shader_type sky;

uniform vec4 sky_top_color : source_color = vec4(0.385, 0.454, 0.55, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.646, 0.656, 0.67, 1.0);
uniform float sky_curve : hint_range(0.0, 1.0) = 0.15;
uniform vec4 ground_bottom_color : source_color = vec4(0.2, 0.169, 0.133, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.646, 0.656, 0.67, 1.0);
uniform float ground_curve : hint_range(0.0, 1.0) = 0.02;
uniform float sun_angle_max = 0.5236;
uniform float sun_curve : hint_range(0.0, 1.0) = 0.15;

uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
// How much of the sky is cloud (0 = clear, 1 = overcast).
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
// How soft the cloud edges are.
uniform float cloud_softness : hint_range(0.01, 1.0) = 0.25;
// Size of the cloud pattern: larger = smaller clouds.
uniform float cloud_scale = 0.35;
// Sky-plane units per second the clouds drift.
uniform vec2 cloud_wind = vec2(0.004, 0.0015);
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.55, 0.58, 0.66, 1.0);
// How much the sun's or moon's colour tints the clouds (0 = only its brightness).
uniform float cloud_sun_tint : hint_range(0.0, 1.0) = 0.3;
// How far above the horizon (EYEDIR.y) the clouds have fully faded in.
uniform float cloud_horizon_fade = 0.2;

void sky() {
	float v_angle = acos(clamp(EYEDIR.y, -1.0, 1.0));
	float c = 1.0 - v_angle / (PI * 0.5);
	vec3 col = mix(sky_horizon_color.rgb, sky_top_color.rgb, clamp(1.0 - pow(1.0 - c, 1.0 / max(sky_curve, 0.001)), 0.0, 1.0));
	if (EYEDIR.y < 0.0) {
		c = (v_angle - PI * 0.5) / (PI * 0.5);
		col = mix(ground_horizon_color.rgb, ground_bottom_color.rgb, clamp(1.0 - pow(1.0 - c, 1.0 / max(ground_curve, 0.001)), 0.0, 1.0));
	}
	vec3 light = LIGHT0_ENABLED ? LIGHT0_COLOR * LIGHT0_ENERGY : vec3(0.0);
	if (LIGHT0_ENABLED && EYEDIR.y >= 0.0) {
		float sun_angle = acos(clamp(dot(LIGHT0_DIRECTION, EYEDIR), -1.0, 1.0));
		if (sun_angle < LIGHT0_SIZE) {
			col = light;
		} else if (sun_angle < sun_angle_max) {
			float c2 = (sun_angle - LIGHT0_SIZE) / (sun_angle_max - LIGHT0_SIZE);
			col = mix(light, col, clamp(1.0 - pow(1.0 - c2, 1.0 / max(sun_curve, 0.001)), 0.0, 1.0));
		}
	}
	// Clouds are left out of the sky's lighting pass (AT_CUBEMAP_PASS), so the world's ambient light and the fog's
	// colour stay what the plain sky gave.
	if (EYEDIR.y > 0.0 && !AT_CUBEMAP_PASS) {
		// The clouds sit on a flat plane overhead, so they crowd together toward the horizon like real ones.
		vec2 uv = EYEDIR.xz / (EYEDIR.y + 0.1) * cloud_scale;
		float n = texture(cloud_noise, uv + cloud_wind * TIME).r * 0.65
			+ texture(cloud_noise, uv * 2.6 + cloud_wind * TIME * 1.6).r * 0.35;
		float edge = 1.0 - cloud_coverage;
		float cover = smoothstep(edge, edge + cloud_softness, n);
		cover *= smoothstep(0.0, cloud_horizon_fade, EYEDIR.y);
		// Thicker parts are their shaded undersides; the sun or moon and the sky's own colour light them.
		float thick = smoothstep(edge, edge + cloud_softness * 2.5, n);
		// The light is mostly taken as brightness, so a strongly coloured sun only warms the clouds.
		vec3 tint = mix(vec3(dot(light, vec3(0.299, 0.587, 0.114))), light, cloud_sun_tint);
		vec3 lit = cloud_color.rgb * (tint * 0.75 + sky_top_color.rgb * 0.35);
		vec3 shade = cloud_shadow_color.rgb * (tint * 0.35 + sky_top_color.rgb * 0.45);
		col = mix(col, mix(lit, shade, thick), cover);
	}
	COLOR = col;
}
