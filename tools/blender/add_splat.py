"""Add Austin's vertex-paint ground splat to `geo` (art/world/source/world_landscape.blend). Blender 4.5, background.
Usage: blender.exe -b <world_landscape.blend> --python tools/blender/add_splat.py -- <repo_root> [--reseed] [--out <file.blend>]
Adds a `Splat` colour attribute (BYTE_COLOR, CORNER, like `Col`) that chooses the ground texture, and rebuilds the
`ground_placeholder` material to blend the textures by it, times `Col` (tint / shading). Idempotent: an existing
`Splat` (maybe painted by Austin) is kept unless --reseed. Vertices, names, transforms and the object list are never
touched (checksummed; prints GEOMETRY_UNCHANGED). Saves the .blend (or --out).

PLACEHOLDER: the channel -> texture mapping (black grass, red rock, green dirt, blue sand) is a stand-in; Austin did
not pick the textures. SPLAT_CHANNELS below, `shaders/world_ground.gdshader` and README "Painting the ground" must agree.
A channel counts as painted at >= SPLAT_THRESHOLD (hard edge; nearest textures stay crisp, no blending). Priority if
several are painted: sand, then dirt, then rock. Grass is the remainder (no channel >= threshold).
Seed (looks as before): rock on faces the old slope rule called rock (1 - |normal.z| > 0.30), sand on corners below the
old shore height. The old sea (water texture) and snow bands have no channel: sea floor seeds as sand, snow as grass."""
import os, sys
import bpy, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import script_args
args = script_args()
root = args[0]
reseed = "--reseed" in args
dst = args[args.index("--out") + 1] if "--out" in args else os.path.join(root, "art/world/source/world_landscape.blend")
# PLACEHOLDER: channel -> texture (Austin has not chosen); None = remainder
SPLAT_CHANNELS = {"R": "rock", "G": "dirt", "B": "sand", None: "grass"}
SPLAT_THRESHOLD = 0.5
SHORE_F, SLOPE = 0.268, 0.30     # the old placeholder rule (texture_austin_map.py)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:
    bpy.context.view_layer.objects.active = o
    if o.mode != "OBJECT": bpy.ops.object.mode_set(mode="OBJECT")
def checksum():
    out = {}
    for o in meshes:
        a = np.empty(len(o.data.vertices)*3); o.data.vertices.foreach_get("co", a)
        out[o.name] = (round(float(a.sum()), 4), round(float(np.abs(a).sum()), 4), len(o.data.vertices), len(o.data.polygons), tuple(round(x, 4) for m in o.matrix_world for x in m))
    return out
before = checksum(); names_before = sorted(o.name for o in bpy.data.objects)

ob = bpy.data.objects["geo"]; me = ob.data
M = np.array(ob.matrix_world)
fresh = "Splat" not in me.color_attributes
if fresh or reseed:
    if not fresh: me.color_attributes.remove(me.color_attributes["Splat"])
    ca = me.color_attributes.new("Splat", "BYTE_COLOR", "CORNER")
    n = len(me.vertices); co = np.empty(n*3); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    wz = (co @ M[:3, :3].T + M[:3, 3])[:, 2]
    shore = wz.min() + SHORE_F * (wz.max() - wz.min())
    li = np.empty(len(me.loops), np.int32); me.loops.foreach_get("vertex_index", li)
    pn = np.empty(len(me.polygons)*3); me.polygons.foreach_get("normal", pn); pn = pn.reshape(-1, 3)
    pn = pn @ np.linalg.inv(M[:3, :3])                    # normals to world space (inverse transpose)
    pn /= np.linalg.norm(pn, axis=1)[:, None]
    steep = (1.0 - np.abs(pn[:, 2])) > SLOPE
    lt = np.empty(len(me.polygons), np.int32); me.polygons.foreach_get("loop_total", lt)
    lp = np.repeat(np.arange(len(lt)), lt)                 # loops of a polygon are contiguous
    rgba = np.zeros((len(li), 4), np.float32); rgba[:, 3] = 1.0
    sand = wz[li] < shore
    rgba[sand, 2] = 1.0                                   # blue = sand
    rgba[steep[lp], :3] = (1.0, 0.0, 0.0)                 # red = rock (the old rule drew rock over everything)
    ca.data.foreach_set("color", rgba.ravel())
    print("SEEDED corners rock=%d sand=%d of %d" % (steep[lp].sum(), (sand & ~steep[lp]).sum(), len(li)))
