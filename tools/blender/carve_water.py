"""One-off: sink the ground under Austin's water outlines (Austin, 2026-10-12: "a one off sinking of the land in blender,
maybe by transposing the water feature vertices onto the main land, subdividing, and lowering with weight").

In your own Blender: open world_landscape.blend, Scripting tab, open this file, Run Script (changes `geo` in the open file;
Ctrl+Z undoes it; save when you like it). Or headless, writing a copy:
blender -b source/world_landscape.blend --python tools/blender/carve_water.py -- <out.blend>

For each water outline (`Pale River`, `The Still Lake`, `Glittering Ocean`), seen straight down onto `geo`:
1. the `geo` faces under the river and lake (plus one face of margin) are subdivided once (the ocean is not: it is wide);
2. every `geo` vertex inside an outline gets a weight that rises from 0 on the outline to 1 at BANK_M inside it
   (smoothstep), kept as the vertex group `water_carve` (the highest weight where outlines overlap);
3. it is lowered by that weight: the river DEPTH_M below the ground it was on; the lake and the sea to DEPTH_M below their
   water level (lake: the lowest ground on its outline; sea: the height of Austin's ocean plane), never raised.
Only `geo` changes; the outlines, markers and everything else are untouched. Headless, it writes <out.blend>, never the input.
"""
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else None

# PLACEHOLDER: depths, bank widths and the lake/sea levels are stand-ins, not designed by Austin.
FEATURES = {  # outline name -> (kind, DEPTH_M, BANK_M)
    "Pale River": ("river", 3.0, 6.0),
    "The Still Lake": ("lake", 4.0, 15.0),
    "Glittering Ocean": ("sea", 8.0, 40.0),
}
SUBDIVIDE = {"river", "lake"}
SAMPLE_M = 1.0   # spacing of the points sampled along each outline

geo = bpy.data.objects["geo"]
mw = geo.matrix_world
mw_inv = mw.inverted()


def footprint(o):
    """The outline flattened onto z = 0: a BVH for inside tests, a KD-tree of points along its boundary, and the
    boundary points themselves."""
    me = o.data
    ws = [o.matrix_world @ v.co for v in me.vertices]
    flat = [Vector((v.x, v.y, 0.0)) for v in ws]
    bvh = BVHTree.FromPolygons(flat, [p.vertices[:] for p in me.polygons])
    count = {}
    for p in me.polygons:
        for k in p.edge_keys:
            count[k] = count.get(k, 0) + 1
    pts = []
    for (a, b), n in count.items():
        if n != 1:
            continue
        pa, pb = flat[a], flat[b]
        steps = max(1, int((pb - pa).length / SAMPLE_M))
        pts += [pa.lerp(pb, i / steps) for i in range(steps + 1)]
    kd = KDTree(len(pts))
    for i, p in enumerate(pts):
        kd.insert(p, i)
    kd.balance()
    return bvh, kd, pts, ws


def inside(bvh, x, y):
    hit = bvh.ray_cast(Vector((x, y, 1.0)), Vector((0, 0, -1)), 2.0)
    return hit[0] is not None


bm = bmesh.new()
bm.from_mesh(geo.data)
bm.verts.ensure_lookup_table()
before = len(bm.verts)

feats = {}
for name, (kind, depth, bank) in FEATURES.items():
    o = bpy.data.objects.get(name)
    if o is None:
        print("MISSING", name)
        continue
    feats[name] = (kind, depth, bank) + footprint(o)

# 1. subdivide under the river and the lake
sub_faces = set()
for name, (kind, depth, bank, bvh, kd, pts, ws) in feats.items():
    if kind not in SUBDIVIDE:
        continue
    xs = [v.x for v in ws]
    ys = [v.y for v in ws]
    lo, hi = Vector((min(xs) - 20, min(ys) - 20)), Vector((max(xs) + 20, max(ys) + 20))
    for f in bm.faces:
        c = mw @ f.calc_center_median()
        if not (lo.x <= c.x <= hi.x and lo.y <= c.y <= hi.y):
            continue
        if inside(bvh, c.x, c.y) or any(inside(bvh, *(mw @ v.co).xy) for v in f.verts):
            sub_faces.add(f)
            sub_faces.update(lf for v in f.verts for lf in v.link_faces)   # one face of margin
edges = list({e for f in sub_faces for e in f.edges})
bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True)
bm.verts.ensure_lookup_table()
print("SUBDIVIDED faces", len(sub_faces), "verts", before, "->", len(bm.verts))

# ground heights along each outline, for the lake and sea levels
bvh_geo = BVHTree.FromBMesh(bm)


def ground(x, y):
    o = mw_inv @ Vector((x, y, 1e5))
    d = (mw_inv.to_3x3() @ Vector((0, 0, -1))).normalized()
    hit = bvh_geo.ray_cast(o, d)
    return (mw @ hit[0]).z if hit[0] else None


# 2. + 3. weight and lower
weights = {}
new_z = {}
for name, (kind, depth, bank, bvh, kd, pts, ws) in feats.items():
    if kind == "lake":
        gs = [g for g in (ground(p.x, p.y) for p in pts) if g is not None]
        level = min(gs)
    elif kind == "sea":
        level = sum(v.z for v in ws) / len(ws)
    else:
        level = None
    xs = [v.x for v in ws]
    ys = [v.y for v in ws]
    moved = 0
    for v in bm.verts:
        w_co = mw @ v.co
        if not (min(xs) <= w_co.x <= max(xs) and min(ys) <= w_co.y <= max(ys)):
            continue
        if not inside(bvh, w_co.x, w_co.y):
            continue
        d = kd.find(Vector((w_co.x, w_co.y, 0.0)))[2]
        t = min(1.0, d / bank)
        w = t * t * (3 - 2 * t)
        z0 = new_z.get(v.index, w_co.z)
        target = z0 - depth if kind == "river" else min(z0, level - depth)
        z1 = min(z0, z0 + (target - z0) * w)
        new_z[v.index] = z1
        weights[v.index] = max(weights.get(v.index, 0.0), w)
        moved += 1
    print("CARVED", name, kind, "level", None if level is None else round(level, 2), "verts", moved)

for i, z in new_z.items():
    v = bm.verts[i]
    w_co = mw @ v.co
    w_co.z = z
    v.co = mw_inv @ w_co

bm.to_mesh(geo.data)
bm.free()
geo.data.update()

vg = geo.vertex_groups.get("water_carve") or geo.vertex_groups.new(name="water_carve")
for i, w in weights.items():
    vg.add([i], w, "REPLACE")

if OUT:
    bpy.ops.wm.save_as_mainfile(filepath=OUT, copy=True)
    print("WROTE", OUT)
