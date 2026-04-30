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
## Held flag for the light-attack button. Tier D split — formerly
## `attack_input` (`primary_ability` action). Renamed alongside the action
## itself; remaining references to "attack" (e.g. `try_attack`) are routed
## through the light-attack path by default.
var light_attack_input := false
## Held flag for the heavy-attack button. Tier D — new in this tier. Tap-or-
## hold detection lives in the consuming states (HeavyAttackState transitions
## to ChargeWindupState if the button is still held past
## `CHARGE_HOLD_THRESHOLD_TICKS`).
var heavy_attack_input := false
var roll_input := false
## Held flag for the block button. BlockState reads it each tick to decide
## whether to stay in block or release. Edge-press is also tracked through
## the buffer dict for "press to enter Block from action-locked states later",
## though Tier C only uses the held flag.
var block_input := false
## Tier E — held flag for the ultimate (slot 4) ability. Activation flows
## through `AvatarActor._unhandled_input` reading `Input.is_action_just_pressed`,
## same shape as secondary_ability/item_1/item_2; this held-flag is here for
## symmetry / future hold-to-channel ultimates. Currently unused on the
## consumer side.
var ultimate_input := false

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
		light_attack_input = Input.is_action_pressed("light_attack")
		heavy_attack_input = Input.is_action_pressed("heavy_attack")
		roll_input = Input.is_action_pressed("roll")
		block_input = Input.is_action_pressed("block")
		ultimate_input = Input.is_action_pressed("ultimate") if InputMap.has_action("ultimate") else false
		var t: int = NetworkTime.tick
		if Input.is_action_just_pressed("light_attack"):
			_press_tick[&"light_attack"] = t
		if Input.is_action_just_pressed("heavy_attack"):
			_press_tick[&"heavy_attack"] = t
		if Input.is_action_just_pressed("roll"):
			_press_tick[&"roll"] = t
		if Input.is_action_just_pressed("block"):
			_press_tick[&"block"] = t
	else:
		input_dir = Vector2.ZERO
		jump_input = false
		run_input = false
		light_attack_input = false
		heavy_attack_input = false
		roll_input = false
		block_input = false
		ultimate_input = false
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
