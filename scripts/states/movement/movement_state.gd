class_name MovementState
extends RewindableState

## A base movement state for common functions, extend when making new movement state.

const WALK_SPEED: float = 5.0
const RUN_MODIFIER: float = 2.5
const ROTATION_INTERPOLATE_SPEED: float = 10.0
const JUMP_VELOCITY: float = 6.5
const JUMP_MOVE_SPEED: float = 3.0

@export var animation_name: String
@export var camera_input: CameraInput
@export var player_model: Node3D
@export var player_input: PlayerInput
@export var parent: Player

func move_player(delta: float, speed: float = WALK_SPEED) -> void:
	var input_dir: Vector2 = get_movement_input()

	# Based on https://github.com/godotengine/godot-demo-projects/blob/4.2-31d1c0c/3d/platformer/player/player.gd#L65
	var direction: Vector3 = (camera_input.camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var position_target: Vector3 = direction * speed

	if get_run():
		position_target *= RUN_MODIFIER

	if position_target:
		parent.velocity.x = position_target.x
		parent.velocity.z = position_target.z
	else:
		parent.velocity.x = move_toward(parent.velocity.x, 0, speed)
		parent.velocity.z = move_toward(parent.velocity.z, 0, speed)

	# https://foxssake.github.io/netfox/netfox/tutorials/rollback-caveats/#characterbody-velocity
	parent.velocity *= NetworkTime.physics_factor
	parent.move_and_slide()
	parent.velocity /= NetworkTime.physics_factor

func rotate_player_model(delta: float) -> void:
	var cam_basis: Basis = camera_input.camera_basis

	# NOTE: Model direction issues can be resolved by adding a negative to camera_z, depending on setup.
	var player_lookat_target: Vector3 = -cam_basis.z

	var q_from: Quaternion = player_model.global_transform.basis.get_rotation_quaternion()
	var q_to: Quaternion = Transform3D().looking_at(player_lookat_target, Vector3.UP).basis.get_rotation_quaternion()

	var set_model_rotation := Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))
	player_model.global_transform.basis = set_model_rotation

# https://foxssake.github.io/netfox/netfox/tutorials/rollback-caveats/#characterbody-on-floor
func force_update_is_on_floor() -> void:
	var old_velocity: Vector3 = parent.velocity
	parent.velocity *= 0
	parent.move_and_slide()
	parent.velocity = old_velocity

func get_movement_input() -> Vector2:
	return player_input.input_dir

func get_run() -> bool:
	return player_input.run_input

func get_jump() -> bool:
	return player_input.jump_input
