class_name Avatar extends CharacterBody3D

## The shared Paladin vessel. Dormant when unclaimed.
## When a player claims it, their input drives this entity
## while their Overlord body stays idle in the tower.

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@export var _avatar_input: AvatarInput
@export var _avatar_camera: AvatarCamera
@export var _avatar_model: Node3D
@export var _state_machine: RewindableStateMachine

@onready var rollback_synchronizer = $RollbackSynchronizer

var _animation_player: AnimationPlayer
var controlling_peer_id: int = -1
var is_dormant: bool = true

func _ready():
	_state_machine.state = &"IdleState"
	_animation_player = _avatar_model.get_node_or_null("AnimationPlayer")
	_state_machine.on_display_state_changed.connect(_on_display_state_changed)
	rollback_synchronizer.process_settings()
	_set_dormant_visual(true)

func activate(peer_id: int):
	## A player claims the Avatar. Transfer control.
	controlling_peer_id = peer_id
	is_dormant = false
	_avatar_input.set_controller(peer_id)
	_avatar_camera.activate(peer_id)
	# Re-process rollback settings so netfox syncs input from the new authority
	rollback_synchronizer.process_settings()
	_set_dormant_visual(false)

func deactivate():
	## Release the Avatar back to dormant state.
	controlling_peer_id = -1
	is_dormant = true
	_avatar_input.set_controller(-1)
	_avatar_camera.deactivate()
	rollback_synchronizer.process_settings()
	_set_dormant_visual(true)
	velocity = Vector3.ZERO

func _set_dormant_visual(dormant: bool):
	# Always visible — dormant just means no one is controlling it
	_avatar_model.visible = true

func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	_force_update_is_on_floor()
	if not is_on_floor():
		apply_gravity(delta)

func _on_display_state_changed(old_state, new_state):
	var anim_name = new_state.animation_name
	if _animation_player and anim_name != "":
		_animation_player.play(anim_name)

func apply_gravity(delta):
	velocity.y -= gravity * delta

func _force_update_is_on_floor():
	var old_velocity = velocity
	velocity *= 0
	move_and_slide()
	velocity = old_velocity
