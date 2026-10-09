"""Build art/world/props.blend: shared placeholder prop library (collections are linked into landscape and POI files).

Run: blender.exe -b --python tools/blender/build_props.py -- <repo_root>
PLACEHOLDER: all shapes are stand-ins.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from common import *

root = script_args()[0]
set_texdir(root)
reset_scene()
set_pixel_world()
sc = bpy.context.scene
sc.name = "props"

tint = lambda k: (k, k, k, 1.0)


def prop(name, build):
    coll = bpy.data.collections.new(name)
    sc.collection.children.link(coll)
    b = Builder()
    build(b)
    ob = b.to_object(name + "_mesh", coll)
    ob["PLACEHOLDER"] = PLACEHOLDER_NOTE
    for x in (coll, ob):
        try:
            x.asset_mark()
        except Exception:
            pass
    return coll


def tree_cone(b):
    b.cone((0, 0, 0), (0.45, 0.45, 2.0), "bark", tint(0.9), top=0.8, segs=5)
    b.cone((0, 0, 1.5), (3.0, 3.0, 4.5), "leaf_pine", tint(0.9), segs=6)
    b.cone((0, 0, 4.2), (2.2, 2.2, 4.0), "leaf_pine", tint(1.0), segs=6)
    b.cone((0, 0, 6.6), (1.4, 1.4, 3.4), "leaf_pine", tint(1.0), segs=6)


def tree_lollipop(b):
    b.cone((0, 0, 0), (0.5, 0.5, 4.2), "bark", tint(0.9), top=0.7, segs=5)
    b.ico((0, 0, 6.0), (3.0, 3.0, 2.8), "leaf_round", tint(1.0), sub=1)


def rock(b):
    b.ico((0, 0, 0.8), (1.6, 1.2, 1.0), "rock", tint(0.9), sub=1)
    b.ico((1.5, 0.6, 0.4), (0.8, 0.7, 0.5), "rock", tint(1.0), sub=1)


def ruin_wall(b):
    b.box((0, 0, 0), (6.0, 0.8, 3.0), "stone", tint(0.85))
    b.box((-1.2, 0, 3.0), (2.4, 0.8, 1.2), "stone", tint(0.9))
    b.box((2.4, 0, 0), (1.2, 1.2, 4.2), "stone", tint(0.8))
    b.box((3.6, 0.6, 0), (1.2, 0.9, 0.9), "stone", tint(0.95), rot=0.4)


def fence(b):
    for x in (-1.4, 0.0, 1.4):
        b.box((x, 0, 0), (0.15, 0.15, 1.2), "wood", tint(0.85))
    for z in (0.35, 0.85):
        b.box((0, 0, z), (3.0, 0.08, 0.12), "wood", tint(1.0))


def grave_marker(b):
    b.box((0, 0, 0), (0.7, 0.25, 1.0), "stone", tint(0.85))
    b.cone((0, 0, 1.0), (0.35, 0.125, 0.25), "stone", tint(0.9), segs=4)  # rough peaked top
    b.box((0, -0.5, 0), (0.6, 1.0, 0.1), "dirt", tint(0.8))


for name, fn in [("tree_cone", tree_cone), ("tree_lollipop", tree_lollipop), ("rock", rock),
                 ("ruin_wall", ruin_wall), ("fence", fence), ("grave_marker", grave_marker)]:
    prop(name, fn)

# lay them out in a row for browsing; instance_offset puts each back at the origin when linked
for i, c in enumerate(sc.collection.children):
    x = i * 10.0 - 25
    for ob in c.objects:
        ob.location = (x, 0, 0)
    c.instance_offset = (x, 0, 0)
add_light_and_sky(sc.collection)
placeholder_text(sc.collection, "PLACEHOLDER props", (-27, -6, 0), 1.5, (math.radians(90), 0, 0))
save(os.path.join(root, "art/world/props.blend"))
print("props saved")
