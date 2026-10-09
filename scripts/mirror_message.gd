class_name MirrorMessage extends RefCounted

## A recorded "video" message from one Overlord to another (GDD §10).
##
## Instead of capturing pixel frames (expensive GPU readback) we record the
## sender's skeleton pose at a fixed sample rate (see MirrorCodec for the frame
## layout). The recipient's mirror plays the message back inside an isolated
## stage scene, writing each frame's bone rotations onto a ghost copy of
## player_model.tscn.

var sender_peer_id: int
var recipient_peer_id: int

# Pose track: fixed-size frames, concatenated.
var pose_sample_rate: float = 30.0
var pose_frame_size: int = 0
var pose_data: PackedByteArray = PackedByteArray()

# Audio
var audio_data: PackedByteArray = PackedByteArray()  # Raw float32 mono samples
var audio_sample_rate: int = 22050
var duration: float = 0.0

func frame_count() -> int:
	if pose_frame_size <= 0:
		return 0
	return floori(pose_data.size() / float(pose_frame_size))

func get_frame(index: int) -> PackedByteArray:
	var count: int = frame_count()
	if count == 0:
		return PackedByteArray()
	var i: int = clampi(index, 0, count - 1)
	return pose_data.slice(i * pose_frame_size, (i + 1) * pose_frame_size)
