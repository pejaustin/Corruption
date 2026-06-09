@tool
extends Terrain3D

## Builds a Terrain3D heightmap world from an Azgaar Fantasy Map Generator "Full" JSON export.
##
## Usage:
##   1. Open scenes/build/azgaar_terrain_importer.tscn in the editor.
##   2. Select the root node, point json_path at the exported "Full" JSON, tweak sizes.
##   3. Tick "Run Build". The terrain appears in the viewport, region data is saved to
##      output_data_directory, and a game-ready scene is written to output_scene_path.
##   Re-running is idempotent — previous regions are cleared first.
##
## Azgaar height model: each grid cell has h in 0-100; h < 20 is water, and land
## elevation follows (h - 18) ^ heightExponent. We keep that curve but rescale it so
## h=20 sits at y=0 (sea level) and h=100 sits at max_land_height. Water cells ramp
## linearly down to -max_water_depth at h=0.
##
## This tool only builds HEIGHT data (plus the scene/data files on first run — an
## existing output scene is never overwritten). Texture painting is a separate pass:
## see scenes/build/terrain_painter.tscn. Re-running this build resets the regions'
## control maps, so repaint afterward.

const SEA_LEVEL_H: float = 20.0  # Azgaar h value at sea level
const HEIGHT_BASE: float = 18.0  # Azgaar: land elevation = (h - HEIGHT_BASE) ^ exponent
const MAX_H: float = 100.0       # Azgaar's nominal max cell height

## Azgaar "Full" JSON export (the .map file is not needed).
@export_global_file("*.json") var json_path: String = "res://assets/terrain/Cania Full 2026-06-06-11-24.json"
## World-space X size of the terrain in godot units. Z size is derived from the map's aspect ratio.
@export var world_width: float = 50000.0
## World-space height of an Azgaar h=100 peak. Sea level is y=0.
@export var max_land_height: float = 2500.0
## World-space depth of an Azgaar h=0 ocean floor, below y=0.
@export var max_water_depth: float = 300.0
## Region size for the import. Applied via change_region_size() at build time because
## Terrain3D's own region_size property is a silent no-op while data is uninitialized.
@export_enum("64:64", "128:128", "256:256", "512:512", "1024:1024", "2048:2048") var import_region_size: int = 512
## Also write the upscaled heightmap as an EXR next to the JSON (for inspection/reuse).
@export var save_heightmap_exr: bool = false

@export_group("Output")
## Directory where Terrain3D region .res files (and the material/assets .tres) are written.
@export var output_data_directory: String = "res://assets/world/terrain_cania"
## Game-ready scene (Node3D root + Terrain3D child) written here.
@export var output_scene_path: String = "res://scenes/world/cania_terrain.tscn"

@export_group("")
## Tick to run the whole build. Uses this node's vertex_spacing for world resolution.
@export var run_build: bool = false: set = _set_run_build


func _set_run_build(p_value: bool) -> void:
	if not p_value:
		return
	if data == null:
		push_error("Terrain3D data not initialized — run this from the opened importer scene in the editor.")
		return
	var map: Dictionary = _parse_map()
	if map.is_empty():
		return
	var heightmap: Image = _build_heightmap(map)
	if save_heightmap_exr:
		var exr_path: String = json_path.get_base_dir().path_join(
				"%s_heightmap.exr" % String(map.map_name).to_lower())
		heightmap.save_exr(exr_path, true)
		print("AzgaarTerrain: wrote ", exr_path)
	_import_heightmap(heightmap)
	_save_outputs(String(map.map_name))


