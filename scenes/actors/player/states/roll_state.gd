extends PlayerState

## Short directional dodge. Commitment-based: action_locked from enter, with
## an empty cancel_whitelist, so nothing interrupts a roll once it starts.
## stagger_immune for the full duration — iframes roll-through-damage is the
## canonical "test the action-gating system" interaction.
##
## Rolls in the current input direction; falls back to backward (away from
## the camera) if no input is held. Animation-agnostic — leave animation_name
## empty until a roll clip is authored, and the state just glides.

const ROLL_DURATION_TICKS: int = 12  # ~0.4s at netfox 30Hz
const ROLL_SPEED: float = 8.0

var _enter_tick: int = 0
var _roll_dir: Vector3 = Vector3.ZERO

func enter(_previous_state: RewindableState, tick: int) -> void:
	_enter_tick = tick
	_roll_dir = _compute_roll_direction()
	action_locked = true
	stagger_immune = true

func tick(_delta: float, tick: int, _is_fresh: bool) -> void:
	actor.velocity.x = _roll_dir.x * ROLL_SPEED
	actor.velocity.z = _roll_dir.z * ROLL_SPEED
	physics_move()
	if tick - _enter_tick >= ROLL_DURATION_TICKS:
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
