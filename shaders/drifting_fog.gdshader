// PLACEHOLDER: the look (every uniform default and every value set on the fog materials), not designed by Austin.
// Drifting fog for a FogVolume: 3D noise carried by the wind (two layers at different speeds, so the fog changes
// shape as it moves), thick near the bottom of the volume and gone at its top, soft at the volume's edges, and
// thicker at night (fog_night, set by WorldFog from the day/night clock).
shader_type fog;

global uniform float fog_night;

uniform float density : hint_range(0.0, 1.0) = 0.01;
uniform vec3 albedo : source_color = vec3(0.85, 0.88, 0.92);
// Density multiplier at full night (1 = no change).
uniform float night_boost = 2.0;
// Height above the volume's origin: full density below full_below, none above clear_above.
uniform float full_below = 5.0;
uniform float clear_above = 30.0;
// Metres from the volume's edge over which the fog fades in.
uniform float edge_fade = 60.0;
uniform sampler3D noise : repeat_enable;
// Metres one tile of the noise covers.
uniform float noise_scale = 160.0;
// 0 = smooth fog, 1 = fully broken into wisps.
uniform float noise_strength = 0.75;
// Metres per second the fog drifts.
uniform vec3 wind = vec3(2.0, 0.0, 0.8);

void fog() {
	float h = WORLD_POSITION.y - OBJECT_POSITION.y;
	float d = density * (1.0 - smoothstep(full_below, clear_above, h));
	d *= clamp(-SDF / max(edge_fade, 0.001), 0.0, 1.0);
	vec3 p = WORLD_POSITION / noise_scale;
	float n = texture(noise, p - wind * TIME / noise_scale).r * 0.65
		+ texture(noise, p * 2.3 - wind * TIME * 1.7 / noise_scale).r * 0.35;
	d *= mix(1.0, smoothstep(0.3, 0.75, n), noise_strength);
	DENSITY = d * mix(1.0, night_boost, fog_night);
	ALBEDO = albedo;
}
