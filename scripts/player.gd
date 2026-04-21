class_name Player extends CharacterBody3D

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 4.5

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export var _player_input : PlayerInput
@export var _camera_input : CameraInput
@export var _player_model : Node3D
@export var _state_machine: RewindableStateMachine

@onready var rollback_synchronizer: RollbackSynchronizer = $RollbackSynchronizer

var _animation_player: AnimationPlayer
var _overlord_active := true

func _enter_tree() -> void:
	_player_input.set_multiplayer_authority(str(name).to_int())
	_camera_input.set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	# Default state
	_state_machine.state = &"IdleState"
	_animation_player = _player_model.get_node("AnimationPlayer")

	_state_machine.on_display_state_changed.connect(_on_display_state_changed)

	# Call this after setting authority
	rollback_synchronizer.process_settings()

	# Hide the loading screen once our player is spawned in game and ready
	if multiplayer.get_unique_id() == str(name).to_int():
		NetworkManager.hide_loading()
	else:
		# Other players' models should be on layer 1 (visible to everyone)
		_set_model_layer(1)

func set_overlord_active(active: bool) -> void:
	## Enable/disable this Overlord's input and camera.
	## Called when the player warps to/from the Avatar entity.
	_overlord_active = active
	var is_local = multiplayer.get_unique_id() == str(name).to_int()

	_player_input.input_enabled = active

	if is_local:
		if active:
			_camera_input.camera_3d.current = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			_camera_input.camera_3d.current = false

func _set_model_layer(layer: int) -> void:
	# Set all visual meshes on the model to the specified layer
	# Layer 1 = visible to all cameras, Layer 2 = hidden from own camera
	var other_layer = 2 if layer == 1 else 1
	for node in $"Model/RootNode/Lich-applying/Armature/Skeleton3D".get_children():
		if node is VisualInstance3D:
			node.set_layer_mask_value(layer, true)
			node.set_layer_mask_value(other_layer, false)

func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	_force_update_is_on_floor()
	if not is_on_floor():
		apply_gravity(delta)

func _on_display_state_changed(old_state: RewindableState, new_state: RewindableState) -> void:
	var animation_name = new_state.animation_name
	if _animation_player && animation_name != "":
		_animation_player.play(animation_name)

func apply_gravity(delta: float) -> void:
	velocity.y -= gravity * delta

# https://foxssake.github.io/netfox/netfox/tutorials/rollback-caveats/#characterbody-on-floor
func _force_update_is_on_floor() -> void:
	var old_velocity = velocity
	velocity *= 0
	move_and_slide()
	velocity = old_velocity
