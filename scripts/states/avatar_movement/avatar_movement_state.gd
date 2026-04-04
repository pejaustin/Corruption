class_name AvatarMovementState
extends RewindableState

## Base movement state for the Avatar entity.
## Mirrors MovementState but references Avatar and AvatarInput.

const WALK_SPEED := 5.0
const RUN_MODIFIER := 2.0
const ROTATION_INTERPOLATE_SPEED := 10
const JUMP_VELOCITY := 6.5

@export var animation_name: String
@export var avatar_camera: AvatarCamera
@export var avatar_model: Node3D
@export var avatar_input: AvatarInput
@export var parent: CharacterBody3D

func move_player(delta: float, speed: float = WALK_SPEED):
	parent.velocity *= NetworkTime.physics_factor
	parent.move_and_slide()
	parent.velocity /= NetworkTime.physics_factor

func rotate_player_model(delta: float):
	var cam_basis: Basis = avatar_camera.camera_basis

	# Model mesh faces +Z, so use cam_basis.z to point it away from camera
	var player_lookat_target = cam_basis.z
	var q_from = avatar_model.global_transform.basis.get_rotation_quaternion()
	var q_to = Transform3D().looking_at(player_lookat_target, Vector3.UP).basis.get_rotation_quaternion()

	var set_model_rotation = Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))
	avatar_model.global_transform.basis = set_model_rotation

func force_update_is_on_floor():
	var old_velocity = parent.velocity
	parent.velocity *= 0
	parent.move_and_slide()
	parent.velocity = old_velocity

func get_movement_input() -> Vector2:
	return avatar_input.input_dir

func get_run() -> bool:
	return avatar_input.run_input

func get_jump() -> bool:
	return avatar_input.jump_input

func get_attack() -> bool:
	return avatar_input.attack_input
