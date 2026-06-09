shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// Depth-fade water for the Cania world map.
//
// Sea level is y = 0 by construction (the Azgaar import carves every water
// cell below 0), so one large plane covers every sea and lake. Water color
// comes from the real water-column depth read back from the depth buffer
// (Beer's law absorption), shores get a noise-broken foam band, and the
// surface animates with two counter-scrolling generated normal maps.
//
// Technique follows the standard Godot 4 depth-fade water shaders
// (stayathomedev.com single-plane water; godotshaders.com stylized water
// with depth fade, MIT) and the official depth-texture reconstruction
// snippet from the Godot docs (screen-reading shaders).

uniform vec3 shallow_color : source_color = vec3(0.18, 0.46, 0.5);
uniform vec3 deep_color : source_color = vec3(0.015, 0.1, 0.22);
/// Beer's-law absorption: higher = water darkens to deep_color sooner.
uniform float absorbance : hint_range(0.001, 0.5) = 0.035;
/// Water-column depth (view units) that still reads as shoreline foam.
uniform float foam_depth : hint_range(0.1, 50.0) = 5.0;
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 1.0);
uniform float water_roughness : hint_range(0.0, 1.0) = 0.08;
uniform float normal_strength : hint_range(0.0, 4.0) = 1.0;
/// World-units → UV tiling. 0.01 tiles the wave noise every 100 units.
uniform float uv_world_scale : hint_range(0.0001, 0.1) = 0.01;
uniform vec2 scroll_1 = vec2(0.018, 0.011);
uniform vec2 scroll_2 = vec2(-0.013, -0.019);
uniform sampler2D normal_map_1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map_2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying vec2 world_uv;

void vertex() {
	// UVs from world XZ so tiling is independent of the plane's size.
	world_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	// Scene position behind this fragment — official docs reconstruction,
	// valid with Godot 4.3+ reversed-Z (INV_PROJECTION_MATRIX encodes it).
	float depth_raw = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	scene_view.xyz /= scene_view.w;
	// View-space -Z is forward: water fragment z minus scene z = column length.
	float water_depth = max(VERTEX.z - scene_view.z, 0.0);

	// Animated surface normals: two counter-scrolling noise normal maps.
	vec2 uv = world_uv * uv_world_scale;
	vec3 n1 = texture(normal_map_1, uv + TIME * scroll_1).rgb;
	vec3 n2 = texture(normal_map_2, uv * 1.83 + TIME * scroll_2).rgb;
	NORMAL_MAP = mix(n1, n2, 0.5);
	NORMAL_MAP_DEPTH = normal_strength;

	// Beer's law: transmittance falls off exponentially with column depth.
	float transmittance = exp(-water_depth * absorbance);
	vec3 water_color = mix(deep_color, shallow_color, transmittance);

	// Shore foam: a band where the column is shallow, broken up by the
	// scrolling wave noise so it shimmers instead of forming a hard line.
	float foam_band = 1.0 - smoothstep(0.0, foam_depth, water_depth);
	float foam_noise = smoothstep(0.35, 0.75,
			mix(n1.g, n2.g, 0.5)
			+ 0.25 * sin(TIME * 1.7 + world_uv.x * 0.05 + world_uv.y * 0.04));
	float foam = foam_band * foam_noise;

	ALBEDO = mix(water_color, foam_color, foam);
	ALPHA = max(clamp(1.0 - transmittance, 0.25, 0.92), foam * 0.95);
	ROUGHNESS = mix(water_roughness, 0.5, foam);
	SPECULAR = 0.5;
}
