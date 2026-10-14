"""Universal Animation Library (Quaternius, CC0): curate the MVP clips and export them for Godot.

  blender -b UAL1.blend -P tools/blender/export_ual.py -- --curate art/characters/ual
      Keep only KEEP's actions, mute root motion, save source/ual_mvp.blend, then export.
  blender -b art/characters/ual/source/ual_mvp.blend -P tools/blender/export_ual.py -- art/characters/ual
      Re-export after editing the curated file.

Exports export/ual_anims.glb (rig + mesh + every action; Godot imports it as the AnimationLibrary)
and export/ual_mannequin_placeholder.glb (rig + mesh, no actions; the stand-in model). Settings follow
Quaternius's Godot GLB settings (Blender_Export_Settings.png in the kit).
"""
import os
import sys

import bpy

# Clips the Corruption MVP uses; see art/characters/ual/README.md for what each is for.
KEEP = [
    "A_TPose",
    # Locomotion
    "Idle_Loop", "Idle_LookAround_Loop", "Idle_Tired_Loop", "Idle_Talking_Loop",
    "Walk_Loop", "Turn90_L", "Turn90_R",
    "Jog_Fwd_Loop", "Jog_Bwd_Loop", "Jog_Left_Loop", "Jog_Right_Loop",
    "Jog_Fwd_L_Loop", "Jog_Fwd_R_Loop", "Jog_Bwd_L_Loop", "Jog_Bwd_R_Loop",
    "Sprint_Enter", "Sprint_Loop", "Sprint_Exit",
    "Jump_Start", "Jump_Loop", "Jump_Land",
    "Crouch_Enter", "Crouch_Idle_Loop", "Crouch_Fwd_Loop", "Crouch_Exit",
    # Defence
    "Roll", "Dodge_Left", "Dodge_Right",
    # Sword
    "Sword_Enter", "Sword_Idle", "Sword_Attack", "Sword_Attack_Standing", "Sword_Exit",
    # Unarmed (minions, a disarmed Paladin)
    "Punch_Jab", "Punch_Cross", "Kick",
    # Magic (quarterstaff, abilities, channelling)
    "Spell_Simple_Enter", "Spell_Simple_Idle_Loop", "Spell_Simple_Shoot", "Spell_Simple_Exit",
    "Spell_Double_Enter", "Spell_Double_Idle_Loop", "Spell_Double_Shoot_Loop", "Spell_Double_Exit",
    # Hit reactions and death
    "Hit_Chest", "Hit_Head", "Hit_Stomach", "Hit_Shoulder_L", "Hit_Shoulder_R",
    "Death01", "Death02",
    # World interaction (relics, crystals, hauling goods, handing over orders)
    "Interact", "PickUp_Kneeling", "PickUp_Table", "Counter_Give",
]


def mute_root_motion():
    # Same as the kit's root_motion_toggle.py "Disable All Root Motion", for Blender 5 layered actions.
    for action in bpy.data.actions:
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    bag = strip.channelbag(slot)
                    if bag is None:
                        continue
                    group = bag.groups.get("root")
                    if group is None:
                        continue
                    group.mute = True
                    for fc in bag.fcurves:
                        if fc.group == group:
                            fc.mute = True


def curate():
    missing = [n for n in KEEP if n not in bpy.data.actions]
    if missing:
        raise SystemExit(f"actions not in the library: {missing}")
    for action in list(bpy.data.actions):
        if action.name not in KEEP:
            bpy.data.actions.remove(action)
    mute_root_motion()
    arm = bpy.data.objects["Armature"]
    arm.animation_data.action = bpy.data.actions["A_TPose"]


def export(path, with_actions):
    bpy.ops.object.select_all(action="DESELECT")
    arm = bpy.data.objects["Armature"]
    arm.select_set(True)
    for child in arm.children:
        if child.type == "MESH":
            child.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_rest_position_armature=True,
        export_def_bones=True,
        export_skins=True,
        export_animations=with_actions,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_optimize_animation_size=False,
        export_optimize_animation_keep_anim_armature=True,
    )


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    do_curate = "--curate" in args
    out = [a for a in args if not a.startswith("--")][0]
    os.makedirs(os.path.join(out, "source"), exist_ok=True)
    os.makedirs(os.path.join(out, "export"), exist_ok=True)
    if do_curate:
        curate()
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(os.path.join(out, "source", "ual_mvp.blend")),
                                    compress=True)
    export(os.path.abspath(os.path.join(out, "export", "ual_anims.glb")), True)
    export(os.path.abspath(os.path.join(out, "export", "ual_mannequin_placeholder.glb")), False)
    print("EXPORTED", len(bpy.data.actions), "actions")


main()
