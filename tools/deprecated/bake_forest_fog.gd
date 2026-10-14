extends SceneTree

## Bakes one fog mask per forest guide outline (art/world/export/areas_2km.json) for scenes/world/fog/world_fog.tscn:
## a PNG over the forest's bounds plus MARGIN_M, red = how much fog (1 inside the wood, fading out across its edge),
## green = the ground height there (ground_min + g * ground_range), so the fog shader can hug the ground.
## Prints each forest's FogVolume position and size and its ground_min / ground_range for the scene.
##   godot --headless --path . -s res://tools/bake_forest_fog.gd
## Re-run after the forest guides or the ground change.

const AREAS_JSON := "res://art/world/export/areas_2km.json"
const LANDSCAPE := "res://art/world/export/world_landscape_2km.tscn"
const OUT := "res://art/world/export/fog/%s_fog_mask.png"
## PLACEHOLDER: tuning — metres per mask pixel, how far fog spills past the wood's edge, the fade across the edge.
const PX_M := 6.0
const MARGIN_M := 40.0
const FADE_IN_M := 30.0

func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AREAS_JSON))
	var world: Node3D = (load(LANDSCAPE) as PackedScene).instantiate()
	root.add_child(world)
	for i in 3:
		await physics_frame
	var space := world.get_world_3d().direct_space_state
	for name: String in data["areas"]:
		var area: Dictionary = data["areas"][name]
		if area["kind"] != "forest":
			continue
		var outline := PackedVector2Array()
		for p in (area["outlines"] as Array)[0]:
			outline.append(Vector2(p[0], p[1]))
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p in outline:
			lo = lo.min(p)
			hi = hi.max(p)
		lo -= Vector2.ONE * MARGIN_M
		hi += Vector2.ONE * MARGIN_M
		var w := int(ceil((hi.x - lo.x) / PX_M))
		var h := int(ceil((hi.y - lo.y) / PX_M))
		var mask := PackedFloat32Array()
		var ground := PackedFloat32Array()
		var gmin := INF
		var gmax := -INF
		for y in h:
			for x in w:
				var p := lo + Vector2(x + 0.5, y + 0.5) * PX_M
				var d := _edge_distance(outline, p)
				if not Geometry2D.is_point_in_polygon(p, outline):
					d = -d
				mask.append(smoothstep(-MARGIN_M, FADE_IN_M, d))
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 600, p.y), Vector3(p.x, -200, p.y)))
				var g: float = hit.position.y if hit else 0.0
				ground.append(g)
				gmin = minf(gmin, g)
				gmax = maxf(gmax, g)
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		var span := maxf(gmax - gmin, 0.01)
		for i in mask.size():
			img.set_pixel(i % w, i / w, Color(mask[i], (ground[i] - gmin) / span, 0.0))
		var slug := name.to_snake_case().replace(" ", "_")
		img.save_png(OUT % slug)
		var c := (lo + hi) * 0.5
		print("[fog] %s: %s  position (%.1f, %.1f, %.1f)  size (%.1f, %.1f, %.1f)  ground_min %.2f  ground_range %.2f" % [
			name, OUT % slug, c.x, (gmin + gmax) * 0.5 + 10.0, c.y, hi.x - lo.x, span + 40.0, hi.y - lo.y, gmin, span])
	quit()

func _edge_distance(outline: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best
