extends PlayerState

## Quick i-frame retreat. Variant of RollState — shorter distance, briefer
## stagger immunity, longer recovery. Used as a roll-cancel from BlockState
## (see RollState entry conditions) and (planned, Tier D) as the input-driven
## backstep when the player presses Roll while no movement key is held and
## block is being tapped.
##
## Action gating: same shape as RollState — action_locked from enter, empty
## cancel_whitelist, full stagger_immune for the i-frame portion. Unlike a
## full roll, the i-frame window cuts off before the recovery tail so a
## misjudged backstep loses to a delayed swing.

const BACKSTEP_DURATION_TICKS: int = 14  # ~0.47s at netfox 30Hz; longer recovery than roll
const BACKSTEP_IFRAME_TICKS: int = 6     # i-frames cover the retreat itself, not the recovery
const BACKSTEP_SPEED: float = 6.0        # slower than roll (8.0) so backstep loses to chase

const BACKSTEP_CLIP: StringName = &"backstep"

var _enter_tick: int = -1
var _retreat_dir: Vector3 = Vector3.ZERO

func enter(_previous_state: RewindableState, tick: int) -> void:
	_enter_tick = NetworkTime.tick
	_retreat_dir = _compute_retreat_direction()
	action_locked = true
	stagger_immune = true

func display_enter(_previous_state: RewindableState, _tick: int) -> void:
	_play_backstep_clip()

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	# Non-authority peers skip enter(); re-latch on first tick.
	if _enter_tick < 0:
		_enter_tick = NetworkTime.tick
		_retreat_dir = _compute_retreat_direction()
	var elapsed: int = NetworkTime.tick - _enter_tick
	# Cut i-frames before recovery — a botched backstep loses to a delayed swing.
	if elapsed >= BACKSTEP_IFRAME_TICKS:
		stagger_immune = false
	actor.velocity.x = _retreat_dir.x * BACKSTEP_SPEED
	actor.velocity.z = _retreat_dir.z * BACKSTEP_SPEED
	physics_move()
	if elapsed >= BACKSTEP_DURATION_TICKS:
		if actor.is_on_floor():
			state_machine.transition(&"IdleState")
		else:
			state_machine.transition(&"FallState")

## Backstep direction: away from the locked target if any, else the negation
## of the camera forward (souls convention — backstep moves the player back
## from where they were facing, not where their model points). Y-flattened.
func _compute_retreat_direction() -> Vector3:
	if is_target_locked():
		var target_pos: Vector3 = locked_target_position()
		var away: Vector3 = actor.global_position - target_pos
		away.y = 0.0
		if away.length_squared() > 0.0001:
			return away.normalized()
	# Free mode: away from where the camera is looking.
	if player.avatar_camera:
		var cam_basis: Basis = player.avatar_camera.camera_basis
		var back: Vector3 = cam_basis.z
		back.y = 0.0
		if back.length_squared() > 0.0001:
			return back.normalized()
	return Vector3.BACK

func _play_backstep_clip() -> void:
	var anim: AnimationPlayer = actor._animation_player
	if anim == null:
		return
	var library := _resolve_library_prefix()
	if library == "":
		return
	var full: String = "%s/%s" % [library, BACKSTEP_CLIP]
	if anim.has_animation(full):
		anim.play(full)

func _resolve_library_prefix() -> String:
	var configured: String = animation_name
	var slash: int = configured.find("/")
	if slash <= 0:
		return ""
	return configured.substr(0, slash)
