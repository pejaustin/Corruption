class_name PlayerState extends ActorState

## Base state for player-specific states.
## Provides camera, input, and movement helpers.

const WALK_SPEED: float = 5.0
const RUN_MODIFIER: float = 2.0
const ROTATION_INTERPOLATE_SPEED: float = 10.0
const JUMP_VELOCITY: float = 6.5

var player: AvatarActor:
	get: return actor as AvatarActor

func get_movement_input() -> Vector2:
	return player.avatar_input.input_dir

func get_run() -> bool:
	return player.avatar_input.run_input

func get_jump() -> bool:
	return player.avatar_input.jump_input

func get_attack() -> bool:
	return player.avatar_input.attack_input

func get_roll() -> bool:
	return player.avatar_input.roll_input

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

## Transition into ChannelState if a capture channel just started. Call at the
## top of tick() in any state that should yield to channeling (IdleState,
## MoveState, JumpState, FallState). AttackState intentionally skips this —
## attacks are commitment-based and finish before the channel takes over.
func try_enter_channel() -> bool:
	if player.active_channel != null and player.active_channel.is_active():
		state_machine.transition(&"ChannelState")
		return true
	return false

## Transition into RollState if the roll input is held OR was buffered within
## the input-queue window. Routes via Actor.try_transition so action_locked
## states can still be Roll-cancelled when RollState is in their
## cancel_whitelist. Returns true if the roll went through.
func try_roll() -> bool:
	if not (get_roll() or player.avatar_input.consume_if_buffered(&"roll")):
		return false
	return actor.try_transition(&"RollState")

## Transition into AttackState if the attack input is held OR was buffered.
## Used by IdleState/MoveState — call at the top of tick() so a press queued
## during a locked attack fires the next swing immediately on recovery.
func try_attack() -> bool:
	if not (get_attack() or player.avatar_input.consume_if_buffered(&"primary_ability")):
		return false
	return actor.try_transition(&"AttackState")

func move_air(delta: float) -> void:
	var input_dir := get_movement_input()
	var direction := (player.avatar_camera.camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed_mod := WALK_SPEED * 0.6
	if direction:
		actor.velocity.x = direction.x * speed_mod
		actor.velocity.z = direction.z * speed_mod
