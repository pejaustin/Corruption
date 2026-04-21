class_name MinionActor extends Actor

## Host-authoritative minion built on the Actor scene stack.
## AI runs on the host; state is broadcast via MinionManager sync.
## Stats applied from a MinionType resource via apply_type().

const COLLISION_LAYER_MINION: int = 8
const COLLISION_MASK_WORLD: int = 1
const DEATH_CLEANUP_TIME: float = 1.5
const INTERPOLATION_SPEED: float = 10.0

signal minion_died(minion: MinionActor)

## Per-type scenes (skeleton_actor.tscn etc.) set this in the inspector; stats
## are auto-applied on _ready(). Left null for generic scenes that get their
## type assigned at runtime via apply_type().
@export var minion_type: MinionType

var owner_peer_id: int = -1
var minion_type_id: StringName = &""
var minion_trait: StringName = &""
var waypoint: Vector3 = Vector3.ZERO
## Set by _on_link_reached when the nav agent hits a NavigationLink3D in the
## "jumpable" group. JumpState reads this to aim its arc.
var jump_target: Vector3 = Vector3.INF

var move_speed: float = 3.5
var attack_damage: int = 10
var attack_cooldown: float = 1.5
var attack_range: float = 1.8
var aggro_radius: float = 8.0
var max_hp_value: int = 40

var attack_timer: float = 0.0
var _death_timer: float = 0.0
var _pending_raise_pos: Vector3 = Vector3.ZERO

# Client-side interp targets
var _target_pos: Vector3
var _target_rot: float

var _minion_manager: Node
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	super()
	add_to_group(&"minions")
	_target_pos = global_position
	_target_rot = rotation.y
	collision_layer = COLLISION_LAYER_MINION
	collision_mask = COLLISION_MASK_WORLD
	_minion_manager = get_tree().current_scene.get_node_or_null("MinionManager")
	if nav_agent:
		nav_agent.link_reached.connect(_on_link_reached)
	if minion_type != null:
		apply_type(minion_type.duplicate_for_match())

func _on_link_reached(details: Dictionary) -> void:
	# Host decides movement; clients are interpolated so they skip jump state.
	if not multiplayer.is_server():
		return
	var link_node := details.get("owner") as Node
	if link_node == null or not link_node.is_in_group(JumpableLink.GROUP):
		return
	jump_target = details.get("link_exit_position", global_position)
	if _state_machine and _state_machine.state != &"JumpState":
		_state_machine.transition(&"JumpState")

func apply_type(mtype: MinionType) -> void:
	minion_type_id = mtype.id
	max_hp_value = mtype.hp
	hp = mtype.hp
	attack_damage = mtype.damage
	move_speed = mtype.speed
	attack_cooldown = mtype.attack_cooldown
	attack_range = mtype.attack_range
	aggro_radius = mtype.aggro_radius
	minion_trait = mtype.trait_tag

func get_max_hp() -> int:
	return max_hp_value

func get_attack_damage() -> int:
	return attack_damage

func get_stagger_duration() -> float:
	return 0.3

func can_take_damage() -> bool:
	if _state_machine.state == &"DeathState":
		return false
	return hp > 0

func get_faction_color() -> Color:
	return GameConstants.faction_colors.get(faction, Color.WHITE)

func _die() -> void:
	super()
	_death_timer = 0.0
	collision_layer = 0
	velocity = Vector3.ZERO
	minion_died.emit(self)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		_interpolate_client(delta)
		return

	force_update_is_on_floor()
	if not is_on_floor():
		apply_gravity(delta)

	_state_machine._rollback_tick(delta, 0, true)

	if _state_machine.state == &"DeathState":
		_death_timer += delta
		if _death_timer >= DEATH_CLEANUP_TIME:
			if _minion_manager and _minion_manager.has_method("notify_minion_died"):
				_minion_manager.notify_minion_died(self)
			else:
				queue_free()

func _interpolate_client(delta: float) -> void:
	global_position = global_position.lerp(_target_pos, INTERPOLATION_SPEED * delta)
	rotation.y = lerp_angle(rotation.y, _target_rot, INTERPOLATION_SPEED * delta)

func sync_from_server(pos: Vector3, rot_y: float, new_state: StringName, new_hp: int) -> void:
	_target_pos = pos
	_target_rot = rot_y
	if _state_machine and _state_machine.state != new_state:
		_state_machine.state = new_state
	hp = new_hp
	if _state_machine and _state_machine.state == &"DeathState" and collision_layer != 0:
		collision_layer = 0
