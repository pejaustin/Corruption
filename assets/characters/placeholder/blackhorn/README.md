PLACEHOLDER: boss form model, not Austin's art (Austin, 2026-10-14: replaces the golem).

Blackhorn of the Shattered Peaks, a retro PSX model from Austin's Drive folder (`Blackhorn of the Shattered Peaks.rar`).
Source and licence not recorded.

- `blackhorn.glb`: converted from the pack's FBX by `tools/blender/convert_rigged_model.py` (Mixamo rig, one mesh,
  256 px texture). The pack's 9 clips were unnamed; named by eye: `idle` (28.7 s), `walk`, `run` (in place),
  `walk_forward`, `run_forward` (the same with root motion), `roar`, `slam` (rears up, both arms down), `sweep`
  (wide two-armed swing), `stomp` (knee high, foot down). No hit or death clip. Idle, walk and run loop
  (`blackhorn.glb.import`).
- `blackhorn.tscn`: the model scene the game uses (nearest filtering). `blackhorn.res`: the animation library
  (`blackhorn/<clip>`), saved from the glb's player.
- `blackhorn_chivato-texture.png`: Godot's extraction of the glb's embedded texture.
- About 3.5 m tall (twice the Paladin), feet at the origin, facing +Z.