## Reads the Azgaar JSON and returns {map_name, map_px, exponent, cells_x, cells_y, cells}.
## Returns an empty Dictionary on failure.
func _parse_map() -> Dictionary:
	if not FileAccess.file_exists(json_path):
		push_error("AzgaarTerrain: file not found: " + json_path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if parsed is not Dictionary:
		push_error("AzgaarTerrain: could not parse JSON: " + json_path)
		return {}
	var json: Dictionary = parsed
	var info: Dictionary = json.get("info", {})
	var grid: Dictionary = json.get("grid", {})
	var settings: Dictionary = json.get("settings", {})
	var cells: Array = grid.get("cells", [])
	var cells_x: int = int(grid.get("cellsX", 0))
	var cells_y: int = int(grid.get("cellsY", 0))
	if cells_x <= 0 or cells_y <= 0 or cells.size() != cells_x * cells_y:
		push_error("AzgaarTerrain: grid.cells (%d) is not a regular %dx%d grid" % [
				cells.size(), cells_x, cells_y])
		return {}
	return {
		map_name = String(info.get("mapName", "map")),
		map_px = Vector2(float(info.get("width", cells_x)), float(info.get("height", cells_y))),
		exponent = String(settings.get("heightExponent", "2")).to_float(),
		cells_x = cells_x,
		cells_y = cells_y,
		cells = cells,
	}


## Rasterizes grid cell heights (row-major regular grid) into a small FORMAT_RF image,
## then cubic-upscales to one pixel per terrain vertex.
func _build_heightmap(map: Dictionary) -> Image:
	var cells_x: int = map.cells_x
	var cells_y: int = map.cells_y
	var cells: Array = map.cells
	var exponent: float = map.exponent
	var land_range: float = pow(MAX_H - HEIGHT_BASE, exponent) - pow(SEA_LEVEL_H - HEIGHT_BASE, exponent)

	var img: Image = Image.create_empty(cells_x, cells_y, false, Image.FORMAT_RF)
	var i: int = 0
	for y: int in cells_y:
		for x: int in cells_x:
			var cell: Dictionary = cells[i]
			var h: float = float(cell.get("h", 0.0))
			var world_h: float
			if h >= SEA_LEVEL_H:
				world_h = (pow(h - HEIGHT_BASE, exponent) - pow(SEA_LEVEL_H - HEIGHT_BASE, exponent)) \
						/ land_range * max_land_height
			else:
				world_h = -(SEA_LEVEL_H - h) / SEA_LEVEL_H * max_water_depth
			img.set_pixel(x, y, Color(world_h, 0.0, 0.0))
			i += 1

	# One pixel per terrain vertex; Z size follows the source map's aspect ratio.
	var map_px: Vector2 = map.map_px
	var width_px: int = roundi(world_width / vertex_spacing)
	var depth_px: int = roundi(world_width * (map_px.y / map_px.x) / vertex_spacing)
	img.resize(width_px, depth_px, Image.INTERPOLATE_CUBIC)
	return img


## Clears existing regions and imports the heightmap roughly centered on the origin.
## The NW corner must land exactly on a region boundary (import slices are written
## from each region's origin), so we snap to region_size * vertex_spacing.
func _import_heightmap(heightmap: Image) -> void:
	for region: Terrain3DRegion in data.get_regions_active():
		data.remove_region(region, false)
	data.update_maps(Terrain3DRegion.TYPE_MAX, true, false)
	# Terrain3D's region_size property setter silently no-ops while data is null,
	# so the importer scene can't preset it — apply it here instead.
	change_region_size(import_region_size)

	var images: Array[Image] = []
	images.resize(Terrain3DRegion.TYPE_MAX)
	images[Terrain3DRegion.TYPE_HEIGHT] = heightmap

	var world_size: Vector2 = Vector2(heightmap.get_width(), heightmap.get_height()) * vertex_spacing
	var snap: float = float(region_size) * vertex_spacing
	var origin: Vector3 = Vector3(
			roundf(-world_size.x * 0.5 / snap) * snap,
			0.0,
			roundf(-world_size.y * 0.5 / snap) * snap)
	data.import_images(images, origin, 0.0, 1.0)
	data.calc_height_range(true)

	print("AzgaarTerrain: %d x %d px heightmap @ vertex_spacing %.1f" % [
			heightmap.get_width(), heightmap.get_height(), vertex_spacing])
	print("AzgaarTerrain: world rect x %.0f..%.0f, z %.0f..%.0f (sea level y=0)" % [
			origin.x, origin.x + world_size.x, origin.z, origin.z + world_size.y])
	print("AzgaarTerrain: %d regions of %d px" % [data.get_regions_active().size(), region_size])


## Saves region data to output_data_directory and, only if it doesn't exist yet,
## packs a bare game scene. An existing scene is never overwritten — your material,
## texture assets, and added nodes are preserved there.
func _save_outputs(map_name: String) -> void:
	var err: Error = DirAccess.make_dir_recursive_absolute(output_data_directory)
	if err != OK:
		push_error("AzgaarTerrain: could not create " + output_data_directory)
		return
	data.save_directory(output_data_directory)
	print("AzgaarTerrain: control maps were reset — repaint with scenes/build/terrain_painter.tscn.")

	if FileAccess.file_exists(output_scene_path):
		print("AzgaarTerrain: ", output_scene_path, " exists — left untouched (reload it if open).")
		EditorInterface.get_resource_filesystem().scan()
		return

	var root: Node3D = Node3D.new()
	root.name = map_name.to_pascal_case() + "Terrain"
	var terrain: Terrain3D = Terrain3D.new()
	terrain.name = "Terrain3D"
	root.add_child(terrain)
	terrain.owner = root
	# region_size is intentionally not set: it isn't serialized (editor-usage only)
	# and Terrain3D restores it from the region files on load.
	terrain.vertex_spacing = vertex_spacing
	terrain.data_directory = output_data_directory

	var packed: PackedScene = PackedScene.new()
	if packed.pack(root) == OK:
		err = ResourceSaver.save(packed, output_scene_path)
		if err != OK:
			push_error("AzgaarTerrain: failed to save scene: " + error_string(err))
		else:
			print("AzgaarTerrain: saved ", output_scene_path, " (data: ", output_data_directory, ")")
	root.free()
	EditorInterface.get_resource_filesystem().scan()
