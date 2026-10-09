"""Add PLACEHOLDER textures to Austin's hand-made map (art/world/source/world_landscape.blend). Blender 4.5, background.
Usage: blender.exe -b <austin original.blend> --python tools/blender/texture_austin_map.py -- <repo_root>
Only ADDS: a material, a 'WorldUV' UV layer (world-space planar, one tile = TILE_M metres) and a 'Col' vertex colour.
Vertex positions, names, transforms and his 'UVMap' are never touched. PLACEHOLDER: look is not designed by Austin."""
import os, sys
import bpy, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import script_args
root = script_args()[0]
TILE_M = 8.0                      # PLACEHOLDER: one 32 px texture tile = 8 m (0.25 m per texel)
# PLACEHOLDER thresholds, as fractions of the map's height range so they follow
# Austin's vertical scale (sea / shore / snow line; slope = 1 - normal.z).
SEA_F, SHORE_F, SNOW_F, SLOPE = 0.206, 0.268, 0.79, 0.30
ob = bpy.data.objects["Plane"]; me = ob.data
# his file was saved in Edit Mode: leave it (writes the edit-mesh back; no geometry change)
bpy.context.view_layer.objects.active = ob
if ob.mode != "OBJECT": bpy.ops.object.mode_set(mode="OBJECT")
mw = np.array(ob.matrix_world)
_wz = [(ob.matrix_world @ v.co).z for v in me.vertices]
_zmin, _zmax = min(_wz), max(_wz)
SEA, SHORE, SNOW = (_zmin + f * (_zmax - _zmin) for f in (SEA_F, SHORE_F, SNOW_F))
print("THRESHOLDS", SEA, SHORE, SNOW)
_a = np.empty(len(me.vertices)*3); me.vertices.foreach_get("co", _a); print("CHK_BEFORE", _a.reshape(-1,3).sum(), np.abs(_a).sum(), len(me.vertices), len(me.polygons))
# 1. world-space planar UVs (new layer, existing UVMap kept)
n = len(me.vertices)
co = np.empty(n*3); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
wco = co @ mw[:3, :3].T + mw[:3, 3]
import bmesh
bm = bmesh.new(); bm.from_mesh(me)
if "WorldUV" not in bm.loops.layers.uv: bm.loops.layers.uv.new("WorldUV")
lay = bm.loops.layers.uv["WorldUV"]
for f in bm.faces:
    for l in f.loops:
        v = mw @ l.vert.co if False else None
        w = ob.matrix_world @ l.vert.co
        l[lay].uv = (w.x / TILE_M, w.y / TILE_M)
bm.to_mesh(me); bm.free()
li = np.empty(len(me.loops), np.int32); me.loops.foreach_get("vertex_index", li)
# 2. vertex colour tint: white, slightly darker in the lows
if "Col" not in me.color_attributes:
    ca = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    shade = np.clip(0.88 + (wco[li][:, 2] - SEA) / 140.0, 0.8, 1.0)
    rgba = np.stack([shade]*3 + [np.ones_like(shade)], 1).astype(np.float32)
    ca.data.foreach_set("color", rgba.ravel())
# 3. material
mat = bpy.data.materials.new("ground_placeholder"); mat.use_nodes = True
nt = mat.node_tree; nt.nodes.clear(); N = nt.nodes.new; L = nt.links.new
out = N("ShaderNodeOutputMaterial"); out.location = (1800, 0)
bsdf = N("ShaderNodeBsdfPrincipled"); bsdf.location = (1500, 0)
bsdf.inputs["Roughness"].default_value = 1.0
for k in ("Specular IOR Level",):
    if k in bsdf.inputs: bsdf.inputs[k].default_value = 0.0
L(bsdf.outputs[0], out.inputs[0])
uvn = N("ShaderNodeUVMap"); uvn.uv_map = "WorldUV"; uvn.location = (-900, 300)
def tex(name, y):
    t = N("ShaderNodeTexImage"); t.location = (-600, y)
    img = bpy.data.images.load(os.path.join(root, "art/world/textures", name + ".png"), check_existing=True)
    img.name = "tex_" + name; img.filepath = bpy.path.relpath(img.filepath) if False else img.filepath
    t.image = img; t.interpolation = "Closest"; t.extension = "REPEAT"
    L(uvn.outputs[0], t.inputs[0]); return t
grass, rock, sand, snow, water = [tex(x, y) for x, y in
    (("grass", 600), ("rock", 300), ("sand", 0), ("snow", -300), ("water", -600))]
geo = N("ShaderNodeNewGeometry"); geo.location = (-900, -900)
sep = N("ShaderNodeSeparateXYZ"); sep.location = (-700, -900)
L(geo.outputs["Normal"], sep.inputs[0]); L(geo.outputs["Position"], sep.inputs[0]) if False else None
sepp = N("ShaderNodeSeparateXYZ"); sepp.location = (-700, -1100); L(geo.outputs["Position"], sepp.inputs[0])
def math(op, a, b, x, y):
    m = N("ShaderNodeMath"); m.operation = op; m.location = (x, y)
    for i, v in enumerate((a, b)):
        if isinstance(v, (int, float)): m.inputs[i].default_value = v
        else: L(v, m.inputs[i])
    return m.outputs[0]
z = sepp.outputs["Z"]
slope = math("SUBTRACT", 1.0, math("ABSOLUTE", sep.outputs["Z"], 0, -500, -900), -300, -900)
def mix(a, b, fac, x, y):
    m = N("ShaderNodeMix"); m.data_type = "RGBA"; m.location = (x, y)
    L(fac, m.inputs[0]); L(a, m.inputs[6]); L(b, m.inputs[7]); return m.outputs[2]
c = grass.outputs["Color"]
c = mix(c, sand.outputs["Color"], math("LESS_THAN", z, SHORE, -300, -1100), 0, 0)
c = mix(c, water.outputs["Color"], math("LESS_THAN", z, SEA, -300, -1250), 200, 0)
c = mix(c, snow.outputs["Color"], math("GREATER_THAN", z, SNOW, -300, -1400), 400, 0)
c = mix(c, rock.outputs["Color"], math("GREATER_THAN", slope, SLOPE, -300, -1550), 600, 0)
vc = N("ShaderNodeVertexColor"); vc.layer_name = "Col"; vc.location = (600, -300)
tint = N("ShaderNodeMix"); tint.data_type = "RGBA"; tint.blend_type = "MULTIPLY"; tint.location = (1000, 0)
tint.inputs[0].default_value = 1.0; L(c, tint.inputs[6]); L(vc.outputs["Color"], tint.inputs[7])
L(tint.outputs[2], bsdf.inputs["Base Color"])
me.materials.clear() if len(me.materials) == 0 else None
if len(me.materials): me.materials[0] = mat
else: me.materials.append(mat)
bpy.data.materials.remove(bpy.data.materials["Material"]) if "Material" in bpy.data.materials and bpy.data.materials["Material"].users == 0 else None
# placeholder marker
ob["PLACEHOLDER"] = "textures are stand-ins (tools/blender/texture_austin_map.py); geometry is Austin's"
# make image paths relative to the saved file
dst = os.path.join(root, "art/world/source/world_landscape.blend")
bpy.ops.wm.save_as_mainfile(filepath=dst, relative_remap=True, copy=False)
a = np.empty(n*3); me.vertices.foreach_get("co", a)
print("CHK", a.reshape(-1,3).sum(), np.abs(a).sum())
