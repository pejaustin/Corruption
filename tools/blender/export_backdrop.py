"""Export the backdrop (art/world/source/world_backdrop.blend) to art/world/export/world_backdrop_<size>.glb for Godot.
Blender 4.5+, background. NEVER SAVES the .blend (Austin sculpts it): opens, exports, quits.
Usage: Blender -b <world_backdrop.blend> --python tools/blender/export_backdrop.py -- <repo_root> [400m|2km|6km]
The file is authored at 2 km (scale 1); the size presets match export_landscape.py (6 km is 3x wide and 5x tall, 400 m a
1/5 miniature). Exported: `backdrop` (ground_placeholder, with Splat -> COLOR_0 and Col -> UV/UV2 packed exactly as
export_landscape.py packs geo, so shaders/world_ground.gdshader reads both the same) and `backdrop sea`
(water_placeholder). No collision: the .glb.import generates none."""
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

_a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["."]
root = _a[0]
SIZES = {"400m": (0.2, 0.2), "2km": (1.0, 1.0), "6km": (3.0, 5.0)}   # same as export_landscape.py
size = _a[1] if len(_a) > 1 and _a[1] in SIZES else "2km"
out = os.path.join(root, "art/world/export/world_backdrop_%s.glb" % size)

if bpy.context.object and bpy.context.object.mode != "OBJECT":   # saved in Edit/Sculpt mode: mesh data is empty until flushed
    bpy.ops.object.mode_set(mode="OBJECT")
land = bpy.data.objects["backdrop"]
me = land.data
if "Splat" in me.color_attributes and "Col" in me.color_attributes:   # in memory only, as export_landscape.py does for geo
    nl = len(me.loops)
    col = np.empty(nl * 4, np.float32)
    me.color_attributes["Col"].data.foreach_get("color", col)
    col = col.reshape(-1, 4)
    for nm in [u.name for u in me.uv_layers]:
        me.uv_layers.remove(me.uv_layers[nm])
    u0 = me.uv_layers.new(name="ColRG")
    u1 = me.uv_layers.new(name="ColB")
    u0.data.foreach_set("uv", np.stack([col[:, 0], 1.0 - col[:, 1]], 1).ravel())
    u1.data.foreach_set("uv", np.stack([col[:, 2], np.ones(nl, np.float32)], 1).ravel())
    me.color_attributes.remove(me.color_attributes["Col"])
    me.color_attributes.active_color = me.color_attributes["Splat"]
else:
    print("WARNING: backdrop has no Splat / Col; regenerate with tools/blender/build_backdrop.py")
fx, fz = SIZES[size]
for o in bpy.data.objects:
    if o.parent is None:
        o.location = Vector((o.location.x * fx, o.location.y * fx, o.location.z * fz))
        o.scale = Vector((o.scale.x * fx, o.scale.y * fx, o.scale.z * fz))
bpy.context.view_layer.update()
for o in bpy.data.objects:
    o.select_set(o.name in ("backdrop", "backdrop sea"))
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out, export_format="GLB", export_yup=True, use_selection=True,
    export_apply=True, export_materials="EXPORT", export_image_format="NONE",
    export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True,
    export_texcoords=True, export_normals=True, export_cameras=False, export_lights=False,
    export_animations=False, export_extras=False)
print("EXPORTED", out, os.path.getsize(out), "bytes")
bpy.ops.wm.quit_blender()   # no save: the .blend is Austin's to sculpt
