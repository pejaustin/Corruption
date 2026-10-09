// PLACEHOLDER: the splat channel -> texture mapping is a stand-in (Austin has not chosen the textures):
// red = rock, green = dirt, blue = sand, black / no channel = grass. Keep in sync with tools/blender/add_splat.py.
// Ground splat texturing for Austin's vertex-painted map (art/world/README.md, "Painting the ground").
// Two Blender colour layers reach this shader through the glTF importer, which maps only COLOR_0 to COLOR
// (tools/blender/export_landscape.py repacks them in memory):
//   COLOR.rgb = `Splat`  (which texture)
//   UV, UV2.x = `Col`    (tint / shading, rgb = UV.x, UV.y, UV2.x)
// Textures are world-space planar (one 32 px tile = tile_metres, nearest). A channel counts as painted at >= 0.5 (hard
// edge, no blend, keeps the nearest-filtered pixels crisp); if several are painted, sand beats dirt beats rock; grass is
// whatever no channel claims (the remainder).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D grass_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_nearest, repeat_enable;

uniform float tile_metres = 8.0; // PLACEHOLDER: one texture tile in metres
uniform float splat_threshold = 0.5; // PLACEHOLDER: a channel at or above this counts as painted

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / tile_metres;
	vec3 s = COLOR.rgb;
	vec3 c = texture(grass_tex, uv).rgb;
	c = mix(c, texture(rock_tex, uv).rgb, step(splat_threshold, s.r));
	c = mix(c, texture(dirt_tex, uv).rgb, step(splat_threshold, s.g));
	c = mix(c, texture(sand_tex, uv).rgb, step(splat_threshold, s.b));
	vec3 tint = vec3(UV, UV2.x);
	ALBEDO = c * tint;
	ROUGHNESS = 1.0;
}
