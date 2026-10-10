extends SceneTree
## Bakes the war-table map's illustration (hill shading and contour lines on parchment) from Austin's 2 km ground
## and saves it as a PNG, which map_floor.tscn uses as the floor's texture.
## Run: godot --headless --path . -s res://tools/bake_map_illustration.gd
## Writes scenes/map/map_illustration.png. Re-run after the ground changes, then re-import.

const OUT: String = "res://scenes/map/map_illustration.png"
const LANDSCAPE: String = "res://art/world/export/world_landscape_2km.glb"
## The part of the world the picture depicts (x, z); must match MapFloor.world_rect.
const WORLD_RECT: Rect2 = Rect2(-1000.0, -1000.0, 2000.0, 2000.0)
## PLACEHOLDER: art direction, not designed. Resolution, shading strength and contour spacing (metres of height).
const RES: int = 256
const SHADE_GAIN: float = 0.6
const CONTOUR_M: float = 20.0

func _init() -> void:
	var land: Node3D = (load(LANDSCAPE) as PackedScene).instantiate()
	root.add_child(land)
	await process_frame
	var geo := land.get_node("geo") as MeshInstance3D
	var tri: TriangleMesh = geo.mesh.generate_triangle_mesh()
	var to_local: Transform3D = geo.global_transform.affine_inverse()
	var heights := PackedFloat32Array()
	heights.resize(RES * RES)
	for y in RES:
		for x in RES:
			var wx := WORLD_RECT.position.x + (float(x) + 0.5) / RES * WORLD_RECT.size.x
			var wz := WORLD_RECT.position.y + (float(y) + 0.5) / RES * WORLD_RECT.size.y
			var from := to_local * Vector3(wx, 3000.0, wz)
			var to := to_local * Vector3(wx, -3000.0, wz)
			var hit := tri.intersect_ray(from, (to - from).normalized())
			heights[y * RES + x] = (geo.global_transform * hit["position"]).y if not hit.is_empty() else 0.0
	var img := Image.create(RES, RES, false, Image.FORMAT_RGB8)
	var parchment := Color(0.8, 0.72, 0.56)
	for y in RES:
		for x in RES:
			var h := heights[y * RES + x]
			var hx := heights[y * RES + mini(x + 1, RES - 1)] - h
			var hy := heights[mini(y + 1, RES - 1) * RES + x] - h
			var shade := clampf(0.5 - (hx + hy) * SHADE_GAIN, 0.0, 1.0)
			var c := parchment.darkened(0.35 * (1.0 - shade))
			if int(floor(h / CONTOUR_M)) != int(floor((h + maxf(absf(hx), absf(hy))) / CONTOUR_M)):
				c = c.darkened(0.25)
			img.set_pixel(x, y, c)
	var err := img.save_png(ProjectSettings.globalize_path(OUT))
	print("[illustration] saved ", OUT, " err=", err)
	quit(err)
