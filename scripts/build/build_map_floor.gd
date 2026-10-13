extends SceneTree
## The map floor's "Copy map points and roads" button, run headless: adds a marker and a road line to
## scenes/map/map_floor.tscn for every MapPoint and Road of the 2 km world that it lacks (MapFloor.copy_from_world)
## and saves the scene. Never touches the markers and lines already there unless OVERWRITE=1.
## Run: godot --headless --path . -s res://scripts/build/build_map_floor.gd      (OVERWRITE=1 also puts them back)
## In the editor the same button is on the MapFloor root of map_floor.tscn.

const FLOOR_SCENE: String = "res://scenes/map/map_floor.tscn"

func _init() -> void:
	_build.call_deferred()

func _build() -> void:
	await process_frame   # the autoloads, for the world's scripts to compile
	# (MapFloor is not named here: this script compiles before the autoloads its class needs exist.)
	var floor_map: Node = (load(FLOOR_SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	print(floor_map.call(&"copy_from_world", OS.get_environment("OVERWRITE") != ""))
	var packed := PackedScene.new()
	var err := packed.pack(floor_map)
	if err == OK:
		err = ResourceSaver.save(packed, FLOOR_SCENE)
	print("[map floor] saved ", FLOOR_SCENE, " err=", err)
	floor_map.free()
	quit(0 if err == OK else 1)
