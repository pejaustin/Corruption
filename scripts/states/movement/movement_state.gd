class_name MovementState extends ActorState

## Base state for OverlordActor movement (Idle/Move/Jump/Fall).
## Mirrors PlayerState's pattern for the Avatar: the state reads input, camera,
## and model through the actor reference instead of per-state NodePath exports.

const WALK_SPEED: float = 5.0
const RUN_MODIFIER: float = 2.5
const ROTATION_INTERPOLATE_SPEED: float = 10.0
const JUMP_VELOCITY: float = 6.5
const JUMP_MOVE_SPEED: float = 3.0

var overlord: OverlordActor:
	get: return actor as OverlordActor

func move_player(delta: float, speed: float = WALK_SPEED) -> void:
	var input_dir := get_movement_input()
	var direction := (overlord._camera_input.camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var position_target := direction * speed
	if get_run():
		position_target *= RUN_MODIFIER
	if position_target:
		overlord.velocity.x = position_target.x
		overlord.velocity.z = position_target.z
	else:
		overlord.velocity.x = move_toward(overlord.velocity.x, 0, speed)
		overlord.velocity.z = move_toward(overlord.velocity.z, 0, speed)
	physics_move()

func rotate_player_model(delta: float) -> void:
	var cam_basis: Basis = overlord._camera_input.camera_basis
	# NOTE: Model direction issues can be resolved by negating camera_z, depending on setup.
	var player_lookat_target: Vector3 = -cam_basis.z
	var q_from := overlord._model.global_transform.basis.get_rotation_quaternion()
	var q_to := Transform3D().looking_at(player_lookat_target, Vector3.UP).basis.get_rotation_quaternion()
	var set_model_rotation := Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))
	overlord._model.global_transform.basis = set_model_rotation

# https://foxssake.github.io/netfox/netfox/tutorials/rollback-caveats/#characterbody-on-floor
func force_update_is_on_floor() -> void:
	var old_velocity: Vector3 = overlord.velocity
	overlord.velocity *= 0
	overlord.move_and_slide()
	overlord.velocity = old_velocity

func get_movement_input() -> Vector2:
	return overlord._player_input.input_dir

func get_run() -> bool:
	return overlord._player_input.run_input

func get_jump() -> bool:
	return overlord._player_input.jump_input
