// Curved world: bends the ground away below the horizon so a flat 2 km map reads as a round world.
// Use in a spatial shader:
//   #include "res://shaders/curved_world.gdshaderinc"
//   void vertex() { curve_bend(VERTEX, MODEL_MATRIX, CAMERA_POSITION_WORLD); }
// (CAMERA_POSITION_WORLD is the editor camera in the editor, so it follows you.)
//
// world.y -= d^2 / (2 R), d = horizontal distance from the camera, R = curve_horizon_m^2 / (2 * curve_eye_height_m),
// i.e. ground at curve_horizon_m away drops by curve_eye_height_m. Change both live in
// Project Settings > Globals > Shader Globals. curve_horizon_m = 0 turns the bend off.
// PLACEHOLDER: the horizon distance, eye height and the whole look are stand-in tuning, not Austin's design.
global uniform float curve_horizon_m;
global uniform float curve_eye_height_m;

// vertex: model-space VERTEX (bent in place); model: MODEL_MATRIX; cam: CAMERA_POSITION_WORLD.
// Normals are left alone.
void curve_bend(inout vec3 vertex, mat4 model, vec3 cam) {
	if (curve_horizon_m <= 0.0) {
		return;
	}
	vec3 w = (model * vec4(vertex, 1.0)).xyz;
	vec2 d = w.xz - cam.xz;
	float drop = dot(d, d) * curve_eye_height_m / (curve_horizon_m * curve_horizon_m);
	// the drop is a world-space -Y shift; bring it back into model space
	vertex += inverse(mat3(model)) * vec3(0.0, -drop, 0.0);
}
