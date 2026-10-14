# Blender, one-off conversion of a rigged FBX/.blend from an asset pack into a glb (2026-10-14, Blackhorn, the Templar and
# the monsters under assets/characters/placeholder/): images relinked by file name, weapons parented to a hand bone
# skinned to it, duplicate takes dropped, unnamed Mixamo takes numbered. HEIGHT=<m> resizes and grounds the rig.
# [HEIGHT=3.1] blender -b --factory-startup -P convert_rigged_model.py -- SRC OUT.glb TEXDIR [ARMATURE_TO_KEEP] [RENAME_JSON] [FALLBACK_PNG]
# args: src out.glb texdir [keep_armature] [rename json] [fallback_texture]
import bpy, sys, os, re, json
a = sys.argv[sys.argv.index('--')+1:]
src, out, texdir = a[0], a[1], a[2]
keep = a[3] if len(a) > 3 and a[3] else None
rename = json.loads(a[4]) if len(a) > 4 and a[4] else {}
fallback = a[5] if len(a) > 5 and a[5] else None
if src.endswith('.blend'):
    bpy.ops.wm.open_mainfile(filepath=src)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True); bpy.ops.import_scene.fbx(filepath=src)
sc = bpy.context.scene
if keep:
    arm = bpy.data.objects[keep]
    keepset = {arm} | {c for c in arm.children_recursive}
    for o in list(sc.objects):
        if o not in keepset: bpy.data.objects.remove(o)
    if arm.parent: 
        mw = arm.matrix_world.copy(); arm.parent = None; arm.matrix_world = mw
# weapons parented to a hand bone: skin them to that bone instead (glTF keeps skins reliably)
for o in list(sc.objects):
    if o.type == 'MESH' and o.parent and o.parent_type == 'BONE':
        arm_o, pb = o.parent, o.parent.pose.bones[o.parent_bone]
        W = o.matrix_world.copy()
        Wr = arm_o.matrix_world @ pb.bone.matrix_local
        Wp = arm_o.matrix_world @ pb.matrix
        o.parent = arm_o; o.parent_type = 'OBJECT'
        o.matrix_world = Wr @ Wp.inverted() @ W
        vg = o.vertex_groups.new(name=pb.name); vg.add(range(len(o.data.vertices)), 1.0, 'REPLACE')
        m = o.modifiers.new('Armature', 'ARMATURE'); m.object = arm_o
        print("WEAPON", o.name, '->', pb.name)
pngs = {f.lower(): os.path.join(texdir, f) for f in os.listdir(texdir) if f.lower().endswith('.png')}
for img in bpy.data.images:
    if img.source != 'FILE': continue
    path = bpy.path.abspath(img.filepath)
    if os.path.exists(path): continue
    base = re.sub(r'\.\d{3}$', '', os.path.basename(img.filepath.replace('\\', '/'))).lower()
    hit = pngs.get(base) or (os.path.join(texdir, fallback) if fallback else None)
    if hit: img.filepath = hit; img.reload()
    print("IMG", img.name, '->', hit)
arm = [o for o in sc.objects if o.type == 'ARMATURE'][0]
bones = {b.name for b in arm.data.bones}
def drives_rig(act):
    paths = []
    try: paths = [fc.data_path for fc in act.fcurves]
    except Exception:
        for l in act.layers:
            for s in l.strips:
                for cb in s.channelbags: paths += [fc.data_path for fc in cb.fcurves]
    return any(any(f'"{b}"' in p for b in bones) for p in paths)
kept = []
for act in list(bpy.data.actions):
    new = rename.get(act.name)
    if new is None and rename: new = None
    elif new is None:
        new = act.name.split('|')[-1]
    if new is None or new == '' or not drives_rig(act) or new in ('ArmatureAction', 'EmptyAction') or new.endswith('Action'):
        bpy.data.actions.remove(act); continue
    act.name = new; act.use_fake_user = True; kept.append(new)
# drop exact duplicate takes (same keys on every curve)
def keys(act):
    out = []
    try: fcs = list(act.fcurves)
    except Exception: fcs = [fc for l in act.layers for st in l.strips for cb in st.channelbags for fc in cb.fcurves]
    for fc in sorted(fcs, key=lambda f: (f.data_path, f.array_index)):
        out.append((fc.data_path, fc.array_index, tuple(round(v, 4) for k in fc.keyframe_points for v in k.co)))
    return hash(tuple(out))
seen = set()
for act in sorted(bpy.data.actions, key=lambda x: x.name):
    h = keys(act)
    if h in seen: bpy.data.actions.remove(act)
    else: seen.add(h)
# unnamed Mixamo takes: number them
for i, act in enumerate(sorted([x for x in bpy.data.actions if 'mixamo' in x.name or x.name.startswith('Layer0')], key=lambda x: x.name)):
    act.name = f"clip_{i+1:02d}"
for act in bpy.data.actions: print("ACT", act.name, int(act.frame_range[1] - act.frame_range[0]))
arm.animation_data_create(); arm.animation_data.action = None
# HEIGHT=<m>: scale the rig so its rest-pose mesh is that tall, feet at the origin, then apply the armature's
# transforms (Mixamo rigs come in at 0.01 scale, which leaves Godot's retarget reading the hip height wrong)
if os.environ.get('HEIGHT'):
    arm.data.pose_position = 'REST'; bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    zs = [(o.matrix_world @ v.co).z for o in sc.objects if o.type == 'MESH' for v in o.evaluated_get(dg).to_mesh().vertices]
    f = float(os.environ['HEIGHT']) / (max(zs) - min(zs))
    arm.location.z -= min(zs); arm.location *= f; arm.scale *= f
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    for o in [arm] + list(arm.children_recursive): o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    s_old = arm.scale.x
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Applying scale moves the bones, not the keys: scale the actions' bone location keys to match.
    for act in bpy.data.actions:
        try: fcs = list(act.fcurves)
        except Exception: fcs = [fc for l in act.layers for st in l.strips for cb in st.channelbags for fc in cb.fcurves]
        for fc in fcs:
            if fc.data_path.endswith('.location'):
                for k in fc.keyframe_points:
                    k.co[1] *= s_old; k.handle_left[1] *= s_old; k.handle_right[1] *= s_old
    arm.data.pose_position = 'POSE'; bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get(); arm.data.pose_position = 'REST'; bpy.context.view_layer.update()
    zs = [(o.matrix_world @ v.co).z for o in sc.objects if o.type == 'MESH' for v in o.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh().vertices]
    print("HEIGHT", round(min(zs), 3), round(max(zs), 3), "hips", tuple(round(c, 3) for c in arm.matrix_world @ arm.pose.bones[0].head))
    arm.data.pose_position = 'POSE'
slug = os.path.splitext(os.path.basename(out))[0]
arm.name = 'Armature'
body = [o for o in sc.objects if o.type == 'MESH' and o.vertex_groups and len(o.vertex_groups) > 1]
if len(body) == 1: body[0].name = slug
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animation_mode='ACTIONS', export_force_sampling=True,
    export_def_bones=False, export_image_format='AUTO', use_selection=False, export_cameras=False, export_lights=False)
print("OK", out, os.path.getsize(out))
