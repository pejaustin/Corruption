class_name MirrorMessage extends RefCounted

## A recorded "video" message from one Overlord to another.
##
## Instead of capturing pixel frames (expensive GPU readback) we record the
## sender's player-model pose at a fixed sample rate. The recipient's mirror
## plays the message back inside an isolated stage scene, driving a ghost
## instance of player_model.tscn from the captured pose track.

var sender_peer_id: int
var recipient_peer_id: int

# Pose track — parallel arrays, one entry per sample.
var pose_sample_rate: float = 30.0
var ghost_xforms: Array[Transform3D] = []   # Model global transform, in stage-local space
var anim_states: PackedStringArray = PackedStringArray()  # Current animation name per sample

# Audio
var audio_data: PackedByteArray = PackedByteArray()  # Raw float32 mono samples
var audio_sample_rate: int = 22050
var duration: float = 0.0
