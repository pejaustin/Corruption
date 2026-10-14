PLACEHOLDER: the Paladin's model, not Austin's art (Austin, 2026-10-14: "use the templar knight for the Paladin standin").

Crimson Templar Knight, a retro PSX model from Austin's Drive folder (`Crimson Templar Knight.rar`). Source and
licence not recorded.

- `crimson_templar.glb`: converted from the pack's `.blend` by `tools/blender/convert_rigged_model.py` with `HEIGHT=3.1`
  (the old Paladin model's height; feet at the origin, the Mixamo rig's 0.01 scale applied so retargeting reads his
  hip height right). The sword is skinned to his right hand. It imports with
  `art/characters/ual/mixamo_bone_map.tres` (Mixamo names to Godot's humanoid profile), so the Universal Animation
  Library plays on him. The pack's own 11 Mixamo takes were unnamed; named by eye where used (`light_1`-`3`, `heavy`,
  `idle`, `sword_idle`, `run`; the rest `clip_NN`). Their bone location keys are scaled with the rig.
- `templar.res`: the pack's clips as library `templar` (saved from the glb's player), used for his attacks.
- `templar.tscn`: the model scene the Paladin uses. Libraries `ual` and `templar`, autoplay `ual/Sword_Idle`; `RightHand` is a bone
  attachment the actor scene hangs its `AttackHitbox` on (a capsule along the blade, which is about 2.7 m long).
