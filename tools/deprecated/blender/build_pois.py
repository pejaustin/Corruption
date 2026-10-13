"""Build art/world/pois/*.blend: one modular file per sketch place + _template, holy_site, graveyard.

Run: blender.exe -b --python tools/blender/build_pois.py -- <repo_root> [only_name ...]
PLACEHOLDER: stand-in shapes, names are the spellings read from Austin's sketch (ticket #606, unconfirmed).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from common import *
from poi_shapes import KINDS, Site

root, *only = script_args()

# file name, kind, ground radius (m), ground material
POIS = [
    ("avequalla", "castle", 80, "grass"),
    ("nofishun", "fort", 60, "rock"),
    ("northwood", "forest_clearing", 70, "grass"),
    ("old_gate", "gate_ruin", 50, "grass"),
    ("teshfield", "hamlet", 70, "grass"),
    ("veilton", "road_end", 40, "dirt"),
    ("valley_cross", "walled_town_round", 90, "grass"),
    ("hopes_gates", "walled_town_square", 100, "grass"),
    ("alebend", "farm", 80, "grass"),
    ("entwar", "river_tower", 60, "sand"),
    ("elder_woods", "great_tree", 90, "grass"),
    ("lastford", "ford", 70, "grass"),
    ("hells_mouth", "volcano", 130, "ash"),
    ("unnamed_harbour", "harbour", 80, "sand"),
    ("_template", "template", 40, "grass"),
    ("holy_site", "holy_site", 50, "grass"),
    ("graveyard", "graveyard", 45, "grass"),
]


def build(name, kind, radius, gmat):
    set_texdir(root)
    reset_scene()
    set_pixel_world()
    sc = bpy.context.scene
    sc.name = name
    sc["kind"] = kind
    sc["landscape_marker"] = "poi_" + name
    cvis = new_collection("Visual")
    ccol = new_collection("Collision (-col)")
    cmark = new_collection("Markers")
    cref = new_collection("Reference (-noimp)")
    path = os.path.join(root, "art/world/pois/%s.blend" % name)
    save(path)  # saved first so linking props.blend can use a relative path

    site = Site()
    KINDS[kind](site)

    # ground patch: visual + collision proxy
    g = Builder()
    g.cone((0, 0, -0.6), (radius, radius, 0.6), gmat, (0.95, 0.95, 0.95, 1), top=1.0, segs=24)
    ground = g.to_object("ground", cvis)
    site.col.cone((0, 0, -0.6), (radius, radius, 0.6), "stone", (1, 1, 1, 1), top=1.0, segs=24)

    site.vis.slot("stone")
    vis = site.vis.to_object("%s_blockout" % name, cvis)
    col = site.col.to_object("%s_blockout-col" % name, ccol)
    col.hide_render = True
    col.display_type = "WIRE"
    for ob in (vis, col, ground):
        ob["PLACEHOLDER"] = PLACEHOLDER_NOTE

    empty("site", (0, 0, 0), "CUBE", 2.0, cmark)["note"] = "Godot-owned: the POI's site/anchor goes here"
    empty("spawn", (0, -radius * 0.5, 0), "SINGLE_ARROW", 3.0, cmark).rotation_euler = (math.radians(90), 0, 0)
    add_light_and_sky(cref)
    scale_figure(cref, (3, -radius * 0.4, 0))
    placeholder_text(cref, "PLACEHOLDER %s (%s)" % (name, kind), (-radius * 0.9, radius * 0.75, 0.2), radius / 12)

    if site.props:
        lib = link_props(os.path.join(root, "art/world/props.blend"))
        for i, (pn, loc, rot, scl) in enumerate(site.props):
            if pn in lib:
                instance(lib[pn], "%s_%d" % (pn, i), loc, rot, scl, cvis)
    save(path)
    print("saved", path)


for entry in POIS:
    if not only or entry[0] in only:
        build(*entry)
