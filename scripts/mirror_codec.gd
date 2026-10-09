class_name MirrorCodec extends RefCounted

## Wire format for the magic mirror (GDD §10): skeleton pose frames and audio chunks.
##
## A pose frame is one PackedByteArray: the model's root transform relative to the
## mirror (position as 3 float32, rotation as a float32 quaternion = 28 bytes),
## then one quantized rotation per bone (4 x int16 = 8 bytes). Bone positions and
## scales are not sent; the ghost is the same model, so its rest values match.
## Live streaming sends one frame per packet; recorded messages concatenate
## frames into one buffer of fixed-size frames.

const ROOT_BYTES: int = 28
const BONE_BYTES: int = 8
const QUAT_SCALE: float = 32767.0
const PCM_SCALE: float = 32767.0

static func find_skeleton(model: Node) -> Skeleton3D:
	if model == null:
		return null
	return model.find_child("Skeleton3D", true, false) as Skeleton3D

static func frame_size(bone_count: int) -> int:
	return ROOT_BYTES + bone_count * BONE_BYTES

static func encode_pose(skeleton: Skeleton3D, root: Transform3D) -> PackedByteArray:
	var bone_count: int = skeleton.get_bone_count() if skeleton else 0
	var frame := PackedByteArray()
	frame.resize(frame_size(bone_count))
	frame.encode_float(0, root.origin.x)
	frame.encode_float(4, root.origin.y)
	frame.encode_float(8, root.origin.z)
	var rq: Quaternion = root.basis.orthonormalized().get_rotation_quaternion()
	frame.encode_float(12, rq.x)
	frame.encode_float(16, rq.y)
	frame.encode_float(20, rq.z)
	frame.encode_float(24, rq.w)
	for i in bone_count:
		_put_quat(frame, ROOT_BYTES + i * BONE_BYTES, skeleton.get_bone_pose_rotation(i))
	return frame

static func decode_root(frame: PackedByteArray) -> Transform3D:
	if frame.size() < ROOT_BYTES:
		return Transform3D.IDENTITY
	var origin := Vector3(frame.decode_float(0), frame.decode_float(4), frame.decode_float(8))
	var q := Quaternion(frame.decode_float(12), frame.decode_float(16), frame.decode_float(20), frame.decode_float(24))
	if q.length_squared() < 0.5:
		q = Quaternion.IDENTITY
	return Transform3D(Basis(q.normalized()), origin)

static func decode_bone_count(frame: PackedByteArray) -> int:
	return maxi(0, floori((frame.size() - ROOT_BYTES) / float(BONE_BYTES)))

static func apply_pose(skeleton: Skeleton3D, frame: PackedByteArray) -> void:
	## Writes the frame's bone rotations onto the skeleton. Extra bones on either
	## side are ignored. The caller sets the root transform (see decode_root).
	if skeleton == null:
		return
	var count: int = mini(decode_bone_count(frame), skeleton.get_bone_count())
	for i in count:
		skeleton.set_bone_pose_rotation(i, _get_quat(frame, ROOT_BYTES + i * BONE_BYTES))

static func encode_audio(samples: PackedFloat32Array, decimate: int) -> PackedByteArray:
	## Mono float samples to int16 PCM, averaging every `decimate` samples (a cheap
	## downsample, so live voice stays small on the wire).
	var step: int = maxi(1, decimate)
	var count: int = floori(samples.size() / float(step))
	var out := PackedByteArray()
	out.resize(count * 2)
	for i in count:
		var sum: float = 0.0
		for j in step:
			sum += samples[i * step + j]
		out.encode_s16(i * 2, int(round(clampf(sum / step, -1.0, 1.0) * PCM_SCALE)))
	return out

static func decode_audio(bytes: PackedByteArray) -> PackedFloat32Array:
	var count: int = floori(bytes.size() / 2.0)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		out[i] = bytes.decode_s16(i * 2) / PCM_SCALE
	return out

static func _put_quat(buf: PackedByteArray, offset: int, q: Quaternion) -> void:
	var n: Quaternion = q.normalized()
	buf.encode_s16(offset, int(round(n.x * QUAT_SCALE)))
	buf.encode_s16(offset + 2, int(round(n.y * QUAT_SCALE)))
	buf.encode_s16(offset + 4, int(round(n.z * QUAT_SCALE)))
	buf.encode_s16(offset + 6, int(round(n.w * QUAT_SCALE)))

static func _get_quat(buf: PackedByteArray, offset: int) -> Quaternion:
	var q := Quaternion(
		buf.decode_s16(offset) / QUAT_SCALE,
		buf.decode_s16(offset + 2) / QUAT_SCALE,
		buf.decode_s16(offset + 4) / QUAT_SCALE,
		buf.decode_s16(offset + 6) / QUAT_SCALE)
	if q.length_squared() < 0.5:
		return Quaternion.IDENTITY
	return q.normalized()
