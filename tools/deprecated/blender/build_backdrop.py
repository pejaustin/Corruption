"""Generate the backdrop around Austin's map: art/world/source/world_backdrop.blend. Blender 4.5, background.
Usage: Blender -b --python tools/blender/build_backdrop.py -- <repo_root> [--force] [--out <file.blend>]
Reads art/world/source/world_landscape.blend (never saves it) for geo's edge heights and the Glittering Ocean's level, and
writes a NEW file with two meshes, at game scale (2 km, 1 unit = 1 m, +Y north):
  `backdrop`      a low-poly ring of land from the map's square edge (tucked 12 m under geo, so his edits never open a
                  crack) out to a circle OUTER_R from the centre. Rows get further apart outward (far land covers few
                  pixels). Splat and Col corner colours like geo, so it takes ground_placeholder.
  `backdrop sea`  water at his ocean's level, the same ring (under the land where the land is higher).
Never walkable: no collision, no navmesh (export_backdrop.py / the Godot scene). The curved-world shader hides it past the
horizon; the far rows carry the silhouette.
What lies beyond each edge (Austin, 2026-10-12): north a mountain wall, east ocean (the Glittering Ocean carries on), south
a mountain wall, west rolling hills. Austin sculpts the generated file from here, so this REFUSES to overwrite an existing
world_backdrop.blend unless --force.
PLACEHOLDER: every shape number below (distances, heights, noise) and the corner blends are stand-ins, not designed."""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector, noise
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import script_args  # noqa: E402

args = script_args()
root = args[0]
force = "--force" in args
dst = args[args.index("--out") + 1] if "--out" in args else os.path.join(root, "art/world/source/world_backdrop.blend")
src = os.path.join(root, "art/world/source/world_landscape.blend")
if os.path.exists(dst) and not force:
    print("REFUSED: %s exists (Austin's sculpt); pass --force to regenerate it" % dst)
    sys.exit(1)

HALF = 1000.0               # the map's square half-width at 2 km
TUCK_IN = 12.0              # the first row sits this far inside the edge, under geo
TUCK_DOWN = 1.5             # ... and this far below it
OUTER_R = 5000.0            # PLACEHOLDER: tuning — the ring's outer radius (the curve hides land past ~3.4 km from 200 m up)
ANGLES = 512                # columns around the ring
# PLACEHOLDER: tuning — rows as fractions of the way from the edge to OUTER_R (closer together near the map)
ROWS = [0.0, 0.004, 0.012, 0.025, 0.045, 0.075, 0.11, 0.16, 0.22, 0.30, 0.39, 0.49, 0.60, 0.72, 0.85, 1.0]
# Direction of each kind of land beyond the edge (Austin, 2026-10-12), as compass angles (0 = east, 90 = north).
SECTORS = {"mountains_n": 90.0, "ocean": 0.0, "mountains_s": 270.0, "hills": 180.0}
SECTOR_SHARPNESS = 6.0      # PLACEHOLDER: tuning — higher = narrower blends at the corners
SEA_FLOOR = -45.0           # PLACEHOLDER: tuning — the ocean floor beyond the edge
ROCK_SLOPE = 0.30           # same slope rule as the old ground seed (add_splat.py)
ROCK_ABOVE = 220.0          # PLACEHOLDER: bare rock above this height
SAND_BAND = 3.0             # sand up to this far above sea level


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def fbm(x, y, scale, octaves=4):
    return noise.fractal(Vector((x / scale, y / scale, 0.0)), 1.0, 2.0, octaves, noise_basis="PERLIN_ORIGINAL")


def ridges(x, y, scale):
    return noise.ridged_multi_fractal(Vector((x / scale, y / scale, 0.7)), 0.9, 2.1, 5, 1.0, 2.0, noise_basis="PERLIN_ORIGINAL")


# PLACEHOLDER: the shapes. d = metres beyond the edge, e = geo's height at the edge.
def mountains(x, y, d, e):
    wall = 260.0 + 140.0 * fbm(x, y, 900.0)            # first range, rising within ~700 m of the edge
    rise = smoothstep(60.0, 700.0, d)
    far = 330.0 + 220.0 * ridges(x, y, 1400.0)          # ranges behind it, carrying the skyline
    h = e + (wall - e) * rise
    return h + (far - h) * smoothstep(900.0, 2200.0, d) + 40.0 * ridges(x, y, 260.0) * rise


def hills(x, y, d, e):
    base = 18.0 + 30.0 * fbm(x, y, 650.0) + 70.0 * smoothstep(1500.0, 4000.0, d) * (0.5 + 0.5 * fbm(x, y, 1800.0))
    return e + (base - e) * smoothstep(0.0, 400.0, d)


def ocean(x, y, d, e, sea):
    floor = min(SEA_FLOOR + 6.0 * fbm(x, y, 400.0), sea - 8.0)
    return e + (floor - e) * smoothstep(0.0, 220.0, d)


