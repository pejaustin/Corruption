class_name Avatar extends CharacterBody3D

## The shared Paladin vessel. Dormant when unclaimed.
## When a player claims it, their input drives this entity
## while their Overlord body stays idle in the tower.

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 4.5
const MAX_HP: int = 100
const ATTACK_DAMAGE: int = 25

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export var _avatar_input: AvatarInput
@export var _avatar_camera: AvatarCamera
@export var _avatar_model: Node3D
@export var _state_machine: RewindableStateMachine

@onready var rollback_synchronizer: RollbackSynchronizer = $RollbackSynchronizer
@onready var watcher_label: Label3D = $WatcherLabel

signal hp_changed(new_hp: int)
signal died

var _animation_player: AnimationPlayer
var controlling_peer_id: int = -1
var is_dormant: bool = true
var hp: int = MAX_HP
var god_mode: bool = false
var stagger_timer: float = 0.0
const STAGGER_DURATION: float = 0.5
const DEATH_TRANSFER_DELAY: float = 2.0
const RESPAWN_POSITION: Vector3 = Vector3(0.1, 0.04, -0.06)
const WATCHER_ORB_DISTANCE: float = 2.5
const WATCHER_ORB_HEIGHT: float = 2.0
const WATCHER_ORB_SIZE: Vector3 = Vector3(0.3, 0.3, 0.3)
const WATCHER_ORB_COLOR: Color = Color(0.4, 0.6, 1.0, 0.7)
const WATCHER_ORB_EMISSION: Color = Color(0.4, 0.6, 1.0)
const WATCHER_ORB_EMISSION_ENERGY: float = 2.0
var _watcher_orbs: Dictionary = {}  # peer_id -> MeshInstance3D

func _ready() -> void:
	_state_machine.state = &"IdleState"
	_animation_player = _avatar_model.get_node_or_null("AnimationPlayer")
	_state_machine.on_display_state_changed.connect(_on_display_state_changed)
	rollback_synchronizer.process_settings()
	_set_dormant_visual(true)
	GameState.watcher_count_changed.connect(_on_watcher_count_changed)
	_update_watcher_label(0)

func activate(peer_id: int) -> void:
	## A player claims the Avatar. Transfer control.
	controlling_peer_id = peer_id
	is_dormant = false
	hp = MAX_HP
	hp_changed.emit(hp)
	_avatar_input.set_controller(peer_id)
	_avatar_camera.activate(peer_id)
	# Re-process rollback settings so netfox syncs input from the new authority
	rollback_synchronizer.process_settings()
	_set_dormant_visual(false)

func deactivate() -> void:
	## Release the Avatar back to dormant state.
	controlling_peer_id = -1
	is_dormant = true
	_avatar_input.set_controller(-1)
	_avatar_camera.deactivate()
	rollback_synchronizer.process_settings()
	_set_dormant_visual(true)
	velocity = Vector3.ZERO
	_state_machine.transition(&"IdleState")

func _set_dormant_visual(dormant: bool) -> void:
	# Always visible — dormant just means no one is controlling it
	_avatar_model.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("avatar_recall") and controlling_peer_id == multiplayer.get_unique_id():
		GameState.request_recall_avatar()

func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	_force_update_is_on_floor()
	if not is_on_floor():
		apply_gravity(delta)

func _on_display_state_changed(old_state: RewindableState, new_state: RewindableState) -> void:
	var anim_name = new_state.animation_name
	if _animation_player and anim_name != "":
		_animation_player.play(anim_name)

func take_damage(amount: int) -> void:
	if god_mode or is_dormant:
		return
	if hp <= 0:
		return
	hp = max(0, hp - amount)
	hp_changed.emit(hp)
	if hp <= 0:
		_die()
	else:
		stagger_timer = STAGGER_DURATION
		if _animation_player:
			_animation_player.play("large-male/Stagger")

func _die() -> void:
	died.emit()
	_state_machine.transition(&"DeathState")
	# Host handles the transfer after a short delay
	if multiplayer.is_server():
		get_tree().create_timer(DEATH_TRANSFER_DELAY).timeout.connect(_on_death_transfer)

func _on_death_transfer() -> void:
	if not multiplayer.is_server():
		return
	GameState.release_avatar()
	_respawn.rpc()

@rpc("authority", "call_local", "reliable")
func _respawn() -> void:
	deactivate()
	global_position = RESPAWN_POSITION
	hp = MAX_HP
	hp_changed.emit(hp)

func apply_gravity(delta: float) -> void:
	velocity.y -= gravity * delta

func _force_update_is_on_floor() -> void:
	var old_velocity = velocity
	velocity *= 0
	move_and_slide()
	velocity = old_velocity

func _on_watcher_count_changed(count: int) -> void:
	_update_watcher_label(count)

func _update_watcher_label(count: int) -> void:
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
	box.size = WATCHER_ORB_SIZE
	orb.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = WATCHER_ORB_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = WATCHER_ORB_EMISSION
	mat.emission_energy_multiplier = WATCHER_ORB_EMISSION_ENERGY
	orb.set_surface_override_material(0, mat)
	add_child(orb)
	return orb

func _process(_delta: float) -> void:
	if stagger_timer > 0:
		stagger_timer -= _delta
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
