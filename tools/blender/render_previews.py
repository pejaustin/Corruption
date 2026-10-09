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
    # Austin's map (2026-10-09, +Y north). Every empty is a POI marker: temporary coloured markers + name labels are
    # added here for the render only and are NOT saved to the file.
    load(os.environ.get("PREVIEW_BLEND") or os.path.join(root, "art/world/source/world_landscape.blend"))
    sc = bpy.context.scene
    sun = bpy.data.objects.new("rsun", bpy.data.lights.new("rsun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    sc.collection.objects.link(sun)
    w = sc.world or bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.45, 0.65, 0.95, 1)
    bg.inputs[1].default_value = 1.0
    mk = bpy.data.materials.new("rmark")
    mk.use_nodes = True
    mk.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1, 0.1, 0.6, 1)
    mk.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1, 0.1, 0.6, 1)
    mk.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 3.0
    pois = [o for o in bpy.data.objects if o.type == "EMPTY"]

    def markers(cam_loc, size, flat_up=False):
        made = []
        for e in pois:
            p = e.matrix_world.translation
            bpy.ops.mesh.primitive_uv_sphere_add(radius=size, location=p + Vector((0, 0, size * 3)))
            m = bpy.context.object
            m.data.materials.append(mk)
            bpy.ops.object.text_add(location=p + Vector((0, 0, size * 6)))
            t = bpy.context.object
            t.data.body = e.name
            t.data.size = size * 5
            t.data.align_x = "CENTER"
            t.data.materials.append(mk)
            d = Vector(cam_loc) - t.location
            t.rotation_euler = d.to_track_quat("Z", "Y").to_euler() if not flat_up else (0, 0, 0)
            made += [m, t]
        return made

    def clear(made):
        for o in made:
            bpy.data.objects.remove(o)

    m = markers((0, 0, 3000), 9, flat_up=True)
    shot("map2_top", (0, 0, 3000), (0, 0, 0), ortho=2100, size=(1800, 1800))
    clear(m)
    hg = bpy.data.objects["Hopes Gate"].matrix_world.translation
    cl = (hg.x, hg.y - 300, hg.z + 90)
    m = markers(cl, 3)
    shot("map2_low_north", cl, (hg.x, hg.y + 800, hg.z + 80), lens=24, size=(1800, 900))
    clear(m)
    # along the Pale River: from its south end looking along it
    r = bpy.data.objects["Pale River"]
    pts = [r.matrix_world @ v.co for v in r.data.vertices]
    pts.sort(key=lambda v: v.y)
    a, b = pts[0], pts[-1]
    cl = (a.x, a.y - 150, a.z + 80)
    m = markers(cl, 3)
    shot("map2_low_river", cl, (b.x, b.y, b.z), lens=24, size=(1800, 900))
    clear(m)
