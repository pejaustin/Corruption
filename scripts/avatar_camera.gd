class_name AvatarCamera extends Node3D

## 3rd-person camera for the shared Avatar entity.
## Authority transfers with the controlling peer.

@export var camera_mount: Node3D
@export var camera_rot: Node3D
@export var camera_3d: Camera3D

var camera_basis: Basis = Basis.IDENTITY

const CAMERA_MOUSE_ROTATION_SPEED: float = 0.005
const CAMERA_X_ROT_MIN: float = deg_to_rad(-70)
const CAMERA_X_ROT_MAX: float = deg_to_rad(60)
const CAMERA_JOYSTICK_ROTATION_SPEED: int = 5
const THIRD_PERSON_OFFSET: Vector3 = Vector3(0, 0.5, 4)

## Soft cap on stacked shake amplitude. Multiple overlapping shake() calls
## accumulate but get clamped here so a flurry of hits can't whip the camera
## off-screen.
const SHAKE_AMPLITUDE_CAP: float = 0.4

var controlling_peer_id: int = -1

var _shake_remaining: float = 0.0
var _shake_amplitude: float = 0.0

func _ready() -> void:
	NetworkTime.before_tick_loop.connect(_gather)
	camera_3d.position = THIRD_PERSON_OFFSET
	camera_3d.current = false

func _gather() -> void:
	camera_basis = get_camera_basis()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and controlling_peer_id == multiplayer.get_unique_id() and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_camera(event.relative * CAMERA_MOUSE_ROTATION_SPEED)

func _process(delta: float) -> void:
	if controlling_peer_id == multiplayer.get_unique_id():
		var total = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
		rotate_camera(total * CAMERA_JOYSTICK_ROTATION_SPEED * delta)
	_tick_shake(delta)

## Add a camera-shake pulse. Amplitudes stack (so a heavy hit immediately
## after a light one feels stronger), and the longer of the two durations
## wins. Local-only — never run from a rollback resimulation path; the
## caller is expected to gate. See HitFx.spawn for an example gate.
func shake(amplitude: float, duration: float) -> void:
	if amplitude <= 0.0 or duration <= 0.0:
		return
	_shake_amplitude = clampf(_shake_amplitude + amplitude, 0.0, SHAKE_AMPLITUDE_CAP)
	_shake_remaining = maxf(_shake_remaining, duration)

func _tick_shake(delta: float) -> void:
	if _shake_remaining <= 0.0:
		# Idempotent reset so a single frame after timeout snaps cleanly
		# rather than leaving the camera at a sub-millimeter offset.
		if camera_3d.position != THIRD_PERSON_OFFSET:
			camera_3d.position = THIRD_PERSON_OFFSET
		_shake_amplitude = 0.0
		return
	_shake_remaining -= delta
	if _shake_remaining <= 0.0:
		camera_3d.position = THIRD_PERSON_OFFSET
		_shake_amplitude = 0.0
		return
	var jitter := Vector3(
		randf_range(-_shake_amplitude, _shake_amplitude),
		randf_range(-_shake_amplitude, _shake_amplitude),
		0.0,
	)
	camera_3d.position = THIRD_PERSON_OFFSET + jitter

func rotate_camera(move: Vector2) -> void:
	camera_mount.rotate_y(-move.x)
	camera_rot.rotation.x = clamp(camera_rot.rotation.x + (-1 * move.y), CAMERA_X_ROT_MIN, CAMERA_X_ROT_MAX)

func get_camera_basis() -> Basis:
	return camera_mount.global_transform.basis

func activate(peer_id: int) -> void:
	controlling_peer_id = peer_id
	# Transfer authority so netfox syncs camera_basis input from the right peer
	set_multiplayer_authority(peer_id)
	if peer_id == multiplayer.get_unique_id():
		camera_3d.current = true
	else:
		camera_3d.current = false

func deactivate() -> void:
	controlling_peer_id = -1
	set_multiplayer_authority(1)
	camera_3d.current = false

func _exit_tree() -> void:
	NetworkTime.before_tick_loop.disconnect(_gather)
