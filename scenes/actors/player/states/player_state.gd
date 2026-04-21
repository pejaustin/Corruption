class_name PlayerState extends ActorState

## Base state for player-specific states.
## Provides camera, input, and movement helpers.

const WALK_SPEED: float = 5.0
const RUN_MODIFIER: float = 2.0
const ROTATION_INTERPOLATE_SPEED: float = 10.0
const JUMP_VELOCITY: float = 6.5

var player: PlayerActor:
	get: return actor as PlayerActor

func get_movement_input() -> Vector2:
	return player.avatar_input.input_dir

func get_run() -> bool:
	return player.avatar_input.run_input

func get_jump() -> bool:
	return player.avatar_input.jump_input

func get_attack() -> bool:
	return player.avatar_input.attack_input

func rotate_player_model(delta: float) -> void:
	var cam_basis: Basis = player.avatar_camera.camera_basis
	var player_lookat_target = cam_basis.z
	var q_from = actor._model.global_transform.basis.get_rotation_quaternion()
	var q_to = Transform3D().looking_at(player_lookat_target, Vector3.UP).basis.get_rotation_quaternion()
	var set_rotation = Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))
	actor._model.global_transform.basis = set_rotation

func move_horizontal(delta: float, speed: float = WALK_SPEED) -> void:
	var input_dir := get_movement_input()
	var direction := (player.avatar_camera.camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var target := direction * speed
	if get_run():
		target *= RUN_MODIFIER
	if target:
		actor.velocity.x = target.x
		actor.velocity.z = target.z
	else:
		actor.velocity.x = move_toward(actor.velocity.x, 0, speed)
		actor.velocity.z = move_toward(actor.velocity.z, 0, speed)

func move_air(delta: float) -> void:
	var input_dir := get_movement_input()
	var direction := (player.avatar_camera.camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed_mod := WALK_SPEED * 0.6
	if direction:
		actor.velocity.x = direction.x * speed_mod
		actor.velocity.z = direction.z * speed_mod
