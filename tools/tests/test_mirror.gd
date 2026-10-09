extends "res://tools/tests/test_base.gd"

## Magic mirror (GDD §10): skeleton pose capture -> message -> ghost round trip,
## audio quantizing, the ring timeout falling back to recording, and ringing.
## Live two-peer streaming needs a real network and is not covered here.

const MODEL: PackedScene = preload("res://scenes/player/player_model.tscn")
const MIRROR: PackedScene = preload("res://scenes/interactibles/mirror.tscn")
const ANGLE_TOLERANCE: float = 0.01

func run_tests() -> void:
	var world := await load_world()
	_test_pose_round_trip()
	_test_audio_round_trip()
	await _test_call_flow(world)

func _bone_error(a: Skeleton3D, b: Skeleton3D) -> float:
	var worst: float = 0.0
	for i in a.get_bone_count():
		worst = maxf(worst, a.get_bone_pose_rotation(i).angle_to(b.get_bone_pose_rotation(i)))
	return worst

func _scramble(skel: Skeleton3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in skel.get_bone_count():
		var axis := Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5).normalized()
		skel.set_bone_pose_rotation(i, Quaternion(axis, rng.randf_range(-1.5, 1.5)))

func _test_pose_round_trip() -> void:
	var src := MODEL.instantiate() as Node3D
	var dst := MODEL.instantiate() as Node3D
	add_child(src)
	add_child(dst)
	var src_skel := MirrorCodec.find_skeleton(src)
	var dst_skel := MirrorCodec.find_skeleton(dst)
	check(src_skel != null and dst_skel != null, "player model has a Skeleton3D")
	_scramble(src_skel)
	check(_bone_error(src_skel, dst_skel) > 0.1, "scrambled source differs from the ghost before applying")

	var root := Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.3, -0.2, 1.5))
	var frame := MirrorCodec.encode_pose(src_skel, root)
	check(frame.size() == MirrorCodec.frame_size(src_skel.get_bone_count()), "frame is root + 8 bytes per bone (%d B, %d bones)" % [frame.size(), src_skel.get_bone_count()])
	var decoded := MirrorCodec.decode_root(frame)
	check(decoded.origin.distance_to(root.origin) < 0.001 and decoded.basis.get_rotation_quaternion().angle_to(root.basis.get_rotation_quaternion()) < 0.001, "root transform survives encode/decode")
	MirrorCodec.apply_pose(dst_skel, frame)
	var err := _bone_error(src_skel, dst_skel)
	check(err < ANGLE_TOLERANCE, "bone rotations round-trip onto the ghost skeleton (worst %.5f rad)" % err)

	var msg := MirrorMessage.new()
	msg.pose_frame_size = frame.size()
	for i in 3:
		msg.pose_data.append_array(frame)
	check(msg.frame_count() == 3 and msg.get_frame(2) == frame and msg.get_frame(99) == frame, "message slices fixed-size frames and clamps the index")
	src.queue_free()
	dst.queue_free()

func _test_audio_round_trip() -> void:
	var samples := PackedFloat32Array()
	for i in 400:
		samples.append(sin(i * 0.05) * 0.5)
	var pcm := MirrorCodec.encode_audio(samples, 4)
	check(pcm.size() == 200, "audio is decimated and packed to int16 (400 samples -> 200 bytes)")
	var back := MirrorCodec.decode_audio(pcm)
	check(back.size() == 100 and absf(back[10] - (samples[40] + samples[41] + samples[42] + samples[43]) / 4.0) < 0.001, "decoded audio matches the averaged input")

func _test_call_flow(world: Node) -> void:
	var overlords := world.find_children("*", "OverlordActor", true, false)
	check(not overlords.is_empty(), "world has a local overlord")
	var mirror := MIRROR.instantiate() as Interactable
	add_child(mirror)
	await frames(5)
	mirror._player_in_range = overlords[0]

	# Ringing the mirror: glow + chime state.
	mirror._on_ring_received(2)
	await frames(3)
	check(mirror._incoming_caller == 2 and mirror._ring_glow.visible and mirror._ring_light.visible, "incoming ring lights the mirror")
	mirror._on_ring_cancelled(2)
	check(mirror._incoming_caller == -1 and not mirror._ring_glow.visible, "caller hanging up stops the ring")

	# Nobody answers: the call falls back to recording.
	mirror.start_call(2)
	check(mirror._state == mirror.State.CALLING, "calling a rival starts ringing")
	mirror._process_calling(mirror.RING_TIMEOUT - 1.0)
	check(mirror._state == mirror.State.CALLING, "still ringing before the timeout")
	mirror._process_calling(1.5)
	check(mirror._state == mirror.State.RECORDING, "unanswered call falls back to recording")
	check(mirror._notice != "", "the caller is told nobody answered")
	for i in 5:
		mirror._process_recording(0.1)
	mirror._stop_recording()
	var msg: MirrorMessage = mirror._recorded_message
	check(mirror._state == mirror.State.PREVIEW and msg != null, "recording ends in a preview")
	check(msg.recipient_peer_id == 2 and msg.frame_count() >= 10, "recorded message addressed to the callee has %d pose frames" % msg.frame_count())

	# Playing a message applies bone poses to the stage ghost.
	var skel := MirrorCodec.find_skeleton(overlords[0].get_model())
	_scramble(skel)
	var frame := MirrorCodec.encode_pose(skel, Transform3D.IDENTITY)
	msg.pose_data = frame
	msg.pose_frame_size = frame.size()
	msg.recipient_peer_id = 1
	mirror._recorded_message = null
	mirror._set_state(mirror.State.IDLE)
	mirror._on_message_received(msg)
	check(mirror._inbox.size() == 1, "message lands in the inbox")
	mirror._start_playback(msg)
	await frames(2)
	if mirror._play_skeleton != null:
		var err := 0.0
		for i in skel.get_bone_count():
			err = maxf(err, skel.get_bone_pose_rotation(i).angle_to(mirror._play_skeleton.get_bone_pose_rotation(i)))
		check(err < ANGLE_TOLERANCE, "playback poses the ghost skeleton (worst %.5f rad)" % err)
	else:
		check(false, "stage ghost skeleton exists during playback")
	mirror._stop_playback()
	check(mirror._inbox.is_empty() and mirror._state == mirror.State.IDLE, "watched message leaves the inbox")
