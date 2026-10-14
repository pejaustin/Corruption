extends "res://tests/support/stage_test.gd"

## The mirror's call flow (GDD §10): ringing, the ring timeout falling back to recording,
## the inbox and playback. Encoding is test_mirror_codec's. Live two-peer streaming needs a
## real network and is a milestone check (tools/net/smoke.sh).

const MIRROR: PackedScene = preload("res://scenes/interactibles/mirror.tscn")
const OVERLORD: PackedScene = preload("res://scenes/actors/player/overlord/overlord_actor.tscn")
const Codec := preload("res://tests/unit/test_mirror_codec.gd")

var mirror: Interactable
var overlord: OverlordActor

func before_each() -> void:
	await super()
	overlord = OVERLORD.instantiate() as OverlordActor
	overlord.name = "1"
	stage.add_child(overlord)
	overlord.process_mode = Node.PROCESS_MODE_DISABLED
	mirror = MIRROR.instantiate() as Interactable
	stage.add_child(mirror)
	mirror._player_in_range = overlord
	await wait_process_frames(2)  # the mirror finds its Mirror3D deferred
	mirror.set_process(false)  # the tests step it

func test_an_incoming_ring_lights_the_mirror() -> void:
	mirror._on_ring_received(2)
	mirror._process_ring_effects(0.1)
	assert_eq(mirror._incoming_caller, 2)
	assert_true(mirror._ring_glow.visible and mirror._ring_light.visible)

func test_the_caller_hanging_up_stops_the_ring() -> void:
	mirror._on_ring_received(2)
	mirror._process_ring_effects(0.1)
	mirror._on_ring_cancelled(2)
	assert_eq(mirror._incoming_caller, -1)
	assert_false(mirror._ring_glow.visible)

func test_calling_rings_until_the_timeout() -> void:
	mirror.start_call(2)
	assert_eq(mirror._state, mirror.State.CALLING)
	mirror._process_calling(mirror.RING_TIMEOUT - 1.0)
	assert_eq(mirror._state, mirror.State.CALLING)

func test_an_unanswered_call_falls_back_to_recording() -> void:
	mirror.start_call(2)
	mirror._process_calling(mirror.RING_TIMEOUT + 0.5)
	assert_eq(mirror._state, mirror.State.RECORDING)
	assert_ne(mirror._notice, "", "the caller is told nobody answered")

func test_recording_ends_in_a_preview_addressed_to_the_callee() -> void:
	mirror.start_call(2)
	mirror._process_calling(mirror.RING_TIMEOUT + 0.5)
	for i in 5:
		mirror._process_recording(0.1)
	mirror._stop_recording()
	var msg: MirrorMessage = mirror._recorded_message
	assert_eq(mirror._state, mirror.State.PREVIEW)
	assert_eq(msg.recipient_peer_id, 2)
	assert_gt(msg.frame_count(), 0)

func _message() -> MirrorMessage:
	var skel := MirrorCodec.find_skeleton(overlord.get_model())
	Codec.scramble(skel)
	var frame := MirrorCodec.encode_pose(skel, Transform3D.IDENTITY)
	var msg := MirrorMessage.new()
	msg.pose_data = frame
	msg.pose_frame_size = frame.size()
	msg.recipient_peer_id = 1
	return msg

func test_a_received_message_lands_in_the_inbox() -> void:
	mirror._on_message_received(_message())
	assert_eq(mirror._inbox.size(), 1)

func test_playback_poses_the_ghost() -> void:
	var msg := _message()
	mirror._on_message_received(msg)
	mirror._start_playback(msg)
	assert_not_null(mirror._play_skeleton)
	assert_lt(Codec.bone_error(MirrorCodec.find_skeleton(overlord.get_model()), mirror._play_skeleton), Codec.ANGLE_TOLERANCE)

func test_a_watched_message_leaves_the_inbox() -> void:
	var msg := _message()
	mirror._on_message_received(msg)
	mirror._start_playback(msg)
	mirror._stop_playback()
	# Headless only (no renderer scenario): giving the viewport its shared world back logs this.
	assert_engine_error("scenario")
	assert_true(mirror._inbox.is_empty())
	assert_eq(mirror._state, mirror.State.IDLE)
