# Hit-Flash Shader

The Tier A "hit-flash" feedback in `scenes/actors/actor.gd` walks the model's
mesh tree on every frame the actor is flashing, and pokes a single shader
uniform on any `ShaderMaterial` it finds:

```
mat.set_shader_parameter(&"hit_flash_intensity", value)
```

Plain `StandardMaterial3D` meshes are skipped silently. To opt a model into
the flash, replace its surface materials with a `ShaderMaterial` that exposes
the contract uniform.

## Contract

A material participates in the flash iff:

1. It is a `ShaderMaterial`.
2. Its shader declares `uniform float hit_flash_intensity = 0.0;`.
3. The shader uses that uniform in the `fragment()` function to add a white
   (or any colour) component to the final albedo / emission.

`Actor` ramps the value from `1.0` to `0.0` linearly over `HIT_FLASH_DURATION`
(0.15s by default) on the local presentation only — never inside the rollback
loop. So the shader sees a smooth fade for the on-hit-impact peer and a flat
zero everywhere else.

## Example shader

Drop this into a new `*.gdshader` file (e.g.
`shaders/hit_flash_albedo.gdshader`), assign it to a `ShaderMaterial`, and
attach the material to the avatar's mesh surfaces.

```glsl
shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float hit_flash_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 hit_flash_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base = albedo * texture(albedo_texture, UV);
	// Mix toward the flash tint at full intensity. The clamp keeps it safe
	// when intensities stack — Actor only writes 0..1 today, but artists may
	// drive it manually for taunts / executions later.
	ALBEDO = mix(base.rgb, hit_flash_tint, clamp(hit_flash_intensity, 0.0, 1.0));
	ROUGHNESS = roughness;
	METALLIC = metallic;
	ALPHA = base.a;
}
```

## Wiring per actor

1. Open the model's `.tscn` (e.g. `assets/characters/avatar/avatar.tscn`).
2. Select each `MeshInstance3D` whose body should flash.
3. In the inspector → Surface Material Override → 0, attach a new
   `ShaderMaterial` that uses the shader above (or any shader honouring the
   uniform).
4. Save. No code changes — `Actor._set_hit_flash_intensity` finds the
   material on the next hit.

## Multi-mesh models

`Actor._walk_mesh_instances` walks the entire `_model` subtree, so split
meshes (helmet, torso, legs) all participate as long as each surface uses
a compatible `ShaderMaterial`. Surface-override materials beat the mesh's
own material — preferred path so the model file stays untouched.

## Cost

The walk only runs while `_hit_flash_intensity > 0.0` (after a hit, for
~150 ms). Outside of damage events the function early-returns and costs
one comparison per actor per frame.

## Future: shared-material caching

If many actors share the same material instance, today's per-frame shader
parameter write is harmless duplicate work. When this becomes hot, cache
the material list on `_ready()` and update only those — the walk happens
once instead of every flash frame.
