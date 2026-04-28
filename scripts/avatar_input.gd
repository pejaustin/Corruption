class_name AvatarInput extends Node

## Input handler for the shared Avatar entity.
## Unlike PlayerInput, authority is dynamically transferred
## based on which peer currently controls the Avatar.

## Edge-pressed inputs are stamped with NetworkTime.tick. While the avatar is
## action-locked, presses land here; states call consume_if_buffered() the
## moment they're free to act, so a press up to BUFFER_WINDOW ticks late still
## fires. Souls/Elden-Ring-style input queueing.
const BUFFER_WINDOW: int = 12

var input_dir: Vector2 = Vector2.ZERO
var jump_input := false
var run_input := false
var attack_input := false
var roll_input := false

## When false, all input is zeroed (pause menu open).
var input_enabled: bool = true

## The peer ID currently controlling the Avatar. -1 = dormant/no one.
var controlling_peer_id: int = -1

var _press_tick: Dictionary[StringName, int] = {}

func _ready() -> void:
	NetworkTime.before_tick_loop.connect(_gather)

func _gather() -> void:
	if input_enabled and controlling_peer_id == multiplayer.get_unique_id():
		input_dir = Input.get_vector("left", "right", "forward", "backward")
		jump_input = Input.is_action_pressed("jump")
		run_input = Input.is_action_pressed("run")
		attack_input = Input.is_action_pressed("primary_ability")
		roll_input = Input.is_action_pressed("roll")
		var t: int = NetworkTime.tick
		if Input.is_action_just_pressed("primary_ability"):
			_press_tick[&"primary_ability"] = t
		if Input.is_action_just_pressed("roll"):
			_press_tick[&"roll"] = t
	else:
		input_dir = Vector2.ZERO
		jump_input = false
		run_input = false
		attack_input = false
		roll_input = false
		_press_tick.clear()

## Returns true if `action` was edge-pressed within BUFFER_WINDOW ticks, and
## clears the buffered press so it doesn't double-fire. Call from a free state
## the moment it's ready to act on a queued input.
func consume_if_buffered(action: StringName) -> bool:
	var last: int = _press_tick.get(action, -10_000)
	if NetworkTime.tick - last <= BUFFER_WINDOW:
		_press_tick[action] = -10_000
		return true
	return false

func set_controller(peer_id: int) -> void:
	controlling_peer_id = peer_id
	# Transfer multiplayer authority so netfox syncs input from the right peer
	if peer_id > 0:
		set_multiplayer_authority(peer_id)
	else:
		# When dormant, authority goes to server
		set_multiplayer_authority(1)

func _exit_tree() -> void:
	NetworkTime.before_tick_loop.disconnect(_gather)
