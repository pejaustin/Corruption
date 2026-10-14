@tool
extends EditorScenePostImport
## Import script for the POI and prop glbs (art/world/pois/export/*.glb, art/world/export/props/*.glb, set in their .import).
## The glTF materials are only names (Blender's node trees do not survive the export): each `mat_<texture>` is replaced by
## art/world/materials/poi/mat_<texture>.tres (curved-world shader, the blockout's 32 px texture times its vertex colour).
## A name with no .tres stays as imported (it will not bend with the ground: add the .tres).
## PLACEHOLDER: the look is a stand-in, not designed by Austin.

const MATERIALS: String = "res://art/world/materials/poi/%s.tres"

func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i)
			var path := MATERIALS % (material.resource_name if material != null else "")
			if material != null and ResourceLoader.exists(path):
				mesh.surface_set_material(i, load(path) as Material)
	return scene
