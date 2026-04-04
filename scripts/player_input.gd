class_name PlayerInput extends Node

var input_dir : Vector2 = Vector2.ZERO
var camera_input : Vector2 = Vector2.ZERO
var jump_input := false
var run_input := false
var attack_input := false

## When false, all input is zeroed (player is controlling the Avatar)
var input_enabled := true

func _ready():
	NetworkTime.before_tick_loop.connect(_gather)

func _gather():
	if is_multiplayer_authority() and input_enabled:
		input_dir = Input.get_vector("left", "right", "forward", "backward")
		jump_input = Input.is_action_pressed("jump")
		run_input = Input.is_action_pressed("run")
		attack_input = Input.is_action_pressed("player_action_1")
		camera_input = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	elif is_multiplayer_authority() and not input_enabled:
		input_dir = Vector2.ZERO
		jump_input = false
		run_input = false
		attack_input = false
		camera_input = Vector2.ZERO

func _exit_tree():
	NetworkTime.before_tick_loop.disconnect(_gather)