# --- read Austin's map (never saved) ---
bpy.ops.wm.open_mainfile(filepath=src)
geo = bpy.data.objects["geo"]
aw = geo.scale.x / 1000.0                    # authored size over 2 km (export_landscape.py's convention)
ah = geo.scale.z / 3.0
mw = geo.matrix_world
mi = mw.inverted()
bvh = BVHTree.FromObject(geo, bpy.context.evaluated_depsgraph_get())
down = (mi.to_3x3() @ Vector((0.0, 0.0, -1.0))).normalized()
ocean_obj = next((o for o in bpy.data.objects if o.type == "MESH" and "ocean" in o.name.lower()), None)
sea = (ocean_obj.matrix_world @ ocean_obj.data.vertices[0].co).z / ah if ocean_obj else -16.8
print("AUTHORED", aw, ah, "SEA", round(sea, 2))


def ground_at(x, y):
    """geo's height (2 km metres) under (x, y) in 2 km metres; None off the map."""
    hit = bvh.ray_cast(mi @ Vector((x * aw, y * aw, 10000.0)), down)
    return (mw @ hit[0]).z / ah if hit[0] else None


def edge_point(theta):
    c, s = math.cos(theta), math.sin(theta)
    r = HALF / max(abs(c), abs(s))
    return c, s, r


cols = []
for i in range(ANGLES):
    th = 2.0 * math.pi * i / ANGLES
    c, s, r_edge = edge_point(th)
    # the lowest ground along this column's stretch of edge, so the ring never stands above geo there
    hs = []
    for k in (-0.5, -0.25, 0.0, 0.25, 0.5):
        cc, ss, rr = edge_point(th + k * 2.0 * math.pi / ANGLES)
        g = ground_at(cc * (rr - 3.0), ss * (rr - 3.0))
        if g is not None:
            hs.append(g)
    e = min(hs) if hs else 0.0
    g_in = ground_at(c * (r_edge - TUCK_IN), s * (r_edge - TUCK_IN))
    cols.append((th, c, s, r_edge, e, g_in if g_in is not None else e))

# --- build the new file ---
bpy.ops.wm.read_factory_settings(use_empty=True)


def sector_weights(th):
    deg = math.degrees(th)
    w = {k: max(0.0, math.cos(math.radians(deg - a))) ** SECTOR_SHARPNESS for k, a in SECTORS.items()}
    t = sum(w.values()) or 1.0
    return {k: v / t for k, v in w.items()}


grid = []   # rows of (x, y, z)
for j, f in enumerate([-1.0] + ROWS):
    row = []
    for th, c, s, r_edge, e, g_in in cols:
        if f < 0.0:
            row.append((c * (r_edge - TUCK_IN), s * (r_edge - TUCK_IN), min(g_in, e) - TUCK_DOWN))
            continue
        r = r_edge + (OUTER_R - r_edge) * f
        x, y, d = c * r, s * r, r - r_edge
        w = sector_weights(th)
        z = (w["mountains_n"] + w["mountains_s"]) * mountains(x, y, d, e) + w["hills"] * hills(x, y, d, e) \
            + w["ocean"] * ocean(x, y, d, e, sea)
        if f == 0.0:
            z = e - TUCK_DOWN * 0.5
        row.append((x, y, z))
    grid.append(row)


def ring_mesh(name, rows, z_of=None):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vs = [[bm.verts.new((x, y, z if z_of is None else z_of)) for x, y, z in row] for row in rows]
    for j in range(len(vs) - 1):
        for i in range(ANGLES):
            a, b = vs[j][i], vs[j][(i + 1) % ANGLES]
            c2, d2 = vs[j + 1][(i + 1) % ANGLES], vs[j + 1][i]
            bm.faces.new((a, d2, c2, b))   # counter-clockwise from above, so normals face up
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob["note"] = "PLACEHOLDER: generated by tools/blender/build_backdrop.py; sculpt freely (Austin, 2026-10-12: N mountains, E ocean, S mountains, W hills)"
    return ob


land = ring_mesh("backdrop", grid)
water = ring_mesh("backdrop sea", [[(x, y, 0.0) for x, y, _ in row] for row in grid[1:]], z_of=sea - 0.25)


def material(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1.0)
    return m


land.data.materials.append(material("ground_placeholder", (0.36, 0.62, 0.24)))
water.data.materials.append(material("water_placeholder", (0.28, 0.50, 0.80)))

# Splat (which texture: R rock, G dirt, B sand, none grass; add_splat.py) and Col (tint, white like most of geo), per corner.
me = land.data
splat = me.color_attributes.new("Splat", "BYTE_COLOR", "CORNER")
col = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
sp = np.zeros((len(me.loops), 4), np.float32)
sp[:, 3] = 1.0
for poly in me.polygons:
    slope = 1.0 - abs(poly.normal.z)
    for li in poly.loop_indices:
        z = me.vertices[me.loops[li].vertex_index].co.z
        if z < sea + SAND_BAND:
            sp[li, 2] = 1.0
        elif slope > ROCK_SLOPE or z > ROCK_ABOVE:
            sp[li, 0] = 1.0
splat.data.foreach_set("color", sp.ravel())
col.data.foreach_set("color", np.tile(np.array([0.98, 0.98, 0.98, 1.0], np.float32), len(me.loops)))
me.color_attributes.active_color = splat

print("BACKDROP", len(me.vertices), "verts", len(me.polygons), "quads; sea", len(water.data.polygons), "quads")
bpy.ops.wm.save_as_mainfile(filepath=dst)
print("SAVED", dst)
