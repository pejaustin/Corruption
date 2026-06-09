@tool
extends Terrain3D

## Rule-based texture painter for an existing Terrain3D data directory.
##
## Two independent passes, each with its own run checkbox:
##   - Run Paint: control maps — grass below snow_height, snow above it, rock
##     wherever the slope exceeds rock_slope_deg, with smoothstep blend bands.
##   - Run Relief Bake: cartographic hillshade + elevation tint baked into the
##     COLOR maps (multiplies albedo in the shader). Unlike realtime lighting,
##     baked shading reads at any camera distance, in editor and in game —
##     this is what makes large-scale peaks and valleys legible. Run Relief
##     Clear resets the color maps to neutral.
##
## Both passes work over the CURRENT height data, in place. Heights, scenes,
## materials, and texture asset lists are never touched, so re-running after
## hand-sculpting or parameter tweaks is safe.
##
## Usage:
##   1. Open scenes/build/terrain_painter.tscn. data_directory is preset to the
##      Cania data; repoint it (and vertex_spacing, which slope math depends on)
##      to paint a different terrain.
##   2. Tweak thresholds and the texture slot ids to match your texture list.
##   3. Tick "Run Paint". Regions are reloaded fresh from disk, repainted, and
##      saved back.
##   4. If the gameplay scene using this data is open in another tab, reload it
##      (Scene > Reload Saved Scene) — and don't re-save it while stale, or its
##      in-memory copy will overwrite the painted files.
##
## The painted data has the autoshader bit off, so it can be touched up afterward
## with the editor's paint brushes.

## Slope in degrees at and above which ground is fully rock, regardless of height.
@export_range(1.0, 89.0) var rock_slope_deg: float = 32.0
## Rock fades in over this many degrees below rock_slope_deg.
@export_range(0.1, 45.0) var rock_blend_deg: float = 8.0
## World height (y) at and above which flat ground is fully snow.
@export var snow_height: float = 1500.0
## Snow fades in over this many world units below snow_height.
@export_range(1.0, 5000.0) var snow_blend: float = 400.0

@export_group("Texture Slots")
## Id in the terrain's texture asset list painted as grass (flat, low).
@export_range(0, 31) var grass_texture_id: int = 0
## Id painted as rock (steep).
@export_range(0, 31) var rock_texture_id: int = 1
## Id painted as snow (flat, high).
@export_range(0, 31) var snow_texture_id: int = 2

@export_group("")
## Tick to repaint all regions in data_directory and save them to disk.
@export var run_paint: bool = false: set = _set_run_paint

@export_group("Relief Shading")
## How dark away-from-light slopes get. 0 = off, 1 = black. Flat ground stays untinted.
@export_range(0.0, 1.0) var hillshade_strength: float = 0.45
## Bake-light compass direction (cartographic convention: 315 = from the northwest).
@export_range(0.0, 360.0) var shade_azimuth_deg: float = 315.0
## Bake-light height above the horizon. Lower = longer, more dramatic shading.
@export_range(5.0, 85.0) var shade_altitude_deg: float = 45.0
## Extra elevation cue: sea level is darkened by this much, fading to none at the peaks.
@export_range(0.0, 1.0) var hypsometric_strength: float = 0.2
## Tick to bake hillshade + elevation tint into every region's color map and save.
@export var run_relief_bake: bool = false: set = _set_run_relief_bake
## Tick to reset every region's color map to neutral (removes the bake) and save.
@export var run_relief_clear: bool = false: set = _set_run_relief_clear


func _set_run_paint(p_value: bool) -> void:
	if not p_value:
		return
	var regions: Array = _load_regions()
	if regions.is_empty():
		return
	var heights: Image = _build_height_mosaic(regions)
	var control: Image = _build_control_map(heights)
	_write_map_slices(regions, control, Terrain3DRegion.TYPE_CONTROL)
	print("TerrainPainter: painted and saved %d regions to %s" % [regions.size(), data_directory])
	print("TerrainPainter: reload any open scene that uses this data before re-saving it.")


func _set_run_relief_bake(p_value: bool) -> void:
	if not p_value:
		return
	var regions: Array = _load_regions()
	if regions.is_empty():
		return
	var heights: Image = _build_height_mosaic(regions)
	var relief: Image = _build_relief_map(heights)
	_write_map_slices(regions, relief, Terrain3DRegion.TYPE_COLOR)
	print("TerrainPainter: baked relief shading into %d regions (%s)" % [regions.size(), data_directory])
	print("TerrainPainter: reload any open scene that uses this data before re-saving it.")


