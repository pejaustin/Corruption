extends GutTest

## Mirror poses and audio as bytes (GDD §10): MirrorCodec and MirrorMessage, no scene tree.

const MODEL: PackedScene = preload("res://scenes/player/player_model.tscn")
const ANGLE_TOLERANCE: float = 0.01

static func bone_error(a: Skeleton3D, b: Skeleton3D) -> float:
	var worst: float = 0.0
	for i in a.get_bone_count():
		worst = maxf(worst, a.get_bone_pose_rotation(i).angle_to(b.get_bone_pose_rotation(i)))
	return worst

static func scramble(skel: Skeleton3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in skel.get_bone_count():
		var axis := Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5).normalized()
		skel.set_bone_pose_rotation(i, Quaternion(axis, rng.randf_range(-1.5, 1.5)))

var src_skel: Skeleton3D
var dst_skel: Skeleton3D

func before_each() -> void:
	src_skel = MirrorCodec.find_skeleton(autofree(MODEL.instantiate()))
	dst_skel = MirrorCodec.find_skeleton(autofree(MODEL.instantiate()))

func test_the_player_model_has_a_skeleton() -> void:
	assert_not_null(src_skel)

func test_a_frame_is_the_root_plus_8_bytes_per_bone() -> void:
	var frame := MirrorCodec.encode_pose(src_skel, Transform3D.IDENTITY)
	assert_eq(frame.size(), MirrorCodec.frame_size(src_skel.get_bone_count()))

func test_the_root_transform_survives_encoding() -> void:
	var root := Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.3, -0.2, 1.5))
	var decoded := MirrorCodec.decode_root(MirrorCodec.encode_pose(src_skel, root))
	assert_almost_eq(decoded.origin, root.origin, Vector3.ONE * 0.001)
	assert_lt(decoded.basis.get_rotation_quaternion().angle_to(root.basis.get_rotation_quaternion()), 0.001)

func test_bone_rotations_round_trip_onto_another_skeleton() -> void:
	scramble(src_skel)
	assert_gt(bone_error(src_skel, dst_skel), 0.1, "they differ before")
	MirrorCodec.apply_pose(dst_skel, MirrorCodec.encode_pose(src_skel, Transform3D.IDENTITY))
	assert_lt(bone_error(src_skel, dst_skel), ANGLE_TOLERANCE)

func test_a_message_slices_frames_and_clamps_the_index() -> void:
	var frame := MirrorCodec.encode_pose(src_skel, Transform3D.IDENTITY)
	var msg := MirrorMessage.new()
	msg.pose_frame_size = frame.size()
	for i in 3:
		msg.pose_data.append_array(frame)
	assert_eq(msg.frame_count(), 3)
	assert_eq(msg.get_frame(2), frame)
	assert_eq(msg.get_frame(99), frame)

func test_audio_is_decimated_and_packed_to_int16() -> void:
	var samples := PackedFloat32Array()
	for i in 400:
		samples.append(sin(i * 0.05) * 0.5)
	var pcm := MirrorCodec.encode_audio(samples, 4)
	assert_eq(pcm.size(), 200)
	var back := MirrorCodec.decode_audio(pcm)
	assert_eq(back.size(), 100)
	assert_almost_eq(back[10], (samples[40] + samples[41] + samples[42] + samples[43]) / 4.0, 0.001)
