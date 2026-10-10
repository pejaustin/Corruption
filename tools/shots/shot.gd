extends Node

## Screenshot rig: loads the world as an offline host, then renders named
## camera views to PNGs. Views come from the SHOTS env var as
## "name:x,y,z:tx,ty,tz:fov:curve_horizon_m;..." (camera position : look-at target : fov : bend horizon, optional), and output goes
## to SHOT_DIR (default user://shots). Run windowed (not --headless):
##   SHOTS="tower:0,60,0:0,40,0" godot --path . res://tools/shots/shot.tscn

## WORLD_SIZE=400m|2km|6km shoots that size's game world (default 2 km); WORLD=res://scenes/world/open_world/open_world_2km.tscn
## shoots that scene instead; SHOT_FAR sets the camera far plane.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	NetworkManager.is_hosting_game = true
	var world_path := OS.get_environment("WORLD") if OS.get_environment("WORLD") != "" else MatchConfig.world_scene_named(OS.get_environment("WORLD_SIZE"))
	var world: Node = (load(world_path) as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	var settle := float(OS.get_environment("SHOT_SETTLE")) if OS.get_environment("SHOT_SETTLE") != "" else 3.0
	await get_tree().create_timer(settle).timeout
	# Optional: SHOT_GIVE_SITE=SiteChapel hands that site to peer 1 so its beacon shows;
	# SHOT_TIME=0.9 sets the time of day (0 = midnight, 0.5 = noon).
	var give: String = OS.get_environment("SHOT_GIVE_SITE")
	if give != "":
		var site: Node = world.get_node_or_null(give)
		if site != null and site.has_method("debug_give_to"):
			site.call("debug_give_to", 1)
	var time_env: String = OS.get_environment("SHOT_TIME")
	if time_env != "":
		var clock: Node = world.get_node_or_null("DayNight")
		if clock != null:
			clock.call("set_time", float(time_env))
	# The debug overlay covers a quarter of the picture; SHOT_OVERLAY=1 keeps it.
	var overlay := world.get_node_or_null("CanvasLayer/DebugOverlay") as CanvasItem
	if overlay != null and OS.get_environment("SHOT_OVERLAY") == "":
		overlay.visible = false
	var cam := Camera3D.new()
	cam.far = float(OS.get_environment("SHOT_FAR")) if OS.get_environment("SHOT_FAR") != "" else 2000.0
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
		if parts.size() > 3 and parts[3] != "":
			cam.fov = float(parts[3])
		# Optional 5th field: curve_horizon_m for this shot (the curved-world bend; 0 = off). Default: the project setting.
		if parts.size() > 4:
			RenderingServer.global_shader_parameter_set("curve_horizon_m", float(parts[4]))
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
