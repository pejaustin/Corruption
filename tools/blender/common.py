"""Shared helpers for the Corruption world blockout generators (Blender 4.5, run in background mode).

PLACEHOLDER: everything generated here is a stand-in blockout, not Austin's design.
"""
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

PLACEHOLDER_NOTE = "PLACEHOLDER: blockout stand-in, not designed by Austin (see art/world/README.md)"

# name -> (base sRGB colour, per-pixel variation, kind)
TEXTURES = {
    "grass": ((0.36, 0.62, 0.24), 0.10, "blades"),
    "rock": ((0.55, 0.52, 0.49), 0.12, "cracks"),
    "sand": ((0.86, 0.78, 0.55), 0.06, "noise"),
    "dirt": ((0.52, 0.38, 0.24), 0.10, "pebbles"),
    "snow": ((0.93, 0.95, 0.98), 0.04, "noise"),
    "ash": ((0.33, 0.29, 0.29), 0.10, "pebbles"),
    "water": ((0.28, 0.50, 0.80), 0.06, "streaks"),
    "stone": ((0.66, 0.65, 0.62), 0.07, "bricks"),
    "roof": ((0.70, 0.30, 0.24), 0.08, "bricks"),
    "plaster": ((0.88, 0.82, 0.70), 0.05, "noise"),
    "wood": ((0.55, 0.38, 0.22), 0.08, "planks"),
    "bark": ((0.40, 0.26, 0.15), 0.10, "planks"),
    "leaf_pine": ((0.16, 0.42, 0.22), 0.12, "blades"),
    "leaf_round": ((0.34, 0.60, 0.20), 0.12, "blades"),
    "lava": ((0.98, 0.45, 0.12), 0.15, "streaks"),
    "canvas": ((0.92, 0.55, 0.15), 0.04, "noise"),  # orange = placeholder figure/markers
}


TEXDIR = [None]   # set by the build scripts: <repo>/art/world/textures


def set_texdir(root):
    TEXDIR[0] = os.path.join(root, "art/world/textures")
    os.makedirs(TEXDIR[0], exist_ok=True)


