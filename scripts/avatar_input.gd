class_name AvatarInput extends Node

## Input handler for the shared Avatar entity.
## Unlike PlayerInput, authority is dynamically transferred
## based on which peer currently controls the Avatar.

var input_dir: Vector2 = Vector2.ZERO
var jump_input := false
var run_input := false
var attack_input := false

## The peer ID currently controlling the Avatar. -1 = dormant/no one.
var controlling_peer_id: int = -1

func _ready():
	NetworkTime.before_tick_loop.connect(_gather)

func _gather():
	if controlling_peer_id == multiplayer.get_unique_id():
		input_dir = Input.get_vector("left", "right", "forward", "backward")
		jump_input = Input.is_action_pressed("jump")
		run_input = Input.is_action_pressed("run")
		attack_input = Input.is_action_pressed("player_action_1")
	else:
		input_dir = Vector2.ZERO
		jump_input = false
		run_input = false
		attack_input = false

func set_controller(peer_id: int):
	controlling_peer_id = peer_id
	# Transfer multiplayer authority so netfox syncs input from the right peer
	if peer_id > 0:
		set_multiplayer_authority(peer_id)
	else:
		# When dormant, authority goes to server
		set_multiplayer_authority(1)

func _exit_tree():
	NetworkTime.before_tick_loop.disconnect(_gather)
