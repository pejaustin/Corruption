extends Node

## Screenshot rig: loads the world as an offline host, then renders named
## camera views to PNGs. Views come from the SHOTS env var as
## "name:x,y,z:tx,ty,tz;..." (camera position : look-at target), and output goes
## to SHOT_DIR (default user://shots). Run windowed (not --headless):
##   SHOTS="tower:0,60,0:0,40,0" godot --path . res://tools/shots/shot.tscn

const WORLD: String = "res://scenes/world/world.tscn"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	NetworkManager.is_hosting_game = true
	var world: Node = (load(WORLD) as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	var settle := float(OS.get_environment("SHOT_SETTLE")) if OS.get_environment("SHOT_SETTLE") != "" else 3.0
	await get_tree().create_timer(settle).timeout
	var cam := Camera3D.new()
	cam.far = 2000.0
	get_tree().root.add_child(cam)
	cam.make_current()
	var out_dir := OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	for spec in OS.get_environment("SHOTS").split(";", false):
		var parts := spec.split(":")
		if parts.size() < 3:
			continue
		var p := _vec(parts[1])
		var t := _vec(parts[2])
		cam.global_position = p
		cam.look_at(t, Vector3.UP if absf((t - p).normalized().y) < 0.99 else Vector3.FORWARD)
		if parts.size() > 3:
			cam.fov = float(parts[3])
		for i in 8:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := out_dir.path_join(parts[0] + ".png")
		img.save_png(path)
		print("[shot] saved ", ProjectSettings.globalize_path(path))
	get_tree().quit()

func _vec(s: String) -> Vector3:
	var c := s.split(",")
	return Vector3(float(c[0]), float(c[1]), float(c[2]))
