"""Export Austin's map (art/world/source/world_landscape.blend) to art/world/export/world_landscape.glb for Godot.
Blender 4.5, background. NEVER SAVES the .blend: it opens it, exports, prints a checksum and quits.
Usage: blender.exe -b <world_landscape.blend> --python tools/blender/export_landscape.py -- <repo_root>
Blender +Y (north) becomes Godot -Z (glTF Y-up conversion). Exported as-is: every mesh and every empty (the POI
markers, Austin's spellings as node names), vertex colour `Col`, materials by name (ground_placeholder,
water_placeholder, forest_placeholder). The materials' Blender node trees are not glTF-exportable; Godot replaces
them by name (art/world/materials/, mapped in world_landscape.glb.import). Ground collision (trimesh on `geo`) is set in
the .glb.import, not here, so the .glb stays faithful. Also prints the ground's world height range and the
height thresholds the Godot ground shader needs (PLACEHOLDER fractions, same as texture_austin_map.py)."""
import hashlib
import os
import sys

import bpy
import numpy as np

root = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "."
out_dir = os.path.join(root, "art/world/export")
out = os.path.join(out_dir, "world_landscape.glb")
os.makedirs(out_dir, exist_ok=True)

# PLACEHOLDER thresholds: fractions of geo's world z range (same as tools/blender/texture_austin_map.py)
SEA_F, SHORE_F, SNOW_F = 0.206, 0.268, 0.79


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
zs = [(geo.matrix_world @ v.co).z for v in geo.data.vertices]
zmin, zmax = min(zs), max(zs)
sea, shore, snow = (zmin + f * (zmax - zmin) for f in (SEA_F, SHORE_F, SNOW_F))
print("GEO_Z_RANGE", zmin, zmax)
print("THRESHOLDS_BLENDER_Z sea=%.4f shore=%.4f snow=%.4f" % (sea, shore, snow))

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
