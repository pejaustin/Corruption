class_name PlayerState extends ActorState

## Base state for player-specific states.
## Provides camera, input, and movement helpers.

const WALK_SPEED: float = 5.0
const RUN_MODIFIER: float = 2.0
const ROTATION_INTERPOLATE_SPEED: float = 10.0
const JUMP_VELOCITY: float = 6.5

var player: AvatarActor:
	get: return actor as AvatarActor

## True iff the avatar's local Targeting child has a hard-lock target.
## Local-only — remote peers see is_locked = false on their copies of the
## avatar, so animation/movement code that branches on this still works.
func is_target_locked() -> bool:
	return player.targeting != null and player.targeting.is_locked and is_instance_valid(player.targeting.current_target)

## Locked-target world position with a chest-height bias for aim math. Caller
## is expected to have already checked is_target_locked().
func locked_target_position() -> Vector3:
	var t: Actor = player.targeting.current_target
	return t.global_position + Vector3(0.0, Targeting.TARGET_CHEST_OFFSET.y, 0.0)

func get_movement_input() -> Vector2:
	return player.avatar_input.input_dir

func get_run() -> bool:
	return player.avatar_input.run_input

func get_jump() -> bool:
	return player.avatar_input.jump_input

## Held flag — light-attack button. Tier D rename: was `attack_input` /
## `primary_ability` pre-split. The legacy `get_attack()` accessor is
## preserved as an alias so older states keep compiling.
func get_light_attack() -> bool:
	return player.avatar_input.light_attack_input

## Held flag — heavy-attack button. New in Tier D.
func get_heavy_attack() -> bool:
	return player.avatar_input.heavy_attack_input

## Legacy accessor — keep callers compiling. Equivalent to `get_light_attack`.
func get_attack() -> bool:
	return player.avatar_input.light_attack_input

func get_roll() -> bool:
	return player.avatar_input.roll_input

func get_block() -> bool:
	return player.avatar_input.block_input

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
	# Tier E — apply Eldritch-style movement slow if active. The multiplier is
	# 1.0 when no slow is in effect.
	var slow_mult: float = actor.get_movement_speed_mult() if actor else 1.0
	var target := direction * speed * slow_mult
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
##
## Tier C: when block is currently held, the dodge resolves to BackstepState
## instead — short i-frame retreat sized for guard-up spacing. The block-then-
## roll combo IS the input grammar for backstep; no separate keybind needed.
func try_roll() -> bool:
	if not (get_roll() or player.avatar_input.consume_if_buffered(&"roll")):
		return false
	if get_block():
		return actor.try_transition(&"BackstepState")
	return actor.try_transition(&"RollState")

## Transition into LightAttackState if the light-attack input is held OR was
## buffered. Used by IdleState/MoveState — call at the top of tick() so a press
## queued during a locked attack fires the next swing immediately on recovery.
##
## Tier D rename: was `try_attack` reading `&"primary_ability"`. The legacy
## `try_attack()` is kept as an alias so any older state still compiles.
func try_light_attack() -> bool:
	if not (get_light_attack() or player.avatar_input.consume_if_buffered(&"light_attack")):
		return false
	# Sprint-attack entry: light press while sprinting (run held + grounded
	# moving). MoveState handles its own override by calling
	# try_sprint_attack() directly; this path is the neutral fallback.
	return actor.try_transition(&"LightAttackState")

## Legacy alias — equivalent to `try_light_attack`. Kept so older callers
## (debug scripts, harnesses) compile.
func try_attack() -> bool:
	return try_light_attack()

## Transition into HeavyAttackState (or RiposteAttackerState if a posture-
## broken target is in range) on a heavy-attack press. Called by IdleState /
## MoveState alongside `try_light_attack`. Routes via `try_transition` so
## locked states with `cancel_whitelist` honored.
func try_heavy_attack() -> bool:
	if not (get_heavy_attack() or player.avatar_input.consume_if_buffered(&"heavy_attack")):
		return false
	# Riposte trigger: posture-broken target in front of us within range.
	if try_riposte():
		return true
	return actor.try_transition(&"HeavyAttackState")

## If the player is locked onto (or facing) a `is_ripostable` target within
## RIPOSTE_RANGE, transition into RiposteAttackerState. Returns true iff the
## riposte path took over. Called from `try_heavy_attack`; standalone callers
## are welcome (e.g. an explicit "execute" key in the future).
func try_riposte() -> bool:
	var victim := _find_riposte_target()
	if victim == null:
		return false
	# Stash the victim so RiposteAttackerState can read it on enter() — the
	# ripostable target isn't in any synced state yet, but the attacker's
	# state machine transition IS synced, so by the time clients resimulate
	# this tick the victim's `is_ripostable` flag is also set on their side.
	player.set_meta(&"_pending_riposte_target", victim)
	return actor.try_transition(&"RiposteAttackerState")

## Range within which a heavy press promotes to riposte. Generous enough to
## land on a stunned target without precise spacing.
const RIPOSTE_RANGE: float = 2.5
## Front-cone half-angle for riposte facing check, degrees.
const RIPOSTE_FACING_CONE_DEG: float = 60.0

func _find_riposte_target() -> Actor:
	# Prefer the locked target when one is held (Tier B).
	if is_target_locked():
		var locked: Actor = player.targeting.current_target
		if _is_ripostable(locked):
			return locked
		# Locked but locked target isn't ripostable — fall through to picker.
	# Otherwise scan all actors in the group for the closest ripostable in front.
	var nodes := actor.get_tree().get_nodes_in_group(&"actors")
	var best: Actor = null
	var best_dist_sq: float = RIPOSTE_RANGE * RIPOSTE_RANGE
	for n in nodes:
		var a := n as Actor
		if not _is_ripostable(a):
			continue
		var to: Vector3 = a.global_position - actor.global_position
		to.y = 0.0
		var d2: float = to.length_squared()
		if d2 > best_dist_sq:
			continue
		# Facing check — must be in our front cone.
		if not _is_in_front_cone(to):
			continue
		best = a
		best_dist_sq = d2
	return best

func _is_ripostable(a: Actor) -> bool:
	if a == null or a == actor:
		return false
	if not is_instance_valid(a):
		return false
	if not a.is_ripostable:
		return false
	if a.hp <= 0:
		return false
	return true

func _is_in_front_cone(to_target: Vector3) -> bool:
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return true
	to_target = to_target.normalized()
	var basis_node: Node3D = actor._model if actor._model else actor
	var fwd: Vector3 = -basis_node.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return false
	fwd = fwd.normalized()
	return fwd.dot(to_target) >= cos(deg_to_rad(RIPOSTE_FACING_CONE_DEG))

## Transition into BlockState if the block input is held. Used by IdleState
## and MoveState — call at the top of tick() so the player can guard from
## any neutral state. Uses the held flag (not buffered press) because block
## is a mode you stay in, not a one-shot. Routes via try_transition so
## action_locked states block the entry while RollState's cancel_whitelist
## remains intact.
func try_block() -> bool:
	if not get_block():
		return false
	return actor.try_transition(&"BlockState")

func move_air(delta: float) -> void:
	var input_dir := get_movement_input()
	var direction := (player.avatar_camera.camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed_mod := WALK_SPEED * 0.6
	if direction:
		actor.velocity.x = direction.x * speed_mod
		actor.velocity.z = direction.z * speed_mod
