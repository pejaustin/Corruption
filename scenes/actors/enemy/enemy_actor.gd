class_name EnemyActor extends Actor

## Host-authoritative enemy. AI runs on server, state broadcast to clients.

const SPEED: float = 3.0
const AGGRO_RADIUS: float = 8.0
const DEAGGRO_RADIUS: float = 12.0
const ATTACK_RANGE: float = 2.0
const ATTACK_COOLDOWN: float = 1.2
const COLLISION_LAYER_ENEMY: int = 4
const COLLISION_MASK_WORLD: int = 1
const DEATH_CLEANUP_TIME: float = 2.0
const SYNC_INTERVAL: float = 0.1
const INTERPOLATION_SPEED: float = 10.0
const MAX_HP_DEFAULT: int = 60
const ATTACK_DAMAGE_DEFAULT: int = 15
const STAGGER_DURATION_DEFAULT: float = 0.4

@export var patrol_point: Vector3 = Vector3.ZERO

var attack_timer: float = 0.0
var _death_timer: float = 0.0
var _sync_timer: float = 0.0
var _enemy_manager: EnemyManager

# Client-side interpolation target
var _target_pos: Vector3
var _target_rot: float

func _ready() -> void:
	super()
	if patrol_point == Vector3.ZERO:
		patrol_point = global_position
	_target_pos = global_position
	_target_rot = rotation.y
	collision_layer = COLLISION_LAYER_ENEMY
	collision_mask = COLLISION_MASK_WORLD
	_enemy_manager = get_tree().current_scene.get_node_or_null("EnemyManager")

func get_max_hp() -> int:
	return MAX_HP_DEFAULT

func get_attack_damage() -> int:
	return ATTACK_DAMAGE_DEFAULT

func get_stagger_duration() -> float:
	return STAGGER_DURATION_DEFAULT

func can_take_damage() -> bool:
	if _state_machine.state == &"DeathState" or _state_machine.state == &"StaggerState":
		return false
	return hp > 0

func _die() -> void:
	super()
	_death_timer = 0.0
	collision_layer = 0  # Avatar can walk through corpse
	# Keep collision_mask = 1 so corpse stays on the ground

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		_interpolate_client(delta)
		return

	# Host runs AI: apply gravity then drive state machine
	force_update_is_on_floor()
	if not is_on_floor():
		apply_gravity(delta)

	# States handle move_and_slide via physics_move()
	_state_machine._rollback_tick(delta, 0, true)

	# Handle death cleanup timer
	if _state_machine.state == &"DeathState":
		_death_timer += delta
		if _death_timer >= DEATH_CLEANUP_TIME:
			if _enemy_manager:
				_enemy_manager.notify_enemy_died(self)
			else:
				queue_free()

	# Broadcast state to clients ~10 times/sec
	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		_sync_state.rpc(global_position, rotation.y, _state_machine.state, hp)

func _interpolate_client(delta: float) -> void:
	global_position = global_position.lerp(_target_pos, INTERPOLATION_SPEED * delta)
	rotation.y = lerp_angle(rotation.y, _target_rot, INTERPOLATION_SPEED * delta)

@rpc("authority", "call_remote", "unreliable")
func _sync_state(pos: Vector3, rot_y: float, new_state: StringName, new_hp: int) -> void:
	_target_pos = pos
	_target_rot = rot_y
	if _state_machine.state != new_state:
		_state_machine.state = new_state
	hp = new_hp
	if _state_machine.state == &"DeathState" and collision_layer != 0:
		collision_layer = 0
