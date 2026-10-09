"""Export Austin's map (art/world/source/world_landscape.blend) to art/world/export/world_landscape.glb for Godot.
Blender 4.5, background. NEVER SAVES the .blend: it opens it, exports, prints a checksum and quits.
Usage: blender.exe -b <world_landscape.blend> --python tools/blender/export_landscape.py -- <repo_root>
Optional 2nd arg: output .glb path (scratch tests). Blender +Y (north) becomes Godot -Z (glTF Y-up conversion).
Exported as-is: every mesh and every empty (the POI markers, Austin's spellings as node names), vertex colour `Col`
(on geo: Splat and Col are repacked in memory, see below), materials by name (ground_placeholder,
water_placeholder, forest_placeholder). The materials' Blender node trees are not glTF-exportable; Godot replaces
them by name (art/world/materials/, mapped in world_landscape.glb.import). Ground collision (trimesh on `geo`) is set in
the .glb.import, not here, so the .glb stays faithful."""
import hashlib
import os
import sys

import bpy
import numpy as np

_a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["."]
root = _a[0]
out = _a[1] if len(_a) > 1 else os.path.join(root, "art/world/export/world_landscape.glb")   # optional 2nd arg: scratch .glb
out_dir = os.path.dirname(out)
os.makedirs(out_dir, exist_ok=True)


def checksum():
    res = {}
    for o in sorted(bpy.data.objects, key=lambda o: o.name):
        mw = tuple(round(x, 4) for r in o.matrix_world for x in r)
        if o.type == "MESH":
            a = np.empty(len(o.data.vertices) * 3)
            o.data.vertices.foreach_get("co", a)
            res[o.name] = (o.type, round(float(a.sum()), 4), round(float(np.abs(a).sum()), 4),
                           len(o.data.vertices), len(o.data.polygons), mw)
        else:
            res[o.name] = (o.type, mw)
    return res


def digest(c):
    return hashlib.sha256(repr(sorted(c.items())).encode()).hexdigest()[:16]


before = checksum()
geo = bpy.data.objects["geo"]
# Ground layers for Godot (IN MEMORY ONLY, never saved): glTF importer maps only COLOR_0 to COLOR, so pack
#   Splat (texture choice, RGB) -> COLOR_0 (the active colour attribute is what gets exported),
#   Col   (tint, RGB)           -> UV (r, g) and UV2 (b, 0)   [replaces geo's UVMap / WorldUV in the export; the shader
#                                  tiles by world position and needs neither].
# shaders/world_ground.gdshader reads them back as COLOR.rgb, UV, UV2.x.
gme = geo.data
if "Splat" in gme.color_attributes and "Col" in gme.color_attributes:
    nl = len(gme.loops)
    col = np.empty(nl * 4, np.float32)
    gme.color_attributes["Col"].data.foreach_get("color", col)
    col = col.reshape(-1, 4)
    for nm in [u.name for u in gme.uv_layers if not u.name.startswith(".")]:
        gme.uv_layers.remove(gme.uv_layers[nm])
    u0 = gme.uv_layers.new(name="ColRG")
    u1 = gme.uv_layers.new(name="ColB")
    # the glTF exporter writes v as 1 - v (and Godot keeps it as is), so store 1 - g / 1 - 0 to arrive as g / 0
    u0.data.foreach_set("uv", np.stack([col[:, 0], 1.0 - col[:, 1]], 1).ravel())
    u1.data.foreach_set("uv", np.stack([col[:, 2], np.ones(nl, np.float32)], 1).ravel())
    gme.color_attributes.remove(gme.color_attributes["Col"])   # else the exporter also writes it as COLOR_1
    gme.color_attributes.active_color = gme.color_attributes["Splat"]
    print("PACKED Splat -> COLOR_0, Col -> UV/UV2")
else:
    print("WARNING: geo has no Splat / Col; run tools/blender/add_splat.py")
bpy.ops.export_scene.gltf(
    filepath=out, export_format="GLB", export_yup=True, use_selection=False,
    export_apply=False, export_materials="EXPORT", export_image_format="NONE",
    export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True,
    export_texcoords=True, export_normals=True, export_cameras=False, export_lights=False,
    export_animations=False, export_extras=False)

after = checksum()
print("EXPORTED", out, os.path.getsize(out), "bytes")
print("GEOMETRY_AND_NAMES_UNCHANGED", before == after, digest(before), digest(after))
print("OBJECTS", len(before), [n for n, v in before.items() if v[0] == "EMPTY"])
bpy.ops.wm.quit_blender()   # no save: the .blend is Austin's
