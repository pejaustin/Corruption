shader_type canvas_item;

// More drastic PS1 look without lowering render resolution.
// pixel_size = fake-pixel chunkiness; color_steps = bits-per-channel banding.

uniform sampler2D screen_texture: hint_screen_texture, repeat_disable, filter_nearest;
uniform float pixel_size: hint_range(1.0, 16.0) = 4.0;
uniform int color_steps: hint_range(2, 64) = 16;

const float ps1_dither[16] = float[16](
	-4.0, 0.0, -3.0, 1.0,
	2.0, -2.0, 3.0, -1.0,
	-3.0, 1.0, -4.0, 0.0,
	3.0, -1.0, 2.0, -2.0
);

void fragment() {
	vec2 snapped_frag = floor(FRAGCOORD.xy / pixel_size) * pixel_size;
	vec2 sample_uv = snapped_frag * SCREEN_PIXEL_SIZE;
	vec3 screen_color = texture(screen_texture, sample_uv).rgb;

	int x = int(snapped_frag.x / pixel_size) % 4;
	int y = int(snapped_frag.y / pixel_size) % 4;
	float dither_offset = ps1_dither[y * 4 + x] / 8.0;

	float steps = float(color_steps);
	vec3 quantized = floor(screen_color * 255.0 / (256.0 / steps) + dither_offset) / (steps - 1.0);
	COLOR = vec4(quantized, 1.0);
}
