# Blender, one-off conversion of a static prop FBX into a glb (2026-10-14, assets/world/props/placeholder/bones_flesh/).
# blender -b --factory-startup -P convert_prop.py -- SRC OUT.glb TEXDIR [FALLBACK_PNG]
import bpy, sys, os, re
src,out,texdir=sys.argv[sys.argv.index('--')+1:][:3]
bpy.ops.wm.read_factory_settings(use_empty=True); bpy.ops.import_scene.fbx(filepath=src)
pngs={f.lower():os.path.join(texdir,f) for f in os.listdir(texdir) if f.lower().endswith('.png')}
for img in bpy.data.images:
    if os.path.exists(bpy.path.abspath(img.filepath)): print("IMG ok", img.name); continue
    base=re.sub(r'\.\d{3}$','',os.path.basename(img.filepath.replace('\\','/'))).lower()
    hit=pngs.get(base); print("IMG", base, '->', hit and os.path.basename(hit))
    hit = hit or (len(sys.argv) > sys.argv.index("--")+4 and os.path.join(texdir, sys.argv[-1]))
    if hit: img.filepath=hit; img.reload()
for o in bpy.context.scene.objects: print("OBJ",o.type,o.name,[m.name for m in getattr(o.data,'materials',[]) or []])
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animations=False, export_cameras=False, export_lights=False)
