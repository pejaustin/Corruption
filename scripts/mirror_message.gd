class_name MirrorMessage extends RefCounted

## A recorded video message from one Overlord to another.

var sender_peer_id: int
var recipient_peer_id: int
var frames: Array[PackedByteArray] = []  # JPEG-compressed images
var audio_data: PackedByteArray = PackedByteArray()  # Raw float32 audio samples
var frame_rate: float = 5.0
var sample_rate: int = 22050
var duration: float = 0.0
