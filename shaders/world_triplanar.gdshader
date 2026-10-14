// PLACEHOLDER: stand-in look for the water and forest patches (not designed by Austin).
// Was a StandardMaterial3D (world triplanar, 8 m tiles, nearest, vertex colour as albedo); a shader now so it can use the
// curved-world bend (curved_world.gdshaderinc). Used by art/world/materials/water_placeholder.tres and forest_placeholder.tres.
shader_type spatial;
render_mode diffuse_lambert;

#include "res://shaders/curved_world.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float tile_metres = 8.0; // PLACEHOLDER: one texture tile in metres (was uv1_scale 0.125)
uniform float triplanar_sharpness = 0.5; // same as the old StandardMaterial3D default

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	curve_bend(VERTEX, MODEL_MATRIX, CAMERA_POSITION_WORLD);
}

void fragment() {
	vec3 w = pow(abs(world_normal), vec3(triplanar_sharpness));
	w /= (w.x + w.y + w.z);
	vec3 p = world_pos / tile_metres;
	vec3 c = texture(albedo_tex, p.zy).rgb * w.x + texture(albedo_tex, p.xz).rgb * w.y + texture(albedo_tex, p.xy).rgb * w.z;
	ALBEDO = c * albedo_color.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
