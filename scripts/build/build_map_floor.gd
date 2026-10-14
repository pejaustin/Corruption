extends Node
## The map floor's "Copy map points and links" button, run headless: adds a marker and a link line to
## scenes/map/map_floor.tscn for every MapPoint and neighbour pair of the 2 km world that it lacks
## (MapFloor.copy_from_world) and saves the scene. Never touches the markers and lines already there unless OVERWRITE=1.
## Run it as the main scene, so the autoloads load and every script compiles (a bare `-s` SceneTree script has no
## autoloads; scripts that use them fail to compile and are packed as `script = null`):
##   godot --headless --path . res://scripts/build/build_map_floor.tscn      (OVERWRITE=1 also puts them back)
## Saved outside the editor, the file loses its `uid=` lines (the scene's and its resources'); put them back from git,
## or use the editor button instead.
## In the editor the same button is on the MapFloor root of map_floor.tscn.

const FLOOR_SCENE: String = "res://scenes/map/map_floor.tscn"

func _ready() -> void:
	var floor_map := (load(FLOOR_SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as MapFloor
	print(floor_map.copy_from_world(OS.get_environment("OVERWRITE") != ""))
	var packed := PackedScene.new()
	var err := packed.pack(floor_map)
	if err == OK:
		err = ResourceSaver.save(packed, FLOOR_SCENE)
	print("[map floor] saved ", FLOOR_SCENE, " err=", err)
	floor_map.free()
	get_tree().quit(0 if err == OK else 1)