else:
    print("SPLAT kept (already there; use --reseed to overwrite)")
# Painting target = active layer (Splat); the viewport / render colour stays Col (tint)
me.color_attributes.active_color = me.color_attributes["Splat"]
me.color_attributes.render_color_index = me.color_attributes.find("Col")

def img(name):
    p = os.path.join(root, "art/world/textures", name + ".png")
    im = bpy.data.images.get("tex_" + name) or bpy.data.images.load(p, check_existing=True)
    im.name = "tex_" + name; im.filepath = p; return im
mat = bpy.data.materials.get("ground_placeholder") or bpy.data.materials.new("ground_placeholder")
mat.use_nodes = True
nt = mat.node_tree; nt.nodes.clear(); N = nt.nodes.new; L = nt.links.new
out = N("ShaderNodeOutputMaterial"); out.location = (1800, 0)
bsdf = N("ShaderNodeBsdfPrincipled"); bsdf.location = (1500, 0); bsdf.inputs["Roughness"].default_value = 1.0
if "Specular IOR Level" in bsdf.inputs: bsdf.inputs["Specular IOR Level"].default_value = 0.0
L(bsdf.outputs[0], out.inputs[0])
uvn = N("ShaderNodeUVMap"); uvn.uv_map = "WorldUV"; uvn.location = (-900, 300)
def tex(name, y):
    t = N("ShaderNodeTexImage"); t.location = (-600, y); t.label = name
    t.image = img(name); t.interpolation = "Closest"; t.extension = "REPEAT"
    L(uvn.outputs[0], t.inputs[0]); return t.outputs["Color"]
sp = N("ShaderNodeVertexColor"); sp.layer_name = "Splat"; sp.location = (-600, -500); sp.label = "Splat (paint this layer)"
sep = N("ShaderNodeSeparateColor"); sep.location = (-400, -500); L(sp.outputs["Color"], sep.inputs[0])
def gt(ch, y):
    m = N("ShaderNodeMath"); m.operation = "GREATER_THAN"; m.location = (-200, y)
    L(sep.outputs[{"R": "Red", "G": "Green", "B": "Blue"}[ch]], m.inputs[0]); m.inputs[1].default_value = SPLAT_THRESHOLD - 1e-4; return m.outputs[0]
def mix(a, b, fac, x):
    m = N("ShaderNodeMix"); m.data_type = "RGBA"; m.location = (x, 0)
    L(fac, m.inputs[0]); L(a, m.inputs[6]); L(b, m.inputs[7]); return m.outputs[2]
c = tex(SPLAT_CHANNELS[None], 600)
for i, (ch, y) in enumerate((("R", -450), ("G", -600), ("B", -750))):   # later = higher priority: sand > dirt > rock
    c = mix(c, tex(SPLAT_CHANNELS[ch], 300 - 300*i), gt(ch, y), 0 + 200*i)
vc = N("ShaderNodeVertexColor"); vc.layer_name = "Col"; vc.location = (600, -300)
tint = N("ShaderNodeMix"); tint.data_type = "RGBA"; tint.blend_type = "MULTIPLY"; tint.location = (1000, 0)
tint.inputs[0].default_value = 1.0; L(c, tint.inputs[6]); L(vc.outputs["Color"], tint.inputs[7])
L(tint.outputs[2], bsdf.inputs["Base Color"])
mat["PLACEHOLDER"] = "channel -> texture mapping is a stand-in (add_splat.py); Austin has not chosen the textures"
if len(me.materials): me.materials[0] = mat
else: me.materials.append(mat)
for im in bpy.data.images:
    if im.name.startswith("tex_"): im.filepath = bpy.path.relpath(im.filepath) if im.filepath and not im.filepath.startswith("//") else im.filepath
bpy.ops.wm.save_as_mainfile(filepath=dst, relative_remap=True, copy=False)
after = checksum()
print("GEOMETRY_UNCHANGED", before == after, "OBJECTS_UNCHANGED", names_before == sorted(o.name for o in bpy.data.objects))
for k in before: print("CHK", k, before[k][:4], after[k][:4])
