"""Build art/world/source/world_landscape.blend: the one-file placeholder world (1 unit = 1 m).

Run: blender.exe -b --python tools/blender/build_landscape.py -- <repo_root>
Requires art/world/props.blend (run build_props.py first). Layout data lives in world_data.py.
PLACEHOLDER: size, shapes, heights and names are stand-ins read off Austin's sketch.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils.bvhtree import BVHTree
from common import *
from poi_shapes import KINDS, Site
from world_data import *

root = script_args()[0]
OUT = os.path.join(root, "art/world/source/world_landscape.blend")
PROPS = os.path.join(root, "art/world/props.blend")
REFDIR = os.path.join(root, "art/world/source/reference")
rs = np.random.default_rng(606)

# ---------------------------------------------------------------- numpy helpers
smooth = lambda t: (lambda c: c * c * (3 - 2 * c))(np.clip(t, 0, 1))


def chaikin(pts, it=2):
    pts = np.asarray(pts, float)
    for _ in range(it):
        q = 0.75 * pts[:-1] + 0.25 * pts[1:]
        r = 0.25 * pts[:-1] + 0.75 * pts[1:]
        new = np.empty((len(q) * 2, 2))
        new[0::2], new[1::2] = q, r
        pts = np.vstack([pts[:1], new, pts[-1:]])
    return pts


def densify(pts, step):
    out = [pts[0]]
    for a, b in zip(pts[:-1], pts[1:]):
        L = np.hypot(*(b - a))
        n = max(1, int(L // step))
        for i in range(1, n + 1):
            out.append(a + (b - a) * i / n)
    return np.array(out)


def pip(X, Y, poly):
    inside = np.zeros(X.shape, bool)
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        inside ^= ((y1 > Y) != (y2 > Y)) & (X < (x2 - x1) * (Y - y1) / (y2 - y1 + 1e-12) + x1)
    return inside


def dist_poly(X, Y, poly):
    best = np.full(X.shape, 1e9)
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        ab = b - a
        t = np.clip(((X - a[0]) * ab[0] + (Y - a[1]) * ab[1]) / (ab @ ab + 1e-12), 0, 1)
        best = np.minimum(best, np.hypot(X - (a[0] + t * ab[0]), Y - (a[1] + t * ab[1])))
    return best


def nearest(S, X, Y):
    best = np.full(X.shape, 1e9)
    bi = np.zeros(X.shape, int)
    for k in range(0, len(S), 200):
        sk = S[k:k + 200]
        d = np.hypot(X[:, None] - sk[None, :, 0], Y[:, None] - sk[None, :, 1])
        j = d.argmin(1)
        dm = d[np.arange(len(X)), j]
        m = dm < best
        best[m], bi[m] = dm[m], j[m] + k
    return best, bi


def moving(a, n):
    k = np.ones(n) / n
    pad = np.pad(a, (n // 2, n // 2), mode="edge")
    return np.convolve(pad, k, mode="valid")[:len(a)]


def wave_noise(X, Y, seed):
    r = np.random.default_rng(seed)
    out = 0
    for f, a in ((1 / 420, 1.0), (1 / 160, 0.5), (1 / 70, 0.2)):
        for _ in range(3):
            ang, ph = r.uniform(0, 6.283, 2)
            out = out + a / 3 * np.sin((X * np.cos(ang) + Y * np.sin(ang)) * f * 6.2832 + ph)
    return out


# ---------------------------------------------------------------- layout in world metres
POI = {}
for k, (xy, kind, rf, rb, mind, coastal) in POIS.items():
    POI[k] = dict(xy=np.array(P(*xy)), kind=kind, rf=rf, rb=rb, mind=mind, coastal=coastal)
sea_poly = PL(SEA)
sdist = lambda X, Y: np.where(pip(X, Y, sea_poly), 1, -1) * dist_poly(X, Y, sea_poly)

river_pts = {k: chaikin(PL(v["pts"]), 2) for k, v in RIVERS.items()}
lake_pts = {k: chaikin(PL(v["pts"]), 2) for k, v in LAKES.items()}
river_s = {k: densify(v, 8.0) for k, v in river_pts.items()}
lake_s = {k: densify(v, 14.0) for k, v in lake_pts.items()}
road_s = {k: densify(chaikin(PL(v), 2), 8.0) for k, v in ROADS.items()}
all_water = np.vstack(list(river_s.values()) + list(lake_s.values()))

# keep POIs off the river banks / inland of the coast (sketch icons sit right on the water)
for k, p in POI.items():
    for _ in range(80):
        moved = False
        if p["mind"] > 0:
            d, i = nearest(all_water, np.array([p["xy"][0]]), np.array([p["xy"][1]]))
            if d[0] < p["mind"]:
                v = p["xy"] - all_water[i[0]]
                p["xy"] = p["xy"] + v / (np.hypot(*v) + 1e-9) * 6.0
                moved = True
        if p["coastal"] and sdist(np.array([p["xy"][0]]), np.array([p["xy"][1]]))[0] > -55:
            p["xy"] = p["xy"] + np.array([-6.0, 0.0])
            moved = True
        if not moved:
            break

# ---------------------------------------------------------------- peaks
keep = np.vstack([all_water[::3]] + [v[::3] for v in road_s.values()] + [np.array([q["xy"] for q in POI.values()])])
peaks = []   # (x, y, r, h)
for poly_px, hmax in MOUNTAINS:
    poly = PL(poly_px)
    lo, hi = poly.min(0), poly.max(0)
    mine = []
    for _ in range(14000):
        x, y = rs.uniform(lo[0], hi[0]), rs.uniform(lo[1], hi[1])
        if not pip(np.array([x]), np.array([y]), poly)[0]:
            continue
        if np.hypot(keep[:, 0] - x, keep[:, 1] - y).min() < 55:
            continue
        if mine and np.hypot(np.array(mine)[:, 0] - x, np.array(mine)[:, 1] - y).min() < 36:
            continue
        edge = dist_poly(np.array([x]), np.array([y]), poly)[0]
        h = hmax * (0.45 + 0.55 * rs.random()) * (0.3 + 0.7 * float(smooth(edge / 140)))
        mine.append((x, y))
        peaks.append((x, y, h * 1.05, h))
pk = np.array(peaks)
vx, vy = P(*POIS["hells_mouth"][0])
VOLC = (vx, vy, 270.0, 100.0)


def terrain0(X, Y):
    """Ground height before carving rivers: plains + peaks + volcano + POI pads + sea."""
    base = 3.0 + 0.006 * (900 - X) + 2.2 * wave_noise(X, Y, 11)
    H = base.copy()
    for ch in range(0, len(pk), 60):
        c = pk[ch:ch + 60]
        d = np.hypot(X[..., None] - c[:, 0], Y[..., None] - c[:, 1])
        cone = np.clip(c[:, 3] * (1 - d / c[:, 2]), 0, None).max(-1)
        H = np.maximum(H, base + cone) if ch == 0 else np.maximum(H, base + cone)
    dv = np.hypot(X - VOLC[0], Y - VOLC[1])
    cone = np.clip(VOLC[3] * (1 - dv / VOLC[2]), 0, None)
    cone = np.where(dv < 48, 72 + dv * 0.5 + 0, cone)   # crater bowl
    H = np.maximum(H, base + cone)
    for p in POI.values():
        if p["rf"] > 0:
            c = terrain_pad_height(p)
            d = np.hypot(X - p["xy"][0], Y - p["xy"][1])
            t = smooth((d - p["rf"]) / max(p["rb"], 1))
            H = c * (1 - t) + H * t
    sd = sdist(X, Y)
    inland = smooth(-sd / 60.0)
    beach = 0.7 + 0.002 * np.clip(-sd, 0, 60)
    land = beach * (1 - inland) + H * inland
    sea = 0.7 - 7.0 * smooth(sd / 90.0)
    return np.where(sd > 0, sea, land)


_pad = {}


def terrain_pad_height(p):
    key = tuple(p["xy"])
    if key not in _pad:
        ring = [p["xy"] + np.array([math.cos(a), math.sin(a)]) * p["rf"] for a in np.linspace(0, 6.28, 8)]
        ring = np.array(ring + [p["xy"]])
        base = 3.0 + 0.006 * (900 - ring[:, 0]) + 2.2 * wave_noise(ring[:, 0], ring[:, 1], 11)
        c = base.mean()
        # raise pads that sit in mountains to the local peak mean (cheap: sample peaks near)
        d = np.hypot(pk[:, 0] - p["xy"][0], pk[:, 1] - p["xy"][1])
        near = d < 60
        if near.any():
            c = c + 0.5 * np.mean(pk[near, 3] * (1 - d[near] / pk[near, 2]))
        _pad[key] = max(c, 1.2)
    return _pad[key]


# ---------------------------------------------------------------- water profiles
feat = {}   # name -> dict(S, w, bed, water, lake)
for name, v in LAKES.items():
    S = lake_s[name]
    h = terrain0(S[:, 0], S[:, 1])
    level = float(h.min()) - 1.5
    feat[name] = dict(S=S, w=v["w"], bed=np.full(len(S), level - 3.0), water=np.full(len(S), level), lake=True)
RIVER_OFF = 1.2
order = ["river_main", "river_south"] + [k for k in RIVERS if k not in ("river_main", "river_south")]
for name in order:
    v = RIVERS[name]
    S = river_s[name]
    h = moving(terrain0(S[:, 0], S[:, 1]), 9)
    bed = h - v["depth"]
    sd = sdist(S[:, 0], S[:, 1])
    bed = np.minimum(bed, np.where(sd > -150, -1.0 + (-sd.clip(-150, 0)) / 150.0 * 4.0, 1e9))   # reach the sea
    bed = np.minimum.accumulate(bed)
    bed = np.minimum.accumulate(moving(bed, 7))
    if "join" in v and v["join"] in feat:
        tgt = feat[v["join"]]
        d, i = nearest(tgt["S"], S[-1:, 0], S[-1:, 1])
        tb = tgt["water"][i[0]] - RIVER_OFF
        dist_end = np.cumsum(np.r_[0, np.hypot(*np.diff(S, axis=0).T)])[::-1]
        t = smooth(1 - dist_end / 90.0)
        bed = bed * (1 - t) + np.minimum(bed, tb) * t if False else bed * (1 - t) + tb * t
    feat[name] = dict(S=S, w=v["w"], bed=bed, water=bed + RIVER_OFF, lake=False)
# lake outflow starts at the lake level
lo = feat["river_lake_out"]
lo["bed"] = np.minimum(lo["bed"], feat["lake_avequalla"]["water"][-1] - RIVER_OFF - 0.5)

# ---------------------------------------------------------------- ground mesh
set_texdir(root)
reset_scene()
set_pixel_world()
sc = bpy.context.scene
sc.name = "world_landscape"
C = {n: new_collection(n) for n in ("Ground", "Water", "Roads", "Forest", "POI markers", "Tower slots",
                                    "Reference (-noimp)")}
root_e = empty("world_root", (0, 0, 0), "PLAIN_AXES", 50.0, C["Ground"])
root_e["PLACEHOLDER"] = "world size %dx%d m is a placeholder until the scale test (ticket #603)" % (WORLD_W, WORLD_H)
root_e["world_size_m"] = (WORLD_W, WORLD_H)
save(OUT)

CELL = 16.0
nx, ny = int(WORLD_W / CELL), int(WORLD_H / CELL)
xs = np.linspace(-WORLD_W / 2, WORLD_W / 2, nx + 1)
ys = np.linspace(-WORLD_H / 2, WORLD_H / 2, ny + 1)
GX, GY = np.meshgrid(xs, ys)
jit = rs.uniform(-4, 4, (2,) + GX.shape)
jit[:, 0, :] = jit[:, -1, :] = 0
jit[:, :, 0] = jit[:, :, -1] = 0
GX, GY = GX + jit[0], GY + jit[1]
GH = terrain0(GX, GY)
fx, fy, fh = GX.ravel(), GY.ravel(), GH.ravel()
for name, f in feat.items():
    wc = max(f["w"], 14.0)
    for lo_i in range(0, len(fx), 4000):
        sl = slice(lo_i, lo_i + 4000)
        d, i = nearest(f["S"], fx[sl], fy[sl])
        carved = f["bed"][i] + np.maximum(0.0, d - wc / 2) * 0.42
        fh[sl] = np.minimum(fh[sl], carved)
GH = fh.reshape(GX.shape)

bm_g = Builder()
bm = bm_g.bm
verts = [[bm.verts.new((GX[j, i], GY[j, i], GH[j, i])) for i in range(nx + 1)] for j in range(ny + 1)]
forest_polys = {k: PL(v["poly"]) for k, v in FORESTS.items()}
ash_c = np.array(P(ASH[0], ASH[1]))
ash_r = np.array([ASH[2] / (SK["x1"] - SK["x0"]) * WORLD_W, ASH[3] / (SK["y1"] - SK["y0"]) * WORLD_H])
fld = [(*P(a, b), c / (SK["x1"] - SK["x0"]) * WORLD_W, d / (SK["y1"] - SK["y0"]) * WORLD_H) for a, b, c, d in FIELDS]
slot = dict(grass=bm_g.slot("grass"), rock=bm_g.slot("rock"), sand=bm_g.slot("sand"), dirt=bm_g.slot("dirt"),
            snow=bm_g.slot("snow"), ash=bm_g.slot("ash"))
mats = ["grass", "rock", "sand", "dirt", "snow", "ash"]


def add_tri(a, b, c):
    f = bm.faces.new((a, b, c))
    cx = (a.co.x + b.co.x + c.co.x) / 3
    cy = (a.co.y + b.co.y + c.co.y) / 3
    cz = (a.co.z + b.co.z + c.co.z) / 3
    nz = f.normal.z if False else None
    n = (b.co - a.co).cross(c.co - a.co).normalized()
    nz = abs(n.z)
    X, Y = np.array([cx]), np.array([cy])
    sd = sdist(X, Y)[0]
    shade = 0.86 + 0.14 * rs.random()
    tint = (1.0, 1.0, 1.0)
    if cz < 1.6 or sd > -22:
        m = "sand"
        tint = (1.0, 0.97, 0.9)
    elif cz > 100 and math.hypot(cx - VOLC[0], cy - VOLC[1]) > 300:
        m = "snow"
    elif nz < 0.86 or cz > 42:
        m = "rock"
        tint = (0.95, 0.92, 0.9) if cz < 60 else (0.85, 0.85, 0.9)
    elif ((cx - ash_c[0]) / ash_r[0]) ** 2 + ((cy - ash_c[1]) / ash_r[1]) ** 2 < 1.0:
        m = "ash"
    else:
        m = "grass"
        tint = (0.88, 0.97, 0.8) if cz > 35 else (1.0, 1.0, 1.0)
        for pk_name, poly in forest_polys.items():
            if pip(X, Y, poly)[0] and pk_name != "lastford_grove":
                tint = (0.62, 0.8, 0.62)
        for fxx, fyy, rx, ry in fld:
            if ((cx - fxx) / rx) ** 2 + ((cy - fyy) / ry) ** 2 < 1.0:
                tint = (1.0, 0.92, 0.5)
    idx = slot[m]
    f.material_index = idx
    f.smooth = False
    col = (tint[0] * shade, tint[1] * shade, tint[2] * shade, 1.0)
    for l in f.loops:
        l[bm_g.col] = col
        l[bm_g.uv].uv = (l.vert.co.x / 6.0, l.vert.co.y / 6.0)
    return f


for j in range(ny):
    for i in range(nx):
        v00, v10, v01, v11 = verts[j][i], verts[j][i + 1], verts[j + 1][i], verts[j + 1][i + 1]
        if (i + j) % 2:
            add_tri(v00, v10, v11)
            add_tri(v00, v11, v01)
        else:
            add_tri(v00, v10, v01)
            add_tri(v10, v11, v01)
bm_g.slots = mats
ground = bm_g.to_object("ground", C["Ground"])
ground["PLACEHOLDER"] = PLACEHOLDER_NOTE
ground.parent = root_e
bvh = BVHTree.FromObject(ground, bpy.context.evaluated_depsgraph_get())


def gz(x, y):
    r = bvh.ray_cast(Vector((x, y, 400.0)), Vector((0, 0, -1)))
    return r[0].z if r[0] else 0.0


# ---------------------------------------------------------------- sea, water, roads
b = Builder()
b.quad([(-WORLD_W / 2, -WORLD_H / 2, 0), (WORLD_W / 2, -WORLD_H / 2, 0), (WORLD_W / 2, WORLD_H / 2, 0),
        (-WORLD_W / 2, WORLD_H / 2, 0)], "water", (0.9, 0.95, 1, 1),
       [(-WORLD_W / 12, -WORLD_H / 12), (WORLD_W / 12, -WORLD_H / 12), (WORLD_W / 12, WORLD_H / 12),
        (-WORLD_W / 12, WORLD_H / 12)])
sea = b.to_object("water_sea", C["Water"])
sea.parent = root_e


def ribbon(bld, S, z, hw, mat, col, vscale=6.0):
    t = np.gradient(S, axis=0)
    t /= np.hypot(t[:, 0], t[:, 1])[:, None] + 1e-9
    n = np.stack([-t[:, 1], t[:, 0]], 1)
    s = np.r_[0, np.cumsum(np.hypot(*np.diff(S, axis=0).T))]
    for i in range(len(S) - 1):
        a = (S[i, 0] + n[i, 0] * hw, S[i, 1] + n[i, 1] * hw, z[i])
        b2 = (S[i, 0] - n[i, 0] * hw, S[i, 1] - n[i, 1] * hw, z[i])
        c = (S[i + 1, 0] - n[i + 1, 0] * hw, S[i + 1, 1] - n[i + 1, 1] * hw, z[i + 1])
        d = (S[i + 1, 0] + n[i + 1, 0] * hw, S[i + 1, 1] + n[i + 1, 1] * hw, z[i + 1])
        bld.quad([a, b2, c, d], mat, col, [(0, s[i] / vscale), (2 * hw / vscale, s[i] / vscale),
                                           (2 * hw / vscale, s[i + 1] / vscale), (0, s[i + 1] / vscale)])


wr, wl = Builder(), Builder()
for name, f in feat.items():
    z = f["water"]
    if not f["lake"]:
        z = moving(np.array([gz(x, y) for x, y in f["S"]]), 5) + 0.55   # follow the carved bed (the grid is coarse)
    ribbon(wl if f["lake"] else wr, f["S"], z, f["w"] / 2 + (4.0 if f["lake"] else 2.0), "water", (1, 1, 1, 1))
for bld, n in ((wr, "water_rivers"), (wl, "water_lakes")):
    ob = bld.to_object(n, C["Water"])
    ob.parent = root_e
    ob["PLACEHOLDER"] = PLACEHOLDER_NOTE

rb = Builder()
for name, S in road_s.items():
    z = np.array([max(gz(x, y), gz(x + 3, y), gz(x - 3, y), gz(x, y + 3), gz(x, y - 3)) for x, y in S])
    zz = np.array([z[max(0, i - 3):i + 4].max() for i in range(len(z))])
    zz = moving(zz, 5) + 0.3
    ribbon(rb, S, zz, 3.2, "dirt", (0.95, 0.85, 0.7, 1))
roads = rb.to_object("roads", C["Roads"])
roads.parent = root_e
roads["PLACEHOLDER"] = PLACEHOLDER_NOTE

# lava pool in the crater
lb = Builder()
lb.cone((VOLC[0], VOLC[1], gz(VOLC[0], VOLC[1]) + 0.2), (24, 24, 0.3), "lava", (1, 1, 1, 1), top=1.0, segs=12)
lava = lb.to_object("lava_pool", C["Ground"])
lava.parent = root_e

# ---------------------------------------------------------------- POI markers + stand-ins
poi_obj = {}
for name, p in POI.items():
    x, y = p["xy"]
    z = gz(x, y)
    e = empty("poi_" + name, (x, y, z), "ARROWS", 12.0, C["POI markers"], root_e)
    e["kind"] = p["kind"]
    e["poi_file"] = "pois/%s.blend" % name
    e["PLACEHOLDER"] = "position and name read from the sketch (ticket #606); the shape is a stand-in"
    s = Site()
    if p["kind"] == "volcano":
        pass
    else:
        KINDS[p["kind"]](s)
    if s.vis.bm.verts:
        so = s.vis.to_object("poi_%s_standin" % name, C["POI markers"])
        so.parent = e
        s.col.bm.free()
    poi_obj[name] = e

# ---------------------------------------------------------------- tower slots (Austin places these)
for i in range(4):
    e = empty("tower_slot_%d" % (i + 1), (-WORLD_W / 2 - 80, 240 - i * 160, 0), "SINGLE_ARROW", 40.0, C["Tower slots"], root_e)
    e["placed"] = False
    e["PLACEHOLDER"] = "UNPLACED: Austin drags this onto the map once the world scale is set"
placeholder_text(C["Tower slots"], "TOWER SLOTS 1-4 - UNPLACED (drag onto the map)",
                 (-WORLD_W / 2 - 140, 300, 1), 18, (0, 0, math.radians(90)))

# ---------------------------------------------------------------- forests (linked tree collections)
save(OUT)
lib = link_props(PROPS, ["tree_cone", "tree_lollipop"])
block = np.vstack([all_water, np.vstack(list(road_s.values())), ] )
nt = 0
for fname, fd in FORESTS.items():
    poly = forest_polys[fname]
    lo_, hi_ = poly.min(0), poly.max(0)
    sp = fd["spacing"]
    for x0 in np.arange(lo_[0], hi_[0], sp):
        for y0 in np.arange(lo_[1], hi_[1], sp):
            x = x0 + rs.uniform(-0.4, 0.4) * sp
            y = y0 + rs.uniform(-0.4, 0.4) * sp
            if not pip(np.array([x]), np.array([y]), poly)[0]:
                continue
            if np.hypot(block[:, 0] - x, block[:, 1] - y).min() < 14:
                continue
            if sdist(np.array([x]), np.array([y]))[0] > -25:
                continue
            if any(np.hypot(*(q["xy"] - (x, y))) < max(q["rf"], 20) + 15 for q in POI.values() if q["kind"] != "forest_clearing"
                   and not (fname == "elder_woods" and q["kind"] == "great_tree")):
                continue
            z = gz(x, y)
            if z < 1.5:
                continue
            instance(lib[fd["tree"]], "%s_%d" % (fd["tree"], nt), (x, y, z), rs.uniform(0, 6.28),
                     rs.uniform(0.8, 1.35), C["Forest"], root_e)
            nt += 1
print("trees", nt)

# ---------------------------------------------------------------- reference, scale figure, lights
src = os.path.join(REFDIR, "world-sketch-original.jpg")
crop = os.path.join(REFDIR, "world_sketch_crop.jpg")
if os.path.exists(src):
    im = bpy.data.images.load(src)
    w, h = im.size
    k = w / 2000.0
    x0, x1 = int(SK["x0"] * k), int(SK["x1"] * k)
    ytop, ybot = int(SK["y0"] * k), int(SK["y1"] * k)
    px = np.array(im.pixels[:], np.float32).reshape(h, w, 4)
    sub = px[h - ybot:h - ytop, x0:x1]
    cim = bpy.data.images.new("world_sketch_crop", sub.shape[1], sub.shape[0])
    cim.pixels = sub.ravel().tolist()
    cim.filepath_raw = crop
    cim.file_format = "JPEG"
    cim.save()
    bpy.data.images.remove(im)
    bpy.data.images.remove(cim)
ref = bpy.data.images.load(crop)
ref.filepath = "//reference/world_sketch_crop.jpg"
rm = bpy.data.materials.new("mat_reference_sketch")
rm.use_nodes = True
nt_ = rm.node_tree
nt_.nodes.clear()
o = nt_.nodes.new("ShaderNodeOutputMaterial")
em = nt_.nodes.new("ShaderNodeEmission")
ti = nt_.nodes.new("ShaderNodeTexImage")
ti.image = ref
nt_.links.new(ti.outputs["Color"], em.inputs["Color"])
nt_.links.new(em.outputs["Emission"], o.inputs["Surface"])
rb2 = Builder()
rb2.quad([(-WORLD_W / 2, -WORLD_H / 2, -12), (WORLD_W / 2, -WORLD_H / 2, -12), (WORLD_W / 2, WORLD_H / 2, -12),
          (-WORLD_W / 2, WORLD_H / 2, -12)], "stone", (1, 1, 1, 1), [(0, 0), (1, 0), (1, 1), (0, 1)])
rp = rb2.to_object("ref_sketch-noimp", C["Reference (-noimp)"])
rp.data.materials.clear()
rp.data.materials.append(rm)
rp.hide_render = True
rp.parent = root_e
rp["note"] = "Austin's sketch under the ground; hide 'ground' and the sea to trace over it. Not exported."
sf = scale_figure(C["Reference (-noimp)"], (-WORLD_W / 2 + 40, -WORLD_H / 2 + 40, 0))
sf.location.z = gz(sf.location.x, sf.location.y)
sf.parent = root_e
pt = placeholder_text(C["Reference (-noimp)"],
                      "PLACEHOLDER WORLD %dx%d m - size not decided (#603)" % (WORLD_W, WORLD_H),
                      (-WORLD_W / 2 + 20, WORLD_H / 2 - 60, 160), 30)
pt.rotation_euler = (0, 0, 0)
pt.parent = root_e

sun = bpy.data.objects.new("sun-noimp", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.0
sun.rotation_euler = (math.radians(50), 0, math.radians(35))
C["Reference (-noimp)"].objects.link(sun)
wd = bpy.data.worlds.new("sky")
wd.use_nodes = True
wd.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.75, 0.95, 1)
wd.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
sc.world = wd

for win in bpy.context.window_manager.windows:
    for area in win.screen.areas:
        if area.type == "VIEW_3D":
            for sp in area.spaces:
                if sp.type == "VIEW_3D":
                    sp.clip_end = 6000.0
                    sp.shading.type = "MATERIAL"
save(OUT)
print("landscape saved", len(ground.data.polygons), "tris")
