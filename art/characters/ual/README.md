# Universal Animation Library (MVP cut)

Quaternius's Universal Animation Library (CC0, `LICENSE.txt`; kit 2026-06-16, viewer: https://quaternius.com/animviewer.html),
cut from 120 clips to the 56 a humanoid needs in the MVP: the Paladin, humanoid troops, couriers, the advisor, townsfolk.
In place (root motion muted), because movement is code-driven under netfox rollback.

| File | What |
|---|---|
| `source/ual_mvp.blend` | Rig (Rigify controls, 65 deform bones, UE mannequin names) + `Mannequin` + the 56 actions. Build your model here. `.gdignore`d |
| `source/root_motion_toggle.py` | The kit's Blender addon: mute/unmute root motion on every action |
| `export/ual_anims.glb` | Imported as an **AnimationLibrary** (Import As: Animation Library). Use it as library `ual` |
| `export/ual_mannequin_placeholder.glb`, `ual_mannequin_placeholder.tscn` | Stand-in model (PLACEHOLDER), plays `ual/Idle` |
| `ual_bone_map.tres` | UE names → Godot `SkeletonProfileHumanoid`. Both glbs import with it, so tracks are `%GeneralSkeleton:<HumanoidBone>` |

Re-export after editing the .blend (writes both glbs; Godot reimports on focus):

```
blender -b art/characters/ual/source/ual_mvp.blend -P tools/blender/export_ual.py -- art/characters/ual
```

`--curate` instead rebuilds the .blend from the kit's `UAL1.blend` with the clip list in `export_ual.py` `KEEP`.

## Your model

Parent your mesh to `Armature` (deform bones only), hide or delete `Mannequin`, export your glb with the selection
(Armature + mesh, no animations; the script's settings), and import it with **Retarget → Bone Map = `ual_bone_map.tres`**
on its Skeleton3D. Its AnimationPlayer then takes `ual` as is. Any other humanoid rig works too, with its own bone map.

## Clips

Godot drops `_Loop` from names and loops those clips (`Idle_Loop` → `ual/Idle`). `Sword_Idle` is set to loop in the import.

| For | Clips |
|---|---|
| Rig reference | `A_TPose` |
| Idle, talk | `Idle`, `Idle_LookAround`, `Idle_Tired` (low stamina), `Idle_Talking` (advisor, couriers reporting) |
| Walk, turn | `Walk`, `Turn90_L`, `Turn90_R` |
| Run, lock-on strafe (8-way) | `Jog_Fwd`, `Jog_Bwd`, `Jog_Left`, `Jog_Right`, `Jog_Fwd_L`, `Jog_Fwd_R`, `Jog_Bwd_L`, `Jog_Bwd_R` |
| Sprint | `Sprint_Enter`, `Sprint`, `Sprint_Exit` |
| Jump | `Jump_Start`, `Jump` (air loop), `Jump_Land` |
| Crouch | `Crouch_Enter`, `Crouch_Idle`, `Crouch_Fwd`, `Crouch_Exit` |
| Dodge | `Roll`, `Dodge_Left`, `Dodge_Right` |
| Sword | `Sword_Enter` (draw), `Sword_Idle`, `Sword_Attack` (moving), `Sword_Attack_Standing`, `Sword_Exit` (sheathe) |
| Unarmed (troops) | `Punch_Jab`, `Punch_Cross`, `Kick` |
| Staff magic, abilities | `Spell_Simple_Enter`, `Spell_Simple_Idle`, `Spell_Simple_Shoot`, `Spell_Simple_Exit`; two-handed: `Spell_Double_Enter`, `Spell_Double_Idle`, `Spell_Double_Shoot` (loop), `Spell_Double_Exit` |
| Hit reactions | `Hit_Chest`, `Hit_Head`, `Hit_Stomach`, `Hit_Shoulder_L`, `Hit_Shoulder_R` |
| Death | `Death01`, `Death02` |
| World | `Interact` (crystals, runestones, relics), `PickUp_Kneeling` / `PickUp_Table` (goods, relics), `Counter_Give` (hand over a scroll) |

Left out (still in the kit): climbing, crawling, swimming, sitting, pistol, push, dance, driving, rock-paper-scissors.
Not in the kit at all: shield block, two-handed weapon swings, a quarterstaff melee set, backstep, riposte, heavy or charged attacks.
