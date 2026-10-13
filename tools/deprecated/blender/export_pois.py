"""Export one POI blockout (art/world/pois/<snake>.blend) to art/world/pois/export/<snake>.glb for Godot.
Blender 4.5, background. NEVER SAVES the .blend (Austin may hand-edit it): it opens it, exports, quits.
Usage: blender.exe -b <poi>.blend --python tools/blender/export_pois.py -- <repo_root> [<out.glb>]
Default output: <repo_root>/art/world/pois/export/<blend file name>.glb. `--props` as 2nd arg instead exports the shared
props (props.blend: tree_cone, tree_lollipop, ...) as art/world/export/props/<collection>.glb, one glb per collection.

What is exported (in memory only; the file is untouched):
  * Visual / Markers: every object, instanced props (collection instances such as the fences) included. Markers (`site`,
    `spawn`) arrive as plain Node3Ds that Godot code owns.
  * `-noimp` objects (sun, 1.8 m figure, PLACEHOLDER text; the Reference collection) are skipped.
  * `ground` (the starter's round patch) is skipped: the world's own ground (`geo`) is the ground; a flat patch on a hillside
    would float or sink.
  * `-col` objects become `-colonly` (Godot makes a StaticBody3D with trimesh collision and drops the mesh; plain `-col`
    would keep the mesh visible). The starter's collision proxy includes a ground slab (faces at or below the POI's ground
    level, z <= 0): those faces are cut from the exported copy so the slab does not stand on the hillside either.
Materials go out by name (mat_wood, ...); Godot maps them in art/world/pois/export/<name>.glb.import to
art/world/materials/poi/ (curved-world shader, textures/<name>.png)."""
import os
import sys

import bmesh
import bpy

_a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["."]
root = _a[0]
PROPS = len(_a) > 1 and _a[1] == "--props"
stem = os.path.splitext(os.path.basename(bpy.data.filepath))[0]
GROUND_Z = 0.001   # collision faces entirely at or below this height are the starter's ground slab


def export(path, objs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_yup=True, use_selection=True,
        export_apply=True, export_materials="EXPORT", export_image_format="NONE",
        export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True,
        export_texcoords=True, export_normals=True, export_cameras=False, export_lights=False,
        export_animations=False, export_extras=False)
    print("EXPORTED", path, os.path.getsize(path), "bytes", len(objs), "objects")


def cut_ground_slab(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    mw = o.matrix_world
    doomed = [f for f in bm.faces if all((mw @ v.co).z <= GROUND_Z for v in f.verts)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    for v in [v for v in bm.verts if not v.link_faces]:
        bm.verts.remove(v)
    bm.to_mesh(o.data)
    bm.free()
    return len(doomed)


if PROPS:
    for coll in bpy.data.collections:
        objs = [o for o in coll.objects if o.type == "MESH" and not o.name.endswith("-noimp")]
        if objs:
            export(os.path.join(root, "art/world/export/props", coll.name + ".glb"), objs)
else:
    out = _a[1] if len(_a) > 1 else os.path.join(root, "art/world/pois/export", stem + ".glb")
    keep = []
    for o in bpy.context.view_layer.objects:
        if o.name.endswith("-noimp") or o.name == "ground" or o.type in ("LIGHT", "CAMERA", "FONT"):
            continue
        if o.users_collection and all(c.name.endswith("(-noimp)") for c in o.users_collection):
            continue
        if o.instance_type == "COLLECTION" or o.type in ("MESH", "EMPTY"):
            keep.append(o)
    for o in keep:
        if o.type == "MESH" and o.name.endswith("-col"):
            n = cut_ground_slab(o)
            o.name = o.name[:-len("-col")] + "-colonly"
            o.data.name = o.name
            print("COLLISION", o.name, "ground slab faces cut:", n, "faces left:", len(o.data.polygons))
    export(out, keep)
bpy.ops.wm.quit_blender()   # no save: the .blend is Austin's
