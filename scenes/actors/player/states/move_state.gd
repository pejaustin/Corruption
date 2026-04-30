extends PlayerState

## Walking / running locomotion. Two modes:
## - Free: movement basis = camera; one forward animation. Existing behavior.
## - Locked (Targeting.is_locked): movement basis = camera-XZ-forward toward
##   target; animation picks one of walk_forward/back/left/right (or run_*)
##   based on the dominant input direction in target-relative space.
##
## Strafe clips are looked up as `<library>/walk_forward`, etc. — same
## convention StaggerState uses. Missing clips fall back silently to the
## existing `animation_name` clip; the state never crashes if art is absent.

## Animation clip suffixes for the strafe set. Library prefix comes from the
## state's configured `animation_name` (e.g. "large-male/Walk" → "large-male").
const STRAFE_WALK_CLIPS: Dictionary[StringName, StringName] = {
	&"forward": &"walk_forward",
	&"back": &"walk_back",
	&"left": &"walk_left",
	&"right": &"walk_right",
}
const STRAFE_RUN_CLIPS: Dictionary[StringName, StringName] = {
	&"forward": &"run_forward",
	&"back": &"run_back",
	&"left": &"run_left",
	&"right": &"run_right",
}

var _last_strafe_clip: StringName = &""

func display_enter(_previous_state: RewindableState, _tick: int) -> void:
	_last_strafe_clip = &""

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	if try_enter_channel():
		return
	if try_roll():
		return
	# Holding block while moving immediately drops into BlockState; the
	# avatar slows to a guarded stop. Same priority as in IdleState.
	if try_block():
		return
	if is_target_locked():
		_face_locked_target(delta)
		_move_target_relative(delta)
		_play_strafe_clip()
	else:
		rotate_player_model(delta)
		move_horizontal(delta)
		_last_strafe_clip = &""
	physics_move()

	if actor.is_on_floor():
		# Sprint-attack override: if running AND attacking, use the dedicated
		# SprintAttackState so we get the lunge profile + carry-momentum feel.
		# Otherwise fall through to the neutral light/heavy entry.
		if get_run() and (get_light_attack() or get_heavy_attack() or player.avatar_input.consume_if_buffered(&"light_attack") or player.avatar_input.consume_if_buffered(&"heavy_attack")):
			if actor.try_transition(&"SprintAttackState"):
				return
		if try_heavy_attack():
			return
		if try_light_attack():
			return
		if get_movement_input() == Vector2.ZERO:
			state_machine.transition(&"IdleState")
		elif get_jump():
			state_machine.transition(&"JumpState")
	else:
		state_machine.transition(&"FallState")

## Face toward the locked target (XZ plane). Ignores camera basis — model
## rotation is driven by the target during a hard-lock, regardless of where
## the camera happens to point this frame.
func _face_locked_target(delta: float) -> void:
	var target_pos: Vector3 = locked_target_position()
	var to_target: Vector3 = target_pos - actor._model.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return
	var look_dir: Vector3 = to_target.normalized()
	var q_from := actor._model.global_transform.basis.get_rotation_quaternion()
	# looking_at expects the target point in world space; use the model's
	# position offset by look_dir so the helper does the basis math for us.
	var q_to := Transform3D().looking_at(-look_dir, Vector3.UP).basis.get_rotation_quaternion()
	var rot := Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))
	actor._model.global_transform.basis = rot

## Compute movement using the avatar→target basis instead of the camera basis.
## W maps to "toward target", S to "away", A/D to lateral strafe.
func _move_target_relative(_delta: float) -> void:
	var target_pos: Vector3 = locked_target_position()
	var forward: Vector3 = target_pos - actor.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		# Degenerate — fall back to camera-relative move so the player isn't
		# stranded if they're standing on top of the target.
		move_horizontal(_delta)
		return
	forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var input_dir := get_movement_input()
	var target_vel: Vector3 = forward * (-input_dir.y) + right * input_dir.x
	if target_vel.length_squared() > 1.0:
		target_vel = target_vel.normalized()
	var speed: float = WALK_SPEED
	if get_run():
		speed *= RUN_MODIFIER
	# Tier E — Eldritch slow multiplier (1.0 when no slow is active).
	speed *= actor.get_movement_speed_mult()
	target_vel *= speed
	if target_vel.length_squared() > 0.0:
		actor.velocity.x = target_vel.x
		actor.velocity.z = target_vel.z
	else:
		actor.velocity.x = move_toward(actor.velocity.x, 0, speed)
		actor.velocity.z = move_toward(actor.velocity.z, 0, speed)

## Switch to the directional walk/run clip whose direction matches the
## dominant input axis in target-relative space. Falls back to the configured
## `animation_name` if the chosen clip isn't in the model's animation library.
## Clip swap is local-only presentation and must NOT run during rollback
## resimulation. AnimationPlayer state isn't in netfox's recorded state, so a
## resim that flips the clip multiple times would just churn — the gate keeps
## the chosen clip stable across the resim window.
func _play_strafe_clip() -> void:
	if NetworkRollback.is_rollback():
		return
	var anim: AnimationPlayer = actor._animation_player
	if anim == null:
		return
	var input_dir := get_movement_input()
	if input_dir == Vector2.ZERO:
		_last_strafe_clip = &""
		return
	var clip_dir: StringName = _dominant_strafe_dir(input_dir)
	var table: Dictionary[StringName, StringName] = STRAFE_RUN_CLIPS if get_run() else STRAFE_WALK_CLIPS
	var clip_suffix: StringName = table.get(clip_dir, &"")
	if clip_suffix == &"":
		return
	var library: String = _resolve_library_prefix()
	if library == "":
		return
	var full: String = "%s/%s" % [library, clip_suffix]
	if not anim.has_animation(full):
		return
	if anim.current_animation == full:
		return
	anim.play(full)
	_last_strafe_clip = StringName(full)

func _dominant_strafe_dir(input_dir: Vector2) -> StringName:
	# Forward in our convention is -Y on the input vector (W). Compare absolute
	# axis magnitudes; ties prefer forward/back.
	if absf(input_dir.y) >= absf(input_dir.x):
		return &"forward" if input_dir.y < 0.0 else &"back"
	return &"right" if input_dir.x > 0.0 else &"left"

func _resolve_library_prefix() -> String:
	var configured: String = animation_name
	var slash: int = configured.find("/")
	if slash <= 0:
		return ""
	return configured.substr(0, slash)
