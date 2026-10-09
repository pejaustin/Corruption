"""Render preview PNGs of the blockout (EEVEE, background). Usage:
blender.exe -b --python tools/blender/render_previews.py -- <repo_root> <out_dir>   (landscape top + 2 low views)
blender.exe -b --python tools/blender/render_previews.py -- <repo_root> <out_dir> poi <name> (one POI file)"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
from common import script_args

args = script_args()
root, out = args[0], args[1]
os.makedirs(out, exist_ok=True)


def shot(name, loc, target, ortho=None, lens=28, size=(1600, 1200), clip=8000):
    sc = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    cam.location = loc
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam.data.clip_end = clip
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.lens = lens
    sc.camera = cam
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.filepath = os.path.join(out, name + ".png")
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    print("rendered", sc.render.filepath)


def load(path):
    bpy.ops.wm.open_mainfile(filepath=path)
    for ob in bpy.data.objects:
        if ob.name.startswith("PLACEHOLDER") or ob.name.startswith("ref_sketch"):
            ob.hide_render = True


if len(args) > 2 and args[2] == "poi":
    n = args[3]
    load(os.path.join(root, "art/world/pois/%s.blend" % n))
    shot("poi_" + n, (90, -120, 90), (0, 0, 5), lens=32, size=(1400, 1000), clip=2000)
else:
    load(os.path.join(root, "art/world/source/world_landscape.blend"))
    shot("landscape_top", (0, 0, 3000), (0, 0, 0), ortho=2150, size=(1600, 1200))
    # from near Hope's Gates looking north
    hg = bpy.data.objects["poi_hopes_gates"].location
    shot("landscape_low_north", (hg.x - 40, hg.y - 260, hg.z + 70), (hg.x + 60, hg.y + 700, hg.z + 30), lens=26)
    # along the eastern coast, from the south-east looking north
    shot("landscape_low_coast", (880, -700, 110), (780, 500, 20), lens=24)