func _set_run_relief_clear(p_value: bool) -> void:
	if not p_value:
		return
	var regions: Array = _load_regions()
	if regions.is_empty():
		return
	var rs: int = region_size
	for region: Terrain3DRegion in regions:
		var neutral: Image = Image.create_empty(rs, rs, false, Image.FORMAT_RGBA8)
		neutral.fill(Color(1.0, 1.0, 1.0, 0.5))
		region.set_map(Terrain3DRegion.TYPE_COLOR, neutral)
		region.set_modified(true)
	data.update_maps(Terrain3DRegion.TYPE_COLOR, true, true)
	data.save_directory(data_directory)
	print("TerrainPainter: cleared color maps to neutral in %d regions" % regions.size())


## Guards + reloads regions fresh from disk so we never paint (or later save)
## stale in-memory data, e.g. after the Azgaar importer rebuilt the heightmaps.
## Returns an empty Array on failure.
func _load_regions() -> Array:
	if data == null:
		push_error("TerrainPainter: data not initialized — run this from the opened painter scene.")
		return []
	if data_directory.is_empty():
		push_error("TerrainPainter: set data_directory to a Terrain3D data folder first.")
		return []
	data.load_directory(data_directory)
	var regions: Array = data.get_regions_active()
	if regions.is_empty():
		push_error("TerrainPainter: no regions found in " + data_directory)
	return regions


## Slices a full-mosaic image back into per-region maps, marks them modified,
## refreshes the GPU arrays, and saves. Color maps get mipmaps (the shader
## samples them with textureLod); control maps must not be filtered.
func _write_map_slices(regions: Array, full_image: Image, map_type: int) -> void:
	var rs: int = region_size
	var min_loc: Vector2i = _min_region_location(regions)
	for region: Terrain3DRegion in regions:
		var offset: Vector2i = (region.get_location() - min_loc) * rs
		region.set_map(map_type, full_image.get_region(Rect2i(offset, Vector2i(rs, rs))))
		region.set_modified(true)
	data.update_maps(map_type, true, map_type == Terrain3DRegion.TYPE_COLOR)
	data.save_directory(data_directory)


## Stitches all region height maps into one image so slope is seam-free at borders.
func _build_height_mosaic(regions: Array) -> Image:
	var rs: int = region_size
	var min_loc: Vector2i = _min_region_location(regions)
	var max_loc: Vector2i = min_loc
	for region: Terrain3DRegion in regions:
		max_loc = max_loc.max(region.get_location())
	var size_px: Vector2i = (max_loc - min_loc + Vector2i.ONE) * rs
	var mosaic: Image = Image.create_empty(size_px.x, size_px.y, false, Image.FORMAT_RF)
	for region: Terrain3DRegion in regions:
		var height_map: Image = region.get_height_map()
		if height_map.get_format() != Image.FORMAT_RF:
			height_map = height_map.duplicate()
			height_map.convert(Image.FORMAT_RF)
		mosaic.blit_rect(height_map, Rect2i(0, 0, rs, rs), (region.get_location() - min_loc) * rs)
	return mosaic


func _min_region_location(regions: Array) -> Vector2i:
	var min_loc: Vector2i = regions[0].get_location()
	for region: Terrain3DRegion in regions:
		min_loc = min_loc.min(region.get_location())
	return min_loc


## Bakes a cartographic hillshade (+ elevation tint) into an RGBA8 color-map
## image. RGB multiplies terrain albedo in the shader: flat ground stays at 1.0
## (untinted), away-from-light slopes darken toward hillshade_strength, and
## lowlands darken toward hypsometric_strength. Alpha 0.5 = neutral roughness.
func _build_relief_map(heightmap: Image) -> Image:
	var start_ms: int = Time.get_ticks_msec()
	var w: int = heightmap.get_width()
	var h: int = heightmap.get_height()
	var heights: PackedFloat32Array = heightmap.get_data().to_float32_array()
	var rgba: PackedByteArray = PackedByteArray()
	rgba.resize(w * h * 4)

	var az: float = deg_to_rad(shade_azimuth_deg)
	var alt: float = deg_to_rad(shade_altitude_deg)
	# Direction TOWARD the light. Azimuth is compass-style: 0 = north (-Z), 90 = east (+X).
	var light: Vector3 = Vector3(sin(az) * cos(alt), sin(alt), -cos(az) * cos(alt))
	var flat_dot: float = sin(alt)  # n·L on flat ground; normalizes so flat = 1.0
	var max_height: float = maxf(data.get_height_range().y, 1.0)
	var inv_step: float = 1.0 / (2.0 * vertex_spacing)

	for y: int in h:
		var row: int = y * w
		var row_n: int = maxi(y - 1, 0) * w
		var row_s: int = mini(y + 1, h - 1) * w
		for x: int in w:
			var i: int = row + x
			var dzdx: float = (heights[row + mini(x + 1, w - 1)] - heights[row + maxi(x - 1, 0)]) * inv_step
			var dzdy: float = (heights[row_s + x] - heights[row_n + x]) * inv_step
			var normal: Vector3 = Vector3(-dzdx, 1.0, -dzdy).normalized()
			var lit: float = clampf(normal.dot(light) / flat_dot, 0.0, 1.0)
			var shade: float = lerpf(1.0, lit, hillshade_strength)
			var hypso: float = lerpf(1.0 - hypsometric_strength, 1.0,
					clampf(heights[i] / max_height, 0.0, 1.0))
			var value: int = clampi(roundi(shade * hypso * 255.0), 0, 255)
			var o: int = i * 4
			rgba[o] = value
			rgba[o + 1] = value
			rgba[o + 2] = value
			rgba[o + 3] = 128  # 0.5 = neutral roughness modifier
		if y % 256 == 0:
			print("TerrainPainter: shading row %d/%d" % [y, h])

	print("TerrainPainter: relief baked in %.1f s" % ((Time.get_ticks_msec() - start_ms) / 1000.0))
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)


