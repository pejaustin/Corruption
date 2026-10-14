extends GutTest

## The Universal Animation Library import (art/characters/ual/): clips are retargeted to Godot's humanoid
## profile (Godot drops the "_Loop" suffix and loops those clips), so any model imported with ual_bone_map.tres (or another humanoid bone map) can play them.

const LIBRARY: String = "res://art/characters/ual/export/ual_anims.glb"
const MANNEQUIN: String = "res://art/characters/ual/ual_mannequin_placeholder.tscn"

func test_tracks_target_the_humanoid_skeleton() -> void:
	var lib: AnimationLibrary = load(LIBRARY)
	var anim: Animation = lib.get_animation(&"Jog_Fwd")
	var paths: Array[String] = []
	for i in anim.get_track_count():
		paths.push_back(String(anim.track_get_path(i)))
	assert_has(paths, "%GeneralSkeleton:Hips")
	assert_has(paths, "%GeneralSkeleton:LeftUpperLeg")

func test_loops_loop_and_one_shots_dont() -> void:
	var lib: AnimationLibrary = load(LIBRARY)
	assert_eq(lib.get_animation(&"Walk").loop_mode, Animation.LOOP_LINEAR)
	assert_eq(lib.get_animation(&"Sword_Idle").loop_mode, Animation.LOOP_LINEAR)
	assert_eq(lib.get_animation(&"Roll").loop_mode, Animation.LOOP_NONE)

func test_mannequin_plays_the_library() -> void:
	var mannequin: Node = (load(MANNEQUIN) as PackedScene).instantiate()
	var player: AnimationPlayer = mannequin.get_node(^"AnimationPlayer")
	var skeleton: Skeleton3D = mannequin.get_node(^"%GeneralSkeleton")
	assert_true(player.has_animation(&"ual/Roll"))
	assert_true(skeleton.find_bone("Hips") >= 0, "bones renamed to the humanoid profile")
	mannequin.free()
