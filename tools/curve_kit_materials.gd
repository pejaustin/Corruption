extends SceneTree

## Makes the castle kit (assets/world/env/mod-castle/**/*.fbx) curved-world aware (shaders/curved_world.gdshaderinc).
## Each .fbx embeds a StandardMaterial3D; this writes an equivalent ShaderMaterial .tres per embedded material into
## assets/world/env/mod-castle/curved_materials/ (shaders/curved_kit*.gdshader: opaque / alpha scissor / alpha depth
## prepass, chosen from the original's transparency) and points the .fbx's .import at it (materials > use_external), the
## same thing the editor's Import dock does. Then run the import so the .fbx files pick it up:
##   godot --headless --path . -s res://tools/curve_kit_materials.gd
##   godot --headless --path . --import      (see art/world/README.md for the Blender workaround; revert project.godot)
## Re-running skips materials already converted. To redo one, delete its .tres and its use_external entry in the .import.

const KIT: String = "res://assets/world/env/mod-castle"
const OUT: String = KIT + "/curved_materials"
const SHADERS: Dictionary = {
	BaseMaterial3D.TRANSPARENCY_DISABLED: "res://shaders/curved_kit.gdshader",
	BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR: "res://shaders/curved_kit_scissor.gdshader",
	BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS: "res://shaders/curved_kit_prepass.gdshader",
}

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var files: Array[String] = []
	_collect(KIT, files)
	var made := 0
	var skipped := 0
	for fbx in files:
		var scene := load(fbx) as PackedScene
		if scene == null:
			push_warning("cannot load " + fbx)
			continue
		var root := scene.instantiate()
		var entries: Dictionary = {}
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s) as BaseMaterial3D
				if mat == null:
					skipped += 1
					continue
				var mname: String = mat.resource_name
				var path := OUT.path_join((fbx.get_file().get_basename() + "." + mname).validate_filename() + ".tres")
				if not SHADERS.has(mat.transparency):
					push_warning("unhandled transparency %d in %s" % [mat.transparency, fbx])
					continue
				var sm := ShaderMaterial.new()
				sm.resource_name = mname
				sm.shader = load(SHADERS[mat.transparency])
				sm.set_shader_parameter("albedo_tex", mat.albedo_texture)
				sm.set_shader_parameter("albedo_color", mat.albedo_color)
				if mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
					sm.set_shader_parameter("alpha_scissor", mat.alpha_scissor_threshold)
				ResourceSaver.save(sm, path)
				# A mesh saved to its own .res (import "save to file") carries the old material inside the file and the
				# import's external-material mapping never touches it, so swap it there too.
				if mesh.resource_path.get_extension() in ["res", "tres"]:
					mesh.surface_set_material(s, sm)
					ResourceSaver.save(mesh, mesh.resource_path)
				entries[mname] = {"use_external/enabled": true, "use_external/path": path}
				made += 1
		root.free()
		if not entries.is_empty():
			_patch_import(fbx + ".import", entries)
	print("[curve_kit] wrote %d materials, skipped %d non-standard surfaces" % [made, skipped])
	quit()

func _patch_import(path: String, entries: Dictionary) -> void:
	var cf := ConfigFile.new()
	cf.load(path)
	var subs: Dictionary = cf.get_value("params", "_subresources", {})
	var mats: Dictionary = subs.get("materials", {})
	mats.merge(entries, true)
	subs["materials"] = mats
	cf.set_value("params", "_subresources", subs)
	cf.save(path)

func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".fbx"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)
