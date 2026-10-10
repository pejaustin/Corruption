extends SceneTree
## Bakes the war-table map's illustration (hill shading and contour lines on parchment) from Austin's ground
## and saves it as a PNG, which map_floor.tscn uses as the floor's texture.
## Run: SIZE=2km godot --headless --path . -s res://tools/bake_map_illustration.gd   (SIZE = 400m | 2km | 6km, default 2km)
## Writes scenes/map/map_illustration.png (2 km) or scenes/map/map_illustration_<size>.png. Re-run after the ground
## changes, then re-import (tools/sync_world_sizes.sh does both).

const Ground = preload("res://scripts/build/world_ground.gd")
## The part of the 2 km world the picture depicts (x, z); other sizes scale it by their width. It must match MapFloor.world_rect
## (scripts/build/build_world_sizes.gd sets that for the derived sizes).
const WORLD_RECT_2KM: Rect2 = Rect2(-1000.0, -1000.0, 2000.0, 2000.0)
## PLACEHOLDER: art direction, not designed. Resolution, shading strength and contour spacing (metres of height, at 2 km;
## other sizes keep the contours on the same terrain features by scaling the spacing with their height factor).
const RES: int = 256
const SHADE_GAIN: float = 0.6
const CONTOUR_M: float = 20.0

func _init() -> void:
	var size: String = OS.get_environment("SIZE") if OS.get_environment("SIZE") != "" else "2km"
	var out := "res://scenes/map/map_illustration.png" if size == "2km" else "res://scenes/map/map_illustration_%s.png" % size
	var ground := Ground.new()
	ground.load_size(size)
	var ref_ground := Ground.new()
	ref_ground.load_size("2km")
	var factors := ground.factors_against(ref_ground)
	var rect := Rect2(WORLD_RECT_2KM.position * factors.x, WORLD_RECT_2KM.size * factors.x)
	var contour_m := CONTOUR_M * factors.y
	# A pixel covers `wide` times more ground than at 2 km: dividing the height step by it gives the same shading for the
	# same-looking slope (a taller map still looks steeper).
	var step_norm := 1.0 / factors.x
	var heights := PackedFloat32Array()
	heights.resize(RES * RES)
	for y in RES:
		for x in RES:
			var wx := rect.position.x + (float(x) + 0.5) / RES * rect.size.x
			var wz := rect.position.y + (float(y) + 0.5) / RES * rect.size.y
			var h := ground.y_at(wx, wz)
			heights[y * RES + x] = 0.0 if is_nan(h) else h
	var img := Image.create(RES, RES, false, Image.FORMAT_RGB8)
	var parchment := Color(0.8, 0.72, 0.56)
	for y in RES:
		for x in RES:
			var h := heights[y * RES + x]
			var hx := heights[y * RES + mini(x + 1, RES - 1)] - h
			var hy := heights[mini(y + 1, RES - 1) * RES + x] - h
			var shade := clampf(0.5 - (hx + hy) * step_norm * SHADE_GAIN, 0.0, 1.0)
			var c := parchment.darkened(0.35 * (1.0 - shade))
			if int(floor(h / contour_m)) != int(floor((h + maxf(absf(hx), absf(hy))) / contour_m)):
				c = c.darkened(0.25)
			img.set_pixel(x, y, c)
	var err := img.save_png(ProjectSettings.globalize_path(out))
	print("[illustration] saved ", out, " err=", err)
	quit(err)