## Computes a Terrain3D control map from a heightmap: per vertex, weights for
## grass/snow (by height) and rock (by slope) are blended, the top two textures
## become base/overlay with an 8-bit blend. Control format (Terrain3D 1.0):
## base id << 27 | overlay id << 22 | blend << 14, autoshader bit (0) left off.
## The uint32 bits are stored raw in a FORMAT_RF image (reinterpreted, not converted).
func _build_control_map(heightmap: Image) -> Image:
	var start_ms: int = Time.get_ticks_msec()
	var w: int = heightmap.get_width()
	var h: int = heightmap.get_height()
	var heights: PackedFloat32Array = heightmap.get_data().to_float32_array()
	var bits: PackedInt32Array = PackedInt32Array()
	bits.resize(w * h)

	var rock_full_rad: float = deg_to_rad(rock_slope_deg)
	var rock_start_rad: float = deg_to_rad(rock_slope_deg - rock_blend_deg)
	var snow_start: float = snow_height - snow_blend
	var inv_step: float = 1.0 / (2.0 * vertex_spacing)
	var counts: Vector3i = Vector3i.ZERO  # x = grass, y = rock, z = snow vertices

	for y: int in h:
		var row: int = y * w
		var row_n: int = maxi(y - 1, 0) * w
		var row_s: int = mini(y + 1, h - 1) * w
		for x: int in w:
			var i: int = row + x
			var x_w: int = maxi(x - 1, 0)
			var x_e: int = mini(x + 1, w - 1)
			var dzdx: float = (heights[row + x_e] - heights[row + x_w]) * inv_step
			var dzdy: float = (heights[row_s + x] - heights[row_n + x]) * inv_step
			var slope: float = atan(sqrt(dzdx * dzdx + dzdy * dzdy))

			var rock_t: float = smoothstep(rock_start_rad, rock_full_rad, slope)
			var snow_t: float = smoothstep(snow_start, snow_height, heights[i])
			var w_rock: float = rock_t
			var w_snow: float = (1.0 - rock_t) * snow_t
			var w_grass: float = (1.0 - rock_t) * (1.0 - snow_t)

			# Dominant texture becomes base, runner-up becomes overlay.
			var base_id: int
			var over_id: int
			var over_w: float
			if w_rock >= w_snow and w_rock >= w_grass:
				base_id = rock_texture_id
				counts.y += 1
				if w_snow >= w_grass:
					over_id = snow_texture_id
					over_w = w_snow
				else:
					over_id = grass_texture_id
					over_w = w_grass
			elif w_snow >= w_grass:
				base_id = snow_texture_id
				counts.z += 1
				over_id = rock_texture_id if w_rock >= w_grass else grass_texture_id
				over_w = maxf(w_rock, w_grass)
			else:
				base_id = grass_texture_id
				counts.x += 1
				over_id = rock_texture_id if w_rock >= w_snow else snow_texture_id
				over_w = maxf(w_rock, w_snow)
			var base_w: float = maxf(w_rock, maxf(w_snow, w_grass))
			var blend: int = clampi(roundi(over_w / (base_w + over_w) * 255.0), 0, 255)
			bits[i] = (base_id << 27) | (over_id << 22) | (blend << 14)
		if y % 256 == 0:
			print("TerrainPainter: painting row %d/%d" % [y, h])

	var total: float = float(w * h) / 100.0
	print("TerrainPainter: painted in %.1f s — grass %.1f%%, rock %.1f%%, snow %.1f%%" % [
			(Time.get_ticks_msec() - start_ms) / 1000.0,
			counts.x / total, counts.y / total, counts.z / total])
	return Image.create_from_data(w, h, false, Image.FORMAT_RF, bits.to_byte_array())
