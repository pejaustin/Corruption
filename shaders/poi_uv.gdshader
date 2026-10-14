// PLACEHOLDER: stand-in look for the POI blockouts (art/world/pois/*.blend, not designed by Austin).
// The blockouts' own pixel look: a 32 px nearest-filtered texture on the mesh's UVs times its vertex colour (`Col`, the tint),
// with the curved-world bend. One material per texture: art/world/materials/poi/mat_<texture>.tres, put on the glb's
// `mat_<texture>` materials by art/world/pois/poi_post_import.gd.
shader_type spatial;
render_mode diffuse_lambert;

#include "res://shaders/curved_world.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);

void vertex() {
	curve_bend(VERTEX, MODEL_MATRIX, CAMERA_POSITION_WORLD);
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * albedo_color.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
