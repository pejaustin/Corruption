class_name CameraInput extends Node3D

@export var camera_mount : Node3D
@export var camera_rot : Node3D
@export var camera_3d : Camera3D
@export var rollback_synchronizer : RollbackSynchronizer

var camera_basis : Basis = Basis.IDENTITY

const CAMERA_MOUSE_ROTATION_SPEED: float = 0.005
const CAMERA_X_ROT_MIN: float = deg_to_rad(-70)
const CAMERA_X_ROT_MAX: float = deg_to_rad(60)
const CAMERA_UP_DOWN_MOVEMENT: int = -1
const CAMERA_JOYSTICK_ROTATION_SPEED: int = 5


func _ready() -> void:
	NetworkTime.before_tick_loop.connect(_gather)

	if multiplayer.get_unique_id() == str(get_parent().name).to_int():
		camera_3d.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		camera_3d.current = false
		$CameraMount/CameraRot/Camera3D/ViewModel.visible = false


func _gather() -> void:
	camera_basis = get_camera_rotation_basis()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and is_multiplayer_authority() and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_camera(event.relative * CAMERA_MOUSE_ROTATION_SPEED)

func get_input_joystick(delta: float) -> void:
	var total = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	rotate_camera(total * CAMERA_JOYSTICK_ROTATION_SPEED * delta)

func _process(delta: float) -> void:
	get_input_joystick(delta)

func rotate_camera(move: Vector2) -> void:
	camera_mount.rotate_y(-move.x)
	camera_rot.rotation.x = clamp(camera_rot.rotation.x + (CAMERA_UP_DOWN_MOVEMENT * move.y), CAMERA_X_ROT_MIN, CAMERA_X_ROT_MAX)

func get_camera_rotation_basis() -> Basis:
	return camera_mount.global_transform.basis

func _exit_tree() -> void:
	NetworkTime.before_tick_loop.disconnect(_gather)
