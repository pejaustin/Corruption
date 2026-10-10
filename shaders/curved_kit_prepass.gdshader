// Castle kit (assets/world/env/mod-castle) with the curved-world bend. Replaces the .fbx files' embedded
// StandardMaterial3D (albedo texture, vertex colour as albedo, linear + mipmaps). Alpha depth-prepass variant; curved_kit and _scissor
// are the same with alpha. Generated materials: tools/curve_kit_materials.gd.
shader_type spatial;
render_mode depth_prepass_alpha;

#include "res://shaders/curved_world.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);

void vertex() {
	curve_bend(VERTEX, MODEL_MATRIX, CAMERA_POSITION_WORLD);
}

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_color * COLOR;
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ROUGHNESS = 1.0;
}
