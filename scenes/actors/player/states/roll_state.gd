extends PlayerState

## Short directional dodge. Commitment-based: action_locked from enter, with
## an empty cancel_whitelist, so nothing interrupts a roll once it starts.
## stagger_immune for the full duration — iframes roll-through-damage is the
## canonical "test the action-gating system" interaction.
##
## Rolls in the current input direction; falls back to backward (away from
## the camera) if no input is held. When Targeting.is_locked, the input
## direction is interpreted in target-relative space, and the played clip
## switches to roll_back/roll_left/roll_right per direction. Missing
## directional clips fall back to `animation_name` (typically the existing
## roll_forward) so the state never crashes if art is absent.

const ROLL_DURATION_TICKS: int = 12  # ~0.4s at netfox 30Hz
const ROLL_SPEED: float = 8.0
## Tier E — baseline distance ROLL_SPEED * ROLL_DURATION_TICKS implies (~3.2m
## at 30Hz physics tick). When AvatarActor's faction overrides this, we scale
## ROLL_DURATION_TICKS to deliver the requested distance at constant speed.
const BASELINE_ROLL_DISTANCE: float = 6.0

## Roll clip suffixes by direction. Resolved against the library prefix in the
## configured `animation_name` ("large-male/Crouch" → "large-male").
const ROLL_CLIPS: Dictionary[StringName, StringName] = {
	&"forward": &"roll_forward",
	&"back": &"roll_back",
	&"left": &"roll_left",
	&"right": &"roll_right",
}

var _enter_tick: int = 0
var _roll_dir: Vector3 = Vector3.ZERO
## Direction tag chosen at enter; consumed by display_enter to pick the clip.
var _roll_dir_tag: StringName = &"forward"
## Tier E — resolved at enter from AvatarActor's faction overrides; falls
## back to the const defaults for actors that don't expose overrides.
var _resolved_duration_ticks: int = ROLL_DURATION_TICKS

func enter(_previous_state: RewindableState, tick: int) -> void:
	_enter_tick = tick
	if is_target_locked():
		var pair := _compute_locked_roll()
		_roll_dir = pair[0]
		_roll_dir_tag = pair[1]
	else:
		_roll_dir = _compute_roll_direction()
		_roll_dir_tag = &"forward"
	action_locked = true
	stagger_immune = true
	# Tier E — resolve faction-driven roll tuning. AvatarActor.get_*_override
	# returns -1 / -1.0 when no override is set. roll_distance scales the
	# duration (constant speed) so longer rolls cover more ground; i-frame
	# ticks are honored directly.
	_resolved_duration_ticks = ROLL_DURATION_TICKS
	if actor.has_method(&"get_roll_distance_override"):
		var dist: float = actor.call(&"get_roll_distance_override")
		if dist > 0.0:
			_resolved_duration_ticks = int(round(ROLL_DURATION_TICKS * dist / BASELINE_ROLL_DISTANCE))
	if actor.has_method(&"get_roll_iframe_ticks_override"):
		var iframes: int = actor.call(&"get_roll_iframe_ticks_override")
		if iframes > 0:
			# I-frame window can outlast the directional movement (Souls
			# convention — long-i-frame rolls coast in the recovery tail).
			_resolved_duration_ticks = max(_resolved_duration_ticks, iframes)

func display_enter(_previous_state: RewindableState, _tick: int) -> void:
	_play_roll_variant()

func tick(_delta: float, tick: int, _is_fresh: bool) -> void:
	actor.velocity.x = _roll_dir.x * ROLL_SPEED
	actor.velocity.z = _roll_dir.z * ROLL_SPEED
	physics_move()
	if tick - _enter_tick >= _resolved_duration_ticks:
		if actor.is_on_floor():
			state_machine.transition(&"IdleState")
		else:
			state_machine.transition(&"FallState")

func _compute_roll_direction() -> Vector3:
	var input_dir := get_movement_input()
	var direction: Vector3
	if input_dir != Vector2.ZERO:
		direction = player.avatar_camera.camera_basis * Vector3(input_dir.x, 0, input_dir.y)
	else:
		# No input: roll backward — away from where the camera/player is facing.
		direction = player.avatar_camera.camera_basis.z
	direction.y = 0
	if direction.length_squared() == 0.0:
		return Vector3.BACK
	return direction.normalized()

## Locked-mode roll: input is interpreted in target-relative basis. Returns
## [Vector3 world-direction, StringName tag] so display_enter can pick the
## correct directional clip without recomputing.
func _compute_locked_roll() -> Array:
	var target_pos: Vector3 = locked_target_position()
	var forward: Vector3 = target_pos - actor.global_position
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		# Degenerate — fall back to free behavior.
		return [_compute_roll_direction(), &"back"]
	forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var input_dir := get_movement_input()
	if input_dir == Vector2.ZERO:
		# No input → back-step away from target. Souls convention.
		return [-forward, &"back"]
	var dir_world: Vector3 = forward * (-input_dir.y) + right * input_dir.x
	dir_world.y = 0.0
	if dir_world.length_squared() == 0.0:
		return [-forward, &"back"]
	dir_world = dir_world.normalized()
	var tag: StringName = _dominant_roll_dir(input_dir)
	return [dir_world, tag]

func _dominant_roll_dir(input_dir: Vector2) -> StringName:
	if absf(input_dir.y) >= absf(input_dir.x):
		return &"forward" if input_dir.y < 0.0 else &"back"
	return &"right" if input_dir.x > 0.0 else &"left"

func _play_roll_variant() -> void:
	var anim: AnimationPlayer = actor._animation_player
	if anim == null:
		return
	var library := _resolve_library_prefix()
	if library == "":
		return
	var clip_suffix: StringName = ROLL_CLIPS.get(_roll_dir_tag, &"")
	if clip_suffix == &"":
		return
	var full: String = "%s/%s" % [library, clip_suffix]
	if not anim.has_animation(full):
		return
	anim.play(full)

func _resolve_library_prefix() -> String:
	var configured: String = animation_name
	var slash: int = configured.find("/")
	if slash <= 0:
		return ""
	return configured.substr(0, slash)
