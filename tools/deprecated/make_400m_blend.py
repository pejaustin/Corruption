"""One-time use (2026-10-13): made art/world/source/world_landscape_400m.blend from world_landscape.blend, scaled to the
400 m preset exactly as the old export_landscape.py rescaled it in memory (0.2 wide and 0.2 tall over the 2 km map; root
objects' locations and every non-empty's scale; empties keep scale 1). Saves a COPY under the new name; never saves over
world_landscape.blend. From then on the 400 m and 2 km maps are separate works (Austin, 2026-10-13).
Usage: Blender -b art/world/source/world_landscape.blend --python tools/deprecated/make_400m_blend.py -- <repo_root>"""
import os
import sys

import bpy
from mathutils import Vector

root = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "."
out = os.path.join(root, "art/world/source/world_landscape_400m.blend")
assert not os.path.exists(out), "%s exists; this script runs once" % out
if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
geo = bpy.data.objects["geo"]
aw, ah = geo.scale.x / 1000.0, geo.scale.z / 3.0   # authored size over the 2 km convention (1000, 1000, 3)
fx, fz = 0.2 / aw, 0.2 / ah
for o in bpy.data.objects:
    if o.parent is None:
        o.location = Vector((o.location.x * fx, o.location.y * fx, o.location.z * fz))
        if o.type != "EMPTY":
            o.scale = Vector((o.scale.x * fx, o.scale.y * fx, o.scale.z * fz))
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=out, copy=True)
print("SAVED", out, "factors", fx, fz)
bpy.ops.wm.quit_blender()
