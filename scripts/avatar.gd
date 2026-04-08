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
@onready var watcher_label: Label3D = $WatcherLabel

var _animation_player: AnimationPlayer
var controlling_peer_id: int = -1
var is_dormant: bool = true
var _watcher_orbs: Dictionary = {}  # peer_id -> MeshInstance3D

const WATCHER_ORB_DISTANCE := 2.5
const WATCHER_ORB_HEIGHT := 2.0

func _ready():
	_state_machine.state = &"IdleState"
	_animation_player = _avatar_model.get_node_or_null("AnimationPlayer")
	_state_machine.on_display_state_changed.connect(_on_display_state_changed)
	rollback_synchronizer.process_settings()
	_set_dormant_visual(true)
	GameState.watcher_count_changed.connect(_on_watcher_count_changed)
	_update_watcher_label(0)

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

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("avatar_recall") and controlling_peer_id == multiplayer.get_unique_id():
		GameState.request_recall_avatar()

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

func _on_watcher_count_changed(count: int):
	_update_watcher_label(count)

func _update_watcher_label(count: int):
	if not watcher_label:
		return
	if count > 0:
		watcher_label.visible = true
		watcher_label.text = "(%d watching)" % count
	else:
		watcher_label.visible = false

func _create_watcher_orb() -> MeshInstance3D:
	var orb = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	orb.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.6, 1.0, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.6, 1.0)
	mat.emission_energy_multiplier = 2.0
	orb.set_surface_override_material(0, mat)
	add_child(orb)
	return orb

func _process(_delta: float):
	var positions = GameState.watcher_positions
	# Remove orbs for scryers who stopped
	for peer_id in _watcher_orbs.keys():
		if peer_id not in positions:
			_watcher_orbs[peer_id].queue_free()
			_watcher_orbs.erase(peer_id)
	# Add/update orbs for active scryers
	for peer_id in positions:
		if peer_id not in _watcher_orbs:
			_watcher_orbs[peer_id] = _create_watcher_orb()
		var cam_pos: Vector3 = positions[peer_id]
		# Direction from Avatar to scryer camera, flattened and normalized
		var dir = (cam_pos - global_position)
		dir.y = 0
		if dir.length() > 0.1:
			dir = dir.normalized()
		else:
			dir = Vector3.FORWARD
		_watcher_orbs[peer_id].position = dir * WATCHER_ORB_DISTANCE + Vector3(0, WATCHER_ORB_HEIGHT, 0)