def write_png(path, rgba):
    """Plain RGBA8 PNG writer (Blender's generated-image save was returning black)."""
    import struct
    import zlib
    h, w, _ = rgba.shape
    raw = b"".join(b"\x00" + rgba[y].tobytes() for y in range(h))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def make_image(name, size=32, seed=1):
    path = os.path.join(TEXDIR[0], name + ".png")
    if os.path.exists(path):
        img = bpy.data.images.load(path)
        img.name = "tex_" + name
        return img
    base, var, kind = TEXTURES[name]
    r = np.random.default_rng(seed)
    base = np.array(base, np.float32)
    px = np.ones((size, size, 4), np.float32)
    shade = 1.0 + var * (r.random((size, size)) - 0.5) * 2
    if kind == "blades":
        for _ in range(size):
            x, y = r.integers(0, size, 2)
            shade[y, x] *= 0.72
    elif kind == "cracks":
        for _ in range(4):
            x, y = r.integers(0, size, 2)
            for _ in range(size // 2):
                shade[y % size, x % size] *= 0.65
                x += int(r.integers(-1, 2))
                y += 1
    elif kind == "pebbles":
        for _ in range(size // 2):
            x, y = r.integers(0, size, 2)
            shade[y, x] *= 1.3
            shade[(y + 1) % size, x] *= 0.75
    elif kind == "streaks":
        for _ in range(size // 3):
            y = int(r.integers(0, size))
            x0 = int(r.integers(0, size))
            for k in range(int(r.integers(4, 10))):
                shade[y, (x0 + k) % size] *= 1.25
    elif kind == "bricks":
        for y in range(0, size, 8):
            shade[y, :] *= 0.7
            for x in range(((y // 8) % 2) * 8, size, 16):
                shade[y:y + 8, x] *= 0.7
    elif kind == "planks":
        shade[:, ::8] *= 0.7
        for _ in range(size // 2):
            x, y = r.integers(0, size, 2)
            shade[y, x] *= 0.7
    px[..., :3] = np.clip(base[None, None, :] * shade[..., None], 0, 1)
    write_png(path, (px * 255 + 0.5).astype(np.uint8))
    img = bpy.data.images.load(path)
    img.name = "tex_" + name
    return img


def get_mat(name):
    """Pixel-look material: tiny nearest-filtered texture x vertex colour 'Col' tint, rough, no specular."""
    mname = "mat_" + name
    if mname in bpy.data.materials:
        return bpy.data.materials[mname]
    img = bpy.data.images.get("tex_" + name) or make_image(name, seed=sum(map(ord, name)))
    m = bpy.data.materials.new(mname)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Specular IOR Level"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    tex.extension = "REPEAT"
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    nt.links.new(tex.outputs["Color"], mix.inputs[6])
    nt.links.new(col.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    if name == "lava":
        nt.links.new(mix.outputs[2], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    return m


def rgba(c, k=1.0):
    return (c[0] * k, c[1] * k, c[2] * k, 1.0)


class Builder:
    """A bmesh + material-slot registry. Primitives are anchored at the bottom centre (cube, cone, cyl)."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.col = self.bm.loops.layers.color.new("Col")
        self.slots = []

    def slot(self, mat):
        if mat not in self.slots:
            self.slots.append(mat)
        return self.slots.index(mat)

    def _paint(self, faces, mat, color):
        idx = self.slot(mat)
        for f in faces:
            f.material_index = idx
            f.smooth = False
            for l in f.loops:
                l[self.col] = color
        return faces

    @staticmethod
    def _faces(geom_verts):
        fs = set()
        for v in geom_verts:
            for f in v.link_faces:
                fs.add(f)
        return list(fs)

    def _mat(self, loc, size, rot, lift):
        return (Matrix.Translation(loc) @ Matrix.Rotation(rot, 4, "Z")
                @ Matrix.Diagonal((size[0], size[1], size[2], 1.0)) @ Matrix.Translation((0, 0, lift)))

    def box(self, loc, size, mat="stone", color=(1, 1, 1, 1), rot=0.0):
        ret = bmesh.ops.create_cube(self.bm, size=1.0, matrix=self._mat(loc, size, rot, 0.5), calc_uvs=True)
        return self._paint(self._faces(ret["verts"]), mat, color)

    def cone(self, loc, size, mat="roof", color=(1, 1, 1, 1), top=0.0, segs=8, rot=0.0):
        """size = (rx, ry, height); top = top radius as a fraction of the base radius (0 = point)."""
        ret = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs, radius1=1.0,
                                    radius2=top, depth=1.0, matrix=self._mat(loc, size, rot, 0.5), calc_uvs=True)
        return self._paint(self._faces(ret["verts"]), mat, color)

    def ico(self, loc, size, mat="leaf_round", color=(1, 1, 1, 1), sub=1):
        """Centred at loc, size = radii."""
        m = Matrix.Translation(loc) @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        ret = bmesh.ops.create_icosphere(self.bm, subdivisions=sub, radius=1.0, matrix=m, calc_uvs=True)
        return self._paint(self._faces(ret["verts"]), mat, color)

    def quad(self, pts, mat, color, uvs=None):
        vs = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(vs)
        if uvs:
            for l, uv in zip(f.loops, uvs):
                l[self.uv].uv = uv
        return self._paint([f], mat, color)

    def to_object(self, name, collection=None, smooth=False):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for s in self.slots:
            me.materials.append(get_mat(s))
        ob = bpy.data.objects.new(name, me)
        if collection is not None:
            collection.objects.link(ob)
        return ob


def new_collection(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(c)
    return c


def empty(name, loc=(0, 0, 0), display="PLAIN_AXES", size=1.0, collection=None, parent=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = display
    e.empty_display_size = size
    e.location = loc
    if collection is not None:
        collection.objects.link(e)
    if parent is not None:
        e.parent = parent
    return e


def placeholder_text(collection, text="PLACEHOLDER", loc=(0, 0, 0), size=1.0, rot=(0, 0, 0)):
    cu = bpy.data.curves.new("PLACEHOLDER_note", "FONT")
    cu.body = text
    cu.size = size
    ob = bpy.data.objects.new("PLACEHOLDER-noimp", cu)
    ob.location = loc
    ob.rotation_euler = rot
    ob["PLACEHOLDER"] = PLACEHOLDER_NOTE
    collection.objects.link(ob)
    bpy.context.scene["PLACEHOLDER"] = PLACEHOLDER_NOTE
    return ob


def scale_figure(collection, loc=(3, -4, 0)):
    """1.8 m stand-in person for scale (not exported: -noimp)."""
    b = Builder()
    o = (1.0, 0.5, 0.1, 1.0)
    b.cone((0, 0, 0), (0.28, 0.2, 1.45), "canvas", o, top=0.7, segs=8)
    b.ico((0, 0, 1.62), (0.18, 0.18, 0.18), "canvas", (1.0, 0.8, 0.6, 1.0))
    ob = b.to_object("scale_figure_1.8m-noimp", collection)
    ob.location = loc
    ob["PLACEHOLDER"] = "1.8 m scale figure"
    return ob


def save(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 backups
    bpy.ops.wm.save_as_mainfile(filepath=path, relative_remap=True, compress=True)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for d in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for x in list(d):
            d.remove(x)


def link_props(propspath, names=None):
    """Link (not append) collections from props.blend, relative path. The current file must already be saved."""
    with bpy.data.libraries.load(propspath, link=True, relative=True) as (src, dst):
        dst.collections = [n for n in src.collections if names is None or n in names]
    return {c.name: c for c in dst.collections}


def instance(coll, name, loc, rot_z=0.0, scale=1.0, collection=None, parent=None):
    e = bpy.data.objects.new(name, None)
    e.instance_type = "COLLECTION"
    e.instance_collection = coll
    e.empty_display_size = 1.0
    e.location = loc
    e.rotation_euler = (0, 0, rot_z)
    e.scale = (scale, scale, scale)
    if collection is not None:
        collection.objects.link(e)
    if parent is not None:
        e.parent = parent
    return e


def set_pixel_world():
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    sc.view_settings.view_transform = "Standard"


def script_args():
    import sys
    a = sys.argv
    return a[a.index("--") + 1:] if "--" in a else []


def add_light_and_sky(collection):
    """A preview sun and sky colour so the file looks right when opened (not exported: -noimp)."""
    sun = bpy.data.objects.new("sun-noimp", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))
    collection.objects.link(sun)
    wd = bpy.data.worlds.new("sky")
    wd.use_nodes = True
    wd.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.75, 0.95, 1)
    bpy.context.scene.world = wd
