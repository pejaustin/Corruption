// PLACEHOLDER: stand-in ground look, not designed by Austin. Mirrors the Blender placeholder texturing in
// tools/blender/texture_austin_map.py: world-space planar UV (one 32 px tile = 8 m, nearest), grass base,
// sand below `shore_height`, water texture below `sea_height`, snow above `snow_height`, rock where the slope
// (1 - |normal.y|) exceeds `rock_slope`, all multiplied by the vertex colour (Blender `Col`).
// Heights are the absolute world heights the Blender script derives from fractions 0.206 / 0.268 / 0.79 of geo's
// world height range (-62.352 .. 153.444 m); recompute them if Austin changes the ground's vertical scale.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D grass_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D water_tex : source_color, filter_nearest, repeat_enable;

uniform float tile_metres = 8.0; // PLACEHOLDER: one texture tile in metres
uniform float sea_height = -17.8983; // PLACEHOLDER: world y below which the water texture shows
uniform float shore_height = -4.5190; // PLACEHOLDER: world y below which sand shows
uniform float snow_height = 108.1265; // PLACEHOLDER: world y above which snow shows
uniform float rock_slope = 0.30; // PLACEHOLDER: slope (1 - |normal.y|) above which rock shows

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / tile_metres;
	vec3 c = texture(grass_tex, uv).rgb;
	c = mix(c, texture(sand_tex, uv).rgb, step(world_pos.y, shore_height));
	c = mix(c, texture(water_tex, uv).rgb, step(world_pos.y, sea_height));
	c = mix(c, texture(snow_tex, uv).rgb, step(snow_height, world_pos.y));
	// the engine's NORMAL is already correct for the ground's non-uniform scale; back to world space
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - abs(world_normal.y);
	c = mix(c, texture(rock_tex, uv).rgb, step(rock_slope, slope));
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = 1.0;
}
